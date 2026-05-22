#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

REPO_ROOT="${PHASE4_REPO_ROOT}"
PARENT_DIR="$(dirname "${REPO_ROOT}")"
PRODUCTION_APPS_DIR="${REPO_ROOT}/kubernetes/production/apps"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
PRODUCTION_DEPLOYMENT_MANIFEST="${PRODUCTION_APPS_DIR}/deployment-manifest.yaml"
UPDATE_PRODUCTION_BASELINE="${SCRIPT_DIR}/23-update-production-release-images.sh"
DEPLOY_OCI_RELEASE="${SCRIPT_DIR}/25-deploy-oci-release.sh"
PROMOTION_OUTPUT_ROOT="${REPO_ROOT}/tmp/deployments"
readonly REPO_ROOT
readonly PARENT_DIR
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly PRODUCTION_DEPLOYMENT_MANIFEST
readonly UPDATE_PRODUCTION_BASELINE
readonly DEPLOY_OCI_RELEASE
readonly PROMOTION_OUTPUT_ROOT

ARTIFACT_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly ARTIFACT_ORDER

JAVA_ARTIFACTS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
)
readonly JAVA_ARTIFACTS

declare -A IMAGE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="ext-authz"
)

declare -A SOURCE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="orchestration"
)

declare -A DOCKERFILES=(
    ["transaction-service"]="Dockerfile"
    ["currency-service"]="Dockerfile"
    ["permission-service"]="Dockerfile"
    ["session-gateway"]="Dockerfile"
    ["budget-analyzer-web"]="Dockerfile.production"
    ["ext-authz"]="Dockerfile"
)

declare -A BUILD_SUBPATHS=(
    ["transaction-service"]="."
    ["currency-service"]="."
    ["permission-service"]="."
    ["session-gateway"]="."
    ["budget-analyzer-web"]="."
    ["ext-authz"]="ext-authz"
)

declare -A BASELINE_IMAGES=()
declare -A BASELINE_ARTIFACT_VERSIONS=()
declare -A BASELINE_SOURCE_REFS=()
declare -A BASELINE_SOURCE_COMMITS=()
declare -A BASELINE_SERVICE_COMMON_VERSIONS=()
declare -A BASELINE_CONTENT_IDENTITIES=()

declare -A CURRENT_SOURCE_REFS=()
declare -A CURRENT_SOURCE_COMMITS=()
declare -A CURRENT_WORKSPACE_STATES=()
declare -A CURRENT_CONTENT_IDENTITIES=()
declare -A CURRENT_SERVICE_COMMON_VERSIONS=()

declare -A FINAL_IMAGES=()
declare -A FINAL_ARTIFACT_VERSIONS=()
declare -A FINAL_SOURCE_REFS=()
declare -A FINAL_SOURCE_COMMITS=()
declare -A FINAL_SERVICE_COMMON_VERSIONS=()

declare -A BUILD_DECISIONS=()
declare -A BUILD_REASONS=()

deployment_id=""
allow_dirty=false
plan_only=false
skip_live_production_verifier=false
explicit_kubeconfig=""
baseline_deployment_id=""
orchestration_commit=""
orchestration_source_ref=""
orchestration_workspace_state=""
orchestration_content_identity=""
plan_output_path=""
deployment_output_path=""

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/promote-current-stack-to-oci.sh [options]

Options:
  --deployment-id ID                 Deployment id. Defaults to
                                     oci-<UTC timestamp>.
  --allow-dirty                      Allow dirty app/orchestration workspaces
                                     to be promoted. Dirty service-common can
                                     be inspected with --plan-only but is
                                     rejected for actual promotion because
                                     release Dockerfiles consume published
                                     packages.
  --plan-only                        Generate and print the change-set diff
                                     without building, pushing, updating the
                                     production baseline, or applying OCI.
  --skip-live-production-verifier    Pass through to the production baseline
                                     updater when a live verifier is not
                                     available from this shell.
  --kubeconfig PATH                  Pass through to the OCI apply wrapper.
  -h, --help                         Show this help.

