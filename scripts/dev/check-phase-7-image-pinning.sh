#!/usr/bin/env bash

# check-phase-7-image-pinning.sh
#
# Static verification for Phase 7 Session 2 image pinning. This is scoped to
# orchestration-owned active assets plus the retained DinD test assets frozen by
# the Phase 7 Session 1 contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET_LIST_FILE="${SCRIPT_DIR}/lib/phase-7-image-pinning-targets.txt"
ALLOWED_LATEST_FILE="${SCRIPT_DIR}/lib/phase-7-allowed-latest.txt"

TARGET_FILES=()
ALLOWED_LATEST_REFS=()

declare -A ALLOWED_LATEST=()

load_list_file() {
    local list_file="$1"
    local -n output_ref="$2"

    if [[ ! -f "${list_file}" ]]; then
        printf 'ERROR: required list file not found: %s\n' "${list_file}" >&2
        exit 1
    fi

    mapfile -t output_ref < <(grep -Ev '^[[:space:]]*(#|$)' "${list_file}")
    if (( ${#output_ref[@]} == 0 )); then
        printf 'ERROR: required list file is empty: %s\n' "${list_file}" >&2
        exit 1
    fi
}

load_inventory() {
    local ref

    load_list_file "${TARGET_LIST_FILE}" TARGET_FILES
    load_list_file "${ALLOWED_LATEST_FILE}" ALLOWED_LATEST_REFS

    for ref in "${ALLOWED_LATEST_REFS[@]}"; do
        ALLOWED_LATEST["$ref"]=1
    done
}

check_target_files_exist() {
    local file
    local -a missing=()

    for file in "${TARGET_FILES[@]}"; do
        if [[ ! -e "${file}" ]]; then
            missing+=("${file}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        printf 'ERROR: Phase 7 image pinning target list references missing files:\n' >&2
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi
}

extract_refs() {
    rg -n --no-heading '^[[:space:]]*image:[[:space:]]*|^[[:space:]]*FROM[[:space:]]+|^[A-Z0-9_]+IMAGE=' "${TARGET_FILES[@]}" |
        while IFS= read -r match; do
            local file="${match%%:*}"
            local remainder="${match#*:}"
            local line="${remainder%%:*}"
            local text="${remainder#*:}"
            local ref=""

            if [[ "$text" =~ ^[[:space:]]*image:[[:space:]]* ]]; then
                ref="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*image:[[:space:]]*([^[:space:]]+).*/\1/')"
            elif [[ "$text" =~ ^[[:space:]]*FROM[[:space:]]+ ]]; then
                ref="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*FROM[[:space:]]+([^[:space:]]+).*/\1/')"
            else
                ref="$(printf '%s' "$text" | sed -E 's/^[A-Z0-9_]+IMAGE="?([^"[:space:]]+)"?.*/\1/')"
            fi

            printf '%s\t%s\t%s\n' "$file" "$line" "$ref"
        done
}

main() {
    cd "${REPO_DIR}"
    load_inventory
    check_target_files_exist

    local refs_checked=0
    local -a failures=()

    while IFS=$'\t' read -r file line ref; do
        [[ -n "${ref}" ]] || continue
        refs_checked=$((refs_checked + 1))

        if [[ "${ref}" == \$\{* ]]; then
            continue
        fi

        if [[ -n "${ALLOWED_LATEST[$ref]:-}" ]]; then
            continue
        fi

        if [[ "${ref}" == *":latest"* ]]; then
            failures+=("${file}:${line}: unexpected :latest image ref: ${ref}")
            continue
        fi

        if [[ "${ref}" =~ @sha256:[0-9a-f]{64}$ ]]; then
            continue
        fi

        failures+=("${file}:${line}: missing @sha256 digest: ${ref}")
    done < <(extract_refs)

    if (( refs_checked == 0 )); then
        printf 'ERROR: no image references were discovered in the Phase 7 target set\n' >&2
        exit 1
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'Phase 7 image pinning check failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        exit 1
    fi

    printf 'Phase 7 image pinning check passed (%d refs checked)\n' "${refs_checked}"
}

main "$@"
