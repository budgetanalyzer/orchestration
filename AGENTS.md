# Budget Analyzer - Orchestration Repository

## Tree Position

**Archetype**: coordinator  
**Scope**: budgetanalyzer ecosystem  
**Role**: system orchestrator; coordinates cross-cutting concerns and deployment

### Relationships
- Coordinates sibling repos through deployment patterns, documentation, and configuration changes
- Owns local platform orchestration, cross-repo operational conventions, and deployment policy

### Permissions
- **Read**: sibling repos via `../`
- **Write**: this repository; documentation and configuration in sibling repos when fixing deployment or environment issues
- **Do not write**: sibling service code from this repo context

### Discovery
```bash
# Sibling repos expected next to this repo
find .. -maxdepth 1 -mindepth 1 -type d \
  \( -name '*-service' -o -name 'session-gateway' -o -name 'budget-analyzer-web' -o -name 'service-common' -o -name 'workspace' \) \
  | sort

# Repo structure
tree -L 2 -I 'node_modules|target|.git'

# Live local platform state
tilt get uiresources
kubectl get pods -A
kubectl get svc -A
```

## Documentation Strategy

Keep `AGENTS.md` pattern-based and discovery-first. Prefer stable rules, discovery commands, and source-of-truth pointers over long inventories that drift.

Use `docs/OWNERSHIP.md` as the control surface for canonical documentation ownership. Update the owner doc first, then update summaries and cross-links.

When editing `AGENTS.md`, apply `docs/agents-md-checkstyle.md` as the active authoring standard. The rationale lives in `docs/decisions/003-pattern-based-claude-md.md`; consult that decision when changing the standard or resolving ambiguity.

Do not optimize `AGENTS.md` for token minimization alone. Keep useful orchestration-specific constraints and workflows, but compress repetition and link to the closer source of truth when one already exists.

Always update the nearest affected documentation in the same change:
- `AGENTS.md` when instructions, guardrails, discovery commands, or repo-specific workflow changes
- `README.md` when setup, usage, or repository purpose changes
- `docs/` when architecture, configuration, APIs, behaviors, or operational workflows change
- If the same detailed documentation is being copied across repos, stop and ask whether a centralized source of truth with links would be better

Treat `docs/archive/` as historical reference only. Do not update archived files.

Treat `docs/decisions/` as ADR context, not an active implementation surface. Do not modify decision files unless the user explicitly asks. Use `docs/agents-md-checkstyle.md` whenever `AGENTS.md` or similar AI context docs are edited.

## Code Exploration

NEVER use Agent/subagent tools for code exploration. Use grep/glob/read style commands directly.

Prefer discovery commands over static inventories:
- Use `rg` for text search
- Use `find` or `tree` for structure
- Use `sed`, `cat`, and targeted file reads for source-of-truth inspection
- Use runtime inspection commands such as `kubectl`, `tilt`, and `docker` when validating current state

## Operating Context

This repository coordinates the deployment and development environment for the Budget Analyzer application, a reference microservices architecture used as an open source learning resource for AI-assisted development.

This project is designed for AI-assisted development. The containerized development environment lives in the sibling `../workspace` repository; that repo owns the devcontainer configuration.

The default debugging model is split across host and container:
- Tilt runs on the host machine
- AI agents run inside the container
- The container has shared workspace access and full `kubectl` access to the host-managed cluster

Production target is Oracle Cloud Infrastructure Free Tier on ARM64:
- Shape: `VM.Standard.A1.Flex`
- Capacity: 4 OCPUs, 24 GB RAM
- OS baseline: Ubuntu 22.04 Minimal
- Region baseline: Phoenix
- Deployment model: single-node, production-grade demo environment

Architecture implications:
- All container images must support `linux/arm64`
- Local Tilt/Kind and OCI/k3s are both treated as production-grade deployment paths
- Observability remains internal-only in both environments

Architecture principles:
- Production parity between local Tilt/Kind and OCI/k3s
- Microservices with clear service boundaries and independent deployability
- Session-based edge authorization for browser security and session management
- Istio ingress handles ext_authz and auth-path throttling; NGINX handles API routing, backend/API rate limiting, and load balancing
- Resource-based routing keeps the frontend decoupled from service topology
- Defense in depth across Istio ingress, Session Gateway or NGINX, and downstream services
- Kubernetes-native development uses Tilt live update so code changes reach running pods quickly while the full security stack stays active; see `docs/development/local-environment.md#live-development-pipeline`

