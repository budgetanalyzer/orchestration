#!/bin/bash

# tag-release.sh - Tag all Budget Analyzer repositories with a common version
#
# Usage: ./scripts/tag-release.sh <version>
# Example: ./scripts/tag-release.sh v1.2.1
#
# This script will:
# 1. Validate the version format
# 2. Check that all repositories exist and are clean
# 3. Tag each repository with the specified version
# 4. Push all tags to remote

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Repository list (relative to parent directory)
REPOS=(
    "budget-analyzer"
    "budget-analyzer-api"
    "budget-analyzer-web"
    "currency-service"
    "service-common"
)

# Get the parent directory (two levels up from scripts dir, or one level up from repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$REPO_ROOT")"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if version argument is provided
if [ $# -eq 0 ]; then
    print_error "No version specified"
    echo "Usage: $0 <version>"
    echo "Example: $0 v1.2.1"
    exit 1
fi

VERSION=$1

# Validate version format (should be vX.Y.Z)
if ! [[ $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_warning "Version doesn't match standard format (vX.Y.Z)"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Aborted"
        exit 0
    fi
fi

print_info "Preparing to tag all repositories with version: $VERSION"
echo

# Phase 1: Validation - check all repos exist and are clean
print_info "Phase 1: Validating repositories..."
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

    # Check if tag already exists
    cd "$REPO_PATH"
    if git rev-parse "$VERSION" >/dev/null 2>&1; then
        print_warning "Tag $VERSION already exists in $REPO"
        VALIDATION_FAILED=1
        continue
    fi

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
    print_error "Validation failed. Please fix the issues above before tagging."
    exit 1
fi

# Phase 2: Confirmation
print_info "The following repositories will be tagged with $VERSION and pushed:"
for REPO in "${REPOS[@]}"; do
    echo "  - $REPO"
done
echo

read -p "Continue with tagging and pushing? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Aborted"
    exit 0
fi

echo

# Phase 3: Tagging
print_info "Phase 2: Tagging repositories..."

TAGGED_REPOS=()
FAILED_REPOS=()

for REPO in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$REPO"
    cd "$REPO_PATH"

    if git tag -a "$VERSION" -m "Release $VERSION"; then
        print_success "✓ Tagged $REPO with $VERSION"
        TAGGED_REPOS+=("$REPO")
    else
        print_error "✗ Failed to tag $REPO"
        FAILED_REPOS+=("$REPO")
    fi
done

echo

# Phase 4: Pushing tags
if [ ${#TAGGED_REPOS[@]} -gt 0 ]; then
    print_info "Phase 3: Pushing tags to remote..."

    PUSHED_REPOS=()
    PUSH_FAILED_REPOS=()

    for REPO in "${TAGGED_REPOS[@]}"; do
        REPO_PATH="$PARENT_DIR/$REPO"
        cd "$REPO_PATH"

        if git push origin "$VERSION"; then
            print_success "✓ Pushed tag from $REPO"
            PUSHED_REPOS+=("$REPO")
        else
            print_error "✗ Failed to push tag from $REPO"
            PUSH_FAILED_REPOS+=("$REPO")
        fi
    done

    echo
fi

# Summary
print_info "=== Summary ==="

if [ ${#PUSHED_REPOS[@]} -gt 0 ]; then
    echo -e "${GREEN}Successfully tagged and pushed ${#PUSHED_REPOS[@]} repositories:${NC}"
    for REPO in "${PUSHED_REPOS[@]}"; do
        echo "  ✓ $REPO"
    done
fi

if [ ${#PUSH_FAILED_REPOS[@]} -gt 0 ]; then
    echo
    echo -e "${YELLOW}Tagged but failed to push ${#PUSH_FAILED_REPOS[@]} repositories:${NC}"
    for REPO in "${PUSH_FAILED_REPOS[@]}"; do
        echo "  ! $REPO (tag exists locally)"
    done
fi

if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
    echo
    echo -e "${RED}Failed to tag ${#FAILED_REPOS[@]} repositories:${NC}"
    for REPO in "${FAILED_REPOS[@]}"; do
        echo "  ✗ $REPO"
    done
fi

if [ ${#PUSHED_REPOS[@]} -eq ${#REPOS[@]} ]; then
    echo
    print_success "All repositories successfully tagged with $VERSION and pushed!"
    exit 0
else
    echo
    print_warning "Some repositories were not fully processed. Please review the summary above."
    exit 1
fi
