#!/bin/bash
# Interactive Redis CLI for the Budget Analyzer cluster.
# Connects as redis-ops (full access) over TLS.
#
# Usage:
#   ./scripts/ops/redis-browse.sh session                              # interactive session
#   ./scripts/ops/redis-browse.sh session --sessions                   # dump all sessions
#   ./scripts/ops/redis-browse.sh session --user-sessions              # dump all user-session sets
#   ./scripts/ops/redis-browse.sh cache                                # interactive cache CLI
#   ./scripts/ops/redis-browse.sh session HGETALL session:<digest>     # one-shot command

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/redis-cli.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x from repo root.
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

usage() {
    echo "Usage: $0 <session|cache> [--sessions] [--user-sessions] [redis-cli arguments...]" >&2
}

if (( $# < 1 )); then
    usage
    exit 2
fi

case "$1" in
    session) REDIS_INSTANCE="redis-session" ;;
    cache) REDIS_INSTANCE="redis-cache" ;;
    *)
        usage
        exit 2
        ;;
esac
shift

REDIS_BOOTSTRAP_SECRET="${REDIS_INSTANCE}-bootstrap-credentials"

REDIS_POD=$(kubectl get pods -n infrastructure -l "app=${REDIS_INSTANCE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$REDIS_POD" ]; then
    echo "ERROR: ${REDIS_INSTANCE} pod not found in infrastructure namespace. Is Tilt running?" >&2
    exit 1
fi

REDIS_INSTANCE_OPS_PASSWORD=$(kubectl get secret "$REDIS_BOOTSTRAP_SECRET" -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
if [ -z "$REDIS_INSTANCE_OPS_PASSWORD" ]; then
    echo "ERROR: ${REDIS_BOOTSTRAP_SECRET} is missing ops-password." >&2
    exit 1
fi

rcli() { redis_cli_in_pod "$REDIS_INSTANCE" infrastructure "$REDIS_POD" redis-ops "$REDIS_INSTANCE_OPS_PASSWORD" "$@"; }

dump_keys() {
    local pattern="$1"
    local label="$2"
    local keys
    keys=$(rcli KEYS "$pattern")
    if [ -z "$keys" ]; then
        echo "No ${label} found."
        echo ""
        return
    fi
    while IFS= read -r key; do
        local type
        type=$(rcli TYPE "$key" | sed 's/^[^ ]* //')
        echo "--- ${key} (${type}) ---"
        case "$type" in
            hash)   rcli HGETALL "$key" ;;
            set)    rcli SMEMBERS "$key" ;;
            string) rcli GET "$key" ;;
            list)   rcli LRANGE "$key" 0 -1 ;;
            zset)   rcli ZRANGE "$key" 0 -1 WITHSCORES ;;
            *)      echo "(unsupported type: ${type})" ;;
        esac
        echo ""
    done <<< "$keys"
}

show_sessions=false
show_user_sessions=false
passthrough=()

for arg in "$@"; do
    case "$arg" in
        --sessions)       show_sessions=true ;;
        --user-sessions)  show_user_sessions=true ;;
        *)                passthrough+=("$arg") ;;
    esac
done

if [ "$REDIS_INSTANCE" = "redis-cache" ] && { "$show_sessions" || "$show_user_sessions"; }; then
    echo "ERROR: session dump options apply only to the session Redis instance." >&2
    exit 2
fi

if $show_sessions || $show_user_sessions; then
    $show_sessions      && dump_keys "session:*"       "sessions"
    $show_user_sessions && dump_keys "user_sessions:*"  "user sessions"
elif [ ${#passthrough[@]} -gt 0 ]; then
    rcli "${passthrough[@]}"
else
    rcli
fi
