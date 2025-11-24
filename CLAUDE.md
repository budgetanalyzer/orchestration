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
- **Kubernetes-Native Development**: Tilt + Kind for consistent local Kubernetes development

## Service Architecture

**Pattern**: Microservices deployed via Tilt to local Kind cluster

**Discovery**:
```bash
# List all running resources
tilt get uiresources

# View pod status
kubectl get pods -n budget-analyzer

# View service endpoints
kubectl get svc -n budget-analyzer
```

**Service Types**:
- **Frontend services**: React-based web applications (port 3000 in dev)
- **Backend microservices**: Spring Boot REST APIs (ports 8082+)
- **Session Gateway (BFF)**: Spring Cloud Gateway (port 8081, HTTP) - browser authentication and session management
- **Token Validation Service**: Spring Boot service (port 8088) - JWT validation for NGINX
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (in infrastructure namespace)
- **Ingress**: Envoy Gateway (port 443, HTTPS) - SSL termination and initial routing
- **API Gateway**: NGINX (port 8080, HTTP) - internal routing, JWT validation, and load balancing

**Adding New Services**:
1. Create Kubernetes manifests in `kubernetes/services/{service-name}/`
2. Add service to `Tiltfile` using `spring_boot_service()` pattern
3. Add routes to `nginx/nginx.k8s.conf` if frontend-facing
4. Follow naming: `{domain}-service` for backends, `{domain}-web` for frontends

## BFF + API Gateway Hybrid Pattern

**Pattern**: Hybrid architecture combining Backend-for-Frontend (BFF) for browser security with API Gateway for routing and validation.

### Request Flow

**All browser traffic goes through Session Gateway.** Think of it as a maxiservice.

```
Browser → Envoy (:443) → Session Gateway (:8081) → Envoy → NGINX (:8080) → Services
```

- **Envoy**: SSL termination for all traffic
- **Session Gateway**: JWT lookup from Redis, inject into header
- **NGINX**: JWT validation, route to service

**Two entry points:**
- `app.budgetanalyzer.localhost` → Envoy → Session Gateway (browser auth)
- `api.budgetanalyzer.localhost` → Envoy → NGINX (API gateway)

### Component Roles

**Envoy Gateway (Port 443, HTTPS) - Ingress Layer**:
- **Purpose**: SSL termination and initial routing
- **Responsibilities**:
  - Handles SSL/TLS termination for both app. and api. subdomains
  - Routes app.budgetanalyzer.localhost to Session Gateway
  - Routes api.budgetanalyzer.localhost to NGINX
  - Provides Gateway API-compliant ingress
- **Key Benefit**: Modern, Kubernetes-native ingress with SSL termination

**NGINX (Port 8080, HTTP) - API Gateway Layer**:
- **Purpose**: JWT validation, routing, and request processing
- **Responsibilities**:
  - Validates JWTs via Token Validation Service (auth_request directive)
  - Routes requests to appropriate microservices
  - Resource-based routing with path transformation
  - Rate limiting per user/IP
  - Load balancing and circuit breaking
- **Key Benefit**: Centralized JWT validation and routing logic

**Session Gateway (Port 8081, HTTP) - BFF Layer**:
- **Purpose**: Browser authentication and session security
- **Responsibilities**:
  - Manages OAuth2 flows with Auth0
  - Stores JWTs in Redis (server-side, never exposed to browser)
  - Issues HttpOnly, Secure session cookies to browsers
  - Proactive token refresh before expiration
  - Proxies authenticated requests to NGINX with JWT injection
- **Key Benefit**: Maximum security for browser-based financial application (JWTs never exposed to XSS)

**Token Validation Service (Port 8088)**:
- **Purpose**: JWT signature verification for NGINX
- **Responsibilities**:
  - Verifies JWT signatures using Auth0 JWKS
  - Validates issuer, audience, and expiration claims
  - Called by NGINX via auth_request for every protected endpoint
- **Key Benefit**: Centralized JWT validation logic, defense in depth

### No CORS Needed

**Same-Origin Architecture**: All browser requests go through Session Gateway (app.budgetanalyzer.localhost), which proxies to NGINX, which routes to backends. Browser sees single origin = no CORS issues!

**Traditional architecture (CORS required)**:
```
Browser → Frontend (3000) → Backend Services (8082+)  ❌ Different origins
```

**Current architecture (No CORS)**:
```
Browser → Session Gateway (app.budgetanalyzer.localhost) → NGINX (api.budgetanalyzer.localhost) → Backend Services  ✅ Same origin
```

### Resource-Based Routing

