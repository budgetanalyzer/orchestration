# Local Development Environment Setup

**Status:** Active
**Audience:** Developers setting up Budget Analyzer locally

## Prerequisites

### Required Software

**Minimum versions:**
- Docker 24.0+
- Kind 0.20+
- kubectl 1.30.8 (matches `kindest/node:v1.30.8`)
- OpenSSL 3.x+
- Helm 3.20.x (tested; Helm 4 unsupported; `setup.sh` auto-installs `v3.20.1` if missing or unsupported)
- Tilt 0.37.0
- Git 2.40+
- mkcert 1.4.4

**For Backend Development (Optional):**
- JDK 24 (for running services outside Docker)
- Gradle 8.5+ or use `./gradlew`

**For Frontend Development (Optional):**
- Node.js 20+ (LTS)
- npm 10+

### Verify Prerequisites

```bash
# Run the check script
./scripts/dev/check-tilt-prerequisites.sh

# Or check manually:
docker --version
kind --version
kubectl version --client
openssl version
helm version
tilt version
git --version
mkcert --version
```

Phase 3 now installs the Istio egress gateway directly from Helm again. The
repo uses Helm for `istio-base`, `istio/cni`, `istiod`, and `istio/gateway`
`1.29.1`; the egress gateway uses
`kubernetes/istio/egress-gateway-values.yaml` to keep
`service.type=ClusterIP`, and ingress gateway hardening plus the fixed NodePort
now flow through Gateway `spec.infrastructure.parametersRef` via
`kubernetes/istio/ingress-gateway-config.yaml`.

For host-side binary installs, prefer the checked-in verified installer:
`./scripts/dev/install-verified-tool.sh <kubectl|helm|tilt|mkcert|kubeconform|kube-linter|kyverno>`.
It uses pinned release artifacts with checked-in SHA-256 values instead of
floating installer endpoints.

## Quick Start

### 1. Clone Repositories

```bash
# Create workspace directory
mkdir -p ~/workspace/budget-analyzer
cd ~/workspace/budget-analyzer

# Clone orchestration (required)
git clone https://github.com/budgetanalyzer/orchestration.git

# Clone services (as needed)
git clone https://github.com/budgetanalyzer/service-common.git
git clone https://github.com/budgetanalyzer/transaction-service.git
git clone https://github.com/budgetanalyzer/currency-service.git
git clone https://github.com/budgetanalyzer/budget-analyzer-web.git
git clone https://github.com/budgetanalyzer/session-gateway.git
git clone https://github.com/budgetanalyzer/permission-service.git
```

**Repository structure:**
```
~/workspace/budget-analyzer/
├── orchestration/           # This repo
├── service-common/          # Shared Spring Boot library
├── transaction-service/     # Transaction microservice
├── currency-service/        # Currency microservice
├── session-gateway/         # Unified session gateway
├── permission-service/      # Internal roles/permissions
└── budget-analyzer-web/     # React frontend
```

**Important:** This side-by-side layout is **required** for cross-repository documentation links to work correctly.

### 2. Bootstrap the Local Platform

Run the setup script on your **host machine**:

```bash
cd orchestration/
./setup.sh
```

**What `setup.sh` does in the current Phase 0 baseline:**
1. Deletes any existing `kind` cluster and recreates it from scratch
2. Rejects older `kindnet`-based clusters that cannot enforce `NetworkPolicy`
3. Installs pinned Calico and waits for CoreDNS readiness
4. Ensures a supported Helm `3.20.x` binary is installed before any Helm-backed setup continues
5. Configures local DNS plus browser-facing and internal transport TLS
6. Installs Gateway API CRDs and prepares `.env`

### 3. Configure Environment Variables

```bash
# Create the file if setup.sh did not already create it
[ -f .env ] || cp .env.example .env

# Review the local PostgreSQL, RabbitMQ, and Redis password defaults, then add
# your Auth0 config/client secret and FRED API key.
```

Tilt is the local secret producer for infrastructure credentials and the local
renderer for non-secret Session Gateway Auth0 config. The Kubernetes manifests
now keep passwords, client secrets, and API keys on the secret path, while
issuer URIs, client IDs, audiences, hosts, ports, usernames, JDBC URLs, and
logout URLs stay on checked-in manifests or ConfigMaps instead.

### 4. Start Tilt

```bash
cd orchestration/
tilt up
```

### 5. Verify Services

