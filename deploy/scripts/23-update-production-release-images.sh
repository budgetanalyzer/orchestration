#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_APPS_DIR="$(phase4_repo_path "kubernetes/production/apps")"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
PRODUCTION_DEPLOYMENT_MANIFEST="${PRODUCTION_APPS_DIR}/deployment-manifest.yaml"
PRODUCTION_KUSTOMIZATION="${PRODUCTION_APPS_DIR}/kustomization.yaml"
PRODUCTION_RUNTIME_METADATA_PATCH="${PRODUCTION_APPS_DIR}/patches/runtime-release-metadata.yaml"
LOCAL_RELEASE_METADATA_JSON="$(phase4_repo_path "docs-aggregator/release-metadata.json")"
PRODUCTION_RELEASE_METADATA_JSON="$(phase4_repo_path "kubernetes/production/docs-aggregator/release-metadata.json")"
PRODUCTION_IMAGE_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
STATIC_VERIFIER="${SCRIPT_DIR}/24-verify-oci-upgrade-lockstep.sh"
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly PRODUCTION_DEPLOYMENT_MANIFEST
readonly PRODUCTION_KUSTOMIZATION
readonly PRODUCTION_RUNTIME_METADATA_PATCH
readonly LOCAL_RELEASE_METADATA_JSON
readonly PRODUCTION_RELEASE_METADATA_JSON
readonly PRODUCTION_IMAGE_VERIFIER
readonly STATIC_VERIFIER

SERVICE_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly SERVICE_ORDER

RUNTIME_DEPLOYMENT_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "ext-authz"
)
readonly RUNTIME_DEPLOYMENT_ORDER

declare -A IMAGE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="ext-authz"
)

declare -A IMAGE_REFS=()
declare -A SOURCE_REPOS=()
declare -A SOURCE_REFS=()
declare -A SOURCE_COMMITS=()
declare -A ARTIFACT_VERSIONS=()
declare -A SERVICE_COMMON_VERSIONS=()

deployment_manifest=""
deployment_id=""
deployment_status=""
deployment_environment=""
orchestration_commit=""
orchestration_source_ref=""
skip_live_production_verifier=false

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/23-update-production-release-images.sh \
    --deployment-manifest tmp/deployments/oci-YYYYMMDD.N.yaml

Options:
  --deployment-manifest PATH       Required schema_version: 2 deployment manifest.
  --skip-live-production-verifier  Skip scripts/guardrails/verify-production-image-overlay.sh.
  -h, --help                       Show this help.

Updates the checked-in OCI production application image baseline from a v2
deployment manifest. The manifest is the source of truth for deployment id,
status, orchestration revision, per-artifact source refs, source commits,
artifact versions, service-common versions, and digest-pinned images.
EOF
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

manifest_map_value() {
    local manifest="$1"
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
    ' "${manifest}"
}

