#!/usr/bin/env bash

# Offline fixtures for check-tilt-prerequisites.sh local-target gating. Docker,
# Kind and kubectl are command stubs; no real cluster or daemon is contacted.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
FIXTURE_REPO="$FIXTURE_DIR/orchestration"
MOCK_BIN="$FIXTURE_DIR/bin"
DOCKER_LOG="$FIXTURE_DIR/docker.log"
KUBECTL_LOG="$FIXTURE_DIR/kubectl.log"
KIND_LOG="$FIXTURE_DIR/kind.log"
mkdir -p "$FIXTURE_REPO/scripts/bootstrap" "$FIXTURE_REPO/scripts/lib" "$MOCK_BIN"
cp "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    "$FIXTURE_REPO/scripts/bootstrap/"
cp "$REPO_DIR/scripts/lib/pinned-tool-versions.sh" \
    "$REPO_DIR/scripts/lib/local-kubernetes-target.sh" \
    "$REPO_DIR/scripts/lib/local-ingress-client-trust.sh" \
    "$FIXTURE_REPO/scripts/lib/"
cp "$REPO_DIR/kind-cluster-config.yaml" "$FIXTURE_REPO/"
touch "$DOCKER_LOG" "$KUBECTL_LOG" "$KIND_LOG"
export DOCKER_LOG KUBECTL_LOG KIND_LOG
trap 'rm -rf "$FIXTURE_DIR"' EXIT

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

cat > "$MOCK_BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KUBECTL_LOG:?}"
case "$*" in
    "config current-context") printf '%s\n' "${FIXTURE_CONTEXT:-kind-kind}" ;;
    "config view --minify -o jsonpath={.contexts[0].context.cluster}")
        printf '%s' kind-kind
        ;;
    "config view --minify -o jsonpath={.clusters[0].cluster.server}")
        printf '%s' https://127.0.0.1:6443
        ;;
    "config view --minify -o jsonpath={.clusters[0].cluster.proxy-url}") ;;
    *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/kind" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KIND_LOG:?}"
[[ "$*" == "get clusters" ]] || exit 1
if [[ "${FIXTURE_KIND_PRESENT:-false}" == true ]]; then
    printf '%s\n' kind
fi
EOF

chmod 0755 "$MOCK_BIN/docker" "$MOCK_BIN/kubectl" "$MOCK_BIN/kind"

pass_count=0

pass() {
    printf 'PASS: %s\n' "$1"
    ((pass_count += 1))
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

run_prerequisites() {
    : > "$DOCKER_LOG"
    : > "$KUBECTL_LOG"
    : > "$KIND_LOG"
    # The checker exits with its error count; these fixtures inspect output
    # and command logs instead of the overall result.
    env -u DOCKER_HOST -u DOCKER_CONTEXT -u KIND_EXPERIMENTAL_PROVIDER \
        PATH="$MOCK_BIN:$PATH" "$@" \
        "$FIXTURE_REPO/scripts/bootstrap/check-tilt-prerequisites.sh" \
        >"$FIXTURE_DIR/run.out" 2>&1 || true
}

expect_output() {
    grep -Fq "$1" "$FIXTURE_DIR/run.out" \
        || fail "$2 did not report '$1'"
}

# Only these commands may run before the exact target passes. Version probes
# and configuration-only kubeconfig reads do not contact a cluster.
assert_no_cluster_specific_commands() {
    local description="$1"

    if grep -Ev '^(version( --client)?|config (current-context|view --minify .*))$' \
        "$KUBECTL_LOG" | grep -q .; then
        fail "$description ran a cluster-specific kubectl command"
    fi
    if grep -Ev '^(version|get clusters)$' "$KIND_LOG" | grep -q .; then
        fail "$description ran a Kind command beyond cluster listing"
    fi
    if grep -Ev '^(--version|context show|context inspect default --format .*|info)$' \
        "$DOCKER_LOG" | grep -q .; then
        fail "$description inspected Kind node containers"
    fi
}

run_prerequisites FIXTURE_KIND_PRESENT=false
expect_output "Kind provider is Docker on a reachable local Unix-socket daemon" \
    "absent cluster"
expect_output "Kind cluster 'kind' does not exist" "absent cluster"
expect_output "Skipping Gateway API check (no cluster connection)" "absent cluster"
grep -Fxq 'get clusters' "$KIND_LOG" \
    || fail "absent cluster was not discovered through Kind"
assert_no_cluster_specific_commands "absent cluster"
if grep -Fq 'config current-context' "$KUBECTL_LOG"; then
    fail "absent cluster ran exact-target checks"
fi
pass "absent Kind cluster keeps tooling checks and skips cluster checks"

run_prerequisites FIXTURE_KIND_PRESENT=true FIXTURE_CONTEXT=production
expect_output "current Kubernetes context is 'production'; expected 'kind-kind'" \
    "wrong target"
expect_output "Skipping cluster diagnostics because the exact local Kind target failed" \
    "wrong target"
expect_output "Skipping Kind node inotify check" "wrong target"
assert_no_cluster_specific_commands "wrong target"
pass "wrong Kubernetes target blocks cluster-specific checks"

run_prerequisites FIXTURE_KIND_PRESENT=true KIND_EXPERIMENTAL_PROVIDER=podman
expect_output "KIND_EXPERIMENTAL_PROVIDER='podman' is unsupported" \
    "alternate Kind provider"
expect_output "Skipping Kind cluster discovery because the local Docker endpoint failed" \
    "alternate Kind provider"
if grep -Fxq 'get clusters' "$KIND_LOG"; then
    fail "alternate Kind provider reached Kind cluster discovery"
fi
if grep -Fq 'config ' "$KUBECTL_LOG"; then
    fail "alternate Kind provider reached exact-target checks"
fi
assert_no_cluster_specific_commands "alternate Kind provider"
pass "alternate Kind provider is rejected before Kind cluster discovery"

printf 'Tilt prerequisite local-target fixtures passed: %s checks.\n' "$pass_count"
