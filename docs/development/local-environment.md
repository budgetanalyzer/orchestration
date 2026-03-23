# Local Development Environment Setup

**Status:** Active
**Audience:** Developers setting up Budget Analyzer locally

## Prerequisites

### Required Software

**Minimum versions:**
- Docker 24.0+
- Kind 0.20+
- kubectl 1.28+
- Helm 3.20.x (tested; Helm 4 unsupported)
- Tilt 0.33+
- Git 2.40+
- mkcert 1.4+

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
helm version
tilt version
git --version
mkcert --version
```

Phase 3 no longer installs the Istio egress gateway from Helm at runtime. The
repo still uses Helm for `istio-base`, `istiod`, and `kyverno`, but the egress
gateway is a checked-in manifest rendered from `istio/gateway` `1.24.3`
because that chart's schema rejects the required `service.type=ClusterIP`
override under the tested Helm `v3.20.1` toolchain.

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
1. Creates or validates the Kind cluster
2. Rejects older `kindnet`-based clusters that cannot enforce `NetworkPolicy`
3. Installs pinned Calico and waits for CoreDNS readiness
4. Configures local DNS and TLS certificates
5. Installs Gateway API CRDs and prepares `.env`

If setup fails because you already have an older local Kind cluster:

```bash
kind delete cluster --name kind
./setup.sh
```

### 3. Configure Environment Variables

```bash
# Create the file if setup.sh did not already create it
[ -f .env ] || cp .env.example .env

# Review the local PostgreSQL, RabbitMQ, and Redis password defaults, then add
# your Auth0 and FRED credentials.
```

Tilt is the local secret producer for infrastructure credentials. The Kubernetes
manifests now consume named secrets only, which is the seam production can later
replace with another secret source.

### 4. Start All Services

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

# Optional but recommended: prove the Phase 2 network policy enforcement
./scripts/dev/verify-phase-2-network-policies.sh

# Optional but recommended: prove the Phase 3 Istio ingress/egress migration
./scripts/dev/verify-phase-3-istio-ingress.sh
```

The Phase 3 verifier is the runtime completion gate for ingress/egress hardening. It proves STRICT mTLS with paired sidecar and no-sidecar probes against a temporary in-mesh echo service, verifies ingress-identity denial with a wrong-identity probe, checks end-to-end identity-header sanitization through a temporary echo route, requires ingress auth throttling to return HTTP `429` plus the `x-local-rate-limit: auth-sensitive` marker on `/login` and `/user`, and inspects the forwarded-header chain that NGINX logs for both frontend and API traffic in development.

The current ingress-facing policy attachment facts are also part of that runtime story: the rendered ingress gateway pods are selected with `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway`, and the ingress-facing `AuthorizationPolicy` principals target `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`. Re-verify both after Istio upgrades before assuming Phase 3 policies still attach.

## Tilt Resources

### Compile Resources

Tilt compiles services locally using Gradle, then builds Docker images:

- `service-common-publish` - Publishes shared library to Maven Local
- `transaction-service-compile` - Compiles transaction service
- `currency-service-compile` - Compiles currency service
- `session-gateway-compile` - Compiles session gateway
### Infrastructure Resources

- `postgresql` - PostgreSQL StatefulSet
- `redis` - Redis Deployment
- `rabbitmq` - RabbitMQ StatefulSet
- `istio-ingress-config` - Istio ingress gateway (auto-provisioned from Gateway API)
- `istio-ingress-routes` - HTTPRoute and ext_authz policy resources
- `istio-egress-gateway` - Istio egress gateway (checked-in manifest)
- `istio-egress-config` - ServiceEntries and egress routing

## Development Workflows

### Workflow 1: Full Stack via Tilt (Recommended)

**Best for:** Most development scenarios

```bash
cd orchestration/
tilt up
```