**Pattern**: Frontend calls clean paths like `/api/transactions`, NGINX routes to appropriate microservice with path transformation.

**Quick Reference**:
- All routes defined in [nginx/nginx.k8s.conf](nginx/nginx.k8s.conf)
- Routing pattern: `location /api/{resource}` → `rewrite ^/api/(.*)$` → `proxy_pass http://{upstream}`
- JWT validation via `auth_request /auth/validate` on all protected routes
- Services accessed via Kubernetes DNS names
- Benefits: Frontend decoupled from service topology, services can be split/merged without frontend changes

**Discovery** (inspect routes without reading full config):
```bash
# List all API routes
grep "location /api" nginx/nginx.k8s.conf | grep -v "#"

# Test Session Gateway health
curl -v https://app.budgetanalyzer.localhost/actuator/health

# Test API Gateway
curl -v https://api.budgetanalyzer.localhost/health
```

**When to consult detailed nginx documentation**:
- Adding new API routes → Read "Adding a New Resource Route" in [nginx/README.md](nginx/README.md)
- Adding new microservices → Read "Adding a New Microservice" in [nginx/README.md](nginx/README.md)
- Moving resources between services → Read "Moving a Resource Between Services" in [nginx/README.md](nginx/README.md)
- Troubleshooting gateway issues → Read "Troubleshooting" section in [nginx/README.md](nginx/README.md)

### Port Summary

| Port | Service | Purpose | Access |
|------|---------|---------|--------|
| 443 | Envoy Gateway | SSL termination, ingress (HTTPS) | Public (browsers via app. and api.budgetanalyzer.localhost) |
| 8080 | NGINX Gateway | JWT validation, routing | Internal (Envoy only) |
| 8081 | Session Gateway | Browser authentication, session management | Internal (Envoy only) |
| 8088 | Token Validation | JWT signature verification | Internal (NGINX only) |
| 8082 | Transaction Service | Business logic | Internal (NGINX only) |
| 8084 | Currency Service | Business logic | Internal (NGINX only) |
| 3000 | React Dev Server | Frontend (dev only) | Internal (NGINX only) |

### Security Benefits

**Defense in Depth**:
1. **Envoy Gateway**: SSL termination for all traffic
2. **Session Gateway**: Prevents JWT exposure to browser (XSS protection)
3. **NGINX auth_request**: Validates every API request before routing
4. **Token Validation Service**: Cryptographic JWT verification
5. **Backend Services**: Data-level authorization (user owns resource)

**For detailed security architecture**: See [docs/architecture/security-architecture.md](docs/architecture/security-architecture.md)

## Technology Stack

**Principle**: Each service manages its own dependencies. Versions are defined in service-specific files.

**Discovery**:
```bash
# List all Tilt resources
tilt get uiresources

# View deployed images
kubectl get pods -n budget-analyzer -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u
```

**Stack Patterns**:
- **Frontend**: React (see individual service package.json)
- **Backend**: Spring Boot + Java (version managed in service-common)
- **Build System**: Gradle (all backend services use Gradle with wrapper)
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (Kubernetes manifests in `kubernetes/infrastructure/`)
- **Ingress**: Envoy Gateway (Kubernetes Gateway API)
- **API Gateway**: NGINX (Alpine-based)
- **Development**: Tilt + Kind (local Kubernetes)

**Note**: Docker images should be pinned to specific versions for reproducibility.

## Development Workflow

### Prerequisites
- Docker (for building images)
- Kind (local Kubernetes cluster)
- kubectl (Kubernetes CLI)
- Helm (for installing Envoy Gateway)
- Tilt (development workflow orchestration)
- JDK 17+ (for local Spring Boot development)
- Node.js 18+ (for local React development)
- Git
- mkcert (for local HTTPS certificates)

Check prerequisites with:
```bash
./scripts/dev/check-tilt-prerequisites.sh
```

### First Time Setup

**HTTPS Certificate Setup**:
The application uses HTTPS for local development with clean subdomain URLs:
- Browser entry point: `https://app.budgetanalyzer.localhost` (Envoy → Session Gateway)
- API Gateway: `https://api.budgetanalyzer.localhost` (Envoy → NGINX → Backend Services)

Run the setup script to generate trusted local certificates:
```bash
# Install mkcert (first time only)
# macOS:   brew install mkcert nss
# Linux:   See https://github.com/FiloSottile/mkcert#installation
# Windows: choco install mkcert

# Generate certificates and create Kubernetes TLS secret
./scripts/dev/setup-k8s-tls.sh
```