Technology pattern:
- Frontend: React web application
- Backends: Spring Boot + Java + Gradle
- Browser auth edge: Session Gateway (Spring WebFlux)
- External authorization: `ext-authz` Go service
- Edge and routing: Istio ingress/egress plus NGINX API gateway
- Infrastructure: PostgreSQL, Redis, RabbitMQ
- Monitoring: Prometheus, Grafana, Jaeger, Kiali

Service topology summary:
- Frontend: React web application for browser clients
- Backend workloads: Spring Boot microservices behind NGINX, plus Session Gateway and `ext-authz` on the auth and authorization path
- Infrastructure: PostgreSQL, Redis, and RabbitMQ in the `infrastructure` namespace; Redis `/data` is PVC-backed through the `redis-data` claim template
- Monitoring: Prometheus, Grafana, kube-state-metrics, the repo-managed Jaeger v2 backend, and standalone Kiali in `monitoring`; Jaeger and Kiali stay `ClusterIP`-only
- Ingress and egress: Istio ingress handles browser entry, `ext_authz`, and auth-path throttling; Istio egress stays `ClusterIP` with `REGISTRY_ONLY`
- Exact service ports and exposure rules live in `docs/architecture/port-reference.md`

Adding a new service:
- Create manifests in `kubernetes/services/{name}/`
- Register the service in `Tiltfile`
- Add NGINX routes when the service owns public resources
- See `docs/architecture/session-edge-authorization-pattern.md` and `nginx/README.md`

Version numbers and concrete dependency selections live in service repos, manifests, and checked-in release inputs, not in this file.

## Source Of Truth

Use the closest source of truth for the topic instead of expanding `AGENTS.md` with inventory detail.

- Documentation ownership map: `docs/OWNERSHIP.md`
- Reusable `AGENTS.md` authoring standard: `docs/agents-md-checkstyle.md`
- High-level system orientation: `docs/architecture/system-overview.md`
- Browser request flow, route ownership, and shared browser session contract: `docs/architecture/session-edge-authorization-pattern.md`
- Resource-based routing rules: `docs/architecture/resource-routing-pattern.md`
- Security posture and layered controls: `docs/architecture/security-architecture.md`
- Service ports and exposure rules: `docs/architecture/port-reference.md`
- Supported local happy path: `docs/development/getting-started.md`
- Local environment mechanics and live development pipeline: `docs/development/local-environment.md`
- Containerized dev environment setup: sibling `../workspace` repository
- Script directory map and canonical entry points: `scripts/README.md`
- NGINX routing patterns, adding resource routes, adding microservices, and gateway troubleshooting: `nginx/README.md`, `nginx/nginx.k8s.conf`, and `nginx/nginx.production.k8s.conf`
- Production overlays and OCI deployment inputs: `kubernetes/production/README.md`
- Observability topology and operator access model: `docs/architecture/observability.md`
- Unified `/api-docs` behavior: `docs-aggregator/README.md`
- Tilt debugging workflow: `docs/runbooks/tilt-debugging.md`

Useful discovery commands:
```bash
# List public and internal NGINX route declarations
rg -n "location .*(/api|/api-docs|/auth|/login|/oauth2|/logout)" \
  nginx/nginx.k8s.conf nginx/nginx.production.k8s.conf

# List Kubernetes manifests that define the core edge and security contracts
find kubernetes -maxdepth 2 -type f \
  \( -path 'kubernetes/gateway/*' -o -path 'kubernetes/istio/*' -o -path 'kubernetes/network-policies/*' \) \
  | sort

# Show deployed image refs in the current cluster
kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u
```

## Core Runtime Pattern

The primary request flow is:

```text
Browser -> Istio Ingress -> ext_authz validates session -> NGINX -> services
Auth paths -> Istio Ingress -> Session Gateway
```

Entry-point ownership:
- Browser auth lifecycle stays on the direct Session Gateway lane
- API traffic stays on the NGINX lane with ingress-layer `ext_authz`
- Exact route ownership and `/api-docs` behavior live in `docs/architecture/session-edge-authorization-pattern.md` and `docs-aggregator/README.md`

