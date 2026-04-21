#!/usr/bin/env bash
# Live verification for the Prometheus Operator least-privilege posture.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OPERATOR_NAMESPACE="monitoring"
OPERATOR_SERVICE_ACCOUNT="prometheus-stack-kube-prom-operator"
OPERATOR_SUBJECT="system:serviceaccount:${OPERATOR_NAMESPACE}:${OPERATOR_SERVICE_ACCOUNT}"
EVIDENCE_DIR="${REPO_DIR}/tmp/prometheus-operator-least-privilege"
KIALI_OUTPUT_DIR="${REPO_DIR}/tmp/kiali-triage"

PASSED=0
FAILED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-prometheus-operator-least-privilege.sh [options]

Runs the full Phase 4 Prometheus Operator least-privilege verification set:
the rendered-manifest verifier, live operator RBAC/object checks, positive and
negative kubectl auth can-i proofs, the monitoring runtime verifier, and Kiali
triage with persisted output.

Options:
  --evidence-dir PATH       Directory for the permission matrix and summary.
                            Default: tmp/prometheus-operator-least-privilege
  --kiali-output-dir PATH   Directory for triage-kiali-findings.sh artifacts.
                            Default: tmp/kiali-triage
  -h, --help                Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --evidence-dir)
            EVIDENCE_DIR="${2:-}"
            shift 2
            ;;
        --kiali-output-dir)
            KIALI_OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "${EVIDENCE_DIR}" != /* ]]; then
    EVIDENCE_DIR="${REPO_DIR}/${EVIDENCE_DIR}"
fi

if [[ "${KIALI_OUTPUT_DIR}" != /* ]]; then
    KIALI_OUTPUT_DIR="${REPO_DIR}/${KIALI_OUTPUT_DIR}"
fi

mkdir -p "${EVIDENCE_DIR}" "${KIALI_OUTPUT_DIR}"

MATRIX_FILE="${EVIDENCE_DIR}/can-i-matrix.tsv"
SUMMARY_FILE="${EVIDENCE_DIR}/summary.md"

section() {
    printf '\n=== %s ===\n' "$1"
}

pass() {
    printf '  [PASS] %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail_check() {
    printf '  [FAIL] %s\n' "$1" >&2
    FAILED=$((FAILED + 1))
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_cluster_access() {
    kubectl get namespace "${OPERATOR_NAMESPACE}" >/dev/null 2>&1 \
        || {
            printf 'ERROR: cannot reach Kubernetes API or namespace %s\n' "${OPERATOR_NAMESPACE}" >&2
            exit 1
        }

    kubectl get -n "${OPERATOR_NAMESPACE}" "serviceaccount/${OPERATOR_SERVICE_ACCOUNT}" >/dev/null 2>&1 \
        || {
            printf 'ERROR: missing service account %s/%s\n' \
                "${OPERATOR_NAMESPACE}" "${OPERATOR_SERVICE_ACCOUNT}" >&2
            exit 1
        }
}

check_object_present() {
    local kind="$1"
    local name="$2"
    local namespace="${3:-}"

    if [[ -n "${namespace}" ]]; then
        if kubectl get "${kind}" -n "${namespace}" "${name}" >/dev/null 2>&1; then
            pass "Found ${kind}/${name} in ${namespace}"
        else
            fail_check "Missing ${kind}/${name} in ${namespace}"
        fi
    else
        if kubectl get "${kind}" "${name}" >/dev/null 2>&1; then
            pass "Found ${kind}/${name}"
        else
            fail_check "Missing ${kind}/${name}"
        fi
    fi
}

check_object_absent() {
    local kind="$1"
    local name="$2"

    if kubectl get "${kind}" "${name}" >/dev/null 2>&1; then
        fail_check "Unexpected live ${kind}/${name} is still present"
    else
        pass "Live ${kind}/${name} is absent"
    fi
}

run_can_i_check() {
    local expectation="$1"
    local scope="$2"
    local verb="$3"
    local resource="$4"
    local reason="$5"
    local allowed
    local status=0

    set +e
    if [[ "${scope}" == "cluster" ]]; then
        allowed="$(kubectl auth can-i --as="${OPERATOR_SUBJECT}" "${verb}" "${resource}")"
    else
        allowed="$(kubectl auth can-i --as="${OPERATOR_SUBJECT}" --namespace "${scope}" "${verb}" "${resource}")"
    fi
    status=$?
    set -e

    if (( status != 0 && status != 1 )); then
        fail_check "${scope} ${verb} ${resource} -> kubectl auth can-i failed (${reason})"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${expectation}" "${scope}" "${verb}" "${resource}" "error" "${reason}" \
            >> "${MATRIX_FILE}"
        return
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${expectation}" "${scope}" "${verb}" "${resource}" "${allowed}" "${reason}" \
        >> "${MATRIX_FILE}"

    if [[ "${allowed}" == "${expectation}" ]]; then
        pass "${scope} ${verb} ${resource} -> ${allowed} (${reason})"
    else
        fail_check "${scope} ${verb} ${resource} -> ${allowed}, expected ${expectation} (${reason})"
    fi
}

write_summary() {
    cat > "${SUMMARY_FILE}" <<EOF
# Prometheus Operator Least-Privilege Phase 4 Verification

- Service account: \`${OPERATOR_SUBJECT}\`
- Permission matrix: \`${MATRIX_FILE#"${REPO_DIR}"/}\`
- Kiali triage output: \`${KIALI_OUTPUT_DIR#"${REPO_DIR}"/}\`
- Passed checks: \`${PASSED}\`
- Failed checks: \`${FAILED}\`
EOF
}

require_command kubectl

section "Checking cluster access"
require_cluster_access
pass "Cluster access and operator service account are available"

section "Rendering and inspecting the monitoring stack"
"${SCRIPT_DIR}/verify-monitoring-rendered-manifests.sh"

section "Checking live operator RBAC objects"
check_object_absent clusterrole prometheus-stack-kube-prom-operator
check_object_absent clusterrolebinding prometheus-stack-kube-prom-operator
check_object_present clusterrole prometheus-stack-kube-prom-operator-cluster-read
check_object_present clusterrolebinding prometheus-stack-kube-prom-operator-cluster-read
check_object_present role prometheus-stack-kube-prom-operator-monitoring monitoring
check_object_present rolebinding prometheus-stack-kube-prom-operator-monitoring monitoring
check_object_present role prometheus-stack-kube-prom-operator-default-read default
check_object_present rolebinding prometheus-stack-kube-prom-operator-default-read default

section "Running operator permission proofs"
printf 'expected\tscope\tverb\tresource\tallowed\treason\n' > "${MATRIX_FILE}"

while IFS='|' read -r expectation scope verb resource reason; do
    [[ -n "${expectation}" ]] || continue
    run_can_i_check "${expectation}" "${scope}" "${verb}" "${resource}" "${reason}"
done <<'EOF'
yes|monitoring|get|servicemonitors.monitoring.coreos.com|operator reads monitoring CRs in the owned namespace
yes|monitoring|get|secrets|operator reads Prometheus config secrets in monitoring
yes|monitoring|create|services|operator reconciles owned Services in monitoring
yes|monitoring|create|statefulsets.apps|operator reconciles Prometheus StatefulSets in monitoring
yes|monitoring|delete|endpointslices.discovery.k8s.io|operator cleans up owned EndpointSlices in monitoring
yes|default|get|servicemonitors.monitoring.coreos.com|operator reads ServiceMonitors from default
yes|default|get|prometheusrules.monitoring.coreos.com|operator reads PrometheusRules from default
yes|cluster|list|namespaces|operator performs namespace discovery
yes|cluster|watch|nodes|operator watches nodes for reconciliation inputs
yes|cluster|get|storageclasses.storage.k8s.io|operator reads StorageClasses
yes|cluster|watch|ingresses.networking.k8s.io|operator watches ingresses
no|default|get|secrets|operator must not read default namespace secrets
no|default|create|services|operator must not create Services outside monitoring
no|default|create|statefulsets.apps|operator must not create StatefulSets outside monitoring
no|default|delete|endpointslices.discovery.k8s.io|operator must not delete EndpointSlices outside monitoring
no|infrastructure|get|servicemonitors.monitoring.coreos.com|operator must not read monitoring CRs in unrelated namespaces
no|infrastructure|get|secrets|operator must not read unrelated namespace secrets
no|infrastructure|create|services|operator must not mutate Services in unrelated namespaces
no|infrastructure|delete|pods|operator must not delete pods in unrelated namespaces
no|istio-system|get|secrets|operator must not read control-plane secrets
no|istio-system|create|services|operator must not mutate control-plane Services
EOF

section "Verifying runtime scrape and Kiali health"
"${SCRIPT_DIR}/verify-monitoring-runtime.sh"

section "Capturing Kiali findings"
"${REPO_DIR}/scripts/ops/triage-kiali-findings.sh" --output-dir "${KIALI_OUTPUT_DIR}"
pass "Captured Kiali triage artifacts in ${KIALI_OUTPUT_DIR}"

write_summary

printf '\nEvidence written to %s\n' "${EVIDENCE_DIR}"
printf 'Kiali artifacts written to %s\n' "${KIALI_OUTPUT_DIR}"

if (( FAILED > 0 )); then
    printf '\nPrometheus Operator least-privilege verification failed: %d check(s) failed.\n' "${FAILED}" >&2
    exit 1
fi

printf '\nPrometheus Operator least-privilege verification passed: %d check(s).\n' "${PASSED}"
