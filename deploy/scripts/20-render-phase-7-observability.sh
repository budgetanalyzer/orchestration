#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
MONITORING_NAMESPACE_FILE="$(phase4_repo_path "kubernetes/monitoring/namespace.yaml")"
readonly MONITORING_NAMESPACE_FILE
JAEGER_CONFIGMAP_FILE="$(phase4_repo_path "kubernetes/monitoring/jaeger/configmap.yaml")"
readonly JAEGER_CONFIGMAP_FILE
JAEGER_PVC_FILE="$(phase4_repo_path "kubernetes/monitoring/jaeger/pvc.yaml")"
readonly JAEGER_PVC_FILE
JAEGER_DEPLOYMENT_FILE="$(phase4_repo_path "kubernetes/monitoring/jaeger/deployment.yaml")"
readonly JAEGER_DEPLOYMENT_FILE
JAEGER_SERVICES_FILE="$(phase4_repo_path "kubernetes/monitoring/jaeger/services.yaml")"
readonly JAEGER_SERVICES_FILE
KIALI_VALUES_FILE="$(phase4_repo_path "kubernetes/monitoring/kiali-values.yaml")"
readonly KIALI_VALUES_FILE
KIALI_POST_RENDERER="$(phase4_repo_path "scripts/ops/post-render-kiali-server.sh")"
readonly KIALI_POST_RENDERER

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/20-render-phase-7-observability.sh [--output-dir DIR]

Renders the reviewed production Jaeger and Kiali observability artifacts for
operator review. The Kiali render uses a Helm server-side dry run against the
current cluster so namespace-scoped RBAC matches the live install footprint.

By default the render output goes to tmp/phase-7-observability/ under the repo
root.
EOF
}

prepare_cluster_context() {
    if [[ -f "${PHASE4_INSTANCE_ENV_FILE}" ]]; then
        phase4_load_instance_env
    else
        phase4_use_default_kubeconfig
    fi

    phase4_require_cluster_access
}

require_namespace() {
    local namespace="$1"

    kubectl get namespace "${namespace}" >/dev/null 2>&1 || \
        phase4_die "required namespace is missing: ${namespace}"
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
    phase4_require_commands helm kubectl install
    prepare_cluster_context

    [[ -f "${MONITORING_NAMESPACE_FILE}" ]] || phase4_die "missing monitoring namespace manifest: ${MONITORING_NAMESPACE_FILE}"
    [[ -f "${JAEGER_CONFIGMAP_FILE}" ]] || phase4_die "missing Jaeger ConfigMap manifest: ${JAEGER_CONFIGMAP_FILE}"
    [[ -f "${JAEGER_PVC_FILE}" ]] || phase4_die "missing Jaeger PVC manifest: ${JAEGER_PVC_FILE}"
    [[ -f "${JAEGER_DEPLOYMENT_FILE}" ]] || phase4_die "missing Jaeger Deployment manifest: ${JAEGER_DEPLOYMENT_FILE}"
    [[ -f "${JAEGER_SERVICES_FILE}" ]] || phase4_die "missing Jaeger Services manifest: ${JAEGER_SERVICES_FILE}"
    [[ -f "${KIALI_VALUES_FILE}" ]] || phase4_die "missing Kiali values file: ${KIALI_VALUES_FILE}"
    [[ -x "${KIALI_POST_RENDERER}" ]] || phase4_die "missing executable Kiali post-renderer: ${KIALI_POST_RENDERER}"

    require_namespace monitoring
    require_namespace istio-system
    require_namespace istio-ingress
    require_namespace istio-egress

    mkdir -p "${output_dir}"

    install -m 0644 "${MONITORING_NAMESPACE_FILE}" "${output_dir}/monitoring-namespace.yaml"
    install -m 0644 "${JAEGER_CONFIGMAP_FILE}" "${output_dir}/jaeger-configmap.yaml"
    install -m 0644 "${JAEGER_PVC_FILE}" "${output_dir}/jaeger-pvc.yaml"
    install -m 0644 "${JAEGER_DEPLOYMENT_FILE}" "${output_dir}/jaeger-deployment.yaml"
    install -m 0644 "${JAEGER_SERVICES_FILE}" "${output_dir}/jaeger-services.yaml"

    phase4_info "updating Helm repo kiali"
    phase4_ensure_helm_repo kiali "${PHASE7_KIALI_HELM_REPO_URL}"
    helm repo update kiali >/dev/null

    phase4_info "rendering Kiali with Helm server-side dry run"
    helm template "${KIALI_RELEASE_NAME}" "${KIALI_CHART_NAME}" \
        --namespace "${MONITORING_NAMESPACE}" \
        --version "${PHASE7_KIALI_CHART_VERSION}" \
        --values "${KIALI_VALUES_FILE}" \
        --dry-run=server \
        --post-renderer "${KIALI_POST_RENDERER}" \
        > "${output_dir}/kiali.yaml"

    [[ -s "${output_dir}/kiali.yaml" ]] || phase4_die "rendered Kiali manifest is empty"

    phase4_info "rendered production observability artifacts into ${output_dir}"
    phase4_info "review ${output_dir}/monitoring-namespace.yaml, ${output_dir}/jaeger-*.yaml, and ${output_dir}/kiali.yaml before any live apply"
}

main "$@"
