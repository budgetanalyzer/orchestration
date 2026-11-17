#!/bin/bash

# Offline stand-in proof of the NGINX backend header contract. It starts one
# disposable container from the digest-pinned nginx-gateway image, with no
# network, the checked-in nginx/includes/backend-headers.conf and an njs echo
# upstream. It then sends synthetic credential, identity and forwarding headers
# and asserts what the upstream receives. The upstream also returns the Spring
# Security default response headers, and the harness asserts what the client
# receives. It prints header names only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
source "${SCRIPT_DIR}/../lib/nginx-docker-harness.sh"
INCLUDE_FILE="${REPO_DIR}/nginx/includes/backend-headers.conf"
DEPLOYMENT_FILE="${REPO_DIR}/kubernetes/services/nginx-gateway/deployment.yaml"

PROBE_USER_ID="usr_backend_header_probe"
PROBE_ROLES="USER"
PROBE_PERMISSIONS="transactions:read"

PASSED=0
FAILED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/guardrails/verify-nginx-backend-headers.sh

Starts a disposable, network-less container from the digest-pinned
nginx-gateway image declared in kubernetes/services/nginx-gateway/deployment.yaml,
mounts nginx/includes/backend-headers.conf read-only, and proxies synthetic
requests to an njs echo upstream in the same container. It asserts that the
upstream receives no Cookie or Authorization header, receives
X-Forwarded-Proto: https and still receives the identity headers. A control
location without the include proves the echo upstream would see the cookie.
The upstream returns X-Frame-Options: DENY, X-Content-Type-Options: nosniff
and X-XSS-Protection: 0. Through the include the client must receive exactly
one X-Frame-Options: SAMEORIGIN, exactly one X-Content-Type-Options: nosniff
and no X-XSS-Protection. The control location must show the backend copies.
Requires docker. Prints header names only and leaves no container behind.

Options:
  -h, --help  Show this help text.
EOF
}

case "${1:-}" in
    "") ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
esac

