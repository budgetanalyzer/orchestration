#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/repo-config.sh"

CONSUMER_REPOS=(
    "currency-service"
    "permission-service"
    "session-gateway"
    "transaction-service"
)

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/release-service-common-snapshot.sh prepare
  ./scripts/repo/release-service-common-snapshot.sh tag --push
  ./scripts/repo/release-service-common-snapshot.sh post

Correct sequence:
  ./scripts/repo/release-service-common-snapshot.sh prepare

  Merge service-common release prep.

  ./scripts/repo/release-service-common-snapshot.sh tag --push

  This tags only service-common to trigger Maven artifact publishing.

  Wait for service-common publish-release.yml.

  ./scripts/repo/release-service-common-snapshot.sh post

Releases the current service-common snapshot through the tag-driven
service-common publish-release.yml workflow.

This script intentionally does not use repo/tag-release.sh during the
service-common Maven release tag. Consumer repos also publish on tag pushes, so
an all-repo tag before post-release consumer version updates would release
consumer source that still points at the snapshot dependency.

Phases:
  prepare
    Requires ../service-common and all Java consumers to be pinned to the same
    MAJOR.MINOR.PATCH-SNAPSHOT version. Rewrites only
    ../service-common/build.gradle.kts to MAJOR.MINOR.PATCH, then runs:
      ./gradlew clean spotlessApply
      ./gradlew clean build

    Commit and merge the service-common release-prep change to main after this
    phase succeeds.

  tag
    Checks out service-common main, fast-forwards from origin/main, verifies
    local main matches origin/main, verifies the checked-in version is
    MAJOR.MINOR.PATCH, creates tag vMAJOR.MINOR.PATCH only in service-common,
    and pushes that tag to origin. This phase requires --push so the
    release-triggering network write is explicit at the call site.

  post
    Verifies the release tag exists on origin and updates Java consumers from
    MAJOR.MINOR.PATCH-SNAPSHOT to MAJOR.MINOR.PATCH. It leaves
    ../service-common/build.gradle.kts on the released version. Run this only
    after publish-release.yml has completed for the tag.
EOF
}

fail() {
    print_error "$1"
    exit 1
}

service_common_dir() {
    printf '%s/service-common\n' "${PARENT_DIR}"
}

service_common_build_file() {
    printf '%s/build.gradle.kts\n' "$(service_common_dir)"
}

consumer_catalog_file() {
    local repo="$1"
    printf '%s/%s/gradle/libs.versions.toml\n' "${PARENT_DIR}" "${repo}"
}

validate_snapshot_version() {
    local version="$1"

    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+-SNAPSHOT$ ]]
}

