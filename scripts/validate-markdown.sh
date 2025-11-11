#!/usr/bin/env bash
# scripts/validate-markdown.sh
# Validates all markdown files for broken @references and executable discovery commands
# across all Budget Analyzer repositories

set -e

# Get script directory and source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/repo-config.sh"

# Validates that cross-repo references have GitHub URLs
# Args: $1=ref (@service-common/file.md), $2=path (service-common/file.md), $3=file
# Returns: 0 if valid, 1 if error (and prints error message)
validate_cross_repo_url() {
    local ref="$1"
    local path="$2"
    local file="$3"
    local first_segment="${path%%/*}"

    # Check if first segment matches any repo in REPOS array
    for repo in "${REPOS[@]}"; do
        if [ "$first_segment" == "$repo" ]; then
            # This is a cross-repo reference - validate GitHub URL
            local total_refs=$(grep -oF "$ref" "$file" 2>/dev/null | wc -l)
            local escaped_path=$(echo "$path" | sed 's/[.]/\\./g')
            local refs_with_url=$(grep -oP "\[@[^]]*${escaped_path}[^]]*\]\(https://github\.com/[^)]+\)" "$file" 2>/dev/null | wc -l)

            if [ "$total_refs" -gt "$refs_with_url" ]; then
                echo "    ❌ Cross-repo reference $ref missing GitHub URL ($refs_with_url/$total_refs instances have URL)"
                echo "       Expected: [$ref](https://github.com/budget-analyzer/$first_segment/...)"
                return 1
            fi
            return 0
        fi
    done
    return 0
}

print_info "Validating markdown files across all repositories..."
echo ""

TOTAL_ERRORS=0
TOTAL_WARNINGS=0

