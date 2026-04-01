#!/usr/bin/env bash
# Verifies that Tilt-generated Kubernetes secrets carry only allowed secret keys.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TILTFILE="${REPO_DIR}/Tiltfile"
INVENTORY_FILE="${SCRIPT_DIR}/lib/secrets-only-expected-keys.txt"

usage() {
    cat <<'EOF'
Usage: ./scripts/dev/check-secrets-only-handling.sh

Checks the Tilt-generated secret payload inventory against the checked-in
allowed key list. Fails if a secret gains an undocumented key or if an
inventory entry no longer exists in the Tiltfile.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -f "${TILTFILE}" ]]; then
    printf 'ERROR: missing Tiltfile: %s\n' "${TILTFILE}" >&2
    exit 1
fi

if [[ ! -f "${INVENTORY_FILE}" ]]; then
    printf 'ERROR: missing inventory file: %s\n' "${INVENTORY_FILE}" >&2
    exit 1
fi

declare -A allowed_keys=()
declare -A allowed_notes=()
declare -A actual_keys=()
unexpected=()
missing=()

while IFS=$'\t' read -r secret_name key classification note; do
    [[ -n "${secret_name}" ]] || continue
    [[ "${secret_name}" == \#* ]] && continue
    allowed_keys["${secret_name}|${key}"]="${classification}"
    allowed_notes["${secret_name}|${key}"]="${note}"
done < "${INVENTORY_FILE}"

current_secret=""
in_secret=0
while IFS= read -r line; do
    if [[ "${line}" =~ create_secret\(\'([^\']+)\'[[:space:]]*, ]]; then
        current_secret="${BASH_REMATCH[1]}"
        in_secret=1
        continue
    fi

    if (( in_secret == 1 )) && [[ "${line}" =~ ^[[:space:]]*\'([^\']+)\'[[:space:]]*: ]]; then
        actual_keys["${current_secret}|${BASH_REMATCH[1]}"]=1
        continue
    fi

    if (( in_secret == 1 )) && [[ "${line}" =~ ^[[:space:]]*}\)[[:space:]]*$ ]]; then
        current_secret=""
        in_secret=0
    fi
done < "${TILTFILE}"

for secret_key in "${!actual_keys[@]}"; do
    if [[ -z "${allowed_keys[${secret_key}]:-}" ]]; then
        unexpected+=("${secret_key}")
    fi
done

for secret_key in "${!allowed_keys[@]}"; do
    if [[ -z "${actual_keys[${secret_key}]:-}" ]]; then
        missing+=("${secret_key}")
    fi
done

if (( ${#unexpected[@]} > 0 )); then
    printf 'Unexpected Tilt secret keys found:\n' >&2
    printf '  - %s\n' "${unexpected[@]}" >&2
fi

if (( ${#missing[@]} > 0 )); then
    printf 'Inventory entries missing from Tiltfile:\n' >&2
    printf '  - %s\n' "${missing[@]}" >&2
fi

if (( ${#unexpected[@]} > 0 || ${#missing[@]} > 0 )); then
    exit 1
fi

printf 'Secrets-only handling inventory passed'
if grep -Fq $'\tmixed_required\t' "${INVENTORY_FILE}"; then
    printf ' (includes documented mixed-required payloads:'
    while IFS=$'\t' read -r secret_name key classification note; do
        [[ "${classification}" == "mixed_required" ]] || continue
        printf ' %s[%s]' "${secret_name}" "${key}"
    done < "${INVENTORY_FILE}"
    printf ' )'
fi
printf '\n'
