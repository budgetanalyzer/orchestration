#!/bin/bash

# generate-unified-api-docs.sh - Generate unified OpenAPI spec for all microservices
#
# Usage: ./scripts/generate-unified-api-docs.sh
#
# This script will:
# 1. Fetch OpenAPI specs from running services through the Kubernetes service proxy,
#    falling back to an in-pod localhost fetch when the proxy path is unavailable
# 2. Merge them into a single unified OpenAPI spec
# 3. Save to docs-aggregator/openapi.yaml and openapi.json
#
# The unified spec can be used by clients to generate client libraries
#
# Note: Individual services generate their own specs at runtime via springdoc-openapi.
# This script does NOT write static files to service repos - that's the anti-pattern.
# It also does not depend on the browser-facing gateway docs routes.

set -Eeuo pipefail

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

print_error_stderr() {
    print_error "$1" >&2
}

handle_unexpected_error() {
    local exit_code="$1"
    local line_number="$2"

    print_error_stderr "Unified OpenAPI generation failed at line ${line_number} (exit ${exit_code})."
    exit "$exit_code"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error_stderr "$1 is required but not installed."
        exit 1
    fi
}

fetch_service_spec() {
    local service_name="$1"
    local port="$2"
    local spec_path="$3"
    local display_name="$4"
    local request_timeout="${KUBECTL_REQUEST_TIMEOUT:-15s}"
    local service_spec

    # Fetch directly from inside the pod. The Kubernetes API server proxy
    # cannot reach pods under Istio STRICT mTLS (no SPIFFE identity), so
    # kubectl exec is the reliable path.
    print_info "Fetching ${display_name} spec from pod..." >&2

    if ! service_spec="$(
        kubectl --request-timeout="$request_timeout" exec "deployment/${service_name}" -c "$service_name" -- sh -lc "
            if command -v wget >/dev/null 2>&1; then
                wget -qO- http://127.0.0.1:${port}${spec_path}
            elif command -v curl >/dev/null 2>&1; then
                curl --fail --silent --show-error http://127.0.0.1:${port}${spec_path}
            else
                echo 'Neither wget nor curl is available in the container' >&2
                exit 127
            fi
        " 2>&1
    )"; then
        print_error_stderr "Failed to fetch ${display_name} spec from service ${service_name}:${port}${spec_path}"
        print_error_stderr "Error: ${service_spec}"
        print_error_stderr "Make sure the cluster is running, the service exists, and your current kubectl context points at the local environment"
        return 1
    fi

    if ! jq -e 'type == "object" and has("openapi")' >/dev/null 2>&1 <<<"$service_spec"; then
        print_error_stderr "Fetched ${display_name} spec is not a valid OpenAPI document."
        return 1
    fi

    printf '%s' "$service_spec"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_ROOT/docs-aggregator"

trap 'handle_unexpected_error "$?" "$LINENO"' ERR

print_info "Generating unified OpenAPI specification..."

require_command jq
require_command kubectl

print_info "Fetching specs for merging..."

if ! BUDGET_SPEC="$(fetch_service_spec "transaction-service" "8082" "/transaction-service/v3/api-docs" "Transaction Service")"; then
    exit 1
fi
print_success "✓ Fetched Transaction Service spec"

if ! CURRENCY_SPEC="$(fetch_service_spec "currency-service" "8084" "/currency-service/v3/api-docs" "Currency Service")"; then
    exit 1
fi
print_success "✓ Fetched Currency Service spec"

print_info "Merging OpenAPI specifications..."

# Create unified spec using jq
UNIFIED_SPEC=$(jq -n \
    --argjson budget "$BUDGET_SPEC" \
    --argjson currency "$CURRENCY_SPEC" '
{
    "openapi": "3.1.0",
    "info": {
        "title": "Budget Analyzer - Unified API",
        "version": "1.0",
        "description": "Unified API documentation for all Budget Analyzer microservices. This specification combines the Budget Analyzer API and Currency Service into a single document for client code generation.",
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
            "url": "https://app.budgetanalyzer.localhost/api",
            "description": "Local environment (via gateway)"
        },
        {
            "url": "https://api.budgetanalyzer.org",
            "description": "Production environment"
        }
    ],
    "tags": (
        ($budget.tags // [] | map(. + {"x-service": "transaction-service"})) +
        ($currency.tags // [] | map(. + {"x-service": "currency-service"}))
    ),
    "paths": (
        ($budget.paths // {}) + ($currency.paths // {})
    ),
    "components": {
        "schemas": (
            ($budget.components.schemas // {}) + ($currency.components.schemas // {})
        )
    }
}
')

# Save JSON output
OUTPUT_JSON="$OUTPUT_DIR/openapi.json"
TMP_JSON="$(mktemp "${OUTPUT_JSON}.tmp.XXXXXX")"
echo "$UNIFIED_SPEC" | jq '.' > "$TMP_JSON"
mv "$TMP_JSON" "$OUTPUT_JSON"
print_success "✓ Generated unified OpenAPI spec (JSON): $OUTPUT_JSON"

# Save YAML output
OUTPUT_YAML="$OUTPUT_DIR/openapi.yaml"
TMP_YAML="$(mktemp "${OUTPUT_YAML}.tmp.XXXXXX")"
if command -v yq &>/dev/null; then
    if yq --version 2>&1 | grep -q "mikefarah"; then
        echo "$UNIFIED_SPEC" | yq -P '.' > "$TMP_YAML"
    else
        # Python yq (kislyuk/yq) wraps jq — uses -y for YAML output
        echo "$UNIFIED_SPEC" | yq -y '.' > "$TMP_YAML"
    fi
    mv "$TMP_YAML" "$OUTPUT_YAML"
    print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
elif command -v python3 &>/dev/null; then
    if echo "$UNIFIED_SPEC" | python3 -c "import sys, json, yaml; yaml.dump(json.load(sys.stdin), sys.stdout, default_flow_style=False, sort_keys=False)" > "$TMP_YAML" 2>/dev/null; then
        mv "$TMP_YAML" "$OUTPUT_YAML"
        print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
    else
        rm -f "$TMP_YAML"
        print_warning "Python yaml module not available — skipping YAML output"
    fi
else
    rm -f "$TMP_YAML"
    print_warning "Neither yq nor python3 found — skipping YAML output"
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
echo "  View YAML spec: cat $OUTPUT_YAML"
echo "  Generate client: openapi-generator-cli generate -i $OUTPUT_JSON -g <generator-name>"
echo
print_info "Available via NGINX at:"
echo "  JSON: https://app.budgetanalyzer.localhost/api-docs/openapi.json"
echo "  YAML: https://app.budgetanalyzer.localhost/api-docs/openapi.yaml"
echo
print_info "To regenerate after service updates, run this script again"
