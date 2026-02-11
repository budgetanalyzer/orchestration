# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

## Architecture Boundaries

This project demonstrates production-grade patterns:

- **Authentication**: OAuth2/OIDC with Auth0, BFF pattern, session management
- **Authorization Infrastructure**: Roles, permissions, delegations (permission-service)
- **API Gateway**: JWT validation, routing, rate limiting (NGINX + Envoy)
- **Microservices**: Spring Boot, Kubernetes, Tilt local development

It intentionally leaves unsolved:

- **Data ownership**: Which transactions belong to which user?
- **Cross-service user scoping**: How does transaction-service know to filter by owner?
- **Multi-tenancy**: Organization-level data isolation

This boundary is deliberate. Data ownership is domain-specific and opinionated - we surface the problem rather than prescribing a solution. We're more interested in discussing these patterns with other architects than generating more code.

## Quick Start

See [Getting Started](docs/development/getting-started.md) for complete setup instructions.

## Documentation

- [Getting Started](docs/development/getting-started.md)
- [Architecture Overview](docs/architecture/system-overview.md)
- [Development Guide](AGENTS.md)

## Service Repositories

- [service-common](https://github.com/budgetanalyzerllc/service-common) - Shared library
- [transaction-service](https://github.com/budgetanalyzerllc/transaction-service) - Transaction API
- [currency-service](https://github.com/budgetanalyzerllc/currency-service) - Currency API
- [budget-analyzer-web](https://github.com/budgetanalyzerllc/budget-analyzer-web) - React frontend
- [session-gateway](https://github.com/budgetanalyzerllc/session-gateway) - Authentication BFF
- [token-validation-service](https://github.com/budgetanalyzerllc/token-validation-service) - JWT validation
- [permission-service](https://github.com/budgetanalyzerllc/permission-service) - Permissions API

## License

MIT
