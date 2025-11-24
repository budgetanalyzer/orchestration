#!/bin/bash

# run-test.sh - Entry point for setup.sh flow testing
#
# This script:
# 1. Builds the test environment image
# 2. Copies repos to a temp directory (simulates clone)
# 3. Starts docker-compose with DinD
# 4. Runs the test and captures results
# 5. Cleans up

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PARENT_DIR="$(dirname "$ORCHESTRATION_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

cleanup() {
    print_step "Cleaning up..."
    cd "$SCRIPT_DIR"
    docker compose -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || true
    rm -rf "$TEMP_REPOS_DIR" 2>/dev/null || true
    print_success "Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup EXIT

print_header "Budget Analyzer - Setup Flow Testing"

# =============================================================================
# Step 1: Validate repos exist
# =============================================================================
print_step "Checking for required repositories..."

REPOS=(
    "orchestration"
    "service-common"
    "transaction-service"
    "currency-service"
    "budget-analyzer-web"
    "session-gateway"
    "token-validation-service"
    "permission-service"
)

MISSING_REPOS=()
for repo in "${REPOS[@]}"; do
    if [ ! -d "$PARENT_DIR/$repo" ]; then
        MISSING_REPOS+=("$repo")
    fi
done

if [ ${#MISSING_REPOS[@]} -gt 0 ]; then
    print_error "Missing repositories: ${MISSING_REPOS[*]}"
    echo ""
    echo "Please ensure all repos are cloned as siblings to orchestration."
    echo "Run: ./scripts/clone-repos.sh"
    exit 1
fi

print_success "All ${#REPOS[@]} repositories found"

# =============================================================================
# Step 2: Create temp directory with repos
# =============================================================================
print_step "Creating temporary repository directory..."

TEMP_REPOS_DIR=$(mktemp -d)
print_step "Using temp directory: $TEMP_REPOS_DIR"

for repo in "${REPOS[@]}"; do
    print_step "Copying $repo..."
    # Use rsync to exclude .git and other large directories for speed
    if command -v rsync &> /dev/null; then
        rsync -a --exclude='.git' --exclude='node_modules' --exclude='target' --exclude='build' \
            "$PARENT_DIR/$repo/" "$TEMP_REPOS_DIR/$repo/"
    else
        cp -r "$PARENT_DIR/$repo" "$TEMP_REPOS_DIR/"
    fi
done

print_success "All repositories copied to temp directory"

# =============================================================================
# Step 3: Build test environment image
# =============================================================================
print_step "Building test environment image..."

cd "$SCRIPT_DIR"
docker compose -f docker-compose.test.yml build --no-cache

print_success "Test image built"

# =============================================================================
# Step 4: Start DinD and test runner
# =============================================================================
print_step "Starting Docker-in-Docker environment..."

docker compose -f docker-compose.test.yml up -d

# Wait for DinD to be healthy
print_step "Waiting for Docker daemon to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker compose -f docker-compose.test.yml exec -T test-runner docker info &>/dev/null; then
        break
    fi
    sleep 2
    ((timeout-=2))
done

if [ $timeout -le 0 ]; then
    print_error "Docker daemon failed to start"
    exit 1
fi

print_success "Docker daemon is ready"

# =============================================================================
# Step 5: Copy repos into container
# =============================================================================
print_step "Copying repositories into container..."

CONTAINER_ID=$(docker compose -f docker-compose.test.yml ps -q test-runner)

for repo in "${REPOS[@]}"; do
    docker cp "$TEMP_REPOS_DIR/$repo" "$CONTAINER_ID:/repos/$repo"
done

# Fix permissions
docker compose -f docker-compose.test.yml exec -T test-runner sudo chown -R testuser:testuser /repos

print_success "Repositories copied into container"

# =============================================================================
# Step 6: Run the test
# =============================================================================
print_step "Running setup flow test..."

# Copy test scripts into container
docker cp "$SCRIPT_DIR/test-setup-flow.sh" "$CONTAINER_ID:/repos/test-setup-flow.sh"
docker cp "$SCRIPT_DIR/setup-test-wrapper.sh" "$CONTAINER_ID:/repos/setup-test-wrapper.sh"
docker compose -f docker-compose.test.yml exec -T test-runner chmod +x /repos/test-setup-flow.sh /repos/setup-test-wrapper.sh

# Run the test
echo ""
echo -e "${BLUE}═══════════════════════ Test Output ═══════════════════════${NC}"
echo ""

TEST_EXIT_CODE=0
docker compose -f docker-compose.test.yml exec -T test-runner /repos/test-setup-flow.sh || TEST_EXIT_CODE=$?

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# =============================================================================
# Step 7: Report results
# =============================================================================
if [ $TEST_EXIT_CODE -eq 0 ]; then
    print_header "TEST PASSED ✓"
    echo -e "${GREEN}All setup.sh flow tests completed successfully!${NC}"
else
    print_header "TEST FAILED ✗"
    echo -e "${RED}Some tests failed. See output above for details.${NC}"
fi

echo ""
exit $TEST_EXIT_CODE
