#!/bin/bash

# clone-repos.sh - Clone all Budget Analyzer service repositories
#
# This script clones all required repositories as siblings to the orchestration repo.
# Run from anywhere - it will clone repos to the parent directory of orchestration.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-config.sh"

GITHUB_ORG="budgetanalyzer"

print_info "Cloning Budget Analyzer repositories..."
print_info "Target directory: $PARENT_DIR"
echo ""

cd "$PARENT_DIR"

cloned=0
skipped=0
failed=0

for repo in "${REPOS[@]}"; do
    if [ "$repo" = "orchestration" ]; then
        # Skip orchestration - we're already in it
        continue
    fi

    if [ -d "$repo" ]; then
        print_warning "$repo already exists, skipping"
        ((skipped++))
    else
        print_info "Cloning $repo..."
        if git clone "https://github.com/$GITHUB_ORG/$repo.git" 2>&1; then
            print_success "Cloned $repo"
            ((cloned++))
        else
            print_error "Failed to clone $repo"
            ((failed++))
        fi
    fi
done

echo ""
print_info "Summary: $cloned cloned, $skipped skipped, $failed failed"

if [ $failed -gt 0 ]; then
    print_error "Some repositories failed to clone. Check your network connection and try again."
    exit 1
fi

print_success "All repositories ready!"
