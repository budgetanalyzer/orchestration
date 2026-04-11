#!/bin/bash

# verify-phase-1-credentials.sh
#
# Runtime verification for Security Hardening v2 Phase 1 credential isolation.
# Tests that per-service identities are enforced across PostgreSQL, RabbitMQ,
# Redis, and ext-authz.
#
# Prerequisites: Tilt running with all infrastructure pods healthy.
#
# Usage:
#   ./scripts/dev/verify-phase-1-credentials.sh

set -euo pipefail

PASSED=0
FAILED=0
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

PORT_FORWARD_PIDS=()
PORT_FORWARD_LOGS=()
TMP_FILES=()
PG_ADMIN_USER="postgres_admin"
RMQ_ADMIN_USER="rabbitmq-admin"
RMQ_CS_USER="currency-service"
REDIS_OPS_USER="redis-ops"
REDIS_SG_USER="session-gateway"
REDIS_EA_USER="ext-authz"
REDIS_CS_USER="currency-service"

usage() {
    cat <<'EOF'
Usage: ./scripts/dev/verify-phase-1-credentials.sh

Options:
  -h, --help                    Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

section() { printf '\n=== %s ===\n' "$1"; }
pass()    { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail()    { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

cleanup() {
    set +e
    for pid in "${PORT_FORWARD_PIDS[@]:-}"; do
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    done
    for file in "${PORT_FORWARD_LOGS[@]:-}"; do
        [ -n "${file:-}" ] && rm -f "$file"
    done
    for file in "${TMP_FILES[@]:-}"; do
        [ -n "${file:-}" ] && rm -f "$file"
    done
}

trap cleanup EXIT

require_host_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

current_context() {
    kubectl config current-context 2>/dev/null || printf 'unknown'
}

require_cluster_access() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes cluster from current kubectl context (%s)\n' "$(current_context)" >&2
        exit 1
    fi
}

namespace_exists() {
    kubectl get namespace "$1" >/dev/null 2>&1
}

pod_count() {
    kubectl get pods -n "$1" --no-headers 2>/dev/null | wc -l | tr -d ' '
}

find_pod() {
    local namespace="$1"
    local selector="$2"

    kubectl get pods -n "$namespace" -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

require_pod() {
    local namespace="$1"
    local selector="$2"
    local label="$3"
    local pod

    if ! namespace_exists "$namespace"; then
        printf 'ERROR: namespace %s not found in current kubectl context (%s)\n' "$namespace" "$(current_context)" >&2
        exit 1
    fi

    pod=$(find_pod "$namespace" "$selector")
    if [ -z "$pod" ]; then
        printf 'ERROR: %s pod not found in namespace %s (context: %s, pods in namespace: %s)\n' \
            "$label" "$namespace" "$(current_context)" "$(pod_count "$namespace")" >&2
        printf '       Tilt may be stopped, still reconciling, or running against a different cluster/context than kubectl.\n' >&2
        exit 1
    fi

    printf '%s' "$pod"
}

read_secret() {
    local namespace="$1"
    local secret_name="$2"
    local key="$3"
    local encoded

    encoded=$(kubectl get secret "$secret_name" -n "$namespace" -o "jsonpath={.data['${key}']}" 2>/dev/null || true)
    if [ -z "$encoded" ]; then
        return 1
    fi

    printf '%s' "$encoded" | base64 -d
}

require_secret_exists() {
    local namespace="$1"
    local secret_name="$2"

    if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        printf 'ERROR: required secret not found: %s/%s (context: %s)\n' \
            "$namespace" "$secret_name" "$(current_context)" >&2
        exit 1
    fi
}

require_secret_value() {
    local namespace="$1"
    local secret_name="$2"
    local key="$3"
    local value

    require_secret_exists "$namespace" "$secret_name"
    value=$(read_secret "$namespace" "$secret_name" "$key" || true)
    if [ -z "$value" ]; then
        printf 'ERROR: missing secret value %s/%s[%s] (context: %s)\n' \
            "$namespace" "$secret_name" "$key" "$(current_context)" >&2
        exit 1
    fi

    printf '%s' "$value"
}

start_port_forward() {
    local namespace="$1"
    local resource="$2"
    local remote_port="$3"
    local log_file
    local pid
    local forwarded_port

    log_file=$(mktemp)
    TMP_FILES+=("$log_file")

    kubectl port-forward -n "$namespace" "$resource" ":${remote_port}" >"$log_file" 2>&1 &
    pid=$!

    PORT_FORWARD_PIDS+=("$pid")
    PORT_FORWARD_LOGS+=("$log_file")

    for _ in $(seq 1 50); do
        if grep -q 'Forwarding from 127\.0\.0\.1:' "$log_file"; then
            forwarded_port=$(sed -nE 's/.*127\.0\.0\.1:([0-9]+).*/\1/p' "$log_file" | head -n1)
            if [ -n "$forwarded_port" ]; then
                printf '%s' "$forwarded_port"
                return 0
            fi
        fi

        if ! kill -0 "$pid" >/dev/null 2>&1; then
            break
        fi

        sleep 0.2
    done

    printf 'ERROR: failed to port-forward %s in namespace %s on remote port %s\n' "$resource" "$namespace" "$remote_port" >&2
    cat "$log_file" >&2
    exit 1
}

HTTP_STATUS=""
HTTP_HEADERS=""
HTTP_BODY=""

http_request() {
    local method="$1"
    local url="$2"
    local user="${3:-}"
    local password="${4:-}"
    local body="${5:-}"

    HTTP_HEADERS=$(mktemp)
    HTTP_BODY=$(mktemp)
    TMP_FILES+=("$HTTP_HEADERS" "$HTTP_BODY")

    local -a curl_args
    curl_args=(curl -sS -D "$HTTP_HEADERS" -o "$HTTP_BODY" -w '%{http_code}' -X "$method")

    if [ -n "$user" ]; then
        curl_args+=(-u "${user}:${password}")
    fi

    if [ -n "$body" ]; then
        curl_args+=(-H 'content-type: application/json' -d "$body")
    fi

    curl_args+=("$url")

    HTTP_STATUS="$("${curl_args[@]}")"
}

pg_query() {
    local user="$1"
    local password="$2"
    local database="$3"
    local sql="${4:-SELECT 1;}"

    # shellcheck disable=SC2016
    kubectl exec -n infrastructure "$POSTGRES_POD" -- \
        /bin/sh -ceu 'PGPASSWORD="$1" psql -X -tA -U "$2" -d "$3" -c "$4"' \
        sh "$password" "$user" "$database" "$sql" 2>&1 || true
}

redis_cmd() {
    local user="$1"
    local password="$2"
    shift 2

    redis_cli_in_pod infrastructure "$REDIS_POD" "$user" "$password" "$@" 2>&1 || true
}

rmq_ctl() {
    kubectl exec -n infrastructure "$RABBITMQ_POD" -- \
        rabbitmqctl --quiet "$@" 2>&1 || true
}

rmq_authenticate() {
    kubectl exec -n infrastructure "$RABBITMQ_POD" -- \
        rabbitmqctl authenticate_user "$1" "$2" >/dev/null 2>&1
}

pg_expect_ok() {
    local user="$1"
    local password="$2"
    local database="$3"
    local out

    out=$(pg_query "$user" "$password" "$database")
    if echo "$out" | grep -q '^1$'; then
        pass "$user -> $database"
    else
        fail "$user -> $database (got: ${out:0:120})"
    fi
}

pg_expect_denied() {
    local user="$1"
    local password="$2"
    local database="$3"
    local out

    out=$(pg_query "$user" "$password" "$database")
    if echo "$out" | grep -qi 'permission denied\|FATAL'; then
        pass "$user denied on $database"
    else
        fail "$user NOT denied on $database (got: ${out:0:120})"
    fi
}

echo "=============================================="
echo "  Phase 1 Credential Verification"
echo "=============================================="

require_host_command kubectl
require_host_command curl
require_cluster_access

POSTGRES_POD=$(require_pod infrastructure app=postgresql PostgreSQL)
RABBITMQ_POD=$(require_pod infrastructure app=rabbitmq RabbitMQ)
REDIS_POD=$(require_pod infrastructure app=redis Redis)
EXT_AUTHZ_POD=$(require_pod default app=ext-authz ext-authz)

PG_ADMIN_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials password)
PG_TXN_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials transaction-service-password)
PG_CUR_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials currency-service-password)
PG_PER_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials permission-service-password)

