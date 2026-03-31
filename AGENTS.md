# Budget Analyzer - Orchestration Repository

## Tree Position

**Archetype**: coordinator
**Scope**: budgetanalyzer ecosystem
**Role**: System orchestrator; coordinates cross-cutting concerns and deployment

### Relationships
- **Coordinates**: All service repos (via patterns and selective documentation/configuration updates, not sibling code changes)
- **Observed by**: architecture-conversations

### Permissions
- **Read**: All siblings via `../`
- **Write**: This repository; capture conversations to `../architecture-conversations/`; documentation and configuration in sibling repos (no sibling code)

### Discovery
```bash
# What I coordinate
ls -d /workspace/*-service /workspace/session-gateway /workspace/budget-analyzer-web
```

## Code Exploration

NEVER use Agent/subagent tools for code exploration. Use Grep, Glob, and Read directly.

## Documentation Discipline

Always keep documentation up to date after any configuration or code change.

Update the nearest affected documentation in the same work:
- `AGENTS.md` when instructions, guardrails, discovery commands, or repository-specific workflow changes
- `README.md` when setup, usage, or repository purpose changes
- `docs/` when architecture, configuration, APIs, behaviors, or operational workflows change

Do not leave documentation updates as follow-up work.

## Project Overview

This orchestration repository coordinates the deployment and development environment for the Budget Analyzer application - a reference architecture for microservices, built as an open-source learning resource for architects exploring AI-assisted development.

**Purpose**: Manages cross-service concerns, local development setup, and deployment coordination. Individual service code lives in separate repositories.

## Project Status: Reference Architecture Complete

This project has reached its intended scope. We are no longer actively developing Budget Analyzer features - we're interested in discussing these patterns with other architects.

**What's implemented:**
- Authentication: OAuth2/OIDC with Auth0, session-based edge authorization, opaque session tokens + ext_authz
- API Gateway: Istio ext_authz for session validation and auth-path throttling, NGINX for API routing and backend/API rate limiting
- Microservices patterns: Spring Boot, Kubernetes, Tilt

**What's intentionally left unsolved:**
- **Data ownership**: Which transactions belong to which user?
- **Cross-service user scoping**: How does transaction-service filter by owner?
- **Multi-tenancy**: Organization-level data isolation

This boundary is deliberate. Data ownership is domain-specific and opinionated. Propagating user ownership to domain services is the next architectural challenge - one we're surfacing, not prescribing.

## Development Environment

**This project is designed for AI-assisted development.**

