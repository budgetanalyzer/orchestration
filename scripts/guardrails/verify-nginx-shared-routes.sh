#!/bin/bash

# Offline stand-in proof of the shared NGINX route includes. For each complete
# server config (nginx.k8s.conf and nginx.production.k8s.conf) it starts one
# disposable, network-less container from the digest-pinned nginx-gateway image
# with the checked-in nginx/includes mounted read-only, runs nginx -t, and
# probes the decoded ";" rejection, the shared unknown-API rejection, query
# preservation and the shared /api-docs headers. The live ingress denies
# literal and encoded ";" before NGINX sees them, so this is where the NGINX
# layer itself is exercised.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INCLUDES_DIR="${REPO_DIR}/nginx/includes"
DEPLOYMENT_FILE="${REPO_DIR}/kubernetes/services/nginx-gateway/deployment.yaml"
DOCS_CSP_INCLUDE="${INCLUDES_DIR}/security-headers-docs-csp.conf"
NGINX_CONFIGS=(
    "${REPO_DIR}/nginx/nginx.k8s.conf"
    "${REPO_DIR}/nginx/nginx.production.k8s.conf"
)
# The configs name the cluster DNS resolver by hostname, which NGINX resolves
# at startup. Point it at loopback so the network-less container can start;
# upstream lookups then fail and proxied routes answer 502.
RESOLVER_HOST="kube-dns.kube-system.svc.cluster.local"

PASSED=0
FAILED=0
WORK_DIR=""
CONTAINER_ID=""