RMQ_ADMIN_PASS=$(require_secret_value infrastructure rabbitmq-bootstrap-credentials password)
RMQ_CS_PASS=$(require_secret_value default currency-service-rabbitmq-credentials password)

REDIS_OPS_PASS=$(require_secret_value infrastructure redis-bootstrap-credentials ops-password)
REDIS_SG_PASS=$(require_secret_value infrastructure redis-bootstrap-credentials session-gateway-password)
REDIS_EA_PASS=$(require_secret_value infrastructure redis-bootstrap-credentials ext-authz-password)
REDIS_CS_PASS=$(require_secret_value infrastructure redis-bootstrap-credentials currency-service-password)

section "PostgreSQL: Positive (service user -> own database)"

pg_expect_ok "transaction_service" "$PG_TXN_PASS" "budget_analyzer"
pg_expect_ok "currency_service" "$PG_CUR_PASS" "currency"
pg_expect_ok "permission_service" "$PG_PER_PASS" "permission"

section "PostgreSQL: Negative (service user denied on other databases)"

pg_expect_denied "transaction_service" "$PG_TXN_PASS" "currency"
pg_expect_denied "transaction_service" "$PG_TXN_PASS" "permission"
pg_expect_denied "currency_service" "$PG_CUR_PASS" "budget_analyzer"
pg_expect_denied "currency_service" "$PG_CUR_PASS" "permission"
pg_expect_denied "permission_service" "$PG_PER_PASS" "budget_analyzer"
pg_expect_denied "permission_service" "$PG_PER_PASS" "currency"

