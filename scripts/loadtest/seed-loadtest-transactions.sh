#!/usr/bin/env bash
# scripts/loadtest/seed-loadtest-transactions.sh
#
# Bulk-creates per-user transaction fixtures on top of the synthetic users
# that `seed-loadtest-users.sh` already seeded. This is Track 1 item 2 from
# docs/plans/load-testing-synthetic-users-2026-04-09.md.
#
# Usage:
#   ./scripts/loadtest/seed-loadtest-transactions.sh [options]
#
# Options:
#   --per-user N    Target number of transactions per synthetic user (default: 10)
#   --shape SHAPE   Distribution shape: uniform | heavy-tail | sparse (default: uniform)
#   --help          Show this help
#
# Shapes:
#   uniform     — every synthetic user gets exactly --per-user transactions
#   heavy-tail  — top 10% of users get --per-user * 10, rest get --per-user
#   sparse      — bottom 80% of users get 1 transaction, top 20% get --per-user
#
# Idempotency:
#   Existing LOADTEST rows (created_by = 'LOADTEST') per owner are counted
#   first. The script only inserts the delta up to the per-user target for the
#   selected shape, so reruns at the same --per-user/--shape are no-ops and
#   reruns at a larger target extend without rewriting existing rows.
#
# Safety:
#   Only touches users whose id begins with `usr_loadtest_`. Fails cleanly if
#   no synthetic users exist yet. Refuses to run against any kubectl context
#   that does not start with `kind-`.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/loadtest-common.sh
source "${SCRIPT_DIR}/../lib/loadtest-common.sh"

# ---- Defaults ----------------------------------------------------------------

PER_USER=10
SHAPE="uniform"

# ---- Arg parsing -------------------------------------------------------------

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --per-user)
            PER_USER="${2:-}"
            shift 2
            ;;
        --shape)
            SHAPE="${2:-}"
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

if ! [[ "$PER_USER" =~ ^[0-9]+$ ]] || [ "$PER_USER" -lt 1 ]; then
    echo "ERROR: --per-user must be a positive integer (got: $PER_USER)" >&2
    exit 1
fi
case "$SHAPE" in
    uniform|heavy-tail|sparse) ;;
    *)
        echo "ERROR: --shape must be one of: uniform, heavy-tail, sparse (got: $SHAPE)" >&2
        exit 1
        ;;
esac

# ---- Preflight ---------------------------------------------------------------

require_kind_context
POSTGRES_POD=$(require_postgres_pod)

# ---- Discover loadtest users -------------------------------------------------
#
# The users must already exist in permission-service. Pull the sorted list
# (by numeric suffix) so the shape thresholds are computed against a stable
# ordering.

USER_LIST=$(postgres_query_in_pod "$POSTGRES_POD" permission \
    "SELECT id FROM users WHERE idp_sub LIKE 'loadtest|%' ORDER BY CAST(substring(id FROM '^usr_loadtest_([0-9]+)\$') AS INTEGER);")

if [ -z "$USER_LIST" ]; then
    echo "ERROR: No synthetic users found in permission-service.users." >&2
    echo "Run ./scripts/loadtest/seed-loadtest-users.sh first." >&2
    exit 1
fi

