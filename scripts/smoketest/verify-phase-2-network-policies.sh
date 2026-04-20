#!/bin/bash

# verify-phase-2-network-policies.sh
#
# Runtime verification for NetworkPolicy enforcement.
# Proves that NetworkPolicy allowlists are enforced in the current Istio
# ingress/egress topology by testing both authorized and unauthorized
# connectivity paths using disposable probe pods.
#
# Each probe pod uses sidecar.istio.io/inject: "false" so Istio does not
# contaminate results. Probes carry the same pod labels as the workload they
# impersonate, which is what NetworkPolicy selectors match on.
#
# Prerequisites: Tilt running with all services and network policies applied.
#
# Usage:
#   ./scripts/smoketest/verify-phase-2-network-policies.sh

set -euo pipefail

PROBE_IMAGE="postgres:16-alpine@sha256:20edbde7749f822887a1a022ad526fde0a47d6b2be9a8364433605cf65099416"
CONNECT_TIMEOUT="${PHASE2_CONNECT_TIMEOUT:-3}"
DENY_TIMEOUT="${PHASE2_DENY_TIMEOUT:-3}"
ALLOW_ATTEMPTS="${PHASE2_ALLOW_ATTEMPTS:-5}"
ALLOW_RETRY_DELAY="${PHASE2_ALLOW_RETRY_DELAY:-1}"
DENY_ATTEMPTS="${PHASE2_DENY_ATTEMPTS:-3}"
DENY_RETRY_DELAY="${PHASE2_DENY_RETRY_DELAY:-1}"
PROBE_STABILIZATION_SECONDS="${PHASE2_PROBE_STABILIZATION_SECONDS:-5}"

PASSED=0
FAILED=0
TEMP_PODS=()
TEMP_SERVICES=()
LAST_SUCCESS_ATTEMPT=0
LAST_FAILURE_ATTEMPTS=0
KUBERNETES_SERVICE_IP=""

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-phase-2-network-policies.sh

Options:
  -h, --help                    Show this help text.
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
    echo ""
    echo "Cleaning up probe resources..."
    for svc_ref in "${TEMP_SERVICES[@]:-}"; do
        kubectl delete service "${svc_ref#*/}" -n "${svc_ref%%/*}" \
            --ignore-not-found >/dev/null 2>&1 || true
    done
    for pod_ref in "${TEMP_PODS[@]:-}"; do
        kubectl delete pod "${pod_ref#*/}" -n "${pod_ref%%/*}" \
            --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true
    done
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

require_host_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

current_context() {
    kubectl config current-context 2>/dev/null || printf 'unknown'
}

require_cluster_access() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes cluster from current kubectl context (%s)\n' "$(current_context)" >&2
        exit 1
    fi
}

require_namespace() {
    if ! kubectl get namespace "$1" >/dev/null 2>&1; then
        printf 'ERROR: namespace %s not found in current kubectl context (%s)\n' "$1" "$(current_context)" >&2
        exit 1
    fi
}

