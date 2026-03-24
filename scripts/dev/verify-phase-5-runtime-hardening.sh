#!/bin/bash

# verify-phase-5-runtime-hardening.sh
#
# Runtime verification for Security Hardening v2 Phase 5 runtime hardening and
# Pod Security. Proves the Istio CNI cutover, namespace PSA posture,
# service-account-token hardening, workload security contexts, and restricted
# PSA admission behavior for meshed workloads. Also runs regressions for
# earlier phase verifiers unless explicitly skipped.
#
# Usage:
#   ./scripts/dev/verify-phase-5-runtime-hardening.sh
#   ./scripts/dev/verify-phase-5-runtime-hardening.sh --skip-regressions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUSYBOX_IMAGE="busybox:1.36.1"
WAIT_TIMEOUT="120s"
RUN_REGRESSIONS=true
TEMP_NAMESPACE=""

PASSED=0
FAILED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/dev/verify-phase-5-runtime-hardening.sh

Options:
  --skip-regressions          Skip Phase 3 and Phase 4 regression verifiers.
  -h, --help                  Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-regressions)
            RUN_REGRESSIONS=false
            shift
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

cleanup() {
    set +e
    if [[ -n "${TEMP_NAMESPACE}" ]]; then
        kubectl delete namespace "${TEMP_NAMESPACE}" --wait=false >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

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

get_namespace_label() {
    local namespace="$1"
    local key="$2"

    kubectl get namespace "$namespace" -o go-template="{{index .metadata.labels \"$key\"}}" 2>/dev/null || true
}

assert_namespace_label() {
    local namespace="$1"
    local key="$2"
    local expected="$3"
    local description="$4"
    local actual

    actual=$(get_namespace_label "$namespace" "$key")
    if [[ "$actual" == "$expected" ]]; then
        pass "$description"
    else
        fail "$description (expected ${key}=${expected}, got ${actual:-<unset>})"
    fi
}

find_pod() {
    local namespace="$1"
    local selector="$2"

    kubectl get pods -n "$namespace" -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

require_pod() {
    local namespace="$1"
    local selector="$2"
    local label="$3"
    local pod

    require_namespace "$namespace"
    pod=$(find_pod "$namespace" "$selector")
    if [[ -z "$pod" ]]; then
        printf 'ERROR: %s pod not found in namespace %s (context: %s)\n' \
            "$label" "$namespace" "$(current_context)" >&2
        exit 1
    fi

    printf '%s' "$pod"
}

assert_pod_ready() {
    local namespace="$1"
    local pod="$2"
    local label="$3"

    if kubectl wait --for=condition=Ready "pod/${pod}" -n "$namespace" --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1; then
        pass "$label pod is Ready"
    else
        fail "$label pod is not Ready"
    fi
}

get_pod_value() {
    local namespace="$1"
    local pod="$2"
    local jsonpath="$3"

    kubectl get pod "$pod" -n "$namespace" -o "jsonpath=${jsonpath}" 2>/dev/null || true
}

assert_pod_automount_false() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local actual

    actual=$(get_pod_value "$namespace" "$pod" '{.spec.automountServiceAccountToken}')
    if [[ "$actual" == "false" ]]; then
        pass "$label disables service-account token automount"
    else
        fail "$label does not set automountServiceAccountToken=false"
    fi
}

assert_pod_seccomp_runtime_default() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local actual

    actual=$(get_pod_value "$namespace" "$pod" '{.spec.securityContext.seccompProfile.type}')
    if [[ "$actual" == "RuntimeDefault" ]]; then
        pass "$label sets pod seccompProfile to RuntimeDefault"
    else
        fail "$label does not set pod seccompProfile.type=RuntimeDefault"
    fi
}

assert_no_kube_api_access_volume() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local volumes

    volumes=$(get_pod_value "$namespace" "$pod" '{range .spec.volumes[*]}{.name}{"\n"}{end}')
    if printf '%s\n' "$volumes" | grep -Eq '^kube-api-access-'; then
        fail "$label still mounts kube-api-access projected token volume"
    else
        pass "$label does not mount the default Kubernetes API token volume"
    fi
}

