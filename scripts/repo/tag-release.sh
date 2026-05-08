#!/bin/bash

# tag-release.sh - Tag all Budget Analyzer repositories with a common version
#
# Usage: ./scripts/repo/tag-release.sh <version>
# Example: ./scripts/repo/tag-release.sh v1.2.1
#
# This script will:
# 1. Validate the version format
# 2. Check that all tagged repositories exist and are clean
# 3. Tag each repository except service-common with the specified version
# 4. Push all tags to remote

set -e  # Exit on error

# Get script directory and source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "$SCRIPT_DIR/repo-config.sh"

# repo-config.sh already defines the release repo set; no exclusions needed

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

SKIPPED_REPOS=("service-common")

repo_is_skipped() {
    local repo="$1"
    local skipped_repo

    for skipped_repo in "${SKIPPED_REPOS[@]}"; do
        if [ "$repo" = "$skipped_repo" ]; then
            return 0
        fi
    done

    return 1
}

print_warning "service-common is skipped by this all-repo tag flow."
echo "  Reason: service-common is tagged earlier to publish Maven artifacts, and"
echo "  after the post flow its checked-in version is the next SNAPSHOT."
echo

# Step 1: Validation - check all repos exist and are clean
print_info "Step 1: Validating repositories..."

# Run the validation script (pass exclusions so it validates the same repo set)
if ! EXCLUDE_REPOS="$(IFS=','; echo "${SKIPPED_REPOS[*]}")" "$SCRIPT_DIR/validate-repos.sh"; then
    print_error "Repository validation failed. Please fix the issues above before tagging."
    exit 1
fi

# Additional validation: Check if tag already exists in any repository
VALIDATION_FAILED=0

# shellcheck disable=SC2153 # REPOS is defined by repo-config.sh.
for REPO in "${REPOS[@]}"; do
    if repo_is_skipped "$REPO"; then
        print_warning "Skipping tag-existence validation for $REPO"
        continue
    fi

    REPO_PATH="$PARENT_DIR/$REPO"
    cd "$REPO_PATH"

    TAG_EXISTS=0
    if git rev-parse "$VERSION" >/dev/null 2>&1; then
        TAG_EXISTS=1
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/$VERSION" >/dev/null 2>&1; then
        TAG_EXISTS=1
    fi

    if [ $TAG_EXISTS -eq 1 ]; then
        print_warning "Tag $VERSION already exists in $REPO"
        VALIDATION_FAILED=1
    fi
done

echo

if [ $VALIDATION_FAILED -eq 1 ]; then
    print_error "Tag already exists in one or more repositories. Aborting."
    exit 1
fi

# Step 2: Confirmation
print_info "The following repositories will be tagged with $VERSION and pushed:"
for REPO in "${REPOS[@]}"; do
    if repo_is_skipped "$REPO"; then
        echo "  - $REPO (skipped; service-common was tagged earlier for Maven release)"
    else
        echo "  - $REPO"
    fi
done
echo

read -p "Continue with tagging and pushing? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Aborted"
    exit 0
fi

echo

# Step 3: Tagging
print_info "Step 3: Tagging repositories..."

TAGGED_REPOS=()
FAILED_REPOS=()

for REPO in "${REPOS[@]}"; do
    if repo_is_skipped "$REPO"; then
        print_warning "↷ Skipping $REPO because service-common is tagged separately"
        continue
    fi

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

# Step 4: Pushing tags
if [ ${#TAGGED_REPOS[@]} -gt 0 ]; then
    print_info "Step 4: Pushing tags to remote..."

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

if [ ${#SKIPPED_REPOS[@]} -gt 0 ]; then
    echo
    echo -e "${YELLOW}Skipped ${#SKIPPED_REPOS[@]} repositories by policy:${NC}"
    for REPO in "${SKIPPED_REPOS[@]}"; do
        echo "  ↷ $REPO (service-common Maven release tag is managed separately)"
    done
fi

EXPECTED_PUSHED_COUNT=$((${#REPOS[@]} - ${#SKIPPED_REPOS[@]}))

if [ ${#PUSHED_REPOS[@]} -eq "$EXPECTED_PUSHED_COUNT" ] && [ ${#FAILED_REPOS[@]} -eq 0 ] && [ ${#PUSH_FAILED_REPOS[@]} -eq 0 ]; then
    echo
    print_success "All required repositories successfully tagged with $VERSION and pushed!"
    exit 0
else
    echo
    print_warning "Some repositories were not fully processed. Please review the summary above."
    exit 1
fi
