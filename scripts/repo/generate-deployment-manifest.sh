#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/repo-config.sh"

DEFAULT_INVENTORY="${REPO_ROOT}/kubernetes/production/apps/image-inventory.yaml"

SERVICE_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly SERVICE_ORDER

JAVA_SERVICES=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
)
readonly JAVA_SERVICES

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

declare -A IMAGE_REFS=()
declare -A ARTIFACT_VERSIONS=()
declare -A SOURCE_REFS=()
declare -A SOURCE_COMMITS=()
declare -A SERVICE_COMMON_VERSIONS=()
declare -A OVERRIDE_IMAGE_REFS=()
declare -A OVERRIDE_ARTIFACT_VERSIONS=()
declare -A OVERRIDE_SOURCE_REFS=()
declare -A OVERRIDE_SOURCE_COMMITS=()

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/generate-deployment-manifest.sh \
    --deployment-id oci-YYYYMMDD.N \
    --status candidate|accepted \
    --output tmp/deployments/oci-YYYYMMDD.N.yaml

Options:
  --inventory PATH                         Existing production image inventory.
                                           Defaults to kubernetes/production/apps/image-inventory.yaml.
  --deployment-id ID                       Required deployment identity.
  --status STATUS                          Deployment status. Defaults to candidate.
  --output PATH                            Output manifest path.
  --artifact-image service=image           Override one artifact image. Ref must be digest-pinned.
  --artifact-version service=version       Override one artifact version.
  --source-ref service=ref                 Override one artifact source ref.
  --source-commit service=sha              Override one artifact source commit.
  --service-common-version version         Set the Java services' shared-library version.
  --service-common-version service=version Set one Java service shared-library version.
  --platform-changed                       Set phase_flags.platform_changed true.
  --infrastructure-changed                 Set phase_flags.infrastructure_changed true.
  --secrets-changed                        Set phase_flags.secrets_changed true.
  --observability-changed                  Set phase_flags.observability_changed true.
  --public-tls-reapply-required            Set phase_flags.public_tls_reapply_required true.
  --force                                  Overwrite an existing output file.
  -h, --help                               Show this help.

The script starts from the checked-in production image inventory, preserves
unchanged artifact digests, and writes a schema_version: 2 deployment manifest.
Use repeated override flags to describe the artifacts being changed.
EOF
}

info() {
    printf '[deployment-manifest] %s\n' "$*"
}

