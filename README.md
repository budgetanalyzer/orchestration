# Budget Analyzer Orchestration

> "Archetype: coordinator. Role: System orchestrator; coordinates cross-cutting concerns and deployment."
>
> — [AGENTS.md](AGENTS.md#tree-position)

## Architecture Boundaries

This project demonstrates production-grade patterns:

- **Authentication**: OAuth2/OIDC with Auth0, session-based edge authorization, session management
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

Once the stack is running, the public API docs surface is split intentionally
on the same origin:
`/api-docs` is the human-readable Swagger UI page, while
`/api-docs/openapi.json` and `/api-docs/openapi.yaml` remain the
machine-readable unified contracts for direct download or tooling.
The docs route uses a dedicated docs-only relaxed CSP because the stock Swagger
UI bundle is not strict-CSP-compatible. The main app and `/api/*` routes keep
their strict CSP posture. The docs route is public, read-only, and serves
self-hosted Swagger UI assets — no CDN dependency.

Current local platform baseline:
- `setup.sh` now deletes any existing `kind` cluster and recreates it with `disableDefaultCNI` plus pinned Calico so `NetworkPolicy` is actually enforceable.
- `setup.sh` also ensures a supported Helm `3.20.x` toolchain is installed from a pinned verified release before continuing.
- `setup.sh` now refreshes the existing `istio` Helm repo index on every run so fresh-cluster rebuilds pick up new pinned chart versions instead of reusing stale host-side metadata.
- `setup.sh` now also refreshes the `prometheus-community` Helm repo index so the pinned `kube-prometheus-stack` chart metadata is available before Tilt installs the monitoring stack.
- Tilt now installs `istio/cni` and enables `pilot.cni.enabled=true` for `istiod`, so meshed workloads can be reinjected without `istio-init` before broader Phase 5 Pod Security enforcement.
- Tilt now pins Gateway API CRDs to `v1.4.0` and Istio Helm charts to `1.29.1`; ingress hardening is declared through Gateway `spec.infrastructure.parametersRef`, and the egress gateway installs directly from `istio/gateway` again using checked-in Helm values.
- Tilt now installs `prometheus-community/kube-prometheus-stack` `83.4.0` into the repo-managed `monitoring` namespace after a local render verification pass that checks digest pinning, explicit token-mount intent, and server dry-run compliance for the rendered workload objects.
- The Prometheus server pod now joins the Istio mesh and default-namespace workloads explicitly allow its service account to scrape Envoy metrics on `:15090`, so the checked-in Envoy `PodMonitor` works under STRICT mTLS plus the repo's existing `AuthorizationPolicy` and `NetworkPolicy` constraints.
- The four Spring Boot workloads in `default` now carry `app.kubernetes.io/framework: spring-boot`, and the checked-in `ServiceMonitor` scrapes their real actuator metrics paths, including the three servlet-context-path variants and the root-path Session Gateway endpoint.
- The repo now ships a checked-in fallback `ConfigMap/session-gateway-idp-config` for non-Tilt applies, and Tilt overwrites that non-secret Session Gateway Auth0 config from `.env`; Kubernetes manifests no longer treat ordinary connection metadata or Auth0 tenant settings as secret data.
- The Auth0 egress allowlist is now rendered from the same `AUTH0_ISSUER_URI` contract used by `session-gateway-idp-config`, via `scripts/ops/render-istio-egress-config.sh`, so the Session Gateway config and the Istio egress policy do not drift by tenant.
- `setup.sh` now also runs `./scripts/bootstrap/setup-infra-tls.sh` to generate the internal `infra-ca` and `infra-tls-*` TLS secrets for Redis, PostgreSQL, and RabbitMQ. Run that script standalone only when you need to regenerate the transport-TLS material.
- Redis is now TLS-only in-cluster; verification and session seeding scripts connect through `infra-ca`, and direct service boot runs must enable Redis SSL with that CA bundle.
- PostgreSQL uses `postgres_admin` plus per-service database users, RabbitMQ uses `rabbitmq-admin` plus `currency-service`, and Redis uses ACL users instead of one shared password.
- Before cluster apply, run `./scripts/guardrails/verify-phase-7-static-manifests.sh` to catch Phase 7 static manifest and setup-guidance regressions locally with the same checks the `security-guardrails.yml` workflow uses, including a generated Kyverno replay for representative approved local Tilt `:tilt-<hash>` deploy refs.
- After `tilt up`, run `./scripts/smoketest/verify-clean-tilt-deployment-admission.sh` first to prove the clean-start admission path for the seven app deployments in `default`, then `./scripts/smoketest/verify-security-prereqs.sh` for the Phase 0 platform baseline, `./scripts/smoketest/verify-phase-1-credentials.sh` for Phase 1 credential isolation, `./scripts/smoketest/verify-phase-4-transport-encryption.sh` as the Phase 4 transport-TLS completion gate, `./scripts/smoketest/verify-phase-3-istio-ingress.sh` as the Phase 3 Istio ingress/egress completion gate, `./scripts/smoketest/verify-phase-5-runtime-hardening.sh` as the Phase 5 runtime-hardening and final PSA completion gate, `./scripts/smoketest/verify-phase-6-session-7-api-rate-limit-identity.sh` for the Phase 6 Session 7 API rate-limit identity proof, `./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` as the Phase 6 completion gate, and `./scripts/smoketest/verify-phase-7-security-guardrails.sh` as the final local Phase 7 completion gate. `./scripts/smoketest/smoketest.sh` is the aggregate local smoke entry point that also wires in the rendered monitoring verifier, monitoring runtime verifier, and Session Architecture Phase 5 verifier.

Monitoring access after `tilt up`:
- Grafana: `https://grafana.budgetanalyzer.localhost` (via Istio ingress, no port-forward needed)
- Grafana admin password: `kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo`
- Prometheus: `kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090` (then open `http://localhost:9090`)
- Prometheus targets to expect: `currency-service`, `transaction-service`, `permission-service`, and `session-gateway`
- Example Prometheus queries: `up{job="spring-boot-services"}`, `jvm_memory_used_bytes`, `jvm_gc_pause_seconds_count`
- See [Observability Architecture](docs/architecture/observability.md) for scrape topology, dashboards, and debugging guidance

Treat Phase 5 as complete only after `./scripts/smoketest/verify-phase-5-runtime-hardening.sh` passes. Treat Phase 4 as complete only after `./scripts/smoketest/verify-phase-4-transport-encryption.sh` passes, and treat Phase 3 as complete only after `./scripts/smoketest/verify-phase-3-istio-ingress.sh` plus the live validation checklist pass. Treat Phase 6 as complete only after `./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` passes and the manual browser-console validation on `/_prod-smoke/` is done; `/api-docs` probes now stay visible as warnings instead of blocking completion. Treat Phase 7 as complete only after `./scripts/smoketest/verify-phase-7-security-guardrails.sh` passes on the current cluster. The static script remains the CI/local reproducer for Session 6, and `./scripts/smoketest/verify-phase-7-runtime-guardrails.sh` remains the targeted live-cluster Session 7 proof when you only need the runtime half.

Auth entrypoints are split intentionally: `/login` is the frontend login page, `/oauth2/authorization/idp` starts OAuth2, and Auth0 returns to `/login/oauth2/code/idp`.
The local `/_prod-smoke/` verification path is a separate Tilt `local_resource`: it runs `npm run build:prod-smoke` in the sibling `budget-analyzer-web` repo, so that repo needs local npm dependencies installed (`npm install`) in addition to the normal frontend container image build.

## Documentation

- [Getting Started](docs/development/getting-started.md)
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
