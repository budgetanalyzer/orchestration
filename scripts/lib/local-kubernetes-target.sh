#!/bin/bash

# Shared fail-closed checks for commands that inspect or mutate the local Kind
# cluster. Source this file; do not execute it directly.

is_local_docker_unix_endpoint() {
    local endpoint="$1"

    [[ "$endpoint" =~ ^unix:///[^[:space:]]+$ ]]
}

assert_local_docker_endpoint() {
    local selected_context endpoint

    if ! command -v docker >/dev/null 2>&1; then
        printf 'ERROR: required command is missing: docker\n' >&2
        return 1
    fi

    if [[ -n "${DOCKER_HOST:-}" && -n "${DOCKER_CONTEXT:-}" ]]; then
        printf 'ERROR: DOCKER_HOST and DOCKER_CONTEXT must not both select the Docker endpoint.\n' >&2
        return 1
    fi

    if [[ -n "${DOCKER_HOST:-}" ]]; then
        endpoint="$DOCKER_HOST"
    else
        if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
            selected_context="$DOCKER_CONTEXT"
        elif ! selected_context="$(docker context show 2>/dev/null)" \
            || [[ -z "$selected_context" ]]; then
            printf 'ERROR: unable to determine the current Docker context.\n' >&2
            return 1
        fi

        if ! endpoint="$(
            docker context inspect "$selected_context" \
                --format '{{ (index .Endpoints "docker").Host }}' 2>/dev/null
        )" || [[ -z "$endpoint" ]]; then
            printf "ERROR: unable to inspect Docker context '%s'.\n" \
                "$selected_context" >&2
            return 1
        fi
    fi

    if ! is_local_docker_unix_endpoint "$endpoint"; then
        printf 'ERROR: selected Docker endpoint is not a local Unix socket: %s\n' \
            "${endpoint:-unknown}" >&2
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        printf 'ERROR: selected local Docker daemon is unreachable: %s\n' \
            "$endpoint" >&2
        return 1
    fi

    return 0
}

is_supported_local_kubernetes_api_server() {
    local api_server="$1"
    local port

    if [[ "$api_server" =~ ^https://(127\.0\.0\.1|localhost):([0-9]{1,5})$ ]]; then
        port="${BASH_REMATCH[2]}"
    elif [[ "$api_server" =~ ^https://\[::1\]:([0-9]{1,5})$ ]]; then
        port="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

assert_local_kind_target() {
    local active_context referenced_cluster api_server proxy_url node_ready command_name
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
    if ! is_supported_local_kubernetes_api_server "$api_server"; then
        printf 'ERROR: Kubernetes API is not an exact supported loopback HTTPS authority: %s\n' \
            "${api_server:-unknown}" >&2
        return 1
    fi

    if ! proxy_url="$(
        kubectl config view --minify \
            -o jsonpath='{.clusters[0].cluster.proxy-url}' 2>/dev/null
    )"; then
        printf 'ERROR: unable to inspect the Kubernetes API proxy configuration.\n' >&2
        return 1
    fi
    if [[ -n "$proxy_url" ]]; then
        printf 'ERROR: Kubernetes API proxy redirection is not allowed for the local target.\n' >&2
        return 1
    fi

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
