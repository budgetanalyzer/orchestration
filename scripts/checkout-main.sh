#!/bin/bash

# checkout-main.sh - Switch all Budget Analyzer repositories from tags to main branch
#
# Usage: ./scripts/checkout-main.sh [--pull]
#
# This script will:
# 1. Check that all repositories exist
# 2. Checkout the main branch in each repository
# 3. Optionally pull latest changes from remote (if --pull flag is provided)
#
# Options:
#   --pull    Pull latest changes from remote after checking out main

set -e  # Exit on error

# Get script directory and source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-config.sh"

# Parse arguments
PULL_CHANGES=0
if [ "$1" = "--pull" ]; then
    PULL_CHANGES=1
fi

print_info "Preparing to checkout main branch in all repositories"
if [ $PULL_CHANGES -eq 1 ]; then
    print_info "Will also pull latest changes from remote"
fi
echo

# Phase 1: Validation - check all repos exist
print_info "Phase 1: Validating repositories..."
VALIDATION_FAILED=0

for REPO in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$REPO"

    if [ ! -d "$REPO_PATH" ]; then
        print_error "Repository not found: $REPO_PATH"
        VALIDATION_FAILED=1
        continue
    fi

    if [ ! -d "$REPO_PATH/.git" ]; then
        print_error "Not a git repository: $REPO_PATH"
        VALIDATION_FAILED=1
        continue
    fi

    cd "$REPO_PATH"

    # Check current status
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
    if [ "$CURRENT_BRANCH" = "HEAD" ]; then
        CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "unknown")
        print_info "  $REPO: Currently on tag $CURRENT_TAG"
    else
        print_info "  $REPO: Currently on branch $CURRENT_BRANCH"
    fi
done

echo

if [ $VALIDATION_FAILED -eq 1 ]; then
    print_error "Repository validation failed. Please fix the issues above."
    exit 1
fi

print_success "All repositories validated"
echo

# Phase 2: Confirmation
print_info "The following repositories will be switched to main branch:"
for REPO in "${REPOS[@]}"; do
    echo "  - $REPO"
done
echo

read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Aborted"
    exit 0
fi

echo

# Phase 3: Checkout main branch
print_info "Phase 2: Checking out main branch..."

SUCCESS_REPOS=()
FAILED_REPOS=()

for REPO in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$REPO"
    cd "$REPO_PATH"

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD 2>/dev/null; then
        print_warning "⚠ $REPO has uncommitted changes, skipping"
        FAILED_REPOS+=("$REPO (uncommitted changes)")
        continue
    fi

    # Checkout main branch
    if git checkout main 2>/dev/null; then
        print_success "✓ Checked out main in $REPO"
        SUCCESS_REPOS+=("$REPO")
    else
        print_error "✗ Failed to checkout main in $REPO"
        FAILED_REPOS+=("$REPO")
        continue
    fi

    # Pull changes if requested
    if [ $PULL_CHANGES -eq 1 ]; then
        if git pull origin main; then
            print_success "  ↓ Pulled latest changes for $REPO"
        else
            print_warning "  ⚠ Could not pull changes for $REPO"
        fi
    fi
done

echo

# Summary
print_info "=== Summary ==="

if [ ${#SUCCESS_REPOS[@]} -gt 0 ]; then
    echo -e "${GREEN}Successfully checked out main in ${#SUCCESS_REPOS[@]} repositories:${NC}"
    for REPO in "${SUCCESS_REPOS[@]}"; do
        echo "  ✓ $REPO"
    done
fi

if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    echo
    echo -e "${RED}Failed to checkout main in ${#FAILED_REPOS[@]} repositories:${NC}"
    for REPO in "${FAILED_REPOS[@]}"; do
        echo "  ✗ $REPO"
    done
fi

if [ ${#SUCCESS_REPOS[@]} -eq ${#REPOS[@]} ]; then
    echo
    print_success "All repositories successfully switched to main branch!"
    exit 0
else
    echo
    print_warning "Some repositories were not processed. Please review the summary above."
    exit 1
fi
