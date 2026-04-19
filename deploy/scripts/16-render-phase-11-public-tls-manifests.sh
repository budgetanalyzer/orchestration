#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/lib/common.sh"

PHASE11_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/phase-11"
readonly PHASE11_RENDER_ROOT
PHASE11_LOCKED_DEMO_DOMAIN="demo.budgetanalyzer.org"
readonly PHASE11_LOCKED_DEMO_DOMAIN

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/16-render-phase-11-public-tls-manifests.sh [--output-dir DIR]

Renders the reviewed public TLS manifests into tmp/phase-11/ for
operator review before apply.

This render path intentionally stays on the current production hostname
contract:
  - demo.budgetanalyzer.org

The public TLS cutover is intentionally app-only. It does not publish
Grafana, Kiali, or Jaeger.

If you want to move production to the apex domain or another hostname, change
the reviewed production and public TLS contract first instead of editing the live
manifests ad hoc.
EOF
}

phase11_render_output_dir() {
    mkdir -p "${PHASE11_RENDER_ROOT}"
    printf '%s\n' "${PHASE11_RENDER_ROOT}"
}

main() {
    local output_dir
    output_dir="$(phase11_render_output_dir)"

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
    phase4_require_env_vars LETSENCRYPT_EMAIL DEMO_DOMAIN

    [[ "${DEMO_DOMAIN}" == "${PHASE11_LOCKED_DEMO_DOMAIN}" ]] || phase4_die \
        "DEMO_DOMAIN=${DEMO_DOMAIN} does not match the locked public TLS application hostname ${PHASE11_LOCKED_DEMO_DOMAIN}"

    mkdir -p "${output_dir}"

    phase4_render_template \
        "$(phase4_repo_path "deploy/manifests/phase-11/cluster-issuer.yaml.template")" \
        "${output_dir}/cluster-issuer.yaml" \
        "LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}"

    phase4_render_template \
        "$(phase4_repo_path "deploy/manifests/phase-11/public-certificate.yaml.template")" \
        "${output_dir}/public-certificate.yaml" \
        "DEMO_DOMAIN=${DEMO_DOMAIN}"

    phase4_render_template \
        "$(phase4_repo_path "deploy/manifests/phase-11/reference-grant.yaml.template")" \
        "${output_dir}/reference-grant.yaml"

    phase4_render_template \
        "$(phase4_repo_path "deploy/manifests/phase-11/ingress-gateway-config.yaml.template")" \
        "${output_dir}/ingress-gateway-config.yaml"

    phase4_render_template \
        "$(phase4_repo_path "deploy/manifests/phase-11/istio-gateway.yaml.template")" \
        "${output_dir}/istio-gateway.yaml" \
        "DEMO_DOMAIN=${DEMO_DOMAIN}"

    phase4_info "rendered public TLS manifests into ${output_dir}"
    phase4_info "review ${output_dir}/cluster-issuer.yaml, ${output_dir}/public-certificate.yaml, ${output_dir}/reference-grant.yaml, ${output_dir}/ingress-gateway-config.yaml, and ${output_dir}/istio-gateway.yaml before apply"
}

main "$@"
