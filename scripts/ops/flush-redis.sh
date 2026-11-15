#!/bin/bash

# Flush a Redis instance (Kubernetes/Tilt).
#
# Usage:
#   ./scripts/ops/flush-redis.sh session
#   ./scripts/ops/flush-redis.sh cache

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/redis-cli.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x from repo root.
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

usage() {
    echo "Usage: $0 <session|cache>" >&2
}

if (( $# != 1 )); then
    usage
    exit 2
fi

case "$1" in
    session)
        REDIS_INSTANCE="redis-session"
        REWRITE_AOF=true
        ;;
    cache)
        REDIS_INSTANCE="redis-cache"
        REWRITE_AOF=false
        ;;
    *)
        usage
        exit 2
        ;;
esac

REDIS_BOOTSTRAP_SECRET="${REDIS_INSTANCE}-bootstrap-credentials"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Redis Flush Script: ${REDIS_INSTANCE} (Kubernetes)${NC}"
echo ""

printf -v confirm_prompt "%bWARNING: This will delete ALL data from %s. Continue? [y/N]:%b " "$RED" "$REDIS_INSTANCE" "$NC"
read -r -p "$confirm_prompt" -n 1
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && echo "Aborted." && exit 0

echo ""
echo -e "${YELLOW}Flushing Redis...${NC}"
echo ""

REDIS_POD=$(kubectl get pods -n infrastructure -l "app=${REDIS_INSTANCE}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$REDIS_POD" ]; then
    echo -e "${RED}${REDIS_INSTANCE} pod not found in infrastructure namespace${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Is Tilt running? Try: tilt up"
    echo "  2. Check pods: kubectl get pods -n infrastructure"
    exit 1
fi

echo -e "${YELLOW}Using Redis pod: $REDIS_POD${NC}"
echo ""

REDIS_INSTANCE_OPS_PASSWORD=$(kubectl get secret "$REDIS_BOOTSTRAP_SECRET" -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
if [ -z "$REDIS_INSTANCE_OPS_PASSWORD" ]; then
    echo -e "${RED}ERROR: ${REDIS_BOOTSTRAP_SECRET} is missing ops-password.${NC}" >&2
    exit 1
fi

flush_reply=$(redis_cli_in_pod "$REDIS_INSTANCE" infrastructure "$REDIS_POD" redis-ops "$REDIS_INSTANCE_OPS_PASSWORD" FLUSHALL 2>&1 | tr -d '\r' || true)
if [ "$flush_reply" != "OK" ]; then
    echo -e "${RED}ERROR: FLUSHALL on ${REDIS_INSTANCE} did not return OK: ${flush_reply}${NC}" >&2
    exit 1
fi

# The session instance persists AOF data on its PVC. Rewrite it so prior
# session tokens are removed from the persisted history. The disposable cache
# instance has persistence disabled and needs no rewrite.
if "$REWRITE_AOF"; then
    echo -e "${YELLOW}Rewriting the append-only file...${NC}"
    redis_cli_in_pod "$REDIS_INSTANCE" infrastructure "$REDIS_POD" redis-ops "$REDIS_INSTANCE_OPS_PASSWORD" BGREWRITEAOF > /dev/null 2>&1

    aof_info=""
    for _ in $(seq 1 60); do
        aof_info=$(redis_cli_in_pod "$REDIS_INSTANCE" infrastructure "$REDIS_POD" redis-ops "$REDIS_INSTANCE_OPS_PASSWORD" INFO persistence 2>/dev/null | tr -d '\r')
        if grep -qx 'aof_rewrite_in_progress:0' <<<"$aof_info" && grep -qx 'aof_rewrite_scheduled:0' <<<"$aof_info"; then
            break
        fi
        sleep 1
    done

    if ! grep -qx 'aof_rewrite_in_progress:0' <<<"$aof_info" \
        || ! grep -qx 'aof_rewrite_scheduled:0' <<<"$aof_info" \
        || ! grep -qx 'aof_last_bgrewrite_status:ok' <<<"$aof_info"; then
        echo -e "${RED}Redis was flushed, but the append-only file rewrite did not finish successfully${NC}"
        echo "Check: kubectl logs -n infrastructure $REDIS_POD"
        exit 1
    fi
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SUCCESS! ${REDIS_INSTANCE} has been flushed${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "All data in ${REDIS_INSTANCE} has been ${GREEN}cleared${NC}."
if [ "$REDIS_INSTANCE" = "redis-session" ]; then
    echo -e "Users will need to log in again."
fi
echo ""
