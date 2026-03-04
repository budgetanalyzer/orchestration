#!/bin/bash

# generate-unified-api-docs.sh - Generate unified OpenAPI spec for all microservices
#
# Usage: ./scripts/generate-unified-api-docs.sh
#
# This script will:
# 1. Fetch OpenAPI specs from all running microservices (live endpoints)
# 2. Merge them into a single unified OpenAPI spec
# 3. Save to docs-aggregator/openapi.yaml and openapi.json
#
# The unified spec can be used by clients to generate client libraries
#
# Note: Individual services generate their own specs at runtime via springdoc-openapi.
# This script does NOT write static files to service repos - that's the anti-pattern.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_ROOT/docs-aggregator"

print_info "Generating unified OpenAPI specification..."

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed. Please install it:"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  macOS: brew install jq"
    exit 1
fi

# Check if yq is installed and which version (optional, for YAML output)
HAS_YQ=false
YQ_VERSION=""
if command -v yq &> /dev/null; then
    # Check if it's the Go version (mikefarah/yq) or Python version
    if yq --version 2>&1 | grep -q "mikefarah"; then
        HAS_YQ=true
        YQ_VERSION="go"
    elif yq --version 2>&1 | grep -q "version"; then
        HAS_YQ=true
        YQ_VERSION="python"
    fi
fi

# Fetch JSON for merging (use gateway endpoints)
TRANSACTION_SERVICE="https://api.budgetanalyzer.localhost/api/transaction-service/v3/api-docs"
CURRENCY_SERVICE="https://api.budgetanalyzer.localhost/api/currency-service/v3/api-docs"
SESSION_GATEWAY="https://app.budgetanalyzer.localhost/v3/api-docs"
print_info "Fetching specs for merging..."

if ! BUDGET_SPEC=$(curl -sfk --connect-timeout 5 --max-time 15 "$TRANSACTION_SERVICE" 2>/dev/null); then
    print_error "Failed to fetch Budget Analyzer API spec from $TRANSACTION_SERVICE"
    print_error "Make sure the service is running and accessible"
    exit 1
fi
print_success "✓ Fetched Budget Analyzer API spec"

if ! CURRENCY_SPEC=$(curl -sfk --connect-timeout 5 --max-time 15 "$CURRENCY_SERVICE" 2>/dev/null); then
    print_error "Failed to fetch Currency Service spec from $CURRENCY_SERVICE"
    print_error "Make sure the service is running and accessible"
    exit 1
fi
print_success "✓ Fetched Currency Service spec"

if ! SESSION_SPEC=$(curl -sfk --connect-timeout 5 --max-time 15 "$SESSION_GATEWAY" 2>/dev/null); then
    print_error "Failed to fetch Session Gateway spec from $SESSION_GATEWAY"
    print_error "Make sure the service is running and accessible"
    exit 1
fi
print_success "✓ Fetched Session Gateway spec"

print_info "Merging OpenAPI specifications..."

