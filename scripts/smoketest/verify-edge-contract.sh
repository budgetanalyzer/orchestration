#!/bin/bash

# Cross-layer live edge contract verifier. This is the single home for tests
# that send real requests through the local HTTPS ingress and assert how the
# ingress, ext_authz, NGINX, sidecars and services behave together. Add new
# cross-layer edge checks here as new sections.
#
# A run without flags creates, updates, deletes and scales no Kubernetes
# object. It only sends ingress requests, uses kubectl get, logs and exec, and
# seeds and removes the synthetic fixture inside the Postgres and Redis pods.
# A new section must not change Kubernetes objects except behind
# --inject-failures, and every function that does must call
# require_inject_failures first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
source "${SCRIPT_DIR}/../lib/local-kubernetes-target.sh"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
source "${SCRIPT_DIR}/../lib/loadtest-common.sh"

BASE_URL="https://app.budgetanalyzer.localhost"
CURL_TIMEOUT=10
RATE_LIMIT_RETRIES=5
SEED_SCRIPT="${REPO_DIR}/scripts/loadtest/seed-loadtest-users.sh"
TEARDOWN_SCRIPT="${REPO_DIR}/scripts/loadtest/teardown-loadtest.sh"
SEEDED_USER_ID="${LOADTEST_USER_ID_PREFIX}1"
SEEDED_SESSION_ID="${LOADTEST_SESSION_ID_PREFIX}1"
SESSION_COOKIE="__Host-BA_SESSION=${SEEDED_SESSION_ID}"

# NGINX-lane traversal matrix. Each probe is
# <prefix><form><sep><form><sep><target>, repeating the traversal twice so it
# climbs from /<service>/v1/<resource>/ to the service context root. Forms
# that already end in an encoded separator take no extra slash.
BOUNDARY_NGINX_PREFIXES=(
    "/api/v1/users/"
    "/api/v1/transactions/"
    "/api/v1/currencies/"
)
BOUNDARY_NGINX_TARGETS=(
    "internal/v1/users/${SEEDED_USER_ID}/authorization"
    "actuator/prometheus"
)
BOUNDARY_TRAVERSAL_FORMS=(
    "..%3b"
    "..%3B"
    "%2e%2e%3b"
    "..;"
    "%2e%2e"
    "..%2f"
    "..%5c"
    "%252e%252e%252f"
    "%2e%2e;"
)

# Semicolon matrix. The ingress path-hardening filter must deny every form
# before NGINX or Session Gateway sees the request. A literal ";" directly
# after a "." or ".." segment is handled separately: HCM normalize_path
# resolves that segment and drops the ";" before any filter runs.
SEMICOLON_FORMS=(";" "%3b" "%3B" "%253b" "%253B" "%25253b" "%25253B")
INGRESS_NAMESPACE="istio-ingress"
INGRESS_SELECTOR="gateway.networking.k8s.io/gateway-name=istio-ingress-gateway"
INGRESS_WORKLOAD="istio-ingress-gateway-istio"
PATH_HARDENING_FILTER="envoy.filters.http.rbac.ingress_path_hardening"
RBAC_DENIED_BODY="RBAC: access denied"

# Authorization failure cases. The block policy is a temporary Admin-tier
# ClusterNetworkPolicy from the pinned Calico manifest: a namespaced
# NetworkPolicy can only add allows, so it cannot override
# allow-ext-authz-ingress-from-istio-ingress. Deny drops the packets, so the
# ingress check hangs until the provider timeout fires.
ISTIOD_VALUES_FILE="${REPO_DIR}/kubernetes/istio/istiod-values.yaml"
EXT_AUTHZ_DEPLOYMENT="ext-authz"
REDIS_NAMESPACE="infrastructure"
REDIS_STATEFULSET="redis"
BLOCK_POLICY_CRD="clusternetworkpolicies.policy.networking.k8s.io"
BLOCK_POLICY_NAME="edge-contract-block-ingress-to-ext-authz-$$"
UNAUTHORIZED_BODY='{"type":"UNAUTHORIZED","message":"Authentication required"}'
# Allowance for curl and TLS on top of the ext_authz timeout.
TIMEOUT_MARGIN_SECONDS="0.5"
RECOVERY_TIMEOUT_SECONDS=300

PASSED=0
FAILED=0
SKIPPED=0
INJECT_FAILURES=false
REPORT_FILE=""
SEEDED=false
WORK_DIR=""
POSTGRES_POD=""
REDIS_POD=""
FRONTEND_SHELL_SHA=""
SEMICOLON_PROBES=0
EXT_AUTHZ_TIMEOUT_SECONDS=""
ORIGINAL_EXT_AUTHZ_REPLICAS=""
ORIGINAL_REDIS_REPLICAS=""
EXT_AUTHZ_SCALED=false
REDIS_STOPPED=false
BLOCK_POLICY_APPLIED=false

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-edge-contract.sh [--inject-failures] [--report FILE]

Live cross-layer edge contract verifier for the local Tilt/Kind stack. Every
request goes through the real HTTPS ingress with normal TLS verification.

The default run changes no Kubernetes object. It sends requests through the
ingress, including DELETE probes and login start, reads with kubectl get, logs
and exec, and seeds and removes one synthetic user and session in Postgres and
Redis with seed-loadtest-users.sh and teardown-loadtest.sh. --inject-failures
adds the Authorization Failure injection cases, which scale ext-authz and
Redis, apply a temporary ClusterNetworkPolicy and may delete ext-authz pods.

Sections:
  Response Headers          One exact HSTS value on app, API, session and login;
                            forged forwarding fields cannot change redirect_uri.
  Public/Internal Boundary  Seeds one synthetic user and session, sends the
                            encoded-path traversal matrix on the NGINX lane and
                            the direct Session Gateway lane with
                            curl --path-as-is, asserts every probe is non-2xx
                            (or is exactly the public frontend shell) with no
                            internal handler output or side effect,
                            then asserts legitimate routes and login start
                            still work. The fixture is removed with
                            teardown-loadtest.sh when the section ends.
  Semicolon Rejection       Seeds the same fixture, then sends literal ";",
                            %3b, %3B, %253b, %253B, %25253b and %25253B
                            probes on the NGINX lane
                            (with the session cookie) and the direct
                            Session Gateway lane. Each must be a 403 from the
                            ingress path-hardening filter: the ingress
                            rbac.denied counter rises by the probe count, the
                            filter is the listener's only enforcing RBAC
                            filter, and neither the NGINX nor the
                            Session Gateway sidecar records a request from the
                            ingress. DELETE probes keep the side-effect check.
                            It then shows that "..;", "..;x" and ".;" segments
                            are resolved by ingress normalization with no ";"
                            reaching NGINX, and that a ";" in the query string
                            still works.
  Authorization Failure     Reads the ext_authz filter from the ingress Envoy
                            config dump and requires the istiod-values
                            timeout, status_on_error 503 and no fail-open.
                            With a seeded session, a missing or unknown
                            session must stay a JSON 401. With
                            --inject-failures it then scales ext-authz to
                            zero, blocks the ingress from ext-authz with a
                            temporary ClusterNetworkPolicy (a hang), and
                            stops Redis. Each must return an empty 503 within
                            the timeout (the hang no sooner than the timeout)
                            and never reach NGINX. Every scaled workload and
                            the temporary policy are restored, and an
                            authorized request must return 200 again before
                            the section ends. Without the flag each injection
                            case prints one [SKIP] line.

