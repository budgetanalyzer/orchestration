#!/bin/bash

# test-setup-flow.sh - Test script that runs inside the container
#
# This script validates each step of setup.sh and reports pass/fail.

set -e

REPOS_DIR="/repos"
ORCHESTRATION_DIR="$REPOS_DIR/orchestration"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

pass_test() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++)) || true
}

fail_test() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++)) || true
    FAILED_TESTS+=("$1")
}

# =============================================================================
# Test 1: Verify tools are available
# =============================================================================
print_test "Checking required tools..."

TOOLS=("docker" "kind" "kubectl" "helm" "tilt" "mkcert" "git" "certutil")
TOOLS_OK=true

for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "  ✓ $tool"
    else
        echo "  ✗ $tool - NOT FOUND"
        TOOLS_OK=false
    fi
done

if [ "$TOOLS_OK" = true ]; then
    pass_test "All required tools are available"
else
    fail_test "Some required tools are missing"
fi

# =============================================================================
# Test 2: Verify Docker daemon (DinD)
# =============================================================================
print_test "Checking Docker daemon..."

if docker info &> /dev/null; then
    pass_test "Docker daemon is accessible"
else
    fail_test "Docker daemon is not accessible"
    echo "Cannot proceed without Docker. Exiting."
    exit 1
fi

# =============================================================================
# Test 3: Verify repos exist (simulating clone)
# =============================================================================
print_test "Checking repositories..."

REPOS=(
    "orchestration"
    "service-common"
    "transaction-service"
    "currency-service"
    "budget-analyzer-web"
    "session-gateway"
    "permission-service"
)

REPOS_OK=true
for repo in "${REPOS[@]}"; do
    if [ -d "$REPOS_DIR/$repo" ]; then
        echo "  ✓ $repo"
    else
        echo "  ✗ $repo - NOT FOUND"
        REPOS_OK=false
    fi
done

if [ "$REPOS_OK" = true ]; then
    pass_test "All ${#REPOS[@]} repositories are present"
else
    fail_test "Some repositories are missing"
fi

# =============================================================================
# Test 4: Create Kind cluster
# =============================================================================
print_test "Creating Kind cluster..."

cd "$ORCHESTRATION_DIR"

# Delete existing cluster if present (for clean test)
kind delete cluster 2>/dev/null || true

# Use test-specific Kind config that allows external API access (for DinD)
KIND_CONFIG="kind-cluster-config.yaml"
if [ -f "$REPOS_DIR/kind-cluster-test-config.yaml" ]; then
    KIND_CONFIG="$REPOS_DIR/kind-cluster-test-config.yaml"
fi

if kind create cluster --config "$KIND_CONFIG"; then
    pass_test "Kind cluster created successfully"
else
    fail_test "Failed to create Kind cluster"
    exit 1
fi

# Verify cluster is running
print_test "Verifying Kind cluster..."

if kind get clusters 2>/dev/null | grep -q "^kind$"; then
    pass_test "Kind cluster is running"
else
    fail_test "Kind cluster not found"
fi

# Set kubectl context
kubectl config use-context kind-kind &>/dev/null || true

# For DinD: Update kubeconfig to use the Docker endpoint host instead of the
# host-only localhost address emitted by Kind.
if [ -n "$DOCKER_HOST" ]; then
    print_test "Updating kubeconfig for DinD environment..."
    API_PORT=$(kubectl config view -o jsonpath='{.clusters[?(@.name=="kind-kind")].cluster.server}' | sed 's/.*://')
    DOCKER_ENDPOINT="${DOCKER_HOST#tcp://}"
    DOCKER_ENDPOINT_HOST="${DOCKER_ENDPOINT%%:*}"
    # Set server and skip TLS verification (cert is issued for the inner node's
    # forwarded address, not the DinD-facing host alias).
    kubectl config set-cluster kind-kind --server="https://${DOCKER_ENDPOINT_HOST}:${API_PORT}" --insecure-skip-tls-verify=true

    # Verify connectivity
    if kubectl get nodes &>/dev/null; then
        pass_test "Kubernetes API accessible via DinD"
    else
        fail_test "Cannot connect to Kubernetes API"
        exit 1
    fi
fi

# =============================================================================
# Test 5: Validate cluster networking model and Calico
# =============================================================================
print_test "Validating Kind networking model..."

if kubectl get daemonset kindnet -n kube-system &>/dev/null; then
    fail_test "Kind default CNI (kindnet) detected - cluster is incompatible with platform hardening"
else
    pass_test "Kind default CNI is disabled"
fi

print_test "Installing Calico CNI..."

if "$ORCHESTRATION_DIR/scripts/bootstrap/install-calico.sh"; then
    pass_test "Calico install script completed"
else
    fail_test "Calico install script failed"
    exit 1
fi

print_test "Verifying Calico readiness..."

CALICO_READY=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
CALICO_DESIRED=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)

if [ "$CALICO_DESIRED" -gt 0 ] && [ "$CALICO_READY" -eq "$CALICO_DESIRED" ]; then
    pass_test "Calico daemonset is ready (${CALICO_READY}/${CALICO_DESIRED})"
else
    fail_test "Calico daemonset is not ready (${CALICO_READY}/${CALICO_DESIRED})"
fi

print_test "Verifying CoreDNS readiness..."

if kubectl rollout status deployment/coredns -n kube-system --timeout=180s >/dev/null; then
    pass_test "CoreDNS is ready"
else
    fail_test "CoreDNS is not ready after Calico installation"
fi

