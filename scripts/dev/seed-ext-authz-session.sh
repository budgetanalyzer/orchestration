#!/bin/bash
# Usage: ./scripts/dev/seed-ext-authz-session.sh [session-id]
# Creates a test session in Redis for ext-authz development/testing.
REDIS_POD=$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}')
SESSION_ID="${1:-test-session-001}"
EXPIRES_AT=$(date -d '+30 minutes' +%s 2>/dev/null || date -v+30M +%s)
kubectl exec -n infrastructure "$REDIS_POD" -- redis-cli HSET \
  "extauthz:session:${SESSION_ID}" \
  user_id "test-user-001" \
  roles "ROLE_USER,ROLE_ADMIN" \
  permissions "transactions:read,transactions:write,currencies:read" \
  created_at "$(date +%s)" \
  expires_at "${EXPIRES_AT}"
kubectl exec -n infrastructure "$REDIS_POD" -- redis-cli EXPIRE \
  "extauthz:session:${SESSION_ID}" 1800
echo "Seeded session: extauthz:session:${SESSION_ID}"
