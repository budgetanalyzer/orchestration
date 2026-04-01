#!/bin/bash

# Runtime verification for Security Hardening v2 Phase 6 Session 7.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROBE_NAMESPACE="default"
PROBE_LABEL_KEY="verify-phase6-session7-temp"
PROBE_LABEL_VALUE="true"
PROBE_POD_A="phase6-session7-probe-a"
PROBE_POD_B="phase6-session7-probe-b"
PROBE_POLICY_NAME="allow-phase6-session7-egress-to-istio-ingress"
PROBE_IMAGE="curlimages/curl:8.12.1@sha256:94e9e444bcba979c2ea12e27ae39bee4cd10bc7041a472c4727a558e213744e6"
NGINX_DEPLOYMENT="deployment/nginx-gateway"
NGINX_LOG_TAIL_LINES=1200
INGRESS_NAMESPACE="istio-ingress"
INGRESS_SERVICE_NAME="istio-ingress-gateway-istio"
INGRESS_POD_LABEL_KEY="gateway.networking.k8s.io/gateway-name"
INGRESS_POD_LABEL_VALUE="istio-ingress-gateway"
FORGED_XFF_PRIMARY="198.51.100.77"
FORGED_XFF_SECONDARY="198.51.100.99"
API_BURST_REQUESTS=45
EXPECTED_PROXY_REGEX='^127\.'

PASSED=0
FAILED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh

Options:
  -h, --help    Show this help text.
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

