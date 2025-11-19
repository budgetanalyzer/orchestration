# Budget Analyzer - Orchestration Repository

## Project Overview

This orchestration repository coordinates the deployment and development environment for the Budget Analyzer application - a production-grade, microservices-based financial management system.

**Purpose**: Manages cross-service concerns, local development setup, and deployment coordination. Individual service code lives in separate repositories.

## Architecture Principles

- **Production Parity**: Development environment faithfully recreates production
- **Microservices**: Independently deployable services with clear boundaries
- **BFF Pattern**: Session Gateway provides browser security and authentication management
- **API Gateway Pattern**: NGINX provides unified routing, JWT validation, and load balancing
- **Resource-Based Routing**: Frontend remains decoupled from service topology
- **Defense in Depth**: Multiple security layers (Session Gateway → NGINX → Services)
- **Containerization**: Docker and Docker Compose for consistent environments

## Service Architecture

**Pattern**: Microservices defined in [docker compose.yml](docker compose.yml)

**Discovery**:
```bash
# List all services
docker compose config --services

# View service details and ports
docker compose config

# See running services
docker compose ps
```

**Service Types**:
- **Frontend services**: React-based web applications (typically port 3000 in dev)
- **Backend microservices**: Spring Boot REST APIs (ports 8082+, see docker compose.yml)
- **Session Gateway (BFF)**: Spring Cloud Gateway (port 8081) - browser authentication and session management
- **Token Validation Service**: Spring Boot service (port 8088) - JWT validation for NGINX
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (see docker compose.yml)
- **API Gateway**: NGINX reverse proxy (port 8080) - internal routing and JWT validation

**Adding New Services**:
1. Add service to [docker compose.yml](docker compose.yml)
2. Add routes to [nginx/nginx.dev.conf](nginx/nginx.dev.conf) if frontend-facing
3. Follow naming: `{domain}-service` for backends, `{domain}-web` for frontends

## BFF + API Gateway Hybrid Pattern

**Pattern**: Hybrid architecture combining Backend-for-Frontend (BFF) for browser security with API Gateway for routing and validation.

### Architecture Flow

**Browser Traffic** (OAuth2/Session-based):
```
Browser → Session Gateway (8081) → NGINX (8080) → Backend Services
```

**M2M Traffic** (Direct JWT):
```
API Client → NGINX (8080) → Backend Services
```

### Component Roles

**Session Gateway (Port 8081) - BFF Layer**:
- **Purpose**: Browser authentication and session security
- **Responsibilities**:
  - Manages OAuth2 flows with Auth0
  - Stores JWTs in Redis (server-side, never exposed to browser)
  - Issues HttpOnly session cookies to browsers
  - Proactive token refresh before expiration
  - Proxies authenticated requests to NGINX with JWT injection
- **Key Benefit**: Maximum security for browser-based financial application (JWTs never exposed to XSS)

**NGINX (Port 8080) - API Gateway Layer**:
- **Purpose**: Internal routing, JWT validation, and request processing
- **Responsibilities**:
  - Validates JWTs via Token Validation Service (auth_request directive)
  - Routes requests to appropriate microservices
  - Resource-based routing with path transformation
  - Rate limiting per user/IP
  - Load balancing and circuit breaking
  - Serves React frontend (proxied from Vite dev server in development)
- **Key Benefit**: Single source of truth for routing and validation

**Token Validation Service (Port 8088)**:
- **Purpose**: JWT signature verification for NGINX
- **Responsibilities**:
  - Verifies JWT signatures using Auth0 JWKS
  - Validates issuer, audience, and expiration claims
  - Called by NGINX via auth_request for every protected endpoint
- **Key Benefit**: Centralized JWT validation logic, defense in depth

### No CORS Needed

**Same-Origin Architecture**: All browser requests go through Session Gateway (localhost:8081), which proxies to NGINX, which routes to backends. Browser sees single origin = no CORS issues!

**Traditional architecture (CORS required)**:
```
Browser → Frontend (3000) → Backend Services (8082+)  ❌ Different origins
```

**Current architecture (No CORS)**:
```
Browser → Session Gateway (8081) → NGINX (8080) → Backend Services  ✅ Same origin
```

### Resource-Based Routing

**Pattern**: Frontend calls clean paths like `/api/transactions`, NGINX routes to appropriate microservice with path transformation.

**Quick Reference**:
- All routes defined in [nginx/nginx.dev.conf](nginx/nginx.dev.conf)
- Routing pattern: `location /api/{resource}` → `rewrite ^/api/(.*)$` → `proxy_pass http://{upstream}`
- JWT validation via `auth_request /auth/validate` on all protected routes
- Services use `host.docker.internal` to reach host services from Docker container
- WebSocket support included for React HMR (hot module replacement)
- Benefits: Frontend decoupled from service topology, services can be split/merged without frontend changes

**Discovery** (inspect routes without reading full config):
```bash
# List all API routes
grep "location /api" nginx/nginx.dev.conf | grep -v "#"

# Test Session Gateway (browser entry point)
curl -v http://localhost:8081/health

# Test NGINX Gateway (internal)
curl -v http://localhost:8080/health
```

