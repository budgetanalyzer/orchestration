#!/bin/bash

# Read-only orchestration preflight for native application bootstrap and daily
# execution. Workspace owns the complete development-VM runtime check.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_DIR="$(dirname "$ORCHESTRATION_DIR")/workspace"
# shellcheck source=../lib/local-kubernetes-target.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
. "$SCRIPT_DIR/../lib/local-kubernetes-target.sh"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/bootstrap/check-agent-vm-prerequisites.sh [--native-runtime]

Without options, validate the system prerequisites used before an explicit
guest-local application bootstrap through the complete workspace-owned native
runtime verifier. With --native-runtime, additionally require the exact live
Kind target for daily application work. Neither mode changes the guest or
cluster.
EOF
}

NATIVE_RUNTIME=false
case "${1:-}" in
    "") ;;
    --native-runtime)
        NATIVE_RUNTIME=true
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        usage >&2
        fail "unknown argument: $1"
        ;;
esac
[[ $# -le 1 ]] || fail "expected at most one argument"

WORKSPACE_CHECK="$WORKSPACE_DIR/scripts/check-agent-vm-tools.sh"
[[ -x "$WORKSPACE_CHECK" ]] \
    || fail "workspace native verifier is missing or not executable: $WORKSPACE_CHECK"
[[ -n "${BUDGET_ANALYZER_WORKTREE_PARENT:-}" ]] \
    || fail "BUDGET_ANALYZER_WORKTREE_PARENT is not set by the managed native environment"
[[ -n "${BUDGET_ANALYZER_BARE_PARENT:-}" ]] \
    || fail "BUDGET_ANALYZER_BARE_PARENT is not set by the managed native environment"

"$WORKSPACE_CHECK" \
    --worktree-parent "$BUDGET_ANALYZER_WORKTREE_PARENT" \
    --bare-parent "$BUDGET_ANALYZER_BARE_PARENT"

if [[ "$NATIVE_RUNTIME" == true ]]; then
    assert_local_kind_target || exit 1

    printf 'Native application runtime prerequisites pass: workspace runtime and exact local Kind target verified.\n'
else
    printf 'Guest-local application bootstrap prerequisites pass: complete workspace native runtime verified.\n'
fi
