#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PUBLIC_TLS_ACKNOWLEDGE_FLAG="--acknowledge-public-tls-downgrade"
RENDERED_OUTPUT_DIR="$(phase4_render_output_dir)"
RENDERED_INGRESS_CONFIG="${RENDERED_OUTPUT_DIR}/ingress-gateway-config.yaml"
RENDERED_GATEWAY="${RENDERED_OUTPUT_DIR}/istio-gateway.yaml"
PEER_AUTHENTICATION_FILE="$(phase4_repo_path "kubernetes/istio/peer-authentication.yaml")"
PRODUCTION_AUTHORIZATION_POLICIES_FILE="$(phase4_repo_path "kubernetes/production/istio/authorization-policies.yaml")"
ACKNOWLEDGE_PUBLIC_TLS_DOWNGRADE=false
PUBLIC_TLS_WAS_DETECTED=false
readonly PUBLIC_TLS_ACKNOWLEDGE_FLAG
readonly RENDERED_OUTPUT_DIR
readonly RENDERED_INGRESS_CONFIG
readonly RENDERED_GATEWAY
readonly PEER_AUTHENTICATION_FILE
readonly PRODUCTION_AUTHORIZATION_POLICIES_FILE

usage() {
    cat <<EOF
Usage: ./deploy/scripts/04-install-istio.sh [${PUBLIC_TLS_ACKNOWLEDGE_FLAG}]

Installs or reconciles the repo-owned Istio control plane plus the phase-4
HTTP ingress baseline.

If the live cluster already serves the phase-11 public TLS path, this script
refuses to continue unless ${PUBLIC_TLS_ACKNOWLEDGE_FLAG} is passed. The
phase-4 reconcile path is HTTP-only and can remove the live 443 -> 30443
listener until the phase-11 public TLS manifests are reapplied.
EOF
}

require_rendered_manifests() {
    [[ -f "${RENDERED_INGRESS_CONFIG}" ]] || phase4_die "missing ${RENDERED_INGRESS_CONFIG}; run deploy/scripts/03-render-phase-4-istio-manifests.sh first"
    [[ -f "${RENDERED_GATEWAY}" ]] || phase4_die "missing ${RENDERED_GATEWAY}; run deploy/scripts/03-render-phase-4-istio-manifests.sh first"
    [[ -f "${PEER_AUTHENTICATION_FILE}" ]] || phase4_die "missing ${PEER_AUTHENTICATION_FILE}"
    [[ -f "${PRODUCTION_AUTHORIZATION_POLICIES_FILE}" ]] || phase4_die "missing ${PRODUCTION_AUTHORIZATION_POLICIES_FILE}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            "${PUBLIC_TLS_ACKNOWLEDGE_FLAG}")
                ACKNOWLEDGE_PUBLIC_TLS_DOWNGRADE=true
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
}

live_public_tls_is_configured() {
    local ingress_service_name
    local https_nodeport
    local gateway_https_listener

    ingress_service_name="$(phase4_ingress_service_name)"
    if [[ -n "${ingress_service_name}" ]]; then
        https_nodeport="$(phase4_find_service_nodeport "${PHASE4_INGRESS_GATEWAY_NAMESPACE}" "${ingress_service_name}" 443)"
        if [[ "${https_nodeport}" == "30443" ]]; then
            return 0
        fi
    fi

    gateway_https_listener="$(
        kubectl get gateway "${PHASE4_INGRESS_GATEWAY_NAME}" -n "${PHASE4_INGRESS_GATEWAY_NAMESPACE}" \
            -o jsonpath='{range .spec.listeners[*]}{.port}:{.protocol}{"\n"}{end}' 2>/dev/null |
            awk -F: '$1 == "443" || $2 == "HTTPS" { print; exit }'
    )"
    [[ -n "${gateway_https_listener}" ]]
}

