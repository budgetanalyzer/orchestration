# Budget Analyzer - System Overview

**Date:** 2026-04-22
**Status:** Active

## Purpose

This document is the high-level map of the Budget Analyzer runtime. It
summarizes the major layers and why they exist without re-owning the exact
contracts that live elsewhere.

Canonical topic owners for exact detail:

- Request flow, route ownership, and browser session contract:
  [session-edge-authorization-pattern.md](session-edge-authorization-pattern.md)
- Security controls and rationale:
  [security-architecture.md](security-architecture.md)
- Ports and service exposure:
  [port-reference.md](port-reference.md)
- Observability access and operator workflows:
  [observability.md](observability.md)
- Unified `/api-docs` surface:
  [../../docs-aggregator/README.md](../../docs-aggregator/README.md)

## Request Flow

**Single browser entry point**: `https://app.budgetanalyzer.localhost`

```
Browser
   │
   ▼
Istio Ingress Gateway
   ├─ Auth lane → Session Gateway
   └─ App/API lane → ext_authz → NGINX Gateway → Backend Services
                                              │
                                              ├─ PostgreSQL
                                              ├─ Redis
                                              └─ RabbitMQ
```

The important split is:

- Session Gateway owns browser authentication and session lifecycle.
- `ext_authz` validates every browser `/api/*` request before NGINX forwards
  it to a backend.
- NGINX owns resource-based routing and backend/API rate limiting.
- Backend services own business logic and data-level authorization.

This gives the repo a same-origin browser surface, keeps tokens out of the
browser, and preserves the same gateway layering in local Tilt and OCI/k3s.

Operational note: `./scripts/smoketest/verify-security-prereqs.sh` proves the
platform security prerequisites. Treat Istio ingress and egress hardening as
verified only after `./scripts/smoketest/verify-phase-3-istio-ingress.sh` and
the live validation checklist pass.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Budget Analyzer Web                    │
│                    (React 19 + TypeScript)                 │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Istio Ingress Gateway                    │
│      (TLS termination, auth throttling, routing, ext_authz)│
└─────────┬──────────────────────────┬────────────────────────┘
          │ auth lane                │ app/API lane
          ▼                          ▼
┌──────────────────────┐   ┌──────────────────────┐
│   Session Gateway    │   │      ext_authz       │
│  (OAuth2, sessions)  │   │  session validation  │
└───────┬──────────────┘   └──────────┬───────────┘
        │                             │ trusted headers
        ▼                             ▼
┌──────────────────────┐   ┌──────────────────────────────────┐
│  Permission Service  │   │         NGINX API Gateway        │
│ roles/permissions +  │   │   routing and backend throttling │
│ bulk session revoke  │   └─────────┬────────────────────────┘
└──────────────────────┘             │
                                     ▼
                 ┌──────────────────────┬──────────────────────┐
                 │  Transaction Service │   Currency Service   │
                 └──────────┬───────────┴─────────┬────────────┘
                            ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Shared Infrastructure                    │
│        PostgreSQL • Redis • RabbitMQ • Monitoring           │
└─────────────────────────────────────────────────────────────┘
```

## Service Layers

### Frontend

`budget-analyzer-web` is a React single-page application. In local development
it runs through the Vite-based workflow; in production-style flows NGINX serves
the built frontend assets.

### Edge and Routing

Istio ingress, Session Gateway, `ext_authz`, NGINX, and Istio egress form the
control plane at the application edge:

- Istio ingress terminates TLS, applies auth-path throttling, and enforces
  `ext_authz` on browser API traffic.
- Session Gateway owns OAuth2 login, logout, and browser session renewal.
- `ext_authz` converts the Redis-backed browser session into trusted identity
  headers on every API request.
- NGINX maps resource routes to backend services and applies backend/API rate
  limiting.
- Istio egress owns the approved outbound paths to external providers such as
  Auth0 and FRED.

See [session-edge-authorization-pattern.md](session-edge-authorization-pattern.md)
for the detailed request-flow and route-ownership contract.

### Business Services

- `transaction-service` owns transaction and budget workflows.
- `currency-service` owns currency and exchange-rate workflows.
- `permission-service` supplies roles and permissions to Session Gateway and
  triggers bulk browser-session revocation when user state changes.

### Shared Infrastructure and Observability

- PostgreSQL is the primary relational store.
- Redis stores browser sessions and selected service caches.
- RabbitMQ carries asynchronous inter-service events.
- Prometheus, Grafana, Jaeger, Kiali, and kube-state-metrics run in the
  `monitoring` namespace and remain internal-only.

See [observability.md](observability.md) for the operator access model and
[port-reference.md](port-reference.md) for the exact service-exposure contract.

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
- See: [service-common/docs/](https://github.com/budgetanalyzer/service-common/tree/main/docs)

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
- Pattern: Provider abstraction (see [service-common/docs/advanced-patterns.md](https://github.com/budgetanalyzer/service-common/blob/main/docs/advanced-patterns.md))

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
- Istio service mesh (mTLS, AuthorizationPolicy, egress control)
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
