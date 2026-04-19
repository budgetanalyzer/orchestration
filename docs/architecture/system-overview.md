# Budget Analyzer - System Overview

**Date:** 2025-11-24
**Status:** Active

## Request Flow

**Single entry point**: `app.budgetanalyzer.localhost`. Istio ingress gateway handles SSL termination, auth-path throttling, and ext_authz enforcement.

```
BROWSER REQUEST FLOW
====================

Browser (https://app.budgetanalyzer.localhost)
    │
    ▼ HTTPS
Istio Ingress Gateway (:443) ─── SSL termination, ext_authz on /api/* paths, auth-path rate limiting
    │
    ├─ /auth/*, /oauth2/*, /login/oauth2/*, /logout → Session Gateway (:8081) ─── auth lifecycle
    │
    ├─ /api/* → ext_authz (:9002) validates session from Redis
    │           ├─ injects X-User-Id, X-Roles, X-Permissions headers
    │           └─ NGINX Gateway (:8080) ─── routes to backend service
    │
    └─ /login, /* → NGINX Gateway (:8080) ─── serves frontend (no auth required)
    │
    ▼ HTTP
Backend Services ─── business logic, data authorization
```

**Why this works:**
- Browser never sees tokens (XSS protection)
- Single origin = no CORS
- Istio ingress handles all SSL
- ext_authz validates every API request
- Session revocation is instant (Redis key delete)

