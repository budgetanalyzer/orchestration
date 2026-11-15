#!/bin/bash

# verify-credential-isolation.sh
#
# Runtime verification for credential isolation.
# Tests that per-service identities are enforced across PostgreSQL, RabbitMQ,
# Redis, and ext-authz.
#
# Prerequisites: Tilt running with all infrastructure pods healthy.
#
# Usage:
#   ./scripts/smoketest/verify-credential-isolation.sh

set -euo pipefail

PASSED=0
FAILED=0
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/redis-cli.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

PORT_FORWARD_PIDS=()
PORT_FORWARD_LOGS=()
TMP_FILES=()
PG_ADMIN_USER="postgres_admin"
RMQ_ADMIN_USER="rabbitmq-admin"
RMQ_CS_USER="currency-service"
REDIS_OPS_USER="redis-ops"
REDIS_DEFAULT_USER="default"
REDIS_HEALTH_USER="redis-health"
REDIS_SESSION_PROBE_COMMAND="redis-cli -e --tls --cacert /tls-ca/ca.crt --user ${REDIS_HEALTH_USER} ping"
REDIS_SG_USER="session-gateway"
REDIS_EA_USER="ext-authz"
REDIS_CS_USER="currency-service"

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-credential-isolation.sh

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
    local output_variable="$4"
    local log_file
    local pid
    local forwarded_port

    if [[ ! "$output_variable" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        printf 'ERROR: invalid port-forward output variable: %s\n' "$output_variable" >&2
        exit 1
    fi

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
                printf -v "$output_variable" '%s' "$forwarded_port"
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

    redis_cli_in_pod redis-session infrastructure "$REDIS_POD" "$user" "$password" "$@" 2>&1 || true
}

redis_cache_cmd() {
    local user="$1"
    local password="$2"
    shift 2

    redis_cli_in_pod redis-cache infrastructure "$REDIS_CACHE_POD" "$user" "$password" "$@" 2>&1 || true
}

# Runs redis-cli in the redis-session pod without credentials. The pod sets
# REDISCLI_AUTH for its probes, so it is removed to start unauthenticated.
redis_session_noauth() {
    kubectl exec -n infrastructure "$REDIS_POD" -c redis-session -- \
        env -u REDISCLI_AUTH redis-cli --tls --cacert /tls-ca/ca.crt "$@" 2>&1 || true
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
echo "  Credential Verification"
echo "=============================================="

require_host_command kubectl
require_host_command curl
require_cluster_access

POSTGRES_POD=$(require_pod infrastructure app=postgresql PostgreSQL)
RABBITMQ_POD=$(require_pod infrastructure app=rabbitmq RabbitMQ)
REDIS_POD=$(require_pod infrastructure app=redis-session Redis)
REDIS_CACHE_POD=$(require_pod infrastructure app=redis-cache "Redis cache")
EXT_AUTHZ_POD=$(require_pod default app=ext-authz ext-authz)

PG_ADMIN_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials password)
PG_TXN_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials transaction-service-password)
PG_CUR_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials currency-service-password)
PG_PER_PASS=$(require_secret_value infrastructure postgresql-bootstrap-credentials permission-service-password)

RMQ_ADMIN_PASS=$(require_secret_value infrastructure rabbitmq-bootstrap-credentials password)
RMQ_CS_PASS=$(require_secret_value default currency-service-rabbitmq-credentials password)

REDIS_OPS_PASS=$(require_secret_value infrastructure redis-session-bootstrap-credentials ops-password)
REDIS_HEALTH_PASS=$(require_secret_value infrastructure redis-session-bootstrap-credentials health-password)
REDIS_SG_PASS=$(require_secret_value default session-gateway-redis-credentials password)
REDIS_EA_PASS=$(require_secret_value default ext-authz-redis-credentials password)
REDIS_CACHE_OPS_PASS=$(require_secret_value infrastructure redis-cache-bootstrap-credentials ops-password)
REDIS_CACHE_DEFAULT_PASS=$(require_secret_value infrastructure redis-cache-bootstrap-credentials default-password)
REDIS_CS_PASS=$(require_secret_value default currency-service-redis-credentials password)

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

