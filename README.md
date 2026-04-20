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
- `setup.sh` now also refreshes the `kiali` Helm repo index so the pinned standalone `kiali-server` chart metadata is available before Tilt installs Kiali.
- Tilt now installs `istio/cni` with `kubernetes/istio/cni-common-values.yaml` plus the local Kind-specific `kubernetes/istio/cni-kind-values.yaml`, and enables `pilot.cni.enabled=true` for `istiod`, so meshed workloads can be reinjected without `istio-init` before broader Pod Security enforcement. Production OCI/k3s deploys use the same common baseline plus `kubernetes/istio/cni-k3s-values.yaml`.
- Tilt now pins Gateway API CRDs to `v1.4.0` and Istio Helm charts to `1.29.1`; ingress hardening is declared through Gateway `spec.infrastructure.parametersRef`, and the egress gateway installs directly from `istio/gateway` again using checked-in Helm values.
- Tilt now installs `prometheus-community/kube-prometheus-stack` `83.4.0` into the repo-managed `monitoring` namespace after a local render verification pass that checks digest pinning, explicit token-mount intent, and server dry-run compliance for the rendered workload objects.
- Tilt now also applies the repo-managed Jaeger `2.17.0` backend manifests from `kubernetes/monitoring/jaeger/`. Jaeger runs as one digest-pinned v2 pod with PVC-backed Badger storage, separate `ClusterIP` collector/query services, and no public route.
- Tilt now wires Istio tracing to Jaeger through the repo-owned `jaeger` OpenTelemetry extension provider in `kubernetes/istio/istiod-values.yaml` and the mesh-default `kubernetes/istio/tracing-telemetry.yaml` resource. Sampling stays on Istio defaults.
- Tilt now installs `kiali/kiali-server` `2.24.0` into `monitoring` with token auth, view-only mode, non-cluster-wide RBAC, a digest-pinned image, and `ClusterIP` service exposure only.
- The Prometheus server pod now joins the Istio mesh and default-namespace workloads explicitly allow its service account to scrape Envoy metrics on `:15090`, so the checked-in Envoy `PodMonitor` works under STRICT mTLS plus the repo's existing `AuthorizationPolicy` and `NetworkPolicy` constraints.
- The four Spring Boot workloads in `default` now carry `app.kubernetes.io/framework: spring-boot`, and the checked-in `ServiceMonitor` scrapes their real actuator metrics paths, including the three servlet-context-path variants and the root-path Session Gateway endpoint.
- The repo now ships a checked-in fallback `ConfigMap/session-gateway-idp-config` for non-Tilt applies, and Tilt overwrites that non-secret Session Gateway Auth0 config from `.env`; Kubernetes manifests no longer treat ordinary connection metadata or Auth0 tenant settings as secret data.
- The Auth0 egress allowlist is now rendered from the same `AUTH0_ISSUER_URI` contract used by `session-gateway-idp-config`, via `scripts/ops/render-istio-egress-config.sh`, so the Session Gateway config and the Istio egress policy do not drift by tenant.
- `setup.sh` now also runs `./scripts/bootstrap/setup-infra-tls.sh` to generate the internal `infra-ca` and `infra-tls-*` TLS secrets for Redis, PostgreSQL, and RabbitMQ. Run that script standalone only when you need to regenerate the transport-TLS material.
- Redis is now TLS-only in-cluster; verification and session seeding scripts connect through `infra-ca`, and direct service boot runs must enable Redis SSL with that CA bundle.
- Redis now runs as a shared local `StatefulSet` with PVC-backed `/data`, matching the baseline shape used by PostgreSQL and RabbitMQ. Deleting `redis-0` or running `tilt down` is not a Redis reset; use `./scripts/ops/flush-redis.sh` or recreate the local cluster/runtime when you need clean Redis state.
- PostgreSQL uses `postgres_admin` plus per-service database users, RabbitMQ uses `rabbitmq-admin` plus `currency-service`, and Redis uses ACL users instead of one shared password.
- The `scripts/` tree is organized by purpose: `bootstrap/` for host and cluster setup, `guardrails/` for CI-safe static checks, `smoketest/` for live-cluster proofs, `ops/` for interactive day-two helpers, `loadtest/` for synthetic fixtures, and `repo/` for cross-repo maintenance. See [`scripts/README.md`](scripts/README.md) for the directory map.
- Before cluster apply, run `./scripts/guardrails/verify-phase-7-static-manifests.sh` to catch static manifest and setup-guidance regressions locally with the same checks the `security-guardrails.yml` workflow uses, including a generated Kyverno replay for representative approved local Tilt `:tilt-<hash>` deploy refs.
- After `tilt up`, run `./scripts/smoketest/verify-clean-tilt-deployment-admission.sh` first to prove the clean-start admission path for the seven app deployments in `default`, then `./scripts/smoketest/verify-security-prereqs.sh` for platform security prerequisites, `./scripts/smoketest/verify-istio-tracing-config.sh` for the Jaeger tracing provider and mesh-default Telemetry resource, `./scripts/smoketest/verify-phase-1-credentials.sh` for credential isolation, `./scripts/smoketest/verify-phase-4-transport-encryption.sh` for infrastructure transport TLS, `./scripts/smoketest/verify-phase-3-istio-ingress.sh` for Istio ingress and egress hardening, `./scripts/smoketest/verify-phase-5-runtime-hardening.sh` for runtime hardening and final PSA enforcement, `./scripts/smoketest/verify-phase-6-session-7-api-rate-limit-identity.sh` for API rate-limit identity, `./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` for edge and browser hardening, and `./scripts/smoketest/verify-phase-7-security-guardrails.sh` for local security guardrails. `./scripts/smoketest/smoketest.sh` is the aggregate local smoke entry point that also wires in the rendered monitoring verifier, Istio tracing verifier, monitoring runtime verifier, the observability port-forward access verifier, and the shared session contract verifier.

