# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

[![Security Guardrails](https://github.com/budgetanalyzer/orchestration/actions/workflows/security-guardrails.yml/badge.svg)](https://github.com/budgetanalyzer/orchestration/actions/workflows/security-guardrails.yml)

This repo is the control plane for Budget Analyzer. It contains every Kubernetes manifest, Tilt workflow, Istio mesh configuration, network policy, monitoring stack, and deployment script needed to run the full platform — locally or in production — from a single `tilt up`.

## What makes this interesting

**One set of manifests, two environments.** The Kubernetes manifests under `kubernetes/services/` are the same ones that run in production. The production overlay (`kubernetes/production/apps/`) patches in pinned image digests and removes `imagePullPolicy: Never` — that's it. Infrastructure (PostgreSQL, Redis, RabbitMQ) follows the same pattern: production reuses the shared baseline and patches only storage sizing. Everything else — service accounts, deployments, services, network policies, Istio security policies — is identical.

**Live code reload inside a real Kubernetes cluster.** Edit a Spring Boot service or the React frontend locally, and Tilt syncs the change into a running pod in seconds. Java services get a recompiled JAR synced and process-restarted; the React frontend gets sub-second Vite HMR. Changes to the shared library (`service-common`) automatically cascade to all downstream services. This all happens while the full production stack stays active: Istio mTLS between services, network policies enforcing least-privilege pod communication, ext_authz session validation at the ingress, and Kyverno admission policies guarding workload security contexts.

**AI agents can debug the full stack.** The selected target runs agents directly
in a dedicated development VM, with repeatable tooling owned by
[workspace](https://github.com/budgetanalyzer/workspace). Repositories, the
normal guest home, Docker and Kind stay guest-local while GitHub publication
remains on the personal host. Former guest-specific and personal-host agent
runtimes are retired and must not be reconstructed. The
[boundary contract](docs/architecture/autonomous-ai-execution.md) explains the
target, and workspace's [host-isolation audit](../workspace/docs/host-isolation-audit.md)
owns the human-only firewall and confinement evidence workflow.

**Production deployment is documented and scripted.** The `deploy/` directory contains the complete, numbered script sequence to bootstrap a k3s cluster on OCI from scratch — Istio mesh, cert-manager with ACME HTTP-01, OCI Vault secret synchronization via External Secrets Operator, Kyverno admission policies, Prometheus/Grafana monitoring, Jaeger tracing, and public TLS. Every step produces reviewable rendered YAML under `tmp/` before anything touches the cluster.

## Architecture

- **Frontend**: React/Vite (budget-analyzer-web), served through NGINX in production, Vite dev server locally
- **API Gateway**: NGINX handles routing and API-path rate limiting; Istio ingress handles TLS termination and auth-path rate limiting
- **Auth**: OAuth2/OIDC with Auth0 via session-gateway, edge session validation via ext-authz (Go), Redis-backed sessions
- **Backend**: Spring Boot microservices (transaction-service, currency-service, permission-service) with PostgreSQL, RabbitMQ
- **Service mesh**: Istio with strict mTLS, network policies, egress gateway for external API calls
- **Observability**: Prometheus, Grafana, Jaeger, Kiali

## Quick Start

```bash
# After the workspace-owned VM, repositories, native tools and trust are ready:
./scripts/bootstrap/check-agent-vm-prerequisites.sh
./setup.sh
tilt up
```

The native development VM is the supported agent environment. Workspace owns
its human provisioning, repository transport, native tools, guest Docker and
OS/NSS trust. Orchestration's first-bootstrap path validates the approved
host-created ingress files, recreates the local Kind cluster and reconciles the
ingress Secret. It is not a daily start command; ordinary work uses the
read-only `--native-runtime` preflight and `tilt up`.

The application development runtime is Ubuntu Linux. A personal host may use a
different OS only if the workspace-owned VM, SSH, browser-forwarding and
certificate-transfer contract supports it; orchestration's CI does not claim
native macOS or Windows setup support.

See [Getting Started](docs/development/getting-started.md) for the full setup walkthrough.

Once the stack is running, orchestration publishes these entry points on VM
loopback:

| | |
|---|---|
| App | `https://app.budgetanalyzer.localhost` |
| Tilt UI | `http://localhost:10350` |
| API docs | `https://app.budgetanalyzer.localhost/api-docs` |

VM-loopback availability does not make these URLs available on the personal
host. Follow the [end-to-end local workflow](docs/development/getting-started.md#operator-entry-points)
and workspace's [personal-host access contract](../workspace/docs/host-isolation.md#personal-host-access)
for the default combined application/Tilt host tunnel. Observability requires
the separate orchestration guest publication helper and remains an optional
second host tunnel.

## Documentation

- [Getting Started](docs/development/getting-started.md) — native VM application setup walkthrough
- [Personal-Host Access](../workspace/docs/host-isolation.md#personal-host-access) — workspace-owned host tunnel and host-loopback transport
- [Local Environment Mechanics](docs/development/local-environment.md) — live update pipeline, mixed workflows
- [Host Isolation Audit](../workspace/docs/host-isolation-audit.md) — workspace-owned human-only host evidence collection and security review
- [Service-Common Artifact Resolution](docs/development/service-common-artifact-resolution.md) — local vs. GitHub Packages
- [Architecture Overview](docs/architecture/system-overview.md)
- [Observability Architecture](docs/architecture/observability.md)
- [Production Deployment](deploy/README.md) — OCI bootstrap scripts and operator runbook
- [Dependency Automation](docs/dependency-automation.md) — production Renovate policy, graph and scanner workflows, bounded evidence artifacts, cost constraints, and failure triage

## Service Repositories

This repository deploys the services below, but their application source lives
in sibling repositories. `ext-authz` is deployed by orchestration while its Go
source, Dockerfile, tests, and release workflow live in its own repo.

- [service-common](https://github.com/budgetanalyzer/service-common) — Shared library
- [transaction-service](https://github.com/budgetanalyzer/transaction-service) — Transaction API
- [currency-service](https://github.com/budgetanalyzer/currency-service) — Currency API
- [budget-analyzer-web](https://github.com/budgetanalyzer/budget-analyzer-web) — React frontend
- [session-gateway](https://github.com/budgetanalyzer/session-gateway) — OAuth2 authentication and session management
- [ext-authz](https://github.com/budgetanalyzer/ext-authz) — Go external authorization service for Istio ingress

## License

MIT