```bash
# Check all pods are running
kubectl get pods -n default
kubectl get pods -n infrastructure

# Test gateway
curl https://app.budgetanalyzer.localhost/health

# Open frontend
open https://app.budgetanalyzer.localhost

# Optional but recommended: prove the Phase 0 platform prerequisites
./scripts/dev/verify-security-prereqs.sh

# Optional but recommended: prove the Phase 1 credential split
./scripts/dev/verify-phase-1-credentials.sh

# Optional but recommended: prove the Session Architecture Rethink Phase 5
# contract from orchestration before you log in
./scripts/dev/verify-session-architecture-phase-5.sh --static-only

# Optional but recommended: prove the Phase 2 network policy enforcement
./scripts/dev/verify-phase-2-network-policies.sh

# Optional but recommended: prove the Phase 4 transport-TLS cutover
./scripts/dev/verify-phase-4-transport-encryption.sh

# Optional but recommended: prove the Phase 3 Istio ingress/egress migration
./scripts/dev/verify-phase-3-istio-ingress.sh

# Optional but recommended: prove the Phase 5 runtime hardening and final PSA labels
./scripts/dev/verify-phase-5-runtime-hardening.sh

# Optional but recommended: prove the Phase 6 edge/browser hardening gate
./scripts/dev/verify-phase-6-edge-browser-hardening.sh

# Optional but recommended anytime: prove the Phase 7 static guardrails
./scripts/dev/verify-phase-7-static-manifests.sh

# Optional but recommended right after tilt up on a clean rebuild: prove the app deployments were admitted cleanly
./scripts/dev/verify-clean-tilt-deployment-admission.sh

# Optional but recommended after the Phase 6 gate: run the final local Phase 7 completion gate
./scripts/dev/verify-phase-7-security-guardrails.sh
```

`./scripts/dev/verify-phase-7-static-manifests.sh` is the Phase 7 Session 6
local static guardrail gate; it matches the dedicated `security-guardrails.yml`
workflow closely enough for local reproduction and does not require a running
cluster. It now also generates a Kyverno replay for representative approved
local Tilt `:tilt-<hash>` refs so the live deploy-time admission path stays
covered by the static guardrail suite.
`./scripts/dev/verify-clean-tilt-deployment-admission.sh` is the host-side
clean-start proof for the seven expected app deployments in `default`. Run it
after `tilt up` when you want the specific admission regression check from the
fresh-cluster workflow.
`./scripts/dev/verify-security-prereqs.sh` proves the Phase 0 platform baseline.
`./scripts/dev/verify-session-architecture-phase-5.sh` proves the Session
Architecture Rethink Phase 5 contract from orchestration: Redis ACL bootstrap
uses `session:*` and `oauth2:state:*`, ext-authz and Session Gateway share the
`session:` key prefix contract plus the `BA_SESSION` cookie-name default,
orchestration explicitly wires `SESSION_COOKIE_NAME=BA_SESSION` into the
`ext-authz` deployment, and `/auth/*`, `/oauth2/*`, `/login/oauth2/*`,
`/logout`, plus `/user` still route only to Session Gateway.
Use `--static-only` for repo-level validation before login. After a browser
login, rerun it without that flag when you want the live Redis ACL/keyspace
proof too, or add `--require-live-session` to insist on at least one real
`session:*` key.
`./scripts/dev/verify-phase-4-transport-encryption.sh` is the Phase 4
transport-TLS completion gate, and
`./scripts/dev/verify-phase-3-istio-ingress.sh` is the Phase 3 completion gate.
`./scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` is the
scoped Phase 6 Session 7 gate for NGINX client-identity derivation and API
rate-limit bucket correctness.
`./scripts/dev/verify-phase-5-runtime-hardening.sh` is the Phase 5 completion
gate and reruns the earlier phase verifiers as regressions.
`./scripts/dev/verify-phase-6-edge-browser-hardening.sh` is the Phase 6
completion gate: it checks the live dev/strict CSP split on the real app
paths, keeps `/api-docs` probes visible as warning-only checks, runs a real
syntax check of the checked-in
`nginx/nginx.production.k8s.conf` inside the running `nginx-gateway` pod with
the mounted include files, the fail-closed `/api-docs/*` contract for unknown
docs paths, final auth-edge throttling coverage,
reruns the Session 3 CSP audit plus the Session 7 API identity verifier, and
then reruns the Phase 5 gate as the regression cascade. It still does not
replace the manual browser-console validation required on `/_prod-smoke/`.
`./scripts/dev/verify-phase-7-security-guardrails.sh` is the final local
Phase 7 completion gate. It runs the Phase 7 Session 6 static gate first and
then the Phase 7 Session 7 runtime gate so contributors do not have to stitch
those commands together manually. CI intentionally remains static-only through
`security-guardrails.yml`.
`./scripts/dev/verify-phase-7-runtime-guardrails.sh` remains the targeted
Phase 7 Session 7 live-cluster guardrail proof. It adds the missing Redis ACL,
PostgreSQL cross-database, and RabbitMQ permission-boundary denials, uses
pinned temporary probe images plus self-cleaning temporary `NetworkPolicy`
rules, and then reruns
`./scripts/dev/verify-phase-6-edge-browser-hardening.sh` as the reused Phase 2
through Phase 6 runtime regression umbrella.
`./scripts/dev/check-tilt-prerequisites.sh` also blocks on the
infrastructure TLS secrets. If they are missing after a cluster recreate, rerun
`./setup.sh` on the host. Use `./scripts/dev/setup-infra-tls.sh` only when you
need to regenerate just the internal transport-TLS secrets.
All verification scripts use the current `kubectl` context. If one reports
missing pods, secrets, or network policies while Tilt appears healthy, verify
`kubectl config current-context` and `tilt get uiresources` from the same host
shell before assuming the script is wrong.

