#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/render-common.sh
# shellcheck disable=SC1091 # Render helper is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/../lib/render-common.sh"

DEFAULT_OUTPUT_DIR="${PRODUCTION_REPO_ROOT}/tmp/observability"
KIALI_RELEASE_NAMESPACE="monitoring"
KIALI_ACCESSIBLE_NAMESPACES=(
    default
    monitoring
    istio-system
    istio-ingress
    istio-egress
)
OBSERVABILITY_RENDER_TEMP_DIR=""
readonly DEFAULT_OUTPUT_DIR
readonly KIALI_RELEASE_NAMESPACE
readonly -a KIALI_ACCESSIBLE_NAMESPACES

cleanup() {
    if [[ -n "${OBSERVABILITY_RENDER_TEMP_DIR}" ]]; then
        rm -rf -- "${OBSERVABILITY_RENDER_TEMP_DIR}"
    fi
}

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/render/observability.sh [--output-dir DIR]

Renders the internal-only Jaeger and Kiali production reference without an
instance file, kubeconfig, namespace lookup, or Kubernetes API. Helm resolves
the pinned chart from its configured repository and performs a client-side
template render. The render deterministically includes Kiali Role/RoleBinding
resources for every approved discovery namespace.
EOF
}

append_kiali_namespace_rbac() {
    local rendered_file="$1"
    local target_namespace="$2"
    local resource_kind

    for resource_kind in Role RoleBinding; do
        awk \
            -v resource_kind="${resource_kind}" \
            -v source_namespace="${KIALI_RELEASE_NAMESPACE}" \
            -v target_namespace="${target_namespace}" '
            function reset_document(    line_number) {
                for (line_number in document_lines) {
                    delete document_lines[line_number]
                }
                line_count = 0
                kind = ""
                metadata_name = ""
                metadata_namespace = ""
                metadata_namespace_line = 0
                in_metadata = 0
            }

            function finish_document(    line_number) {
                if (kind == resource_kind &&
                    metadata_name == "kiali-viewer" &&
                    metadata_namespace == source_namespace) {
                    matches++
                    print "---"
                    for (line_number = 1; line_number <= line_count; line_number++) {
                        if (line_number == metadata_namespace_line) {
                            print "  namespace: " target_namespace
                        } else {
                            print document_lines[line_number]
                        }
                    }
                }
                reset_document()
            }

            BEGIN {
                reset_document()
            }

            /^---[[:space:]]*$/ {
                finish_document()
                next
            }

            {
                document_lines[++line_count] = $0

                if ($0 ~ /^kind:[[:space:]]*/) {
                    kind = $0
                    sub(/^kind:[[:space:]]*/, "", kind)
                }

                if ($0 == "metadata:") {
                    in_metadata = 1
                    next
                }

                if (in_metadata && $0 ~ /^[^[:space:]]/) {
                    in_metadata = 0
                }

                if (in_metadata && $0 ~ /^  name:[[:space:]]*/) {
                    metadata_name = $0
                    sub(/^  name:[[:space:]]*/, "", metadata_name)
                }

                if (in_metadata && $0 ~ /^  namespace:[[:space:]]*/) {
                    metadata_namespace = $0
                    sub(/^  namespace:[[:space:]]*/, "", metadata_namespace)
                    gsub(/^"|"$/, "", metadata_namespace)
                    metadata_namespace_line = line_count
                }
            }

            END {
                finish_document()
                if (matches != 1) {
                    exit 1
                }
            }
        ' "${rendered_file}" || return 1
    done
}

main() {
    local output_dir="${DEFAULT_OUTPUT_DIR}"
    local monitoring_dir
    local kiali_chart_render
    local namespace

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
    OBSERVABILITY_RENDER_TEMP_DIR="$(mktemp -d)"
    trap cleanup EXIT
    kiali_chart_render="${OBSERVABILITY_RENDER_TEMP_DIR}/kiali-chart.yaml"

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
        > "${kiali_chart_render}"

    [[ -s "${kiali_chart_render}" ]] || production_render_die "rendered Kiali chart output is empty"
    install -m 0644 "${kiali_chart_render}" "${output_dir}/kiali.yaml"

    # The chart discovers namespaces with Helm lookup during install/upgrade.
    # Client-side helm template cannot perform that lookup, so derive the
    # missing namespace RBAC from the chart-rendered release-namespace objects.
    for namespace in "${KIALI_ACCESSIBLE_NAMESPACES[@]}"; do
        if [[ "${namespace}" == "${KIALI_RELEASE_NAMESPACE}" ]]; then
            continue
        fi
        append_kiali_namespace_rbac "${kiali_chart_render}" "${namespace}" \
            >> "${output_dir}/kiali.yaml" || \
            production_render_die "could not derive Kiali RBAC for namespace ${namespace}"
    done

    [[ -s "${output_dir}/kiali.yaml" ]] || production_render_die "rendered Kiali reference is empty"
    production_render_info "rendered observability reference into ${output_dir}"
}

main "$@"
