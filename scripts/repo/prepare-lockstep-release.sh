#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/repo-config.sh"

PUBLISH_WORKFLOWS=(
    "service-common:publish-release.yml"
    "transaction-service:publish-release.yml"
    "currency-service:publish-release.yml"
    "permission-service:publish-release.yml"
    "session-gateway:publish-release.yml"
    "budget-analyzer-web:publish-release.yml"
    "orchestration:publish-ext-authz-release.yml"
)
readonly PUBLISH_WORKFLOWS

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/prepare-lockstep-release.sh --release-version 0.0.x
  ./scripts/repo/prepare-lockstep-release.sh v0.0.x --tag
  ./scripts/repo/prepare-lockstep-release.sh v0.0.x --tag-current-state

Options:
  --release-version <version>  Release version as X.Y.Z or vX.Y.Z.
  --tag                        After validation, prompt before calling
                               scripts/repo/tag-lockstep-release.sh vX.Y.Z.
  --tag-current-state          After validation, prompt before calling
                               scripts/repo/tag-lockstep-release.sh vX.Y.Z
                               --current-state so already-current tags are
                               skipped and absent tags are created.
  -h, --help                   Show this help.

This helper is source-release preparation only. It does not deploy to OCI and
does not update production image refs.
EOF
}

info() {
    printf '[release-prep] %s\n' "$*"
}

warn() {
    printf '[release-prep] WARN: %s\n' "$*" >&2
}

die() {
    printf '[release-prep] ERROR: %s\n' "$*" >&2
    exit 1
}

normalize_release_version() {
    local version="$1"

    version="${version#v}"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "release version must use X.Y.Z or vX.Y.Z format: ${version}"
    printf '%s\n' "${version}"
}

repo_path() {
    printf '%s/%s\n' "${PARENT_DIR}" "$1"
}

read_service_common_version() {
    local file_path
    local version=""
    local match_count=0

    file_path="$(repo_path "service-common")/build.gradle.kts"
    [[ -f "${file_path}" ]] || die "missing service-common build file: ../service-common/build.gradle.kts"

    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]*version[[:space:]]*=[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
            version="${BASH_REMATCH[1]}"
            match_count=$((match_count + 1))
        fi
    done < "${file_path}"

    [[ ${match_count} -eq 1 ]] || die "expected exactly one service-common version literal, found ${match_count}"
    printf '%s\n' "${version}"
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

    [[ ${match_count} -eq 1 ]] || die "expected exactly one serviceCommon entry in ../${repo}/gradle/libs.versions.toml, found ${match_count}"
    printf '%s\n' "${version}"
}

verify_repo_exists() {
    local repo="$1"
    local path

    path="$(repo_path "${repo}")"
    [[ -d "${path}/.git" ]] || die "missing git repository: ../${repo}"
}

verify_repo_clean_and_up_to_date() {
    local repo="$1"
    local path
    local branch
    local local_ref
    local upstream_ref
    local merge_base
    local status_output

    path="$(repo_path "${repo}")"
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
}

print_commit_table() {
    local repo path sha

    info "current release repository SHAs:"
    for repo in "${LOCKSTEP_RELEASE_REPOS[@]}"; do
        path="$(repo_path "${repo}")"
        sha="$(git -C "${path}" rev-parse HEAD)"
        printf '  %-24s %s\n' "${repo}" "${sha}"
    done
}

verify_release_repos() {
    local repo

    for repo in "${LOCKSTEP_RELEASE_REPOS[@]}"; do
        verify_repo_exists "${repo}"
        verify_repo_clean_and_up_to_date "${repo}"
    done
}

verify_service_common_versions() {
    local release_version="$1"
    local service_common_version
    local repo
    local consumer_version

    service_common_version="$(read_service_common_version)"
    [[ "${service_common_version}" == "${release_version}" ]] || \
        die "../service-common/build.gradle.kts is ${service_common_version}; expected ${release_version}"

    for repo in "${JAVA_RUNTIME_REPOS[@]}"; do
        consumer_version="$(read_consumer_service_common_version "${repo}")"
        [[ "${consumer_version}" == "${release_version}" ]] || \
            die "../${repo}/gradle/libs.versions.toml serviceCommon is ${consumer_version}; expected ${release_version}"
    done
}

