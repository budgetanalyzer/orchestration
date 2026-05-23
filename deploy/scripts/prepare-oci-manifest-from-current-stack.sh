#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

REPO_ROOT="${PHASE4_REPO_ROOT}"
PARENT_DIR="$(dirname "${REPO_ROOT}")"
PRODUCTION_DEPLOYMENT_MANIFEST="${REPO_ROOT}/kubernetes/production/apps/deployment-manifest.yaml"
UPDATE_PRODUCTION_BASELINE="${SCRIPT_DIR}/23-update-production-release-images.sh"
STATIC_VERIFIER="${SCRIPT_DIR}/24-verify-oci-upgrade-lockstep.sh"
DEPLOYMENT_OUTPUT_ROOT="${REPO_ROOT}/tmp/deployments"
readonly REPO_ROOT
readonly PARENT_DIR
readonly PRODUCTION_DEPLOYMENT_MANIFEST
readonly UPDATE_PRODUCTION_BASELINE
readonly STATIC_VERIFIER
readonly DEPLOYMENT_OUTPUT_ROOT

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

declare -A SOURCE_COMMITS=()
declare -A SOURCE_REFS=()
declare -A SERVICE_COMMON_VERSIONS=()
declare -A IMAGE_REFS=()
declare -A TAG_ACTIONS=()

declare -a GHCR_TOKEN_AUTH_ARGS=()

source_tag="${OCI_SOURCE_TAG:-}"
deployment_id="${OCI_DEPLOYMENT_ID:-}"
command_mode="${OCI_PREPARE_MODE:-}"
assume_yes=false
deployment_output_path=""
docker_label=""

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh \
    --source-tag vX.Y.Z --plan-only

  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh \
    --source-tag vX.Y.Z --push-tags [options]

  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh \
    --source-tag vX.Y.Z --resolve-images [options]

Options:
  --source-tag vX.Y.Z              Source tag to ensure in each deployable
                                   source repository. May also be set with
                                   OCI_SOURCE_TAG.
  --deployment-id ID               Desired OCI deployment id. Defaults to
                                   oci-<UTC timestamp>.
  --plan-only                      Validate and print the intended tag/image
                                   work without creating tags, waiting for
                                   GHCR, or changing the manifest.
  --push-tags                      Create and push any missing source tags,
                                   then stop so the operator can wait for
                                   GitHub Actions image workflows.
  --resolve-images                 Read already-published GHCR image tags,
                                   resolve digests, update checked-in
                                   production desired state, and stop for
                                   review.
  --yes, -y                        Do not prompt before creating and pushing
                                   missing source tags.
  -h, --help                       Show this help.

The command prepares checked-in OCI desired state from the current clean source
workspace. It does not build Docker images, push images, require OCI
kubeconfig access, or deploy to OCI.

Use --plan-only first to preview source tag actions and expected GHCR image
tags. Use --push-tags to create or push the missing source tags, then wait for
the owning GitHub Actions release-image workflows to publish the expected GHCR
tags. Use --resolve-images after those tags exist; missing GHCR tags are a
direct prerequisite failure rather than a retry loop.

GHCR image reads use the Docker Registry API token flow. Public packages can
resolve without credentials. For private packages, set GHCR_USERNAME and
GHCR_TOKEN to a GitHub token with read:packages. GITHUB_ACTOR and GITHUB_TOKEN
are accepted as fallbacks.
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

repo_path_for_source_repo() {
    local source_repo="$1"

    if [[ "${source_repo}" == "orchestration" ]]; then
        printf '%s\n' "${REPO_ROOT}"
        return
    fi

    printf '%s/%s\n' "${PARENT_DIR}" "${source_repo}"
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

normalize_source_tag() {
    local tag="$1"

    tag="${tag#v}"
    [[ "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "source tag must use X.Y.Z or vX.Y.Z format so tag-push image workflows publish predictable GHCR labels: ${tag}"
    printf 'v%s\n' "${tag}"
}

set_command_mode() {
    local requested="$1"

    [[ -z "${command_mode}" || "${command_mode}" == "${requested}" ]] || \
        die "choose exactly one mode: --plan-only, --push-tags, or --resolve-images"
    command_mode="${requested}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source-tag)
                source_tag="${2:-}"
                [[ -n "${source_tag}" ]] || die "missing value for --source-tag"
                shift
                ;;
            --deployment-id)
                deployment_id="${2:-}"
                [[ -n "${deployment_id}" ]] || die "missing value for --deployment-id"
                shift
                ;;
            --wait-timeout)
                die "--wait-timeout was removed; wait for GitHub Actions manually, then rerun with --resolve-images"
                ;;
            --poll-interval)
                die "--poll-interval was removed; wait for GitHub Actions manually, then rerun with --resolve-images"
                ;;
            --plan-only)
                set_command_mode "plan"
                ;;
            --push-tags)
                set_command_mode "push-tags"
                ;;
            --resolve-images)
                set_command_mode "resolve-images"
                ;;
            --yes|-y)
                assume_yes=true
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

