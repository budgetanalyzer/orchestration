#!/usr/bin/env bash
# Local live-cluster smoke test dispatcher.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PHASE7_ARGS=()
OBSERVABILITY_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/smoketest.sh [options]

Runs the local live-cluster validation sequence:
  1. ./scripts/guardrails/verify-phase-7-static-manifests.sh
  2. ./scripts/smoketest/verify-security-prereqs.sh
  3. ./scripts/smoketest/verify-clean-tilt-deployment-admission.sh
  4. ./scripts/smoketest/verify-monitoring-rendered-manifests.sh
  5. ./scripts/smoketest/verify-istio-tracing-config.sh
  6. ./scripts/smoketest/verify-monitoring-runtime.sh
  7. ./scripts/smoketest/verify-observability-port-forward-access.sh
  8. ./scripts/smoketest/verify-session-architecture-phase-5.sh
  9. ./scripts/smoketest/verify-phase-7-security-guardrails.sh

Options:
  --observability-grafana-port <port>
      Pass through to verify-observability-port-forward-access.sh.
  --observability-prometheus-port <port>
      Pass through to verify-observability-port-forward-access.sh.
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
        --observability-grafana-port)
            require_value "$1" "${2:-}"
            OBSERVABILITY_ARGS+=("--grafana-port" "$2")
            shift 2
            ;;
        --observability-prometheus-port)
            require_value "$1" "${2:-}"
            OBSERVABILITY_ARGS+=("--prometheus-port" "$2")
            shift 2
            ;;
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

run_step "Static security manifest guardrails" \
    "${REPO_DIR}/scripts/guardrails/verify-phase-7-static-manifests.sh"
run_step "Platform security baseline" \
    "${REPO_DIR}/scripts/smoketest/verify-security-prereqs.sh"
run_step "Clean Tilt deployment admission" \
    "${REPO_DIR}/scripts/smoketest/verify-clean-tilt-deployment-admission.sh"
run_step "Rendered monitoring manifests" \
    "${SCRIPT_DIR}/verify-monitoring-rendered-manifests.sh"
run_step "Istio tracing configuration" \
    "${SCRIPT_DIR}/verify-istio-tracing-config.sh"
run_step "Monitoring runtime" \
    "${SCRIPT_DIR}/verify-monitoring-runtime.sh"
run_step "Observability port-forward access" \
    "${SCRIPT_DIR}/verify-observability-port-forward-access.sh" "${OBSERVABILITY_ARGS[@]}"
run_step "Shared session contract" \
    "${SCRIPT_DIR}/verify-session-architecture-phase-5.sh"
run_step "Security guardrails" \
    "${REPO_DIR}/scripts/smoketest/verify-phase-7-security-guardrails.sh" "${PHASE7_ARGS[@]}"

printf '\nSmoketest passed.\n'
