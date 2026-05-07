#!/usr/bin/env bash
# Verifies internal transport-TLS secrets before infrastructure StatefulSets start.

set -euo pipefail

MISSING=()

require_command() {
    local command_name="$1"

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
}

check_secret() {
    local namespace="$1"
    local secret_name="$2"

    if ! kubectl get secret "${secret_name}" -n "${namespace}" >/dev/null 2>&1; then
        MISSING+=("secret/${namespace}/${secret_name}")
    fi
}

require_command kubectl

if ! kubectl cluster-info >/dev/null 2>&1; then
    printf 'ERROR: Kubernetes cluster is not reachable from kubectl.\n' >&2
    printf 'Ensure your local cluster is running and kubectl is pointed at it.\n' >&2
    exit 1
fi

if ! kubectl get namespace infrastructure >/dev/null 2>&1; then
    MISSING+=("namespace/infrastructure")
else
    check_secret infrastructure infra-ca
    check_secret infrastructure infra-tls-postgresql
    check_secret infrastructure infra-tls-redis
    check_secret infrastructure infra-tls-rabbitmq
fi

check_secret default infra-ca

if (( ${#MISSING[@]} > 0 )); then
    printf 'ERROR: internal transport-TLS prerequisites are missing.\n' >&2
    printf 'Missing resources:\n' >&2
    printf '  - %s\n' "${MISSING[@]}" >&2
    printf '\n' >&2
    printf 'Run this from your host terminal, not from the devcontainer or Tilt:\n' >&2
    printf '  ./scripts/bootstrap/setup-infra-tls.sh\n' >&2
    printf '\n' >&2
    printf 'Then rerun this check or trigger the Tilt resource again:\n' >&2
    printf '  ./scripts/bootstrap/check-infra-tls-secrets.sh\n' >&2
    exit 1
fi

printf 'Infrastructure TLS prerequisites are present.\n'
