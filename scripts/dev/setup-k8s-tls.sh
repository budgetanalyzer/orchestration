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

# Check if certutil is installed (needed for browser trust stores)
if ! command -v certutil &> /dev/null; then
    echo "[WARN] certutil is not installed - browser trust stores won't be updated"
    echo "       Install with: sudo apt install libnss3-tools"
    CERTUTIL_AVAILABLE=false
else
    CERTUTIL_AVAILABLE=true
fi

echo "[OK] mkcert is installed"
echo "[OK] kubectl is installed"
echo "[OK] Kubernetes cluster is accessible"
if [ "$CERTUTIL_AVAILABLE" = true ]; then
    echo "[OK] certutil is installed"
fi

# Install mkcert CA to browser trust stores
echo
echo "Installing mkcert CA to browser trust stores..."

CA_ROOT="$(mkcert -CAROOT)"
CA_FILE="$CA_ROOT/rootCA.pem"

# Detect OS
case "$(uname -s)" in
    Linux*)  OS=linux;;
    Darwin*) OS=macos;;
    MINGW*|CYGWIN*|MSYS*) OS=windows;;
    *)       OS=unknown;;
esac

if [ "$OS" = "linux" ] && [ "$CERTUTIL_AVAILABLE" = true ]; then
    # Linux: Install to NSS trust stores (browsers)
    echo "Installing CA to browser trust stores (NSS)..."
    TRUST_STORES=nss mkcert -install

    # Handle snap-installed Chromium (uses isolated NSS database)
    SNAP_CHROMIUM_NSS="$HOME/snap/chromium/current/.pki/nssdb"
    if [ -d "$SNAP_CHROMIUM_NSS" ]; then
        if ! certutil -d sql:$SNAP_CHROMIUM_NSS -L 2>/dev/null | grep -q "mkcert"; then
            echo "Installing CA to snap Chromium..."
            certutil -d sql:$SNAP_CHROMIUM_NSS -A -t "C,," -n "mkcert" -i "$CA_FILE" && \
                echo "[OK] CA installed to snap Chromium" || \
                echo "[WARN] Failed to install CA to snap Chromium"
        else
            echo "[SKIP] CA already in snap Chromium"
        fi
    fi

    # Handle snap-installed Firefox (uses isolated profile directories)
    SNAP_FIREFOX_DIR="$HOME/snap/firefox/common/.mozilla/firefox"
    if [ -d "$SNAP_FIREFOX_DIR" ]; then
        for profile in "$SNAP_FIREFOX_DIR"/*.default* "$SNAP_FIREFOX_DIR"/*.default-release*; do
            if [ -d "$profile" ]; then
                profile_name=$(basename "$profile")
                if ! certutil -d sql:$profile -L 2>/dev/null | grep -q "mkcert"; then
                    echo "Installing CA to snap Firefox profile ($profile_name)..."
                    certutil -d sql:$profile -A -t "C,," -n "mkcert" -i "$CA_FILE" && \
                        echo "[OK] CA installed to snap Firefox" || \
                        echo "[WARN] Failed to install CA to snap Firefox"
                else
                    echo "[SKIP] CA already in snap Firefox ($profile_name)"
                fi
            fi
        done
    fi

    # Handle native Firefox profiles (non-snap)
    NATIVE_FIREFOX_DIR="$HOME/.mozilla/firefox"
    if [ -d "$NATIVE_FIREFOX_DIR" ]; then
        for profile in "$NATIVE_FIREFOX_DIR"/*.default* "$NATIVE_FIREFOX_DIR"/*.default-release*; do
            if [ -d "$profile" ]; then
                profile_name=$(basename "$profile")
                if ! certutil -d sql:$profile -L 2>/dev/null | grep -q "mkcert"; then
                    echo "Installing CA to native Firefox profile ($profile_name)..."
                    certutil -d sql:$profile -A -t "C,," -n "mkcert" -i "$CA_FILE" 2>/dev/null && \
                        echo "[OK] CA installed to native Firefox" || true
                fi
            fi
        done
    fi

else
    # macOS/Windows or no certutil: use default mkcert install
    mkcert -install
fi

echo "[OK] mkcert CA installed"
echo
echo "[NOTE] Restart your browser for certificate changes to take effect"

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
