#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PHASE5_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/phase-5"
readonly PHASE5_RENDER_ROOT

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/09-render-phase-5-secrets.sh [--output-dir DIR]

Renders the reviewed Phase 5 non-secret artifacts into a local output
directory:
  - ClusterSecretStore for OCI Vault instance-principal access
  - ExternalSecret resources for the exact Phase 5 native Secret contract
  - production ConfigMap/session-gateway-idp-config

By default the render output goes to tmp/phase-5/ under the repo root.
EOF
}

phase5_render_output_dir() {
    mkdir -p "${PHASE5_RENDER_ROOT}"
    printf '%s\n' "${PHASE5_RENDER_ROOT}"
}

main() {
    local output_dir
    output_dir="$(phase5_render_output_dir)"

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
    phase4_require_env_vars \
        OCI_REGION \
        OCI_COMPARTMENT_OCID \
        OCI_VAULT_OCID \
        AUTH0_CLIENT_ID \
        AUTH0_ISSUER_URI \
        IDP_AUDIENCE \
        IDP_LOGOUT_RETURN_TO

    mkdir -p "${output_dir}"

    phase4_render_template \
        "$(phase4_repo_path "deploy/manifests/phase-5/cluster-secret-store.yaml.template")" \
        "${output_dir}/cluster-secret-store.yaml" \
        "OCI_REGION=${OCI_REGION}" \
        "OCI_COMPARTMENT_OCID=${OCI_COMPARTMENT_OCID}" \
        "OCI_VAULT_OCID=${OCI_VAULT_OCID}"

    install -m 0644 \
        "$(phase4_repo_path "deploy/manifests/phase-5/external-secrets.yaml")" \
        "${output_dir}/external-secrets.yaml"

    phase4_render_template \
        "$(phase4_repo_path "deploy/manifests/phase-5/session-gateway-idp-config.yaml.template")" \
        "${output_dir}/session-gateway-idp-config.yaml" \
        "AUTH0_CLIENT_ID=${AUTH0_CLIENT_ID}" \
        "AUTH0_ISSUER_URI=${AUTH0_ISSUER_URI}" \
        "IDP_AUDIENCE=${IDP_AUDIENCE}" \
        "IDP_LOGOUT_RETURN_TO=${IDP_LOGOUT_RETURN_TO}"

    phase4_info "rendered Phase 5 secrets artifacts into ${output_dir}"
}

main "$@"
