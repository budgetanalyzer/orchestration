#!/bin/bash
# Pre-flight check for Tilt-Kind development environment

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_DIR="$(cd "$ORCHESTRATION_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "=============================================="
echo "  Tilt-Kind Pre-flight Check"
echo "=============================================="
echo
echo "Orchestration directory: $ORCHESTRATION_DIR"
echo "Looking for service repos in: $WORKSPACE_DIR"
echo

# Function to check if command exists
check_command() {
    local cmd=$1
    local name=$2
    local install_hint=$3

    if command -v "$cmd" &> /dev/null; then
        # Different tools use different version flags
        local version
        case "$cmd" in
            kubectl|helm|tilt)
                version=$($cmd version --client --short 2>&1 | head -n1 || $cmd version 2>&1 | head -n1)
                ;;
            *)
                version=$($cmd --version 2>&1 | head -n1)
                ;;
        esac
        echo -e "${GREEN}✓${NC} $name installed: $version"
        return 0
    else
        echo -e "${RED}✗${NC} $name NOT installed"
        echo "  Install with: $install_hint"
        ((ERRORS++))
        return 1
    fi
}

# Function to check directory exists
check_repo() {
    local repo=$1
    local path="$WORKSPACE_DIR/$repo"

    if [ -d "$path" ]; then
        echo -e "${GREEN}✓${NC} $repo exists"
        return 0
    else
        echo -e "${RED}✗${NC} $repo NOT found at $path"
        echo "  Repos must be siblings to orchestration. Clone with:"
        echo "  cd $WORKSPACE_DIR && git clone https://github.com/budgetanalyzer/$repo.git"
        ((ERRORS++))
        return 1
    fi
}

# Function to check file exists
check_file() {
    local desc=$1
    local path=$2

    if [ -f "$path" ]; then
        echo -e "${GREEN}✓${NC} $desc exists"
        return 0
    else
        echo -e "${RED}✗${NC} $desc NOT found: $path"
        ((ERRORS++))
        return 1
    fi
}

echo "1. Checking required tools..."
echo "---------------------------------------------"

check_command "docker" "Docker" "sudo apt-get install -y docker.io && sudo usermod -aG docker \$USER"
check_command "kind" "KIND" "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"
check_command "kubectl" "kubectl" "curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl"
check_command "helm" "Helm" "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
check_command "tilt" "Tilt" "curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash"
check_command "mkcert" "mkcert" "sudo apt install libnss3-tools && curl -JLO 'https://dl.filippo.io/mkcert/latest?for=linux/amd64' && chmod +x mkcert-* && sudo mv mkcert-* /usr/local/bin/mkcert"

echo

echo "2. Checking Docker daemon..."
echo "---------------------------------------------"

if docker info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Docker daemon is running"
else
    echo -e "${RED}✗${NC} Docker daemon is NOT running or not accessible"
    echo "  Start Docker or add user to docker group: sudo usermod -aG docker \$USER && newgrp docker"
    ((ERRORS++))
fi

echo

echo "3. Checking service repositories..."
echo "---------------------------------------------"

REPOS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "token-validation-service"
    "budget-analyzer-web"
)

for repo in "${REPOS[@]}"; do
    check_repo "$repo"
done

echo

echo "4. Checking Dockerfiles..."
echo "---------------------------------------------"

SPRING_SERVICES=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "token-validation-service"
)

for service in "${SPRING_SERVICES[@]}"; do
    check_file "$service/Dockerfile" "$WORKSPACE_DIR/$service/Dockerfile"
done

check_file "budget-analyzer-web/Dockerfile" "$WORKSPACE_DIR/budget-analyzer-web/Dockerfile"

echo

echo "5. Checking Gradle build files..."
echo "---------------------------------------------"

for service in "${SPRING_SERVICES[@]}"; do
    check_file "$service/build.gradle.kts" "$WORKSPACE_DIR/$service/build.gradle.kts"
done

echo

echo "6. Checking Kind cluster..."
echo "---------------------------------------------"

