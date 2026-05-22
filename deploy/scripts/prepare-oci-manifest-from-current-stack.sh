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

declare -a CURL_AUTH_ARGS=()

source_tag="${OCI_SOURCE_TAG:-}"
deployment_id="${OCI_DEPLOYMENT_ID:-}"
wait_timeout_seconds="${OCI_IMAGE_WAIT_TIMEOUT_SECONDS:-1800}"
poll_interval_seconds="${OCI_IMAGE_POLL_INTERVAL_SECONDS:-30}"
plan_only=false
assume_yes=false
run_cluster_verifier=false
deployment_output_path=""
docker_label=""

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh \
    --source-tag vX.Y.Z [options]

Options:
  --source-tag vX.Y.Z              Source tag to ensure in each deployable
                                   source repository. May also be set with
                                   OCI_SOURCE_TAG.
  --deployment-id ID               Desired OCI deployment id. Defaults to
                                   oci-<UTC timestamp>.
  --wait-timeout SECONDS           Maximum time to wait for GHCR images.
                                   Defaults to 1800.
  --poll-interval SECONDS          GHCR polling interval. Defaults to 30.
  --plan-only                      Validate and print the intended tag/image
                                   work without creating tags, waiting for
                                   GHCR, or changing the manifest.
  --yes, -y                        Do not prompt before creating and pushing
                                   missing source tags.
  --run-cluster-verifier           Also run the cluster-backed production
                                   render verifier from the baseline updater.
  -h, --help                       Show this help.

The command prepares checked-in OCI desired state from the current clean source
workspace. It does not build Docker images, push images, require OCI
kubeconfig access, or deploy to OCI. GitHub Actions builds images after source
tags are pushed; this command waits for the corresponding GHCR tags, resolves
their digests, updates the production manifest and inventory, then stops for
human review, commit, and push.

If GHCR requires authentication for manifest reads, set GHCR_USERNAME and
GHCR_TOKEN. GITHUB_ACTOR and GITHUB_TOKEN are accepted as fallbacks.
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

valid_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
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
                wait_timeout_seconds="${2:-}"
                valid_positive_integer "${wait_timeout_seconds}" || die "--wait-timeout must be a positive integer"
                shift
                ;;
            --poll-interval)
                poll_interval_seconds="${2:-}"
                valid_positive_integer "${poll_interval_seconds}" || die "--poll-interval must be a positive integer"
                shift
                ;;
            --plan-only)
                plan_only=true
                ;;
            --yes|-y)
                assume_yes=true
                ;;
            --run-cluster-verifier)
                run_cluster_verifier=true
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
    source_tag="$(normalize_source_tag "${source_tag}")"
    docker_label="${source_tag#v}"

    if [[ -z "${deployment_id}" ]]; then
        deployment_id="oci-$(date -u +%Y%m%dT%H%M%SZ)"
    fi

    deployment_output_path="${DEPLOYMENT_OUTPUT_ROOT}/${deployment_id}.yaml"
    [[ ! -e "${deployment_output_path}" || "${plan_only}" == true ]] || \
        die "deployment manifest output already exists: ${deployment_output_path}"
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
            [[ "${existing_commit}" == "${head_commit}" ]] || \
                die "${source_repo}: ${source_tag} points at ${existing_commit}, but current HEAD is ${head_commit}"
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
    printf '  plan-only: %s\n' "${plan_only}"
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
                info "${source_repo}: ${source_tag} already exists at current HEAD"
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

initialize_ghcr_auth() {
    local username="${GHCR_USERNAME:-${GITHUB_ACTOR:-}}"
    local token="${GHCR_TOKEN:-${GITHUB_TOKEN:-}}"
    local encoded

    CURL_AUTH_ARGS=()
    if [[ -n "${username}" && -n "${token}" ]]; then
        phase4_require_commands base64
        encoded="$(printf '%s:%s' "${username}" "${token}" | base64 | tr -d '\n')"
        CURL_AUTH_ARGS=(-H "Authorization: Basic ${encoded}")
    elif [[ -n "${token}" ]]; then
        CURL_AUTH_ARGS=(-H "Authorization: Bearer ${token}")
    fi
}

ghcr_manifest_url() {
    local image_repo="$1"
    local tag="$2"

    printf 'https://ghcr.io/v2/budgetanalyzer/%s/manifests/%s\n' "${image_repo}" "${tag}"
}

resolve_ghcr_digest_once() {
    local image_repo="$1"
    local tag="$2"
    local headers_file="$3"
    local body_file="$4"
    local url digest

    url="$(ghcr_manifest_url "${image_repo}" "${tag}")"
    if ! curl -fsSL \
        -D "${headers_file}" \
        -o "${body_file}" \
        "${CURL_AUTH_ARGS[@]}" \
        -H 'Accept: application/vnd.oci.image.index.v1+json' \
        -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
        -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
        "${url}"; then
        return 1
    fi

    digest="$(awk 'BEGIN {IGNORECASE = 1} /^docker-content-digest:/ {gsub(/\r/, "", $2); print $2; exit}' "${headers_file}")"
    [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
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

wait_for_ghcr_images() {
    local artifact image_repo tag_ref digest deadline now
    local temp_dir headers_file body_file

    initialize_ghcr_auth
    temp_dir="$(mktemp -d)"
    deadline=$(( $(date +%s) + wait_timeout_seconds ))

    for artifact in "${ARTIFACT_ORDER[@]}"; do
        image_repo="${IMAGE_REPOS[${artifact}]}"
        tag_ref="ghcr.io/budgetanalyzer/${image_repo}:${docker_label}"
        headers_file="${temp_dir}/${artifact}.headers"
        body_file="${temp_dir}/${artifact}.json"

        info "waiting for ${tag_ref}"
        digest=""
        while [[ -z "${digest}" ]]; do
            if digest="$(resolve_ghcr_digest_once "${image_repo}" "${docker_label}" "${headers_file}" "${body_file}")"; then
                break
            fi

            now="$(date +%s)"
            if (( now >= deadline )); then
                die "timed out waiting for ${tag_ref}; confirm the ${source_tag} GitHub Actions release workflow succeeded"
            fi
            sleep "${poll_interval_seconds}"
        done

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

    if [[ "${run_cluster_verifier}" != true ]]; then
        args+=(--skip-live-production-verifier)
    fi

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
    phase4_require_commands git curl awk sed date kubectl

    validate_repo_layout
    discover_source_state
    plan_source_tags
    print_plan

    if [[ "${plan_only}" == true ]]; then
        info "plan-only complete; no tags were pushed, no GHCR images were read, and no files were changed"
        return
    fi

    ensure_source_tags
    wait_for_ghcr_images
    validate_resolved_images
    write_deployment_manifest
    update_production_desired_state
    "${STATIC_VERIFIER}"
    verify_no_lifecycle_status_in_desired_state
    print_completion
}

main "$@"
