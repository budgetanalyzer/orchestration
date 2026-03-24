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
            kubectl)
                version=$($cmd version --client 2>&1 | head -n1 || $cmd version 2>&1 | head -n1)
                ;;
            helm)
                version=$($cmd version --template '{{.Version}}' 2>&1 | head -n1 || $cmd version 2>&1 | head -n1)
                ;;
            tilt)
                version=$($cmd version 2>&1 | head -n1)
                ;;
            openssl)
                version=$($cmd version 2>&1 | head -n1)
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

normalize_semver() {
    printf '%s\n' "$1" | sed -nE 's/.*v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

version_ge() {
    [ "$1" = "$2" ] || [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

version_lt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

check_helm_version() {
    local raw_version supported_minimum supported_maximum tested_version parsed_version

    supported_minimum="3.20.0"
    supported_maximum="4.0.0"
    tested_version="v3.20.1"
    raw_version=$(helm version --template '{{.Version}}' 2>/dev/null || helm version --short 2>/dev/null || true)
    parsed_version=$(normalize_semver "$raw_version")

    if [ -z "$parsed_version" ]; then
        echo -e "${RED}✗${NC} Could not parse Helm version"
        echo "  Raw output: $raw_version"
        echo "  Install Helm $tested_version with:"
        echo "  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=$tested_version bash"
        ((ERRORS++))
        return 1
    fi

    if version_ge "$parsed_version" "$supported_minimum" && version_lt "$parsed_version" "$supported_maximum"; then
        echo -e "${GREEN}✓${NC} Helm version supported for this repo ($raw_version; tested with $tested_version)"
        return 0
    fi

    echo -e "${RED}✗${NC} Unsupported Helm version: $raw_version"
    echo "  Supported range: >= $supported_minimum and < $supported_maximum"
    echo "  Helm 4 is not supported in this repo."
    echo "  Install Helm $tested_version with:"
    echo "  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=$tested_version bash"
    ((ERRORS++))
    return 1
}

expected_kind_node_image() {
    awk '/^[[:space:]]*image:[[:space:]]*/ {print $2; exit}' "$ORCHESTRATION_DIR/kind-cluster-config.yaml"
}

echo "1. Checking required tools..."
echo "---------------------------------------------"

check_command "docker" "Docker" "sudo apt-get install -y docker.io && sudo usermod -aG docker \$USER"
check_command "kind" "KIND" "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"
check_command "kubectl" "kubectl" "curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl"
check_command "openssl" "OpenSSL" "Install via your OS package manager (for example: sudo apt-get install -y openssl)"
if check_command "helm" "Helm" "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v3.20.1 bash"; then
    check_helm_version
fi
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
    "session-gateway"
    "permission-service"
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
    "session-gateway"
    "permission-service"
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

CLUSTER_CONNECTED=false

if kind get clusters 2>/dev/null | grep -q "kind"; then
    echo -e "${GREEN}✓${NC} Kind cluster 'kind' exists"

    EXPECTED_KIND_IMAGE="$(expected_kind_node_image)"
    ACTUAL_KIND_IMAGE="$(docker inspect kind-control-plane --format '{{.Config.Image}}' 2>/dev/null || true)"
    if [ -n "$EXPECTED_KIND_IMAGE" ] && [ -n "$ACTUAL_KIND_IMAGE" ]; then
        if [ "$ACTUAL_KIND_IMAGE" = "$EXPECTED_KIND_IMAGE" ]; then
            echo -e "${GREEN}✓${NC} Kind node image matches config (${ACTUAL_KIND_IMAGE})"
        else
            echo -e "${RED}✗${NC} Kind node image does not match config"
            echo "  Expected: $EXPECTED_KIND_IMAGE"
            echo "  Actual:   $ACTUAL_KIND_IMAGE"
            echo "  Recreate with: kind delete cluster --name kind && cd $ORCHESTRATION_DIR && kind create cluster --config kind-cluster-config.yaml"
            ((ERRORS++))
        fi
    fi

    # Check if kubectl can connect
    if kubectl cluster-info --context kind-kind &> /dev/null; then
        echo -e "${GREEN}✓${NC} kubectl can connect to Kind cluster"
        CLUSTER_CONNECTED=true
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

    # Check cluster networking model and CNI readiness
    if [ "$CLUSTER_CONNECTED" = true ]; then
        if kubectl get daemonset kindnet -n kube-system &> /dev/null; then
            echo -e "${RED}✗${NC} Cluster uses Kind default CNI (kindnet)"
            echo "  Security Phase 0 requires disableDefaultCNI + Calico."
            echo "  Rebuild with:"
            echo "  kind delete cluster --name kind"
            echo "  cd $ORCHESTRATION_DIR && kind create cluster --config kind-cluster-config.yaml"
            ((ERRORS++))
        else
            echo -e "${GREEN}✓${NC} Kind default CNI is disabled (kindnet not detected)"
        fi

        if kubectl get daemonset calico-node -n kube-system &> /dev/null; then
            CALICO_READY=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
            CALICO_DESIRED=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
            if [ "$CALICO_DESIRED" -gt 0 ] && [ "$CALICO_READY" -eq "$CALICO_DESIRED" ]; then
                echo -e "${GREEN}✓${NC} Calico daemonset ready (${CALICO_READY}/${CALICO_DESIRED})"
            else
                echo -e "${RED}✗${NC} Calico daemonset not ready (${CALICO_READY}/${CALICO_DESIRED})"
                echo "  Run: cd $ORCHESTRATION_DIR && ./scripts/dev/install-calico.sh"
                ((ERRORS++))
            fi
        else
            echo -e "${RED}✗${NC} Calico is not installed"
            echo "  Run: cd $ORCHESTRATION_DIR && ./scripts/dev/install-calico.sh"
            ((ERRORS++))
        fi
    fi
else
    echo -e "${YELLOW}!${NC} Kind cluster 'kind' does not exist"
    echo "  Create with: cd $ORCHESTRATION_DIR && kind create cluster --config kind-cluster-config.yaml"
    ((WARNINGS++))
fi

echo

echo "7. Checking Gateway API CRDs..."
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
    echo "  Add with: echo '127.0.0.1  app.budgetanalyzer.localhost' | sudo tee -a /etc/hosts"
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

echo "10. Checking Phase 4 infrastructure TLS secrets..."
echo "---------------------------------------------"

if [ "$CLUSTER_CONNECTED" = true ]; then
    PHASE4_MISSING=()
    PHASE4_INFRA_SECRETS=(infra-ca infra-tls-redis infra-tls-postgresql infra-tls-rabbitmq)

    if ! kubectl get namespace infrastructure &> /dev/null; then
        PHASE4_MISSING+=("namespace/infrastructure")
    fi

    if ! kubectl get secret infra-ca -n default &> /dev/null; then
        PHASE4_MISSING+=("secret/default/infra-ca")
    fi

    if kubectl get namespace infrastructure &> /dev/null; then
        for secret_name in "${PHASE4_INFRA_SECRETS[@]}"; do
            if ! kubectl get secret "$secret_name" -n infrastructure &> /dev/null; then
                PHASE4_MISSING+=("secret/infrastructure/$secret_name")
            fi
        done
    else
        for secret_name in "${PHASE4_INFRA_SECRETS[@]}"; do
            PHASE4_MISSING+=("secret/infrastructure/$secret_name")
        done
    fi

    if [ ${#PHASE4_MISSING[@]} -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Phase 4 infrastructure TLS secrets are present"
    else
        echo -e "${RED}✗${NC} Phase 4 infrastructure TLS prerequisites are missing"
        for missing in "${PHASE4_MISSING[@]}"; do
            echo "  Missing: $missing"
        done
        echo "  Run ./scripts/dev/setup-infra-tls.sh on your host, then rerun the prerequisite check."
        ((ERRORS++))
    fi
else
    echo -e "${YELLOW}!${NC} Skipping Phase 4 TLS secret check (cluster not connected)"
    ((WARNINGS++))
fi

echo

echo "11. Verifying runtime security prerequisites..."
echo "---------------------------------------------"

VERIFY_SCRIPT="$ORCHESTRATION_DIR/scripts/dev/verify-security-prereqs.sh"

if [ "$CLUSTER_CONNECTED" = true ]; then
    if [ ! -x "$VERIFY_SCRIPT" ]; then
        echo -e "${RED}✗${NC} Runtime verifier missing or not executable: $VERIFY_SCRIPT"
        ((ERRORS++))
    elif kubectl get deployment -n istio-system istiod &> /dev/null \
        && kubectl get deployment -n kyverno kyverno-admission-controller &> /dev/null \
        && kubectl get clusterpolicy smoke-disallow-privileged &> /dev/null; then
        if "$VERIFY_SCRIPT"; then
            echo -e "${GREEN}✓${NC} Runtime security verifier passed"
        else
            echo -e "${RED}✗${NC} Runtime security verifier failed"
            ((ERRORS++))
        fi
    else
        echo -e "${YELLOW}!${NC} Skipping runtime verifier (required platform components not fully installed yet)"
        echo "  Required: istiod deployment, kyverno-admission-controller deployment, and smoke-disallow-privileged ClusterPolicy"
        echo "  Run: tilt up"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}!${NC} Skipping runtime verifier (cluster not connected)"
    ((WARNINGS++))
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
