#!/bin/bash

# Live restart proof for redis-session AOF persistence on local Tilt/Kind.
#
# It runs the real Session Gateway Lua scripts as the session-gateway ACL user
# against the running redis-session pod. Restart 1 puts a seed session in the
# AOF base with BGREWRITEAOF, writes session creation, heartbeat refresh and
# OAuth state into the incremental AOF, restarts the StatefulSet with
# `kubectl rollout restart`, and asserts what the replay restored. Restart 2
# does the same for two bulk revocations of sessions seeded before a second
# rewrite. Sessions are also checked through the verified-HTTPS ingress. The
# restarts run only with --allow-restart. It never flushes the database and
# touches only keys it created; every key carries a TTL so interrupted-run
# residue expires on its own. The offline counterpart, including the
# expired-but-present revocation case that needs DEBUG, is
# scripts/guardrails/verify-redis-session-aof-replay.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
source "${SCRIPT_DIR}/../lib/local-kubernetes-target.sh"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
source "${SCRIPT_DIR}/../lib/redis-cli.sh"

SESSION_GATEWAY_DIR="${SESSION_GATEWAY_DIR:-$(dirname "${REPO_DIR}")/session-gateway}"
CREATE_LUA_FILE="${SESSION_GATEWAY_DIR}/src/main/resources/redis/create-session.lua"
UPDATE_LUA_FILE="${SESSION_GATEWAY_DIR}/src/main/resources/redis/conditional-update.lua"
DELETE_LUA_FILE="${SESSION_GATEWAY_DIR}/src/main/resources/redis/delete-user-sessions.lua"
OAUTH_JAVA_FILE="${SESSION_GATEWAY_DIR}/src/main/java/org/budgetanalyzer/sessiongateway/security/RedisAuthorizationRequestRepository.java"
SESSION_FIELDS_JAVA_FILE="${SESSION_GATEWAY_DIR}/src/main/java/org/budgetanalyzer/sessiongateway/session/SessionHashFields.java"
SESSION_GATEWAY_APP_YML="${SESSION_GATEWAY_DIR}/src/main/resources/application.yml"

SESSION_PREFIX="session:"
INDEX_PREFIX="user_sessions:"
OAUTH_PREFIX="oauth2:state:"

NAMESPACE="infrastructure"
STATEFULSET="redis-session"
POD="redis-session-0"
CONTAINER="redis-session"
SECRET="redis-session-bootstrap-credentials"
AOF_DIR="/data/appendonlydir"
AOF_MANIFEST="${AOF_DIR}/appendonly.aof.manifest"
# Redis uses UINT64_MAX as the client id of the AOF loader (CLIENT_ID_AOF).
AOF_LOADER_CLIENT_ID="18446744073709551615"
EXPECTED_DEFAULT_ACL="user default off sanitize-payload ~* &* +@all"
EXPECTED_HEALTH_ACL_REGEX='^user redis-health on sanitize-payload #[0-9a-f]{64} resetchannels -@all \+ping$'

REWRITE_TIMEOUT_SECONDS=60
ROLLOUT_TIMEOUT_SECONDS=300
READY_TIMEOUT_SECONDS=60
# TTLs outlast the restart and bound residue from an interrupted run.
SESSION_TTL=900
REFRESH_TTL=1800
OAUTH_TTL=900
# GET /api/v1/currencies needs only currencies:read and reads no user data.
SEED_PERMISSIONS="transactions:read,currencies:read"
REFRESH_PERMISSIONS="transactions:read,transactions:write,currencies:read"
INGRESS_PATH="/api/v1/currencies"
INGRESS_URL="https://app.budgetanalyzer.localhost${INGRESS_PATH}"
INGRESS_ATTEMPTS=15
CURL_TIMEOUT=10

ALLOW_RESTART=false
PASSED=0
FAILED=0
WORK_DIR=""
OWNED_KEYS=()
CLEANUP_NEEDED=false
RESTART_REQUESTED=false
PVC_IDENTITY=""
MANIFEST_BEFORE=""
INCR_FILE=""
BASE_FILE=""

GATEWAY_PASSWORD=""
EXT_AUTHZ_PASSWORD=""
OPS_PASSWORD=""
CREATE_LUA=""
UPDATE_LUA=""
DELETE_LUA=""
OAUTH_LUA=""

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-redis-session-persistence.sh --allow-restart

Live redis-session AOF persistence proof for the local Tilt/Kind stack. It
restarts the redis-session StatefulSet, so it runs only with --allow-restart
and is not part of smoketest.sh. Run it only after the Redis Session ACL
Cutover in docs/development/local-environment.md.

Before any write it requires the exact local Kubernetes target, a Ready
redis-session-0, the checked-in `default` and `redis-health` ACL lines live,
and no AOF-loader ACL denials since the pod started. If the fixed ACL is not
live it stops without writing or restarting.

