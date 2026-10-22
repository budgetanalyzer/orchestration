#!/usr/bin/env bash
# Install pinned host tooling from verified release artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=../lib/pinned-tool-versions.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/../lib/pinned-tool-versions.sh"
# shellcheck source=../lib/verified-tool-destination.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/../lib/verified-tool-destination.sh"

usage() {
    cat <<'EOF'
Usage: scripts/bootstrap/install-verified-tool.sh <kubectl|helm|tilt|mkcert|kind|kubeconform|kube-linter|kyverno|yq> [--install-dir DIR]

Installs the repo-pinned tool release for the current OS/architecture after
verifying the checked-in SHA-256 checksum. A recognized existing binary is
replaced with the pin, whether it is newer or older.

The default /usr/local/bin destination is installed with sudo; it, its
ancestors and any existing destination must be root-owned, not symlinked and
not writable by group/other. A custom --install-dir is installed without sudo:
missing directories are created with mkdir -p under the current umask, and an
existing destination must be a regular, non-symlinked file. Normal filesystem
permissions govern custom writes.
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
    if [[ "$SYSTEM_INSTALL" == false ]]; then
        mkdir -p -- "$dir"
        return 0
    fi
    if [[ -d "$dir" ]]; then
        return 0
    fi
    require_command sudo
    sudo install -d -m 0755 -- "$dir"
}

install_binary() {
    local source_file destination_file

    source_file="$1"
    destination_file="$2"
    if [[ "$SYSTEM_INSTALL" == false ]]; then
        install -m 0755 -- "$source_file" "$destination_file"
        return 0
    fi
    require_command sudo
    sudo install -m 0755 -- "$source_file" "$destination_file"
}

download_file() {
    local url output

    url="$1"
    output="$2"
    curl --fail --show-error --silent --location \
        --proto '=https' --proto-redir '=https' \
        --output "$output" "$url"
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
            if [[ $# -lt 2 ]]; then
                echo "--install-dir requires a directory" >&2
                exit 1
            fi
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
    kubectl|helm|tilt|mkcert|kind|kubeconform|kube-linter|kyverno|yq)
        ;;
    *)
        echo "Unsupported tool: $TOOL" >&2
        usage
        exit 1
        ;;
esac

require_command curl
require_command install

case "$INSTALL_DIR" in
    /*) ;;
    *)
        echo "Install directory must be an absolute path: $INSTALL_DIR" >&2
        exit 1
        ;;
esac
case "$INSTALL_DIR/" in
    *'/../'*|*'/./'*|*'//'*)
        echo "Install directory must be lexically normalized: $INSTALL_DIR" >&2
        exit 1
        ;;
esac

PLATFORM="$(phase7_platform_key)"
VERSION="$(phase7_tool_version "$TOOL")"
URL="$(phase7_tool_url "$TOOL" "$PLATFORM")"
EXPECTED_SHA256="$(phase7_tool_sha256 "$TOOL" "$PLATFORM")"
SYSTEM_INSTALL=false
if [[ "$INSTALL_DIR" == /usr/local/bin ]]; then
    SYSTEM_INSTALL=true
    require_command stat
fi
DESTINATION="$INSTALL_DIR/$TOOL"

if [[ "$SYSTEM_INSTALL" == true ]]; then
    verified_tool_validate_privileged_destination "$DESTINATION"
fi
EXISTING_VERSION="$(verified_tool_existing_destination_version "$TOOL" "$DESTINATION")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
STAGED_BINARY="$TMP_DIR/staged-$TOOL"

ARTIFACT="$TMP_DIR/$TOOL.download"
download_file "$URL" "$ARTIFACT"
phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARTIFACT" "$EXPECTED_SHA256"
phase7_stage_tool_binary "$TOOL" "$PLATFORM" "$ARTIFACT" "$STAGED_BINARY"

ensure_directory "$INSTALL_DIR"
if [[ "$SYSTEM_INSTALL" == true ]]; then
    verified_tool_validate_privileged_destination "$DESTINATION"
    EXISTING_VERSION="$(verified_tool_existing_destination_version "$TOOL" "$DESTINATION")"
fi
if [[ -n "$EXISTING_VERSION" ]]; then
    echo "Replacing $TOOL $EXISTING_VERSION with pinned $VERSION at $DESTINATION"
fi
install_binary "$STAGED_BINARY" "$DESTINATION"

echo "Installed $TOOL $VERSION to $INSTALL_DIR/$TOOL"
if [[ "$TOOL" == "mkcert" ]]; then
    echo "Note: mkcert still needs trust-store tooling on the host. Linux uses libnss3-tools; macOS still works best with Homebrew nss."
fi
