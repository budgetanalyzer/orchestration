# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

## Architecture Boundaries

This project demonstrates production-grade patterns:

- **Authentication**: OAuth2/OIDC with Auth0, session-based edge authorization, session management
- **API Gateway**: Session validation (ext_authz), auth-path throttling at Istio ingress, API routing and API-path throttling at NGINX
- **Microservices**: Spring Boot, Kubernetes, Tilt local development

## Live Development in Kubernetes

Edit code locally. Changes reach the running Kubernetes pod in seconds — without image rebuilds or pod restarts — while the full production stack (Istio mTLS, network policies, ext_authz, TLS infrastructure) stays active.

- **Java services**: Gradle compiles on the host, Tilt syncs the JAR into the pod and restarts the process
- **React frontend**: Tilt syncs source files, Vite HMR hot-patches the browser (sub-second)
- **Shared library**: Changes to `service-common` automatically cascade to all downstream services

This avoids the usual tradeoff between fast local development and production-faithful Kubernetes environments. See [Live Development Pipeline](docs/development/local-environment.md#live-development-pipeline) for details.

## Quick Start

[Getting Started](docs/development/getting-started.md) owns the supported local
startup checklist. It is the only setup doc that should be treated as the
happy-path `./setup.sh` and `tilt up` flow.

For deeper detail, use the owner docs directly:

- [Local Environment Mechanics](docs/development/local-environment.md) - live
  update, mixed local-and-cluster workflows, and environment internals
- [Service-Common Artifact Resolution](docs/development/service-common-artifact-resolution.md)
  - local credential-free artifact flow versus GitHub Packages
- [Tilt/Kind Manual Deep Dive](docs/tilt-kind-setup-guide.md) - manual
  bootstrap internals only; not the default onboarding path
- [Scripts Directory](scripts/README.md) - verifier catalog and operational
  entry points

Common operator entry points after the stack is healthy:

- app: `https://app.budgetanalyzer.localhost`
- Tilt UI: `http://localhost:10350`
- unified API docs: `https://app.budgetanalyzer.localhost/api-docs`
- observability helper:
  `./scripts/ops/start-observability-port-forwards.sh`

Exact `/api-docs` behavior lives in
[docs-aggregator/README.md](docs-aggregator/README.md). Exact observability
access commands and operator posture live in
[Observability Architecture](docs/architecture/observability.md).

## Documentation

- [Documentation Ownership](docs/OWNERSHIP.md)
- [AGENTS.md Checkstyle](docs/agents-md-checkstyle.md)
- [Getting Started](docs/development/getting-started.md)
- [Local Environment Mechanics](docs/development/local-environment.md)
- [Tilt/Kind Manual Deep Dive](docs/tilt-kind-setup-guide.md)
- [Architecture Overview](docs/architecture/system-overview.md)
- [Observability Architecture](docs/architecture/observability.md)
- [Development Guide](AGENTS.md)

## Service Repositories

- [service-common](https://github.com/budgetanalyzer/service-common) - Shared library
- [transaction-service](https://github.com/budgetanalyzer/transaction-service) - Transaction API
- [currency-service](https://github.com/budgetanalyzer/currency-service) - Currency API
- [budget-analyzer-web](https://github.com/budgetanalyzer/budget-analyzer-web) - React frontend
- [session-gateway](https://github.com/budgetanalyzer/session-gateway) - OAuth2 authentication and session management

## License

MIT
