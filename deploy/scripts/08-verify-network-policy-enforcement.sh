#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/lib/common.sh"

PHASE4_NETWORK_POLICY_PROBE_IMAGE="${PHASE4_NETWORK_POLICY_PROBE_IMAGE:-postgres:16-alpine@sha256:20edbde7749f822887a1a022ad526fde0a47d6b2be9a8364433605cf65099416}"
readonly PHASE4_NETWORK_POLICY_PROBE_IMAGE
CONNECT_TIMEOUT="${PHASE4_NETWORK_POLICY_CONNECT_TIMEOUT:-3}"
readonly CONNECT_TIMEOUT
DENY_TIMEOUT="${PHASE4_NETWORK_POLICY_DENY_TIMEOUT:-3}"
readonly DENY_TIMEOUT
ALLOW_ATTEMPTS="${PHASE4_NETWORK_POLICY_ALLOW_ATTEMPTS:-5}"
readonly ALLOW_ATTEMPTS
ALLOW_RETRY_DELAY="${PHASE4_NETWORK_POLICY_ALLOW_RETRY_DELAY:-1}"
readonly ALLOW_RETRY_DELAY
DENY_ATTEMPTS="${PHASE4_NETWORK_POLICY_DENY_ATTEMPTS:-3}"
readonly DENY_ATTEMPTS
DENY_RETRY_DELAY="${PHASE4_NETWORK_POLICY_DENY_RETRY_DELAY:-1}"
readonly DENY_RETRY_DELAY
PROBE_STABILIZATION_SECONDS="${PHASE4_NETWORK_POLICY_PROBE_STABILIZATION_SECONDS:-5}"
readonly PROBE_STABILIZATION_SECONDS

PROBE_ISTIO_INGRESS="phase4-np-ingress-probe"
readonly PROBE_ISTIO_INGRESS
PROBE_NGINX="phase4-np-nginx-probe"
readonly PROBE_NGINX
PROBE_SESSION="phase4-np-session-probe"
readonly PROBE_SESSION
PROBE_EXTAUTHZ="phase4-np-extauthz-probe"
readonly PROBE_EXTAUTHZ
PROBE_TXN="phase4-np-txn-probe"
readonly PROBE_TXN
PROBE_CURRENCY="phase4-np-currency-probe"
readonly PROBE_CURRENCY
PROBE_PERM="phase4-np-perm-probe"
readonly PROBE_PERM
PROBE_UNLABELED="phase4-np-unlabeled-probe"
readonly PROBE_UNLABELED

LISTENER_NGINX="phase4-np-nginx-listener"
readonly LISTENER_NGINX
LISTENER_EXTAUTHZ="phase4-np-extauthz-listener"
readonly LISTENER_EXTAUTHZ
LISTENER_SESSION="phase4-np-session-listener"
readonly LISTENER_SESSION
LISTENER_TXN="phase4-np-txn-listener"
readonly LISTENER_TXN
LISTENER_CURRENCY="phase4-np-currency-listener"
readonly LISTENER_CURRENCY
LISTENER_WEB="phase4-np-web-listener"
readonly LISTENER_WEB
LISTENER_PERMISSION="phase4-np-perm-listener"
readonly LISTENER_PERMISSION
LISTENER_REDIS="phase4-np-redis-listener"
readonly LISTENER_REDIS
LISTENER_POSTGRESQL="phase4-np-postgresql-listener"
readonly LISTENER_POSTGRESQL
LISTENER_RABBITMQ="phase4-np-rabbitmq-listener"
readonly LISTENER_RABBITMQ
LISTENER_GRAFANA="phase4-np-grafana-listener"
readonly LISTENER_GRAFANA

PASSED=0
FAILED=0
LAST_SUCCESS_ATTEMPT=0
LAST_FAILURE_ATTEMPTS=0
TEMP_PODS=()
ISTIOD_SERVICE_IP=""
ISTIO_EGRESS_SERVICE_IP=""