**All services in Kubernetes:**
- Live reload for all services
- Automatic rebuilds on file changes
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
postgresql://transaction_service:${POSTGRES_TRANSACTION_SERVICE_PASSWORD:-budget-analyzer-transaction-service}@localhost:5432/budget_analyzer
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
| PostgreSQL | 5432 | localhost:5432 | Database access |
| Redis | 6379 | localhost:6379 | Cache access |
| RabbitMQ | 5672/15672 | localhost:15672 | Management UI |
| Tilt UI | 10350 | http://localhost:10350 | Development dashboard |

## Environment Variables

### Backend Services (Spring Boot)

Environment variables are injected via Kubernetes secrets. PostgreSQL Step 2
uses a `postgres_admin` bootstrap user plus dedicated service users. RabbitMQ
Step 3 now bootstraps `rabbitmq-admin` and `currency-service` from a
definitions file. Redis Step 4 now uses ACL users: a restricted `default` user
for probes plus dedicated `session-gateway`, `ext-authz`, `currency-service`,
and `redis-ops` identities.

Current local secret names:

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `postgresql-bootstrap-credentials` | `infrastructure` | PostgreSQL bootstrap admin + init inputs |
| `transaction-service-postgresql-credentials` | `default` | transaction-service database connection |
| `currency-service-postgresql-credentials` | `default` | currency-service database connection |
| `permission-service-postgresql-credentials` | `default` | permission-service database connection |
| `rabbitmq-bootstrap-credentials` | `infrastructure` | RabbitMQ admin access + boot-time definitions |
| `currency-service-rabbitmq-credentials` | `default` | currency-service AMQP connection |
| `redis-bootstrap-credentials` | `infrastructure` | Redis ACL bootstrap + probe credentials |
| `session-gateway-redis-credentials` | `default` | session-gateway Redis connection |
| `ext-authz-redis-credentials` | `default` | ext-authz Redis connection |
| `currency-service-redis-credentials` | `default` | currency-service Redis connection |

For local development outside Tilt, create `application-local.yml`:

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/budget_analyzer
    username: ${SPRING_DATASOURCE_USERNAME:transaction_service}
    password: ${SPRING_DATASOURCE_PASSWORD:}

  data:
    redis:
      host: ${SPRING_DATA_REDIS_HOST:localhost}
      port: ${SPRING_DATA_REDIS_PORT:6379}
      username: ${SPRING_DATA_REDIS_USERNAME:session-gateway}
      password: ${SPRING_DATA_REDIS_PASSWORD:}

  # Only currency-service needs RabbitMQ locally.
  rabbitmq:
    host: ${SPRING_RABBITMQ_HOST:localhost}
    port: ${SPRING_RABBITMQ_PORT:5672}
    username: ${SPRING_RABBITMQ_USERNAME:currency-service}
    password: ${SPRING_RABBITMQ_PASSWORD:}

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

Redis local access:
- `session-gateway` uses username `session-gateway`; direct `bootRun` should set `SPRING_DATA_REDIS_PASSWORD=$REDIS_SESSION_GATEWAY_PASSWORD`
- `currency-service` uses username `currency-service`; direct `bootRun` should set `SPRING_DATA_REDIS_PASSWORD=$REDIS_CURRENCY_SERVICE_PASSWORD`
- `ext-authz` uses `REDIS_HOST=localhost`, `REDIS_PORT=6379`, `REDIS_USERNAME=ext-authz`, and `REDIS_EXT_AUTHZ_PASSWORD` from `.env`
- `redis-ops` is the maintenance identity for manual `redis-cli` access and `FLUSHALL`
- `default` is probe-only and should not be used by application code

RabbitMQ local access:
- Management UI: `http://localhost:15672`
- Management username: `rabbitmq-admin`
- Management password: value from `RABBITMQ_BOOTSTRAP_PASSWORD`
- AMQP username for `currency-service`: `currency-service` (or override with `SPRING_RABBITMQ_USERNAME`)
- AMQP password for `currency-service`: set `SPRING_RABBITMQ_PASSWORD` from `RABBITMQ_CURRENCY_SERVICE_PASSWORD`
- Virtual host: `/`

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
# Re-run certificate setup on HOST
./scripts/dev/setup-k8s-tls.sh

# Verify secret exists
kubectl get secret -n default budgetanalyzer-localhost-wildcard-tls

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