The command promotes the current intended workspace stack by convention:
all managed workloads are discovered from the repository map, unchanged
digest-pinned images and runtime metadata are carried forward, changed
workloads are built and pushed as linux/arm64 GHCR images, one complete
schema v2 deployment snapshot is written, the checked-in production baseline
is updated from that snapshot, and the managed production app set is applied.

Use --plan-only when you need a non-mutating diff before changing OCI.
EOF
}

die() {
    phase4_die "$1"
}

info() {
    phase4_info "$*"
}

warn() {
    phase4_warn "$*"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment-id)
                deployment_id="${2:-}"
                [[ -n "${deployment_id}" ]] || die "missing value for --deployment-id"
                shift
                ;;
            --allow-dirty)
                allow_dirty=true
                ;;
            --plan-only)
                plan_only=true
                ;;
            --skip-live-production-verifier)
                skip_live_production_verifier=true
                ;;
            --kubeconfig)
                explicit_kubeconfig="${2:-}"
                [[ -n "${explicit_kubeconfig}" ]] || die "missing value for --kubeconfig"
                shift
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

is_java_artifact() {
    local target="$1"
    local artifact

    for artifact in "${JAVA_ARTIFACTS[@]}"; do
        if [[ "${artifact}" == "${target}" ]]; then
            return 0
        fi
    done

    return 1
}

repo_path_for_source_repo() {
    local source_repo="$1"

    if [[ "${source_repo}" == "orchestration" ]]; then
        printf '%s\n' "${REPO_ROOT}"
        return
    fi

    printf '%s/%s\n' "${PARENT_DIR}" "${source_repo}"
}

artifact_context_path() {
    local artifact="$1"
    local source_repo="${SOURCE_REPOS[${artifact}]}"
    local repo_path
    local build_subpath="${BUILD_SUBPATHS[${artifact}]}"

    repo_path="$(repo_path_for_source_repo "${source_repo}")"
    if [[ "${build_subpath}" == "." ]]; then
        printf '%s\n' "${repo_path}"
    else
        printf '%s/%s\n' "${repo_path}" "${build_subpath}"
    fi
}

artifact_dockerfile_path() {
    local artifact="$1"
    local context_path

    context_path="$(artifact_context_path "${artifact}")"
    printf '%s/%s\n' "${context_path}" "${DOCKERFILES[${artifact}]}"
}

valid_commit_sha() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
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

image_ref_tag() {
    local image_ref="$1"

    printf '%s\n' "${image_ref}" | sed -E 's#^ghcr\.io/budgetanalyzer/[a-z0-9-]+:([^@]+)@sha256:[0-9a-f]{64}$#\1#'
}

valid_digest_pinned_image() {
    local artifact="$1"
    local image_ref="$2"
    local repo="${IMAGE_REPOS[${artifact}]}"
    local pattern

    pattern="^ghcr\\.io/budgetanalyzer/${repo}:[A-Za-z0-9_.-]+@sha256:[0-9a-f]{64}$"
    [[ "${image_ref}" =~ ${pattern} ]] || return 1
    [[ "${image_ref}" != *":latest@"* && "${image_ref}" != *":tilt-"* ]]
}

repo_is_dirty() {
    local repo_path="$1"

    [[ -n "$(git -C "${repo_path}" status --porcelain --untracked-files=all)" ]]
}

repo_workspace_state() {
    local repo_path="$1"

    if repo_is_dirty "${repo_path}"; then
        printf '%s\n' "dirty"
    else
        printf '%s\n' "clean"
    fi
}

path_is_dirty() {
    local repo_path="$1"
    local pathspec="$2"

    [[ -n "$(git -C "${repo_path}" status --porcelain --untracked-files=all -- "${pathspec}")" ]]
}