Operational note: `./scripts/smoketest/verify-security-prereqs.sh` proves the platform security prerequisites. Treat Istio ingress and egress hardening as verified only after `./scripts/smoketest/verify-phase-3-istio-ingress.sh` and the live validation checklist pass.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Budget Analyzer Web                     │
│                    (React 19 + TypeScript)                   │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                Istio Ingress Gateway (:443)                   │
│   (SSL termination, auth-path throttling, ext_authz, routing)│
└─────────┬──────────────────────────┬────────────────────────┘
          │ auth paths               │ /api/*, /*
          ▼                          ▼
┌──────────────────────┐   ┌──────────────────────┐
│   Session Gateway    │   │   ext_authz (:9002)  │
│   (OAuth2, Sessions) │   │   session validation │
│   :8081              │   └──────────┬───────────┘
└───────┬──────────────┘              │ headers injected
        │                             ▼
        ▼                   ┌──────────────────────────────────┐
┌──────────────────────┐   │         NGINX API Gateway         │
│  Permission Service  │   │   (routing, backend/API rate      │
│   :8086              │   │    limiting)                      │
└──────────────────────┘   │   :8080                           │
                           └─────────┬────────────────────────┘
                                     │
                          ┌──────────┴──────────────────────┐
                          ▼                                 ▼
                 ┌──────────────────────┐  ┌──────────────────────┐
                 │  Transaction Service │  │   Currency Service   │
                 │   :8082              │  │   :8084              │
                 └──────────┬───────────┘  └─────────┬────────────┘
          │                                            │
          ▼                                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Shared Infrastructure                           │
│  • PostgreSQL (primary database)                             │
│  • Redis (session hash storage, caching)                     │
│  • RabbitMQ (async messaging)                                │
└─────────────────────────────────────────────────────────────┘
```

## Services

### Frontend Services

**budget-analyzer-web**
- React 19 single-page application
- Features: Transaction management, CSV import, search, analytics
- Development port: 3000
- Production: Static assets served via NGINX

### Gateway Services

**Istio Ingress Gateway** (Port 443)
- SSL/TLS termination
- ext_authz enforcement on `/api/*` paths via meshConfig extensionProvider
- Auth-path throttling on `/login`, `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, and `/logout`
- Ingress routing based on path (Gateway API HTTPRoutes)
- Kubernetes Gateway API compliant
- Runs inside the Istio service mesh with SPIFFE identity

**Istio Egress Gateway** (ClusterIP, istio-egress namespace)
- Routes approved outbound traffic (Auth0, FRED API) via ServiceEntry + VirtualService
- Uses TLS `PASSTHROUGH`; workload-to-egress traffic keeps `tls.mode: DISABLE` so the original external TLS/SNI reaches the gateway unchanged
- Enforces REGISTRY_ONLY outbound policy — unapproved hosts are blocked
- Only gateway pod with external internet access (NetworkPolicy enforced)

**ext_authz Service** (Port 9002 HTTP, Port 8090 Health)
- Per-request session validation via Redis lookup
- Header injection (X-User-Id, X-Roles, X-Permissions)
- Go HTTP service implementing Envoy ext_authz protocol

**Session Gateway** (Port 8081)
- OAuth2 authentication with Auth0
- Session management via Redis hashes (`session:{id}`)
- No Auth0 tokens stored after login — session hashes hold only user identity and permissions
- Heartbeat endpoint `GET /auth/v1/session` extends the session TTL for active browser users (2-minute frontend default cadence; heartbeat is local Redis only, no Auth0 calls)
- Calls permission-service to enrich session with roles/permissions

**NGINX API Gateway** (Port 8080)
- Resource-based routing
- Backend/API rate limiting
- Load balancing

### Backend Microservices

**transaction-service** (Port 8082)
- Domain: Transactions and budgets
- Key features: CSV import (multi-bank), transaction CRUD, advanced search
- Database: PostgreSQL (transactions, budgets, categories)

**currency-service** (Port 8084)
- Domain: Currencies and exchange rates
- Key features: FRED API integration, scheduled imports, distributed caching
- Database: PostgreSQL (currencies, exchange rates)
- External: Federal Reserve Economic Data (FRED)

### Infrastructure Services

**PostgreSQL**
- Primary database for all services
- Service-specific databases
- Managed via Flyway migrations per service

**Redis**
- Session storage (Session Gateway writes `session:{id}` hashes, ext_authz reads them)
- Distributed caching (currency-service)

**RabbitMQ**
- Async messaging between services
- Event-driven architecture (Spring Modulith)

### Monitoring Services

**Prometheus** (Port 9090, `monitoring` namespace)
- Metrics scraping and storage (10Gi PVC)
- Scrapes Spring Boot actuator endpoints, istiod, and Envoy sidecars
- Mesh-injected for STRICT mTLS compliance
- Access via port-forward only

**Grafana** (Port 80, `monitoring` namespace)
- Dashboard visualization
- Pre-provisioned JVM and Spring Boot dashboards
- Exposed at `https://grafana.budgetanalyzer.localhost` via Istio ingress

**kube-state-metrics** (`monitoring` namespace)
- Kubernetes resource metrics for Prometheus

See [Observability Architecture](observability.md) for details.

## Key Architectural Principles

### 1. Resource-Based Routing
Frontend is decoupled from service topology. Routes map to resources, not services.
- See: [002-resource-based-routing.md](../decisions/002-resource-based-routing.md)

### 2. Service Independence
Each service:
- Owns its database schema
- Can be deployed independently
- Has its own release cycle
- Manages its own dependencies (inherits from service-common)

### 3. Shared Patterns
Common patterns documented once in service-common:
- Spring Boot conventions
- Testing patterns
- Error handling
- Code quality standards
- See: [@service-common/docs/](https://github.com/budgetanalyzer/service-common/tree/main/docs)

### 4. Production Parity
Local development environment mirrors production architecture:
- Same services
- Same infrastructure (PostgreSQL, Redis, RabbitMQ)
- Same gateway routing
- Different: Resource limits, replication

### 5. Event-Driven Communication
Services communicate asynchronously where possible:
- Spring Modulith transactional outbox
- RabbitMQ for inter-service events
- Ensures eventual consistency

## Technology Stack

### Discovery Commands

```bash
# Frontend framework
cat budget-analyzer-web/package.json | grep '"react"'

# Spring Boot version (canonical source)
cat service-common/build.gradle.kts | grep 'springBootVersion'

# List all Tilt resources
tilt get uiresources
```

### Core Technologies

**Frontend:**
- React 19 with TypeScript
- Vite (build tool)
- TanStack Query (server state)
- Redux Toolkit (UI state)

**Backend:**
- Spring Boot 3.x
- Java 24
- Pure JPA (Jakarta Persistence API)
- Spring Modulith (modularity + events)

**Infrastructure:**
- Kubernetes (Kind for local dev)
- Tilt (development orchestration)
- PostgreSQL 16+
- Redis 7+
- RabbitMQ 3.x
- Istio Ingress Gateway (ingress + ext_authz) and Egress Gateway (outbound control)
- NGINX (API gateway)

## Service Communication Patterns

### Synchronous (REST)
- Frontend → Istio Ingress → ext_authz → NGINX → Services
- Used for: User-initiated actions, queries

### Asynchronous (Events)
- Service → RabbitMQ → Service
- Used for: Background processing, cross-service notifications
- Pattern: Spring Modulith transactional outbox

### External APIs
- currency-service → FRED API
- Pattern: Provider abstraction (see [@service-common/docs/advanced-patterns.md](https://github.com/budgetanalyzer/service-common/blob/main/docs/advanced-patterns.md))

## Data Management

### Database Strategy
- **Per-service databases**: Each service owns its database
- **No shared tables**: Services never share database tables
- **Flyway migrations**: Version-controlled schema evolution
- **PostgreSQL**: Single instance, multiple databases (local dev)

### Caching Strategy
- **Redis distributed cache**: Used by currency-service
- **Session storage**: Used by session-gateway (Redis hashes, read by ext_authz)
- **TTL-based expiration**: Configurable per cache
- **Cache-aside pattern**: Services manage cache population

### Data Consistency
- **Eventual consistency**: For cross-service data
- **Transactional outbox**: Guarantees event delivery
- **Idempotent consumers**: Services handle duplicate events

## Deployment Architecture

### Local Development
- Tilt + Kind orchestration
- Live reload for all services
- HTTPS: https://app.budgetanalyzer.localhost (Istio Ingress Gateway 443)
- Port forwards for direct service access

### Production (Future)
- Kubernetes deployment
- Horizontal scaling per service
- Istio service mesh (mTLS, AuthorizationPolicy, egress control implemented)
- Distributed tracing (future)

## Discovery Commands

```bash
# List all Tilt resources
tilt get uiresources

# View pod status
kubectl get pods

# View service endpoints
kubectl get svc

# View API routes
grep "location /api" nginx/nginx.k8s.conf | grep -v "#"
```

## References

- [security-architecture.md](security-architecture.md) - Security design
- [resource-routing-pattern.md](resource-routing-pattern.md) - Gateway routing details
- [service-communication.md](service-communication.md) - Inter-service communication
- [001-orchestration-repo.md](../decisions/001-orchestration-repo.md) - Why this repo exists
- [002-resource-based-routing.md](../decisions/002-resource-based-routing.md) - Routing decision