if kind get clusters 2>/dev/null | grep -q "kind"; then
    echo -e "${GREEN}✓${NC} Kind cluster 'kind' exists"

    # Check if kubectl can connect
    if kubectl cluster-info --context kind-kind &> /dev/null; then
        echo -e "${GREEN}✓${NC} kubectl can connect to Kind cluster"
    else
        echo -e "${RED}✗${NC} kubectl cannot connect to Kind cluster"
        echo "  Try: kubectl config use-context kind-kind"
        ((ERRORS++))
    fi

    # Check port mappings for HTTPS access
    if docker port kind-control-plane 2>/dev/null | grep -q "30443/tcp -> 0.0.0.0:443"; then
        echo -e "${GREEN}✓${NC} Port 443 mapped correctly (30443 -> 443)"
    else
        echo -e "${YELLOW}!${NC} Port 443 NOT mapped correctly"
        echo "  Cluster was created without kind-cluster-config.yaml"
        echo "  Recreate with: kind delete cluster && cd $ORCHESTRATION_DIR && kind create cluster --config kind-cluster-config.yaml"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}!${NC} Kind cluster 'kind' does not exist"
    echo "  Create with: cd $ORCHESTRATION_DIR && kind create cluster --config kind-cluster-config.yaml"
    ((WARNINGS++))
fi

echo

echo "7. Checking Gateway API and Envoy Gateway..."
echo "---------------------------------------------"

# Only check if cluster exists and is accessible
if kubectl cluster-info --context kind-kind &> /dev/null; then
    # Check Gateway API CRDs
    if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
        echo -e "${GREEN}✓${NC} Gateway API CRDs installed"
    else
        echo -e "${YELLOW}!${NC} Gateway API CRDs NOT installed"
        read -p "  Install Gateway API CRDs? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "  Installing Gateway API CRDs..."
            kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
            echo -e "${GREEN}✓${NC} Gateway API CRDs installed"
        else
            echo "  Skipped. Install manually with:"
            echo "  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml"
            ((WARNINGS++))
        fi
    fi

    # Check Envoy Gateway
    if kubectl get deployment -n envoy-gateway-system envoy-gateway &> /dev/null; then
        echo -e "${GREEN}✓${NC} Envoy Gateway installed"
    else
        echo -e "${YELLOW}!${NC} Envoy Gateway NOT installed"
        read -p "  Install Envoy Gateway? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "  Installing Envoy Gateway..."
            # Use --server-side to avoid annotation size limit issues with large CRDs
            kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.2.1/install.yaml
            echo "  Waiting for Envoy Gateway to be ready..."
            kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
            echo -e "${GREEN}✓${NC} Envoy Gateway installed and ready"
        else
            echo "  Skipped. Install manually with:"
            echo "  kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.2.1/install.yaml"
            ((WARNINGS++))
        fi
    fi
else
    echo -e "${YELLOW}!${NC} Skipping Gateway API check (no cluster connection)"
fi

echo

echo "8. Checking DNS configuration (/etc/hosts)..."
echo "---------------------------------------------"

if grep -q "budgetanalyzer.localhost" /etc/hosts 2>/dev/null; then
    echo -e "${GREEN}✓${NC} budgetanalyzer.localhost entries found in /etc/hosts"
    grep "budgetanalyzer.localhost" /etc/hosts | while read line; do
        echo "  $line"
    done
else
    echo -e "${YELLOW}!${NC} budgetanalyzer.localhost NOT in /etc/hosts"
    echo "  Add with: echo '127.0.0.1  app.budgetanalyzer.localhost api.budgetanalyzer.localhost' | sudo tee -a /etc/hosts"
    ((WARNINGS++))
fi

echo

echo "9. Checking orchestration files..."
echo "---------------------------------------------"

check_file "Tiltfile" "$ORCHESTRATION_DIR/Tiltfile"
check_file "nginx/nginx.k8s.conf" "$ORCHESTRATION_DIR/nginx/nginx.k8s.conf"

if [ -d "$ORCHESTRATION_DIR/kubernetes/services" ]; then
    echo -e "${GREEN}✓${NC} kubernetes/services directory exists"
else
    echo -e "${RED}✗${NC} kubernetes/services directory NOT found"
    ((ERRORS++))
fi

echo

echo "=============================================="
echo "  Summary"
echo "=============================================="
echo

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo
    echo "You can now run: tilt up"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s), 0 errors${NC}"
    echo
    echo "Warnings are non-blocking but should be addressed."
    echo "You can try: tilt up"
else
    echo -e "${RED}$ERRORS error(s), $WARNINGS warning(s)${NC}"
    echo
    echo "Please fix the errors above before running tilt up."
fi

echo

exit $ERRORS