initialize_defaults() {
    [[ -n "${source_tag}" ]] || die "missing --source-tag vX.Y.Z"
    [[ -n "${command_mode}" ]] || die "choose one mode: --plan-only, --push-tags, or --resolve-images"
    case "${command_mode}" in
        plan|push-tags|resolve-images)
            ;;
        *)
            die "unknown mode from OCI_PREPARE_MODE: ${command_mode}"
            ;;
    esac
    source_tag="$(normalize_source_tag "${source_tag}")"
    docker_label="${source_tag#v}"

    if [[ -z "${deployment_id}" ]]; then
        deployment_id="oci-$(date -u +%Y%m%dT%H%M%SZ)"
    fi

    deployment_output_path="${DEPLOYMENT_OUTPUT_ROOT}/${deployment_id}.yaml"
    [[ "${command_mode}" != "resolve-images" || ! -e "${deployment_output_path}" ]] || \
        die "deployment manifest output already exists: ${deployment_output_path}"
}

require_mode_commands() {
    local commands=(git awk sed date)

    if [[ "${command_mode}" == "resolve-images" ]]; then
        commands+=(curl kubectl)
    fi

    phase4_require_commands "${commands[@]}"
}

repo_is_dirty() {
    local repo_path="$1"

    [[ -n "$(git -C "${repo_path}" status --porcelain --untracked-files=all)" ]]
}

