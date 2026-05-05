#!/bin/bash

# verify-phase-5-runtime-hardening.sh
#
# Runtime verification for runtime hardening and Pod Security. Proves the
# Istio CNI cutover, namespace PSA posture,
# service-account-token hardening, workload security contexts, and restricted
# PSA admission behavior for meshed workloads. Also runs regressions for
# earlier security verifiers unless explicitly skipped.
#
# Usage:
#   ./scripts/smoketest/verify-phase-5-runtime-hardening.sh
#   ./scripts/smoketest/verify-phase-5-runtime-hardening.sh --skip-regressions
#   ./scripts/smoketest/verify-phase-5-runtime-hardening.sh --regression-timeout 10m

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_IMAGE="postgres:16-alpine@sha256:4e6e670bb069649261c9c18031f0aded7bb249a5b6664ddec29c013a89310d50"
WAIT_TIMEOUT="120s"
REGRESSION_TIMEOUT="10m"
RUN_REGRESSIONS=true
TEMP_NAMESPACE=""

PASSED=0
FAILED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-phase-5-runtime-hardening.sh

Options:
  --skip-regressions          Skip credential, NetworkPolicy, ingress, and
                              transport-TLS regression verifiers.
  --regression-timeout <dur>  Per-script timeout for those regression
                              regression verifiers (default: 10m).
  -h, --help                  Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-regressions)
            RUN_REGRESSIONS=false
            shift
            ;;
        --regression-timeout)
            if [[ $# -lt 2 ]]; then
                printf 'ERROR: --regression-timeout requires a duration argument\n' >&2
                usage >&2
                exit 1
            fi
            REGRESSION_TIMEOUT="$2"
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

assert_kube_api_access_volume_present() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local volumes

    volumes=$(get_pod_value "$namespace" "$pod" '{range .spec.volumes[*]}{.name}{"\n"}{end}')
    if printf '%s\n' "$volumes" | grep -Eq '^kube-api-access-'; then
        pass "$label still mounts the Kubernetes API token volume where the current gateway configuration intentionally retains it"
    else
        fail "$label does not mount the Kubernetes API token volume that the current gateway configuration still retains"
    fi
}

container_security_line() {
    local namespace="$1"
    local pod="$2"
    local container="$3"

    kubectl get pod "$pod" -n "$namespace" \
        -o jsonpath='{range .spec.containers[*]}{.name}{"|"}{.securityContext.runAsNonRoot}{"|"}{.securityContext.allowPrivilegeEscalation}{"|"}{.securityContext.readOnlyRootFilesystem}{"|"}{.securityContext.capabilities.drop}{"|"}{.securityContext.runAsUser}{"|"}{.securityContext.runAsGroup}{"\n"}{end}' \
        2>/dev/null | grep -F "${container}|" || true
}

init_container_security_line() {
    local namespace="$1"
    local pod="$2"
    local container="$3"

    kubectl get pod "$pod" -n "$namespace" \
        -o jsonpath='{range .spec.initContainers[*]}{.name}{"|"}{.securityContext.runAsNonRoot}{"|"}{.securityContext.allowPrivilegeEscalation}{"|"}{.securityContext.readOnlyRootFilesystem}{"|"}{.securityContext.capabilities.drop}{"|"}{.securityContext.runAsUser}{"|"}{.securityContext.runAsGroup}{"|"}{.securityContext.seccompProfile.type}{"\n"}{end}' \
        2>/dev/null | grep -F "${container}|" || true
}

assert_container_baseline() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local label="$4"
    local require_read_only="$5"
    local line run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group

    line=$(container_security_line "$namespace" "$pod" "$container")
    if [[ -z "$line" ]]; then
        fail "$label container ${container} not found in pod spec"
        return
    fi

    IFS='|' read -r _ run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group <<<"$line"

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

assert_init_container_baseline() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local label="$4"
    local line run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group seccomp

    line=$(init_container_security_line "$namespace" "$pod" "$container")
    if [[ -z "$line" ]]; then
        fail "$label init container ${container} not found in pod spec"
        return
    fi

    IFS='|' read -r _ run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group seccomp <<<"$line"

    if [[ "$run_as_non_root" == "true" ]]; then
        pass "$label init container ${container} sets runAsNonRoot=true"
    else
        fail "$label init container ${container} does not set runAsNonRoot=true"
    fi

    if [[ "$allow_pe" == "false" ]]; then
        pass "$label init container ${container} sets allowPrivilegeEscalation=false"
    else
        fail "$label init container ${container} does not set allowPrivilegeEscalation=false"
    fi

    if [[ "$drop_caps" == *ALL* ]]; then
        pass "$label init container ${container} drops ALL Linux capabilities"
    else
        fail "$label init container ${container} does not drop ALL Linux capabilities"
    fi

    if [[ "$read_only" == "true" ]]; then
        pass "$label init container ${container} enables readOnlyRootFilesystem"
    else
        fail "$label init container ${container} does not enable readOnlyRootFilesystem"
    fi

    if [[ "$seccomp" == "RuntimeDefault" ]]; then
        pass "$label init container ${container} sets seccompProfile to RuntimeDefault"
    else
        fail "$label init container ${container} does not set seccompProfile.type=RuntimeDefault"
    fi
}

