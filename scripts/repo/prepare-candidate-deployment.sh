#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/prepare-candidate-deployment.sh

This helper is superseded. Candidate Git tags are no longer part of the OCI
deployment flow, and deployment snapshots now record accepted production state.

Use the full-stack promotion command instead:

  ./deploy/scripts/promote-current-stack-to-oci.sh --plan-only
  ./deploy/scripts/promote-current-stack-to-oci.sh
EOF
}

die() {
    printf '[candidate-prep] ERROR: %s\n' "$*" >&2
    exit 1
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        usage >&2
        die "candidate deployment prep has been retired"
        ;;
    *)
        usage >&2
        die "candidate deployment prep has been retired; unknown option: $1"
        ;;
esac
