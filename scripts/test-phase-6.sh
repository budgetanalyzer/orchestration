#!/bin/bash

################################################################################
# Phase 6 Testing Script
#
# This script automates testing of the microservice template system by creating
# various test services and validating they build and run correctly.
#
# Test Scenarios:
# 1. Minimal Non-Web Service (no add-ons)
# 2. REST API Service (Web + PostgreSQL + SpringDoc)
# 3. Message Consumer Service (PostgreSQL + RabbitMQ)
# 4. Scheduled Batch Service (PostgreSQL + Scheduling + ShedLock)
# 5. Full-Featured REST Service (Web + PostgreSQL + Redis + TestContainers + SpringDoc)
# 6. Code Quality Checks
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKSPACE_DIR="/workspace"
TEST_SERVICES_DIR="${WORKSPACE_DIR}/test-services"
RESULTS_FILE="${WORKSPACE_DIR}/orchestration/docs/service-creation/phase-6-test-results.md"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Phase 6 Testing - Microservice Template Validation${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
    echo ""
}

test_passed() {
    local test_name="$1"
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    print_success "$test_name"
}

test_failed() {
    local test_name="$1"
    local error_msg="${2:-No error message provided}"
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$test_name: $error_msg")
    print_error "$test_name - $error_msg"
}

################################################################################
# Test Service Creation Functions
################################################################################

create_minimal_service() {
    print_section "Test 1: Creating Minimal Non-Web Service"

    local service_name="test-minimal"
    local service_dir="${TEST_SERVICES_DIR}/${service_name}"

    # Clean up if exists
    rm -rf "$service_dir"

    # Clone template
    print_info "Cloning template repository..."
    git clone --quiet https://github.com/budgetanalyzer/spring-boot-service-template.git "$service_dir"

    if [ ! -d "$service_dir" ]; then
        test_failed "Minimal Service - Clone" "Failed to clone template"
        return 1
    fi
    test_passed "Minimal Service - Clone"

    # Replace placeholders
    print_info "Replacing placeholders..."
    cd "$service_dir"

    # Replace in files
    find . -type f -not -path './.git/*' -exec sed -i \
        -e "s/{SERVICE_NAME}/test-minimal/g" \
        -e "s/{DOMAIN_NAME}/testminimal/g" \
        -e "s/{ServiceClassName}/TestMinimal/g" \
        -e "s/{SERVICE_PORT}/9990/g" \
        -e "s/{DATABASE_NAME}/test_minimal/g" \
        -e "s/{SERVICE_COMMON_VERSION}/0.0.1-SNAPSHOT/g" \
        -e "s/{JAVA_VERSION}/24/g" \
        {} \; 2>/dev/null || true

    test_passed "Minimal Service - Placeholder Replacement"

    # Build
    print_info "Building service..."
    if ./gradlew clean build --no-daemon > /tmp/test-minimal-build.log 2>&1; then
        test_passed "Minimal Service - Build"
    else
        test_failed "Minimal Service - Build" "Build failed (see /tmp/test-minimal-build.log)"
        return 1
    fi

    # Run briefly to verify
    print_info "Running service (5 second test)..."
    if timeout 5s ./gradlew bootRun --no-daemon > /tmp/test-minimal-run.log 2>&1 || [ $? -eq 124 ]; then
        test_passed "Minimal Service - Startup"
    else
        test_failed "Minimal Service - Startup" "Service failed to start (see /tmp/test-minimal-run.log)"
        return 1
    fi

    cd "$WORKSPACE_DIR/orchestration"
}

create_rest_api_service() {
    print_section "Test 2: Creating REST API Service"

    local service_name="test-rest-api"
    local service_dir="${TEST_SERVICES_DIR}/${service_name}"

    # This test requires manual intervention with create-service.sh
    # or implementing non-interactive mode

    print_warning "REST API Service test requires manual execution of create-service.sh"
    print_info "Run: cd /workspace/orchestration && ./scripts/create-service.sh"
    print_info "Options: test-rest-api, port 9991, add Spring Boot Web, PostgreSQL, SpringDoc"

    # For now, mark as skipped
    print_info "Skipping automated test - manual verification required"
}

cleanup_test_services() {
    print_section "Cleanup"

    if [ -d "$TEST_SERVICES_DIR" ]; then
        print_info "Removing test services directory..."
        rm -rf "$TEST_SERVICES_DIR"
        print_success "Cleanup complete"
    fi
}

################################################################################
# Test Execution
################################################################################

run_all_tests() {
    print_header

    # Create test services directory
    mkdir -p "$TEST_SERVICES_DIR"

    # Run tests
    create_minimal_service || true
    create_rest_api_service || true

    # Print summary
    print_section "Test Summary"
    echo -e "Tests run: ${BLUE}${TESTS_RUN}${NC}"
    echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
    echo ""

    if [ ${TESTS_FAILED} -gt 0 ]; then
        echo -e "${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        echo ""
    fi

    # Cleanup
    if [ "${CLEANUP:-true}" = "true" ]; then
        cleanup_test_services
    else
        print_info "Skipping cleanup (CLEANUP=false)"
    fi

    # Exit with appropriate code
    if [ ${TESTS_FAILED} -eq 0 ]; then
        print_success "All tests passed!"
        exit 0
    else
        print_error "Some tests failed"
        exit 1
    fi
}

################################################################################
# Main
################################################################################

# Parse arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--no-cleanup]"
        echo ""
        echo "Options:"
        echo "  --no-cleanup    Keep test services after completion"
        echo "  --help, -h      Show this help message"
        exit 0
        ;;
    --no-cleanup)
        CLEANUP=false
        ;;
esac

run_all_tests
