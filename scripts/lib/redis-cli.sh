#!/usr/bin/env bash
# Shared helper for running redis-cli against the in-cluster Redis pod over TLS.

set -euo pipefail

redis_cli_in_pod() {
    local namespace="$1"
    local pod="$2"
    local user="$3"
    local password="$4"
    shift 4

    local -a kubectl_flags=()
    if [ -t 0 ] && [ $# -eq 0 ]; then
        kubectl_flags+=("-it")
    fi

    kubectl exec "${kubectl_flags[@]}" -n "$namespace" "$pod" -- \
        redis-cli \
        --tls \
        --cacert /tls-ca/ca.crt \
        --user "$user" \
        --pass "$password" \
        --no-auth-warning \
        "$@"
}

# Prints the lowercase hex SHA-256 of a browser session token. Session Gateway
# and ext-authz store this digest, never the raw cookie value, as the session
# key suffix and as the user_sessions:<userId> index member.
session_digest_for() {
    local token="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$token" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$token" | shasum -a 256 | awk '{print $1}'
    else
        echo "ERROR: neither sha256sum nor shasum is available" >&2
        return 1
    fi
}

# Prints the Redis session key for a browser session token: the key prefix
# (default session:) followed by session_digest_for of the token.
session_key_for() {
    local token="$1"
    local prefix="${2:-session:}"
    local digest

    digest=$(session_digest_for "$token")
    printf '%s%s\n' "$prefix" "$digest"
}
