#!/bin/bash
# Interactive Redis CLI for the Budget Analyzer cluster.
# Connects as redis-ops (full access) over TLS.
#
# Usage:
#   ./scripts/ops/redis-browse.sh                                      # interactive session
#   ./scripts/ops/redis-browse.sh --sessions                           # dump all sessions
#   ./scripts/ops/redis-browse.sh --user-sessions                      # dump all user-session sets
#   ./scripts/ops/redis-browse.sh --sessions --user-sessions           # both
#   ./scripts/ops/redis-browse.sh HGETALL session:<id>                 # one-shot command

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

REDIS_POD=$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$REDIS_POD" ]; then
    echo "ERROR: Redis pod not found in infrastructure namespace. Is Tilt running?" >&2
    exit 1
fi

REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
if [ -z "$REDIS_OPS_PASSWORD" ]; then
    echo "ERROR: redis-bootstrap-credentials is missing ops-password." >&2
    exit 1
fi

rcli() { redis_cli_in_pod infrastructure "$REDIS_POD" redis-ops "$REDIS_OPS_PASSWORD" "$@"; }

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

if $show_sessions || $show_user_sessions; then
    $show_sessions      && dump_keys "session:*"       "sessions"
    $show_user_sessions && dump_keys "user_sessions:*"  "user sessions"
elif [ ${#passthrough[@]} -gt 0 ]; then
    rcli "${passthrough[@]}"
else
    rcli
fi