Tilt now renders the Auth0 Istio egress manifests through
`./scripts/dev/render-istio-egress-config.sh`, using the same
`AUTH0_ISSUER_URI` contract that populates `ConfigMap/session-gateway-idp-config`.
Production config sourcing should keep that same seam: the value that creates
the Session Gateway IDP config must also drive the Auth0 egress render/apply
step.

Service runtime knobs that orchestration intentionally exposes now stay on the
checked-in manifest path. Today that means `ConfigMap/session-gateway-config`
carries `SESSION_TTL_SECONDS=900` seconds (15 minutes) for local browser and
token-exchange sessions, while `ConfigMap/permission-service-config` carries
the in-cluster `SESSION_GATEWAY_BASE_URL` plus the bounded session-revocation
retry defaults. Those values stay in checked-in config instead of drifting into
ad hoc deployment env entries or secret-only paths.

The Phase 3 verifier is the runtime completion gate for ingress/egress hardening. It proves STRICT mTLS with paired sidecar and no-sidecar probes against a temporary in-mesh echo service, verifies ingress-identity denial with a wrong-identity probe, checks end-to-end identity-header sanitization through a temporary echo route, verifies that `/login` still loads as the frontend login page at normal request rates while `/oauth2/authorization/idp` still redirects into the Session Gateway OAuth2 flow, requires ingress auth throttling to return HTTP `429` plus the `x-local-rate-limit: auth-sensitive` marker on `/login`, `/oauth2/authorization/idp`, and `/user`, confirms the `/login/oauth2/*` callback prefix stays attached to Session Gateway, proves that the Auth0 egress `ServiceEntry`, egress `Gateway`, and `VirtualService` all match the configured `session-gateway-idp-config` `AUTH0_ISSUER_URI` hostname, and inspects the forwarded-header chain that NGINX logs for both frontend and API traffic in development.

The current ingress-facing policy attachment facts are also part of that runtime story: the rendered ingress gateway pods are selected with `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway`, and the ingress-facing `AuthorizationPolicy` principals target `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`. Re-verify both after Istio upgrades before assuming Phase 3 policies still attach.

## Tilt Resources

### Compile Resources

Tilt compiles services locally using Gradle, then builds Docker images:

- `service-common-publish` - Publishes shared library to Maven Local
- `transaction-service-compile` - Compiles transaction service
- `currency-service-compile` - Compiles currency service
- `session-gateway-compile` - Compiles session gateway
- `permission-service-compile` - Compiles permission service

### Infrastructure Resources

- `postgresql` - PostgreSQL StatefulSet
- `redis` - Redis Deployment
- `rabbitmq` - RabbitMQ StatefulSet
- `istio-ingress-config` - Istio ingress gateway (auto-provisioned from Gateway API)
- `istio-ingress-routes` - HTTPRoute and ext_authz policy resources
- `istio-egress-gateway` - Istio egress gateway (Helm chart via values file)
- `istio-egress-config` - ServiceEntries and egress routing

## Live Development Pipeline