Options:
  --inject-failures  Also run the Authorization Failure injection cases.
                     They interrupt authorization and Redis-dependent
                     services; run them only on the disposable local stack
                     without concurrent traffic.
  --report FILE      Also write one tab-separated line per probe
                     (lane, method, path, HTTP status, verdict) to FILE.
  -h, --help         Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --inject-failures)
            INJECT_FAILURES=true
            shift
            ;;
        --report)
            REPORT_FILE="${2:-}"
            if [[ -z "$REPORT_FILE" ]]; then
                printf 'ERROR: --report requires a file path\n' >&2
                exit 1
            fi
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

pass()    { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail()    { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
skip()    { printf '  [SKIP] %s\n' "$1"; SKIPPED=$((SKIPPED + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }

# Backstop for every function that changes a Kubernetes object: without
# --inject-failures, stop the run before the change is attempted.
require_inject_failures() {
    [[ "$INJECT_FAILURES" == true ]] && return 0
    printf 'ERROR: %s changes Kubernetes objects and runs only with --inject-failures\n' \
        "${FUNCNAME[1]}" >&2
    FAILED=$((FAILED + 1))
    exit 1
}

cleanup() {
    local exit_status=$?
    set +e
    # Without --inject-failures, require_inject_failures stopped every change
    # before it ran, so there is nothing to restore.
    if [[ "$INJECT_FAILURES" == true ]] && [[ "$BLOCK_POLICY_APPLIED" == true || "$REDIS_STOPPED" == true \
        || "$EXT_AUTHZ_SCALED" == true || -n "$ORIGINAL_EXT_AUTHZ_REPLICAS" ]]; then
        echo ""
        echo "Restoring the authorization failure workloads..."
        if assert_local_kind_target; then
            if ! restore_authorization_failure_state; then
                echo "ERROR: authorization failure cleanup incomplete; inspect workload replicas and ${BLOCK_POLICY_NAME}" >&2
                exit_status=1
            fi
        else
            exit_status=1
        fi
    fi
    if [[ "$SEEDED" == true ]]; then
        echo ""
        echo "Removing the synthetic boundary fixture..."
        if assert_local_kind_target; then
            "$TEARDOWN_SCRIPT" >/dev/null || exit_status=1
        else
            exit_status=1
        fi
    fi
    if [[ -n "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

record() {
    [[ -n "$REPORT_FILE" ]] || return 0
    printf '%s\t%s\t%s\t%s\t%s\n' "$@" >>"$REPORT_FILE"
}

# Sends one request through the ingress and prints the HTTP status. The body
# lands in ${WORK_DIR}/body and the headers in ${WORK_DIR}/headers. A 429
# means the per-client ingress limiter answered instead of the chain under
# test, so wait for refill and retry rather than count it as a denial. The
# total time of the last attempt, in seconds, lands in ${WORK_DIR}/time.
edge_request() {
    local method="$1" path="$2"
    shift 2
    local status="000" result attempt

    for ((attempt = 1; attempt <= RATE_LIMIT_RETRIES; attempt++)); do
        : >"${WORK_DIR}/headers"
        : >"${WORK_DIR}/body"
        result=$(curl --silent --path-as-is --max-redirs 0 --max-time "$CURL_TIMEOUT" \
            -X "$method" \
            -D "${WORK_DIR}/headers" \
            -o "${WORK_DIR}/body" \
            -w '%{http_code} %{time_total}' \
            "$@" "${BASE_URL}${path}" 2>/dev/null || true)
        status="${result%% *}"
        status="${status:-000}"
        printf '%s\n' "${result#* }" >"${WORK_DIR}/time"
        [[ "$status" == "429" ]] || break
        sleep 3
    done

    printf '%s\n' "$status"
}

body_has_internal_handler_output() {
    # InternalAuthorizationResponse carries userId; Prometheus text exposition
    # starts metric families with # HELP / # TYPE.
    grep -Eq '"userId"|^# (HELP|TYPE) ' "${WORK_DIR}/body" 2>/dev/null
}

body_sha() {
    sha256sum "${WORK_DIR}/body" | cut -d' ' -f1
}

# The ingress normalizes some traversal forms (for example %2e%2e) before
# routing, so the request leaves the auth lane for the app catch-all and the
# frontend answers 200 with its HTML shell for any path. That is the public
# page every visitor gets at /, not the targeted internal surface. Accept a
# 2xx only when it is byte-identical to that shell.
response_is_frontend_shell() {
    local content_type

    content_type=$(sed -n 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//p' "${WORK_DIR}/headers" | tr -d '\r' | tail -n 1)
    [[ -n "$FRONTEND_SHELL_SHA" && "${content_type,,}" == text/html* \
        && "$(body_sha)" == "$FRONTEND_SHELL_SHA" ]]
}

seeded_session_present() {
    local exists member

    exists=$(redis_cli_exec_in_pod "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" \
        EXISTS "$(session_key_for "$SEEDED_SESSION_ID")" 2>/dev/null | tr -d '[:space:]' || true)
    member=$(redis_cli_exec_in_pod "$REDIS_POD" "$REDIS_USERNAME" "$REDIS_OPS_PASSWORD" \
        SISMEMBER "user_sessions:${SEEDED_USER_ID}" "$(session_digest_for "$SEEDED_SESSION_ID")" 2>/dev/null | tr -d '[:space:]' || true)
    [[ "$exists" == "1" && "$member" == "1" ]]
}

seeded_user_row() {
    postgres_query_in_pod "$POSTGRES_POD" permission \
        "SELECT id, idp_sub, email, display_name, status, updated_at, updated_by
         FROM users WHERE id = '${SEEDED_USER_ID}';" 2>/dev/null
}

seed_fixture() {
    assert_local_kind_target
    "$SEED_SCRIPT" --count 1 >/dev/null
    SEEDED=true
}

assert_boundary_probe() {
    local lane="$1" method="$2" path="$3"
    shift 3
    local status verdict

    status=$(edge_request "$method" "$path" "$@")

    if [[ "$status" == "000" || "$status" == "429" ]]; then
        verdict="inconclusive"
        fail "${lane} ${method} ${path} -> ${status} (no decision from the chain under test)"
    elif body_has_internal_handler_output; then
        verdict="leaked"
        fail "${lane} ${method} ${path} -> ${status} with internal handler output in the body"
    elif [[ "$status" == 2* ]] && response_is_frontend_shell; then
        verdict="frontend-shell"
        pass "${lane} ${method} ${path} -> ${status} (ingress normalized it out of the lane; public frontend shell)"
    elif [[ "$status" == 2* ]]; then
        verdict="reached"
        fail "${lane} ${method} ${path} -> ${status} (internal surface reachable)"
    else
        verdict="blocked"
        pass "${lane} ${method} ${path} -> ${status}"
    fi

    record "$lane" "$method" "$path" "$status" "$verdict"
}

assert_session_survived() {
    local path="$1"

    if seeded_session_present; then
        pass "Seeded session and user_sessions index survived DELETE ${path}"
        record "auth" "DELETE-side-effect" "$path" "-" "session-intact"
    else
        fail "DELETE ${path} removed the seeded session (internal revocation handler ran)"
        record "auth" "DELETE-side-effect" "$path" "-" "session-revoked"
        # Restore the fixture so the remaining probes still measure something.
        seed_fixture
    fi
}

traversal_path() {
    local prefix="$1" form="$2" target="$3"
    local sep="/"

    case "$form" in
        *%2f|*%2F|*%5c|*%5C|*%252f|*%252F) sep="" ;;
    esac

    printf '%s%s%s%s%s%s\n' "$prefix" "$form" "$sep" "$form" "$sep" "$target"
}

assert_legitimate_status() {
    local label="$1" expected="$2" method="$3" path="$4"
    shift 4
    local status

    status=$(edge_request "$method" "$path" "$@")
    if [[ "$status" == "$expected" ]]; then
        pass "${label}: ${method} ${path} -> ${status}"
    else
        fail "${label}: ${method} ${path} -> ${status} (expected ${expected})"
    fi
    record "legitimate" "$method" "$path" "$status" "$([[ "$status" == "$expected" ]] && echo ok || echo broken)"
}

verify_public_internal_boundary() {
    local prefix target form path user_row_before user_row_after status location
    local auth0_issuer_uri auth0_host

    section "Public/Internal Boundary"

    if [[ -f "${REPO_DIR}/${LOADTEST_POOL_FILE}" ]]; then
        fail "A load-test fixture is already active (${LOADTEST_POOL_FILE}); teardown would remove it. Finish or tear it down first."
        return
    fi

    POSTGRES_POD=$(require_postgres_pod)
    REDIS_POD=$(require_redis_pod)
    load_redis_ops_credentials

    echo "  Seeding one synthetic user and session (${SEEDED_USER_ID})..."
    seed_fixture

    if seeded_session_present; then
        pass "Seeded session ${SEEDED_SESSION_ID} is present in Redis"
    else
        fail "Seeded session ${SEEDED_SESSION_ID} is missing from Redis"
        return
    fi

    # Without a valid session ext_authz answers 401 before NGINX, and every
    # NGINX-lane probe would pass without testing anything.
    assert_legitimate_status "Seeded session passes ext_authz to currency-service" 200 \
        GET "/api/v1/currencies" --cookie "$SESSION_COOKIE"

    status=$(edge_request GET "/")
    if [[ "$status" == "200" ]] && ! body_has_internal_handler_output; then
        FRONTEND_SHELL_SHA=$(body_sha)
        pass "Captured the public frontend shell from GET / for fallback comparison"
    else
        fail "GET / returned ${status}; cannot identify the public frontend shell"
    fi

    user_row_before=$(seeded_user_row)

    echo "  NGINX lane (session cookie attached, ext_authz passes):"
    for prefix in "${BOUNDARY_NGINX_PREFIXES[@]}"; do
        for target in "${BOUNDARY_NGINX_TARGETS[@]}"; do
            for form in "${BOUNDARY_TRAVERSAL_FORMS[@]}"; do
                path=$(traversal_path "$prefix" "$form" "$target")
                assert_boundary_probe "nginx" GET "$path" --cookie "$SESSION_COOKIE"
            done
        done
    done

    user_row_after=$(seeded_user_row)
    if [[ -n "$user_row_before" && "$user_row_before" == "$user_row_after" ]]; then
        pass "Seeded permission-service user row is unchanged after the NGINX-lane probes"
    else
        fail "Seeded permission-service user row changed during the NGINX-lane probes"
    fi

    echo "  Direct Session Gateway lane:"
    for form in "${BOUNDARY_TRAVERSAL_FORMS[@]}"; do
        path=$(traversal_path "/auth/v1/" "$form" "actuator/prometheus")
        assert_boundary_probe "auth" GET "$path"
    done
    for form in "${BOUNDARY_TRAVERSAL_FORMS[@]}"; do
        path=$(traversal_path "/auth/v1/" "$form" "internal/v1/sessions/users/${SEEDED_USER_ID}")
        assert_boundary_probe "auth" DELETE "$path"
        assert_session_survived "$path"
    done

    echo "  Legitimate routes:"
    assert_legitimate_status "Session heartbeat refreshes authorization from permission-service" 200 \
        POST "/auth/v1/session" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "Session user read" 200 \
        GET "/auth/v1/user" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "transaction-service public route" 200 \
        GET "/api/v1/transactions" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "transaction-service statement formats" 200 \
        GET "/api/v1/statement-formats" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "transaction-service saved views" 200 \
        GET "/api/v1/views" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "currency-service exchange rates" 200 \
        GET "/api/v1/exchange-rates?targetCurrency=THB" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "transaction-service OpenAPI route" 200 \
        GET "/api/transaction-service/v3/api-docs" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "currency-service OpenAPI route" 200 \
        GET "/api/currency-service/v3/api-docs" --cookie "$SESSION_COOKIE"

    # The seeded USER lacks users:read, so the application answers 403. A mesh
    # RBAC denial would carry Envoy's "RBAC: access denied" body instead.
    status=$(edge_request GET "/api/v1/users" --cookie "$SESSION_COOKIE")
    if [[ "$status" == "403" ]] && ! grep -Fq 'RBAC: access denied' "${WORK_DIR}/body"; then
        pass "permission-service public route reaches the application (USER -> application 403, not mesh RBAC)"
        record "legitimate" GET "/api/v1/users" "$status" "ok"
    else
        fail "permission-service public route returned ${status} without an application-level decision"
        record "legitimate" GET "/api/v1/users" "$status" "broken"
    fi

    auth0_issuer_uri=$(kubectl get configmap session-gateway-idp-config -n default \
        -o "jsonpath={.data['AUTH0_ISSUER_URI']}" 2>/dev/null || true)
    auth0_host=$(printf '%s\n' "$auth0_issuer_uri" | sed -E 's#^https://([^/:?#]+).*$#\1#')
    status=$(edge_request GET "/oauth2/authorization/idp")
    location=$(sed -n 's/^[Ll]ocation:[[:space:]]*//p' "${WORK_DIR}/headers" | tr -d '\r' | tail -n 1)
    if [[ "$status" == "302" && -n "$auth0_host" && "$location" == "https://${auth0_host}/authorize?"* ]]; then
        pass "Login start redirects to https://${auth0_host}/authorize"
        record "legitimate" GET "/oauth2/authorization/idp" "$status" "ok"
    else
        fail "Login start returned ${status} (expected 302 to the configured IdP authorize endpoint)"
        record "legitimate" GET "/oauth2/authorization/idp" "$status" "broken"
    fi

    if seeded_session_present; then
        pass "Seeded session is still valid at the end of the section"
    else
        fail "Seeded session was removed during the section"
    fi

    assert_local_kind_target
    "$TEARDOWN_SCRIPT" >/dev/null
    SEEDED=false
    pass "Synthetic boundary fixture removed with teardown-loadtest.sh"
}

# Sum of the rbac.denied counters on every ingress gateway pod.
ingress_rbac_denied_total() {
    local pod total=0 value

    while IFS= read -r pod; do
        [[ -n "$pod" ]] || continue
        value=$(kubectl exec -n "$INGRESS_NAMESPACE" "$pod" -c istio-proxy -- \
            pilot-agent request GET stats 2>/dev/null |
            awk -F': ' '$1 ~ /^http\..*\.rbac\.denied$/ { sum += $2 } END { printf "%d", sum }')
        total=$((total + ${value:-0}))
    done < <(kubectl get pods -n "$INGRESS_NAMESPACE" -l "$INGRESS_SELECTOR" -o name)

    printf '%s\n' "$total"
}

# Prints the problem when the path-hardening filter is not the only enforcing
# RBAC filter ahead of ext_authz on every ingress pod; prints nothing otherwise.
ingress_path_hardening_filter_problem() {
    local pod

    while IFS= read -r pod; do
        [[ -n "$pod" ]] || continue
        kubectl exec -n "$INGRESS_NAMESPACE" "$pod" -c istio-proxy -- \
            pilot-agent request GET config_dump 2>/dev/null |
            python3 -I -c '
import json
import sys

pod, wanted = sys.argv[1], sys.argv[2]
chains = []
for config in json.load(sys.stdin).get("configs", []):
    for listener in config.get("dynamic_listeners", []):
        active = (listener.get("active_state") or {}).get("listener") or {}
        for chain in active.get("filter_chains", []):
            for network_filter in chain.get("filters", []):
                if network_filter.get("name") == "envoy.filters.network.http_connection_manager":
                    chains.append(network_filter["typed_config"].get("http_filters", []))
if not chains:
    print(f"{pod}: no HTTP connection manager found")
for filters in chains:
    names = [item.get("name") for item in filters]
    enforcing = [
        item.get("name")
        for item in filters
        if (item.get("typed_config") or {}).get("@type", "").endswith("rbac.v3.RBAC")
        and "rules" in item.get("typed_config", {})
    ]
    if enforcing != [wanted]:
        print(f"{pod}: enforcing RBAC filters are {enforcing}, expected only {wanted}")
    elif "envoy.filters.http.ext_authz" not in names or names.index(wanted) > names.index("envoy.filters.http.ext_authz"):
        print(f"{pod}: {wanted} is not ahead of ext_authz")
' "${pod#pod/}" "$PATH_HARDENING_FILTER"
    done < <(kubectl get pods -n "$INGRESS_NAMESPACE" -l "$INGRESS_SELECTOR" -o name)
}

# Sum of istio_requests_total from the ingress gateway, as reported by the
# destination sidecars of every pod with the given app label.
sidecar_requests_from_ingress() {
    local app="$1" pod total=0 value

    while IFS= read -r pod; do
        [[ -n "$pod" ]] || continue
        value=$(kubectl exec -n default "$pod" -c istio-proxy -- \
            pilot-agent request GET stats/prometheus 2>/dev/null |
            awk -v source="source_workload=\"${INGRESS_WORKLOAD}\"" '
                /^istio_requests_total\{/ && /reporter="destination"/ && index($0, source) { sum += $NF }
                END { printf "%d", sum }')
        total=$((total + ${value:-0}))
    done < <(kubectl get pods -n default -l "app=${app}" -o name)

    printf '%s\n' "$total"
}

nginx_logs_since() {
    kubectl logs -n default -l app=nginx-gateway -c nginx --since-time="$1" --tail=-1 2>/dev/null || true
}

assert_ingress_semicolon_denial() {
    local lane="$1" method="$2" path="$3"
    shift 3
    local status verdict

    status=$(edge_request "$method" "$path" "$@")
    if [[ "$status" == "403" ]] && [[ "$(cat "${WORK_DIR}/body" 2>/dev/null)" == "$RBAC_DENIED_BODY" ]]; then
        verdict="ingress-denied"
        pass "${lane} ${method} ${path} -> 403 ${RBAC_DENIED_BODY}"
    else
        verdict="not-denied"
        fail "${lane} ${method} ${path} -> ${status} (expected the ingress 403 ${RBAC_DENIED_BODY})"
    fi
    SEMICOLON_PROBES=$((SEMICOLON_PROBES + 1))
    record "semicolon-${lane}" "$method" "$path" "$status" "$verdict"
}

verify_semicolon_rejection() {
    local form marker start_time problem path status
    local denied_before denied_after nginx_before nginx_after gateway_before gateway_after
    local -a segments=()

    section "Semicolon Rejection"

    if [[ -f "${REPO_DIR}/${LOADTEST_POOL_FILE}" ]]; then
        fail "A load-test fixture is already active (${LOADTEST_POOL_FILE}); teardown would remove it. Finish or tear it down first."
        return
    fi

    POSTGRES_POD=$(require_postgres_pod)
    REDIS_POD=$(require_redis_pod)
    load_redis_ops_credentials

    echo "  Seeding one synthetic user and session (${SEEDED_USER_ID})..."
    seed_fixture
    if ! seeded_session_present; then
        fail "Seeded session ${SEEDED_SESSION_ID} is missing from Redis"
        return
    fi

    # Without a valid session ext_authz would answer 401 and an NGINX-lane
    # probe could not show whether the ingress filter or ext_authz decided.
    assert_legitimate_status "Seeded session passes ext_authz to currency-service" 200 \
        GET "/api/v1/currencies" --cookie "$SESSION_COOKIE"

    problem=$(ingress_path_hardening_filter_problem)
    if [[ -z "$problem" ]]; then
        pass "${PATH_HARDENING_FILTER} is the only enforcing RBAC filter and runs before ext_authz"
    else
        fail "Ingress filter chain: ${problem//$'\n'/; }"
    fi

    marker="semicolon-probe-$(date -u +%s)"
    SEMICOLON_PROBES=0
    start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    denied_before=$(ingress_rbac_denied_total)
    nginx_before=$(sidecar_requests_from_ingress nginx-gateway)
    gateway_before=$(sidecar_requests_from_ingress session-gateway)

    for form in "${SEMICOLON_FORMS[@]}"; do
        segments=("%2e%2e${form}")
        # A literal "..;" segment is resolved by normalization; see below.
        [[ "$form" == ";" ]] || segments+=("..${form}")

        assert_ingress_semicolon_denial "nginx" GET "/api/v1/transactions${form}${marker}" \
            --cookie "$SESSION_COOKIE"
        for path in "${segments[@]}"; do
            assert_ingress_semicolon_denial "nginx" GET \
                "/api/v1/users/${path}/${path}/internal/v1/users/${SEEDED_USER_ID}/authorization" \
                --cookie "$SESSION_COOKIE"
        done

        assert_ingress_semicolon_denial "auth" POST "/auth/v1/session${form}${marker}"
        for path in "${segments[@]}"; do
            assert_ingress_semicolon_denial "auth" GET "/auth/v1/${path}/${path}/actuator/prometheus"
            assert_ingress_semicolon_denial "auth" DELETE \
                "/auth/v1/${path}/${path}/internal/v1/sessions/users/${SEEDED_USER_ID}"
            assert_session_survived "/auth/v1/${path}/${path}/internal/v1/sessions/users/${SEEDED_USER_ID}"
        done
    done

    denied_after=$(ingress_rbac_denied_total)
    nginx_after=$(sidecar_requests_from_ingress nginx-gateway)
    gateway_after=$(sidecar_requests_from_ingress session-gateway)

    if (( denied_after - denied_before == SEMICOLON_PROBES )); then
        pass "Ingress rbac.denied rose by exactly ${SEMICOLON_PROBES} (one per probe)"
    else
        fail "Ingress rbac.denied rose by $((denied_after - denied_before)), expected ${SEMICOLON_PROBES}"
    fi
    if (( nginx_after == nginx_before )); then
        pass "NGINX sidecar recorded no request from the ingress during the probes"
    else
        fail "NGINX sidecar recorded $((nginx_after - nginx_before)) request(s) from the ingress during the probes"
    fi
    if (( gateway_after == gateway_before )); then
        pass "Session Gateway sidecar recorded no request from the ingress during the probes"
    else
        fail "Session Gateway sidecar recorded $((gateway_after - gateway_before)) request(s) from the ingress during the probes"
    fi
    if nginx_logs_since "$start_time" | grep -Fq "$marker"; then
        fail "NGINX logged a semicolon probe"
    else
        pass "NGINX logged no semicolon probe"
    fi

    echo "  Dot segments with ';' are resolved by ingress normalization:"
    for path in "..;" "..;x" ".;"; do
        status=$(edge_request GET "/${marker}-dot/${path}/${marker}-target")
        record "semicolon-normalized" GET "/${marker}-dot/${path}/${marker}-target" "$status" "-"
    done
    sleep 2
    if nginx_logs_since "$start_time" | grep -F "$marker" | grep -q ';'; then
        fail "A ';' from a dot segment reached NGINX"
    elif [[ "$(nginx_logs_since "$start_time" | grep -Fc "GET /${marker}-target HTTP")" -eq 2 ]] \
        && nginx_logs_since "$start_time" | grep -Fq "GET /${marker}-dot/${marker}-target HTTP"; then
        pass "'..;', '..;x' and '.;' reached NGINX as resolved paths with no ';'"
    else
        fail "NGINX did not log the resolved dot-segment paths"
    fi

    echo "  Query strings keep ';':"
    assert_legitimate_status "Query ';' on the NGINX lane" 200 \
        GET "/api/v1/exchange-rates?targetCurrency=THB&probe=a;b" --cookie "$SESSION_COOKIE"
    assert_legitimate_status "Query ';' on the Session Gateway lane" 200 \
        GET "/auth/v1/user?probe=a;b" --cookie "$SESSION_COOKIE"

    assert_local_kind_target
    "$TEARDOWN_SCRIPT" >/dev/null
    SEEDED=false
    pass "Synthetic semicolon fixture removed with teardown-loadtest.sh"
}

# Prints one "<timeout seconds> <status_on_error code> <failure_mode_allow>"
# line per distinct ext_authz filter on the ingress gateway pods.
ingress_ext_authz_settings() {
    local pod

    while IFS= read -r pod; do
        [[ -n "$pod" ]] || continue
        kubectl exec -n "$INGRESS_NAMESPACE" "$pod" -c istio-proxy -- \
            pilot-agent request GET config_dump 2>/dev/null |
            python3 -I -c '
import json
import sys

for config in json.load(sys.stdin).get("configs", []):
    for listener in config.get("dynamic_listeners", []):
        active = (listener.get("active_state") or {}).get("listener") or {}
        for chain in active.get("filter_chains", []):
            for network_filter in chain.get("filters", []):
                if network_filter.get("name") != "envoy.filters.network.http_connection_manager":
                    continue
                for item in network_filter["typed_config"].get("http_filters", []):
                    if item.get("name") != "envoy.filters.http.ext_authz":
                        continue
                    typed = item.get("typed_config", {})
                    timeout = typed.get("http_service", {}).get("server_uri", {}).get("timeout", "none")
                    status = (typed.get("status_on_error") or {}).get("code", "none")
                    print(timeout.rstrip("s") if timeout.endswith("s") else timeout, status,
                          str(typed.get("failure_mode_allow", False)).lower())
'
    done < <(kubectl get pods -n "$INGRESS_NAMESPACE" -l "$INGRESS_SELECTOR" -o name) | sort -u
}

# Sum of ext_authz checks from the ingress recorded by the ext-authz sidecars,
# optionally only those with the given response code. The ingress sends the
# check without peer metadata, so match its namespace rather than workload.
ext_authz_checks_from_ingress() {
    local code="${1:-}" pod total=0 value

    while IFS= read -r pod; do
        [[ -n "$pod" ]] || continue
        value=$(kubectl exec -n default "$pod" -c istio-proxy -- \
            pilot-agent request GET stats/prometheus 2>/dev/null |
            awk -v source="source_workload_namespace=\"${INGRESS_NAMESPACE}\"" \
                -v code="${code:+response_code=\"${code}\"}" '
                /^istio_requests_total\{/ && /reporter="destination"/ && index($0, source) \
                    && (code == "" || index($0, code)) { sum += $NF }
                END { printf "%d", sum }')
        total=$((total + ${value:-0}))
    done < <(kubectl get pods -n default -l "app=${EXT_AUTHZ_DEPLOYMENT}" -o name)

    printf '%s\n' "$total"
}

response_content_type() {
    sed -n 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//p' "${WORK_DIR}/headers" | tr -d '\r' | tail -n 1
}

# True when $1 <= $2 for decimal seconds.
seconds_at_most() {
    awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 <= b + 0) }'
}

assert_missing_session_401() {
    local label="$1" path="$2"
    shift 2
    local status elapsed content_type

    status=$(edge_request GET "$path" "$@")
    elapsed=$(cat "${WORK_DIR}/time")
    content_type=$(response_content_type)
    if [[ "$status" == "401" && "${content_type,,}" == application/json* \
        && "$(cat "${WORK_DIR}/body")" == "$UNAUTHORIZED_BODY" ]]; then
        pass "${label}: GET ${path} -> 401 ${content_type} ${UNAUTHORIZED_BODY} (${elapsed}s)"
        record "authz-no-session" GET "$path" "$status" "json-401"
    else
        fail "${label}: GET ${path} -> ${status} content-type '${content_type}' (expected the JSON 401)"
        record "authz-no-session" GET "$path" "$status" "broken"
    fi
}

# An authorizer failure must be Envoy's status_on_error reply: 503 with no
# body and no content-type, answered within the timeout. A hang must also take
# at least the timeout, which shows the timeout and not a fast failure decided.
assert_authorizer_failure() {
    local case_name="$1" min_seconds="$2" path="$3"
    shift 3
    local status elapsed content_type max_seconds

    max_seconds=$(awk -v t="$EXT_AUTHZ_TIMEOUT_SECONDS" -v m="$TIMEOUT_MARGIN_SECONDS" 'BEGIN { print t + m }')
    status=$(edge_request GET "$path" "$@")
    elapsed=$(cat "${WORK_DIR}/time")
    content_type=$(response_content_type)

    if [[ "$status" != "503" ]]; then
        fail "${case_name}: GET ${path} -> ${status} (expected 503)"
    elif [[ -s "${WORK_DIR}/body" || -n "$content_type" ]]; then
        fail "${case_name}: GET ${path} -> 503 with content-type '${content_type}' and a $(wc -c <"${WORK_DIR}/body")-byte body (expected an empty 503)"
    elif ! seconds_at_most "$elapsed" "$max_seconds"; then
        fail "${case_name}: GET ${path} -> 503 after ${elapsed}s (limit ${max_seconds}s)"
    elif ! seconds_at_most "$min_seconds" "$elapsed"; then
        fail "${case_name}: GET ${path} -> 503 after ${elapsed}s, before the ${min_seconds}s timeout (not a hang)"
    else
        pass "${case_name}: GET ${path} -> empty 503 in ${elapsed}s"
        record "authz-${case_name}" GET "$path" "$status" "empty-503@${elapsed}s"
        return
    fi
    record "authz-${case_name}" GET "$path" "$status" "broken@${elapsed}s"
}

assert_nginx_not_reached() {
    local case_name="$1" before="$2" start_time="$3" marker="$4" after

    after=$(sidecar_requests_from_ingress nginx-gateway)
    if (( after == before )); then
        pass "${case_name}: NGINX sidecar recorded no request from the ingress"
    else
        fail "${case_name}: NGINX sidecar recorded $((after - before)) request(s) from the ingress"
    fi
    if nginx_logs_since "$start_time" | grep -Fq "$marker"; then
        fail "${case_name}: NGINX logged a probe"
    else
        pass "${case_name}: NGINX logged no probe"
    fi
}

apply_block_policy() {
    require_inject_failures
    assert_local_kind_target
    BLOCK_POLICY_APPLIED=true
    kubectl apply -f - >/dev/null <<EOF
apiVersion: policy.networking.k8s.io/v1alpha2
kind: ClusterNetworkPolicy
metadata:
  name: ${BLOCK_POLICY_NAME}
spec:
  tier: Admin
  priority: 0
  subject:
    pods:
      namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: default
      podSelector:
        matchLabels:
          app: ${EXT_AUTHZ_DEPLOYMENT}
  ingress:
    - name: drop-istio-ingress-checks
      action: Deny
      from:
        - pods:
            namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: ${INGRESS_NAMESPACE}
            podSelector: {}
EOF
}

scale_ext_authz() {
    require_inject_failures
    assert_local_kind_target
    kubectl scale deployment "$EXT_AUTHZ_DEPLOYMENT" -n default --replicas="$1" >/dev/null
}

# Waits for ext-authz to be Ready again. A Redis outage fails its liveness
# probe, so a container can sit in CrashLoopBackOff after Redis returns;
# deleting the pod once resets the backoff.
wait_for_ext_authz_ready() {
    local deadline=$((SECONDS + RECOVERY_TIMEOUT_SECONDS)) restarted=false ready

    while (( SECONDS < deadline )); do
        ready=$(kubectl get deployment "$EXT_AUTHZ_DEPLOYMENT" -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
        [[ "${ready:-0}" == "$ORIGINAL_EXT_AUTHZ_REPLICAS" ]] && return 0
        if [[ "$restarted" == false ]] && kubectl get pods -n default -l "app=${EXT_AUTHZ_DEPLOYMENT}" \
            -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null |
            grep -qw CrashLoopBackOff; then
            require_inject_failures
            assert_local_kind_target || return 1
            kubectl delete pods -n default -l "app=${EXT_AUTHZ_DEPLOYMENT}" --wait=false >/dev/null || return 1
            restarted=true
        fi
        sleep 3
    done
    return 1
}

# Restores every workload and policy the section changed. Safe to call from
# the EXIT trap at any point in the section.
restore_authorization_failure_state() {
    local restored=true

    require_inject_failures
    assert_local_kind_target || return 1
    if [[ "$BLOCK_POLICY_APPLIED" == true ]]; then
        if kubectl delete clusternetworkpolicy "$BLOCK_POLICY_NAME" --ignore-not-found >/dev/null; then
            BLOCK_POLICY_APPLIED=false
        else
            restored=false
        fi
    fi
    if [[ "$REDIS_STOPPED" == true ]]; then
        kubectl scale statefulset "$REDIS_STATEFULSET" -n "$REDIS_NAMESPACE" \
            --replicas="$ORIGINAL_REDIS_REPLICAS" >/dev/null || restored=false
        kubectl rollout status statefulset "$REDIS_STATEFULSET" -n "$REDIS_NAMESPACE" \
            --timeout="${RECOVERY_TIMEOUT_SECONDS}s" >/dev/null || restored=false
    fi
    if [[ "$EXT_AUTHZ_SCALED" == true ]]; then
        kubectl scale deployment "$EXT_AUTHZ_DEPLOYMENT" -n default \
            --replicas="$ORIGINAL_EXT_AUTHZ_REPLICAS" >/dev/null || restored=false
    fi
    if [[ -n "$ORIGINAL_EXT_AUTHZ_REPLICAS" ]]; then
        wait_for_ext_authz_ready || restored=false
        kubectl wait --for=condition=Available deployment --all -n default \
            --timeout="${RECOVERY_TIMEOUT_SECONDS}s" >/dev/null || restored=false
    fi
    if [[ "$restored" == true ]]; then
        REDIS_STOPPED=false
        EXT_AUTHZ_SCALED=false
        return 0
    fi
    return 1
}

# Retries an authorized request until it returns 200, so the next case starts
# from a working chain.
wait_for_authorized_200() {
    local label="$1" deadline=$((SECONDS + RECOVERY_TIMEOUT_SECONDS)) status="000"

    while (( SECONDS < deadline )); do
        status=$(edge_request GET "/api/v1/currencies" --cookie "$SESSION_COOKIE")
        if [[ "$status" == "200" ]]; then
            pass "${label}: authorized GET /api/v1/currencies -> 200"
            record "authz-recovery" GET "/api/v1/currencies" "$status" "$label"
            return 0
        fi
        sleep 2
    done
    fail "${label}: authorized GET /api/v1/currencies -> ${status} after ${RECOVERY_TIMEOUT_SECONDS}s (expected 200)"
    record "authz-recovery" GET "/api/v1/currencies" "$status" "broken"
    return 1
}

verify_authorization_failure() {
    local settings values_timeout timeout_value status_code fail_open marker start_time nginx_before
    local checks_before checks_after authorizer_503_before authorizer_503_after
    local probe_path

    section "Authorization Failure"

    if [[ -f "${REPO_DIR}/${LOADTEST_POOL_FILE}" ]]; then
        fail "A load-test fixture is already active (${LOADTEST_POOL_FILE}); teardown would remove it. Finish or tear it down first."
        return
    fi
    if [[ "$INJECT_FAILURES" == true ]] && ! kubectl get crd "$BLOCK_POLICY_CRD" >/dev/null 2>&1; then
        fail "${BLOCK_POLICY_CRD} is missing; the pinned Calico manifest installs it and the hang case needs it"
        return
    fi

    settings=$(ingress_ext_authz_settings)
    values_timeout=$(awk '
        /^    - name:[[:space:]]*ext-authz-http[[:space:]]*$/ { in_provider = 1; next }
        in_provider && /^    - / { exit }
        in_provider && /^        timeout:/ { sub(/^        timeout:[[:space:]]*/, ""); sub(/s[[:space:]]*$/, ""); print; exit }
    ' "$ISTIOD_VALUES_FILE")
    read -r timeout_value status_code fail_open <<<"$settings"
    if [[ -z "$settings" || "$settings" == *$'\n'* ]]; then
        fail "Expected one ext_authz configuration on the ingress, found: ${settings//$'\n'/; }"
        return
    elif [[ -z "$values_timeout" ]] || ! awk -v a="$timeout_value" -v b="$values_timeout" 'BEGIN { exit !(a + 0 == b + 0 && a + 0 > 0) }'; then
        fail "Ingress ext_authz timeout is ${timeout_value}s; istiod-values sets '${values_timeout}s'"
        return
    elif [[ "$status_code" != "ServiceUnavailable" || "$fail_open" != "false" ]]; then
        fail "Ingress ext_authz has status_on_error ${status_code} and failure_mode_allow ${fail_open} (expected ServiceUnavailable and false)"
        return
    fi
    EXT_AUTHZ_TIMEOUT_SECONDS="$timeout_value"
    pass "Ingress ext_authz config dump: timeout ${timeout_value}s, status_on_error ServiceUnavailable, failure_mode_allow false"

    POSTGRES_POD=$(require_postgres_pod)
    REDIS_POD=$(require_redis_pod)
    load_redis_ops_credentials

    echo "  Seeding one synthetic user and session (${SEEDED_USER_ID})..."
    seed_fixture
    if ! seeded_session_present; then
        fail "Seeded session ${SEEDED_SESSION_ID} is missing from Redis"
        return
    fi

    # Failure probes carry the seeded session so a 503 cannot be a missing
    # session answered early, and a query marker so NGINX logs would show them.
    marker="authz-failure-$(date -u +%s)"
    probe_path="/api/v1/currencies?probe=${marker}"
    assert_legitimate_status "Seeded session passes ext_authz to currency-service" 200 \
        GET "/api/v1/currencies" --cookie "$SESSION_COOKIE"

    echo "  No session:"
    start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    nginx_before=$(sidecar_requests_from_ingress nginx-gateway)
    assert_missing_session_401 "No cookie" "$probe_path"
    assert_missing_session_401 "Unknown session" "$probe_path" --cookie "__Host-BA_SESSION=${marker}-unknown"
    sleep 2
    assert_nginx_not_reached "No session" "$nginx_before" "$start_time" "$marker"

    if [[ "$INJECT_FAILURES" != true ]]; then
        skip "ext-authz scaled to zero: needs --inject-failures"
        skip "ext-authz unreachable (temporary ClusterNetworkPolicy drop): needs --inject-failures"
        skip "Redis stopped: needs --inject-failures"
        remove_authorization_failure_fixture
        return
    fi

    ORIGINAL_EXT_AUTHZ_REPLICAS=$(kubectl get deployment "$EXT_AUTHZ_DEPLOYMENT" -n default -o jsonpath='{.spec.replicas}')
    ORIGINAL_REDIS_REPLICAS=$(kubectl get statefulset "$REDIS_STATEFULSET" -n "$REDIS_NAMESPACE" -o jsonpath='{.spec.replicas}')
    if [[ ! "$ORIGINAL_EXT_AUTHZ_REPLICAS" =~ ^[1-9][0-9]*$ || ! "$ORIGINAL_REDIS_REPLICAS" =~ ^[1-9][0-9]*$ ]]; then
        fail "ext-authz (${ORIGINAL_EXT_AUTHZ_REPLICAS:-unset}) and Redis (${ORIGINAL_REDIS_REPLICAS:-unset}) must be running before the failure cases"
        ORIGINAL_EXT_AUTHZ_REPLICAS=""
        return
    fi

    echo "  ext-authz scaled to zero:"
    EXT_AUTHZ_SCALED=true
    scale_ext_authz 0
    kubectl wait --for=delete pod -n default -l "app=${EXT_AUTHZ_DEPLOYMENT}" --timeout=120s >/dev/null
    start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    nginx_before=$(sidecar_requests_from_ingress nginx-gateway)
    assert_authorizer_failure "ext-authz-zero" 0 "$probe_path" --cookie "$SESSION_COOKIE"
    assert_authorizer_failure "ext-authz-zero" 0 "$probe_path"
    sleep 2
    assert_nginx_not_reached "ext-authz scaled to zero" "$nginx_before" "$start_time" "$marker"

    # Apply the block while no ext-authz pod exists, so the ingress holds no
    # established connection that conntrack would keep admitting.
    echo "  ext-authz unreachable (temporary ClusterNetworkPolicy drop):"
    apply_block_policy
    scale_ext_authz "$ORIGINAL_EXT_AUTHZ_REPLICAS"
    kubectl rollout status deployment "$EXT_AUTHZ_DEPLOYMENT" -n default --timeout="${RECOVERY_TIMEOUT_SECONDS}s" >/dev/null
    EXT_AUTHZ_SCALED=false
    sleep 3
    start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    nginx_before=$(sidecar_requests_from_ingress nginx-gateway)
    checks_before=$(ext_authz_checks_from_ingress)
    assert_authorizer_failure "ext-authz-hang" "$EXT_AUTHZ_TIMEOUT_SECONDS" "$probe_path" --cookie "$SESSION_COOKIE"
    assert_authorizer_failure "ext-authz-hang" "$EXT_AUTHZ_TIMEOUT_SECONDS" "$probe_path"
    sleep 2
    checks_after=$(ext_authz_checks_from_ingress)
    if (( checks_after == checks_before )); then
        pass "ext-authz hang: no check reached the ext-authz sidecar (the policy dropped them)"
    else
        fail "ext-authz hang: $((checks_after - checks_before)) check(s) reached ext-authz; the block did not hold"
    fi
    assert_nginx_not_reached "ext-authz hang" "$nginx_before" "$start_time" "$marker"
    restore_authorization_failure_state || { fail "Restoring ext-authz after the hang case did not complete"; return; }
    wait_for_authorized_200 "After removing the block policy" || return

    # ext-authz answers its own JSON 503 while it is still Ready; once its
    # Redis-backed probes fail, the ingress has no ext-authz endpoint. Either
    # way the client must get the empty 503.
    echo "  Redis stopped:"
    authorizer_503_before=$(ext_authz_checks_from_ingress 503)
    require_inject_failures
    REDIS_STOPPED=true
    assert_local_kind_target
    kubectl scale statefulset "$REDIS_STATEFULSET" -n "$REDIS_NAMESPACE" --replicas=0 >/dev/null
    kubectl wait --for=delete pod -n "$REDIS_NAMESPACE" -l "app=${REDIS_STATEFULSET}" --timeout=120s >/dev/null
    start_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    nginx_before=$(sidecar_requests_from_ingress nginx-gateway)
    assert_authorizer_failure "redis-stopped" 0 "$probe_path" --cookie "$SESSION_COOKIE"
    assert_authorizer_failure "redis-stopped" 0 "$probe_path" --cookie "$SESSION_COOKIE"
    sleep 2
    authorizer_503_after=$(ext_authz_checks_from_ingress 503)
    assert_nginx_not_reached "Redis stopped" "$nginx_before" "$start_time" "$marker"
    echo "  ext-authz sidecar recorded $((authorizer_503_after - authorizer_503_before)) authorizer 503 responses during the two probes; client replies were empty"
    record "authz-redis-stopped" "ext-authz-503" "-" "$((authorizer_503_after - authorizer_503_before))" "-"
    restore_authorization_failure_state || { fail "Restoring Redis and ext-authz after the Redis case did not complete"; return; }
    wait_for_authorized_200 "After restarting Redis" || return

    remove_authorization_failure_fixture
}

remove_authorization_failure_fixture() {
    assert_local_kind_target
    "$TEARDOWN_SCRIPT" >/dev/null
    SEEDED=false
    ORIGINAL_EXT_AUTHZ_REPLICAS=""
    pass "Synthetic authorization failure fixture removed with teardown-loadtest.sh"
}

verify_response_headers() {
    section "Response Headers"
    seed_fixture
    local path method status expected headers location
    for path in / /api/v1/currencies /auth/v1/session /oauth2/authorization/idp; do
        method=GET
        expected=200
        [[ "$path" != /auth/v1/session ]] || method=POST
        [[ "$path" != /oauth2/authorization/idp ]] || expected=302
        status=$(edge_request "$method" "$path" --cookie "$SESSION_COOKIE")
        headers=$(sed -n 's/^Strict-Transport-Security:[[:space:]]*//Ip' "${WORK_DIR}/headers" | tr -d '\r')
        if [[ "$status" == "$expected" && "$headers" == 'max-age=31536000' ]]; then
            pass "${path}: ${status} with exactly one HSTS value (no subdomains or preload)"
        else
            fail "${path}: expected ${expected} and one exact HSTS value; got ${status}, ${headers:-missing}"
        fi
        record "headers" "$method" "$path" "$status" "hsts=${headers:-missing}"
    done

    # Exercise each field alone as well as together: Forwarded takes precedence
    # over X-Forwarded-* in Spring, so a combined probe alone can mask a defect.
    local forged
    for forged in 'X-Forwarded-Host: attacker.invalid' \
        'Forwarded: host=attacker.invalid;proto=http' \
        'X-Forwarded-Port: 444' 'X-Forwarded-Prefix: /evil' 'X-Forwarded-Ssl: off' all; do
        local -a probe_headers=(-H "$forged")
        if [[ "$forged" == all ]]; then
            probe_headers=(-H 'X-Forwarded-Host: attacker.invalid' \
                -H 'Forwarded: host=attacker.invalid;proto=http' \
                -H 'X-Forwarded-Port: 444' -H 'X-Forwarded-Prefix: /evil' -H 'X-Forwarded-Ssl: off')
        fi
        status=$(edge_request GET /oauth2/authorization/idp "${probe_headers[@]}")
        location=$(sed -n 's/^Location:[[:space:]]*//Ip' "${WORK_DIR}/headers" | tr -d '\r')
        if [[ "$status" == 302 ]] && python3 - "$location" <<'REDIRECT_PY'
import sys
from urllib.parse import parse_qs, urlsplit
assert parse_qs(urlsplit(sys.argv[1]).query).get("redirect_uri") == [
    "https://app.budgetanalyzer.localhost/login/oauth2/code/idp"
]
REDIRECT_PY
        then
            pass "Forged ${forged%%:*}: login redirect_uri uses the real HTTPS host"
        else
            fail "Forged ${forged%%:*}: login redirect_uri changed or login failed (${status})"
        fi
    done
    assert_local_kind_target
    "$TEARDOWN_SCRIPT" >/dev/null
    SEEDED=false
}

main() {
    local command_name

    for command_name in curl kubectl kind grep sed awk python3; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'ERROR: required command not found: %s\n' "$command_name" >&2
            exit 1
        fi
    done

    assert_local_kind_target
    WORK_DIR=$(mktemp -d)

    if [[ -n "$REPORT_FILE" ]]; then
        : >"$REPORT_FILE"
    fi

    verify_public_internal_boundary
    verify_semicolon_rejection
    verify_authorization_failure
    verify_response_headers

    printf '\n=== Summary ===\n'
    printf '  Passed: %d\n  Failed: %d\n  Skipped: %d\n' "$PASSED" "$FAILED" "$SKIPPED"
    if (( SKIPPED > 0 )); then
        printf '  Skipped cases need --inject-failures; this run is not full coverage.\n'
    fi
    if (( FAILED > 0 )); then
        exit 1
    fi
    printf 'Edge contract verification passed.\n'
}

main "$@"
