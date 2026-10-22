#!/usr/bin/env bash
# Download and verify kubectl, Helm, Tilt, and Kind for both supported Linux architectures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/pinned-tool-versions.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/../lib/pinned-tool-versions.sh"

usage() {
    cat <<'EOF'
Usage: scripts/bootstrap/verify-platform-tool-releases.sh [--download-dir DIR]

Downloads the pinned kubectl, Helm, Tilt, and Kind release artifacts for Linux
amd64 and arm64, verifies their SHA-256 checksums, and validates required
archive members without installing or executing any downloaded binary.
EOF
}

DOWNLOAD_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --download-dir)
            if [[ $# -lt 2 ]]; then
                echo "--download-dir requires a directory" >&2
                exit 1
            fi
            DOWNLOAD_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$DOWNLOAD_DIR" ]]; then
    DOWNLOAD_DIR="$(mktemp -d)"
    trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
else
    mkdir -p -- "$DOWNLOAD_DIR"
fi

for platform in linux-amd64 linux-arm64; do
    for tool in kubectl helm tilt kind; do
        version="$(phase7_tool_version "$tool")"
        url="$(phase7_tool_url "$tool" "$platform")"
        artifact="$DOWNLOAD_DIR/${tool}-${platform}.download"
        curl --fail --show-error --silent --location \
            --proto '=https' --proto-redir '=https' \
            --output "$artifact" "$url"
        phase7_validate_tool_artifact "$tool" "$platform" "$artifact"
        printf 'Verified %s %s for %s\n' "$tool" "$version" "$platform"
    done
done

echo "Verified 8 platform-tool release artifacts without installation or execution."