The Tiltfile implements a live update pipeline that delivers near-local iteration speed inside a production-faithful Kubernetes cluster. You edit code locally; changes reach the running pod in seconds — without image rebuilds or pod restarts — while the full infrastructure (service mesh, mTLS, network policies, ext_authz) stays active around it.

### Java Services (Spring Boot)

Each Java service uses a two-stage pipeline:

**Stage 1 — Host-side compilation (`local_resource`):**
Tilt watches `src/` and `build.gradle.kts`. When you save a Java file, Gradle runs `bootJar` on the host using the build cache. This produces a JAR in `build/libs/`.

**Stage 2 — Live sync and process restart (`docker_build_with_restart`):**
The dev image is JRE-only — no JDK, no Gradle, no source code. It's defined inline in the Tiltfile as a thin runtime container: `COPY build/libs/*.jar app.jar`. When the JAR changes, Tilt syncs it into the running pod and restarts the Java process. The pod itself is not recreated and the image is not rebuilt.

This is intentionally different from the production Dockerfile in each service repo, which uses a full multi-stage build (JDK build stage + JRE runtime stage). The dev image skips the build stage because Gradle already ran on the host.

### Frontend (React/Vite)

The frontend keeps the single-stage Vite/HMR dev loop and adds a separate production-smoke build path for browser-policy verification:

**Image build (`docker_build`):**
Tilt builds from the Dockerfile in `budget-analyzer-web/` — installs dependencies, copies source, runs the Vite dev server.

**Live sync (no restart needed):**
When you edit React code, Tilt syncs `src/`, `public/`, and `index.html` into the running pod. Vite's HMR detects the change and hot-patches the browser — no container restart, no page reload. If `package.json` changes, Tilt triggers `npm install` inside the pod.

**Production-smoke build (`local_resource` + init container):**
Tilt also runs `npm run build:prod-smoke` from the sibling repo, builds a tiny static-asset image from `dist/`, and has `nginx-gateway` copy that bundle into an internal volume during pod startup. NGINX serves that bundle at `https://app.budgetanalyzer.localhost/_prod-smoke/` for strict-CSP and other browser-security checks while `/` and `/login` stay on the live Vite route.

That local smoke-build path depends on host/devcontainer npm state in the
sibling `budget-analyzer-web` repo. Before expecting `/_prod-smoke/` to build
or refresh, make sure `npm install` has been run there so
`npm run build:prod-smoke` can execute locally. This is intentionally separate
from the normal frontend pod, which still installs and runs inside its own
image. Tilt now watches the sibling smoke-build inputs plus the Vite env files
that affect the build (`.env`, `.env.local`, `.env.production`, and
`.env.production.local`) so those local config changes retrigger the smoke
asset path.

That seam is deliberately local-only. The checked-in production cutover now
lives in `nginx/nginx.production.k8s.conf`, where `/` and `/login` serve the
built frontend bundle directly and the Vite-only public paths plus
`/_prod-smoke/` are not exposed.

The Phase 6 Session 3 stop-gate is now repeatable from this repo with:

```bash
./scripts/dev/audit-phase-6-session-3-frontend-csp.sh
```

That audit rebuilds the sibling smoke bundle and proves the repo-owned
strict-CSP prerequisites before and after Session 4 tightens the NGINX headers.
It does not replace the manual browser-console validation required by the
Phase 6 plan.

The Phase 6 Session 7 runtime proof is also repeatable from this repo:

```bash
./scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh
```

That verifier creates two temporary no-sidecar probe pods, sends authenticated
API traffic through the live ingress gateway, confirms NGINX derives the client
identity from the ingress-appended downstream hop instead of a forged external
`X-Forwarded-For` value, and proves different downstream clients do not share
the same NGINX API rate-limit bucket.

The full Phase 6 completion gate is now:

```bash
./scripts/dev/verify-phase-6-edge-browser-hardening.sh
```

That verifier checks the checked-in dev/strict CSP split on the real app
paths, the live headers on `/` and `/_prod-smoke/`, warning-only `/api-docs`
visibility plus fail-closed checks, the checked-in production-route syntax validation inside the live
`nginx-gateway` runtime, the fail-closed `/api-docs/*` behavior for unknown
docs paths, the remaining auth-edge throttling
paths, reruns the Session 3 frontend CSP audit and the Session 7 API identity
proof, and then reruns the full Phase 5 runtime-hardening cascade. Manual
browser-console validation on `/_prod-smoke/` is still required before Phase 6
can be declared complete.

