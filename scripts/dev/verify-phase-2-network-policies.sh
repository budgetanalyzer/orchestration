#!/bin/bash

# verify-phase-2-network-policies.sh
#
# Runtime verification for Security Hardening v2 Phase 2 network policies.
# Proves that NetworkPolicy allowlists are enforced by testing both authorized
# and unauthorized connectivity paths using disposable probe pods.
#
# Each probe pod uses sidecar.istio.io/inject: "false" so Istio does not
# contaminate results. Probes carry the same pod labels as the workload they
# impersonate, which is what NetworkPolicy selectors match on.
#
# Prerequisites: Tilt running with all services and network policies applied.
#
# Usage:
#   ./scripts/dev/verify-phase-2-network-policies.sh

set -euo pipefail

BUSYBOX_IMAGE="busybox:1.36.1"
CONNECT_TIMEOUT=3
DENY_TIMEOUT=3
ALLOW_ATTEMPTS=5
ALLOW_RETRY_DELAY=1
DENY_ATTEMPTS=3
DENY_RETRY_DELAY=1
PROBE_STABILIZATION_SECONDS=5

PASSED=0
FAILED=0
TEMP_PODS=()
LAST_SUCCESS_ATTEMPT=0
LAST_FAILURE_ATTEMPTS=0

usage() {
    cat <<'EOF'
Usage: ./scripts/dev/verify-phase-2-network-policies.sh

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
    echo "Cleaning up probe pods..."
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

require_cluster_access() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes cluster\n' >&2
        exit 1
    fi
}

