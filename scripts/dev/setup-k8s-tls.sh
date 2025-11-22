#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
K8S_CERTS_DIR="$ORCHESTRATION_DIR/nginx/certs/k8s"

echo "=== Budget Analyzer - Kubernetes TLS Setup ==="
echo

# Check if mkcert is installed
if ! command -v mkcert &> /dev/null; then
    echo "[ERROR] mkcert is not installed"
    echo
    echo "Install mkcert first:"
    echo "  macOS:   brew install mkcert nss"
    echo "  Linux:   sudo apt install libnss3-tools && curl -JLO https://dl.filippo.io/mkcert/latest?for=linux/amd64 && chmod +x mkcert-* && sudo mv mkcert-* /usr/local/bin/mkcert"
    echo
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "[ERROR] kubectl is not installed"
    echo
    echo "Install kubectl first:"
    echo "  sudo apt-get install -y kubectl"
    echo
    exit 1
fi

# Check if kind cluster is accessible
if ! kubectl cluster-info &>/dev/null; then
    echo "[ERROR] Cannot connect to Kubernetes cluster"
    echo
    echo "Ensure Kind cluster is running:"
    echo "  kind get clusters"
    echo "  kind create cluster --name kind"
    echo
    exit 1
fi

echo "[OK] mkcert is installed"
echo "[OK] kubectl is installed"
echo "[OK] Kubernetes cluster is accessible"

# Ensure mkcert CA is installed
echo
echo "Ensuring mkcert CA is installed..."
mkcert -install 2>/dev/null || true
echo "[OK] mkcert CA installed"

# Create certs directory
mkdir -p "$K8S_CERTS_DIR"
cd "$K8S_CERTS_DIR"

# Generate certificates for K8s domain (.local)
echo
echo "Generating wildcard certificate for *.budgetanalyzer.localhost..."

CERT_FILE="$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost.pem"
KEY_FILE="$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost-key.pem"

if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "[SKIP] Certificate already exists"
    echo "       To regenerate: rm $K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost*.pem"
else
    mkcert "*.budgetanalyzer.localhost" "budgetanalyzer.localhost"

    # mkcert adds +1 suffix when multiple domains are specified, rename to expected names
    if [ -f "$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost+1.pem" ]; then
        mv "$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost+1.pem" "$CERT_FILE"
        mv "$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost+1-key.pem" "$KEY_FILE"
    fi

    echo "[OK] Certificate generated"
fi

# Show certificate files
echo
echo "Certificate files:"
ls -lh "$K8S_CERTS_DIR"/_wildcard.budgetanalyzer.localhost*.pem 2>/dev/null || echo "  (none found)"

# Create Kubernetes TLS secret
echo
echo "Creating Kubernetes TLS secret..."

NAMESPACE="default"
SECRET_NAME="budgetanalyzer-localhost-wildcard-tls"

# Delete existing secret if present
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Deleting existing secret..."
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
fi

# Create the TLS secret
kubectl create secret tls "$SECRET_NAME" \
    --cert="$CERT_FILE" \
    --key="$KEY_FILE" \
    -n "$NAMESPACE"

echo "[OK] TLS secret '$SECRET_NAME' created in namespace '$NAMESPACE'"

# Verify the secret
echo
echo "Verifying secret..."
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}' | grep -q "kubernetes.io/tls" && \
    echo "[OK] Secret is correctly typed as kubernetes.io/tls" || \
    echo "[WARN] Secret type may be incorrect"

# Show secret details
echo
echo "Secret details:"
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE"

echo
echo "=== Setup Complete! ==="
echo
echo "The TLS secret '$SECRET_NAME' is now available for the Envoy Gateway."
echo
echo "=== Next Steps ==="
echo
echo "1. Add to /etc/hosts (if not already):"
echo "   echo '127.0.0.1  app.budgetanalyzer.localhost api.budgetanalyzer.localhost' | sudo tee -a /etc/hosts"
echo
echo "2. Run Tilt:"
echo "   tilt up"
echo
echo "3. Access application:"
echo "   https://app.budgetanalyzer.localhost (via port forward or Envoy Gateway)"
echo
