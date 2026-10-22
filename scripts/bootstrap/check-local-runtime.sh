#!/bin/bash

# Read-only orchestration preflight for the local Docker and Kind runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/local-kubernetes-target.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
. "$SCRIPT_DIR/../lib/local-kubernetes-target.sh"

usage() {
    cat <<'EOF'
Usage: scripts/bootstrap/check-local-runtime.sh

Require the Docker CLI to select a reachable local Unix-socket daemon and
require the exact Ready loopback kind-kind Kubernetes target. This check is
read-only.
EOF
}

if [[ $# -gt 1 ]]; then
    usage >&2
    printf 'ERROR: expected no arguments\n' >&2
    exit 2
fi

case "${1:-}" in
    "") ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        usage >&2
        printf 'ERROR: unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
esac

assert_local_docker_endpoint
assert_local_kind_target

printf 'Local application runtime prerequisites pass: local Docker and exact Kind target verified.\n'
