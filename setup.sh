#!/bin/bash

# setup.sh - One-command setup for Budget Analyzer development environment
#
# This script sets up everything you need to run Budget Analyzer locally.
# Run it once after cloning the orchestration repository.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./scripts/lib/pinned-tool-versions.sh
. "$SCRIPT_DIR/scripts/lib/pinned-tool-versions.sh"

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

SUPPORTED_HELM_MINIMUM="3.20.0"
SUPPORTED_HELM_MAXIMUM="4.0.0"
TESTED_HELM_VERSION="$PHASE7_HELM_VERSION"

normalize_semver() {
    printf '%s\n' "$1" | sed -nE 's/.*v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

version_ge() {
    [ "$1" = "$2" ] || [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

version_lt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

install_supported_helm() {
    print_step "Installing Helm ${TESTED_HELM_VERSION}..."
    if ! "$SCRIPT_DIR/scripts/bootstrap/install-verified-tool.sh" helm; then
        print_error "Automatic Helm installation failed"
        echo "Install Helm ${TESTED_HELM_VERSION} manually, then rerun ./setup.sh"
        exit 1
    fi
}

ensure_supported_helm() {
    local raw_version
    local parsed_version

    if command -v helm &> /dev/null; then
        raw_version="$(helm version --template '{{.Version}}' 2>/dev/null || helm version --short 2>/dev/null || true)"
        parsed_version="$(normalize_semver "$raw_version")"

        if [[ -n "$parsed_version" ]] && version_ge "$parsed_version" "$SUPPORTED_HELM_MINIMUM" && version_lt "$parsed_version" "$SUPPORTED_HELM_MAXIMUM"; then
            print_success "Helm version supported: $raw_version"
            return 0
        fi

        print_warning "Unsupported Helm version detected: ${raw_version:-unknown}"
    else
        print_warning "Helm not found"
    fi

    install_supported_helm

    raw_version="$(helm version --template '{{.Version}}' 2>/dev/null || helm version --short 2>/dev/null || true)"
    parsed_version="$(normalize_semver "$raw_version")"
    if [[ -z "$parsed_version" ]] || ! version_ge "$parsed_version" "$SUPPORTED_HELM_MINIMUM" || ! version_lt "$parsed_version" "$SUPPORTED_HELM_MAXIMUM"; then
        print_error "Helm installation did not produce a supported version"
        echo "Expected >= ${SUPPORTED_HELM_MINIMUM} and < ${SUPPORTED_HELM_MAXIMUM}; got ${raw_version:-unknown}"
        exit 1
    fi

    print_success "Helm version ready: $raw_version"
}

expected_kind_node_image() {
    awk '/^[[:space:]]*image:[[:space:]]*/ {print $2; exit}' "$SCRIPT_DIR/kind-cluster-config.yaml"
}

check_kind_cluster_node_image() {
    local expected_image
    local actual_image

    expected_image="$(expected_kind_node_image)"
    actual_image="$(docker inspect kind-control-plane --format '{{.Config.Image}}' 2>/dev/null || true)"

    if [[ -z "$expected_image" || -z "$actual_image" ]]; then
        return 0
    fi

    if [[ "$actual_image" != "$expected_image" ]]; then
        print_error "Detected existing Kind cluster with node image '$actual_image'"
        echo "  This branch expects '$expected_image' from kind-cluster-config.yaml."
        echo "  Rebuild with:"
        echo "    kind delete cluster --name kind"
        echo "    kind create cluster --config \"$SCRIPT_DIR/kind-cluster-config.yaml\""
        echo "  Then rerun ./setup.sh"
        exit 1
    fi
}

check_kind_cluster_network_model() {
    if ! kubectl cluster-info --context kind-kind >/dev/null 2>&1; then
        print_error "Cannot connect to Kind cluster context (kind-kind)"
        echo "  Try: kubectl config use-context kind-kind"
        exit 1
    fi

    check_kind_cluster_node_image

    if kubectl get daemonset kindnet -n kube-system >/dev/null 2>&1; then
        print_error "Detected existing Kind cluster created with default CNI (kindnet)"
        echo "  Platform hardening requires a cluster created with disableDefaultCNI + Calico."
        echo "  Rebuild with:"
        echo "    kind delete cluster --name kind"
        echo "    kind create cluster --config \"$SCRIPT_DIR/kind-cluster-config.yaml\""
        echo "  Then rerun ./setup.sh"
        exit 1
    fi
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
check_tool "tilt" || true
check_tool "mkcert" || true
check_tool "git" || true

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    print_error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Please install missing tools first. See docs/development/prerequisites.md"
    echo "Or run: ./scripts/bootstrap/check-tilt-prerequisites.sh for installation hints"
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

ensure_supported_helm

# =============================================================================
# Step 2: Create Kind cluster
# =============================================================================
print_step "Setting up Kind cluster..."

if kind get clusters 2>/dev/null | grep -q "^kind$"; then
    print_warning "Deleting existing Kind cluster 'kind' to guarantee a clean bootstrap"
    kind delete cluster --name kind
    print_success "Existing Kind cluster deleted"
fi

print_step "Creating Kind cluster with port mappings..."
kind create cluster --config "$SCRIPT_DIR/kind-cluster-config.yaml"
print_success "Kind cluster created"

# Set kubectl context
kubectl config use-context kind-kind &>/dev/null || true
check_kind_cluster_network_model

# =============================================================================
# Step 3: Install Calico CNI
# =============================================================================
print_step "Installing/validating Calico CNI..."
"$SCRIPT_DIR/scripts/bootstrap/install-calico.sh"
print_success "Calico and CoreDNS are ready"

# =============================================================================
# Step 4: Configure DNS
# =============================================================================
print_step "Checking DNS configuration..."

REQUIRED_HOSTS=("app.budgetanalyzer.localhost" "grafana.budgetanalyzer.localhost")
MISSING_HOSTS=()
for host in "${REQUIRED_HOSTS[@]}"; do
    if ! grep -q "$host" /etc/hosts 2>/dev/null; then
        MISSING_HOSTS+=("$host")
    fi
done

if [ ${#MISSING_HOSTS[@]} -eq 0 ]; then
    print_success "DNS entries already configured in /etc/hosts"
else
    print_warning "Missing DNS entries: ${MISSING_HOSTS[*]}"
    echo ""
    echo "  Add the following to /etc/hosts:"
    echo "  127.0.0.1  ${MISSING_HOSTS[*]}"
    echo ""
    read -p "  Add automatically? (requires sudo) [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "127.0.0.1  ${MISSING_HOSTS[*]}" | sudo tee -a /etc/hosts > /dev/null
        print_success "DNS entries added to /etc/hosts"
    else
        print_warning "Skipped. Please add DNS entries manually before running tilt up"
    fi
fi

# =============================================================================
# Step 5: Install Gateway API CRDs
# =============================================================================
print_step "Setting up Gateway API CRDs..."

# Gateway API CRDs (required before Istio ingress gateway, which Tilt installs)
if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
    print_success "Gateway API CRDs already installed"
else
    print_step "Installing Gateway API CRDs..."
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
    print_success "Gateway API CRDs installed"
fi

# Note: Istio and the ingress gateway are installed by Tilt via Helm (see Tiltfile)

# =============================================================================
# Step 6: Install Istio Helm repository
# =============================================================================
print_step "Setting up Istio Helm repository..."

if helm repo list 2>/dev/null | grep -q "^istio"; then
    helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update >/dev/null
    helm repo update istio >/dev/null
    print_success "Istio Helm repository refreshed"
else
    helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
    helm repo update istio >/dev/null
    print_success "Istio Helm repository added and refreshed"
fi

# =============================================================================
# Step 6b: Install Prometheus Community Helm repository
# =============================================================================
print_step "Setting up Prometheus Community Helm repository..."

if helm repo list 2>/dev/null | grep -q "^prometheus-community"; then
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
    helm repo update prometheus-community >/dev/null
    print_success "Prometheus Community Helm repository refreshed"
else
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
    helm repo update prometheus-community >/dev/null
    print_success "Prometheus Community Helm repository added and refreshed"
fi

# =============================================================================
# Step 7: Generate TLS certificates
# =============================================================================
print_step "Setting up TLS certificates..."

"$SCRIPT_DIR/scripts/bootstrap/setup-k8s-tls.sh"

# =============================================================================
# Step 8: Generate infrastructure TLS certificates
# =============================================================================
print_step "Setting up infrastructure TLS certificates..."

"$SCRIPT_DIR/scripts/bootstrap/setup-infra-tls.sh"

# =============================================================================
# Step 9: Create .env file
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
echo "│  0. Review local infrastructure credential defaults         │"
echo "│     - PostgreSQL now uses postgres_admin plus distinct      │"
echo "│       service-user passwords from .env                      │"
echo "│     - RabbitMQ and Redis now use fixed local service        │"
echo "│       identities and passwords from .env                    │"
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
