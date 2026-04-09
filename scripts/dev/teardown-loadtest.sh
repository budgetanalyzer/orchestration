#!/usr/bin/env bash
# scripts/dev/teardown-loadtest.sh
#
# Removes every synthetic Track 1 artifact created by the loadtest fixture
# scripts: Redis session hashes, per-user session indexes, transaction-service
# rows, permission-service user_roles rows, permission-service users rows, and
# the generated `.loadtest/session-pool.txt` file.
#
# Usage:
#   ./scripts/dev/teardown-loadtest.sh
#   ./scripts/dev/teardown-loadtest.sh --help
#
# Safety:
#   Refuses to run against any kubectl context that does not start with
#   `kind-`. The delete predicates are limited to the checked-in synthetic
#   markers (`usr_loadtest_`, `loadtest|`, `LOADTEST:` / `LOADTEST`).
#
# Idempotency:
#   Safe to run repeatedly. Missing keys, rows, or pool files are treated as
#   zero-count cleanup.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/loadtest-common.sh
source "${SCRIPT_DIR}/lib/loadtest-common.sh"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "$#" -ne 0 ]; then
    echo "ERROR: teardown-loadtest.sh takes no arguments." >&2
    usage >&2
    exit 1
fi

normalize_count() {
    local raw="${1:-0}"
    raw="${raw//[[:space:]]/}"
    if [ -z "$raw" ]; then
        echo 0
    else
        echo "$raw"
    fi
}

count_lines() {
    local input="${1:-}"
    if [ -z "$input" ]; then
        echo 0
        return
    fi
    printf '%s\n' "$input" | sed '/^$/d' | wc -l | tr -d '[:space:]'
}

require_kind_context

POSTGRES_POD=$(require_postgres_pod)
REDIS_POD=$(require_redis_pod)
load_redis_ops_credentials

REPO_ROOT=$(loadtest_repo_root)
POOL_FILE="${REPO_ROOT}/${LOADTEST_POOL_FILE}"
POOL_DIR="${REPO_ROOT}/${LOADTEST_POOL_DIR}"

SESSION_KEYS=$(
    redis_cli_exec_in_pod \
        "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" \
        --scan --pattern "session:${LOADTEST_SESSION_ID_PREFIX}*" || true
)
USER_SESSION_KEYS=$(
    redis_cli_exec_in_pod \
        "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" \
        --scan --pattern "user_sessions:${LOADTEST_USER_ID_PREFIX}*" || true
)

SESSION_KEY_COUNT=$(count_lines "$SESSION_KEYS")
USER_SESSION_KEY_COUNT=$(count_lines "$USER_SESSION_KEYS")

TRANSACTION_COUNT=$(normalize_count "$(
    postgres_query_in_pod "$POSTGRES_POD" budget_analyzer \
        "SELECT count(*) FROM transaction
         WHERE owner_id LIKE 'usr_loadtest_%'
            OR description LIKE 'LOADTEST:%'
            OR created_by = 'LOADTEST';"
)")
USER_ROLE_COUNT=$(normalize_count "$(
    postgres_query_in_pod "$POSTGRES_POD" permission \
        "SELECT count(*) FROM user_roles
         WHERE user_id LIKE 'usr_loadtest_%';"
)")
USER_COUNT=$(normalize_count "$(
    postgres_query_in_pod "$POSTGRES_POD" permission \
        "SELECT count(*) FROM users
         WHERE id LIKE 'usr_loadtest_%'
            OR idp_sub LIKE 'loadtest|%';"
)")

echo "Tearing down synthetic Track 1 data"
echo "  Postgres pod: ${POSTGRES_POD}"
echo "  Redis pod:    ${REDIS_POD}"
echo "  Redis keys:   ${SESSION_KEY_COUNT} session hashes, ${USER_SESSION_KEY_COUNT} user_sessions sets"
echo "  Postgres:     ${TRANSACTION_COUNT} transactions, ${USER_ROLE_COUNT} user_roles, ${USER_COUNT} users"

if [ "$SESSION_KEY_COUNT" -gt 0 ]; then
    printf '%s\n' "$SESSION_KEYS" \
        | sed '/^$/d;s/^/UNLINK /' \
        | redis_cli_pipe_in_pod "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" >/dev/null
fi

if [ "$USER_SESSION_KEY_COUNT" -gt 0 ]; then
    printf '%s\n' "$USER_SESSION_KEYS" \
        | sed '/^$/d;s/^/UNLINK /' \
        | redis_cli_pipe_in_pod "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" >/dev/null
fi

{
    echo "BEGIN;"
    echo "DELETE FROM transaction
          WHERE owner_id LIKE 'usr_loadtest_%'
             OR description LIKE 'LOADTEST:%'
             OR created_by = 'LOADTEST';"
    echo "COMMIT;"
} | postgres_pipe_in_pod "$POSTGRES_POD" budget_analyzer >/dev/null

{
    echo "BEGIN;"
    echo "DELETE FROM user_roles
          WHERE user_id LIKE 'usr_loadtest_%';"
    echo "DELETE FROM users
          WHERE id LIKE 'usr_loadtest_%'
             OR idp_sub LIKE 'loadtest|%';"
    echo "COMMIT;"
} | postgres_pipe_in_pod "$POSTGRES_POD" permission >/dev/null

POOL_FILE_REMOVED="no"
if [ -f "$POOL_FILE" ]; then
    rm -f "$POOL_FILE"
    POOL_FILE_REMOVED="yes"
fi
if [ -d "$POOL_DIR" ] && [ -z "$(find "$POOL_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    rmdir "$POOL_DIR" || true
fi

echo "Cleanup summary"
echo "  redis pattern session:${LOADTEST_SESSION_ID_PREFIX}*        -> deleted ${SESSION_KEY_COUNT} keys"
echo "  redis pattern user_sessions:${LOADTEST_USER_ID_PREFIX}* -> deleted ${USER_SESSION_KEY_COUNT} keys"
echo "  budget_analyzer.transaction                             -> deleted ${TRANSACTION_COUNT} rows"
echo "  permission.user_roles                                   -> deleted ${USER_ROLE_COUNT} rows"
echo "  permission.users                                        -> deleted ${USER_COUNT} rows"
echo "  ${LOADTEST_POOL_FILE}                                   -> removed ${POOL_FILE_REMOVED}"
echo "Done."
