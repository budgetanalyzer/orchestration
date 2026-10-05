#!/bin/bash

# Shared fail-closed checks for bootstrap commands that must use this machine's
# default Docker Unix socket. Source this file; do not execute it directly.

assert_local_docker_target() {
    local context endpoint server_name local_hostname docker_root
    local remote_variable

    for remote_variable in \
        DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH \
        TESTCONTAINERS_HOST_OVERRIDE; do
        if [[ -n "${!remote_variable:-}" ]]; then
            printf 'ERROR: %s is set; refusing a possibly remote Docker endpoint.\n' "$remote_variable" >&2
            return 1
        fi
    done

    if [[ ! -S /var/run/docker.sock ]]; then
        printf 'ERROR: /var/run/docker.sock is not a local Unix socket.\n' >&2
        return 1
    fi

    context="$(docker context show 2>/dev/null || true)"
    if [[ "$context" != "default" ]]; then
        printf "ERROR: Docker context is '%s'; expected 'default'.\n" "${context:-none}" >&2
        return 1
    fi

    endpoint="$(docker context inspect default --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)"
    if [[ "$endpoint" != "unix:///var/run/docker.sock" ]]; then
        printf "ERROR: Docker endpoint is '%s'; expected the local Unix socket.\n" "${endpoint:-unknown}" >&2
        return 1
    fi

    if command -v systemctl >/dev/null 2>&1 \
        && ! systemctl is-active --quiet docker; then
        printf 'ERROR: the local Docker service is not active.\n' >&2
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        printf 'ERROR: the local Docker daemon is not reachable.\n' >&2
        return 1
    fi

    server_name="$(docker info --format '{{.Name}}' 2>/dev/null || true)"
    local_hostname="$(hostname -s)"
    if [[ -z "$server_name" || "$server_name" != "$local_hostname" ]]; then
        printf "ERROR: Docker daemon name '%s' does not match local hostname '%s'.\n" \
            "${server_name:-unknown}" "$local_hostname" >&2
        return 1
    fi

    docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
    if [[ "$docker_root" != "/var/lib/docker" ]]; then
        printf "ERROR: Docker data root is '%s'; expected guest-local /var/lib/docker.\n" \
            "${docker_root:-unknown}" >&2
        return 1
    fi

    return 0
}
