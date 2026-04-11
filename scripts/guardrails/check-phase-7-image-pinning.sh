#!/usr/bin/env bash

# check-phase-7-image-pinning.sh
#
# Static verification for Phase 7 Session 2 image pinning. This is scoped to
# orchestration-owned active assets plus the retained DinD test assets frozen by
# the Phase 7 Session 1 contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TARGET_LIST_FILE="${SCRIPT_DIR}/../lib/phase-7-image-pinning-targets.txt"
ALLOWED_LATEST_FILE="${SCRIPT_DIR}/../lib/phase-7-allowed-latest.txt"

TARGET_FILES=()
ALLOWED_LATEST_REFS=()
APPROVED_LOCAL_REPOS=()

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

build_approved_local_repo_inventory() {
    local ref repo
    local -A seen_repos=()
    local -a failures=()

    APPROVED_LOCAL_REPOS=()

    for ref in "${ALLOWED_LATEST_REFS[@]}"; do
        if [[ ! "${ref}" =~ ^([a-z0-9]+([._-][a-z0-9]+)*)\:latest$ ]]; then
            failures+=("unexpected approved-local ref format: ${ref}")
            continue
        fi

        repo="${BASH_REMATCH[1]}"
        if [[ -n "${seen_repos[${repo}]:-}" ]]; then
            failures+=("duplicate approved-local repo in ${ALLOWED_LATEST_FILE}: ${repo}")
            continue
        fi

        seen_repos["${repo}"]=1
        APPROVED_LOCAL_REPOS+=("${repo}")
    done

    if (( ${#APPROVED_LOCAL_REPOS[@]} == 0 )); then
        failures+=("no approved local repos were loaded from ${ALLOWED_LATEST_FILE}")
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'ERROR: approved local image contract is invalid:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        exit 1
    fi
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

search_image_refs() {
    local pattern='^[[:space:]]*image:[[:space:]]*|^[[:space:]]*FROM[[:space:]]+|^[A-Z0-9_]+IMAGE='

    if command -v rg >/dev/null 2>&1; then
        rg -n --no-heading "${pattern}" "${TARGET_FILES[@]}" || true
        return 0
    fi

    grep -nH -E --binary-files=without-match "${pattern}" "${TARGET_FILES[@]}" || true
}

extract_refs() {
    search_image_refs |
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

print_approved_local_repos() {
    printf '%s\n' "${APPROVED_LOCAL_REPOS[@]}"
}

print_approved_local_tilt_refs() {
    local repo
    local tilt_hash="0123456789abcdef"

    for repo in "${APPROVED_LOCAL_REPOS[@]}"; do
        printf '%s:tilt-%s\n' "${repo}" "${tilt_hash}"
        printf 'docker.io/library/%s:tilt-%s\n' "${repo}" "${tilt_hash}"
    done
}

usage() {
    cat <<'EOF'
Usage: scripts/guardrails/check-phase-7-image-pinning.sh [--print-approved-local-repos|--print-approved-local-tilt-refs]

Without flags, scans the Phase 7 image-pinning inventory for unexpected
checked-in :latest refs and missing third-party @sha256 digests.

Optional output modes:
  --print-approved-local-repos
      Print the approved local Tilt-built repo names derived from
      scripts/lib/phase-7-allowed-latest.txt.
  --print-approved-local-tilt-refs
      Print representative bare and docker.io/library Tilt deploy refs for the
      approved local repos using the contract hash pattern.
EOF
}

main() {
    local mode="scan"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --print-approved-local-repos)
                mode="repos"
                shift
                ;;
            --print-approved-local-tilt-refs)
                mode="tilt-refs"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'ERROR: unknown argument: %s\n' "$1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done

    cd "${REPO_DIR}"
    load_inventory
    build_approved_local_repo_inventory
    check_target_files_exist

    case "${mode}" in
        repos)
            print_approved_local_repos
            return 0
            ;;
        tilt-refs)
            print_approved_local_tilt_refs
            return 0
            ;;
    esac

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
