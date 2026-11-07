#!/bin/bash

# Offline stand-in proof of the NGINX backend header contract. It starts one
# disposable container from the digest-pinned nginx-gateway image, with no
# network, the checked-in nginx/includes/backend-headers.conf and an njs echo
# upstream. It then sends synthetic credential, identity and forwarding headers
# and asserts what the upstream receives. It prints header names only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INCLUDE_FILE="${REPO_DIR}/nginx/includes/backend-headers.conf"
DEPLOYMENT_FILE="${REPO_DIR}/kubernetes/services/nginx-gateway/deployment.yaml"

PROBE_USER_ID="usr_backend_header_probe"
PROBE_ROLES="USER"
PROBE_PERMISSIONS="transactions:read"

PASSED=0
FAILED=0
WORK_DIR=""
CONTAINER_ID=""

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

cleanup() {
    set +e
    if [[ -n "${CONTAINER_ID}" ]]; then
        docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1
    fi
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
}

trap cleanup EXIT

nginx_image() {
    local image

    image=$(sed -nE 's#^[[:space:]]*image:[[:space:]]*(nginxinc/nginx-unprivileged[^[:space:]]*).*$#\1#p' \
        "${DEPLOYMENT_FILE}" | head -n 1)
    if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
        printf 'ERROR: nginx-gateway image in %s is not digest-pinned: %s\n' \
            "${DEPLOYMENT_FILE#"${REPO_DIR}"/}" "${image:-<missing>}" >&2
        exit 1
    fi
    printf '%s\n' "${image}"
}

write_fixture() {
    cat >"${WORK_DIR}/nginx.conf" <<'EOF'
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
    # and synthetic identity values are echoed so they can be compared.
    cat >"${WORK_DIR}/echo.js" <<'EOF'
function headers(r) {
    var names = Object.keys(r.headersIn).map(function (n) { return n.toLowerCase(); }).sort();
    var lines = names.map(function (n) { return 'name=' + n; });
    ['X-Forwarded-Proto', 'X-User-Id', 'X-Roles', 'X-Permissions'].forEach(function (h) {
        lines.push('value.' + h.toLowerCase() + '=' + (r.headersIn[h] || ''));
    });
    r.return(200, lines.join('\n') + '\n');
}

export default { headers };
EOF
}

start_container() {
    local image="$1" attempt

    CONTAINER_ID=$(docker run --detach --network none --read-only \
        --tmpfs /tmp --entrypoint nginx \
        -v "${WORK_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro" \
        -v "${WORK_DIR}/echo.js:/etc/nginx/echo/echo.js:ro" \
        -v "${INCLUDE_FILE}:/etc/nginx/includes/backend-headers.conf:ro" \
        "${image}" -g 'daemon off;')

    for ((attempt = 1; attempt <= 20; attempt++)); do
        if docker exec "${CONTAINER_ID}" curl --silent --fail --max-time 2 \
            -o /dev/null http://127.0.0.1:9000/ready 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done

    printf 'ERROR: disposable NGINX did not start\n' >&2
    docker logs "${CONTAINER_ID}" >&2 || true
    exit 1
}

# Sends one request through the stand-in NGINX and prints the echo body.
probe() {
    local path="$1"

    docker exec "${CONTAINER_ID}" curl --silent --show-error --fail --max-time 5 \
        -H 'Cookie: __Host-BA_SESSION=synthetic-session-not-real; other=synthetic' \
        -H 'Cookie: second=synthetic' \
        -H 'Authorization: Bearer synthetic-token-not-real' \
        -H 'X-Forwarded-Proto: http' \
        -H "X-User-Id: ${PROBE_USER_ID}" \
        -H "X-Roles: ${PROBE_ROLES}" \
        -H "X-Permissions: ${PROBE_PERMISSIONS}" \
        "http://127.0.0.1:8080${path}"
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
    local image body control

    if ! command -v docker >/dev/null 2>&1; then
        printf 'ERROR: required command not found: docker\n' >&2
        exit 1
    fi
    if [[ ! -f "${INCLUDE_FILE}" ]]; then
        printf 'ERROR: missing %s\n' "${INCLUDE_FILE#"${REPO_DIR}"/}" >&2
        exit 1
    fi

    image=$(nginx_image)
    WORK_DIR=$(mktemp -d)
    chmod 755 "${WORK_DIR}"
    write_fixture
    chmod 644 "${WORK_DIR}/nginx.conf" "${WORK_DIR}/echo.js"

    printf '=== NGINX Backend Header Contract (disposable %s) ===\n' "${image%%@*}"
    start_container "${image}"

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

    printf '\n=== Summary ===\n'
    printf '  Passed: %d\n  Failed: %d\n' "${PASSED}" "${FAILED}"
    if (( FAILED > 0 )); then
        exit 1
    fi
    printf 'NGINX backend header contract verification passed.\n'
}

main "$@"
