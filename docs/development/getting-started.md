# Getting Started

**Tested with:** VS Code, Claude Code (extension or terminal), Anthropic account. We use open source tools—Cursor is closed source.

```bash
git clone https://github.com/budgetanalyzer/workspace.git
```

Open in VS Code → "Reopen in Container" when prompted.

First time takes several minutes to download Docker images. Click "show log" in the VS Code notification to watch progress — otherwise it looks stuck.

You're now in the devcontainer. You'll see all repos in the sidebar, but don't just click them — that browses files but doesn't load the repo's AGENTS.md. Use File → Open Folder to launch a new VS Code instance with the right Claude context.

---

## Run the Budget Analyzer App

Want to see the microservices architecture running locally? Useful for understanding how the pieces connect or making changes to services.

1. File → Open Folder → `/workspace/orchestration`
2. Follow the steps below

From your **host terminal** (not the devcontainer):

```bash
cd path/to/workspace/orchestration
./setup.sh        # Recreates the kind cluster, ensures supported Helm, installs Calico, configures certs (browser + infra TLS), DNS, and .env
vim .env          # Review infra password defaults; add Auth0 config/client secret and FRED API key
./scripts/guardrails/verify-phase-7-static-manifests.sh   # Optional but recommended before cluster apply: static security guardrails, including the approved local Tilt-tag replay
tilt up           # Start everything
./scripts/smoketest/verify-clean-tilt-deployment-admission.sh  # Optional but recommended clean-start admission proof for the seven app deployments
./scripts/smoketest/verify-security-prereqs.sh   # Optional but recommended platform security prerequisite proof
./scripts/smoketest/verify-phase-1-credentials.sh   # Optional but recommended credential isolation proof
./scripts/smoketest/verify-session-architecture-phase-5.sh --static-only  # Optional but recommended static proof of the shared session contract and full Session Gateway auth-route contract
./scripts/smoketest/verify-phase-2-network-policies.sh  # Optional but recommended NetworkPolicy enforcement proof
./scripts/smoketest/verify-phase-3-istio-ingress.sh  # Optional but recommended Istio ingress and egress hardening proof
./scripts/smoketest/verify-phase-4-transport-encryption.sh  # Optional but recommended infrastructure transport-TLS proof
./scripts/smoketest/verify-phase-5-runtime-hardening.sh  # Optional but recommended runtime hardening and Pod Security proof
./scripts/smoketest/verify-observability-port-forward-access.sh  # Optional but recommended loopback-only Grafana, Prometheus, Jaeger, and Kiali access proof
./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh  # Optional but recommended edge and browser security proof
./scripts/smoketest/verify-phase-7-security-guardrails.sh  # Optional but recommended final local security guardrail proof
./scripts/smoketest/smoketest.sh  # Optional aggregate live-cluster smoke pass
```

Open https://app.budgetanalyzer.localhost when services are green.

This local startup flow should not require `GITHUB_ACTOR`, `GITHUB_TOKEN`, or a
personal access token for `service-common`. Tilt publishes `service-common`
locally before the downstream Java builds run. For the local-vs-release
artifact contract, see
[service-common-artifact-resolution.md](service-common-artifact-resolution.md).

The script tree is now purpose-split: `scripts/bootstrap/` for host and
cluster setup, `scripts/guardrails/` for CI-safe static checks,
`scripts/smoketest/` for live-cluster verifiers, `scripts/ops/` for
interactive maintenance, `scripts/loadtest/` for synthetic fixtures, and
`scripts/repo/` for cross-repo maintenance. See [`scripts/README.md`](../../scripts/README.md)
for the full map and the `smoketest.sh` execution order.

