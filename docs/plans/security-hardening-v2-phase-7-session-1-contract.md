# Security Hardening v2 Phase 7 Session 1 Contract Freeze

Session 1 freezes the Phase 7 scope before any mass pinning or installer edits land.
This document is the source of truth for what counts as an allowed local image,
what must be digest-pinned, which test assets are stale but still in scope, and
which grep hits are explicit exclusions.

## Frozen Rules

- Only explicit local Tilt build outputs may remain on `:latest`, and only when
  the Kubernetes manifest also sets `imagePullPolicy: Never`.
- Every third-party image or base image in active repo assets, retained test
  assets, and coordinated sibling build assets must move to
  `name:tag@sha256:...`.
- No new pipe-to-shell install guidance is allowed. Do not add new
  `| bash`, floating `stable.txt`, or floating `latest` installer instructions
  where a pinned, integrity-checkable release artifact exists.
- Certificate generation remains host-only. Phase 7 may harden the host-side
  `mkcert` guidance, but it must not move `mkcert` or OpenSSL key generation
  into agent-run automation.
- `tests/setup-flow` and `tests/security-preflight` are retained, stale,
  non-gating Phase 7 assets until they are explicitly realigned to the current
  Istio-only baseline. If they remain checked in, their third-party image refs
  still follow the same digest-pinning rule as the rest of the repo.

## Allowed Local `:latest` Images

These are the only checked-in exceptions to the third-party digest-pinning rule.

| Image | Evidence | Why allowed |
|---|---|---|
| `transaction-service:latest` | `Tiltfile`; `kubernetes/services/transaction-service/deployment.yaml` | Local Tilt build output loaded into Kind |
| `currency-service:latest` | `Tiltfile`; `kubernetes/services/currency-service/deployment.yaml` | Local Tilt build output loaded into Kind |
| `permission-service:latest` | `Tiltfile`; `kubernetes/services/permission-service/deployment.yaml` | Local Tilt build output loaded into Kind |
| `session-gateway:latest` | `Tiltfile`; `kubernetes/services/session-gateway/deployment.yaml` | Local Tilt build output loaded into Kind |
| `ext-authz:latest` | `Tiltfile`; `kubernetes/services/ext-authz/deployment.yaml` | Local Tilt build output loaded into Kind |
| `budget-analyzer-web:latest` | `Tiltfile`; `kubernetes/services/budget-analyzer-web/deployment.yaml` | Local Tilt build output loaded into Kind |
| `budget-analyzer-web-prod-smoke:latest` | `Tiltfile`; `kubernetes/services/nginx-gateway/deployment.yaml` | Local Tilt smoke-build asset image loaded into Kind |

## Orchestration-Owned Third-Party Pinning Targets

| Surface | Current refs | Class | Notes |
|---|---|---|---|
| `kind-cluster-config.yaml` | `kindest/node:v1.30.8` | Third-party runtime image | Active local cluster bootstrap image |
| `kubernetes/infrastructure/postgresql/statefulset.yaml` | `postgres:16-alpine` | Third-party runtime image | Used by both `fix-tls-perms` init container and main PostgreSQL container |
| `kubernetes/infrastructure/redis/deployment.yaml` | `redis:7-alpine` | Third-party runtime image | Active infrastructure runtime image |
| `kubernetes/infrastructure/rabbitmq/statefulset.yaml` | `rabbitmq:3.13-management` | Third-party runtime image | Active infrastructure runtime image |
| `kubernetes/services/nginx-gateway/deployment.yaml` | `nginxinc/nginx-unprivileged:1.29.4-alpine` | Third-party runtime image | Active gateway runtime image |
| `kubernetes/services/{currency-service,permission-service,session-gateway,transaction-service}/deployment.yaml` | `busybox:1.36.1` | Third-party runtime image | Shared init-container image across four service deployments |
| `Tiltfile` | `eclipse-temurin:24-jre-alpine` | Third-party build/base image | Inline base image for local Spring Boot service images |
| `Tiltfile` | `alpine:3.22.2` | Third-party build/base image | Inline base image for `budget-analyzer-web-prod-smoke` |
| `ext-authz/Dockerfile` | `golang:1.24-alpine`, `gcr.io/distroless/static:nonroot` | Third-party build/base images | Builder and runtime bases for `ext-authz` |
| `scripts/dev/verify-security-prereqs.sh` | `busybox:1.36.1`, `hashicorp/http-echo:1.0.0` | Test/probe images | Active verifier images; still in scope for digest pinning |
| `scripts/dev/verify-phase-2-network-policies.sh` | `busybox:1.36.1` | Test/probe image | Active verifier image |
| `scripts/dev/verify-phase-3-istio-ingress.sh` | `busybox:1.36.1`, `mendhak/http-https-echo:38` | Test/probe images | Active verifier images |
| `scripts/dev/verify-phase-4-transport-encryption.sh` | `redis:7-alpine`, `postgres:16-alpine`, `python:3.12-alpine` | Test/probe images | Active verifier images |
| `scripts/dev/verify-phase-5-runtime-hardening.sh` | `busybox:1.36.1` | Test/probe image | Active verifier image |
| `scripts/dev/verify-phase-6-edge-browser-hardening.sh` | `curlimages/curl:8.12.1` | Test/probe image | Active verifier image |
| `scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` | `curlimages/curl:8.12.1` | Test/probe image | Active verifier image |

