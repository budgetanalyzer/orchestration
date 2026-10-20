#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
FIXTURE_REPO="$FIXTURE_DIR/repo"
MOCK_BIN="$FIXTURE_DIR/bin"
DOCKER_LOG="$FIXTURE_DIR/docker.log"
KUBECTL_LOG="$FIXTURE_DIR/kubectl.log"
KIND_LOG="$FIXTURE_DIR/kind.log"
mkdir -p "$FIXTURE_REPO/scripts/bootstrap" "$FIXTURE_REPO/scripts/lib" "$MOCK_BIN"
cp "$REPO_DIR/scripts/bootstrap/check-local-runtime.sh" \
    "$FIXTURE_REPO/scripts/bootstrap/"
cp "$REPO_DIR/scripts/lib/local-kubernetes-target.sh" \
    "$FIXTURE_REPO/scripts/lib/"
touch "$DOCKER_LOG" "$KUBECTL_LOG" "$KIND_LOG"
export DOCKER_LOG KUBECTL_LOG KIND_LOG
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat > "$MOCK_BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_LOG:?}"
case "${1:-}" in
    context)
        case "${2:-}" in
            show)
                printf '%s\n' "${FIXTURE_DOCKER_CONTEXT:-default}"
                ;;
            inspect)
                printf '%s\n' "${FIXTURE_CONTEXT_ENDPOINT:-unix:///var/run/docker.sock}"
                ;;
            *) exit 1 ;;
        esac
        ;;
    info)
        [[ "${FIXTURE_DOCKER_REACHABLE:-true}" == true ]]
        ;;
    *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KUBECTL_LOG:?}"
case "$*" in
    "config current-context") printf '%s\n' "${FIXTURE_CONTEXT:-kind-kind}" ;;
    "config view --minify -o jsonpath={.contexts[0].context.cluster}")
        printf '%s' "${FIXTURE_CLUSTER:-kind-kind}"
        ;;
    "config view --minify -o jsonpath={.clusters[0].cluster.server}")
        printf '%s' "${FIXTURE_API_SERVER:-https://127.0.0.1:6443}"
        ;;
    "config view --minify -o jsonpath={.clusters[0].cluster.proxy-url}") ;;
    "get node kind-control-plane -o jsonpath={.status.conditions[?(@.type==\"Ready\")].status}")
        printf '%s' "${FIXTURE_NODE_READY:-True}"
        ;;
    *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/kind" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KIND_LOG:?}"
[[ "$*" == "get clusters" ]] || exit 1
if [[ "${FIXTURE_KIND_PRESENT:-true}" == true ]]; then
    printf '%s\n' kind
fi
EOF

chmod 0755 "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh" \
    "$MOCK_BIN/docker" "$MOCK_BIN/kubectl" "$MOCK_BIN/kind"

pass_count=0