path_workspace_state() {
    local repo_path="$1"
    local pathspec="$2"

    if path_is_dirty "${repo_path}" "${pathspec}"; then
        printf '%s\n' "dirty"
    else
        printf '%s\n' "clean"
    fi
}

repo_source_ref() {
    local repo_path="$1"
    local branch

    branch="$(git -C "${repo_path}" symbolic-ref -q --short HEAD || true)"
    if [[ -n "${branch}" ]]; then
        printf 'refs/heads/%s\n' "${branch}"
    else
        git -C "${repo_path}" rev-parse HEAD
    fi
}

path_content_identity() {
    local repo_path="$1"
    local pathspec="$2"

    {
        {
            git -C "${repo_path}" ls-files -z -- "${pathspec}"
            git -C "${repo_path}" ls-files -z --others --exclude-standard -- "${pathspec}"
        } | LC_ALL=C sort -zu | while IFS= read -r -d '' path; do
            printf 'path:%s\n' "${path}"
            if [[ -f "${repo_path}/${path}" ]]; then
                sha256sum "${repo_path}/${path}"
            else
                printf 'missing\n'
            fi
        done
    } | sha256sum | awk '{print "sha256:" $1}'
}

short_identity() {
    local identity="$1"

    printf '%s\n' "${identity#*:}" | cut -c1-12
}

read_service_common_version() {
    local repo_path="$1"
    local version_file="${repo_path}/gradle/libs.versions.toml"

    [[ -f "${version_file}" ]] || die "missing version catalog: ${version_file}"
    awk -F= '
        /^[[:space:]]*serviceCommon[[:space:]]*=/ {
            value = $2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
        }
    ' "${version_file}"
}

sanitize_docker_tag() {
    local raw="$1"
    local sanitized

    sanitized="$(printf '%s\n' "${raw}" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//')"
    sanitized="$(printf '%s\n' "${sanitized}" | cut -c1-128)"
    [[ -n "${sanitized}" ]] || die "could not derive Docker tag from ${raw}"
    printf '%s\n' "${sanitized}"
}

load_baseline() {
    local artifact image artifact_version source_ref source_commit service_common_version

    [[ -f "${PRODUCTION_IMAGE_INVENTORY}" ]] || die "missing production image inventory: ${PRODUCTION_IMAGE_INVENTORY}"
    [[ -f "${PRODUCTION_DEPLOYMENT_MANIFEST}" ]] || die "missing production deployment manifest: ${PRODUCTION_DEPLOYMENT_MANIFEST}"
    [[ "$(manifest_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "schema_version")" == "2" ]] || \
        die "production deployment manifest must use schema_version: 2"

    baseline_deployment_id="$(manifest_map_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "deployment" "id")"
    [[ -n "${baseline_deployment_id}" ]] || die "production deployment manifest is missing deployment.id"

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        image="$(manifest_nested_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "image")"
        artifact_version="$(manifest_nested_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "artifact_version")"
        source_ref="$(manifest_nested_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "source_ref")"
        source_commit="$(manifest_nested_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "source_commit")"
        service_common_version="$(manifest_nested_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "service_common_version")"

        [[ -n "${image}" ]] || image="$(inventory_value "${artifact}")"
        [[ -n "${artifact_version}" ]] || artifact_version="$(inventory_value "${artifact}.artifact-version")"
        [[ -n "${source_ref}" ]] || source_ref="$(inventory_value "${artifact}.source-ref")"
        [[ -n "${source_commit}" ]] || source_commit="$(inventory_value "${artifact}.source-commit")"
        if [[ -z "${service_common_version}" ]]; then
            service_common_version="$(inventory_value "${artifact}.service-common-version")"
        fi

        [[ -n "${image}" ]] || die "baseline is missing image for ${artifact}"
        valid_digest_pinned_image "${artifact}" "${image}" || die "baseline image for ${artifact} is not digest-pinned: ${image}"
        [[ -n "${artifact_version}" ]] || die "baseline is missing artifact version for ${artifact}"
        [[ -n "${source_ref}" ]] || die "baseline is missing source ref for ${artifact}"
        valid_commit_sha "${source_commit}" || die "baseline is missing valid source commit for ${artifact}"
        if is_java_artifact "${artifact}" && [[ -z "${service_common_version}" ]]; then
            die "baseline is missing service_common_version for Java artifact ${artifact}"
        fi

        BASELINE_IMAGES["${artifact}"]="${image}"
        BASELINE_ARTIFACT_VERSIONS["${artifact}"]="${artifact_version}"
        BASELINE_SOURCE_REFS["${artifact}"]="${source_ref}"
        BASELINE_SOURCE_COMMITS["${artifact}"]="${source_commit}"
        BASELINE_SERVICE_COMMON_VERSIONS["${artifact}"]="${service_common_version}"
        BASELINE_CONTENT_IDENTITIES["${artifact}"]="$(manifest_nested_value "${PRODUCTION_DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "content_identity")"
    done
}