require_network_policies() {
    local default_count infra_count ingress_count egress_count monitoring_count
    require_namespace default
    require_namespace infrastructure
    require_namespace monitoring
    require_namespace istio-ingress
    require_namespace istio-egress

    default_count=$(kubectl get networkpolicy -n default --no-headers 2>/dev/null | wc -l)
    infra_count=$(kubectl get networkpolicy -n infrastructure --no-headers 2>/dev/null | wc -l)
    ingress_count=$(kubectl get networkpolicy -n istio-ingress --no-headers 2>/dev/null | wc -l)
    egress_count=$(kubectl get networkpolicy -n istio-egress --no-headers 2>/dev/null | wc -l)
    monitoring_count=$(kubectl get networkpolicy -n monitoring --no-headers 2>/dev/null | wc -l)

    if [[ "$default_count" -eq 0 ]]; then
        printf 'ERROR: No network policies in default namespace (context: %s).\n' "$(current_context)" >&2
        printf '       Run Tilt until the network policy resources reconcile, or trigger network-policies-core explicitly.\n' >&2
        exit 1
    fi
    if [[ "$infra_count" -eq 0 ]]; then
        printf 'ERROR: No network policies in infrastructure namespace (context: %s).\n' "$(current_context)" >&2
        printf '       Run Tilt until the network policy resources reconcile, or trigger network-policies-core explicitly.\n' >&2
        exit 1
    fi
    if [[ "$ingress_count" -eq 0 ]]; then
        printf 'ERROR: No network policies in istio-ingress namespace (context: %s).\n' "$(current_context)" >&2
        printf '       Run Tilt until the ingress network policies reconcile, or trigger istio-ingress-network-policies explicitly.\n' >&2
        exit 1
    fi
    if [[ "$egress_count" -eq 0 ]]; then
        printf 'ERROR: No network policies in istio-egress namespace (context: %s).\n' "$(current_context)" >&2
        printf '       Run Tilt until the egress network policies reconcile, or trigger istio-egress-network-policies explicitly.\n' >&2
        exit 1
    fi
    if [[ "$monitoring_count" -eq 0 ]]; then
        printf 'ERROR: No network policies in monitoring namespace (context: %s).\n' "$(current_context)" >&2
        printf '       Run Tilt until the monitoring network policies reconcile, or trigger network-policies-core explicitly.\n' >&2
        exit 1
    fi

    printf '  Found %d policies in default, %d in infrastructure, %d in istio-ingress, %d in istio-egress, %d in monitoring\n' \
        "$default_count" "$infra_count" "$ingress_count" "$egress_count" "$monitoring_count"
}

# Create a disposable probe pod.
# Args: namespace pod-name label1=val1 [label2=val2 ...]
create_probe() {
    local ns="$1" name="$2"
    shift 2

    local label_lines=""
    for lbl in "$@"; do
        label_lines="${label_lines}    ${lbl%%=*}: \"${lbl#*=}\"
"
    done

    kubectl delete pod "$name" -n "$ns" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "$ns" -f - >/dev/null 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  annotations:
    sidecar.istio.io/inject: "false"
  labels:
${label_lines}spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${PROBE_IMAGE}
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

    TEMP_PODS+=("${ns}/${name}")
}

create_listener() {
    local ns="$1" name="$2" port="$3"
    shift 3

    local label_lines=""
    local lbl
    for lbl in "$@"; do
        label_lines="${label_lines}    ${lbl%%=*}: \"${lbl#*=}\"
"
    done
    label_lines="${label_lines}    budgetanalyzer.io/network-policy-listener: \"${name}\"
"

    kubectl delete pod "$name" -n "$ns" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "$ns" -f - >/dev/null 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  annotations:
    sidecar.istio.io/inject: "false"
  labels:
${label_lines}spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: listener
      image: ${PROBE_IMAGE}
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

    TEMP_PODS+=("${ns}/${name}")
}

create_service() {
    local ns="$1" name="$2" port="$3"

    kubectl delete service "$name" -n "$ns" \
        --ignore-not-found >/dev/null 2>&1 || true

    kubectl apply -n "$ns" -f - >/dev/null 2>&1 <<MANIFEST
apiVersion: v1
kind: Service
metadata:
  name: ${name}
spec:
  selector:
    budgetanalyzer.io/network-policy-listener: "${name}"
  ports:
    - name: tcp-${port}
      port: ${port}
      targetPort: ${port}
      protocol: TCP
MANIFEST

    TEMP_SERVICES+=("${ns}/${name}")
}

# Test raw TCP connectivity from a probe pod.
# Returns 0 if the connection succeeds, 1 otherwise.
test_tcp() {
    local ns="$1" pod="$2" target="$3" port="$4" timeout="${5:-$CONNECT_TIMEOUT}"
    kubectl exec -n "$ns" "$pod" -- \
        sh -c "nc -w ${timeout} ${target} ${port} </dev/null >/dev/null 2>&1" 2>/dev/null
}

warm_probe_dns() {
    local ns="$1" pod="$2"
    kubectl exec -n "$ns" "$pod" -- \
        sh -c 'nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 || true' \
        >/dev/null 2>&1 || true
}

service_fqdn() {
    local ns="$1" name="$2"
    printf '%s.%s.svc.cluster.local' "$name" "$ns"
}

