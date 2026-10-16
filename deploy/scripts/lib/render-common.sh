#!/usr/bin/env bash

# Minimal helpers for provider-neutral, offline production-reference renders.
# This library must not load host configuration, select a kubeconfig, or access
# a Kubernetes API.

PRODUCTION_RENDER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCTION_REPO_ROOT="$(cd "${PRODUCTION_RENDER_LIB_DIR}/../../.." && pwd)"
readonly PRODUCTION_RENDER_LIB_DIR
readonly PRODUCTION_REPO_ROOT

# shellcheck source=scripts/lib/production-version-contract.sh
source "${PRODUCTION_REPO_ROOT}/scripts/lib/production-version-contract.sh"

production_render_info() {
    printf '[production-reference] %s\n' "$*"
}

production_render_die() {
    printf '[production-reference] ERROR: %s\n' "$*" >&2
    exit 1
}

production_render_require_commands() {
    local command_name

    for command_name in "$@"; do
        command -v "${command_name}" >/dev/null 2>&1 || \
            production_render_die "required command not found: ${command_name}"
    done
}

production_repo_path() {
    printf '%s/%s\n' "${PRODUCTION_REPO_ROOT}" "$1"
}

