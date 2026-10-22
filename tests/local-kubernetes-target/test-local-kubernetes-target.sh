#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
MOCK_BIN="$FIXTURE_DIR/bin"
KUBECTL_LOG="$FIXTURE_DIR/kubectl.log"
KIND_LOG="$FIXTURE_DIR/kind.log"
DOCKER_LOG="$FIXTURE_DIR/docker.log"
mkdir -p "$MOCK_BIN"
touch "$KUBECTL_LOG" "$KIND_LOG" "$DOCKER_LOG"
export KUBECTL_LOG KIND_LOG DOCKER_LOG
unset KIND_EXPERIMENTAL_PROVIDER
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# shellcheck source=scripts/lib/local-kubernetes-target.sh
. "$REPO_DIR/scripts/lib/local-kubernetes-target.sh"

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
    "config view --minify -o jsonpath={.clusters[0].cluster.proxy-url}")
        printf '%s' "${FIXTURE_PROXY_URL:-}"
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
printf '%s\n' "$*" >> "${KIND_LOG:?}"
[[ "$*" == "get clusters" ]] || exit 1
printf '%s\n' "${FIXTURE_KIND_CLUSTER:-kind}"
EOF
cat > "$MOCK_BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_LOG:?}"
case "$*" in
    "context show") printf '%s\n' default ;;
    "context inspect default --format "*) printf '%s\n' unix:///var/run/docker.sock ;;
    info) ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/kubectl" "$MOCK_BIN/kind" "$MOCK_BIN/docker"

run_kind_fixture() {
    PATH="$MOCK_BIN:$PATH" assert_local_kind_target
}

expect_target_rejected_before_cluster_access() {
    local description="$1"
    local api_server="$2"
    local proxy_url="${3:-}"

    : > "$KUBECTL_LOG"
    : > "$KIND_LOG"
    if env PATH="$MOCK_BIN:$PATH" \
        FIXTURE_API_SERVER="$api_server" \
        FIXTURE_PROXY_URL="$proxy_url" \
        bash -c ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target" \
        >/dev/null 2>&1; then
        printf 'FAIL: %s unexpectedly passed\n' "$description" >&2
        return 1
    fi
    if grep -Fq 'get node ' "$KUBECTL_LOG" || [[ -s "$KIND_LOG" ]]; then
        printf 'FAIL: %s reached a cluster-access command\n' "$description" >&2
        return 1
    fi
    printf 'PASS: %s rejected before cluster access\n' "$description"
    ((pass_count += 1))
}

expect_pass "exact local Kind target" run_kind_fixture
expect_pass "localhost Kind target" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_API_SERVER=https://localhost:6443 \
        bash -c ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_pass "IPv6 loopback Kind target" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_API_SERVER='https://[::1]:6443' \
        bash -c ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_fail "wrong Kubernetes context" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_CONTEXT=production bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_fail "wrong referenced cluster" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_CLUSTER=production bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_fail "nonloopback Kubernetes API" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_API_SERVER=https://192.0.2.10:6443 bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"
expect_target_rejected_before_cluster_access \
    "Kubernetes API with deceptive userinfo" \
    'https://127.0.0.1:6443@outside.invalid:443'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with deceptive localhost prefix" \
    'https://localhost.outside.invalid:6443'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with path" \
    'https://127.0.0.1:6443/api'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with query" \
    'https://localhost:6443?target=outside.invalid'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with fragment" \
    'https://[::1]:6443#outside.invalid'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with alternative scheme" \
    'http://127.0.0.1:6443'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with malformed port" \
    'https://127.0.0.1:not-a-port'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with out-of-range port" \
    'https://127.0.0.1:65536'
expect_target_rejected_before_cluster_access \
    "Kubernetes API with proxy redirection" \
    'https://127.0.0.1:6443' 'https://outside.invalid:8443'
expect_fail "missing Kind control-plane node" \
    env PATH="$MOCK_BIN:$PATH" FIXTURE_NODE_PRESENT=false bash -c \
        ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_kind_target"

run_docker_endpoint_with_provider() {
    if [[ "$1" == "<unset>" ]]; then
        env -u KIND_EXPERIMENTAL_PROVIDER -u DOCKER_HOST -u DOCKER_CONTEXT \
            PATH="$MOCK_BIN:$PATH" bash -c \
            ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_docker_endpoint"
    else
        env -u DOCKER_HOST -u DOCKER_CONTEXT \
            PATH="$MOCK_BIN:$PATH" KIND_EXPERIMENTAL_PROVIDER="$1" bash -c \
            ". '$REPO_DIR/scripts/lib/local-kubernetes-target.sh'; assert_local_docker_endpoint"
    fi
}

for provider in '<unset>' '' docker; do
    : > "$DOCKER_LOG"
    expect_pass "Kind provider '$provider' with local Docker endpoint" \
        run_docker_endpoint_with_provider "$provider"
    grep -Fxq info "$DOCKER_LOG" || {
        printf "FAIL: Kind provider '%s' skipped the Docker endpoint checks\n" \
            "$provider" >&2
        exit 1
    }
done

for provider in podman nerdctl Docker 'docker ' 'docker;podman'; do
    : > "$DOCKER_LOG"
    : > "$KUBECTL_LOG"
    : > "$KIND_LOG"
    if run_docker_endpoint_with_provider "$provider" \
        >"$FIXTURE_DIR/provider.out" 2>&1; then
        printf "FAIL: Kind provider '%s' unexpectedly passed\n" "$provider" >&2
        exit 1
    fi
    grep -Fq "KIND_EXPERIMENTAL_PROVIDER='$provider' is unsupported" \
        "$FIXTURE_DIR/provider.out" || {
        printf "FAIL: Kind provider '%s' lacked a provider diagnostic\n" \
            "$provider" >&2
        exit 1
    }
    if [[ -s "$DOCKER_LOG" || -s "$KUBECTL_LOG" || -s "$KIND_LOG" ]]; then
        printf "FAIL: Kind provider '%s' reached Docker, kubectl or Kind\n" \
            "$provider" >&2
        exit 1
    fi
    printf "PASS: Kind provider '%s' rejected before Docker or Kind access\n" \
        "$provider"
    ((pass_count += 1))
done

printf 'Local Kubernetes target fixtures passed: %s checks.\n' "$pass_count"