guard_live_public_tls_reconcile() {
    if ! live_public_tls_is_configured; then
        return
    fi

    PUBLIC_TLS_WAS_DETECTED=true

    if [[ "${ACKNOWLEDGE_PUBLIC_TLS_DOWNGRADE}" == "true" ]]; then
        phase4_warn "live ingress already exposes the phase-11 public TLS path. This phase-4 reconcile is HTTP-only; rerun the phase-11 public TLS apply path immediately after this script completes."
        return
    fi

    phase4_die "live ingress already exposes the phase-11 public TLS path (443 -> 30443). Rerunning this script can remove that listener until the phase-11 manifests are reapplied. Rerun with ${PUBLIC_TLS_ACKNOWLEDGE_FLAG} only if you intend to reconcile Istio and then immediately reapply the phase-11 public TLS manifests."
}

parse_args "$@"
phase4_load_instance_env
phase4_require_commands helm kubectl
phase4_require_cluster_access
guard_live_public_tls_reconcile
phase4_info "refreshing the rendered ingress manifests"
"${SCRIPT_DIR}/03-render-phase-4-istio-manifests.sh" --output-dir "${RENDERED_OUTPUT_DIR}" >/dev/null
require_rendered_manifests

phase4_info "installing Istio charts ${PHASE4_ISTIO_CHART_VERSION}"
phase4_ensure_helm_repo istio "${PHASE4_ISTIO_HELM_REPO_URL}"
helm repo update istio >/dev/null

helm upgrade --install istio-base istio/base \
    --namespace istio-system \
    --create-namespace \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --wait

helm upgrade --install istio-cni istio/cni \
    --namespace istio-system \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --values "$(phase4_repo_path "kubernetes/istio/cni-common-values.yaml")" \
    --values "$(phase4_repo_path "kubernetes/istio/cni-k3s-values.yaml")" \
    --wait

helm upgrade --install istiod istio/istiod \
    --namespace istio-system \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --values "$(phase4_repo_path "kubernetes/istio/istiod-values.yaml")" \
    --wait

kubectl rollout status daemonset/istio-cni-node -n istio-system --timeout=180s
kubectl rollout status deployment/istiod -n istio-system --timeout=180s

phase4_info "installing the chart-managed egress gateway"
kubectl apply -f "$(phase4_repo_path "kubernetes/istio/egress-namespace.yaml")" >/dev/null
helm upgrade --install istio-egress-gateway istio/gateway \
    --namespace istio-egress \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --values "$(phase4_repo_path "kubernetes/istio/egress-gateway-values.yaml")" \
    --wait
kubectl rollout status deployment/istio-egress-gateway -n istio-egress --timeout=180s

phase4_info "applying the rendered ingress resources"
kubectl apply -f "$(phase4_repo_path "kubernetes/istio/ingress-namespace.yaml")" >/dev/null
kubectl apply -f "${RENDERED_INGRESS_CONFIG}" >/dev/null
kubectl apply -f "${RENDERED_GATEWAY}" >/dev/null
kubectl wait \
    --for=condition=Programmed \
    "gateway/${PHASE4_INGRESS_GATEWAY_NAME}" \
    -n "${PHASE4_INGRESS_GATEWAY_NAMESPACE}" \
    --timeout=180s
kubectl rollout status deployment/istio-ingress-gateway-istio -n "${PHASE4_INGRESS_GATEWAY_NAMESPACE}" --timeout=180s

phase4_info "applying mesh security policies"
kubectl apply -f "${PEER_AUTHENTICATION_FILE}" >/dev/null
kubectl apply -f "${PRODUCTION_AUTHORIZATION_POLICIES_FILE}" >/dev/null

phase4_info "Istio mesh and ingress path are installed"
if [[ "${PUBLIC_TLS_WAS_DETECTED}" == "true" ]]; then
    phase4_warn "phase-11 public TLS was detected before this reconcile. Rerun ./deploy/scripts/16-render-phase-11-public-tls-manifests.sh and reapply tmp/phase-11/{cluster-issuer.yaml,public-certificate.yaml,reference-grant.yaml,ingress-gateway-config.yaml,istio-gateway.yaml} to restore the 443 -> 30443 public listener path."
fi