Tilt now generates the local PostgreSQL, RabbitMQ, and Redis secrets from `.env`.
The repo also ships a checked-in fallback
`ConfigMap/session-gateway-idp-config`, and Tilt overwrites its non-secret
Session Gateway Auth0 settings from `.env`, while
`Secret/auth0-credentials` now carries only `AUTH0_CLIENT_SECRET`.
PostgreSQL uses a `postgres_admin` bootstrap user plus distinct per-service
database users. RabbitMQ uses `rabbitmq-admin` plus the `currency-service`
broker identity. Redis uses ACL users (`session-gateway`, `ext-authz`,
`currency-service`, `redis-ops`) plus a restricted probe-only `default` user.
`setup.sh` now rebuilds the `kind` cluster from scratch on every run instead of
reusing an existing cluster, and it installs Helm `v3.20.1` automatically from
a pinned verified release if the current Helm binary is missing or unsupported.
It also refreshes the existing `istio` Helm repo index on every run so the host
does not reuse stale chart metadata after an Istio version bump.
`setup.sh` now generates the internal transport-TLS secrets automatically.
To regenerate them standalone, run `./scripts/bootstrap/setup-infra-tls.sh` from the host.
`./scripts/bootstrap/check-tilt-prerequisites.sh` fails until `infra-ca` plus the
three `infra-tls-*` secrets exist.
`./scripts/smoketest/verify-phase-4-transport-encryption.sh` is the transport-TLS
completion gate for Redis, PostgreSQL, and RabbitMQ.
`./scripts/smoketest/verify-phase-5-runtime-hardening.sh` is the final Pod Security
and runtime-hardening gate; it reruns the earlier phase verifiers as
regressions.
`./scripts/guardrails/verify-phase-7-static-manifests.sh` is the local static
Session 6 guardrail gate and matches the dedicated CI workflow closely enough
for local reproduction without a cluster. It now also replays representative
approved local Tilt `:tilt-<hash>` refs through Kyverno so the deploy-time
admission contract stays aligned with the manifest-literal inventory.
`./scripts/smoketest/verify-clean-tilt-deployment-admission.sh` is the host-side
clean-start proof for the seven app deployments in `default`; run it after
`tilt up` when you want the specific admission-regression check from the clean
rebuild workflow.
`./scripts/smoketest/verify-session-architecture-phase-5.sh --static-only` is the
repo-level proof that the Session Gateway cutover still matches orchestration:
Redis ACL bootstrap uses `session:*` and `oauth2:state:*`, ext-authz and
Session Gateway share the `session:` key prefix contract plus the
`BA_SESSION` cookie-name default, orchestration explicitly wires
`SESSION_COOKIE_NAME=BA_SESSION` into the `ext-authz` deployment, and
`/auth/*`, `/oauth2/*`, `/login/oauth2/*`, and `/logout` still belong to
Session Gateway with no standalone `/user` ingress route.
After logging in once, rerun the verifier without `--static-only` or with
`--require-live-session` when you want the live Redis ACL/keyspace proof too.
`./scripts/smoketest/verify-phase-7-security-guardrails.sh` is the final local
security guardrail command; it runs the static gate and then the live runtime
proof in order. The narrower
`./scripts/smoketest/verify-phase-7-runtime-guardrails.sh` entrypoint remains useful
when you only need the live-cluster runtime guardrail proof.
All verification scripts run against the current `kubectl` context. If a
verifier says pods or network policies are missing while Tilt looks healthy,
check `kubectl config current-context` and `tilt get uiresources` from the same
host shell before debugging the verifier itself.

> **Setup failing?** Run `./scripts/bootstrap/check-tilt-prerequisites.sh` — it tells you exactly what's missing and points Linux/macOS hosts at the checked-in verified installer flow for `kubectl`, Helm, Tilt, and `mkcert`.

## External Services (~10 min one-time setup)

The app needs two external accounts in addition to the local infrastructure password defaults already present in `.env`. Both are free:

### Auth0 (authentication)

1. Create account at [auth0.com](https://auth0.com)
2. Create Application → "Regular Web Application"
3. Copy Domain, Client ID, Client Secret to `.env`
4. Full guide: [auth0-setup.md](../setup/auth0-setup.md)

### FRED API (exchange rates)

1. Get free key at [fred.stlouisfed.org](https://fred.stlouisfed.org/docs/api/api_key.html)
2. Copy to `.env`
3. Full guide: [fred-api-setup.md](../setup/fred-api-setup.md)

### Using the App

The docs UI and raw OpenAPI downloads stay on the same public origin as the
main app. The `/api-docs` route uses a docs-only relaxed CSP (the stock Swagger
UI bundle needs `'unsafe-inline'` in `style-src`). The main app and `/api/*`
routes are not affected — they keep the strict CSP. The docs route is public,
read-only, and serves self-hosted assets with no CDN dependency.
The browser-visible login page is `/login`; it starts the real OAuth2 flow at
`/oauth2/authorization/idp`. After sign-in, the frontend keeps the opaque
`BA_SESSION` cookie alive with same-origin `GET /auth/v1/session` heartbeats
while the user is active. Session Gateway stores browser sessions as
`session:{id}` hashes in Redis and uses temporary `oauth2:state:{state}` hashes
for the OAuth2 round-trip.

- **Application**: https://app.budgetanalyzer.localhost
- **API Docs UI**: https://app.budgetanalyzer.localhost/api-docs
- **OpenAPI JSON**: https://app.budgetanalyzer.localhost/api-docs/openapi.json
- **OpenAPI YAML**: https://app.budgetanalyzer.localhost/api-docs/openapi.yaml
- **Tilt observability contract**: `tilt up` deploys Grafana, Prometheus, Jaeger, and Kiali, but it does not open localhost tunnels for them
- **Convenience helper**: `./scripts/ops/start-observability-port-forwards.sh`
- **Grafana**: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-grafana 3300:80`, then open http://localhost:3300
- **Prometheus**: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090`, then open http://localhost:9090
- **Jaeger**: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/jaeger-query 16686:16686`, then open http://localhost:16686/jaeger
- **Kiali**: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/kiali 20001:20001`, then open http://localhost:20001/kiali and sign in with `kubectl -n monitoring create token kiali`
- **Focused access proof**: `./scripts/smoketest/verify-observability-port-forward-access.sh`
- **Tilt UI**: http://localhost:10350 (logs and status)

Observability is internal-only in both local Tilt and production OCI/k3s.
Keep Grafana authentication enabled, keep observability port-forwards bound to
`127.0.0.1`, and do not use `grafana.budgetanalyzer.localhost`,
`grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, or
`jaeger.budgetanalyzer.org` as operator entry points. The focused smoke script
starts any missing temporary forwards on the canonical ports and reuses the
expected existing loopback `kubectl port-forward` listeners when the helper or
manual forwards already hold those ports. Pass explicit `--grafana-port`,
`--prometheus-port`, `--jaeger-port`, and `--kiali-port` overrides only when
some other intentional listener already owns a canonical port.

### Stopping

```bash
tilt down
```