### Shared Library Cascade

When `service-common` source changes, Tilt:
1. Publishes the library to Maven Local (`publishToMavenLocal`)
2. Triggers recompilation of all four downstream services
3. Each service's new JAR syncs into its pod and the process restarts

The entire cascade — library publish, service recompiles, JAR syncs, process restarts — is automatic and typically completes in under 30 seconds.

### Why This Matters

Most teams compromise: develop locally without Kubernetes (fast but unfaithful to production) or rebuild images on every change (faithful but slow). This setup avoids the tradeoff — inner-loop development runs at near-local speed while the workload executes in a real Kubernetes cluster with Istio mTLS, Calico network policies, ext_authz session validation, and TLS-encrypted infrastructure connections.

## Development Workflows

### Workflow 1: Full Stack via Tilt (Recommended)

**Best for:** Most development scenarios

```bash
cd orchestration/
tilt up
```

**All services in Kubernetes:**
- Java changes: host compile → JAR sync → process restart (seconds, no image rebuild)
- React changes: source sync → Vite HMR (sub-second, no restart)
- React production-smoke checks: `/_prod-smoke/` serves the built bundle from NGINX on the same origin without replacing the live dev route
- Production route cutover work should target `nginx/nginx.production.k8s.conf`, not mutate the live Vite route graph with ad-hoc env toggles
- Shared library changes: automatic cascade to all dependent services
- Unified logging in Tilt UI

### Workflow 2: Backend Service Local, Rest in Tilt

**Best for:** Debugging a specific backend service

```bash
# Start everything in Tilt
tilt up

# Scale down the service you want to debug
kubectl scale deployment transaction-service -n default --replicas=0

# Run locally with debugger
cd transaction-service/
./gradlew bootRun --args='--spring.profiles.active=local'
```

**Benefits:**
- Full debugging capabilities with IDE
- Breakpoints and step-through debugging
- Service still accessible via port forward

### Workflow 3: Frontend Local, Backend in Tilt

**Best for:** Frontend development with HMR

```bash
# Start backend in Tilt
tilt up

# Scale down frontend
kubectl scale deployment budget-analyzer-web -n default --replicas=0

# Run frontend locally
cd budget-analyzer-web/
npm install
npm run dev
```

**Benefits:**
- Faster HMR (Hot Module Replacement)
- Local debugging tools

## Database Setup

See: [database-setup.md](database-setup.md) for detailed database configuration.

**Quick reference:**
```bash
# transaction-service database connection (via port forward)
Host: localhost
Port: 5432
Database: budget_analyzer
User: transaction_service
Password: value from POSTGRES_TRANSACTION_SERVICE_PASSWORD (default: budget-analyzer-transaction-service)

# Break-glass admin connection
User: postgres_admin
Password: value from POSTGRES_BOOTSTRAP_PASSWORD (default: budget-analyzer-postgres-admin)

# Connection string
postgresql://transaction_service:${POSTGRES_TRANSACTION_SERVICE_PASSWORD:-budget-analyzer-transaction-service}@localhost:5432/budget_analyzer?sslmode=verify-full&sslrootcert=./nginx/certs/infra/infra-ca.pem
```


## Port Reference

| Service | Port | URL | Notes |
|---------|------|-----|-------|
| Istio Ingress Gateway | 443 | https://app.budgetanalyzer.localhost | **Primary browser entry point** |
| Istio Ingress Gateway | 443 | https://app.budgetanalyzer.localhost/api/* | API paths (same origin) |
| NGINX Gateway | 8080 | - | Internal (routing) |
| Session Gateway | 8081 | - | Internal (behind Istio ingress) |
| transaction-service | 8082 | http://localhost:8082 | Direct access via port forward |
| currency-service | 8084 | http://localhost:8084 | Direct access via port forward |
| permission-service | 8086 | http://localhost:8086 | Direct access via port forward |
| ext-authz | 9002 | http://localhost:9002/check | Direct access via port forward |
| ext-authz | 8090 | http://localhost:8090/healthz | Health endpoint |
| Frontend | 3000 | http://localhost:3000 | Direct access via port forward |
| PostgreSQL | 5432 | localhost:5432 | Database access (`sslmode=verify-full`) |
| Redis | 6379 | localhost:6379 | TLS-only cache/session access |
| RabbitMQ | 5671 | localhost:5671 | AMQPS data plane |
| RabbitMQ Management | 15672 | http://localhost:15672 | Internal management UI |
| Tilt UI | 10350 | http://localhost:10350 | Development dashboard |