connect_eventually() {
    local ns="$1" pod="$2" target="$3" port="$4"
    local attempts="${5:-$ALLOW_ATTEMPTS}" delay="${6:-$ALLOW_RETRY_DELAY}"
    local timeout="${7:-$CONNECT_TIMEOUT}"
    local attempt

    LAST_SUCCESS_ATTEMPT=0
    LAST_FAILURE_ATTEMPTS=0

    for attempt in $(seq 1 "$attempts"); do
        if test_tcp "$ns" "$pod" "$target" "$port" "$timeout"; then
            LAST_SUCCESS_ATTEMPT="$attempt"
            return 0
        fi
        LAST_FAILURE_ATTEMPTS="$attempt"
        if [[ "$attempt" -lt "$attempts" ]]; then
            sleep "$delay"
        fi
    done

    return 1
}

assert_allow_eventually() {
    local desc="$1" ns="$2" pod="$3" target="$4" port="$5"

    if connect_eventually "$ns" "$pod" "$target" "$port"; then
        if [[ "$LAST_SUCCESS_ATTEMPT" -gt 1 ]]; then
            pass "$desc (attempt ${LAST_SUCCESS_ATTEMPT}/${ALLOW_ATTEMPTS})"
        else
            pass "$desc"
        fi
    else
        fail "$desc (failed ${LAST_FAILURE_ATTEMPTS}/${ALLOW_ATTEMPTS} attempts from ${ns}/${pod} to ${target}:${port})"
    fi
}

assert_deny_consistently() {
    local desc="$1" ns="$2" pod="$3" target="$4" port="$5"
    local attempt

    for attempt in $(seq 1 "$DENY_ATTEMPTS"); do
        if test_tcp "$ns" "$pod" "$target" "$port" "$DENY_TIMEOUT"; then
            fail "$desc (unexpected connection on attempt ${attempt}/${DENY_ATTEMPTS} from ${ns}/${pod} to ${target}:${port})"
            return
        fi
        if [[ "$attempt" -lt "$DENY_ATTEMPTS" ]]; then
            sleep "$DENY_RETRY_DELAY"
        fi
    done

    pass "$desc"
}

# ---------------------------------------------------------------------------
# Probe pods
# ---------------------------------------------------------------------------

PROBE_ISTIO_INGRESS="np2-istio-ingress"
PROBE_NGINX="np2-nginx"
PROBE_SESSION="np2-session"
PROBE_EXTAUTHZ="np2-extauthz"
PROBE_TXN="np2-txn"
PROBE_CURRENCY="np2-currency"
PROBE_PERM="np2-perm"
PROBE_UNLABELED="np2-unlabeled"
PROBE_ISTIO_EGRESS="np2-istio-egress"
PROBE_MONITORING_GRAFANA="np2-monitoring-grafana"
PROBE_MONITORING_PROMETHEUS="np2-monitoring-prometheus"
PROBE_MONITORING_KIALI="np2-monitoring-kiali"
PROBE_MONITORING_UNLABELED="np2-monitoring-unlabeled"

LISTENER_GRAFANA="np2-grafana-listener"
LISTENER_PROMETHEUS="np2-prometheus-listener"
LISTENER_KUBE_STATE_METRICS="np2-kube-state-metrics-listener"
LISTENER_PROMETHEUS_OPERATOR="np2-prometheus-operator-listener"
LISTENER_JAEGER_QUERY_GRPC="np2-jaeger-query-grpc-listener"
LISTENER_JAEGER_QUERY_HTTP="np2-jaeger-query-http-listener"
LISTENER_JAEGER_COLLECTOR="np2-jaeger-collector-listener"
LISTENER_SPRING_BOOT_8081="np2-spring-boot-8081"
LISTENER_SPRING_BOOT_8082="np2-spring-boot-8082"
LISTENER_SPRING_BOOT_8084="np2-spring-boot-8084"
LISTENER_SPRING_BOOT_8086="np2-spring-boot-8086"

