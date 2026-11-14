#!/usr/bin/env bash
# Shared helper for running redis-cli against the in-cluster Redis pod over TLS.

set -euo pipefail

redis_cli_in_pod() {
    if (( $# < 5 )); then
        echo "ERROR: redis_cli_in_pod requires an instance, namespace, pod, user, and password." >&2
        return 2
    fi

    local instance="$1"
    local namespace="$2"
    local pod="$3"
    local user="$4"
    local password="$5"
    shift 5

    case "$instance" in
        redis-session|redis-cache) ;;
        *)
            echo "ERROR: unsupported Redis instance '$instance' (expected redis-session or redis-cache)." >&2
            return 2
            ;;
    esac

    local -a kubectl_flags=()
    if [ -t 0 ] && [ $# -eq 0 ]; then
        kubectl_flags+=("-it")
    fi

    kubectl exec "${kubectl_flags[@]}" -n "$namespace" "$pod" -c "$instance" -- \
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
