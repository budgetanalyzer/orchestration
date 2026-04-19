#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/lib/common.sh"

PHASE6_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/phase-6"
readonly PHASE6_RENDER_ROOT
LOCKED_DEMO_DOMAIN="demo.budgetanalyzer.org"
readonly LOCKED_DEMO_DOMAIN
LOCKED_GRAFANA_DOMAIN="grafana.budgetanalyzer.org"
readonly LOCKED_GRAFANA_DOMAIN

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/13-render-phase-6-production-manifests.sh [--output-dir DIR]

Renders the reviewed production gateway routes, Istio ingress
policies, monitoring hostname override, and Istio egress manifests into a
local output directory.

By default the render output goes to tmp/phase-6/ under the repo root.
EOF
}

phase6_render_output_dir() {
    mkdir -p "${PHASE6_RENDER_ROOT}"
    printf '%s\n' "${PHASE6_RENDER_ROOT}"
}

main() {
    local output_dir
    output_dir="$(phase6_render_output_dir)"

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
    phase4_require_env_vars AUTH0_ISSUER_URI DEMO_DOMAIN GRAFANA_DOMAIN

    [[ "${DEMO_DOMAIN}" == "${LOCKED_DEMO_DOMAIN}" ]] || phase4_die \
        "DEMO_DOMAIN=${DEMO_DOMAIN} does not match the locked production hostname ${LOCKED_DEMO_DOMAIN}"
    [[ "${GRAFANA_DOMAIN}" == "${LOCKED_GRAFANA_DOMAIN}" ]] || phase4_die \
        "GRAFANA_DOMAIN=${GRAFANA_DOMAIN} does not match the locked monitoring hostname ${LOCKED_GRAFANA_DOMAIN}"

    mkdir -p "${output_dir}"

    kubectl kustomize "$(phase4_repo_path "kubernetes/production/gateway-routes")" \
        --load-restrictor=LoadRestrictionsNone > "${output_dir}/gateway-routes.yaml"

    kubectl kustomize "$(phase4_repo_path "kubernetes/production/istio-ingress-policies")" \
        --load-restrictor=LoadRestrictionsNone > "${output_dir}/istio-ingress-policies.yaml"

    install -m 0644 \
        "$(phase4_repo_path "kubernetes/production/monitoring/prometheus-stack-values.override.yaml")" \
        "${output_dir}/prometheus-stack-values.override.yaml"

    "$(phase4_repo_path "scripts/ops/render-istio-egress-config.sh")" \
        --auth0-issuer-uri "${AUTH0_ISSUER_URI}" > "${output_dir}/istio-egress.yaml"

    if grep -R -E -n 'budgetanalyzer\.localhost|auth0-issuer\.placeholder\.invalid' "${output_dir}" >/dev/null; then
        phase4_die "rendered production output still contains localhost or placeholder Auth0 values"
    fi

    phase4_info "rendered production artifacts into ${output_dir}"
    phase4_info "review ${output_dir}/gateway-routes.yaml, ${output_dir}/istio-ingress-policies.yaml, ${output_dir}/prometheus-stack-values.override.yaml, and ${output_dir}/istio-egress.yaml before any live apply"
}

main "$@"
