#!/usr/bin/env bash
# Render or apply Istio egress config with the Auth0 host derived from AUTH0_ISSUER_URI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DEFAULT_NAMESPACE="default"
DEFAULT_CONFIGMAP_NAME="session-gateway-idp-config"
AUTH0_CONFIG_KEY="AUTH0_ISSUER_URI"
AUTH0_HOST_PLACEHOLDER="auth0-issuer.placeholder.invalid"
TEMPLATE_FILES=(
    "${REPO_DIR}/kubernetes/istio/egress-service-entries.yaml"
    "${REPO_DIR}/kubernetes/istio/egress-routing.yaml"
)

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/render-istio-egress-config.sh [options]

Renders the checked-in Istio egress manifests with the Auth0 issuer hostname
derived from AUTH0_ISSUER_URI.

Options:
  --apply                         Apply the rendered manifests with kubectl.
  --auth0-issuer-uri URI          Override the issuer URI instead of reading the
                                  in-cluster session-gateway IDP config.
  --namespace NAMESPACE           ConfigMap namespace when reading from the cluster
                                  (default: default).
  --configmap-name NAME           ConfigMap name when reading from the cluster
                                  (default: session-gateway-idp-config).
  -h, --help                      Show this help text.

When --auth0-issuer-uri is omitted, the script reads AUTH0_ISSUER_URI from the
configured Kubernetes ConfigMap. That keeps local Tilt config rendering and any
production config source on the same contract: the egress allowlist and the
session-gateway IDP config must both come from the same issuer URI.
EOF
}

read_configmap_value() {
    local namespace="$1" configmap_name="$2" key="$3"
    local value

    value=$(kubectl get configmap "${configmap_name}" -n "${namespace}" \
        -o "jsonpath={.data['${key}']}" 2>/dev/null || true)
    [[ -n "${value}" ]] || return 1

    printf '%s' "${value}"
}

extract_host_from_uri() {
    local uri="$1"
    local host

    host=$(printf '%s\n' "${uri}" | sed -E 's#^[[:space:]]*[A-Za-z][A-Za-z0-9+.-]*://([^/:?#]+).*$#\1#')
    if [[ -z "${host}" || "${host}" == "${uri}" ]]; then
        printf 'ERROR: could not parse hostname from AUTH0_ISSUER_URI: %s\n' "${uri}" >&2
        exit 1
    fi

    printf '%s\n' "${host}"
}

render_templates() {
    local auth0_host="$1"
    local template_file

    for template_file in "${TEMPLATE_FILES[@]}"; do
        if [[ ! -f "${template_file}" ]]; then
            printf 'ERROR: missing template file: %s\n' "${template_file}" >&2
            exit 1
        fi

        sed "s|${AUTH0_HOST_PLACEHOLDER}|${auth0_host}|g" "${template_file}"
        printf '\n'
    done
}

main() {
    local apply_rendered=false
    local namespace="${DEFAULT_NAMESPACE}"
    local configmap_name="${DEFAULT_CONFIGMAP_NAME}"
    local auth0_issuer_uri=""
    local auth0_host=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply)
                apply_rendered=true
                ;;
            --auth0-issuer-uri)
                auth0_issuer_uri="${2:-}"
                shift
                ;;
            --namespace)
                namespace="${2:-}"
                shift
                ;;
            --configmap-name)
                configmap_name="${2:-}"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "${auth0_issuer_uri}" ]]; then
        auth0_issuer_uri=$(read_configmap_value "${namespace}" "${configmap_name}" "${AUTH0_CONFIG_KEY}" || true)
    fi

    if [[ -z "${auth0_issuer_uri}" ]]; then
        printf 'ERROR: AUTH0_ISSUER_URI is required. Pass --auth0-issuer-uri or create %s/%s[%s].\n' \
            "${namespace}" "${configmap_name}" "${AUTH0_CONFIG_KEY}" >&2
        exit 1
    fi

    auth0_host=$(extract_host_from_uri "${auth0_issuer_uri}")

    if [[ "${apply_rendered}" == true ]]; then
        render_templates "${auth0_host}" | kubectl apply -f -
        return 0
    fi

    render_templates "${auth0_host}"
}

main "$@"
