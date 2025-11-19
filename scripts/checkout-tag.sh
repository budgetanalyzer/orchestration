#!/bin/bash

# checkout-tag.sh - Checkout a specific tag across all Budget Analyzer repositories
#
# Usage: ./checkout-tag.sh <tag-name>
#
# This script will:
# 1. Verify all repositories are on main branch
# 2. Verify all repositories are up to date with remote
# 3. Checkout the specified tag in all repositories
# 4. Report any errors and stop if repositories are not in a clean state

set -e

# Get script directory and source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-config.sh"

# Validate arguments
if [ $# -ne 1 ]; then
    print_error "Usage: $0 <tag-name>"
    exit 1
fi

TAG_NAME="$1"
ERRORS=0

print_info "Checking out tag '$TAG_NAME' across all repositories"
echo ""

# Phase 1: Validate all repositories
print_info "Phase 1: Validating repository states..."
echo ""

for repo in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$repo"

    if [ ! -d "$REPO_PATH" ]; then
        print_error "$repo: Repository not found at $REPO_PATH"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    cd "$REPO_PATH"

    # Check if it's a git repository
    if [ ! -d ".git" ]; then
        print_error "$repo: Not a git repository"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Get current branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    # Check if on main branch
    if [ "$CURRENT_BRANCH" != "main" ]; then
        print_error "$repo: Not on main branch (currently on '$CURRENT_BRANCH')"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        print_error "$repo: Has uncommitted changes"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Check for untracked files
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        print_warning "$repo: Has untracked files (will continue anyway)"
    fi

    # Fetch latest from remote
    print_info "$repo: Fetching from remote..."
    if ! git fetch origin main --tags 2>&1 | grep -v "^From"; then
        print_error "$repo: Failed to fetch from remote"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Check if branch is up to date
    LOCAL_COMMIT=$(git rev-parse HEAD)
    REMOTE_COMMIT=$(git rev-parse origin/main)

    if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
        AHEAD=$(git rev-list --count origin/main..HEAD)
        BEHIND=$(git rev-list --count HEAD..origin/main)

        if [ "$BEHIND" -gt 0 ]; then
            print_error "$repo: Branch is $BEHIND commit(s) behind origin/main"
            ERRORS=$((ERRORS + 1))
        fi

        if [ "$AHEAD" -gt 0 ]; then
            print_error "$repo: Branch is $AHEAD commit(s) ahead of origin/main"
            ERRORS=$((ERRORS + 1))
        fi
        continue
    fi

    # Check if tag exists
    if ! git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
        print_error "$repo: Tag '$TAG_NAME' does not exist"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    print_success "$repo: Ready to checkout tag"
done

echo ""

# Exit if there were any errors
if [ $ERRORS -gt 0 ]; then
    print_error "Found $ERRORS error(s). Please fix the issues above before checking out tags."
    exit 1
fi

# Phase 2: Checkout tags
print_info "Phase 2: Checking out tag '$TAG_NAME'..."
echo ""

for repo in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$repo"

    cd "$REPO_PATH"

    print_info "$repo: Checking out tag '$TAG_NAME'..."
    if git checkout "$TAG_NAME"; then
        print_success "$repo: Successfully checked out tag '$TAG_NAME'"
    else
        print_error "$repo: Failed to checkout tag '$TAG_NAME'"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""

if [ $ERRORS -eq 0 ]; then
    print_success "All repositories successfully checked out to tag '$TAG_NAME'"
    exit 0
else
    print_error "Some repositories failed to checkout. See errors above."
    exit 1
fi
