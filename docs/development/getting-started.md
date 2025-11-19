# Getting Started with Local Development

## Prerequisites

- Docker and Docker Compose ([installation guide](https://docs.docker.com/get-docker/))
- Git

## Quick Start

### 1. Clone Repositories

Clone all repositories side-by-side:

```bash
cd /workspace
git clone https://github.com/budgetanalyzer/orchestration.git
git clone https://github.com/budgetanalyzer/service-common.git
git clone https://github.com/budgetanalyzer/transaction-service.git
git clone https://github.com/budgetanalyzer/currency-service.git
git clone https://github.com/budgetanalyzer/budget-analyzer-web.git
git clone https://github.com/budgetanalyzer/session-gateway.git
git clone https://github.com/budgetanalyzer/token-validation-service.git
git clone https://github.com/budgetanalyzer/basic-repository-template.git
```

### 2. Start Infrastructure

From the orchestration directory:

```bash
cd orchestration
docker compose up -d
```

This starts:
- PostgreSQL (shared database for all services)
- NGINX gateway (API gateway, JWT validation, and reverse proxy)
- Redis (session storage for Session Gateway)
- RabbitMQ (message broker)

### 3. Publish service-common to Maven Local

The backend services depend on the shared `service-common` library. You must publish it to your local Maven repository before running any backend services:

```bash
cd /workspace/service-common
./gradlew publishToMavenLocal
```

This makes the shared library available to all services that depend on it (transaction-service, currency-service, etc.).

**Note**: Re-run this command whenever you make changes to service-common.

### 4. Verify Setup

Check all services are running:

```bash
docker compose ps
```

Access the application:
- **Frontend (via Session Gateway)**: http://localhost:8081
- **Unified API Documentation**: http://localhost:8080/api/docs (internal access)
- **OpenAPI JSON**: http://localhost:8080/api/docs/openapi.json
- **OpenAPI YAML**: http://localhost:8080/api/docs/openapi.yaml

**Important**: All browser requests go through Session Gateway: `http://localhost:8081`
- Session Gateway (8081) handles authentication and proxies to NGINX
- NGINX (8080) validates JWTs and routes to backend services

### 5. Start Session Gateway and Token Validation Service

**Token Validation Service** (JWT validation for NGINX):
```bash
cd /workspace/token-validation-service
# Configure Auth0 (optional for local dev - placeholder values work)
# AUTH0_ISSUER_URI=https://your-tenant.auth0.com/
./gradlew bootRun
```

**Session Gateway** (BFF - Browser authentication):
```bash
cd /workspace/session-gateway
# Configure Auth0 credentials (required for OAuth login)
# AUTH0_CLIENT_ID=your-client-id
# AUTH0_CLIENT_SECRET=your-client-secret
# AUTH0_ISSUER_URI=https://your-tenant.auth0.com/
./gradlew bootRun
```

**Note**: See [docs/architecture/authentication-implementation-plan.md](../architecture/authentication-implementation-plan.md) for Auth0 setup details.

### 6. Start Backend Services

Each backend service can run locally or in Docker. For local development:

**Transaction Service:**
```bash
cd /workspace/transaction-service
./gradlew bootRun
```

**Currency Service:**
```bash
cd /workspace/currency-service
./gradlew bootRun
```

**Frontend:**
```bash
cd /workspace/budget-analyzer-web
npm install
npm run dev
```

The frontend development server runs on port 3000 but is served through Session Gateway (8081) → NGINX (8080) → Vite (3000).

## Access Patterns

### Browser Access (via Session Gateway)

All browser requests go through the **Session Gateway** at `http://localhost:8081`:

**Frontend:**
- Application: `http://localhost:8081/`
- Login: `http://localhost:8081/oauth2/authorization/auth0`
- Logout: `http://localhost:8081/logout`

**API Endpoints (authenticated, requires login):**
- Transactions: `http://localhost:8081/api/v1/transactions`
- Currencies: `http://localhost:8081/api/v1/currencies`
- Exchange Rates: `http://localhost:8081/api/v1/exchange-rates`

**Architecture Flow:**
```
Browser → Session Gateway (8081) → NGINX (8080) → Backend Services (8082+)
         OAuth2/Session           JWT Validation    Business Logic
```

### Internal/Development Access

**Direct Service Access (for debugging only):**
- Transaction Service Swagger: `http://localhost:8082/swagger-ui.html`
- Currency Service Swagger: `http://localhost:8084/swagger-ui.html`
- Transaction Service Health: `http://localhost:8082/actuator/health`
- Currency Service Health: `http://localhost:8084/actuator/health`
- Token Validation Service Health: `http://localhost:8088/actuator/health`

**Note**: Direct service access bypasses authentication - only for local development debugging.

## Next Steps

- **Database Configuration**: See [database-setup.md](database-setup.md)
- **Development Workflows**: See [local-environment.md](local-environment.md)
- **NGINX Gateway Configuration**: See [../../nginx/README.md](../../nginx/README.md)

## Stopping Services

```bash
# Stop infrastructure
cd orchestration
docker compose down

# Stop backend services (Ctrl+C if running in foreground)

# Remove all data (WARNING: deletes databases)
docker compose down -v
```
