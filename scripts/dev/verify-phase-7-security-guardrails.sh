#!/usr/bin/env bash
# Final local Phase 7 completion gate. Runs the static guardrail suite first,
# then the live-cluster runtime guardrail proof.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATIC_GATE="${REPO_DIR}/scripts/dev/verify-phase-7-static-manifests.sh"
RUNTIME_GATE="${REPO_DIR}/scripts/dev/verify-phase-7-runtime-guardrails.sh"

runtime_wait_timeout="${PHASE7_WAIT_TIMEOUT:-}"
runtime_regression_timeout="${PHASE7_REGRESSION_TIMEOUT:-}"

usage() {
    cat <<'EOF'
Usage: ./scripts/dev/verify-phase-7-security-guardrails.sh [options]

Runs the local final Phase 7 completion gate in this order:
  1. ./scripts/dev/verify-phase-7-static-manifests.sh
  2. ./scripts/dev/verify-phase-7-runtime-guardrails.sh

Options:
  --runtime-wait-timeout <duration>
      Override PHASE7_WAIT_TIMEOUT for the runtime verifier only.
  --runtime-regression-timeout <duration>
      Override PHASE7_REGRESSION_TIMEOUT for the runtime verifier only.
  -h, --help
      Show this help text.

Environment:
  PHASE7_WAIT_TIMEOUT
      Default runtime probe readiness timeout to pass to the runtime verifier.
  PHASE7_REGRESSION_TIMEOUT
      Default runtime regression umbrella timeout to pass to the runtime verifier.

Notes:
  - This is the local Phase 7 completion command.
  - CI remains intentionally static-only via
    ./scripts/dev/verify-phase-7-static-manifests.sh.
EOF
}

section() {
    printf '\n=== %s ===\n' "$1"
}

require_value() {
    local flag_name="$1"
    local value="${2:-}"

    if [[ -z "${value}" ]]; then
        printf 'ERROR: %s requires a value\n' "${flag_name}" >&2
        usage >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime-wait-timeout)
            require_value "$1" "${2:-}"
            runtime_wait_timeout="$2"
            shift 2
            ;;
        --runtime-regression-timeout)
            require_value "$1" "${2:-}"
            runtime_regression_timeout="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ ! -x "${STATIC_GATE}" ]]; then
    printf 'ERROR: static Phase 7 gate is missing or not executable: %s\n' "${STATIC_GATE}" >&2
    exit 1
fi

if [[ ! -x "${RUNTIME_GATE}" ]]; then
    printf 'ERROR: runtime Phase 7 gate is missing or not executable: %s\n' "${RUNTIME_GATE}" >&2
    exit 1
fi

section "Phase 7 Static Guardrails"
"${STATIC_GATE}"

section "Phase 7 Runtime Guardrails"
PHASE7_WAIT_TIMEOUT="${runtime_wait_timeout}" \
PHASE7_REGRESSION_TIMEOUT="${runtime_regression_timeout}" \
    "${RUNTIME_GATE}"

section "Phase 7 Final Gate"
printf 'Phase 7 static and runtime guardrails passed.\n'