## Coordinated Sibling Pinning Targets

These refs are outside this repo's write scope for code, but they are inside the
Phase 7 inventory because they are coordinated build assets.

| Repo surface | Current refs | Class | Notes |
|---|---|---|---|
| `../transaction-service/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset; pinned in Session 3 |
| `../currency-service/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset; pinned in Session 3 |
| `../permission-service/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset; pinned in Session 3 |
| `../session-gateway/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset; pinned in Session 3 |
| `../budget-analyzer-web/Dockerfile` | `node:20-alpine@sha256:f598378b5240225e6beab68fa9f356db1fb8efe55173e6d4d8153113bb8f333c` | Third-party build/base image | Active sibling dev image; pinned in Session 3 |
| `../budget-analyzer-web/Dockerfile.dev` | `node:20-alpine@sha256:f598378b5240225e6beab68fa9f356db1fb8efe55173e6d4d8153113bb8f333c` | Third-party build/base image | Retained sibling dev/HMR Dockerfile; pinned in Session 3 |
| `../workspace/ai-agent-sandbox/Dockerfile` | `docker.io/library/ubuntu:24.04@sha256:186072bba1b2f436cbb91ef2567abca677337cfc786c86e107d25b7072feef0c` | Third-party build/base image | Workspace devcontainer/tooling image; pinned in Session 3 |

## Retained Stale DinD Assets

These files are not Phase 7 completion gates. They stay in the inventory so they
do not silently drift further away from the active stack.

| Surface | Current refs | Why still tracked |
|---|---|---|
| `tests/shared/Dockerfile.test-env` | `ubuntu:22.04` | Shared base image for the retained DinD suites |
| `tests/setup-flow/docker-compose.test.yml` | `docker:27-dind` | Retained setup-flow DinD daemon image |
| `tests/setup-flow/kind-cluster-test-config.yaml` | `kindest/node:v1.32.2` | Retained setup-flow Kind node image |
| `tests/security-preflight/docker-compose.test.yml` | `docker:27-dind` | Retained security-preflight DinD daemon image |

## Explicit Exclusions And No-Action Scan Results

- `docs/architecture/deployment-architecture-gcp.md` and
  `docs/architecture/deployment-architecture-gcp-demo-mode.md` contain
  documentation snippets with `image:` and `FROM` lines. They are not active
  manifests or active build assets for Phase 7.
- `docs/architecture/autonomous-ai-execution.md` contains a `docker:27-dind`
  snippet as documentation. The live retained test assets are the compose files
  under `tests/`, not this document example.
- `../transaction-service/docs/database-schema.md` contains SQL `FROM ...`
  clauses. Those are grep false positives, not image or Docker base refs.
- `../service-common` was scanned and currently has no relevant `image:` or
  `FROM` refs requiring Phase 7 action.
- `../checkstyle-config` was scanned and currently has no relevant `image:` or
  `FROM` refs requiring Phase 7 action.
- `../workspace/ai-agent-sandbox/docker-compose.yml` was scanned and contains a
  build-only service definition, not a direct third-party `image:` ref.

## Installer Surfaces Frozen For Follow-Up Hardening

Historical snapshot note: this table preserves the Session 1 freeze exactly as
recorded before Session 4 landed. Current-state clarification as of March 27,
2026: `setup.sh`, `scripts/dev/check-tilt-prerequisites.sh`,
`docs/tilt-kind-setup-guide.md`, `tests/shared/Dockerfile.test-env`, and
`../workspace/ai-agent-sandbox/Dockerfile` now use the hardened installer path
described in Session 4, while `scripts/dev/setup-k8s-tls.sh` still keeps
certificate generation host-only and now points Linux users at the verified
`mkcert` installer.

| Surface | Current issue |
|---|---|
| `setup.sh` | Helm auto-install is version-pinned, but still uses `get-helm-3 | bash` |
| `scripts/dev/check-tilt-prerequisites.sh` | Recommends `kubectl` via floating `stable.txt`, Helm via `get-helm-3 | bash`, Tilt via install script, and `mkcert` via floating `latest` URL |
| `docs/tilt-kind-setup-guide.md` | User-facing install guide still contains the same pipe-to-shell and floating-release patterns |
| `tests/shared/Dockerfile.test-env` | Uses floating `kubectl stable.txt`, `get-helm-3 | bash`, Tilt install script, and floating `mkcert latest` artifact |
| `../workspace/ai-agent-sandbox/Dockerfile` | Uses NodeSource `setup_lts.x | bash`, `get-helm-3 | bash`, and Tilt install script |
| `scripts/dev/setup-k8s-tls.sh` | Host-only `mkcert` guidance still references a floating `latest` artifact URL |

## Scan Summary

- Active local `:latest` exceptions are limited to seven known Tilt-built images.
- Active third-party pinning targets exist in orchestration manifests, inline
  Tilt Dockerfiles, `ext-authz`, runtime verifier scripts, Kind configs, the
  retained DinD assets, sibling service Dockerfiles, and the workspace
  devcontainer Dockerfile.
- `service-common` and `checkstyle-config` currently have no relevant refs.
