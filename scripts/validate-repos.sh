#!/bin/bash

# validate-repos.sh - Validate all Budget Analyzer repositories are on main and up to date
#
# Usage: ./scripts/validate-repos.sh [--fix]
#
# This script will:
# 1. Check that all repositories exist and are git repositories
# 2. Verify each repository is on the main branch
# 3. Check for uncommitted changes
# 4. Verify local branch is up to date with remote
#
# Options:
#   --fix    Attempt to fix issues automatically where possible:
#            - Switch to main branch if not on it (fails if uncommitted changes)
#            - Pull latest changes if behind remote
#
# Exit codes:
#   0 - All repositories are valid and up to date
#   1 - One or more repositories failed validation

# Get script directory and source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-config.sh"

# Parse command line arguments
FIX_MODE=0
if [ "$1" = "--fix" ] || [ "$1" = "--clean" ]; then
    FIX_MODE=1
    print_info "Running in fix mode - will attempt to fix issues automatically"
fi

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
        if [ $FIX_MODE -eq 1 ]; then
            print_warning "Not on main branch in $REPO (currently on: $CURRENT_BRANCH)"
            print_info "Attempting to switch to main branch..."
            if git checkout main; then
                print_success "✓ Switched to main branch in $REPO"
            else
                print_error "Failed to switch to main branch in $REPO"
                VALIDATION_FAILED=1
                continue
            fi
        else
            print_error "Not on main branch in $REPO (currently on: $CURRENT_BRANCH)"
            VALIDATION_FAILED=1
            continue
        fi
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

    if ! REMOTE=$(git rev-parse @{u} 2>/dev/null); then
        print_error "No upstream branch configured for $REPO. Run: git branch --set-upstream-to=origin/main main"
        VALIDATION_FAILED=1
        continue
    fi

    if ! BASE=$(git merge-base @ @{u} 2>/dev/null); then
        print_error "Failed to find merge base for $REPO"
        VALIDATION_FAILED=1
        continue
    fi

    if [ "$LOCAL" != "$REMOTE" ]; then
        if [ "$LOCAL" = "$BASE" ]; then
            if [ $FIX_MODE -eq 1 ]; then
                print_warning "$REPO is behind remote. Attempting to pull latest changes..."
                if git pull origin main --quiet; then
                    print_success "✓ Pulled latest changes for $REPO"
                else
                    print_error "Failed to pull latest changes for $REPO"
                    VALIDATION_FAILED=1
                    continue
                fi
            else
                print_error "$REPO is behind remote. Please pull latest changes."
                VALIDATION_FAILED=1
                continue
            fi
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
