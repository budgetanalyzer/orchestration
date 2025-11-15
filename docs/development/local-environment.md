# Local Development Environment Setup

**Status:** Active
**Audience:** Developers setting up Budget Analyzer locally

## Prerequisites

### Required Software

**Minimum versions:**
- Docker 24.0+
- Docker Compose 2.20+
- Git 2.40+

**For Backend Development (Optional):**
- JDK 21+ (for running services outside Docker)
- Gradle 8.5+ or use `./gradlew`

**For Frontend Development (Optional):**
- Node.js 20+ (LTS)
- npm 10+

### Verify Prerequisites

```bash
# Docker
docker --version
docker compose version

# Git
git --version

# Optional: Java
java -version

# Optional: Node.js
node --version
npm --version
```

## Quick Start

### 1. Clone Repositories

```bash
# Create workspace directory
mkdir -p ~/workspace/budget-analyzer
cd ~/workspace/budget-analyzer

# Clone orchestration (required)
git clone https://github.com/budget-analyzer/orchestration.git

# Clone services (as needed)
git clone https://github.com/budget-analyzer/service-common.git
git clone https://github.com/budget-analyzer/transaction-service.git
git clone https://github.com/budget-analyzer/currency-service.git
git clone https://github.com/budget-analyzer/budget-analyzer-web.git
```

**Repository structure:**
```
~/workspace/budget-analyzer/
├── orchestration/           # This repo
├── service-common/          # Shared Spring Boot library
├── transaction-service/     # Transaction microservice
├── currency-service/        # Currency microservice
└── budget-analyzer-web/     # React frontend
```

**Important:** This side-by-side layout is **required** for cross-repository documentation links to work correctly. Claude Code uses relative paths (e.g., `../service-common/CLAUDE.md`) to navigate between repositories, which only works when repositories are cloned adjacent to each other.

### 2. Start All Services

```bash
cd orchestration/

# Start everything (infrastructure + services)
docker compose up -d

# View logs
docker compose logs -f

# Stop everything
docker compose down
```

### 3. Verify Services

```bash
# Check all services running
docker compose ps

# Test gateway
curl http://localhost:8080/health

# Test backend services
curl http://localhost:8082/actuator/health  # transaction-service
curl http://localhost:8084/actuator/health  # currency-service

# Open frontend
open http://localhost:8080
```

## Service-by-Service Setup

### Shared Library (service-common)

**Before running any backend services**, you must publish the shared `service-common` library to your local Maven repository:

```bash
cd service-common/
./gradlew publishToMavenLocal
```

This makes the shared library available to all backend services (transaction-service, currency-service, etc.).

**When to republish:**
- After cloning service-common for the first time
- After pulling updates to service-common
- After making local changes to service-common

**Troubleshooting:**
If backend services fail to start with dependency errors like `Could not find com.budgetanalyzer:service-common:X.X.X`, republish service-common to Maven Local.

### Infrastructure Only

Start just infrastructure (PostgreSQL, Redis, RabbitMQ, NGINX):

```bash
docker compose up -d postgres redis rabbitmq api-gateway
```

### Backend Services (Spring Boot)

**Option 1: Run in Docker**
```bash
docker compose up -d transaction-service currency-service
```

**Option 2: Run locally (for development)**
```bash
# Terminal 1: transaction-service
cd transaction-service/
./gradlew bootRun

# Terminal 2: currency-service
cd currency-service/
./gradlew bootRun
```

**Benefits of local execution:**
- Faster iteration (hot reload)
- Easier debugging
- IDE integration

**Drawbacks:**
- Must manage Java dependencies locally
- Environment configuration required

### Frontend (React)

**Option 1: Run in Docker**
```bash
docker compose up -d budget-analyzer-web
```

**Option 2: Run locally (for development)**
```bash
cd budget-analyzer-web/
npm install
npm start
```

**Frontend will be available at:** http://localhost:8080 (served through NGINX gateway)

## Development Workflows

### Workflow 1: Full Stack in Docker

**Best for:** Testing complete system, minimal setup

```bash
cd orchestration/
docker compose up -d
```

**All services in Docker:**
- Fast setup (one command)
- Production-like environment
- Slower iteration (rebuild containers)

### Workflow 2: Backend Local, Frontend Docker

**Best for:** Backend development

```bash
# Start infrastructure + frontend
cd orchestration/
docker compose up -d postgres redis rabbitmq api-gateway budget-analyzer-web

# Run backend locally
cd transaction-service/
./gradlew bootRun
```

**Benefits:**
- Hot reload for backend code
- Fast iteration on backend
- Frontend still available

### Workflow 3: Frontend Local, Backend Docker

**Best for:** Frontend development

```bash
# Start infrastructure + backend
cd orchestration/
docker compose up -d postgres redis rabbitmq api-gateway \
  transaction-service currency-service

# Run frontend locally
cd budget-analyzer-web/
npm start
```

**Benefits:**
- Hot reload for frontend code
- Fast iteration on React components
- Backend APIs available

