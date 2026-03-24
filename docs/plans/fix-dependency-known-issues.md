# Plan: Fix Known Issues from Dependency Notifications

## Context

The dependency notifications doc (`docs/dependency-notifications.md`) identified three known issues during the dependency audit. All three are config/infra issues, not application code changes. Each issue is an independent fix.

## Issue 1: Pin NGINX Image Tag

**File**: `orchestration/kubernetes/services/nginx-gateway/deployment.yaml` (line 21)

**Current**: `image: nginx:alpine` (unpinned - pulls whatever latest alpine is)

**Change**: `image: nginx:1.27-alpine`

NGINX 1.27 is the current mainline branch. Using `1.27-alpine` pins to the major.minor while still receiving alpine base image updates. This matches the pattern used by other infrastructure images in the project (e.g., `postgres:16-alpine`, `redis:7-alpine`).

**Verification**: `tilt up` and confirm nginx-gateway pod is Running: `kubectl get pod -l app=nginx-gateway`

## Issue 2: Fix Spring Cloud Version Mismatch

**File**: `currency-service/gradle/libs.versions.toml` (line 4)

**Current**: `springCloud = "2024.0.0"`

**Change**: `springCloud = "2025.0.0"`

Spring Cloud 2024.0.x is designed for Spring Boot 3.4.x. Currency-service is on Spring Boot 3.5.7, which requires Spring Cloud 2025.0.x. Session-gateway is already correctly on 2025.0.0. This is a version catalog config file, not application code.

Currency-service uses two Spring Cloud components:
- `spring-cloud-stream`
- `spring-cloud-stream-binder-rabbit`

These are stable messaging APIs unlikely to have breaking changes between 2024.0.0 and 2025.0.0, but tests should confirm.

**Verification**: `cd /workspace/currency-service && ./gradlew build` - compilation and tests pass

## Issue 3: Pin Tilt Version

**File**: `workspace/ai-agent-sandbox/Dockerfile` (line 69)

**Current**: `RUN curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash`

The install script hardcodes `VERSION="0.37.0"` (current latest), but future runs will pull whatever version is latest at that time. Pin to a specific release tarball:

**Change**:
```dockerfile
# Install tilt (pinned version)
ARG TILT_VERSION=0.37.0
RUN curl -fsSL "https://github.com/tilt-dev/tilt/releases/download/v${TILT_VERSION}/tilt.${TILT_VERSION}.linux.x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin tilt
```

This makes the version explicit and upgradeable via a single `ARG` change.

**Verification**: Rebuild devcontainer image and verify `tilt version` outputs `v0.37.0`

## Issue 4: Update dependency-notifications.md

After fixing issues 1-3, update `docs/dependency-notifications.md`:
- Remove the three items from the Known Issues section
- Update NGINX version in the version inventory tables from `alpine (UNPINNED)` to `1.27-alpine`
- Update Tilt version in the version inventory from `latest (unpinned)` to `0.37.0 (pinned)`
- Update Spring Cloud version for currency-service from `2024.0.0` to `2025.0.0`

## Files to Modify

| File | Repo | Change |
|---|---|---|
| `kubernetes/services/nginx-gateway/deployment.yaml` | orchestration | Pin `nginx:1.27-alpine` |
| `currency-service/gradle/libs.versions.toml` | currency-service (sibling config) | `springCloud = "2025.0.0"` |
| `workspace/ai-agent-sandbox/Dockerfile` | workspace (sibling config) | Pin Tilt to v0.37.0 via release tarball |
| `docs/dependency-notifications.md` | orchestration | Update Known Issues + version inventory |