require_network_policies() {
    local default_count infra_count
    default_count=$(kubectl get networkpolicy -n default --no-headers 2>/dev/null | wc -l)
    infra_count=$(kubectl get networkpolicy -n infrastructure --no-headers 2>/dev/null | wc -l)

    if [[ "$default_count" -eq 0 ]]; then
        printf 'ERROR: No network policies in default namespace. Apply policies first.\n' >&2
        exit 1
    fi
    if [[ "$infra_count" -eq 0 ]]; then
        printf 'ERROR: No network policies in infrastructure namespace. Apply policies first.\n' >&2
        exit 1
    fi

    printf '  Found %d policies in default, %d in infrastructure\n' "$default_count" "$infra_count"
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
  containers:
    - name: probe
      image: ${BUSYBOX_IMAGE}
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

PROBE_ENVOY="np2-envoy"
PROBE_NGINX="np2-nginx"
PROBE_SESSION="np2-session"
PROBE_EXTAUTHZ="np2-extauthz"
PROBE_TXN="np2-txn"
PROBE_CURRENCY="np2-currency"
PROBE_PERM="np2-perm"
PROBE_UNLABELED="np2-unlabeled"

create_all_probes() {
    echo "Creating probe pods..."

    # Envoy Gateway proxy probe in envoy-gateway-system
    create_probe envoy-gateway-system "$PROBE_ENVOY" \
        "app.kubernetes.io/component=proxy" \
        "gateway.envoyproxy.io/owning-gateway-name=ingress-gateway" \
        "gateway.envoyproxy.io/owning-gateway-namespace=default"

    # Default namespace probes impersonating each workload
    create_probe default "$PROBE_NGINX"     "app=nginx-gateway"
    create_probe default "$PROBE_SESSION"   "app=session-gateway"
    create_probe default "$PROBE_EXTAUTHZ"  "app=ext-authz"
    create_probe default "$PROBE_TXN"       "app=transaction-service"
    create_probe default "$PROBE_CURRENCY"  "app=currency-service"
    create_probe default "$PROBE_PERM"      "app=permission-service"

    # Unlabeled probe: no app label, only matches podSelector:{} policies (DNS)
    create_probe default "$PROBE_UNLABELED" "np2-role=probe"

    # Wait for all probes to be ready
    kubectl wait --for=condition=Ready \
        "pod/${PROBE_ENVOY}" -n envoy-gateway-system --timeout=60s >/dev/null 2>&1
    kubectl wait --for=condition=Ready \
        "pod/${PROBE_NGINX}" \
        "pod/${PROBE_SESSION}" \
        "pod/${PROBE_EXTAUTHZ}" \
        "pod/${PROBE_TXN}" \
        "pod/${PROBE_CURRENCY}" \
        "pod/${PROBE_PERM}" \
        "pod/${PROBE_UNLABELED}" \
        -n default --timeout=60s >/dev/null 2>&1

    echo "  All probe pods ready"
    echo "  Waiting ${PROBE_STABILIZATION_SECONDS}s for probe DNS/network stabilization..."
    sleep "$PROBE_STABILIZATION_SECONDS"

    warm_probe_dns envoy-gateway-system "$PROBE_ENVOY"
    warm_probe_dns default "$PROBE_NGINX"
    warm_probe_dns default "$PROBE_SESSION"
    warm_probe_dns default "$PROBE_EXTAUTHZ"
    warm_probe_dns default "$PROBE_TXN"
    warm_probe_dns default "$PROBE_CURRENCY"
    warm_probe_dns default "$PROBE_PERM"
    warm_probe_dns default "$PROBE_UNLABELED"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo "=============================================="
    echo "  Phase 2 Network Policy Verifier"
    echo "=============================================="
    echo

    require_host_command kubectl
    require_cluster_access
    require_network_policies
    create_all_probes

    # ------------------------------------------------------------------
    section "Positive: Envoy Gateway proxy -> Ingress Services"
    # ------------------------------------------------------------------
    # Envoy proxy pods are the only external entry point into the cluster.
    # Target services are in the default namespace; probes resolve via FQDN.

    assert_allow_eventually "envoy -> nginx-gateway:8080" \
        envoy-gateway-system "$PROBE_ENVOY" nginx-gateway.default 8080

    assert_allow_eventually "envoy -> ext-authz:9002" \
        envoy-gateway-system "$PROBE_ENVOY" ext-authz.default 9002

    assert_allow_eventually "envoy -> session-gateway:8081" \
        envoy-gateway-system "$PROBE_ENVOY" session-gateway.default 8081

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
    # The istiod egress policy allows sidecar-injected workloads to reach
    # istiod for xDS config and mTLS cert rotation. Test from a labeled probe.

    assert_allow_eventually "nginx-gateway-labeled pod -> istiod:15012" \
        default "$PROBE_NGINX" istiod.istio-system 15012

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

    # ------------------------------------------------------------------
    section "Negative: Explicit Phase 2 Non-Edges"
    # ------------------------------------------------------------------
    # These paths are explicitly outside the Phase 2 contract and must stay
    # blocked unless the topology changes and the policy set is updated.

    assert_deny_consistently "session-gateway -> nginx-gateway:8080" \
        default "$PROBE_SESSION" nginx-gateway 8080

    assert_deny_consistently "envoy -> ext-authz:8090" \
        envoy-gateway-system "$PROBE_ENVOY" ext-authz.default 8090

    assert_deny_consistently "currency-service -> rabbitmq:15672" \
        default "$PROBE_CURRENCY" rabbitmq.infrastructure 15672

    # ------------------------------------------------------------------
    section "Conditional: External Egress (TCP 443)"
    # ------------------------------------------------------------------
    # session-gateway and currency-service have temporary TCP 443 egress.
    # Other workloads must not. Test only if the cluster has external
    # connectivity (verified from a pod that should have 443 egress).

    if connect_eventually default "$PROBE_CURRENCY" 1.1.1.1 443 3 1; then
        if [[ "$LAST_SUCCESS_ATTEMPT" -gt 1 ]]; then
            pass "currency-service allowed external TCP 443 (attempt ${LAST_SUCCESS_ATTEMPT}/3)"
        else
            pass "currency-service allowed external TCP 443"
        fi

        assert_allow_eventually "session-gateway allowed external TCP 443" \
            default "$PROBE_SESSION" 1.1.1.1 443

        assert_deny_consistently "transaction-service denied external TCP 443" \
            default "$PROBE_TXN" 1.1.1.1 443

        assert_deny_consistently "permission-service denied external TCP 443" \
            default "$PROBE_PERM" 1.1.1.1 443
    else
        echo "  [SKIP] No external connectivity from cluster; skipping egress tests"
    fi

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
