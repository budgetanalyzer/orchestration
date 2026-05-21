#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/generate-release-manifest.sh

Status:
  Superseded. The historical lockstep release-manifest shape is no longer a
  production deployment input.

Use the convention-based OCI promotion flow instead:

  ./deploy/scripts/promote-current-stack-to-oci.sh --plan-only
  ./deploy/scripts/promote-current-stack-to-oci.sh

The promotion command writes the complete schema v2 deployment snapshot
consumed by the production baseline renderer.
EOF
}

die() {
    printf '[release-manifest] ERROR: %s\n' "$*" >&2
    exit 1
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    die "generate-release-manifest.sh is superseded; use deploy/scripts/promote-current-stack-to-oci.sh"
}

main "$@"
