#!/bin/bash

# Offline AOF replay regression harness for redis-session. It starts disposable,
# network-less Redis containers from the digest-pinned redis-session image, runs
# the real Session Gateway scripts as the session-gateway ACL user, restarts
# Redis gracefully on the same data volume, and asserts what the AOF replay
# restores. Legacy-control mode must reproduce the known AOF-loader ACL denials
# and data loss/revival; deployed mode loads the checked-in ACL from
# start-redis.sh and must preserve every write and keep clients from
# authenticating as `default`. It never contacts a Kubernetes
# cluster, never prints the synthetic credentials, and removes every container,
# volume and temporary file it creates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATEFULSET_FILE="${REPO_DIR}/kubernetes/infrastructure/redis-session/statefulset.yaml"
START_SCRIPT_FILE="${REPO_DIR}/kubernetes/infrastructure/redis-session/start-redis.sh"
SESSION_GATEWAY_DIR="${SESSION_GATEWAY_DIR:-$(dirname "${REPO_DIR}")/session-gateway}"

CREATE_LUA_FILE="${SESSION_GATEWAY_DIR}/src/main/resources/redis/create-session.lua"
UPDATE_LUA_FILE="${SESSION_GATEWAY_DIR}/src/main/resources/redis/conditional-update.lua"
DELETE_LUA_FILE="${SESSION_GATEWAY_DIR}/src/main/resources/redis/delete-user-sessions.lua"
OAUTH_JAVA_FILE="${SESSION_GATEWAY_DIR}/src/main/java/org/budgetanalyzer/sessiongateway/security/RedisAuthorizationRequestRepository.java"
SESSION_FIELDS_JAVA_FILE="${SESSION_GATEWAY_DIR}/src/main/java/org/budgetanalyzer/sessiongateway/session/SessionHashFields.java"
SESSION_GATEWAY_APP_YML="${SESSION_GATEWAY_DIR}/src/main/resources/application.yml"

# Key prefixes are anchored against the Session Gateway sources in load_inputs.
SESSION_PREFIX="session:"
INDEX_PREFIX="user_sessions:"
OAUTH_PREFIX="oauth2:state:"

# Historical, test-only copy of the pre-fix `default` user from
# kubernetes/infrastructure/redis-session/start-redis.sh, with a harness-only
# password variable. It exists only so the legacy-control mode can reproduce
# the AOF-loader denials. Never deploy it.
# shellcheck disable=SC2016 # ${...} is expanded by the container start script, not here.
LEGACY_DEFAULT_ACL='user default reset on >${HARNESS_LEGACY_DEFAULT_PASSWORD} ~* +ping +auth'

# Redis uses UINT64_MAX as the client id of the AOF loader (CLIENT_ID_AOF).
AOF_LOADER_CLIENT_ID="18446744073709551615"

WAIT_SECONDS=30
VERIFIER_LABEL="org.budgetanalyzer.verifier=redis-session-aof-replay"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
RUN_LABEL="org.budgetanalyzer.verifier-run=${RUN_ID}"

MODE="all"
PASSED=0
FAILED=0
WORK_DIR=""
REDIS_IMAGE=""
CONTAINERS=()
VOLUMES=()

APP_ACL_LINES=""
DEPLOYED_ACL_LINES=""
CREATE_LUA=""
UPDATE_LUA=""
DELETE_LUA=""
OAUTH_LUA=""

GATEWAY_PASSWORD=""
EXT_AUTHZ_PASSWORD=""
OPS_PASSWORD=""
LEGACY_DEFAULT_PASSWORD=""
HEALTH_PASSWORD=""