validate_repo_layout() {
    local artifact source_repo repo_path
    local service_common_repo="${PARENT_DIR}/service-common"

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        source_repo="${SOURCE_REPOS[${artifact}]}"
        repo_path="$(repo_path_for_source_repo "${source_repo}")"
        [[ -d "${repo_path}/.git" ]] || die "missing git repository for ${artifact}: ${repo_path}"
    done

    [[ -d "${service_common_repo}/.git" ]] || die "missing git repository: ${service_common_repo}"
    [[ -x "${UPDATE_PRODUCTION_BASELINE}" ]] || die "missing executable: ${UPDATE_PRODUCTION_BASELINE}"
    [[ -x "${STATIC_VERIFIER}" ]] || die "missing executable: ${STATIC_VERIFIER}"
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

discover_source_state() {
    local artifact source_repo repo_path service_common_version
    local dirty_repos=()

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        source_repo="${SOURCE_REPOS[${artifact}]}"
        repo_path="$(repo_path_for_source_repo "${source_repo}")"

        if repo_is_dirty "${repo_path}"; then
            dirty_repos+=("${source_repo}")
        fi

        SOURCE_COMMITS["${artifact}"]="$(git -C "${repo_path}" rev-parse HEAD)"
        SOURCE_REFS["${artifact}"]="refs/tags/${source_tag}"

        if is_java_artifact "${artifact}"; then
            service_common_version="$(read_service_common_version "${repo_path}")"
            [[ -n "${service_common_version}" ]] || die "missing serviceCommon version for ${artifact}"
            SERVICE_COMMON_VERSIONS["${artifact}"]="${service_common_version}"
        fi
    done

    if repo_is_dirty "${PARENT_DIR}/service-common"; then
        dirty_repos+=("service-common")
    fi

    if (( ${#dirty_repos[@]} > 0 )); then
        die "source workspaces must be clean before preparing OCI desired state: ${dirty_repos[*]}"
    fi
}

local_tag_commit() {
    local repo_path="$1"

    git -C "${repo_path}" rev-parse -q --verify "${source_tag}^{commit}" 2>/dev/null || true
}

remote_tag_commit() {
    local repo_path="$1"
    local output
    local peeled_ref="refs/tags/${source_tag}^{}"
    local exact_ref="refs/tags/${source_tag}"

    if ! output="$(git -C "${repo_path}" ls-remote --tags origin "refs/tags/${source_tag}*" 2>&1)"; then
        die "could not inspect remote tags for ${repo_path}: ${output}"
    fi
    awk -v peeled_ref="${peeled_ref}" -v exact_ref="${exact_ref}" '
        $2 == peeled_ref {
            peeled = $1
        }
        $2 == exact_ref {
            exact = $1
        }
        END {
            if (peeled != "") {
                print peeled
            } else if (exact != "") {
                print exact
            }
        }
    ' <<< "${output}"
}

plan_source_tags() {
    local artifact source_repo repo_path head_commit local_commit remote_commit existing_commit

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        source_repo="${SOURCE_REPOS[${artifact}]}"
        repo_path="$(repo_path_for_source_repo "${source_repo}")"
        head_commit="${SOURCE_COMMITS[${artifact}]}"
        local_commit="$(local_tag_commit "${repo_path}")"
        remote_commit="$(remote_tag_commit "${repo_path}")"

        if [[ -n "${local_commit}" && -n "${remote_commit}" && "${local_commit}" != "${remote_commit}" ]]; then
            die "${source_repo}: ${source_tag} differs between local and origin; local=${local_commit}, origin=${remote_commit}"
        fi

        existing_commit="${local_commit:-${remote_commit}}"
        if [[ -n "${existing_commit}" ]]; then
            if [[ "${existing_commit}" != "${head_commit}" ]]; then
                if [[ "${artifact}" == "ext-authz" && "${source_repo}" == "orchestration" ]]; then
                    SOURCE_COMMITS["${artifact}"]="${existing_commit}"
                else
                    die "${source_repo}: ${source_tag} points at ${existing_commit}, but current HEAD is ${head_commit}"
                fi
            fi
            if [[ -n "${local_commit}" && -z "${remote_commit}" ]]; then
                TAG_ACTIONS["${artifact}"]="push-existing"
            else
                TAG_ACTIONS["${artifact}"]="exists"
            fi
        else
            TAG_ACTIONS["${artifact}"]="create-and-push"
        fi
    done
}

print_plan() {
    local artifact

    info "OCI manifest preparation plan"
    printf '  deployment-id: %s\n' "${deployment_id}"
    printf '  source-tag: %s\n' "${source_tag}"
    printf '  docker-label: %s\n' "${docker_label}"
    printf '  mode: %s\n' "${command_mode}"
    printf '\n'
    printf '%-24s %-20s %-42s %s\n' "ARTIFACT" "TAG ACTION" "SOURCE COMMIT" "EXPECTED IMAGE TAG"
    for artifact in "${ARTIFACT_ORDER[@]}"; do
        printf '%-24s %-20s %-42s ghcr.io/budgetanalyzer/%s:%s\n' \
            "${artifact}" \
            "${TAG_ACTIONS[${artifact}]}" \
            "${SOURCE_COMMITS[${artifact}]}" \
            "${IMAGE_REPOS[${artifact}]}" \
            "${docker_label}"
    done
}

confirm_tag_mutation() {
    local reply

    if [[ "${assume_yes}" == true ]]; then
        return
    fi

    printf '[phase4] Create and push any missing %s source tags? [y/N] ' "${source_tag}"
    read -r reply
    [[ "${reply}" =~ ^[Yy]$ ]] || die "aborted"
}

ensure_source_tags() {
    local artifact source_repo repo_path action

    confirm_tag_mutation

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        action="${TAG_ACTIONS[${artifact}]}"
        source_repo="${SOURCE_REPOS[${artifact}]}"
        repo_path="$(repo_path_for_source_repo "${source_repo}")"

        case "${action}" in
            exists)
                info "${source_repo}: ${source_tag} already exists at ${SOURCE_COMMITS[${artifact}]}"
                ;;
            push-existing)
                info "${source_repo}: pushing existing local ${source_tag}"
                git -C "${repo_path}" push origin "${source_tag}"
                ;;
            create-and-push)
                info "${source_repo}: creating and pushing ${source_tag}"
                git -C "${repo_path}" tag -a "${source_tag}" -m "Release ${source_tag}"
                git -C "${repo_path}" push origin "${source_tag}"
                ;;
            *)
                die "unknown tag action for ${artifact}: ${action}"
                ;;
        esac
    done
}

