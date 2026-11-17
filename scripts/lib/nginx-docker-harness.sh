#!/bin/bash

# Shared image selection and disposable container lifecycle for the offline
# NGINX Docker harnesses in scripts/guardrails/. Callers install
# `trap nginx_harness_cleanup EXIT`. Source this file; do not execute it
# directly.

NGINX_HARNESS_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NGINX_HARNESS_CONTAINER_ID=""
NGINX_HARNESS_WORK_DIR=""

nginx_harness_require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        printf 'ERROR: required command not found: docker\n' >&2
        exit 1
    fi
}

# Prints the digest-pinned nginx-gateway image declared in the deployment file.
nginx_harness_image() {
    local deployment_file="$1" image

    image=$(sed -nE 's#^[[:space:]]*image:[[:space:]]*(nginxinc/nginx-unprivileged[^[:space:]]*).*$#\1#p' \
        "${deployment_file}" | head -n 1)
    if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
        printf 'ERROR: nginx-gateway image in %s is not digest-pinned: %s\n' \
            "${deployment_file#"${NGINX_HARNESS_REPO_DIR}"/}" "${image:-<missing>}" >&2
        exit 1
    fi
    printf '%s\n' "${image}"
}

# Sets NGINX_HARNESS_WORK_DIR. Do not call it in a command substitution.
nginx_harness_make_work_dir() {
    NGINX_HARNESS_WORK_DIR=$(mktemp -d)
    chmod 755 "${NGINX_HARNESS_WORK_DIR}"
}

# Usage: nginx_harness_start <image> <ready-url> [extra docker run args...]
# Sets NGINX_HARNESS_CONTAINER_ID before polling so the EXIT trap removes a
# container that never becomes ready. Do not call it in a command substitution.
nginx_harness_start() {
    local image="$1" ready_url="$2" attempt

    shift 2
    NGINX_HARNESS_CONTAINER_ID=$(docker run --detach --network none --read-only \
        --tmpfs /tmp --entrypoint nginx \
        "$@" \
        "${image}" -g 'daemon off;')

    for ((attempt = 1; attempt <= 20; attempt++)); do
        if docker exec "${NGINX_HARNESS_CONTAINER_ID}" curl --silent --fail --max-time 2 \
            -o /dev/null "${ready_url}" 2>/dev/null; then
            return 0
        fi
        sleep 0.5
    done

    printf 'ERROR: disposable NGINX did not start\n' >&2
    docker logs "${NGINX_HARNESS_CONTAINER_ID}" >&2 || true
    exit 1
}

nginx_harness_stop() {
    if [[ -n "${NGINX_HARNESS_CONTAINER_ID}" ]]; then
        docker rm -f "${NGINX_HARNESS_CONTAINER_ID}" >/dev/null 2>&1 || true
        NGINX_HARNESS_CONTAINER_ID=""
    fi
}

nginx_harness_cleanup() {
    set +e
    nginx_harness_stop
    if [[ -n "${NGINX_HARNESS_WORK_DIR}" ]]; then
        rm -rf "${NGINX_HARNESS_WORK_DIR}"
    fi
}
