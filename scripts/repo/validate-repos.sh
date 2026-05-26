#!/usr/bin/env bash

set -euo pipefail

# Get script directory and source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x from repo root.
source "$SCRIPT_DIR/repo-config.sh"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/validate-repos.sh [options]

Options:
  --exclude repo[,repo...]  Exclude sibling repositories from validation.
                            May also be set with EXCLUDE_REPOS.
  -h, --help                Show this help.

Validates that the Budget Analyzer sibling repositories exist, are Git
repositories, are on main, have an upstream, are up to date with that upstream,
and have no uncommitted tracked changes. The command does not switch branches,
pull, clean, tag, commit, or push.
EOF
}

exclude_repos="${EXCLUDE_REPOS:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --exclude)
            exclude_repos="${2:-}"
            if [[ -z "${exclude_repos}" ]]; then
                print_error "missing value for --exclude"
                exit 1
            fi
            shift
            ;;
        --fix|--clean)
            print_error "$1 was removed; validate-repos.sh is read-only"
            exit 1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "unknown option: $1"
            usage >&2
            exit 1
            ;;
    esac
    shift
done

# Allow callers to exclude repos via EXCLUDE_REPOS (comma-separated)
if [[ -n "${exclude_repos}" ]]; then
    IFS=',' read -r -a _EXCLUDED <<< "${exclude_repos}"
    _FILTERED=()
    for REPO in "${REPOS[@]}"; do
        _SKIP=0
        for _EX in "${_EXCLUDED[@]}"; do
            if [[ "${REPO}" == "${_EX}" ]]; then
                _SKIP=1
                break
            fi
        done
        if [[ "${_SKIP}" -eq 0 ]]; then
            _FILTERED+=("${REPO}")
        fi
    done
    REPOS=("${_FILTERED[@]}")
fi

print_info "Validating repositories..."
VALIDATION_FAILED=0

for REPO in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$REPO"

    # Check if repository exists
    if [[ ! -d "${REPO_PATH}" ]]; then
        print_error "Repository not found: $REPO_PATH"
        VALIDATION_FAILED=1
        continue
    fi

    # Check if it's a git repository
    if [[ ! -d "${REPO_PATH}/.git" ]]; then
        print_error "Not a git repository: $REPO_PATH"
        VALIDATION_FAILED=1
        continue
    fi

    cd "$REPO_PATH" || {
        print_error "Failed to enter repository: $REPO_PATH"
        VALIDATION_FAILED=1
        continue
    }

    # Check if on main branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${CURRENT_BRANCH}" != "main" ]]; then
        print_error "Not on main branch in $REPO (currently on: $CURRENT_BRANCH)"
        VALIDATION_FAILED=1
        continue
    fi

    # Fetch latest from remote
    print_info "Fetching latest from remote for $REPO..."
    if ! git fetch origin main --quiet 2>/dev/null; then
        print_error "Failed to fetch from remote for $REPO"
        VALIDATION_FAILED=1
        continue
    fi

    # Check if local is behind remote
    # Use error handling since these can fail if upstream isn't configured
    if ! LOCAL=$(git rev-parse @ 2>/dev/null); then
        print_error "Failed to get local revision for $REPO"
        VALIDATION_FAILED=1
        continue
    fi

    if ! REMOTE=$(git rev-parse '@{u}' 2>/dev/null); then
        print_error "No upstream branch configured for $REPO. Run: git branch --set-upstream-to=origin/main main"
        VALIDATION_FAILED=1
        continue
    fi

    if ! BASE=$(git merge-base @ '@{u}' 2>/dev/null); then
        print_error "Failed to find merge base for $REPO"
        VALIDATION_FAILED=1
        continue
    fi

    # If behind remote, pull first (in fix mode) before checking for uncommitted changes
    if [[ "${LOCAL}" != "${REMOTE}" ]]; then
        if [[ "${LOCAL}" == "${BASE}" ]]; then
            print_error "$REPO is behind remote. Please pull latest changes."
            VALIDATION_FAILED=1
            continue
        elif [[ "${REMOTE}" == "${BASE}" ]]; then
            print_error "$REPO has unpushed commits. Please push before tagging."
            VALIDATION_FAILED=1
            continue
        else
            print_error "$REPO has diverged from remote. Please sync before tagging."
            VALIDATION_FAILED=1
            continue
        fi
    fi

    # Refresh the git index to avoid false positives
    git update-index --refresh >/dev/null 2>&1 || true

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        print_warning "Uncommitted changes in $REPO"
        VALIDATION_FAILED=1
        continue
    fi

    # Check for untracked files
    if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
        print_warning "Untracked files in $REPO"
    fi

    print_success "✓ $REPO"
done

echo

if [[ "${VALIDATION_FAILED}" -eq 1 ]]; then
    print_error "Validation failed. Please fix the issues above."
    exit 1
fi

print_success "All repositories are valid and up to date!"
exit 0
