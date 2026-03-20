#!/bin/bash

# install-calico.sh - Install pinned Calico CNI for Kind clusters with default CNI disabled.

set -euo pipefail

CALICO_VERSION="v3.29.3"
CALICO_MANIFEST_URL="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
CALICO_NAMESPACE="kube-system"

print_step() {
    echo "▶ $1"
}

print_success() {
    echo "✓ $1"
}

print_error() {
    echo "✗ $1" >&2
}

require_cluster_access() {
    if ! kubectl cluster-info --context kind-kind >/dev/null 2>&1; then
        print_error "Cannot reach cluster context kind-kind"
        echo "  Run: kubectl config use-context kind-kind"
        exit 1
    fi
}

is_calico_ready() {
    local ds_ready
    local ds_desired

    ds_ready="$(kubectl get daemonset calico-node -n "${CALICO_NAMESPACE}" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)"
    ds_desired="$(kubectl get daemonset calico-node -n "${CALICO_NAMESPACE}" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)"

    if [[ "${ds_desired}" -eq 0 ]]; then
        return 1
    fi

    if [[ "${ds_ready}" -ne "${ds_desired}" ]]; then
        return 1
    fi

    if ! kubectl wait --for=condition=Available deployment/calico-kube-controllers -n "${CALICO_NAMESPACE}" --timeout=1s >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

ensure_cluster_uses_disable_default_cni_model() {
    if kubectl get daemonset kindnet -n kube-system >/dev/null 2>&1; then
        print_error "Detected kindnet daemonset in kube-system"
        echo "  This cluster was created with Kind's default CNI and cannot enforce NetworkPolicy as required."
        echo "  Rebuild with: kind delete cluster --name kind && kind create cluster --config kind-cluster-config.yaml"
        exit 1
    fi
}

main() {
    require_cluster_access
    ensure_cluster_uses_disable_default_cni_model

    if is_calico_ready; then
        print_success "Calico already installed and ready (${CALICO_VERSION})"
        exit 0
    fi

    print_step "Installing Calico (${CALICO_VERSION})..."
    kubectl apply -f "${CALICO_MANIFEST_URL}" >/dev/null

    print_step "Waiting for calico-node daemonset rollout..."
    kubectl rollout status daemonset/calico-node -n "${CALICO_NAMESPACE}" --timeout=5m >/dev/null

    print_step "Waiting for calico-kube-controllers deployment..."
    kubectl wait --for=condition=Available deployment/calico-kube-controllers -n "${CALICO_NAMESPACE}" --timeout=5m >/dev/null

    if ! is_calico_ready; then
        print_error "Calico resources exist but are not ready"
        kubectl get pods -n "${CALICO_NAMESPACE}" -l k8s-app=calico-node || true
        exit 1
    fi

    print_success "Calico installed and ready (${CALICO_VERSION})"
}

main "$@"
