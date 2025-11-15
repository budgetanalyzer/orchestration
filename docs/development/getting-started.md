# Getting Started with Local Development

## Prerequisites

- Docker and Docker Compose ([installation guide](https://docs.docker.com/get-docker/))
- Git

## Quick Start

### 1. Clone Repositories

Clone all repositories side-by-side:

```bash
cd /workspace
git clone https://github.com/budget-analyzer/orchestration.git
git clone https://github.com/budget-analyzer/service-common.git
git clone https://github.com/budget-analyzer/transaction-service.git
git clone https://github.com/budget-analyzer/currency-service.git
git clone https://github.com/budget-analyzer/budget-analyzer-web.git
```

### 2. Start Infrastructure

From the orchestration directory:

```bash
cd orchestration
docker compose up -d
```

This starts:
- PostgreSQL (shared database for all services)
- NGINX gateway (API gateway and reverse proxy)
- Redis
- RabbitMQ

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
- **Frontend**: http://localhost:8080
- **Unified API Documentation**: http://localhost:8080/api/docs
- **OpenAPI JSON**: http://localhost:8080/api/docs/openapi.json
- **OpenAPI YAML**: http://localhost:8080/api/docs/openapi.yaml

All API requests go through the gateway: `http://localhost:8080/api/*`

### 5. Start Backend Services

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

The frontend development server runs on port 3000 but NGINX serves it through port 8080.

## Access Patterns

All user-facing access goes through the NGINX gateway at `http://localhost:8080`.

**API Endpoints:**
- Transactions: `http://localhost:8080/api/v1/transactions`
- Currencies: `http://localhost:8080/api/v1/currencies`
- Exchange Rates: `http://localhost:8080/api/v1/exchange-rates`

**Development Tools (direct service access):**
- Transaction Service Swagger: `http://localhost:8082/swagger-ui.html`
- Currency Service Swagger: `http://localhost:8084/swagger-ui.html`
- Transaction Service Health: `http://localhost:8082/actuator/health`
- Currency Service Health: `http://localhost:8084/actuator/health`

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