LISTENER_NGINX_IP=""
LISTENER_EXTAUTHZ_IP=""
LISTENER_SESSION_IP=""
LISTENER_TXN_IP=""
LISTENER_CURRENCY_IP=""
LISTENER_WEB_IP=""
LISTENER_PERMISSION_IP=""
LISTENER_REDIS_IP=""
LISTENER_POSTGRESQL_IP=""
LISTENER_RABBITMQ_IP=""
LISTENER_GRAFANA_IP=""

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/08-verify-network-policy-enforcement.sh

This verifier creates disposable probe and listener pods so the production ingress path can prove
the checked-in NetworkPolicy contract on the current k3s cluster before any
application or infrastructure workloads are deployed.

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
            phase4_die "unknown option: $1"
            ;;
    esac
done

pass() {
    printf '  [PASS] %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf '  [FAIL] %s\n' "$1" >&2
    FAILED=$((FAILED + 1))
}

section() {
    printf '\n=== %s ===\n' "$1"
}

cleanup() {
    set +e

    if (( ${#TEMP_PODS[@]} == 0 )); then
        return
    fi

    phase4_info "cleaning up temporary NetworkPolicy verifier pods"
    for pod_ref in "${TEMP_PODS[@]}"; do
        kubectl delete pod "${pod_ref#*/}" -n "${pod_ref%%/*}" \
            --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true
    done
}

trap cleanup EXIT

load_operator_context() {
    if [[ -f "${PHASE4_INSTANCE_ENV_FILE}" ]]; then
        phase4_load_instance_env
        return
    fi

    phase4_warn "instance config ${PHASE4_INSTANCE_ENV_FILE} not found; continuing with the current kubectl context"
    phase4_use_default_kubeconfig
}

require_namespace() {
    local namespace="$1"

    kubectl get namespace "${namespace}" >/dev/null 2>&1 || \
        phase4_die "required namespace not found: ${namespace}"
}

require_nonempty_value() {
    local description="$1"
    local value="$2"

    [[ -n "${value}" ]] || phase4_die "missing required value: ${description}"
}

require_network_policies() {
    local default_count
    local infrastructure_count
    local ingress_count
    local egress_count

    require_namespace default
    require_namespace infrastructure
    require_namespace monitoring
    require_namespace istio-system
    require_namespace istio-ingress
    require_namespace istio-egress

    default_count="$(kubectl get networkpolicy -n default --no-headers 2>/dev/null | wc -l)"
    infrastructure_count="$(kubectl get networkpolicy -n infrastructure --no-headers 2>/dev/null | wc -l)"
    ingress_count="$(kubectl get networkpolicy -n istio-ingress --no-headers 2>/dev/null | wc -l)"
    egress_count="$(kubectl get networkpolicy -n istio-egress --no-headers 2>/dev/null | wc -l)"

    [[ "${default_count}" -gt 0 ]] || phase4_die "no NetworkPolicy resources found in namespace default; run deploy/scripts/07-apply-network-policies.sh first"
    [[ "${infrastructure_count}" -gt 0 ]] || phase4_die "no NetworkPolicy resources found in namespace infrastructure; run deploy/scripts/07-apply-network-policies.sh first"
    [[ "${ingress_count}" -gt 0 ]] || phase4_die "no NetworkPolicy resources found in namespace istio-ingress; run deploy/scripts/07-apply-network-policies.sh first"
    [[ "${egress_count}" -gt 0 ]] || phase4_die "no NetworkPolicy resources found in namespace istio-egress; run deploy/scripts/07-apply-network-policies.sh first"

    phase4_info "found ${default_count} policies in default, ${infrastructure_count} in infrastructure, ${ingress_count} in istio-ingress, ${egress_count} in istio-egress"
}

require_live_istio_targets() {
    local istiod_ready
    local istio_egress_ready

    istiod_ready="$(kubectl get pod -n istio-system -l app=istiod -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)"
    [[ "${istiod_ready}" == "true" ]] || phase4_die "istiod is not ready in namespace istio-system; Chunk 3 must be complete before running this verifier"

    istio_egress_ready="$(kubectl get pod -n istio-egress -l app=istio-egress-gateway,istio=egress-gateway -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)"
    [[ "${istio_egress_ready}" == "true" ]] || phase4_die "istio-egress-gateway is not ready in namespace istio-egress; Chunk 3 must be complete before running this verifier"

    ISTIOD_SERVICE_IP="$(kubectl get service istiod -n istio-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
    require_nonempty_value "istiod service ClusterIP" "${ISTIOD_SERVICE_IP}"

    ISTIO_EGRESS_SERVICE_IP="$(kubectl get service istio-egress-gateway -n istio-egress -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
    require_nonempty_value "istio-egress-gateway service ClusterIP" "${ISTIO_EGRESS_SERVICE_IP}"
}

build_label_lines() {
    local label_lines=""
    local label

    for label in "$@"; do
        label_lines="${label_lines}    ${label%%=*}: \"${label#*=}\"
"
    done

    printf '%s' "${label_lines}"
}

create_probe() {
    local namespace="$1"
    local name="$2"
    local label_lines

    shift 2
    label_lines="$(build_label_lines "$@")"

    kubectl delete pod "${name}" -n "${namespace}" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "${namespace}" -f - >/dev/null <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  annotations:
    sidecar.istio.io/inject: "false"
  labels:
${label_lines}
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${PHASE4_NETWORK_POLICY_PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
MANIFEST

    TEMP_PODS+=("${namespace}/${name}")
}

create_listener() {
    local namespace="$1"
    local name="$2"
    local port="$3"
    local label_lines

    shift 3
    label_lines="$(build_label_lines "$@")"

    kubectl delete pod "${name}" -n "${namespace}" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "${namespace}" -f - >/dev/null <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  annotations:
    sidecar.istio.io/inject: "false"
  labels:
${label_lines}
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: listener
      image: ${PHASE4_NETWORK_POLICY_PROBE_IMAGE}
      command:
        - sh
        - -c
        - |
          exec nc -lk -p ${port} -e /bin/cat
      ports:
        - containerPort: ${port}
          protocol: TCP
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
MANIFEST

    TEMP_PODS+=("${namespace}/${name}")
}

wait_for_pod() {
    local namespace="$1"
    local pod_name="$2"

    kubectl wait --for=condition=Ready "pod/${pod_name}" -n "${namespace}" --timeout=60s >/dev/null
}

pod_ip() {
    local namespace="$1"
    local pod_name="$2"

    kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.podIP}'
}

test_tcp() {
    local namespace="$1"
    local pod_name="$2"
    local target_host="$3"
    local target_port="$4"
    local timeout="${5:-${CONNECT_TIMEOUT}}"

    kubectl exec -n "${namespace}" "${pod_name}" -- \
        sh -c "nc -w ${timeout} ${target_host} ${target_port} </dev/null >/dev/null 2>&1" >/dev/null 2>&1
}

test_dns() {
    local namespace="$1"
    local pod_name="$2"

    kubectl exec -n "${namespace}" "${pod_name}" -- \
        sh -c 'nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1' >/dev/null 2>&1
}

connect_eventually() {
    local namespace="$1"
    local pod_name="$2"
    local target_host="$3"
    local target_port="$4"
    local attempts="${5:-${ALLOW_ATTEMPTS}}"
    local delay="${6:-${ALLOW_RETRY_DELAY}}"
    local timeout="${7:-${CONNECT_TIMEOUT}}"
    local attempt

    LAST_SUCCESS_ATTEMPT=0
    LAST_FAILURE_ATTEMPTS=0

    for attempt in $(seq 1 "${attempts}"); do
        if test_tcp "${namespace}" "${pod_name}" "${target_host}" "${target_port}" "${timeout}"; then
            LAST_SUCCESS_ATTEMPT="${attempt}"
            return 0
        fi

        LAST_FAILURE_ATTEMPTS="${attempt}"
        if [[ "${attempt}" -lt "${attempts}" ]]; then
            sleep "${delay}"
        fi
    done

    return 1
}

assert_dns_success() {
    local description="$1"
    local namespace="$2"
    local pod_name="$3"

    if test_dns "${namespace}" "${pod_name}"; then
        pass "${description}"
        return
    fi

    fail "${description}"
}

assert_allow_eventually() {
    local description="$1"
    local namespace="$2"
    local pod_name="$3"
    local target_host="$4"
    local target_port="$5"

    if connect_eventually "${namespace}" "${pod_name}" "${target_host}" "${target_port}"; then
        if [[ "${LAST_SUCCESS_ATTEMPT}" -gt 1 ]]; then
            pass "${description} (attempt ${LAST_SUCCESS_ATTEMPT}/${ALLOW_ATTEMPTS})"
        else
            pass "${description}"
        fi
        return
    fi

    fail "${description} (failed ${LAST_FAILURE_ATTEMPTS}/${ALLOW_ATTEMPTS} attempts from ${namespace}/${pod_name} to ${target_host}:${target_port})"
}

assert_deny_consistently() {
    local description="$1"
    local namespace="$2"
    local pod_name="$3"
    local target_host="$4"
    local target_port="$5"
    local attempt

    for attempt in $(seq 1 "${DENY_ATTEMPTS}"); do
        if test_tcp "${namespace}" "${pod_name}" "${target_host}" "${target_port}" "${DENY_TIMEOUT}"; then
            fail "${description} (unexpected connection on attempt ${attempt}/${DENY_ATTEMPTS} from ${namespace}/${pod_name} to ${target_host}:${target_port})"
            return
        fi

        if [[ "${attempt}" -lt "${DENY_ATTEMPTS}" ]]; then
            sleep "${DENY_RETRY_DELAY}"
        fi
    done

    pass "${description}"
}

create_all_temp_pods() {
    phase4_info "creating disposable listener and probe pods"

    create_listener default "${LISTENER_NGINX}" 8080 "app=nginx-gateway"
    create_listener default "${LISTENER_EXTAUTHZ}" 9002 "app=ext-authz"
    create_listener default "${LISTENER_SESSION}" 8081 "app=session-gateway"
    create_listener default "${LISTENER_TXN}" 8082 "app=transaction-service"
    create_listener default "${LISTENER_CURRENCY}" 8084 "app=currency-service"
    create_listener default "${LISTENER_WEB}" 3000 "app=budget-analyzer-web"
    create_listener default "${LISTENER_PERMISSION}" 8086 "app=permission-service"
    create_listener infrastructure "${LISTENER_REDIS}" 6379 "app=redis"
    create_listener infrastructure "${LISTENER_POSTGRESQL}" 5432 "app=postgresql"
    create_listener infrastructure "${LISTENER_RABBITMQ}" 5671 "app=rabbitmq"
    create_listener monitoring "${LISTENER_GRAFANA}" 3000 "app.kubernetes.io/name=grafana"

    create_probe istio-ingress "${PROBE_ISTIO_INGRESS}" \
        "gateway.networking.k8s.io/gateway-name=istio-ingress-gateway"
    create_probe default "${PROBE_NGINX}" "app=nginx-gateway"
    create_probe default "${PROBE_SESSION}" "app=session-gateway"
    create_probe default "${PROBE_EXTAUTHZ}" "app=ext-authz"
    create_probe default "${PROBE_TXN}" "app=transaction-service"
    create_probe default "${PROBE_CURRENCY}" "app=currency-service"
    create_probe default "${PROBE_PERM}" "app=permission-service"
    create_probe default "${PROBE_UNLABELED}" "phase4-network-policy-verifier=unlabeled"

    wait_for_pod default "${LISTENER_NGINX}"
    wait_for_pod default "${LISTENER_EXTAUTHZ}"
    wait_for_pod default "${LISTENER_SESSION}"
    wait_for_pod default "${LISTENER_TXN}"
    wait_for_pod default "${LISTENER_CURRENCY}"
    wait_for_pod default "${LISTENER_WEB}"
    wait_for_pod default "${LISTENER_PERMISSION}"
    wait_for_pod infrastructure "${LISTENER_REDIS}"
    wait_for_pod infrastructure "${LISTENER_POSTGRESQL}"
    wait_for_pod infrastructure "${LISTENER_RABBITMQ}"
    wait_for_pod monitoring "${LISTENER_GRAFANA}"
    wait_for_pod istio-ingress "${PROBE_ISTIO_INGRESS}"
    wait_for_pod default "${PROBE_NGINX}"
    wait_for_pod default "${PROBE_SESSION}"
    wait_for_pod default "${PROBE_EXTAUTHZ}"
    wait_for_pod default "${PROBE_TXN}"
    wait_for_pod default "${PROBE_CURRENCY}"
    wait_for_pod default "${PROBE_PERM}"
    wait_for_pod default "${PROBE_UNLABELED}"

    phase4_info "waiting ${PROBE_STABILIZATION_SECONDS}s for probe networking to stabilize"
    sleep "${PROBE_STABILIZATION_SECONDS}"

    LISTENER_NGINX_IP="$(pod_ip default "${LISTENER_NGINX}")"
    LISTENER_EXTAUTHZ_IP="$(pod_ip default "${LISTENER_EXTAUTHZ}")"
    LISTENER_SESSION_IP="$(pod_ip default "${LISTENER_SESSION}")"
    LISTENER_TXN_IP="$(pod_ip default "${LISTENER_TXN}")"
    LISTENER_CURRENCY_IP="$(pod_ip default "${LISTENER_CURRENCY}")"
    LISTENER_WEB_IP="$(pod_ip default "${LISTENER_WEB}")"
    LISTENER_PERMISSION_IP="$(pod_ip default "${LISTENER_PERMISSION}")"
    LISTENER_REDIS_IP="$(pod_ip infrastructure "${LISTENER_REDIS}")"
    LISTENER_POSTGRESQL_IP="$(pod_ip infrastructure "${LISTENER_POSTGRESQL}")"
    LISTENER_RABBITMQ_IP="$(pod_ip infrastructure "${LISTENER_RABBITMQ}")"
    LISTENER_GRAFANA_IP="$(pod_ip monitoring "${LISTENER_GRAFANA}")"
}

main() {
    printf '==============================================\n'
    printf '  NetworkPolicy Enforcement Verifier\n'
    printf '==============================================\n\n'

    load_operator_context
    phase4_require_commands kubectl
    phase4_require_cluster_access
    require_network_policies
    require_live_istio_targets
    create_all_temp_pods

    section "Positive: DNS Baseline"
    assert_dns_success "unlabeled default probe -> kube-dns" default "${PROBE_UNLABELED}"

    section "Positive: Istio Ingress Egress"
    assert_allow_eventually "istio-ingress probe -> nginx listener:8080" \
        istio-ingress "${PROBE_ISTIO_INGRESS}" "${LISTENER_NGINX_IP}" 8080
    assert_allow_eventually "istio-ingress probe -> ext-authz listener:9002" \
        istio-ingress "${PROBE_ISTIO_INGRESS}" "${LISTENER_EXTAUTHZ_IP}" 9002
    assert_allow_eventually "istio-ingress probe -> session-gateway listener:8081" \
        istio-ingress "${PROBE_ISTIO_INGRESS}" "${LISTENER_SESSION_IP}" 8081
    assert_allow_eventually "istio-ingress probe -> grafana listener:3000" \
        istio-ingress "${PROBE_ISTIO_INGRESS}" "${LISTENER_GRAFANA_IP}" 3000

    section "Positive: Default Namespace East-West"
    assert_allow_eventually "nginx probe -> transaction-service listener:8082" \
        default "${PROBE_NGINX}" "${LISTENER_TXN_IP}" 8082
    assert_allow_eventually "nginx probe -> currency-service listener:8084" \
        default "${PROBE_NGINX}" "${LISTENER_CURRENCY_IP}" 8084
    assert_allow_eventually "nginx probe -> budget-analyzer-web listener:3000" \
        default "${PROBE_NGINX}" "${LISTENER_WEB_IP}" 3000
    assert_allow_eventually "nginx probe -> permission-service listener:8086" \
        default "${PROBE_NGINX}" "${LISTENER_PERMISSION_IP}" 8086
    assert_allow_eventually "session-gateway probe -> permission-service listener:8086" \
        default "${PROBE_SESSION}" "${LISTENER_PERMISSION_IP}" 8086
    assert_allow_eventually "permission-service probe -> session-gateway listener:8081" \
        default "${PROBE_PERM}" "${LISTENER_SESSION_IP}" 8081

    section "Positive: Application To Infrastructure"
    assert_allow_eventually "session-gateway probe -> redis listener:6379" \
        default "${PROBE_SESSION}" "${LISTENER_REDIS_IP}" 6379
    assert_allow_eventually "ext-authz probe -> redis listener:6379" \
        default "${PROBE_EXTAUTHZ}" "${LISTENER_REDIS_IP}" 6379
    assert_allow_eventually "transaction-service probe -> postgresql listener:5432" \
        default "${PROBE_TXN}" "${LISTENER_POSTGRESQL_IP}" 5432
    assert_allow_eventually "currency-service probe -> postgresql listener:5432" \
        default "${PROBE_CURRENCY}" "${LISTENER_POSTGRESQL_IP}" 5432
    assert_allow_eventually "currency-service probe -> rabbitmq listener:5671" \
        default "${PROBE_CURRENCY}" "${LISTENER_RABBITMQ_IP}" 5671
    assert_allow_eventually "currency-service probe -> redis listener:6379" \
        default "${PROBE_CURRENCY}" "${LISTENER_REDIS_IP}" 6379
    assert_allow_eventually "permission-service probe -> postgresql listener:5432" \
        default "${PROBE_PERM}" "${LISTENER_POSTGRESQL_IP}" 5432

    section "Positive: Live Istio Targets"
    assert_allow_eventually "nginx probe -> istiod:15012" \
        default "${PROBE_NGINX}" "${ISTIOD_SERVICE_IP}" 15012
    assert_allow_eventually "istio-ingress probe -> istiod:15012" \
        istio-ingress "${PROBE_ISTIO_INGRESS}" "${ISTIOD_SERVICE_IP}" 15012
    assert_allow_eventually "session-gateway probe -> istio-egress-gateway:443" \
        default "${PROBE_SESSION}" "${ISTIO_EGRESS_SERVICE_IP}" 443
    assert_allow_eventually "currency-service probe -> istio-egress-gateway:443" \
        default "${PROBE_CURRENCY}" "${ISTIO_EGRESS_SERVICE_IP}" 443

    section "Negative: Unlabeled Isolation"
    assert_deny_consistently "unlabeled default probe -> nginx listener:8080" \
        default "${PROBE_UNLABELED}" "${LISTENER_NGINX_IP}" 8080
    assert_deny_consistently "unlabeled default probe -> session-gateway listener:8081" \
        default "${PROBE_UNLABELED}" "${LISTENER_SESSION_IP}" 8081
    assert_deny_consistently "unlabeled default probe -> ext-authz listener:9002" \
        default "${PROBE_UNLABELED}" "${LISTENER_EXTAUTHZ_IP}" 9002
    assert_deny_consistently "unlabeled default probe -> transaction-service listener:8082" \
        default "${PROBE_UNLABELED}" "${LISTENER_TXN_IP}" 8082
    assert_deny_consistently "unlabeled default probe -> currency-service listener:8084" \
        default "${PROBE_UNLABELED}" "${LISTENER_CURRENCY_IP}" 8084
    assert_deny_consistently "unlabeled default probe -> permission-service listener:8086" \
        default "${PROBE_UNLABELED}" "${LISTENER_PERMISSION_IP}" 8086
    assert_deny_consistently "unlabeled default probe -> budget-analyzer-web listener:3000" \
        default "${PROBE_UNLABELED}" "${LISTENER_WEB_IP}" 3000
    assert_deny_consistently "unlabeled default probe -> redis listener:6379" \
        default "${PROBE_UNLABELED}" "${LISTENER_REDIS_IP}" 6379
    assert_deny_consistently "unlabeled default probe -> postgresql listener:5432" \
        default "${PROBE_UNLABELED}" "${LISTENER_POSTGRESQL_IP}" 5432
    assert_deny_consistently "unlabeled default probe -> rabbitmq listener:5671" \
        default "${PROBE_UNLABELED}" "${LISTENER_RABBITMQ_IP}" 5671
    assert_deny_consistently "unlabeled default probe -> istio-egress-gateway:443" \
        default "${PROBE_UNLABELED}" "${ISTIO_EGRESS_SERVICE_IP}" 443

    section "Negative: Cross-Identity Restrictions"
    assert_deny_consistently "session-gateway probe -> nginx listener:8080" \
        default "${PROBE_SESSION}" "${LISTENER_NGINX_IP}" 8080
    assert_deny_consistently "session-gateway probe -> transaction-service listener:8082" \
        default "${PROBE_SESSION}" "${LISTENER_TXN_IP}" 8082
    assert_deny_consistently "session-gateway probe -> currency-service listener:8084" \
        default "${PROBE_SESSION}" "${LISTENER_CURRENCY_IP}" 8084
    assert_deny_consistently "transaction-service probe -> redis listener:6379" \
        default "${PROBE_TXN}" "${LISTENER_REDIS_IP}" 6379
    assert_deny_consistently "transaction-service probe -> rabbitmq listener:5671" \
        default "${PROBE_TXN}" "${LISTENER_RABBITMQ_IP}" 5671
    assert_deny_consistently "ext-authz probe -> postgresql listener:5432" \
        default "${PROBE_EXTAUTHZ}" "${LISTENER_POSTGRESQL_IP}" 5432
    assert_deny_consistently "ext-authz probe -> rabbitmq listener:5671" \
        default "${PROBE_EXTAUTHZ}" "${LISTENER_RABBITMQ_IP}" 5671
    assert_deny_consistently "istio-ingress probe -> permission-service listener:8086" \
        istio-ingress "${PROBE_ISTIO_INGRESS}" "${LISTENER_PERMISSION_IP}" 8086
    assert_deny_consistently "ext-authz probe -> istio-egress-gateway:443" \
        default "${PROBE_EXTAUTHZ}" "${ISTIO_EGRESS_SERVICE_IP}" 443
    assert_deny_consistently "transaction-service probe -> istio-egress-gateway:443" \
        default "${PROBE_TXN}" "${ISTIO_EGRESS_SERVICE_IP}" 443
    assert_deny_consistently "permission-service probe -> istio-egress-gateway:443" \
        default "${PROBE_PERM}" "${ISTIO_EGRESS_SERVICE_IP}" 443

    printf '\n==============================================\n'
    if [[ "${FAILED}" -eq 0 ]]; then
        printf '  %s passed (out of %s)\n' "${PASSED}" "$((PASSED + FAILED))"
    else
        printf '  %s passed, %s failed (out of %s)\n' "${PASSED}" "${FAILED}" "$((PASSED + FAILED))"
    fi
    printf '==============================================\n'

    [[ "${FAILED}" -eq 0 ]]
}

main "$@"
