#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/repo-config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/tag-lockstep-release.sh <vX.Y.Z> [--repo-set lockstep] [--yes]
  ./scripts/repo/tag-lockstep-release.sh <vX.Y.Z> --repo-set runtime-images --current-state [--plan-only] [--yes]

Options:
  --repo-set <set>   Repository set to inspect and tag:
                     lockstep, runtime-images, or oci-release.
                     Defaults to lockstep for the historical coordinated path.
  --current-state  Compare the requested tag with each repo's current local
                   HEAD. Tag repos where the tag is absent, skip repos where
                   the tag already points at current HEAD, and fail if the tag
                   points somewhere else.
  --plan-only      With --current-state, print what would be tagged and exit
                   without creating or pushing tags.
  --yes, -y        Do not prompt before creating and pushing tags.
  -h, --help       Show this help.

Tags an explicit release repository set. This helper exists for rare
coordinated stack releases and current-state runtime image tagging. Use
tag-release.sh --repo <repo> for normal single-repository releases. The default
mode keeps the historical strict release checks. Use --current-state only when
the current local checked-out state is the intended deployable state.
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

select_repo_set() {
    local repo_set="$1"

    case "${repo_set}" in
        lockstep)
            SELECTED_REPOS=("${LOCKSTEP_RELEASE_REPOS[@]}")
            ;;
        runtime-images)
            SELECTED_REPOS=("${RUNTIME_IMAGE_REPOS[@]}")
            ;;
        oci-release)
            SELECTED_REPOS=("${OCI_RELEASE_SOURCE_REPOS[@]}")
            ;;
        *)
            die "unknown repo set: ${repo_set}. Expected lockstep, runtime-images, or oci-release"
            ;;
    esac
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

repo_is_push_only() {
    local repo="$1"
    local push_only_repo

    for push_only_repo in "${PUSH_ONLY_REPOS[@]}"; do
        if [[ "${repo}" == "${push_only_repo}" ]]; then
            return 0
        fi
    done

    return 1
}

local_tag_commit() {
    local repo="$1"
    local path

    path="$(repo_path "${repo}")"
    git -C "${path}" rev-parse -q --verify "${VERSION}^{commit}" 2>/dev/null || true
}

