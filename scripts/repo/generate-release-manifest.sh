#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/generate-release-manifest.sh

Status:
  Superseded. The historical lockstep release-manifest shape is no longer a
  production deployment input.

Use the OCI desired-state preparation flow instead:

  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --plan-only
  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --push-tags
  # After GitHub Actions publishes the expected GHCR tags:
  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --resolve-images

The preparation command writes the complete schema v2 desired-state manifest
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

    die "generate-release-manifest.sh is superseded; use deploy/scripts/prepare-oci-manifest-from-current-stack.sh"
}

main "$@"
