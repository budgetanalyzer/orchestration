#!/bin/bash

# Reconcile Kind node inotify sysctls used by Kubernetes log-follow paths.

set -euo pipefail

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
MIN_INOTIFY_INSTANCES="${MIN_INOTIFY_INSTANCES:-8192}"
MIN_INOTIFY_WATCHES="${MIN_INOTIFY_WATCHES:-524288}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local command_name=$1

    if ! command -v "$command_name" >/dev/null 2>&1; then
        fail "$command_name is required to reconcile the Kind node inotify budget"
    fi
}

require_unsigned_integer() {
    local name=$1
    local value=$2

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        fail "$name must be an unsigned integer, got: $value"
    fi
}

reconcile_node_value() {
    local node=$1
    local sysctl_key=$2
    local proc_path=$3
    local minimum=$4
    local current_value
    local final_value

    require_unsigned_integer "$sysctl_key minimum" "$minimum"

    current_value="$(docker exec "$node" cat "$proc_path" 2>/dev/null || true)"
    if ! [[ "$current_value" =~ ^[0-9]+$ ]]; then
        fail "could not read $sysctl_key from Kind node $node"
    fi

    if (( current_value < minimum )); then
        docker exec "$node" sysctl -w "${sysctl_key}=${minimum}" >/dev/null
        final_value="$(docker exec "$node" cat "$proc_path" 2>/dev/null || true)"
        require_unsigned_integer "$sysctl_key final value" "$final_value"
        printf '%s: %s=%s (raised from %s; minimum %s)\n' \
            "$node" "$sysctl_key" "$final_value" "$current_value" "$minimum"
    else
        printf '%s: %s=%s (minimum %s)\n' \
            "$node" "$sysctl_key" "$current_value" "$minimum"
    fi
}

main() {
    local nodes=()
    local node

    require_command docker
    require_command kind

    mapfile -t nodes < <(kind get nodes --name "$KIND_CLUSTER_NAME" 2>/dev/null || true)
    if [[ ${#nodes[@]} -eq 0 ]]; then
        fail "no Kind nodes found for cluster $KIND_CLUSTER_NAME"
    fi

    for node in "${nodes[@]}"; do
        reconcile_node_value \
            "$node" \
            "fs.inotify.max_user_instances" \
            "/proc/sys/fs/inotify/max_user_instances" \
            "$MIN_INOTIFY_INSTANCES"
        reconcile_node_value \
            "$node" \
            "fs.inotify.max_user_watches" \
            "/proc/sys/fs/inotify/max_user_watches" \
            "$MIN_INOTIFY_WATCHES"
    done
}

main "$@"
