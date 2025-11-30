#!/usr/bin/env bash
# scripts/doc-coverage-report.sh
# Reports on documentation coverage across the Budget Analyzer project

# Change to repository root (parent of scripts directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Documentation Coverage Report ==="
echo "Generated: $(date)"
echo "Working directory: $REPO_ROOT"
echo ""

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# Track overall status
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Helper function
check_item() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ "$1" -eq 0 ]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        echo -e "  ${GREEN}✅${NC} $2"
    else
        echo -e "  ${RED}❌${NC} $2"
    fi
}

note_item() {
    echo -e "  ${YELLOW}ℹ️${NC}  $1"
}

# 1. Check CLAUDE.md files
echo "## CLAUDE.md Files"
echo ""

# Orchestration repo
if [ -f "./CLAUDE.md" ]; then
    lines=$(wc -l < "./CLAUDE.md")
    if [ "$lines" -lt 200 ]; then
        check_item 0 "orchestration/CLAUDE.md ($lines lines) - Good size ✓"
    else
        check_item 1 "orchestration/CLAUDE.md ($lines lines) - Too large (recommend < 200)"
    fi
else
    check_item 1 "orchestration/CLAUDE.md missing"
fi

# Check for service repositories (if they exist)
SERVICE_REPOS=("service-common" "transaction-service" "currency-service" "budget-analyzer-web")

for repo in "${SERVICE_REPOS[@]}"; do
    repo_path="../$repo"
    if [ -d "$repo_path" ]; then
        if [ -f "$repo_path/CLAUDE.md" ]; then
            lines=$(wc -l < "$repo_path/CLAUDE.md" 2>/dev/null || echo "0")
            check_item 0 "$repo/CLAUDE.md ($lines lines)"
        else
            check_item 1 "$repo/CLAUDE.md missing"
        fi
    else
        note_item "$repo not found (may not be cloned)"
    fi
done

echo ""

# 2. Check documentation structure
echo "## Documentation Structure"
echo ""

# Orchestration docs
if [ -d "./docs" ]; then
    check_item 0 "orchestration/docs/ directory exists"

    # Check subdirectories
    [ -d "./docs/architecture" ] && check_item 0 "docs/architecture/ exists" || check_item 1 "docs/architecture/ missing"
    [ -d "./docs/decisions" ] && check_item 0 "docs/decisions/ exists" || check_item 1 "docs/decisions/ missing"
    [ -d "./docs/development" ] && check_item 0 "docs/development/ exists" || check_item 1 "docs/development/ missing (optional)"
else
    check_item 1 "orchestration/docs/ directory missing"
fi

echo ""

# 3. Check Architecture Decision Records
echo "## Architecture Decision Records (ADRs)"
echo ""

if [ -d "./docs/decisions" ]; then
    # Count ADRs (excluding template)
    adr_count=$(find ./docs/decisions -name "[0-9][0-9][0-9]-*.md" 2>/dev/null | wc -l)
    if [ "$adr_count" -gt 0 ]; then
        check_item 0 "$adr_count ADR(s) documented"

        # List them
        find ./docs/decisions -name "[0-9][0-9][0-9]-*.md" 2>/dev/null | sort | while read -r adr; do
            basename "$adr" | sed 's/^/     • /'
        done
    else
        check_item 1 "No ADRs found"
    fi

    # Check for template
    [ -f "./docs/decisions/template.md" ] && check_item 0 "ADR template exists" || check_item 1 "ADR template missing"
else
    check_item 1 "docs/decisions/ directory missing"
fi

echo ""

# 4. Check NGINX configuration
echo "## NGINX Gateway Configuration"
echo ""

if [ -f "./nginx/nginx.dev.conf" ]; then
    check_item 0 "nginx/nginx.dev.conf exists"

    # Count API routes
    route_count=$(grep -c "location /api" ./nginx/nginx.dev.conf 2>/dev/null || echo "0")
    note_item "$route_count API route(s) configured"
else
    check_item 1 "nginx/nginx.dev.conf missing"
fi

if [ -f "./nginx/README.md" ]; then
    check_item 0 "nginx/README.md exists"
else
    check_item 1 "nginx/README.md missing"
fi

echo ""

# 5. Check Docker Compose
echo "## Docker Compose Configuration"
echo ""

if [ -f "./docker-compose.yml" ]; then
    check_item 0 "docker-compose.yml exists"

    # Count services using docker compose (v2) or docker-compose (v1 fallback)
    if command -v docker &> /dev/null; then
        service_count=$(docker compose config --services 2>/dev/null | wc -l || echo "?")
        note_item "$service_count service(s) defined"
    elif command -v docker-compose &> /dev/null; then
        service_count=$(docker-compose config --services 2>/dev/null | wc -l || echo "?")
        note_item "$service_count service(s) defined"
    fi
else
    check_item 1 "docker-compose.yml missing"
fi

echo ""

# 6. Check service-common docs (if available)
echo "## Service-Common Documentation"
echo ""

if [ -d "../service-common" ]; then
    service_common_docs="../service-common/docs"

    if [ -d "$service_common_docs" ]; then
        check_item 0 "service-common/docs/ exists"

        doc_count=$(find "$service_common_docs" -name "*.md" 2>/dev/null | wc -l)
        note_item "$doc_count documentation file(s)"
    else
        check_item 1 "service-common/docs/ missing"
    fi
else
    note_item "service-common not found (may not be cloned)"
fi

echo ""

# 7. Check service API documentation (live endpoints, not static files)
echo "## Service API Documentation"
echo ""

note_item "Services generate OpenAPI specs at runtime via springdoc-openapi"
note_item "Access live specs at /v3/api-docs when services are running"
note_item "Unified spec available at https://api.budgetanalyzer.localhost/api/docs/"

echo ""

# 8. Summary
echo "==================================="
echo "## Summary"
echo ""
echo "Documentation coverage: $PASSED_CHECKS/$TOTAL_CHECKS checks passed"

percentage=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

if [ "$percentage" -ge 90 ]; then
    echo -e "${GREEN}Status: Excellent ✓${NC}"
elif [ "$percentage" -ge 70 ]; then
    echo -e "${YELLOW}Status: Good${NC}"
elif [ "$percentage" -ge 50 ]; then
    echo -e "${YELLOW}Status: Fair - Improvement needed${NC}"
else
    echo -e "${RED}Status: Poor - Significant gaps${NC}"
fi

echo ""
echo "==================================="
echo ""
echo "Run './scripts/validate-claude-context.sh' to check for broken references"
echo ""
