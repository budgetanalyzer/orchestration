#!/bin/bash

# Generate RSA 2048-bit key pair for JWT signing
# Appends JWT_SIGNING_PRIVATE_KEY_PEM to .env file
#
# Usage:
#   ./scripts/dev/generate-jwt-signing-key.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}.env file not found at $ENV_FILE${NC}"
    echo "Run: cp .env.example .env"
    exit 1
fi

# Check if key already exists in .env
if grep -q "^JWT_SIGNING_PRIVATE_KEY_PEM=" "$ENV_FILE" 2>/dev/null; then
    echo -e "${YELLOW}JWT_SIGNING_PRIVATE_KEY_PEM already exists in .env — skipping${NC}"
    echo "To regenerate, remove the existing JWT_SIGNING_PRIVATE_KEY_PEM line from .env first."
    exit 0
fi

echo -e "${YELLOW}Generating RSA 2048-bit key pair for JWT signing...${NC}"

# Generate RSA private key
PRIVATE_KEY=$(openssl genrsa 2048 2>/dev/null)

if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Failed to generate RSA key${NC}"
    exit 1
fi

# Convert to single-line format for .env (replace newlines with literal \n)
PRIVATE_KEY_ONELINE=$(echo "$PRIVATE_KEY" | awk '{printf "%s\\n", $0}')

# Append to .env
echo "" >> "$ENV_FILE"
echo "# JWT signing key (auto-generated)" >> "$ENV_FILE"
echo "JWT_SIGNING_PRIVATE_KEY_PEM=$PRIVATE_KEY_ONELINE" >> "$ENV_FILE"

echo -e "${GREEN}JWT signing key generated and appended to .env${NC}"
echo ""
echo "The key will be loaded by Tilt via dotenv() and injected into the"
echo "jwt-signing-credentials Kubernetes secret."