section "PostgreSQL: Break-glass (${PG_ADMIN_USER} -> all databases)"

pg_expect_ok "$PG_ADMIN_USER" "$PG_ADMIN_PASS" "budget_analyzer"
pg_expect_ok "$PG_ADMIN_USER" "$PG_ADMIN_PASS" "currency"
pg_expect_ok "$PG_ADMIN_USER" "$PG_ADMIN_PASS" "permission"

section "RabbitMQ: Live credential and permission checks"

if rmq_authenticate "$RMQ_ADMIN_USER" "$RMQ_ADMIN_PASS"; then
    pass "${RMQ_ADMIN_USER} credentials authenticate"
else
    fail "${RMQ_ADMIN_USER} credentials authenticate"
fi

if rmq_authenticate "$RMQ_CS_USER" "$RMQ_CS_PASS"; then
    pass "${RMQ_CS_USER} credentials authenticate"
else
    fail "${RMQ_CS_USER} credentials authenticate"
fi

RMQ_USERS=$(rmq_ctl list_users)
if echo "$RMQ_USERS" | grep "^${RMQ_ADMIN_USER}" | grep -q 'administrator'; then
    pass "${RMQ_ADMIN_USER} exists with administrator tag"
else
    fail "${RMQ_ADMIN_USER} missing or lacks administrator tag"
fi

if echo "$RMQ_USERS" | grep -q '^guest'; then
    fail "guest user still exists"
else
    pass "guest user removed"
fi

