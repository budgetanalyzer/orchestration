#!/usr/bin/env bash
# scripts/loadtest/seed-loadtest-users.sh
#
# Bulk-creates synthetic Budget Analyzer users for Track 1 (data-path) load
# testing, then writes matching Redis session hashes plus the per-user
# `user_sessions:` index entries so ext-authz validates synthetic traffic the
# same way it validates real logins. Also emits `.loadtest/session-pool.txt`
# so later traffic-replay tooling can reuse the seeded sessions.
#
# Usage:
#   ./scripts/loadtest/seed-loadtest-users.sh [options]
#
# Options:
#   --count N          Number of synthetic users/sessions (default: 10)
#   --admin-count K    First K users receive ADMIN instead of USER (default: 0)
#   --session-ttl S    Session TTL in seconds (default: 900)
#   --help             Show this help
#
# Idempotency:
#   Rerunning with the same --count is a no-op for permission-service rows
#   (ON CONFLICT DO NOTHING). A larger --count extends the range. Redis session
#   hashes are refreshed on every run — this deliberately resets the TTL so
#   operators can extend a running test by re-running the seeder.
#
# Safety:
#   Refuses to run against any kubectl context that does not start with
#   `kind-`. See `docs/plans/load-testing-synthetic-users-2026-04-09.md`.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/loadtest-common.sh
source "${SCRIPT_DIR}/../lib/loadtest-common.sh"

# ---- Defaults ----------------------------------------------------------------

COUNT=10
ADMIN_COUNT=0
SESSION_TTL=900

# ---- Arg parsing -------------------------------------------------------------

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --count)
            COUNT="${2:-}"
            shift 2
            ;;
        --admin-count)
            ADMIN_COUNT="${2:-}"
            shift 2
            ;;
        --session-ttl)
            SESSION_TTL="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ]; then
    echo "ERROR: --count must be a positive integer (got: $COUNT)" >&2
    exit 1
fi
if ! [[ "$ADMIN_COUNT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --admin-count must be a non-negative integer (got: $ADMIN_COUNT)" >&2
    exit 1
fi
if [ "$ADMIN_COUNT" -gt "$COUNT" ]; then
    echo "ERROR: --admin-count ($ADMIN_COUNT) cannot exceed --count ($COUNT)" >&2
    exit 1
fi
if ! [[ "$SESSION_TTL" =~ ^[0-9]+$ ]] || [ "$SESSION_TTL" -lt 1 ]; then
    echo "ERROR: --session-ttl must be a positive integer (got: $SESSION_TTL)" >&2
    exit 1
fi

# ---- Preflight ---------------------------------------------------------------

require_kind_context

POSTGRES_POD=$(require_postgres_pod)
REDIS_POD=$(require_redis_pod)
load_redis_ops_credentials

CREATED_AT=$(date +%s)
EXPIRES_AT=$((CREATED_AT + SESSION_TTL))

REPO_ROOT=$(loadtest_repo_root)
POOL_DIR="${REPO_ROOT}/${LOADTEST_POOL_DIR}"
POOL_FILE="${REPO_ROOT}/${LOADTEST_POOL_FILE}"
mkdir -p "$POOL_DIR"

echo "Seeding ${COUNT} synthetic users (${ADMIN_COUNT} ADMIN, $((COUNT - ADMIN_COUNT)) USER)"
echo "  Postgres pod: ${POSTGRES_POD}"
echo "  Redis pod:    ${REDIS_POD}"
echo "  Session TTL:  ${SESSION_TTL}s"
echo "  Pool file:    ${POOL_FILE}"

# ---- Permission-service rows -------------------------------------------------
#
# Wrap the whole batch in a single transaction so a failure mid-way leaves the
# database unchanged. ON CONFLICT DO NOTHING covers both idempotent reruns at
# the same count and extension runs at a larger count.

{
    echo "BEGIN;"
    for ((n = 1; n <= COUNT; n++)); do
        user_id="${LOADTEST_USER_ID_PREFIX}${n}"
        idp_sub="${LOADTEST_IDP_SUB_PREFIX}${n}"
        email="loadtest-${n}@${LOADTEST_EMAIL_DOMAIN}"
        display_name="Load Test User ${n}"
        if [ "$n" -le "$ADMIN_COUNT" ]; then
            role="ADMIN"
        else
            role="USER"
        fi
        printf "INSERT INTO users (id, idp_sub, email, display_name, created_at, created_by, status) VALUES ('%s', '%s', '%s', '%s', now(), '%s', 'ACTIVE') ON CONFLICT DO NOTHING;\n" \
            "$user_id" "$idp_sub" "$email" "$display_name" "$LOADTEST_CREATED_BY"
        printf "INSERT INTO user_roles (user_id, role_id, created_at, created_by) VALUES ('%s', '%s', now(), '%s') ON CONFLICT DO NOTHING;\n" \
            "$user_id" "$role" "$LOADTEST_CREATED_BY"
    done
    echo "COMMIT;"
} | postgres_pipe_in_pod "$POSTGRES_POD" permission >/dev/null

echo "  permission-service: users + user_roles upserted"

# ---- Redis sessions ----------------------------------------------------------
#
# One HSET per session populating the full 9-field shape session-gateway
# produces at real login (see session-gateway SessionHashFields.java), plus
# the per-user `user_sessions:` SET that bulk revocation consumes. Both keys
# get the same TTL so they expire together.
#
# display_name intentionally uses an underscore-separated form to avoid
# quoting issues in redis-cli's line-mode parser.

{
    for ((n = 1; n <= COUNT; n++)); do
        user_id="${LOADTEST_USER_ID_PREFIX}${n}"
        idp_sub="${LOADTEST_IDP_SUB_PREFIX}${n}"
        session_id="${LOADTEST_SESSION_ID_PREFIX}${n}"
        email="loadtest-${n}@${LOADTEST_EMAIL_DOMAIN}"
        display_name="LoadTest_User_${n}"
        picture="https://loadtest.invalid/avatar/${n}.png"
        if [ "$n" -le "$ADMIN_COUNT" ]; then
            role="ADMIN"
            perms="$LOADTEST_ADMIN_PERMISSIONS"
        else
            role="USER"
            perms="$LOADTEST_USER_PERMISSIONS"
        fi
        printf "HSET session:%s user_id %s idp_sub %s email %s display_name %s picture %s roles %s permissions %s created_at %s expires_at %s\n" \
            "$session_id" "$user_id" "$idp_sub" "$email" "$display_name" "$picture" "$role" "$perms" "$CREATED_AT" "$EXPIRES_AT"
        printf "EXPIRE session:%s %s\n" "$session_id" "$SESSION_TTL"
        printf "SADD user_sessions:%s %s\n" "$user_id" "$session_id"
        printf "EXPIRE user_sessions:%s %s\n" "$user_id" "$SESSION_TTL"
    done
} | redis_cli_pipe_in_pod "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" >/dev/null

echo "  redis:              ${COUNT} session hashes + user_sessions indices written"

# ---- Session pool file -------------------------------------------------------
#
# k6 reads this file and assigns one session ID per virtual user.

{
    for ((n = 1; n <= COUNT; n++)); do
        printf "%s%s\n" "$LOADTEST_SESSION_ID_PREFIX" "$n"
    done
} > "$POOL_FILE"

echo "  pool file:          wrote ${COUNT} session IDs to ${POOL_FILE}"
echo "Done."