It reads the Session Gateway scripts from ../session-gateway (or
SESSION_GATEWAY_DIR) and runs them as session-gateway with uniquely named
synthetic sessions, users and OAuth state, in two rounds:
  restart 1  before a BGREWRITEAOF: one session to refresh. After it: session
             creation, heartbeat refresh and OAuth state (each MULTI/EXEC)
  restart 2  before a BGREWRITEAOF: two live sessions for one user; one 1 s
             session plus one live session for another user, with the short
             key gone before the rewrite. After it: bulk revocation of both
             users (each a single DEL)
Before each restart it confirms those writes are in the incremental AOF with
that framing, then runs `kubectl rollout restart statefulset/redis-session`
and waits for a new Ready pod on the same PVC. After each restart it asserts
that the same base and incremental files were loaded, there are no AOF-loader
ACL denials and `default` is still off. After restart 1 it asserts identical
hashes, index membership and absolute expirations, and that the restored
sessions authorize GET /api/v1/currencies through the ingress (200). After
restart 2 it asserts the revoked keys stay absent and the revoked session
cookies are denied at the ingress (401). Ingress requests use normal TLS
verification. The expired-but-present revocation case needs DEBUG and stays
in the offline harness.

It never flushes Redis, never prints credentials or session tokens, and
removes the keys it created on exit. Session Gateway and ext-authz keep running;
their clients reconnect after the restart.

Options:
  --allow-restart  Required. Permit the redis-session StatefulSet restart.
  -h, --help       Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-restart)
            ALLOW_RESTART=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "${ALLOW_RESTART}" != true ]]; then
    printf 'ERROR: this verifier restarts redis-session; rerun with --allow-restart\n' >&2
    usage >&2
    exit 2
fi