RMQ_API_PORT=$(start_port_forward infrastructure service/rabbitmq 15672)
http_request GET "http://127.0.0.1:${RMQ_API_PORT}/api/whoami" "$RMQ_ADMIN_USER" "$RMQ_ADMIN_PASS"
if [ "$HTTP_STATUS" = "200" ] \
    && grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${RMQ_ADMIN_USER}\"" "$HTTP_BODY" \
    && grep -q 'administrator' "$HTTP_BODY"; then
    pass "${RMQ_ADMIN_USER} can access Management API"
else
    fail "${RMQ_ADMIN_USER} cannot access Management API (status=${HTTP_STATUS})"
fi

http_request GET "http://127.0.0.1:${RMQ_API_PORT}/api/permissions" "$RMQ_ADMIN_USER" "$RMQ_ADMIN_PASS"
if [ "$HTTP_STATUS" = "200" ] \
    && grep -Eq "\"user\"[[:space:]]*:[[:space:]]*\"${RMQ_CS_USER}\"" "$HTTP_BODY" \
    && grep -q '"configure"' "$HTTP_BODY" \
    && grep -q '"write"' "$HTTP_BODY" \
    && grep -q '"read"' "$HTTP_BODY"; then
    pass "${RMQ_ADMIN_USER} can inspect broker permissions via Management API"
else
    fail "${RMQ_ADMIN_USER} cannot inspect broker permissions via Management API (status=${HTTP_STATUS})"
fi

RMQ_PERMISSIONS=$(rmq_ctl list_permissions -p /)
if echo "$RMQ_PERMISSIONS" | grep -Eq "^${RMQ_ADMIN_USER}[[:space:]]" \
    && echo "$RMQ_PERMISSIONS" | grep -Eq "^${RMQ_CS_USER}[[:space:]]"; then
    pass "rabbitmqctl list_permissions returns broker permissions for /"
else
    fail "rabbitmqctl list_permissions missing expected entries (got: ${RMQ_PERMISSIONS:0:200})"
fi

# Verify currency-service AMQP permission regexes via rabbitmqctl
# (currency-service has no management tag, so Management API returns 401)
RMQ_CS_PERM_LINE=$(rmq_ctl list_permissions -p / | grep "^${RMQ_CS_USER}[[:space:]]")
RMQ_CS_CONFIGURE=$(echo "$RMQ_CS_PERM_LINE" | awk '{print $2}')
RMQ_CS_WRITE=$(echo "$RMQ_CS_PERM_LINE" | awk '{print $3}')

RMQ_ALLOWED_NAME="amq.gen.phase1.verify.$RANDOM.$RANDOM"
RMQ_FORBIDDEN_NAME="phase1.forbidden.verify.$RANDOM.$RANDOM"

if echo "$RMQ_ALLOWED_NAME" | grep -Eq "^${RMQ_CS_CONFIGURE}$"; then
    pass "${RMQ_CS_USER} configure regex matches ${RMQ_ALLOWED_NAME}"
else
    fail "${RMQ_CS_USER} configure regex does not match ${RMQ_ALLOWED_NAME} (regex=${RMQ_CS_CONFIGURE})"
fi

if echo "amq.default" | grep -Eq "^${RMQ_CS_WRITE}$"; then
    pass "${RMQ_CS_USER} write regex matches amq.default"
else
    fail "${RMQ_CS_USER} write regex does not match amq.default (regex=${RMQ_CS_WRITE})"
fi

if echo "$RMQ_FORBIDDEN_NAME" | grep -Eq "^${RMQ_CS_CONFIGURE}$"; then
    fail "${RMQ_CS_USER} configure regex incorrectly matches ${RMQ_FORBIDDEN_NAME}"
else
    pass "${RMQ_CS_USER} configure regex denies ${RMQ_FORBIDDEN_NAME}"
fi

if echo "$RMQ_FORBIDDEN_NAME" | grep -Eq "^${RMQ_CS_WRITE}$"; then
    fail "${RMQ_CS_USER} write regex incorrectly matches ${RMQ_FORBIDDEN_NAME}"