This script will:
1. Install a local Certificate Authority (CA) in your system's trust store
2. Generate a wildcard certificate for `*.budgetanalyzer.localhost`
3. Create Kubernetes TLS secret for Envoy Gateway
4. Your browser will automatically trust these certificates (no warnings!)

**Environment Variables Setup**:
Configure Auth0 credentials for authentication:
```bash
# Copy the example file
cp .env.example .env

# Edit .env with your Auth0 credentials from https://manage.auth0.com/dashboard
```

The `.env` file is gitignored and loaded by Tilt via the dotenv extension. No shell exports needed!

### Quick Start
```bash
# Start all services with Tilt
tilt up

# Access Tilt UI for logs and status
# Browser: http://localhost:10350

# Access application
# Browser: https://app.budgetanalyzer.localhost

# Stop all services
tilt down
```

### Troubleshooting

**Quick commands**:
```bash
# Check pod status
kubectl get pods -n budget-analyzer

# View logs for a service
kubectl logs -n budget-analyzer deployment/nginx-gateway

# Check NGINX configuration validity
kubectl exec -n budget-analyzer deployment/nginx-gateway -- nginx -t

# View Envoy Gateway logs
kubectl logs -n envoy-gateway-system deployment/envoy-gateway

```

**For detailed troubleshooting**: When encountering specific issues (502 errors, CORS problems, connection refused, etc.), consult the comprehensive troubleshooting guide in [nginx/README.md](nginx/README.md)

## Workspace Structure

All repositories should be cloned side-by-side in a common parent directory:

```
/workspace/
├── .github/                    # Organization-level GitHub config (templates, profile README)
├── orchestration/              # This repo - deployment coordination
├── session-gateway/            # BFF service
├── token-validation-service/   # JWT validation service
├── transaction-service/        # Transaction management
├── currency-service/           # Currency/exchange rates
├── permission-service/         # Permission management
├── budget-analyzer-web/        # React frontend
├── service-common/             # Shared Java library
└── checkstyle-config/          # Shared checkstyle rules
```

**Note**: The `.github` directory at workspace root is the [organization-level .github repository](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file) containing default issue/PR templates for all repos.

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
- **permission-service**: https://github.com/budgetanalyzer/permission-service - Permission management API

## Best Practices

1. **Environment Parity**: Keep dev and prod configurations as similar as possible
2. **Configuration Management**: Use environment variables for configuration
3. **Health Checks**: All services expose health endpoints
4. **Service Independence**: Each microservice should be independently deployable
5. **API Versioning**: Version APIs to support backward compatibility
6. **Living Documentation**: Verify accuracy by running discovery commands

## Notes for Claude Code

**CRITICAL - Prerequisites First**: Before implementing any plan or feature:
1. Check for prerequisites in documentation (e.g., "Prerequisites: service-common Enhancement")
2. If prerequisites are NOT satisfied, STOP immediately and inform the user
3. Do NOT attempt to hack around missing prerequisites - this leads to broken implementations that must be deleted
4. Complete prerequisites first, then return to the original task

### SSL/TLS Certificate Constraints

**NEVER run SSL write operations** - Claude runs in a container with its own mkcert CA, but the user's browser trusts their host's mkcert CA. These are different CAs, so certificates generated in Claude's sandbox will cause browser SSL warnings.

**Forbidden operations** (must be run by user on host):
- `mkcert` (any certificate generation)
- `openssl genrsa`, `openssl req -new`, `openssl x509 -req` (key/cert generation)
- Any script that generates certificates (e.g., `setup-k8s-tls.sh`)

**Allowed operations** (read-only):
- `openssl x509 -text -noout` (inspect certificates)
- `openssl verify` (verify certificate chains)
- `kubectl get secret -o yaml` (view secrets)
- Certificate file reads for debugging

When SSL issues occur, guide the user to run certificate scripts on their host machine.

When working on this project:
- Follow the resource-based routing pattern for new API endpoints
- Ensure Kubernetes configurations remain simple and maintainable
- Keep service independence - avoid tight coupling between services
- Each microservice lives in its own repository
- This orchestration repo coordinates deployment and environment setup
- All repositories should be cloned side-by-side in a common parent directory for cross-repo documentation links to work
- **Path Portability**: Never hardcode absolute paths like `/workspace`. The orchestration repo must work when cloned to any directory. Use relative paths or dynamic resolution (e.g., `config.main_dir` in Tiltfiles, `$(dirname "$0")` in shell scripts)
- Ignore all files in docs/archive and docs/decisions. Never change them, they are just for historical reference.