## Environment Variables

### Backend Services (Spring Boot)

Sensitive environment variables are injected via Kubernetes secrets, while
non-secret runtime settings stay on checked-in manifests or ConfigMaps.
PostgreSQL Step 2 uses a `postgres_admin` bootstrap user plus dedicated service
users. RabbitMQ Step 3 now bootstraps `rabbitmq-admin` and `currency-service`
from a definitions file. Redis Step 4 now uses ACL users: a restricted
`default` user for probes plus dedicated `session-gateway`, `ext-authz`,
`currency-service`, and `redis-ops` identities.

Current local secret names:

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `postgresql-bootstrap-credentials` | `infrastructure` | PostgreSQL bootstrap/admin and init passwords |
| `transaction-service-postgresql-credentials` | `default` | transaction-service PostgreSQL password |
| `currency-service-postgresql-credentials` | `default` | currency-service PostgreSQL password |
| `permission-service-postgresql-credentials` | `default` | permission-service PostgreSQL password |
| `rabbitmq-bootstrap-credentials` | `infrastructure` | RabbitMQ admin password plus boot-time definitions document |
| `currency-service-rabbitmq-credentials` | `default` | currency-service RabbitMQ password |
| `redis-bootstrap-credentials` | `infrastructure` | Redis ACL bootstrap and probe passwords |
| `session-gateway-redis-credentials` | `default` | session-gateway Redis password |
| `ext-authz-redis-credentials` | `default` | ext-authz Redis password |
| `currency-service-redis-credentials` | `default` | currency-service Redis password |

Current local config names:

| ConfigMap | Namespace | Purpose |
|-----------|-----------|---------|
| `permission-service-config` | `default` | checked-in Permission Service runtime settings such as `SESSION_GATEWAY_BASE_URL` and bounded session-revocation retry knobs |
| `session-gateway-config` | `default` | checked-in Session Gateway runtime settings such as `SESSION_TTL_SECONDS` |
| `session-gateway-idp-config` | `default` | checked-in fallback for non-secret Auth0/IDP settings (`AUTH0_CLIENT_ID`, `AUTH0_ISSUER_URI`, `IDP_AUDIENCE`, `IDP_LOGOUT_RETURN_TO`); Tilt overwrites it locally from `.env` |

For the full local secret/config inventory and the static guardrail that checks
it, see [Secrets-Only Handling](secrets-only-handling.md).

For local development outside Tilt, create `application-local.yml`:

```yaml
spring:
  ssl:
    bundle:
      pem:
        infra-ca:
          truststore:
            certificate: ${INFRA_CA_CERT_PATH:}

  datasource:
    url: jdbc:postgresql://localhost:5432/budget_analyzer?sslmode=verify-full&sslrootcert=${POSTGRES_SSLROOTCERT:../orchestration/nginx/certs/infra/infra-ca.pem}
    username: ${SPRING_DATASOURCE_USERNAME:transaction_service}
    password: ${SPRING_DATASOURCE_PASSWORD:}

  data:
    redis:
      host: ${SPRING_DATA_REDIS_HOST:localhost}
      port: ${SPRING_DATA_REDIS_PORT:6379}
      username: ${SPRING_DATA_REDIS_USERNAME:session-gateway}
      password: ${SPRING_DATA_REDIS_PASSWORD:}
      ssl:
        enabled: ${SPRING_DATA_REDIS_SSL_ENABLED:true}
        bundle: ${SPRING_DATA_REDIS_SSL_BUNDLE:infra-ca}

  # Only currency-service needs RabbitMQ locally.
  rabbitmq:
    host: ${SPRING_RABBITMQ_HOST:localhost}
    port: ${SPRING_RABBITMQ_PORT:5671}
    username: ${SPRING_RABBITMQ_USERNAME:currency-service}
    password: ${SPRING_RABBITMQ_PASSWORD:}
    ssl:
      enabled: ${SPRING_RABBITMQ_SSL_ENABLED:true}
      bundle: ${SPRING_RABBITMQ_SSL_BUNDLE:infra-ca}

server:
  port: 8082  # Change per service
```

Password placeholders intentionally default to empty. A direct `bootRun`
without env vars should fail with a connection error so each service uses its
own explicit password.

