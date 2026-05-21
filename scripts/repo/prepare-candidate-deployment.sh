#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/repo-config.sh"

declare -A ARTIFACT_SOURCE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="orchestration"
)

declare -A ARTIFACT_IMAGE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="ext-authz"
)

declare -A ARTIFACT_WORKFLOWS=(
    ["transaction-service"]="publish-release.yml"
    ["currency-service"]="publish-release.yml"
    ["permission-service"]="publish-release.yml"
    ["session-gateway"]="publish-release.yml"
    ["budget-analyzer-web"]="publish-release.yml"
    ["ext-authz"]="publish-ext-authz-release.yml"
)

RUNTIME_ARTIFACTS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly RUNTIME_ARTIFACTS

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/prepare-candidate-deployment.sh --service <artifact> [options]
  ./scripts/repo/prepare-candidate-deployment.sh --service transaction-service

Options:
  --service <artifact>       Runtime artifact to prepare:
                             transaction-service, currency-service,
                             permission-service, session-gateway,
                             budget-analyzer-web, or ext-authz.
  --candidate-tag <tag>      Candidate tag to validate. Defaults to
                             candidate-<artifact>-YYYYMMDD-<short-sha>.
  --create-tag               After validation, create an annotated Git tag.
  --push                     Push the created tag to origin. Requires
                             --create-tag.
  --yes, -y                  Do not prompt before creating or pushing a tag.
  -h, --help                 Show this help.

Candidate tags are Git tags, not GitHub Releases. They must start with
candidate-, must not start with v, and the image workflow publishes the same
Docker-safe tag as the container image tag.
EOF
}

info() {
    printf '[candidate-prep] %s\n' "$*"
}

warn() {
    printf '[candidate-prep] WARN: %s\n' "$*" >&2
}

die() {
    printf '[candidate-prep] ERROR: %s\n' "$*" >&2
    exit 1
}

repo_path() {
    printf '%s/%s\n' "${PARENT_DIR}" "$1"
}

