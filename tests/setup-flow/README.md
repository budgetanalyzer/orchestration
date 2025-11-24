# Setup Flow Testing

Containerized test environment that validates the complete `setup.sh` flow using Docker-in-Docker (DinD).

## Overview

This test suite creates an isolated environment that simulates a fresh developer machine to validate that `setup.sh` correctly:

1. Checks required tools
2. Creates a Kind cluster with proper port mappings
3. Configures DNS entries
4. Installs Gateway API CRDs
5. Installs Envoy Gateway
6. Generates TLS certificates
7. Creates Kubernetes TLS secret
8. Creates `.env` file

## Prerequisites

- Docker (running)
- All Budget Analyzer repositories cloned as siblings to orchestration

## Usage

From the orchestration root:

```bash
./tests/setup-flow/run-test.sh
```

## What It Tests

| Test | Description |
|------|-------------|
| Tool verification | All required tools (docker, kind, kubectl, helm, tilt, mkcert, git) are available |
| Docker daemon | DinD is accessible from test container |
| Repository validation | All 8 repositories are present |
| Kind cluster | Cluster created successfully with correct port mappings |
| DNS configuration | `/etc/hosts` entries configured |
| Gateway API CRDs | CRDs installed and accessible |
| Envoy Gateway | Deployment available and ready |
| TLS certificates | Wildcard cert generated with mkcert |
| TLS secret | Kubernetes secret created with correct type |
| Environment file | `.env` created from `.env.example` |

## Expected Runtime

~5-10 minutes (primarily waiting for Envoy Gateway to become ready)

## Files

| File | Purpose |
|------|---------|
| `Dockerfile.test-env` | Test image with all prerequisites |
| `docker-compose.test.yml` | Orchestrates DinD and test runner |
| `run-test.sh` | Entry point script (run on host) |
| `test-setup-flow.sh` | Test script (runs in container) |
| `setup-test-wrapper.sh` | Modified setup for testing |

## Test Output

- **Exit code 0**: All tests pass
- **Exit code 1**: One or more tests failed

The test outputs detailed logs for each step and a summary showing passed/failed counts.

## Troubleshooting

### Docker daemon not accessible

```bash
# Check DinD container is running
docker compose -f tests/setup-flow/docker-compose.test.yml ps
docker compose -f tests/setup-flow/docker-compose.test.yml logs dind
```

### Kind cluster fails to create

This usually indicates insufficient resources or Docker issues:

```bash
# Check Docker has enough resources
docker info | grep -E "Memory|CPUs"

# Check for existing kind clusters
docker ps -a | grep kind
```

### Envoy Gateway timeout

Envoy Gateway can take several minutes to become ready. If it times out:

```bash
# Check Envoy Gateway pod status
docker compose -f tests/setup-flow/docker-compose.test.yml exec test-runner \
    kubectl get pods -n envoy-gateway-system
```

### Manual cleanup

If tests fail and leave resources behind:

```bash
cd tests/setup-flow
docker compose -f docker-compose.test.yml down -v --remove-orphans
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Host Machine                                       │
│  ┌─────────────────────────────────────────────┐   │
│  │  docker-compose.test.yml                     │   │
│  │  ┌─────────────┐    ┌──────────────────┐    │   │
│  │  │ dind        │    │ test-runner      │    │   │
│  │  │ (docker:dind)│◄───│ (test-env image) │    │   │
│  │  │             │    │                  │    │   │
│  │  │ Docker      │    │ - kind           │    │   │
│  │  │ daemon      │    │ - kubectl        │    │   │
│  │  │             │    │ - mkcert         │    │   │
│  │  └─────────────┘    │ - etc.           │    │   │
│  │                     │                  │    │   │
│  │                     │ Runs:            │    │   │
│  │                     │ test-setup-flow  │    │   │
│  │                     └──────────────────┘    │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```
