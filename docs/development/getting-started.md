# Getting Started

**Tested with:** VS Code, Claude Code (extension or terminal), Anthropic account. We use open source tools—Cursor is closed source.

```bash
git clone https://github.com/budgetanalyzer/workspace.git
```

Open in VS Code → "Reopen in Container" when prompted.

First time takes several minutes to download Docker images. Click "show log" in the VS Code notification to watch progress — otherwise it looks stuck.

You're now in the devcontainer. You'll see all repos in the sidebar, but don't just click them — that browses files but doesn't load the repo's AGENTS.md. Use File → Open Folder to launch a new VS Code instance with the right Claude context.

---

## Talk to Architecture Claude

Want to discuss AI-native architecture patterns, explore how this system is designed, or understand the decisions behind it?

1. File → Open Folder → `/workspace/architecture-conversations`
2. Start a Claude Code conversation

Claude has full context on the architectural patterns and the relationships between repos.

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
./scripts/dev/verify-phase-7-static-manifests.sh   # Optional but recommended before cluster apply Phase 7 static proof, including the approved local Tilt-tag replay
tilt up           # Start everything
./scripts/dev/verify-clean-tilt-deployment-admission.sh  # Optional but recommended clean-start admission proof for the seven app deployments
./scripts/dev/verify-security-prereqs.sh   # Optional but recommended Phase 0 proof
./scripts/dev/verify-phase-1-credentials.sh   # Optional but recommended Phase 1 proof
./scripts/dev/verify-session-architecture-phase-5.sh --static-only  # Optional but recommended static proof of the shared session contract and full Session Gateway auth-route contract
./scripts/dev/verify-phase-2-network-policies.sh  # Optional but recommended Phase 2 proof
./scripts/dev/verify-phase-3-istio-ingress.sh  # Optional but recommended Phase 3 proof
./scripts/dev/verify-phase-4-transport-encryption.sh  # Optional but recommended Phase 4 proof
./scripts/dev/verify-phase-5-runtime-hardening.sh  # Optional but recommended Phase 5 proof
./scripts/dev/verify-phase-6-edge-browser-hardening.sh  # Optional but recommended Phase 6 completion gate
./scripts/dev/verify-phase-7-security-guardrails.sh  # Optional but recommended final local Phase 7 completion gate
```

Open https://app.budgetanalyzer.localhost when services are green.

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
To regenerate them standalone, run `./scripts/dev/setup-infra-tls.sh` from the host.
`./scripts/dev/check-tilt-prerequisites.sh` fails until `infra-ca` plus the
three `infra-tls-*` secrets exist.
`./scripts/dev/verify-phase-4-transport-encryption.sh` is the transport-TLS
completion gate for Redis, PostgreSQL, and RabbitMQ.
`./scripts/dev/verify-phase-5-runtime-hardening.sh` is the final Pod Security
and runtime-hardening gate; it reruns the earlier phase verifiers as
regressions.
`./scripts/dev/verify-phase-7-static-manifests.sh` is the local static
Session 6 guardrail gate and matches the dedicated CI workflow closely enough
for local reproduction without a cluster. It now also replays representative
approved local Tilt `:tilt-<hash>` refs through Kyverno so the deploy-time
admission contract stays aligned with the manifest-literal inventory.
`./scripts/dev/verify-clean-tilt-deployment-admission.sh` is the host-side
clean-start proof for the seven app deployments in `default`; run it after
`tilt up` when you want the specific admission-regression check from the clean
rebuild workflow.
`./scripts/dev/verify-session-architecture-phase-5.sh --static-only` is the
repo-level proof that the Session Gateway cutover still matches orchestration:
Redis ACL bootstrap uses `session:*` and `oauth2:state:*`, ext-authz and
Session Gateway share the `session:` key prefix contract plus the
`BA_SESSION` cookie-name default, orchestration explicitly wires
`SESSION_COOKIE_NAME=BA_SESSION` into the `ext-authz` deployment, and
`/auth/*`, `/oauth2/*`, `/login/oauth2/*`, and `/logout` still belong to
Session Gateway with no standalone `/user` ingress route.
After logging in once, rerun the verifier without `--static-only` or with
`--require-live-session` when you want the live Redis ACL/keyspace proof too.
`./scripts/dev/verify-phase-7-security-guardrails.sh` is the final local Phase
7 completion command; it runs the Session 6 static gate and then the Session 7
live runtime proof in order. The narrower
`./scripts/dev/verify-phase-7-runtime-guardrails.sh` entrypoint remains useful
when you only need the live-cluster Phase 7 runtime half.
All verification scripts run against the current `kubectl` context. If a
verifier says pods or network policies are missing while Tilt looks healthy,
check `kubectl config current-context` and `tilt get uiresources` from the same
host shell before debugging the verifier itself.

> **Setup failing?** Run `./scripts/dev/check-tilt-prerequisites.sh` — it tells you exactly what's missing and points Linux/macOS hosts at the checked-in verified installer flow for `kubectl`, Helm, Tilt, and `mkcert`.

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
- **Grafana**: https://grafana.budgetanalyzer.localhost
- **Tilt UI**: http://localhost:10350 (logs and status)

### Stopping

```bash
tilt down
```