container_security_line() {
    local namespace="$1"
    local pod="$2"
    local container="$3"

    kubectl get pod "$pod" -n "$namespace" \
        -o jsonpath='{range .spec.containers[*]}{.name}{"|"}{.securityContext.runAsNonRoot}{"|"}{.securityContext.allowPrivilegeEscalation}{"|"}{.securityContext.readOnlyRootFilesystem}{"|"}{.securityContext.capabilities.drop}{"\n"}{end}' \
        2>/dev/null | grep -F "${container}|" || true
}

assert_container_baseline() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local label="$4"
    local require_read_only="$5"
    local line run_as_non_root allow_pe read_only drop_caps

    line=$(container_security_line "$namespace" "$pod" "$container")
    if [[ -z "$line" ]]; then
        fail "$label container ${container} not found in pod spec"
        return
    fi

    IFS='|' read -r _ run_as_non_root allow_pe read_only drop_caps <<<"$line"

    if [[ "$run_as_non_root" == "true" ]]; then
        pass "$label container ${container} sets runAsNonRoot=true"
    else
        fail "$label container ${container} does not set runAsNonRoot=true"
    fi

    if [[ "$allow_pe" == "false" ]]; then
        pass "$label container ${container} sets allowPrivilegeEscalation=false"
    else
        fail "$label container ${container} does not set allowPrivilegeEscalation=false"
    fi

    if [[ "$drop_caps" == *ALL* ]]; then
        pass "$label container ${container} drops ALL Linux capabilities"
    else
        fail "$label container ${container} does not drop ALL Linux capabilities"
    fi

    if [[ "$require_read_only" == "true" ]]; then
        if [[ "$read_only" == "true" ]]; then
            pass "$label container ${container} enables readOnlyRootFilesystem"
        else
            fail "$label container ${container} does not enable readOnlyRootFilesystem"
        fi
    fi
}

assert_no_istio_init() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local init_containers

    init_containers=$(get_pod_value "$namespace" "$pod" '{.spec.initContainers[*].name}')
    if printf '%s\n' "$init_containers" | grep -qw 'istio-init'; then
        fail "$label still contains injected istio-init"
    else
        pass "$label does not contain istio-init"
    fi
}

pod_service_account() {
    local namespace="$1"
    local pod="$2"

    get_pod_value "$namespace" "$pod" '{.spec.serviceAccountName}'
}

assert_serviceaccount_automount_false() {
    local namespace="$1"
    local service_account="$2"
    local label="$3"
    local actual

    actual=$(kubectl get serviceaccount "$service_account" -n "$namespace" -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || true)
    if [[ "$actual" == "false" ]]; then
        pass "$label ServiceAccount disables token automount"
    else
        fail "$label ServiceAccount does not set automountServiceAccountToken=false"
    fi
}

verify_workload() {
    local namespace="$1"
    local selector="$2"
    local label="$3"
    local container="$4"
    local require_read_only="$5"
    local require_no_istio_init="$6"
    local check_service_account="$7"
    local pod sa

    pod=$(require_pod "$namespace" "$selector" "$label")
    assert_pod_ready "$namespace" "$pod" "$label"
    assert_pod_automount_false "$namespace" "$pod" "$label"
    assert_no_kube_api_access_volume "$namespace" "$pod" "$label"
    assert_pod_seccomp_runtime_default "$namespace" "$pod" "$label"
    assert_container_baseline "$namespace" "$pod" "$container" "$label" "$require_read_only"

    if [[ "$require_no_istio_init" == "true" ]]; then
        assert_no_istio_init "$namespace" "$pod" "$label"
    fi

    if [[ "$check_service_account" == "true" ]]; then
        sa=$(pod_service_account "$namespace" "$pod")
        if [[ -n "$sa" ]]; then
            assert_serviceaccount_automount_false "$namespace" "$sa" "$label"
        else
            fail "$label pod does not expose a serviceAccountName"
        fi
    fi
}