validate_repo_layout() {
    local artifact source_repo repo_path context_path dockerfile_path
    local service_common_repo="${PARENT_DIR}/service-common"

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        source_repo="${SOURCE_REPOS[${artifact}]}"
        repo_path="$(repo_path_for_source_repo "${source_repo}")"
        [[ -d "${repo_path}/.git" ]] || die "missing git repository for ${artifact}: ${repo_path}"

        context_path="$(artifact_context_path "${artifact}")"
        dockerfile_path="$(artifact_dockerfile_path "${artifact}")"
        [[ -d "${context_path}" ]] || die "missing build context for ${artifact}: ${context_path}"
        [[ -f "${dockerfile_path}" ]] || die "missing Dockerfile for ${artifact}: ${dockerfile_path}"
    done

    [[ -d "${service_common_repo}/.git" ]] || die "missing git repository: ${service_common_repo}"
}

discover_current_workspace() {
    local artifact source_repo repo_path build_subpath service_common_version

    orchestration_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
    orchestration_source_ref="$(repo_source_ref "${REPO_ROOT}")"
    orchestration_workspace_state="$(repo_workspace_state "${REPO_ROOT}")"
    orchestration_content_identity="$(path_content_identity "${REPO_ROOT}" ".")"

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        source_repo="${SOURCE_REPOS[${artifact}]}"
        repo_path="$(repo_path_for_source_repo "${source_repo}")"
        build_subpath="${BUILD_SUBPATHS[${artifact}]}"

        CURRENT_SOURCE_COMMITS["${artifact}"]="$(git -C "${repo_path}" rev-parse HEAD)"
        CURRENT_SOURCE_REFS["${artifact}"]="$(repo_source_ref "${repo_path}")"
        CURRENT_WORKSPACE_STATES["${artifact}"]="$(path_workspace_state "${repo_path}" "${build_subpath}")"
        CURRENT_CONTENT_IDENTITIES["${artifact}"]="$(path_content_identity "${repo_path}" "${build_subpath}")"

        if is_java_artifact "${artifact}"; then
            service_common_version="$(read_service_common_version "${repo_path}")"
            [[ -n "${service_common_version}" ]] || die "missing serviceCommon version for ${artifact}"
            CURRENT_SERVICE_COMMON_VERSIONS["${artifact}"]="${service_common_version}"
        fi
    done
}