For containerized development environment setup, see the [workspace](https://github.com/budgetanalyzer/workspace) repository. That's where the devcontainer configuration lives.

## Architecture Principles

- **Production Parity**: Development environment faithfully recreates production
- **Microservices**: Independently deployable services with clear boundaries
- **Session-Based Edge Authorization**: Session Gateway provides browser security and authentication management
- **Gateway Pattern**: Istio ingress handles ext_authz and auth-path throttling; NGINX handles API routing, backend/API rate limiting, and load balancing
- **Resource-Based Routing**: Frontend remains decoupled from service topology
- **Defense in Depth**: Multiple security layers (Istio ingress/ext_authz → Session Gateway or NGINX → Services)
- **Kubernetes-Native Development**: Tilt + Kind for consistent local Kubernetes development. The Tiltfile implements live update pipelines — Java JAR sync with process restart, React source sync with Vite HMR — so code changes reach running pods in seconds without image rebuilds, while the full production stack (mTLS, network policies, ext_authz) stays active. See [Live Development Pipeline](docs/development/local-environment.md#live-development-pipeline)

## Service Architecture

**Pattern**: Microservices deployed via Tilt to local Kind cluster

**Discovery**:
```bash
# List all running resources
tilt get uiresources

# View pod status (services run in default namespace)
kubectl get pods

# View service endpoints
kubectl get svc
```

**Service Types**:
- **Frontend services**: React-based web applications (port 3000 in dev)
- **Backend microservices**: Spring Boot REST APIs (ports 8082+)
- **Session Gateway**: Spring WebFlux (port 8081, HTTP) - browser authentication and heartbeat-driven session management
- **ext-authz**: Go HTTP service (port 9002) - Istio external authorization, session validation via Redis
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (in infrastructure namespace)
- **Ingress**: Istio Ingress Gateway (port 443, HTTPS) - SSL termination, routing, ext_authz enforcement, and auth-path throttling
- **Egress**: Istio Egress Gateway (ClusterIP) - outbound traffic control with REGISTRY_ONLY policy
- **API Gateway**: NGINX (port 8080, HTTP) - internal routing, backend/API rate limiting, and load balancing

**Adding New Services**: Create K8s manifests in `kubernetes/services/{name}/`, add to `Tiltfile`, add NGINX routes if needed. See [docs/architecture/session-edge-authorization-pattern.md](docs/architecture/session-edge-authorization-pattern.md) for details.

**Health Probes**: All Spring Boot services use a three-probe pattern:
- **startupProbe**: Allows up to 120s for slow-starting JVM apps (5s × 24 checks). Pod won't receive traffic until startup succeeds.
- **readinessProbe**: Checks if pod can accept traffic (10s interval)
- **livenessProbe**: Checks if pod is healthy (20s interval)

This prevents "connection refused" errors during deployments when services are still starting.

## Session Edge Authorization + API Gateway Pattern

**Pattern**: Hybrid architecture combining session-based edge authorization for browser security with API Gateway for routing and validation.

**Request Flow**:
```
Browser → Istio Ingress (:443) → ext_authz validates session → NGINX (:8080) → Services
Auth paths: Browser → Istio Ingress (:443, auth-path throttling) → Session Gateway (:8081)
```

**Single entry point**: `app.budgetanalyzer.localhost`
- `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`, `/user` → Session Gateway (auth lifecycle)
- `/api/*` → NGINX (ext_authz enforced, routing to backends)
- `/api-docs`, `/api-docs/*` → NGINX (public API documentation route)
- `/login`, `/*` → NGINX (frontend, no auth required)

**Note**: During session creation, Session Gateway calls permission-service (:8086) to resolve roles/permissions. Active browser sessions stay alive through `GET /auth/session` under `/auth/*`, which lets Session Gateway extend the session TTL and refresh the upstream IDP grant when needed.
- `app.budgetanalyzer.localhost/api-docs` → Unified API documentation (Swagger UI)

**Key Benefits**:
- Same-origin architecture = no CORS issues
- Opaque session tokens = no JWTs exposed to browser (XSS protection)
- Centralized session validation and auth-path throttling at Istio ingress, with backend/API rate limiting remaining at NGINX

**Discovery**:
```bash
# List all API routes
grep "location /api" nginx/nginx.k8s.conf | grep -v "#"

# Test gateway
curl -v https://app.budgetanalyzer.localhost/health

# View service ports
kubectl get svc
```

**When to consult detailed documentation**:
- Understanding component roles and request flow → [docs/architecture/session-edge-authorization-pattern.md](docs/architecture/session-edge-authorization-pattern.md)
- Port reference and service topology → [docs/architecture/port-reference.md](docs/architecture/port-reference.md)
- Adding new API routes → "Adding a New Resource Route" in [nginx/README.md](nginx/README.md)
- Adding new microservices → "Adding a New Microservice" in [nginx/README.md](nginx/README.md)
- Troubleshooting gateway issues → "Troubleshooting" in [nginx/README.md](nginx/README.md)
- Security architecture details → [docs/architecture/security-architecture.md](docs/architecture/security-architecture.md)

## Technology Stack

**Principle**: Each service manages its own dependencies. Versions are defined in service-specific files.

**Discovery**:
```bash
# List all Tilt resources
tilt get uiresources

# View deployed images
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u
```

**Stack Patterns**:
- **Frontend**: React (see individual service package.json)
- **Backend**: Spring Boot + Java (version managed in service-common)
- **Build System**: Gradle (all backend services use Gradle with wrapper)
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (Kubernetes manifests in `kubernetes/infrastructure/`)
- **Ingress**: Istio Ingress Gateway (Kubernetes Gateway API)
- **API Gateway**: NGINX (unprivileged Alpine image)
- **Development**: Tilt + Kind (local Kubernetes)

**Note**: Docker images should be pinned to specific versions for reproducibility.

## Development Workflow

### Prerequisites & Setup

**Required tools**: Docker, Kind, kubectl, OpenSSL, Tilt, Git, mkcert
Helm `3.20.x` is still the required runtime toolchain, but `./setup.sh` now
installs the tested `v3.20.1` automatically when Helm is missing or unsupported.

**Helm version**: Use Helm `3.20.x`. Helm 4 is not supported in this repo.
Gateway API CRDs are pinned to `v1.4.0`, and the repo installs
`istio/base`, `istio/cni`, `istio/istiod`, and `istio/gateway` `1.29.1`
directly from Helm. Ingress gateway hardening is declared through
`kubernetes/istio/ingress-gateway-config.yaml` via Gateway
`spec.infrastructure.parametersRef`, and the egress gateway uses
`kubernetes/istio/egress-gateway-values.yaml` with `service.type=ClusterIP`.

Check prerequisites:
```bash
./scripts/dev/check-tilt-prerequisites.sh
```

**First-time setup**:
```bash
./setup.sh        # Recreates the kind cluster from scratch, installs Calico, ensures supported Helm, refreshes the Istio Helm repo index, configures certs (browser + infra TLS), DNS, and .env
# Edit .env with your Auth0 and FRED API credentials
```

### Quick Start
```bash
# Optional but recommended before cluster apply
# Catch Phase 7 static manifest/security regressions locally
./scripts/dev/verify-phase-7-static-manifests.sh

# Start all services with Tilt
tilt up

# Optional but recommended after tilt up on a clean rebuild
# Prove the seven app deployments were admitted without Phase 7 image-policy violations
./scripts/dev/verify-clean-tilt-deployment-admission.sh

# Optional but recommended after core platform resources are healthy
# Prove the Phase 0 platform baseline
./scripts/dev/verify-security-prereqs.sh
# Close Phase 3 ingress/egress hardening
./scripts/dev/verify-phase-3-istio-ingress.sh
# Close Phase 5 runtime hardening and namespace PSA enforcement
./scripts/dev/verify-phase-5-runtime-hardening.sh
# Close the final local Phase 7 security-guardrail gate
./scripts/dev/verify-phase-7-security-guardrails.sh

# Access Tilt UI for logs and status
# Browser: http://localhost:10350

# Access application
# Browser: https://app.budgetanalyzer.localhost

# Stop all services
tilt down
```

`./scripts/dev/verify-phase-7-static-manifests.sh` is the Phase 7 Session 6 local static guardrail gate and matches the dedicated `security-guardrails.yml` workflow closely enough for local reproduction. It also replays representative approved local Tilt `:tilt-<hash>` refs through Kyverno so the live deploy-time admission path stays covered. `./scripts/dev/verify-clean-tilt-deployment-admission.sh` is the host-side clean-start proof for the seven app deployments in `default` after `tilt up`. `./scripts/dev/verify-phase-7-security-guardrails.sh` is the final local Phase 7 completion command; it runs the static gate first and then `./scripts/dev/verify-phase-7-runtime-guardrails.sh` for the live Session 7 proof. CI stays static-only. `./scripts/dev/verify-security-prereqs.sh` is the Phase 0 baseline proof. `./scripts/dev/verify-phase-3-istio-ingress.sh` is the Phase 3 completion gate. `./scripts/dev/verify-phase-5-runtime-hardening.sh` is the Phase 5 completion gate and reruns the earlier phase verifiers as regressions. Browser login starts at the frontend route `/login`, which initiates OAuth2 through `/oauth2/authorization/idp` and returns through `/login/oauth2/code/idp`.

### Troubleshooting

**Quick commands**:
```bash
# Check pod status (services run in default namespace)
kubectl get pods

# Validate the Phase 0 platform baseline
./scripts/dev/verify-security-prereqs.sh

# View logs for a service
kubectl logs deployment/nginx-gateway

# Check NGINX configuration validity
kubectl exec deployment/nginx-gateway -- nginx -t

# View Istio ingress gateway logs
kubectl logs -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway

```

**For detailed troubleshooting**: When encountering specific issues (502 errors, CORS problems, connection refused, etc.), consult the comprehensive troubleshooting guide in [nginx/README.md](nginx/README.md)

## Workspace Structure

All repositories should be cloned side-by-side in a common parent directory:

```
/workspace/
├── .github/                    # Organization-level GitHub config (templates, profile README)
├── workspace/                  # Devcontainer entry point (clone this first)
├── orchestration/              # This repo - deployment coordination
├── session-gateway/            # Auth service (session lifecycle)
├── transaction-service/        # Transaction management
├── currency-service/           # Currency/exchange rates
├── permission-service/         # Internal roles/permissions
├── budget-analyzer-web/        # React frontend
├── service-common/             # Shared Java library
├── checkstyle-config/          # Shared checkstyle rules
├── architecture-conversations/ # Architectural discourse and patterns
└── claude-discovery/           # Experimental discovery tool
```

**Note**: The `.github` directory at workspace root is the [organization-level .github repository](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file) containing default issue/PR templates for all repos.

## Repository Structure

**Discovery**:
```bash
# View structure
tree -L 2 -I 'node_modules|target'
```

**Key directories**:
- [nginx/](nginx/) - Gateway configuration (dev and prod)
- [scripts/](scripts/) - Automation and tooling
- [docs/](docs/) - Architecture and cross-service documentation
- [kubernetes/](kubernetes/) - Production deployment manifests

## Service Repositories

Each microservice is maintained in its own repository:
- **service-common**: https://github.com/budgetanalyzer/service-common - Shared library for all backend services
- **transaction-service**: https://github.com/budgetanalyzer/transaction-service - Transaction management API
- **currency-service**: https://github.com/budgetanalyzer/currency-service - Currency and exchange rate API
- **budget-analyzer-web**: https://github.com/budgetanalyzer/budget-analyzer-web - React frontend application
- **session-gateway**: https://github.com/budgetanalyzer/session-gateway - OAuth2 authentication and session management
- **permission-service**: https://github.com/budgetanalyzer/permission-service - Internal roles/permissions resolution

## Best Practices

1. **Environment Parity**: Keep dev and prod configurations as similar as possible
2. **Configuration Management**: Use environment variables for configuration
3. **Health Checks**: All services expose health endpoints
4. **Service Independence**: Each microservice should be independently deployable
5. **API Versioning**: Version APIs to support backward compatibility
6. **Living Documentation**: Verify accuracy by running discovery commands

## NOTES FOR AI AGENTS

**Project Focus**: This reference architecture is complete. Current priorities are:
1. Documentation improvements and clarifications
2. Architectural discussions and pattern explanations
3. Bug fixes in existing functionality
4. NOT new features or data-ownership implementation

### Phase 7 Contract Freeze

- Use `docs/plans/security-hardening-v2-phase-7-session-1-contract.md` as the
  source of truth for Phase 7 image-pinning scope, local `:latest`
  exceptions, installer-hardening targets, and explicit exclusions.
- The executable Phase 7 image inventories live in
  `scripts/dev/lib/phase-7-image-pinning-targets.txt` and
  `scripts/dev/lib/phase-7-allowed-latest.txt`; keep them aligned with that
  contract doc.
- Only the seven documented local image repos may remain on `:latest` in
  checked-in manifests. Live Tilt deploys rewrite those same repos to immutable
  `:tilt-<hash>` refs and currently force `imagePullPolicy: IfNotPresent` on
  those managed deploys; treat every third-party `image:` or `FROM` ref as a
  digest-pinning target unless it is explicitly excluded in that contract doc.
- `tests/setup-flow` and `tests/security-preflight` are stale, non-gating
  Phase 7 assets until they are explicitly realigned to the current Istio-only
  baseline. Do not treat them as current completion gates.

**CRITICAL - Prerequisites First**: Before implementing any plan or feature:
1. Check for prerequisites in documentation (e.g., "Prerequisites: service-common Enhancement")
2. If prerequisites are NOT satisfied, STOP immediately and inform the user
3. Do NOT attempt to hack around missing prerequisites - this leads to broken implementations that must be deleted
4. Complete prerequisites first, then return to the original task

### Cross-Repo Boundaries

**Do NOT write code (Java, TypeScript, etc.) in sibling repositories.** This repo is the orchestrator — it coordinates, it doesn't implement service logic. When debugging cross-service issues, read sibling repos freely and only write to:
- This repository (orchestration)
- Documentation in sibling repos
- Configuration files (e.g., `application.yml`, manifests, env/config wiring) in sibling repos when fixing deployment/config issues

If a fix requires code changes in a service repo, describe the needed changes and let the user handle it (or switch to that repo's context).

### Planning Transparency

**Write plans to `docs/plans/`, not hidden locations.** When planning work:
- Create plan files in `docs/plans/` so they're visible and version-controlled
- Don't use ephemeral plan modes that hide work from the user
- Plans should be collaborative artifacts, not invisible scaffolding

### Autonomous AI Execution Pattern

**Key principle**: An effective technique for running AI agents is autonomous execution. Set clear success criteria, then run with `--dangerously-skip-permissions`.

**For detailed understanding of**:
- Why autonomous execution is essential for AI agents
- How the container sandbox makes this safe
- Docker access patterns (wormhole for TestContainers, true DinD for CI)
- Success criteria patterns and best practices

→ See [docs/architecture/autonomous-ai-execution.md](docs/architecture/autonomous-ai-execution.md)

### SSL/TLS Certificate Constraints

**NEVER run SSL write operations** - Claude runs in a container with its own mkcert CA, but the user's browser trusts their host's mkcert CA. These are different CAs, so certificates generated in Claude's sandbox will cause browser SSL warnings.

**Forbidden operations** (must be run by user on host):
- `mkcert` (any certificate generation)
- `openssl genrsa`, `openssl req -new`, `openssl x509 -req` (key/cert generation)
- Any script that generates certificates (e.g., `setup-k8s-tls.sh`, `setup-infra-tls.sh`)

**Allowed operations** (read-only):
- `openssl x509 -text -noout` (inspect certificates)
- `openssl verify` (verify certificate chains)
- `kubectl get secret -o yaml` (view secrets)
- Certificate file reads for debugging

When SSL issues occur, guide the user to run certificate scripts on their host machine.

When working on this project:
- Follow the resource-based routing pattern for new API endpoints
- Ensure Kubernetes configurations remain simple and maintainable
- Keep service independence - avoid tight coupling between services
- Each microservice lives in its own repository
- This orchestration repo coordinates deployment and environment setup
- All repositories should be cloned side-by-side in a common parent directory for cross-repo documentation links to work
- **Path Portability**: Never hardcode absolute paths like `/workspace`. The orchestration repo must work when cloned to any directory. Use relative paths or dynamic resolution (e.g., `config.main_dir` in Tiltfiles, `$(dirname "$0")` in shell scripts)
- Ignore all files in docs/archive and docs/decisions. Never change them, they are just for historical reference.

**NO GIT WRITE OPERATIONS**: Never run git commands (commit, push, checkout, reset, etc.) without explicit user request. The user controls git workflow entirely. You may suggest what to commit, but don't do it.

## Honest Discourse

Do not over-validate ideas. The user wants honest pushback, not agreement.

- If something seems wrong, say so directly
- Distinguish "novel" from "obvious in retrospect"
- Push back on vague claims — ask for concrete constraints
- Don't say "great question" or "that's a really interesting point"
- Skip the preamble and caveats — just answer
