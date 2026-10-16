#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/render-common.sh
source "${SCRIPT_DIR}/../lib/render-common.sh"

DEFAULT_OUTPUT_DIR="${PRODUCTION_REPO_ROOT}/tmp/observability"
readonly DEFAULT_OUTPUT_DIR

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/render/observability.sh [--output-dir DIR]

Renders the internal-only Jaeger and Kiali production reference without an
instance file, kubeconfig, namespace lookup, or Kubernetes API. Helm resolves
the pinned chart from its configured repository and performs a client-side
template render.
EOF
}

main() {
    local output_dir="${DEFAULT_OUTPUT_DIR}"
    local monitoring_dir

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir)
                output_dir="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                production_render_die "unknown option: $1"
                ;;
        esac
    done

    [[ -n "${output_dir}" ]] || production_render_die "--output-dir requires a non-empty value"
    production_render_require_commands helm install
    monitoring_dir="$(production_repo_path "kubernetes/monitoring")"
    mkdir -p "${output_dir}"

    install -m 0644 "${monitoring_dir}/namespace.yaml" "${output_dir}/monitoring-namespace.yaml"
    install -m 0644 "${monitoring_dir}/jaeger/configmap.yaml" "${output_dir}/jaeger-configmap.yaml"
    install -m 0644 "${monitoring_dir}/jaeger/pvc.yaml" "${output_dir}/jaeger-pvc.yaml"
    install -m 0644 "${monitoring_dir}/jaeger/deployment.yaml" "${output_dir}/jaeger-deployment.yaml"
    install -m 0644 "${monitoring_dir}/jaeger/services.yaml" "${output_dir}/jaeger-services.yaml"

    helm template kiali kiali-server \
        --repo "${PRODUCTION_KIALI_HELM_REPO_URL}" \
        --namespace monitoring \
        --version "${PRODUCTION_KIALI_CHART_VERSION}" \
        --kube-version "${PRODUCTION_KUBERNETES_VERSION}" \
        --values "${monitoring_dir}/kiali-values.yaml" \
        --post-renderer "$(production_repo_path "scripts/ops/post-render-kiali-server.sh")" \
        > "${output_dir}/kiali.yaml"

    [[ -s "${output_dir}/kiali.yaml" ]] || production_render_die "rendered Kiali reference is empty"
    production_render_info "rendered observability reference into ${output_dir}"
}

main "$@"
