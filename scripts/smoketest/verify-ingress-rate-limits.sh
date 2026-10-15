#!/bin/bash

# Focused live proof for the four per-client ingress local-rate-limit policies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=scripts/lib/local-kubernetes-target.sh
source "${SCRIPT_DIR}/../lib/local-kubernetes-target.sh"
# shellcheck source=scripts/lib/redis-cli.sh
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

PROBE_NAMESPACE="default"
PROBE_LABEL_KEY="verify-ingress-rate-limits-temp"
PROBE_LABEL_VALUE="true"
PROBE_POD_A="ingress-rate-limit-probe-a"
PROBE_POD_B="ingress-rate-limit-probe-b"
PROBE_POLICY_NAME="allow-ingress-rate-limit-egress"
PROBE_CA_CONFIGMAP="ingress-rate-limit-probe-ca"
# renovate: datasource=docker depName=curlimages/curl
PROBE_IMAGE="curlimages/curl:8.12.1@sha256:94e9e444bcba979c2ea12e27ae39bee4cd10bc7041a472c4727a558e213744e6"
PROBE_CA_FILE="${REPO_DIR}/nginx/certs/k8s/_mkcert-rootCA.pem"
PROBE_CA_MOUNT="/etc/budget-analyzer-ca/ca.crt"
INGRESS_NAMESPACE="istio-ingress"
INGRESS_DEPLOYMENT="istio-ingress-gateway-istio"
INGRESS_SERVICE_NAME="istio-ingress-gateway-istio"
INGRESS_LABEL_SELECTOR="gateway.networking.k8s.io/gateway-name=istio-ingress-gateway"
NGINX_DEPLOYMENT="deployment/nginx-gateway"
FORGED_XFF_PRIMARY="198.51.100.77"
FORGED_XFF_SECONDARY="198.51.100.99"
SESSION_ID=""
ORIGINAL_INGRESS_REPLICAS=""
REPLICAS_CHANGED=false
INGRESS_CLUSTER_IP=""
PORT_FORWARD_PIDS=()
PORT_FORWARD_LOGS=()
PASSED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-ingress-rate-limits.sh [options]

Options:
  -h, --help  Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

pass() {
    printf '  [PASS] %s\n' "$1"
    PASSED=$((PASSED + 1))
}

section() {
    printf '\n=== %s ===\n' "$1"
}

