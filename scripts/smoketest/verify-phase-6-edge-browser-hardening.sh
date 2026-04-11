#!/bin/bash

# verify-phase-6-edge-browser-hardening.sh
#
# Completion gate for Security Hardening v2 Phase 6 edge/browser hardening.
# Proves the checked-in dev/production edge contract, the live CSP/header
# behavior on the real app paths, the final auth-edge throttling coverage, the
# API rate-limit identity model, and the Phase 5 regression cascade.
#
# The shared /api-docs surface remains observable here, but docs-route problems
# are warning-only and do not block Phase 6 completion.
#
# Usage:
#   ./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh
#   ./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh --subverifier-timeout 20m
#   ./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh --phase5-regression-timeout 10m

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

APP_BASE_URL="https://app.budgetanalyzer.localhost"
CURL_TIMEOUT=10
AUTH_RATE_LIMIT_BURST=15
AUTH_RATE_LIMIT_MATCH_HEADER="x-local-rate-limit: auth-sensitive"
SUBVERIFIER_TIMEOUT="20m"
PHASE5_REGRESSION_TIMEOUT="10m"

NGINX_DEPLOYMENT="deployment/nginx-gateway"
NGINX_NAMESPACE="default"
NGINX_POD_LABEL_SELECTOR="app=nginx-gateway"
PRODUCTION_NGINX_CONFIG_PATH="nginx/nginx.production.k8s.conf"
PORT_FORWARD_PID=""
PORT_FORWARD_PORT=""
PORT_FORWARD_LOG=""

PROBE_NAMESPACE="default"
PROBE_LABEL_KEY="verify-phase6-temp"
PROBE_LABEL_VALUE="true"
PROBE_POD_NAME="phase6-edge-browser-probe"
PROBE_POLICY_NAME="allow-phase6-edge-browser-egress-to-istio-ingress"
PROBE_IMAGE="curlimages/curl:8.12.1@sha256:94e9e444bcba979c2ea12e27ae39bee4cd10bc7041a472c4727a558e213744e6"
INGRESS_NAMESPACE="istio-ingress"
INGRESS_SERVICE_NAME="istio-ingress-gateway-istio"
INGRESS_POD_LABEL_KEY="gateway.networking.k8s.io/gateway-name"
INGRESS_POD_LABEL_VALUE="istio-ingress-gateway"
INGRESS_CLUSTER_IP=""

PASSED=0
FAILED=0
WARNED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh

Options:
  --subverifier-timeout <dur>         Timeout for each nested verifier
                                      (default: 20m).
  --phase5-regression-timeout <dur>   Per-script timeout passed through to the
                                      Phase 5 regression verifier
                                      (default: 10m).
  -h, --help                          Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subverifier-timeout)
            if [[ $# -lt 2 ]]; then
                printf 'ERROR: --subverifier-timeout requires a duration argument\n' >&2
                usage >&2
                exit 1
            fi
            SUBVERIFIER_TIMEOUT="$2"
            shift 2
            ;;
        --phase5-regression-timeout)
            if [[ $# -lt 2 ]]; then
                printf 'ERROR: --phase5-regression-timeout requires a duration argument\n' >&2
                usage >&2
                exit 1
            fi
            PHASE5_REGRESSION_TIMEOUT="$2"
            shift 2
            ;;
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
done

section() { printf '\n=== %s ===\n' "$1"; }
pass()    { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail()    { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
warn()    { printf '  [WARN] %s\n' "$1"; WARNED=$((WARNED + 1)); }
info()    { printf '  [INFO] %s\n' "$1"; }

info_block() {
    local text="$1"

    [[ -z "${text}" ]] && return

    while IFS= read -r line; do
        printf '  [INFO] %s\n' "${line}"
    done <<< "${text}"
}

cleanup() {
    set +e

    if [[ -n "${PORT_FORWARD_PID}" ]]; then
        kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
        wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    fi

    if [[ -n "${PORT_FORWARD_LOG}" ]]; then
        rm -f "${PORT_FORWARD_LOG}" >/dev/null 2>&1 || true
    fi

    kubectl delete pod "${PROBE_POD_NAME}" -n "${PROBE_NAMESPACE}" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true
    kubectl delete networkpolicy "${PROBE_POLICY_NAME}" -n "${PROBE_NAMESPACE}" \
        --ignore-not-found >/dev/null 2>&1 || true
}

trap cleanup EXIT

require_host_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_cluster_access() {
    if ! kubectl get namespace "${NGINX_NAMESPACE}" >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes API or %s namespace\n' "${NGINX_NAMESPACE}" >&2
        exit 1
    fi
}

extract_http_status() {
    printf '%s\n' "$1" | sed -n 's/^HTTP_STATUS://p' | tail -n 1
}

extract_header_value() {
    local header_name="$1" response="$2"
    printf '%s\n' "$response" | sed -n "s/^[[:space:]]*${header_name}:[[:space:]]*//Ip" | tail -n 1 | tr -d '\r'
}

count_status() {
    local status="$1"
    grep -c "^${status}$" || true
}

assert_file_contains() {
    local file="$1" pattern="$2" description="$3"
    if rg -q "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_file_not_contains() {
    local file="$1" pattern="$2" description="$3"
    if rg -q "$pattern" "$file"; then
        fail "$description"
    else
        pass "$description"
    fi
}

warn_file_contains() {
    local file="$1" pattern="$2" description="$3"
    if rg -q "$pattern" "$file"; then
        pass "$description"
    else
        warn "$description"
    fi
}

warn_file_not_contains() {
    local file="$1" pattern="$2" description="$3"
    if rg -q "$pattern" "$file"; then
        warn "$description"
    else
        pass "$description"
    fi
}

location_block() {
    local file="$1" start_regex="$2"

    awk -v start="${start_regex}" '
        $0 ~ start {capture=1}
        capture {print}
        capture && /^[[:space:]]*}[[:space:]]*$/ {exit}
    ' "$file"
}

assert_location_block_contains() {
    local file="$1" start_regex="$2" expected="$3" description="$4"
    local block

    block="$(location_block "$file" "$start_regex")"
    if [[ -n "${block}" ]] && printf '%s\n' "${block}" | grep -Fq "${expected}"; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_location_block_not_contains() {
    local file="$1" start_regex="$2" unexpected="$3" description="$4"
    local block

    block="$(location_block "$file" "$start_regex")"
    if [[ -n "${block}" ]] && ! printf '%s\n' "${block}" | grep -Fq "${unexpected}"; then
        pass "$description"
    else
        fail "$description"
    fi
}

warn_location_block_contains() {
    local file="$1" start_regex="$2" expected="$3" description="$4"
    local block

    block="$(location_block "$file" "$start_regex")"
    if [[ -n "${block}" ]] && printf '%s\n' "${block}" | grep -Fq "${expected}"; then
        pass "$description"
    else
        warn "$description"
    fi
}

external_headers_and_status() {
    local path="$1"
    shift

    curl -sk -D - -o /dev/null --max-time "${CURL_TIMEOUT}" --max-redirs 0 \
        -w 'HTTP_STATUS:%{http_code}\n' \
        "$@" "${APP_BASE_URL}${path}" 2>/dev/null || true
}

external_body_and_status() {
    local path="$1"
    shift

    curl -sk --max-time "${CURL_TIMEOUT}" --max-redirs 0 \
        -w '\nHTTP_STATUS:%{http_code}\n' \
        "$@" "${APP_BASE_URL}${path}" 2>/dev/null || true
}

start_nginx_port_forward() {
    kubectl rollout status "${NGINX_DEPLOYMENT}" -n "${NGINX_NAMESPACE}" --timeout=120s >/dev/null

    PORT_FORWARD_LOG="$(mktemp)"
    kubectl port-forward "${NGINX_DEPLOYMENT}" -n "${NGINX_NAMESPACE}" :8080 >"${PORT_FORWARD_LOG}" 2>&1 &
    PORT_FORWARD_PID=$!

    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        PORT_FORWARD_PORT="$(sed -n 's/.*127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "${PORT_FORWARD_LOG}" | tail -n 1)"
        if [[ -n "${PORT_FORWARD_PORT}" ]]; then
            return 0
        fi
        if ! kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    printf 'ERROR: failed to start kubectl port-forward for %s/%s\n' "${NGINX_NAMESPACE}" "${NGINX_DEPLOYMENT}" >&2
    [[ -f "${PORT_FORWARD_LOG}" ]] && cat "${PORT_FORWARD_LOG}" >&2
    exit 1
}

local_nginx_headers_and_status() {
    local path="$1"
    shift

    curl -sD - -o /dev/null --max-time "${CURL_TIMEOUT}" --max-redirs 0 \
        -w 'HTTP_STATUS:%{http_code}\n' \
        "$@" "http://127.0.0.1:${PORT_FORWARD_PORT}${path}" 2>/dev/null || true
}

local_nginx_body_and_status() {
    local path="$1"
    shift

    curl -s --max-time "${CURL_TIMEOUT}" --max-redirs 0 \
        -w '\nHTTP_STATUS:%{http_code}\n' \
        "$@" "http://127.0.0.1:${PORT_FORWARD_PORT}${path}" 2>/dev/null || true
}

extract_body() {
    printf '%s\n' "$1" | sed '$d'
}

nginx_gateway_pod_name() {
    kubectl get pod -n "${NGINX_NAMESPACE}" -l "${NGINX_POD_LABEL_SELECTOR}" \
        -o jsonpath='{.items[0].metadata.name}'
}

assert_csp_contains() {
    local csp="$1" description="$2"
    shift 2

    local token
    for token in "$@"; do
        if [[ "${csp}" != *"${token}"* ]]; then
            fail "${description} (missing ${token})"
            return
        fi
    done

    pass "${description}"
}

assert_csp_excludes() {
    local csp="$1" description="$2"
    shift 2

    local token
    for token in "$@"; do
        if [[ "${csp}" == *"${token}"* ]]; then
            fail "${description} (unexpected ${token})"
            return
        fi
    done

    pass "${description}"
}

assert_text_excludes() {
    local text="$1" description="$2"
    shift 2

    local token
    for token in "$@"; do
        if [[ "${text}" == *"${token}"* ]]; then
            fail "${description} (unexpected ${token})"
            return
        fi
    done

    pass "${description}"
}

warn_text_excludes() {
    local text="$1" description="$2"
    shift 2

    local token
    for token in "$@"; do
        if [[ "${text}" == *"${token}"* ]]; then
            warn "${description} (unexpected ${token})"
            return
        fi
    done

    pass "${description}"
}

create_probe_policy() {
    kubectl apply -n "${PROBE_NAMESPACE}" -f - >/dev/null <<MANIFEST
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${PROBE_POLICY_NAME}
  labels:
    ${PROBE_LABEL_KEY}: "${PROBE_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      ${PROBE_LABEL_KEY}: "${PROBE_LABEL_VALUE}"
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${INGRESS_NAMESPACE}
          podSelector:
            matchLabels:
              ${INGRESS_POD_LABEL_KEY}: ${INGRESS_POD_LABEL_VALUE}
      ports:
        - protocol: TCP
          port: 443
MANIFEST
}

create_probe_pod() {
    kubectl delete pod "${PROBE_POD_NAME}" -n "${PROBE_NAMESPACE}" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "${PROBE_NAMESPACE}" -f - >/dev/null <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${PROBE_POD_NAME}
  annotations:
    sidecar.istio.io/inject: "false"
  labels:
    ${PROBE_LABEL_KEY}: "${PROBE_LABEL_VALUE}"
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: curl
      image: ${PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
MANIFEST
}

wait_for_probe_ready() {
    kubectl wait --for=condition=Ready "pod/${PROBE_POD_NAME}" -n "${PROBE_NAMESPACE}" --timeout=120s >/dev/null
}

probe_headers_and_status() {
    local path="$1"
    shift
    local curl_args=""
    local arg

    for arg in "$@"; do
        curl_args="${curl_args} $(printf '%q' "${arg}")"
    done

    kubectl exec -n "${PROBE_NAMESPACE}" "${PROBE_POD_NAME}" -- sh -lc \
        "curl -sk -D - -o /dev/null --max-time ${CURL_TIMEOUT} --max-redirs 0 -w 'HTTP_STATUS:%{http_code}\n' --resolve app.budgetanalyzer.localhost:443:${INGRESS_CLUSTER_IP}${curl_args} 'https://app.budgetanalyzer.localhost${path}'" 2>/dev/null || true
}

require_ingress_rate_limit_from_probe() {
    local path="$1" path_label="$2"
    shift 2

    local tmpdir i num_429s proof_response
    tmpdir="$(mktemp -d)"

    for ((i = 1; i <= AUTH_RATE_LIMIT_BURST; i++)); do
        probe_headers_and_status "${path}" "$@" >"${tmpdir}/${i}"
    done

    num_429s=$(
        for ((i = 1; i <= AUTH_RATE_LIMIT_BURST; i++)); do
            sed -n 's/^HTTP_STATUS://p' "${tmpdir}/${i}"
        done | count_status 429
    )

    if [[ "${num_429s}" -ge 1 ]]; then
        pass "${path_label} is rate limited at ingress for in-cluster callers (saw ${num_429s} HTTP 429 responses)"
    else
        fail "${path_label} never returned HTTP 429 during a ${AUTH_RATE_LIMIT_BURST}-request probe burst"
        rm -rf "${tmpdir}"
        return
    fi

    proof_response="$(
        for ((i = 1; i <= AUTH_RATE_LIMIT_BURST; i++)); do
            if [[ "$(sed -n 's/^HTTP_STATUS://p' "${tmpdir}/${i}" | tail -n 1)" == "429" ]]; then
                cat "${tmpdir}/${i}"
                break
            fi
        done
    )"

    if printf '%s\n' "${proof_response}" | tr -d '\r' | grep -Fqi "${AUTH_RATE_LIMIT_MATCH_HEADER}"; then
        pass "Rate-limited ${path_label} response includes the local rate-limit marker header"
    else
        fail "Rate-limited ${path_label} response did not include ${AUTH_RATE_LIMIT_MATCH_HEADER}"
    fi

    rm -rf "${tmpdir}"
}

run_subverifier() {
    local label="$1"
    shift
    local exit_code=0

    if timeout --foreground --kill-after=10s "${SUBVERIFIER_TIMEOUT}" "$@"; then
        pass "${label} passed"
        return
    fi

    exit_code=$?
    if [[ "${exit_code}" -eq 124 || "${exit_code}" -eq 137 ]]; then
        fail "${label} timed out after ${SUBVERIFIER_TIMEOUT}"
    else
        fail "${label} failed"
    fi
}

verify_production_nginx_syntax() {
    section "Production NGINX Syntax Validation"

    local pod_name tmpdir prep_output copy_output validation_output
    local config_path="${REPO_DIR}/${PRODUCTION_NGINX_CONFIG_PATH}"

    if [[ ! -f "${config_path}" ]]; then
        fail "Checked-in production NGINX config is missing at ${PRODUCTION_NGINX_CONFIG_PATH}"
        return
    fi

    if ! kubectl rollout status "${NGINX_DEPLOYMENT}" -n "${NGINX_NAMESPACE}" --timeout=120s >/dev/null 2>&1; then
        fail "Cannot validate ${PRODUCTION_NGINX_CONFIG_PATH} because ${NGINX_DEPLOYMENT} is not ready"
        return
    fi

    pod_name="$(nginx_gateway_pod_name)"
    if [[ -z "${pod_name}" ]]; then
        fail "Cannot validate ${PRODUCTION_NGINX_CONFIG_PATH} because no nginx-gateway pod is running"
        return
    fi

    if ! tmpdir="$(kubectl exec -n "${NGINX_NAMESPACE}" "${pod_name}" -- sh -lc 'mktemp -d /tmp/phase6-prod-nginx.XXXXXX' 2>/dev/null)"; then
        fail "Could not create a temporary validation directory inside ${pod_name}"
        return
    fi

    if ! prep_output="$(
        kubectl exec -n "${NGINX_NAMESPACE}" "${pod_name}" -- sh -lc "
            set -eu
            mkdir -p '${tmpdir}/includes'
            for required in \
                /etc/nginx/mime.types \
                /etc/nginx/includes/backend-headers.conf \
                /etc/nginx/includes/security-headers-dev-csp.conf \
                /etc/nginx/includes/security-headers-strict-csp.conf
            do
                if [ ! -f \"\${required}\" ]; then
                    printf 'missing runtime dependency: %s\n' \"\${required}\" >&2
                    exit 1
                fi
            done
            cp -R /etc/nginx/includes/. '${tmpdir}/includes/'
        " 2>&1
    )"; then
        fail "Production NGINX syntax validation could not stage the required runtime files from ${pod_name}"
        info_block "${prep_output}"
        kubectl exec -n "${NGINX_NAMESPACE}" "${pod_name}" -- sh -lc "rm -rf '${tmpdir}'" >/dev/null 2>&1 || true
        return
    fi

    if ! copy_output="$(
        kubectl exec -i -n "${NGINX_NAMESPACE}" "${pod_name}" -- sh -lc "cat > '${tmpdir}/nginx.production.k8s.conf'" \
            < "${config_path}" 2>&1
    )"; then
        fail "Could not copy ${PRODUCTION_NGINX_CONFIG_PATH} into ${pod_name} for syntax validation"
        info_block "${copy_output}"
        kubectl exec -n "${NGINX_NAMESPACE}" "${pod_name}" -- sh -lc "rm -rf '${tmpdir}'" >/dev/null 2>&1 || true
        return
    fi

    if validation_output="$(
        kubectl exec -n "${NGINX_NAMESPACE}" "${pod_name}" -- sh -lc "
            cd '${tmpdir}'
            nginx -p '${tmpdir}/' -t -c nginx.production.k8s.conf
        " 2>&1
    )"; then
        pass "Checked-in production NGINX config parses successfully inside ${pod_name}"
    else
        fail "Checked-in production NGINX config does not parse inside ${pod_name}"
        info_block "${validation_output}"
    fi

    kubectl exec -n "${NGINX_NAMESPACE}" "${pod_name}" -- sh -lc "rm -rf '${tmpdir}'" >/dev/null 2>&1 || true
}

verify_static_contracts() {
    section "Static Edge Contract"

    assert_file_contains "${REPO_DIR}/nginx/includes/security-headers-dev-csp.conf" "'unsafe-inline'" \
        "Dev CSP include keeps 'unsafe-inline' for Vite/HMR"
    assert_file_contains "${REPO_DIR}/nginx/includes/security-headers-dev-csp.conf" "'unsafe-eval'" \
        "Dev CSP include keeps 'unsafe-eval' for Vite/HMR"
    assert_file_contains "${REPO_DIR}/nginx/includes/security-headers-dev-csp.conf" "wss://app\\.budgetanalyzer\\.localhost" \
        "Dev CSP include still allows same-origin WSS for Vite HMR"

    assert_file_not_contains "${REPO_DIR}/nginx/includes/security-headers-strict-csp.conf" "'unsafe-inline'" \
        "Strict CSP include omits 'unsafe-inline'"
    assert_file_not_contains "${REPO_DIR}/nginx/includes/security-headers-strict-csp.conf" "'unsafe-eval'" \
        "Strict CSP include omits 'unsafe-eval'"
    assert_file_contains "${REPO_DIR}/nginx/includes/security-headers-strict-csp.conf" "object-src 'none'" \
        "Strict CSP include disables object-src"
    assert_file_contains "${REPO_DIR}/nginx/includes/security-headers-strict-csp.conf" "base-uri 'self'" \
        "Strict CSP include pins base-uri to self"
    warn_file_contains "${REPO_DIR}/nginx/includes/security-headers-docs-csp.conf" "style-src 'self' 'unsafe-inline'" \
        "Docs CSP include keeps the docs-only relaxed style policy explicit"
    warn_file_not_contains "${REPO_DIR}/nginx/includes/security-headers-docs-csp.conf" "'unsafe-eval'" \
        "Docs CSP include still omits 'unsafe-eval'"

    assert_file_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "include includes/security-headers-dev-csp\\.conf;" \
        "Dev NGINX config defaults to the relaxed CSP include"
    assert_file_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "location /@vite/client" \
        "Dev NGINX config still exposes the Vite client route"
    assert_file_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "location /src" \
        "Dev NGINX config still exposes the Vite source route"
    assert_file_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "location /node_modules" \
        "Dev NGINX config still exposes the Vite node_modules route"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "^[[:space:]]*location \\^~ /_prod-smoke/ \\{$" \
        "include includes/security-headers-strict-csp.conf;" \
        "Dev smoke route re-includes the strict CSP"

    # Keep docs assertions limited to the retained route graph.
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "^[[:space:]]*location = /api-docs \\{$" \
        "include includes/security-headers-docs-csp.conf;" \
        "Dev /api-docs route re-includes the docs-only CSP"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "^[[:space:]]*location = /api-docs \\{$" \
        "alias /usr/share/nginx/html/docs/index.html;" \
        "Dev /api-docs route still serves the checked-in docs shell"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "^[[:space:]]*location ~ \\^/api-docs/\\(swagger-ui\\\\\\.css\\|swagger-ui-bundle\\\\\\.js\\|swagger-initializer\\\\\\.js\\|swagger-ui-overrides\\\\\\.css\\)\\$ \\{$" \
        "alias /usr/share/nginx/html/docs/\$1;" \
        "Dev /api-docs route explicitly serves the self-hosted Swagger UI assets"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "^[[:space:]]*location ~ \\^/api-docs/\\(openapi\\\\\\.\\(json\\|yaml\\)\\)\\$ \\{$" \
        "alias /usr/share/nginx/html/docs/\$1;" \
        "Dev OpenAPI download route still serves the mounted spec files"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.k8s.conf" "^[[:space:]]*location /api-docs/ \\{$" \
        "return 404;" \
        "Dev /api-docs/* catch-all fails closed"

    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = /@vite/client \\{$" \
        "return 404;" \
        "Production config removes /@vite/client"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = /api-docs \\{$" \
        "include includes/security-headers-docs-csp.conf;" \
        "Production /api-docs route re-includes the docs-only CSP"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = /api-docs \\{$" \
        "alias /usr/share/nginx/html/docs/index.html;" \
        "Production /api-docs route still serves the checked-in docs shell"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location ~ \\^/api-docs/\\(swagger-ui\\\\\\.css\\|swagger-ui-bundle\\\\\\.js\\|swagger-initializer\\\\\\.js\\|swagger-ui-overrides\\\\\\.css\\)\\$ \\{$" \
        "alias /usr/share/nginx/html/docs/\$1;" \
        "Production /api-docs route explicitly serves the self-hosted Swagger UI assets"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location ~ \\^/api-docs/\\(openapi\\\\\\.\\(json\\|yaml\\)\\)\\$ \\{$" \
        "alias /usr/share/nginx/html/docs/\$1;" \
        "Production OpenAPI download route still serves the mounted spec files"
    warn_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location /api-docs/ \\{$" \
        "return 404;" \
        "Production /api-docs/* catch-all fails closed"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = /_prod-smoke \\{$" \
        "return 404;" \
        "Production config removes /_prod-smoke"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location \\^~ /_prod-smoke/ \\{$" \
        "return 404;" \
        "Production config removes /_prod-smoke/"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = /src \\{$" \
        "return 404;" \
        "Production config removes bare /src"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location \\^~ /src/ \\{$" \
        "return 404;" \
        "Production config removes /src/"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = /node_modules \\{$" \
        "return 404;" \
        "Production config removes bare /node_modules"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location \\^~ /node_modules/ \\{$" \
        "return 404;" \
        "Production config removes /node_modules/"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = /login \\{$" \
        "try_files /index.html =404;" \
        "Production config serves /login from the built frontend bundle"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location = / \\{$" \
        "try_files /index.html =404;" \
        "Production config serves / from the built frontend bundle"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location \\^~ /assets/ \\{$" \
        "root /usr/share/nginx/html;" \
        "Production config serves built frontend assets from local files"
    assert_location_block_contains "${REPO_DIR}/nginx/nginx.production.k8s.conf" "^[[:space:]]*location \\^~ /assets/ \\{$" \
        "try_files \$uri =404;" \
        "Production config resolves frontend assets without proxying to Vite"

    assert_file_contains "${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml" 'auth-sensitive' \
        "Ingress rate-limit config still marks auth-sensitive paths explicitly"
    assert_file_contains "${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml" 'login/oauth2' \
        "Ingress rate-limit config still covers /login/oauth2/*"
    assert_file_contains "${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml" 'oauth2' \
        "Ingress rate-limit config still covers /oauth2/*"
    assert_file_contains "${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml" 'auth\(\?:/\.\*\)\?' \
        "Ingress rate-limit config still covers /auth/*"
    assert_file_contains "${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml" 'logout' \
        "Ingress rate-limit config still covers /logout"
    assert_file_not_contains "${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml" 'logout\(\?:/\.\*\)\?\|user\|auth\(\?:/\.\*\)\?' \
        "Ingress rate-limit config no longer carries a standalone /user matcher"
    assert_file_contains "${REPO_DIR}/kubernetes/gateway/auth-httproute.yaml" 'value: /auth' \
        "Auth HTTPRoute still routes /auth/* to Session Gateway"
    assert_file_contains "${REPO_DIR}/kubernetes/gateway/auth-httproute.yaml" 'value: /oauth2' \
        "Auth HTTPRoute still routes /oauth2/* to Session Gateway"
    assert_file_contains "${REPO_DIR}/kubernetes/gateway/auth-httproute.yaml" 'value: /login/oauth2' \
        "Auth HTTPRoute still routes /login/oauth2/* to Session Gateway"
    assert_file_contains "${REPO_DIR}/kubernetes/gateway/auth-httproute.yaml" 'value: /logout' \
        "Auth HTTPRoute still routes /logout to Session Gateway"
    assert_file_not_contains "${REPO_DIR}/kubernetes/gateway/auth-httproute.yaml" 'value: /user' \
        "Auth HTTPRoute no longer exposes a standalone /user match"
    assert_file_contains "${REPO_DIR}/kubernetes/gateway/app-httproute.yaml" 'value: /api-docs' \
        "App HTTPRoute explicitly routes /api-docs through nginx-gateway"
}

verify_docs_fail_closed_response() {
    local path="$1" label="$2"
    local response status csp body_response body

    response="$(external_headers_and_status "${path}")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "404" ]]; then
        pass "${label} returns 404"
    else
        warn "${label} returned ${status:-000} (expected 404)"
    fi

    csp="$(extract_header_value "Content-Security-Policy" "${response}")"
    if [[ -n "${csp}" ]]; then
        pass "${label} includes a Content-Security-Policy header"
    else
        warn "${label} does not include a Content-Security-Policy header"
    fi

    body_response="$(curl -sk --max-time "${CURL_TIMEOUT}" --max-redirs 0 \
        -w '\nHTTP_STATUS:%{http_code}\n' \
        "${APP_BASE_URL}${path}" 2>/dev/null || true)"
    body="$(extract_body "${body_response}")"
    warn_text_excludes "${body}" "${label} does not fall through to the frontend SPA" "/@vite/client" "/src/main.tsx" '<div id="root"></div>'
}

verify_public_headers() {
    section "Public Header Contract"

    local response status csp

    response="$(external_headers_and_status "/")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "200" ]]; then
        pass "GET / returns 200 through the public ingress"
    else
        fail "GET / returned ${status:-000} (expected 200)"
    fi
    csp="$(extract_header_value "Content-Security-Policy" "${response}")"
    if [[ -n "${csp}" ]]; then
        pass "GET / includes a Content-Security-Policy header"
    else
        fail "GET / does not include a Content-Security-Policy header"
    fi
    assert_csp_contains "${csp}" "Dev frontend route keeps the relaxed Vite/HMR CSP" "'unsafe-inline'" "'unsafe-eval'" "wss://app.budgetanalyzer.localhost"

    response="$(external_headers_and_status "/@vite/client")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "200" ]]; then
        pass "GET /@vite/client returns 200 through the public ingress"
    else
        fail "GET /@vite/client returned ${status:-000} (expected 200)"
    fi
    csp="$(extract_header_value "Content-Security-Policy" "${response}")"
    assert_csp_contains "${csp}" "Vite client route still receives the relaxed dev CSP" "'unsafe-inline'" "'unsafe-eval'" "wss://app.budgetanalyzer.localhost"

    response="$(external_headers_and_status "/_prod-smoke/")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "200" ]]; then
        pass "GET /_prod-smoke/ returns 200 through the public ingress"
    else
        fail "GET /_prod-smoke/ returned ${status:-000} (expected 200)"
    fi
    csp="$(extract_header_value "Content-Security-Policy" "${response}")"
    if [[ -n "${csp}" ]]; then
        pass "GET /_prod-smoke/ includes a Content-Security-Policy header"
    else
        fail "GET /_prod-smoke/ does not include a Content-Security-Policy header"
    fi
    assert_csp_excludes "${csp}" "Production-smoke route omits unsafe CSP directives" "'unsafe-inline'" "'unsafe-eval'"
    assert_csp_contains "${csp}" "Production-smoke route uses the strict CSP contract" "script-src 'self'" "style-src 'self'" "object-src 'none'" "base-uri 'self'"
}

verify_public_api_route_not_spa() {
    local path="$1" label="$2"
    shift 2

    local response status content_type body_response body

    response="$(external_headers_and_status "${path}" "$@")"
    status="$(extract_http_status "${response}")"
    content_type="$(extract_header_value "Content-Type" "${response}")"

    if [[ "${content_type}" == text/html* ]]; then
        fail "${label} should not advertise text/html through the public ingress"
    else
        pass "${label} does not advertise text/html through the public ingress"
    fi

    if [[ "${status}" == "200" ]]; then
        info "${label} returned HTTP 200; checking body for SPA leakage"
    else
        info "${label} returned HTTP ${status:-000}; checking body for SPA leakage"
    fi

    body_response="$(external_body_and_status "${path}" "$@")"
    body="$(extract_body "${body_response}")"
    assert_text_excludes "${body}" "${label} does not fall through to the frontend SPA" \
        "/@vite/client" "/src/main.tsx" '<div id="root"></div>'
}

verify_public_api_route_ownership() {
    section "Public API Route Ownership"

    verify_public_api_route_not_spa \
        "/api/v1/transactions/search?page=0&size=1&sort=date,DESC&sort=id,DESC" \
        "Public transactions search collection route"
    verify_public_api_route_not_spa \
        "/api/v1/transactions/search/count" \
        "Public transactions search count route"
}

verify_docs_headers() {
    section "Docs Visibility (Warning-Only)"

    start_nginx_port_forward

    local response status csp cors

    response="$(external_headers_and_status "/api-docs")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "200" ]]; then
        pass "Public /api-docs route returns 200"
    else
        warn "Public /api-docs route returned ${status:-000} (expected 200)"
    fi
    csp="$(extract_header_value "Content-Security-Policy" "${response}")"
    if [[ -n "${csp}" ]]; then
        pass "Public /api-docs route includes a Content-Security-Policy header"
    else
        warn "Public /api-docs route does not include a Content-Security-Policy header"
    fi

    response="$(external_headers_and_status "/api-docs/openapi.json")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "200" ]]; then
        pass "Public /api-docs/openapi.json returns 200"
    else
        warn "Public /api-docs/openapi.json returned ${status:-000} (expected 200)"
    fi
    cors="$(extract_header_value "Access-Control-Allow-Origin" "${response}")"
    if [[ "${cors}" == "*" ]]; then
        warn "/api-docs/openapi.json still exposes wildcard CORS"
    else
        pass "/api-docs/openapi.json does not expose wildcard CORS"
    fi
    csp="$(extract_header_value "Content-Security-Policy" "${response}")"
    if [[ -n "${csp}" ]]; then
        pass "Public /api-docs/openapi.json includes a Content-Security-Policy header"
    else
        warn "Public /api-docs/openapi.json does not include a Content-Security-Policy header"
    fi

    response="$(external_headers_and_status "/api-docs/openapi.yaml")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "200" ]]; then
        pass "Public /api-docs/openapi.yaml returns 200"
    else
        warn "Public /api-docs/openapi.yaml returned ${status:-000} (expected 200)"
    fi
    cors="$(extract_header_value "Access-Control-Allow-Origin" "${response}")"
    if [[ "${cors}" == "*" ]]; then
        warn "/api-docs/openapi.yaml still exposes wildcard CORS"
    else
        pass "/api-docs/openapi.yaml does not expose wildcard CORS"
    fi
    csp="$(extract_header_value "Content-Security-Policy" "${response}")"
    if [[ -n "${csp}" ]]; then
        pass "Public /api-docs/openapi.yaml includes a Content-Security-Policy header"
    else
        warn "Public /api-docs/openapi.yaml does not include a Content-Security-Policy header"
    fi

    verify_docs_fail_closed_response "/api-docs/not-a-real-file" "Public unknown /api-docs path"

    response="$(local_nginx_headers_and_status "/api-docs")"
    status="$(extract_http_status "${response}")"
    if [[ "${status}" == "200" ]]; then
        pass "Direct NGINX /api-docs route returns 200"
    else
        warn "Direct NGINX /api-docs route returned ${status:-000} (expected 200)"
    fi
}

verify_auth_edge_runtime() {
    section "Auth Edge Runtime Coverage"

    INGRESS_CLUSTER_IP="$(kubectl get svc "${INGRESS_SERVICE_NAME}" -n "${INGRESS_NAMESPACE}" -o jsonpath='{.spec.clusterIP}')"
    if [[ -z "${INGRESS_CLUSTER_IP}" ]]; then
        printf 'ERROR: could not determine ClusterIP for %s/%s\n' "${INGRESS_NAMESPACE}" "${INGRESS_SERVICE_NAME}" >&2
        exit 1
    fi

    create_probe_policy
    create_probe_pod
    wait_for_probe_ready

    require_ingress_rate_limit_from_probe "/login" "/login"
    require_ingress_rate_limit_from_probe "/auth/v1/user" "/auth/v1/user"
    require_ingress_rate_limit_from_probe "/logout" "/logout"
    require_ingress_rate_limit_from_probe "/login/oauth2/code/idp?code=phase6&state=phase6" "/login/oauth2/code/idp"
}

verify_nested_verifiers() {
    section "Nested Verifiers"
    info "Per-verifier timeout: ${SUBVERIFIER_TIMEOUT}"
    info "Phase 5 regression timeout: ${PHASE5_REGRESSION_TIMEOUT}"

    run_subverifier \
        "Phase 6 Session 3 strict-CSP audit" \
        "${SCRIPT_DIR}/audit-phase-6-session-3-frontend-csp.sh"

    run_subverifier \
        "Phase 6 Session 7 API rate-limit identity verifier" \
        "${SCRIPT_DIR}/verify-phase-6-session-7-api-rate-limit-identity.sh"

    run_subverifier \
        "Phase 5 runtime-hardening regression cascade" \
        "${SCRIPT_DIR}/verify-phase-5-runtime-hardening.sh" \
        --regression-timeout "${PHASE5_REGRESSION_TIMEOUT}"
}

main() {
    echo "==============================================================="
    echo "  Phase 6 Edge + Browser Hardening Verifier"
    echo "==============================================================="
    echo

    require_host_command curl
    require_host_command kubectl
    require_host_command rg
    require_host_command timeout
    require_cluster_access

    verify_production_nginx_syntax
    verify_static_contracts
    verify_public_headers
    verify_public_api_route_ownership
    verify_docs_headers
    verify_auth_edge_runtime
    verify_nested_verifiers

    section "Summary"
    printf 'Passed: %d\n' "${PASSED}"
    printf 'Failed: %d\n' "${FAILED}"
    printf 'Warnings: %d\n' "${WARNED}"
    info "Manual browser-console validation is still required on /_prod-smoke/ before Phase 6 can be called complete"
    info "Warnings from /api-docs checks stay visible here but do not block Phase 6 completion"

    echo
    echo "==============================================================="
    total=$((PASSED + FAILED))
    if [[ "${FAILED}" -eq 0 ]]; then
        echo "  ${PASSED} passed, ${WARNED} warnings (out of ${total} blocking checks)"
    else
        echo "  ${PASSED} passed, ${FAILED} failed, ${WARNED} warnings (out of ${total} blocking checks)"
    fi
    echo "==============================================================="

    [[ "${FAILED}" -gt 0 ]] && exit 1 || exit 0
}

main "$@"