start_port_forward infrastructure service/rabbitmq 15672 RMQ_API_PORT
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
RMQ_CS_READ=$(echo "$RMQ_CS_PERM_LINE" | awk '{print $4}')

RMQ_ALLOWED_NAME="amq.gen.phase1.verify.$RANDOM.$RANDOM"
RMQ_ALLOWED_EXCHANGE="exchange-rate.import.requested"
RMQ_ALLOWED_QUEUE="exchange-rate.import.requested.exchange-rate-import-service"
RMQ_ALLOWED_DLQ="${RMQ_ALLOWED_QUEUE}.dlq"
RMQ_ALLOWED_DLX="DLX"
RMQ_OLD_EXCHANGE="currency.created"
RMQ_OLD_QUEUE="currency.created.exchange-rate-import-service"
RMQ_OLD_DLQ="${RMQ_OLD_QUEUE}.dlq"
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

if echo "$RMQ_ALLOWED_EXCHANGE" | grep -Eq "^${RMQ_CS_CONFIGURE}$"; then
    pass "${RMQ_CS_USER} configure regex matches ${RMQ_ALLOWED_EXCHANGE}"
else
    fail "${RMQ_CS_USER} configure regex does not match ${RMQ_ALLOWED_EXCHANGE} (regex=${RMQ_CS_CONFIGURE})"
fi

if echo "$RMQ_ALLOWED_EXCHANGE" | grep -Eq "^${RMQ_CS_WRITE}$"; then
    pass "${RMQ_CS_USER} write regex matches ${RMQ_ALLOWED_EXCHANGE}"
else
    fail "${RMQ_CS_USER} write regex does not match ${RMQ_ALLOWED_EXCHANGE} (regex=${RMQ_CS_WRITE})"
fi

if echo "$RMQ_ALLOWED_EXCHANGE" | grep -Eq "^${RMQ_CS_READ}$"; then
    pass "${RMQ_CS_USER} read regex matches ${RMQ_ALLOWED_EXCHANGE}"
else
    fail "${RMQ_CS_USER} read regex does not match ${RMQ_ALLOWED_EXCHANGE} (regex=${RMQ_CS_READ})"
fi

if echo "$RMQ_ALLOWED_QUEUE" | grep -Eq "^${RMQ_CS_CONFIGURE}$" \
    && echo "$RMQ_ALLOWED_QUEUE" | grep -Eq "^${RMQ_CS_WRITE}$" \
    && echo "$RMQ_ALLOWED_QUEUE" | grep -Eq "^${RMQ_CS_READ}$"; then
    pass "${RMQ_CS_USER} configure/write/read regexes match ${RMQ_ALLOWED_QUEUE}"
else
    fail "${RMQ_CS_USER} configure/write/read regexes do not match ${RMQ_ALLOWED_QUEUE} (configure=${RMQ_CS_CONFIGURE}, write=${RMQ_CS_WRITE}, read=${RMQ_CS_READ})"
fi

if echo "$RMQ_ALLOWED_DLQ" | grep -Eq "^${RMQ_CS_CONFIGURE}$" \
    && echo "$RMQ_ALLOWED_DLQ" | grep -Eq "^${RMQ_CS_WRITE}$" \
    && echo "$RMQ_ALLOWED_DLQ" | grep -Eq "^${RMQ_CS_READ}$"; then
    pass "${RMQ_CS_USER} configure/write/read regexes match ${RMQ_ALLOWED_DLQ}"
else
    fail "${RMQ_CS_USER} configure/write/read regexes do not match ${RMQ_ALLOWED_DLQ} (configure=${RMQ_CS_CONFIGURE}, write=${RMQ_CS_WRITE}, read=${RMQ_CS_READ})"
fi

if echo "$RMQ_ALLOWED_DLX" | grep -Eq "^${RMQ_CS_CONFIGURE}$" \
    && echo "$RMQ_ALLOWED_DLX" | grep -Eq "^${RMQ_CS_WRITE}$" \
    && echo "$RMQ_ALLOWED_DLX" | grep -Eq "^${RMQ_CS_READ}$"; then
    pass "${RMQ_CS_USER} configure/write/read regexes match ${RMQ_ALLOWED_DLX}"
else
    fail "${RMQ_CS_USER} configure/write/read regexes do not match ${RMQ_ALLOWED_DLX} (configure=${RMQ_CS_CONFIGURE}, write=${RMQ_CS_WRITE}, read=${RMQ_CS_READ})"
