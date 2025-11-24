# Autonomous AI Execution Pattern

## Overview

**Core Principle**: An effective technique for running AI coding agents is to give them a clear task, define success criteria, and let them execute autonomously in a safe sandbox.

This document explains the architectural pattern that makes this possible: containerized AI agent execution with full privileges, isolated from the host system.

## The Pattern

### Autonomous Execution Flow

```
1. Define the task clearly
2. Set testable success criteria
3. Run agent with --dangerously-skip-permissions
4. Verify results against success criteria
```

### Why `--dangerously-skip-permissions` is Essential

AI agents need to execute **autonomously** to be effective. Permission prompts break the execution flow:

- Agent makes a plan
- Agent executes step 1
- Agent needs sudo for step 2 → **BLOCKS waiting for permission**
- Human approves
- Agent executes step 2
- Agent needs to install a package → **BLOCKS again**
- Human approves
- And so on...

**This is not how AI should work.** The pattern should be:

1. Human reviews the plan
2. Agent executes entire plan autonomously
3. Human verifies results

### Bash Alias for Quick Access

The project provides a convenient alias:

```bash
alias dangerous="claude --dangerously-skip-permissions"
```

Use this for autonomous execution sessions where you've already reviewed the plan.

### Headless/CI Mode

For automated workflows:

```bash
claude -p "fix all lint errors" \
  --dangerously-skip-permissions \
  --output-format json
```

## Container Architecture: Safety Through Isolation

### The VS Code Devcontainer Sandbox

**Key Insight**: Give Claude Code maximum capability with zero risk by running it in an isolated container.

```
┌─────────────────────────────────────────────────────┐
│  Host Machine (Protected)                          │
│  ┌────────────────────────────────────────────┐   │
│  │  VS Code Devcontainer (Isolated)            │   │
│  │  ┌────────────────────────────────────────┐│   │
│  │  │  Claude Code Agent                     ││   │
│  │  │  - Full sudo access                    ││   │
│  │  │  - Install any package                 ││   │
│  │  │  - Modify system config                ││   │
│  │  │  - Run any command                     ││   │
│  │  │  ✓ Safe: cannot affect host            ││   │
│  │  └────────────────────────────────────────┘│   │
│  │  Workspace Volume: /workspace              │   │
│  │  (only accessible location)                │   │
│  └────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### What Claude CAN Do (Inside Container)

- Run `sudo` commands without restrictions
- Install packages: `apt-get install`, `npm install -g`, `pip install`
- Modify system configurations (e.g., configure nginx, set environment variables)
- Compile and build anything (Java, Node.js, Go, Rust, etc.)
- Create, modify, delete files in `/workspace`
- Run Docker commands (via wormhole pattern - see below)
- Execute integration tests with TestContainers
- Start local Kubernetes clusters (Kind)

### What Claude CANNOT Do

- Access files outside `/workspace` (container filesystem boundary)
- Affect host system's packages or configuration
- Modify the sandbox configuration itself (mounted read-only at `.devcontainer/`)
- Break out of container isolation
- Access host network directly (except via exposed ports)

### Self-Protecting Configuration

The sandbox directory is mounted read-only to prevent accidental modification:

```yaml
# claude-code-sandbox/docker-compose.yml
volumes:
  - .:/workspace/orchestration/claude-code-sandbox:ro  # read-only
```

Claude cannot "shoot itself in the foot" by modifying its own container config.

## Docker Access Patterns

This project implements two complementary Docker patterns, each serving different needs.

### Pattern 1: Wormhole (Docker-outside-of-Docker)

**Implemented in**: PR #3, commit `00a27ae`
**Use case**: Running TestContainers integration tests

#### The Problem

Spring Boot services use [TestContainers](https://testcontainers.com/) for integration testing - they spin up real PostgreSQL, Redis, and RabbitMQ containers during tests.

Claude Code runs in a container. How does it run Docker commands to create test containers?

#### The Solution: Docker Socket Wormhole

Mount the host's Docker socket into the Claude container:

```yaml
# claude-code-sandbox/docker-compose.yml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock  # "Wormhole" to host Docker

environment:
  - TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
  - TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal
  - TESTCONTAINERS_REUSE_ENABLE=true
