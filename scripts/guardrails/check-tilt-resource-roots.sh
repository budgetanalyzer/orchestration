#!/usr/bin/env bash
# Verifies Tilt root resources and critical startup dependencies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_DIR="$(cd "${REPO_DIR}/.." && pwd)"
ALLOWLIST_FILE="${SCRIPT_DIR}/../lib/tilt-intentional-root-resources.txt"
KUBE_CONTEXT="kind-kind"
REQUIRED_SIBLING_PATHS=(
    "budget-analyzer-web/Dockerfile"
    "currency-service/build.gradle.kts"
    "ext-authz/Dockerfile"
    "permission-service/build.gradle.kts"
    "service-common/build.gradle.kts"
    "session-gateway/build.gradle.kts"
    "transaction-service/build.gradle.kts"
)

usage() {
    cat <<'EOF'
Usage: scripts/guardrails/check-tilt-resource-roots.sh [--context <kubectl-context>]

Evaluates the Tiltfile and compares resources with empty resource_deps to the
checked-in intentional-root allowlist. Also verifies that Tilt reconciles
existing ingress TLS files without invoking certificate generation or trust
installation, and that infrastructure startup waits for Kyverno readiness.
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

if ! jq -e '
    [.Manifests[] | select(.Name == "ingress-tls-secret")] | length == 1
' "${tilt_result_file}" >/dev/null; then
    printf 'ERROR: expected exactly one ingress-tls-secret Tilt resource.\n' >&2
    exit 1
fi

if ! jq -e '
    .Manifests[]
    | select(.Name == "ingress-tls-secret")
    | .DeployTarget.UpdateCmdSpec.args
        == ["sh", "-c", "./scripts/bootstrap/install-imported-ingress-tls.sh"]
      and .ResourceDependencies == ["kind-node-inotify-budget"]
' "${tilt_result_file}" >/dev/null; then
    printf 'ERROR: ingress-tls-secret must use the guarded non-generating installer after the Kind prerequisite.\n' >&2
    exit 1
fi

if ! jq -e '
    .Manifests[]
    | select(.Name == "infra-tls-prerequisites")
    | (.ResourceDependencies | sort)
        == ["infrastructure-namespace", "kyverno-ready"]
' "${tilt_result_file}" >/dev/null; then
    printf 'ERROR: infrastructure setup must wait for both its namespace and Kyverno readiness.\n' >&2
    exit 1
fi

for infrastructure_resource in postgresql redis rabbitmq; do
    if ! jq -e --arg name "${infrastructure_resource}" '
        .Manifests[]
        | select(.Name == $name)
        | .ResourceDependencies == ["infra-tls-prerequisites"]
    ' "${tilt_result_file}" >/dev/null; then
        printf 'ERROR: %s must inherit the Kyverno readiness gate through infra-tls-prerequisites.\n' \
            "${infrastructure_resource}" >&2
        exit 1
    fi
done

if jq -e '
    .Manifests[]
    | .DeployTarget.UpdateCmdSpec.args[]?
    | select(
        contains("setup-k8s-tls.sh")
        or contains("renew-host-ingress-tls.sh")
        or contains("install-agent-vm-local-ca-trust.sh")
        or contains("--install-system-trust")
      )
' "${tilt_result_file}" >/dev/null; then
    printf 'ERROR: Tilt must not generate browser TLS or install guest trust.\n' >&2
    exit 1
fi

printf 'Tilt resource root allowlist passed (%s roots checked)\n' "$(wc -l < "${actual_file}" | tr -d ' ')"
printf 'Tilt ingress TLS reconciliation guard passed\n'
printf 'Tilt infrastructure Kyverno readiness guard passed\n'
