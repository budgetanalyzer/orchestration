#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/render-common.sh
# shellcheck disable=SC1091 # Render helper is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/../lib/render-common.sh"

DEFAULT_OUTPUT_DIR="${PRODUCTION_REPO_ROOT}/tmp/production-routes"
REFERENCE_AUTH0_ISSUER_URI="https://auth.budgetanalyzer.org/"
readonly DEFAULT_OUTPUT_DIR
readonly REFERENCE_AUTH0_ISSUER_URI

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/render/production-routes.sh [--output-dir DIR]

Renders the provider-neutral production-reference routes, ingress policies,
internal-only monitoring values, and egress configuration without loading an
instance file or contacting a Kubernetes cluster.

The checked-in reference retains demo.budgetanalyzer.org and
https://auth.budgetanalyzer.org/ as non-secret offline render values. A future
deployment must review and replace environment-specific publication and IDP
inputs before applying anything.
EOF
}

main() {
    local output_dir="${DEFAULT_OUTPUT_DIR}"

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
    production_render_require_commands kubectl install
    mkdir -p "${output_dir}"

    kubectl kustomize "$(production_repo_path "kubernetes/production/gateway-routes")" \
        --load-restrictor=LoadRestrictionsNone > "${output_dir}/gateway-routes.yaml"

    kubectl kustomize "$(production_repo_path "kubernetes/production/istio-ingress-policies")" \
        --load-restrictor=LoadRestrictionsNone > "${output_dir}/istio-ingress-policies.yaml"

    kubectl kustomize "$(production_repo_path "kubernetes/production/istio")" \
        --load-restrictor=LoadRestrictionsNone > "${output_dir}/authorization-policies.yaml"

    kubectl kustomize "$(production_repo_path "kubernetes/production/istio-ingress-gateway")" \
        --load-restrictor=LoadRestrictionsNone > "${output_dir}/ingress-gateway-config.yaml"

    install -m 0644 \
        "$(production_repo_path "kubernetes/production/monitoring/prometheus-stack-values.override.yaml")" \
        "${output_dir}/prometheus-stack-values.override.yaml"

    "$(production_repo_path "scripts/ops/render-istio-egress-config.sh")" \
        --auth0-issuer-uri "${REFERENCE_AUTH0_ISSUER_URI}" > "${output_dir}/istio-egress.yaml"

    if grep -R -E -n 'budgetanalyzer\.localhost|auth0-issuer\.placeholder\.invalid' "${output_dir}" >/dev/null; then
        production_render_die "rendered production reference still contains localhost or placeholder Auth0 values"
    fi

    production_render_info "rendered route and egress reference into ${output_dir}"
}

main "$@"
