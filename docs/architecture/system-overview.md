# Budget Analyzer - System Overview

**Date:** 2025-11-10
**Status:** Active

## Architecture Overview

Budget Analyzer is a microservices-based financial management system with a React frontend, Spring Boot backend services, and NGINX API gateway.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Budget Analyzer Web                     │
│                    (React 19 + TypeScript)                   │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTP/REST
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     NGINX API Gateway                        │
│              (Resource-based routing: /api/*)                │
└─────────┬──────────────────────────┬────────────────────────┘
          │                          │
          ▼                          ▼
┌──────────────────────┐   ┌──────────────────────┐
│  Transaction Service │   │   Currency Service   │
│   (Spring Boot)      │   │   (Spring Boot)      │
│   Port: 8082         │   │   Port: 8084         │
└──────────┬───────────┘   └─────────┬────────────┘
           │                         │
           ▼                         ▼
┌─────────────────────────────────────────────────┐
│              Shared Infrastructure              │
│  • PostgreSQL (primary database)                │
│  • Redis (distributed caching)                  │
│  • RabbitMQ (async messaging)                   │
└─────────────────────────────────────────────────┘
```

## Services

### Frontend Services

**budget-analyzer-web**
- React 19 single-page application
- Features: Transaction management, CSV import, search, analytics
- Development port: 3000
- Production: Static assets served via NGINX

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

**NGINX API Gateway** (Port 8080)
- Unified entry point for all API calls
- Resource-based routing (see [002-resource-based-routing.md](../decisions/002-resource-based-routing.md))
- TLS termination (production)

**PostgreSQL**
- Primary database for all services
- Service-specific schemas
- Managed via Flyway migrations per service

**Redis**
- Distributed caching (currency-service)
- Session storage (future)

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
- See: [@service-common/docs/](https://github.com/budget-analyzer/service-common/tree/main/docs)

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
cat service-common/pom.xml | grep '<spring-boot.version>'

# Infrastructure versions
docker compose config | grep 'image:' | sort -u
```

### Core Technologies

**Frontend:**
- React 19 with TypeScript
- Vite (build tool)
- TanStack Query (server state)
- Redux Toolkit (UI state)

**Backend:**
- Spring Boot 3.x
- Java 21
- Pure JPA (Jakarta Persistence API)
- Spring Modulith (modularity + events)

**Infrastructure:**
- Docker & Docker Compose
- PostgreSQL 16+
- Redis 7+
- RabbitMQ 3.x
- NGINX (Alpine-based)

## Service Communication Patterns

### Synchronous (REST)
- Frontend → Gateway → Services
- Used for: User-initiated actions, queries

### Asynchronous (Events)
- Service → RabbitMQ → Service
- Used for: Background processing, cross-service notifications
- Pattern: Spring Modulith transactional outbox

### External APIs
- currency-service → FRED API
- Pattern: Provider abstraction (see [@service-common/docs/advanced-patterns.md](https://github.com/budget-analyzer/service-common/blob/main/docs/advanced-patterns.md))

## Data Management

### Database Strategy
- **Per-service schemas**: Each service owns its schema
- **No shared tables**: Services never share database tables
- **Flyway migrations**: Version-controlled schema evolution
- **PostgreSQL**: Single instance, multiple schemas (local dev)

### Caching Strategy
- **Redis distributed cache**: Used by currency-service
- **TTL-based expiration**: Configurable per cache
- **Cache-aside pattern**: Services manage cache population

### Data Consistency
- **Eventual consistency**: For cross-service data
- **Transactional outbox**: Guarantees event delivery
- **Idempotent consumers**: Services handle duplicate events

## Deployment Architecture

### Local Development
- Docker Compose orchestration
- Hot reload for all services
- Ports: 3000 (web), 8080 (gateway), 8082+ (services)

### Production (Future)
- Kubernetes deployment
- Horizontal scaling per service
- Service mesh (future consideration)
- Distributed tracing (future)

## Discovery Commands

```bash
# List all services
docker compose config --services

# View service configurations
docker compose config

# Check running services
docker compose ps

# View API routes
grep "location /api" nginx/nginx.dev.conf | grep -v "#"
```

## References

- [security-architecture.md](security-architecture.md) - Security design
- [resource-routing-pattern.md](resource-routing-pattern.md) - Gateway routing details
- [service-communication.md](service-communication.md) - Inter-service communication
- [001-orchestration-repo.md](../decisions/001-orchestration-repo.md) - Why this repo exists
- [002-resource-based-routing.md](../decisions/002-resource-based-routing.md) - Routing decision
