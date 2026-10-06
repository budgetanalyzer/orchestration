#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
FIXTURE_PARENT="$FIXTURE_DIR/layout"
FIXTURE_ORCHESTRATION="$FIXTURE_PARENT/orchestration"
FIXTURE_WORKSPACE="$FIXTURE_PARENT/workspace"
MOCK_BIN="$FIXTURE_DIR/bin"
WORKSPACE_LOG="$FIXTURE_DIR/workspace.log"
KUBECTL_LOG="$FIXTURE_DIR/kubectl.log"
KIND_LOG="$FIXTURE_DIR/kind.log"
mkdir -p \
    "$FIXTURE_ORCHESTRATION/scripts/bootstrap" \
    "$FIXTURE_ORCHESTRATION/scripts/lib" \
    "$FIXTURE_WORKSPACE/scripts" \
    "$MOCK_BIN"
cp "$REPO_DIR/scripts/bootstrap/check-agent-vm-prerequisites.sh" \
    "$FIXTURE_ORCHESTRATION/scripts/bootstrap/"
cp "$REPO_DIR/scripts/lib/local-kubernetes-target.sh" \
    "$FIXTURE_ORCHESTRATION/scripts/lib/"
touch "$WORKSPACE_LOG" "$KUBECTL_LOG" "$KIND_LOG"
export WORKSPACE_LOG KUBECTL_LOG KIND_LOG
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat > "$FIXTURE_WORKSPACE/scripts/check-agent-vm-tools.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${WORKSPACE_LOG:?}"
exit "${FIXTURE_WORKSPACE_EXIT:-0}"
EOF
cat > "$MOCK_BIN/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KUBECTL_LOG:?}"
case "$*" in
    "config current-context") printf 'kind-kind\n' ;;
    "config view --minify -o jsonpath={.contexts[0].context.cluster}") printf 'kind-kind' ;;
    "config view --minify -o jsonpath={.clusters[0].cluster.server}") printf 'https://127.0.0.1:6443' ;;
    "config view --minify -o jsonpath={.clusters[0].cluster.proxy-url}") ;;
    "get node kind-control-plane -o jsonpath={.status.conditions[?(@.type==\"Ready\")].status}") printf 'True' ;;
    *) exit 1 ;;
esac
EOF
cat > "$MOCK_BIN/kind" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KIND_LOG:?}"
[[ "$*" == "get clusters" ]] || exit 1
printf 'kind\n'
EOF
chmod +x \
    "$FIXTURE_ORCHESTRATION/scripts/bootstrap/check-agent-vm-prerequisites.sh" \
    "$FIXTURE_WORKSPACE/scripts/check-agent-vm-tools.sh" \
    "$MOCK_BIN/kubectl" "$MOCK_BIN/kind"

pass_count=0

pass() {
    printf 'PASS: %s\n' "$1"
    ((pass_count += 1))
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

run_preflight() {
    env \
        PATH="$MOCK_BIN:$PATH" \
        BUDGET_ANALYZER_WORKTREE_PARENT=/fixture/worktrees \
        BUDGET_ANALYZER_BARE_PARENT=/fixture/bares \
        "$FIXTURE_ORCHESTRATION/scripts/bootstrap/check-agent-vm-prerequisites.sh" \
        "$@"
}

if ! run_preflight >/dev/null; then
    fail "bootstrap wrapper rejected the complete workspace verifier fixture"
fi
expected_args='--worktree-parent /fixture/worktrees --bare-parent /fixture/bares'
[[ "$(tail -n1 "$WORKSPACE_LOG")" == "$expected_args" ]] \
    || fail "wrapper did not forward the two managed native environment inputs"
[[ ! -s "$KUBECTL_LOG" && ! -s "$KIND_LOG" ]] \
    || fail "bootstrap mode inspected Kind before it exists"
pass "bootstrap mode invokes the complete workspace contract without Kind access"

: > "$KUBECTL_LOG"
: > "$KIND_LOG"
if ! run_preflight --native-runtime >/dev/null; then
    fail "daily wrapper rejected the valid workspace and Kind fixtures"
fi
grep -Fxq 'config current-context' "$KUBECTL_LOG" \
    || fail "daily mode did not invoke the orchestration Kind target check"
grep -Fxq 'get clusters' "$KIND_LOG" \
    || fail "daily mode did not verify the local Kind cluster"
pass "daily mode adds the exact orchestration-owned Kind target check"

: > "$KUBECTL_LOG"
: > "$KIND_LOG"
if FIXTURE_WORKSPACE_EXIT=42 run_preflight --native-runtime >/dev/null 2>&1; then
    fail "workspace verifier failure unexpectedly passed"
fi
[[ ! -s "$KUBECTL_LOG" && ! -s "$KIND_LOG" ]] \
    || fail "workspace failure reached the Kubernetes target"
pass "workspace failure stops before Kubernetes access"

: > "$WORKSPACE_LOG"
if env -u BUDGET_ANALYZER_WORKTREE_PARENT \
    BUDGET_ANALYZER_BARE_PARENT=/fixture/bares \
    "$FIXTURE_ORCHESTRATION/scripts/bootstrap/check-agent-vm-prerequisites.sh" \
    >/dev/null 2>&1; then
    fail "missing managed worktree input unexpectedly passed"
fi
[[ ! -s "$WORKSPACE_LOG" ]] \
    || fail "missing managed input reached the workspace verifier"
pass "missing managed native environment input fails before delegation"

mv "$FIXTURE_WORKSPACE" "$FIXTURE_PARENT/workspace-away"
if run_preflight >"$FIXTURE_DIR/missing-workspace.out" 2>&1; then
    fail "missing workspace checkout unexpectedly passed"
fi
grep -Fq 'workspace native verifier is missing or not executable' \
    "$FIXTURE_DIR/missing-workspace.out" \
    || fail "missing workspace checkout did not report the required verifier"
mv "$FIXTURE_PARENT/workspace-away" "$FIXTURE_WORKSPACE"
pass "missing workspace checkout fails before application bootstrap"

setup_preflight_line="$(grep -nF "    \"\$SCRIPT_DIR/scripts/bootstrap/check-agent-vm-prerequisites.sh\"" \
    "$REPO_DIR/setup.sh" | cut -d: -f1)"
setup_tls_line="$(grep -nF "    \"\$SCRIPT_DIR/scripts/bootstrap/install-imported-ingress-tls.sh\" --validate-only" \
    "$REPO_DIR/setup.sh" | cut -d: -f1)"
setup_delete_line="$(grep -nE '^[[:space:]]*kind delete cluster --name kind$' \
    "$REPO_DIR/setup.sh" | cut -d: -f1)"
[[ -n "$setup_preflight_line" && -n "$setup_tls_line" && -n "$setup_delete_line" ]] \
    || fail "could not locate the guest setup safety sequence"
(( setup_preflight_line < setup_tls_line && setup_tls_line < setup_delete_line )) \
    || fail "guest setup prerequisites do not precede Kind deletion"
grep -Fxq 'set -e' "$REPO_DIR/setup.sh" \
    || fail "setup no longer fails closed on prerequisite errors"
pass "guest setup runs workspace and imported-TLS checks before Kind deletion"

grep -Fq "if \"\$NATIVE_PREFLIGHT\"; then" \
    "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    || fail "Tilt guest diagnostics do not delegate to the wrapper"
grep -Fq 'if assert_local_kind_target; then' \
    "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    || fail "Tilt guest diagnostics lost the orchestration Kind check"
pass "Tilt guest diagnostics delegate native readiness and retain Kind validation"

printf 'Native preflight wrapper fixtures passed: %s checks.\n' "$pass_count"