fi

if echo "$RMQ_OLD_EXCHANGE" | grep -Eq "^${RMQ_CS_CONFIGURE}$" \
    || echo "$RMQ_OLD_EXCHANGE" | grep -Eq "^${RMQ_CS_WRITE}$" \
    || echo "$RMQ_OLD_EXCHANGE" | grep -Eq "^${RMQ_CS_READ}$"; then
    fail "${RMQ_CS_USER} regexes still allow old exchange ${RMQ_OLD_EXCHANGE}"
else
    pass "${RMQ_CS_USER} regexes deny old exchange ${RMQ_OLD_EXCHANGE}"
fi

if echo "$RMQ_OLD_QUEUE" | grep -Eq "^${RMQ_CS_CONFIGURE}$" \
    || echo "$RMQ_OLD_QUEUE" | grep -Eq "^${RMQ_CS_WRITE}$" \
    || echo "$RMQ_OLD_QUEUE" | grep -Eq "^${RMQ_CS_READ}$"; then
    fail "${RMQ_CS_USER} regexes still allow old queue ${RMQ_OLD_QUEUE}"
else
    pass "${RMQ_CS_USER} regexes deny old queue ${RMQ_OLD_QUEUE}"
fi

if echo "$RMQ_OLD_DLQ" | grep -Eq "^${RMQ_CS_CONFIGURE}$" \
    || echo "$RMQ_OLD_DLQ" | grep -Eq "^${RMQ_CS_WRITE}$" \
    || echo "$RMQ_OLD_DLQ" | grep -Eq "^${RMQ_CS_READ}$"; then
    fail "${RMQ_CS_USER} regexes still allow old DLQ ${RMQ_OLD_DLQ}"
else
    pass "${RMQ_CS_USER} regexes deny old DLQ ${RMQ_OLD_DLQ}"
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
VERIFY_SESSION_DIGEST=$(session_digest_for "$VERIFY_KEY")
VERIFY_SESSION_KEY=$(session_key_for "$VERIFY_KEY")

sg_expect() {
    local expected="$1"
    local label="$2"
    local out
    shift 2

    out=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" "$@")
    if printf '%s\n' "$out" | grep -Eq -- "$expected"; then
        pass "session-gateway ${label}"
    else
        fail "session-gateway ${label} (got: ${out:0:120})"
    fi
}

SG_SESSION_KEY="$VERIFY_SESSION_KEY"
SG_INDEX_KEY="user_sessions:${VERIFY_KEY}"
SG_STATE_KEY="oauth2:state:${VERIFY_KEY}"
SG_LUA_TYPE="return redis.call('type', KEYS[1]).ok"
SG_LUA_TYPE_SHA=$(printf '%s' "$SG_LUA_TYPE" | sha1sum | awk '{print $1}')

sg_expect '^PONG$' "PING" PING
sg_expect '^redis_version:' "INFO server" INFO server
sg_expect '^OK$' "CLIENT SETINFO" CLIENT SETINFO lib-name credential-isolation-verify
sg_expect 'proto' "HELLO" HELLO 3
sg_expect '^[0-9]+$' "HSET on session:*" HSET "$SG_SESSION_KEY" field ok
sg_expect '^ok$' "HGET on session:*" HGET "$SG_SESSION_KEY" field
sg_expect '^ok$' "HGETALL on session:*" HGETALL "$SG_SESSION_KEY"
sg_expect '^1$' "EXPIRE on session:*" EXPIRE "$SG_SESSION_KEY" 60
sg_expect '^hash$' "TYPE on session:*" TYPE "$SG_SESSION_KEY"
sg_expect '^hash$' "EVAL running TYPE inside Lua" EVAL "$SG_LUA_TYPE" 1 "$SG_SESSION_KEY"
sg_expect '^hash$' "EVALSHA of the cached script" EVALSHA "$SG_LUA_TYPE_SHA" 1 "$SG_SESSION_KEY"
sg_expect '^1$' "SADD on user_sessions:*" SADD "$SG_INDEX_KEY" "$VERIFY_SESSION_DIGEST"
sg_expect "^${VERIFY_SESSION_DIGEST}\$" "SMEMBERS on user_sessions:*" SMEMBERS "$SG_INDEX_KEY"
sg_expect '^1$' "SREM on user_sessions:*" SREM "$SG_INDEX_KEY" "$VERIFY_SESSION_DIGEST"
sg_expect '^OK$' "HMSET on oauth2:state:*" HMSET "$SG_STATE_KEY" redirect_uri /login/oauth2/code/idp
sg_expect '^1$' "DEL on oauth2:state:*" DEL "$SG_STATE_KEY"
sg_expect '^1$' "UNLINK on session:*" UNLINK "$SG_SESSION_KEY"