usage() {
    cat <<'EOF'
Usage: ./scripts/guardrails/verify-nginx-shared-routes.sh

Starts a disposable, network-less container from the digest-pinned
nginx-gateway image declared in kubernetes/services/nginx-gateway/deployment.yaml
for each of nginx/nginx.k8s.conf and nginx/nginx.production.k8s.conf, with
nginx/includes mounted read-only. It runs nginx -t and asserts that a decoded
";" in the path returns 400 with the security headers, that a ";" in the query
string is not rejected, that unknown API paths get the shared 404, and that
/api-docs answers with the docs CSP. Requires docker and leaves no container
behind.

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

stop_container() {
    if [[ -n "${CONTAINER_ID}" ]]; then
        docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true
        CONTAINER_ID=""
    fi
}

cleanup() {
    set +e
    stop_container
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

start_container() {
    local image="$1" config="$2" attempt

    CONTAINER_ID=$(docker run --detach --network none --read-only \
        --add-host "${RESOLVER_HOST}:127.0.0.1" \
        --tmpfs /tmp --entrypoint nginx \
        -v "${config}:/etc/nginx/nginx.conf:ro" \
        -v "${INCLUDES_DIR}:/etc/nginx/includes:ro" \
        "${image}" -g 'daemon off;')

    for ((attempt = 1; attempt <= 20; attempt++)); do
        if docker exec "${CONTAINER_ID}" curl --silent --fail --max-time 2 \
            -o /dev/null http://127.0.0.1:8080/health 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done

    printf 'ERROR: disposable NGINX did not start\n' >&2
    docker logs "${CONTAINER_ID}" >&2 || true
    exit 1
}

# Sends one request with the path as-is and prints the status line, the
# response headers and the body, separated by a blank line. Proxied routes wait
# for the 5s resolver_timeout before answering 502, so allow longer than that.
probe() {
    local path="$1"

    { docker exec "${CONTAINER_ID}" curl --silent --path-as-is --max-time 15 \
        -D - "http://127.0.0.1:8080${path}" || true; } | tr -d '\r'
}

status_of() {
    sed -nE '1s#^HTTP/[0-9.]+ ([0-9]{3}).*$#\1#p' <<<"$1"
}

header_of() {
    local name="$2"

    sed -n '/^$/q;p' <<<"$1" | sed -n "s/^${name}:[[:space:]]*//Ip" | tail -n 1
}

body_of() {
    sed '1,/^$/d' <<<"$1"
}

assert_status() {
    local path="$1" expected="$2" label="$3" response status

    response=$(probe "${path}")
    status=$(status_of "${response}")
    if [[ "${status}" == "${expected}" ]]; then
        pass "${label}: ${path} -> ${status}"
    else
        fail "${label}: ${path} -> ${status:-none} (expected ${expected})"
    fi
}

assert_semicolon_rejected() {
    local path="$1" response status

    response=$(probe "${path}")
    status=$(status_of "${response}")
    if [[ "${status}" == "400" && "$(header_of "${response}" X-Content-Type-Options)" == "nosniff" \
        && -n "$(header_of "${response}" Content-Security-Policy)" ]]; then
        pass "Decoded ';' rejected with security headers: ${path} -> 400"
    else
        fail "Decoded ';' not rejected with security headers: ${path} -> ${status:-none}"
    fi
}

assert_unknown_api() {
    local path="$1" response status body

    response=$(probe "${path}")
    status=$(status_of "${response}")
    body=$(body_of "${response}")
    if [[ "${status}" == "404" && "${body}" == "Not Found" ]]; then
        pass "Shared unknown-API rejection: ${path} -> 404 Not Found"
    else
        fail "Shared unknown-API rejection: ${path} -> ${status:-none} (expected the shared 404 Not Found)"
    fi
}

verify_config() {
    local image="$1" config="$2" docs_csp response status

    printf '\n=== %s ===\n' "${config#"${REPO_DIR}"/}"
    start_container "${image}" "${config}"

    if docker exec "${CONTAINER_ID}" nginx -t >/dev/null 2>&1; then
        pass "nginx -t passes with the mounted includes"
    else
        fail "nginx -t fails with the mounted includes"
        docker exec "${CONTAINER_ID}" nginx -t >&2 || true
    fi

    assert_semicolon_rejected "/api/v1/transactions;x"
    assert_semicolon_rejected "/api/v1/transactions%3bx"
    assert_semicolon_rejected "/api/v1/transactions%3Bx"
    assert_semicolon_rejected "/api/v1/users/..;/internal/v1/users/x/authorization"
    assert_semicolon_rejected "/api-docs;x"
    assert_semicolon_rejected "/;x"

    # %253b decodes once to the literal text %3b, which holds no ";". Only the
    # ingress filter rejects this double-encoded form and deeper ones such as
    # %25253b.
    response=$(probe "/api/v1/transactions%253bx")
    printf '  [INFO] /api/v1/transactions%%253bx -> %s at NGINX (double- and deeper-encoded forms are ingress-only)\n' \
        "$(status_of "${response}")"

    assert_unknown_api "/api"
    assert_unknown_api "/api/v1/unknown-route"
    assert_unknown_api "/api/v1/unknown-route?x=a;b"
    # 502: the request passed the ";" check and reached the shared proxy
    # location; the network-less container has no backend to answer.
    assert_status "/api/v1/transactions?q=a;b" 502 "Query ';' preserved and reaches the transactions proxy"
    assert_status "/api/v1/exchange-rates?targetCurrency=THB" 502 "Query reaches the exchange-rates proxy"

    docs_csp=$(sed -nE 's/^add_header Content-Security-Policy "(.*)" always;$/\1/p' "${DOCS_CSP_INCLUDE}")
    response=$(probe "/api-docs/unknown")
    status=$(status_of "${response}")
    if [[ "${status}" == "404" && -n "${docs_csp}" \
        && "$(header_of "${response}" Content-Security-Policy)" == "${docs_csp}" ]]; then
        pass "Shared /api-docs/ fallback -> 404 with the docs CSP"
    else
        fail "Shared /api-docs/ fallback -> ${status:-none} without the docs CSP"
    fi

    stop_container
}

main() {
    local image config

    if ! command -v docker >/dev/null 2>&1; then
        printf 'ERROR: required command not found: docker\n' >&2
        exit 1
    fi
    for config in "${NGINX_CONFIGS[@]}" "${INCLUDES_DIR}/api-routes.conf" "${INCLUDES_DIR}/api-docs-routes.conf"; do
        if [[ ! -f "${config}" ]]; then
            printf 'ERROR: missing %s\n' "${config#"${REPO_DIR}"/}" >&2
            exit 1
        fi
    done

    image=$(nginx_image)
    printf '=== NGINX Shared Routes (disposable %s) ===\n' "${image%%@*}"

    for config in "${NGINX_CONFIGS[@]}"; do
        verify_config "${image}" "${config}"
    done

    printf '\n=== Summary ===\n'
    printf '  Passed: %d\n  Failed: %d\n' "${PASSED}" "${FAILED}"
    if (( FAILED > 0 )); then
        exit 1
    fi
    printf 'NGINX shared route verification passed.\n'
}

main "$@"