assert_container_user_group() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local label="$4"
    local expected_user="$5"
    local expected_group="$6"
    local line run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group

    line=$(container_security_line "$namespace" "$pod" "$container")
    if [[ -z "$line" ]]; then
        fail "$label container ${container} not found in pod spec"
        return
    fi

    IFS='|' read -r _ run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group <<<"$line"

    if [[ "$run_as_user" == "$expected_user" ]]; then
        pass "$label container ${container} sets runAsUser=${expected_user}"
    else
        fail "$label container ${container} does not set runAsUser=${expected_user} (got ${run_as_user:-<unset>})"
    fi

    if [[ "$run_as_group" == "$expected_group" ]]; then
        pass "$label container ${container} sets runAsGroup=${expected_group}"
    else
        fail "$label container ${container} does not set runAsGroup=${expected_group} (got ${run_as_group:-<unset>})"
    fi
}

assert_init_container_user_group() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local label="$4"
    local expected_user="$5"
    local expected_group="$6"
    local line run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group seccomp

    line=$(init_container_security_line "$namespace" "$pod" "$container")
    if [[ -z "$line" ]]; then
        fail "$label init container ${container} not found in pod spec"
        return
    fi

    IFS='|' read -r _ run_as_non_root allow_pe read_only drop_caps run_as_user run_as_group seccomp <<<"$line"

    if [[ "$run_as_user" == "$expected_user" ]]; then
        pass "$label init container ${container} sets runAsUser=${expected_user}"
    else
        fail "$label init container ${container} does not set runAsUser=${expected_user} (got ${run_as_user:-<unset>})"
    fi

    if [[ "$run_as_group" == "$expected_group" ]]; then
        pass "$label init container ${container} sets runAsGroup=${expected_group}"
    else
        fail "$label init container ${container} does not set runAsGroup=${expected_group} (got ${run_as_group:-<unset>})"
    fi
}

assert_container_mount_path() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local label="$4"
    local volume_name="$5"
    local mount_path="$6"
    local mounts

    mounts=$(kubectl get pod "$pod" -n "$namespace" \
        -o jsonpath="{range .spec.containers[?(@.name==\"${container}\")].volumeMounts[*]}{.name}{\"|\"}{.mountPath}{\"\n\"}{end}" \
        2>/dev/null || true)

    if printf '%s\n' "$mounts" | grep -Fxq "${volume_name}|${mount_path}"; then
        pass "$label container ${container} mounts ${volume_name} at ${mount_path}"
    else
        fail "$label container ${container} does not mount ${volume_name} at ${mount_path}"
    fi
}

assert_empty_dir_volume() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local volume_name="$4"
    local volume_type

    volume_type=$(kubectl get pod "$pod" -n "$namespace" \
        -o jsonpath="{range .spec.volumes[?(@.name==\"${volume_name}\")]}{.emptyDir}{end}" \
        2>/dev/null || true)

    if [[ -n "$volume_type" ]]; then
        pass "$label pod defines ${volume_name} as an emptyDir volume"
    else
        fail "$label pod does not define ${volume_name} as an emptyDir volume"
    fi
}