die() {
    printf '[deployment-manifest] ERROR: %s\n' "$*" >&2
    exit 1
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

is_java_service() {
    local candidate="$1"
    local service

    for service in "${JAVA_SERVICES[@]}"; do
        if [[ "${service}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

valid_digest_pinned_image() {
    local service="$1"
    local image_ref="$2"
    local repo="${IMAGE_REPOS[${service}]}"
    local pattern

    pattern="^ghcr\\.io/budgetanalyzer/${repo}:[A-Za-z0-9_.-]+@sha256:[0-9a-f]{64}$"
    [[ "${image_ref}" =~ ${pattern} ]] || return 1
    [[ "${image_ref}" != *":latest@"* && "${image_ref}" != *":tilt-"* ]]
}

valid_commit_sha() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

inventory_value() {
    local inventory="$1"
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
    ' "${inventory}"
}

image_tag() {
    local image_ref="$1"

    printf '%s\n' "${image_ref}" | sed -E 's#^ghcr\.io/budgetanalyzer/[a-z0-9-]+:([^@]+)@sha256:[0-9a-f]{64}$#\1#'
}

repo_commit_sha() {
    local repo="$1"
    local repo_path="${PARENT_DIR}/${repo}"

    [[ -d "${repo_path}/.git" ]] || die "missing git repository: ../${repo}"
    git -C "${repo_path}" rev-parse HEAD
}

repo_symbolic_ref() {
    local repo="$1"
    local repo_path="${PARENT_DIR}/${repo}"
    local branch

    branch="$(git -C "${repo_path}" symbolic-ref -q --short HEAD || true)"
    if [[ -n "${branch}" ]]; then
        printf 'refs/heads/%s\n' "${branch}"
    else
        git -C "${repo_path}" rev-parse HEAD
    fi
}

repo_ref_commit() {
    local repo="$1"
    local ref="$2"
    local repo_path="${PARENT_DIR}/${repo}"

    [[ -d "${repo_path}/.git" ]] || die "missing git repository: ../${repo}"
    git -C "${repo_path}" rev-parse --verify "${ref}^{commit}" 2>/dev/null || true
}

parse_assignment() {
    local assignment="$1"
    local service="${assignment%%=*}"
    local value="${assignment#*=}"

    [[ "${assignment}" == *=* ]] || die "assignment must use service=value form: ${assignment}"
    service_exists "${service}" || die "unknown artifact: ${service}"
    [[ -n "${value}" ]] || die "empty value for ${service}"

    printf '%s\t%s\n' "${service}" "${value}"
}

load_inventory() {
    local inventory="$1"
    local service image_ref version source_repo source_commit

    [[ -f "${inventory}" ]] || die "inventory not found: ${inventory}"

    for service in "${SERVICE_ORDER[@]}"; do
        image_ref="$(inventory_value "${inventory}" "${service}")"
        [[ -n "${image_ref}" ]] || die "inventory is missing ${service}"
        valid_digest_pinned_image "${service}" "${image_ref}" || die "invalid digest-pinned image for ${service}: ${image_ref}"

        version="$(inventory_value "${inventory}" "${service}.artifact-version")"
        if [[ -z "${version}" ]]; then
            version="$(image_tag "${image_ref}")"
        fi

        source_repo="${ARTIFACT_SOURCE_REPOS[${service}]}"
        IMAGE_REFS["${service}"]="${image_ref}"
        ARTIFACT_VERSIONS["${service}"]="${version}"
        SOURCE_REFS["${service}"]="$(inventory_value "${inventory}" "${service}.source-ref")"
        SOURCE_COMMITS["${service}"]="$(inventory_value "${inventory}" "${service}.source-commit")"

        if [[ -z "${SOURCE_REFS[${service}]}" ]]; then
            if [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                SOURCE_REFS["${service}"]="refs/tags/v${version}"
            else
                SOURCE_REFS["${service}"]="refs/tags/${version}"
            fi
        fi
        if [[ -z "${SOURCE_COMMITS[${service}]}" ]]; then
            source_commit="$(repo_ref_commit "${source_repo}" "${SOURCE_REFS[${service}]}")"
            if [[ -n "${source_commit}" ]]; then
                SOURCE_COMMITS["${service}"]="${source_commit}"
            fi
        fi
    done
}

set_service_common_version() {
    local assignment="$1"
    local service version

    if [[ "${assignment}" == *=* ]]; then
        service="${assignment%%=*}"
        version="${assignment#*=}"
        service_exists "${service}" || die "unknown artifact for --service-common-version: ${service}"
        is_java_service "${service}" || die "--service-common-version service=version is only valid for Java runtime services: ${service}"
        [[ -n "${version}" ]] || die "empty service-common version for ${service}"
        SERVICE_COMMON_VERSIONS["${service}"]="${version}"
        return
    fi

    for service in "${JAVA_SERVICES[@]}"; do
        SERVICE_COMMON_VERSIONS["${service}"]="${assignment}"
    done
}

validate_manifest_inputs() {
    local service image_ref source_commit

    for service in "${SERVICE_ORDER[@]}"; do
        image_ref="${IMAGE_REFS[${service}]:-}"
        [[ -n "${image_ref}" ]] || die "missing image for ${service}"
        valid_digest_pinned_image "${service}" "${image_ref}" || die "invalid digest-pinned image for ${service}: ${image_ref}"

        [[ -n "${ARTIFACT_VERSIONS[${service}]:-}" ]] || die "missing artifact version for ${service}"
        [[ -n "${SOURCE_REFS[${service}]:-}" ]] || die "missing source ref for ${service}"

        source_commit="${SOURCE_COMMITS[${service}]:-}"
        [[ -n "${source_commit}" ]] || die "missing source commit for ${service}; pass --source-commit ${service}=<sha>"
        valid_commit_sha "${source_commit}" || die "invalid source commit for ${service}: ${source_commit}"
    done
}

write_manifest() {
    local output_path="$1"
    local deployment_id="$2"
    local status="$3"
    local platform_changed="$4"
    local infrastructure_changed="$5"
    local secrets_changed="$6"
    local observability_changed="$7"
    local public_tls_reapply_required="$8"
    local temp_file="${output_path}.tmp"
    local service source_repo

    mkdir -p "$(dirname "${output_path}")"

    {
        printf 'schema_version: 2\n'
        printf 'deployment:\n'
        printf '  id: "%s"\n' "${deployment_id}"
        printf '  environment: "oci-production"\n'
        printf '  status: "%s"\n' "${status}"
        printf '  orchestration_repository:\n'
        printf '    commit: "%s"\n' "$(repo_commit_sha "orchestration")"
        printf '    source_ref: "%s"\n' "$(repo_symbolic_ref "orchestration")"
        printf 'artifacts:\n'
        for service in "${SERVICE_ORDER[@]}"; do
            source_repo="${ARTIFACT_SOURCE_REPOS[${service}]}"
            printf '  %s:\n' "${service}"
            printf '    source_repository: "%s"\n' "${source_repo}"
            printf '    source_ref: "%s"\n' "${SOURCE_REFS[${service}]}"
            printf '    source_commit: "%s"\n' "${SOURCE_COMMITS[${service}]}"
            printf '    artifact_version: "%s"\n' "${ARTIFACT_VERSIONS[${service}]}"
            printf '    image: "%s"\n' "${IMAGE_REFS[${service}]}"
            if [[ -n "${SERVICE_COMMON_VERSIONS[${service}]:-}" ]]; then
                printf '    service_common_version: "%s"\n' "${SERVICE_COMMON_VERSIONS[${service}]}"
            fi
        done
        printf 'phase_flags:\n'
        printf '  platform_changed: %s\n' "${platform_changed}"
        printf '  infrastructure_changed: %s\n' "${infrastructure_changed}"
        printf '  secrets_changed: %s\n' "${secrets_changed}"
        printf '  observability_changed: %s\n' "${observability_changed}"
        printf '  public_tls_reapply_required: %s\n' "${public_tls_reapply_required}"
    } > "${temp_file}"

    mv "${temp_file}" "${output_path}"
}

main() {
    local inventory="${DEFAULT_INVENTORY}"
    local deployment_id=""
    local status="candidate"
    local output_path=""
    local force=false
    local platform_changed=false
    local infrastructure_changed=false
    local secrets_changed=false
    local observability_changed=false
    local public_tls_reapply_required=false
    local parsed service value source_repo source_commit

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --inventory)
                inventory="${2:-}"
                [[ -n "${inventory}" ]] || die "missing value for --inventory"
                shift
                ;;
            --deployment-id)
                deployment_id="${2:-}"
                [[ -n "${deployment_id}" ]] || die "missing value for --deployment-id"
                shift
                ;;
            --status)
                status="${2:-}"
                [[ -n "${status}" ]] || die "missing value for --status"
                shift
                ;;
            --output)
                output_path="${2:-}"
                [[ -n "${output_path}" ]] || die "missing value for --output"
                shift
                ;;
            --artifact-image)
                parsed="$(parse_assignment "${2:-}")"
                service="${parsed%%$'\t'*}"
                value="${parsed#*$'\t'}"
                OVERRIDE_IMAGE_REFS["${service}"]="${value}"
                OVERRIDE_ARTIFACT_VERSIONS["${service}"]="$(image_tag "${value}")"
                shift
                ;;
            --artifact-version)
                parsed="$(parse_assignment "${2:-}")"
                service="${parsed%%$'\t'*}"
                value="${parsed#*$'\t'}"
                OVERRIDE_ARTIFACT_VERSIONS["${service}"]="${value}"
                shift
                ;;
            --source-ref)
                parsed="$(parse_assignment "${2:-}")"
                service="${parsed%%$'\t'*}"
                value="${parsed#*$'\t'}"
                OVERRIDE_SOURCE_REFS["${service}"]="${value}"
                source_repo="${ARTIFACT_SOURCE_REPOS[${service}]}"
                source_commit="$(repo_ref_commit "${source_repo}" "${value}")"
                if [[ -n "${source_commit}" ]]; then
                    OVERRIDE_SOURCE_COMMITS["${service}"]="${source_commit}"
                fi
                shift
                ;;
            --source-commit)
                parsed="$(parse_assignment "${2:-}")"
                service="${parsed%%$'\t'*}"
                value="${parsed#*$'\t'}"
                OVERRIDE_SOURCE_COMMITS["${service}"]="${value}"
                shift
                ;;
            --service-common-version)
                set_service_common_version "${2:-}"
                shift
                ;;
            --platform-changed)
                platform_changed=true
                ;;
            --infrastructure-changed)
                infrastructure_changed=true
                ;;
            --secrets-changed)
                secrets_changed=true
                ;;
            --observability-changed)
                observability_changed=true
                ;;
            --public-tls-reapply-required)
                public_tls_reapply_required=true
                ;;
            --force)
                force=true
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

    [[ -n "${deployment_id}" ]] || die "missing --deployment-id"
    [[ -n "${output_path}" ]] || output_path="${REPO_ROOT}/tmp/deployments/${deployment_id}.yaml"

    if [[ "${inventory}" != /* ]]; then
        inventory="${REPO_ROOT}/${inventory}"
    fi
    if [[ "${output_path}" != /* ]]; then
        output_path="${REPO_ROOT}/${output_path}"
    fi

    if [[ -e "${output_path}" && "${force}" != true ]]; then
        die "output file already exists: ${output_path}; use --force to overwrite"
    fi

    load_inventory "${inventory}"

    for service in "${SERVICE_ORDER[@]}"; do
        if [[ -n "${OVERRIDE_IMAGE_REFS[${service}]:-}" ]]; then
            IMAGE_REFS["${service}"]="${OVERRIDE_IMAGE_REFS[${service}]}"
        fi
        if [[ -n "${OVERRIDE_ARTIFACT_VERSIONS[${service}]:-}" ]]; then
            ARTIFACT_VERSIONS["${service}"]="${OVERRIDE_ARTIFACT_VERSIONS[${service}]}"
        fi
        if [[ -n "${OVERRIDE_SOURCE_REFS[${service}]:-}" ]]; then
            SOURCE_REFS["${service}"]="${OVERRIDE_SOURCE_REFS[${service}]}"
        fi
        if [[ -n "${OVERRIDE_SOURCE_COMMITS[${service}]:-}" ]]; then
            SOURCE_COMMITS["${service}"]="${OVERRIDE_SOURCE_COMMITS[${service}]}"
        fi
    done

    validate_manifest_inputs
    write_manifest \
        "${output_path}" \
        "${deployment_id}" \
        "${status}" \
        "${platform_changed}" \
        "${infrastructure_changed}" \
        "${secrets_changed}" \
        "${observability_changed}" \
        "${public_tls_reapply_required}"

    info "wrote ${output_path}"
}

main "$@"
