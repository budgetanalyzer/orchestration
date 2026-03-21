#!/bin/bash

# verify-phase-1-credentials.sh
#
# Runtime verification for Security Hardening v2 Phase 1 credential isolation.
# Tests that per-service identities are enforced across PostgreSQL, RabbitMQ,
# and Redis.
#
# Prerequisites: Tilt running with all infrastructure pods healthy.
#
# Usage:
#   ./scripts/dev/verify-phase-1-credentials.sh

set -euo pipefail

PASSED=0
FAILED=0

# ── Output helpers ─────────────────────────────────────────────────────────

section() { printf '\n━━━ %s ━━━\n' "$1"; }
pass()    { printf '  ✓ %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail()    { printf '  ✗ %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

# ── Secret reader ──────────────────────────────────────────────────────────

read_secret() {
    local ns="$1" name="$2" key="$3"
    kubectl get secret "$name" -n "$ns" -o "jsonpath={.data['${key}']}" | base64 -d
}

# ── Pod discovery ──────────────────────────────────────────────────────────

echo "=============================================="
echo "  Phase 1 Credential Verification"
echo "=============================================="

POSTGRES_POD=$(kubectl get pods -n infrastructure -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
RABBITMQ_POD=$(kubectl get pods -n infrastructure -l app=rabbitmq -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
REDIS_POD=$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

for var in POSTGRES_POD RABBITMQ_POD REDIS_POD; do
    if [ -z "${!var}" ]; then
        printf 'ERROR: %s not found. Is Tilt running?\n' "$var" >&2
        exit 1
    fi
done

# ── Read credentials from Kubernetes Secrets ───────────────────────────────

PG_ADMIN_USER=$(read_secret infrastructure postgresql-bootstrap-credentials username)
PG_ADMIN_PASS=$(read_secret infrastructure postgresql-bootstrap-credentials password)
PG_TXN_PASS=$(read_secret infrastructure postgresql-bootstrap-credentials transaction-service-password)
PG_CUR_PASS=$(read_secret infrastructure postgresql-bootstrap-credentials currency-service-password)
PG_PER_PASS=$(read_secret infrastructure postgresql-bootstrap-credentials permission-service-password)

RMQ_ADMIN_USER=$(read_secret infrastructure rabbitmq-bootstrap-credentials username)
RMQ_CS_USER=$(read_secret infrastructure rabbitmq-bootstrap-credentials currency-service-username)

REDIS_OPS_USER=$(read_secret infrastructure redis-bootstrap-credentials ops-username)
REDIS_OPS_PASS=$(read_secret infrastructure redis-bootstrap-credentials ops-password)
REDIS_SG_USER=$(read_secret infrastructure redis-bootstrap-credentials session-gateway-username)
REDIS_SG_PASS=$(read_secret infrastructure redis-bootstrap-credentials session-gateway-password)
REDIS_EA_USER=$(read_secret infrastructure redis-bootstrap-credentials ext-authz-username)
REDIS_EA_PASS=$(read_secret infrastructure redis-bootstrap-credentials ext-authz-password)
REDIS_CS_USER=$(read_secret infrastructure redis-bootstrap-credentials currency-service-username)
REDIS_CS_PASS=$(read_secret infrastructure redis-bootstrap-credentials currency-service-password)

# ── Infrastructure test helpers ────────────────────────────────────────────

pg_query() {
    local user="$1" pass="$2" db="$3" sql="${4:-SELECT 1;}"
    kubectl exec -n infrastructure "$POSTGRES_POD" -- \
        /bin/sh -ceu 'PGPASSWORD="$1" psql -X -tA -U "$2" -d "$3" -c "$4"' \
        sh "$pass" "$user" "$db" "$sql" 2>&1 || true
}

redis_cmd() {
    local user="$1" pass="$2"; shift 2
    kubectl exec -n infrastructure "$REDIS_POD" -- \
        redis-cli --user "$user" --pass "$pass" --no-auth-warning "$@" 2>&1 || true
}

rmq_ctl() {
    kubectl exec -n infrastructure "$RABBITMQ_POD" -- \
        rabbitmqctl --quiet "$@" 2>&1 || true
}

# ════════════════════════════════════════════════════════════════════════════
# PostgreSQL
# ════════════════════════════════════════════════════════════════════════════

pg_expect_ok() {
    local user="$1" pass="$2" db="$3"
    local out
    out=$(pg_query "$user" "$pass" "$db")
    if echo "$out" | grep -q '^1$'; then
        pass "$user -> $db"
    else
        fail "$user -> $db (got: ${out:0:80})"
    fi
}

pg_expect_denied() {
    local user="$1" pass="$2" db="$3"
    local out
    out=$(pg_query "$user" "$pass" "$db")
    if echo "$out" | grep -qi 'denied\|FATAL'; then
        pass "$user denied on $db"
    else
        fail "$user NOT denied on $db (got: ${out:0:80})"
    fi
}

section "PostgreSQL: Positive (service user -> own database)"

pg_expect_ok "transaction_service" "$PG_TXN_PASS" "budget_analyzer"
pg_expect_ok "currency_service"    "$PG_CUR_PASS" "currency"
pg_expect_ok "permission_service"  "$PG_PER_PASS" "permission"

section "PostgreSQL: Negative (service user denied on other databases)"

pg_expect_denied "transaction_service" "$PG_TXN_PASS" "currency"
pg_expect_denied "transaction_service" "$PG_TXN_PASS" "permission"
pg_expect_denied "currency_service"    "$PG_CUR_PASS" "budget_analyzer"
pg_expect_denied "currency_service"    "$PG_CUR_PASS" "permission"
pg_expect_denied "permission_service"  "$PG_PER_PASS" "budget_analyzer"
pg_expect_denied "permission_service"  "$PG_PER_PASS" "currency"

section "PostgreSQL: Break-glass (${PG_ADMIN_USER} -> all databases)"

pg_expect_ok "$PG_ADMIN_USER" "$PG_ADMIN_PASS" "budget_analyzer"
pg_expect_ok "$PG_ADMIN_USER" "$PG_ADMIN_PASS" "currency"
pg_expect_ok "$PG_ADMIN_USER" "$PG_ADMIN_PASS" "permission"

# ════════════════════════════════════════════════════════════════════════════
# RabbitMQ
# ════════════════════════════════════════════════════════════════════════════

section "RabbitMQ: User and permission verification"

RMQ_USERS=$(rmq_ctl list_users)

# Positive: admin user with administrator tag
if echo "$RMQ_USERS" | grep "^${RMQ_ADMIN_USER}" | grep -q 'administrator'; then
    pass "${RMQ_ADMIN_USER} exists with administrator tag"
else
    fail "${RMQ_ADMIN_USER} missing or lacks administrator tag"
fi

# Positive: currency-service user exists
if echo "$RMQ_USERS" | grep -q "^${RMQ_CS_USER}"; then
    pass "${RMQ_CS_USER} user exists"
else
    fail "${RMQ_CS_USER} user missing"
fi

# Negative: guest user removed
if echo "$RMQ_USERS" | grep -q '^guest'; then
    fail "guest user still exists"
else
    pass "guest user removed"
fi

# Negative: currency-service configure permission is scoped (not ".*")
CS_PERMS=$(rmq_ctl list_user_permissions "$RMQ_CS_USER")
CS_CONFIGURE=$(echo "$CS_PERMS" | awk -F'\t' '/^\// { print $2 }')

if [ -n "$CS_CONFIGURE" ] && [ "$CS_CONFIGURE" != ".*" ]; then
    pass "${RMQ_CS_USER} configure permission scoped"
else
    fail "${RMQ_CS_USER} configure permission unrestricted or missing"
fi

# Break-glass: admin has full permissions
ADMIN_PERMS=$(rmq_ctl list_user_permissions "$RMQ_ADMIN_USER")
ADMIN_CONFIGURE=$(echo "$ADMIN_PERMS" | awk -F'\t' '/^\// { print $2 }')

if [ "$ADMIN_CONFIGURE" = ".*" ]; then
    pass "${RMQ_ADMIN_USER} has full permissions"
else
    fail "${RMQ_ADMIN_USER} configure permission restricted: ${ADMIN_CONFIGURE}"
fi

# ════════════════════════════════════════════════════════════════════════════
# Redis
# ════════════════════════════════════════════════════════════════════════════

VKEY="__phase1_verify__"

section "Redis: Positive (authorized operations)"

# session-gateway: SET/GET on spring:session:*
SG_SET=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" SET "spring:session:${VKEY}" "ok")
SG_GET=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" GET "spring:session:${VKEY}")
redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" DEL "spring:session:${VKEY}" >/dev/null 2>&1 || true

if [ "$SG_SET" = "OK" ] && [ "$SG_GET" = "ok" ]; then
    pass "session-gateway SET/GET on spring:session:*"
else
    fail "session-gateway SET/GET on spring:session:* (SET=${SG_SET}, GET=${SG_GET})"
fi

# session-gateway: write to extauthz:session:* (dual namespace access)
EA_SG_HSET=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" HSET "extauthz:session:${VKEY}" "field" "value")
redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" DEL "extauthz:session:${VKEY}" >/dev/null 2>&1 || true

if echo "$EA_SG_HSET" | grep -qE '^[0-9]+$'; then
    pass "session-gateway HSET on extauthz:session:*"
else
    fail "session-gateway HSET on extauthz:session:* (${EA_SG_HSET})"
fi

# ext-authz: read extauthz session hashes
redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" HSET "extauthz:session:${VKEY}" "field" "value" >/dev/null 2>&1
EA_READ=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" HGETALL "extauthz:session:${VKEY}")
redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" DEL "extauthz:session:${VKEY}" >/dev/null 2>&1 || true

if echo "$EA_READ" | grep -q 'value'; then
    pass "ext-authz HGETALL on extauthz:session:*"
else
    fail "ext-authz HGETALL on extauthz:session:* (${EA_READ})"
fi

# ext-authz: PING
EA_PING=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" PING)
if [ "$EA_PING" = "PONG" ]; then
    pass "ext-authz PING"
else
    fail "ext-authz PING (${EA_PING})"
fi

# currency-service: SET/GET on currency-service:*
CS_SET=$(redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" SET "currency-service:${VKEY}" "ok")
CS_GET=$(redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" GET "currency-service:${VKEY}")
redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" DEL "currency-service:${VKEY}" >/dev/null 2>&1 || true

if [ "$CS_SET" = "OK" ] && [ "$CS_GET" = "ok" ]; then
    pass "currency-service SET/GET on currency-service:*"
else
    fail "currency-service SET/GET on currency-service:* (SET=${CS_SET}, GET=${CS_GET})"
fi

section "Redis: Negative (unauthorized operations denied)"

# ext-authz: SET denied (command not in allow-list)
EA_SET=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" SET "extauthz:session:${VKEY}" "nope")
if echo "$EA_SET" | grep -qi 'NOPERM'; then
    pass "ext-authz denied SET command"
else
    fail "ext-authz NOT denied SET (${EA_SET})"
fi

# ext-authz: wrong key pattern
EA_CROSS=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" HGETALL "spring:session:anything")
if echo "$EA_CROSS" | grep -qi 'NOPERM'; then
    pass "ext-authz denied on spring:session:* keys"
else
    fail "ext-authz NOT denied on spring:session:* (${EA_CROSS})"
fi

# currency-service: wrong key pattern
CS_CROSS=$(redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" GET "spring:session:anything")
if echo "$CS_CROSS" | grep -qi 'NOPERM'; then
    pass "currency-service denied on spring:session:* keys"
else
    fail "currency-service NOT denied on spring:session:* (${CS_CROSS})"
fi

# session-gateway: wrong key pattern
SG_CROSS=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" GET "currency-service:anything")
if echo "$SG_CROSS" | grep -qi 'NOPERM'; then
    pass "session-gateway denied on currency-service:* keys"
else
    fail "session-gateway NOT denied on currency-service:* (${SG_CROSS})"
fi

section "Redis: Break-glass (${REDIS_OPS_USER})"

OPS_DBSIZE=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" DBSIZE)
if echo "$OPS_DBSIZE" | grep -qi 'keys'; then
    pass "${REDIS_OPS_USER} DBSIZE"
else
    fail "${REDIS_OPS_USER} DBSIZE (${OPS_DBSIZE})"
fi

OPS_CONFIG=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" CONFIG GET maxmemory)
if echo "$OPS_CONFIG" | grep -q 'maxmemory'; then
    pass "${REDIS_OPS_USER} CONFIG GET (admin command)"
else
    fail "${REDIS_OPS_USER} CONFIG GET (${OPS_CONFIG})"
fi

# ════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "=============================================="
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo "  All ${TOTAL} Phase 1 credential checks passed"
else
    echo "  ${PASSED} passed, ${FAILED} FAILED (out of ${TOTAL})"
fi
echo "=============================================="

[ "$FAILED" -gt 0 ] && exit 1 || exit 0
