#!/usr/bin/env bash
# Install pinned host tooling from verified release artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./lib/pinned-tool-versions.sh
. "$SCRIPT_DIR/lib/pinned-tool-versions.sh"

usage() {
    cat <<'EOF'
Usage: scripts/dev/install-verified-tool.sh <kubectl|helm|tilt|mkcert|kubeconform|kube-linter|kyverno> [--install-dir DIR]

Installs the repo-pinned tool release for the current OS/architecture after
verifying the checked-in SHA-256 checksum.
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

ensure_directory() {
    local dir

    dir="$1"
    if [[ -d "$dir" ]]; then
        return 0
    fi

    if mkdir -p "$dir" 2>/dev/null; then
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$dir"
        return 0
    fi

    echo "Cannot create install directory '$dir'. Re-run with --install-dir or install sudo." >&2
    exit 1
}

install_binary() {
    local source_file destination_file destination_dir

    source_file="$1"
    destination_file="$2"
    destination_dir="$(dirname "$destination_file")"

    ensure_directory "$destination_dir"

    if install -m 0755 "$source_file" "$destination_file" 2>/dev/null; then
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo install -m 0755 "$source_file" "$destination_file"
        return 0
    fi

    echo "Cannot write to '$destination_dir'. Re-run with --install-dir or install sudo." >&2
    exit 1
}

download_file() {
    local url output

    url="$1"
    output="$2"
    curl -fsSLo "$output" "$url"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

TOOL="$1"
shift
INSTALL_DIR="/usr/local/bin"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

case "$TOOL" in
    kubectl|helm|tilt|mkcert|kubeconform|kube-linter|kyverno)
        ;;
    *)
        echo "Unsupported tool: $TOOL" >&2
        usage
        exit 1
        ;;
esac

require_command curl

PLATFORM="$(phase7_platform_key)"
VERSION="$(phase7_tool_version "$TOOL")"
URL="$(phase7_tool_url "$TOOL" "$PLATFORM")"
EXPECTED_SHA256="$(phase7_tool_sha256 "$TOOL" "$PLATFORM")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

case "$TOOL" in
    kubectl)
        ARTIFACT="$TMP_DIR/kubectl"
        download_file "$URL" "$ARTIFACT"
        phase7_verify_sha256 "$ARTIFACT" "$EXPECTED_SHA256"
        install_binary "$ARTIFACT" "$INSTALL_DIR/kubectl"
        ;;
    helm)
        ARCHIVE="$TMP_DIR/helm.tar.gz"
        ARTIFACT_DIR="$TMP_DIR/$PLATFORM"
        download_file "$URL" "$ARCHIVE"
        phase7_verify_sha256 "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xzf "$ARCHIVE" -C "$TMP_DIR"
        install_binary "$ARTIFACT_DIR/helm" "$INSTALL_DIR/helm"
        ;;
    tilt)
        ARCHIVE="$TMP_DIR/tilt.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_verify_sha256 "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xzf "$ARCHIVE" -C "$TMP_DIR"
        install_binary "$TMP_DIR/tilt" "$INSTALL_DIR/tilt"
        ;;
    mkcert)
        ARTIFACT="$TMP_DIR/mkcert"
        download_file "$URL" "$ARTIFACT"
        phase7_verify_sha256 "$ARTIFACT" "$EXPECTED_SHA256"
        install_binary "$ARTIFACT" "$INSTALL_DIR/mkcert"
        ;;
    kubeconform)
        ARCHIVE="$TMP_DIR/kubeconform.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_verify_sha256 "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xzf "$ARCHIVE" -C "$TMP_DIR"
        install_binary "$TMP_DIR/kubeconform" "$INSTALL_DIR/kubeconform"
        ;;
    kube-linter)
        ARCHIVE="$TMP_DIR/kube-linter.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_verify_sha256 "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xzf "$ARCHIVE" -C "$TMP_DIR"
        install_binary "$TMP_DIR/kube-linter" "$INSTALL_DIR/kube-linter"
        ;;
    kyverno)
        ARCHIVE="$TMP_DIR/kyverno.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_verify_sha256 "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xzf "$ARCHIVE" -C "$TMP_DIR"
        install_binary "$TMP_DIR/kyverno" "$INSTALL_DIR/kyverno"
        ;;
esac

echo "Installed $TOOL $VERSION to $INSTALL_DIR/$TOOL"
if [[ "$TOOL" == "mkcert" ]]; then
    echo "Note: mkcert still needs trust-store tooling on the host. Linux uses libnss3-tools; macOS still works best with Homebrew nss."
fi
