#!/bin/bash

# Shared fail-closed checks for native commands that inspect or mutate the
# guest-local Kind cluster. Source this file; do not execute it directly.

assert_local_kind_target() {
    local active_context referenced_cluster api_server node_ready command_name
    local expected_context="kind-kind"
    local expected_cluster="kind-kind"
    local expected_kind_cluster="kind"

    for command_name in kubectl kind; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'ERROR: required command is missing: %s\n' "$command_name" >&2
            return 1
        fi
    done

    active_context="$(kubectl config current-context 2>/dev/null || true)"
    if [[ "$active_context" != "$expected_context" ]]; then
        printf "ERROR: current Kubernetes context is '%s'; expected '%s'.\n" \
            "${active_context:-none}" "$expected_context" >&2
        return 1
    fi

    referenced_cluster="$(
        kubectl config view --minify \
            -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || true
    )"
    if [[ "$referenced_cluster" != "$expected_cluster" ]]; then
        printf "ERROR: current context references '%s'; expected '%s'.\n" \
            "${referenced_cluster:-none}" "$expected_cluster" >&2
        return 1
    fi

    api_server="$(
        kubectl config view --minify \
            -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true
    )"
    case "$api_server" in
        https://127.0.0.1:*|https://localhost:*|https://\[::1\]:*) ;;
        *)
            printf 'ERROR: Kubernetes API is not loopback-bound: %s\n' \
                "${api_server:-unknown}" >&2
            return 1
            ;;
    esac

    if ! kind get clusters 2>/dev/null | grep -Fxq "$expected_kind_cluster"; then
        printf "ERROR: local Kind cluster '%s' is absent.\n" \
            "$expected_kind_cluster" >&2
        return 1
    fi

    node_ready="$(
        kubectl get node kind-control-plane \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
            2>/dev/null || true
    )"
    if [[ "$node_ready" != "True" ]]; then
        printf 'ERROR: required node kind-control-plane is not Ready.\n' >&2
        return 1
    fi

    return 0
}
