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
# 4. Fetch the Session Gateway spec separately (not merged) and save alongside
# 5. Copy both specs to budget-analyzer-web/docs/api/ (only the api/ subdirectory)
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

# Convert JSON on stdin to YAML at the given output path.
# Usage: echo "$JSON" | convert_json_to_yaml "/path/to/output.yaml" "description"
# Returns 1 if no YAML converter is available.
convert_json_to_yaml() {
    local output_path="$1"
    local description="$2"
    local tmp_yaml
    tmp_yaml="$(mktemp "${output_path}.tmp.XXXXXX")"

    if command -v yq &>/dev/null; then
        if yq --version 2>&1 | grep -q "mikefarah"; then
            cat | yq -P '.' > "$tmp_yaml"
        else
            cat | yq -y '.' > "$tmp_yaml"
        fi
        mv "$tmp_yaml" "$output_path"
        print_success "✓ Generated ${description} (YAML): $output_path"
    elif command -v python3 &>/dev/null; then
        if cat | python3 -c "import sys, json, yaml; yaml.dump(json.load(sys.stdin), sys.stdout, default_flow_style=False, sort_keys=False)" > "$tmp_yaml" 2>/dev/null; then
            mv "$tmp_yaml" "$output_path"
            print_success "✓ Generated ${description} (YAML): $output_path"
        else
            rm -f "$tmp_yaml"
            print_warning "Python yaml module not available — skipping YAML output for ${description}"
            return 1
        fi
    else
        rm -f "$tmp_yaml"
        print_warning "Neither yq nor python3 found — skipping YAML output for ${description}"
        return 1
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

if ! PERMISSION_SPEC="$(fetch_service_spec "permission-service" "8086" "/permission-service/v3/api-docs" "Permission Service")"; then
    exit 1
fi
print_success "✓ Fetched Permission Service spec"

# Filter out /internal/* routes and Internal* schemas from all specs — those are service-to-service only
BUDGET_SPEC=$(echo "$BUDGET_SPEC" | jq '.paths |= with_entries(select(.key | contains("/internal") | not)) | .components.schemas |= with_entries(select(.key | startswith("Internal") | not))')
CURRENCY_SPEC=$(echo "$CURRENCY_SPEC" | jq '.paths |= with_entries(select(.key | contains("/internal") | not)) | .components.schemas |= with_entries(select(.key | startswith("Internal") | not))')
PERMISSION_SPEC=$(echo "$PERMISSION_SPEC" | jq '.paths |= with_entries(select(.key | contains("/internal") | not)) | .components.schemas |= with_entries(select(.key | startswith("Internal") | not))')

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
        "description": "Unified API documentation for all Budget Analyzer microservices. This specification combines the Transaction Service, Currency Service, and Permission Service into a single document for client code generation.\n\nAll endpoints are served under the `/api` base path.",
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
        ($budget.tags // [] | map(select(.name != "Internal")) | map(. + {"x-service": "transaction-service"})) +
        ($currency.tags // [] | map(select(.name != "Internal")) | map(. + {"x-service": "currency-service"})) +
        ($permission.tags // [] | map(select(.name != "Internal")) | map(. + {"x-service": "permission-service"}))
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
TMP_JSON="$(mktemp "${OUTPUT_JSON}.tmp.XXXXXX")"
echo "$UNIFIED_SPEC" | jq '.' > "$TMP_JSON"
mv "$TMP_JSON" "$OUTPUT_JSON"
print_success "✓ Generated unified OpenAPI spec (JSON): $OUTPUT_JSON"

# Save YAML output
OUTPUT_YAML="$OUTPUT_DIR/openapi.yaml"
echo "$UNIFIED_SPEC" | convert_json_to_yaml "$OUTPUT_YAML" "unified OpenAPI spec" || true

# --- Session Gateway spec (separate from unified spec) ---

print_info "Fetching Session Gateway spec..."

if ! SESSION_GW_SPEC="$(fetch_service_spec "session-gateway" "8081" "/v3/api-docs" "Session Gateway")"; then
    exit 1
fi
print_success "✓ Fetched Session Gateway spec"

# Filter out /internal/* routes — those are service-to-service only
SESSION_GW_SPEC=$(echo "$SESSION_GW_SPEC" | jq '.paths |= with_entries(select(.key | startswith("/internal") | not))')

# Convert to YAML via temp file (not saved to docs-aggregator — that's NGINX-served)
SESSION_GW_YAML="$(mktemp "${OUTPUT_DIR}/session-gateway-api.yaml.tmp.XXXXXX")"
if ! echo "$SESSION_GW_SPEC" | convert_json_to_yaml "$SESSION_GW_YAML" "Session Gateway spec"; then
    rm -f "$SESSION_GW_YAML"
    print_error "Failed to convert Session Gateway spec to YAML"
    exit 1
fi

# Copy to budget-analyzer-web for frontend consumption
WEB_DOCS_DIR="$REPO_ROOT/../budget-analyzer-web/docs"
if [ -d "$WEB_DOCS_DIR" ]; then
    WEB_API_DIR="$WEB_DOCS_DIR/api"
    mkdir -p "$WEB_API_DIR"
    cp "$OUTPUT_YAML" "$WEB_API_DIR/budget-analyzer-api.yaml"
    cp "$SESSION_GW_YAML" "$WEB_API_DIR/session-gateway-api.yaml"
    print_success "✓ Copied to budget-analyzer-web: $WEB_API_DIR/budget-analyzer-api.yaml"
    print_success "✓ Copied to budget-analyzer-web: $WEB_API_DIR/session-gateway-api.yaml"
else
    print_warning "budget-analyzer-web/docs directory not found - skipping copy"
fi

rm -f "$SESSION_GW_YAML"

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
