# Getting Started with Local Development

## Prerequisites

- Docker ([installation guide](https://docs.docker.com/get-docker/))
- Kind (local Kubernetes cluster)
- kubectl (Kubernetes CLI)
- Helm (for installing Envoy Gateway)
- Tilt (development workflow orchestration)
- JDK 24 (for Spring Boot development)
- Node.js 18+ (for React development)
- mkcert (for local HTTPS certificates)
- Git

Check prerequisites with:
```bash
./scripts/dev/check-tilt-prerequisites.sh
```

## Quick Start

### 1. Clone & Setup

```bash
git clone https://github.com/budgetanalyzer/orchestration.git
cd orchestration
./setup.sh
```

The setup script will:
- Clone all service repositories
- Create Kind cluster with correct port mappings
- Configure DNS in `/etc/hosts`
- Install Gateway API and Envoy Gateway
- Generate TLS certificates
- Create `.env` from template

### 2. Configure External Services

Edit `.env` with your credentials:

```bash
vim .env
```

**Required:**
- **Auth0**: See [../setup/auth0-setup.md](../setup/auth0-setup.md)
- **FRED API**: See [../setup/fred-api-setup.md](../setup/fred-api-setup.md)

### 3. Start All Services

```bash
tilt up
```

This will:
- Build all service images
- Deploy to local Kind cluster
- Set up Envoy Gateway for SSL termination
- Configure NGINX for JWT validation and routing
- Start PostgreSQL, Redis, RabbitMQ

### 5. Access the Application

- **Tilt UI**: http://localhost:10350 (logs, status, buttons)
- **Application**: https://app.budgetanalyzer.localhost
- **API Documentation**: https://api.budgetanalyzer.localhost/api/docs
- **OpenAPI JSON**: https://api.budgetanalyzer.localhost/api/docs/openapi.json

**Architecture Flow:**
```
Browser → Envoy Gateway (443) → Session Gateway (8081) → Envoy Gateway → NGINX (8080) → Backend Services
         SSL/HTTPS             OAuth2/Session                            JWT Validation    Business Logic
```

## Tilt UI Overview

The Tilt UI at http://localhost:10350 provides:

- **Resource Status**: Real-time status of all services
- **Logs**: Live logs from all pods
- **Buttons**: Quick actions for development

**Key Resources:**
- `service-common-publish` - Builds shared library
- `*-compile` - Compiles each service

## Access Patterns

### Browser Access (via Envoy/Session Gateway)

All browser requests go through **Envoy Gateway** at `https://app.budgetanalyzer.localhost`:

**Frontend:**
- Application: `https://app.budgetanalyzer.localhost/`
- Login: `https://app.budgetanalyzer.localhost/oauth2/authorization/auth0`
- Logout: `https://app.budgetanalyzer.localhost/logout`

**API Endpoints (authenticated, requires login):**
- Transactions: `https://app.budgetanalyzer.localhost/api/v1/transactions`
- Currencies: `https://app.budgetanalyzer.localhost/api/v1/currencies`
- Exchange Rates: `https://app.budgetanalyzer.localhost/api/v1/exchange-rates`

### Internal/Development Access

**Direct Service Access (for debugging only):**
- Transaction Service Swagger: `http://localhost:8082/swagger-ui.html`
- Currency Service Swagger: `http://localhost:8084/swagger-ui.html`
- Transaction Service Health: `http://localhost:8082/actuator/health`
- Currency Service Health: `http://localhost:8084/actuator/health`
- Token Validation Service Health: `http://localhost:8088/actuator/health`

**Note**: Direct service access bypasses authentication - only for local development debugging.

## Troubleshooting

### Check Pod Status

```bash
# View all pods
kubectl get pods -n budget-analyzer

# View infrastructure pods
kubectl get pods -n infrastructure
```

### View Logs

```bash
# Via Tilt UI (recommended)
# http://localhost:10350 → Click on resource

# Via kubectl
kubectl logs -n budget-analyzer deployment/transaction-service
kubectl logs -n budget-analyzer deployment/nginx-gateway
kubectl logs -n envoy-gateway-system deployment/envoy-gateway
```

### Common Issues

**Service not starting:**
- Check Tilt UI for error messages
- Verify `service-common-publish` completed successfully
- Check compile step completed

**502 Bad Gateway:**
- Check if target service pod is running
- View NGINX logs for routing errors
- Verify Kubernetes service exists

**SSL Certificate Errors:**
- Re-run `./scripts/dev/setup-k8s-tls.sh` on host
- Restart browser

## Next Steps

- **Database Configuration**: See [database-setup.md](database-setup.md)
- **Development Workflows**: See [local-environment.md](local-environment.md)
- **NGINX Gateway Configuration**: See [../../nginx/README.md](../../nginx/README.md)

## Stopping Services

```bash
# Stop all services
tilt down

# Delete Kind cluster completely (removes all data)
kind delete cluster
```