for REPO in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$REPO"

    # Check if repository exists
    if [ ! -d "$REPO_PATH" ]; then
        print_warning "Repository not found: $REPO_PATH (skipping)"
        continue
    fi

    echo ""
    print_info "=== Validating $REPO ==="

    cd "$REPO_PATH"

    ERRORS=0
    WARNINGS=0

    # Find all .md files
    MD_FILES=$(find . -name "*.md" -not -path "*/node_modules/*" -not -path "*/target/*" -not -path "*/bin/*" -not -path "*/build/*" 2>/dev/null || true)

    if [ -z "$MD_FILES" ]; then
        print_warning "No markdown files found in $REPO"
        continue
    fi

    for file in $MD_FILES; do
        echo ""
        echo "  Checking: $file"

        # Skip if file doesn't exist (shouldn't happen, but defensive)
        if [ ! -f "$file" ]; then
            echo "    ⚠️  File not found (skipping)"
            continue
        fi

        # Skip docs/decisions directory (ADRs and planning docs may reference future files)
        if [[ "$file" == *"/docs/decisions/"* ]]; then
            echo "    ⏭️  Skipped (planning/decision document)"
            continue
        fi

        # Skip templates directory (templates reference files that will exist in target repos)
        if [[ "$file" == *"/templates/"* ]]; then
            echo "    ⏭️  Skipped (template file)"
            continue
        fi

        # Extract @references (e.g., @docs/some-file.md, @nginx/nginx.dev.conf)
        # Only matches file/directory paths: must contain a slash AND start with lowercase letter
        # This filters out Java annotations (@Service, @GetMapping), generic words (@references), etc.
        # Also excludes references inside code blocks (```...```)

        # First, remove code blocks from consideration
        CONTENT_NO_CODEBLOCKS=$(awk '
            /^```/ { in_block = !in_block; next }
            !in_block { print }
        ' "$file")

        REFS=$(echo "$CONTENT_NO_CODEBLOCKS" | grep -oE '@[a-z][a-zA-Z0-9_-]*/[a-zA-Z0-9/_.-]+' 2>/dev/null || true)

        if [ -n "$REFS" ]; then
            # Deduplicate references to avoid checking the same reference multiple times
            UNIQUE_REFS=$(echo "$REFS" | sort -u)
            echo "    Found $(echo "$UNIQUE_REFS" | wc -l) unique @references to validate..."

            for ref in $UNIQUE_REFS; do
                # Remove @ prefix
                path="${ref:1}"

                # Skip if it looks like an email
                if [[ "$path" == *"@"* ]]; then
                    continue
                fi

                # Skip obvious placeholder patterns used in example documentation
                if [[ "$path" == "path/to/file" ]]; then
                    echo "    ⏭️  Skipped (placeholder): $ref"
                    continue
                fi

                # Check if reference appears in backticks or example context
                if grep -q "\`@${path}\`" "$file" 2>/dev/null || \
                   grep -q "Use @${path}" "$file" 2>/dev/null || \
                   grep -q "Example.*@${path}" "$file" 2>/dev/null; then
                    echo "    ⏭️  Skipped (placeholder/example): $ref"
                    continue
                fi

                # Validate cross-repo references have GitHub URLs
                if ! validate_cross_repo_url "$ref" "$path" "$file"; then
                    ERRORS=$((ERRORS + 1))
                    continue
                fi

                # Get directory of the CLAUDE.md file
                dir=$(dirname "$file")

                # Try different path resolutions:
                # 1. Relative to CLAUDE.md location
                # 2. Relative to repository root (current directory)
                # 3. Relative to parent directory (for cross-repo references like @service-common/...)
                full_path="$dir/$path"
                root_path="./$path"
                parent_path="../$path"

                if [ -e "$full_path" ]; then
                    echo "    ✅ Valid reference: $ref → $full_path"
                elif [ -e "$root_path" ]; then
                    echo "    ✅ Valid reference: $ref → $root_path"
                elif [ -e "$parent_path" ]; then
                    echo "    ✅ Valid reference: $ref → $parent_path (cross-repo)"
                else
                    echo "    ❌ Broken reference: $ref"
                    echo "       Tried: $full_path"
                    echo "       Tried: $root_path"
                    echo "       Tried: $parent_path"
                    ERRORS=$((ERRORS + 1))
                fi
            done
        else
            echo "    ℹ️  No @references found"
        fi

        # Check for discovery commands in code blocks
        # Extract bash code blocks and check if they look runnable
        echo "    Checking discovery commands..."

        # Simple check: look for common command patterns that should exist
        if grep -q "docker compose" "$file"; then
            if ! command -v docker &> /dev/null; then
                echo "    ⚠️  Warning: References docker compose but docker command not available"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi

        if grep -q "mvnw" "$file"; then
            # Check if we're in a context where mvnw should exist
            if [ ! -f "./mvnw" ] && [ ! -f "../mvnw" ]; then
                echo "    ℹ️  Note: References ./mvnw (may be in service repo context)"
            fi
        fi

        # Check file size (warn if CLAUDE.md is too large)
        # This check only applies to CLAUDE.md and CLAUDE.local.md files
        filename=$(basename "$file")
        if [[ "$filename" == "CLAUDE.md" ]] || [[ "$filename" == "CLAUDE.local.md" ]]; then
            lines=$(wc -l < "$file")
            if [ "$lines" -gt 200 ]; then
                echo "    ⚠️  Warning: File has $lines lines (recommend < 200 for pattern-based docs)"
                WARNINGS=$((WARNINGS + 1))
            else
                echo "    ✅ File size OK: $lines lines"
            fi
        fi

    done

    # Repository summary
    TOTAL_ERRORS=$((TOTAL_ERRORS + ERRORS))
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + WARNINGS))

    echo ""
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        print_success "✓ $REPO: All markdown files valid (no errors, no warnings)"
    elif [ $ERRORS -eq 0 ]; then
        print_warning "⚠ $REPO: Validation passed with $WARNINGS warning(s)"
    else
        print_error "✗ $REPO: Validation failed with $ERRORS error(s) and $WARNINGS warning(s)"
    fi

done

echo ""
print_info "=== Overall Summary ==="
if [ $TOTAL_ERRORS -eq 0 ] && [ $TOTAL_WARNINGS -eq 0 ]; then
    print_success "All markdown files valid across all repositories!"
    echo "   Errors: 0"
    echo "   Warnings: 0"
    exit 0
elif [ $TOTAL_ERRORS -eq 0 ]; then
    print_warning "Validation passed with warnings"
    echo "   Errors: 0"
    echo "   Warnings: $TOTAL_WARNINGS"
    exit 0
else
    print_error "Validation failed"
    echo "   Errors: $TOTAL_ERRORS"
    echo "   Warnings: $TOTAL_WARNINGS"
    exit 1
fi
