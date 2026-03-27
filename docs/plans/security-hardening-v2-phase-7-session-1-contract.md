# Security Hardening v2 Phase 7 Session 1 Contract

This document freezes the Phase 7 supply-chain scope for the orchestration
repo. It is the source of truth for:

- the executable image-pinning inventory
- the only approved local-image exceptions
- the retained stale assets that still stay inside the static scan
- the installer-hardening surfaces frozen in Session 1

## Scope

Phase 7 guardrails cover orchestration-owned third-party image references in:

- active Kubernetes manifests
- orchestration-owned Dockerfiles and inline Tilt Dockerfiles
- retained DinD assets that still ship in this repo
- verifier probe image constants that are part of the Phase 0 through Phase 7
  runtime proofs

The checked-in executable inventory for that scope lives in:

- `scripts/dev/lib/phase-7-image-pinning-targets.txt`
- `scripts/dev/lib/phase-7-allowed-latest.txt`

`scripts/dev/check-phase-7-image-pinning.sh` must read those inventories
instead of carrying its own parallel file list.

## Local Tilt Image Contract

Only the seven approved local Tilt-built image repos may bypass the normal
third-party digest rule, and only for the local development path.

### Checked-In Manifest Literals

These are the only approved checked-in `:latest` literals:

- `transaction-service:latest`
- `currency-service:latest`
- `permission-service:latest`
- `session-gateway:latest`
- `ext-authz:latest`
- `budget-analyzer-web:latest`
- `budget-analyzer-web-prod-smoke:latest`

Those checked-in refs remain valid only when the workload also sets
`imagePullPolicy: Never`.

### Tilt Deploy-Time Refs

Tilt does not deploy those seven images as literal `:latest` refs. During the
live apply path it rewrites them to immutable local tags with the pattern:

- `<approved-repo>:tilt-[0-9a-f]{16}`

Captured March 27, 2026 from `tilt dump engine` on the failing host-side Tilt
run:

- `transaction-service:tilt-f3207b6e83858452`
- `ext-authz:tilt-752304df648dc1e1`
- `budget-analyzer-web-prod-smoke:tilt-d1622efb13cae97b`

The same Tilt run's node-load logs also showed Docker's canonicalized local
form:

- `docker.io/library/transaction-service:tilt-f3207b6e83858452`
- `docker.io/library/ext-authz:tilt-752304df648dc1e1`
- `docker.io/library/budget-analyzer-web-prod-smoke:tilt-d1622efb13cae97b`

Phase 7 admission policy must stay narrow:

- allow only those same seven repo names
- allow only the checked-in `:latest` literals or Tilt's immutable
  `:tilt-<hash>` deploy tags for those repos
- continue to require `imagePullPolicy: Never` for those local-only refs
- reject any other mutable tag, repo name, or registry broadening

Every other orchestration-owned third-party `image:` or `FROM` reference must
be pinned with `@sha256:`.

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
| `scripts/dev/verify-security-prereqs.sh` | `busybox:1.36.1`, `hashicorp/http-echo:1.0.0` | Test/probe images | Active verifier images |
| `scripts/dev/verify-phase-2-network-policies.sh` | `busybox:1.36.1` | Test/probe image | Active verifier image |
| `scripts/dev/verify-phase-3-istio-ingress.sh` | `busybox:1.36.1`, `mendhak/http-https-echo:38` | Test/probe images | Active verifier images |
| `scripts/dev/verify-phase-4-transport-encryption.sh` | `redis:7-alpine`, `postgres:16-alpine`, `python:3.12-alpine` | Test/probe images | Active verifier images |
| `scripts/dev/verify-phase-5-runtime-hardening.sh` | `busybox:1.36.1` | Test/probe image | Active verifier image |
| `scripts/dev/verify-phase-6-edge-browser-hardening.sh` | `curlimages/curl:8.12.1` | Test/probe image | Active verifier image |
| `scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` | `curlimages/curl:8.12.1` | Test/probe image | Active verifier image |
| `scripts/dev/verify-phase-7-runtime-guardrails.sh` | probe images referenced there | Test/probe images | Active verifier image set stays in scope through Phase 7 |