```

#### How It Works

```
┌───────────────────────────────────────────────────────┐
│  Host Machine                                         │
│  ┌─────────────────────────────────────────────┐     │
│  │  Docker Daemon (dockerd)                     │     │
│  │  ├─ claude-dev container (Claude Code)       │     │
│  │  ├─ postgres-test container (TestContainers) │     │
│  │  └─ redis-test container (TestContainers)    │     │
│  └──────────────┬──────────────────────────────┘     │
│                 │                                      │
│  /var/run/docker.sock (Unix socket)                   │
│                 │                                      │
│  ┌──────────────┴──────────────────────────────┐     │
│  │  Claude Container                            │     │
│  │  /var/run/docker.sock (mounted from host)    │     │
│  │  → docker ps                                 │     │
│  │  → ./gradlew test (TestContainers)           │     │
│  └──────────────────────────────────────────────┘     │
└───────────────────────────────────────────────────────┘
```

When Claude runs `docker` commands or `./gradlew test`:
1. Command goes to `/var/run/docker.sock` inside container
2. Socket is actually the host's Docker socket (mounted)
3. Host Docker daemon receives the command
4. Containers are created as **siblings** to the Claude container (not nested)

#### Benefits

- No Docker-in-Docker complexity (no dind daemon)
- Test containers run at native speed
- Claude can run full integration test suites
- Containers are reused across test runs (`TESTCONTAINERS_REUSE_ENABLE=true`)

#### Why It's Called "Wormhole"

The Docker socket acts like a wormhole - commands issued inside the container "teleport" to the host Docker daemon. From Claude's perspective, it has Docker. From the host's perspective, Claude is just another Docker client.

### Pattern 2: True Docker-in-Docker (CI Testing)

**Implemented in**: `tests/setup-flow/`
**Use case**: Testing the complete developer onboarding flow in CI

#### The Problem

We need to test that a brand new developer can:
1. Clone the repo
2. Run `./scripts/dev/setup-k8s-tls.sh`
3. Run `tilt up`
4. Access the application at `https://app.budgetanalyzer.localhost`

But we can't use the wormhole pattern here - that would pollute the CI host's Docker daemon with Kind clusters, test containers, and other artifacts.

#### The Solution: True Docker-in-Docker

Run a Docker daemon **inside** a container, completely isolated from the host:

```yaml
# tests/setup-flow/docker-compose.test.yml
services:
  dind:
    image: docker:28.5.2-dind
    privileged: true  # Required for Docker daemon
    environment:
      - DOCKER_TLS_CERTDIR=/certs
    volumes:
      - docker-certs:/certs/client
      - docker-data:/var/lib/docker

  test-runner:
    build:
      context: .
      dockerfile: Dockerfile.test-env
    depends_on:
      - dind
    environment:
      - DOCKER_HOST=tcp://dind:2376
      - DOCKER_CERT_PATH=/certs/client
      - DOCKER_TLS_VERIFY=1
    volumes:
      - docker-certs:/certs/client:ro
      - ../../:/workspace/orchestration:ro
```

#### How It Works

```
┌─────────────────────────────────────────────────────┐
│  CI Host (GitHub Actions / GitLab CI)              │
│  ┌───────────────────────────────────────────────┐ │
│  │  docker-compose.test.yml                       │ │
│  │  ┌─────────────┐    ┌──────────────────────┐  │ │
│  │  │ dind        │    │ test-runner          │  │ │
│  │  │ (docker:dind)│◄───│ (test-env image)     │  │ │
│  │  │             │TLS │                      │  │ │
│  │  │ Docker      │2376│ - kind               │  │ │
│  │  │ daemon      │    │ - kubectl            │  │ │
│  │  │             │    │ - mkcert             │  │ │
│  │  └─────────────┘    │ - run tests          │  │ │
│  │                     └──────────────────────┘  │ │
│  └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

When the test-runner executes Docker commands:
1. Commands go to `DOCKER_HOST=tcp://dind:2376`
2. The dind container's Docker daemon handles them
3. Containers run **inside** the dind container's environment
4. Completely isolated from the CI host's Docker

#### Benefits

- True isolation - no pollution of host Docker
- Reproducible - simulates fresh developer machine
- CI-friendly - exit code 0 = success, 1 = failure
- Fast cleanup - destroy the dind container, everything is gone

#### Running the Test

```bash
cd tests/setup-flow
docker compose -f docker-compose.test.yml up --build --abort-on-container-exit
```

Expected: Exit code 0, runtime ~5-10 minutes.

### When to Use Which Pattern

| Pattern | Use Case | Tradeoff |
|---------|----------|----------|
| **Wormhole (DooD)** | Development, TestContainers tests | Faster, simpler, but shares host Docker |
| **True DinD** | CI, isolated testing, validating setup flows | Slower, more complex, but fully isolated |

