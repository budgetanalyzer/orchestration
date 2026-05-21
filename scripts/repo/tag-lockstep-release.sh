#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/repo-config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/tag-lockstep-release.sh <vX.Y.Z> [--yes]

Options:
  --yes, -y    Do not prompt before creating and pushing tags.
  -h, --help   Show this help.

Tags the explicit lockstep release repository set. This helper exists for rare
coordinated stack releases. Use tag-release.sh --repo <repo> for normal
single-repository releases.
EOF
}

info() {
    printf '[tag-lockstep] %s\n' "$*"
}

warn() {
    printf '[tag-lockstep] WARN: %s\n' "$*" >&2
}

die() {
    printf '[tag-lockstep] ERROR: %s\n' "$*" >&2
    exit 1
}

repo_path() {
    printf '%s/%s\n' "${PARENT_DIR}" "$1"
}

normalize_tag() {
    local tag="$1"

    tag="${tag#v}"
    [[ "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "release version must use X.Y.Z or vX.Y.Z format: ${tag}"
    printf 'v%s\n' "${tag}"
}

repo_is_skipped() {
    local repo="$1"
    local skipped_repo

    for skipped_repo in "${SKIPPED_REPOS[@]}"; do
        if [[ "${repo}" == "${skipped_repo}" ]]; then
            return 0
        fi
    done

    return 1
}

validate_repo_state() {
    local repo="$1"
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
            die "../${repo} is behind its upstream; pull before lockstep tagging"
        fi
        if [[ "${upstream_ref}" == "${merge_base}" ]]; then
            die "../${repo} has unpushed commits; push or reset before lockstep tagging"
        fi
        die "../${repo} has diverged from its upstream"
    fi

    git -C "${path}" update-index --refresh >/dev/null 2>&1 || true
    status_output="$(git -C "${path}" status --porcelain)"
    [[ -z "${status_output}" ]] || die "../${repo} has uncommitted or untracked changes"
}

validate_repos() {
    local repo
    local path
    local validation_failed=false

    for repo in "${LOCKSTEP_RELEASE_REPOS[@]}"; do
        validate_repo_state "${repo}"
    done

    for repo in "${LOCKSTEP_RELEASE_REPOS[@]}"; do
        path="$(repo_path "${repo}")"
        if git -C "${path}" rev-parse "${VERSION}" >/dev/null 2>&1 || \
            git -C "${path}" ls-remote --exit-code --tags origin "refs/tags/${VERSION}" >/dev/null 2>&1; then
            if [[ "${repo}" == "service-common" ]]; then
                warn "${VERSION} already exists in service-common; skipping service-common in this lockstep tag run"
                SKIPPED_REPOS+=("${repo}")
            else
                warn "${VERSION} already exists in ${repo}"
                validation_failed=true
            fi
        fi
    done

    [[ "${validation_failed}" != true ]] || die "tag already exists in one or more required repositories"
}

confirm() {
    local repo
    local reply

    info "The following repositories will be tagged with ${VERSION} and pushed:"
    for repo in "${LOCKSTEP_RELEASE_REPOS[@]}"; do
        if repo_is_skipped "${repo}"; then
            printf '  - %s (skipped; tag already exists)\n' "${repo}"
        else
            printf '  - %s\n' "${repo}"
        fi
    done

    printf '[tag-lockstep] Continue? [y/N] '
    read -r reply
    [[ "${reply}" =~ ^[Yy]$ ]] || die "aborted"
}

tag_repos() {
    local repo
    local path

    for repo in "${LOCKSTEP_RELEASE_REPOS[@]}"; do
        if repo_is_skipped "${repo}"; then
            warn "skipping ${repo} because ${VERSION} already exists"
            continue
        fi

        path="$(repo_path "${repo}")"
        if git -C "${path}" tag -a "${VERSION}" -m "Release ${VERSION}"; then
            info "tagged ${repo} with ${VERSION}"
            TAGGED_REPOS+=("${repo}")
        else
            warn "failed to tag ${repo}"
            FAILED_REPOS+=("${repo}")
        fi
    done
}

push_tags() {
    local repo
    local path

    for repo in "${TAGGED_REPOS[@]}"; do
        path="$(repo_path "${repo}")"
        if git -C "${path}" push origin "${VERSION}"; then
            info "pushed ${VERSION} from ${repo}"
            PUSHED_REPOS+=("${repo}")
        else
            warn "failed to push ${VERSION} from ${repo}"
            PUSH_FAILED_REPOS+=("${repo}")
        fi
    done
}

print_summary() {
    local expected_pushed_count
    local repo

    info "summary"

    if [[ "${#PUSHED_REPOS[@]}" -gt 0 ]]; then
        printf 'Pushed %s repositories:\n' "${#PUSHED_REPOS[@]}"
        for repo in "${PUSHED_REPOS[@]}"; do
            printf '  - %s\n' "${repo}"
        done
    fi

    if [[ "${#PUSH_FAILED_REPOS[@]}" -gt 0 ]]; then
        printf 'Tagged but failed to push %s repositories:\n' "${#PUSH_FAILED_REPOS[@]}"
        for repo in "${PUSH_FAILED_REPOS[@]}"; do
            printf '  - %s\n' "${repo}"
        done
    fi

    if [[ "${#FAILED_REPOS[@]}" -gt 0 ]]; then
        printf 'Failed to tag %s repositories:\n' "${#FAILED_REPOS[@]}"
        for repo in "${FAILED_REPOS[@]}"; do
            printf '  - %s\n' "${repo}"
        done
    fi

    expected_pushed_count=$((${#LOCKSTEP_RELEASE_REPOS[@]} - ${#SKIPPED_REPOS[@]}))
    if [[ "${#PUSHED_REPOS[@]}" -eq "${expected_pushed_count}" && \
        "${#FAILED_REPOS[@]}" -eq 0 && \
        "${#PUSH_FAILED_REPOS[@]}" -eq 0 ]]; then
        info "all required repositories tagged with ${VERSION} and pushed"
        return 0
    fi

    return 1
}

main() {
    local assume_yes=false

    VERSION=""
    SKIPPED_REPOS=()
    TAGGED_REPOS=()
    FAILED_REPOS=()
    PUSHED_REPOS=()
    PUSH_FAILED_REPOS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
                [[ -z "${VERSION}" ]] || die "release version was provided more than once"
                VERSION="$1"
                ;;
        esac
        shift
    done

    [[ -n "${VERSION}" ]] || die "missing release version"
    VERSION="$(normalize_tag "${VERSION}")"

    info "preparing lockstep tag ${VERSION}"
    validate_repos

    if [[ "${assume_yes}" != true ]]; then
        confirm
    fi

    tag_repos
    push_tags
    print_summary
}

main "$@"