else
    pass "${RMQ_CS_USER} write regex denies ${RMQ_FORBIDDEN_NAME}"
fi

section "Redis: Positive (authorized operations)"

VERIFY_KEY="__phase1_verify__"

SG_SET=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" SET "session:${VERIFY_KEY}" "ok")
SG_GET=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" GET "session:${VERIFY_KEY}")
redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" DEL "session:${VERIFY_KEY}" >/dev/null 2>&1 || true
if [ "$SG_SET" = "OK" ] && [ "$SG_GET" = "ok" ]; then
    pass "session-gateway SET/GET on session:*"
else
    fail "session-gateway SET/GET on session:* (SET=${SG_SET}, GET=${SG_GET})"
fi

EA_SG_HSET=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" HSET "oauth2:state:${VERIFY_KEY}" "redirect_uri" "/login/oauth2/code/idp")
redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" DEL "oauth2:state:${VERIFY_KEY}" >/dev/null 2>&1 || true
if echo "$EA_SG_HSET" | grep -qE '^[0-9]+$'; then
    pass "session-gateway HSET on oauth2:state:*"
else
    fail "session-gateway HSET on oauth2:state:* (${EA_SG_HSET})"
fi

redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" HSET "session:${VERIFY_KEY}" "field" "value" >/dev/null 2>&1
EA_READ=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" HGETALL "session:${VERIFY_KEY}")
redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" DEL "session:${VERIFY_KEY}" >/dev/null 2>&1 || true
if echo "$EA_READ" | grep -q 'value'; then
    pass "ext-authz HGETALL on session:*"
else
    fail "ext-authz HGETALL on session:* (${EA_READ})"
fi

EA_PING=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" PING)
if [ "$EA_PING" = "PONG" ]; then
    pass "ext-authz PING"
else
    fail "ext-authz PING (${EA_PING})"
fi

