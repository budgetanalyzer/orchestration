#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_APPS_DIR="$(phase4_repo_path "kubernetes/production/apps")"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
PRODUCTION_KUSTOMIZATION="${PRODUCTION_APPS_DIR}/kustomization.yaml"
PRODUCTION_RUNTIME_METADATA_PATCH="${PRODUCTION_APPS_DIR}/patches/runtime-release-metadata.yaml"
LOCAL_RELEASE_METADATA_JSON="$(phase4_repo_path "docs-aggregator/release-metadata.json")"
PRODUCTION_RELEASE_METADATA_JSON="$(phase4_repo_path "kubernetes/production/docs-aggregator/release-metadata.json")"
PRODUCTION_IMAGE_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
LOCKSTEP_VERIFIER="${SCRIPT_DIR}/24-verify-oci-upgrade-lockstep.sh"
INSTANCE_ENV_TEMPLATE="$(phase4_repo_path "deploy/instance.env.template")"
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly PRODUCTION_KUSTOMIZATION
readonly PRODUCTION_RUNTIME_METADATA_PATCH
readonly LOCAL_RELEASE_METADATA_JSON
readonly PRODUCTION_RELEASE_METADATA_JSON
readonly PRODUCTION_IMAGE_VERIFIER
readonly LOCKSTEP_VERIFIER
readonly INSTANCE_ENV_TEMPLATE

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

declare -A ARTIFACT_SOURCE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="orchestration"
)

RELEASE_REPOS=(
    "orchestration"
    "service-common"
    "transaction-service"
    "currency-service"
    "budget-analyzer-web"
    "session-gateway"
    "permission-service"
)
readonly RELEASE_REPOS

declare -A IMAGE_REFS=()
declare -A SOURCE_REPOS=()
declare -A COMMIT_SHAS=()

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/23-update-production-release-images.sh \
    --release-version 0.0.x \
    --transaction-service ghcr.io/budgetanalyzer/transaction-service:0.0.x@sha256:<digest> \
    --currency-service ghcr.io/budgetanalyzer/currency-service:0.0.x@sha256:<digest> \
    --permission-service ghcr.io/budgetanalyzer/permission-service:0.0.x@sha256:<digest> \
    --session-gateway ghcr.io/budgetanalyzer/session-gateway:0.0.x@sha256:<digest> \
    --budget-analyzer-web ghcr.io/budgetanalyzer/budget-analyzer-web:0.0.x@sha256:<digest> \
    --ext-authz ghcr.io/budgetanalyzer/ext-authz:0.0.x@sha256:<digest>

  ./deploy/scripts/23-update-production-release-images.sh \
    --release-manifest tmp/releases/v0.0.x.yaml

Updates the checked-in OCI production application image baseline. The release
manifest form is the normal release path and requires the Phase 1 contract:
release.version, release.image_tag, OCI release source repository commit SHAs,
artifact workflow run URLs, digest-pinned artifact images, and boolean
phase_flags. The legacy flat manifest form with release-version/version plus
the six service keys is still accepted for local repair.

By default the script runs:
  kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
  ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
  ./scripts/guardrails/verify-production-image-overlay.sh

Use --skip-live-production-verifier only when no live Kubernetes context is
available for the existing production verifier's Helm server-side Kiali render.
EOF
}

manifest_value() {
    local manifest="$1"
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
    ' "${manifest}"
}

