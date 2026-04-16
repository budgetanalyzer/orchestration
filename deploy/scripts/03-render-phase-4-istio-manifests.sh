#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR="${PHASE4_RENDER_ROOT}"

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/03-render-phase-4-istio-manifests.sh [--output-dir DIR]

Renders the Phase 4 production ingress ConfigMap and Gateway manifests into
tmp/phase-4/ for operator review.

The rendered Gateway is intentionally HTTP-only in Phase 4 and keeps a single
wildcard listener so the checked-in localhost HTTPRoutes still attach until the
production host-specific HTTPRoutes are rendered in lockstep in a later phase.
Phase 11 adds the public TLS listener and certificate secret wiring after
certificate issuance is in place.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="${2:-}"
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

mkdir -p "${OUTPUT_DIR}"

phase4_render_template \
    "$(phase4_repo_path "deploy/manifests/phase-4/ingress-gateway-config.yaml.template")" \
    "${OUTPUT_DIR}/ingress-gateway-config.yaml"

phase4_render_template \
    "$(phase4_repo_path "deploy/manifests/phase-4/istio-gateway.yaml.template")" \
    "${OUTPUT_DIR}/istio-gateway.yaml"

phase4_info "rendered Phase 4 ingress manifests into ${OUTPUT_DIR}"
phase4_info "review these files before running deploy/scripts/04-install-istio.sh"