mapfile -t USER_IDS <<< "$USER_LIST"
TOTAL_USERS=${#USER_IDS[@]}

# ---- Discover existing per-owner transaction counts --------------------------
#
# One aggregate query against transaction-service gives us every loadtest
# owner's current row count, which then drives delta-only inserts for
# idempotency.

declare -A EXISTING_COUNTS
EXISTING_RAW=$(postgres_query_in_pod "$POSTGRES_POD" budget_analyzer \
    "SELECT owner_id || '|' || count(*) FROM transaction WHERE owner_id LIKE 'usr_loadtest_%' AND created_by = 'LOADTEST' GROUP BY owner_id;" || true)

if [ -n "$EXISTING_RAW" ]; then
    while IFS='|' read -r owner_id cnt; do
        [ -z "$owner_id" ] && continue
        EXISTING_COUNTS["$owner_id"]="$cnt"
    done <<< "$EXISTING_RAW"
fi

# ---- Shape → per-user target ------------------------------------------------

compute_target() {
    local rank=$1  # 1-based position in sorted USER_IDS
    case "$SHAPE" in
        uniform)
            echo "$PER_USER"
            ;;
        heavy-tail)
            # Top 10% of users get 10x the baseline.
            local threshold=$(( TOTAL_USERS - TOTAL_USERS / 10 ))
            if [ "$rank" -gt "$threshold" ]; then
                echo $(( PER_USER * 10 ))
            else
                echo "$PER_USER"
            fi
            ;;
        sparse)
            # Bottom 80% get 1 row, top 20% get the full per_user target.
            local threshold=$(( TOTAL_USERS * 8 / 10 ))
            if [ "$rank" -gt "$threshold" ]; then
                echo "$PER_USER"
            else
                echo 1
            fi
            ;;
    esac
}

# ---- Plan + summary ----------------------------------------------------------

TOTAL_TO_INSERT=0
declare -a PLAN_OWNER PLAN_FROM PLAN_TO PLAN_INDEX
for ((i = 0; i < TOTAL_USERS; i++)); do
    owner_id="${USER_IDS[$i]}"
    rank=$((i + 1))
    target=$(compute_target "$rank")
    existing=${EXISTING_COUNTS["$owner_id"]:-0}
    if [ "$existing" -ge "$target" ]; then
        continue
    fi
    from=$((existing + 1))
    PLAN_OWNER+=("$owner_id")
    PLAN_INDEX+=("$rank")
    PLAN_FROM+=("$from")
    PLAN_TO+=("$target")
    TOTAL_TO_INSERT=$((TOTAL_TO_INSERT + target - existing))
done

echo "Seeding transactions for ${TOTAL_USERS} synthetic users"
echo "  shape:     ${SHAPE}"
echo "  per-user:  ${PER_USER}"
echo "  to insert: ${TOTAL_TO_INSERT} new rows across ${#PLAN_OWNER[@]} owners"

if [ "$TOTAL_TO_INSERT" -eq 0 ]; then
    echo "  nothing to do — all owners already at target"
    exit 0
fi

# ---- Emit one generate_series INSERT per owner ------------------------------
#
# All values are computed deterministically from (user_index, txn_index) so
# reruns (and teardown) remain predictable. The LOADTEST: marker and the
# created_by = 'LOADTEST' stamp both satisfy the teardown contract.

{
    echo "BEGIN;"
    for ((p = 0; p < ${#PLAN_OWNER[@]}; p++)); do
        owner_id="${PLAN_OWNER[$p]}"
        rank="${PLAN_INDEX[$p]}"
        from="${PLAN_FROM[$p]}"
        to="${PLAN_TO[$p]}"
        cat <<SQL
INSERT INTO transaction (bank_name, date, currency_iso_code, amount, type, description, owner_id, account_id, created_at, created_by, deleted)
SELECT
    'LoadTestBank',
    current_date - (((${rank} * 7 + k) % 365)),
    CASE ((${rank} + k) % 4)
        WHEN 0 THEN 'USD'
        WHEN 1 THEN 'EUR'
        WHEN 2 THEN 'GBP'
        ELSE 'CAD'
    END,
    round(((((${rank} * 31 + k * 7) % 100000) + 50)::numeric) / 100, 2),
    CASE WHEN (k % 2) = 0 THEN 'CREDIT' ELSE 'DEBIT' END,
    'LOADTEST:u${rank}:t' || k,
    '${owner_id}',
    'loadtest-acct-${rank}',
    now(),
    'LOADTEST',
    false
FROM generate_series(${from}, ${to}) AS k;
SQL
    done
    echo "COMMIT;"
} | postgres_pipe_in_pod "$POSTGRES_POD" budget_analyzer >/dev/null

echo "  inserted ${TOTAL_TO_INSERT} rows into transaction-service.transaction"
echo "Done."