pass() { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

trap nginx_harness_cleanup EXIT

write_fixture() {
    cat >"${NGINX_HARNESS_WORK_DIR}/nginx.conf" <<'EOF'
load_module modules/ngx_http_js_module.so;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;

events {}

http {
    access_log off;
    client_body_temp_path /tmp/client_temp;
    proxy_temp_path /tmp/proxy_temp;
    fastcgi_temp_path /tmp/fastcgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    scgi_temp_path /tmp/scgi_temp;
    js_import echo from /etc/nginx/echo/echo.js;

    # Mirrors an API route: variable proxy_pass, rewrite, shared include.
    server {
        listen 127.0.0.1:8080;

        # Stand-in for the server-level security-headers-*-csp.conf include,
        # which sends no X-XSS-Protection.
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;

        location /api/v1/transactions {
            set $transaction_backend "http://127.0.0.1:9000";
            rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
            proxy_pass $transaction_backend;
            include includes/backend-headers.conf;
        }

        # Control: plain proxy_pass without the include.
        location /control {
            proxy_pass http://127.0.0.1:9000;
        }
    }

    server {
        listen 127.0.0.1:9000;

        location / {
            js_content echo.headers;
        }
    }
}
EOF

    # Header names are lowercased and sorted. Only the non-secret forwarding
    # and synthetic identity values are echoed so they can be compared. The
    # response carries the Spring Security default security headers.
    cat >"${NGINX_HARNESS_WORK_DIR}/echo.js" <<'EOF'
function headers(r) {
    var names = Object.keys(r.headersIn).map(function (n) { return n.toLowerCase(); }).sort();
    var lines = names.map(function (n) { return 'name=' + n; });
    ['X-Forwarded-Proto', 'X-User-Id', 'X-Roles', 'X-Permissions'].forEach(function (h) {
        lines.push('value.' + h.toLowerCase() + '=' + (r.headersIn[h] || ''));
    });
    r.headersOut['X-Frame-Options'] = 'DENY';
    r.headersOut['X-Content-Type-Options'] = 'nosniff';
    r.headersOut['X-XSS-Protection'] = '0';
    r.return(200, lines.join('\n') + '\n');
}

export default { headers };
EOF
}

# Sends one request through the stand-in NGINX. Extra curl arguments follow
# the path. Without them it prints the echo body.
probe() {
    local path="$1"

    shift
    docker exec "${NGINX_HARNESS_CONTAINER_ID}" curl --silent --show-error --fail --max-time 5 \
        "$@" \
        -H 'Cookie: __Host-BA_SESSION=synthetic-session-not-real; other=synthetic' \
        -H 'Cookie: second=synthetic' \
        -H 'Authorization: Bearer synthetic-token-not-real' \
        -H 'X-Forwarded-Proto: http' \
        -H "X-User-Id: ${PROBE_USER_ID}" \
        -H "X-Roles: ${PROBE_ROLES}" \
        -H "X-Permissions: ${PROBE_PERMISSIONS}" \
        "http://127.0.0.1:8080${path}"
}

# Sends the same request and prints only the response header lines, without \r.
probe_response_headers() {
    probe "$1" --output /dev/null --dump-header - | tr -d '\r'
}

# Prints the values of every response header line named $2, case-insensitively.
response_values() {
    awk -v name="$2" '
        BEGIN { name = tolower(name) }
        {
            i = index($0, ":")
            if (i > 0 && tolower(substr($0, 1, i - 1)) == name) {
                value = substr($0, i + 1)
                sub(/^[ \t]+/, "", value)
                sub(/[ \t]+$/, "", value)
                print value
            }
        }' <<<"$1"
}

# Passes when the sorted values of response header $2 equal $3, one per line.
# An empty $3 means the header must be absent.
assert_response_values() {
    local headers="$1" name="$2" expected="$3" label="$4"

    if [[ "$(response_values "${headers}" "${name}" | LC_ALL=C sort)" == "${expected}" ]]; then
        pass "${label}"
    else
        fail "${label}"
    fi
}

has_name() {
    grep -Fxq "name=$2" <<<"$1"
}

value_of() {
    sed -n "s/^value\\.$2=//p" <<<"$1"
}

assert_absent() {
    if has_name "$1" "$2"; then
        fail "$3 forwards $2"
    else
        pass "$3 does not forward $2"
    fi
}

assert_value() {
    local body="$1" name="$2" expected="$3" label="$4"

    if has_name "${body}" "${name}" && [[ "$(value_of "${body}" "${name}")" == "${expected}" ]]; then
        pass "${label}"
    else
        fail "${label}"
    fi
}

main() {
    local image body control headers

    nginx_harness_require_docker
    if [[ ! -f "${INCLUDE_FILE}" ]]; then
        printf 'ERROR: missing %s\n' "${INCLUDE_FILE#"${REPO_DIR}"/}" >&2
        exit 1
    fi

    image=$(nginx_harness_image "${DEPLOYMENT_FILE}")
    nginx_harness_make_work_dir
    write_fixture
    chmod 644 "${NGINX_HARNESS_WORK_DIR}/nginx.conf" "${NGINX_HARNESS_WORK_DIR}/echo.js"

    printf '=== NGINX Backend Header Contract (disposable %s) ===\n' "${image%%@*}"
    nginx_harness_start "${image}" http://127.0.0.1:9000/ready \
        -v "${NGINX_HARNESS_WORK_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro" \
        -v "${NGINX_HARNESS_WORK_DIR}/echo.js:/etc/nginx/echo/echo.js:ro" \
        -v "${INCLUDE_FILE}:/etc/nginx/includes/backend-headers.conf:ro"

    control=$(probe "/control")
    if has_name "${control}" "cookie" && has_name "${control}" "authorization"; then
        pass "Control location without the include forwards cookie and authorization (echo can see them)"
    else
        fail "Control location did not forward cookie and authorization; the echo upstream cannot prove stripping"
    fi

    body=$(probe "/api/v1/transactions")
    printf '  Header names received through the include:\n'
    sed -n 's/^name=/    /p' <<<"${body}"

    assert_absent "${body}" "cookie" "Shared include"
    assert_absent "${body}" "authorization" "Shared include"
    assert_value "${body}" "x-forwarded-proto" "https" \
        "Shared include sends X-Forwarded-Proto: https and overrides the client value"
    assert_value "${body}" "x-user-id" "${PROBE_USER_ID}" "Shared include forwards X-User-Id"
    assert_value "${body}" "x-roles" "${PROBE_ROLES}" "Shared include forwards X-Roles"
    assert_value "${body}" "x-permissions" "${PROBE_PERMISSIONS}" "Shared include forwards X-Permissions"

    headers=$(probe_response_headers "/control")
    assert_response_values "${headers}" "x-frame-options" $'DENY\nSAMEORIGIN' \
        "Control location returns the backend X-Frame-Options: DENY and the edge SAMEORIGIN"
    assert_response_values "${headers}" "x-content-type-options" $'nosniff\nnosniff' \
        "Control location returns the backend and edge X-Content-Type-Options: nosniff"
    assert_response_values "${headers}" "x-xss-protection" "0" \
        "Control location returns the backend X-XSS-Protection: 0"

    headers=$(probe_response_headers "/api/v1/transactions")
    assert_response_values "${headers}" "x-frame-options" "SAMEORIGIN" \
        "Shared include returns exactly one X-Frame-Options: SAMEORIGIN"
    assert_response_values "${headers}" "x-content-type-options" "nosniff" \
        "Shared include returns exactly one X-Content-Type-Options: nosniff"
    assert_response_values "${headers}" "x-xss-protection" "" \
        "Shared include returns no X-XSS-Protection"

    printf '\n=== Summary ===\n'
    printf '  Passed: %d\n  Failed: %d\n' "${PASSED}" "${FAILED}"
    if (( FAILED > 0 )); then
        exit 1
    fi
    printf 'NGINX backend header contract verification passed.\n'
}

main "$@"
