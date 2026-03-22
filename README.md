# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

## Architecture Boundaries

This project demonstrates production-grade patterns:

- **Authentication**: OAuth2/OIDC with Auth0, BFF pattern, session management
- **API Gateway**: Session validation (ext_authz), routing, rate limiting (NGINX + Envoy)
- **Microservices**: Spring Boot, Kubernetes, Tilt local development

It intentionally leaves unsolved:

- **Data ownership**: Which transactions belong to which user?
- **Cross-service user scoping**: How does transaction-service know to filter by owner?
- **Multi-tenancy**: Organization-level data isolation

This boundary is deliberate. Data ownership is domain-specific and opinionated - we surface the problem rather than prescribing a solution. We're more interested in discussing these patterns with other architects than generating more code.

## Quick Start

See [Getting Started](docs/development/getting-started.md) for complete setup instructions.

Current local platform baseline:
- `setup.sh` bootstraps a Kind cluster with `disableDefaultCNI` and pinned Calico so `NetworkPolicy` is actually enforceable.
- Tilt now generates local bootstrap and per-service infrastructure secrets from `.env`; Kubernetes manifests only consume named secrets so production can replace the source later.
- PostgreSQL uses `postgres_admin` plus per-service database users, RabbitMQ uses `rabbitmq-admin` plus `currency-service`, and Redis uses ACL users instead of one shared password.
- After `tilt up`, run `./scripts/dev/verify-security-prereqs.sh` to prove the Phase 0 platform prerequisites are active, then `./scripts/dev/verify-phase-1-credentials.sh` to prove Phase 1 credential isolation.

## Documentation

- [Getting Started](docs/development/getting-started.md)
- [Architecture Overview](docs/architecture/system-overview.md)
- [Development Guide](AGENTS.md)

## Service Repositories

- [service-common](https://github.com/budgetanalyzer/service-common) - Shared library
- [transaction-service](https://github.com/budgetanalyzer/transaction-service) - Transaction API
- [currency-service](https://github.com/budgetanalyzer/currency-service) - Currency API
- [budget-analyzer-web](https://github.com/budgetanalyzer/budget-analyzer-web) - React frontend
- [session-gateway](https://github.com/budgetanalyzer/session-gateway) - Authentication BFF

## License

MIT
