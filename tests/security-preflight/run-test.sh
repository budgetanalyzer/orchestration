#!/bin/bash

# run-test.sh - Entry point for security preflight testing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_REPOS_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo
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

cleanup() {
    print_step "Cleaning up"
    cd "$SCRIPT_DIR"
    docker compose -f docker-compose.test.yml down -v --remove-orphans >/dev/null 2>&1 || true
    if [ -n "$TEMP_REPOS_DIR" ]; then
        rm -rf "$TEMP_REPOS_DIR" >/dev/null 2>&1 || true
    fi
    print_success "Cleanup complete"
}

trap cleanup EXIT

print_header "Budget Analyzer - Security Preflight Testing"

if [ ! -d "$ORCHESTRATION_DIR" ]; then
    print_error "Orchestration directory not found at: $ORCHESTRATION_DIR"
    exit 1
fi

print_step "Preparing temporary repository copy"
TEMP_REPOS_DIR=$(mktemp -d)

if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.git' --exclude='node_modules' --exclude='target' --exclude='build' \
        "$ORCHESTRATION_DIR/" "$TEMP_REPOS_DIR/orchestration/"
else
    cp -r "$ORCHESTRATION_DIR" "$TEMP_REPOS_DIR/orchestration"
fi

cp "$ORCHESTRATION_DIR/tests/setup-flow/kind-cluster-test-config.yaml" "$TEMP_REPOS_DIR/kind-cluster-test-config.yaml"
print_success "Repository copy prepared"

print_step "Building test environment image"
cd "$SCRIPT_DIR"
docker compose -f docker-compose.test.yml build --no-cache >/dev/null
print_success "Test image built"

print_step "Starting Docker-in-Docker environment"
docker compose -f docker-compose.test.yml up -d >/dev/null

print_step "Waiting for Docker daemon in test runner"
timeout=60
while [ $timeout -gt 0 ]; do
    if docker compose -f docker-compose.test.yml exec -T test-runner docker info >/dev/null 2>&1; then
        break
    fi
    sleep 2
    timeout=$((timeout - 2))
done

if [ $timeout -le 0 ]; then
    print_error "Docker daemon failed to become ready"
    exit 1
fi
print_success "Docker daemon is ready"

CONTAINER_ID=$(docker compose -f docker-compose.test.yml ps -q test-runner)

print_step "Copying test inputs into container"
docker cp "$TEMP_REPOS_DIR/orchestration" "$CONTAINER_ID:/repos/orchestration"
docker cp "$TEMP_REPOS_DIR/kind-cluster-test-config.yaml" "$CONTAINER_ID:/repos/kind-cluster-test-config.yaml"
docker cp "$SCRIPT_DIR/test-security-preflight.sh" "$CONTAINER_ID:/repos/test-security-preflight.sh"
docker compose -f docker-compose.test.yml exec -T test-runner sudo chown -R testuser:testuser /repos
docker compose -f docker-compose.test.yml exec -T test-runner chmod +x /repos/test-security-preflight.sh
print_success "Container prepared"

print_step "Running security preflight test"

echo
TEST_EXIT_CODE=0
docker compose -f docker-compose.test.yml exec -T test-runner /repos/test-security-preflight.sh || TEST_EXIT_CODE=$?
echo

if [ $TEST_EXIT_CODE -eq 0 ]; then
    print_header "TEST PASSED ✓"
    echo -e "${GREEN}Security preflight checks completed successfully.${NC}"
else
    print_header "TEST FAILED ✗"
    echo -e "${RED}Security preflight checks failed. Review output above.${NC}"
fi

exit $TEST_EXIT_CODE
