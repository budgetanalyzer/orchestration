#!/bin/bash

# setup.sh - One-command setup for Budget Analyzer development environment
#
# This script bootstraps Budget Analyzer on a local Docker daemon.
# Run it after transferring the three approved ingress TLS files.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./scripts/lib/pinned-tool-versions.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/scripts/lib/pinned-tool-versions.sh"
# shellcheck source=./scripts/lib/local-kubernetes-target.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/scripts/lib/local-kubernetes-target.sh"

usage() {
    cat <<'EOF'
Usage: ./setup.sh

Recreate Kind on the selected local Docker Unix socket and reconcile the three
imported ingress TLS files into its Secret.

This is a destructive Kind bootstrap, not a daily start command. Optional
development-VM setup and trust guidance lives in ../workspace/docs/.
EOF
}

case "${1:-}" in
    "") ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi

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

assert_not_in_container() {
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        print_error "Run ./setup.sh from a human-operated OS shell on the machine that runs Docker and Kind, not from a container."
        echo "Setup recreates Kind and generates infrastructure TLS on the local machine."
        echo "Open a human-operated machine terminal in this repository and run:"
        echo "  ./setup.sh"
        exit 1
    fi
}

PINNED_TOOL_INSTALL_DIR=/usr/local/bin

install_pinned_tool() {
    local tool expected_version

    tool="$1"
    expected_version="$(phase7_tool_version "$tool")"
    print_step "Installing ${tool} ${expected_version}..."
    if ! "$SCRIPT_DIR/scripts/bootstrap/install-verified-tool.sh" "$tool"; then
        print_error "Automatic ${tool} installation failed"
        echo "Install ${tool} ${expected_version} manually, then rerun ./setup.sh"
        exit 1
    fi
    hash -r 2>/dev/null || true
}

ensure_pinned_tool() {
    local tool expected_version resolved raw_version

    tool="$1"
    expected_version="$(phase7_tool_version "$tool")"
    if resolved="$(command -v "$tool")"; then
        if raw_version="$(phase7_tool_raw_version_at "$tool" "$resolved")" &&
            phase7_tool_version_matches "$tool" "$raw_version"; then
            print_success "${tool} version ready: $raw_version"
            return 0
        fi

        print_warning "${tool} at ${resolved} is not the pinned version: ${raw_version:-version probe failed}"
        echo "  Expected ${tool} ${expected_version} from scripts/lib/pinned-tool-versions.sh"
    else
        print_warning "${tool} not found"
    fi

    install_pinned_tool "$tool"

    if ! raw_version="$(phase7_verify_effective_tool_version "$tool" "$PINNED_TOOL_INSTALL_DIR/$tool")"; then
        print_error "${tool} selected by PATH is not the pinned ${expected_version} after installation"
        echo "Fix PATH as reported above, then rerun ./setup.sh"
        exit 1
    fi

    print_success "${tool} version ready: $raw_version"
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

print_header "Budget Analyzer - Local Kind Bootstrap"
assert_not_in_container

print_step "Validating imported ingress TLS before recreating Kind..."
"$SCRIPT_DIR/scripts/bootstrap/install-imported-ingress-tls.sh" --validate-only
print_success "Imported ingress TLS files verified"

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
check_tool "git" || true

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    print_error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo ""
    echo "Install the missing local prerequisite(s), then rerun ./setup.sh."
    exit 1
fi

print_success "All required tools installed"

# Check the Kind provider and the transport that Docker CLI and Kind will
# actually use before any cluster deletion or creation.
if ! assert_local_docker_endpoint; then
    print_error "Kind must use the Docker provider on a reachable local Unix-socket daemon"
    exit 1
fi

print_success "Kind provider is Docker on a reachable local Unix-socket daemon"

ensure_pinned_tool "kubectl"
ensure_pinned_tool "kind"
ensure_pinned_tool "helm"
ensure_pinned_tool "tilt"

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

REQUIRED_HOSTS=("app.budgetanalyzer.localhost")
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
print_step "Applying Gateway API CRDs (${PHASE7_GATEWAY_API_VERSION})..."
kubectl apply -f "$(phase7_gateway_api_manifest_url)"
print_success "Gateway API CRDs reconciled (${PHASE7_GATEWAY_API_VERSION})"

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
# Step 6c: Install Kiali Helm repository
# =============================================================================
print_step "Setting up Kiali Helm repository..."

if helm repo list 2>/dev/null | grep -q "^kiali"; then
    helm repo add kiali https://kiali.org/helm-charts --force-update >/dev/null
    helm repo update kiali >/dev/null
    print_success "Kiali Helm repository refreshed"
else
    helm repo add kiali https://kiali.org/helm-charts >/dev/null
    helm repo update kiali >/dev/null
    print_success "Kiali Helm repository added and refreshed"
fi

# =============================================================================
# Step 7: Reconcile imported browser-facing TLS
# =============================================================================
print_step "Validating imported ingress TLS and installing its Kubernetes Secret..."
"$SCRIPT_DIR/scripts/bootstrap/install-imported-ingress-tls.sh"

# =============================================================================
# Step 8: Generate infrastructure TLS certificates
# =============================================================================
print_step "Setting up infrastructure TLS certificates..."

"$SCRIPT_DIR/scripts/bootstrap/setup-infra-tls.sh"
"$SCRIPT_DIR/scripts/bootstrap/check-infra-tls-secrets.sh"

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

print_warning "Bootstrap recreated Kind. Do not use ./setup.sh as a daily start command."

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