# Create unified spec using jq
# Session-gateway paths need a server override since they're served from app.budgetanalyzer.localhost
# (the BFF entry point), not api.budgetanalyzer.localhost like the other services.
UNIFIED_SPEC=$(jq -n \
    --argjson budget "$BUDGET_SPEC" \
    --argjson currency "$CURRENCY_SPEC" \
    --argjson session "$SESSION_SPEC" '

# Add per-path server override to all session-gateway paths
def with_session_servers:
    to_entries | map(
        .value += {"servers": [
            {"url": "https://app.budgetanalyzer.localhost", "description": "Local environment (BFF)"},
            {"url": "https://app.budgetanalyzer.org", "description": "Production environment (BFF)"}
        ]}
    ) | from_entries;

{
    "openapi": "3.1.0",
    "info": {
        "title": "Budget Analyzer - Unified API",
        "version": "1.0",
        "description": "Unified API documentation for all Budget Analyzer microservices. This specification combines the Budget Analyzer API, Currency Service, and Session Gateway into a single document for client code generation. Note: Session Gateway endpoints (User) are served from the BFF origin (app.*), not the API gateway.",
        "contact": {
            "name": "Bleu Rubin",
            "email": "contact@budgetanalyzer.org"
        },
        "license": {
            "name": "MIT",
            "url": "https://opensource.org/licenses/MIT"
        }
    },
    "servers": [
        {
            "url": "https://api.budgetanalyzer.localhost/api",
            "description": "Local environment (via gateway)"
        },
        {
            "url": "https://api.budgetanalyzer.org",
            "description": "Production environment"
        }
    ],
    "tags": (
        ($budget.tags // [] | map(. + {"x-service": "transaction-service"})) +
        ($currency.tags // [] | map(. + {"x-service": "currency-service"})) +
        ($session.tags // [] | map(. + {"x-service": "session-gateway"}))
    ),
    "paths": (
        ($budget.paths // {}) + ($currency.paths // {}) + (($session.paths // {}) | with_session_servers)
    ),
    "components": {
        "schemas": (
            ($budget.components.schemas // {}) + ($currency.components.schemas // {}) + ($session.components.schemas // {})
        )
    }
}
')

# Save JSON output
OUTPUT_JSON="$OUTPUT_DIR/openapi.json"
echo "$UNIFIED_SPEC" | jq '.' > "$OUTPUT_JSON"
print_success "✓ Generated unified OpenAPI spec (JSON): $OUTPUT_JSON"

# Save YAML output if yq is available
OUTPUT_YAML="$OUTPUT_DIR/openapi.yaml"
if [ "$HAS_YQ" = true ]; then
    if [ "$YQ_VERSION" = "go" ]; then
        # mikefarah/yq (Go version)
        echo "$UNIFIED_SPEC" | yq -P '.' > "$OUTPUT_YAML"
    elif [ "$YQ_VERSION" = "python" ]; then
        # Python yq version
        echo "$UNIFIED_SPEC" | yq -y '.' > "$OUTPUT_YAML"
    fi
    print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
else
    # Fallback: use Python if available
    if command -v python3 &> /dev/null; then
        if echo "$UNIFIED_SPEC" | python3 -c "import sys, json, yaml; yaml.dump(json.load(sys.stdin), sys.stdout, default_flow_style=False, sort_keys=False)" > "$OUTPUT_YAML" 2>/dev/null; then
            print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
        else
            print_warning "yq not installed and Python yaml module not available - skipping YAML output"
            print_info "To generate YAML output, install yq or Python PyYAML: pip install pyyaml"
        fi
    else
        print_warning "yq not installed - skipping YAML output"
        print_info "To generate YAML output, install yq: https://github.com/mikefarah/yq"
    fi
fi

# Copy to budget-analyzer-web for frontend consumption
WEB_DOCS_DIR="$REPO_ROOT/../budget-analyzer-web/docs"
if [ -d "$WEB_DOCS_DIR" ]; then
    cp "$OUTPUT_YAML" "$WEB_DOCS_DIR/budget-analyzer-api.yaml"
    print_success "✓ Copied to budget-analyzer-web: $WEB_DOCS_DIR/budget-analyzer-api.yaml"
else
    print_warning "budget-analyzer-web/docs directory not found - skipping copy"
fi

echo
print_success "=== Unified OpenAPI specification generated successfully ==="
echo
print_info "Usage:"
echo "  View JSON spec: cat $OUTPUT_JSON"
if [ "$HAS_YQ" = true ]; then
    echo "  View YAML spec: cat $OUTPUT_YAML"
fi
echo "  Generate client: openapi-generator-cli generate -i $OUTPUT_JSON -g <generator-name>"
echo
print_info "Available via NGINX at:"
echo "  JSON: https://api.budgetanalyzer.localhost/api/docs/openapi.json"
if [ "$HAS_YQ" = true ]; then
    echo "  YAML: https://api.budgetanalyzer.localhost/api/docs/openapi.yaml"
fi
echo
print_info "To regenerate after service updates, run this script again"
