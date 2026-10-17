#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/../lib/common.sh"

PRODUCTION_DEPLOYMENT_MANIFEST="$(phase4_repo_path "kubernetes/production/apps/deployment-manifest.yaml")"
DEPLOY_OCI_RELEASE_LIB="${SCRIPT_DIR}/../lib/deploy-oci-release.sh"
readonly PRODUCTION_DEPLOYMENT_MANIFEST
readonly DEPLOY_OCI_RELEASE_LIB

declare -a DEPLOY_ARGS=()

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/release/deploy-current-oci-manifest.sh [options]

Options:
  --kubeconfig PATH  Use an explicit OCI host kubeconfig.
  -h, --help         Show this help.

Applies the checked-in OCI production desired state from
kubernetes/production/apps/deployment-manifest.yaml, waits only for changed
managed application rollouts, and verifies live pod metadata against that
manifest. It does not inspect sibling source repositories, create tags, build
images, push images, or mutate the production manifest.
EOF
}

die() {
    phase4_die "$1"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --kubeconfig)
                [[ -n "${2:-}" ]] || die "missing value for --kubeconfig"
                DEPLOY_ARGS+=("--kubeconfig" "$2")
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"

    [[ -f "${PRODUCTION_DEPLOYMENT_MANIFEST}" ]] || \
        die "missing checked-in production deployment manifest: ${PRODUCTION_DEPLOYMENT_MANIFEST}"
    [[ -f "${DEPLOY_OCI_RELEASE_LIB}" ]] || die "missing release deploy library: ${DEPLOY_OCI_RELEASE_LIB}"

    # shellcheck source=deploy/scripts/lib/deploy-oci-release.sh
    # shellcheck disable=SC1091 # Library path is resolved from SCRIPT_DIR at runtime.
    source "${DEPLOY_OCI_RELEASE_LIB}"
    deploy_oci_release_main \
        --deployment-manifest "${PRODUCTION_DEPLOYMENT_MANIFEST}" \
        "${DEPLOY_ARGS[@]}"
}

main "$@"
