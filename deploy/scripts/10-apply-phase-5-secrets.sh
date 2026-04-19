#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PHASE5_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/phase-5"
readonly PHASE5_RENDER_ROOT

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/10-apply-phase-5-secrets.sh [--output-dir DIR]

Refreshes the reviewed Phase 5 render output and applies:
  - ClusterSecretStore/budget-analyzer-oci-vault
  - ConfigMap/session-gateway-idp-config
  - the full ExternalSecret set for default and infrastructure
EOF
}

require_rendered_manifests() {
    local output_dir="$1"

    [[ -f "${output_dir}/cluster-secret-store.yaml" ]] || phase4_die "missing ${output_dir}/cluster-secret-store.yaml; run deploy/scripts/09-render-phase-5-secrets.sh first"
    [[ -f "${output_dir}/external-secrets.yaml" ]] || phase4_die "missing ${output_dir}/external-secrets.yaml; run deploy/scripts/09-render-phase-5-secrets.sh first"
    [[ -f "${output_dir}/session-gateway-idp-config.yaml" ]] || phase4_die "missing ${output_dir}/session-gateway-idp-config.yaml; run deploy/scripts/09-render-phase-5-secrets.sh first"
}

main() {
    local output_dir="${PHASE5_RENDER_ROOT}"

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

    phase4_load_instance_env
    phase4_require_commands kubectl
    phase4_require_cluster_access

    phase4_info "refreshing the rendered Phase 5 secrets artifacts"
    "${SCRIPT_DIR}/09-render-phase-5-secrets.sh" --output-dir "${output_dir}" >/dev/null
    require_rendered_manifests "${output_dir}"

    phase4_info "applying ClusterSecretStore"
    kubectl apply -f "${output_dir}/cluster-secret-store.yaml"

    phase4_info "applying production session-gateway IDP config"
    kubectl apply -f "${output_dir}/session-gateway-idp-config.yaml"

    phase4_info "applying ExternalSecret resources"
    kubectl apply -f "${output_dir}/external-secrets.yaml"

    phase4_warn "if IAM propagation is still incomplete, ClusterSecretStore or ExternalSecret status may stay not-ready until OCI finishes applying the dynamic-group and policy changes"
    phase4_info "current Phase 5 secret-sync snapshot"
    kubectl get clustersecretstore budget-analyzer-oci-vault
    kubectl get externalsecret -A
    kubectl get configmap -n default session-gateway-idp-config
}

main "$@"
