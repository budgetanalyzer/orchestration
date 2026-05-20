#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_INVENTORY="${REPO_ROOT}/kubernetes/production/apps/image-inventory.yaml"

EXPECTED_VERSION=""
INVENTORY_PATH="${DEFAULT_INVENTORY}"
STRICT=false
TRACKED_ONLY=false

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/show-pod-version-labels.sh [options]

Lists pod release labels for the current Kubernetes context and warns when
Budget Analyzer runtime pods do not match the expected release version.

Options:
  --expected-version VERSION  Expected app.kubernetes.io/version value. Accepts
                              X.Y.Z or vX.Y.Z; comparison uses X.Y.Z.
  --inventory PATH            Image inventory to read release-version from.
                              Default: kubernetes/production/apps/image-inventory.yaml
  --tracked-only              Print only Budget Analyzer runtime pods.
  --strict                    Exit non-zero when warnings are found.
  -h, --help                  Show this help text.

Examples:
  ./scripts/ops/show-pod-version-labels.sh
  ./scripts/ops/show-pod-version-labels.sh --expected-version 0.0.14 --strict
  ./scripts/ops/show-pod-version-labels.sh --tracked-only
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

read_inventory_version() {
    local inventory="$1"

    [[ -f "${inventory}" ]] || return 0

    awk '
        $1 == "release-version:" {
            value = $2
            gsub(/"/, "", value)
            print value
            exit
        }
    ' "${inventory}"
}

is_tracked_app() {
    case "$1" in
        transaction-service|currency-service|permission-service|session-gateway|budget-analyzer-web|nginx-gateway|ext-authz)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

normalize_label_version() {
    local version="$1"

    printf '%s\n' "${version#v}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --expected-version)
                EXPECTED_VERSION="${2:-}"
                [[ -n "${EXPECTED_VERSION}" ]] || {
                    printf 'ERROR: missing value for --expected-version\n' >&2
                    exit 1
                }
                shift
                ;;
            --inventory)
                INVENTORY_PATH="${2:-}"
                [[ -n "${INVENTORY_PATH}" ]] || {
                    printf 'ERROR: missing value for --inventory\n' >&2
                    exit 1
                }
                shift
                ;;
            --tracked-only)
                TRACKED_ONLY=true
                ;;
            --strict)
                STRICT=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'ERROR: unknown option: %s\n' "$1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    local expected_label_version
    local pod_template
    local pod_rows
    local namespace pod app version part_of images
    local status tracked
    local warning_count=0
    local printed_count=0

    parse_args "$@"
    require_command kubectl

    if [[ -z "${EXPECTED_VERSION}" ]]; then
        EXPECTED_VERSION="$(read_inventory_version "${INVENTORY_PATH}")"
    fi
    expected_label_version="$(normalize_label_version "${EXPECTED_VERSION}")"

    if [[ -z "${expected_label_version}" ]]; then
        printf 'WARNING: no expected version supplied and no release-version found in %s; mismatch checks disabled.\n' \
            "${INVENTORY_PATH}" >&2
    else
        printf 'Expected app.kubernetes.io/version: %s\n' "${expected_label_version}"
    fi

    printf '%-10s %-16s %-52s %-24s %-12s %-18s %s\n' \
        "STATUS" "NAMESPACE" "POD" "APP" "VERSION" "PART-OF" "IMAGES"

    # shellcheck disable=SC2016 # Go template variables must remain literal for kubectl.
    pod_template='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{index .metadata.labels "app"}}{{"\t"}}{{index .metadata.labels "app.kubernetes.io/version"}}{{"\t"}}{{index .metadata.labels "app.kubernetes.io/part-of"}}{{"\t"}}{{range $index, $container := .spec.containers}}{{if $index}},{{end}}{{$container.image}}{{end}}{{"\n"}}{{end}}'
    pod_rows="$(kubectl get pods -A -o "go-template=${pod_template}")"

    while IFS=$'\t' read -r namespace pod app version part_of images; do
        [[ -n "${namespace}" ]] || continue

        tracked=false
        if is_tracked_app "${app}" || [[ "${part_of}" == "budget-analyzer" ]]; then
            tracked=true
        fi

        if [[ "${TRACKED_ONLY}" == true && "${tracked}" != true ]]; then
            continue
        fi

        status="OK"
        if [[ "${tracked}" == true && -n "${expected_label_version}" ]]; then
            if [[ -z "${version}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                printf 'WARNING: %s/%s is missing app.kubernetes.io/version; expected %s\n' \
                    "${namespace}" "${pod}" "${expected_label_version}" >&2
            elif [[ "${version}" != "${expected_label_version}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                printf 'WARNING: %s/%s has app.kubernetes.io/version=%s; expected %s\n' \
                    "${namespace}" "${pod}" "${version}" "${expected_label_version}" >&2
            fi
        elif [[ "${tracked}" != true ]]; then
            status="INFO"
        fi

        printf '%-10s %-16s %-52s %-24s %-12s %-18s %s\n' \
            "${status}" "${namespace}" "${pod}" "${app:-<none>}" "${version:-<none>}" "${part_of:-<none>}" "${images:-<none>}"
        printed_count=$((printed_count + 1))
    done <<< "${pod_rows}"

    printf '\nPrinted pods: %s\n' "${printed_count}"
    printf 'Warnings: %s\n' "${warning_count}"

    if [[ "${STRICT}" == true && "${warning_count}" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
