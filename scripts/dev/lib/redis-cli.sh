#!/usr/bin/env bash
# Shared helper for running redis-cli against the in-cluster Redis pod over TLS.

set -euo pipefail

redis_cli_in_pod() {
    local namespace="$1"
    local pod="$2"
    local user="$3"
    local password="$4"
    shift 4

    kubectl exec -n "$namespace" "$pod" -- \
        redis-cli \
        --tls \
        --cacert /tls-ca/ca.crt \
        --user "$user" \
        --pass "$password" \
        --no-auth-warning \
        "$@"
}