pass() { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

check() {
    local description="$1"
    shift
    if "$@"; then
        pass "${description}"
    else
        fail "${description}"
    fi
}

check_eq() {
    local description="$1" expected="$2" actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        pass "${description}"
    else
        fail "${description} (expected '${expected}', got '${actual}')"
    fi
}

cli_as() {
    local user="$1" password="$2"
    shift 2
    redis_cli_in_pod "${STATEFULSET}" "${NAMESPACE}" "${POD}" "${user}" "${password}" "$@" | tr -d '\r'
}

ops() { cli_as redis-ops "${OPS_PASSWORD}" "$@"; }
gateway() { cli_as session-gateway "${GATEWAY_PASSWORD}" "$@"; }

cleanup() {
    local exit_status=$? remaining
    set +e
    if [[ "${CLEANUP_NEEDED}" == true ]]; then
        printf '\nRemoving the synthetic keys...\n'
        if [[ "${RESTART_REQUESTED}" == true ]]; then
            kubectl rollout status "statefulset/${STATEFULSET}" -n "${NAMESPACE}" \
                --timeout="${ROLLOUT_TIMEOUT_SECONDS}s" >/dev/null 2>&1
        fi
        if assert_local_kind_target \
            && ops UNLINK "${OWNED_KEYS[@]}" >/dev/null \
            && remaining=$(ops EXISTS "${OWNED_KEYS[@]}") \
            && [[ "${remaining}" == "0" ]]; then
            printf '  Synthetic keys removed.\n'
        else
            printf 'ERROR: synthetic key cleanup incomplete; the keys expire within %ss\n' \
                "${REFRESH_TTL}" >&2
            exit_status=1
        fi
    fi
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
    exit "${exit_status}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_anchor() {
    local file="$1" anchor="$2"
    grep -qF -- "${anchor}" "${file}" \
        || die "contract drift: '${anchor}' not found in ${file}; update this verifier deliberately"
}

# Extracts the CREATE_REQUEST_SCRIPT Java text block, as the offline harness
# does, and fails on drift that would change the Lua Session Gateway sends.
extract_oauth_script() {
    local count script

    count=$(grep -c 'RedisScript<Long> CREATE_REQUEST_SCRIPT =' "${OAUTH_JAVA_FILE}" || true)
    [[ "${count}" == "1" ]] || die "expected one CREATE_REQUEST_SCRIPT in ${OAUTH_JAVA_FILE}, found ${count}"

    script=$(awk '
        /RedisScript<Long> CREATE_REQUEST_SCRIPT =/ { found = 1; next }
        found && !inblock && /"""/ { inblock = 1; next }
        inblock && /"""/ { closed = 1; exit }
        inblock { sub(/^[[:space:]]+/, ""); print }
        END { if (!closed) exit 1 }
    ' "${OAUTH_JAVA_FILE}") || die "could not extract the CREATE_REQUEST_SCRIPT text block from ${OAUTH_JAVA_FILE}"

    [[ "${script}" != *\\* ]] || die "CREATE_REQUEST_SCRIPT contains Java escapes; this extractor does not translate them"
    [[ "${script}" == *"redis.call('HSET', KEYS[1], unpack(ARGV, 2))"* ]] \
        || die "CREATE_REQUEST_SCRIPT no longer writes fields with HSET from ARGV[2..]"
    [[ "${script}" == *"redis.call('EXPIRE', KEYS[1], ARGV[1])"* ]] \
        || die "CREATE_REQUEST_SCRIPT no longer sets the TTL from ARGV[1]"
    printf '%s\n' "${script}"
}

load_scripts() {
    local file

    [[ -d "${SESSION_GATEWAY_DIR}" ]] \
        || die "Session Gateway sources not found at ${SESSION_GATEWAY_DIR}; clone it beside this repo or set SESSION_GATEWAY_DIR"
    for file in "${CREATE_LUA_FILE}" "${UPDATE_LUA_FILE}" "${DELETE_LUA_FILE}" \
        "${OAUTH_JAVA_FILE}" "${SESSION_FIELDS_JAVA_FILE}" "${SESSION_GATEWAY_APP_YML}"; do
        [[ -r "${file}" ]] || die "required input is missing or unreadable: ${file}"
    done

    require_anchor "${CREATE_LUA_FILE}" "-- KEYS[2]: user sessions index key"
    require_anchor "${CREATE_LUA_FILE}" "-- ARGV[2]: TTL in seconds"
    require_anchor "${CREATE_LUA_FILE}" "-- ARGV[3..N]: alternating hash field/value pairs"
    require_anchor "${UPDATE_LUA_FILE}" "-- ARGV[2..N-1]: field/value pairs to HSET"
    require_anchor "${UPDATE_LUA_FILE}" "-- ARGV[N]: TTL in seconds (always the last argument)"
    require_anchor "${DELETE_LUA_FILE}" "-- KEYS[1]: user sessions index key"
    require_anchor "${DELETE_LUA_FILE}" "-- ARGV[1]: session key prefix"
    require_anchor "${OAUTH_JAVA_FILE}" "KEY_PREFIX = \"${OAUTH_PREFIX}\""
    require_anchor "${SESSION_FIELDS_JAVA_FILE}" "USER_SESSIONS_KEY_PREFIX = \"${INDEX_PREFIX}\""
    require_anchor "${SESSION_GATEWAY_APP_YML}" "key-prefix: \${SESSION_KEY_PREFIX:${SESSION_PREFIX}}"

    CREATE_LUA=$(cat "${CREATE_LUA_FILE}")
    UPDATE_LUA=$(cat "${UPDATE_LUA_FILE}")
    DELETE_LUA=$(cat "${DELETE_LUA_FILE}")
    OAUTH_LUA=$(extract_oauth_script)

    printf 'Contract inputs (sha256):\n'
    for file in "${CREATE_LUA_FILE}" "${UPDATE_LUA_FILE}" "${DELETE_LUA_FILE}" "${OAUTH_JAVA_FILE}"; do
        printf '  %s  %s\n' "$(sha256sum "${file}" | cut -c1-64)" "${file}"
    done
}

secret_value() {
    local key="$1" value
    value=$(kubectl get secret "${SECRET}" -n "${NAMESPACE}" -o jsonpath="{.data.${key}}" | base64 -d)
    [[ -n "${value}" ]] || die "${SECRET} is missing ${key}"
    printf '%s' "${value}"
}

random_hex() {
    od -An -tx1 -N"$1" /dev/urandom | tr -d ' \n'
}

pod_uid() {
    kubectl get pod "${POD}" -n "${NAMESPACE}" -o jsonpath='{.metadata.uid}' 2>/dev/null || true
}

pod_ready() {
    kubectl get pod "${POD}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true
}

info_field() {
    ops INFO "$1" | sed -n "s/^$2://p"
}

server_time_ms() {
    local sec usec
    { read -r sec; read -r usec; } < <(ops TIME)
    printf '%s\n' $(( sec * 1000 + usec / 1000 ))
}

hash_snapshot() {
    ops HGETALL "$1" | paste -d= - - | LC_ALL=C sort | paste -sd';' -
}

pexpiretime() {
    ops PEXPIRETIME "$1"
}

manifest() {
    kubectl exec -n "${NAMESPACE}" "${POD}" -c "${CONTAINER}" -- cat "${AOF_MANIFEST}"
}

manifest_file() {
    awk -v t="$2" '$1 == "file" && $NF == t { print $2 }' <<<"$1"
}

# One line per ACL LOG entry: username|context|object|reason|client-info.
acl_log_entries() {
    ops ACL LOG 128 | awk '
        function flush() { if (have) print e["username"] "|" e["context"] "|" e["object"] "|" e["reason"] "|" e["client-info"]; delete e; have = 0 }
        NR % 2 == 1 { key = $0; if (key == "count") flush(); next }
        { e[key] = $0; have = 1 }
        END { flush() }
    '
}

loader_entries() {
    acl_log_entries | awk -F'|' -v id="${AOF_LOADER_CLIENT_ID}" \
        'index($5, "id=" id " ") == 1 && index($5, " fd=-1 ") > 0'
}

# Prints "<key> multi" or "<key> toplevel" for each owned key found as a
# command argument in the copied incremental AOF.
aof_framing() {
    local file="$1"
    shift
    tr -d '\r' <"${file}" | awk -v keys="$*" '
        BEGIN { n = split(keys, list, " "); for (i = 1; i <= n; i++) want[list[i]] = 1 }
        $0 == "MULTI" { inblock = 1; next }
        $0 == "EXEC" { inblock = 0; next }
        ($0 in want) { print $0 " " (inblock ? "multi" : "toplevel") }
    ' | LC_ALL=C sort -u
}

# Asserts an absolute expiry lies within [start + ttl, end + ttl] plus 1 s slack.
check_expiry_window() {
    local description="$1" actual="$2" start_ms="$3" end_ms="$4" ttl_seconds="$5"
    local low=$(( start_ms + ttl_seconds * 1000 - 1000 )) high=$(( end_ms + ttl_seconds * 1000 + 1000 ))
    if [[ "${actual}" =~ ^[0-9]+$ ]] && (( actual >= low && actual <= high )); then
        pass "${description}"
    else
        fail "${description} (expected ${low}..${high}, got '${actual}')"
    fi
}

create_session() {
    local digest="$1" user_id="$2" ttl="$3" roles="$4" permissions="$5" now
    now=$(( $(server_time_ms) / 1000 ))
    gateway EVAL "${CREATE_LUA}" 2 \
        "${SESSION_PREFIX}${digest}" "${INDEX_PREFIX}${user_id}" \
        "${digest}" "${ttl}" \
        user_id "${user_id}" \
        idp_sub "redis-persistence|${user_id}" \
        email "${user_id}@budgetanalyzer.invalid" \
        display_name "Synthetic-${user_id}" \
        picture "" \
        roles "${roles}" \
        permissions "${permissions}" \
        created_at "${now}" \
        expires_at "$(( now + ttl ))"
}

rewrite_base() {
    local before reply deadline
    before=$(info_field persistence aof_rewrites)
    [[ "${before}" =~ ^[0-9]+$ ]] || die "could not read aof_rewrites"
    reply=$(ops BGREWRITEAOF)
    [[ "${reply}" == "Background append only file rewriting started" ]] \
        || die "BGREWRITEAOF did not start: ${reply}"
    deadline=$(( $(date +%s) + REWRITE_TIMEOUT_SECONDS ))
    while (( $(date +%s) < deadline )); do
        if (( $(info_field persistence aof_rewrites) > before )) \
            && [[ "$(info_field persistence aof_rewrite_in_progress)" == "0" ]] \
            && [[ "$(info_field persistence aof_rewrite_scheduled)" == "0" ]]; then
            check_eq "base rewrite finished with status ok" "ok" \
                "$(info_field persistence aof_last_bgrewrite_status)"
            return 0
        fi
        sleep 1
    done
    die "AOF rewrite did not finish within ${REWRITE_TIMEOUT_SECONDS}s"
}

preflight() {
    local acl replicas ready entries

    printf '\nPreflight\n'
    assert_local_kind_target || die "exact local Kubernetes target check failed"
    pass "exact local Kubernetes target (kind-kind)"

    replicas=$(kubectl get statefulset "${STATEFULSET}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
    ready=$(kubectl get statefulset "${STATEFULSET}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
    [[ "${replicas}" == "1" && "${ready}" == "1" ]] \
        || die "${STATEFULSET} must have exactly one ready replica (spec ${replicas:-unset}, ready ${ready:-0})"
    [[ "$(pod_ready)" == "True" ]] || die "${POD} is not Ready"
    pass "${STATEFULSET} has one Ready replica"

    OPS_PASSWORD=$(secret_value ops-password)
    GATEWAY_PASSWORD=$(secret_value session-gateway-password)
    EXT_AUTHZ_PASSWORD=$(secret_value ext-authz-password)

    acl=$(ops ACL LIST)
    grep -Fqx "${EXPECTED_DEFAULT_ACL}" <<<"${acl}" \
        || die "the live ACL does not have '${EXPECTED_DEFAULT_ACL}'; complete the Redis Session ACL Cutover first (nothing was written or restarted)"
    grep -Eqx "${EXPECTED_HEALTH_ACL_REGEX}" <<<"${acl}" \
        || die "the live ACL does not limit redis-health to PING; complete the Redis Session ACL Cutover first (nothing was written or restarted)"
    pass "live ACL has default off with replay permissions and a PING-only redis-health"

    [[ "$(info_field persistence aof_enabled)" == "1" ]] || die "AOF is not enabled on ${POD}"
    pass "AOF is enabled"

    entries=$(loader_entries)
    [[ -z "${entries}" ]] \
        || die "the current ${POD} start logged AOF-loader ACL denials; inspect ACL LOG before restarting"
    pass "no AOF-loader ACL denials since the current start"
}

# Prints the HTTP status of the protected ingress request with a session
# cookie. The cookie goes through curl's stdin config so the token never
# appears in a process argument list. Rate limiting (429) and transient
# upstream or connection errors (5xx, 000) are retried, because ext-authz
# reconnects to Redis after a restart; 200 and 401 return immediately.
ingress_status() {
    local token="$1" status attempt
    for ((attempt = 1; attempt <= INGRESS_ATTEMPTS; attempt++)); do
        status=$(printf 'cookie = "__Host-BA_SESSION=%s"\n' "${token}" \
            | curl --silent --output /dev/null --max-redirs 0 --max-time "${CURL_TIMEOUT}" \
                --write-out '%{http_code}' --config - "${INGRESS_URL}" 2>/dev/null || true)
        status="${status:-000}"
        [[ "${status}" == "429" || "${status}" == 5* || "${status}" == "000" ]] || break
        sleep 2
    done
    printf '%s\n' "${status}"
}

check_ingress() {
    local description="$1" expected="$2" token="$3"
    check_eq "${description}" "${expected}" "$(ingress_status "${token}")"
}

pvc_identity() {
    local claim
    claim=$(kubectl get pod "${POD}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.volumes[?(@.name=="redis-data")].persistentVolumeClaim.claimName}')
    printf '%s %s\n' "${claim}" "$(kubectl get pvc "${claim}" -n "${NAMESPACE}" \
        -o jsonpath='{.metadata.uid} {.spec.volumeName}')"
}

new_token() {
    random_hex 32
}

# Starts a new AOF base and records the manifest, base file and the
# incremental file the next writes go to (MANIFEST_BEFORE, BASE_FILE,
# INCR_FILE).
rewrite_and_record() {
    rewrite_base
    MANIFEST_BEFORE=$(manifest)
    INCR_FILE=$(manifest_file "${MANIFEST_BEFORE}" i)
    BASE_FILE=$(manifest_file "${MANIFEST_BEFORE}" b)
    [[ -n "${INCR_FILE}" && "${INCR_FILE}" != *$'\n'* ]] \
        || die "expected one incremental AOF file, got: ${INCR_FILE:-<none>}"
}

# Requires that the given keys appear in the current incremental AOF with the
# expected framing. Arguments are "<key> multi|toplevel" lines.
check_framing() {
    local description="$1" expected keys=() line
    shift
    expected=$(printf '%s\n' "$@" | LC_ALL=C sort -u)
    for line in "$@"; do
        keys+=("${line%% *}")
    done
    check_eq "AOF manifest unchanged since the base rewrite" "${MANIFEST_BEFORE}" "$(manifest)"
    (
        umask 077
        kubectl exec -n "${NAMESPACE}" "${POD}" -c "${CONTAINER}" -- \
            cat "${AOF_DIR}/${INCR_FILE}" >"${WORK_DIR}/incr.aof"
    )
    check_eq "${description}" "${expected}" "$(aof_framing "${WORK_DIR}/incr.aof" "${keys[@]}")"
    rm -f "${WORK_DIR}/incr.aof"
}

# Restarts the StatefulSet, waits for a replaced Ready pod that answers PING,
# and checks that it replayed the recorded base and incremental files from the
# same PersistentVolumeClaim without AOF-loader denials.
restart_and_check_replay() {
    local old_uid new_uid deadline logs
    assert_local_kind_target || die "exact local Kubernetes target check failed before the restart"
    old_uid=$(pod_uid)
    check_eq "AOF manifest still unchanged immediately before restart" "${MANIFEST_BEFORE}" "$(manifest)"
    RESTART_REQUESTED=true
    kubectl rollout restart "statefulset/${STATEFULSET}" -n "${NAMESPACE}" >/dev/null
    kubectl rollout status "statefulset/${STATEFULSET}" -n "${NAMESPACE}" \
        --timeout="${ROLLOUT_TIMEOUT_SECONDS}s" >/dev/null \
        || die "${STATEFULSET} rollout did not finish within ${ROLLOUT_TIMEOUT_SECONDS}s"
    deadline=$(( $(date +%s) + READY_TIMEOUT_SECONDS ))
    new_uid=$(pod_uid)
    while [[ "$(pod_ready)" != "True" || -z "${new_uid}" || "${new_uid}" == "${old_uid}" \
        || "$(ops PING 2>/dev/null)" != "PONG" ]]; do
        (( $(date +%s) < deadline )) || die "${POD} was not replaced and ready within ${READY_TIMEOUT_SECONDS}s"
        sleep 1
        new_uid=$(pod_uid)
    done
    pass "${POD} was replaced (new UID) and answers PING"
    check_eq "${POD} mounts the same PersistentVolumeClaim and volume" "${PVC_IDENTITY}" "$(pvc_identity)"

    logs=$(kubectl logs "${POD}" -n "${NAMESPACE}" -c "${CONTAINER}")
    check "restart loaded base ${BASE_FILE}" grep -qF "DB loaded from base file ${BASE_FILE}" <<<"${logs}"
    check "restart replayed incremental AOF ${INCR_FILE}" grep -qF "DB loaded from incr file ${INCR_FILE}" <<<"${logs}"
    check_eq "no AOF-loader ACL denials" "" "$(loader_entries)"
    check "default is still off with replay permissions" grep -Fqx "${EXPECTED_DEFAULT_ACL}" <(ops ACL LIST)
}

main() {
    local run_id user_refresh user_create user_live user_gone
    local t_refresh t_create t_live1 t_live2 t_gone_live
    local d_refresh d_create d_live1 d_live2 d_gone_short d_gone_live state
    local s_refresh s_create s_live1 s_live2 s_gone_short s_gone_live
    local i_refresh i_create i_live i_gone oauth
    local seed_refresh created_short start end reply
    local pre_refresh pre_refresh_exp pre_i_refresh_exp pre_create pre_create_exp pre_i_create_exp
    local pre_oauth pre_oauth_exp

    command -v kubectl >/dev/null 2>&1 || die "kubectl is required"
    command -v curl >/dev/null 2>&1 || die "curl is required"
    load_scripts
    preflight
    PVC_IDENTITY=$(pvc_identity)
    [[ "${PVC_IDENTITY}" =~ ^[^\ ]+\ [0-9a-f-]{36}\ [^\ ]+$ ]] \
        || die "could not resolve the ${POD} PersistentVolumeClaim (got '${PVC_IDENTITY}')"
    printf '  PVC: %s\n' "${PVC_IDENTITY}"

    WORK_DIR=$(mktemp -d)
    run_id=$(random_hex 6)
    user_refresh="usr_redis_persistence_${run_id}_refresh"
    user_create="usr_redis_persistence_${run_id}_create"
    user_live="usr_redis_persistence_${run_id}_revoke_live"
    user_gone="usr_redis_persistence_${run_id}_revoke_gone"
    t_refresh=$(new_token); d_refresh=$(session_digest_for "${t_refresh}")
    t_create=$(new_token); d_create=$(session_digest_for "${t_create}")
    t_live1=$(new_token); d_live1=$(session_digest_for "${t_live1}")
    t_live2=$(new_token); d_live2=$(session_digest_for "${t_live2}")
    d_gone_short=$(session_digest_for "$(new_token)")
    t_gone_live=$(new_token); d_gone_live=$(session_digest_for "${t_gone_live}")
    state=$(random_hex 16)
    s_refresh="${SESSION_PREFIX}${d_refresh}"; i_refresh="${INDEX_PREFIX}${user_refresh}"
    s_create="${SESSION_PREFIX}${d_create}"; i_create="${INDEX_PREFIX}${user_create}"
    s_live1="${SESSION_PREFIX}${d_live1}"; s_live2="${SESSION_PREFIX}${d_live2}"
    i_live="${INDEX_PREFIX}${user_live}"
    s_gone_short="${SESSION_PREFIX}${d_gone_short}"; s_gone_live="${SESSION_PREFIX}${d_gone_live}"
    i_gone="${INDEX_PREFIX}${user_gone}"
    oauth="${OAUTH_PREFIX}${state}"
    OWNED_KEYS=("${s_refresh}" "${i_refresh}" "${s_create}" "${i_create}" \
        "${s_live1}" "${s_live2}" "${i_live}" "${s_gone_short}" "${s_gone_live}" "${i_gone}" "${oauth}")
    [[ "$(ops EXISTS "${OWNED_KEYS[@]}")" == "0" ]] || die "a synthetic key name is already in use"
    CLEANUP_NEEDED=true
    printf 'Synthetic run id: %s\n' "${run_id}"

    check_ingress "unknown session is denied at ingress (401)" 401 "$(new_token)"

    printf '\nRestart 1: creation, heartbeat refresh and OAuth state\n'
    printf '\nSeed write before the base rewrite\n'
    check_eq "session to refresh created" "1" \
        "$(create_session "${d_refresh}" "${user_refresh}" "${SESSION_TTL}" USER "${SEED_PERMISSIONS}")"
    seed_refresh=$(hash_snapshot "${s_refresh}")
    rewrite_and_record

    printf '\nWrites after the base rewrite\n'
    start=$(server_time_ms)
    check_eq "session created after the rewrite" "1" \
        "$(create_session "${d_create}" "${user_create}" "${SESSION_TTL}" USER "${SEED_PERMISSIONS}")"
    reply=$(gateway EVAL "${UPDATE_LUA}" 2 "${s_refresh}" "${i_refresh}" "${d_refresh}" \
        roles USER,ADMIN \
        permissions "${REFRESH_PERMISSIONS}" \
        expires_at "$(( start / 1000 + REFRESH_TTL ))" \
        "${REFRESH_TTL}")
    check_eq "heartbeat refresh changed permissions and expiry" "1" "${reply}"
    reply=$(gateway EVAL "${OAUTH_LUA}" 1 "${oauth}" "${OAUTH_TTL}" \
        browser_binding_hash "$(session_digest_for "binding-${state}")" \
        redirect_uri https://app.budgetanalyzer.localhost/login/oauth2/code/idp \
        return_url /dashboard \
        nonce "nonce-${state}" \
        code_verifier "verifier-${state}")
    check_eq "OAuth state created" "1" "${reply}"
    end=$(server_time_ms)

    pre_refresh=$(hash_snapshot "${s_refresh}"); pre_refresh_exp=$(pexpiretime "${s_refresh}")
    pre_i_refresh_exp=$(pexpiretime "${i_refresh}")
    pre_create=$(hash_snapshot "${s_create}"); pre_create_exp=$(pexpiretime "${s_create}")
    pre_i_create_exp=$(pexpiretime "${i_create}")
    pre_oauth=$(hash_snapshot "${oauth}"); pre_oauth_exp=$(pexpiretime "${oauth}")

    check "refreshed hash differs from the seed" test "${pre_refresh}" != "${seed_refresh}"
    check "refreshed hash has the new permissions" \
        grep -qF ";permissions=${REFRESH_PERMISSIONS};" <<<"${pre_refresh}"
    check "refreshed hash has the new roles" grep -q ';roles=USER,ADMIN;' <<<"${pre_refresh}"
    check_expiry_window "refreshed session expiry moved to the new TTL" "${pre_refresh_exp}" "${start}" "${end}" "${REFRESH_TTL}"
    check_expiry_window "refreshed index expiry moved forward" "${pre_i_refresh_exp}" "${start}" "${end}" "${REFRESH_TTL}"
    check "created session hash is complete" grep -q "^created_at=.*user_id=${user_create}$" <<<"${pre_create}"
    check_eq "created session is indexed" "1" "$(ops SISMEMBER "${i_create}" "${d_create}")"
    check_expiry_window "created session expiry" "${pre_create_exp}" "${start}" "${end}" "${SESSION_TTL}"
    check_expiry_window "created index expiry" "${pre_i_create_exp}" "${start}" "${end}" "${SESSION_TTL}"
    check "OAuth hash has every field" \
        grep -q '^browser_binding_hash=.*;code_verifier=.*;nonce=.*;redirect_uri=.*;return_url=/dashboard$' <<<"${pre_oauth}"
    check_expiry_window "OAuth state expiry" "${pre_oauth_exp}" "${start}" "${end}" "${OAUTH_TTL}"
    check_ingress "created session authorizes GET ${INGRESS_PATH} before restart (200)" 200 "${t_create}"
    check_ingress "refreshed session authorizes GET ${INGRESS_PATH} before restart (200)" 200 "${t_refresh}"

    printf '\nIncremental AOF before restart 1\n'
    check_framing "creation, refresh and OAuth writes are MULTI/EXEC blocks" \
        "${s_create} multi" "${s_refresh} multi" "${oauth} multi"

    printf '\nRestart 1\n'
    restart_and_check_replay
    check_eq "created session hash survives" "${pre_create}" "$(hash_snapshot "${s_create}")"
    check_eq "created session expiry survives" "${pre_create_exp}" "$(pexpiretime "${s_create}")"
    check_eq "created session index membership survives" "1" "$(ops SISMEMBER "${i_create}" "${d_create}")"
    check_eq "created index expiry survives" "${pre_i_create_exp}" "$(pexpiretime "${i_create}")"
    check_eq "refreshed roles and permissions survive" "${pre_refresh}" "$(hash_snapshot "${s_refresh}")"
    check_eq "refreshed session expiry survives" "${pre_refresh_exp}" "$(pexpiretime "${s_refresh}")"
    check_eq "refreshed session index membership survives" "1" "$(ops SISMEMBER "${i_refresh}" "${d_refresh}")"
    check_eq "refreshed index expiry survives" "${pre_i_refresh_exp}" "$(pexpiretime "${i_refresh}")"
    check_eq "OAuth state hash survives" "${pre_oauth}" "$(hash_snapshot "${oauth}")"
    check_eq "OAuth state expiry survives" "${pre_oauth_exp}" "$(pexpiretime "${oauth}")"
    check "remaining TTLs are positive, so absent keys would be replay loss, not expiry" \
        test "$(ops PTTL "${s_create}")" -gt 0 -a "$(ops PTTL "${s_refresh}")" -gt 0 -a "$(ops PTTL "${oauth}")" -gt 0
    check "ext-authz reads the restored session as itself" grep -qx "${user_create}" \
        <(cli_as ext-authz "${EXT_AUTHZ_PASSWORD}" HGETALL "${s_create}")
    check_ingress "restored created session authorizes GET ${INGRESS_PATH} (200)" 200 "${t_create}"
    check_ingress "restored refreshed session authorizes GET ${INGRESS_PATH} (200)" 200 "${t_refresh}"

    printf '\nRestart 2: bulk revocation\n'
    printf '\nSeed writes before the base rewrite\n'
    check_eq "first live session for bulk revocation created" "1" \
        "$(create_session "${d_live1}" "${user_live}" "${SESSION_TTL}" USER "${SEED_PERMISSIONS}")"
    check_eq "second live session for bulk revocation created" "1" \
        "$(create_session "${d_live2}" "${user_live}" "${SESSION_TTL}" USER "${SEED_PERMISSIONS}")"
    # The short-lived session goes first so the live session's EXPIRE sets
    # the index TTL.
    check_eq "short-lived session created" "1" \
        "$(create_session "${d_gone_short}" "${user_gone}" 1 USER "${SEED_PERMISSIONS}")"
    created_short=$(server_time_ms)
    check_eq "live session beside the short-lived one created" "1" \
        "$(create_session "${d_gone_live}" "${user_gone}" "${SESSION_TTL}" USER "${SEED_PERMISSIONS}")"
    check_ingress "first all-live session authorizes before revocation (200)" 200 "${t_live1}"
    check_ingress "second all-live session authorizes before revocation (200)" 200 "${t_live2}"
    check_ingress "live session beside the gone member authorizes before revocation (200)" 200 "${t_gone_live}"
    while (( $(server_time_ms) < created_short + 1500 )); do
        sleep 0.2
    done
    # Reading the expired key removes it if active expiry has not yet.
    check_eq "short-lived key is gone" "0" "$(ops EXISTS "${s_gone_short}")"
    check_eq "index still lists the gone session" "1" "$(ops SISMEMBER "${i_gone}" "${d_gone_short}")"
    rewrite_and_record

    printf '\nRevocations after the base rewrite\n'
    check_eq "bulk revocation, all members live, deleted both sessions and the index" "3" \
        "$(gateway EVAL "${DELETE_LUA}" 1 "${i_live}" "${SESSION_PREFIX}")"
    check_eq "bulk revocation, one member already gone, deleted the live session and the index" "2" \
        "$(gateway EVAL "${DELETE_LUA}" 1 "${i_gone}" "${SESSION_PREFIX}")"
    check_eq "revoked keys are absent before restart" "0" \
        "$(ops EXISTS "${s_live1}" "${s_live2}" "${i_live}" "${s_gone_short}" "${s_gone_live}" "${i_gone}")"
    check_ingress "revoked all-live sessions are denied before restart (401)" 401 "${t_live1}"
    check_ingress "revoked gone-member user's live session is denied before restart (401)" 401 "${t_gone_live}"

    printf '\nIncremental AOF before restart 2\n'
    check_framing "both revocations are top-level DEL commands" \
        "${i_live} toplevel" "${i_gone} toplevel"

    printf '\nRestart 2\n'
    restart_and_check_replay
    check_eq "all-live revocation holds" "0" "$(ops EXISTS "${s_live1}" "${s_live2}" "${i_live}")"
    check_eq "gone-member revocation holds" "0" "$(ops EXISTS "${s_gone_short}" "${s_gone_live}" "${i_gone}")"
    check_ingress "first revoked all-live session is denied after restart (401)" 401 "${t_live1}"
    check_ingress "second revoked all-live session is denied after restart (401)" 401 "${t_live2}"
    check_ingress "revoked gone-member user's live session is denied after restart (401)" 401 "${t_gone_live}"
    check_eq "restart-1 session survives restart 2 from the new base" "${pre_create}" "$(hash_snapshot "${s_create}")"
    check_ingress "restart-1 session still authorizes after restart 2 (200)" 200 "${t_create}"

    printf '\nPassed: %d  Failed: %d\n' "${PASSED}" "${FAILED}"
    (( FAILED == 0 ))
}
main
