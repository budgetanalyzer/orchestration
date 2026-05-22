#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

GENERATE_DEPLOYMENT_MANIFEST="$(phase4_repo_path "scripts/repo/generate-deployment-manifest.sh")"
UPDATE_PRODUCTION_BASELINE="${SCRIPT_DIR}/23-update-production-release-images.sh"
readonly GENERATE_DEPLOYMENT_MANIFEST
readonly UPDATE_PRODUCTION_BASELINE

ARTIFACT_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly ARTIFACT_ORDER

artifact=""
to_manifest=""
deployment_id=""
output_path=""
force=false
update_production_baseline=false
skip_live_production_verifier=false

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/26-rollback-oci-artifact.sh \
    --service transaction-service \
    --to-manifest tmp/deployments/previous.yaml

Options:
  --service ARTIFACT                 Artifact to roll back.
  --artifact ARTIFACT                Alias for --service.
  --to-manifest PATH                 Previous schema v2 deployment manifest.
  --deployment-id ID                 Rollback deployment id. Defaults to
                                     rollback-<UTC timestamp>-<artifact>.
  --output PATH                      Output rollback manifest path. Defaults
                                     to tmp/deployments/<deployment-id>.yaml.
  --force                            Overwrite an existing output manifest.
  --update-production-baseline       After generating the manifest, run
                                     deploy/scripts/23-update-production-release-images.sh.
  --skip-live-production-verifier    Pass through to the production baseline
                                     updater when --update-production-baseline
                                     is used.
  -h, --help                         Show this help.

The helper starts from the current checked-in production image inventory and
copies only the selected artifact's image and metadata from --to-manifest.
Unrelated artifacts remain on the current production baseline.
EOF
}

die() {
    phase4_die "$1"
}

info() {
    phase4_info "$*"
}

artifact_exists() {
    local candidate="$1"
    local known

    for known in "${ARTIFACT_ORDER[@]}"; do
        if [[ "${known}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

manifest_value() {
    local manifest="$1"
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
    ' "${manifest}"
}

manifest_nested_value() {
    local manifest="$1"
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
    ' "${manifest}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --service|--artifact)
                artifact="${2:-}"
                [[ -n "${artifact}" ]] || die "missing value for $1"
                artifact_exists "${artifact}" || die "unknown artifact: ${artifact}"
                shift
                ;;
            --to-manifest)
                to_manifest="${2:-}"
                [[ -n "${to_manifest}" ]] || die "missing value for --to-manifest"
                shift
                ;;
            --deployment-id)
                deployment_id="${2:-}"
                [[ -n "${deployment_id}" ]] || die "missing value for --deployment-id"
                shift
                ;;
            --output)
                output_path="${2:-}"
                [[ -n "${output_path}" ]] || die "missing value for --output"
                shift
                ;;
            --force)
                force=true
                ;;
            --update-production-baseline)
                update_production_baseline=true
                ;;
            --skip-live-production-verifier)
                skip_live_production_verifier=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
        shift
    done
}

resolve_inputs() {
    [[ -n "${artifact}" ]] || die "missing --service"
    [[ -n "${to_manifest}" ]] || die "missing --to-manifest"

    if [[ "${to_manifest}" != /* && ! -f "${to_manifest}" ]]; then
        to_manifest="$(phase4_repo_path "${to_manifest}")"
    fi
    [[ -f "${to_manifest}" ]] || die "rollback source manifest not found: ${to_manifest}"
    [[ "$(manifest_value "${to_manifest}" "schema_version")" == "2" ]] || die "rollback source manifest must use schema_version: 2"

    if [[ -z "${deployment_id}" ]]; then
        deployment_id="rollback-$(date -u +%Y%m%dT%H%M%SZ)-${artifact}"
    fi

    if [[ -z "${output_path}" ]]; then
        output_path="$(phase4_repo_path "tmp/deployments/${deployment_id}.yaml")"
    elif [[ "${output_path}" != /* ]]; then
        output_path="$(phase4_repo_path "${output_path}")"
    fi
}

generate_rollback_manifest() {
    local image artifact_version source_ref source_commit service_common_version
    local args=()

    image="$(manifest_nested_value "${to_manifest}" "artifacts" "${artifact}" "image")"
    artifact_version="$(manifest_nested_value "${to_manifest}" "artifacts" "${artifact}" "artifact_version")"
    source_ref="$(manifest_nested_value "${to_manifest}" "artifacts" "${artifact}" "source_ref")"
    source_commit="$(manifest_nested_value "${to_manifest}" "artifacts" "${artifact}" "source_commit")"
    service_common_version="$(manifest_nested_value "${to_manifest}" "artifacts" "${artifact}" "service_common_version")"

    [[ -n "${image}" ]] || die "source manifest is missing artifacts.${artifact}.image"
    [[ -n "${artifact_version}" ]] || die "source manifest is missing artifacts.${artifact}.artifact_version"
    [[ -n "${source_ref}" ]] || die "source manifest is missing artifacts.${artifact}.source_ref"
    [[ -n "${source_commit}" ]] || die "source manifest is missing artifacts.${artifact}.source_commit"

    args=(
        --deployment-id "${deployment_id}"
        --output "${output_path}"
        --artifact "${artifact}"
        --artifact-image "${artifact}=${image}"
        --artifact-version "${artifact}=${artifact_version}"
        --source-ref "${artifact}=${source_ref}"
        --source-commit "${artifact}=${source_commit}"
    )

    if [[ -n "${service_common_version}" ]]; then
        args+=(--service-common-version "${artifact}=${service_common_version}")
    fi
    if [[ "${force}" == "true" ]]; then
        args+=(--force)
    fi

    "${GENERATE_DEPLOYMENT_MANIFEST}" "${args[@]}"
}

update_baseline_if_requested() {
    local args=(--deployment-manifest "${output_path}")

    if [[ "${update_production_baseline}" != "true" ]]; then
        return
    fi

    if [[ "${skip_live_production_verifier}" == "true" ]]; then
        args+=(--skip-live-production-verifier)
    fi

    "${UPDATE_PRODUCTION_BASELINE}" "${args[@]}"
}

main() {
    parse_args "$@"
    resolve_inputs

    generate_rollback_manifest
    update_baseline_if_requested

    info "rollback manifest for ${artifact}: ${output_path}"
    if [[ "${update_production_baseline}" != "true" ]]; then
        info "review it, then run deploy/scripts/23-update-production-release-images.sh --deployment-manifest ${output_path}"
    fi
}

main "$@"
