# Budget Analyzer - System Overview

**Date:** 2025-11-24
**Status:** Active

## Request Flow

**Browser traffic always goes through Session Gateway.** Think of it as a maxiservice - the browser connects to one thing.

```
BROWSER REQUEST FLOW
====================

Browser (https://app.budgetanalyzer.localhost)
    │
    ▼ HTTPS
Envoy Gateway (:443) ─── SSL termination
    │
    ▼ HTTP
Session Gateway (:8081) ─── JWT lookup from Redis, inject into header
    │
    ▼ HTTPS
Envoy Gateway (:443) ─── routes to api.budgetanalyzer.localhost
    │
    ▼ HTTP
NGINX Gateway (:8080) ─── JWT validation, route to service
    │
    ▼ HTTP
Backend Services ─── business logic, data authorization
```

**Two entry points, same pattern:**
- `app.budgetanalyzer.localhost` → Envoy → Session Gateway (browser auth, stores JWT in Redis)
- `api.budgetanalyzer.localhost` → Envoy → NGINX (API gateway, validates JWT)

**Why this works:**
- Browser never sees JWT (XSS protection)
- Single origin = no CORS
- Envoy handles all SSL
- NGINX validates every request

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
│              (SSL termination, ingress routing)              │
└─────────┬──────────────────────────┬────────────────────────┘
          │ app.*                    │ api.*
          ▼                          ▼
┌──────────────────────┐   ┌──────────────────────────────────┐
│   Session Gateway    │   │         NGINX API Gateway         │
│   (BFF, OAuth2)      │──▶│   (JWT validation, routing)       │
│   :8081              │   │   :8080                           │
└──────────────────────┘   └─────────┬────────────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
│  Transaction Service │ │   Currency Service   │ │  Permission Service  │
│   :8082              │ │   :8084              │ │   :8086              │
└──────────┬───────────┘ └─────────┬────────────┘ └──────────┬───────────┘
           │                       │                         │
           ▼                       ▼                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Shared Infrastructure                           │
│  • PostgreSQL (primary database)                             │
│  • Redis (session storage, caching)                          │
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
- Ingress routing based on hostname
- Kubernetes Gateway API compliant

**Session Gateway (BFF)** (Port 8081)
- OAuth2 authentication with Auth0
- Session management via Redis
- JWT storage (never exposed to browser)

**NGINX API Gateway** (Port 8080)
- JWT validation via Token Validation Service
- Resource-based routing
- Load balancing

**Token Validation Service** (Port 8088)
- JWT signature verification
- JWKS integration with Auth0

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

**permission-service** (Port 8086)
- Domain: User permissions and authorization
- Key features: Role-based access control
- Database: PostgreSQL (permissions, roles)

### Infrastructure Services

**PostgreSQL**
- Primary database for all services
- Service-specific databases
- Managed via Flyway migrations per service

**Redis**
- Session storage (Session Gateway)
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
- Envoy Gateway (ingress)
- NGINX (API gateway)

## Service Communication Patterns

### Synchronous (REST)
- Frontend → Envoy → Session Gateway → NGINX → Services
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
- **Session storage**: Used by session-gateway
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
- BFF pattern (browser never sees JWT)
- Redis-backed session management
- Token refresh and lifecycle

**Authorization Infrastructure:**
- permission-service: Roles, permissions, delegations
- Temporal tracking for compliance
- Cascading revocation
- Audit logging

**Gateway Patterns:**
- Envoy: SSL termination, ingress
- Session Gateway: Session-to-JWT translation
- NGINX: JWT validation, resource routing
- Token Validation Service: JWKS-based verification

### What's Left as an Exercise

**Data Ownership** - the core unsolved problem:
- Which transactions belong to which user?
- How does transaction-service know to filter queries by owner?
- How does user identity propagate from gateway to data layer?

**Cross-Service User Scoping:**
- Services receive a validated JWT with user identity
- But: No implemented pattern for scoping queries by that identity
- This is domain-specific and we're not prescribing a solution

**Multi-Tenancy:**
- permission-service schema includes `organization_id`
- But: Organization-level isolation is not implemented
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
kubectl get pods -n budget-analyzer

# View service endpoints
kubectl get svc -n budget-analyzer

# View API routes
grep "location /api" nginx/nginx.k8s.conf | grep -v "#"
```

## References

- [security-architecture.md](security-architecture.md) - Security design
- [resource-routing-pattern.md](resource-routing-pattern.md) - Gateway routing details
- [service-communication.md](service-communication.md) - Inter-service communication
- [001-orchestration-repo.md](../decisions/001-orchestration-repo.md) - Why this repo exists
- [002-resource-based-routing.md](../decisions/002-resource-based-routing.md) - Routing decision