For `currency-service`, swap in `currency`, `currency_service`, and set
`SPRING_DATASOURCE_PASSWORD` from `POSTGRES_CURRENCY_SERVICE_PASSWORD`.
For `permission-service`, use `permission`, `permission_service`, and set
`SPRING_DATASOURCE_PASSWORD` from `POSTGRES_PERMISSION_SERVICE_PASSWORD`.
`transaction-service` no longer needs any RabbitMQ env vars. `session-gateway`
only needs `SPRING_DATA_REDIS_PASSWORD`; its Redis username defaults to
`session-gateway`.
Set `POSTGRES_SSLROOTCERT="$(cd ../orchestration && pwd)/nginx/certs/infra/infra-ca.pem"`
for JDBC `sslrootcert`, and
`INFRA_CA_CERT_PATH="file:$(cd ../orchestration && pwd)/nginx/certs/infra/infra-ca.pem"`
for Spring SSL bundles.

Redis local access:
- `session-gateway` uses username `session-gateway`; direct `bootRun` should set `SPRING_DATA_REDIS_PASSWORD=$REDIS_SESSION_GATEWAY_PASSWORD`, `SPRING_DATA_REDIS_SSL_ENABLED=true`, and `SPRING_DATA_REDIS_SSL_BUNDLE=infra-ca`
- `currency-service` uses username `currency-service`; direct `bootRun` should set `SPRING_DATA_REDIS_PASSWORD=$REDIS_CURRENCY_SERVICE_PASSWORD`, `SPRING_DATA_REDIS_SSL_ENABLED=true`, and `SPRING_DATA_REDIS_SSL_BUNDLE=infra-ca`
- `ext-authz` uses `REDIS_ADDR=localhost:6379`, `REDIS_USERNAME=ext-authz`, `REDIS_EXT_AUTHZ_PASSWORD` from `.env`, `REDIS_TLS=true`, and `REDIS_CA_CERT` pointing at the `infra-ca` PEM
- `redis-ops` is the maintenance identity for manual `redis-cli` access and `FLUSHALL`; use `redis-cli --tls --cacert ./nginx/certs/infra/infra-ca.pem --user redis-ops --pass "$REDIS_OPS_PASSWORD" -h localhost -p 6379 ...`
- `default` is probe-only and should not be used by application code
- `session-gateway` owns the long-lived `session:{id}` hashes plus the temporary `oauth2:state:{state}` OAuth2 request state, while ext-authz reads only the `session:*` namespace
- active browser sessions are extended through same-origin `GET /auth/session` heartbeats from the frontend; bare `/login` stays frontend-owned and only kicks off the real OAuth2 flow through `/oauth2/authorization/idp`
- The in-cluster Redis Deployment now runs with `readOnlyRootFilesystem: true`; local ACL bootstrap still writes `/tmp/users.acl`, and Redis AOF writes to `/data` on an `emptyDir`, so cache/session durability remains intentionally ephemeral in local dev. Production persistence would require a PVC-backed `/data` volume.

RabbitMQ local access:
- Management UI: `http://localhost:15672`
- Management username: `rabbitmq-admin`
- Management password: value from `RABBITMQ_BOOTSTRAP_PASSWORD`
- AMQP username for `currency-service`: `currency-service` (or override with `SPRING_RABBITMQ_USERNAME`)
- AMQP password for `currency-service`: set `SPRING_RABBITMQ_PASSWORD` from `RABBITMQ_CURRENCY_SERVICE_PASSWORD`
- AMQPS port: `5671`
- Direct `bootRun` must set `SPRING_RABBITMQ_SSL_ENABLED=true`, `SPRING_RABBITMQ_SSL_BUNDLE=infra-ca`, and `INFRA_CA_CERT_PATH` to the host-side `infra-ca.pem`
- Virtual host: `/`
- The in-cluster RabbitMQ StatefulSet now runs as UID/GID `999` with `fsGroup: 999` and `readOnlyRootFilesystem: true`; `/var/lib/rabbitmq` remains the only writable runtime path and stays PVC-backed, while the config, definitions, and TLS material stay mounted read-only.

Activate with:
```bash
./gradlew bootRun --args='--spring.profiles.active=local'
```

### Frontend (React)

Create `.env.local`:

```bash
# API Base URL (relative, served through same origin)
VITE_API_BASE_URL=/api

# Feature flags (optional)
VITE_ENABLE_ANALYTICS=true
```

## Troubleshooting

