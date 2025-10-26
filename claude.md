# Budget Analyzer - Orchestration Repository

## Project Overview

This is an orchestration repository that manages the deployment and development environment for the Budget Analyzer application - a production-grade, microservices-based financial management system.

## Architecture

### Core Services

1. **budget-analyzer-web** - React 19 web application
   - Modern frontend for budget tracking and financial analysis
   - Development server runs on port 3000
   - Production build served as static assets

2. **budget-analyzer-api** - Spring Boot microservice
   - Core business logic for budget and transaction management
   - Runs on port 8082
   - RESTful API endpoints under `/budget-analyzer-api/*`

3. **currency-service** - Spring Boot microservice
   - Currency conversion and exchange rate management
   - Runs on port 8084
   - RESTful API endpoints under `/currency-service/*`

4. **nginx-gateway** - NGINX API Gateway
   - Unified entry point for all services (port 8080)
   - Resource-based routing (frontend calls clean `/api/*` paths)
   - Decouples frontend from backend service architecture
   - Separate configurations for development and production

### Architecture Principles

- **Production Parity**: Development environment faithfully recreates production
- **Microservices**: Independently deployable services with clear boundaries
- **API Gateway Pattern**: NGINX provides unified routing and load balancing
- **Resource-Based Routing**: Frontend remains decoupled from service topology
- **Containerization**: Docker and Docker Compose for consistent environments

## Repository Structure

```
budget-analyzer/
├── claude.md                    # This file - AI assistant context
├── README.md                    # Human-readable project documentation
├── docker-compose.yml           # Development orchestration
├── nginx/
│   ├── nginx.dev.conf          # Development NGINX configuration
│   └── README.md               # NGINX configuration documentation
├── scripts/                     # Build, release, and development scripts
├── docs/                        # Additional documentation
├── kubernetes/                  # K8s manifests for production deployment
└── .gitignore
```

## Development Workflow

### Prerequisites
- Docker and Docker Compose
- JDK 17+ (for local Spring Boot development)
- Node.js 18+ (for local React development)
- Git

### Starting the Development Environment

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop all services
docker-compose down
```

### Service Endpoints (Development)

- **NGINX Gateway**: http://localhost:8080
- **React App**: http://localhost:3000 (direct, for hot reload)
- **Budget Analyzer API**: http://localhost:8082
- **Currency Service**: http://localhost:8084

### Frontend Access Pattern

The frontend should call the NGINX gateway at `http://localhost:8080/api/*`:
- `/api/transactions` → routed to budget-analyzer-api
- `/api/currencies` → routed to currency-service
- `/api/exchange-rates` → routed to currency-service

## NGINX Gateway Routing

### Resource-Based Routing Strategy

The gateway uses **resource-based routing** instead of service-based routing:

**Benefits:**
- Frontend is decoupled from backend service architecture
- Moving a resource to a different service requires only an NGINX config change
- No DNS resolver needed
- Clean, RESTful API paths for frontend

**Adding New Routes:**
1. Add location block in `nginx/nginx.dev.conf`
2. Point to appropriate upstream and path
3. No frontend changes required

### Development vs Production Configurations

- **nginx.dev.conf**: Proxies to local services via `host.docker.internal`
- **nginx.prod.conf** (future): Will use Docker service names or production endpoints

## Docker Compose Configuration

### Development (`docker-compose.yml`)
- Uses `nginx/nginx.dev.conf`
- Configured for hot-reload and local development
- Services communicate via `host.docker.internal`
- NGINX runs in container, apps run on host for easier debugging

### Production (future `docker-compose.prod.yml`)
- Will use `nginx/nginx.prod.conf`
- All services containerized
- Optimized for performance and security
- Services communicate via Docker network

## Build and Release Scripts

### Build Scripts (`scripts/build/`)
- Build individual services
- Create Docker images
- Run tests and quality checks

### Release Scripts (`scripts/release/`)
- Version management
- Tag creation
- Deployment automation
- Rollback procedures

### Development Scripts (`scripts/dev/`)
- Environment setup
- Database migrations
- Test data seeding
- Log aggregation

## Technology Stack

### Frontend
- React 19
- Modern JavaScript/TypeScript
- Webpack/Vite for bundling
- Hot Module Replacement for development

### Backend
- Spring Boot 3.x
- Java 17+
- RESTful APIs
- Microservices architecture

### Infrastructure
- Docker for containerization
- Docker Compose for orchestration
- NGINX for API gateway and reverse proxy
- Kubernetes for production deployment
- PostgreSQL/MySQL for databases (if applicable)

## Best Practices

1. **Environment Parity**: Keep dev and prod configurations as similar as possible
2. **Configuration Management**: Use environment variables for configuration
3. **Health Checks**: All services expose `/health` endpoints
4. **Logging**: Centralized logging strategy across all services
5. **Version Control**: Tag releases and maintain changelog
6. **Documentation**: Keep this file updated as architecture evolves
7. **Service Independence**: Each microservice should be independently deployable
8. **API Versioning**: Version APIs to support backward compatibility

## Common Tasks

### Adding a New Microservice
1. Create service in separate repository
2. Add upstream definition in NGINX config (`nginx/nginx.dev.conf`)
3. Add location blocks for service routes
4. Update `docker-compose.yml` if running service locally
5. Update this documentation

### Modifying API Routes
1. Update `nginx/nginx.dev.conf` location blocks
2. Test routing with `docker-compose restart nginx-gateway`
3. Update API documentation
4. Ensure production config is synchronized when created

### Troubleshooting
```bash
# Check NGINX configuration
docker exec api-gateway nginx -t

# View NGINX logs
docker logs api-gateway

# Reload NGINX without downtime
docker exec api-gateway nginx -s reload

# Check service health
curl http://localhost:8080/health

# Test API routing
curl http://localhost:8080/api/transactions
curl http://localhost:8080/api/currencies
```

## Service Repositories

Each microservice is maintained in its own repository:
- **budget-analyzer-web**: [repository URL]
- **budget-analyzer-api**: [repository URL]
- **currency-service**: [repository URL]

## Deployment

### Local Development
Uses `docker-compose.yml` with NGINX gateway. Backend services run on host machine for easier debugging and hot-reload.

### Production (Kubernetes)
Uses manifests in `kubernetes/` directory. All services containerized and deployed to cluster.

## Future Enhancements

- [ ] Production Docker Compose configuration
- [ ] Complete Kubernetes manifests for all services
- [ ] CI/CD pipeline integration (GitHub Actions/Jenkins)
- [ ] Automated testing scripts
- [ ] Database migration management
- [ ] Monitoring and observability stack (Prometheus, Grafana)
- [ ] Service mesh integration (Istio/Linkerd - optional)
- [ ] API documentation aggregation (Swagger/OpenAPI)
- [ ] Distributed tracing (Jaeger/Zipkin)
- [ ] Centralized logging (ELK/Loki stack)

## Notes for Claude Code

When working on this project:
- Maintain separation between dev and prod configurations
- Follow the resource-based routing pattern for new API endpoints
- Ensure Docker configurations remain simple and maintainable
- Keep service independence - avoid tight coupling between services
- Update this file when architecture changes
- Follow Spring Boot and React best practices
- Prioritize production readiness while maintaining dev experience
- Each microservice lives in its own repository
- This orchestration repo coordinates deployment and environment setup