assert_persistent_volume_claim() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local volume_name="$4"
    local expected_claim_name="${5:-}"
    local claim_name

    claim_name=$(kubectl get pod "$pod" -n "$namespace" \
        -o jsonpath="{range .spec.volumes[?(@.name==\"${volume_name}\")]}{.persistentVolumeClaim.claimName}{end}" \
        2>/dev/null || true)

    if [[ -n "$expected_claim_name" && "$claim_name" == "$expected_claim_name" ]]; then
        pass "$label pod defines ${volume_name} as persistentVolumeClaim ${expected_claim_name}"
    elif [[ -n "$expected_claim_name" ]]; then
        fail "$label pod does not define ${volume_name} as persistentVolumeClaim ${expected_claim_name} (got ${claim_name:-<unset>})"
    elif [[ -n "$claim_name" ]]; then
        pass "$label pod defines ${volume_name} as a persistentVolumeClaim volume (${claim_name})"
    else
        fail "$label pod does not define ${volume_name} as a persistentVolumeClaim volume"
    fi
}

assert_pod_fs_group() {
    local namespace="$1"
    local pod="$2"
    local label="$3"
    local expected_group="$4"
    local actual_group

    actual_group=$(get_pod_value "$namespace" "$pod" '{.spec.securityContext.fsGroup}')
    if [[ "$actual_group" == "$expected_group" ]]; then
        pass "$label pod sets fsGroup=${expected_group}"
    else
        fail "$label pod does not set fsGroup=${expected_group} (got ${actual_group:-<unset>})"
    fi
}

assert_container_mount_read_only_true() {
    local namespace="$1"
    local pod="$2"
    local container="$3"
    local label="$4"
    local volume_name="$5"
    local mounts

    mounts=$(kubectl get pod "$pod" -n "$namespace" \
        -o jsonpath="{range .spec.containers[?(@.name==\"${container}\")].volumeMounts[*]}{.name}{\"|\"}{.readOnly}{\"\n\"}{end}" \
        2>/dev/null || true)

    if printf '%s\n' "$mounts" | grep -Fxq "${volume_name}|true"; then
        pass "$label container ${container} mounts ${volume_name} read-only"
    else
        fail "$label container ${container} does not mount ${volume_name} read-only"
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

assert_serviceaccount_automount_not_false() {
    local namespace="$1"
    local service_account="$2"
    local label="$3"
    local actual

    actual=$(kubectl get serviceaccount "$service_account" -n "$namespace" -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || true)
    if [[ "$actual" == "false" ]]; then
        fail "$label ServiceAccount disables token automount even though the current gateway configuration still retains Kubernetes API access"
    else
        pass "$label ServiceAccount preserves Kubernetes API token automount for the current gateway configuration"
    fi
}

verify_workload() {
    local namespace="$1"
    local selector="$2"
    local label="$3"
    local container="$4"
    local require_read_only="$5"
    local require_no_istio_init="$6"
    local token_mode="$7"
    local check_service_account="$8"
    local pod sa

    pod=$(require_pod "$namespace" "$selector" "$label")
    assert_pod_ready "$namespace" "$pod" "$label"
    assert_pod_seccomp_runtime_default "$namespace" "$pod" "$label"
    assert_container_baseline "$namespace" "$pod" "$container" "$label" "$require_read_only"

    case "$token_mode" in
        disabled)
            assert_pod_automount_false "$namespace" "$pod" "$label"
            assert_no_kube_api_access_volume "$namespace" "$pod" "$label"
            ;;
        retained)
            assert_kube_api_access_volume_present "$namespace" "$pod" "$label"
            ;;
        *)
            fail "$label uses unsupported token verification mode: $token_mode"
            ;;
    esac

    if [[ "$require_no_istio_init" == "true" ]]; then
        assert_no_istio_init "$namespace" "$pod" "$label"
    fi

    if [[ "$check_service_account" == "true" ]]; then
        sa=$(pod_service_account "$namespace" "$pod")
        if [[ -n "$sa" ]]; then
            if [[ "$token_mode" == "disabled" ]]; then
                assert_serviceaccount_automount_false "$namespace" "$sa" "$label"
            else
                assert_serviceaccount_automount_not_false "$namespace" "$sa" "$label"
            fi
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
        "default|app=budget-analyzer-web|budget-analyzer-web|budget-analyzer-web|false|true|disabled|true"
        "default|app=currency-service|currency-service|currency-service|true|true|disabled|true"
        "default|app=ext-authz|ext-authz|ext-authz|true|true|disabled|true"
        "default|app=nginx-gateway|nginx-gateway|nginx|true|true|disabled|true"
        "default|app=permission-service|permission-service|permission-service|true|true|disabled|true"
        "default|app=session-gateway|session-gateway|session-gateway|true|true|disabled|true"
        "default|app=transaction-service|transaction-service|transaction-service|true|true|disabled|true"
        "infrastructure|app=redis|redis|redis|true|false|disabled|false"
        "infrastructure|app=postgresql|postgresql|postgresql|true|false|disabled|false"
        "infrastructure|app=rabbitmq|rabbitmq|rabbitmq|true|false|disabled|false"
        "istio-ingress|gateway.networking.k8s.io/gateway-name=istio-ingress-gateway|istio ingress gateway|istio-proxy|true|false|retained|true"
        "istio-egress|app=istio-egress-gateway|istio egress gateway|istio-proxy|true|false|retained|true"
    )
    local spec namespace selector label container require_ro require_no_init token_mode check_sa

    for spec in "${specs[@]}"; do
        IFS='|' read -r namespace selector label container require_ro require_no_init token_mode check_sa <<<"$spec"
        verify_workload "$namespace" "$selector" "$label" "$container" "$require_ro" "$require_no_init" "$token_mode" "$check_sa"
    done
}

