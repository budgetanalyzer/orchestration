#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_WAIT_TIMEOUT="${PHASE7_OBSERVABILITY_HELM_WAIT_TIMEOUT:-5m}"
readonly HELM_WAIT_TIMEOUT

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PHASE7_OBSERVABILITY_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/phase-7-observability"
readonly PHASE7_OBSERVABILITY_RENDER_ROOT
MONITORING_NAMESPACE="monitoring"
readonly MONITORING_NAMESPACE
KIALI_RELEASE_NAME="kiali"
readonly KIALI_RELEASE_NAME
KIALI_CHART_NAME="kiali/kiali-server"
readonly KIALI_CHART_NAME
KIALI_VALUES_FILE="$(phase4_repo_path "kubernetes/monitoring/kiali-values.yaml")"
readonly KIALI_VALUES_FILE
KIALI_POST_RENDERER="$(phase4_repo_path "scripts/ops/post-render-kiali-server.sh")"
readonly KIALI_POST_RENDERER
PRODUCTION_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
readonly PRODUCTION_VERIFIER

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/21-apply-phase-7-observability.sh [--output-dir DIR]

Refreshes the reviewed production Jaeger/Kiali render output, applies the
shared Jaeger manifests, installs Kiali with the checked-in pinned values, and
waits for both Deployments to become ready.
EOF
}

require_namespace() {
    local namespace="$1"

    kubectl get namespace "${namespace}" >/dev/null 2>&1 || \
        phase4_die "required namespace is missing: ${namespace}"
}

require_service() {
    local namespace="$1"
    local service="$2"

    kubectl get service "${service}" -n "${namespace}" >/dev/null 2>&1 || \
        phase4_die "required Service is missing: ${namespace}/${service}"
}

assert_no_observability_httproutes() {
    local stale_routes

    stale_routes="$(
        kubectl get httproute -A \
            -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' |
        awk -F '\t' '$2 ~ /^(grafana|prometheus|kiali|jaeger)(-route)?$/'
    )"

    if [[ -n "${stale_routes}" ]]; then
        printf '%s\n' "${stale_routes}" >&2
        phase4_die "observability HTTPRoutes are still present; delete the stale public observability routes before treating the rollout as complete"
    fi
}

main() {
    local output_dir="${PHASE7_OBSERVABILITY_RENDER_ROOT}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir)
                output_dir="${2:-}"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                phase4_die "unknown option: $1"
                ;;
        esac
        shift
    done

    [[ -n "${output_dir}" ]] || phase4_die "--output-dir requires a non-empty value"

    phase4_load_instance_env
    phase4_require_commands helm kubectl
    phase4_require_cluster_access

    [[ -x "${PRODUCTION_VERIFIER}" ]] || phase4_die "missing production verifier: ${PRODUCTION_VERIFIER}"
    [[ -f "${KIALI_VALUES_FILE}" ]] || phase4_die "missing Kiali values file: ${KIALI_VALUES_FILE}"
    [[ -x "${KIALI_POST_RENDERER}" ]] || phase4_die "missing executable Kiali post-renderer: ${KIALI_POST_RENDERER}"

    phase4_info "re-running the production verifier before live observability apply"
    "${PRODUCTION_VERIFIER}"

    require_namespace monitoring
    require_namespace istio-system
    require_namespace istio-ingress
    require_namespace istio-egress
    require_service monitoring prometheus-stack-kube-prom-prometheus

    phase4_info "refreshing the reviewed production observability render output"
    "${SCRIPT_DIR}/20-render-phase-7-observability.sh" --output-dir "${output_dir}" >/dev/null

    phase4_info "applying monitoring namespace and Jaeger manifests from ${output_dir}"
    kubectl apply -f "${output_dir}/monitoring-namespace.yaml"
    kubectl apply -f "${output_dir}/jaeger-configmap.yaml"
    kubectl apply -f "${output_dir}/jaeger-pvc.yaml"
    kubectl apply -f "${output_dir}/jaeger-deployment.yaml"
    kubectl apply -f "${output_dir}/jaeger-services.yaml"

    phase4_info "waiting for Deployment/jaeger"
    kubectl rollout status deployment/jaeger -n "${MONITORING_NAMESPACE}" --timeout="${HELM_WAIT_TIMEOUT}"

    phase4_info "updating Helm repo kiali"
    phase4_ensure_helm_repo kiali "${PHASE7_KIALI_HELM_REPO_URL}"
    helm repo update kiali >/dev/null

    phase4_info "installing Kiali ${PHASE7_KIALI_CHART_VERSION} (timeout ${HELM_WAIT_TIMEOUT})"
    helm upgrade --install "${KIALI_RELEASE_NAME}" "${KIALI_CHART_NAME}" \
        --namespace "${MONITORING_NAMESPACE}" \
        --version "${PHASE7_KIALI_CHART_VERSION}" \
        --values "${KIALI_VALUES_FILE}" \
        --post-renderer "${KIALI_POST_RENDERER}" \
        --wait \
        --timeout "${HELM_WAIT_TIMEOUT}"

    phase4_info "waiting for Deployment/kiali"
    kubectl rollout status deployment/kiali -n "${MONITORING_NAMESPACE}" --timeout="${HELM_WAIT_TIMEOUT}"

    phase4_info "production observability service snapshot"
    kubectl get svc -n "${MONITORING_NAMESPACE}" jaeger-collector jaeger-query kiali

    phase4_info "negative public-exposure check"
    assert_no_observability_httproutes
}

main "$@"