die() {
    printf '  [FAIL] %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

cleanup_session() {
    [[ -n "${SESSION_ID}" ]] || return 0

    local redis_pod redis_password
    redis_pod=$(kubectl get pod -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    redis_password=$(kubectl get secret redis-bootstrap-credentials -n infrastructure \
        -o jsonpath='{.data.ops-password}' 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -n "${redis_pod}" && -n "${redis_password}" ]]; then
        redis_cli_in_pod infrastructure "${redis_pod}" redis-ops "${redis_password}" \
            DEL "session:${SESSION_ID}" >/dev/null 2>&1 || true
    fi
}

stop_port_forwards() {
    local pid log_file
    for pid in "${PORT_FORWARD_PIDS[@]:-}"; do
        [[ -n "${pid}" ]] || continue
        kill "${pid}" >/dev/null 2>&1 || true
        wait "${pid}" >/dev/null 2>&1 || true
    done
    for log_file in "${PORT_FORWARD_LOGS[@]:-}"; do
        [[ -n "${log_file}" ]] || continue
        rm -f "${log_file}" >/dev/null 2>&1 || true
    done
    PORT_FORWARD_PIDS=()
    PORT_FORWARD_LOGS=()
}

cleanup() {
    local exit_code=$?
    set +e
    stop_port_forwards

    if assert_local_kind_target >/dev/null 2>&1; then
        if [[ "${REPLICAS_CHANGED}" == "true" && -n "${ORIGINAL_INGRESS_REPLICAS}" ]]; then
            kubectl scale deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
                --replicas="${ORIGINAL_INGRESS_REPLICAS}" >/dev/null 2>&1 || true
            kubectl rollout status deployment/"${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
                --timeout=120s >/dev/null 2>&1 || true
        fi
        cleanup_session
        kubectl delete pod,networkpolicy,configmap -n "${PROBE_NAMESPACE}" \
            -l "${PROBE_LABEL_KEY}=${PROBE_LABEL_VALUE}" \
            --ignore-not-found --wait=false >/dev/null 2>&1 || true
    else
        printf 'WARNING: exact local Kind guard failed; temporary cluster resources were not mutated during cleanup.\n' >&2
    fi

    exit "${exit_code}"
}

trap cleanup EXIT

create_probe_resources() {
    assert_local_kind_target

    kubectl delete pod,networkpolicy,configmap -n "${PROBE_NAMESPACE}" \
        -l "${PROBE_LABEL_KEY}=${PROBE_LABEL_VALUE}" \
        --ignore-not-found --wait=true >/dev/null

    kubectl create configmap "${PROBE_CA_CONFIGMAP}" -n "${PROBE_NAMESPACE}" \
        --from-file="ca.crt=${PROBE_CA_FILE}" --dry-run=client -o yaml |
        kubectl label --local -f - "${PROBE_LABEL_KEY}=${PROBE_LABEL_VALUE}" -o yaml |
        kubectl apply -f - >/dev/null

    kubectl apply -f - >/dev/null <<MANIFEST
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${PROBE_POLICY_NAME}
  namespace: ${PROBE_NAMESPACE}
  labels:
    ${PROBE_LABEL_KEY}: "${PROBE_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      ${PROBE_LABEL_KEY}: "${PROBE_LABEL_VALUE}"
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${INGRESS_NAMESPACE}
          podSelector:
            matchLabels:
              gateway.networking.k8s.io/gateway-name: istio-ingress-gateway
      ports:
        - protocol: TCP
          port: 443
---
apiVersion: v1
kind: Pod
metadata:
  name: ${PROBE_POD_A}
  namespace: ${PROBE_NAMESPACE}
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
      volumeMounts:
        - name: public-ca
          mountPath: /etc/budget-analyzer-ca
          readOnly: true
  volumes:
    - name: public-ca
      configMap:
        name: ${PROBE_CA_CONFIGMAP}
  terminationGracePeriodSeconds: 0
---
apiVersion: v1
kind: Pod
metadata:
  name: ${PROBE_POD_B}
  namespace: ${PROBE_NAMESPACE}
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
      volumeMounts:
        - name: public-ca
          mountPath: /etc/budget-analyzer-ca
          readOnly: true
  volumes:
    - name: public-ca
      configMap:
        name: ${PROBE_CA_CONFIGMAP}
  terminationGracePeriodSeconds: 0
MANIFEST

    kubectl wait --for=condition=Ready pod/"${PROBE_POD_A}" pod/"${PROBE_POD_B}" \
        -n "${PROBE_NAMESPACE}" --timeout=120s >/dev/null
}

probe_response() {
    local pod_name="$1" path="$2" forged_xff="${3:-}" session_id="${4:-}" probe_id="${5:-rate-limit-probe}"
    local -a curl_args=(
        curl --silent --show-error --max-time 10 --max-redirs 0
        --cacert "${PROBE_CA_MOUNT}"
        --resolve "app.budgetanalyzer.localhost:443:${INGRESS_CLUSTER_IP}"
        -A "${probe_id}"
        -D - -o /dev/null -w 'HTTP_STATUS:%{http_code}\n'
    )
    [[ -z "${forged_xff}" ]] || curl_args+=(-H "X-Forwarded-For: ${forged_xff}")
    [[ -z "${session_id}" ]] || curl_args+=(--cookie "BA_SESSION=${session_id}")
    curl_args+=("https://app.budgetanalyzer.localhost${path}")
    kubectl exec -n "${PROBE_NAMESPACE}" "${pod_name}" -- "${curl_args[@]}" 2>/dev/null
}

response_status() {
    sed -n 's/^HTTP_STATUS://p' | tail -n 1
}

response_marker() {
    sed -n 's/^[[:space:]]*x-local-rate-limit-policy:[[:space:]]*//Ip' | tail -n 1 | tr -d '\r'
}

probe_burst() {
    local pod_name="$1" path="$2" count="$3" parallelism="$4" forged_mode="$5" prefix="$6"
    kubectl exec -i -n "${PROBE_NAMESPACE}" "${pod_name}" -- sh -s -- \
        "${INGRESS_CLUSTER_IP}" "${PROBE_CA_MOUNT}" "${path}" "${count}" "${parallelism}" \
        "${forged_mode}" "${prefix}" <<'POD_BURST'
set -u
ingress_ip="$1"
ca_file="$2"
path="$3"
count="$4"
parallelism="$5"
forged_mode="$6"
prefix="$7"
i=1
active=0
case "$path" in
    *\?*) separator='&' ;;
    *) separator='?' ;;
