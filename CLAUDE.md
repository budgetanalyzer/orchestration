# Budget Analyzer - Orchestration Repository

## Project Overview

This orchestration repository coordinates the deployment and development environment for the Budget Analyzer application - a production-grade, microservices-based financial management system.

**Purpose**: Manages cross-service concerns, local development setup, and deployment coordination. Individual service code lives in separate repositories.

## Architecture Principles

- **Production Parity**: Development environment faithfully recreates production
- **Microservices**: Independently deployable services with clear boundaries
- **API Gateway Pattern**: NGINX provides unified routing and load balancing
- **Resource-Based Routing**: Frontend remains decoupled from service topology
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
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (see docker compose.yml)
- **Gateway**: NGINX reverse proxy (port 8080) routes all frontend requests

**Adding New Services**:
1. Add service to [docker compose.yml](docker compose.yml)
2. Add routes to [nginx/nginx.dev.conf](nginx/nginx.dev.conf) if frontend-facing
3. Follow naming: `{domain}-service` for backends, `{domain}-web` for frontends

## API Gateway Pattern

**Pattern**: Resource-based routing through NGINX gateway. Frontend calls clean paths like `/api/transactions`, NGINX routes to appropriate microservice with path transformation. All requests go through `http://localhost:8080/api/*`.

**Quick Reference**:
- All routes defined in [nginx/nginx.dev.conf](nginx/nginx.dev.conf)
- Routing pattern: `location /api/{resource}` → `rewrite ^/api/(.*)$` → `proxy_pass http://{upstream}`
- Services use `host.docker.internal` to reach host services from Docker container
- WebSocket support included for React HMR (hot module replacement)
- Benefits: Frontend decoupled from service topology, services can be split/merged without frontend changes

**Discovery** (inspect routes without reading full config):
```bash
# List all API routes
grep "location /api" nginx/nginx.dev.conf | grep -v "#"

# Test gateway routing
curl -v http://localhost:8080/api/v1/health
```

**When to consult detailed nginx documentation**:
- Adding new API routes → Read "Adding a New Resource Route" in [nginx/README.md](nginx/README.md)
- Adding new microservices → Read "Adding a New Microservice" in [nginx/README.md](nginx/README.md)
- Moving resources between services → Read "Moving a Resource Between Services" in [nginx/README.md](nginx/README.md)
- Troubleshooting gateway issues → Read "Troubleshooting" section in [nginx/README.md](nginx/README.md)

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
- **service-common**: https://github.com/budget-analyzer/service-common
- **transaction-service**: https://github.com/budget-analyzer/transaction-service
- **currency-service**: https://github.com/budget-analyzer/currency-service
- **budget-analyzer-web**: https://github.com/budget-analyzer/budget-analyzer-web

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