Session and identity rules:
- Session Gateway resolves roles and permissions from `permission-service` during session creation and owns browser session lifecycle on the direct auth lane
- Keep browser session logic on the direct `/auth/*` lane rather than pushing it through the general API path
- Exact browser endpoints and the shared Session Gateway/`ext_authz` contract live in `docs/architecture/session-edge-authorization-pattern.md`

Operational guardrails:
- Follow the resource-based routing pattern for new API endpoints
- Treat any new public `/api/...` route as incomplete until both `nginx/nginx.k8s.conf` and `nginx/nginx.production.k8s.conf` claim it and verification proves it does not fall through to the SPA
- Keep Spring Boot workloads on the startup/readiness/liveness probe pattern used by the checked-in manifests
- Keep PostgreSQL, RabbitMQ, and Redis on their repo-owned stateful deployment patterns
- Redis `/data` is PVC-backed. Do not treat pod replacement or `tilt down` as a Redis reset. Use `./scripts/ops/flush-redis.sh` for a logical reset, or recreate the cluster/runtime when a full clean state is required

Observability rules:
- Grafana, Prometheus, Jaeger, and Kiali are internal-only in both local Tilt and OCI/k3s
- Use loopback-only access for operators: raw `kubectl port-forward --address 127.0.0.1 ...` or `./scripts/ops/start-observability-port-forwards.sh`
- `./scripts/smoketest/verify-observability-port-forward-access.sh` is the focused access proof
- Do not introduce public observability hostnames
- Do not use `--address 0.0.0.0` for observability access
- Exact observability access commands, local ports, and Kiali auth flow live in `docs/architecture/observability.md`

## Development Workflow

Use the prerequisite script rather than guessing tool or environment state:

```bash
./scripts/bootstrap/check-tilt-prerequisites.sh
```

Supported local startup path:
- `docs/development/getting-started.md` owns the exact bootstrap and verifier sequence
- `tilt up` remains the supported full-stack entry point after the documented prerequisites are complete
- `docs/development/local-environment.md` owns live-update mechanics and mixed local-and-cluster workflow detail
- `scripts/README.md` owns the full verifier catalog and targeted capability checks

Primary operator entry points:
- App: `https://app.budgetanalyzer.localhost`
- Tilt UI: `http://localhost:10350`
- Unified API docs surface: `https://app.budgetanalyzer.localhost/api-docs`
- Observability helper: `./scripts/ops/start-observability-port-forwards.sh`

Use targeted verifiers from `scripts/README.md` when working on one capability such as monitoring, tracing, shared session contracts, rate limiting, or browser hardening.

Troubleshooting discovery:
```bash
kubectl get pods -A
kubectl logs deployment/nginx-gateway
kubectl exec deployment/nginx-gateway -- nginx -t
kubectl logs -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway
tilt get uiresources
kubectl config current-context
```

When the failure is routing-related, start with `nginx/README.md`. When the failure is cluster-behavior-related, start with `docs/runbooks/tilt-debugging.md` and the targeted scripts in `scripts/smoketest/`.

## GitHub Actions Baseline

This repository coordinates GitHub Actions workflow standards and upgrade planning across the Budget Analyzer repos.

Keep repository workflows on Node 24-ready action majors. In this repo that means:
- `actions/checkout@v6` for first-party checkout steps
- `docker/setup-qemu-action@v4`
- `docker/setup-buildx-action@v4`
- `docker/login-action@v4`
- `docker/build-push-action@v7`
- `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` at workflow scope

When workflow changes span multiple repos, coordinate the shared policy here and make repo-local workflow edits in the owning repos as needed.

## Project Priorities

This reference architecture is functionally complete. Current priorities are:
1. Documentation improvements and clarifications
2. Architectural discussions and pattern explanations
3. Bug fixes in existing functionality
4. Not net-new features or data-ownership implementation

## Shell Script Validation

When adding or modifying shell scripts in this repo, always validate them before considering the work complete:

1. `bash -n <script>`
2. `shellcheck <script>`

Fix all errors and warnings before finishing. Do not suppress a ShellCheck warning without an in-file `# shellcheck disable=SC####` justification comment.

## Prerequisites First

Before implementing a plan or feature:
1. Check the relevant documentation for prerequisites
2. If prerequisites are missing, stop and call that out
3. Do not hack around a missing prerequisite with orchestration-level compensating changes
4. Complete prerequisites first, then return to the requested work

## Image Pinning And Supply Chain Guardrails

