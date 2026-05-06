#!/usr/bin/env bash
# Verifies that Tilt resources without resource_deps are intentional roots.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_DIR="$(cd "${REPO_DIR}/.." && pwd)"
ALLOWLIST_FILE="${SCRIPT_DIR}/../lib/tilt-intentional-root-resources.txt"
KUBE_CONTEXT="kind-kind"
REQUIRED_SIBLING_PATHS=(
    "budget-analyzer-web/Dockerfile"
    "currency-service/build.gradle.kts"
    "permission-service/build.gradle.kts"
    "service-common/build.gradle.kts"
    "session-gateway/build.gradle.kts"
    "transaction-service/build.gradle.kts"
)

usage() {
    cat <<'EOF'
Usage: scripts/guardrails/check-tilt-resource-roots.sh [--context <kubectl-context>]

Evaluates the Tiltfile and compares resources with empty resource_deps to the
checked-in intentional-root allowlist.
EOF
}

require_command() {
    local command_name="$1"

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
}

load_allowlist() {
    if [[ ! -f "${ALLOWLIST_FILE}" ]]; then
        printf 'ERROR: missing Tilt root allowlist: %s\n' "${ALLOWLIST_FILE}" >&2
        exit 1
    fi

    grep -Ev '^[[:space:]]*(#|$)' "${ALLOWLIST_FILE}" | sort -u
}

find_duplicate_allowlist_entries() {
    grep -Ev '^[[:space:]]*(#|$)' "${ALLOWLIST_FILE}" | sort | uniq -d
}

check_workspace_siblings() {
    local relative_path
    local -a missing=()

    for relative_path in "${REQUIRED_SIBLING_PATHS[@]}"; do
        if [[ ! -e "${WORKSPACE_DIR}/${relative_path}" ]]; then
            missing+=("${relative_path}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        printf 'ERROR: Tiltfile evaluation requires the standard side-by-side workspace checkout.\n' >&2
        printf 'Missing sibling repo paths under %s:\n' "${WORKSPACE_DIR}" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context)
            if [[ -z "${2:-}" ]]; then
                echo 'ERROR: --context requires a value' >&2
                usage >&2
                exit 1
            fi
            KUBE_CONTEXT="$2"
            shift 2
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

require_command tilt
require_command jq
check_workspace_siblings

duplicates="$(find_duplicate_allowlist_entries)"
if [[ -n "${duplicates}" ]]; then
    printf 'ERROR: duplicate Tilt root allowlist entries:\n' >&2
    while IFS= read -r duplicate; do
        printf '  - %s\n' "${duplicate}" >&2
    done <<< "${duplicates}"
    exit 1
fi

expected_file="$(mktemp)"
actual_file="$(mktemp)"
unexpected_file="$(mktemp)"
missing_file="$(mktemp)"
tilt_result_file="$(mktemp)"

cleanup() {
    rm -f "${expected_file}" "${actual_file}" "${unexpected_file}" "${missing_file}" "${tilt_result_file}"
}
trap cleanup EXIT

load_allowlist > "${expected_file}"

(
    cd "${REPO_DIR}"
    tilt alpha tiltfile-result --context "${KUBE_CONTEXT}" > "${tilt_result_file}"
)

jq -r '.Manifests[] | select((.ResourceDependencies // []) | length == 0) | .Name' \
    "${tilt_result_file}" | sort -u > "${actual_file}"

comm -13 "${expected_file}" "${actual_file}" > "${unexpected_file}"
comm -23 "${expected_file}" "${actual_file}" > "${missing_file}"

if [[ -s "${unexpected_file}" ]]; then
    printf 'Unexpected Tilt root resources found:\n' >&2
    sed 's/^/  - /' "${unexpected_file}" >&2
fi

if [[ -s "${missing_file}" ]]; then
    printf 'Expected Tilt root resources were not roots:\n' >&2
    sed 's/^/  - /' "${missing_file}" >&2
fi

if [[ -s "${unexpected_file}" || -s "${missing_file}" ]]; then
    exit 1
fi

printf 'Tilt resource root allowlist passed (%s roots checked)\n' "$(wc -l < "${actual_file}" | tr -d ' ')"
