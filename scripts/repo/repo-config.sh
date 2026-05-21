#!/bin/bash

# repo-config.sh - Shared configuration for Budget Analyzer repository scripts
#
# This file should be sourced by other scripts that need to operate on
# the Budget Analyzer repositories.
#
# Usage: source "$(dirname "$0")/repo-config.sh"
#
# shellcheck disable=SC2034 # Sourced configuration exports repo sets and paths for callers.

# Repository lists (relative to parent directory)
#
# Keep these sets explicit so release scripts do not accidentally treat tooling
# repositories as OCI runtime artifacts.
RUNTIME_IMAGE_REPOS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "orchestration"
)

JAVA_RUNTIME_REPOS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
)

INFRASTRUCTURE_REPOS=(
    "orchestration"
)

SHARED_LIBRARY_REPOS=(
    "service-common"
)

TOOLING_REPOS=(
    "checkstyle-config"
)

LOCKSTEP_RELEASE_REPOS=(
    "orchestration"
    "service-common"
    "transaction-service"
    "currency-service"
    "budget-analyzer-web"
    "session-gateway"
    "permission-service"
    "checkstyle-config"
)

OCI_RELEASE_SOURCE_REPOS=(
    "orchestration"
    "service-common"
    "transaction-service"
    "currency-service"
    "budget-analyzer-web"
    "session-gateway"
    "permission-service"
)

# Backward-compatible alias for older repo-wide maintenance helpers. New
# release scripts should choose one of the explicit sets above.
REPOS=("${LOCKSTEP_RELEASE_REPOS[@]}")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions for consistent output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Get directory paths
# These variables should be set by the calling script before sourcing this file:
# - SCRIPT_DIR: The directory containing the script
# If not set, we'll try to determine them
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PARENT_DIR="$(dirname "$REPO_ROOT")"
