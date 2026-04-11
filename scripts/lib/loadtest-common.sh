#!/usr/bin/env bash
# Shared helpers for Budget Analyzer load-test fixture scripts.
#
# Implements the Track 1 common pieces from
# docs/plans/load-testing-synthetic-users-2026-04-09.md:
#   - kind-only context guard
#   - psql bulk pipe against the in-cluster PostgreSQL pod
#   - redis-cli bulk pipe against the in-cluster Redis pod
#   - shared loadtest id / marker / pool-file constants
#   - single-command redis-cli exec helper for scan / unlink workflows
#
# Source this file from seed-loadtest-users.sh,
# seed-loadtest-transactions.sh, and teardown-loadtest.sh.
#
# shellcheck disable=SC2034,SC2016

set -euo pipefail

# ---- Shared loadtest identifiers ---------------------------------------------
# Every synthetic artifact must carry one of these so teardown can find it.

LOADTEST_USER_ID_PREFIX="usr_loadtest_"
LOADTEST_IDP_SUB_PREFIX="loadtest|"
LOADTEST_SESSION_ID_PREFIX="loadtest_"
LOADTEST_EMAIL_DOMAIN="budgetanalyzer.invalid"
LOADTEST_DESCRIPTION_MARKER="LOADTEST:"
LOADTEST_CREATED_BY="LOADTEST"

# Path (relative to repo root) where seed-loadtest-users.sh writes the
# session-cookie pool consumed by any later traffic-replay tooling.
LOADTEST_POOL_DIR=".loadtest"
LOADTEST_POOL_FILE="${LOADTEST_POOL_DIR}/session-pool.txt"

# ---- Cluster guard -----------------------------------------------------------

# Refuse to run against anything that is not a local kind cluster. Every
# script that mutates fixtures must call this before touching kubectl.
require_kind_context() {
    local ctx
    ctx=$(kubectl config current-context 2>/dev/null || true)
    if [ -z "$ctx" ]; then
        echo "ERROR: No kubectl context is currently set." >&2
        echo "Load-test scripts only run against a local kind cluster." >&2
        exit 1
    fi
    case "$ctx" in
        kind-*)
            return 0
            ;;
        *)
            echo "ERROR: kubectl context is '$ctx'." >&2
            echo "Load-test scripts refuse to run against anything that is" >&2
            echo "not a local kind cluster (context prefix 'kind-')." >&2
            echo "Switch context with: kubectl config use-context kind-<name>" >&2
            exit 1
            ;;
    esac
}

# ---- Pod discovery -----------------------------------------------------------

