#!/usr/bin/env bash
# Destination checks for scripts/bootstrap/install-verified-tool.sh.
# Requires scripts/lib/pinned-tool-versions.sh to be sourced first.

verified_tool_path_uid() {
    stat -c '%u' -- "$1" 2>/dev/null || stat -f '%u' -- "$1"
}

verified_tool_path_mode() {
    stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Lp' -- "$1"
}

# Privileged contract: not a symlink, root-owned, not group/world-writable.
verified_tool_validate_privileged_path() {
    local path context uid mode

    path="$1"
    context="$2"
    if [[ -L "$path" ]]; then
        echo "Symlinked ${context}: $path" >&2
        return 1
    fi
    uid="$(verified_tool_path_uid "$path")" || return 1
    mode="$(verified_tool_path_mode "$path")" || return 1
    if [[ "$uid" != 0 ]]; then
        echo "System ${context} is not root-owned: $path" >&2
        return 1
    fi
    if (( 8#$mode & 8#022 )); then
        echo "Group/world-writable ${context}: $path" >&2
        return 1
    fi
}

# Validate a privileged destination, its nearest existing parent and every
# ancestor up to /.
verified_tool_validate_privileged_destination() {
    local destination path

    destination="$1"
    path="$(dirname "$destination")"
    while [[ ! -e "$path" && ! -L "$path" ]]; do
        path="$(dirname "$path")"
    done
    while :; do
        verified_tool_validate_privileged_path "$path" "install parent" || return 1
        [[ "$path" == / ]] && break
        path="$(dirname "$path")"
    done
    if [[ -e "$destination" && ! -L "$destination" ]]; then
        verified_tool_validate_privileged_path "$destination" "install destination" || return 1
    fi
}

# Shared by both contracts. Prints the normalized version of a recognized
# existing destination binary, or nothing when the destination is absent.
# Rejects symlinks, non-regular files and unidentifiable contents.
verified_tool_existing_destination_version() {
    local tool destination raw_version installed_version

    tool="$1"
    destination="$2"
    if [[ -L "$destination" ]]; then
        echo "Symlinked install destination: $destination" >&2
        return 1
    fi
    [[ -e "$destination" ]] || return 0
    if [[ ! -f "$destination" ]]; then
        echo "Destination collision: not a regular file: $destination" >&2
        return 1
    fi
    raw_version="$(phase7_tool_raw_version_at "$tool" "$destination" 2>/dev/null)" || raw_version=""
    installed_version="$(phase7_normalize_semver "$raw_version")"
    if [[ -z "$installed_version" ]]; then
        echo "Destination collision: cannot identify existing $tool at $destination" >&2
        return 1
    fi
    printf '%s\n' "$installed_version"
}
