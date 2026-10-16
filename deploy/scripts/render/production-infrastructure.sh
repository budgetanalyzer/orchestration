#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/render-common.sh
source "${SCRIPT_DIR}/../lib/render-common.sh"

DEFAULT_OUTPUT_DIR="${PRODUCTION_REPO_ROOT}/tmp/production-infrastructure"
readonly DEFAULT_OUTPUT_DIR

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/render/production-infrastructure.sh [--output-dir DIR]

Renders the provider-neutral production infrastructure reference with
Kustomize. The command does not load environment configuration or contact a
Kubernetes cluster. Storage classes and capacity remain deployment
prerequisites for any future hosted environment.
EOF
}

main() {
    local output_dir="${DEFAULT_OUTPUT_DIR}"
    local output_path
    local temp_output_path

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
    production_render_require_commands kubectl

    mkdir -p "${output_dir}"
    output_path="${output_dir}/infrastructure.yaml"
    temp_output_path="${output_path}.tmp"

    kubectl kustomize "$(production_repo_path "kubernetes/production/infrastructure")" \
        --load-restrictor=LoadRestrictionsNone > "${temp_output_path}"

    [[ -s "${temp_output_path}" ]] || production_render_die "rendered production infrastructure reference is empty"
    mv "${temp_output_path}" "${output_path}"
    production_render_info "rendered infrastructure reference into ${output_path}"
}

main "$@"