enforce_dirty_policy() {
    local dirty_repos=()
    local repo_name repo_path

    for repo_name in orchestration service-common transaction-service currency-service permission-service session-gateway budget-analyzer-web; do
        repo_path="$(repo_path_for_source_repo "${repo_name}")"
        if repo_is_dirty "${repo_path}"; then
            dirty_repos+=("${repo_name}")
        fi
    done

    if repo_is_dirty "$(repo_path_for_source_repo "service-common")"; then
        if [[ "${plan_only}" == "true" ]]; then
            warn "service-common has uncommitted changes; actual promotion will reject this until service-common is released/published and Java consumers are updated"
        else
            die "service-common has uncommitted changes. Release/publish service-common and update Java consumers before OCI promotion."
        fi
    fi

    if (( ${#dirty_repos[@]} > 0 )) && [[ "${allow_dirty}" != "true" ]]; then
        die "dirty workspaces are not promoted by default: ${dirty_repos[*]}. Re-run with --allow-dirty only when those local changes are intentionally deployable."
    fi
}

decide_builds() {
    local artifact reason baseline_content current_content current_version baseline_version

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        reason=""
        baseline_content="${BASELINE_CONTENT_IDENTITIES[${artifact}]:-}"
        current_content="${CURRENT_CONTENT_IDENTITIES[${artifact}]}"

        if [[ "${CURRENT_WORKSPACE_STATES[${artifact}]}" == "dirty" ]]; then
            reason="workspace build inputs are dirty"
        elif [[ -n "${baseline_content}" ]]; then
            if [[ "${current_content}" != "${baseline_content}" ]]; then
                reason="build inputs changed"
            fi
        elif [[ "${CURRENT_SOURCE_COMMITS[${artifact}]}" != "${BASELINE_SOURCE_COMMITS[${artifact}]}" ]]; then
            reason="source commit changed"
        fi

        if is_java_artifact "${artifact}"; then
            current_version="${CURRENT_SERVICE_COMMON_VERSIONS[${artifact}]}"
            baseline_version="${BASELINE_SERVICE_COMMON_VERSIONS[${artifact}]}"
            if [[ "${current_version}" != "${baseline_version}" ]]; then
                if [[ -n "${reason}" ]]; then
                    reason="${reason}; service-common version changed"
                else
                    reason="service-common version changed"
                fi
            fi
        fi

        if [[ -n "${reason}" ]]; then
            BUILD_DECISIONS["${artifact}"]="rebuilt"
            BUILD_REASONS["${artifact}"]="${reason}"
        else
            BUILD_DECISIONS["${artifact}"]="reused"
            BUILD_REASONS["${artifact}"]="matches accepted baseline"
        fi
    done
}

rebuild_count() {
    local artifact count=0

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        if [[ "${BUILD_DECISIONS[${artifact}]}" == "rebuilt" ]]; then
            count=$((count + 1))
        fi
    done

    printf '%s\n' "${count}"
}

java_rebuild_count() {
    local artifact count=0

    for artifact in "${JAVA_ARTIFACTS[@]}"; do
        if [[ "${BUILD_DECISIONS[${artifact}]}" == "rebuilt" ]]; then
            count=$((count + 1))
        fi
    done

    printf '%s\n' "${count}"
}

assign_reused_final_metadata() {
    local artifact

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        FINAL_IMAGES["${artifact}"]="${BASELINE_IMAGES[${artifact}]}"
        FINAL_ARTIFACT_VERSIONS["${artifact}"]="${BASELINE_ARTIFACT_VERSIONS[${artifact}]}"
        FINAL_SOURCE_REFS["${artifact}"]="${BASELINE_SOURCE_REFS[${artifact}]}"
        FINAL_SOURCE_COMMITS["${artifact}"]="${BASELINE_SOURCE_COMMITS[${artifact}]}"
        FINAL_SERVICE_COMMON_VERSIONS["${artifact}"]="${BASELINE_SERVICE_COMMON_VERSIONS[${artifact}]:-}"
    done
}

print_diff_summary() {
    local artifact

    info "OCI stack promotion diff"
    printf '  deployment-id: %s\n' "${deployment_id}"
    printf '  status: accepted\n'
    printf '  baseline: %s\n' "${baseline_deployment_id}"
    printf '  plan-only: %s\n' "${plan_only}"
    printf '\n'
    printf '%-24s %-8s %s\n' "ARTIFACT" "DECISION" "REASON"
    for artifact in "${ARTIFACT_ORDER[@]}"; do
        printf '%-24s %-8s %s\n' "${artifact}" "${BUILD_DECISIONS[${artifact}]}" "${BUILD_REASONS[${artifact}]}"
    done
}

write_plan_file() {
    local temp_file="${plan_output_path}.tmp"
    local artifact

    mkdir -p "$(dirname "${plan_output_path}")"
    {
        printf 'schema_version: 1\n'
        printf 'promotion:\n'
        printf '  deployment_id: "%s"\n' "${deployment_id}"
        printf '  status: "accepted"\n'
        printf '  target_environment: "oci-production"\n'
        printf '  baseline_deployment_id: "%s"\n' "${baseline_deployment_id}"
        printf '  orchestration_repository:\n'
        printf '    commit: "%s"\n' "${orchestration_commit}"
        printf '    source_ref: "%s"\n' "${orchestration_source_ref}"
        printf '    workspace_state: "%s"\n' "${orchestration_workspace_state}"
        printf '    content_identity: "%s"\n' "${orchestration_content_identity}"
        printf 'artifacts:\n'
        for artifact in "${ARTIFACT_ORDER[@]}"; do
            printf '  %s:\n' "${artifact}"
            printf '    source_repository: "%s"\n' "${SOURCE_REPOS[${artifact}]}"
            printf '    baseline_image: "%s"\n' "${BASELINE_IMAGES[${artifact}]}"
            printf '    baseline_source_commit: "%s"\n' "${BASELINE_SOURCE_COMMITS[${artifact}]}"
            printf '    current_source_commit: "%s"\n' "${CURRENT_SOURCE_COMMITS[${artifact}]}"
            printf '    current_source_ref: "%s"\n' "${CURRENT_SOURCE_REFS[${artifact}]}"
            printf '    workspace_state: "%s"\n' "${CURRENT_WORKSPACE_STATES[${artifact}]}"
            printf '    content_identity: "%s"\n' "${CURRENT_CONTENT_IDENTITIES[${artifact}]}"
            printf '    build_decision: "%s"\n' "${BUILD_DECISIONS[${artifact}]}"
            printf '    build_reason: "%s"\n' "${BUILD_REASONS[${artifact}]}"
            if is_java_artifact "${artifact}"; then
                printf '    service_common_version: "%s"\n' "${CURRENT_SERVICE_COMMON_VERSIONS[${artifact}]}"
            fi
        done
    } > "${temp_file}"
    mv "${temp_file}" "${plan_output_path}"
}

require_build_prerequisites() {
    if [[ "$(rebuild_count)" == "0" ]]; then
        return
    fi

    phase4_require_commands docker
    docker buildx version >/dev/null 2>&1 || die "docker buildx is required to build linux/arm64 promotion images"

    if [[ "$(java_rebuild_count)" != "0" ]]; then
        [[ -n "${SERVICE_COMMON_PACKAGES_USERNAME:-}" ]] || die "missing SERVICE_COMMON_PACKAGES_USERNAME for Java image builds"
        [[ -n "${SERVICE_COMMON_PACKAGES_READ_TOKEN:-}" ]] || die "missing SERVICE_COMMON_PACKAGES_READ_TOKEN for Java image builds"
    fi
}

metadata_digest() {
    local metadata_file="$1"
    local tag_ref="$2"
    local digest

    digest="$(sed -nE 's/.*"containerimage.digest"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${metadata_file}" | head -n 1)"
    if [[ -z "${digest}" ]]; then
        digest="$(docker buildx imagetools inspect "${tag_ref}" 2>/dev/null \
            | sed -nE 's/^[[:space:]]*Digest:[[:space:]]*(sha256:[0-9a-f]{64}).*$/\1/p' \
            | head -n 1)"
    fi

    [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "could not resolve pushed digest for ${tag_ref}"
    printf '%s\n' "${digest}"
}

build_changed_images() {
    local artifact repo image_repo context_path dockerfile_path tag tag_ref metadata_file digest source_repo
    local github_actor_secret="id=github_actor,env=SERVICE_COMMON_PACKAGES_USERNAME"
    local github_token_secret="id=github_token,env=SERVICE_COMMON_PACKAGES_READ_TOKEN"
    local metadata_dir="${PROMOTION_OUTPUT_ROOT}/${deployment_id}-build-metadata"
    local build_args=()

    mkdir -p "${metadata_dir}"

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        [[ "${BUILD_DECISIONS[${artifact}]}" == "rebuilt" ]] || continue

        repo="${IMAGE_REPOS[${artifact}]}"
        image_repo="ghcr.io/budgetanalyzer/${repo}"
        context_path="$(artifact_context_path "${artifact}")"
        dockerfile_path="$(artifact_dockerfile_path "${artifact}")"
        tag="$(sanitize_docker_tag "promotion-${deployment_id}-$(short_identity "${CURRENT_CONTENT_IDENTITIES[${artifact}]}")")"
        tag_ref="${image_repo}:${tag}"
        metadata_file="${metadata_dir}/${artifact}.json"
        source_repo="${SOURCE_REPOS[${artifact}]}"

        build_args=(
            buildx build
            --platform linux/arm64
            --push
            --metadata-file "${metadata_file}"
            --tag "${tag_ref}"
            --label "org.opencontainers.image.source=https://github.com/budgetanalyzer/${source_repo}"
            --label "org.opencontainers.image.revision=${CURRENT_SOURCE_COMMITS[${artifact}]}"
            --label "org.opencontainers.image.version=${tag}"
            -f "${dockerfile_path}"
        )

        if is_java_artifact "${artifact}"; then
            build_args+=(
                --secret "${github_actor_secret}"
                --secret "${github_token_secret}"
            )
        fi

        info "building and pushing ${tag_ref}"
        docker "${build_args[@]}" "${context_path}"
        digest="$(metadata_digest "${metadata_file}" "${tag_ref}")"

        FINAL_IMAGES["${artifact}"]="${tag_ref}@${digest}"
        FINAL_ARTIFACT_VERSIONS["${artifact}"]="${tag}"
        FINAL_SOURCE_REFS["${artifact}"]="${CURRENT_SOURCE_REFS[${artifact}]}"
        FINAL_SOURCE_COMMITS["${artifact}"]="${CURRENT_SOURCE_COMMITS[${artifact}]}"
        if is_java_artifact "${artifact}"; then
            FINAL_SERVICE_COMMON_VERSIONS["${artifact}"]="${CURRENT_SERVICE_COMMON_VERSIONS[${artifact}]}"
        fi
    done
}

write_deployment_manifest() {
    local temp_file="${deployment_output_path}.tmp"
    local artifact

    mkdir -p "$(dirname "${deployment_output_path}")"
    {
        printf 'schema_version: 2\n'
        printf 'deployment:\n'
        printf '  id: "%s"\n' "${deployment_id}"
        printf '  environment: "oci-production"\n'
        printf '  status: "accepted"\n'
        printf '  created_at: "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '  production_baseline_input: "%s"\n' "${PRODUCTION_DEPLOYMENT_MANIFEST#"${REPO_ROOT}"/}"
        printf '  production_baseline_deployment_id: "%s"\n' "${baseline_deployment_id}"
        printf '  orchestration_repository:\n'
        printf '    commit: "%s"\n' "${orchestration_commit}"
        printf '    source_ref: "%s"\n' "${orchestration_source_ref}"
        printf '    workspace_state: "%s"\n' "${orchestration_workspace_state}"
        printf '    content_identity: "%s"\n' "${orchestration_content_identity}"
        printf 'artifacts:\n'
        for artifact in "${ARTIFACT_ORDER[@]}"; do
            printf '  %s:\n' "${artifact}"
            printf '    source_repository: "%s"\n' "${SOURCE_REPOS[${artifact}]}"
            printf '    source_ref: "%s"\n' "${FINAL_SOURCE_REFS[${artifact}]}"
            printf '    source_commit: "%s"\n' "${FINAL_SOURCE_COMMITS[${artifact}]}"
            printf '    artifact_version: "%s"\n' "${FINAL_ARTIFACT_VERSIONS[${artifact}]}"
            printf '    image: "%s"\n' "${FINAL_IMAGES[${artifact}]}"
            if is_java_artifact "${artifact}"; then
                printf '    service_common_version: "%s"\n' "${FINAL_SERVICE_COMMON_VERSIONS[${artifact}]}"
            fi
            printf '    build_decision: "%s"\n' "${BUILD_DECISIONS[${artifact}]}"
            printf '    build_reason: "%s"\n' "${BUILD_REASONS[${artifact}]}"
            printf '    workspace_state: "%s"\n' "${CURRENT_WORKSPACE_STATES[${artifact}]}"
            printf '    content_identity: "%s"\n' "${CURRENT_CONTENT_IDENTITIES[${artifact}]}"
            printf '    baseline_image: "%s"\n' "${BASELINE_IMAGES[${artifact}]}"
        done
    } > "${temp_file}"
    mv "${temp_file}" "${deployment_output_path}"
}

validate_final_manifest() {
    local artifact

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        valid_digest_pinned_image "${artifact}" "${FINAL_IMAGES[${artifact}]}" || \
            die "final image for ${artifact} is not digest-pinned: ${FINAL_IMAGES[${artifact}]}"
        [[ "${FINAL_ARTIFACT_VERSIONS[${artifact}]}" == "$(image_ref_tag "${FINAL_IMAGES[${artifact}]}")" ]] || \
            die "final artifact version for ${artifact} does not match the image tag"
        valid_commit_sha "${FINAL_SOURCE_COMMITS[${artifact}]}" || \
            die "final source commit for ${artifact} is invalid"
        if is_java_artifact "${artifact}"; then
            [[ -n "${FINAL_SERVICE_COMMON_VERSIONS[${artifact}]:-}" ]] || \
                die "final manifest is missing service-common version for ${artifact}"
        fi
    done
}

update_production_baseline() {
    local args=(--deployment-manifest "${deployment_output_path}")

    if [[ "${skip_live_production_verifier}" == "true" ]]; then
        args+=(--skip-live-production-verifier)
    fi

    "${UPDATE_PRODUCTION_BASELINE}" "${args[@]}"
}

apply_to_oci() {
    local args=(--deployment-manifest "${PRODUCTION_DEPLOYMENT_MANIFEST}")

    if [[ -n "${explicit_kubeconfig}" ]]; then
        args+=(--kubeconfig "${explicit_kubeconfig}")
    fi

    "${DEPLOY_OCI_RELEASE}" "${args[@]}"
}

initialize_defaults() {
    if [[ -z "${deployment_id}" ]]; then
        deployment_id="oci-$(date -u +%Y%m%dT%H%M%SZ)"
    fi

    plan_output_path="${PROMOTION_OUTPUT_ROOT}/${deployment_id}.plan.yaml"
    deployment_output_path="${PROMOTION_OUTPUT_ROOT}/${deployment_id}.yaml"

    [[ ! -e "${deployment_output_path}" ]] || die "deployment snapshot already exists: ${deployment_output_path}"
}

main() {
    parse_args "$@"
    initialize_defaults
    phase4_require_commands git awk sed sha256sum date

    validate_repo_layout
    load_baseline
    discover_current_workspace
    enforce_dirty_policy
    decide_builds
    assign_reused_final_metadata
    write_plan_file
    print_diff_summary

    info "wrote promotion plan: ${plan_output_path}"

    if [[ "${plan_only}" == "true" ]]; then
        info "plan-only complete; no images were built and OCI was not changed"
        return
    fi

    require_build_prerequisites
    build_changed_images
    validate_final_manifest
    write_deployment_manifest

    info "wrote deployment snapshot: ${deployment_output_path}"
    update_production_baseline
    apply_to_oci
}

main "$@"
