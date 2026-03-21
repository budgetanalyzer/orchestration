# Budget Analyzer - System Overview

**Date:** 2025-11-24
**Status:** Active

## Request Flow

**Single entry point**: `app.budgetanalyzer.localhost`. Envoy handles SSL termination and ext_authz enforcement.

```
BROWSER REQUEST FLOW
====================

Browser (https://app.budgetanalyzer.localhost)
    │
    ▼ HTTPS
Envoy Gateway (:443) ─── SSL termination, ext_authz on /api/* paths
    │
    ├─ /auth/*, /login/*, /logout → Session Gateway (:8081) ─── auth lifecycle
    │
    ├─ /api/* → ext_authz (:9002) validates session from Redis
    │           ├─ injects X-User-Id, X-Roles, X-Permissions headers
    │           └─ NGINX Gateway (:8080) ─── routes to backend service
    │
    └─ /* → NGINX Gateway (:8080) ─── serves frontend (no auth required)
    │
    ▼ HTTP
Backend Services ─── business logic, data authorization
```

**Why this works:**
- Browser never sees tokens (XSS protection)
- Single origin = no CORS
- Envoy handles all SSL
- ext_authz validates every API request
- Session revocation is instant (Redis key delete)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Budget Analyzer Web                     │
│                    (React 19 + TypeScript)                   │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      Envoy Gateway (:443)                    │
│       (SSL termination, ext_authz enforcement, routing)      │
└─────────┬──────────────────────────┬────────────────────────┘
          │ auth paths               │ /api/*, /*
          ▼                          ▼
┌──────────────────────┐   ┌──────────────────────┐
│   Session Gateway    │   │   ext_authz (:9002)  │
│   (BFF, OAuth2)      │   │   session validation │
│   :8081              │   └──────────┬───────────┘
└───────┬──────────────┘              │ headers injected
        │                             ▼
        ▼                   ┌──────────────────────────────────┐
┌──────────────────────┐   │         NGINX API Gateway         │
│  Permission Service  │   │   (routing, rate limiting)        │
│   :8086              │   │   :8080                           │
└──────────────────────┘   └─────────┬────────────────────────┘
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
│  • Redis (session storage + ext_authz schema, caching)       │
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

**Envoy Gateway** (Port 443)
- SSL/TLS termination
- ext_authz enforcement on `/api/*` paths
- Ingress routing based on path
- Kubernetes Gateway API compliant

**ext_authz Service** (Port 9002 HTTP, Port 8090 Health)
- Per-request session validation via Redis lookup
- Header injection (X-User-Id, X-Roles, X-Permissions)
- Go HTTP service implementing Envoy ext_authz protocol

**Session Gateway (BFF)** (Port 8081)
- OAuth2 authentication with Auth0
- Session management via Redis
- Auth0 token storage; dual-writes session data to ext_authz Redis schema (never exposed to browser)
- Calls permission-service to enrich session with roles/permissions
- Token exchange endpoint for native/M2M clients

**NGINX API Gateway** (Port 8080)
- Resource-based routing
- Rate limiting
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
- Session storage (Session Gateway - Spring Session + ext_authz schema)
- Distributed caching (currency-service)

**RabbitMQ**
- Async messaging between services
- Event-driven architecture (Spring Modulith)

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
- Different: Resource limits, replication, monitoring

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
- Envoy Gateway (ingress + ext_authz)
- NGINX (API gateway)

## Service Communication Patterns

### Synchronous (REST)
- Frontend → Envoy → ext_authz → NGINX → Services
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
- **Session storage**: Used by session-gateway (Spring Session + ext_authz schema)
- **TTL-based expiration**: Configurable per cache
- **Cache-aside pattern**: Services manage cache population

### Data Consistency
- **Eventual consistency**: For cross-service data
- **Transactional outbox**: Guarantees event delivery
- **Idempotent consumers**: Services handle duplicate events

## Intentional Boundaries

This reference architecture deliberately stops before solving data ownership. Understanding where we stopped - and why - is as valuable as understanding what we built.

### What's Implemented

**Authentication & Sessions:**
- OAuth2/OIDC flows with Auth0
- BFF pattern (browser never sees tokens)
- Redis-backed session management
- Token refresh and lifecycle

**Platform Security Baseline (Phase 0):**
- Kind uses `disableDefaultCNI` with pinned Calico in local development so `NetworkPolicy` is enforceable
- Namespace Pod Security Admission labels are applied in `warn`/`audit` mode
- Kyverno is installed with a smoke policy and verified by `scripts/dev/verify-security-prereqs.sh`
- ext_authz dual-write for per-request validation

**Gateway Patterns:**
- Envoy: SSL termination, ext_authz enforcement, ingress
- Session Gateway: Auth lifecycle, session dual-write to ext_authz Redis schema
- ext_authz: Per-request session validation, header injection
- NGINX: Resource routing, rate limiting

### What's Left as an Exercise

**Data Ownership** - the core unsolved problem:
- Which transactions belong to which user?
- How does transaction-service know to filter queries by owner?
- How does user identity propagate from gateway to data layer?

**Cross-Service User Scoping:**
- Services receive validated identity via X-User-Id, X-Roles, X-Permissions headers
- But: No implemented pattern for scoping queries by that identity
- This is domain-specific and we're not prescribing a solution

**Multi-Tenancy:**
- Organization-level isolation is not implemented
- Patterns exist (row-level security, tenant headers) - we leave the choice to you

### Why This Boundary?

Data ownership is deeply domain-specific. A financial app might scope by account ownership, delegation chains, or organization membership. A SaaS product might use tenant IDs. A social app might use visibility rules.

We demonstrate the infrastructure. You architect the ownership model.

## Deployment Architecture

### Local Development
- Tilt + Kind orchestration
- Live reload for all services
- HTTPS: https://app.budgetanalyzer.localhost (Envoy Gateway 443)
- Port forwards for direct service access

### Production (Future)
- Kubernetes deployment
- Horizontal scaling per service
- Service mesh (future consideration)
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