# =============================================================================
# Test 6: Verify port mappings
# =============================================================================
print_test "Checking port mappings..."

PORT_443=$(docker port kind-control-plane 2>/dev/null | grep "30443/tcp" || true)
PORT_80=$(docker port kind-control-plane 2>/dev/null | grep "80/tcp" || true)

PORTS_OK=true
if [ -n "$PORT_443" ]; then
    echo "  ✓ Port 30443 -> 443 mapping"
else
    echo "  ✗ Port 30443 -> 443 mapping not found"
    PORTS_OK=false
fi

if [ -n "$PORT_80" ]; then
    echo "  ✓ Port 80 mapping"
else
    echo "  ✗ Port 80 mapping not found"
    PORTS_OK=false
fi

if [ "$PORTS_OK" = true ]; then
    pass_test "Port mappings are correct"
else
    fail_test "Port mappings are incorrect"
fi

# =============================================================================
# Test 7: Configure DNS (in container)
# =============================================================================
print_test "Configuring DNS in container..."

if grep -q "budgetanalyzer.localhost" /etc/hosts; then
    pass_test "DNS entries already configured"
else
    echo "127.0.0.1  app.budgetanalyzer.localhost api.budgetanalyzer.localhost grafana.budgetanalyzer.localhost" | sudo tee -a /etc/hosts > /dev/null
    if grep -q "budgetanalyzer.localhost" /etc/hosts; then
        pass_test "DNS entries added to /etc/hosts"
    else
        fail_test "Failed to add DNS entries"
    fi
fi

# =============================================================================
# Test 8: Install Gateway API CRDs
# =============================================================================
print_test "Installing Gateway API CRDs..."

if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
    pass_test "Gateway API CRDs already installed"
else
    if kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml; then
        # Verify installation
        if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
            pass_test "Gateway API CRDs installed successfully"
        else
            fail_test "Gateway API CRDs installation failed"
        fi
    else
        fail_test "Failed to apply Gateway API CRDs"
    fi
fi

# =============================================================================
# Test 9: Refresh Istio Helm repository
# =============================================================================
print_test "Refreshing Istio Helm repository..."

if helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update >/dev/null 2>&1 \
    && helm repo update istio >/dev/null \
    && helm search repo istio/base --versions | grep -q "^istio/base"; then
    pass_test "Istio Helm repository refresh is idempotent and chart metadata is available"
else
    fail_test "Istio Helm repository refresh failed"
fi

# =============================================================================
# Test 10: Install Envoy Gateway
# =============================================================================
print_test "Installing Envoy Gateway..."

if kubectl get deployment -n envoy-gateway-system envoy-gateway &> /dev/null; then
    pass_test "Envoy Gateway already installed"
else
    if kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.2.1/install.yaml; then
        echo "  Waiting for Envoy Gateway to be ready (this may take a few minutes)..."
        if kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available; then
            pass_test "Envoy Gateway installed and ready"
        else
            fail_test "Envoy Gateway failed to become ready"
        fi
    else
        fail_test "Failed to apply Envoy Gateway"
    fi
fi

# =============================================================================
# Test 11: Generate TLS certificates
# =============================================================================
print_test "Generating TLS certificates..."

K8S_CERTS_DIR="$ORCHESTRATION_DIR/nginx/certs/k8s"
mkdir -p "$K8S_CERTS_DIR"
cd "$K8S_CERTS_DIR"

CERT_FILE="$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost.pem"
KEY_FILE="$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost-key.pem"

if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    pass_test "Certificates already exist"
else
    # Initialize mkcert CA if needed
    mkcert -install 2>/dev/null || true

    if mkcert "*.budgetanalyzer.localhost" "budgetanalyzer.localhost"; then
        # Rename files (mkcert adds +1 suffix for multiple domains)
        if [ -f "$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost+1.pem" ]; then
            mv "$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost+1.pem" "$CERT_FILE"
            mv "$K8S_CERTS_DIR/_wildcard.budgetanalyzer.localhost+1-key.pem" "$KEY_FILE"
        fi

        if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
            pass_test "TLS certificates generated"
        else
            fail_test "Certificate files not found after generation"
        fi
    else
        fail_test "Failed to generate certificates"
    fi
fi

# =============================================================================
# Test 12: Create Kubernetes TLS secret
# =============================================================================
print_test "Creating Kubernetes TLS secret..."

SECRET_NAME="budgetanalyzer-localhost-wildcard-tls"
NAMESPACE="default"

# Delete existing secret if present
kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" 2>/dev/null || true

if kubectl create secret tls "$SECRET_NAME" \
    --cert="$CERT_FILE" \
    --key="$KEY_FILE" \
    -n "$NAMESPACE"; then

    # Verify secret exists and is correct type
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}' | grep -q "kubernetes.io/tls"; then
        pass_test "TLS secret created successfully"
    else
        fail_test "TLS secret has incorrect type"
    fi
else
    fail_test "Failed to create TLS secret"
fi

# =============================================================================
# Test 13: Create .env file
# =============================================================================
print_test "Creating .env file..."

cd "$ORCHESTRATION_DIR"

if [ -f ".env" ]; then
    pass_test ".env file already exists"
else
    if [ -f ".env.example" ]; then
        cp ".env.example" ".env"
        if [ -f ".env" ]; then
            pass_test ".env file created from .env.example"
        else
            fail_test "Failed to create .env file"
        fi
    else
        fail_test ".env.example not found"
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "                    TEST SUMMARY"
echo "════════════════════════════════════════════════════════════"
echo ""
echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    exit 0
fi