### Workflow 4: Everything Local

**Best for:** Full-stack development, debugging

```bash
# Start only infrastructure
cd orchestration/
docker compose up -d postgres redis rabbitmq api-gateway

# Terminal 1: transaction-service
cd transaction-service/
./gradlew bootRun

# Terminal 2: currency-service
cd currency-service/
./gradlew bootRun

# Terminal 3: frontend
cd budget-analyzer-web/
npm start
```

**Benefits:**
- Maximum development speed
- Full debugging capabilities
- IDE integration for all services

**Drawbacks:**
- More terminal windows
- More resource intensive
- More setup required

## Database Setup

See: [database-setup.md](database-setup.md) for detailed database configuration.

**Quick reference:**
```bash
# PostgreSQL connection
Host: localhost
Port: 5432
Database: budget_analyzer
User: budget_analyzer
Password: budget_analyzer

# Connection string
postgresql://budget_analyzer:budget_analyzer@localhost:5432/budget_analyzer
```

## Port Reference

| Service | Port | URL | Notes |
|---------|------|-----|-------|
| API Gateway (NGINX) | 8080 | http://localhost:8080 | **Primary access point** |
| Frontend (React dev server) | 3000 | - | Served through gateway on 8080 |
| transaction-service | 8082 | http://localhost:8082 | Direct access for development/debugging |
| currency-service | 8084 | http://localhost:8084 | Direct access for development/debugging |
| PostgreSQL | 5432 | localhost:5432 | Database access |
| Redis | 6379 | localhost:6379 | Cache access |
| RabbitMQ Management | 15672 | http://localhost:15672 | Management UI |

## Environment Variables

### Backend Services (Spring Boot)

Create `application-local.yml` in each service:

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/budget_analyzer
    username: budget_analyzer
    password: budget_analyzer

  redis:
    host: localhost
    port: 6379

  rabbitmq:
    host: localhost
    port: 5672
    username: guest
    password: guest

# Service-specific config
server:
  port: 8082  # Change per service
```

Activate with:
```bash
./gradlew bootRun --args='--spring.profiles.active=local'
```

### Frontend (React)

Create `.env.local`:

```bash
# API Gateway URL
VITE_API_BASE_URL=http://localhost:8080

# Feature flags (optional)
VITE_ENABLE_ANALYTICS=true
```

## Troubleshooting

### Port Already in Use

```bash
# Find process using port
lsof -i :8082

# Kill process
kill -9 <PID>

# Or change port in docker compose.yml
```

### Database Connection Refused

```bash
# Check if PostgreSQL is running
docker compose ps postgres

# View PostgreSQL logs
docker logs postgres

# Restart PostgreSQL
docker compose restart postgres
```

### Service Not Responding

```bash
# Check service logs
docker compose logs transaction-service

# Check if service is healthy
curl http://localhost:8082/actuator/health

# Restart service
docker compose restart transaction-service
```

### Frontend Not Loading

```bash
# Check if frontend is running
docker compose ps budget-analyzer-web

# View frontend logs
docker logs budget-analyzer-web

# Check if API gateway is accessible
curl http://localhost:8080/health

# Rebuild frontend
docker compose up -d --build budget-analyzer-web
```

### NGINX Gateway Issues

```bash
# Check NGINX config syntax
docker exec api-gateway nginx -t

# View NGINX logs
docker logs api-gateway

# Reload NGINX config
docker exec api-gateway nginx -s reload

# Restart gateway
docker compose restart api-gateway
```

## Data Seeding

### Test Data

```bash
# Seed test transactions
curl -X POST http://localhost:8082/admin/seed-test-data

# Seed currencies (one-time)
curl -X POST http://localhost:8084/admin/seed-currencies
```

### Sample CSV Files

Located in: `transaction-service/src/test/resources/csv-samples/`

**Upload via frontend:**
1. Go to http://localhost:8080
2. Click "Import"
3. Select CSV file
4. Choose bank format
5. Upload

## IDE Setup

### IntelliJ IDEA

**Import Projects:**
1. File → Open → Select `orchestration/` directory
2. Import as Gradle project
3. Repeat for each service repository

**Run Configurations:**
- Create Spring Boot run config for each service
- Set working directory to service root
- Add `--spring.profiles.active=local` to VM options

### VS Code

**Extensions:**
- Spring Boot Extension Pack
- Gradle for Java
- ESLint (for frontend)
- Prettier (for frontend)

**workspace.code-workspace:**
```json
{
  "folders": [
    {"path": "orchestration"},
    {"path": "service-common"},
    {"path": "transaction-service"},
    {"path": "currency-service"},
    {"path": "budget-analyzer-web"}
  ]
}
```

## Next Steps

- **Database:** [database-setup.md](database-setup.md)
- **Debugging:** [debugging-guide.md](debugging-guide.md)
- **Testing:** [testing-strategy.md](testing-strategy.md)
- **Architecture:** [../architecture/system-overview.md](../architecture/system-overview.md)
