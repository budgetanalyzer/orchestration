#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# repo-config.sh lives beside this script and is resolved from SCRIPT_DIR at runtime.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/repo-config.sh"

JAVA_CONSUMER_REPOS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
)
readonly JAVA_CONSUMER_REPOS

TARGET_VERSION=""
DRY_RUN=false
VALIDATE_ONLY=false
declare -a CHANGED_FILES=()

usage() {
    cat <<'EOF'
Usage: ./scripts/repo/update-service-common-version.sh [options] <target-version>

Updates the checked-in service-common version in:
- ../service-common/build.gradle.kts
- ../transaction-service/gradle/libs.versions.toml
- ../currency-service/gradle/libs.versions.toml
- ../permission-service/gradle/libs.versions.toml
- ../session-gateway/gradle/libs.versions.toml

Options:
  --dry-run        Print the files that would change without editing them.
  --validate-only Verify every target already uses <target-version>.
  -h, --help      Show this help text.

Accepted version format:
- MAJOR.MINOR.PATCH
- MAJOR.MINOR.PATCH-SNAPSHOT

Examples:
- ./scripts/repo/update-service-common-version.sh --dry-run 0.0.14-SNAPSHOT
- ./scripts/repo/update-service-common-version.sh 0.0.13
- ./scripts/repo/update-service-common-version.sh --validate-only 0.0.13
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -n "${TARGET_VERSION}" ]]; then
                    print_error "Only one target version may be provided."
                    usage
                    exit 1
                fi
                TARGET_VERSION="$1"
                ;;
        esac
        shift
    done

    if [[ -z "${TARGET_VERSION}" ]]; then
        print_error "Missing target version."
        usage
        exit 1
    fi

    if [[ ! "${TARGET_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-SNAPSHOT)?$ ]]; then
        print_error "Invalid target version: ${TARGET_VERSION}"
        echo "Expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-SNAPSHOT"
        exit 1
    fi
}

require_file() {
    local file_path="$1"

    if [[ ! -f "${file_path}" ]]; then
        print_error "Required file not found: ${file_path}"
        exit 1
    fi
}

service_common_build_file() {
    printf '%s/service-common/build.gradle.kts\n' "${PARENT_DIR}"
}

consumer_catalog_file() {
    local repo="$1"

    printf '%s/%s/gradle/libs.versions.toml\n' "${PARENT_DIR}" "${repo}"
}

display_path() {
    local file_path="$1"

    printf '../%s\n' "${file_path#"${PARENT_DIR}/"}"
}

read_gradle_version_literal() {
    local file_path="$1"

    awk '
        /^[[:space:]]*version[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$/ {
            value = $0
            sub(/^[[:space:]]*version[[:space:]]*=[[:space:]]*"/, "", value)
            sub(/"[[:space:]]*$/, "", value)
            print value
            count++
        }
        END {
            if (count != 1) {
                exit 1
            }
        }
    ' "${file_path}"
}

read_toml_service_common_version() {
    local file_path="$1"

    awk '
        /^[[:space:]]*serviceCommon[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$/ {
            value = $0
            sub(/^[[:space:]]*serviceCommon[[:space:]]*=[[:space:]]*"/, "", value)
            sub(/"[[:space:]]*$/, "", value)
            print value
            count++
        }
        END {
            if (count != 1) {
                exit 1
            }
        }
    ' "${file_path}"
}

replace_gradle_version_literal() {
    local file_path="$1"
    local temp_file
    local match_count=0

    temp_file="$(mktemp)"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^([[:space:]]*)version[[:space:]]*=[[:space:]]*\"[^\"]+\"([[:space:]]*)$ ]]; then
            printf '%sversion = "%s"%s\n' "${BASH_REMATCH[1]}" "${TARGET_VERSION}" "${BASH_REMATCH[2]}" >> "${temp_file}"
            match_count=$((match_count + 1))
        else
            printf '%s\n' "${line}" >> "${temp_file}"
        fi
    done < "${file_path}"

    if [[ ${match_count} -ne 1 ]]; then
        rm -f "${temp_file}"
        print_error "Expected exactly one version literal in $(display_path "${file_path}"), found ${match_count}"
        exit 1
    fi

    apply_replacement "${file_path}" "${temp_file}"
}

replace_toml_service_common_version() {
    local file_path="$1"
    local temp_file
    local match_count=0

    temp_file="$(mktemp)"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^([[:space:]]*)serviceCommon[[:space:]]*=[[:space:]]*\"[^\"]+\"([[:space:]]*)$ ]]; then
            printf '%sserviceCommon = "%s"%s\n' "${BASH_REMATCH[1]}" "${TARGET_VERSION}" "${BASH_REMATCH[2]}" >> "${temp_file}"
            match_count=$((match_count + 1))
        else
            printf '%s\n' "${line}" >> "${temp_file}"
        fi
    done < "${file_path}"

    if [[ ${match_count} -ne 1 ]]; then
        rm -f "${temp_file}"
        print_error "Expected exactly one serviceCommon version entry in $(display_path "${file_path}"), found ${match_count}"
        exit 1
    fi

    apply_replacement "${file_path}" "${temp_file}"
}

apply_replacement() {
    local file_path="$1"
    local temp_file="$2"
    local shown_path

    shown_path="$(display_path "${file_path}")"

    if cmp -s "${file_path}" "${temp_file}"; then
        rm -f "${temp_file}"
        return 0
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        print_info "Would update ${shown_path}"
        rm -f "${temp_file}"
        CHANGED_FILES+=("${shown_path}")
        return 0
    fi

    mv "${temp_file}" "${file_path}"
    CHANGED_FILES+=("${shown_path}")
}

validate_versions() {
    local service_common_file
    local current_version
    local repo catalog_file
    local validation_failed=false

    service_common_file="$(service_common_build_file)"
    current_version="$(read_gradle_version_literal "${service_common_file}")" || {
        print_error "Expected exactly one version literal in $(display_path "${service_common_file}")"
        exit 1
    }

    if [[ "${current_version}" != "${TARGET_VERSION}" ]]; then
        print_error "$(display_path "${service_common_file}") is ${current_version}, expected ${TARGET_VERSION}"
        validation_failed=true
    fi

    for repo in "${JAVA_CONSUMER_REPOS[@]}"; do
        catalog_file="$(consumer_catalog_file "${repo}")"
        current_version="$(read_toml_service_common_version "${catalog_file}")" || {
            print_error "Expected exactly one serviceCommon version entry in $(display_path "${catalog_file}")"
            exit 1
        }

        if [[ "${current_version}" != "${TARGET_VERSION}" ]]; then
            print_error "$(display_path "${catalog_file}") is ${current_version}, expected ${TARGET_VERSION}"
            validation_failed=true
        fi
    done

    if [[ "${validation_failed}" == true ]]; then
        exit 1
    fi
}

print_targets() {
    local repo

    print_info "Target service-common version: ${TARGET_VERSION}"
    echo "Targets:"
    echo "- $(display_path "$(service_common_build_file)")"
    for repo in "${JAVA_CONSUMER_REPOS[@]}"; do
        echo "- $(display_path "$(consumer_catalog_file "${repo}")")"
    done
}

main() {
    local repo

    parse_args "$@"

    require_file "$(service_common_build_file)"
    for repo in "${JAVA_CONSUMER_REPOS[@]}"; do
        require_file "$(consumer_catalog_file "${repo}")"
    done

    print_targets

    if [[ "${VALIDATE_ONLY}" == true ]]; then
        validate_versions
        print_success "All service-common version references already match ${TARGET_VERSION}"
        exit 0
    fi

    replace_gradle_version_literal "$(service_common_build_file)"
    for repo in "${JAVA_CONSUMER_REPOS[@]}"; do
        replace_toml_service_common_version "$(consumer_catalog_file "${repo}")"
    done

    if [[ "${DRY_RUN}" == false ]]; then
        validate_versions
        print_success "Updated service-common version references to ${TARGET_VERSION}"
    else
        print_success "Dry run completed for service-common version ${TARGET_VERSION}"
    fi

    if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
        echo "No files changed."
        exit 0
    fi

    echo "Changed files:"
    for changed_file in "${CHANGED_FILES[@]}"; do
        echo "- ${changed_file}"
    done
}

main "$@"
