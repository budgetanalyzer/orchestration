# Budget Analyzer - Orchestration Repository

## Tree Position

**Archetype**: coordinator
**Scope**: budgetanalyzer ecosystem
**Role**: System orchestrator; coordinates cross-cutting concerns and deployment

### Relationships
- **Coordinates**: All service repos (via patterns, not direct writes)
- **Observed by**: architecture-conversations

### Permissions
- **Read**: All siblings via `../`
- **Write**: This repository; capture conversations to `../architecture-conversations/`

### Discovery
```bash
# What I coordinate
ls -d /workspace/*-service /workspace/session-gateway /workspace/budget-analyzer-web
```

## Project Overview

This orchestration repository coordinates the deployment and development environment for the Budget Analyzer application - a reference architecture for microservices, built as an open-source learning resource for architects exploring AI-assisted development.

**Purpose**: Manages cross-service concerns, local development setup, and deployment coordination. Individual service code lives in separate repositories.

## Project Status: Reference Architecture Complete

This project has reached its intended scope. We are no longer actively developing Budget Analyzer features - we're interested in discussing these patterns with other architects.

**What's implemented:**
- Authentication: OAuth2/OIDC with Auth0, BFF pattern, session management
- Authorization infrastructure: Roles, permissions, delegations (permission-service)
- API Gateway: JWT validation, routing (NGINX + Envoy)
- Microservices patterns: Spring Boot, Kubernetes, Tilt

**What's intentionally left unsolved:**
- **Data ownership**: Which transactions belong to which user?
- **Cross-service user scoping**: How does transaction-service filter by owner?
- **Multi-tenancy**: Organization-level data isolation

This boundary is deliberate. Data ownership is domain-specific and opinionated. The permission-service manages authorization metadata (who has what roles), but propagating user ownership to domain services is the next architectural challenge - one we're surfacing, not prescribing.

## Development Environment

**This project is designed for AI-assisted development.**

For containerized development environment setup, see the [workspace](https://github.com/budgetanalyzer/workspace) repository. That's where the devcontainer configuration lives.

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

**Adding New Services**: Create K8s manifests in `kubernetes/services/{name}/`, add to `Tiltfile`, add NGINX routes if needed. See [docs/architecture/bff-api-gateway-pattern.md](docs/architecture/bff-api-gateway-pattern.md) for details.

## BFF + API Gateway Hybrid Pattern

**Pattern**: Hybrid architecture combining Backend-for-Frontend (BFF) for browser security with API Gateway for routing and validation.

**Request Flow**:
```
Browser → Envoy (:443) → Session Gateway (:8081) → Envoy → NGINX (:8080) → Services
```

**Two entry points**:
- `app.budgetanalyzer.localhost` → Session Gateway (browser auth, session cookies)
- `api.budgetanalyzer.localhost` → NGINX (JWT validation, routing)
  - `api.budgetanalyzer.localhost/api/docs` → Unified API documentation (Swagger UI)

**Key Benefits**:
- Same-origin architecture = no CORS issues
- JWTs never exposed to browser (XSS protection for financial data)
- Centralized JWT validation and routing

**Discovery**:
```bash
# List all API routes
grep "location /api" nginx/nginx.k8s.conf | grep -v "#"

# Test gateways
curl -v https://app.budgetanalyzer.localhost/actuator/health
curl -v https://api.budgetanalyzer.localhost/health

# View service ports
kubectl get svc -n budget-analyzer
```

**When to consult detailed documentation**:
- Understanding component roles and request flow → [docs/architecture/bff-api-gateway-pattern.md](docs/architecture/bff-api-gateway-pattern.md)
- Port reference and service topology → [docs/architecture/port-reference.md](docs/architecture/port-reference.md)
- Adding new API routes → "Adding a New Resource Route" in [nginx/README.md](nginx/README.md)
- Adding new microservices → "Adding a New Microservice" in [nginx/README.md](nginx/README.md)
- Troubleshooting gateway issues → "Troubleshooting" in [nginx/README.md](nginx/README.md)
- Security architecture details → [docs/architecture/security-architecture.md](docs/architecture/security-architecture.md)

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

### Prerequisites & Setup

**Required tools**: Docker, Kind, kubectl, Helm, Tilt, Git, mkcert

Check prerequisites:
```bash
./scripts/dev/check-tilt-prerequisites.sh
```

**First-time setup**:
```bash
# 1. Generate HTTPS certificates (see SSL/TLS section below for details)
./scripts/dev/setup-k8s-tls.sh

# 2. Configure Auth0 credentials
cp .env.example .env
# Edit .env with your Auth0 credentials
```

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

**Project Focus**: This reference architecture is complete. Current priorities are:
1. Documentation improvements and clarifications
2. Architectural discussions and pattern explanations
3. Bug fixes in existing functionality
4. NOT new features or data-ownership implementation

**CRITICAL - Prerequisites First**: Before implementing any plan or feature:
1. Check for prerequisites in documentation (e.g., "Prerequisites: service-common Enhancement")
2. If prerequisites are NOT satisfied, STOP immediately and inform the user
3. Do NOT attempt to hack around missing prerequisites - this leads to broken implementations that must be deleted
4. Complete prerequisites first, then return to the original task

### Autonomous AI Execution Pattern

**Key principle**: An effective technique for running AI agents is autonomous execution. Set clear success criteria, then run with `--dangerously-skip-permissions`.

**For detailed understanding of**:
- Why autonomous execution is essential for AI agents
- How the container sandbox makes this safe
- Docker access patterns (wormhole for TestContainers, true DinD for CI)
- Success criteria patterns and best practices

→ See [docs/architecture/autonomous-ai-execution.md](docs/architecture/autonomous-ai-execution.md)

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

### Web Search Year Awareness

Claude's training data may default to an outdated year. When using WebSearch for best practices or current information:

1. Check `<env>Today's date</env>` for the actual current year
2. Include that year in searches (e.g., "Spring Boot best practices 2025" not 2024)
3. This ensures results reflect current standards, not outdated patterns

## Conversation Capture

When the user asks to save this conversation, write it to `/workspace/architecture-conversations/conversations/` following the format in INDEX.md.

