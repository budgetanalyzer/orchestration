#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DEFAULT_NAMESPACE_MANIFESTS=(
    "kubernetes/infrastructure/namespace.yaml"
    "kubernetes/monitoring/namespace.yaml"
    "kubernetes/istio/ingress-namespace.yaml"
    "kubernetes/istio/egress-namespace.yaml"
)
readonly DEFAULT_NAMESPACE_MANIFESTS

apply_namespace_manifests() {
    local manifest_path

    for manifest_path in "${DEFAULT_NAMESPACE_MANIFESTS[@]}"; do
        kubectl apply -f "$(phase4_repo_path "${manifest_path}")" >/dev/null
    done
}

label_default_namespace() {
    phase4_label_namespace default \
        istio-injection=enabled \
        budgetanalyzer.io/ingress-routes=true \
        pod-security.kubernetes.io/enforce=restricted \
        "pod-security.kubernetes.io/enforce-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/warn=restricted \
        "pod-security.kubernetes.io/warn-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/audit=restricted \
        "pod-security.kubernetes.io/audit-version=${PHASE4_POD_SECURITY_VERSION}"
}

label_istio_system_namespace() {
    phase4_create_or_update_namespace istio-system
    phase4_label_namespace istio-system \
        pod-security.kubernetes.io/enforce=privileged \
        "pod-security.kubernetes.io/enforce-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/warn=privileged \
        "pod-security.kubernetes.io/warn-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/audit=privileged \
        "pod-security.kubernetes.io/audit-version=${PHASE4_POD_SECURITY_VERSION}"
}

label_baseline_namespace() {
    local namespace="$1"

    phase4_create_or_update_namespace "${namespace}"
    phase4_label_namespace "${namespace}" \
        pod-security.kubernetes.io/enforce=baseline \
        "pod-security.kubernetes.io/enforce-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/warn=baseline \
        "pod-security.kubernetes.io/warn-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/audit=baseline \
        "pod-security.kubernetes.io/audit-version=${PHASE4_POD_SECURITY_VERSION}"
}

phase4_load_instance_env
phase4_require_commands kubectl
phase4_require_cluster_access

phase4_info "installing Gateway API CRDs ${PHASE4_GATEWAY_API_CRDS_VERSION}"
kubectl apply -f "${PHASE4_GATEWAY_API_STANDARD_INSTALL_URL}" >/dev/null
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=120s >/dev/null

phase4_info "applying checked-in namespace manifests"
apply_namespace_manifests

phase4_info "labeling default and controller namespaces"
label_default_namespace
label_istio_system_namespace
label_baseline_namespace external-secrets
label_baseline_namespace cert-manager

phase4_info "namespace label snapshot"
kubectl get namespace \
    default infrastructure monitoring istio-system istio-ingress istio-egress external-secrets cert-manager \
    --show-labels
