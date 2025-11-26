# Docker-in-Docker Migration Plan

**Created**: 2025-11-26
**Status**: Proposed
**Context**: Architecture Conversations 11 & 12 (Docker Socket Wormhole Discovery)

## Executive Summary

The current devcontainer uses a manual docker-outside-of-docker (DooD) implementation that creates a security vulnerability. This plan proposes migrating to the official VS Code `docker-in-docker` feature, which provides proper isolation while maintaining TestContainers functionality.

## Current State Analysis

### What We Have Now

**Custom Implementation** (`claude-code-sandbox/`):
- Dockerfile manually installs Docker CLI (lines 42-73)
- docker-compose.yml mounts host Docker socket (currently commented out)
- Custom docker group GID management to match host
- Manual TestContainers environment variable configuration

**Security Posture** (as of commit `0f052ab` "scary"):
- Docker socket mount commented out: `#- /var/run/docker.sock:/var/run/docker.sock`
- This closes the wormhole but **breaks TestContainers**
- Trade-off: Security ✅ vs Functionality ❌

### The Wormhole Vulnerability

**Discovery**: Architecture Conversation 12 (Nov 25, 2025)

Even with read-only config mounts, mounting the Docker socket creates a complete escape hatch:

```yaml
# Attacker scenario:
# 1. Write evil.yml to /workspace/
services:
  evil:
    image: alpine
    volumes:
      - /home/user/.ssh:/stolen-keys  # Mount host's SSH keys

# 2. Execute from inside container:
docker compose -f /workspace/evil.yml up -d

# 3. Now have access to host filesystem via docker volume mounts
```

**Why read-only mounts don't help**: Claude can still write files to `/workspace` (which is read-write), then use those files with docker commands that mount arbitrary host paths.

**Current mitigation**: Comment out socket mount = nuclear option. Effective but breaks functionality.

## Problem Statement

We need TestContainers for integration tests, but:

1. **Socket mount (DooD) = Security vulnerability**
   - Container can mount arbitrary host paths via docker commands
   - Equivalent to root access on host
   - No effective sandboxing

2. **No socket mount = Broken functionality**
   - TestContainers cannot reach Docker daemon
   - Integration tests fail
   - Development workflow degraded

3. **Manual implementation is incomplete**
   - Custom GID management fragile across different hosts
   - Missing automatic configuration that official features provide
   - Maintenance burden for edge cases

## Proposed Solution: Official docker-in-docker Feature

### What is Docker-in-Docker?