EA_SG_HSET=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" HSET "oauth2:state:${VERIFY_KEY}" "redirect_uri" "/login/oauth2/code/idp")
redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" DEL "oauth2:state:${VERIFY_KEY}" >/dev/null 2>&1 || true
if echo "$EA_SG_HSET" | grep -qE '^[0-9]+$'; then
    pass "session-gateway HSET on oauth2:state:*"
else
    fail "session-gateway HSET on oauth2:state:* (${EA_SG_HSET})"
fi

redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" HSET "$VERIFY_SESSION_KEY" "field" "value" >/dev/null 2>&1
EA_READ=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" HGETALL "$VERIFY_SESSION_KEY")
redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" DEL "$VERIFY_SESSION_KEY" >/dev/null 2>&1 || true
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

CS_SET=$(redis_cache_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" SET "currency-service:${VERIFY_KEY}" "ok")
CS_GET=$(redis_cache_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" GET "currency-service:${VERIFY_KEY}")
redis_cache_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" DEL "currency-service:${VERIFY_KEY}" >/dev/null 2>&1 || true
if [ "$CS_SET" = "OK" ] && [ "$CS_GET" = "ok" ]; then
    pass "currency-service SET/GET on currency-service:*"
else
    fail "currency-service SET/GET on currency-service:* (SET=${CS_SET}, GET=${CS_GET})"
fi

section "Redis: Negative (unauthorized operations denied)"

EA_SET=$(redis_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" SET "$VERIFY_SESSION_KEY" "nope")
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

CS_SESSION_AUTH=$(redis_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" PING)
if echo "$CS_SESSION_AUTH" | grep -qi 'WRONGPASS'; then
    pass "currency-service cannot authenticate to redis-session"
else
    fail "currency-service unexpectedly authenticated to redis-session (${CS_SESSION_AUTH})"
fi

SG_CACHE_AUTH=$(redis_cache_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" PING)
if echo "$SG_CACHE_AUTH" | grep -qi 'WRONGPASS'; then
    pass "session-gateway cannot authenticate to redis-cache"
else
    fail "session-gateway unexpectedly authenticated to redis-cache (${SG_CACHE_AUTH})"
fi

EA_CACHE_AUTH=$(redis_cache_cmd "$REDIS_EA_USER" "$REDIS_EA_PASS" PING)
if echo "$EA_CACHE_AUTH" | grep -qi 'WRONGPASS'; then
    pass "ext-authz cannot authenticate to redis-cache"
else
    fail "ext-authz unexpectedly authenticated to redis-cache (${EA_CACHE_AUTH})"
fi

SESSION_OPS_CACHE_AUTH=$(redis_cache_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" PING)
CACHE_OPS_SESSION_AUTH=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_CACHE_OPS_PASS" PING)
if echo "$SESSION_OPS_CACHE_AUTH" | grep -qi 'WRONGPASS' \
    && echo "$CACHE_OPS_SESSION_AUTH" | grep -qi 'WRONGPASS'; then
    pass "redis-ops credentials are isolated between Redis instances"
else
    fail "redis-ops credentials are not isolated (session->cache=${SESSION_OPS_CACHE_AUTH}, cache->session=${CACHE_OPS_SESSION_AUTH})"
fi

CACHE_DEFAULT_PING=$(redis_cache_cmd "$REDIS_DEFAULT_USER" "$REDIS_CACHE_DEFAULT_PASS" PING)
CACHE_DEFAULT_SESSION_AUTH=$(redis_cmd "$REDIS_DEFAULT_USER" "$REDIS_CACHE_DEFAULT_PASS" PING)
if [ "$CACHE_DEFAULT_PING" = "PONG" ] \
    && echo "$CACHE_DEFAULT_SESSION_AUTH" | grep -qi 'WRONGPASS'; then
    pass "redis-cache default credentials are valid only on redis-cache"
else
    fail "redis-cache default credentials are not isolated (cache=${CACHE_DEFAULT_PING}, cache->session=${CACHE_DEFAULT_SESSION_AUTH})"
fi

HEALTH_CACHE_AUTH=$(redis_cache_cmd "$REDIS_HEALTH_USER" "$REDIS_HEALTH_PASS" PING)
HEALTH_CACHE_DEFAULT_AUTH=$(redis_cache_cmd "$REDIS_DEFAULT_USER" "$REDIS_HEALTH_PASS" PING)
CACHE_DEFAULT_HEALTH_AUTH=$(redis_cmd "$REDIS_HEALTH_USER" "$REDIS_CACHE_DEFAULT_PASS" PING)
if echo "$HEALTH_CACHE_AUTH" | grep -qi 'WRONGPASS' \
    && echo "$HEALTH_CACHE_DEFAULT_AUTH" | grep -qi 'WRONGPASS' \
    && echo "$CACHE_DEFAULT_HEALTH_AUTH" | grep -qi 'WRONGPASS'; then
    pass "redis-health credentials are valid only on redis-session"
else
    fail "redis-health credentials are not isolated (health->cache=${HEALTH_CACHE_AUTH}, health->cache default=${HEALTH_CACHE_DEFAULT_AUTH}, cache default->session health=${CACHE_DEFAULT_HEALTH_AUTH})"
fi

CS_KEYS=$(redis_cache_cmd "$REDIS_CS_USER" "$REDIS_CS_PASS" KEYS "currency-service:*")
if echo "$CS_KEYS" | grep -qi "NOPERM.*'keys'"; then
    pass "currency-service denied KEYS command"
else
    fail "currency-service NOT denied KEYS (${CS_KEYS})"
fi

SG_CROSS=$(redis_cmd "$REDIS_SG_USER" "$REDIS_SG_PASS" HGETALL "currency-service:anything")
if echo "$SG_CROSS" | grep -qi 'NOPERM'; then
    pass "session-gateway denied on currency-service:* keys"
else
    fail "session-gateway NOT denied on currency-service:* (${SG_CROSS})"
fi

# ACL DRYRUN checks permission, not capability, so it is used only for denials.
redis_session_dryrun_denied() {
    local user="$1"
    local out
    shift

    out=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" ACL DRYRUN "$user" "$@")
    if printf '%s' "$out" | grep -q "no permissions to run the '"; then
        pass "${user} ACL DRYRUN denies $*"
    else
        fail "${user} ACL DRYRUN does not deny $* (got: ${out:0:120})"
    fi
}

sg_dryrun_denied() {
    redis_session_dryrun_denied "$REDIS_SG_USER" "$@"
}

sg_dryrun_denied FLUSHALL
sg_dryrun_denied FLUSHDB
sg_dryrun_denied CONFIG GET maxmemory
sg_dryrun_denied CONFIG SET appendonly no
sg_dryrun_denied SHUTDOWN
sg_dryrun_denied REPLICAOF NO ONE
sg_dryrun_denied ACL LIST
sg_dryrun_denied ACL SETUSER "$REDIS_SG_USER" +@all
sg_dryrun_denied KEYS "session:*"
sg_dryrun_denied SCAN 0 MATCH "session:*"
sg_dryrun_denied CLIENT KILL USER "$REDIS_EA_USER"
sg_dryrun_denied SCRIPT FLUSH
sg_dryrun_denied PUBLISH "$VERIFY_KEY" message

section "Redis: Session default user disabled, probes use ${REDIS_HEALTH_USER}"

# The AOF loader replays as default, so default keeps full permissions but is
# off: no client may authenticate as it, and it has no password.
SESSION_ACL_LIST=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" ACL LIST | tr -d '\r')
if printf '%s\n' "$SESSION_ACL_LIST" | grep -qx 'user default off sanitize-payload ~\* &\* +@all'; then
    pass "redis-session default is off, passwordless and keeps replay permissions"
else
    fail "redis-session default is not 'user default off sanitize-payload ~* &* +@all' (got: $(printf '%s\n' "$SESSION_ACL_LIST" | grep '^user default ' | head -c 120))"
fi
if printf '%s\n' "$SESSION_ACL_LIST" \
    | grep -Eqx "user ${REDIS_HEALTH_USER} on sanitize-payload #[0-9a-f]{64} resetchannels -@all \\+ping"; then
    pass "${REDIS_HEALTH_USER} has one password and only +ping"
else
    fail "${REDIS_HEALTH_USER} ACL is not PING-only (got: $(printf '%s\n' "$SESSION_ACL_LIST" | grep "^user ${REDIS_HEALTH_USER} " | head -c 120))"
fi

WRONG_REDIS_PASS="wrong-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"

NOAUTH_PING=$(redis_session_noauth PING)
if printf '%s' "$NOAUTH_PING" | grep -q 'NOAUTH'; then
    pass "redis-session refuses unauthenticated PING"
else
    fail "redis-session accepted an unauthenticated command (got: ${NOAUTH_PING:0:120})"
fi

session_default_auth_refused() {
    local label="$1"
    local out
    shift

    out=$(redis_session_noauth "$@")
    if printf '%s' "$out" | grep -q 'WRONGPASS'; then
        pass "redis-session refuses ${label}"
    else
        fail "redis-session did not refuse ${label} (got: ${out:0:120})"
    fi
}

session_default_auth_refused "AUTH default with the health password" AUTH "$REDIS_DEFAULT_USER" "$REDIS_HEALTH_PASS"
session_default_auth_refused "AUTH default with a random password" AUTH "$REDIS_DEFAULT_USER" "$WRONG_REDIS_PASS"
session_default_auth_refused "password-only AUTH with the health password" AUTH "$REDIS_HEALTH_PASS"
session_default_auth_refused "HELLO AUTH default with the health password" \
    HELLO 3 AUTH "$REDIS_DEFAULT_USER" "$REDIS_HEALTH_PASS"

HEALTH_PING=$(redis_cmd "$REDIS_HEALTH_USER" "$REDIS_HEALTH_PASS" PING | tr -d '\r')
if [ "$HEALTH_PING" = "PONG" ]; then
    pass "${REDIS_HEALTH_USER} PING returns PONG"
else
    fail "${REDIS_HEALTH_USER} PING did not return exactly PONG (got: ${HEALTH_PING:0:120})"
fi

HEALTH_KEY="${VERIFY_SESSION_KEY}:health"
redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" SET "$HEALTH_KEY" ok >/dev/null
health_denied() {
    local out

    out=$(redis_cmd "$REDIS_HEALTH_USER" "$REDIS_HEALTH_PASS" "$@")
    if printf '%s' "$out" | grep -q 'NOPERM'; then
        pass "${REDIS_HEALTH_USER} denied $1"
    else
        fail "${REDIS_HEALTH_USER} NOT denied $* (got: ${out:0:120})"
    fi
}

health_denied GET "$HEALTH_KEY"
health_denied HGETALL "$HEALTH_KEY"
health_denied EXISTS "$HEALTH_KEY"
health_denied KEYS "*"
health_denied SCAN 0
health_denied SET "${HEALTH_KEY}:write" nope
health_denied DEL "$HEALTH_KEY"
health_denied INFO server
health_denied CONFIG GET maxmemory
health_denied ACL WHOAMI
health_denied CLIENT LIST
health_denied SELECT 1
HEALTH_KEY_STATE=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" EXISTS "$HEALTH_KEY" "${HEALTH_KEY}:write")
redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" DEL "$HEALTH_KEY" "${HEALTH_KEY}:write" >/dev/null
if [ "$HEALTH_KEY_STATE" = "1" ]; then
    pass "${REDIS_HEALTH_USER} denials left keys unchanged"
else
    fail "${REDIS_HEALTH_USER} denials changed keys (EXISTS=${HEALTH_KEY_STATE})"
fi

for command in FLUSHALL FLUSHDB SHUTDOWN BGREWRITEAOF "CONFIG SET appendonly no" \
    "ACL SETUSER ${REDIS_HEALTH_USER} +@all" "PUBLISH ${VERIFY_KEY} message" "EVAL return 0"; do
    # shellcheck disable=SC2086 # Word splitting turns each entry into command arguments.
    redis_session_dryrun_denied "$REDIS_HEALTH_USER" $command
done

redis_session_jsonpath() {
    kubectl get pod -n infrastructure "$REDIS_POD" \
        -o jsonpath="{range .spec.containers[?(@.name==\"redis-session\")]${1}}{@}{\"\\n\"}{end}"
}

AUTH_REF=$(redis_session_jsonpath '.env[?(@.name=="REDISCLI_AUTH")].valueFrom.secretKeyRef' \
    | tr -d '\r')
if printf '%s' "$AUTH_REF" | grep -q '"key":"health-password"' \
    && printf '%s' "$AUTH_REF" | grep -q '"name":"redis-session-bootstrap-credentials"'; then
    pass "redis-session REDISCLI_AUTH is the health password"
else
    fail "redis-session REDISCLI_AUTH is not redis-session-bootstrap-credentials[health-password] (got: ${AUTH_REF:0:120})"
fi

for probe in livenessProbe readinessProbe; do
    mapfile -t PROBE_ARGS < <(redis_session_jsonpath ".${probe}.exec.command[*]")
    if [ "${PROBE_ARGS[*]}" != "$REDIS_SESSION_PROBE_COMMAND" ]; then
        fail "redis-session ${probe} is not '${REDIS_SESSION_PROBE_COMMAND}' (got: ${PROBE_ARGS[*]})"
        continue
    fi
    pass "redis-session ${probe} selects ${REDIS_HEALTH_USER} with -e"

    if PROBE_OUT=$(kubectl exec -n infrastructure "$REDIS_POD" -c redis-session -- "${PROBE_ARGS[@]}" 2>&1) \
        && [ "$(printf '%s' "$PROBE_OUT" | tr -d '\r')" = "PONG" ]; then
        pass "redis-session ${probe} command succeeds with the pod credential"
    else
        fail "redis-session ${probe} command failed with the pod credential (got: ${PROBE_OUT:0:120})"
    fi

    if PROBE_OUT=$(kubectl exec -n infrastructure "$REDIS_POD" -c redis-session -- \
        env REDISCLI_AUTH="$WRONG_REDIS_PASS" "${PROBE_ARGS[@]}" 2>&1); then
        fail "redis-session ${probe} command exited 0 with a wrong REDISCLI_AUTH (got: ${PROBE_OUT:0:120})"
    else
        pass "redis-session ${probe} command exits non-zero with a wrong REDISCLI_AUTH"
    fi
done

section "Redis: Break-glass (${REDIS_OPS_USER})"

OPS_WHOAMI=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" ACL WHOAMI)
if [ "$OPS_WHOAMI" = "$REDIS_OPS_USER" ]; then
    pass "${REDIS_OPS_USER} ACL WHOAMI"
else
    fail "${REDIS_OPS_USER} ACL WHOAMI (${OPS_WHOAMI})"
fi

# Non-TTY redis-cli prints CONFIG GET as one line for the name and one for the
# value. Command substitution drops the trailing newline, so an empty value
# such as save "" renders as the name alone.
assert_redis_config() {
    local instance="$1"
    local parameter="$2"
    local expected_value="$3"
    local out
    local expected

    if [ "$instance" = "redis-session" ]; then
        out=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" CONFIG GET "$parameter" | tr -d '\r')
    else
        out=$(redis_cache_cmd "$REDIS_OPS_USER" "$REDIS_CACHE_OPS_PASS" CONFIG GET "$parameter" | tr -d '\r')
    fi
    expected=$(printf '%s\n%s\n' "$parameter" "$expected_value")

    if [ "$out" = "$expected" ]; then
        pass "${instance} ${parameter} is '${expected_value}'"
    else
        fail "${instance} ${parameter} is not '${expected_value}' (got: ${out:0:120})"
    fi
}

# Non-TTY redis-cli prints a nil reply as an empty line, which command
# substitution reduces to an empty string. The own-user control proves that
# ACL GETUSER itself ran, so an empty reply means the user is absent.
assert_redis_user_absent() {
    local instance="$1"
    local own_user="$2"
    local absent_user="$3"
    local control
    local out

    if [ "$instance" = "redis-session" ]; then
        control=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" ACL GETUSER "$own_user" | tr -d '\r')
        out=$(redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" ACL GETUSER "$absent_user" | tr -d '\r')
    else
        control=$(redis_cache_cmd "$REDIS_OPS_USER" "$REDIS_CACHE_OPS_PASS" ACL GETUSER "$own_user" | tr -d '\r')
        out=$(redis_cache_cmd "$REDIS_OPS_USER" "$REDIS_CACHE_OPS_PASS" ACL GETUSER "$absent_user" | tr -d '\r')
    fi

    if ! printf '%s\n' "$control" | grep -qx 'flags'; then
        fail "${instance} ACL GETUSER control for ${own_user} did not return a user (got: ${control:0:120})"
    elif [ -z "$out" ]; then
        pass "${absent_user} ACL user does not exist on ${instance}"
    else
        fail "${absent_user} ACL user exists on ${instance} or ACL GETUSER failed (got: ${out:0:120})"
    fi
}

# Expected values come from kubernetes/infrastructure/redis-session/start-redis.sh.
assert_redis_config redis-session maxmemory 134217728
assert_redis_config redis-session maxmemory-policy noeviction
assert_redis_config redis-session appendonly yes

CACHE_OPS_WHOAMI=$(redis_cache_cmd "$REDIS_OPS_USER" "$REDIS_CACHE_OPS_PASS" ACL WHOAMI)
if [ "$CACHE_OPS_WHOAMI" = "$REDIS_OPS_USER" ]; then
    pass "redis-cache ${REDIS_OPS_USER} ACL WHOAMI"
else
    fail "redis-cache ${REDIS_OPS_USER} ACL WHOAMI (${CACHE_OPS_WHOAMI})"
fi

# Expected values come from kubernetes/infrastructure/redis-cache/start-redis.sh.
assert_redis_config redis-cache maxmemory 67108864
assert_redis_config redis-cache maxmemory-policy allkeys-lru
assert_redis_config redis-cache appendonly no
assert_redis_config redis-cache save ""

# WRONGPASS checks above prove the passwords differ; these prove the foreign
# application users are absent from each instance's ACL.
assert_redis_user_absent redis-session "$REDIS_SG_USER" "$REDIS_CS_USER"
assert_redis_user_absent redis-cache "$REDIS_CS_USER" "$REDIS_SG_USER"
assert_redis_user_absent redis-cache "$REDIS_CS_USER" "$REDIS_EA_USER"
assert_redis_user_absent redis-cache "$REDIS_CS_USER" "$REDIS_HEALTH_USER"

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

start_port_forward default deployment/ext-authz 8090 EXT_AUTHZ_HEALTH_PORT
start_port_forward default deployment/ext-authz 9002 EXT_AUTHZ_HTTP_PORT

http_request GET "http://127.0.0.1:${EXT_AUTHZ_HEALTH_PORT}/livez"
if [ "$HTTP_STATUS" = "200" ] && grep -qi '^ok$' "$HTTP_BODY"; then
    pass "ext-authz /livez returns 200"
else
    fail "ext-authz /livez failed (status=${HTTP_STATUS})"
fi

http_request GET "http://127.0.0.1:${EXT_AUTHZ_HEALTH_PORT}/readyz"
if [ "$HTTP_STATUS" = "200" ] && grep -qi '^ok$' "$HTTP_BODY"; then
    pass "ext-authz /readyz returns 200"
else
    fail "ext-authz /readyz failed (status=${HTTP_STATUS})"
fi

EXT_AUTHZ_SESSION_ID="phase1-verify-$RANDOM-$RANDOM"
"${SCRIPT_DIR}/../ops/seed-ext-authz-session.sh" "$EXT_AUTHZ_SESSION_ID" >/dev/null

AUTH_HEADERS=$(mktemp)
TMP_FILES+=("$AUTH_HEADERS")
AUTH_STATUS=$(curl -sS -D "$AUTH_HEADERS" -o /dev/null -w '%{http_code}' \
    -H "Cookie: __Host-BA_SESSION=${EXT_AUTHZ_SESSION_ID}" \
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

redis_cmd "$REDIS_OPS_USER" "$REDIS_OPS_PASS" DEL "$(session_key_for "$EXT_AUTHZ_SESSION_ID")" >/dev/null 2>&1 || true

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