pass() {
    printf 'PASS: %s\n' "$1"
    ((pass_count += 1))
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

run_runtime() {
    env -u DOCKER_HOST -u DOCKER_CONTEXT \
        PATH="$MOCK_BIN:$PATH" \
        "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"
}

expect_failure() {
    local description="$1"
    local expected_text="$2"
    shift 2

    if "$@" >"$FIXTURE_DIR/failure.out" 2>&1; then
        fail "$description unexpectedly passed"
    fi
    grep -Fq "$expected_text" "$FIXTURE_DIR/failure.out" \
        || fail "$description did not report '$expected_text'"
    pass "$description fails closed"
}

run_runtime >"$FIXTURE_DIR/pass.out"
grep -Fq 'local Docker and exact Kind target verified' "$FIXTURE_DIR/pass.out" \
    || fail "valid local runtime did not report success"
grep -Fxq 'context show' "$DOCKER_LOG" \
    || fail "current Docker context was not selected"
grep -Fxq 'info' "$DOCKER_LOG" \
    || fail "selected Docker daemon reachability was not checked"
pass "current local Unix-socket context and exact Kind target pass"

: > "$DOCKER_LOG"
: > "$KUBECTL_LOG"
: > "$KIND_LOG"
env -u DOCKER_CONTEXT PATH="$MOCK_BIN:$PATH" \
    DOCKER_HOST=unix:///run/user/1000/docker.sock \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh" >/dev/null
if grep -Fq 'context ' "$DOCKER_LOG"; then
    fail "explicit DOCKER_HOST did not select the Docker CLI endpoint directly"
fi
pass "explicit local Unix-socket DOCKER_HOST passes"

: > "$KUBECTL_LOG"
: > "$KIND_LOG"
expect_failure "remote DOCKER_HOST" "not a local Unix socket" \
    env -u DOCKER_CONTEXT PATH="$MOCK_BIN:$PATH" \
    DOCKER_HOST=tcp://192.0.2.10:2375 \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"
[[ ! -s "$KUBECTL_LOG" && ! -s "$KIND_LOG" ]] \
    || fail "remote DOCKER_HOST reached Kind target inspection"

expect_failure "remote explicit Docker context" "not a local Unix socket" \
    env -u DOCKER_HOST PATH="$MOCK_BIN:$PATH" \
    DOCKER_CONTEXT=remote FIXTURE_CONTEXT_ENDPOINT=tcp://192.0.2.10:2375 \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"

expect_failure "remote current Docker context" "not a local Unix socket" \
    env -u DOCKER_HOST -u DOCKER_CONTEXT PATH="$MOCK_BIN:$PATH" \
    FIXTURE_DOCKER_CONTEXT=remote \
    FIXTURE_CONTEXT_ENDPOINT=ssh://builder.example.invalid \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"

: > "$DOCKER_LOG"
expect_failure "conflicting Docker selectors" "must not both select" \
    env PATH="$MOCK_BIN:$PATH" \
    DOCKER_HOST=unix:///var/run/docker.sock DOCKER_CONTEXT=default \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"
[[ ! -s "$DOCKER_LOG" ]] \
    || fail "conflicting Docker selectors invoked the Docker CLI"

: > "$KUBECTL_LOG"
: > "$KIND_LOG"
expect_failure "unreachable local Docker daemon" "daemon is unreachable" \
    env -u DOCKER_HOST -u DOCKER_CONTEXT PATH="$MOCK_BIN:$PATH" \
    FIXTURE_DOCKER_REACHABLE=false \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"
[[ ! -s "$KUBECTL_LOG" && ! -s "$KIND_LOG" ]] \
    || fail "unreachable Docker daemon reached Kind target inspection"

expect_failure "absent Kind cluster" "local Kind cluster 'kind' is absent" \
    env -u DOCKER_HOST -u DOCKER_CONTEXT PATH="$MOCK_BIN:$PATH" \
    FIXTURE_KIND_PRESENT=false \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"

: > "$KIND_LOG"
expect_failure "wrong Kubernetes context" "expected 'kind-kind'" \
    env -u DOCKER_HOST -u DOCKER_CONTEXT PATH="$MOCK_BIN:$PATH" \
    FIXTURE_CONTEXT=production \
    "$FIXTURE_REPO/scripts/bootstrap/check-local-runtime.sh"
[[ ! -s "$KIND_LOG" ]] \
    || fail "wrong Kubernetes context reached Kind cluster inspection"

setup_docker_line="$(grep -nF 'if ! assert_local_docker_endpoint; then' \
    "$REPO_DIR/setup.sh" | cut -d: -f1)"
setup_delete_line="$(grep -nE '^[[:space:]]*kind delete cluster --name kind$' \
    "$REPO_DIR/setup.sh" | cut -d: -f1)"
[[ -n "$setup_docker_line" && -n "$setup_delete_line" ]] \
    || fail "could not locate setup Docker guard and Kind deletion"
(( setup_docker_line < setup_delete_line )) \
    || fail "setup does not assert the local Docker endpoint before Kind deletion"
pass "setup checks the selected Docker transport before cluster mutation"

printf 'Local runtime fixtures passed: %s checks.\n' "$pass_count"
