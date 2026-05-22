#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/repo-config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/tag-release.sh --repo <repo> --version <vX.Y.Z> [--yes] [--no-push]
  ./scripts/repo/tag-release.sh --repo transaction-service v0.0.15

Options:
  --repo <repo>       Repository to tag. Must be a runtime image repo or
                      service-common. Use tag-lockstep-release.sh for the
                      rare coordinated all-repo tag.
  --version <tag>     Release tag in vX.Y.Z form.
  --yes               Do not prompt before creating and pushing the tag.
  --no-push           Create the local tag only.
  -h, --help          Show this help.

This is the normal single-repository tag helper. It validates only the selected
repository and does not tag unrelated repos.
EOF
}

info() {
    printf '[tag-release] %s\n' "$*"
}

warn() {
    printf '[tag-release] WARN: %s\n' "$*" >&2
}

die() {
    printf '[tag-release] ERROR: %s\n' "$*" >&2
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

validate_repo_allowed() {
    local repo="$1"

    if repo_in_set "${repo}" "${RUNTIME_IMAGE_REPOS[@]}" || \
        repo_in_set "${repo}" "${SHARED_LIBRARY_REPOS[@]}"; then
        return
    fi

    if repo_in_set "${repo}" "${TOOLING_REPOS[@]}"; then
        die "${repo} is a tooling repo, not an OCI runtime release repo"
    fi

    die "unknown or unsupported release repo: ${repo}"
}

validate_repo_state() {
    local repo="$1"
    local tag="$2"
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
            die "../${repo} is behind its upstream; pull before tagging"
        fi
        if [[ "${upstream_ref}" == "${merge_base}" ]]; then
            die "../${repo} has unpushed commits; push or reset before tagging"
        fi
        die "../${repo} has diverged from its upstream"
    fi

    git -C "${path}" update-index --refresh >/dev/null 2>&1 || true
    status_output="$(git -C "${path}" status --porcelain)"
    [[ -z "${status_output}" ]] || die "../${repo} has uncommitted or untracked changes"

    if git -C "${path}" rev-parse "${tag}" >/dev/null 2>&1; then
        die "${tag} already exists locally in ../${repo}"
    fi
    if git -C "${path}" ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
        die "${tag} already exists remotely in ${repo}"
    fi
}

confirm() {
    local repo="$1"
    local tag="$2"
    local push_tag="$3"
    local reply

    info "repository: ${repo}"
    info "tag: ${tag}"
    if [[ "${push_tag}" == true ]]; then
        info "action: create local annotated tag and push it to origin"
    else
        warn "action: create local annotated tag only"
    fi

    printf '[tag-release] Continue? [y/N] '
    read -r reply
    [[ "${reply}" =~ ^[Yy]$ ]] || die "aborted"
}

main() {
    local repo=""
    local tag=""
    local assume_yes=false
    local push_tag=true
    local path

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)
                repo="${2:-}"
                [[ -n "${repo}" ]] || die "missing value for --repo"
                shift
                ;;
            --version)
                tag="${2:-}"
                [[ -n "${tag}" ]] || die "missing value for --version"
                shift
                ;;
            --yes|-y)
                assume_yes=true
                ;;
            --no-push)
                push_tag=false
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                [[ -z "${tag}" ]] || die "release version was provided more than once"
                tag="$1"
                ;;
        esac
        shift
    done

    [[ -n "${repo}" ]] || die "missing --repo"
    [[ -n "${tag}" ]] || die "missing release version"
    tag="$(normalize_tag "${tag}")"

    validate_repo_allowed "${repo}"
    validate_repo_state "${repo}" "${tag}"

    if [[ "${assume_yes}" != true ]]; then
        confirm "${repo}" "${tag}" "${push_tag}"
    fi

    path="$(repo_path "${repo}")"
    git -C "${path}" tag -a "${tag}" -m "Release ${tag}"
    info "tagged ${repo} with ${tag}"

    if [[ "${push_tag}" == true ]]; then
        git -C "${path}" push origin "${tag}"
        info "pushed ${tag} from ${repo}"
    fi
}

main "$@"
