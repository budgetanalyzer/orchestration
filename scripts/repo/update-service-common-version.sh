#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# repo-config.sh lives beside this script and is resolved from SCRIPT_DIR at runtime.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/repo-config.sh"

usage() {
    cat <<'EOF'
Usage: ./scripts/repo/update-service-common-version.sh <target-version>

Rewrites the checked-in service-common version literal in:
- service-common/build.gradle.kts
- transaction-service/gradle/libs.versions.toml
- currency-service/gradle/libs.versions.toml
- permission-service/gradle/libs.versions.toml
- session-gateway/gradle/libs.versions.toml

Accepted version format:
- MAJOR.MINOR.PATCH
- MAJOR.MINOR.PATCH-SNAPSHOT

Examples:
- 0.0.8
- 0.0.9-SNAPSHOT
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

TARGET_VERSION="$1"

if [[ ! "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-SNAPSHOT)?$ ]]; then
    print_error "Invalid target version: ${TARGET_VERSION}"
    echo "Expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-SNAPSHOT"
    exit 1
fi

declare -a CHANGED_FILES=()

update_gradle_version_literal() {
    local file_path="$1"
    local display_path="$2"
    local temp_file
    local match_count=0

    if [[ ! -f "$file_path" ]]; then
        print_error "Required file not found: ${file_path}"
        exit 1
    fi

    temp_file="$(mktemp)"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*)version[[:space:]]*=[[:space:]]*\"[^\"]+\"([[:space:]]*)$ ]]; then
            printf '%sversion = "%s"%s\n' "${BASH_REMATCH[1]}" "$TARGET_VERSION" "${BASH_REMATCH[2]}" >> "$temp_file"
            match_count=$((match_count + 1))
        else
            printf '%s\n' "$line" >> "$temp_file"
        fi
    done < "$file_path"

    if [[ $match_count -ne 1 ]]; then
        rm -f "$temp_file"
        print_error "Expected exactly one version literal in ${display_path}, found ${match_count}"
        exit 1
    fi

    if cmp -s "$file_path" "$temp_file"; then
        rm -f "$temp_file"
        return 0
    fi

    cat "$temp_file" > "$file_path"
    rm -f "$temp_file"
    CHANGED_FILES+=("$display_path")
}

update_toml_service_common_version() {
    local file_path="$1"
    local display_path="$2"
    local temp_file
    local match_count=0

    if [[ ! -f "$file_path" ]]; then
        print_error "Required file not found: ${file_path}"
        exit 1
    fi

    temp_file="$(mktemp)"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([[:space:]]*)serviceCommon[[:space:]]*=[[:space:]]*\"[^\"]+\"([[:space:]]*)$ ]]; then
            printf '%sserviceCommon = "%s"%s\n' "${BASH_REMATCH[1]}" "$TARGET_VERSION" "${BASH_REMATCH[2]}" >> "$temp_file"
            match_count=$((match_count + 1))
        else
            printf '%s\n' "$line" >> "$temp_file"
        fi
    done < "$file_path"

    if [[ $match_count -ne 1 ]]; then
        rm -f "$temp_file"
        print_error "Expected exactly one serviceCommon version entry in ${display_path}, found ${match_count}"
        exit 1
    fi

    if cmp -s "$file_path" "$temp_file"; then
        rm -f "$temp_file"
        return 0
    fi

    cat "$temp_file" > "$file_path"
    rm -f "$temp_file"
    CHANGED_FILES+=("$display_path")
}

update_gradle_version_literal \
    "${PARENT_DIR}/service-common/build.gradle.kts" \
    "../service-common/build.gradle.kts"

update_toml_service_common_version \
    "${PARENT_DIR}/transaction-service/gradle/libs.versions.toml" \
    "../transaction-service/gradle/libs.versions.toml"
update_toml_service_common_version \
    "${PARENT_DIR}/currency-service/gradle/libs.versions.toml" \
    "../currency-service/gradle/libs.versions.toml"
update_toml_service_common_version \
    "${PARENT_DIR}/permission-service/gradle/libs.versions.toml" \
    "../permission-service/gradle/libs.versions.toml"
update_toml_service_common_version \
    "${PARENT_DIR}/session-gateway/gradle/libs.versions.toml" \
    "../session-gateway/gradle/libs.versions.toml"

print_success "Updated service-common version to ${TARGET_VERSION}"

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
    echo "No files changed."
    exit 0
fi

echo "Changed files:"
for changed_file in "${CHANGED_FILES[@]}"; do
    echo "- ${changed_file}"
done