verify_nginx_runtime() {
    section "NGINX Gateway Runtime Specifics"

    local namespace="default"
    local selector="app=nginx-gateway"
    local label="nginx-gateway"
    local container="nginx"
    local pod

    pod=$(require_pod "$namespace" "$selector" "$label")
    assert_container_user_group "$namespace" "$pod" "$container" "$label" "101" "101"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "nginx-tmp" "/tmp"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "nginx-config" "/etc/nginx/nginx.conf"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "nginx-includes" "/etc/nginx/includes"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "nginx-docs" "/usr/share/nginx/html/docs"
    assert_empty_dir_volume "$namespace" "$pod" "$label" "nginx-tmp"
    assert_container_mount_read_only_true "$namespace" "$pod" "$container" "$label" "nginx-config"
    assert_container_mount_read_only_true "$namespace" "$pod" "$container" "$label" "nginx-includes"
    assert_container_mount_read_only_true "$namespace" "$pod" "$container" "$label" "nginx-docs"
}

verify_budget_analyzer_web_runtime() {
    section "Budget Analyzer Web Runtime Specifics"

    local namespace="default"
    local selector="app=budget-analyzer-web"
    local label="budget-analyzer-web"
    local container="budget-analyzer-web"
    local pod

    pod=$(require_pod "$namespace" "$selector" "$label")
    assert_container_user_group "$namespace" "$pod" "$container" "$label" "1001" "1001"
}

verify_redis_runtime() {
    section "Redis Runtime Specifics"

    local namespace="infrastructure"
    local selector="app=redis"
    local label="redis"
    local container="redis"
    local pod

    pod=$(require_pod "$namespace" "$selector" "$label")
    assert_container_user_group "$namespace" "$pod" "$container" "$label" "999" "1000"
    assert_pod_fs_group "$namespace" "$pod" "$label" "1000"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "redis-tmp" "/tmp"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "redis-data" "/data"
    assert_empty_dir_volume "$namespace" "$pod" "$label" "redis-tmp"
    assert_persistent_volume_claim "$namespace" "$pod" "$label" "redis-data" "redis-data-redis-0"
}