esac

while [ "$i" -le "$count" ]; do
    (
        forged_header=""
        case "$forged_mode" in
            fixed) forged_header="198.51.100.77" ;;
            rotate) forged_header="198.51.100.$((i % 200 + 1))" ;;
        esac
        if [ -n "$forged_header" ]; then
            result=$(curl --silent --show-error --max-time 10 --max-redirs 0 \
                --cacert "$ca_file" \
                --resolve "app.budgetanalyzer.localhost:443:${ingress_ip}" \
                -A "${prefix}-${i}" \
                -H "X-Forwarded-For: ${forged_header}" \
                -o /dev/null \
                -w '%{http_code}|%header{x-local-rate-limit-policy}\n' \
                "https://app.budgetanalyzer.localhost${path}${separator}probe=${prefix}-${i}" 2>/dev/null || true)
        else
            result=$(curl --silent --show-error --max-time 10 --max-redirs 0 \
                --cacert "$ca_file" \
                --resolve "app.budgetanalyzer.localhost:443:${ingress_ip}" \
                -A "${prefix}-${i}" \
                -o /dev/null \
                -w '%{http_code}|%header{x-local-rate-limit-policy}\n' \
                "https://app.budgetanalyzer.localhost${path}${separator}probe=${prefix}-${i}" 2>/dev/null || true)
        fi
        printf '%s\n' "${result:-000|}"
    ) &
    active=$((active + 1))
    if [[ "$active" -ge "$parallelism" ]]; then
        wait
        active=0
    fi
    i=$((i + 1))
done
wait
POD_BURST
}

burst_count_status() {
    local status="$1"
    awk -F'|' -v status="${status}" '$1 == status {count++} END {print count + 0}'
}

assert_burst_rejected() {
    local output="$1" policy="$2" label="$3"
    local rejected wrong_marker failed_transport
    rejected=$(printf '%s\n' "${output}" | burst_count_status 429)
    wrong_marker=$(printf '%s\n' "${output}" | awk -F'|' -v policy="${policy}" '$1 == 429 && $2 != policy {count++} END {print count + 0}')
    failed_transport=$(printf '%s\n' "${output}" | burst_count_status 000)
    [[ "${failed_transport}" -eq 0 ]] || die "${label} had ${failed_transport} transport failures"
    [[ "${rejected}" -gt 0 ]] || die "${label} did not produce an ingress rejection"
    [[ "${wrong_marker}" -eq 0 ]] || die "${label} had ${wrong_marker} HTTP 429 responses without the ${policy} marker"
    pass "${label} exhausted only the policy-marked ${policy} allowance (${rejected} rejected)"
}

assert_response_not_limited() {
    local response="$1" label="$2" expected_status="${3:-}"
    local status marker
    status=$(printf '%s\n' "${response}" | response_status)
    marker=$(printf '%s\n' "${response}" | response_marker)
    [[ -n "${status}" && "${status}" != "000" && "${status}" != "429" ]] || die "${label} was unavailable (HTTP ${status:-000})"
    [[ -z "${expected_status}" || "${status}" == "${expected_status}" ]] || die "${label} returned HTTP ${status}, expected ${expected_status}"
    [[ -z "${marker}" ]] || die "${label} unexpectedly carried policy marker ${marker}"
    pass "${label} remained available (HTTP ${status})"
}

gateway_pods() {
    kubectl get pod -n "${INGRESS_NAMESPACE}" -l "${INGRESS_LABEL_SELECTOR}" \
        --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort
}

envoy_stat() {
    local pod_name="$1" stat_name="$2"
    kubectl exec -n "${INGRESS_NAMESPACE}" "${pod_name}" -c istio-proxy -- \
        curl -sS http://127.0.0.1:15000/stats 2>/dev/null |
        awk -F': ' -v stat_name="${stat_name}" '$1 == stat_name {print $2; found=1} END {if (!found) print 0}'
}

ext_authz_request_count() {
    local pod_name="$1"
    kubectl exec -n "${INGRESS_NAMESPACE}" "${pod_name}" -c istio-proxy -- \
        curl -sS http://127.0.0.1:15000/clusters 2>/dev/null |
        awk -F'::' '/^outbound\|9002\|\|ext-authz\.default\.svc\.cluster\.local::/ && /::rq_total::/ {sum += $NF} END {print sum + 0}'
}

