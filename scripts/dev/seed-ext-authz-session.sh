#!/bin/bash
# Usage: ./scripts/dev/seed-ext-authz-session.sh [session-id]
# Creates a test session in Redis for ext-authz development/testing.

set -euo pipefail

REDIS_POD=$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$REDIS_POD" ]; then
    echo "ERROR: Redis pod not found in infrastructure namespace. Is Tilt running?" >&2
    exit 1
fi

REDIS_USERNAME=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-username}' | base64 -d)
REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)

if [ -z "$REDIS_USERNAME" ] || [ -z "$REDIS_OPS_PASSWORD" ]; then
    echo "ERROR: redis-bootstrap-credentials is missing redis-ops credentials." >&2
    exit 1
fi

SESSION_ID="${1:-test-session-001}"
EXPIRES_AT=$(date -d '+30 minutes' +%s 2>/dev/null || date -v+30M +%s)

kubectl exec -n infrastructure "$REDIS_POD" -- \
    redis-cli --user "$REDIS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning HSET \
    "extauthz:session:${SESSION_ID}" \
    user_id "test-user-001" \
    roles "ROLE_USER,ROLE_ADMIN" \
    permissions "transactions:read,transactions:write,currencies:read" \
    created_at "$(date +%s)" \
    expires_at "${EXPIRES_AT}" >/dev/null

kubectl exec -n infrastructure "$REDIS_POD" -- \
    redis-cli --user "$REDIS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning EXPIRE \
    "extauthz:session:${SESSION_ID}" 1800 >/dev/null

echo "Seeded session: extauthz:session:${SESSION_ID}"
