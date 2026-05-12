#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/lib/common.sh"

INSTALL_K3S_EXEC_FLAGS="--disable=traefik --disable=servicelb --disable=metrics-server --write-kubeconfig-mode=644"
readonly INSTALL_K3S_EXEC_FLAGS
INOTIFY_SYSCTL_CONFIG="/etc/sysctl.d/90-budget-analyzer-inotify.conf"
readonly INOTIFY_SYSCTL_CONFIG

read_sysctl_value() {
    local key="$1"
    local value

    value="$(phase4_run_sudo sysctl -n "${key}" 2>/dev/null || true)"
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
        phase4_die "could not read ${key}"
    fi

    printf '%s\n' "${value}"
}

max_sysctl_value() {
    local current_value="$1"
    local minimum_value="$2"

    if (( current_value > minimum_value )); then
        printf '%s\n' "${current_value}"
    else
        printf '%s\n' "${minimum_value}"
    fi
}

write_inotify_sysctl_config() {
    local instances="$1"
    local watches="$2"

    printf '%s\n' \
        "# Managed by Budget Analyzer production bootstrap." \
        "# Required for reliable k3s/containerd log-follow streaming." \
        "fs.inotify.max_user_instances = ${instances}" \
        "fs.inotify.max_user_watches = ${watches}" |
        phase4_run_sudo tee "${INOTIFY_SYSCTL_CONFIG}" >/dev/null
}

converge_inotify_budget() {
    local current_instances
    local current_watches
    local target_instances
    local target_watches

    current_instances="$(read_sysctl_value fs.inotify.max_user_instances)"
    current_watches="$(read_sysctl_value fs.inotify.max_user_watches)"
    target_instances="$(max_sysctl_value "${current_instances}" "${PHASE4_MIN_INOTIFY_INSTANCES}")"
    target_watches="$(max_sysctl_value "${current_watches}" "${PHASE4_MIN_INOTIFY_WATCHES}")"

    phase4_info "converging host inotify budget for k3s/containerd log streaming"
    write_inotify_sysctl_config "${target_instances}" "${target_watches}"
    phase4_run_sudo sysctl -p "${INOTIFY_SYSCTL_CONFIG}" >/dev/null

    phase4_info "host inotify budget:"
    phase4_run_sudo sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
}

phase4_load_instance_env
phase4_require_commands curl sudo sysctl tee

phase4_info "installing or reconciling k3s ${PHASE4_K3S_VERSION}"
converge_inotify_budget
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
