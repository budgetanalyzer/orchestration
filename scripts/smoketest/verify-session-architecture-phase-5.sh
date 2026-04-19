#!/usr/bin/env bash
# Verify Session Architecture Rethink Phase 5 in the orchestration repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

STATIC_ONLY=false
REQUIRE_LIVE_SESSION=false
PASSED=0
FAILED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-session-architecture-phase-5.sh [options]

Verifies the Session Architecture Rethink Phase 5 contract:
- Redis ACL bootstrap uses the unified `session:*` and `oauth2:state:*` namespaces
- Session Gateway and ext-authz share the `SESSION_KEY_PREFIX=session:` and `SESSION_COOKIE_NAME=BA_SESSION` defaults
- ext-authz deployment explicitly sets `SESSION_COOKIE_NAME=BA_SESSION` and does not override `SESSION_KEY_PREFIX`
- `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, and `/logout` still route only to Session Gateway, with no standalone `/user` match
- Live Redis ACLs and keyspace hygiene match the checked-in contract

Options:
  --static-only           Run only repository-level checks; skip live cluster checks.
  --require-live-session  Require at least one live `session:*` key in Redis.
  -h, --help              Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --static-only)
            STATIC_ONLY=true
            ;;
        --require-live-session)
            REQUIRE_LIVE_SESSION=true
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
    shift
done

section() { printf '\n=== %s ===\n' "$1"; }
info() { printf '  [INFO] %s\n' "$1"; }
pass() { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

require_host_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if grep -Fq -- "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label"
    fi
}

assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if grep -Fq -- "$pattern" "$file"; then
        fail "$label"
    else
        pass "$label"
    fi
}

assert_file_exists() {
    local file="$1"
    local label="$2"

    if [[ -f "$file" ]]; then
        pass "$label"
    else
        fail "$label"
    fi
}

assert_value_equals() {
    local actual="$1"
    local expected="$2"
    local label="$3"

    if [[ -z "$actual" ]]; then
        fail "${label} (value missing)"
    elif [[ "$actual" == "$expected" ]]; then
        pass "$label"
    else
        fail "${label} (found '${actual}', want '${expected}')"
    fi
}

assert_values_match() {
    local left_value="$1"
    local right_value="$2"
    local label="$3"

    if [[ -z "$left_value" || -z "$right_value" ]]; then
        fail "${label} (one side is missing)"
    elif [[ "$left_value" == "$right_value" ]]; then
        pass "${label} (${left_value})"
    else
        fail "${label} (${left_value} != ${right_value})"
    fi
}

extract_session_gateway_key_prefix_default() {
    local file="$1"

    sed -nE 's/^[[:space:]]*key-prefix:[[:space:]]*\$\{SESSION_KEY_PREFIX:([^}]*)\}[[:space:]]*$/\1/p' "$file" | head -n 1
}

extract_session_gateway_cookie_name_default_from_yaml() {
    local file="$1"

    awk '
        function indent_of(line,    match_pos) {
            match(line, /[^ ]/)
            match_pos = RSTART
            return match_pos ? match_pos - 1 : length(line)
        }

        BEGIN {
            in_session = 0
            in_cookie = 0
            session_indent = -1
            cookie_indent = -1
        }

        /^[[:space:]]*session:[[:space:]]*$/ {
            in_session = 1
            in_cookie = 0
            session_indent = indent_of($0)
            next
        }

        in_session {
            current_indent = indent_of($0)
            if ($0 !~ /^[[:space:]]*$/ && current_indent <= session_indent) {
                in_session = 0
                in_cookie = 0
            }
        }

        !in_session { next }

        /^[[:space:]]*cookie:[[:space:]]*$/ {
            in_cookie = 1
            cookie_indent = indent_of($0)
            next
        }

        in_cookie {
            current_indent = indent_of($0)
            if ($0 !~ /^[[:space:]]*$/ && current_indent <= cookie_indent) {
                in_cookie = 0
            }
        }

        in_cookie && /^[[:space:]]*name:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]*name:[[:space:]]*/, "", value)
            sub(/[[:space:]]+#.*$/, "", value)
            gsub(/"/, "", value)
            if (value ~ /^\$\{SESSION_COOKIE_NAME:.*\}$/) {
                sub(/^\$\{SESSION_COOKIE_NAME:/, "", value)
                sub(/\}$/, "", value)
            }
            print value
            exit
        }
    ' "$file"
}

extract_ext_authz_session_key_prefix_default() {
    local file="$1"

    sed -nE 's/.*SessionKeyPrefix:[[:space:]]*envOrDefault\("SESSION_KEY_PREFIX", "([^"]+)"\).*/\1/p' "$file" | head -n 1
}

extract_ext_authz_session_cookie_name_default() {
    local file="$1"

    sed -nE 's/.*SessionCookieName:[[:space:]]*envOrDefault\("SESSION_COOKIE_NAME", "([^"]+)"\).*/\1/p' "$file" | head -n 1
}

extract_named_env_value_from_yaml() {
    local env_name="$1"

    awk -v target="$env_name" '
        BEGIN {
            current_name = ""
        }

        /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            current_name = $0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", current_name)
            gsub(/"/, "", current_name)
            next
        }

        current_name == target && /^[[:space:]]*value:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]*value:[[:space:]]*/, "", value)
            gsub(/"/, "", value)
            print value
            exit
        }
    '
}

capture_command_output() {
    local __resultvar="$1"
    shift
    local output

    if ! output="$("$@" 2>&1)"; then
        printf -v "$__resultvar" '%s' "$output"
        return 1
    fi

    printf -v "$__resultvar" '%s' "$output"
    return 0
}

parse_auth_route_rules() {
    local route_yaml="$1"

    awk '
        function indent_of(line,    match_pos) {
            match(line, /[^ ]/)
            match_pos = RSTART
            return match_pos ? match_pos - 1 : length(line)
        }

        BEGIN {
            in_rules = 0
            rules_indent = -1
            current_rule = 0
            path_indent = -1
            backend_refs_indent = -1
            backend_ref_item_indent = -1
            current_path_type = ""
        }

        /^[[:space:]]*rules:[[:space:]]*$/ {
            in_rules = 1
            rules_indent = indent_of($0)
            next
        }

        in_rules {
            current_indent = indent_of($0)
            if ($0 !~ /^[[:space:]]*$/ \
                && (current_indent < rules_indent \
                || (current_indent == rules_indent && $0 !~ /^[[:space:]]*-/))) {
                in_rules = 0
                path_indent = -1
                backend_refs_indent = -1
                backend_ref_item_indent = -1
                current_path_type = ""
            }
        }

        !in_rules { next }

        /^[[:space:]]*-[[:space:]]*(matches|backendRefs|filters):[[:space:]]*$/ {
            current_rule++
            path_indent = -1
            backend_refs_indent = -1
            backend_ref_item_indent = -1
            current_path_type = ""
        }

        path_indent >= 0 {
            current_indent = indent_of($0)
            if ($0 !~ /^[[:space:]]*$/ && current_indent <= path_indent) {
                path_indent = -1
                current_path_type = ""
            }
        }

        backend_refs_indent >= 0 {
            current_indent = indent_of($0)
            if ($0 !~ /^[[:space:]]*$/ \
                && (current_indent < backend_refs_indent \
                || (current_indent == backend_refs_indent && $0 !~ /^[[:space:]]*-/) \
                || (backend_ref_item_indent >= 0 && current_indent <= backend_ref_item_indent && $0 !~ /^[[:space:]]*-/))) {
                backend_refs_indent = -1
                backend_ref_item_indent = -1
            }
        }

        /^[[:space:]]*-[[:space:]]*path:[[:space:]]*$/ {
            path_indent = indent_of($0)
            current_path_type = ""
            next
        }

        path_indent >= 0 && /^[[:space:]]*type:[[:space:]]*/ {
            current_path_type = $0
            sub(/^[[:space:]]*type:[[:space:]]*/, "", current_path_type)
            gsub(/"/, "", current_path_type)
            next
        }

        path_indent >= 0 && current_path_type != "" && /^[[:space:]]*value:[[:space:]]*/ {
            path_value = $0
            sub(/^[[:space:]]*value:[[:space:]]*/, "", path_value)
            gsub(/"/, "", path_value)
            print "PATH\t" current_rule "\t" current_path_type "\t" path_value
            next
        }

        /^[[:space:]]*(-[[:space:]]*)?backendRefs:[[:space:]]*$/ {
            backend_refs_indent = indent_of($0)
            backend_ref_item_indent = -1
            next
        }

        backend_refs_indent >= 0 && /^[[:space:]]*-[[:space:]]*/ {
            backend_ref_item_indent = indent_of($0)
        }

        backend_refs_indent >= 0 && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            backend_name = $0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", backend_name)
            gsub(/"/, "", backend_name)
            print "BACKEND\t" current_rule "\t" backend_name
            next
        }

        backend_ref_item_indent >= 0 && indent_of($0) > backend_ref_item_indent && /^[[:space:]]*name:[[:space:]]*/ {
            backend_name = $0
            sub(/^[[:space:]]*name:[[:space:]]*/, "", backend_name)
            gsub(/"/, "", backend_name)
            print "BACKEND\t" current_rule "\t" backend_name
        }
    ' <<<"$route_yaml"
}

rule_targets_only_session_gateway() {
    local backend_lines="$1"
    local backend_count=0
    local backend_name

    while IFS= read -r backend_name; do
        [[ -z "$backend_name" ]] && continue
        backend_count=$((backend_count + 1))
        if [[ "$backend_name" != "session-gateway" ]]; then
            return 1
        fi
    done <<<"$backend_lines"

    [[ "$backend_count" -eq 1 ]]
}

assert_auth_route_contract_yaml() {
    local route_yaml="$1"
    local scope="$2"
    local parsed kind rule type value key expected_label
    local -A rule_backends=()
    local -A rule_paths=()
    local -A expected_paths=(
        ["PathPrefix|/auth"]="/auth/*"
        ["PathPrefix|/oauth2"]="/oauth2/*"
        ["PathPrefix|/login/oauth2"]="/login/oauth2/*"
        ["PathPrefix|/logout"]="/logout"
    )
    local found bad_backend

    parsed="$(parse_auth_route_rules "$route_yaml")"

    while IFS=$'\t' read -r kind rule type value; do
        [[ -z "$kind" ]] && continue

        if [[ "$kind" == "BACKEND" ]]; then
            rule_backends["$rule"]+="${type}"$'\n'
        elif [[ "$kind" == "PATH" ]]; then
            key="${type}|${value}"
            if [[ -n "${expected_paths[$key]:-}" ]]; then
                rule_paths["$rule"]+="${key}"$'\n'
            fi
        fi
    done <<<"$parsed"

    if awk -F '\t' '$1 == "PATH" && $3 == "Exact" && $4 == "/user" { found = 1 } END { exit(found ? 0 : 1) }' <<<"$parsed"; then
        fail "${scope} still exposes a standalone /user -> session-gateway contract"
    else
        pass "${scope} no longer exposes a standalone /user auth-route match"
    fi

    for key in "PathPrefix|/auth" "PathPrefix|/oauth2" "PathPrefix|/login/oauth2" "PathPrefix|/logout"; do
        expected_label="${expected_paths[$key]}"
        found=false
        bad_backend=false

        for rule in "${!rule_paths[@]}"; do
            if grep -Fxq -- "$key" <<<"${rule_paths[$rule]}"; then
                found=true
                if rule_targets_only_session_gateway "${rule_backends[$rule]:-}"; then
                    :
                else
                    bad_backend=true
                fi
            fi
        done

        if [[ "$bad_backend" == true ]]; then
            fail "${scope} routes ${expected_label} to a backend other than session-gateway"
        elif [[ "$found" == true ]]; then
            pass "${scope} routes ${expected_label} only to session-gateway"
        else
            fail "${scope} is missing the ${expected_label} -> session-gateway contract"
        fi
    done
}

require_kubectl_resource() {
    local kind="$1"
    local name="$2"
    local namespace="$3"

    kubectl get "$kind" "$name" -n "$namespace" >/dev/null 2>&1
}

assert_ready_deployment() {
    local namespace="$1"
    local name="$2"
    local ready

    ready="$(kubectl get deployment "$name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    if [[ -n "$ready" && "$ready" != "0" ]]; then
        pass "deployment/${name} is Ready in ${namespace}"
    else
        fail "deployment/${name} is not Ready in ${namespace}"
    fi
}

assert_ready_statefulset() {
    local namespace="$1"
    local name="$2"
    local ready
    local replicas

    ready="$(kubectl get statefulset "$name" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    replicas="$(kubectl get statefulset "$name" -n "$namespace" -o jsonpath='{.status.replicas}' 2>/dev/null || true)"
    if [[ -n "$ready" && -n "$replicas" && "$ready" == "$replicas" && "$ready" != "0" ]]; then
        pass "statefulset/${name} is Ready in ${namespace}"
    else
        fail "statefulset/${name} is not Ready in ${namespace}"
    fi
}

# shellcheck disable=SC2317,SC2329 # Invoked indirectly through capture_command_output.
redis_exec() {
    kubectl exec -n infrastructure "$REDIS_POD" -- \
        redis-cli \
        --tls \
        --cacert /tls-ca/ca.crt \
        --user "$REDIS_OPS_USERNAME" \
        --pass "$REDIS_OPS_PASSWORD" \
        --no-auth-warning \
        "$@"
}

REDIS_POD=""
REDIS_OPS_USERNAME=""
REDIS_OPS_PASSWORD=""

run_static_checks() {
    local route_yaml
    local ext_authz_config_file ext_authz_deployment_file session_gateway_application_file session_gateway_cookie_helper_file
    local session_gateway_key_prefix_default ext_authz_key_prefix_default
    local session_gateway_cookie_name_yaml_default ext_authz_deployment_cookie_name
    local ext_authz_cookie_name_default

    section "Static Contract"

    ext_authz_config_file="${REPO_ROOT}/ext-authz/config.go"
    ext_authz_deployment_file="${REPO_ROOT}/kubernetes/services/ext-authz/deployment.yaml"
    session_gateway_application_file="${REPO_ROOT}/../session-gateway/src/main/resources/application.yml"
    session_gateway_cookie_helper_file="${REPO_ROOT}/../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/session/SessionCookieHelper.java"

    # shellcheck disable=SC2016 # Match the literal checked-in Redis bootstrap template.
    assert_file_contains \
        "${REPO_ROOT}/kubernetes/infrastructure/redis/start-redis.sh" \
        'user session-gateway reset on >${REDIS_SESSION_GATEWAY_PASSWORD} ~session:* ~user_sessions:* ~oauth2:state:* &* +@all' \
        "Redis ACL bootstrap grants session-gateway access to session:* and oauth2:state:*"
    # shellcheck disable=SC2016 # Match the literal checked-in Redis bootstrap template.
    assert_file_contains \
        "${REPO_ROOT}/kubernetes/infrastructure/redis/start-redis.sh" \
        'user ext-authz reset on >${REDIS_EXT_AUTHZ_PASSWORD} ~session:* +hgetall +ping +auth +hello +info' \
        "Redis ACL bootstrap restricts ext-authz to read-only session:* access"
    assert_file_not_contains \
        "${REPO_ROOT}/kubernetes/infrastructure/redis/start-redis.sh" \
        "~spring:session:*" \
        "Redis ACL bootstrap no longer references spring:session:*"
    assert_file_not_contains \
        "${REPO_ROOT}/kubernetes/infrastructure/redis/start-redis.sh" \
        "~extauthz:session:*" \
        "Redis ACL bootstrap no longer references extauthz:session:*"

    assert_file_exists \
        "$session_gateway_application_file" \
        "Session Gateway application.yml is available for the shared session contract check"
    assert_file_exists \
        "$session_gateway_cookie_helper_file" \
        "Session Gateway SessionCookieHelper is available for the shared session contract check"
    assert_file_exists \
        "$ext_authz_config_file" \
        "ext-authz config.go is available for the shared session contract check"

    session_gateway_key_prefix_default="$(extract_session_gateway_key_prefix_default "$session_gateway_application_file")"
    ext_authz_key_prefix_default="$(extract_ext_authz_session_key_prefix_default "$ext_authz_config_file")"
    session_gateway_cookie_name_yaml_default="$(extract_session_gateway_cookie_name_default_from_yaml "$session_gateway_application_file")"
    ext_authz_cookie_name_default="$(extract_ext_authz_session_cookie_name_default "$ext_authz_config_file")"
    ext_authz_deployment_cookie_name="$(extract_named_env_value_from_yaml "SESSION_COOKIE_NAME" < "$ext_authz_deployment_file")"

    assert_value_equals \
        "$session_gateway_key_prefix_default" \
        "session:" \
        "Session Gateway default is SESSION_KEY_PREFIX=session:"
    assert_value_equals \
        "$ext_authz_key_prefix_default" \
        "session:" \
        "ext-authz default is SESSION_KEY_PREFIX=session:"
    assert_values_match \
        "$session_gateway_key_prefix_default" \
        "$ext_authz_key_prefix_default" \
        "Session Gateway and ext-authz share the SESSION_KEY_PREFIX default"

    assert_value_equals \
        "$session_gateway_cookie_name_yaml_default" \
        "BA_SESSION" \
        "Session Gateway application.yml default is session.cookie.name=BA_SESSION"
    assert_file_contains \
        "$session_gateway_cookie_helper_file" \
        'this.cookieName = cookieProperties.name();' \
        "Session Gateway SessionCookieHelper reads the cookie name from SessionProperties"
    assert_value_equals \
        "$ext_authz_cookie_name_default" \
        "BA_SESSION" \
        "ext-authz default is SESSION_COOKIE_NAME=BA_SESSION"
    assert_values_match \
        "$session_gateway_cookie_name_yaml_default" \
        "$ext_authz_cookie_name_default" \
        "Session Gateway and ext-authz share the session cookie-name default"
    assert_value_equals \
        "$ext_authz_deployment_cookie_name" \
        "BA_SESSION" \
        "ext-authz deployment explicitly sets SESSION_COOKIE_NAME=BA_SESSION"

    assert_file_not_contains \
        "$ext_authz_deployment_file" \
        "- name: SESSION_KEY_PREFIX" \
        "ext-authz deployment does not override SESSION_KEY_PREFIX"

    route_yaml="$(<"${REPO_ROOT}/kubernetes/gateway/auth-httproute.yaml")"
    assert_auth_route_contract_yaml \
        "$route_yaml" \
        "checked-in auth-route"
}

prepare_live_redis_context() {
    REDIS_POD="$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    REDIS_OPS_USERNAME="redis-ops"
    REDIS_OPS_PASSWORD="$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' 2>/dev/null | base64 -d 2>/dev/null || true)"

    if [[ -z "$REDIS_POD" || -z "$REDIS_OPS_USERNAME" || -z "$REDIS_OPS_PASSWORD" ]]; then
        fail "live Redis proof prerequisites are missing (redis pod or redis-bootstrap-credentials)"
        return 1
    fi

    pass "live Redis proof prerequisites are present"
}

run_live_checks() {
    local route_yaml ext_authz_yaml ext_authz_deployment_cookie_name session_keys old_spring_keys old_extauthz_keys sg_acl ea_acl

    section "Live Cluster Contract"

    if require_kubectl_resource httproute auth-route default; then
        route_yaml="$(kubectl get httproute auth-route -n default -o yaml)"
        assert_auth_route_contract_yaml \
            "$route_yaml" \
            "live auth-route"
    else
        fail "httproute/auth-route is missing from the live cluster"
    fi

    if require_kubectl_resource deployment ext-authz default; then
        ext_authz_yaml="$(kubectl get deployment ext-authz -n default -o yaml)"
        ext_authz_deployment_cookie_name="$(extract_named_env_value_from_yaml "SESSION_COOKIE_NAME" <<<"$ext_authz_yaml")"
        assert_value_equals \
            "$ext_authz_deployment_cookie_name" \
            "BA_SESSION" \
            "live ext-authz deployment explicitly sets SESSION_COOKIE_NAME=BA_SESSION"
        if grep -Fq 'name: SESSION_KEY_PREFIX' <<<"$ext_authz_yaml"; then
            fail "live ext-authz deployment still overrides SESSION_KEY_PREFIX"
        else
            pass "live ext-authz deployment relies on the baked-in SESSION_KEY_PREFIX=session: default"
        fi
        assert_ready_deployment default ext-authz
    else
        fail "deployment/ext-authz is missing from the live cluster"
    fi

    if require_kubectl_resource deployment session-gateway default; then
        assert_ready_deployment default session-gateway
    else
        fail "deployment/session-gateway is missing from the live cluster"
    fi

    if require_kubectl_resource statefulset redis infrastructure; then
        assert_ready_statefulset infrastructure redis
    else
        fail "statefulset/redis is missing from the live cluster"
    fi

    if ! prepare_live_redis_context; then
        return
    fi

    if capture_command_output sg_acl redis_exec ACL GETUSER session-gateway; then
        if grep -Fq '~session:*' <<<"$sg_acl" && grep -Fq '~oauth2:state:*' <<<"$sg_acl" \
            && ! grep -Fq '~spring:session:*' <<<"$sg_acl" && ! grep -Fq '~extauthz:session:*' <<<"$sg_acl"; then
            pass "live session-gateway ACL matches the unified session namespace contract"
        else
            fail "live session-gateway ACL does not match the unified session namespace contract"
        fi
    else
        fail "live session-gateway ACL query failed"
    fi

    if capture_command_output ea_acl redis_exec ACL GETUSER ext-authz; then
        if grep -Fq '~session:*' <<<"$ea_acl" \
            && ! grep -Fq '~spring:session:*' <<<"$ea_acl" && ! grep -Fq '~extauthz:session:*' <<<"$ea_acl"; then
            pass "live ext-authz ACL matches the unified session namespace contract"
        else
            fail "live ext-authz ACL does not match the unified session namespace contract"
        fi
    else
        fail "live ext-authz ACL query failed"
    fi

    if capture_command_output old_spring_keys redis_exec KEYS 'spring:session:*'; then
        if [[ -z "$old_spring_keys" ]]; then
            pass "live Redis has no spring:session:* keys"
        else
            fail "live Redis still has spring:session:* keys"
        fi
    else
        fail "live Redis spring:session:* query failed"
    fi

    if capture_command_output old_extauthz_keys redis_exec KEYS 'extauthz:session:*'; then
        if [[ -z "$old_extauthz_keys" ]]; then
            pass "live Redis has no extauthz:session:* keys"
        else
            fail "live Redis still has extauthz:session:* keys"
        fi
    else
        fail "live Redis extauthz:session:* query failed"
    fi

    if capture_command_output session_keys redis_exec KEYS 'session:*'; then
        if [[ "$REQUIRE_LIVE_SESSION" == true ]]; then
            if [[ -n "$session_keys" ]]; then
                pass "live Redis has at least one session:* key"
            else
                fail "live Redis has no session:* keys; create a session first and rerun with --require-live-session"
            fi
        else
            pass "live Redis session:* namespace query succeeded"
            if [[ -n "$session_keys" ]]; then
                info "Observed live session:* keys"
            else
                info "No live session:* keys observed; use --require-live-session after a login if you want that stronger proof"
            fi
        fi
    else
        fail "live Redis session:* query failed"
    fi
}

main() {
    require_host_command kubectl
    run_static_checks
    if [[ "$STATIC_ONLY" == false ]]; then
        run_live_checks
    else
        info "Skipping live cluster checks (--static-only)"
    fi

    echo ""
    echo "=============================================="
    echo "  ${PASSED} passed"
    if [[ "$FAILED" -eq 0 ]]; then
        echo "  0 failed"
        exit 0
    fi

    echo "  ${FAILED} failed"
    exit 1
}

main "$@"