verify_remote_tag_absent_or_skippable() {
    local tag_name="$1"
    local repo path

    for repo in "${LOCKSTEP_RELEASE_REPOS[@]}"; do
        path="$(repo_path "${repo}")"
        if git -C "${path}" ls-remote --exit-code --tags origin "refs/tags/${tag_name}" >/dev/null 2>&1; then
            if [[ "${repo}" == "service-common" ]]; then
                warn "${tag_name} already exists in service-common; repo/tag-lockstep-release.sh will skip that documented case"
                continue
            fi
            die "${tag_name} already exists remotely in ${repo}"
        fi
    done
}

print_workflow_urls() {
    local tag_name="$1"
    local entry repo workflow

    info "workflow pages to monitor after tags are pushed:"
    for entry in "${PUBLISH_WORKFLOWS[@]}"; do
        repo="${entry%%:*}"
        workflow="${entry#*:}"
        printf '  %-24s https://github.com/budgetanalyzer/%s/actions/workflows/%s\n' "${repo}" "${repo}" "${workflow}"
    done

    info "for OCI production, use the desired-state preparation flow instead of the historical release-manifest shape:"
    printf '  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag %s --plan-only\n' "${tag_name}"
    printf '  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag %s --push-tags\n' "${tag_name}"
    printf '  # After GitHub Actions publishes the expected GHCR tags:\n'
    printf '  ./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag %s --resolve-images\n' "${tag_name}"
}

maybe_tag_release() {
    local tag_name="$1"
    local current_state_tagging="$2"
    local reply
    local tag_args=("${tag_name}")

    if [[ "${current_state_tagging}" == true ]]; then
        tag_args+=("--current-state")
    fi

    printf '[release-prep] Call scripts/repo/tag-lockstep-release.sh'
    printf ' %s' "${tag_args[@]}"
    printf ' now? [y/N] '
    read -r reply
    if [[ "${reply}" =~ ^[Yy]$ ]]; then
        "${SCRIPT_DIR}/tag-lockstep-release.sh" "${tag_args[@]}"
        return
    fi

    info "tagging skipped; run ${SCRIPT_DIR}/tag-lockstep-release.sh ${tag_args[*]} when ready"
}

main() {
    local release_version=""
    local tag_after_validation=false
    local current_state_tagging=false
    local tag_name

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release-version)
                release_version="${2:-}"
                [[ -n "${release_version}" ]] || die "missing value for --release-version"
                shift
                ;;
            --tag)
                [[ "${current_state_tagging}" != true ]] || die "--tag and --tag-current-state are mutually exclusive"
                tag_after_validation=true
                ;;
            --tag-current-state)
                [[ "${tag_after_validation}" != true ]] || die "--tag and --tag-current-state are mutually exclusive"
                tag_after_validation=true
                current_state_tagging=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                [[ -z "${release_version}" ]] || die "release version was provided more than once"
                release_version="$1"
                ;;
        esac
        shift
    done

    [[ -n "${release_version}" ]] || die "missing release version"
    release_version="$(normalize_release_version "${release_version}")"
    tag_name="v${release_version}"

    verify_release_repos
    verify_service_common_versions "${release_version}"
    if [[ "${current_state_tagging}" == true ]]; then
        info "current-state tagging requested; tag-lockstep-release.sh will decide which repos need ${tag_name}"
    else
        verify_remote_tag_absent_or_skippable "${tag_name}"
    fi
    print_commit_table
    print_workflow_urls "${tag_name}"

    info "release preparation checks passed for ${tag_name}"

    if [[ "${tag_after_validation}" == true ]]; then
        maybe_tag_release "${tag_name}" "${current_state_tagging}"
    else
        info "tagging not requested; rerun with --tag, --tag-current-state, or run scripts/repo/tag-lockstep-release.sh ${tag_name}"
    fi
}

main "$@"
