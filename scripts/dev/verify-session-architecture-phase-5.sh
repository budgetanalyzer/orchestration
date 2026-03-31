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
Usage: ./scripts/dev/verify-session-architecture-phase-5.sh [options]

Verifies the Session Architecture Rethink Phase 5 contract:
- Redis ACL bootstrap uses the unified `session:*` and `oauth2:state:*` namespaces
- ext-authz is configured with `SESSION_KEY_PREFIX=session:`
- `/auth/*` and the related auth paths still route to Session Gateway
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
    section "Static Contract"

    assert_file_contains \
        "${REPO_ROOT}/kubernetes/infrastructure/redis/start-redis.sh" \
        'user session-gateway reset on >${REDIS_SESSION_GATEWAY_PASSWORD} ~session:* ~oauth2:state:* &* +@all' \
        "Redis ACL bootstrap grants session-gateway access to session:* and oauth2:state:*"
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

    assert_file_contains \
        "${REPO_ROOT}/kubernetes/services/ext-authz/deployment.yaml" \
        "- name: SESSION_KEY_PREFIX" \
        "ext-authz deployment declares SESSION_KEY_PREFIX"
    assert_file_contains \
        "${REPO_ROOT}/kubernetes/services/ext-authz/deployment.yaml" \
        'value: "session:"' \
        "ext-authz deployment sets SESSION_KEY_PREFIX=session:"

    assert_file_contains \
        "${REPO_ROOT}/kubernetes/gateway/auth-httproute.yaml" \
        "value: /auth" \
        "auth-route still includes the /auth prefix"
    assert_file_contains \
        "${REPO_ROOT}/kubernetes/gateway/auth-httproute.yaml" \
        "name: session-gateway" \
        "auth-route still targets session-gateway"
}

prepare_live_redis_context() {
    REDIS_POD="$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    REDIS_OPS_USERNAME="$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-username}' 2>/dev/null | base64 -d 2>/dev/null || true)"
    REDIS_OPS_PASSWORD="$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' 2>/dev/null | base64 -d 2>/dev/null || true)"

    if [[ -z "$REDIS_POD" || -z "$REDIS_OPS_USERNAME" || -z "$REDIS_OPS_PASSWORD" ]]; then
        fail "live Redis proof prerequisites are missing (redis pod or redis-bootstrap-credentials)"
        return 1
    fi

    pass "live Redis proof prerequisites are present"
}

run_live_checks() {
    local route_yaml ext_authz_yaml session_keys old_spring_keys old_extauthz_keys sg_acl ea_acl

    section "Live Cluster Contract"

    if require_kubectl_resource httproute auth-route default; then
        route_yaml="$(kubectl get httproute auth-route -n default -o yaml)"
        if grep -Fq 'value: /auth' <<<"$route_yaml" && grep -Fq 'name: session-gateway' <<<"$route_yaml"; then
            pass "live auth-route sends /auth traffic to session-gateway"
        else
            fail "live auth-route does not match the checked-in Session Gateway auth routing contract"
        fi
    else
        fail "httproute/auth-route is missing from the live cluster"
    fi

    if require_kubectl_resource deployment ext-authz default; then
        ext_authz_yaml="$(kubectl get deployment ext-authz -n default -o yaml)"
        if grep -Fq 'name: SESSION_KEY_PREFIX' <<<"$ext_authz_yaml" && grep -Fq 'value: session:' <<<"$ext_authz_yaml"; then
            pass "live ext-authz deployment sets SESSION_KEY_PREFIX=session:"
        else
            fail "live ext-authz deployment is missing SESSION_KEY_PREFIX=session:"
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

    if require_kubectl_resource deployment redis infrastructure; then
        assert_ready_deployment infrastructure redis
    else
        fail "deployment/redis is missing from the live cluster"
    fi

    if ! prepare_live_redis_context; then
        return
    fi

    sg_acl="$(redis_exec ACL GETUSER session-gateway 2>&1 || true)"
    if grep -Fq '~session:*' <<<"$sg_acl" && grep -Fq '~oauth2:state:*' <<<"$sg_acl" \
        && ! grep -Fq '~spring:session:*' <<<"$sg_acl" && ! grep -Fq '~extauthz:session:*' <<<"$sg_acl"; then
        pass "live session-gateway ACL matches the unified session namespace contract"
    else
        fail "live session-gateway ACL does not match the unified session namespace contract"
    fi

    ea_acl="$(redis_exec ACL GETUSER ext-authz 2>&1 || true)"
    if grep -Fq '~session:*' <<<"$ea_acl" \
        && ! grep -Fq '~spring:session:*' <<<"$ea_acl" && ! grep -Fq '~extauthz:session:*' <<<"$ea_acl"; then
        pass "live ext-authz ACL matches the unified session namespace contract"
    else
        fail "live ext-authz ACL does not match the unified session namespace contract"
    fi

    old_spring_keys="$(redis_exec KEYS 'spring:session:*' 2>&1 || true)"
    if [[ -z "$old_spring_keys" ]]; then
        pass "live Redis has no spring:session:* keys"
    else
        fail "live Redis still has spring:session:* keys"
    fi

    old_extauthz_keys="$(redis_exec KEYS 'extauthz:session:*' 2>&1 || true)"
    if [[ -z "$old_extauthz_keys" ]]; then
        pass "live Redis has no extauthz:session:* keys"
    else
        fail "live Redis still has extauthz:session:* keys"
    fi

    session_keys="$(redis_exec KEYS 'session:*' 2>&1 || true)"
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