- Treat checked-in third-party image refs and Dockerfile base images as digest-pinning targets unless an exception is explicitly documented in the executable inventories
- The executable inventories live in `scripts/lib/phase-7-image-pinning-targets.txt` and `scripts/lib/phase-7-allowed-latest.txt`
- Keep those inventories aligned with the static security guardrail checks
- Only the documented local image repos may remain on `:latest` in checked-in manifests
- Live Tilt deploys rewrite those same repos to immutable `:tilt-<hash>` refs and currently force `imagePullPolicy: IfNotPresent` on those managed deploys
- Treat every third-party `image:` or `FROM` ref as a digest-pinning target unless it is explicitly excluded in the inventories
- `tests/setup-flow` and `tests/security-preflight` are stale, non-gating retained assets until they are explicitly realigned to the current Istio-only baseline. Do not treat them as current completion gates

## Cross-Repo Boundaries

Do NOT write code in sibling repositories from this repo context.

Allowed write surface from this repo:
- This repository
- Documentation in sibling repos
- Configuration in sibling repos when fixing deployment, environment, or manifest wiring issues

If a fix requires service logic changes in a sibling repo:
- Stop
- Describe the needed service-side change clearly
- Let the user handle it, or switch to that repo's context

Do not hide sibling-repo contract failures with orchestration workarounds.

Example: if Spring Boot services fail to expose `/actuator/prometheus` and that contract belongs in `service-common`, fix or rebuild `service-common`. Do not patch orchestration manifests with compensating `MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health,prometheus` overrides just to hide the defect.

## Production-Grade Parity

Treat both supported runtime paths, local Tilt/Kind and OCI/k3s, as production-grade microservices deployments.

Do not present the following as durable fixes:
- manual live-cluster drift
- security bypasses
- relaxed policies
- untracked Helm overrides
- degraded persistence such as replacing StatefulSets with `emptyDir`
- orchestration-level compensations for service-owned defects

Temporary recovery commands are acceptable only when clearly labeled as diagnostics or incident-recovery steps. Every durable fix must be repo-owned, repeatable from scripts/manifests, documented in the affected runbook or plan, and verified with the relevant smoke or guardrail checks.

## Planning Transparency

Write plans to `docs/plans/`, not hidden locations.

Plans should be visible, version-controlled collaboration artifacts. Do not hide meaningful project planning in ephemeral or private planning mechanisms.

## Autonomous AI Execution Pattern

The preferred AI execution pattern in this repo is autonomous execution with clear success criteria. For rationale, safety model, Docker access patterns, and examples, see `docs/architecture/autonomous-ai-execution.md`.

## SSL/TLS Certificate Constraints

NEVER run SSL write operations from the AI container.

The container has its own `mkcert` CA, but the user's browser trusts the host CA. Certificates generated inside the container will cause browser trust failures.

Forbidden operations that must be run by the user on the host:
- `mkcert`
- `openssl genrsa`
- `openssl req -new`
- `openssl x509 -req`
- Any script that generates browser or infrastructure certificates, including `scripts/bootstrap/setup-k8s-tls.sh` and `scripts/bootstrap/setup-infra-tls.sh`

Allowed read-only operations:
- `openssl x509 -text -noout`
- `openssl verify`
- `kubectl get secret -o yaml`
- Certificate file reads for debugging

When SSL issues occur, guide the user to run the certificate scripts on the host.

## Path Portability

Never hardcode absolute workspace paths such as `/workspace`.

Use relative paths or dynamically resolved paths instead:
- `../service-common`
- `$(dirname "$0")`
- Tilt variables such as `config.main_dir`

All repositories are expected to be cloned side-by-side under a common parent directory so cross-repo relative references continue to work.

## Historical Docs

Ignore `docs/archive/` for active implementation work.

Use `docs/decisions/` for context and rationale, not as an implementation surface. Do not edit decision records unless explicitly asked.

## NO GIT WRITE OPERATIONS

Never run git write commands such as `commit`, `push`, `checkout`, `reset`, or branch manipulation without explicit user request. The user owns git workflow entirely.

## Honest Discourse

Do not over-validate ideas. The user wants honest pushback, not agreement.

- If something seems wrong, say so directly
- Distinguish novel ideas from ideas that are obvious in retrospect
- Push back on vague claims and ask for concrete constraints
- Skip empty praise and filler