## Coordinated Sibling Pinning Targets

These refs are outside this repo's write scope for code, but they are inside
the Phase 7 inventory because they are coordinated build assets.

| Repo surface | Current refs | Class | Notes |
|---|---|---|---|
| `../transaction-service/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset |
| `../currency-service/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset |
| `../permission-service/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset |
| `../session-gateway/Dockerfile` | `eclipse-temurin:24-jdk-alpine@sha256:8fdbcb6bc6b846640cea7058e6eeb56c311fae4efaa506a213789134065c6b90`, `eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f` | Third-party build/base images | Coordinated sibling service build asset |
| `../budget-analyzer-web/Dockerfile` | `node:20-alpine@sha256:f598378b5240225e6beab68fa9f356db1fb8efe55173e6d4d8153113bb8f333c` | Third-party build/base image | Active sibling dev image |
| `../budget-analyzer-web/Dockerfile.dev` | `node:20-alpine@sha256:f598378b5240225e6beab68fa9f356db1fb8efe55173e6d4d8153113bb8f333c` | Third-party build/base image | Retained sibling dev/HMR Dockerfile |
| `../workspace/ai-agent-sandbox/Dockerfile` | `docker.io/library/ubuntu:24.04@sha256:186072bba1b2f436cbb91ef2567abca677337cfc786c86e107d25b7072feef0c` | Third-party build/base image | Workspace devcontainer/tooling image |

## Retained Stale Assets

These files are not Phase 7 completion gates. They stay in the inventory so
they do not silently drift further away from the active stack.

| Surface | Current refs | Why still tracked |
|---|---|---|
| `tests/shared/Dockerfile.test-env` | `ubuntu:22.04` | Shared base image for the retained DinD suites |
| `tests/setup-flow/docker-compose.test.yml` | `docker:27-dind` | Retained setup-flow DinD daemon image |
| `tests/setup-flow/kind-cluster-test-config.yaml` | `kindest/node:v1.32.2` | Retained setup-flow Kind node image |
| `tests/security-preflight/docker-compose.test.yml` | `docker:27-dind` | Retained security-preflight DinD daemon image |

`tests/setup-flow/**` and `tests/security-preflight/**` remain stale,
non-gating runtime suites, but their checked-in image references are still
frozen and stay inside the static image-pinning scan while those assets remain
in this repo.

## Explicit Exclusions

- `docs/archive/**` and `docs/decisions/**` are historical only and not part of
  the guardrail scope.
- Documentation snippets may show unpinned images as examples; they are not the
  executable inventory.
- `docs/architecture/autonomous-ai-execution.md` may show DinD examples, but
  the live retained test assets are the files under `tests/`.
- `../service-common` and `../checkstyle-config` currently have no relevant
  `image:` or `FROM` refs requiring Phase 7 action.

## Installer Surfaces Frozen In Session 1

Historical snapshot note: this table preserves the Session 1 freeze exactly as
the installer-hardening follow-up scope, even though later sessions hardened
most of these surfaces.

| Surface | Session 1 follow-up target |
|---|---|
| `setup.sh` | Replace legacy Helm bootstrap guidance with a pinned, integrity-checked path |
| `scripts/dev/check-tilt-prerequisites.sh` | Remove floating `stable.txt`, `latest`, and pipe-to-shell install guidance |
| `docs/tilt-kind-setup-guide.md` | Remove the same floating-release and pipe-to-shell patterns from user-facing setup docs |
| `tests/shared/Dockerfile.test-env` | Replace floating installer flows in the retained DinD asset |
| `../workspace/ai-agent-sandbox/Dockerfile` | Replace NodeSource/Helm/Tilt floating installer flows in the coordinated workspace image |
| `scripts/dev/setup-k8s-tls.sh` | Keep certificate generation host-only while hardening `mkcert` install guidance |

## Change Rule

If a Phase 7 guarded surface is added, removed, or renamed:

1. Update `scripts/dev/lib/phase-7-image-pinning-targets.txt` or
   `scripts/dev/lib/phase-7-allowed-latest.txt` first.
2. Update this contract doc in the same change.
3. Rerun `./scripts/dev/check-phase-7-image-pinning.sh`.
