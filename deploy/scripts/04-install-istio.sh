#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

RENDERED_OUTPUT_DIR="$(phase4_render_output_dir)"
RENDERED_INGRESS_CONFIG="${RENDERED_OUTPUT_DIR}/ingress-gateway-config.yaml"
RENDERED_GATEWAY="${RENDERED_OUTPUT_DIR}/istio-gateway.yaml"
readonly RENDERED_OUTPUT_DIR
readonly RENDERED_INGRESS_CONFIG
readonly RENDERED_GATEWAY

require_rendered_manifests() {
    [[ -f "${RENDERED_INGRESS_CONFIG}" ]] || phase4_die "missing ${RENDERED_INGRESS_CONFIG}; run deploy/scripts/03-render-phase-4-istio-manifests.sh first"
    [[ -f "${RENDERED_GATEWAY}" ]] || phase4_die "missing ${RENDERED_GATEWAY}; run deploy/scripts/03-render-phase-4-istio-manifests.sh first"
}

phase4_load_instance_env
phase4_require_commands helm kubectl
phase4_require_cluster_access
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
    --values "$(phase4_repo_path "kubernetes/istio/cni-values.yaml")" \
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

phase4_info "applying the rendered Phase 4 ingress resources"
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
kubectl apply -f "$(phase4_repo_path "kubernetes/istio/peer-authentication.yaml")" >/dev/null
kubectl apply -f "$(phase4_repo_path "kubernetes/istio/authorization-policies.yaml")" >/dev/null

phase4_info "Istio mesh and Phase 4 ingress path are installed"
