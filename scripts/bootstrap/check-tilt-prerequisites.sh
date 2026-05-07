#!/bin/bash
# Pre-flight check for Tilt-Kind development environment

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_DIR="$(cd "$ORCHESTRATION_DIR/.." && pwd)"
# shellcheck source=scripts/lib/pinned-tool-versions.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
. "$SCRIPT_DIR/../lib/pinned-tool-versions.sh"

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
            kind)
                version=$($cmd version 2>&1 | head -n1)
                ;;
            mkcert)
                version=$($cmd --version 2>&1 | head -n1)
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
    printf '%s\n' "$1" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

version_ge() {
    [ "$1" = "$2" ] || [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

version_lt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

check_java_version() {
    local raw_version major_version

    raw_version=$(java -version 2>&1 | head -n1 || true)
    major_version=$(printf '%s\n' "$raw_version" | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -n1)

    if [ -z "$major_version" ]; then
        echo -e "${RED}✗${NC} Could not parse Java version"
        echo "  Raw output: $raw_version"
        echo "  Install JDK 25 and ensure it is first on PATH or selected by JAVA_HOME."
        ((ERRORS++))
        return 1
    fi

    if [ "$major_version" = "25" ]; then
        echo -e "${GREEN}✓${NC} Java baseline matches local Tilt build path ($raw_version)"
        return 0
    fi

    echo -e "${RED}✗${NC} Unsupported Java version for local Tilt build path: $raw_version"
    echo "  Expected JDK 25. Gradle local resources run on the host before Docker images are built."
    echo "  Set JAVA_HOME to a JDK 25 install and ensure java on PATH resolves to that JDK."
    ((ERRORS++))
    return 1
}

check_node_version() {
    local raw_version parsed_version

    raw_version=$(node --version 2>/dev/null || true)
    parsed_version=$(normalize_semver "$raw_version")

    if [ -z "$parsed_version" ]; then
        echo -e "${RED}✗${NC} Could not parse Node.js version"
        echo "  Raw output: $raw_version"
        echo "  Install Node.js 20+ for the local frontend prod-smoke Tilt resource."
        ((ERRORS++))
        return 1
    fi

    if version_ge "$parsed_version" "20.0.0"; then
        echo -e "${GREEN}✓${NC} Node.js version supported for local Tilt frontend build ($raw_version)"
        return 0
    fi

    echo -e "${RED}✗${NC} Unsupported Node.js version: $raw_version"
    echo "  Expected Node.js 20+ for the local frontend prod-smoke Tilt resource."
    ((ERRORS++))
    return 1
}

check_npm_version() {
    local raw_version parsed_version

    raw_version=$(npm --version 2>/dev/null || true)
    parsed_version=$(normalize_semver "$raw_version")

    if [ -z "$parsed_version" ]; then
        echo -e "${RED}✗${NC} Could not parse npm version"
        echo "  Raw output: $raw_version"
        echo "  Install npm 10+ for the local frontend prod-smoke Tilt resource."
        ((ERRORS++))
        return 1
    fi

    if version_ge "$parsed_version" "10.0.0"; then
        echo -e "${GREEN}✓${NC} npm version supported for local Tilt frontend build ($raw_version)"
        return 0
    fi

    echo -e "${RED}✗${NC} Unsupported npm version: $raw_version"
    echo "  Expected npm 10+ for the local frontend prod-smoke Tilt resource."
    ((ERRORS++))
    return 1
}

tool_raw_version() {
    case "$1" in
        kubectl)
            kubectl version --client 2>/dev/null | head -n1 || true
            ;;
        tilt)
            tilt version 2>/dev/null | head -n1 || true
            ;;
        mkcert)
            mkcert --version 2>/dev/null | head -n1 || true
            ;;
        kind)
            kind version 2>/dev/null | head -n1 || true
            ;;
        *)
            "$1" --version 2>/dev/null | head -n1 || true
            ;;
    esac
}

