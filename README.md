# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

[![Security Guardrails](https://github.com/budgetanalyzer/orchestration/actions/workflows/security-guardrails.yml/badge.svg)](https://github.com/budgetanalyzer/orchestration/actions/workflows/security-guardrails.yml)

This repo is the control plane for Budget Analyzer. It contains every Kubernetes manifest, Tilt workflow, Istio mesh configuration, network policy, monitoring stack, and deployment script needed to run the full platform — locally or in production — from a single `tilt up`.

## What makes this interesting

**One set of manifests, two environments.** The Kubernetes manifests under `kubernetes/services/` are the same ones that run in production. The production overlay (`kubernetes/production/apps/`) patches in pinned image digests and removes `imagePullPolicy: Never` — that's it. Infrastructure (PostgreSQL, Redis, RabbitMQ) follows the same pattern: production reuses the shared baseline and patches only storage sizing. Everything else — service accounts, deployments, services, network policies, Istio security policies — is identical.

**Live code reload inside a real Kubernetes cluster.** Edit a Spring Boot service or the React frontend locally, and Tilt syncs the change into a running pod in seconds. Java services get a recompiled JAR synced and process-restarted; the React frontend gets sub-second Vite HMR. Changes to the shared library (`service-common`) automatically cascade to all downstream services. This all happens while the full production stack stays active: Istio mTLS between services, network policies enforcing least-privilege pod communication, ext_authz session validation at the ingress, and Kyverno admission policies guarding workload security contexts.

**AI agents can debug the full stack.** The development environment runs inside a sandboxed Docker container ([workspace](https://github.com/budgetanalyzer/workspace)) that has kubectl, helm, tilt, and host-network access to the Kind cluster. An AI coding agent operating in this container can inspect pods, read logs, restart deployments, run tests, and trace requests through the mesh — the same workflow a human operator would use, with no special tooling or adapters.

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
./setup.sh    # bootstrap Kind cluster, install dependencies
tilt up       # start everything
```

See [Getting Started](docs/development/getting-started.md) for the full setup walkthrough.

Once the stack is running:

| | |
|---|---|
| App | `https://app.budgetanalyzer.localhost` |
| Tilt UI | `http://localhost:10350` |
| API docs | `https://app.budgetanalyzer.localhost/api-docs` |

## Documentation

- [Getting Started](docs/development/getting-started.md) — setup walkthrough
- [Local Environment Mechanics](docs/development/local-environment.md) — live update pipeline, mixed workflows
- [Service-Common Artifact Resolution](docs/development/service-common-artifact-resolution.md) — local vs. GitHub Packages
- [Architecture Overview](docs/architecture/system-overview.md)
- [Observability Architecture](docs/architecture/observability.md)
- [Production Deployment](deploy/README.md) — OCI bootstrap scripts and operator runbook

## Service Repositories

- [service-common](https://github.com/budgetanalyzer/service-common) — Shared library
- [transaction-service](https://github.com/budgetanalyzer/transaction-service) — Transaction API
- [currency-service](https://github.com/budgetanalyzer/currency-service) — Currency API
- [budget-analyzer-web](https://github.com/budgetanalyzer/budget-analyzer-web) — React frontend
- [session-gateway](https://github.com/budgetanalyzer/session-gateway) — OAuth2 authentication and session management

## License

MIT
