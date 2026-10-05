#!/bin/bash

# Read-only preflight for guest-local bootstrap and native daily execution.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/local-docker-target.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
. "$SCRIPT_DIR/../lib/local-docker-target.sh"
# shellcheck source=../lib/local-kubernetes-target.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
. "$SCRIPT_DIR/../lib/local-kubernetes-target.sh"
# shellcheck source=../lib/native-guest-boundary.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
. "$SCRIPT_DIR/../lib/native-guest-boundary.sh"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/bootstrap/check-agent-vm-prerequisites.sh [--native-runtime]

Without options, validate the system prerequisites used before an explicit
guest-local bootstrap. With --native-runtime, additionally run the
workspace-owned native tool/user verifier and require the exact live Kind
target. Neither mode changes the guest or cluster.
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

assert_native_guest_process || exit 1

if [[ ! -r /etc/os-release ]]; then
    fail "cannot read /etc/os-release"
fi

# shellcheck disable=SC1091 # This is the standard Linux OS identity file.
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    fail "expected Ubuntu 24.04 LTS for the development VM"
fi

required_commands=(docker git openssl java node npm)
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "required command is missing: $command_name"
done

assert_local_docker_target || exit 1

java_major="$(java -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -n1)"
[[ "$java_major" == "25" ]] || fail "JDK 25 is required; detected major '${java_major:-unknown}'"

node_major="$(node --version | sed -nE 's/^v([0-9]+).*/\1/p')"
[[ "$node_major" =~ ^[0-9]+$ && "$node_major" -ge 20 ]] \
    || fail "Node.js 20 or newer is required"

npm_major="$(npm --version | sed -nE 's/^([0-9]+).*/\1/p')"
[[ "$npm_major" =~ ^[0-9]+$ && "$npm_major" -ge 10 ]] \
    || fail "npm 10 or newer is required"

assert_no_forwarded_host_authority || exit 1

if [[ "$NATIVE_RUNTIME" == true ]]; then
    WORKSPACE_CHECK="$ORCHESTRATION_DIR/../workspace/scripts/check-agent-vm-tools.sh"
    [[ -x "$WORKSPACE_CHECK" ]] \
        || fail "workspace native verifier is missing or not executable: $WORKSPACE_CHECK"
    [[ -n "${BUDGET_ANALYZER_WORKTREE_PARENT:-}" ]] \
        || fail "BUDGET_ANALYZER_WORKTREE_PARENT is not set by the native user environment"
    [[ -n "${BUDGET_ANALYZER_BARE_PARENT:-}" ]] \
        || fail "BUDGET_ANALYZER_BARE_PARENT is not set by the native user environment"

    "$WORKSPACE_CHECK" \
        --worktree-parent "$BUDGET_ANALYZER_WORKTREE_PARENT" \
        --bare-parent "$BUDGET_ANALYZER_BARE_PARENT"
    assert_local_kind_target || exit 1

    printf 'Native runtime prerequisites pass: workspace tools/user/home and exact local Kind target verified.\n'
else
    printf 'Guest-local bootstrap prerequisites pass: Ubuntu 24.04, local Docker, Git, OpenSSL, JDK 25, Node.js and npm.\n'
fi