check_pinned_tool_version() {
    local tool raw_version parsed_version expected_version expected_semver

    tool="$1"
    expected_version="$(phase7_tool_version "$tool")"
    expected_semver="$(normalize_semver "$expected_version")"
    raw_version="$(tool_raw_version "$tool")"
    parsed_version="$(normalize_semver "$raw_version")"

    if [ -z "$parsed_version" ]; then
        echo -e "${RED}✗${NC} Could not parse ${tool} version"
        echo "  Raw output: $raw_version"
        echo "  Expected: $expected_version"
        echo "  Install with: $(phase7_install_hint "$tool" "$ORCHESTRATION_DIR")"
        ((ERRORS++))
        return 1
    fi

    if [ "$parsed_version" = "$expected_semver" ]; then
        echo -e "${GREEN}✓${NC} ${tool} version matches this repo ($raw_version; expected $expected_version)"
        return 0
    fi

    echo -e "${RED}✗${NC} ${tool} version mismatch: $raw_version"
    echo "  Expected: $expected_version"
    echo "  Install with: $(phase7_install_hint "$tool" "$ORCHESTRATION_DIR")"
    ((ERRORS++))
    return 1
}

check_helm_version() {
    local raw_version supported_minimum supported_maximum tested_version parsed_version

    supported_minimum="3.20.0"
    supported_maximum="4.0.0"
    tested_version="$PHASE7_HELM_VERSION"
    raw_version=$(helm version --template '{{.Version}}' 2>/dev/null || helm version --short 2>/dev/null || true)
    parsed_version=$(normalize_semver "$raw_version")

    if [ -z "$parsed_version" ]; then
        echo -e "${RED}✗${NC} Could not parse Helm version"
        echo "  Raw output: $raw_version"
        echo "  Install Helm $tested_version with:"
        echo "  $(phase7_install_hint helm "$ORCHESTRATION_DIR")"
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
    echo "  $(phase7_install_hint helm "$ORCHESTRATION_DIR")"
    ((ERRORS++))
    return 1
}

expected_kind_node_image() {
    awk '/^[[:space:]]*image:[[:space:]]*/ {print $2; exit}' "$ORCHESTRATION_DIR/kind-cluster-config.yaml"
}

echo "1. Checking required tools..."
echo "---------------------------------------------"

check_command "docker" "Docker" "sudo apt-get install -y docker.io && sudo usermod -aG docker \$USER"
if check_command "kind" "Kind" "$(phase7_install_hint kind "$ORCHESTRATION_DIR")"; then
    check_pinned_tool_version kind
fi
if check_command "kubectl" "kubectl" "$(phase7_install_hint kubectl "$ORCHESTRATION_DIR")"; then
    check_pinned_tool_version kubectl
fi
check_command "openssl" "OpenSSL" "Install via your OS package manager (for example: sudo apt-get install -y openssl)"
if check_command "helm" "Helm" "$(phase7_install_hint helm "$ORCHESTRATION_DIR")"; then
    check_helm_version
fi
if check_command "tilt" "Tilt" "$(phase7_install_hint tilt "$ORCHESTRATION_DIR")"; then
    check_pinned_tool_version tilt
fi
if check_command "mkcert" "mkcert" "$(phase7_install_hint mkcert "$ORCHESTRATION_DIR")"; then
    check_pinned_tool_version mkcert
fi
if check_command "java" "Java" "Install JDK 25 and set JAVA_HOME/PATH to that JDK"; then
    check_java_version
fi
if check_command "node" "Node.js" "Install Node.js 20+ from your OS package manager, nvm, or Volta"; then
    check_node_version
fi
if check_command "npm" "npm" "Install npm 10+ with Node.js"; then
    check_npm_version
fi

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

if [ -d "$WORKSPACE_DIR/budget-analyzer-web" ]; then
    if [ -d "$WORKSPACE_DIR/budget-analyzer-web/node_modules" ]; then
        echo -e "${GREEN}✓${NC} budget-analyzer-web/node_modules exists for the local prod-smoke build"
    else
        echo -e "${RED}✗${NC} budget-analyzer-web/node_modules is missing"
        echo "  Tilt's budget-analyzer-web-prod-smoke-build resource runs npm on the host."
        echo "  Run: cd $WORKSPACE_DIR/budget-analyzer-web && npm install"
        ((ERRORS++))
    fi