Monitoring access after `tilt up`:
Tilt deploys Grafana, Prometheus, Jaeger, and Kiali, but it does not open or
hold the localhost tunnels for them. Use explicit loopback-bound
`kubectl port-forward` commands when you want operator access:
- Grafana: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-grafana 3300:80` (then open `http://localhost:3300`)
- Grafana admin password: `kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo`
- Prometheus: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090` (then open `http://localhost:9090`)
- Jaeger: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/jaeger-query 16686:16686` (then open `http://localhost:16686/jaeger`; generate several app requests first because tracing uses Istio default sampling)
- Kiali: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/kiali 20001:20001` (then open `http://localhost:20001/kiali`; login with a short-lived token from `kubectl -n monitoring create token kiali`)
- Focused access proof: `./scripts/smoketest/verify-observability-port-forward-access.sh`
- Prometheus targets to expect: `currency-service`, `transaction-service`, `permission-service`, and `session-gateway`
- Example Prometheus queries: `up{namespace="default", application!=""}`, `jvm_memory_used_bytes`, `jvm_gc_pause_seconds_count`
- Observability is internal-only in both local Tilt and production OCI/k3s. `grafana.budgetanalyzer.localhost`, `grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, and `jaeger.budgetanalyzer.org` are not active operator entry points.
- Keep Grafana and Kiali authentication enabled and keep observability port-forwards loopback-bound. Do not use `--address 0.0.0.0`. The focused smoke expects the canonical local ports `3300`, `9090`, `16686`, and `20001` unless you pass explicit overrides.
- See [Observability Architecture](docs/architecture/observability.md) for scrape topology, dashboards, and debugging guidance

Use the targeted smoke scripts as capability checks rather than numbered completion gates. `./scripts/smoketest/verify-phase-5-runtime-hardening.sh` verifies runtime hardening and PSA enforcement, `./scripts/smoketest/verify-phase-4-transport-encryption.sh` verifies infrastructure transport TLS, and `./scripts/smoketest/verify-phase-3-istio-ingress.sh` plus the live validation checklist verifies Istio ingress and egress hardening. `./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` verifies edge and browser hardening, with manual browser-console validation on `/_prod-smoke/`; `/api-docs` probes now stay visible as warnings. `./scripts/smoketest/verify-phase-7-security-guardrails.sh` is the local security guardrail umbrella for the current cluster. The static script remains the CI/local reproducer for static guardrails, and `./scripts/smoketest/verify-phase-7-runtime-guardrails.sh` remains the targeted live-cluster runtime proof when you only need that half.

Auth entrypoints are split intentionally: `/login` is the frontend login page, `/oauth2/authorization/idp` starts OAuth2, and Auth0 returns to `/login/oauth2/code/idp`.
The local `/_prod-smoke/` verification path is a separate Tilt `local_resource`: it runs `npm run build:prod-smoke` in the sibling `budget-analyzer-web` repo, stages the resulting bundle under orchestration-owned `.tilt/budget-analyzer-web-prod-smoke/`, and builds the tiny smoke image from that local staging directory. The sibling repo still needs local npm dependencies installed (`npm install`) for that local-only verification seam, but this does not change the frontend release image or production overlay behavior.

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