create_all_probes() {
    echo "Creating probe pods..."

    create_listener monitoring "$LISTENER_GRAFANA" 3000 \
        "app.kubernetes.io/name=grafana" \
        "app.kubernetes.io/instance=prometheus-stack"
    create_listener monitoring "$LISTENER_PROMETHEUS" 9090 \
        "app.kubernetes.io/name=prometheus" \
        "operator.prometheus.io/name=prometheus-stack-kube-prom-prometheus"
    create_listener monitoring "$LISTENER_KUBE_STATE_METRICS" 8080 \
        "app.kubernetes.io/name=kube-state-metrics" \
        "app.kubernetes.io/instance=prometheus-stack"
    create_listener monitoring "$LISTENER_PROMETHEUS_OPERATOR" 8080 \
        "app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator" \
        "app.kubernetes.io/instance=prometheus-stack"
    create_listener monitoring "$LISTENER_JAEGER_QUERY_GRPC" 16685 "app.kubernetes.io/name=jaeger"
    create_listener monitoring "$LISTENER_JAEGER_QUERY_HTTP" 16686 "app.kubernetes.io/name=jaeger"
    create_listener monitoring "$LISTENER_JAEGER_COLLECTOR" 4317 "app.kubernetes.io/name=jaeger"
    create_listener default "$LISTENER_SPRING_BOOT_8081" 8081 "app.kubernetes.io/framework=spring-boot"
    create_listener default "$LISTENER_SPRING_BOOT_8082" 8082 "app.kubernetes.io/framework=spring-boot"
    create_listener default "$LISTENER_SPRING_BOOT_8084" 8084 "app.kubernetes.io/framework=spring-boot"
    create_listener default "$LISTENER_SPRING_BOOT_8086" 8086 "app.kubernetes.io/framework=spring-boot"

    create_service monitoring "$LISTENER_GRAFANA" 3000
    create_service monitoring "$LISTENER_PROMETHEUS" 9090
    create_service monitoring "$LISTENER_KUBE_STATE_METRICS" 8080
    create_service monitoring "$LISTENER_PROMETHEUS_OPERATOR" 8080
    create_service monitoring "$LISTENER_JAEGER_QUERY_GRPC" 16685
    create_service monitoring "$LISTENER_JAEGER_QUERY_HTTP" 16686
    create_service monitoring "$LISTENER_JAEGER_COLLECTOR" 4317
    create_service default "$LISTENER_SPRING_BOOT_8081" 8081
    create_service default "$LISTENER_SPRING_BOOT_8082" 8082
    create_service default "$LISTENER_SPRING_BOOT_8084" 8084
    create_service default "$LISTENER_SPRING_BOOT_8086" 8086

    # Istio ingress gateway probe in istio-ingress
    create_probe istio-ingress "$PROBE_ISTIO_INGRESS" \
        "gateway.networking.k8s.io/gateway-name=istio-ingress-gateway"
    create_probe istio-egress "$PROBE_ISTIO_EGRESS" "istio=egress-gateway"

    # Default namespace probes impersonating each workload
    create_probe default "$PROBE_NGINX"     "app=nginx-gateway" "security.istio.io/tlsMode=istio"
    create_probe default "$PROBE_SESSION"   "app=session-gateway" "security.istio.io/tlsMode=istio"
    create_probe default "$PROBE_EXTAUTHZ"  "app=ext-authz" "security.istio.io/tlsMode=istio"
    create_probe default "$PROBE_TXN"       "app=transaction-service" "security.istio.io/tlsMode=istio"
    create_probe default "$PROBE_CURRENCY"  "app=currency-service" "security.istio.io/tlsMode=istio"
    create_probe default "$PROBE_PERM"      "app=permission-service" "security.istio.io/tlsMode=istio"

    # Unlabeled probe: no app label, only matches podSelector:{} policies (DNS)
    create_probe default "$PROBE_UNLABELED" "np2-role=probe"
    create_probe monitoring "$PROBE_MONITORING_GRAFANA" \
        "app.kubernetes.io/name=grafana" \
        "app.kubernetes.io/instance=prometheus-stack"
    create_probe monitoring "$PROBE_MONITORING_PROMETHEUS" \
        "app.kubernetes.io/name=prometheus" \
        "operator.prometheus.io/name=prometheus-stack-kube-prom-prometheus" \
        "security.istio.io/tlsMode=istio"
    create_probe monitoring "$PROBE_MONITORING_KIALI" "app.kubernetes.io/name=kiali"
    create_probe monitoring "$PROBE_MONITORING_UNLABELED" "np2-role=monitoring-unlabeled"

    # Wait for all probes to be ready
    kubectl wait --for=condition=Ready \
        "pod/${PROBE_ISTIO_INGRESS}" -n istio-ingress --timeout=60s >/dev/null 2>&1
    kubectl wait --for=condition=Ready \
        "pod/${PROBE_ISTIO_EGRESS}" -n istio-egress --timeout=60s >/dev/null 2>&1
    kubectl wait --for=condition=Ready \
        "pod/${PROBE_NGINX}" \
        "pod/${PROBE_SESSION}" \
        "pod/${PROBE_EXTAUTHZ}" \
        "pod/${PROBE_TXN}" \
        "pod/${PROBE_CURRENCY}" \
        "pod/${PROBE_PERM}" \
        "pod/${PROBE_UNLABELED}" \
        "pod/${LISTENER_SPRING_BOOT_8081}" \
        "pod/${LISTENER_SPRING_BOOT_8082}" \
        "pod/${LISTENER_SPRING_BOOT_8084}" \
        "pod/${LISTENER_SPRING_BOOT_8086}" \
        -n default --timeout=60s >/dev/null 2>&1
    kubectl wait --for=condition=Ready \
        "pod/${PROBE_MONITORING_GRAFANA}" \
        "pod/${PROBE_MONITORING_PROMETHEUS}" \
        "pod/${PROBE_MONITORING_KIALI}" \
        "pod/${PROBE_MONITORING_UNLABELED}" \
        "pod/${LISTENER_GRAFANA}" \
        "pod/${LISTENER_PROMETHEUS}" \
        "pod/${LISTENER_KUBE_STATE_METRICS}" \
        "pod/${LISTENER_PROMETHEUS_OPERATOR}" \
        "pod/${LISTENER_JAEGER_QUERY_GRPC}" \
        "pod/${LISTENER_JAEGER_QUERY_HTTP}" \
        "pod/${LISTENER_JAEGER_COLLECTOR}" \
        -n monitoring --timeout=60s >/dev/null 2>&1

    echo "  All probe pods ready"
    echo "  Waiting ${PROBE_STABILIZATION_SECONDS}s for probe DNS/network stabilization..."
    sleep "$PROBE_STABILIZATION_SECONDS"

    warm_probe_dns istio-ingress "$PROBE_ISTIO_INGRESS"
    warm_probe_dns default "$PROBE_NGINX"
    warm_probe_dns default "$PROBE_SESSION"
    warm_probe_dns default "$PROBE_EXTAUTHZ"
    warm_probe_dns default "$PROBE_TXN"
    warm_probe_dns default "$PROBE_CURRENCY"
    warm_probe_dns default "$PROBE_PERM"
    warm_probe_dns default "$PROBE_UNLABELED"
    warm_probe_dns monitoring "$PROBE_MONITORING_GRAFANA"
    warm_probe_dns monitoring "$PROBE_MONITORING_PROMETHEUS"
    warm_probe_dns monitoring "$PROBE_MONITORING_KIALI"
    warm_probe_dns monitoring "$PROBE_MONITORING_UNLABELED"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo "=============================================="
    echo "  Network Policy Verifier"
    echo "=============================================="
    echo

    require_host_command kubectl
    require_cluster_access
    require_network_policies
    KUBERNETES_SERVICE_IP=$(kubectl get service kubernetes -n default -o jsonpath='{.spec.clusterIP}')
    create_all_probes

    # ------------------------------------------------------------------
    section "Positive: Istio Ingress Gateway -> Ingress Services"
    # ------------------------------------------------------------------
    # Istio ingress gateway pods are the only ingress-facing callers allowed
    # to reach these default-namespace services. Target services resolve via
    # cluster DNS.

    assert_allow_eventually "istio-ingress -> nginx-gateway:8080" \
        istio-ingress "$PROBE_ISTIO_INGRESS" nginx-gateway.default 8080

    assert_allow_eventually "istio-ingress -> ext-authz:9002" \
        istio-ingress "$PROBE_ISTIO_INGRESS" ext-authz.default 9002

    assert_allow_eventually "istio-ingress -> session-gateway:8081" \
        istio-ingress "$PROBE_ISTIO_INGRESS" session-gateway.default 8081

    # ------------------------------------------------------------------
    section "Positive: East-West (nginx-gateway -> backends)"
    # ------------------------------------------------------------------

    assert_allow_eventually "nginx-gateway -> transaction-service:8082" \
        default "$PROBE_NGINX" transaction-service 8082

    assert_allow_eventually "nginx-gateway -> currency-service:8084" \
        default "$PROBE_NGINX" currency-service 8084

    assert_allow_eventually "nginx-gateway -> budget-analyzer-web:3000" \
        default "$PROBE_NGINX" budget-analyzer-web 3000

    # ------------------------------------------------------------------
    section "Positive: East-West (session-gateway -> permission-service)"
    # ------------------------------------------------------------------

    assert_allow_eventually "session-gateway -> permission-service:8086" \
        default "$PROBE_SESSION" permission-service 8086

    # ------------------------------------------------------------------
    section "Positive: Application -> Infrastructure"
    # ------------------------------------------------------------------

    assert_allow_eventually "session-gateway -> redis:6379" \
        default "$PROBE_SESSION" redis.infrastructure 6379

    assert_allow_eventually "ext-authz -> redis:6379" \
        default "$PROBE_EXTAUTHZ" redis.infrastructure 6379

    assert_allow_eventually "transaction-service -> postgresql:5432" \
        default "$PROBE_TXN" postgresql.infrastructure 5432

    assert_allow_eventually "currency-service -> postgresql:5432" \
        default "$PROBE_CURRENCY" postgresql.infrastructure 5432

    assert_allow_eventually "currency-service -> rabbitmq:5671" \
        default "$PROBE_CURRENCY" rabbitmq.infrastructure 5671

    assert_allow_eventually "currency-service -> redis:6379" \
        default "$PROBE_CURRENCY" redis.infrastructure 6379

    assert_allow_eventually "permission-service -> postgresql:5432" \
        default "$PROBE_PERM" postgresql.infrastructure 5432

    # ------------------------------------------------------------------
    section "Positive: Istiod Egress"
    # ------------------------------------------------------------------
    # NetworkPolicy allows current workloads and the Istio ingress gateway to
    # reach istiod for config and certificate distribution.

    assert_allow_eventually "nginx-gateway-labeled pod -> istiod:15012" \
        default "$PROBE_NGINX" istiod.istio-system 15012

    assert_allow_eventually "istio-ingress-labeled pod -> istiod:15012" \
        istio-ingress "$PROBE_ISTIO_INGRESS" istiod.istio-system 15012

    # ------------------------------------------------------------------
    section "Positive: Monitoring Namespace"
    # ------------------------------------------------------------------

    assert_allow_eventually "grafana -> prometheus:9090" \
        monitoring "$PROBE_MONITORING_GRAFANA" "$(service_fqdn monitoring "$LISTENER_PROMETHEUS")" 9090

    assert_allow_eventually "prometheus -> grafana:3000" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn monitoring "$LISTENER_GRAFANA")" 3000

    assert_allow_eventually "prometheus -> kube-state-metrics:8080" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn monitoring "$LISTENER_KUBE_STATE_METRICS")" 8080

    assert_allow_eventually "prometheus -> prometheus-operator:8080" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn monitoring "$LISTENER_PROMETHEUS_OPERATOR")" 8080

    assert_allow_eventually "prometheus -> prometheus:9090" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn monitoring "$LISTENER_PROMETHEUS")" 9090

    assert_allow_eventually "prometheus -> spring-boot metrics:8081" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn default "$LISTENER_SPRING_BOOT_8081")" 8081

    assert_allow_eventually "prometheus -> spring-boot metrics:8082" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn default "$LISTENER_SPRING_BOOT_8082")" 8082

    assert_allow_eventually "prometheus -> spring-boot metrics:8084" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn default "$LISTENER_SPRING_BOOT_8084")" 8084

    assert_allow_eventually "prometheus -> spring-boot metrics:8086" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn default "$LISTENER_SPRING_BOOT_8086")" 8086

    assert_allow_eventually "kiali -> prometheus:9090" \
        monitoring "$PROBE_MONITORING_KIALI" "$(service_fqdn monitoring "$LISTENER_PROMETHEUS")" 9090

    assert_allow_eventually "kiali -> jaeger-query:16685" \
        monitoring "$PROBE_MONITORING_KIALI" "$(service_fqdn monitoring "$LISTENER_JAEGER_QUERY_GRPC")" 16685

    assert_allow_eventually "kiali -> jaeger-query:16686" \
        monitoring "$PROBE_MONITORING_KIALI" "$(service_fqdn monitoring "$LISTENER_JAEGER_QUERY_HTTP")" 16686

    assert_allow_eventually "kiali -> kubernetes.default:443" \
        monitoring "$PROBE_MONITORING_KIALI" "$KUBERNETES_SERVICE_IP" 443

    assert_allow_eventually "prometheus -> kubernetes.default:443" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$KUBERNETES_SERVICE_IP" 443

    assert_allow_eventually "kube-state-metrics -> kubernetes.default:443" \
        monitoring "$LISTENER_KUBE_STATE_METRICS" "$KUBERNETES_SERVICE_IP" 443

    assert_allow_eventually "prometheus-operator -> kubernetes.default:443" \
        monitoring "$LISTENER_PROMETHEUS_OPERATOR" "$KUBERNETES_SERVICE_IP" 443

    assert_allow_eventually "nginx-gateway -> jaeger-collector:4317" \
        default "$PROBE_NGINX" "$(service_fqdn monitoring "$LISTENER_JAEGER_COLLECTOR")" 4317

    assert_allow_eventually "istio-ingress -> jaeger-collector:4317" \
        istio-ingress "$PROBE_ISTIO_INGRESS" "$(service_fqdn monitoring "$LISTENER_JAEGER_COLLECTOR")" 4317

    assert_allow_eventually "istio-egress -> jaeger-collector:4317" \
        istio-egress "$PROBE_ISTIO_EGRESS" "$(service_fqdn monitoring "$LISTENER_JAEGER_COLLECTOR")" 4317

    assert_allow_eventually "monitoring prometheus -> jaeger-collector:4317" \
        monitoring "$PROBE_MONITORING_PROMETHEUS" "$(service_fqdn monitoring "$LISTENER_JAEGER_COLLECTOR")" 4317

    # ------------------------------------------------------------------
    section "Negative: Unlabeled Pod Isolation"
    # ------------------------------------------------------------------
    # An unlabeled pod in default gets DNS egress (podSelector:{}) but
    # no other ingress or egress allows. It cannot reach any service.

    assert_deny_consistently "unlabeled -> nginx-gateway:8080" \
        default "$PROBE_UNLABELED" nginx-gateway 8080

    assert_deny_consistently "unlabeled -> session-gateway:8081" \
        default "$PROBE_UNLABELED" session-gateway 8081

    assert_deny_consistently "unlabeled -> ext-authz:9002" \
        default "$PROBE_UNLABELED" ext-authz 9002

    assert_deny_consistently "unlabeled -> transaction-service:8082" \
        default "$PROBE_UNLABELED" transaction-service 8082

    assert_deny_consistently "unlabeled -> currency-service:8084" \
        default "$PROBE_UNLABELED" currency-service 8084

    assert_deny_consistently "unlabeled -> permission-service:8086" \
        default "$PROBE_UNLABELED" permission-service 8086

    assert_deny_consistently "unlabeled -> budget-analyzer-web:3000" \
        default "$PROBE_UNLABELED" budget-analyzer-web 3000

    assert_deny_consistently "unlabeled -> redis:6379" \
        default "$PROBE_UNLABELED" redis.infrastructure 6379

    assert_deny_consistently "unlabeled -> postgresql:5432" \
        default "$PROBE_UNLABELED" postgresql.infrastructure 5432

    assert_deny_consistently "unlabeled -> rabbitmq:5671" \
        default "$PROBE_UNLABELED" rabbitmq.infrastructure 5671

    assert_deny_consistently "unlabeled -> istio-egress-gateway:443" \
        default "$PROBE_UNLABELED" istio-egress-gateway.istio-egress 443
    assert_deny_consistently "unlabeled monitoring -> prometheus:9090" \
        monitoring "$PROBE_MONITORING_UNLABELED" "$(service_fqdn monitoring "$LISTENER_PROMETHEUS")" 9090
    assert_deny_consistently "unlabeled monitoring -> jaeger-query:16686" \
        monitoring "$PROBE_MONITORING_UNLABELED" "$(service_fqdn monitoring "$LISTENER_JAEGER_QUERY_HTTP")" 16686
    assert_deny_consistently "unlabeled monitoring -> kubernetes.default:443" \
        monitoring "$PROBE_MONITORING_UNLABELED" "$KUBERNETES_SERVICE_IP" 443

    # ------------------------------------------------------------------
    section "Negative: Cross-Identity Restrictions"
    # ------------------------------------------------------------------
    # Workloads must not reach services outside their approved edges.

    assert_deny_consistently "transaction-service -> redis:6379" \
        default "$PROBE_TXN" redis.infrastructure 6379

    assert_deny_consistently "transaction-service -> rabbitmq:5671" \
        default "$PROBE_TXN" rabbitmq.infrastructure 5671

    assert_deny_consistently "ext-authz -> postgresql:5432" \
        default "$PROBE_EXTAUTHZ" postgresql.infrastructure 5432

    assert_deny_consistently "ext-authz -> rabbitmq:5671" \
        default "$PROBE_EXTAUTHZ" rabbitmq.infrastructure 5671

    assert_deny_consistently "session-gateway -> transaction-service:8082" \
        default "$PROBE_SESSION" transaction-service 8082

    assert_deny_consistently "session-gateway -> currency-service:8084" \
        default "$PROBE_SESSION" currency-service 8084

    assert_deny_consistently "ext-authz -> istio-egress-gateway:443" \
        default "$PROBE_EXTAUTHZ" istio-egress-gateway.istio-egress 443
    assert_deny_consistently "nginx-gateway -> prometheus:9090" \
        default "$PROBE_NGINX" "$(service_fqdn monitoring "$LISTENER_PROMETHEUS")" 9090
    assert_deny_consistently "nginx-gateway -> jaeger-query:16686" \
        default "$PROBE_NGINX" "$(service_fqdn monitoring "$LISTENER_JAEGER_QUERY_HTTP")" 16686

    # ------------------------------------------------------------------
    section "Negative: Explicit Non-Edges"
    # ------------------------------------------------------------------
    # These paths are explicitly outside the NetworkPolicy contract and must stay
    # blocked unless the topology changes and the policy set is updated.

    assert_deny_consistently "session-gateway -> nginx-gateway:8080" \
        default "$PROBE_SESSION" nginx-gateway 8080

    assert_deny_consistently "istio-ingress -> ext-authz:8090" \
        istio-ingress "$PROBE_ISTIO_INGRESS" ext-authz.default 8090

    assert_deny_consistently "currency-service -> rabbitmq:15672" \
        default "$PROBE_CURRENCY" rabbitmq.infrastructure 15672

    # ------------------------------------------------------------------
    section "Current Topology: Istio Egress Gateway Access"
    # ------------------------------------------------------------------
    # In the Istio topology, only session-gateway and currency-service may
    # connect to the egress gateway on port 443. Other workloads must stay
    # blocked before any external routing logic is involved.

    assert_allow_eventually "session-gateway -> istio-egress-gateway:443" \
        default "$PROBE_SESSION" istio-egress-gateway.istio-egress 443

    assert_allow_eventually "currency-service -> istio-egress-gateway:443" \
        default "$PROBE_CURRENCY" istio-egress-gateway.istio-egress 443

    assert_deny_consistently "transaction-service -> istio-egress-gateway:443" \
        default "$PROBE_TXN" istio-egress-gateway.istio-egress 443

    assert_deny_consistently "permission-service -> istio-egress-gateway:443" \
        default "$PROBE_PERM" istio-egress-gateway.istio-egress 443

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------

    echo ""
    echo "=============================================="
    local total=$((PASSED + FAILED))
    if [[ "$FAILED" -eq 0 ]]; then
        echo "  ${PASSED} passed (out of ${total})"
    else
        echo "  ${PASSED} passed, ${FAILED} failed (out of ${total})"
    fi
    echo "=============================================="

    [[ "$FAILED" -gt 0 ]] && exit 1 || exit 0
}

main "$@"
