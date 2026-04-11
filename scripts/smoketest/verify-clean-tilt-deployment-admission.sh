#!/usr/bin/env bash
# Post-tilt clean-start admission proof for the app workloads in default.

set -euo pipefail

DEFAULT_NAMESPACE="default"
WAIT_SECONDS="${PHASE7_CLEAN_TILT_WAIT_SECONDS:-600}"
EVENT_TAIL="${PHASE7_CLEAN_TILT_EVENT_TAIL:-100}"
EXPECTED_DEPLOYMENTS=(
    budget-analyzer-web
    currency-service
    ext-authz
    nginx-gateway
    permission-service
    session-gateway
    transaction-service
)

usage() {
    cat <<'EOF'
Usage: scripts/smoketest/verify-clean-tilt-deployment-admission.sh [--wait-seconds <n>] [--event-tail <n>]

Run this from the host after:
  1. ./setup.sh
  2. tilt up

The verifier waits for the seven expected app deployments in the default
namespace, checks their rollouts, prints deployment/pod/event summaries, and
fails if Kyverno reports phase7-require-third-party-image-digests violations in
default.
EOF
}

section() {
    printf '\n==> %s\n' "$1"
}

wait_for_expected_deployments() {
    local waited=0
    local -a missing=()
    local deployment

    while (( waited < WAIT_SECONDS )); do
        missing=()
        for deployment in "${EXPECTED_DEPLOYMENTS[@]}"; do
            if ! kubectl get deployment "${deployment}" -n "${DEFAULT_NAMESPACE}" >/dev/null 2>&1; then
                missing+=("${deployment}")
            fi
        done

        if (( ${#missing[@]} == 0 )); then
            return 0
        fi

        sleep 5
        waited=$((waited + 5))
    done

    printf 'ERROR: expected default-namespace deployments were not all created within %ss:\n' "${WAIT_SECONDS}" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    printf '\nCurrent deployments in %s:\n' "${DEFAULT_NAMESPACE}" >&2
    kubectl get deploy -n "${DEFAULT_NAMESPACE}" >&2 || true
    exit 1
}

wait_for_rollouts() {
    local deployment

    for deployment in "${EXPECTED_DEPLOYMENTS[@]}"; do
        printf 'Waiting for deployment/%s rollout...\n' "${deployment}"
        kubectl rollout status "deployment/${deployment}" -n "${DEFAULT_NAMESPACE}" --timeout="${WAIT_SECONDS}s"
    done
}

print_events_tail() {
    kubectl get events -n "${DEFAULT_NAMESPACE}" --sort-by=.lastTimestamp | tail -n "${EVENT_TAIL}"
}

check_for_policy_violations() {
    local violations

    violations="$(kubectl get events -n "${DEFAULT_NAMESPACE}" --sort-by=.lastTimestamp 2>/dev/null | grep 'PolicyViolation' | grep 'phase7-require-third-party-image-digests' || true)"
    if [[ -n "${violations}" ]]; then
        printf 'ERROR: Kyverno phase7-require-third-party-image-digests violations remain in %s:\n' "${DEFAULT_NAMESPACE}" >&2
        printf '%s\n' "${violations}" >&2
        exit 1
    fi
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --wait-seconds)
                if [[ $# -lt 2 ]]; then
                    printf 'ERROR: --wait-seconds requires a numeric argument\n' >&2
                    exit 1
                fi
                WAIT_SECONDS="$2"
                shift 2
                ;;
            --event-tail)
                if [[ $# -lt 2 ]]; then
                    printf 'ERROR: --event-tail requires a numeric argument\n' >&2
                    exit 1
                fi
                EVENT_TAIL="$2"
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

    section "Waiting For Deployments"
    wait_for_expected_deployments

    section "Waiting For Rollouts"
    wait_for_rollouts

    section "Deployment Summary"
    kubectl get deploy -n "${DEFAULT_NAMESPACE}"

    section "Pod Summary"
    kubectl get pods -n "${DEFAULT_NAMESPACE}"

    section "Recent Events"
    print_events_tail

    check_for_policy_violations

    printf '\nClean Tilt deployment admission verification passed.\n'
}

main "$@"