validate_release_version() {
    local version="$1"

    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

read_service_common_version() {
    local file_path
    local version=""
    local match_count=0

    file_path="$(service_common_build_file)"

    [[ -f "${file_path}" ]] || fail "Required file not found: ${file_path}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*version[[:space:]]*=[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
            version="${BASH_REMATCH[1]}"
            match_count=$((match_count + 1))
        fi
    done < "${file_path}"

    [[ ${match_count} -eq 1 ]] || fail "Expected exactly one service-common version literal in ${file_path}, found ${match_count}"

    printf '%s\n' "${version}"
}

read_consumer_version() {
    local repo="$1"
    local file_path
    local version=""
    local match_count=0

    file_path="$(consumer_catalog_file "${repo}")"

    [[ -f "${file_path}" ]] || fail "Required file not found: ${file_path}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*serviceCommon[[:space:]]*=[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
            version="${BASH_REMATCH[1]}"
            match_count=$((match_count + 1))
        fi
    done < "${file_path}"

    [[ ${match_count} -eq 1 ]] || fail "Expected exactly one serviceCommon entry in ${file_path}, found ${match_count}"

    printf '%s\n' "${version}"
}

require_clean_worktree() {
    local repo="$1"
    local repo_path="${PARENT_DIR}/${repo}"

    [[ -d "${repo_path}/.git" ]] || fail "Not a git repository: ${repo_path}"

    git -C "${repo_path}" update-index --refresh >/dev/null 2>&1 || true

    if ! git -C "${repo_path}" diff-index --quiet HEAD --; then
        fail "${repo} has uncommitted changes. Commit, stash, or discard them before running this phase."
    fi
}

require_main_at_origin() {
    local repo="$1"
    local repo_path="${PARENT_DIR}/${repo}"
    local current_branch
    local local_head
    local origin_head

    current_branch="$(git -C "${repo_path}" rev-parse --abbrev-ref HEAD)"
    [[ "${current_branch}" == "main" ]] || fail "${repo} must be on main; currently on ${current_branch}."

    local_head="$(git -C "${repo_path}" rev-parse HEAD)"
    origin_head="$(git -C "${repo_path}" rev-parse origin/main)"
    [[ "${local_head}" == "${origin_head}" ]] || fail "${repo} main is not at origin/main after fast-forward."
}

require_all_versions_on_same_snapshot() {
    local service_version
    local repo consumer_version

    service_version="$(read_service_common_version)"

    if ! validate_snapshot_version "${service_version}"; then
        fail "service-common version must end in -SNAPSHOT before release prep; found ${service_version}"
    fi

    for repo in "${CONSUMER_REPOS[@]}"; do
        consumer_version="$(read_consumer_version "${repo}")"

        if ! validate_snapshot_version "${consumer_version}"; then
            fail "${repo} serviceCommon version must end in -SNAPSHOT before release prep; found ${consumer_version}"
        fi

        if [[ "${consumer_version}" != "${service_version}" ]]; then
            fail "${repo} serviceCommon version is ${consumer_version}; expected ${service_version}"
        fi
    done

    printf '%s\n' "${service_version}"
}

rewrite_service_common_version() {
    local target_version="$1"
    local file_path
    local temp_file
    local match_count=0

    file_path="$(service_common_build_file)"
    temp_file="$(mktemp)"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^([[:space:]]*)version[[:space:]]*=[[:space:]]*\"[^\"]+\"([[:space:]]*)$ ]]; then
            printf '%sversion = "%s"%s\n' "${BASH_REMATCH[1]}" "${target_version}" "${BASH_REMATCH[2]}" >> "${temp_file}"
            match_count=$((match_count + 1))
        else
            printf '%s\n' "${line}" >> "${temp_file}"
        fi
    done < "${file_path}"

    if [[ ${match_count} -ne 1 ]]; then
        rm -f "${temp_file}"
        fail "Expected exactly one service-common version literal in ${file_path}, found ${match_count}"
    fi

    mv "${temp_file}" "${file_path}"
}

rewrite_consumer_version() {
    local repo="$1"
    local target_version="$2"
    local file_path
    local temp_file
    local match_count=0

    file_path="$(consumer_catalog_file "${repo}")"
    temp_file="$(mktemp)"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^([[:space:]]*)serviceCommon[[:space:]]*=[[:space:]]*\"[^\"]+\"([[:space:]]*)$ ]]; then
            printf '%sserviceCommon = "%s"%s\n' "${BASH_REMATCH[1]}" "${target_version}" "${BASH_REMATCH[2]}" >> "${temp_file}"
            match_count=$((match_count + 1))
        else
            printf '%s\n' "${line}" >> "${temp_file}"
        fi
    done < "${file_path}"

    if [[ ${match_count} -ne 1 ]]; then
        rm -f "${temp_file}"
        fail "Expected exactly one serviceCommon entry in ${file_path}, found ${match_count}"
    fi

    mv "${temp_file}" "${file_path}"
}

resolve_prepare_versions() {
    local snapshot_version

    snapshot_version="$(require_all_versions_on_same_snapshot)"
    printf '%s\n' "${snapshot_version}"
}

resolve_release_version() {
    local current_version

    current_version="$(read_service_common_version)"
    validate_release_version "${current_version}" || fail "service-common version is ${current_version}; expected a release version MAJOR.MINOR.PATCH."
    printf '%s\n' "${current_version}"
}

verify_origin_tag_exists() {
    local tag_name="$1"

    if ! git -C "$(service_common_dir)" ls-remote --exit-code --tags origin "refs/tags/${tag_name}" >/dev/null 2>&1; then
        fail "Origin tag ${tag_name} does not exist in service-common. Run the tag phase first."
    fi
}

run_prepare() {
    local snapshot_version
    local release_version

    snapshot_version="$(resolve_prepare_versions)"
    release_version="${snapshot_version%-SNAPSHOT}"

    require_clean_worktree "service-common"

    print_info "Preparing service-common ${release_version} from ${snapshot_version}"
    rewrite_service_common_version "${release_version}"

    print_info "Running service-common release validation"
    (
        cd "$(service_common_dir)"
        ./gradlew clean spotlessApply
        ./gradlew clean build
    )

    print_success "service-common release prep complete for ${release_version}"
    echo "Next: commit and merge the service-common release-prep change to main, then run:"
    echo "./scripts/repo/release-service-common-snapshot.sh tag --push"
}

run_tag() {
    local release_version
    local checked_in_version
    local tag_name

    require_clean_worktree "service-common"

    print_info "Synchronizing service-common main"
    git -C "$(service_common_dir)" fetch origin
    git -C "$(service_common_dir)" checkout main
    git -C "$(service_common_dir)" pull --ff-only origin main
    require_main_at_origin "service-common"

    release_version="$(resolve_release_version)"
    checked_in_version="$(read_service_common_version)"
    tag_name="v${release_version}"

    [[ "${checked_in_version}" == "${release_version}" ]] || fail "service-common main has version ${checked_in_version}; expected ${release_version}"

    if git -C "$(service_common_dir)" rev-parse --verify --quiet "refs/tags/${tag_name}" >/dev/null; then
        fail "Local tag ${tag_name} already exists in service-common."
    fi

    if git -C "$(service_common_dir)" ls-remote --exit-code --tags origin "refs/tags/${tag_name}" >/dev/null 2>&1; then
        fail "Origin tag ${tag_name} already exists in service-common."
    fi

    print_info "Creating and pushing ${tag_name}"
    git -C "$(service_common_dir)" tag "${tag_name}"
    git -C "$(service_common_dir)" push origin "${tag_name}"

    print_success "Pushed service-common ${tag_name}"
    echo "Next: wait for service-common publish-release.yml to complete, then run:"
    echo "./scripts/repo/release-service-common-snapshot.sh post"
}

run_post() {
    local release_version="$1"
    local service_version
    local expected_snapshot
    local repo consumer_version

    validate_release_version "${release_version}" || fail "Invalid release version: ${release_version}. Expected MAJOR.MINOR.PATCH."

    service_version="$(read_service_common_version)"
    expected_snapshot="${release_version}-SNAPSHOT"

    [[ "${service_version}" == "${release_version}" ]] || fail "service-common version is ${service_version}; expected released version ${release_version}"

    for repo in "${CONSUMER_REPOS[@]}"; do
        consumer_version="$(read_consumer_version "${repo}")"

        if ! validate_snapshot_version "${consumer_version}"; then
            fail "${repo} serviceCommon version must still end in -SNAPSHOT before post-release update; found ${consumer_version}"
        fi

        [[ "${consumer_version}" == "${expected_snapshot}" ]] || fail "${repo} serviceCommon version is ${consumer_version}; expected ${expected_snapshot}"
    done

    verify_origin_tag_exists "v${release_version}"
    print_info "Assuming publish-release.yml has completed for v${release_version}."

    for repo in "${CONSUMER_REPOS[@]}"; do
        require_clean_worktree "${repo}"
    done

    print_info "Updating Java consumers to ${release_version}"
    for repo in "${CONSUMER_REPOS[@]}"; do
        rewrite_consumer_version "${repo}" "${release_version}"
    done

    print_success "Post-release version updates complete"
    echo "Changed:"
    for repo in "${CONSUMER_REPOS[@]}"; do
        echo "- ../${repo}/gradle/libs.versions.toml -> ${release_version}"
    done
    echo
    echo "service-common remains on ${release_version}; bump it manually when ready."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

command_name="${1:-}"
[[ -n "${command_name}" ]] || {
    usage
    exit 1
}
shift

case "${command_name}" in
    prepare)
        [[ $# -eq 0 ]] || fail "prepare does not accept version arguments; it reads ../service-common/build.gradle.kts."
        run_prepare
        ;;
    tag)
        tag_push=0

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --push)
                    tag_push=1
                    ;;
                -*)
                    fail "Unknown tag option: $1"
                    ;;
                *)
                    fail "tag does not accept version arguments; it reads ../service-common/build.gradle.kts."
                    ;;
            esac
            shift
        done

        [[ ${tag_push} -eq 1 ]] || fail "tag pushes the release tag and requires --push."
        run_tag
        ;;
    post)
        [[ $# -eq 0 ]] || fail "post does not accept version arguments; it reads ../service-common/build.gradle.kts."
        post_release_version="$(resolve_release_version)"
        run_post "${post_release_version}"
        ;;
    *)
        usage
        exit 1
        ;;
esac
