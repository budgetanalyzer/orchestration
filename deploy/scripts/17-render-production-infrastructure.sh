#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_INFRASTRUCTURE_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/production-infrastructure"
readonly PRODUCTION_INFRASTRUCTURE_RENDER_ROOT
PRODUCTION_INFRASTRUCTURE_MANIFEST="infrastructure.yaml"
readonly PRODUCTION_INFRASTRUCTURE_MANIFEST

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/17-render-production-infrastructure.sh [--output-dir DIR]

Renders the reviewed production infrastructure overlay for operator review.
By default the manifest is written to:

  tmp/production-infrastructure/infrastructure.yaml

The render uses Kustomize with LoadRestrictionsNone because the production
overlay intentionally reuses the shared kubernetes/infrastructure baseline.
EOF
}

main() {
    local output_dir="${PRODUCTION_INFRASTRUCTURE_RENDER_ROOT}"
    local output_path
    local temp_output_path

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
    phase4_require_commands kubectl

    mkdir -p "${output_dir}"
    output_path="${output_dir}/${PRODUCTION_INFRASTRUCTURE_MANIFEST}"
    temp_output_path="${output_path}.tmp"

    kubectl kustomize "$(phase4_repo_path "kubernetes/production/infrastructure")" \
        --load-restrictor=LoadRestrictionsNone > "${temp_output_path}"

    [[ -s "${temp_output_path}" ]] || phase4_die "rendered production infrastructure manifest is empty"
    mv "${temp_output_path}" "${output_path}"

    phase4_info "rendered production infrastructure into ${output_path}"
    phase4_info "review ${output_path} before any live apply"
}

main "$@"