verify_istio_cni() {
    section "Istio CNI"

    if kubectl rollout status daemonset/istio-cni-node -n istio-system --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1; then
        pass "istio-cni-node DaemonSet is rolled out in istio-system"
    else
        fail "istio-cni-node DaemonSet is not ready in istio-system"
    fi
}

verify_namespace_policy_targets() {
    section "Namespace Pod Security Labels"

    assert_namespace_label default "pod-security.kubernetes.io/enforce" "restricted" "default namespace enforces restricted Pod Security"
    assert_namespace_label default "pod-security.kubernetes.io/warn" "restricted" "default namespace warns on restricted Pod Security violations"
    assert_namespace_label default "pod-security.kubernetes.io/audit" "restricted" "default namespace audits restricted Pod Security violations"

    assert_namespace_label infrastructure "pod-security.kubernetes.io/enforce" "baseline" "infrastructure namespace enforces baseline Pod Security"
    assert_namespace_label infrastructure "pod-security.kubernetes.io/warn" "baseline" "infrastructure namespace warns on baseline Pod Security violations"
    assert_namespace_label infrastructure "pod-security.kubernetes.io/audit" "baseline" "infrastructure namespace audits baseline Pod Security violations"

    assert_namespace_label istio-ingress "pod-security.kubernetes.io/enforce" "restricted" "istio-ingress namespace enforces restricted Pod Security"
    assert_namespace_label istio-ingress "pod-security.kubernetes.io/warn" "restricted" "istio-ingress namespace warns on restricted Pod Security violations"
    assert_namespace_label istio-ingress "pod-security.kubernetes.io/audit" "restricted" "istio-ingress namespace audits restricted Pod Security violations"

    assert_namespace_label istio-egress "pod-security.kubernetes.io/enforce" "restricted" "istio-egress namespace enforces restricted Pod Security"
    assert_namespace_label istio-egress "pod-security.kubernetes.io/warn" "restricted" "istio-egress namespace warns on restricted Pod Security violations"
    assert_namespace_label istio-egress "pod-security.kubernetes.io/audit" "restricted" "istio-egress namespace audits restricted Pod Security violations"

    assert_namespace_label istio-system "pod-security.kubernetes.io/enforce" "privileged" "istio-system namespace enforces privileged Pod Security for istio-cni"
}

verify_workloads() {
    section "Workload Hardening"

    local specs=(
        "default|app=budget-analyzer-web|budget-analyzer-web|budget-analyzer-web|false|true|true"
        "default|app=currency-service|currency-service|currency-service|true|true|true"
        "default|app=ext-authz|ext-authz|ext-authz|true|true|true"
        "default|app=nginx-gateway|nginx-gateway|nginx|true|true|true"
        "default|app=permission-service|permission-service|permission-service|true|true|true"
        "default|app=session-gateway|session-gateway|session-gateway|true|true|true"
        "default|app=transaction-service|transaction-service|transaction-service|true|true|true"
        "infrastructure|app=redis|redis|redis|false|false|false"
        "infrastructure|app=postgresql|postgresql|postgresql|false|false|false"
        "infrastructure|app=rabbitmq|rabbitmq|rabbitmq|false|false|false"
        "istio-ingress|gateway.networking.k8s.io/gateway-name=istio-ingress-gateway|istio ingress gateway|istio-proxy|true|false|true"
        "istio-egress|app=istio-egress-gateway|istio egress gateway|istio-proxy|true|false|true"
    )
    local spec namespace selector label container require_ro require_no_init check_sa

    for spec in "${specs[@]}"; do
        IFS='|' read -r namespace selector label container require_ro require_no_init check_sa <<<"$spec"
        verify_workload "$namespace" "$selector" "$label" "$container" "$require_ro" "$require_no_init" "$check_sa"
    done
}