verify_postgresql_runtime() {
    section "PostgreSQL Runtime Specifics"

    local namespace="infrastructure"
    local selector="app=postgresql"
    local label="postgresql"
    local container="postgresql"
    local init_container="fix-tls-perms"
    local pod

    pod=$(require_pod "$namespace" "$selector" "$label")
    assert_init_container_baseline "$namespace" "$pod" "$init_container" "$label"
    assert_init_container_user_group "$namespace" "$pod" "$init_container" "$label" "70" "70"
    assert_container_user_group "$namespace" "$pod" "$container" "$label" "70" "70"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "postgresql-run" "/var/run/postgresql"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "postgresql-tmp" "/tmp"
    assert_empty_dir_volume "$namespace" "$pod" "$label" "postgresql-run"
    assert_empty_dir_volume "$namespace" "$pod" "$label" "postgresql-tmp"
}

verify_rabbitmq_runtime() {
    section "RabbitMQ Runtime Specifics"

    local namespace="infrastructure"
    local selector="app=rabbitmq"
    local label="rabbitmq"
    local container="rabbitmq"
    local pod

    pod=$(require_pod "$namespace" "$selector" "$label")
    assert_pod_fs_group "$namespace" "$pod" "$label" "999"
    assert_container_user_group "$namespace" "$pod" "$container" "$label" "999" "999"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "rabbitmq-data" "/var/lib/rabbitmq"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "rabbitmq-config" "/etc/rabbitmq/rabbitmq.conf"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "rabbitmq-bootstrap" "/etc/rabbitmq/definitions"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "rabbitmq-tls" "/tls"
    assert_container_mount_path "$namespace" "$pod" "$container" "$label" "rabbitmq-ca" "/tls-ca"
    assert_container_mount_read_only_true "$namespace" "$pod" "$container" "$label" "rabbitmq-config"
    assert_container_mount_read_only_true "$namespace" "$pod" "$container" "$label" "rabbitmq-bootstrap"
    assert_container_mount_read_only_true "$namespace" "$pod" "$container" "$label" "rabbitmq-tls"
    assert_container_mount_read_only_true "$namespace" "$pod" "$container" "$label" "rabbitmq-ca"
    assert_persistent_volume_claim "$namespace" "$pod" "$label" "rabbitmq-data"
}

verify_restricted_psa_smoke() {
    section "Restricted PSA Meshed Smoke Test"

    TEMP_NAMESPACE="ba-phase5-psa-$(date +%s)"
    cat <<MANIFEST | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: ${TEMP_NAMESPACE}
  labels:
    istio-injection: enabled
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.32
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.32
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.32
MANIFEST

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
      image: ${PROBE_IMAGE}
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
      image: ${PROBE_IMAGE}
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
    require_host_command timeout
    printf '  Using per-script regression timeout: %s\n' "$REGRESSION_TIMEOUT"

    run_regression_verifier() {
        local label="$1"
        local script_path="$2"
        local exit_code=0

        if timeout --foreground --kill-after=10s "$REGRESSION_TIMEOUT" "$script_path"; then
            pass "${label} still passes after runtime hardening"
            return
        fi

        exit_code=$?
        if [[ "$exit_code" -eq 124 || "$exit_code" -eq 137 ]]; then
            fail "${label} timed out after ${REGRESSION_TIMEOUT}"
        else
            fail "${label} failed after runtime hardening"
        fi
    }

    run_regression_verifier "Credential isolation verification" "${SCRIPT_DIR}/verify-phase-1-credentials.sh"
    run_regression_verifier "NetworkPolicy verification" "${SCRIPT_DIR}/verify-phase-2-network-policies.sh"
    run_regression_verifier "Istio ingress verification" "${SCRIPT_DIR}/verify-phase-3-istio-ingress.sh"
    run_regression_verifier "Transport-encryption verification" "${SCRIPT_DIR}/verify-phase-4-transport-encryption.sh"
}

main() {
    echo "=============================================="
    echo "  Runtime Hardening Verifier"
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
    verify_nginx_runtime
    verify_budget_analyzer_web_runtime
    verify_redis_runtime
    verify_postgresql_runtime
    verify_rabbitmq_runtime
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
