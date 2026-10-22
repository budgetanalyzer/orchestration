# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

[![Security Guardrails](https://github.com/budgetanalyzer/orchestration/actions/workflows/security-guardrails.yml/badge.svg)](https://github.com/budgetanalyzer/orchestration/actions/workflows/security-guardrails.yml)

This repo is the control plane for Budget Analyzer. It contains the Kubernetes
manifests, Tilt workflow, Istio mesh configuration, network policy, monitoring
stack, and offline production reference used to coordinate the platform. Local
Kind/Tilt is the live validation target; no production environment is currently
configured.

## What makes this interesting

**One shared manifest base, two deployment shapes.** The production reference
reuses the Kubernetes manifests under `kubernetes/services/`, patches in pinned
image digests, and uses the same stateful infrastructure baseline with a narrow
storage-size override. The overlays are maintained and checked offline while
Kind/Tilt proves the live local path.

**Live code reload inside a real Kubernetes cluster.** Edit a Spring Boot service or the React frontend locally, and Tilt syncs the change into a running pod in seconds. Java services get a recompiled JAR synced and process-restarted; the React frontend gets sub-second Vite HMR. Changes to the shared library (`service-common`) automatically cascade to all downstream services. This all happens while the full security stack stays active: Istio mTLS between services, network policies enforcing least-privilege pod communication, ext_authz session validation at the ingress, and Kyverno admission policies guarding workload security contexts.

**AI agents can debug the full stack.** Orchestration's
[application authority contract](docs/architecture/autonomous-ai-execution.md)
defines the exact local Kind target, local credentials and production
exclusions. The optional
[workspace environment](../workspace/docs/host-isolation.md) owns development-VM
provisioning, agent tooling, host isolation and personal-host transport.

**Production architecture remains reviewable offline.** The `deploy/`
directory renders provider-neutral routing, infrastructure, and observability
references without cloud configuration or cluster access. `archive/oci/`
contains the lean set of removed OCI files; its owner README points to the
complete tagged Git history. Neither is an active deployment path.

## Architecture

- **Frontend**: React/Vite (budget-analyzer-web), served through NGINX in the production reference, Vite dev server locally
- **API Gateway**: NGINX handles resource routing; Istio ingress handles TLS termination and per-client auth/API rate limiting
- **Auth**: OAuth2/OIDC with Auth0 via session-gateway, edge session validation via ext-authz (Go), Redis-backed sessions
- **Backend**: Spring Boot microservices (transaction-service, currency-service, permission-service) with PostgreSQL, RabbitMQ
- **Service mesh**: Istio with strict mTLS, network policies, egress gateway for external API calls
- **Observability**: Prometheus, Grafana, Jaeger, Kiali

## Quick Start

```bash
# After installing Docker and preparing the three ingress TLS files:
./setup.sh
tilt up
```

Run `scripts/bootstrap/renew-host-ingress-tls.sh` on the machine whose browser
will be used; if Kind runs elsewhere, place the three published files in that
machine's `nginx/certs/k8s/` directory. `setup.sh` installs the pinned platform
tools, validates those files, recreates Kind and reconciles the ingress Secret.
For daily startup, run `scripts/bootstrap/check-local-runtime.sh` and then
`tilt up` instead of rebuilding the cluster.

The application development runtime is Ubuntu Linux; orchestration's CI does
not claim native macOS or Windows setup support. Other personal-host operating
systems can use the optional workspace development VM.

See [Getting Started](docs/development/getting-started.md) for the full setup walkthrough.

Once the stack is running, orchestration publishes these entry points on local
loopback:

| | |
|---|---|
| App | `https://app.budgetanalyzer.localhost` |
| Tilt UI | `http://localhost:10350` |
| API docs | `https://app.budgetanalyzer.localhost/api-docs` |

In the optional workspace development VM, VM-loopback availability does not
make these URLs available on the personal host. Follow the [end-to-end local workflow](docs/development/getting-started.md#operator-entry-points)
and workspace's [personal-host access contract](../workspace/docs/host-isolation.md#personal-host-access)
for the default combined application/Tilt host tunnel. Observability requires
the separate orchestration guest publication helper and remains an optional
second host tunnel.

## Documentation

- [Getting Started](docs/development/getting-started.md) — self-contained application setup and daily startup
- [Personal-Host Access](../workspace/docs/host-isolation.md#personal-host-access) — workspace-owned host tunnel and host-loopback transport
- [Local Environment Mechanics](docs/development/local-environment.md) — live update pipeline, mixed workflows
- [Host Isolation Audit](../workspace/docs/host-isolation-audit.md) — workspace-owned human-only host evidence collection and security review
- [Service-Common Artifact Resolution](docs/development/service-common-artifact-resolution.md) — local vs. GitHub Packages
- [Architecture Overview](docs/architecture/system-overview.md)
- [Observability Architecture](docs/architecture/observability.md)
- [Production Reference](deploy/README.md) — provider-neutral offline renders and deployment prerequisites
- [Retired OCI Archive](archive/oci/README.md) — lean removed-file inventory, tagged history, and restoration caveats
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