validate_source_tags_ready_for_resolve() {
    local artifact action
    local pending_actions=()

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        action="${TAG_ACTIONS[${artifact}]}"
        if [[ "${action}" != "exists" ]]; then
            pending_actions+=("${SOURCE_REPOS[${artifact}]}:${action}")
        fi
    done

    if (( ${#pending_actions[@]} > 0 )); then
        die "source tags must exist on origin before --resolve-images; run --push-tags first. Pending tag actions: ${pending_actions[*]}"
    fi
}

initialize_ghcr_auth() {
    local username="${GHCR_USERNAME:-${GITHUB_ACTOR:-}}"
    local token="${GHCR_TOKEN:-${GITHUB_TOKEN:-}}"
    local encoded

    GHCR_TOKEN_AUTH_ARGS=()
    if [[ -n "${username}" && -n "${token}" ]]; then
        phase4_require_commands base64
        encoded="$(printf '%s:%s' "${username}" "${token}" | base64 | tr -d '\n')"
        GHCR_TOKEN_AUTH_ARGS=(-H "Authorization: Basic ${encoded}")
    elif [[ -n "${token}" ]]; then
        warn "GHCR token is set without a username; using anonymous GHCR token flow. Set GHCR_USERNAME with GHCR_TOKEN for private packages."
    fi
}

ghcr_manifest_url() {
    local image_repo="$1"
    local tag="$2"

    printf 'https://ghcr.io/v2/budgetanalyzer/%s/manifests/%s\n' "${image_repo}" "${tag}"
}

request_ghcr_pull_token() {
    local image_repo="$1"
    local token_file="$2"
    local token

    if ! curl -fsSL \
        -o "${token_file}" \
        "${GHCR_TOKEN_AUTH_ARGS[@]}" \
        --get \
        --data-urlencode 'service=ghcr.io' \
        --data-urlencode "scope=repository:budgetanalyzer/${image_repo}:pull" \
        'https://ghcr.io/token'; then
        return 1
    fi

    token="$(sed -nE 's/.*"(token|access_token)"[[:space:]]*:[[:space:]]*"([^"]+)".*/\2/p' "${token_file}" | head -n 1)"
    [[ -n "${token}" ]] || return 1
    printf '%s\n' "${token}"
}

resolve_ghcr_digest() {
    local image_repo="$1"
    local tag="$2"
    local headers_file="$3"
    local body_file="$4"
    local token_file="$5"
    local url digest token

    url="$(ghcr_manifest_url "${image_repo}" "${tag}")"
    token="$(request_ghcr_pull_token "${image_repo}" "${token_file}")" || return 2

    if ! curl -fsSL \
        -D "${headers_file}" \
        -o "${body_file}" \
        -H "Authorization: Bearer ${token}" \
        -H 'Accept: application/vnd.oci.image.index.v1+json' \
        -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
        -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        "${url}"; then
        return 1
    fi

    digest="$(awk 'BEGIN {IGNORECASE = 1} /^docker-content-digest:/ {gsub(/\r/, "", $2); print $2; exit}' "${headers_file}")"
    [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || return 3
    printf '%s\n' "${digest}"
}

validate_manifest_mentions_arm64() {
    local body_file="$1"
    local image_ref="$2"

    if grep -Eq '"architecture"[[:space:]]*:[[:space:]]*"arm64"' "${body_file}"; then
        return
    fi

    warn "could not confirm linux/arm64 from GHCR manifest body for ${image_ref}; digest was resolved"
}

resolve_ghcr_images() {
    local artifact image_repo tag_ref digest
    local temp_dir headers_file body_file token_file resolve_status

    initialize_ghcr_auth
    temp_dir="$(mktemp -d)"

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        image_repo="${IMAGE_REPOS[${artifact}]}"
        tag_ref="ghcr.io/budgetanalyzer/${image_repo}:${docker_label}"
        headers_file="${temp_dir}/${artifact}.headers"
        body_file="${temp_dir}/${artifact}.json"
        token_file="${temp_dir}/${artifact}.token.json"

        info "resolving ${tag_ref}"
        resolve_status=0
        digest="$(resolve_ghcr_digest "${image_repo}" "${docker_label}" "${headers_file}" "${body_file}" "${token_file}")" || resolve_status=$?
        if [[ "${resolve_status}" -ne 0 ]]; then
            if [[ "${resolve_status}" -eq 2 ]]; then
                die "could not get GHCR pull token for ${tag_ref}; if the package is private, set GHCR_USERNAME and GHCR_TOKEN to a GitHub token with read:packages"
            fi

            die "missing or inaccessible GHCR image tag prerequisite: ${tag_ref}; wait for the ${source_tag} GitHub Actions release-image workflow in ${SOURCE_REPOS[${artifact}]} to publish it, then rerun with --resolve-images"
        fi

        IMAGE_REFS["${artifact}"]="${tag_ref}@${digest}"
        validate_manifest_mentions_arm64 "${body_file}" "${IMAGE_REFS[${artifact}]}"
    done

    rm -rf "${temp_dir}"
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

validate_resolved_images() {
    local artifact

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        valid_digest_pinned_image "${artifact}" "${IMAGE_REFS[${artifact}]}" || \
            die "resolved image for ${artifact} is not digest-pinned: ${IMAGE_REFS[${artifact}]:-<missing>}"
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
        printf '  created_at: "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '  production_baseline_input: "%s"\n' "${PRODUCTION_DEPLOYMENT_MANIFEST#"${REPO_ROOT}"/}"
        printf '  orchestration_repository:\n'
        printf '    commit: "%s"\n' "$(git -C "${REPO_ROOT}" rev-parse HEAD)"
        printf '    source_ref: "%s"\n' "$(git -C "${REPO_ROOT}" rev-parse HEAD)"
        printf 'artifacts:\n'
        for artifact in "${ARTIFACT_ORDER[@]}"; do
            printf '  %s:\n' "${artifact}"
            printf '    source_repository: "%s"\n' "${SOURCE_REPOS[${artifact}]}"
            printf '    source_ref: "%s"\n' "${SOURCE_REFS[${artifact}]}"
            printf '    source_commit: "%s"\n' "${SOURCE_COMMITS[${artifact}]}"
            printf '    artifact_version: "%s"\n' "${docker_label}"
            printf '    image: "%s"\n' "${IMAGE_REFS[${artifact}]}"
            if is_java_artifact "${artifact}"; then
                printf '    service_common_version: "%s"\n' "${SERVICE_COMMON_VERSIONS[${artifact}]}"
            fi
        done
    } > "${temp_file}"
    mv "${temp_file}" "${deployment_output_path}"
}

update_production_desired_state() {
    local args=(--deployment-manifest "${deployment_output_path}")

    "${UPDATE_PRODUCTION_BASELINE}" "${args[@]}"
}

verify_no_lifecycle_status_in_desired_state() {
    if grep -R -n 'deployment-status\|status: "accepted"\|budgetanalyzer.org/deployment-status' \
        "${REPO_ROOT}/kubernetes/production/apps/deployment-manifest.yaml" \
        "${REPO_ROOT}/kubernetes/production/apps/image-inventory.yaml" \
        "${REPO_ROOT}/kubernetes/production/apps/patches/runtime-release-metadata.yaml" \
        "${REPO_ROOT}/docs-aggregator/release-metadata.json" \
        "${REPO_ROOT}/kubernetes/production/docs-aggregator/release-metadata.json"; then
        die "desired-state files still contain deployment lifecycle status"
    fi
}

print_tag_completion() {
    info "source tag step complete"
    printf '\nNext steps:\n'
    printf '  1. Wait for the owning GitHub Actions release-image workflows to publish these GHCR tags:\n'

    local artifact
    for artifact in "${ARTIFACT_ORDER[@]}"; do
        printf '     - ghcr.io/budgetanalyzer/%s:%s\n' "${IMAGE_REPOS[${artifact}]}" "${docker_label}"
    done

    printf '  2. Rerun:\n'
    printf '     ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag %s --resolve-images\n' "${source_tag}"
}

print_completion() {
    info "prepared OCI desired state"
    printf '  deployment-manifest: %s\n' "${deployment_output_path}"
    printf '  checked-in manifest: kubernetes/production/apps/deployment-manifest.yaml\n'
    printf '  checked-in inventory: kubernetes/production/apps/image-inventory.yaml\n'
    printf '\nNext steps:\n'
    printf '  1. Review the orchestration diff.\n'
    printf '  2. Commit and push the orchestration desired-state update.\n'
    printf '  3. On the OCI host, pull the repo and run deploy/scripts/deploy-current-oci-manifest.sh.\n'
}

main() {
    parse_args "$@"
    initialize_defaults
    require_mode_commands

    validate_repo_layout
    discover_source_state
    plan_source_tags
    print_plan

    if [[ "${command_mode}" == "plan" ]]; then
        info "plan-only complete; no tags were pushed, no GHCR images were read, and no files were changed"
        return
    fi

    if [[ "${command_mode}" == "push-tags" ]]; then
        ensure_source_tags
        print_tag_completion
        return
    fi

    validate_source_tags_ready_for_resolve
    resolve_ghcr_images
    validate_resolved_images
    write_deployment_manifest
    update_production_desired_state
    "${STATIC_VERIFIER}"
    verify_no_lifecycle_status_in_desired_state
    print_completion
}

main "$@"
