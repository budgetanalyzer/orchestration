#!/usr/bin/env bash
# Local live-cluster smoke test dispatcher.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PHASE7_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/smoketest.sh [options]

Runs the local live-cluster validation sequence:
  1. ./scripts/guardrails/verify-phase-7-static-manifests.sh
  2. ./scripts/smoketest/verify-security-prereqs.sh
  3. ./scripts/smoketest/verify-clean-tilt-deployment-admission.sh
  4. ./scripts/smoketest/verify-monitoring-rendered-manifests.sh
  5. ./scripts/smoketest/verify-monitoring-runtime.sh
  6. ./scripts/smoketest/verify-session-architecture-phase-5.sh
  7. ./scripts/smoketest/verify-phase-7-security-guardrails.sh

Options:
  --runtime-wait-timeout <duration>
      Pass through to verify-phase-7-security-guardrails.sh.
  --runtime-regression-timeout <duration>
      Pass through to verify-phase-7-security-guardrails.sh.
  -h, --help
      Show this help text.
EOF
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
        --runtime-wait-timeout|--runtime-regression-timeout)
            require_value "$1" "${2:-}"
            PHASE7_ARGS+=("$1" "$2")
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

run_step() {
    local label="$1"
    shift

    printf '\n=== %s ===\n' "${label}"
    "$@"
}

run_step "Phase 7 static manifest guardrails" \
    "${REPO_DIR}/scripts/guardrails/verify-phase-7-static-manifests.sh"
run_step "Phase 0 platform baseline" \
    "${REPO_DIR}/scripts/smoketest/verify-security-prereqs.sh"
run_step "Clean Tilt deployment admission" \
    "${REPO_DIR}/scripts/smoketest/verify-clean-tilt-deployment-admission.sh"
run_step "Rendered monitoring manifests" \
    "${SCRIPT_DIR}/verify-monitoring-rendered-manifests.sh"
run_step "Monitoring runtime" \
    "${SCRIPT_DIR}/verify-monitoring-runtime.sh"
run_step "Session architecture Phase 5" \
    "${SCRIPT_DIR}/verify-session-architecture-phase-5.sh"
run_step "Phase 7 security guardrails" \
    "${REPO_DIR}/scripts/smoketest/verify-phase-7-security-guardrails.sh" "${PHASE7_ARGS[@]}"

printf '\nSmoketest passed.\n'
