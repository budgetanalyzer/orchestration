#!/bin/bash
set -e

echo "=== Budget Analyzer - Local HTTPS Setup ==="
echo

# Check if mkcert is installed
if ! command -v mkcert &> /dev/null; then
    echo "❌ mkcert is not installed"
    echo
    echo "Install mkcert:"
    echo "  macOS:   brew install mkcert nss"
    echo "  Linux:   See https://github.com/FiloSottile/mkcert#installation"
    echo "  Windows: choco install mkcert"
    echo
    exit 1
fi

echo "✅ mkcert is installed"

# Check if local CA is installed
if ! mkcert -CAROOT &> /dev/null; then
    echo "Installing local CA..."
    mkcert -install
    echo "✅ Local CA installed"
else
    echo "✅ Local CA already installed"
fi

# Generate certificates
echo
echo "Generating wildcard certificate for *.budgetanalyzer.localhost..."

cd "$(dirname "$0")/../nginx/certs" || exit 1

# Check if certificates already exist
if [ -f "_wildcard.budgetanalyzer.localhost.pem" ]; then
    echo "⚠️  Certificate already exists. Remove it first to regenerate."
    echo "   To regenerate: rm nginx/certs/_wildcard.budgetanalyzer.localhost*.pem"
else
    mkcert "*.budgetanalyzer.localhost"
    echo "✅ Certificate generated:"
    ls -lh _wildcard.budgetanalyzer.localhost*.pem
fi

# Convert to PKCS12 for Session Gateway
echo
echo "Converting certificate to PKCS12 format for Spring Boot..."

PKCS12_PATH="../../session-gateway/src/main/resources/certs"
mkdir -p "$PKCS12_PATH"

# Check if PKCS12 already exists
if [ -f "$PKCS12_PATH/budgetanalyzer.p12" ]; then
    echo "⚠️  PKCS12 keystore already exists. Remove it first to regenerate."
    echo "   To regenerate: rm session-gateway/src/main/resources/certs/budgetanalyzer.p12"
else
    openssl pkcs12 -export \
      -in _wildcard.budgetanalyzer.localhost.pem \
      -inkey _wildcard.budgetanalyzer.localhost-key.pem \
      -out "$PKCS12_PATH/budgetanalyzer.p12" \
      -name budgetanalyzer \
      -passout pass:changeit

    echo "✅ PKCS12 keystore created"
fi

echo

echo "=== Setup Complete! ==="
echo
echo "Next steps:"
echo "1. Restart Docker services: docker compose restart"
echo "2. Access application: https://app.budgetanalyzer.localhost"
echo "3. API Gateway: https://api.budgetanalyzer.localhost"
echo
echo "Note: Your browser will trust these certificates automatically!"