usage() {
    cat <<'EOF'
Usage: ./scripts/guardrails/verify-redis-session-aof-replay.sh [--mode MODE]

Offline AOF replay regression harness for redis-session. Each scenario starts a
fresh guest-Docker container from the digest-pinned image in
kubernetes/infrastructure/redis-session/statefulset.yaml with --network none,
no published ports, a read-only root filesystem and a private named data
volume. It runs the real Session Gateway Lua scripts (read from
../session-gateway, or SESSION_GATEWAY_DIR) as the session-gateway ACL user
extracted from start-redis.sh, stops Redis gracefully, starts it again on the
same volume without an AOF rewrite, and asserts the replayed state.

Scenarios: session creation, heartbeat permission/expiry refresh and OAuth
state creation after a completed base rewrite; bulk revocation with all
indexed sessions live, with one expired-but-present key, and with one member
whose key is already gone; and, in deployed mode, client authentication
isolation plus the `redis-cli -e --user redis-health ping` probe form.

The isolated test configuration listens on container loopback without TLS,
disables automatic AOF rewrites and RDB snapshots, and enables DEBUG (local
connections only) solely in the expired-but-present revocation case. It does
not change deployment inputs, generate certificates or contact a cluster.

Options:
  --mode MODE  legacy    reproduce the defect with the historical ACL fixture
               deployed  prove the checked-in ACL from start-redis.sh
               all       run legacy then deployed (default)
  -h, --help   Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            [[ $# -ge 2 ]] || { printf 'ERROR: --mode requires a value\n' >&2; exit 1; }
            MODE="$2"
            shift 2
            ;;
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

case "${MODE}" in
    legacy|deployed|all) ;;
    *)
        printf 'ERROR: unknown mode: %s\n' "${MODE}" >&2
        exit 1
        ;;
esac

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

remove_container() {
    local name="$1"
    docker rm -f "${name}" >/dev/null 2>&1 || true
}

remove_volume() {
    local name="$1"
    docker volume rm -f "${name}" >/dev/null 2>&1 || true
}

cleanup() {
    set +e
    local name
    for name in "${CONTAINERS[@]}"; do
        remove_container "${name}"
    done
    for name in "${VOLUMES[@]}"; do
        remove_volume "${name}"
    done
    if [[ -n "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
}

trap cleanup EXIT

redis_image() {
    local image

    image=$(sed -nE 's#^[[:space:]]*image:[[:space:]]*(redis:[^[:space:]]*).*$#\1#p' \
        "${STATEFULSET_FILE}" | head -n 1)
    if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
        die "redis-session image in ${STATEFULSET_FILE#"${REPO_DIR}"/} is not digest-pinned: ${image:-<missing>}"
    fi
    printf '%s\n' "${image}"
}

# Prints the body of the ACL heredoc that start-redis.sh writes to $ACL_FILE.
deployed_acl_lines() {
    awk '
        /^cat > "\$ACL_FILE" <<EOF$/ { inblock = 1; next }
        inblock && /^EOF$/ { closed = 1; exit }
        inblock { print }
        END { if (!closed) exit 1 }
    ' "${START_SCRIPT_FILE}" \
        || die "could not extract the ACL heredoc from ${START_SCRIPT_FILE#"${REPO_DIR}"/}"
}

# Legacy-control mode keeps the exact checked-in application and operator lines.
app_acl_lines() {
    local user line count lines=""

    for user in session-gateway ext-authz redis-ops; do
        count=$(grep -cE "^user ${user} " "${START_SCRIPT_FILE}" || true)
        [[ "${count}" == "1" ]] \
            || die "expected exactly one 'user ${user}' ACL line in ${START_SCRIPT_FILE#"${REPO_DIR}"/}, found ${count}"
        line=$(grep -E "^user ${user} " "${START_SCRIPT_FILE}")
        lines+="${line}"$'\n'
    done
    printf '%s' "${lines}"
}

require_anchor() {
    local file="$1" anchor="$2"
    grep -qF -- "${anchor}" "${file}" \
        || die "contract drift: '${anchor}' not found in ${file}; update this harness deliberately"
}

# Extracts the CREATE_REQUEST_SCRIPT Java text block. Fails on any drift that
# would make the extracted Lua differ from what Session Gateway sends.
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
    [[ "${script}" == *"if redis.call('TYPE', KEYS[1]).ok ~= 'none' then"* ]] \
        || die "CREATE_REQUEST_SCRIPT no longer starts with the TYPE guard"
    [[ "${script}" == *"redis.call('HSET', KEYS[1], unpack(ARGV, 2))"* ]] \
        || die "CREATE_REQUEST_SCRIPT no longer writes fields with HSET from ARGV[2..]"
    [[ "${script}" == *"redis.call('EXPIRE', KEYS[1], ARGV[1])"* ]] \
        || die "CREATE_REQUEST_SCRIPT no longer sets the TTL from ARGV[1]"
    printf '%s\n' "${script}"
}

load_inputs() {
    local file

    [[ -d "${SESSION_GATEWAY_DIR}" ]] \
        || die "Session Gateway sources not found at ${SESSION_GATEWAY_DIR}; clone it beside this repo or set SESSION_GATEWAY_DIR"
    for file in "${CREATE_LUA_FILE}" "${UPDATE_LUA_FILE}" "${DELETE_LUA_FILE}" \
        "${OAUTH_JAVA_FILE}" "${SESSION_FIELDS_JAVA_FILE}" "${SESSION_GATEWAY_APP_YML}" \
        "${START_SCRIPT_FILE}" "${STATEFULSET_FILE}"; do
        [[ -r "${file}" ]] || die "required input is missing or unreadable: ${file}"
    done

    # Calling conventions the harness relies on.
    require_anchor "${CREATE_LUA_FILE}" "-- KEYS[2]: user sessions index key"
    require_anchor "${CREATE_LUA_FILE}" "-- ARGV[2]: TTL in seconds"
    require_anchor "${CREATE_LUA_FILE}" "-- ARGV[3..N]: alternating hash field/value pairs"
    require_anchor "${UPDATE_LUA_FILE}" "-- ARGV[2..N-1]: field/value pairs to HSET"
    require_anchor "${UPDATE_LUA_FILE}" "-- ARGV[N]: TTL in seconds (always the last argument)"
    require_anchor "${DELETE_LUA_FILE}" "-- KEYS[1]: user sessions index key"
    require_anchor "${DELETE_LUA_FILE}" "-- ARGV[1]: session key prefix"
    require_anchor "${OAUTH_JAVA_FILE}" "KEY_PREFIX = \"${OAUTH_PREFIX}\""
    require_anchor "${OAUTH_JAVA_FILE}" "arguments.add(Long.toString(ttl.toSeconds()));"
    require_anchor "${SESSION_FIELDS_JAVA_FILE}" "USER_SESSIONS_KEY_PREFIX = \"${INDEX_PREFIX}\""
    require_anchor "${SESSION_GATEWAY_APP_YML}" "key-prefix: \${SESSION_KEY_PREFIX:${SESSION_PREFIX}}"

    CREATE_LUA=$(cat "${CREATE_LUA_FILE}")
    UPDATE_LUA=$(cat "${UPDATE_LUA_FILE}")
    DELETE_LUA=$(cat "${DELETE_LUA_FILE}")
    OAUTH_LUA=$(extract_oauth_script)
    APP_ACL_LINES=$(app_acl_lines)
    DEPLOYED_ACL_LINES=$(deployed_acl_lines)

    printf 'Contract inputs (sha256):\n'
    for file in "${CREATE_LUA_FILE}" "${UPDATE_LUA_FILE}" "${DELETE_LUA_FILE}" "${OAUTH_JAVA_FILE}"; do
        printf '  %s  %s\n' "$(sha256sum "${file}" | cut -c1-64)" "${file}"
    done
    printf '  %s  CREATE_REQUEST_SCRIPT text block (extracted)\n' \
        "$(printf '%s\n' "${OAUTH_LUA}" | sha256sum | cut -c1-64)"
    printf '  %s  %s (ACL heredoc)\n' \
        "$(sha256sum "${START_SCRIPT_FILE}" | cut -c1-64)" "${START_SCRIPT_FILE#"${REPO_DIR}"/}"
    printf 'Redis image: %s\n' "${REDIS_IMAGE}"
}

random_hex() {
    od -An -tx1 -N"$1" /dev/urandom | tr -d ' \n'
}

digest_of() {
    printf '%s' "$1" | sha256sum | cut -c1-64
}

write_fixtures() {
    local mode acl_lines fixture_dir

    GATEWAY_PASSWORD=$(random_hex 24)
    EXT_AUTHZ_PASSWORD=$(random_hex 24)
    OPS_PASSWORD=$(random_hex 24)
    LEGACY_DEFAULT_PASSWORD=$(random_hex 24)
    HEALTH_PASSWORD=$(random_hex 24)

    (
        umask 077
        cat >"${WORK_DIR}/redis.env" <<EOF
REDIS_SESSION_GATEWAY_PASSWORD=${GATEWAY_PASSWORD}
REDIS_EXT_AUTHZ_PASSWORD=${EXT_AUTHZ_PASSWORD}
REDIS_SESSION_OPS_PASSWORD=${OPS_PASSWORD}
REDIS_SESSION_HEALTH_PASSWORD=${HEALTH_PASSWORD}
HARNESS_LEGACY_DEFAULT_PASSWORD=${LEGACY_DEFAULT_PASSWORD}
EOF
    )

    for mode in legacy deployed; do
        if [[ "${mode}" == "legacy" ]]; then
            acl_lines="${APP_ACL_LINES}"$'\n'"${LEGACY_DEFAULT_ACL}"
        else
            acl_lines="${DEPLOYED_ACL_LINES}"
        fi
        fixture_dir="${WORK_DIR}/fixture-${mode}"
        mkdir -p "${fixture_dir}"
        chmod 755 "${fixture_dir}"
        # The start script holds ${VAR} references only; Redis receives the
        # synthetic passwords through the container environment.
        cat >"${fixture_dir}/start.sh" <<EOF
#!/bin/sh
# Isolated ${mode} test configuration for verify-redis-session-aof-replay.sh.
# Loopback without TLS, no automatic AOF rewrites and no RDB snapshots.
set -eu
umask 077

cat > /tmp/users.acl <<ACL
${acl_lines}
ACL

if [ "\${HARNESS_DEBUG_COMMAND:-no}" = "local" ]; then
  set -- --enable-debug-command local
else
  set --
fi

exec redis-server \\
  --appendonly yes \\
  --auto-aof-rewrite-percentage 0 \\
  --save "" \\
  --maxmemory 128mb \\
  --maxmemory-policy noeviction \\
  --aclfile /tmp/users.acl \\
  --dir /data \\
  --bind 127.0.0.1 \\
  --port 6379 \\
  "\$@"
EOF
        chmod 644 "${fixture_dir}/start.sh"
    done
}

start_instance() {
    local name="$1" mode="$2" debug="$3"

    docker volume create --label "${VERIFIER_LABEL}" --label "${RUN_LABEL}" "${name}" >/dev/null
    VOLUMES+=("${name}")
    CONTAINERS+=("${name}")
    docker run --detach --name "${name}" \
        --label "${VERIFIER_LABEL}" --label "${RUN_LABEL}" \
        --network none --read-only \
        --tmpfs /tmp:rw,size=8m,mode=1777 \
        --user 999:1000 --cap-drop ALL --security-opt no-new-privileges \
        --memory 256m --pids-limit 64 \
        --env-file "${WORK_DIR}/redis.env" \
        --env "HARNESS_DEBUG_COMMAND=${debug}" \
        -v "${name}:/data" \
        -v "${WORK_DIR}/fixture-${mode}:/harness:ro" \
        --entrypoint /bin/sh \
        "${REDIS_IMAGE}" /harness/start.sh >/dev/null
    wait_ready "${name}"
}

finish_instance() {
    local name="$1"
    remove_container "${name}"
    remove_volume "${name}"
}

# Runs redis-cli inside the container as one ACL user. The password reaches
# docker exec through the environment, never through argv.
cli_as() {
    local container="$1" user="$2" password="$3"
    shift 3
    REDISCLI_AUTH="${password}" docker exec -e REDISCLI_AUTH "${container}" \
        redis-cli --no-auth-warning --user "${user}" "$@" | tr -d '\r'
}

ops() { local c="$1"; shift; cli_as "${c}" redis-ops "${OPS_PASSWORD}" "$@"; }
gateway() { local c="$1"; shift; cli_as "${c}" session-gateway "${GATEWAY_PASSWORD}" "$@"; }

# Sends raw commands on stdin over one unauthenticated connection.
raw_session() {
    local container="$1" commands="$2"
    printf '%s\n' "${commands}" | docker exec -i "${container}" redis-cli | tr -d '\r' | sed '/^$/d'
}

wait_ready() {
    local container="$1" deadline reply
    deadline=$(( $(date +%s) + WAIT_SECONDS ))
    while (( $(date +%s) < deadline )); do
        if [[ "$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null)" != "true" ]]; then
            docker logs --tail 20 "${container}" >&2 2>&1 || true
            die "${container} exited before becoming ready"
        fi
        reply=$(ops "${container}" PING 2>/dev/null || true)
        if [[ "${reply}" == "PONG" ]]; then
            return 0
        fi
        sleep 0.2
    done
    docker logs --tail 20 "${container}" >&2 2>&1 || true
    die "${container} did not become ready within ${WAIT_SECONDS}s"
}

server_time_ms() {
    local container="$1" sec usec
    { read -r sec; read -r usec; } < <(ops "${container}" TIME)
    printf '%s\n' $(( sec * 1000 + usec / 1000 ))
}

info_field() {
    local container="$1" section="$2" field="$3"
    ops "${container}" INFO "${section}" | sed -n "s/^${field}://p"
}

manifest() {
    docker exec "$1" cat /data/appendonlydir/appendonly.aof.manifest
}

manifest_file() {
    local container="$1" type="$2"
    manifest "${container}" | awk -v t="${type}" '$1 == "file" && $NF == t { print $2 }'
}

# Prints each command in the single incremental AOF file as one line with an
# uppercased command name and space-joined arguments.
incr_commands() {
    local container="$1" files
    files=$(manifest_file "${container}" i)
    [[ -n "${files}" && "${files}" != *$'\n'* ]] || die "expected exactly one incremental AOF file, got: ${files:-<none>}"
    docker exec "${container}" cat "/data/appendonlydir/${files}" | tr -d '\r' | awk '
        state == 0 {
            if ($0 ~ /^\*[0-9]+$/) { n = substr($0, 2) + 0; i = 0; line = ""; state = (n > 0) ? 1 : 0; next }
            if ($0 ~ /^#/) next
            print "PARSE_ERROR line " NR; exit 1
        }
        state == 1 {
            if ($0 ~ /^\$[0-9]+$/) { state = 2; next }
            print "PARSE_ERROR line " NR; exit 1
        }
        state == 2 {
            line = (i == 0) ? toupper($0) : line " " $0
            i++
            if (i == n) { print line; state = 0 } else { state = 1 }
            next
        }
        END { if (state != 0) { print "PARSE_ERROR truncated"; exit 1 } }
    '
}

# Groups each MULTI ... EXEC block into one "MULTI | CMD ... | EXEC" line.
group_transactions() {
    awk '
        $0 == "MULTI" { inblock = 1; block = "MULTI"; next }
        inblock && $0 == "EXEC" { print block " | EXEC"; inblock = 0; next }
        inblock { block = block " | " $0; next }
        { print }
        END { if (inblock) print "UNTERMINATED " block }
    '
}

count_multi() {
    grep -c '^MULTI' <<<"$1" || true
}

non_select_toplevel() {
    grep -vE '^(MULTI|SELECT )' <<<"$1" || true
}

# True when one MULTI block contains every given fixed substring.
has_block() {
    local view="$1" line substring ok
    shift
    while IFS= read -r line; do
        [[ "${line}" == MULTI* ]] || continue
        ok=1
        for substring in "$@"; do
            [[ "${line}" == *"${substring}"* ]] || ok=0
        done
        (( ok )) && return 0
    done <<<"${view}"
    return 1
}

# Prints the DEL command whose arguments are exactly the given keys, in any order.
find_del() {
    local commands="$1" line key
    local -a words
    shift
    while IFS= read -r line; do
        read -r -a words <<<"${line}"
        [[ "${words[0]:-}" == "DEL" && ${#words[@]} -eq $(( $# + 1 )) ]] || continue
        for key in "$@"; do
            [[ " ${line} " == *" ${key} "* ]] || continue 2
        done
        printf '%s\n' "${line}"
        return 0
    done <<<"${commands}"
    return 1
}

rewrite_base() {
    local container="$1" before reply deadline base incr
    before=$(info_field "${container}" persistence aof_rewrites)
    reply=$(ops "${container}" BGREWRITEAOF)
    [[ "${reply}" == "Background append only file rewriting started" ]] || die "BGREWRITEAOF failed: ${reply}"
    deadline=$(( $(date +%s) + WAIT_SECONDS ))
    while (( $(date +%s) < deadline )); do
        if (( $(info_field "${container}" persistence aof_rewrites) > before )) \
            && [[ "$(info_field "${container}" persistence aof_rewrite_in_progress)" == "0" ]] \
            && [[ "$(info_field "${container}" persistence aof_rewrite_scheduled)" == "0" ]]; then
            [[ "$(info_field "${container}" persistence aof_last_bgrewrite_status)" == "ok" ]] \
                || die "AOF rewrite did not succeed"
            base=$(manifest_file "${container}" b)
            [[ "${base}" == *.base.rdb && "${base}" != *$'\n'* ]] || die "unexpected AOF base after rewrite: ${base:-<none>}"
            incr=$(incr_commands "${container}")
            check_eq "base rewrite completed with an empty incremental AOF" "" "${incr}"
            return 0
        fi
        sleep 0.2
    done
    die "AOF rewrite did not finish within ${WAIT_SECONDS}s"
}

# Graceful stop and start on the same volume, with no rewrite in between.
restart_instance() {
    local container="$1" before_manifest exits_before exits_after incr
    before_manifest=$(manifest "${container}")
    incr=$(manifest_file "${container}" i)
    exits_before=$(docker logs "${container}" 2>&1 | grep -c 'Redis is now ready to exit' || true)
    docker stop --time 30 "${container}" >/dev/null
    check_eq "graceful shutdown exit code" "0" "$(docker inspect -f '{{.State.ExitCode}}' "${container}")"
    exits_after=$(docker logs "${container}" 2>&1 | grep -c 'Redis is now ready to exit' || true)
    check_eq "Redis logged a clean shutdown" "$(( exits_before + 1 ))" "${exits_after}"
    docker start "${container}" >/dev/null
    wait_ready "${container}"
    check_eq "AOF manifest unchanged across restart" "${before_manifest}" "$(manifest "${container}")"
    check "restart replayed incremental AOF ${incr}" \
        grep -qF "DB loaded from incr file ${incr}" <(docker logs "${container}" 2>&1)
}

# One line per ACL LOG entry: username|context|object|reason|client-info.
acl_log_entries() {
    ops "$1" ACL LOG 128 | awk '
        function flush() { if (have) print e["username"] "|" e["context"] "|" e["object"] "|" e["reason"] "|" e["client-info"]; delete e; have = 0 }
        NR % 2 == 1 { key = $0; if (key == "count") flush(); next }
        { e[key] = $0; have = 1 }
        END { flush() }
    '
}

loader_entries() {
    acl_log_entries "$1" | awk -F'|' -v id="${AOF_LOADER_CLIENT_ID}" \
        'index($5, "id=" id " ") == 1 && index($5, " fd=-1 ") > 0'
}

client_entries() {
    acl_log_entries "$1" | awk -F'|' -v id="${AOF_LOADER_CLIENT_ID}" 'index($5, "id=" id " ") != 1'
}

check_no_loader_denials() {
    local entries
    entries=$(loader_entries "$1")
    check_eq "no AOF-loader ACL denials" "" "${entries}"
}

check_loader_denials() {
    local container="$1" entries object
    shift
    entries=$(loader_entries "${container}")
    check "AOF loader logged ACL denials" test -n "${entries}"
    check "every AOF-loader denial is user default in a replayed transaction" \
        test -z "$(awk -F'|' '$1 != "default" || $2 != "multi" || $4 != "command"' <<<"${entries}")"
    for object in "$@"; do
        check "AOF loader denied replayed ${object}" \
            grep -qx "default|multi|${object}|command|.*" <<<"${entries}"
    done
}

hash_snapshot() {
    ops "$1" HGETALL "$2" | paste -d= - - | LC_ALL=C sort | paste -sd';' -
}

pexpiretime() {
    ops "$1" PEXPIRETIME "$2"
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
    local container="$1" digest="$2" user_id="$3" ttl="$4" roles="$5" permissions="$6" now
    now=$(( $(server_time_ms "${container}") / 1000 ))
    gateway "${container}" EVAL "${CREATE_LUA}" 2 \
        "${SESSION_PREFIX}${digest}" "${INDEX_PREFIX}${user_id}" \
        "${digest}" "${ttl}" \
        user_id "${user_id}" \
        idp_sub "auth0|${user_id}" \
        email "${user_id}@example.invalid" \
        display_name "Synthetic-${user_id}" \
        picture "" \
        roles "${roles}" \
        permissions "${permissions}" \
        created_at "${now}" \
        expires_at "$(( now + ttl ))"
}

revoke_user() {
    gateway "$1" EVAL "${DELETE_LUA}" 1 "${INDEX_PREFIX}$2" "${SESSION_PREFIX}"
}

# Creation, heartbeat refresh and OAuth state written after a base rewrite.
scenario_writes() {
    local mode="$1"
    local c="ba-redis-aof-replay-${RUN_ID}-${mode}-writes"
    local user1="usr_aof_replay_refresh" user2="usr_aof_replay_create"
    local d1 d2 state s1 s2 i1 i2 oauth start end reply
    local seed_s1 seed_s1_exp seed_i1_exp
    local pre_s1 pre_s1_exp pre_i1_exp pre_s2 pre_s2_exp pre_i2_exp pre_oauth pre_oauth_exp
    local commands view

    printf '\n[%s] creation, heartbeat refresh and OAuth state after a base rewrite\n' "${mode}"
    d1=$(digest_of "refresh-$(random_hex 16)")
    d2=$(digest_of "create-$(random_hex 16)")
    state=$(random_hex 16)
    s1="${SESSION_PREFIX}${d1}"; i1="${INDEX_PREFIX}${user1}"
    s2="${SESSION_PREFIX}${d2}"; i2="${INDEX_PREFIX}${user2}"
    oauth="${OAUTH_PREFIX}${state}"

    start_instance "${c}" "${mode}" no
    check "DEBUG is refused outside the lazy-expiry case" \
        grep -q 'DEBUG command not allowed' <<<"$(ops "${c}" DEBUG SET-ACTIVE-EXPIRE 0)"

    check_eq "seed session created as session-gateway" "1" \
        "$(create_session "${c}" "${d1}" "${user1}" 600 USER transactions:read)"
    seed_s1=$(hash_snapshot "${c}" "${s1}")
    seed_s1_exp=$(pexpiretime "${c}" "${s1}")
    seed_i1_exp=$(pexpiretime "${c}" "${i1}")
    rewrite_base "${c}"

    start=$(server_time_ms "${c}")
    check_eq "session created after the rewrite" "1" \
        "$(create_session "${c}" "${d2}" "${user2}" 900 USER transactions:read)"
    reply=$(gateway "${c}" EVAL "${UPDATE_LUA}" 2 "${s1}" "${i1}" "${d1}" \
        roles USER,ADMIN \
        permissions transactions:read,transactions:write \
        expires_at "$(( start / 1000 + 1800 ))" \
        1800)
    check_eq "heartbeat refresh changed permissions and expiry" "1" "${reply}"
    reply=$(gateway "${c}" EVAL "${OAUTH_LUA}" 1 "${oauth}" 300 \
        browser_binding_hash "$(digest_of "binding-${state}")" \
        redirect_uri https://app.budgetanalyzer.localhost/login/oauth2/code/idp \
        return_url /dashboard \
        nonce "nonce-${state}" \
        code_verifier "verifier-${state}")
    check_eq "OAuth state created" "1" "${reply}"
    end=$(server_time_ms "${c}")

    pre_s1=$(hash_snapshot "${c}" "${s1}"); pre_s1_exp=$(pexpiretime "${c}" "${s1}")
    pre_i1_exp=$(pexpiretime "${c}" "${i1}")
    pre_s2=$(hash_snapshot "${c}" "${s2}"); pre_s2_exp=$(pexpiretime "${c}" "${s2}")
    pre_i2_exp=$(pexpiretime "${c}" "${i2}")
    pre_oauth=$(hash_snapshot "${c}" "${oauth}"); pre_oauth_exp=$(pexpiretime "${c}" "${oauth}")

    check "refreshed hash has the new permissions" \
        grep -q ';permissions=transactions:read,transactions:write;' <<<"${pre_s1}"
    check "refreshed hash has the new roles" grep -q ';roles=USER,ADMIN;' <<<"${pre_s1}"
    check_expiry_window "refreshed session expiry moved to the new TTL" "${pre_s1_exp}" "${start}" "${end}" 1800
    check_expiry_window "refreshed index expiry moved forward" "${pre_i1_exp}" "${start}" "${end}" 1800
    check "created session hash is complete" grep -q "^created_at=.*user_id=${user2}$" <<<"${pre_s2}"
    check_eq "created session is indexed" "1" "$(ops "${c}" SISMEMBER "${i2}" "${d2}")"
    check_expiry_window "created session expiry" "${pre_s2_exp}" "${start}" "${end}" 900
    check_expiry_window "created index expiry" "${pre_i2_exp}" "${start}" "${end}" 900
    check "OAuth hash has every field" \
        grep -q '^browser_binding_hash=.*;code_verifier=.*;nonce=.*;redirect_uri=.*;return_url=/dashboard$' <<<"${pre_oauth}"
    check_expiry_window "OAuth state expiry" "${pre_oauth_exp}" "${start}" "${end}" 300

    commands=$(incr_commands "${c}")
    view=$(group_transactions <<<"${commands}")
    check_eq "incremental AOF holds exactly three script transactions" "3" "$(count_multi "${view}")"
    check_eq "incremental AOF has no top-level writes" "" "$(non_select_toplevel "${view}")"
    check "creation transaction is in the incremental AOF" has_block "${view}" \
        "| HSET ${s2} user_id ${user2} |" "| PEXPIREAT ${s2} " "| SADD ${i2} ${d2} |" "| PEXPIREAT ${i2} "
    check "refresh transaction is in the incremental AOF" has_block "${view}" \
        "| HSET ${s1} roles USER,ADMIN |" "| HSET ${s1} permissions transactions:read,transactions:write |" \
        "| PEXPIREAT ${s1} ${pre_s1_exp} |" "| PEXPIREAT ${i1} ${pre_i1_exp}"
    check "OAuth transaction is in the incremental AOF" has_block "${view}" \
        "| HSET ${oauth} " "| PEXPIREAT ${oauth} ${pre_oauth_exp} |"

    restart_instance "${c}"

    if [[ "${mode}" == "legacy" ]]; then
        check_loader_denials "${c}" hset pexpireat sadd
        check_eq "legacy: session created after the rewrite is lost" "0" "$(ops "${c}" EXISTS "${s2}" "${i2}")"
        check_eq "legacy: OAuth state is lost" "0" "$(ops "${c}" EXISTS "${oauth}")"
        check_eq "legacy: refreshed session reverts to base permissions" "${seed_s1}" "$(hash_snapshot "${c}" "${s1}")"
        check_eq "legacy: refreshed session reverts to base expiry" "${seed_s1_exp}" "$(pexpiretime "${c}" "${s1}")"
        check_eq "legacy: index reverts to base expiry" "${seed_i1_exp}" "$(pexpiretime "${c}" "${i1}")"
        check_legacy_auth_control "${c}"
    else
        check_no_loader_denials "${c}"
        check_eq "created session hash survives" "${pre_s2}" "$(hash_snapshot "${c}" "${s2}")"
        check_eq "created session expiry survives" "${pre_s2_exp}" "$(pexpiretime "${c}" "${s2}")"
        check_eq "created session index membership survives" "1" "$(ops "${c}" SISMEMBER "${i2}" "${d2}")"
        check_eq "created index expiry survives" "${pre_i2_exp}" "$(pexpiretime "${c}" "${i2}")"
        check_eq "refreshed permissions survive" "${pre_s1}" "$(hash_snapshot "${c}" "${s1}")"
        check_eq "refreshed session expiry survives" "${pre_s1_exp}" "$(pexpiretime "${c}" "${s1}")"
        check_eq "refreshed index expiry survives" "${pre_i1_exp}" "$(pexpiretime "${c}" "${i1}")"
        check_eq "OAuth state hash survives" "${pre_oauth}" "$(hash_snapshot "${c}" "${oauth}")"
        check_eq "OAuth state expiry survives" "${pre_oauth_exp}" "$(pexpiretime "${c}" "${oauth}")"
        check "ext-authz reads the restored session as itself" grep -qx "${user2}" \
            <(cli_as "${c}" ext-authz "${EXT_AUTHZ_PASSWORD}" HGETALL "${s2}")
        check_deployed_auth "${c}" "${s2}" "${pre_s2}"
    fi

    finish_instance "${c}"
}

# Legacy control: password-only AUTH logs in as default. This shows the
# deployed-mode rejection checks can observe a successful login.
check_legacy_auth_control() {
    local c="$1" out
    out=$(raw_session "${c}" "AUTH ${LEGACY_DEFAULT_PASSWORD}"$'\n'"PING")
    check_eq "legacy control: password-only AUTH logs in as default" $'OK\nPONG' "${out}"
}

# Runs `redis-cli [-e] [--user U] ping` with REDISCLI_AUTH set or unset and
# prints "<exit status> <reply>".
probe() {
    local container="$1" password="$2" status out
    shift 2
    set +e
    if [[ -n "${password}" ]]; then
        out=$(REDISCLI_AUTH="${password}" docker exec -e REDISCLI_AUTH "${container}" redis-cli "$@" ping 2>&1)
    else
        out=$(docker exec "${container}" redis-cli "$@" ping 2>&1)
    fi
    status=$?
    set -e
    # The PING reply and redis-cli's "AUTH failed" stderr line may interleave.
    printf '%s %s\n' "${status}" "$(tr -d '\r' <<<"${out}" | grep -E '^(PONG$|NOAUTH )' | tail -n 1)"
}

check_probe_failure() {
    local c="$1" label="$2" password="$3" result
    shift 3
    result=$(probe "${c}" "${password}" -e "$@")
    check "probe with -e exits non-zero with ${label}" \
        grep -qE '^[1-9][0-9]* NOAUTH ' <<<"${result}"
    result=$(probe "${c}" "${password}" "$@")
    check "probe without -e exits 0 despite ${label}" \
        grep -qE '^0 NOAUTH ' <<<"${result}"
}

check_deployed_auth() {
    local c="$1" session_key="$2" session_snapshot="$3" out command induced
    local wrong
    wrong=$(random_hex 24)

    check "checked-in ACL leaves default disabled, passwordless, with replay permissions" \
        grep -Eqx 'user default off sanitize-payload ~\* &\* \+@all' <(ops "${c}" ACL LIST)
    check "checked-in ACL limits redis-health to PING with no key or channel access" \
        grep -Eqx 'user redis-health on sanitize-payload #[0-9a-f]{64} resetchannels -@all \+ping' \
        <(ops "${c}" ACL LIST)

    check_eq "unauthenticated command is refused" "NOAUTH Authentication required." \
        "$(raw_session "${c}" "GET ${session_key}")"
    for out in "${HEALTH_PASSWORD}" "${OPS_PASSWORD}" "${GATEWAY_PASSWORD}"; do
        check_eq "password-only AUTH is refused" \
            $'WRONGPASS invalid username-password pair or user is disabled.\nNOAUTH Authentication required.' \
            "$(raw_session "${c}" "AUTH ${out}"$'\n'"PING")"
    done
    check_eq "explicit AUTH as default is refused" \
        $'WRONGPASS invalid username-password pair or user is disabled.\nWRONGPASS invalid username-password pair or user is disabled.\nNOAUTH Authentication required.' \
        "$(raw_session "${c}" "AUTH default ${HEALTH_PASSWORD}"$'\n'"AUTH default ${wrong}"$'\n'"PING")"
    check "HELLO AUTH as default is refused" grep -q '^WRONGPASS ' \
        <(raw_session "${c}" "HELLO 2 AUTH default ${wrong}")

    check_eq "redis-health authenticates and gets PONG" $'OK\nPONG' \
        "$(raw_session "${c}" "AUTH redis-health ${HEALTH_PASSWORD}"$'\n'"PING")"
    for command in "GET ${session_key}" "HGETALL ${session_key}" "SET harness:probe x" \
        "DEL ${session_key}" "EXPIRE ${session_key} 1" "KEYS *" "SCAN 0" "DBSIZE" "INFO" \
        "CONFIG GET maxmemory" "CONFIG SET maxmemory 1mb" "ACL LIST" "CLIENT LIST" \
        "FLUSHALL" "SHUTDOWN" "SELECT 1" "PUBLISH harness x" "EVAL return 1 0" \
        "BGREWRITEAOF"; do
        out=$(raw_session "${c}" "AUTH redis-health ${HEALTH_PASSWORD}"$'\n'"${command}" | tail -n +2)
        check "redis-health is denied: ${command}" grep -q '^NOPERM ' <<<"${out}"
    done
    check_eq "denied redis-health writes left the session intact" "${session_snapshot}" \
        "$(hash_snapshot "${c}" "${session_key}")"
    check_eq "denied redis-health writes created no key" "0" "$(ops "${c}" EXISTS harness:probe)"
    check_eq "Redis still running after denied SHUTDOWN" "PONG" "$(ops "${c}" PING)"

    check_eq "probe form exits 0 with the health password" "0 PONG" \
        "$(probe "${c}" "${HEALTH_PASSWORD}" -e --user redis-health)"
    check_probe_failure "${c}" "no credentials" "" --user redis-health
    check_probe_failure "${c}" "a wrong password" "${wrong}" --user redis-health
    check_probe_failure "${c}" "password-only AUTH" "${HEALTH_PASSWORD}"

    check_no_loader_denials "${c}"
    induced=$(client_entries "${c}")
    check "induced default AUTH failures are logged as client denials" \
        grep -q '^default|toplevel|AUTH|auth|' <<<"${induced}"
    check "induced redis-health denials are logged as client denials" \
        grep -q '^redis-health|toplevel|get|command|' <<<"${induced}"
}

# Bulk revocation after the live session and index are in the base RDB.
# Cases: all-live, lazy (expired key still present) and gone (key already removed).
scenario_revocation() {
    local mode="$1" kind="$2"
    local c="ba-redis-aof-replay-${RUN_ID}-${mode}-revoke-${kind}"
    local user="usr_aof_replay_revoke_${kind}" index other_digest live_digest other live
    local created deadline expected_reply commands view del pre_live

    printf '\n[%s] bulk revocation: %s\n' "${mode}" "${kind}"
    index="${INDEX_PREFIX}${user}"
    live_digest=$(digest_of "live-$(random_hex 16)")
    other_digest=$(digest_of "other-$(random_hex 16)")
    live="${SESSION_PREFIX}${live_digest}"
    other="${SESSION_PREFIX}${other_digest}"

    if [[ "${kind}" == "lazy" ]]; then
        start_instance "${c}" "${mode}" local
        check_eq "active expiry disabled (isolated DEBUG)" "OK" "$(ops "${c}" DEBUG SET-ACTIVE-EXPIRE 0)"
    else
        start_instance "${c}" "${mode}" no
    fi

    case "${kind}" in
        live)
            check_eq "first live session created" "1" \
                "$(create_session "${c}" "${other_digest}" "${user}" 900 USER transactions:read)"
            check_eq "second live session created" "1" \
                "$(create_session "${c}" "${live_digest}" "${user}" 900 USER transactions:read)"
            rewrite_base "${c}"
            check_eq "both sessions and the index are in memory" "3" "$(ops "${c}" DBSIZE)"
            expected_reply=3
            ;;
        lazy|gone)
            # The short-lived session goes first so the live session's
            # EXPIRE sets the index TTL.
            check_eq "short-lived session created" "1" \
                "$(create_session "${c}" "${other_digest}" "${user}" 1 USER transactions:read)"
            created=$(server_time_ms "${c}")
            check_eq "live session created" "1" \
                "$(create_session "${c}" "${live_digest}" "${user}" 900 USER transactions:read)"
            if [[ "${kind}" == "gone" ]]; then
                # Active expiry removes the key; DBSIZE does not touch keys.
                deadline=$(( $(date +%s) + WAIT_SECONDS ))
                while [[ "$(ops "${c}" DBSIZE)" != "2" ]] && (( $(date +%s) < deadline )); do
                    sleep 0.2
                done
                check_eq "active expiry removed the short-lived key" "2" "$(ops "${c}" DBSIZE)"
                rewrite_base "${c}"
            else
                rewrite_base "${c}"
                # Wait for the key to expire without reading it.
                while (( $(server_time_ms "${c}") < created + 1500 )); do
                    sleep 0.2
                done
                check_eq "expired key is still physically present" "3" "$(ops "${c}" DBSIZE)"
            fi
            check_eq "index still lists the short-lived session" "1" \
                "$(ops "${c}" SISMEMBER "${index}" "${other_digest}")"
            expected_reply=2
            ;;
    esac
    pre_live=$(hash_snapshot "${c}" "${live}")

    check_eq "revocation deleted the expected key count" "${expected_reply}" "$(revoke_user "${c}" "${user}")"
    check_eq "revoked keys are absent before restart" "0" "$(ops "${c}" EXISTS "${live}" "${index}")"

    commands=$(incr_commands "${c}")
    view=$(group_transactions <<<"${commands}")
    if [[ "${kind}" == "lazy" ]]; then
        check_eq "revocation is one MULTI/EXEC block" "1" "$(count_multi "${view}")"
        check_eq "incremental AOF has no top-level writes" "" "$(non_select_toplevel "${view}")"
        del=$(find_del "${commands}" "${other}" "${live}" "${index}" || true)
        check "block holds the lazy-expiry DEL and the revocation DEL" has_block "${view}" \
            "| DEL ${other} |" "| ${del} |"
    else
        check_eq "revocation is not wrapped in MULTI/EXEC" "0" "$(count_multi "${view}")"
        del=$(find_del "${commands}" "${other}" "${live}" "${index}" || true)
        check "revocation is one top-level DEL of every indexed key" test -n "${del}"
        check_eq "incremental AOF holds only that DEL" "${del}" "$(non_select_toplevel "${view}")"
    fi

    restart_instance "${c}"

    if [[ "${mode}" == "legacy" && "${kind}" == "lazy" ]]; then
        check_loader_denials "${c}" del
        check_eq "legacy: revoked live session is valid again" "${pre_live}" "$(hash_snapshot "${c}" "${live}")"
        check_eq "legacy: revoked index member is back" "1" "$(ops "${c}" SISMEMBER "${index}" "${live_digest}")"
    else
        check_no_loader_denials "${c}"
        check_eq "revocation holds after restart" "0" "$(ops "${c}" EXISTS "${live}" "${other}" "${index}")"
    fi

    finish_instance "${c}"
}

run_mode() {
    local mode="$1" kind
    printf '\n== %s mode ==\n' "${mode}"
    scenario_writes "${mode}"
    for kind in live lazy gone; do
        scenario_revocation "${mode}" "${kind}"
    done
}

command -v docker >/dev/null 2>&1 || die "docker is required"
REDIS_IMAGE=$(redis_image)
load_inputs
WORK_DIR=$(mktemp -d)
write_fixtures

if [[ "${MODE}" == "legacy" || "${MODE}" == "all" ]]; then
    run_mode legacy
fi
if [[ "${MODE}" == "deployed" || "${MODE}" == "all" ]]; then
    run_mode deployed
fi

cleanup
CONTAINERS=()
VOLUMES=()
check_eq "no harness containers remain" "" "$(docker ps -aq --filter "label=${RUN_LABEL}")"
check_eq "no harness volumes remain" "" "$(docker volume ls -q --filter "label=${RUN_LABEL}")"

printf '\nPassed: %d  Failed: %d\n' "${PASSED}" "${FAILED}"
(( FAILED == 0 ))