find_postgres_pod() {
    kubectl get pods -n infrastructure -l app=postgresql \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

find_redis_pod() {
    kubectl get pods -n infrastructure -l app=redis \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

require_postgres_pod() {
    local pod
    pod=$(find_postgres_pod)
    if [ -z "$pod" ]; then
        echo "ERROR: PostgreSQL pod not found in infrastructure namespace." >&2
        echo "Is Tilt running? Try: tilt up" >&2
        exit 1
    fi
    echo "$pod"
}

require_redis_pod() {
    local pod
    pod=$(find_redis_pod)
    if [ -z "$pod" ]; then
        echo "ERROR: Redis pod not found in infrastructure namespace." >&2
        echo "Is Tilt running? Try: tilt up" >&2
        exit 1
    fi
    echo "$pod"
}

# ---- Redis credentials -------------------------------------------------------

# Exports REDIS_USERNAME and REDIS_OPS_PASSWORD from the
# redis-bootstrap-credentials secret.
load_redis_ops_credentials() {
    REDIS_USERNAME="redis-ops"
    REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials \
        -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
    if [ -z "$REDIS_OPS_PASSWORD" ]; then
        echo "ERROR: redis-bootstrap-credentials is missing the ops-password key." >&2
        exit 1
    fi
    export REDIS_USERNAME REDIS_OPS_PASSWORD
}

# ---- PostgreSQL pipe / query helpers -----------------------------------------

# Executes a SQL script read from stdin against the given database.
# Caller is responsible for ON ERROR STOP semantics — this wrapper uses
# `-v ON_ERROR_STOP=1` so any psql error aborts the whole batch.
#
# Usage:
#   postgres_pipe_in_pod "$POSTGRES_POD" permission <<'SQL'
#   INSERT INTO users (...) VALUES (...);
#   SQL
postgres_pipe_in_pod() {
    local pod="$1"
    local database="$2"

    kubectl exec -i -n infrastructure "$pod" -- /bin/sh -ceu \
        'PGPASSWORD="$POSTGRES_PASSWORD" psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$1"' \
        sh "$database"
}

# Runs a single-statement query and echoes the tuple-only result.
#
# Usage:
#   count=$(postgres_query_in_pod "$POSTGRES_POD" permission \
#       "SELECT count(*) FROM users WHERE idp_sub LIKE 'loadtest|%';")
postgres_query_in_pod() {
    local pod="$1"
    local database="$2"
    local sql="$3"

    kubectl exec -n infrastructure "$pod" -- /bin/sh -ceu \
        'PGPASSWORD="$POSTGRES_PASSWORD" psql -X -tAc "$2" -U "$POSTGRES_USER" -d "$1"' \
        sh "$database" "$sql"
}

# ---- Redis pipe helper -------------------------------------------------------

# Executes newline-separated redis-cli commands read from stdin against the
# given Redis pod over the in-cluster TLS listener. Uses a single kubectl exec
# so bulk HSET / EXPIRE / SADD runs stay fast.
#
# Usage:
#   redis_cli_pipe_in_pod "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" <<'REDIS'
#   HSET session:loadtest_1 user_id usr_loadtest_1 ...
#   EXPIRE session:loadtest_1 900
#   REDIS
redis_cli_pipe_in_pod() {
    local pod="$1"
    local user="$2"
    local password="$3"

    kubectl exec -i -n infrastructure "$pod" -- \
        redis-cli \
        --tls \
        --cacert /tls-ca/ca.crt \
        --user "$user" \
        --pass "$password" \
        --no-auth-warning
}

# Executes a single redis-cli command inside the Redis pod. Prefer the pipe
# helper for bulk writes; use this for scans and one-off commands that need
# structured output.
#
# Usage:
#   redis_cli_exec_in_pod "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" \
#       --scan --pattern 'session:loadtest_*'
redis_cli_exec_in_pod() {
    local pod="$1"
    local user="$2"
    local password="$3"
    shift 3

    kubectl exec -n infrastructure "$pod" -- /bin/sh -ceu '
        user="$1"
        password="$2"
        shift 2
        export REDISCLI_AUTH="$password"
        exec redis-cli \
            --tls \
            --cacert /tls-ca/ca.crt \
            --user "$user" \
            --no-auth-warning \
            "$@"
    ' sh "$user" "$password" "$@"
}

# ---- USER / ADMIN permission strings ----------------------------------------
#
# These must match permission-service/src/main/resources/db/migration/
# V2__seed_default_data.sql. Sessions carry the role's permission set verbatim
# because session-gateway denormalises roles+permissions into the session hash
# at login time (see session-gateway/src/main/java/.../SessionHashFields.java).
# Keeping these in one place means the session writer and the teardown script
# agree on what a USER / ADMIN session looks like.

LOADTEST_USER_PERMISSIONS="transactions:read,transactions:write,transactions:delete,views:read,views:write,views:delete,statementformats:read,currencies:read"
LOADTEST_ADMIN_PERMISSIONS="transactions:read,transactions:write,transactions:delete,transactions:read:any,transactions:write:any,transactions:delete:any,users:read,users:write,users:delete,statementformats:read,statementformats:write,currencies:read,currencies:write"

# ---- Repo-root resolver ------------------------------------------------------

# Resolves the absolute repo root from this file's on-disk location, so
# scripts can open the pool file regardless of the caller's cwd.
loadtest_repo_root() {
    local lib_dir
    lib_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    cd "${lib_dir}/../../.." && pwd
}
