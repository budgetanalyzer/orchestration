#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

INSTALL_K3S_EXEC_FLAGS="--disable=traefik --disable=servicelb --disable=metrics-server --write-kubeconfig-mode=644"
readonly INSTALL_K3S_EXEC_FLAGS

phase4_load_instance_env
phase4_require_commands curl sudo

phase4_info "installing or reconciling k3s ${PHASE4_K3S_VERSION}"
curl -sfL "${PHASE4_K3S_INSTALL_URL}" | phase4_run_sudo env \
    INSTALL_K3S_VERSION="${PHASE4_K3S_VERSION}" \
    INSTALL_K3S_EXEC="${INSTALL_K3S_EXEC_FLAGS}" \
    sh -

phase4_run_sudo systemctl is-active --quiet k3s || phase4_die "k3s service is not active after install"

phase4_use_default_kubeconfig
phase4_require_commands kubectl
phase4_require_cluster_access

phase4_info "k3s version:"
phase4_run_sudo k3s --version | head -n 1
phase4_info "cluster readiness snapshot:"
kubectl get nodes
kubectl get pods -A
kubectl get storageclass