Runs a **separate, isolated Docker daemon inside the devcontainer**. From the [devcontainers features documentation](https://github.com/devcontainers/features/blob/main/src/docker-in-docker/README.md):

> "Creates child containers inside a container, independent from the host's docker instance"

### Security Model

```
Host Machine
└─ Host Docker Daemon
   └─ Devcontainer (privileged)
      └─ Container Docker Daemon (isolated)
         └─ TestContainers spin up here
```

**Key security property**: Even if Claude runs `docker compose -f evil.yml up`, it only affects the **container's daemon**, not the host's daemon. The worst case is corrupting the container environment, which can be rebuilt.

**Trade-offs**:
- ✅ Host filesystem protected - no arbitrary volume mounts to host
- ✅ TestContainers works - daemon available inside container
- ⚠️ Requires privileged container - but isolated by VM in most cloud dev environments
- ⚠️ Higher overhead - separate daemon with own images/cache
- ⚠️ No shared Docker cache with host

### Why This is Better Than Docker Socket Proxy

Alternative considered: [tecnativa/docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy)

**Socket proxy approach**:
- Filters which Docker API endpoints container can access
- Still exposes host's Docker daemon (filtered)
- Additional component to maintain
- Defense in depth, but not isolation

**DinD approach**:
- Complete isolation via separate daemon
- Built-in VS Code feature (zero maintenance)
- Cannot touch host daemon even with full Docker API access
- Simpler architecture

## Implementation Plan

### 1. Update `devcontainer.json`

**Add** the official feature:

```json
{
  "name": "Budget Analyzer",
  "dockerComposeFile": "../claude-code-sandbox/docker-compose.yml",
  "service": "claude-dev",
  "workspaceFolder": "/workspace/orchestration",
  "shutdownAction": "none",

  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {
      "version": "latest",
      "moby": true
    }
  },

  "remoteEnv": {
    "SSH_AUTH_SOCK": ""
  },

  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code"
      ]
    }
  }
}
```

### 2. Update `Dockerfile`

**Remove** manual Docker installation (lines 42-73):

```dockerfile
# DELETE THIS SECTION:
# Install Docker CLI (for docker-outside-of-docker pattern with Testcontainers)
#
# Note: Pinning to Docker 28.5.2 because 29.0.0 requires client version 1.44+
#       and Testcontainers uses client version 1.32.  Revisit when Testcontainers
#       releases a fix.
#
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli=5:28.5.2-1~ubuntu.24.04~noble docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*
```

**Remove** manual docker group management (lines 64-72):

```dockerfile
# DELETE THIS:
ARG DOCKER_GID

# Create docker group with host's docker GID
RUN groupadd --gid $DOCKER_GID docker || true

# ...
    && usermod -aG docker $USERNAME \
```

**Keep** the rest - the feature will handle Docker installation and group setup.

### 3. Update `docker-compose.yml`

**Remove** socket mount and related config:

```yaml
services:
  claude-dev:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        USERNAME: vscode
        USER_UID: ${USER_UID:-1000}
        USER_GID: ${USER_GID:-1000}
        # REMOVE: DOCKER_GID: ${DOCKER_GID:-999}

    volumes:
      # Mount dev directory as workspace (read/write)
      - ../../:/workspace:cached

      # Mount claude-code-sandbox as read-only
      - .:/workspace/orchestration/claude-code-sandbox:ro

      # Persistent storage for Claude Code credentials
      - claude-anthropic:/home/vscode/.anthropic

      # REMOVE: Mount Docker socket
      # REMOVE: #- /var/run/docker.sock:/var/run/docker.sock

    network_mode: host
    extra_hosts:
      - "host.docker.internal:host-gateway"

    # REMOVE: TestContainers env vars (feature handles this)
    # REMOVE: environment:
    # REMOVE:   - TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
    # REMOVE:   - TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal
    # REMOVE:   - TESTCONTAINERS_REUSE_ENABLE=true

    command: sleep infinity
    user: vscode

volumes:
  claude-anthropic:
```

### 4. Update `setup-env.sh`

**Remove** docker GID detection:

```bash
# DELETE THIS:
# Detect docker group GID
DOCKER_GID=$(getent group docker | cut -d: -f3)
if [ -z "$DOCKER_GID" ]; then
    echo "Warning: docker group not found, using default GID 999"
    DOCKER_GID=999
fi
export DOCKER_GID
```

The feature auto-handles this.

## Testing Strategy

After implementation:

1. **Rebuild devcontainer**: VS Code will download and configure the DinD feature
2. **Verify Docker daemon**: `docker ps` should work inside container
3. **Run TestContainers tests**: Integration tests should pass
4. **Verify isolation**: Run `docker ps` on host vs inside container - should show different lists
5. **Security test**: Attempt to write evil.yml and mount host path - should only affect container daemon

## Migration Path

### Prerequisites

- User must rebuild devcontainer (not just reload)
- First build will be slower (downloads DinD image)
- Existing containers from host won't be visible (separate daemon)

### Rollback Plan

If issues arise:

1. Revert commits to Dockerfile, devcontainer.json, docker-compose.yml
2. Uncomment socket mount if TestContainers needed urgently
3. Document specific issue for later investigation

## References

### Official Documentation
- [VS Code: Use Docker from a Container](https://code.visualstudio.com/remote/advancedcontainers/use-docker-kubernetes)
- [devcontainers/features: docker-in-docker](https://github.com/devcontainers/features/blob/main/src/docker-in-docker/README.md)
- [TestContainers: Docker-in-Docker Patterns](https://java.testcontainers.org/supported_docker_environment/continuous_integration/dind_patterns/)

### Security Analysis
- [The Dangers of Docker.sock](https://raesene.github.io/blog/2016/03/06/The-Dangers-Of-Docker.sock/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Securing Devcontainers (part 3) - Docker-in-Docker](https://some-natalie.dev/blog/devcontainer-docker-in-docker/)
- [What is the Docker security risk of /var/run/docker.sock?](https://stackoverflow.com/questions/40844197/what-is-the-docker-security-risk-of-var-run-docker-sock)

### Alternatives Considered
- [Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy) - Defense in depth but not isolation
- [TestContainers Cloud](https://www.docker.com/blog/testcontainers-cloud-vs-docker-in-docker-for-testing-scenarios/) - SaaS alternative, adds dependency

### Related Discussions
- Architecture Conversation 11: Trust boundaries, sandbox validation
- Architecture Conversation 12: Docker socket wormhole discovery, recursive AI design
- Commit `0f052ab` "scary": Socket mount commented out

## Decision Record

### Why DinD over DooD?

**Docker-outside-of-Docker (current)**:
- Pro: Shared cache with host
- Pro: Lower overhead
- **Con: Security vulnerability (wormhole)**
- Con: Manual implementation fragile

**Docker-in-Docker (proposed)**:
- **Pro: True isolation from host**
- Pro: Official VS Code feature
- Pro: Zero maintenance
- Pro: TestContainers works
- Con: Higher overhead
- Con: Separate image cache

**Conclusion**: Security isolation outweighs cache efficiency for an AI agent environment.

### Why DinD over Socket Proxy?

**Socket Proxy**:
- Pro: Can filter dangerous operations
- Con: Still exposes host daemon
- Con: Additional component to maintain
- Con: Complex ACL configuration

**DinD**:
- **Pro: Complete isolation**
- Pro: Built-in feature
- Pro: Simple configuration

**Conclusion**: Prefer isolation over filtered access.

## Open Questions

1. **Performance impact**: How much slower are builds with separate daemon?
   - Answer: TBD after implementation
   - Mitigation: `moby: true` uses Moby engine which is optimized for DinD

2. **Disk usage**: Will we run out of space with duplicate images?
   - Answer: Monitor disk usage in container
   - Mitigation: Regular `docker system prune` in container

3. **TestContainers compatibility**: Any edge cases with DinD?
   - Answer: Official docs confirm TestContainers works with DinD
   - Reference: https://java.testcontainers.org/supported_docker_environment/continuous_integration/dind_patterns/

## Success Criteria

- [ ] Devcontainer builds successfully with DinD feature
- [ ] `docker ps` works inside container
- [ ] TestContainers integration tests pass
- [ ] Host Docker daemon isolated from container daemon
- [ ] No manual Docker installation in Dockerfile
- [ ] Documentation updated (CLAUDE.md, README)

## Timeline

**Phase 1** (Immediate): Document plan ✅
**Phase 2** (Next session): Implement changes
**Phase 3** (After rebuild): Test and validate
**Phase 4** (If successful): Update architecture docs

---

**Status**: Ready for implementation pending user approval
