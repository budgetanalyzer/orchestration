#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_INVENTORY="${REPO_ROOT}/kubernetes/production/apps/image-inventory.yaml"

EXPECTED_SOURCE="inventory"
EXPECTED_PATH="${DEFAULT_INVENTORY}"
STRICT=false
TRACKED_ONLY=false

SERVICE_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly SERVICE_ORDER

declare -A EXPECTED_IMAGE_REFS=()
declare -A EXPECTED_ARTIFACT_VERSIONS=()
declare -A EXPECTED_SOURCE_REFS=()
declare -A EXPECTED_SOURCE_COMMITS=()
declare -A EXPECTED_SERVICE_COMMON_VERSIONS=()

expected_deployment_id=""
expected_deployment_status=""

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/show-pod-version-labels.sh [options]

Lists Budget Analyzer pod deployment metadata for the current Kubernetes
context and verifies tracked runtime pods against a schema v2 deployment
manifest or the checked-in production image inventory.

Options:
  --deployment-manifest PATH  Schema v2 deployment manifest to verify against.
  --inventory PATH            Schema v2 image inventory to verify against.
                              Default: kubernetes/production/apps/image-inventory.yaml
  --tracked-only              Print only Budget Analyzer runtime pods.
  --strict                    Exit non-zero when warnings are found.
  -h, --help                  Show this help text.
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    }
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

manifest_value() {
    local file="$1"
    local key="$2"

    awk -v key="${key}" '
        function clean(value) {
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            return value
        }
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            value = $0
            sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
            print clean(value)
            exit
        }
    ' "${file}"
}

manifest_map_value() {
    local file="$1"
    local section="$2"
    local key="$3"

    awk -v section="${section}" -v key="${key}" '
        function clean(value) {
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            return value
        }
        $0 == section ":" {
            in_section = 1
            next
        }
        in_section && $0 ~ /^[^[:space:]][^:]*:/ {
            in_section = 0
        }
        in_section && index($0, "  " key ":") == 1 {
            value = $0
            sub("^  " key ":[[:space:]]*", "", value)
            print clean(value)
            exit
        }
    ' "${file}"
}

manifest_nested_value() {
    local file="$1"
    local section="$2"
    local item="$3"
    local key="$4"

    awk -v section="${section}" -v item="${item}" -v key="${key}" '
        function clean(value) {
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            return value
        }
        $0 == section ":" {
            in_section = 1
            next
        }
        in_section && $0 ~ /^[^[:space:]][^:]*:/ {
            in_section = 0
            in_item = 0
        }
        in_section && $0 == "  " item ":" {
            in_item = 1
            next
        }
        in_section && in_item && $0 ~ /^  [^[:space:]][^:]*:/ {
            in_item = 0
        }
        in_section && in_item && index($0, "    " key ":") == 1 {
            value = $0
            sub("^    " key ":[[:space:]]*", "", value)
            print clean(value)
            exit
        }
    ' "${file}"
}

inventory_value() {
    local file="$1"
    local key="$2"

    awk -v key="${key}" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            value = $0
            sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
        }
    ' "${file}"
}

is_tracked_app() {
    case "$1" in
        transaction-service|currency-service|permission-service|session-gateway|nginx-gateway|ext-authz)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

artifact_for_workload() {
    case "$1" in
        nginx-gateway)
            printf '%s\n' "budget-analyzer-web"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

load_expected_from_manifest() {
    local file="$1"
    local schema_version service value

    [[ -f "${file}" ]] || die "deployment manifest not found: ${file}"
    schema_version="$(manifest_value "${file}" "schema_version")"
    [[ "${schema_version}" == "2" ]] || die "deployment manifest must use schema_version: 2"

    expected_deployment_id="$(manifest_map_value "${file}" "deployment" "id")"
    expected_deployment_status="$(manifest_map_value "${file}" "deployment" "status")"
    [[ -n "${expected_deployment_id}" ]] || die "deployment manifest is missing deployment.id"
    [[ -n "${expected_deployment_status}" ]] || die "deployment manifest is missing deployment.status"

    for service in "${SERVICE_ORDER[@]}"; do
        value="$(manifest_nested_value "${file}" "artifacts" "${service}" "image")"
        [[ -n "${value}" ]] || die "deployment manifest is missing artifacts.${service}.image"
        EXPECTED_IMAGE_REFS["${service}"]="${value}"

        value="$(manifest_nested_value "${file}" "artifacts" "${service}" "artifact_version")"
        [[ -n "${value}" ]] || die "deployment manifest is missing artifacts.${service}.artifact_version"
        EXPECTED_ARTIFACT_VERSIONS["${service}"]="${value}"

        value="$(manifest_nested_value "${file}" "artifacts" "${service}" "source_ref")"
        [[ -n "${value}" ]] || die "deployment manifest is missing artifacts.${service}.source_ref"
        EXPECTED_SOURCE_REFS["${service}"]="${value}"

        value="$(manifest_nested_value "${file}" "artifacts" "${service}" "source_commit")"
        [[ -n "${value}" ]] || die "deployment manifest is missing artifacts.${service}.source_commit"
        EXPECTED_SOURCE_COMMITS["${service}"]="${value}"

        value="$(manifest_nested_value "${file}" "artifacts" "${service}" "service_common_version")"
        if [[ -n "${value}" ]]; then
            EXPECTED_SERVICE_COMMON_VERSIONS["${service}"]="${value}"
        fi
    done
}

