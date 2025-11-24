#!/bin/bash

# setup.sh - One-command setup for Budget Analyzer development environment
#
# This script sets up everything you need to run Budget Analyzer locally.
# Run it once after cloning the orchestration repository.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_header "Budget Analyzer - Development Setup"

# =============================================================================
# Step 1: Check required tools
# =============================================================================
print_step "Checking required tools..."

MISSING_TOOLS=()

check_tool() {
    if ! command -v "$1" &> /dev/null; then
        MISSING_TOOLS+=("$1")
        return 1
    fi
    return 0
}

check_tool "docker" || true
check_tool "kind" || true
check_tool "kubectl" || true
check_tool "helm" || true
check_tool "tilt" || true
check_tool "mkcert" || true
check_tool "git" || true

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    print_error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Please install missing tools first. See docs/development/prerequisites.md"
    echo "Or run: ./scripts/dev/check-tilt-prerequisites.sh for installation hints"
    exit 1
fi

print_success "All required tools installed"

# Check Docker daemon
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running"
    echo "Please start Docker and try again"
    exit 1
fi

print_success "Docker daemon is running"

# =============================================================================
# Step 2: Clone service repositories
# =============================================================================
print_step "Cloning service repositories..."

"$SCRIPT_DIR/scripts/clone-repos.sh"

# =============================================================================
# Step 3: Create Kind cluster
# =============================================================================
print_step "Setting up Kind cluster..."

if kind get clusters 2>/dev/null | grep -q "^kind$"; then
    print_success "Kind cluster already exists"

    # Check port mappings
    if ! docker port kind-control-plane 2>/dev/null | grep -q "30443/tcp -> 0.0.0.0:443"; then
        print_warning "Kind cluster exists but port mappings may be incorrect"
        echo "  Consider recreating: kind delete cluster && kind create cluster --config kind-cluster-config.yaml"
    fi
else
    print_step "Creating Kind cluster with port mappings..."
    kind create cluster --config "$SCRIPT_DIR/kind-cluster-config.yaml"
    print_success "Kind cluster created"
fi

# Set kubectl context
kubectl config use-context kind-kind &>/dev/null || true

# =============================================================================
# Step 4: Configure DNS
# =============================================================================
print_step "Checking DNS configuration..."

if grep -q "budgetanalyzer.localhost" /etc/hosts 2>/dev/null; then
    print_success "DNS entries already configured in /etc/hosts"
else
    print_warning "DNS entries not found in /etc/hosts"
    echo ""
    echo "  Add the following line to /etc/hosts:"
    echo "  127.0.0.1  app.budgetanalyzer.localhost api.budgetanalyzer.localhost"
    echo ""
    read -p "  Add automatically? (requires sudo) [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "127.0.0.1  app.budgetanalyzer.localhost api.budgetanalyzer.localhost" | sudo tee -a /etc/hosts > /dev/null
        print_success "DNS entries added to /etc/hosts"
    else
        print_warning "Skipped. Please add DNS entries manually before running tilt up"
    fi
fi

# =============================================================================
# Step 5: Install Gateway API and Envoy Gateway
# =============================================================================
print_step "Setting up Gateway API and Envoy Gateway..."

# Check Gateway API CRDs
if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
    print_success "Gateway API CRDs already installed"
else
    print_step "Installing Gateway API CRDs..."
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
    print_success "Gateway API CRDs installed"
fi

# Check Envoy Gateway
if kubectl get deployment -n envoy-gateway-system envoy-gateway &> /dev/null; then
    print_success "Envoy Gateway already installed"
else
    print_step "Installing Envoy Gateway..."
    kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.2.1/install.yaml
    print_step "Waiting for Envoy Gateway to be ready..."
    kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
    print_success "Envoy Gateway installed and ready"
fi

# =============================================================================
# Step 6: Generate TLS certificates
# =============================================================================
print_step "Setting up TLS certificates..."

"$SCRIPT_DIR/scripts/dev/setup-k8s-tls.sh"

# =============================================================================
# Step 7: Create .env file
# =============================================================================
print_step "Setting up environment file..."

if [ -f "$SCRIPT_DIR/.env" ]; then
    print_success ".env file already exists"
else
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    print_success ".env file created from .env.example"
fi

# =============================================================================
# Setup Complete!
# =============================================================================
print_header "Setup Complete!"

echo -e "${GREEN}Almost ready!${NC} Just configure your external services:"
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│  Configure your .env file with:                             │"
echo "├─────────────────────────────────────────────────────────────┤"
echo "│                                                             │"
echo "│  1. Auth0 (authentication)                                  │"
echo "│     - Go to: https://manage.auth0.com                       │"
echo "│     - Create app → Regular Web Application                  │"
echo "│     - See: docs/setup/auth0-setup.md                        │"
echo "│                                                             │"
echo "│  2. FRED API (exchange rates)                               │"
echo "│     - Go to: https://fred.stlouisfed.org/docs/api/api_key.html│"
echo "│     - See: docs/setup/fred-api-setup.md                     │"
echo "│                                                             │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""
echo "Edit your credentials:"
echo -e "  ${BLUE}vim .env${NC}"
echo ""
echo "Then start the application:"
echo -e "  ${BLUE}tilt up${NC}"
echo ""
echo "Access at: https://app.budgetanalyzer.localhost"
echo ""