manifest_nested_map_value() {
    local manifest="$1"
    local section="$2"
    local subsection="$3"
    local key="$4"

    awk -v section="${section}" -v subsection="${subsection}" -v key="${key}" '
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
            in_subsection = 0
        }
        in_section && $0 == "  " subsection ":" {
            in_subsection = 1
            next
        }
        in_section && in_subsection && $0 ~ /^  [^[:space:]][^:]*:/ {
            in_subsection = 0
        }
        in_section && in_subsection && index($0, "    " key ":") == 1 {
            value = $0
            sub("^    " key ":[[:space:]]*", "", value)
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

manifest_artifact_image_keys() {
    local manifest="$1"

    awk '
        $0 == "artifacts:" {
            in_artifacts = 1
            next
        }
        in_artifacts && $0 ~ /^[^[:space:]][^:]*:/ {
            in_artifacts = 0
            current = ""
        }
        in_artifacts && $0 ~ /^  [^[:space:]][^:]*:/ {
            current = $0
            sub(/^  /, "", current)
            sub(/:.*/, "", current)
            next
        }
        in_artifacts && current != "" && $0 ~ /^    image:[[:space:]]*/ {
            print current
        }
    ' "${manifest}"
}

valid_commit_sha() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

valid_bool() {
    [[ "$1" == "true" || "$1" == "false" ]]
}

service_exists() {
    local candidate="$1"
    local service

    for service in "${SERVICE_ORDER[@]}"; do
        if [[ "${service}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

image_ref_tag() {
    local image_ref="$1"

    printf '%s\n' "${image_ref}" | sed -E 's#^ghcr\.io/budgetanalyzer/[a-z0-9-]+:([^@]+)@sha256:[0-9a-f]{64}$#\1#'
}

inventory_value() {
    local key="$1"

    awk -v key="${key}" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            value = $0
            sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
        }
    ' "${PRODUCTION_IMAGE_INVENTORY}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment-manifest)
                deployment_manifest="${2:-}"
                [[ -n "${deployment_manifest}" ]] || phase4_die "missing value for --deployment-manifest"
                shift
                ;;
            --skip-live-production-verifier)
                skip_live_production_verifier=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                phase4_die "unknown option: $1"
                ;;
        esac
        shift
    done
}

resolve_manifest_path() {
    [[ -n "${deployment_manifest}" ]] || phase4_die "missing --deployment-manifest"
    if [[ "${deployment_manifest}" != /* && ! -f "${deployment_manifest}" ]]; then
        deployment_manifest="$(phase4_repo_path "${deployment_manifest}")"
    fi
    [[ -f "${deployment_manifest}" ]] || phase4_die "deployment manifest not found: ${deployment_manifest}"
}

load_deployment_manifest() {
    local schema_version
    local service value image_key flag
    local expected_image_key_count actual_image_key_count

    schema_version="$(manifest_value "${deployment_manifest}" "schema_version")"
    [[ "${schema_version}" == "2" ]] || phase4_die "deployment manifest must use schema_version: 2"

    deployment_id="$(manifest_map_value "${deployment_manifest}" "deployment" "id")"
    deployment_status="$(manifest_map_value "${deployment_manifest}" "deployment" "status")"
    deployment_environment="$(manifest_map_value "${deployment_manifest}" "deployment" "environment")"
    orchestration_commit="$(manifest_nested_map_value "${deployment_manifest}" "deployment" "orchestration_repository" "commit")"
    orchestration_source_ref="$(manifest_nested_map_value "${deployment_manifest}" "deployment" "orchestration_repository" "source_ref")"

    [[ -n "${deployment_id}" ]] || phase4_die "deployment manifest is missing deployment.id"
    [[ -n "${deployment_status}" ]] || phase4_die "deployment manifest is missing deployment.status"
    [[ -n "${deployment_environment}" ]] || phase4_die "deployment manifest is missing deployment.environment"
    [[ -n "${orchestration_commit}" ]] || phase4_die "deployment manifest is missing deployment.orchestration_repository.commit"
    [[ -n "${orchestration_source_ref}" ]] || phase4_die "deployment manifest is missing deployment.orchestration_repository.source_ref"
    valid_commit_sha "${orchestration_commit}" || phase4_die "invalid deployment orchestration commit: ${orchestration_commit}"

    for service in "${SERVICE_ORDER[@]}"; do
        value="$(manifest_nested_value "${deployment_manifest}" "artifacts" "${service}" "source_repository")"
        [[ -n "${value}" ]] || phase4_die "deployment manifest is missing artifacts.${service}.source_repository"
        SOURCE_REPOS["${service}"]="${value}"

        value="$(manifest_nested_value "${deployment_manifest}" "artifacts" "${service}" "source_ref")"
        [[ -n "${value}" ]] || phase4_die "deployment manifest is missing artifacts.${service}.source_ref"
        SOURCE_REFS["${service}"]="${value}"

        value="$(manifest_nested_value "${deployment_manifest}" "artifacts" "${service}" "source_commit")"
        [[ -n "${value}" ]] || phase4_die "deployment manifest is missing artifacts.${service}.source_commit"
        valid_commit_sha "${value}" || phase4_die "invalid source commit for artifacts.${service}: ${value}"
        SOURCE_COMMITS["${service}"]="${value}"

        value="$(manifest_nested_value "${deployment_manifest}" "artifacts" "${service}" "artifact_version")"
        [[ -n "${value}" ]] || phase4_die "deployment manifest is missing artifacts.${service}.artifact_version"
        ARTIFACT_VERSIONS["${service}"]="${value}"

        value="$(manifest_nested_value "${deployment_manifest}" "artifacts" "${service}" "image")"
        [[ -n "${value}" ]] || phase4_die "deployment manifest is missing artifacts.${service}.image"
        IMAGE_REFS["${service}"]="${value}"

        value="$(manifest_nested_value "${deployment_manifest}" "artifacts" "${service}" "service_common_version")"
        if [[ -n "${value}" ]]; then
            SERVICE_COMMON_VERSIONS["${service}"]="${value}"
        fi
    done

    for flag in platform_changed infrastructure_changed secrets_changed observability_changed public_tls_reapply_required; do
        value="$(manifest_map_value "${deployment_manifest}" "phase_flags" "${flag}")"
        [[ -n "${value}" ]] || phase4_die "deployment manifest is missing phase_flags.${flag}"
        valid_bool "${value}" || phase4_die "phase_flags.${flag} must be true or false"
    done

    expected_image_key_count="${#SERVICE_ORDER[@]}"
    actual_image_key_count=0
    while IFS= read -r image_key; do
        [[ -n "${image_key}" ]] || continue
        service_exists "${image_key}" || phase4_die "deployment manifest contains unknown artifact image key: ${image_key}"
        actual_image_key_count=$((actual_image_key_count + 1))
    done < <(manifest_artifact_image_keys "${deployment_manifest}")
    [[ "${actual_image_key_count}" == "${expected_image_key_count}" ]] || \
        phase4_die "deployment manifest must contain exactly ${expected_image_key_count} artifact image entries; found ${actual_image_key_count}"
}

validate_image_refs() {
    local service repo image_ref expected_pattern tag

    for service in "${SERVICE_ORDER[@]}"; do
        repo="${IMAGE_REPOS[${service}]}"
        image_ref="${IMAGE_REFS[${service}]}"
        expected_pattern="^ghcr\\.io/budgetanalyzer/${repo}:[A-Za-z0-9_.-]+@sha256:[0-9a-f]{64}$"
        [[ "${image_ref}" =~ ${expected_pattern} ]] || \
            phase4_die "invalid image ref for ${service}; expected digest-pinned ghcr.io/budgetanalyzer/${repo}:<tag>@sha256:<64 lowercase hex>, got: ${image_ref}"

        [[ "${image_ref}" != *":latest@"* && "${image_ref}" != *":tilt-"* ]] || \
            phase4_die "mutable image ref is not allowed for ${service}: ${image_ref}"

        tag="$(image_ref_tag "${image_ref}")"
        [[ "${ARTIFACT_VERSIONS[${service}]}" == "${tag}" ]] || \
            phase4_die "artifact version for ${service} (${ARTIFACT_VERSIONS[${service}]}) does not match image tag (${tag})"
    done
}

write_image_inventory() {
    local temp_file="${PRODUCTION_IMAGE_INVENTORY}.tmp"
    local service

    {
        cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: production-image-inventory
  namespace: default
  labels:
    app.kubernetes.io/part-of: budget-analyzer
    app.kubernetes.io/component: production-image-inventory
data:
  schema-version: "2"
  deployment-id: "${deployment_id}"
  deployment-status: "${deployment_status}"
  deployment-environment: "${deployment_environment}"
  orchestration-commit: "${orchestration_commit}"
  orchestration-source-ref: "${orchestration_source_ref}"
EOF
        for service in "${SERVICE_ORDER[@]}"; do
            printf '  %s: "%s"\n' "${service}" "${IMAGE_REFS[${service}]}"
            printf '  %s.artifact-version: "%s"\n' "${service}" "${ARTIFACT_VERSIONS[${service}]}"
            printf '  %s.source-repository: "%s"\n' "${service}" "${SOURCE_REPOS[${service}]}"
            printf '  %s.source-ref: "%s"\n' "${service}" "${SOURCE_REFS[${service}]}"
            printf '  %s.source-commit: "%s"\n' "${service}" "${SOURCE_COMMITS[${service}]}"
            if [[ -n "${SERVICE_COMMON_VERSIONS[${service}]:-}" ]]; then
                printf '  %s.service-common-version: "%s"\n' "${service}" "${SERVICE_COMMON_VERSIONS[${service}]}"
            fi
        done
    } > "${temp_file}"

    mv "${temp_file}" "${PRODUCTION_IMAGE_INVENTORY}"
}

write_deployment_manifest_baseline() {
    local temp_file="${PRODUCTION_DEPLOYMENT_MANIFEST}.tmp"

    cp "${deployment_manifest}" "${temp_file}"
    mv "${temp_file}" "${PRODUCTION_DEPLOYMENT_MANIFEST}"
}

write_release_metadata_json_file() {
    local output_path="$1"
    local temp_file="${output_path}.tmp"
    local service service_common_version
    local index=0

    mkdir -p "$(dirname "${output_path}")"

    {
        printf '{\n'
        printf '  "schemaVersion": 2,\n'
        printf '  "deployment": {\n'
        printf '    "id": "%s",\n' "${deployment_id}"
        printf '    "environment": "%s",\n' "${deployment_environment}"
        printf '    "status": "%s",\n' "${deployment_status}"
        printf '    "orchestrationRepository": {\n'
        printf '      "commit": "%s",\n' "${orchestration_commit}"
        printf '      "sourceRef": "%s"\n' "${orchestration_source_ref}"
        printf '    }\n'
        printf '  },\n'
        printf '  "artifacts": {\n'
        for service in "${SERVICE_ORDER[@]}"; do
            if [[ "${index}" -gt 0 ]]; then
                printf ',\n'
            fi
            printf '    "%s": {\n' "${service}"
            printf '      "sourceRepository": "%s",\n' "${SOURCE_REPOS[${service}]}"
            printf '      "sourceRef": "%s",\n' "${SOURCE_REFS[${service}]}"
            printf '      "sourceCommit": "%s",\n' "${SOURCE_COMMITS[${service}]}"
            printf '      "artifactVersion": "%s",\n' "${ARTIFACT_VERSIONS[${service}]}"
            service_common_version="${SERVICE_COMMON_VERSIONS[${service}]:-}"
            if [[ -n "${service_common_version}" ]]; then
                printf '      "serviceCommonVersion": "%s",\n' "${service_common_version}"
            fi
            printf '      "image": "%s"\n' "${IMAGE_REFS[${service}]}"
            printf '    }'
            index=$((index + 1))
        done
        printf '\n'
        printf '  }\n'
        printf '}\n'
    } > "${temp_file}"

    mv "${temp_file}" "${output_path}"
}

write_release_metadata_json() {
    write_release_metadata_json_file "${LOCAL_RELEASE_METADATA_JSON}"
    write_release_metadata_json_file "${PRODUCTION_RELEASE_METADATA_JSON}"
}

write_runtime_metadata_document() {
    local temp_file="$1"
    local workload="$2"
    local artifact="$3"

    cat >> "${temp_file}" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${workload}
  namespace: default
  labels:
    app.kubernetes.io/name: ${workload}
    app.kubernetes.io/part-of: budget-analyzer
    app.kubernetes.io/version: ${ARTIFACT_VERSIONS[${artifact}]}
    budgetanalyzer.org/deployment-id: ${deployment_id}
  annotations:
    budgetanalyzer.org/deployment-status: ${deployment_status}
    budgetanalyzer.org/image: ${IMAGE_REFS[${artifact}]}
    budgetanalyzer.org/source-ref: ${SOURCE_REFS[${artifact}]}
    org.opencontainers.image.version: ${ARTIFACT_VERSIONS[${artifact}]}
    org.opencontainers.image.revision: ${SOURCE_COMMITS[${artifact}]}
EOF
    if [[ -n "${SERVICE_COMMON_VERSIONS[${artifact}]:-}" ]]; then
        cat >> "${temp_file}" <<EOF
    budgetanalyzer.org/service-common-version: ${SERVICE_COMMON_VERSIONS[${artifact}]}
EOF
    fi
    cat >> "${temp_file}" <<EOF
spec:
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${workload}
        app.kubernetes.io/part-of: budget-analyzer
        app.kubernetes.io/version: ${ARTIFACT_VERSIONS[${artifact}]}
        budgetanalyzer.org/deployment-id: ${deployment_id}
      annotations:
        budgetanalyzer.org/deployment-status: ${deployment_status}
        budgetanalyzer.org/image: ${IMAGE_REFS[${artifact}]}
        budgetanalyzer.org/source-ref: ${SOURCE_REFS[${artifact}]}
        org.opencontainers.image.version: ${ARTIFACT_VERSIONS[${artifact}]}
        org.opencontainers.image.revision: ${SOURCE_COMMITS[${artifact}]}
EOF
    if [[ -n "${SERVICE_COMMON_VERSIONS[${artifact}]:-}" ]]; then
        cat >> "${temp_file}" <<EOF
        budgetanalyzer.org/service-common-version: ${SERVICE_COMMON_VERSIONS[${artifact}]}
EOF
    fi
}

write_runtime_release_metadata_patch() {
    local temp_file="${PRODUCTION_RUNTIME_METADATA_PATCH}.tmp"
    local service

    : > "${temp_file}"

    for service in "${RUNTIME_DEPLOYMENT_ORDER[@]}"; do
        write_runtime_metadata_document "${temp_file}" "${service}" "${service}"
        printf -- '---\n' >> "${temp_file}"
    done

    write_runtime_metadata_document "${temp_file}" "nginx-gateway" "budget-analyzer-web"

    mv "${temp_file}" "${PRODUCTION_RUNTIME_METADATA_PATCH}"
}

replace_image_ref_in_kustomization() {
    local service="$1"
    local repo="${IMAGE_REPOS[${service}]}"
    local old_ref new_ref temp_file

    old_ref="$(inventory_value "${service}")"
    new_ref="${IMAGE_REFS[${service}]}"

    [[ -n "${old_ref}" ]] || phase4_die "current production image inventory is missing ${service}"
    if ! grep -Fq "${old_ref}" "${PRODUCTION_KUSTOMIZATION}"; then
        phase4_die "current kustomization does not contain the inventory image for ${service}: ${old_ref}"
    fi

    temp_file="${PRODUCTION_KUSTOMIZATION}.tmp"
    sed -E "s#ghcr\\.io/budgetanalyzer/${repo}:[^[:space:]\"']+@sha256:[0-9a-f]{64}#${new_ref}#g" \
        "${PRODUCTION_KUSTOMIZATION}" > "${temp_file}"
    mv "${temp_file}" "${PRODUCTION_KUSTOMIZATION}"
}

update_kustomization() {
    local service

    for service in "${SERVICE_ORDER[@]}"; do
        replace_image_ref_in_kustomization "${service}"
    done
}

verify_updates() {
    phase4_require_commands kubectl

    kubectl kustomize "${PRODUCTION_APPS_DIR}" --load-restrictor=LoadRestrictionsNone >/dev/null
    "${STATIC_VERIFIER}"

    if [[ "${skip_live_production_verifier}" == false ]]; then
        "${PRODUCTION_IMAGE_VERIFIER}"
    else
        phase4_warn "skipped live production verifier; run ${PRODUCTION_IMAGE_VERIFIER} before OCI apply"
    fi
}

main() {
    parse_args "$@"

    [[ -f "${PRODUCTION_IMAGE_INVENTORY}" ]] || phase4_die "missing image inventory: ${PRODUCTION_IMAGE_INVENTORY}"
    [[ -f "${PRODUCTION_KUSTOMIZATION}" ]] || phase4_die "missing production kustomization: ${PRODUCTION_KUSTOMIZATION}"

    resolve_manifest_path
    load_deployment_manifest
    validate_image_refs
    update_kustomization
    write_deployment_manifest_baseline
    write_image_inventory
    write_release_metadata_json
    write_runtime_release_metadata_patch
    verify_updates

    phase4_info "updated production deployment baseline to ${deployment_id}"
    phase4_info "review the diff before deploying to OCI"
}

main "$@"
