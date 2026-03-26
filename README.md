# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

## Architecture Boundaries

This project demonstrates production-grade patterns:

- **Authentication**: OAuth2/OIDC with Auth0, BFF pattern, session management
- **API Gateway**: Session validation (ext_authz), auth-path throttling at Istio ingress, API routing and API-path throttling at NGINX
- **Microservices**: Spring Boot, Kubernetes, Tilt local development

It intentionally leaves unsolved:

- **Data ownership**: Which transactions belong to which user?
- **Cross-service user scoping**: How does transaction-service know to filter by owner?
- **Multi-tenancy**: Organization-level data isolation

This boundary is deliberate. Data ownership is domain-specific and opinionated - we surface the problem rather than prescribing a solution. We're more interested in discussing these patterns with other architects than generating more code.

## Live Development in Kubernetes

Edit code locally. Changes reach the running Kubernetes pod in seconds — without image rebuilds or pod restarts — while the full production stack (Istio mTLS, network policies, ext_authz, TLS infrastructure) stays active.

- **Java services**: Gradle compiles on the host, Tilt syncs the JAR into the pod and restarts the process
- **React frontend**: Tilt syncs source files, Vite HMR hot-patches the browser (sub-second)
- **Shared library**: Changes to `service-common` automatically cascade to all downstream services

This avoids the usual tradeoff between fast local development and production-faithful Kubernetes environments. See [Live Development Pipeline](docs/development/local-environment.md#live-development-pipeline) for details.

## Quick Start

See [Getting Started](docs/development/getting-started.md) for complete setup instructions.

Current local platform baseline:
- `setup.sh` now deletes any existing `kind` cluster and recreates it with `disableDefaultCNI` plus pinned Calico so `NetworkPolicy` is actually enforceable.
- `setup.sh` also ensures a supported Helm `3.20.x` toolchain is installed before continuing.
- `setup.sh` now refreshes the existing `istio` Helm repo index on every run so fresh-cluster rebuilds pick up new pinned chart versions instead of reusing stale host-side metadata.
- Tilt now installs `istio/cni` and enables `pilot.cni.enabled=true` for `istiod`, so meshed workloads can be reinjected without `istio-init` before broader Phase 5 Pod Security enforcement.
- Tilt now pins Gateway API CRDs to `v1.4.0` and Istio Helm charts to `1.29.1`; ingress hardening is declared through Gateway `spec.infrastructure.parametersRef`, and the egress gateway installs directly from `istio/gateway` again using checked-in Helm values.
- Tilt now generates local bootstrap and per-service infrastructure secrets from `.env`; Kubernetes manifests only consume named secrets so production can replace the source later.
- `setup.sh` now also runs `./scripts/dev/setup-infra-tls.sh` to generate the internal `infra-ca` and `infra-tls-*` TLS secrets for Redis, PostgreSQL, and RabbitMQ. Run that script standalone only when you need to regenerate the transport-TLS material.
- Redis is now TLS-only in-cluster; verification and session seeding scripts connect through `infra-ca`, and direct service boot runs must enable Redis SSL with that CA bundle.
- PostgreSQL uses `postgres_admin` plus per-service database users, RabbitMQ uses `rabbitmq-admin` plus `currency-service`, and Redis uses ACL users instead of one shared password.
- After `tilt up`, run `./scripts/dev/verify-security-prereqs.sh` to prove the Phase 0 platform baseline, `./scripts/dev/verify-phase-1-credentials.sh` for Phase 1 credential isolation, `./scripts/dev/verify-phase-4-transport-encryption.sh` as the Phase 4 transport-TLS completion gate, `./scripts/dev/verify-phase-3-istio-ingress.sh` as the Phase 3 Istio ingress/egress completion gate, `./scripts/dev/verify-phase-5-runtime-hardening.sh` as the Phase 5 runtime-hardening and final PSA completion gate, `./scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` for the Phase 6 Session 7 API rate-limit identity proof, and `./scripts/dev/verify-phase-6-edge-browser-hardening.sh` as the Phase 6 completion gate.

Treat Phase 5 as complete only after `./scripts/dev/verify-phase-5-runtime-hardening.sh` passes. Treat Phase 4 as complete only after `./scripts/dev/verify-phase-4-transport-encryption.sh` passes, and treat Phase 3 as complete only after `./scripts/dev/verify-phase-3-istio-ingress.sh` plus the live validation checklist pass. Treat Phase 6 as complete only after `./scripts/dev/verify-phase-6-edge-browser-hardening.sh` passes and the manual browser-console validation on `/_prod-smoke/` is done; `/api/docs` probes now stay visible as warnings instead of blocking completion.

Auth entrypoints are split intentionally: `/login` is the frontend login page, `/oauth2/authorization/idp` starts OAuth2, and Auth0 returns to `/login/oauth2/code/idp`.
The local `/_prod-smoke/` verification path is a separate Tilt `local_resource`: it runs `npm run build:prod-smoke` in the sibling `budget-analyzer-web` repo, so that repo needs local npm dependencies installed (`npm install`) in addition to the normal frontend container image build.

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