verify_live_filter_order() {
    local pod_name="$1" chain
    chain=$(kubectl exec -n "${INGRESS_NAMESPACE}" "${pod_name}" -c istio-proxy -- \
        pilot-agent request GET config_dump 2>/dev/null |
        jq -r '[.. | objects | select(.name? == "envoy.filters.network.http_connection_manager") | .typed_config.http_filters? // empty | map(.name)] | .[] | select(index("envoy.filters.http.ext_authz")) | @tsv' |
        head -n 1)
    [[ -n "${chain}" ]] || die "could not locate the live ingress HTTP filter chain"

    python3 - "${chain}" <<'PY'
import sys

chain = sys.argv[1].split("\t")
expected = [
    "envoy.filters.http.local_ratelimit.login_initiation",
    "envoy.filters.http.local_ratelimit.login_completion",
    "envoy.filters.http.local_ratelimit.session_operations",
    "envoy.filters.http.local_ratelimit.api_requests",
]
if any(chain.count(name) != 1 for name in expected):
    raise SystemExit("live chain does not contain exactly one of each named limiter")
if "envoy.filters.http.local_ratelimit" in chain:
    raise SystemExit("live chain still contains the retired generic auth limiter")
ext_authz = chain.index("envoy.filters.http.ext_authz")
if any(chain.index(name) >= ext_authz for name in expected):
    raise SystemExit("a named limiter is not before ext_authz")
PY
    pass "live listener has exactly four named limiters before ext_authz and no legacy generic limiter"
}

find_nginx_log_line() {
    local probe_id="$1" line
    for _ in 1 2 3 4 5; do
        line=$(kubectl logs "${NGINX_DEPLOYMENT}" --tail=1200 2>/dev/null | rg -F "${probe_id}" | tail -n 1 || true)
        if [[ -n "${line}" ]]; then
            printf '%s\n' "${line}"
            return 0
        fi
        sleep 1
    done
    return 1
}

verify_nginx_forwarded_identity() {
    local pod_name="$1" forged_xff="$2" session_id="$3" probe_id="$4" expected_ip="$5"
    local response status log_line
    response=$(probe_response "${pod_name}" "/api/v1/transactions?identity_probe=${probe_id}" \
        "${forged_xff}" "${session_id}" "${probe_id}")
    status=$(printf '%s\n' "${response}" | response_status)
    [[ "${status}" == "200" ]] || die "NGINX identity request from ${pod_name} returned HTTP ${status:-000}"
    log_line=$(find_nginx_log_line "${probe_id}" || true)
    [[ -n "${log_line}" ]] || die "NGINX did not log the forwarded-identity request from ${pod_name}"
    [[ "${log_line}" == *"remote_addr=${expected_ip} "* ]] || die "NGINX did not derive ${expected_ip} for ${pod_name}"
    [[ "${log_line}" != *"remote_addr=${forged_xff} "* ]] || die "NGINX trusted forged X-Forwarded-For for ${pod_name}"
    [[ "${log_line}" =~ proxy_addr=127\. ]] || die "NGINX trusted proxy hop was not pod-local loopback for ${pod_name}"
    [[ "${log_line}" == *"xff=\"${forged_xff},${expected_ip}\""* || "${log_line}" == *"xff=\"${forged_xff}, ${expected_ip}\""* ]] ||
        die "NGINX did not preserve the caller value plus ingress-appended client hop for ${pod_name}"
}

