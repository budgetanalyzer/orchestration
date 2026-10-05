#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
MOCK_BIN="$FIXTURE_DIR/bin"
mkdir -p "$MOCK_BIN" "$FIXTURE_DIR/native-root/run" "$FIXTURE_DIR/container-root/run"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# shellcheck source=scripts/lib/local-docker-target.sh
. "$REPO_DIR/scripts/lib/local-docker-target.sh"
# shellcheck source=scripts/lib/local-kubernetes-target.sh
. "$REPO_DIR/scripts/lib/local-kubernetes-target.sh"
# shellcheck source=scripts/lib/native-guest-boundary.sh
. "$REPO_DIR/scripts/lib/native-guest-boundary.sh"

pass_count=0

expect_pass() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'PASS: %s\n' "$description"
        ((pass_count += 1))
    else
        printf 'FAIL: %s\n' "$description" >&2
        return 1
    fi
}

expect_fail() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'FAIL: %s unexpectedly passed\n' "$description" >&2
        return 1
    fi
    printf 'PASS: %s rejected\n' "$description"
    ((pass_count += 1))
}

touch "$FIXTURE_DIR/container-root/.dockerenv"
expect_pass "native process fixture" \
    assert_native_guest_process "$FIXTURE_DIR/native-root"
expect_fail "container process fixture" \
    assert_native_guest_process "$FIXTURE_DIR/container-root"

expect_fail "forwarded GitHub credential" \
    env GH_TOKEN=fixture-token bash -c \
        ". '$REPO_DIR/scripts/lib/native-guest-boundary.sh'; assert_no_forwarded_host_authority"

expect_fail "remote Docker environment" \
    env DOCKER_HOST=tcp://127.0.0.1:2375 bash -c \
        ". '$REPO_DIR/scripts/lib/local-docker-target.sh'; assert_local_docker_target"
expect_fail "Testcontainers host override" \
    env TESTCONTAINERS_HOST_OVERRIDE=192.0.2.10 bash -c \
        ". '$REPO_DIR/scripts/lib/local-docker-target.sh'; assert_local_docker_target"

cat > "$MOCK_BIN/docker" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3" in
    "context show ") printf 'default\n' ;;
    "context inspect default") printf '%s\n' "${FIXTURE_DOCKER_ENDPOINT:-unix:///var/run/docker.sock}" ;;
    "info --format {{.Name}}") hostname -s ;;
    "info --format {{.DockerRootDir}}") printf '/var/lib/docker\n' ;;
    "info  ") exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/docker"

expect_fail "non-Unix Docker endpoint" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_DOCKER_ENDPOINT=tcp://127.0.0.1:2375 \
        bash -c ". '$REPO_DIR/scripts/lib/local-docker-target.sh'; assert_local_docker_target"

cat > "$MOCK_BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "config current-context") printf '%s\n' "${FIXTURE_CONTEXT:-kind-kind}" ;;
    "config view --minify -o jsonpath={.contexts[0].context.cluster}")
        printf '%s' "${FIXTURE_CLUSTER:-kind-kind}"
        ;;
    "config view --minify -o jsonpath={.clusters[0].cluster.server}")
        printf '%s' "${FIXTURE_API_SERVER:-https://127.0.0.1:6443}"
        ;;
    "get node kind-control-plane -o jsonpath={.status.conditions[?(@.type==\"Ready\")].status}")
        [[ "${FIXTURE_NODE_PRESENT:-true}" == true ]] || exit 1
        printf '%s' "${FIXTURE_NODE_READY:-True}"
        ;;
    *) exit 1 ;;
esac
EOF
cat > "$MOCK_BIN/kind" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "get clusters" ]] || exit 1
printf '%s\n' "${FIXTURE_KIND_CLUSTER:-kind}"
EOF
chmod +x "$MOCK_BIN/kubectl" "$MOCK_BIN/kind"

run_kind_fixture() {
    PATH="$MOCK_BIN:$PATH" assert_local_kind_target
}

expect_pass "exact local Kind target" run_kind_fixture
expect_fail "wrong Kubernetes context" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_CONTEXT=production bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_fail "wrong referenced cluster" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_CLUSTER=production bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_fail "nonloopback Kubernetes API" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_API_SERVER=https://192.0.2.10:6443 bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_fail "missing Kind control-plane node" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_NODE_PRESENT=false bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"

printf 'Native guest preflight fixtures passed: %s checks.\n' "$pass_count"