remote_tag_commit() {
    local repo="$1"
    local path
    local output
    local peeled_ref
    local exact_ref

    path="$(repo_path "${repo}")"
    peeled_ref="refs/tags/${VERSION}^{}"
    exact_ref="refs/tags/${VERSION}"

    output="$(git -C "${path}" ls-remote --tags origin "refs/tags/${VERSION}*" 2>/dev/null || true)"
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

validate_repo_current_state() {
    local repo="$1"
    local path
    local branch
    local status_output
    local head_commit
    local local_commit
    local remote_commit
    local existing_commit

    path="$(repo_path "${repo}")"
    [[ -d "${path}/.git" ]] || die "missing git repository: ../${repo}"

    branch="$(git -C "${path}" rev-parse --abbrev-ref HEAD)"
    if [[ "${branch}" == "HEAD" ]]; then
        branch="detached"
    fi

    git -C "${path}" update-index --refresh >/dev/null 2>&1 || true
    status_output="$(git -C "${path}" status --porcelain)"
    [[ -z "${status_output}" ]] || die "../${repo} has uncommitted or untracked changes"

    head_commit="$(git -C "${path}" rev-parse HEAD)"
    local_commit="$(local_tag_commit "${repo}")"
    remote_commit="$(remote_tag_commit "${repo}")"

    if [[ -n "${local_commit}" && -n "${remote_commit}" && "${local_commit}" != "${remote_commit}" ]]; then
        die "${VERSION} differs between local and origin for ${repo}; local=${local_commit}, origin=${remote_commit}"
    fi

    existing_commit="${local_commit:-${remote_commit}}"
    if [[ -n "${existing_commit}" ]]; then
        if [[ "${existing_commit}" == "${head_commit}" ]]; then
            if [[ -n "${local_commit}" && -z "${remote_commit}" ]]; then
                info "${repo}: ${VERSION} exists locally at current ${branch} HEAD ${head_commit}; will push existing local tag"
                PUSH_ONLY_REPOS+=("${repo}")
            else
                info "${repo}: ${VERSION} already points at current ${branch} HEAD ${head_commit}; skipping"
                SKIPPED_REPOS+=("${repo}")
            fi
            return
        fi

        die "${repo}: ${VERSION} points at ${existing_commit}, but current ${branch} HEAD is ${head_commit}"
    fi

    info "${repo}: ${VERSION} is absent; will tag current ${branch} HEAD ${head_commit}"
}

validate_repos() {
    local repo
    local path
    local validation_failed=false

    if [[ "${CURRENT_STATE_MODE}" == true ]]; then
        for repo in "${SELECTED_REPOS[@]}"; do
            validate_repo_current_state "${repo}"
        done
        return
    fi

    for repo in "${SELECTED_REPOS[@]}"; do
        validate_repo_state "${repo}"
    done

    for repo in "${SELECTED_REPOS[@]}"; do
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

    if [[ "${CURRENT_STATE_MODE}" == true ]]; then
        info "Current-state mode is active. Repositories with ${VERSION} already at current HEAD will be skipped."
    fi

    info "The following ${REPO_SET} repositories will be tagged with ${VERSION} and pushed:"
    for repo in "${SELECTED_REPOS[@]}"; do
        if repo_is_skipped "${repo}"; then
            printf '  - %s (skipped; tag already points at current HEAD)\n' "${repo}"
        elif repo_is_push_only "${repo}"; then
            printf '  - %s (push existing local tag)\n' "${repo}"
        else
            printf '  - %s\n' "${repo}"
        fi
    done

    printf '[tag-lockstep] Continue? [y/N] '
    read -r reply
    [[ "${reply}" =~ ^[Yy]$ ]] || die "aborted"
}

print_plan() {
    local repo

    info "current-state tag plan for ${VERSION} across ${REPO_SET} repos:"
    for repo in "${SELECTED_REPOS[@]}"; do
        if repo_is_skipped "${repo}"; then
            printf '  - %s: skip, tag already points at current HEAD\n' "${repo}"
        elif repo_is_push_only "${repo}"; then
            printf '  - %s: push existing local tag\n' "${repo}"
        else
            printf '  - %s: create and push tag\n' "${repo}"
        fi
    done
}

tag_repos() {
    local repo
    local path

    for repo in "${SELECTED_REPOS[@]}"; do
        if repo_is_skipped "${repo}"; then
            warn "skipping ${repo} because ${VERSION} already exists"
            continue
        fi
        if repo_is_push_only "${repo}"; then
            warn "not creating ${repo} because ${VERSION} already exists locally at current HEAD"
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

    for repo in "${TAGGED_REPOS[@]}" "${PUSH_ONLY_REPOS[@]}"; do
        [[ -n "${repo}" ]] || continue
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

    expected_pushed_count=$((${#SELECTED_REPOS[@]} - ${#SKIPPED_REPOS[@]}))
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
    REPO_SET="lockstep"
    SELECTED_REPOS=()
    CURRENT_STATE_MODE=false
    PLAN_ONLY=false
    SKIPPED_REPOS=()
    PUSH_ONLY_REPOS=()
    TAGGED_REPOS=()
    FAILED_REPOS=()
    PUSHED_REPOS=()
    PUSH_FAILED_REPOS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo-set)
                REPO_SET="${2:-}"
                [[ -n "${REPO_SET}" ]] || die "missing value for --repo-set"
                shift
                ;;
            --current-state)
                CURRENT_STATE_MODE=true
                ;;
            --plan-only)
                PLAN_ONLY=true
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
                [[ -z "${VERSION}" ]] || die "release version was provided more than once"
                VERSION="$1"
                ;;
        esac
        shift
    done

    [[ -n "${VERSION}" ]] || die "missing release version"
    VERSION="$(normalize_tag "${VERSION}")"
    select_repo_set "${REPO_SET}"
    if [[ "${PLAN_ONLY}" == true && "${CURRENT_STATE_MODE}" != true ]]; then
        die "--plan-only requires --current-state"
    fi

    info "preparing ${REPO_SET} tag ${VERSION}"
    validate_repos

    if [[ "${PLAN_ONLY}" == true ]]; then
        print_plan
        exit 0
    fi

    if [[ "${assume_yes}" != true ]]; then
        confirm
    fi

    tag_repos
    push_tags
    print_summary
}

main "$@"