pass()    { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail()    { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }

cleanup() {
    set +e
    kubectl delete pod "${PROBE_POD_A}" "${PROBE_POD_B}" -n "${PROBE_NAMESPACE}" \
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
    if ! kubectl get namespace "${PROBE_NAMESPACE}" >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes API or %s namespace\n' "${PROBE_NAMESPACE}" >&2
        exit 1
    fi
}

extract_log_field() {
    local field_name="$1" log_line="$2"
    printf '%s\n' "$log_line" | sed -n "s/.*${field_name}=\\([^ ]*\\).*/\\1/p" | tail -n 1
}

count_status() {
    local status="$1"
    grep -c "^${status}$" || true
}

find_nginx_log_line() {
    local probe_id="$1" attempt nginx_log_line

    for attempt in 1 2 3 4 5; do
        nginx_log_line=$(
            kubectl logs "${NGINX_DEPLOYMENT}" --tail="${NGINX_LOG_TAIL_LINES}" 2>/dev/null |
                grep "$probe_id" | tail -n 1 || true
        )
        if [[ -n "$nginx_log_line" ]]; then
            printf '%s\n' "$nginx_log_line"
            return 0
        fi
        sleep 2
    done

    return 1
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
    local pod_name="$1"

    kubectl delete pod "${pod_name}" -n "${PROBE_NAMESPACE}" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "${PROBE_NAMESPACE}" -f - >/dev/null <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
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

wait_for_pod_ready() {
    kubectl wait --for=condition=Ready "pod/$1" -n "${PROBE_NAMESPACE}" --timeout=120s >/dev/null
}

get_pod_ip() {
    kubectl get pod "$1" -n "${PROBE_NAMESPACE}" -o jsonpath='{.status.podIP}'
}

pod_api_status() {
    local pod_name="$1" session_id="$2" forged_xff="$3" probe_id="$4"
    kubectl exec -n "${PROBE_NAMESPACE}" "${pod_name}" -- sh -lc \
        "curl -sk -o /dev/null -w '%{http_code}\n' \
            --resolve app.budgetanalyzer.localhost:443:${INGRESS_CLUSTER_IP} \
            -A '${probe_id}' \
            -H 'X-Forwarded-For: ${forged_xff}' \
            --cookie 'BA_SESSION=${session_id}' \
            'https://app.budgetanalyzer.localhost/api/v1/transactions?${probe_id}'"
}

pod_api_burst() {
    local pod_name="$1" session_id="$2" forged_xff="$3" probe_prefix="$4" count="$5"
    kubectl exec -n "${PROBE_NAMESPACE}" "${pod_name}" -- sh -lc \
        "for i in \$(seq 1 ${count}); do
            curl -sk -o /dev/null -w '%{http_code}\n' \
                --resolve app.budgetanalyzer.localhost:443:${INGRESS_CLUSTER_IP} \
                -A '${probe_prefix}-'\$i \
                -H 'X-Forwarded-For: ${forged_xff}' \
                --cookie 'BA_SESSION=${session_id}' \
                'https://app.budgetanalyzer.localhost/api/v1/transactions?${probe_prefix}-'\$i
        done"
}

verify_log_identity() {
    local description="$1" probe_id="$2" expected_client_ip="$3" forged_xff="$4"
    local nginx_log_line derived_client_ip proxy_addr

    nginx_log_line=$(find_nginx_log_line "$probe_id" || true)
    if [[ -z "$nginx_log_line" ]]; then
        fail "NGINX log does not contain the probe request for ${description}"
        return
    fi

    pass "NGINX logged the probe request for ${description}"

    derived_client_ip=$(extract_log_field "remote_addr" "$nginx_log_line")
    proxy_addr=$(extract_log_field "proxy_addr" "$nginx_log_line")

    if [[ "$derived_client_ip" == "$expected_client_ip" ]]; then
        pass "Derived client IP for ${description} matches the actual probe pod IP ${expected_client_ip}"
    else
        fail "Derived client IP for ${description} was ${derived_client_ip:-<missing>} (expected ${expected_client_ip})"
    fi

    if [[ "$derived_client_ip" != "$forged_xff" ]]; then
        pass "Derived client IP for ${description} ignores the forged external X-Forwarded-For value"
    else
        fail "Derived client IP for ${description} incorrectly trusted the forged X-Forwarded-For value ${forged_xff}"
    fi

    if [[ "$proxy_addr" =~ ${EXPECTED_PROXY_REGEX} ]]; then
        pass "Trusted proxy hop for ${description} stays on the pod-local loopback path (${proxy_addr})"
    else
        fail "Trusted proxy hop for ${description} was ${proxy_addr:-<missing>} (expected loopback)"
    fi

    if printf '%s\n' "$nginx_log_line" | grep -Eq "xff=\"${forged_xff}, ?${expected_client_ip}\""; then
        pass "Forwarded-header chain for ${description} preserves the caller value and ingress-appended downstream hop"
    else
        fail "Forwarded-header chain for ${description} did not show ${forged_xff},${expected_client_ip}"
    fi
}

main() {
    echo "==============================================================="
    echo "  Phase 6 Session 7 API Rate-Limit Identity Verifier"
    echo "==============================================================="
    echo

    require_host_command kubectl
    require_cluster_access

    INGRESS_CLUSTER_IP=$(kubectl get svc "${INGRESS_SERVICE_NAME}" -n "${INGRESS_NAMESPACE}" -o jsonpath='{.spec.clusterIP}')
    if [[ -z "${INGRESS_CLUSTER_IP}" ]]; then
        printf 'ERROR: could not determine ClusterIP for %s/%s\n' "${INGRESS_NAMESPACE}" "${INGRESS_SERVICE_NAME}" >&2
        exit 1
    fi

    section "Probe Setup"

    create_probe_policy
    create_probe_pod "${PROBE_POD_A}"
    create_probe_pod "${PROBE_POD_B}"
    wait_for_pod_ready "${PROBE_POD_A}"
    wait_for_pod_ready "${PROBE_POD_B}"

    local probe_ip_a probe_ip_b
    probe_ip_a=$(get_pod_ip "${PROBE_POD_A}")
    probe_ip_b=$(get_pod_ip "${PROBE_POD_B}")

    if [[ -n "${probe_ip_a}" && -n "${probe_ip_b}" ]]; then
        pass "Probe pods received IPs ${probe_ip_a} and ${probe_ip_b}"
    else
        fail "Could not determine probe pod IPs"
    fi

    if [[ "${probe_ip_a}" != "${probe_ip_b}" ]]; then
        pass "Probe pods have distinct downstream client IPs"
    else
        fail "Probe pods did not get distinct downstream client IPs"
    fi

    section "Trusted Client Identity"

    local identity_session identity_probe_a identity_probe_b identity_status_a identity_status_b
    identity_session="phase6-session7-identity-$(date +%s)"
    "${SCRIPT_DIR}/seed-ext-authz-session.sh" "${identity_session}" >/dev/null

    identity_probe_a="${identity_session}-a"
    identity_status_a=$(pod_api_status "${PROBE_POD_A}" "${identity_session}" "${FORGED_XFF_PRIMARY}" "${identity_probe_a}")
    if [[ "${identity_status_a}" == "200" ]]; then
        pass "Probe A request returned 200"
    else
        fail "Probe A request returned ${identity_status_a:-000} (expected 200)"
    fi

    identity_probe_b="${identity_session}-b"
    identity_status_b=$(pod_api_status "${PROBE_POD_B}" "${identity_session}" "${FORGED_XFF_SECONDARY}" "${identity_probe_b}")
    if [[ "${identity_status_b}" == "200" ]]; then
        pass "Probe B request returned 200"
    else
        fail "Probe B request returned ${identity_status_b:-000} (expected 200)"
    fi

    verify_log_identity "probe A" "${identity_probe_a}" "${probe_ip_a}" "${FORGED_XFF_PRIMARY}"
    verify_log_identity "probe B" "${identity_probe_b}" "${probe_ip_b}" "${FORGED_XFF_SECONDARY}"
    pass "Forged external X-Forwarded-For values do not control the derived client identity that feeds the API limiter"

    section "Rate-Limit Buckets"

    local rate_session burst_prefix burst_statuses burst_429s other_client_status
    rate_session="phase6-session7-rate-$(date +%s)"
    "${SCRIPT_DIR}/seed-ext-authz-session.sh" "${rate_session}" >/dev/null
    burst_prefix="${rate_session}-burst-a"
    burst_statuses=$(pod_api_burst "${PROBE_POD_A}" "${rate_session}" "${FORGED_XFF_PRIMARY}" "${burst_prefix}" "${API_BURST_REQUESTS}")
    burst_429s=$(printf '%s\n' "${burst_statuses}" | count_status 429)

    if [[ "${burst_429s}" -ge 1 ]]; then
        pass "Same real client exhausted a single API rate-limit bucket (saw ${burst_429s} HTTP 429 responses)"
    else
        fail "Burst traffic from one real client did not trigger any HTTP 429 responses"
    fi

    other_client_status=$(pod_api_status "${PROBE_POD_B}" "${rate_session}" "${FORGED_XFF_PRIMARY}" "${rate_session}-other-client")
    if [[ "${other_client_status}" == "200" ]]; then
        pass "A different real client gets a separate API rate-limit bucket through the same ingress path"
    else
        fail "A different real client returned ${other_client_status:-000} instead of HTTP 200"
    fi

    if [[ "${FAILED}" -eq 0 ]]; then
        echo
        echo "Phase 6 Session 7 verification succeeded (${PASSED} checks passed)."
    else
        echo
        echo "Phase 6 Session 7 verification FAILED (${FAILED} failed, ${PASSED} passed)." >&2
        exit 1
    fi
}

main "$@"