### Port Already in Use (Tilt)

If you see this error when running `tilt up`:
```
Error: Tilt cannot start because you already have another process on port 10350
```

**Check what's using the port:**
```bash
lsof -i :10350
```

**Common cause:** VS Code port forwarding is reserving the port. If you see `code` as the process:
```
COMMAND    PID  USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
code    151299 devex   93u  IPv4 584246      0t0  TCP localhost:10350 (LISTEN)
```

**Solution:** Disable VS Code auto port forwarding in your user settings:
```json
{
  "remote.autoForwardPorts": false
}
```

Then restart VS Code. See the [Sandboxed Container Configuration](#sandboxed-container-configuration) section for more details.

### Pod Not Starting

```bash
# Check pod status and events
kubectl describe pod -n default <pod-name>

# Check logs
kubectl logs -n default <pod-name>

# Check Tilt UI for compile errors
# http://localhost:10350
```

### Database Connection Refused

```bash
# Check if PostgreSQL is running
kubectl get pods -n infrastructure | grep postgresql

# View PostgreSQL logs
kubectl logs -n infrastructure postgresql-0

# Verify port forward is active
kubectl port-forward -n infrastructure svc/postgresql 5432:5432
```

### Service Not Responding

```bash
# Check service endpoints
kubectl get endpoints -n default <service-name>

# Check service logs
kubectl logs -n default deployment/<service-name>

# Check if service is healthy
curl http://localhost:<port>/actuator/health
```

### NGINX Gateway Issues

```bash
# Check NGINX config syntax
kubectl exec -n default deployment/nginx-gateway -- nginx -t

# View NGINX logs
kubectl logs -n default deployment/nginx-gateway

# Trigger config reload
tilt trigger nginx-gateway-config
```

### Istio Ingress Gateway Issues

```bash
# Check Istio ingress gateway pod
kubectl get pods -n istio-ingress
kubectl logs -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway

# Check the rendered ingress ServiceAccount/principal basis
kubectl get deploy,sa -n istio-ingress -o yaml | rg 'istio-ingress-gateway-istio|serviceAccountName'

# Check Gateway status
kubectl get gateway -n istio-ingress istio-ingress-gateway

# Check HTTPRoute status
kubectl get httproute -n default

# Verify ext_authz is configured
kubectl get cm istio -n istio-system -o yaml | grep ext-authz-http
```

### SSL Certificate Errors

```bash
# Re-run browser-facing wildcard certificate setup on HOST
./scripts/dev/setup-k8s-tls.sh

# Verify wildcard secret exists
kubectl get secret -n default budgetanalyzer-localhost-wildcard-tls

# Re-run internal transport-TLS setup on HOST
./scripts/dev/setup-infra-tls.sh

# Verify infra secrets exist
kubectl get secret -n default infra-ca
kubectl get secret -n infrastructure infra-tls-postgresql infra-tls-redis infra-tls-rabbitmq

# Restart browser to clear certificate cache
```

## IDE Setup

> **Note:** IntelliJ IDEA is not supported. It cannot run containerized AI agents, making it unsuitable for AI-assisted development workflows.

### VS Code

**Extensions:**
- Spring Boot Extension Pack
- Gradle for Java
- ESLint (for frontend)
- Prettier (for frontend)
- Kubernetes (for cluster inspection)

**workspace.code-workspace:**
```json
{
  "folders": [
    {"path": "orchestration"},
    {"path": "service-common"},
    {"path": "transaction-service"},
    {"path": "currency-service"},
    {"path": "session-gateway"},
    {"path": "permission-service"},
    {"path": "budget-analyzer-web"}
  ]
}
```

**Sandboxed Container Configuration:**

When running VS Code in a sandboxed container (e.g., for AI agent development), disable automatic port forwarding to ensure complete isolation:

```json
// VS Code User Settings (not workspace settings)
{
  "remote.autoForwardPorts": false
}
```

**Why disable port forwarding?**
- **True isolation**: No accidental leakage between container and host
- **No port conflicts**: VS Code won't claim ports needed by Tilt or other services
- **Cleaner workflow**: No need to manage or kill processes on the host

**Note:** This setting goes in your VS Code user settings (`Ctrl/Cmd + ,`), not in the workspace `.vscode/settings.json` file.

## Next Steps

- **Database:** [database-setup.md](database-setup.md)
- **Architecture:** [../architecture/system-overview.md](../architecture/system-overview.md)