manifest_section_present() {
    local manifest="$1"
    local section="$2"

    awk -v section="${section}" '
        $0 == section ":" {
            found = 1
            exit
        }
        END {
            exit found ? 0 : 1
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

manifest_release_value() {
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
        $0 == "release:" {
            in_release = 1
            next
        }
        in_release && $0 ~ /^[^[:space:]][^:]*:/ {
            in_release = 0
        }
        in_release && index($0, "  " key ":") == 1 {
            value = $0
            sub("^  " key ":[[:space:]]*", "", value)
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

normalize_release_version() {
    local version="$1"

    version="${version#v}"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        phase4_die "release version must use X.Y.Z or vX.Y.Z format: ${version}"
    printf '%s\n' "${version}"
}

valid_commit_sha() {
    local sha="$1"

    [[ "${sha}" =~ ^[0-9a-f]{40}$ ]]
}

valid_workflow_run_url() {
    local url="$1"

    [[ "${url}" =~ ^https://github\.com/budgetanalyzer/[A-Za-z0-9_.-]+/actions/runs/[0-9]+(/.*)?$ ]]
}

valid_bool() {
    local value="$1"

    [[ "${value}" == "true" || "${value}" == "false" ]]
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

load_manifest() {
    local manifest="$1"
    local full_manifest=false
    local service repo flag value image_key
    local manifest_release_version
    local manifest_image_tag
    local expected_image_key_count
    local actual_image_key_count

    [[ -f "${manifest}" ]] || phase4_die "release manifest not found: ${manifest}"

    if manifest_section_present "${manifest}" "release" || \
        manifest_section_present "${manifest}" "repositories" || \
        manifest_section_present "${manifest}" "artifacts" || \
        manifest_section_present "${manifest}" "phase_flags"; then
        full_manifest=true
    fi

    if [[ -z "${release_version}" ]]; then
        release_version="$(manifest_release_value "${manifest}" "version")"
        if [[ -z "${release_version}" ]]; then
            release_version="$(manifest_value "${manifest}" "release-version")"
        fi
        if [[ -z "${release_version}" ]]; then
            release_version="$(manifest_value "${manifest}" "version")"
        fi
    fi

    for service in "${SERVICE_ORDER[@]}"; do
        if [[ -z "${IMAGE_REFS[${service}]:-}" ]]; then
            value="$(manifest_nested_value "${manifest}" "artifacts" "${service}" "image")"
            if [[ -z "${value}" ]]; then
                value="$(manifest_nested_value "${manifest}" "images" "${service}" "image")"
            fi
            if [[ -z "${value}" ]]; then
                value="$(manifest_value "${manifest}" "${service}")"
            fi
            if [[ -n "${value}" ]]; then
                IMAGE_REFS["${service}"]="${value}"
            fi
        fi

        value="$(manifest_nested_value "${manifest}" "artifacts" "${service}" "source_repository")"
        if [[ -n "${value}" ]]; then
            SOURCE_REPOS["${service}"]="${value}"
        fi
    done

    if [[ "${full_manifest}" != true ]]; then
        return
    fi

    manifest_release_version="$(manifest_release_value "${manifest}" "version")"
    manifest_image_tag="$(manifest_release_value "${manifest}" "image_tag")"
    [[ -n "${manifest_release_version}" ]] || phase4_die "release manifest is missing release.version"
    [[ -n "${manifest_image_tag}" ]] || phase4_die "release manifest is missing release.image_tag"
    [[ "${manifest_release_version}" == v* ]] || phase4_die "release manifest release.version must use vX.Y.Z form"
    [[ "${manifest_image_tag}" != v* ]] || phase4_die "release manifest release.image_tag must use X.Y.Z form"

    manifest_release_version="$(normalize_release_version "${manifest_release_version}")"
    manifest_image_tag="$(normalize_release_version "${manifest_image_tag}")"
    [[ "${manifest_release_version}" == "${manifest_image_tag}" ]] || \
        phase4_die "release manifest release.version and release.image_tag disagree"

    if [[ -n "${release_version}" ]]; then
        [[ "$(normalize_release_version "${release_version}")" == "${manifest_release_version}" ]] || \
            phase4_die "release manifest version does not match --release-version"
    fi

    release_version="${manifest_release_version}"

    for repo in "${RELEASE_REPOS[@]}"; do
        value="$(manifest_nested_value "${manifest}" "repositories" "${repo}" "commit")"
        [[ -n "${value}" ]] || phase4_die "release manifest is missing repositories.${repo}.commit"
        valid_commit_sha "${value}" || phase4_die "invalid commit SHA for repositories.${repo}.commit: ${value}"
        COMMIT_SHAS["${repo}"]="${value}"
    done

    for service in "${SERVICE_ORDER[@]}"; do
        value="$(artifact_source_repo "${service}")"
        [[ -n "${COMMIT_SHAS[${value}]:-}" ]] || \
            phase4_die "artifacts.${service}.source_repository does not match a repository commit entry: ${value}"
    done

    for service in "${SERVICE_ORDER[@]}"; do
        value="$(manifest_nested_value "${manifest}" "artifacts" "${service}" "workflow_run_url")"
        [[ -n "${value}" ]] || phase4_die "release manifest is missing artifacts.${service}.workflow_run_url"
        valid_workflow_run_url "${value}" || phase4_die "invalid workflow run URL for artifacts.${service}: ${value}"
    done

    for flag in platform_changed infrastructure_changed secrets_changed observability_changed public_tls_reapply_required; do
        value="$(manifest_nested_value "${manifest}" "phase_flags" "${flag}" "unused")"
        if [[ -z "${value}" ]]; then
            value="$(awk -v flag="${flag}" '
                $0 == "phase_flags:" {
                    in_flags = 1
                    next
                }
                in_flags && $0 ~ /^[^[:space:]][^:]*:/ {
                    in_flags = 0
                }
                in_flags && index($0, "  " flag ":") == 1 {
                    value = $0
                    sub("^  " flag ":[[:space:]]*", "", value)
                    sub(/^[[:space:]]*/, "", value)
                    sub(/[[:space:]]*$/, "", value)
                    gsub(/^"/, "", value)
                    gsub(/"$/, "", value)
                    print value
                    exit
                }
            ' "${manifest}")"
        fi
        [[ -n "${value}" ]] || phase4_die "release manifest is missing phase_flags.${flag}"
        valid_bool "${value}" || phase4_die "phase_flags.${flag} must be true or false"
    done

    expected_image_key_count="${#SERVICE_ORDER[@]}"
    actual_image_key_count=0
    while IFS= read -r image_key; do
        [[ -n "${image_key}" ]] || continue
        service_exists "${image_key}" || phase4_die "release manifest contains unknown artifact image key: ${image_key}"
        actual_image_key_count=$((actual_image_key_count + 1))
    done < <(manifest_artifact_image_keys "${manifest}")
    [[ "${actual_image_key_count}" == "${expected_image_key_count}" ]] || \
        phase4_die "release manifest must contain exactly ${expected_image_key_count} artifact image entries; found ${actual_image_key_count}"
}

validate_image_refs() {
    local service repo image_ref expected_pattern

    release_version="$(normalize_release_version "${release_version}")"

    for service in "${SERVICE_ORDER[@]}"; do
        repo="${IMAGE_REPOS[${service}]}"
        image_ref="${IMAGE_REFS[${service}]:-}"
        [[ -n "${image_ref}" ]] || phase4_die "missing image ref for ${service}"

        expected_pattern="^ghcr\\.io/budgetanalyzer/${repo}:${release_version}@sha256:[0-9a-f]{64}$"
        if [[ ! "${image_ref}" =~ ${expected_pattern} ]]; then
            phase4_die "invalid image ref for ${service}; expected ghcr.io/budgetanalyzer/${repo}:${release_version}@sha256:<64 lowercase hex>, got: ${image_ref}"
        fi

        if [[ "${image_ref}" == *":latest"* || "${image_ref}" == *":tilt-"* ]]; then
            phase4_die "mutable image ref is not allowed for ${service}: ${image_ref}"
        fi
    done
}

write_image_inventory() {
    local temp_file

    temp_file="${PRODUCTION_IMAGE_INVENTORY}.tmp"
    cat > "${temp_file}" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: production-image-inventory
  namespace: default
  labels:
    app.kubernetes.io/part-of: budget-analyzer
    app.kubernetes.io/component: production-image-inventory
data:
  release-version: "${release_version}"
  transaction-service: "${IMAGE_REFS[transaction-service]}"
  currency-service: "${IMAGE_REFS[currency-service]}"
  permission-service: "${IMAGE_REFS[permission-service]}"
  session-gateway: "${IMAGE_REFS[session-gateway]}"
  budget-analyzer-web: "${IMAGE_REFS[budget-analyzer-web]}"
  ext-authz: "${IMAGE_REFS[ext-authz]}"
EOF
    mv "${temp_file}" "${PRODUCTION_IMAGE_INVENTORY}"
}

artifact_source_repo() {
    local service="$1"

    printf '%s\n' "${SOURCE_REPOS[${service}]:-${ARTIFACT_SOURCE_REPOS[${service}]}}"
}

artifact_revision() {
    local service="$1"
    local source_repo

    source_repo="$(artifact_source_repo "${service}")"
    printf '%s\n' "${COMMIT_SHAS[${source_repo}]:-}"
}

write_release_metadata_json_file() {
    local output_path="$1"
    local temp_file="${output_path}.tmp"
    local service
    local index=0

    mkdir -p "$(dirname "${output_path}")"

    {
        printf '{\n'
        printf '  "release": {\n'
        printf '    "version": "v%s",\n' "${release_version}"
        printf '    "imageTag": "%s"\n' "${release_version}"
        printf '  },\n'
        printf '  "artifacts": {\n'
        for service in "${SERVICE_ORDER[@]}"; do
            if [[ "${index}" -gt 0 ]]; then
                printf ',\n'
            fi
            printf '    "%s": {\n' "${service}"
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
    local image_ref="$3"
    local revision="$4"

    cat >> "${temp_file}" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${workload}
  namespace: default
  labels:
    app.kubernetes.io/name: ${workload}
    app.kubernetes.io/part-of: budget-analyzer
    budgetanalyzer.org/environment-release: v${release_version}
  annotations:
    budgetanalyzer.org/release-version: v${release_version}
    budgetanalyzer.org/image: ${image_ref}
    org.opencontainers.image.version: ${release_version}
EOF

    if [[ -n "${revision}" ]]; then
        cat >> "${temp_file}" <<EOF
    org.opencontainers.image.revision: ${revision}
EOF
    fi

    cat >> "${temp_file}" <<EOF
spec:
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${workload}
        app.kubernetes.io/part-of: budget-analyzer
        budgetanalyzer.org/environment-release: v${release_version}
      annotations:
        budgetanalyzer.org/release-version: v${release_version}
        budgetanalyzer.org/image: ${image_ref}
        org.opencontainers.image.version: ${release_version}
EOF

    if [[ -n "${revision}" ]]; then
        cat >> "${temp_file}" <<EOF
        org.opencontainers.image.revision: ${revision}
EOF
    fi
}

write_runtime_release_metadata_patch() {
    local temp_file="${PRODUCTION_RUNTIME_METADATA_PATCH}.tmp"
    local service
    local revision

    : > "${temp_file}"

    for service in "${RUNTIME_DEPLOYMENT_ORDER[@]}"; do
        revision="$(artifact_revision "${service}")"
        write_runtime_metadata_document "${temp_file}" "${service}" "${IMAGE_REFS[${service}]}" "${revision}"
        printf -- '---\n' >> "${temp_file}"
    done

    revision="$(artifact_revision "budget-analyzer-web")"
    write_runtime_metadata_document "${temp_file}" "nginx-gateway" "${IMAGE_REFS[budget-analyzer-web]}" "${revision}"

    mv "${temp_file}" "${PRODUCTION_RUNTIME_METADATA_PATCH}"
}

replace_literal_in_file() {
    local file="$1"
    local old="$2"
    local new="$3"
    local temp_file
    local escaped_old
    local escaped_new

    [[ -f "${file}" ]] || return 0
    [[ "${old}" != "${new}" ]] || return 0

    escaped_old="$(phase4_escape_sed_replacement "${old}")"
    escaped_new="$(phase4_escape_sed_replacement "${new}")"
    temp_file="${file}.tmp"

    sed "s/${escaped_old}/${escaped_new}/g" "${file}" > "${temp_file}"
    mv "${temp_file}" "${file}"
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

update_release_version_references() {
    local old_release_version="$1"
    local doc

    replace_literal_in_file "${INSTANCE_ENV_TEMPLATE}" \
        "PRODUCTION_RELEASE_VERSION=${old_release_version}" \
        "PRODUCTION_RELEASE_VERSION=${release_version}"

    for doc in \
        "$(phase4_repo_path "kubernetes/production/README.md")" \
        "$(phase4_repo_path "scripts/README.md")" \
        "$(phase4_repo_path "docs/ci-cd.md")"; do
        replace_literal_in_file "${doc}" "${old_release_version}" "${release_version}"
        replace_literal_in_file "${doc}" "v${old_release_version}" "v${release_version}"
    done
}

verify_updates() {
    phase4_require_commands kubectl

    kubectl kustomize "${PRODUCTION_APPS_DIR}" --load-restrictor=LoadRestrictionsNone >/dev/null

    if [[ -x "${LOCKSTEP_VERIFIER}" ]]; then
        "${LOCKSTEP_VERIFIER}"
    else
        phase4_warn "lockstep verifier is not executable yet: ${LOCKSTEP_VERIFIER}"
    fi

    if [[ "${skip_live_production_verifier}" == false ]]; then
        "${PRODUCTION_IMAGE_VERIFIER}"
    else
        phase4_warn "skipped live production verifier; run ${PRODUCTION_IMAGE_VERIFIER} before OCI apply"
    fi
}

main() {
    local release_manifest=""
    local old_release_version
    local explicit_image_count=0

    release_version=""
    skip_live_production_verifier=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release-version)
                release_version="${2:-}"
                shift
                ;;
            --release-manifest)
                release_manifest="${2:-}"
                [[ -n "${release_manifest}" ]] || phase4_die "missing value for --release-manifest"
                shift
                ;;
            --transaction-service|--currency-service|--permission-service|--session-gateway|--budget-analyzer-web|--ext-authz)
                IMAGE_REFS["${1#--}"]="${2:-}"
                [[ -n "${IMAGE_REFS[${1#--}]}" ]] || phase4_die "missing value for $1"
                explicit_image_count=$((explicit_image_count + 1))
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

    [[ -f "${PRODUCTION_IMAGE_INVENTORY}" ]] || phase4_die "missing image inventory: ${PRODUCTION_IMAGE_INVENTORY}"
    [[ -f "${PRODUCTION_KUSTOMIZATION}" ]] || phase4_die "missing production kustomization: ${PRODUCTION_KUSTOMIZATION}"

    if [[ -n "${release_manifest}" ]]; then
        [[ "${explicit_image_count}" -eq 0 ]] || phase4_die "use either --release-manifest or explicit image arguments, not both"
        if [[ "${release_manifest}" != /* && ! -f "${release_manifest}" ]]; then
            release_manifest="$(phase4_repo_path "${release_manifest}")"
        fi
        load_manifest "${release_manifest}"
    fi

    [[ -n "${release_version}" ]] || phase4_die "missing --release-version or release-version in manifest"
    old_release_version="$(inventory_value "release-version")"
    [[ -n "${old_release_version}" ]] || phase4_die "current production image inventory is missing release-version"

    validate_image_refs
    update_kustomization
    write_image_inventory
    write_release_metadata_json
    write_runtime_release_metadata_patch
    update_release_version_references "${old_release_version}"
    verify_updates

    phase4_info "updated production release image baseline to ${release_version}"
    phase4_info "review the diff before tagging or deploying to OCI"
}

main "$@"