fi

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
            echo "  Platform security requires disableDefaultCNI + Calico."
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
            CALICO_IMAGES=$(kubectl get daemonset calico-node -n kube-system -o jsonpath='{.spec.template.spec.containers[*].image}' 2>/dev/null || true)
            if [ "$CALICO_DESIRED" -gt 0 ] && [ "$CALICO_READY" -eq "$CALICO_DESIRED" ]; then
                echo -e "${GREEN}✓${NC} Calico daemonset ready (${CALICO_READY}/${CALICO_DESIRED})"
            else
                echo -e "${RED}✗${NC} Calico daemonset not ready (${CALICO_READY}/${CALICO_DESIRED})"
                echo "  Run: cd $ORCHESTRATION_DIR && ./scripts/bootstrap/install-calico.sh"
                ((ERRORS++))
            fi
            if printf '%s\n' "$CALICO_IMAGES" | grep -q "calico/node:${PHASE7_CALICO_VERSION}"; then
                echo -e "${GREEN}✓${NC} Calico version matches this repo (${PHASE7_CALICO_VERSION})"
            else
                echo -e "${RED}✗${NC} Calico version mismatch"
                echo "  Expected: ${PHASE7_CALICO_VERSION}"
                echo "  Actual images: ${CALICO_IMAGES:-unknown}"
                echo "  Reconcile with: cd $ORCHESTRATION_DIR && ./scripts/bootstrap/install-calico.sh"
                ((ERRORS++))
            fi
        else
            echo -e "${RED}✗${NC} Calico is not installed"
            echo "  Run: cd $ORCHESTRATION_DIR && ./scripts/bootstrap/install-calico.sh"
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

# Only check if the expected local Kind cluster exists and is accessible.
if [ "$CLUSTER_CONNECTED" = true ]; then
    if kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
        GATEWAY_API_VERSION=$(kubectl get crd gateways.gateway.networking.k8s.io -o go-template='{{ index .metadata.annotations "gateway.networking.k8s.io/bundle-version" }}' 2>/dev/null || true)
        if [ "$GATEWAY_API_VERSION" = "$PHASE7_GATEWAY_API_VERSION" ]; then
            echo -e "${GREEN}✓${NC} Gateway API CRDs match this repo (${PHASE7_GATEWAY_API_VERSION})"
        else
            echo -e "${RED}✗${NC} Gateway API CRD version mismatch"
            echo "  Expected: ${PHASE7_GATEWAY_API_VERSION}"
            echo "  Actual:   ${GATEWAY_API_VERSION:-unknown}"
            echo "  Reconcile with: kubectl apply -f $(phase7_gateway_api_manifest_url)"
            ((ERRORS++))
        fi
    else
        echo -e "${RED}✗${NC} Gateway API CRDs NOT installed"
        echo "  Reconcile with: kubectl apply -f $(phase7_gateway_api_manifest_url)"
        ((ERRORS++))
    fi
else
    echo -e "${YELLOW}!${NC} Skipping Gateway API check (no cluster connection)"
fi

echo

echo "8. Checking DNS configuration (/etc/hosts)..."
echo "---------------------------------------------"

if grep -q "budgetanalyzer.localhost" /etc/hosts 2>/dev/null; then
    echo -e "${GREEN}✓${NC} budgetanalyzer.localhost entries found in /etc/hosts"
    grep "budgetanalyzer.localhost" /etc/hosts | while read -r line; do
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

echo "10. Checking infrastructure TLS secrets..."
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
        echo -e "${GREEN}✓${NC} Infrastructure TLS secrets are present"
    else
        echo -e "${RED}✗${NC} Infrastructure TLS prerequisites are missing"
        for missing in "${PHASE4_MISSING[@]}"; do
            echo "  Missing: $missing"
        done
        echo "  Run ./scripts/bootstrap/setup-infra-tls.sh on your host, then rerun the prerequisite check."
        ((ERRORS++))
    fi
else
    echo -e "${YELLOW}!${NC} Skipping infrastructure TLS secret check (cluster not connected)"
    ((WARNINGS++))
fi

echo

echo "11. Verifying runtime security prerequisites..."
echo "---------------------------------------------"

VERIFY_SCRIPT="$ORCHESTRATION_DIR/scripts/smoketest/verify-security-prereqs.sh"

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