load_expected_from_inventory() {
    local file="$1"
    local schema_version service value

    [[ -f "${file}" ]] || die "inventory not found: ${file}"
    schema_version="$(inventory_value "${file}" "schema-version")"
    [[ "${schema_version}" == "2" ]] || die "inventory must use schema-version: \"2\""

    expected_deployment_id="$(inventory_value "${file}" "deployment-id")"
    expected_deployment_status="$(inventory_value "${file}" "deployment-status")"
    [[ -n "${expected_deployment_id}" ]] || die "inventory is missing deployment-id"
    [[ -n "${expected_deployment_status}" ]] || die "inventory is missing deployment-status"

    for service in "${SERVICE_ORDER[@]}"; do
        value="$(inventory_value "${file}" "${service}")"
        [[ -n "${value}" ]] || die "inventory is missing ${service}"
        EXPECTED_IMAGE_REFS["${service}"]="${value}"

        value="$(inventory_value "${file}" "${service}.artifact-version")"
        [[ -n "${value}" ]] || die "inventory is missing ${service}.artifact-version"
        EXPECTED_ARTIFACT_VERSIONS["${service}"]="${value}"

        value="$(inventory_value "${file}" "${service}.source-ref")"
        [[ -n "${value}" ]] || die "inventory is missing ${service}.source-ref"
        EXPECTED_SOURCE_REFS["${service}"]="${value}"

        value="$(inventory_value "${file}" "${service}.source-commit")"
        [[ -n "${value}" ]] || die "inventory is missing ${service}.source-commit"
        EXPECTED_SOURCE_COMMITS["${service}"]="${value}"

        value="$(inventory_value "${file}" "${service}.service-common-version")"
        if [[ -n "${value}" ]]; then
            EXPECTED_SERVICE_COMMON_VERSIONS["${service}"]="${value}"
        fi
    done
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment-manifest)
                EXPECTED_SOURCE="manifest"
                EXPECTED_PATH="${2:-}"
                [[ -n "${EXPECTED_PATH}" ]] || die "missing value for --deployment-manifest"
                shift
                ;;
            --inventory)
                EXPECTED_SOURCE="inventory"
                EXPECTED_PATH="${2:-}"
                [[ -n "${EXPECTED_PATH}" ]] || die "missing value for --inventory"
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

    if [[ "${EXPECTED_PATH}" != /* && ! -f "${EXPECTED_PATH}" ]]; then
        EXPECTED_PATH="${REPO_ROOT}/${EXPECTED_PATH}"
    fi
}

warn_mismatch() {
    local message="$1"

    printf 'WARNING: %s\n' "${message}" >&2
}

main() {
    local pod_template pod_rows
    local namespace pod app app_name deployment_id app_version part_of image_annotation revision_annotation source_ref_annotation service_common_annotation images
    local workload artifact expected_service_common
    local status tracked
    local warning_count=0
    local printed_count=0

    parse_args "$@"
    require_command kubectl

    if [[ "${EXPECTED_SOURCE}" == "manifest" ]]; then
        load_expected_from_manifest "${EXPECTED_PATH}"
    else
        load_expected_from_inventory "${EXPECTED_PATH}"
    fi

    printf 'Expected deployment id: %s\n' "${expected_deployment_id}"
    printf 'Expected deployment status: %s\n' "${expected_deployment_status}"
    printf '%-10s %-16s %-52s %-24s %-20s %-12s %-18s %s\n' \
        "STATUS" "NAMESPACE" "POD" "APP" "DEPLOYMENT-ID" "VERSION" "PART-OF" "IMAGES"

    # shellcheck disable=SC2016 # Go template variables must remain literal for kubectl.
    pod_template='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{index .metadata.labels "app"}}{{"\t"}}{{index .metadata.labels "app.kubernetes.io/name"}}{{"\t"}}{{index .metadata.labels "budgetanalyzer.org/deployment-id"}}{{"\t"}}{{index .metadata.labels "app.kubernetes.io/version"}}{{"\t"}}{{index .metadata.labels "app.kubernetes.io/part-of"}}{{"\t"}}{{index .metadata.annotations "budgetanalyzer.org/image"}}{{"\t"}}{{index .metadata.annotations "org.opencontainers.image.revision"}}{{"\t"}}{{index .metadata.annotations "budgetanalyzer.org/source-ref"}}{{"\t"}}{{index .metadata.annotations "budgetanalyzer.org/service-common-version"}}{{"\t"}}{{range $index, $container := .spec.containers}}{{if $index}},{{end}}{{$container.image}}{{end}}{{"\n"}}{{end}}'
    pod_rows="$(kubectl get pods -A -o "go-template=${pod_template}")"

    while IFS=$'\t' read -r namespace pod app app_name deployment_id app_version part_of image_annotation revision_annotation source_ref_annotation service_common_annotation images; do
        [[ -n "${namespace}" ]] || continue

        workload="${app:-${app_name}}"
        tracked=false
        if is_tracked_app "${workload}" || [[ "${part_of}" == "budget-analyzer" && "${workload}" == "nginx-gateway" ]]; then
            tracked=true
        fi

        if [[ "${TRACKED_ONLY}" == true && "${tracked}" != true ]]; then
            continue
        fi

        status="OK"
        if [[ "${tracked}" == true ]]; then
            artifact="$(artifact_for_workload "${workload}")"
            if [[ -z "${EXPECTED_IMAGE_REFS[${artifact}]:-}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                warn_mismatch "${namespace}/${pod} maps to unknown deployment artifact ${artifact}"
            elif [[ "${deployment_id}" != "${expected_deployment_id}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                warn_mismatch "${namespace}/${pod} has deployment-id=${deployment_id:-<none>}; expected ${expected_deployment_id}"
            elif [[ "${app_version}" != "${EXPECTED_ARTIFACT_VERSIONS[${artifact}]}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                warn_mismatch "${namespace}/${pod} has app.kubernetes.io/version=${app_version:-<none>}; expected ${EXPECTED_ARTIFACT_VERSIONS[${artifact}]}"
            elif [[ "${image_annotation}" != "${EXPECTED_IMAGE_REFS[${artifact}]}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                warn_mismatch "${namespace}/${pod} has budgetanalyzer.org/image=${image_annotation:-<none>}; expected ${EXPECTED_IMAGE_REFS[${artifact}]}"
            elif [[ "${revision_annotation}" != "${EXPECTED_SOURCE_COMMITS[${artifact}]}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                warn_mismatch "${namespace}/${pod} has org.opencontainers.image.revision=${revision_annotation:-<none>}; expected ${EXPECTED_SOURCE_COMMITS[${artifact}]}"
            elif [[ "${source_ref_annotation}" != "${EXPECTED_SOURCE_REFS[${artifact}]}" ]]; then
                status="WARN"
                warning_count=$((warning_count + 1))
                warn_mismatch "${namespace}/${pod} has budgetanalyzer.org/source-ref=${source_ref_annotation:-<none>}; expected ${EXPECTED_SOURCE_REFS[${artifact}]}"
            else
                expected_service_common="${EXPECTED_SERVICE_COMMON_VERSIONS[${artifact}]:-}"
                if [[ -n "${expected_service_common}" && "${service_common_annotation}" != "${expected_service_common}" ]]; then
                    status="WARN"
                    warning_count=$((warning_count + 1))
                    warn_mismatch "${namespace}/${pod} has service-common-version=${service_common_annotation:-<none>}; expected ${expected_service_common}"
                fi
            fi
        elif [[ "${tracked}" != true ]]; then
            status="INFO"
        fi

        printf '%-10s %-16s %-52s %-24s %-20s %-12s %-18s %s\n' \
            "${status}" "${namespace}" "${pod}" "${workload:-<none>}" "${deployment_id:-<none>}" "${app_version:-<none>}" "${part_of:-<none>}" "${images:-<none>}"
        printed_count=$((printed_count + 1))
    done <<< "${pod_rows}"

    printf '\nPrinted pods: %s\n' "${printed_count}"
    printf 'Warnings: %s\n' "${warning_count}"

    if [[ "${STRICT}" == true && "${warning_count}" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
