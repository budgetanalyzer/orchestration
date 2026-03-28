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
    local proxy_path="/api/v1/namespaces/default/services/http:${service_name}:${port}/proxy${spec_path}"
    local service_spec
    local proxy_error
    local exec_error

    print_info "Fetching ${display_name} spec via kubectl service proxy..." >&2

    if ! service_spec="$(kubectl --request-timeout="$request_timeout" get --raw "$proxy_path" 2>&1)"; then
        proxy_error="$service_spec"
        print_warning "Service proxy fetch failed for ${display_name}; retrying inside the pod..." >&2

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
            exec_error="$service_spec"
            print_error_stderr "Failed to fetch ${display_name} spec from service ${service_name}:${port}${spec_path}"
            print_error_stderr "Service proxy error: ${proxy_error}"
            print_error_stderr "In-pod fallback error: ${exec_error}"
            print_error_stderr "Make sure the cluster is running, the service exists, and your current kubectl context points at the local environment"
            return 1
        fi
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

generate_yaml_with_node() {
    OPENAPI_JSON="$1" node - <<'EOF'
const fs = require('fs');

const input = process.env.OPENAPI_JSON || '';
const document = JSON.parse(input);

function isScalar(value) {
  return value === null || ['string', 'number', 'boolean'].includes(typeof value);
}

function formatScalar(value) {
  if (value === null) {
    return 'null';
  }

  if (typeof value === 'string') {
    return JSON.stringify(value);
  }

  return String(value);
}

function formatKey(key) {
  return /^[A-Za-z0-9_-]+$/.test(key) ? key : JSON.stringify(key);
}

function render(value, indent = 0) {
  const pad = ' '.repeat(indent);

  if (Array.isArray(value)) {
    if (value.length === 0) {
      return `${pad}[]`;
    }

    return value.map((item) => {
      if (isScalar(item)) {
        return `${pad}- ${formatScalar(item)}`;
      }

      return `${pad}-\n${render(item, indent + 2)}`;
    }).join('\n');
  }

  if (value && typeof value === 'object') {
    const entries = Object.entries(value);

    if (entries.length === 0) {
      return `${pad}{}`;
    }

    return entries.map(([key, entryValue]) => {
      if (isScalar(entryValue)) {
        return `${pad}${formatKey(key)}: ${formatScalar(entryValue)}`;
      }

      return `${pad}${formatKey(key)}:\n${render(entryValue, indent + 2)}`;
    }).join('\n');
  }

  return `${pad}${formatScalar(value)}`;
}

process.stdout.write(`${render(document)}\n`);
EOF
}

print_info "Fetching specs for merging..."

if ! BUDGET_SPEC="$(fetch_service_spec "transaction-service" "8082" "/transaction-service/v3/api-docs" "Transaction Service")"; then
    exit 1
fi
print_success "✓ Fetched Transaction Service spec"

if ! CURRENCY_SPEC="$(fetch_service_spec "currency-service" "8084" "/currency-service/v3/api-docs" "Currency Service")"; then
    exit 1
fi
print_success "✓ Fetched Currency Service spec"

if ! SESSION_SPEC="$(fetch_service_spec "session-gateway" "8081" "/v3/api-docs" "Session Gateway")"; then
    exit 1
fi
print_success "✓ Fetched Session Gateway spec"

print_info "Merging OpenAPI specifications..."

# Create unified spec using jq
# Session-gateway paths need a server override since they're served from the BFF origin (app.*)
# at the root path, not under /api like the other services.
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
TMP_JSON="$(mktemp "${OUTPUT_JSON}.tmp.XXXXXX")"
echo "$UNIFIED_SPEC" | jq '.' > "$TMP_JSON"
mv "$TMP_JSON" "$OUTPUT_JSON"
print_success "✓ Generated unified OpenAPI spec (JSON): $OUTPUT_JSON"

# Save YAML output if yq is available
OUTPUT_YAML="$OUTPUT_DIR/openapi.yaml"
YAML_GENERATED=false
TMP_YAML="$(mktemp "${OUTPUT_YAML}.tmp.XXXXXX")"
if [ "$HAS_YQ" = true ]; then
    if [ "$YQ_VERSION" = "go" ]; then
        # mikefarah/yq (Go version)
        echo "$UNIFIED_SPEC" | yq -P '.' > "$TMP_YAML"
    elif [ "$YQ_VERSION" = "python" ]; then
        # Python yq version
        echo "$UNIFIED_SPEC" | yq -y '.' > "$TMP_YAML"
    fi
    YAML_GENERATED=true
    mv "$TMP_YAML" "$OUTPUT_YAML"
    print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
else
    # Fallback: use Python if available
    if command -v python3 &> /dev/null; then
        if echo "$UNIFIED_SPEC" | python3 -c "import sys, json, yaml; yaml.dump(json.load(sys.stdin), sys.stdout, default_flow_style=False, sort_keys=False)" > "$TMP_YAML" 2>/dev/null; then
            YAML_GENERATED=true
            mv "$TMP_YAML" "$OUTPUT_YAML"
            print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
        elif command -v node &> /dev/null && generate_yaml_with_node "$UNIFIED_SPEC" > "$TMP_YAML"; then
            YAML_GENERATED=true
            mv "$TMP_YAML" "$OUTPUT_YAML"
            print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
        else
            rm -f "$TMP_YAML"
            print_warning "yq not installed and Python yaml module not available - skipping YAML output"
            print_info "To generate YAML output, install yq, Python PyYAML, or Node.js"
        fi
    elif command -v node &> /dev/null && generate_yaml_with_node "$UNIFIED_SPEC" > "$TMP_YAML"; then
        YAML_GENERATED=true
        mv "$TMP_YAML" "$OUTPUT_YAML"
        print_success "✓ Generated unified OpenAPI spec (YAML): $OUTPUT_YAML"
    else
        rm -f "$TMP_YAML"
        print_warning "yq not installed - skipping YAML output"
        print_info "To generate YAML output, install yq, Python PyYAML, or Node.js"
    fi
fi

# Copy to budget-analyzer-web for frontend consumption
WEB_DOCS_DIR="$REPO_ROOT/../budget-analyzer-web/docs"
if [ "$YAML_GENERATED" = true ] && [ -d "$WEB_DOCS_DIR" ]; then
    cp "$OUTPUT_YAML" "$WEB_DOCS_DIR/budget-analyzer-api.yaml"
    print_success "✓ Copied to budget-analyzer-web: $WEB_DOCS_DIR/budget-analyzer-api.yaml"
elif [ "$YAML_GENERATED" != true ] && [ -d "$WEB_DOCS_DIR" ]; then
    print_warning "Skipping copy to budget-analyzer-web because YAML output was not generated"
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
echo "  JSON: https://app.budgetanalyzer.localhost/api-docs/openapi.json"
if [ "$YAML_GENERATED" = true ]; then
    echo "  YAML: https://app.budgetanalyzer.localhost/api-docs/openapi.yaml"
fi
echo
print_info "To regenerate after service updates, run this script again"
