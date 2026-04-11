#!/bin/bash
# Usage: ./scripts/ops/seed-ext-authz-session.sh [session-id]
# Creates a test session in Redis for ext-authz development/testing.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

REDIS_POD=$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$REDIS_POD" ]; then
    echo "ERROR: Redis pod not found in infrastructure namespace. Is Tilt running?" >&2
    exit 1
fi

REDIS_USERNAME="redis-ops"
REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)

if [ -z "$REDIS_USERNAME" ] || [ -z "$REDIS_OPS_PASSWORD" ]; then
    echo "ERROR: redis-bootstrap-credentials is missing redis-ops credentials." >&2
    exit 1
fi

SESSION_ID="${1:-test-session-001}"
SESSION_TTL_SECONDS="${SESSION_TTL_SECONDS:-900}"
EXPIRES_AT="$(($(date +%s) + SESSION_TTL_SECONDS))"

redis_cli_in_pod infrastructure "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" HSET \
    "session:${SESSION_ID}" \
    user_id "test-user-001" \
    roles "ROLE_USER,ROLE_ADMIN" \
    permissions "transactions:read,transactions:write,currencies:read" \
    created_at "$(date +%s)" \
    expires_at "${EXPIRES_AT}" >/dev/null

redis_cli_in_pod infrastructure "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" EXPIRE \
    "session:${SESSION_ID}" "${SESSION_TTL_SECONDS}" >/dev/null

echo "Seeded session: session:${SESSION_ID}"
