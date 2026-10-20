#!/usr/bin/env bash
# Install pinned host tooling from verified release artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=../lib/pinned-tool-versions.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/../lib/pinned-tool-versions.sh"

usage() {
    cat <<'EOF'
Usage: scripts/bootstrap/install-verified-tool.sh <kubectl|helm|tilt|mkcert|kind|kubeconform|kube-linter|kyverno|yq> [--install-dir DIR]

Installs the repo-pinned tool release for the current OS/architecture after
verifying the checked-in SHA-256 checksum. The default system destination must
be root-owned; a custom --install-dir must be owned by the invoking user or
root. Install paths may not be symlinked or writable by group/other.
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

path_uid() {
    stat -c '%u' -- "$1" 2>/dev/null || stat -f '%u' -- "$1"
}

path_mode() {
    stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Lp' -- "$1"
}

validate_owned_path() {
    local path context uid mode permissions

    path="$1"
    context="$2"
    if [[ -L "$path" ]]; then
        echo "Symlinked ${context}: $path" >&2
        return 1
    fi

    uid="$(path_uid "$path")"
    mode="$(path_mode "$path")"
    if [[ "$SYSTEM_INSTALL" == true ]]; then
        if [[ "$uid" != 0 ]]; then
            echo "System ${context} is not root-owned: $path" >&2
            return 1
        fi
    elif [[ "$uid" != 0 && "$uid" != "$CURRENT_UID" ]]; then
        echo "Custom ${context} is not owned by root or uid ${CURRENT_UID}: $path" >&2
        return 1
    fi

    permissions=$((8#$mode))
    if (( permissions & 18 )); then
        echo "Group/world-writable ${context}: $path" >&2
        return 1
    fi
}

validate_existing_ancestors() {
    local path context

    path="$1"
    context="$2"
    while [[ ! -e "$path" && ! -L "$path" ]]; do
        path="$(dirname "$path")"
    done
    while :; do
        validate_owned_path "$path" "$context parent" || return 1
        [[ "$path" == / ]] && break
        path="$(dirname "$path")"
    done
}

validate_install_destination() {
    local destination raw_version installed_version selected_version

    destination="$1"
    validate_existing_ancestors "$(dirname "$destination")" "install" || return 1

    if [[ -L "$destination" ]]; then
        echo "Symlinked install destination: $destination" >&2
        return 1
    fi
    if [[ ! -e "$destination" ]]; then
        return 0
    fi
    validate_owned_path "$destination" "install destination" || return 1
    if [[ ! -f "$destination" || ! -x "$destination" ]]; then
        echo "Destination collision with a non-executable file: $destination" >&2
        return 1
    fi

    raw_version="$(phase7_tool_raw_version_at "$TOOL" "$destination" 2>/dev/null || true)"
    installed_version="$(phase7_normalize_semver "$raw_version")"
    selected_version="$(phase7_normalize_semver "$VERSION")"
    if [[ -z "$installed_version" ]]; then
        echo "Destination collision: cannot identify existing $TOOL at $destination" >&2
        return 1
    fi
    if phase7_semver_is_newer "$installed_version" "$selected_version"; then
        echo "Refusing to downgrade existing $TOOL $installed_version to $VERSION at $destination" >&2
        return 1
    fi
}

check_resolved_system_tool_for_downgrade() {
    local resolved raw_version installed_version selected_version

    [[ "$SYSTEM_INSTALL" == true ]] || return 0
    resolved="$(command -v "$TOOL" 2>/dev/null || true)"
    [[ -n "$resolved" && "$resolved" != "$DESTINATION" ]] || return 0
    if [[ "$resolved" != /* ]]; then
        echo "Command collision: $TOOL resolves to a non-absolute path: $resolved" >&2
        return 1
    fi
    validate_existing_ancestors "$(dirname "$resolved")" "resolved command" || return 1
    validate_owned_path "$resolved" "resolved command" || return 1
    raw_version="$(phase7_tool_raw_version_at "$TOOL" "$resolved" 2>/dev/null || true)"
    installed_version="$(phase7_normalize_semver "$raw_version")"
    selected_version="$(phase7_normalize_semver "$VERSION")"
    if [[ -z "$installed_version" ]]; then
        echo "Command collision: cannot identify existing $TOOL at $resolved" >&2
        return 1
    fi
    if phase7_semver_is_newer "$installed_version" "$selected_version"; then
        echo "Refusing to downgrade existing $TOOL $installed_version to $VERSION from $resolved" >&2
        return 1
    fi
}

ensure_directory() {
    local dir

    dir="$1"
    if [[ -d "$dir" ]]; then
        return 0
    fi
    if [[ -e "$dir" || -L "$dir" ]]; then
        echo "Install directory collision: $dir" >&2
        return 1
    fi

    if [[ "$SYSTEM_INSTALL" == false ]]; then
        mkdir -p -- "$dir"
        chmod 0755 -- "$dir"
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
require_command stat

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
CURRENT_UID="$(id -u)"
SYSTEM_INSTALL=false
if [[ "$INSTALL_DIR" == /usr/local/bin ]]; then
    SYSTEM_INSTALL=true
fi
DESTINATION="$INSTALL_DIR/$TOOL"

validate_install_destination "$DESTINATION"
check_resolved_system_tool_for_downgrade

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
STAGED_BINARY="$TMP_DIR/staged-$TOOL"

case "$TOOL" in
    kubectl)
        ARTIFACT="$TMP_DIR/kubectl"
        download_file "$URL" "$ARTIFACT"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARTIFACT" "$EXPECTED_SHA256"
        cp -- "$ARTIFACT" "$STAGED_BINARY"
        ;;
    helm)
        ARCHIVE="$TMP_DIR/helm.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xOzf "$ARCHIVE" "$(phase7_tool_archive_member "$TOOL" "$PLATFORM")" > "$STAGED_BINARY"
        ;;
    tilt)
        ARCHIVE="$TMP_DIR/tilt.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xOzf "$ARCHIVE" "$(phase7_tool_archive_member "$TOOL" "$PLATFORM")" > "$STAGED_BINARY"
        ;;
    mkcert)
        ARTIFACT="$TMP_DIR/mkcert"
        download_file "$URL" "$ARTIFACT"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARTIFACT" "$EXPECTED_SHA256"
        cp -- "$ARTIFACT" "$STAGED_BINARY"
        ;;
    kind)
        ARTIFACT="$TMP_DIR/kind"
        download_file "$URL" "$ARTIFACT"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARTIFACT" "$EXPECTED_SHA256"
        cp -- "$ARTIFACT" "$STAGED_BINARY"
        ;;
    kubeconform)
        ARCHIVE="$TMP_DIR/kubeconform.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xOzf "$ARCHIVE" "$(phase7_tool_archive_member "$TOOL" "$PLATFORM")" > "$STAGED_BINARY"
        ;;
    kube-linter)
        ARCHIVE="$TMP_DIR/kube-linter.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xOzf "$ARCHIVE" "$(phase7_tool_archive_member "$TOOL" "$PLATFORM")" > "$STAGED_BINARY"
        ;;
    kyverno)
        ARCHIVE="$TMP_DIR/kyverno.tar.gz"
        download_file "$URL" "$ARCHIVE"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARCHIVE" "$EXPECTED_SHA256"
        tar -xOzf "$ARCHIVE" "$(phase7_tool_archive_member "$TOOL" "$PLATFORM")" > "$STAGED_BINARY"
        ;;
    yq)
        ARTIFACT="$TMP_DIR/yq"
        download_file "$URL" "$ARTIFACT"
        phase7_validate_tool_artifact "$TOOL" "$PLATFORM" "$ARTIFACT" "$EXPECTED_SHA256"
        cp -- "$ARTIFACT" "$STAGED_BINARY"
        ;;
esac

ensure_directory "$INSTALL_DIR"
validate_install_destination "$DESTINATION"
install_binary "$STAGED_BINARY" "$DESTINATION"

echo "Installed $TOOL $VERSION to $INSTALL_DIR/$TOOL"
if [[ "$TOOL" == "mkcert" ]]; then
    echo "Note: mkcert still needs trust-store tooling on the host. Linux uses libnss3-tools; macOS still works best with Homebrew nss."
fi
