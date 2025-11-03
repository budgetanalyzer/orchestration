#!/bin/bash

# validate-repos.sh - Validate all Budget Analyzer repositories are on main and up to date
#
# Usage: ./scripts/validate-repos.sh
#
# This script will:
# 1. Check that all repositories exist and are git repositories
# 2. Verify each repository is on the main branch
# 3. Check for uncommitted changes
# 4. Verify local branch is up to date with remote
#
# Exit codes:
#   0 - All repositories are valid and up to date
#   1 - One or more repositories failed validation

set -e  # Exit on error

# Get script directory and source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-config.sh"

print_info "Validating repositories..."
VALIDATION_FAILED=0

for REPO in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$REPO"

    # Check if repository exists
    if [ ! -d "$REPO_PATH" ]; then
        print_error "Repository not found: $REPO_PATH"
        VALIDATION_FAILED=1
        continue
    fi

    # Check if it's a git repository
    if [ ! -d "$REPO_PATH/.git" ]; then
        print_error "Not a git repository: $REPO_PATH"
        VALIDATION_FAILED=1
        continue
    fi

    cd "$REPO_PATH"

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        print_warning "Uncommitted changes in $REPO"
        VALIDATION_FAILED=1
        continue
    fi

    # Check for untracked files
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        print_warning "Untracked files in $REPO"
    fi

    # Check if on main branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [ "$CURRENT_BRANCH" != "main" ]; then
        print_error "Not on main branch in $REPO (currently on: $CURRENT_BRANCH)"
        VALIDATION_FAILED=1
        continue
    fi

    # Fetch latest from remote
    print_info "Fetching latest from remote for $REPO..."
    if ! git fetch origin main --quiet; then
        print_error "Failed to fetch from remote for $REPO"
        VALIDATION_FAILED=1
        continue
    fi

    # Check if local is behind remote
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    BASE=$(git merge-base @ @{u})

    if [ "$LOCAL" != "$REMOTE" ]; then
        if [ "$LOCAL" = "$BASE" ]; then
            print_error "$REPO is behind remote. Please pull latest changes."
            VALIDATION_FAILED=1
            continue
        elif [ "$REMOTE" = "$BASE" ]; then
            print_error "$REPO has unpushed commits. Please push before tagging."
            VALIDATION_FAILED=1
            continue
        else
            print_error "$REPO has diverged from remote. Please sync before tagging."
            VALIDATION_FAILED=1
            continue
        fi
    fi

    print_success "✓ $REPO"
done

echo

if [ $VALIDATION_FAILED -eq 1 ]; then
    print_error "Validation failed. Please fix the issues above."
    exit 1
fi

print_success "All repositories are valid and up to date!"
exit 0