verify_restricted_psa_smoke() {
    section "Restricted PSA Meshed Smoke Test"

    TEMP_NAMESPACE="ba-phase5-psa-$(date +%s)"
    kubectl create namespace "${TEMP_NAMESPACE}" >/dev/null
    kubectl label namespace "${TEMP_NAMESPACE}" \
        istio-injection=enabled \
        pod-security.kubernetes.io/enforce=restricted \
        pod-security.kubernetes.io/warn=restricted \
        pod-security.kubernetes.io/audit=restricted \
        >/dev/null

    set +e
    local output status
    output=$(kubectl apply -n "${TEMP_NAMESPACE}" -f - 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: secure-meshed-smoke
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: ${BUSYBOX_IMAGE}
      command: ["sh", "-c", "sleep 300"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65532
MANIFEST
)
    status=$?
    set -e

    if [[ "$status" -ne 0 ]]; then
        fail "Restricted meshed smoke pod was rejected: ${output:0:220}"
        return
    fi

    if kubectl wait --for=condition=Ready pod/secure-meshed-smoke -n "${TEMP_NAMESPACE}" --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1; then
        pass "Restricted meshed smoke pod starts successfully"
    else
        fail "Restricted meshed smoke pod did not become Ready"
    fi

    local init_containers
    init_containers=$(get_pod_value "${TEMP_NAMESPACE}" secure-meshed-smoke '{.spec.initContainers[*].name}')
    if printf '%s\n' "$init_containers" | grep -qw 'istio-init'; then
        fail "Restricted meshed smoke pod still contains istio-init"
    else
        pass "Restricted meshed smoke pod does not contain istio-init"
    fi

    local containers
    containers=$(get_pod_value "${TEMP_NAMESPACE}" secure-meshed-smoke '{.spec.containers[*].name}')
    if printf '%s\n' "$containers" | grep -qw 'istio-proxy'; then
        pass "Restricted meshed smoke pod still receives the Istio sidecar"
    else
        fail "Restricted meshed smoke pod did not receive the Istio sidecar"
    fi

    set +e
    output=$(kubectl apply -n "${TEMP_NAMESPACE}" -f - 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: insecure-meshed-smoke
spec:
  automountServiceAccountToken: false
  containers:
    - name: app
      image: ${BUSYBOX_IMAGE}
      command: ["sh", "-c", "sleep 300"]
      securityContext:
        privileged: true
MANIFEST
)
    status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        fail "Restricted meshed namespace admitted an intentionally insecure pod"
    elif printf '%s\n' "$output" | grep -Eqi 'PodSecurity|forbidden|violates'; then
        pass "Restricted meshed namespace rejects an intentionally insecure pod"
    else
        fail "Insecure meshed pod failed for an unexpected reason: ${output:0:220}"
    fi
}

run_regressions() {
    if [[ "$RUN_REGRESSIONS" != true ]]; then
        section "Regression: Earlier Security Phases"
        pass "Regression verifiers were skipped by request"
        return
    fi

    section "Regression: Earlier Security Phases"

    if "${SCRIPT_DIR}/verify-phase-3-istio-ingress.sh"; then
        pass "Phase 3 ingress verification still passes after runtime hardening"
    else
        fail "Phase 3 ingress verification failed after runtime hardening"
    fi

    if "${SCRIPT_DIR}/verify-phase-4-transport-encryption.sh"; then
        pass "Phase 4 transport-encryption verification still passes after runtime hardening"
    else
        fail "Phase 4 transport-encryption verification failed after runtime hardening"
    fi
}

main() {
    echo "=============================================="
    echo "  Phase 5 Runtime Hardening Verifier"
    echo "=============================================="
    echo

    require_host_command kubectl
    require_cluster_access
    require_namespace default
    require_namespace infrastructure
    require_namespace istio-system
    require_namespace istio-ingress
    require_namespace istio-egress

    verify_istio_cni
    verify_namespace_policy_targets
    verify_workloads
    verify_restricted_psa_smoke
    run_regressions

    echo ""
    echo "=============================================="
    total=$((PASSED + FAILED))
    if [[ "$FAILED" -eq 0 ]]; then
        echo "  ${PASSED} passed (out of ${total})"
    else
        echo "  ${PASSED} passed, ${FAILED} failed (out of ${total})"
    fi
    echo "=============================================="

    [[ "$FAILED" -gt 0 ]] && exit 1 || exit 0
}

main "$@"