start_pod_port_forward() {
    local pod_name="$1" log_file port
    log_file=$(mktemp)
    kubectl port-forward -n "${INGRESS_NAMESPACE}" "pod/${pod_name}" :443 >"${log_file}" 2>&1 &
    PORT_FORWARD_PIDS+=("$!")
    PORT_FORWARD_LOGS+=("${log_file}")
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        port=$(sed -n 's/.*127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "${log_file}" | tail -n 1)
        if [[ -n "${port}" ]]; then
            printf '%s\n' "${port}"
            return 0
        fi
        sleep 1
    done
    cat "${log_file}" >&2
    return 1
}

port_forward_burst() {
    local port="$1" count="$2" prefix="$3"
    seq 1 "${count}" | xargs -I{} -P "${count}" sh -c '
        curl --silent --show-error --max-time 10 --max-redirs 0 --http1.1 \
            --resolve "app.budgetanalyzer.localhost:'"${port}"':127.0.0.1" \
            -H "Host: app.budgetanalyzer.localhost" \
            -o /dev/null -w "%{http_code}|%header{x-local-rate-limit-policy}\\n" \
            "https://app.budgetanalyzer.localhost:'"${port}"'/oauth2/authorization/idp?replica_probe='"${prefix}"'-{}"'
}

verify_replica_semantics() {
    local -a pods
    local port_a port_b output status_b

    assert_local_kind_target
    REPLICAS_CHANGED=true
    kubectl scale deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" --replicas=2 >/dev/null
    kubectl rollout status deployment/"${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" --timeout=120s >/dev/null
    mapfile -t pods < <(gateway_pods)
    [[ "${#pods[@]}" -eq 2 ]] || die "replica proof expected exactly two Running ingress pods"

    verify_live_filter_order "${pods[0]}"
    verify_live_filter_order "${pods[1]}"
    port_a=$(start_pod_port_forward "${pods[0]}") || die "could not port-forward the first ingress pod"
    port_b=$(start_pod_port_forward "${pods[1]}") || die "could not port-forward the second ingress pod"

    output=$(port_forward_burst "${port_a}" 35 "replica-a")
    assert_burst_rejected "${output}" "login-initiation" "first ingress instance"
    status_b=$(curl --silent --show-error --max-time 10 --max-redirs 0 --http1.1 \
        --resolve "app.budgetanalyzer.localhost:${port_b}:127.0.0.1" \
        -H 'Host: app.budgetanalyzer.localhost' \
        -o /dev/null -w '%{http_code}' \
        "https://app.budgetanalyzer.localhost:${port_b}/oauth2/authorization/idp?replica_probe=b")
    [[ "${status_b}" == "302" ]] || die "second ingress instance returned HTTP ${status_b} after first-instance exhaustion"
    pass "same client identity retained an independent allowance on the second ingress instance"

    stop_port_forwards
    assert_local_kind_target
    kubectl scale deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
        --replicas="${ORIGINAL_INGRESS_REPLICAS}" >/dev/null
    kubectl rollout status deployment/"${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" --timeout=120s >/dev/null
    REPLICAS_CHANGED=false
    pass "repo-defined ingress replica count ${ORIGINAL_INGRESS_REPLICAS} restored"
}

main() {
    local command_name ingress_pod pod_ip_a pod_ip_b response output
    local ext_before ext_after accepted rejected controlled_before controlled_after
    local controlled_accepted controlled_rejected
    local stat_value

    echo "==============================================================="
    echo "  Ingress Per-Client Rate-Limit Verifier"
    echo "==============================================================="

    for command_name in base64 curl jq kubectl python3 rg xargs; do
        require_command "${command_name}"
    done
    [[ -s "${PROBE_CA_FILE}" ]] || die "required imported public CA is missing: ${PROBE_CA_FILE}"
    assert_local_kind_target

    ORIGINAL_INGRESS_REPLICAS=$(kubectl get deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
        -o jsonpath='{.spec.replicas}')
    [[ "${ORIGINAL_INGRESS_REPLICAS}" == "1" ]] || die "repo-defined local proof requires one ingress replica before setup"
    INGRESS_CLUSTER_IP=$(kubectl get service "${INGRESS_SERVICE_NAME}" -n "${INGRESS_NAMESPACE}" \
        -o jsonpath='{.spec.clusterIP}')
    [[ -n "${INGRESS_CLUSTER_IP}" ]] || die "could not resolve the ingress Service ClusterIP"
    ingress_pod=$(gateway_pods)
    [[ "$(printf '%s\n' "${ingress_pod}" | sed '/^$/d' | wc -l)" -eq 1 ]] || die "main isolation proof requires one Running ingress pod"

    section "Static And Live Configuration"
    "${SCRIPT_DIR}/verify-ingress-rate-limit-config.sh"
    ! rg -n 'limit_req(_zone|_status)?[[:space:]]' \
        "${REPO_DIR}/nginx/nginx.k8s.conf" \
        "${REPO_DIR}/nginx/nginx.production.k8s.conf" \
        "${REPO_DIR}/kubernetes/production/nginx/nginx.production.k8s.conf" >/dev/null ||
        die "blanket NGINX limit_req configuration remains after ingress cutover"
    pass "all local and production NGINX inputs have relinquished blanket API limiting"
    ! kubectl get envoyfilter ingress-auth-local-rate-limit -n "${INGRESS_NAMESPACE}" >/dev/null 2>&1 ||
        die "retired ingress-auth-local-rate-limit EnvoyFilter still exists"
    verify_live_filter_order "${ingress_pod}"

    section "Controlled Client Setup"
    create_probe_resources
    pod_ip_a=$(kubectl get pod "${PROBE_POD_A}" -n "${PROBE_NAMESPACE}" -o jsonpath='{.status.podIP}')
    pod_ip_b=$(kubectl get pod "${PROBE_POD_B}" -n "${PROBE_NAMESPACE}" -o jsonpath='{.status.podIP}')
    [[ -n "${pod_ip_a}" && -n "${pod_ip_b}" && "${pod_ip_a}" != "${pod_ip_b}" ]] ||
        die "controlled clients do not have two distinct pod source addresses"
    pass "controlled clients have distinct source addresses ${pod_ip_a} and ${pod_ip_b}"

    SESSION_ID="ingress-rate-limit-$(date +%s)-${RANDOM}"
    assert_local_kind_target
    SESSION_TTL_SECONDS=600 "${SCRIPT_DIR}/../ops/seed-ext-authz-session.sh" "${SESSION_ID}" >/dev/null
    verify_nginx_forwarded_identity "${PROBE_POD_A}" "${FORGED_XFF_PRIMARY}" "${SESSION_ID}" \
        "${SESSION_ID}-identity-a" "${pod_ip_a}"
    verify_nginx_forwarded_identity "${PROBE_POD_B}" "${FORGED_XFF_SECONDARY}" "${SESSION_ID}" \
        "${SESSION_ID}-identity-b" "${pod_ip_b}"
    pass "NGINX preserves ingress-appended client identity and ignores forged forwarding identity"

    section "Login Initiation Isolation"
    response=$(probe_response "${PROBE_POD_A}" "/oauth2/authorization/idp" "${FORGED_XFF_PRIMARY}")
    assert_response_not_limited "${response}" "client A login initiation baseline" 302
    output=$(probe_burst "${PROBE_POD_A}" "/oauth2/authorization/idp" 35 35 fixed "init-a")
    assert_burst_rejected "${output}" "login-initiation" "client A login initiation"
    response=$(probe_response "${PROBE_POD_B}" "/oauth2/authorization/idp" "${FORGED_XFF_PRIMARY}")
    assert_response_not_limited "${response}" "client B login initiation through the same Envoy instance" 302

    output=$(probe_burst "${PROBE_POD_A}" "/oauth2/authorization/idp" 5 5 rotate "init-forged-a")
    [[ "$(printf '%s\n' "${output}" | burst_count_status 429)" -eq 5 ]] ||
        die "rotating forged forwarding headers escaped client A's exhausted initiation bucket"
    assert_burst_rejected "${output}" "login-initiation" "client A forged-header rotation"

    response=$(probe_response "${PROBE_POD_A}" "/login/oauth2/code/idp?code=invalid&state=invalid")
    assert_response_not_limited "${response}" "client A login callback after initiation exhaustion"
    response=$(probe_response "${PROBE_POD_A}" "/auth/v1/user")
    assert_response_not_limited "${response}" "client A session operation after initiation exhaustion" 401
    sleep 2
    response=$(probe_response "${PROBE_POD_A}" "/oauth2/authorization/idp?refill=1")
    assert_response_not_limited "${response}" "client A initiation after the one-second refill" 302

    section "Login Completion Isolation"
    output=$(probe_burst "${PROBE_POD_A}" "/login/oauth2/code/idp?code=invalid&state=invalid" 65 65 rotate "callback-a")
    assert_burst_rejected "${output}" "login-completion" "client A login completion"
    response=$(probe_response "${PROBE_POD_A}" "/auth/v1/session")
    assert_response_not_limited "${response}" "client A session operation after callback exhaustion" 401

    section "API Isolation And Authorization Order"
    response=$(probe_response "${PROBE_POD_A}" "/api/v1/transactions?baseline=1" "${FORGED_XFF_PRIMARY}")
    assert_response_not_limited "${response}" "unauthenticated client A API baseline" 401
    ext_before=$(ext_authz_request_count "${ingress_pod}")
    output=$(probe_burst "${PROBE_POD_A}" "/api/v1/transactions" 90 90 rotate "api-a")
    assert_burst_rejected "${output}" "api-requests" "unauthenticated client A API"
    accepted=$(printf '%s\n' "${output}" | awk -F'|' '$1 != 429 && $1 != 000 {count++} END {print count + 0}')
    rejected=$(printf '%s\n' "${output}" | burst_count_status 429)
    ext_after=$(ext_authz_request_count "${ingress_pod}")
    [[ $((ext_after - ext_before)) -eq "${accepted}" ]] ||
        die "ext_authz request delta $((ext_after - ext_before)) did not match ${accepted} ingress-admitted API requests"
    pass "only the ${accepted} ingress-admitted API requests invoked ext_authz; ${rejected} ingress rejections did not"

    controlled_before=$(ext_authz_request_count "${ingress_pod}")
    output=$(probe_burst "${PROBE_POD_A}" "/api/v1/transactions" 20 20 rotate "api-order-a")
    assert_burst_rejected "${output}" "api-requests" "controlled exhausted API probe"
    controlled_accepted=$(printf '%s\n' "${output}" | awk -F'|' '$1 != 429 && $1 != 000 {count++} END {print count + 0}')
    controlled_rejected=$(printf '%s\n' "${output}" | burst_count_status 429)
    controlled_after=$(ext_authz_request_count "${ingress_pod}")
    [[ $((controlled_after - controlled_before)) -eq "${controlled_accepted}" ]] ||
        die "controlled ext_authz delta $((controlled_after - controlled_before)) did not match ${controlled_accepted} admitted requests"
    pass "controlled follow-up proved ${controlled_rejected} ingress rejections did not invoke ext_authz while refill-admitted requests did"

    response=$(probe_response "${PROBE_POD_B}" "/api/v1/transactions?client=b" "${FORGED_XFF_PRIMARY}")
    assert_response_not_limited "${response}" "client B API allowance through the same Envoy instance" 401
    response=$(probe_response "${PROBE_POD_A}" "/auth/v1/user")
    assert_response_not_limited "${response}" "client A session allowance after API exhaustion" 401

    section "Policy Diagnostics"
    for stat_value in \
        ingress_login_initiation.http_local_rate_limit.enforced \
        ingress_login_completion.http_local_rate_limit.enforced \
        ingress_api_requests.http_local_rate_limit.enforced; do
        [[ "$(envoy_stat "${ingress_pod}" "${stat_value}")" -gt 0 ]] || die "live Envoy counter ${stat_value} did not record a rejection"
    done
    [[ "$(envoy_stat "${ingress_pod}" ingress_session_operations.http_local_rate_limit.ok)" -gt 0 ]] ||
        die "live Envoy session-operation acceptance counter did not increment"
    pass "policy-specific accepted and enforced counters are exposed by the live ingress"

    section "Browser Callback Completion"
    "${REPO_DIR}/../budget-analyzer-api-tests/.venv/bin/python" \
        "${SCRIPT_DIR}/verify-ingress-browser-callback.py"
    pass "real browser login completed its original callback after same-client initiation exhaustion"

    section "Per-Instance Replica Semantics"
    verify_replica_semantics

    section "Cleanup Proof"
    assert_local_kind_target
    cleanup_session
    SESSION_ID=""
    kubectl delete pod,networkpolicy,configmap -n "${PROBE_NAMESPACE}" \
        -l "${PROBE_LABEL_KEY}=${PROBE_LABEL_VALUE}" --ignore-not-found --wait=true >/dev/null
    if kubectl get pod,networkpolicy,configmap -n "${PROBE_NAMESPACE}" \
        -l "${PROBE_LABEL_KEY}=${PROBE_LABEL_VALUE}" -o name | rg -q .; then
        die "temporary rate-limit probe resources remain"
    fi
    [[ "$(kubectl get deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" -o jsonpath='{.spec.replicas}')" == "${ORIGINAL_INGRESS_REPLICAS}" ]] ||
        die "ingress replica count was not restored"
    pass "temporary clients, policy, CA ConfigMap, session, port-forwards, and replica change were cleaned up"

    printf '\nIngress rate-limit verification succeeded (%d checks passed).\n' "${PASSED}"
}

main "$@"
