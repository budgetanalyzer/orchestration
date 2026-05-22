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
  ./scripts/repo/prepare-service-release.sh --service <artifact> --version <X.Y.Z> [--tag] [--yes]
  ./scripts/repo/prepare-service-release.sh --service transaction-service --version 0.0.15

Options:
  --service <artifact>  Runtime artifact to prepare:
                        transaction-service, currency-service,
                        permission-service, session-gateway,
                        budget-analyzer-web, or ext-authz.
  --version <version>   Release version as X.Y.Z or vX.Y.Z.
  --tag                 After validation, call tag-release.sh for the selected
                        source repository.
  --yes, -y             Pass --yes to tag-release.sh when --tag is used.
  -h, --help            Show this help.

This helper validates only the selected artifact's source repository. It does
not validate or tag unrelated runtime repositories.
EOF
}

info() {
    printf '[service-release-prep] %s\n' "$*"
}

die() {
    printf '[service-release-prep] ERROR: %s\n' "$*" >&2
    exit 1
}

repo_path() {
    printf '%s/%s\n' "${PARENT_DIR}" "$1"
}

normalize_release_version() {
    local version="$1"

    version="${version#v}"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "release version must use X.Y.Z or vX.Y.Z format: ${version}"
    printf '%s\n' "${version}"
}

artifact_exists() {
    local target="$1"
    local artifact

    for artifact in "${RUNTIME_ARTIFACTS[@]}"; do
        if [[ "${artifact}" == "${target}" ]]; then
            return 0
        fi
    done

    return 1
}

repo_in_set() {
    local repo="$1"
    shift
    local target

    for target in "$@"; do
        if [[ "${repo}" == "${target}" ]]; then
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
            die "../${repo} is behind its upstream; pull before release prep"
        fi
        if [[ "${upstream_ref}" == "${merge_base}" ]]; then
            die "../${repo} has unpushed commits; push or reset before release prep"
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

print_release_summary() {
    local artifact="$1"
    local source_repo="$2"
    local image_repo="$3"
    local release_version="$4"
    local tag_name="$5"
    local workflow="$6"
    local source_sha
    local service_common_version=""

    source_sha="$(git -C "$(repo_path "${source_repo}")" rev-parse HEAD)"

    if repo_in_set "${source_repo}" "${JAVA_RUNTIME_REPOS[@]}"; then
        service_common_version="$(read_consumer_service_common_version "${source_repo}")"
    fi

    info "artifact: ${artifact}"
    info "source repository: ${source_repo}"
    info "source commit: ${source_sha}"
    info "source tag to create: ${tag_name}"
    info "image tag expected from workflow: ${release_version}"
    info "image repository: ghcr.io/budgetanalyzer/${image_repo}"
    if [[ -n "${service_common_version}" ]]; then
        info "checked-in serviceCommon version: ${service_common_version}"
    fi
    info "workflow page: https://github.com/budgetanalyzer/${source_repo}/actions/workflows/${workflow}"
    info "after the workflow publishes, run deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag ${tag_name} from the intended workspace state"
}

maybe_tag_release() {
    local source_repo="$1"
    local tag_name="$2"
    local assume_yes="$3"
    local tag_args=("--repo" "${source_repo}" "--version" "${tag_name}")

    if [[ "${assume_yes}" == true ]]; then
        tag_args+=("--yes")
    fi

    "${SCRIPT_DIR}/tag-release.sh" "${tag_args[@]}"
}

main() {
    local artifact=""
    local release_version=""
    local tag_after_validation=false
    local assume_yes=false
    local tag_name
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
            --version|--release-version)
                release_version="${2:-}"
                [[ -n "${release_version}" ]] || die "missing value for --version"
                shift
                ;;
            --tag)
                tag_after_validation=true
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
    [[ -n "${release_version}" ]] || die "missing --version"

    release_version="$(normalize_release_version "${release_version}")"
    tag_name="v${release_version}"
    source_repo="${ARTIFACT_SOURCE_REPOS[${artifact}]}"
    image_repo="${ARTIFACT_IMAGE_REPOS[${artifact}]}"
    workflow="${ARTIFACT_WORKFLOWS[${artifact}]}"

    validate_repo_state "${source_repo}" "${tag_name}"
    print_release_summary "${artifact}" "${source_repo}" "${image_repo}" "${release_version}" "${tag_name}" "${workflow}"

    if [[ "${tag_after_validation}" == true ]]; then
        maybe_tag_release "${source_repo}" "${tag_name}" "${assume_yes}"
    else
        info "tagging not requested; rerun with --tag or run scripts/repo/tag-release.sh --repo ${source_repo} ${tag_name}"
    fi
}

main "$@"