artifact_exists() {
    local candidate="$1"
    local artifact

    for artifact in "${RUNTIME_ARTIFACTS[@]}"; do
        if [[ "${artifact}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

repo_in_set() {
    local repo="$1"
    shift
    local candidate

    for candidate in "$@"; do
        if [[ "${repo}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

read_consumer_service_common_version() {
    local repo="$1"
    local file_path
    local version=""
    local match_count=0

    file_path="$(repo_path "${repo}")/gradle/libs.versions.toml"
    [[ -f "${file_path}" ]] || die "missing version catalog: ../${repo}/gradle/libs.versions.toml"

    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*serviceCommon[[:space:]]*=[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
            version="${BASH_REMATCH[1]}"
            match_count=$((match_count + 1))
        fi
    done < "${file_path}"

    [[ "${match_count}" -eq 1 ]] || die "expected exactly one serviceCommon entry in ../${repo}/gradle/libs.versions.toml, found ${match_count}"
    printf '%s\n' "${version}"
}

default_candidate_tag() {
    local artifact="$1"
    local source_repo="$2"
    local short_sha
    local date_stamp

    short_sha="$(git -C "$(repo_path "${source_repo}")" rev-parse --short=7 HEAD)"
    date_stamp="$(date -u +%Y%m%d)"
    printf 'candidate-%s-%s-%s\n' "${artifact}" "${date_stamp}" "${short_sha}"
}

validate_candidate_tag() {
    local artifact="$1"
    local tag="$2"
    local pattern

    [[ "${tag}" != v* ]] || die "candidate tag must not start with v: ${tag}"
    [[ "${tag}" == candidate-* ]] || die "candidate tag must start with candidate-: ${tag}"
    [[ "${tag}" != "latest" ]] || die "candidate tag must not be latest"

    pattern="^candidate-${artifact}-[0-9]{8}-[0-9a-f]{6,12}$"
    [[ "${tag}" =~ ${pattern} ]] || \
        die "candidate tag must match candidate-${artifact}-YYYYMMDD-<short-sha>: ${tag}"
}

validate_repo_state() {
    local repo="$1"
    local tag_name="$2"
    local path
    local branch
    local local_ref
    local upstream_ref
    local merge_base
    local status_output

    path="$(repo_path "${repo}")"
    [[ -d "${path}/.git" ]] || die "missing git repository: ../${repo}"

    branch="$(git -C "${path}" rev-parse --abbrev-ref HEAD)"
    [[ "${branch}" == "main" ]] || die "../${repo} is on ${branch}; expected main"

    info "fetching origin/main for ${repo}"
    git -C "${path}" fetch origin main --quiet

    local_ref="$(git -C "${path}" rev-parse @)"
    upstream_ref="$(git -C "${path}" rev-parse '@{u}')" || \
        die "../${repo} main has no upstream; set upstream to origin/main"
    merge_base="$(git -C "${path}" merge-base @ '@{u}')"

    if [[ "${local_ref}" != "${upstream_ref}" ]]; then
        if [[ "${local_ref}" == "${merge_base}" ]]; then
            die "../${repo} is behind its upstream; pull before candidate prep"
        fi
        if [[ "${upstream_ref}" == "${merge_base}" ]]; then
            die "../${repo} has unpushed commits; push or reset before candidate prep"
        fi
        die "../${repo} has diverged from its upstream"
    fi

    git -C "${path}" update-index --refresh >/dev/null 2>&1 || true
    status_output="$(git -C "${path}" status --porcelain)"
    [[ -z "${status_output}" ]] || die "../${repo} has uncommitted or untracked changes"

    if git -C "${path}" rev-parse "${tag_name}" >/dev/null 2>&1; then
        die "${tag_name} already exists locally in ../${repo}"
    fi
    if git -C "${path}" ls-remote --exit-code --tags origin "refs/tags/${tag_name}" >/dev/null 2>&1; then
        die "${tag_name} already exists remotely in ${repo}"
    fi
}

confirm_tag_write() {
    local source_repo="$1"
    local tag_name="$2"
    local push_tag="$3"
    local reply

    info "repository: ${source_repo}"
    info "candidate tag: ${tag_name}"
    if [[ "${push_tag}" == true ]]; then
        info "action: create local annotated tag and push it to origin"
    else
        warn "action: create local annotated tag only"
    fi

    printf '[candidate-prep] Continue? [y/N] '
    read -r reply
    [[ "${reply}" =~ ^[Yy]$ ]] || die "aborted"
}

print_candidate_summary() {
    local artifact="$1"
    local source_repo="$2"
    local image_repo="$3"
    local candidate_tag="$4"
    local workflow="$5"
    local source_sha
    local service_common_version=""

    source_sha="$(git -C "$(repo_path "${source_repo}")" rev-parse HEAD)"

    if repo_in_set "${source_repo}" "${JAVA_RUNTIME_REPOS[@]}"; then
        service_common_version="$(read_consumer_service_common_version "${source_repo}")"
    fi

    info "artifact: ${artifact}"
    info "source repository: ${source_repo}"
    info "source commit: ${source_sha}"
    info "candidate source tag: ${candidate_tag}"
    info "candidate source ref: refs/tags/${candidate_tag}"
    info "image tag expected from workflow: ${candidate_tag}"
    info "image repository: ghcr.io/budgetanalyzer/${image_repo}"
    if [[ -n "${service_common_version}" ]]; then
        info "checked-in serviceCommon version: ${service_common_version}"
    fi
    info "workflow page: https://github.com/budgetanalyzer/${source_repo}/actions/workflows/${workflow}"
    info "after the workflow publishes, create a candidate deployment manifest with --status candidate"
    info "candidate tags should be retained until the manifest and workflow evidence are no longer needed"
}

create_candidate_tag() {
    local source_repo="$1"
    local candidate_tag="$2"
    local push_tag="$3"
    local path

    path="$(repo_path "${source_repo}")"
    git -C "${path}" tag -a "${candidate_tag}" -m "Candidate ${candidate_tag}"
    info "tagged ${source_repo} with ${candidate_tag}"

    if [[ "${push_tag}" == true ]]; then
        git -C "${path}" push origin "${candidate_tag}"
        info "pushed ${candidate_tag} from ${source_repo}"
    fi
}

main() {
    local artifact=""
    local candidate_tag=""
    local create_tag=false
    local push_tag=false
    local assume_yes=false
    local source_repo
    local image_repo
    local workflow

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --service|--artifact)
                artifact="${2:-}"
                [[ -n "${artifact}" ]] || die "missing value for --service"
                shift
                ;;
            --candidate-tag)
                candidate_tag="${2:-}"
                [[ -n "${candidate_tag}" ]] || die "missing value for --candidate-tag"
                shift
                ;;
            --create-tag)
                create_tag=true
                ;;
            --push)
                push_tag=true
                ;;
            --yes|-y)
                assume_yes=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                die "unexpected argument: $1"
                ;;
        esac
        shift
    done

    [[ -n "${artifact}" ]] || die "missing --service"
    artifact_exists "${artifact}" || die "unknown runtime artifact: ${artifact}"

    source_repo="${ARTIFACT_SOURCE_REPOS[${artifact}]}"
    image_repo="${ARTIFACT_IMAGE_REPOS[${artifact}]}"
    workflow="${ARTIFACT_WORKFLOWS[${artifact}]}"

    if [[ -z "${candidate_tag}" ]]; then
        candidate_tag="$(default_candidate_tag "${artifact}" "${source_repo}")"
    fi

    validate_candidate_tag "${artifact}" "${candidate_tag}"
    validate_repo_state "${source_repo}" "${candidate_tag}"
    print_candidate_summary "${artifact}" "${source_repo}" "${image_repo}" "${candidate_tag}" "${workflow}"

    if [[ "${push_tag}" == true && "${create_tag}" != true ]]; then
        die "--push requires --create-tag"
    fi

    if [[ "${create_tag}" == true ]]; then
        if [[ "${assume_yes}" != true ]]; then
            confirm_tag_write "${source_repo}" "${candidate_tag}" "${push_tag}"
        fi
        create_candidate_tag "${source_repo}" "${candidate_tag}" "${push_tag}"
    else
        info "tag creation not requested; rerun with --create-tag --push after review"
    fi
}

main "$@"