The Budget Analyzer project uses **wormhole for development** (Claude's devcontainer) and **true DinD for CI validation** (setup flow tests).

## Why This Architecture Matters

### For AI Agents

**Traditional approach** (AI on host machine):
- User nervous about giving AI sudo access
- AI needs permission for every sensitive operation
- Constant interruptions break execution flow
- Risk of accidental host system damage

**Containerized approach** (this architecture):
- AI has full sudo access (safe due to isolation)
- No permission prompts needed
- Autonomous execution from start to finish
- Zero risk to host system

**Result**: AI agents can actually work the way they're supposed to - autonomously.

### For Developers

**Benefits**:
- Consistent environment (everyone uses same container)
- Pre-installed tooling (JDK, Node.js, Docker, kubectl, etc.)
- No "works on my machine" issues
- Easy onboarding (open in VS Code, done)

### For Learning & Experimentation

This project is designed as a **learning resource for AI-assisted development**. The container architecture lets you:

- Experiment fearlessly (can't break your host)
- Try new tools without permanent installation
- Test agent prompts safely
- Learn by observing what AI agents do autonomously

## Success Criteria Pattern

To make autonomous execution effective, define **clear, testable success criteria** before running the agent.

### Example: From Authentication Testing Plan

```markdown
## Success Criteria

### Phase 6 (Testing)
- [ ] Token refresh happens automatically before expiration
- [ ] Users cannot access other users' data (403)
- [ ] Rate limiting triggers 429 on abuse
- [ ] Session timeout works correctly
- [ ] M2M client flow works
```

### Pattern Characteristics

1. **Checkbox-based** - clear yes/no for each item
2. **Testable** - specific HTTP codes, behaviors
3. **Phased** - break large tasks into smaller milestones
4. **Prerequisites** - explicit dependencies between phases

### Agent Execution Workflow

```bash
# 1. Human reviews plan and success criteria
cat docs/plans/authentication-testing-plan.md

# 2. Human starts agent in autonomous mode
claude --dangerously-skip-permissions

# 3. Agent executes plan (human monitors but doesn't interrupt)

# 4. Human verifies success criteria
kubectl logs -n budget-analyzer deployment/session-gateway | grep "token refresh"
curl -H "Authorization: Bearer $TOKEN" https://api.budgetanalyzer.localhost/api/transactions/other-user-id
# Should return 403
```

## Security Constraints

Even in a sandbox, some operations are forbidden because they would cause issues outside the container.

### SSL/TLS Certificates (CRITICAL)

**NEVER generate certificates inside the container.**

#### Why

- Claude's container has its own `mkcert` CA (unique to container)
- User's browser trusts their **host machine's** `mkcert` CA
- These are **different CAs** (different root certificates)
- Certificates generated in container → browser shows SSL warnings

#### Forbidden Operations

```bash
# DO NOT run these inside Claude's container:
mkcert "*.budgetanalyzer.localhost"
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr
./scripts/dev/setup-k8s-tls.sh  # (generates certificates)
```

#### Allowed Operations (Read-Only)

```bash
# These are fine (inspection only):
openssl x509 -text -noout -in /workspace/orchestration/certs/budgetanalyzer.crt
kubectl get secret -n budget-analyzer tls-secret -o yaml
openssl verify -CAfile ~/.local/share/mkcert/rootCA.pem budgetanalyzer.crt
```

#### Resolution

When SSL issues occur, guide the user to run certificate generation scripts **on their host machine**:

```bash
# User runs on host (outside container):
cd /path/to/orchestration
./scripts/dev/setup-k8s-tls.sh
```

## Configuration Files

### Devcontainer Setup

**File**: `.devcontainer/devcontainer.json`

```json
{
  "name": "Budget Analyzer",
  "dockerComposeFile": "../claude-code-sandbox/docker-compose.yml",
  "service": "claude-dev",
  "workspaceFolder": "/workspace/orchestration",
  "shutdownAction": "none",  // Container persists across sessions

  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code"  // Pre-install Claude Code extension
      ]
    }
  }
}
```

### Docker Compose Configuration

**File**: `claude-code-sandbox/docker-compose.yml`

Key configurations:

```yaml
services:
  claude-dev:
    build:
      context: .
      dockerfile: Dockerfile

    volumes:
      # Workspace (all repos accessible)
      - ../..:/workspace

      # Sandbox config (read-only)
      - .:/workspace/orchestration/claude-code-sandbox:ro

      # Docker socket wormhole
      - /var/run/docker.sock:/var/run/docker.sock

    environment:
      # TestContainers configuration
      - TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
      - TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal
      - TESTCONTAINERS_REUSE_ENABLE=true

    # User mapping (prevents permission issues)
    user: "${HOST_UID}:${HOST_GID}"
```

### Bash Aliases

**File**: `claude-code-sandbox/bash_aliases.sh`

Sourced automatically on container startup:

```bash
# Quick access to autonomous mode
alias dangerous="claude --dangerously-skip-permissions"

# Example headless usage (commented):
# claude -p "fix all lint errors" --dangerously-skip-permissions --output-format json
```

## Best Practices

### 1. Plan First, Execute Second

```bash
# BAD: Run agent without plan
claude --dangerously-skip-permissions -p "make the app better"

# GOOD: Review plan, then execute
claude -p "implement user authentication"  # Plan mode
# Review plan, ask clarifying questions
# Once plan approved:
dangerous -p "implement the plan we just discussed"
```

### 2. Define Success Criteria Before Execution

Create a checklist before running the agent:

```markdown
## Success Criteria
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] No linting errors
- [ ] Documentation updated
- [ ] Feature works in browser
```

### 3. Use Phased Execution for Large Tasks

Break large tasks into phases:

```bash
# Phase 1: Setup
dangerous -p "create database migrations for user auth"

# Verify Phase 1 success
./gradlew flywayMigrate

# Phase 2: Implementation
dangerous -p "implement auth endpoints"

# Verify Phase 2 success
./gradlew test

# Phase 3: Integration
dangerous -p "integrate auth with frontend"
```

### 4. Monitor Logs During Execution

Even though execution is autonomous, monitoring is valuable:

```bash
# Terminal 1: Run agent
dangerous -p "implement feature X"

# Terminal 2: Monitor test output
watch -n 2 'kubectl get pods -n budget-analyzer'

# Terminal 3: Check application logs
kubectl logs -f -n budget-analyzer deployment/session-gateway
```

### 5. Verify Results Against Criteria

After execution, systematically verify each success criterion:

```bash
# Automated verification
./gradlew test
./gradlew build
kubectl get pods -n budget-analyzer  # All should be Running

# Manual verification
open https://app.budgetanalyzer.localhost
# Test the feature in browser
```

## Troubleshooting

### Agent Gets Stuck Waiting for Permission

**Symptom**: Agent stops mid-execution, waiting for user approval.

**Cause**: Not running with `--dangerously-skip-permissions`.

**Solution**:
```bash
# Exit current session (Ctrl+C)
# Restart with dangerous mode
dangerous
```

### Container Can't Run Docker Commands

**Symptom**: `docker: command not found` or `Cannot connect to the Docker daemon`.

**Cause**: Docker socket not mounted, or incorrect permissions.

**Solution**:
```bash
# Check socket is mounted
ls -la /var/run/docker.sock

# Check user is in docker group
groups | grep docker

# Rebuild container
cd claude-code-sandbox
docker compose down
docker compose up -d
```

### TestContainers Tests Fail with "Cannot connect to Docker"

**Symptom**: Tests fail with Docker connection errors.

**Cause**: TestContainers environment variables not set.

**Solution**:
```bash
# Check environment variables
env | grep TESTCONTAINERS

# Should see:
# TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
# TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal
# TESTCONTAINERS_REUSE_ENABLE=true

# If missing, rebuild container
cd claude-code-sandbox
docker compose down
docker compose build --no-cache
docker compose up -d
```

### Agent Tries to Generate SSL Certificates

**Symptom**: Agent runs `mkcert` or `openssl genrsa`, browser shows SSL warnings.

**Cause**: Agent doesn't understand SSL constraint.

**Solution**: Remind agent of constraint:
```
STOP. SSL certificates must be generated on the host machine, not in this container.
The browser trusts the host's mkcert CA, not this container's CA.

Please guide me to run:
./scripts/dev/setup-k8s-tls.sh

on my host machine (outside the container).
```

## Related Documentation

- [BFF + API Gateway Pattern](bff-api-gateway-pattern.md) - Request flow and routing architecture
- [Security Architecture](security-architecture.md) - Defense-in-depth security model
- [Claude Code Sandbox README](../../claude-code-sandbox/README.md) - Detailed container setup guide
- [Setup Flow Testing](../../tests/setup-flow/README.md) - Docker-in-Docker CI testing

## References

- **PR #3**: "allow claude to run docker so it can work on TestContainers tests" - Implemented wormhole pattern
- **Commit `00a27ae`**: "wormhole pattern for docker" - Core Docker socket mounting logic
- **TestContainers**: https://testcontainers.com/ - Integration testing with real containers
- **Docker-in-Docker**: https://hub.docker.com/_/docker - Official Docker-in-Docker image
- **VS Code Dev Containers**: https://code.visualstudio.com/docs/devcontainers/containers