CS_SET=$(redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" SET "currency-service:${VERIFY_KEY}" "ok")
CS_GET=$(redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" GET "currency-service:${VERIFY_KEY}")
redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" DEL "currency-service:${VERIFY_KEY}" >/dev/null 2>&1 || true
if [ "$CS_SET" = "OK" ] && [ "$CS_GET" = "ok" ]; then
    pass "currency-service SET/GET on currency-service:*"
else
    fail "currency-service SET/GET on currency-service:* (SET=${CS_SET}, GET=${CS_GET})"
fi

section "Redis: Negative (unauthorized operations denied)"

EA_SET=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" SET "session:${VERIFY_KEY}" "nope")
if echo "$EA_SET" | grep -qi 'NOPERM'; then
    pass "ext-authz denied SET command"
else
    fail "ext-authz NOT denied SET (${EA_SET})"
fi

EA_CROSS=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" HGETALL "oauth2:state:anything")
if echo "$EA_CROSS" | grep -qi 'NOPERM'; then
    pass "ext-authz denied on oauth2:state:* keys"
else
    fail "ext-authz NOT denied on oauth2:state:* (${EA_CROSS})"
fi

CS_CROSS=$(redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" GET "session:anything")
if echo "$CS_CROSS" | grep -qi 'NOPERM'; then
    pass "currency-service denied on session:* keys"
else
    fail "currency-service NOT denied on session:* (${CS_CROSS})"
fi

SG_CROSS=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" GET "currency-service:anything")
if echo "$SG_CROSS" | grep -qi 'NOPERM'; then
    pass "session-gateway denied on currency-service:* keys"
else
    fail "session-gateway NOT denied on currency-service:* (${SG_CROSS})"
fi

section "Redis: Break-glass (${REDIS_OPS_USER})"

OPS_WHOAMI=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" ACL WHOAMI)
if [ "$OPS_WHOAMI" = "$REDIS_OPS_USER" ]; then
    pass "${REDIS_OPS_USER} ACL WHOAMI"
else
    fail "${REDIS_OPS_USER} ACL WHOAMI (${OPS_WHOAMI})"
fi

OPS_CONFIG=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" CONFIG GET maxmemory)
if echo "$OPS_CONFIG" | grep -q 'maxmemory'; then
    pass "${REDIS_OPS_USER} CONFIG GET"
else
    fail "${REDIS_OPS_USER} CONFIG GET (${OPS_CONFIG})"
fi

OPS_DB15_SET=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" -n 15 SET "__phase1_flushdb__" "ok")
OPS_DB15_FLUSH=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" -n 15 FLUSHDB ASYNC)
sleep 1
OPS_DB15_EXISTS=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" -n 15 EXISTS "__phase1_flushdb__")
if [ "$OPS_DB15_SET" = "OK" ] && [ "$OPS_DB15_FLUSH" = "OK" ] && [ "$OPS_DB15_EXISTS" = "0" ]; then
    pass "${REDIS_OPS_USER} FLUSHDB on isolated DB"
else
    fail "${REDIS_OPS_USER} FLUSHDB on isolated DB (SET=${OPS_DB15_SET}, FLUSH=${OPS_DB15_FLUSH}, EXISTS=${OPS_DB15_EXISTS})"
fi

section "ext-authz: Live Redis username/password validation"

if kubectl get pod -n default "$EXT_AUTHZ_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null | grep -q '^true$'; then
    pass "ext-authz pod is Ready"
else
    fail "ext-authz pod is not Ready"
fi

EXT_AUTHZ_HEALTH_PORT=$(start_port_forward default deployment/ext-authz 8090)
EXT_AUTHZ_HTTP_PORT=$(start_port_forward default deployment/ext-authz 9002)

http_request GET "http://127.0.0.1:${EXT_AUTHZ_HEALTH_PORT}/healthz"
if [ "$HTTP_STATUS" = "200" ] && grep -qi '^ok$' "$HTTP_BODY"; then
    pass "ext-authz /healthz returns 200"
else
    fail "ext-authz /healthz failed (status=${HTTP_STATUS})"
fi

EXT_AUTHZ_SESSION_ID="phase1-verify-$RANDOM-$RANDOM"
"${SCRIPT_DIR}/../ops/seed-ext-authz-session.sh" "$EXT_AUTHZ_SESSION_ID" >/dev/null

AUTH_HEADERS=$(mktemp)
TMP_FILES+=("$AUTH_HEADERS")
AUTH_STATUS=$(curl -sS -D "$AUTH_HEADERS" -o /dev/null -w '%{http_code}' \
    -H "Cookie: BA_SESSION=${EXT_AUTHZ_SESSION_ID}" \
    -H 'X-Envoy-Original-Path: /api/v1/currencies' \
    "http://127.0.0.1:${EXT_AUTHZ_HTTP_PORT}/check")

if [ "$AUTH_STATUS" = "200" ] \
    && grep -qi '^X-User-Id: test-user-001' "$AUTH_HEADERS" \
    && grep -qi '^X-Roles: ROLE_USER,ROLE_ADMIN' "$AUTH_HEADERS" \
    && grep -qi '^X-Permissions: transactions:read,transactions:write,currencies:read' "$AUTH_HEADERS"; then
    pass "ext-authz resolves a seeded session via Redis username/password auth"
else
    fail "ext-authz session lookup failed (status=${AUTH_STATUS})"
fi

redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" DEL "session:${EXT_AUTHZ_SESSION_ID}" >/dev/null 2>&1 || true

echo ""
echo "=============================================="
TOTAL=$((PASSED + FAILED))
if [ "$FAILED" -eq 0 ]; then
    echo "  ${PASSED} passed (out of ${TOTAL})"
else
    echo "  ${PASSED} passed, ${FAILED} failed (out of ${TOTAL})"
fi
echo "=============================================="

[ "$FAILED" -gt 0 ] && exit 1 || exit 0
