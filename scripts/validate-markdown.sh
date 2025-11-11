#!/usr/bin/env bash
# scripts/validate-markdown.sh
# Validates all markdown files for broken @references and executable discovery commands

set -e

# Change to repository root (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Validating Markdown Files ==="
echo "Working directory: $REPO_ROOT"
echo ""

ERRORS=0
WARNINGS=0

# Find all .md files
MD_FILES=$(find . -name "*.md" -not -path "*/node_modules/*" -not -path "*/target/*" -not -path "*/bin/*" -not -path "*/build/*" 2>/dev/null || true)

if [ -z "$MD_FILES" ]; then
    echo "❌ No markdown files found!"
    exit 1
fi

for file in $MD_FILES; do
    echo ""
    echo "Checking: $file"

    # Skip if file doesn't exist (shouldn't happen, but defensive)
    if [ ! -f "$file" ]; then
        echo "  ⚠️  File not found (skipping)"
        continue
    fi

    # Skip docs/decisions directory (ADRs and planning docs may reference future files)
    if [[ "$file" == *"/docs/decisions/"* ]]; then
        echo "  ⏭️  Skipped (planning/decision document)"
        continue
    fi

    # Skip templates directory (templates reference files that will exist in target repos)
    if [[ "$file" == *"/templates/"* ]]; then
        echo "  ⏭️  Skipped (template file)"
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
        echo "  Found $(echo "$REFS" | wc -l) @references to validate..."

        for ref in $REFS; do
            # Remove @ prefix
            path="${ref:1}"

            # Skip if it looks like an email
            if [[ "$path" == *"@"* ]]; then
                continue
            fi

            # Skip obvious placeholder patterns used in example documentation
            if [[ "$path" == "path/to/file" ]]; then
                echo "  ⏭️  Skipped (placeholder): $ref"
                continue
            fi

            # Check if reference appears in backticks or example context
            if grep -q "\`@${path}\`" "$file" 2>/dev/null || \
               grep -q "Use @${path}" "$file" 2>/dev/null || \
               grep -q "Example.*@${path}" "$file" 2>/dev/null; then
                echo "  ⏭️  Skipped (placeholder/example): $ref"
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
                echo "  ✅ Valid reference: $ref → $full_path"
            elif [ -e "$root_path" ]; then
                echo "  ✅ Valid reference: $ref → $root_path"
            elif [ -e "$parent_path" ]; then
                echo "  ✅ Valid reference: $ref → $parent_path (cross-repo)"
            else
                echo "  ❌ Broken reference: $ref"
                echo "     Tried: $full_path"
                echo "     Tried: $root_path"
                echo "     Tried: $parent_path"
                ERRORS=$((ERRORS + 1))
            fi
        done
    else
        echo "  ℹ️  No @references found"
    fi

    # Check for discovery commands in code blocks
    # Extract bash code blocks and check if they look runnable
    echo "  Checking discovery commands..."

    # Simple check: look for common command patterns that should exist
    if grep -q "docker compose" "$file"; then
        if ! command -v docker &> /dev/null; then
            echo "  ⚠️  Warning: References docker compose but docker command not available"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi

    if grep -q "mvnw" "$file"; then
        # Check if we're in a context where mvnw should exist
        if [ ! -f "./mvnw" ] && [ ! -f "../mvnw" ]; then
            echo "  ℹ️  Note: References ./mvnw (may be in service repo context)"
        fi
    fi

    # Check file size (warn if CLAUDE.md is too large)
    # This check only applies to CLAUDE.md and CLAUDE.local.md files
    filename=$(basename "$file")
    if [[ "$filename" == "CLAUDE.md" ]] || [[ "$filename" == "CLAUDE.local.md" ]]; then
        lines=$(wc -l < "$file")
        if [ "$lines" -gt 200 ]; then
            echo "  ⚠️  Warning: File has $lines lines (recommend < 200 for pattern-based docs)"
            WARNINGS=$((WARNINGS + 1))
        else
            echo "  ✅ File size OK: $lines lines"
        fi
    fi

done

echo ""
echo "=== Summary ==="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ All markdown files valid!"
    echo "   No errors, no warnings"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo "⚠️  Validation passed with warnings"
    echo "   Errors: $ERRORS"
    echo "   Warnings: $WARNINGS"
    exit 0
else
    echo "❌ Validation failed"
    echo "   Errors: $ERRORS"
    echo "   Warnings: $WARNINGS"
    exit 1
fi
