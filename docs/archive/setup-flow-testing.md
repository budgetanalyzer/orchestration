# Test Plan: setup.sh Flow Testing with Docker-in-Docker

## Overview

Create a containerized test environment that simulates a fresh developer machine to validate the complete setup.sh flow.

## Files to Create

### 1. `tests/setup-flow/Dockerfile.test-env`

A Docker image with all prerequisites installed:
- docker CLI (for DinD)
- kind, kubectl, helm, tilt
- mkcert, certutil
- git

### 2. `tests/setup-flow/docker-compose.test.yml`

Orchestrates the test with:
- DinD container (docker:dind)
- Test runner container with prerequisites
- Volume mounts for repos

### 3. `tests/setup-flow/run-test.sh`

Host script to:
1. Build test image
2. Copy repos to temp directory (manual clone alternative)
3. Start docker-compose
4. Run test and capture results
5. Clean up

### 4. `tests/setup-flow/test-setup-flow.sh`

Test script that runs inside the container:
- Executes setup.sh with modified clone step
- Validates each step succeeded
- Reports pass/fail for each component

## Test Approach

### Pre-test Setup (on host)

```bash
# Create temp directory with all repos
mkdir -p /tmp/ba-test-repos
cp -r ../orchestration /tmp/ba-test-repos/
cp -r ../service-common /tmp/ba-test-repos/
cp -r ../transaction-service /tmp/ba-test-repos/
cp -r ../currency-service /tmp/ba-test-repos/
cp -r ../budget-analyzer-web /tmp/ba-test-repos/
cp -r ../session-gateway /tmp/ba-test-repos/
cp -r ../token-validation-service /tmp/ba-test-repos/
cp -r ../permission-service /tmp/ba-test-repos/
```

### Test Execution Steps

1. **Tool verification** - Verify all tools are available in container
2. **Docker daemon** - Confirm DinD is accessible
3. **Clone repos** - Skip git clone, verify copied repos exist
4. **Kind cluster** - Create cluster, verify port mappings
5. **DNS configuration** - Modify /etc/hosts in container
6. **Gateway API/Envoy** - Install and verify CRDs
7. **TLS certificates** - Generate certs with mkcert, create K8s secret
8. **Environment file** - Verify .env creation

### Validation Checks

- `kind get clusters` returns "kind"
- `kubectl get crd gateways.gateway.networking.k8s.io` succeeds
- `kubectl get deployment -n envoy-gateway-system envoy-gateway` shows Available
- `kubectl get secret budgetanalyzer-localhost-wildcard-tls` exists
- `.env` file exists in orchestration dir
- All 7 sibling repos present

### Test Output

- Exit code 0 = all tests pass
- Detailed log of each step
- Summary of pass/fail for each component

## Modifications Needed to setup.sh

Create `tests/setup-flow/setup-test-wrapper.sh` that:
1. Sets env var to skip git clone step
2. Sources modified clone-repos that just validates dirs exist
3. Runs rest of setup.sh normally

## Directory Structure

```
tests/
└── setup-flow/
    ├── Dockerfile.test-env
    ├── docker-compose.test.yml
    ├── run-test.sh              # Entry point on host
    ├── test-setup-flow.sh       # Runs inside container
    ├── setup-test-wrapper.sh    # Modified setup for testing
    └── README.md                # Usage instructions
```

## Usage

```bash
# From orchestration root
./tests/setup-flow/run-test.sh
```

## Expected Runtime

~5-10 minutes (mostly waiting for Envoy Gateway to become ready)
