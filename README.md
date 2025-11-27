# Budget Analyzer

A reference architecture for microservices, built as an open-source learning resource for architects exploring AI-assisted development.

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

**For development environment setup**, use the [workspace](https://github.com/budgetanalyzer/workspace) repository. That's where the devcontainer configuration lives.

Once in the devcontainer:

```bash
cd /workspace/orchestration
./setup.sh   # Will tell you if prerequisites are missing
tilt up
```

Open https://app.budgetanalyzer.localhost

API Documentation: https://api.budgetanalyzer.localhost/api/docs

## Documentation

- [Getting Started](docs/development/getting-started.md)
- [Architecture Overview](docs/architecture/system-overview.md)
- [Development Guide](CLAUDE.md)

## Service Repositories

- [service-common](https://github.com/budgetanalyzer/service-common) - Shared library
- [transaction-service](https://github.com/budgetanalyzer/transaction-service) - Transaction API
- [currency-service](https://github.com/budgetanalyzer/currency-service) - Currency API
- [budget-analyzer-web](https://github.com/budgetanalyzer/budget-analyzer-web) - React frontend
- [session-gateway](https://github.com/budgetanalyzer/session-gateway) - Authentication BFF
- [token-validation-service](https://github.com/budgetanalyzer/token-validation-service) - JWT validation
- [permission-service](https://github.com/budgetanalyzer/permission-service) - Permissions API

## License

MIT