**When to consult detailed nginx documentation**:
- Adding new API routes → Read "Adding a New Resource Route" in [nginx/README.md](nginx/README.md)
- Adding new microservices → Read "Adding a New Microservice" in [nginx/README.md](nginx/README.md)
- Moving resources between services → Read "Moving a Resource Between Services" in [nginx/README.md](nginx/README.md)
- Troubleshooting gateway issues → Read "Troubleshooting" section in [nginx/README.md](nginx/README.md)

### Port Summary

| Port | Service | Purpose | Access |
|------|---------|---------|--------|
| 8081 | Session Gateway | Browser entry point, authentication | Public (browsers) |
| 8080 | NGINX Gateway | Internal routing, JWT validation | Internal (Session Gateway, M2M) |
| 8088 | Token Validation | JWT signature verification | Internal (NGINX only) |
| 8082 | Transaction Service | Business logic | Internal (NGINX only) |
| 8084 | Currency Service | Business logic | Internal (NGINX only) |
| 3000 | React Dev Server | Frontend (dev only) | Internal (NGINX only) |

### Security Benefits

**Defense in Depth**:
1. **Session Gateway**: Prevents JWT exposure to browser (XSS protection)
2. **NGINX auth_request**: Validates every API request before routing
3. **Token Validation Service**: Cryptographic JWT verification
4. **Backend Services**: Data-level authorization (user owns resource)

**For detailed security architecture**: See [docs/architecture/security-architecture.md](docs/architecture/security-architecture.md)

## Technology Stack

**Principle**: Each service manages its own dependencies. Versions are defined in service-specific files.

**Discovery**:
```bash
# List infrastructure versions
docker compose config | grep 'image:' | sort -u

# Check service ports
grep -A 3 "ports:" docker compose.yml
```

**Stack Patterns**:
- **Frontend**: React (see individual service package.json)
- **Backend**: Spring Boot + Java (version managed in service-common)
- **Build System**: Gradle (all backend services use Gradle with wrapper)
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (see docker compose.yml)
- **Gateway**: NGINX (Alpine-based)

**Note**: Docker images should be pinned to specific versions for reproducibility.

## Development Workflow

### Prerequisites
- Docker and Docker Compose
- JDK 17+ (for local Spring Boot development)
- Node.js 18+ (for local React development)
- Git

### Quick Start
```bash
# Start all infrastructure
docker compose up -d

# View logs
docker compose logs -f

# Stop all services
docker compose down
```

### Troubleshooting

**Quick commands**:
```bash
# Check NGINX configuration validity
docker exec api-gateway nginx -t

# View NGINX logs
docker logs api-gateway

# Reload NGINX without downtime
docker exec api-gateway nginx -s reload

# Test service connectivity
docker compose ps
```

**For detailed troubleshooting**: When encountering specific issues (502 errors, CORS problems, HMR not working, connection refused, etc.), consult the comprehensive troubleshooting guide in [nginx/README.md](nginx/README.md)

## Repository Structure

**Discovery**:
```bash
# View structure
tree -L 2 -I 'node_modules|target'
```

**Key directories**:
- [nginx/](nginx/) - Gateway configuration (dev and prod)
- [scripts/](scripts/) - Automation and tooling
- [docs/](docs/) - Architecture and cross-service documentation
- [kubernetes/](kubernetes/) - Production deployment manifests

## Service Repositories

Each microservice is maintained in its own repository:
- **service-common**: https://github.com/budgetanalyzer/service-common - Shared library for all backend services
- **transaction-service**: https://github.com/budgetanalyzer/transaction-service - Transaction management API
- **currency-service**: https://github.com/budgetanalyzer/currency-service - Currency and exchange rate API
- **budget-analyzer-web**: https://github.com/budgetanalyzer/budget-analyzer-web - React frontend application
- **session-gateway**: https://github.com/budgetanalyzer/session-gateway - BFF for browser authentication
- **token-validation-service**: https://github.com/budgetanalyzer/token-validation-service - JWT validation for NGINX
- **basic-repository-template**: https://github.com/budgetanalyzer/basic-repository-template - Template for creating new services

## Best Practices

1. **Environment Parity**: Keep dev and prod configurations as similar as possible
2. **Configuration Management**: Use environment variables for configuration
3. **Health Checks**: All services expose health endpoints
4. **Service Independence**: Each microservice should be independently deployable
5. **API Versioning**: Version APIs to support backward compatibility
6. **Living Documentation**: Verify accuracy by running discovery commands

## Notes for Claude Code

When working on this project:
- Follow the resource-based routing pattern for new API endpoints
- Ensure Docker configurations remain simple and maintainable
- Keep service independence - avoid tight coupling between services
- Each microservice lives in its own repository
- This orchestration repo coordinates deployment and environment setup
- All repositories should be cloned side-by-side in `/workspace/` for cross-repo documentation links to work

