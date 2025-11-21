#!/bin/bash

# generate-unified-api-docs.sh - Generate unified OpenAPI spec for all microservices
#
# Usage: ./scripts/generate-unified-api-docs.sh
#
# This script will:
# 1. Fetch OpenAPI specs from all running microservices
# 2. Merge them into a single unified OpenAPI spec
# 3. Save to docs-aggregator/openapi.yaml and openapi.json
#
# The unified spec can be used by clients to generate client libraries

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

# Service configurations: name|url|repo-path (using | as delimiter to avoid conflict with : in URLs)
SERVICES=(
    "transaction-service|http://localhost:8082/transaction-service/v3/api-docs.yaml|../transaction-service"
    "currency-service|http://localhost:8084/currency-service/v3/api-docs.yaml|../currency-service"
    "permission-service|http://localhost:8086/permission-service/v3/api-docs.yaml|../permission-service"
)

print_info "Fetching OpenAPI specs from microservices..."

# Fetch and save individual service specs
for SERVICE_CONFIG in "${SERVICES[@]}"; do
    IFS='|' read -r SERVICE_NAME SERVICE_URL REPO_PATH <<< "$SERVICE_CONFIG"

    print_info "Fetching $SERVICE_NAME..."

    # Check if repo exists
    if [ ! -d "$REPO_ROOT/$REPO_PATH" ]; then
        print_warning "Repository not found at $REPO_ROOT/$REPO_PATH - skipping individual save"
    else
        # Create docs/api directory if needed
        SERVICE_DOCS_DIR="$REPO_ROOT/$REPO_PATH/docs/api"
        mkdir -p "$SERVICE_DOCS_DIR"

        # Fetch YAML and save to service repo
        if curl -sf "$SERVICE_URL" -o "$SERVICE_DOCS_DIR/openapi.yaml" 2>/dev/null; then
            print_success "✓ Saved to $REPO_PATH/docs/api/openapi.yaml"
        else
            print_warning "Failed to save individual spec to $REPO_PATH/docs/api/openapi.yaml"
        fi
    fi
done

# Also fetch JSON for merging (use gateway endpoints)
TRANSACTION_SERVICE="https://api.budgetanalyzer.localhost/api/transaction-service/v3/api-docs"
CURRENCY_SERVICE="https://api.budgetanalyzer.localhost/api/currency-service/v3/api-docs"
PERMISSION_SERVICE="https://api.budgetanalyzer.localhost/api/permission-service/v3/api-docs"

print_info "Fetching specs for merging..."

BUDGET_SPEC=$(curl -sfk "$TRANSACTION_SERVICE" 2>/dev/null)
if [ $? -ne 0 ]; then
    print_error "Failed to fetch Budget Analyzer API spec from $TRANSACTION_SERVICE"
    print_error "Make sure the service is running and accessible"
    exit 1
fi
print_success "✓ Fetched Budget Analyzer API spec"

CURRENCY_SPEC=$(curl -sfk "$CURRENCY_SERVICE" 2>/dev/null)
if [ $? -ne 0 ]; then
    print_error "Failed to fetch Currency Service spec from $CURRENCY_SERVICE"
    print_error "Make sure the service is running and accessible"
    exit 1
fi
print_success "✓ Fetched Currency Service spec"

PERMISSION_SPEC=$(curl -sfk "$PERMISSION_SERVICE" 2>/dev/null)
if [ $? -ne 0 ]; then
    print_error "Failed to fetch Permission Service spec from $PERMISSION_SERVICE"
    print_error "Make sure the service is running and accessible"
    exit 1
fi
print_success "✓ Fetched Permission Service spec"

print_info "Merging OpenAPI specifications..."

# Create unified spec using jq
UNIFIED_SPEC=$(jq -n \
    --argjson budget "$BUDGET_SPEC" \
    --argjson currency "$CURRENCY_SPEC" \
    --argjson permission "$PERMISSION_SPEC" '
{
    "openapi": "3.1.0",
    "info": {
        "title": "Budget Analyzer - Unified API",
        "version": "1.0",
        "description": "Unified API documentation for all Budget Analyzer microservices. This specification combines the Budget Analyzer API and Currency Service into a single document for client code generation.",
        "contact": {
            "name": "Bleu Rubin",
            "email": "support@bleurubin.com"
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
            "url": "https://api.bleurubin.com",
            "description": "Production environment"
        }
    ],
    "tags": (
        ($budget.tags // [] | map(. + {"x-service": "transaction-service"})) +
        ($currency.tags // [] | map(. + {"x-service": "currency-service"})) +
        ($permission.tags // [] | map(. + {"x-service": "permission-service"}))
    ),
    "paths": (
        ($budget.paths // {}) + ($currency.paths // {}) + ($permission.paths // {})
    ),
    "components": {
        "schemas": (
            ($budget.components.schemas // {}) + ($currency.components.schemas // {}) + ($permission.components.schemas // {})
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
        echo "$UNIFIED_SPEC" | python3 -c "import sys, json, yaml; yaml.dump(json.load(sys.stdin), sys.stdout, default_flow_style=False, sort_keys=False)" > "$OUTPUT_YAML" 2>/dev/null
        if [ $? -eq 0 ]; then
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
