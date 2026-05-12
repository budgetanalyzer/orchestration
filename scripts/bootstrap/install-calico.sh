#!/bin/bash

# install-calico.sh - Install pinned Calico CNI for Kind clusters with default CNI disabled.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/pinned-tool-versions.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/../lib/pinned-tool-versions.sh"

CALICO_VERSION="$PHASE7_CALICO_VERSION"
CALICO_MANIFEST_URL="$(phase7_calico_manifest_url)"
CALICO_NAMESPACE="kube-system"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
MIN_INOTIFY_INSTANCES="${MIN_INOTIFY_INSTANCES:-8192}"
MIN_INOTIFY_WATCHES="${MIN_INOTIFY_WATCHES:-524288}"

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

is_calico_version_pinned() {
    local images

    images="$(kubectl get daemonset calico-node -n "${CALICO_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[*].image}' 2>/dev/null || true)"
    printf '%s\n' "$images" | grep -q "calico/node:${CALICO_VERSION}"
}

ensure_cluster_uses_disable_default_cni_model() {
    if kubectl get daemonset kindnet -n kube-system >/dev/null 2>&1; then
        print_error "Detected kindnet daemonset in kube-system"
        echo "  This cluster was created with Kind's default CNI and cannot enforce NetworkPolicy as required."
        echo "  Rebuild with: kind delete cluster --name kind && kind create cluster --config kind-cluster-config.yaml"
        exit 1
    fi
}

ensure_kind_node_inotify_budget() {
    if ! command -v kind >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    local nodes=()
    local node
    local current_value
    local final_value
    local changed
    local updated_any=false

    mapfile -t nodes < <(kind get nodes --name "${KIND_CLUSTER_NAME}" 2>/dev/null || true)

    if [[ ${#nodes[@]} -eq 0 ]]; then
        return 0
    fi

    for node in "${nodes[@]}"; do
        changed=false

        current_value="$(docker exec "${node}" cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"
        if ! [[ "${current_value}" =~ ^[0-9]+$ ]]; then
            print_error "Could not read fs.inotify.max_user_instances from Kind node ${node}"
            exit 1
        fi
        if (( current_value < MIN_INOTIFY_INSTANCES )); then
            docker exec "${node}" sysctl -w "fs.inotify.max_user_instances=${MIN_INOTIFY_INSTANCES}" >/dev/null
            changed=true
        fi

        current_value="$(docker exec "${node}" cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)"
        if ! [[ "${current_value}" =~ ^[0-9]+$ ]]; then
            print_error "Could not read fs.inotify.max_user_watches from Kind node ${node}"
            exit 1
        fi
        if (( current_value < MIN_INOTIFY_WATCHES )); then
            docker exec "${node}" sysctl -w "fs.inotify.max_user_watches=${MIN_INOTIFY_WATCHES}" >/dev/null
            changed=true
        fi

        if [[ "${changed}" == true ]]; then
            final_value="$(docker exec "${node}" cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"
            print_step "Kind node ${node}: fs.inotify.max_user_instances=${final_value}"
            final_value="$(docker exec "${node}" cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)"
            print_step "Kind node ${node}: fs.inotify.max_user_watches=${final_value}"
            updated_any=true
        fi
    done

    if [[ "${updated_any}" == true ]]; then
        print_step "Kind node inotify budget reconciled"
    fi
}

ensure_kube_proxy_ready() {
    if ! kubectl get daemonset kube-proxy -n "${CALICO_NAMESPACE}" >/dev/null 2>&1; then
        print_error "kube-proxy daemonset not found in ${CALICO_NAMESPACE}"
        exit 1
    fi

    print_step "Waiting for kube-proxy daemonset rollout..."
    if ! kubectl rollout status daemonset/kube-proxy -n "${CALICO_NAMESPACE}" --timeout=2m >/dev/null; then
        print_error "kube-proxy did not become ready"
        kubectl get pods -n "${CALICO_NAMESPACE}" -l k8s-app=kube-proxy || true
        kubectl logs -n "${CALICO_NAMESPACE}" -l k8s-app=kube-proxy --tail=50 || true
        exit 1
    fi
}

main() {
    require_cluster_access
    ensure_cluster_uses_disable_default_cni_model
    ensure_kind_node_inotify_budget
    ensure_kube_proxy_ready

    if is_calico_ready && is_calico_version_pinned; then
        print_step "Calico already ready (${CALICO_VERSION})"
    else
        print_step "Installing/reconciling Calico (${CALICO_VERSION})..."
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

        if ! is_calico_version_pinned; then
            print_error "Calico daemonset does not use pinned image version ${CALICO_VERSION}"
            kubectl get daemonset calico-node -n "${CALICO_NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}' || true
            exit 1
        fi
    fi

    print_step "Waiting for CoreDNS deployment (confirms CNI is functional)..."
    if ! kubectl rollout status deployment/coredns -n "${CALICO_NAMESPACE}" --timeout=5m >/dev/null; then
        print_error "CoreDNS did not become ready after Calico setup"
        kubectl get pods -n "${CALICO_NAMESPACE}" -l k8s-app=kube-dns || true
        exit 1
    fi

    print_success "Calico and CoreDNS are ready (${CALICO_VERSION})"
}

main "$@"
