# Local Development Environment Setup

**Status:** Active
**Audience:** Developers setting up Budget Analyzer locally

## Prerequisites

### Required Software

**Minimum versions:**
- Docker 24.0+
- Kind 0.20+
- kubectl 1.28+
- Helm 3.12+
- Tilt 0.33+
- Git 2.40+

**For Backend Development (Optional):**
- JDK 24 (for running services outside Docker)
- Gradle 8.5+ or use `./gradlew`

**For Frontend Development (Optional):**
- Node.js 20+ (LTS)
- npm 10+

### Verify Prerequisites

```bash
# Run the check script
./scripts/dev/check-tilt-prerequisites.sh

# Or check manually:
docker --version
kind --version
kubectl version --client
helm version
tilt version
git --version
```

## Quick Start

### 1. Clone Repositories

```bash
# Create workspace directory
mkdir -p ~/workspace/budget-analyzer
cd ~/workspace/budget-analyzer

# Clone orchestration (required)
git clone https://github.com/budgetanalyzer/orchestration.git

# Clone services (as needed)
git clone https://github.com/budgetanalyzer/service-common.git
git clone https://github.com/budgetanalyzer/transaction-service.git
git clone https://github.com/budgetanalyzer/currency-service.git
git clone https://github.com/budgetanalyzer/budget-analyzer-web.git
git clone https://github.com/budgetanalyzer/session-gateway.git
git clone https://github.com/budgetanalyzer/token-validation-service.git
git clone https://github.com/budgetanalyzer/permission-service.git
```

**Repository structure:**
```
~/workspace/budget-analyzer/
├── orchestration/           # This repo
├── service-common/          # Shared Spring Boot library
├── transaction-service/     # Transaction microservice
├── currency-service/        # Currency microservice
├── permission-service/      # Permission microservice
├── session-gateway/         # BFF for authentication
├── token-validation-service/ # JWT validation
└── budget-analyzer-web/     # React frontend
```

**Important:** This side-by-side layout is **required** for cross-repository documentation links to work correctly.

### 2. Set Up Local HTTPS

The application uses HTTPS for local development with clean subdomain URLs. Run the setup script on your **host machine** (not in containers):

```bash
cd orchestration/

# Install mkcert first (if not installed)
# macOS:   brew install mkcert nss
# Linux:   sudo apt install libnss3-tools && see mkcert docs
# Windows: choco install mkcert

# Run the setup script
./scripts/dev/setup-k8s-tls.sh
```

**What this script does:**
1. Creates a Kind cluster if it doesn't exist
2. Installs a local CA in your system's trust store
3. Generates wildcard certificate for `*.budgetanalyzer.localhost`
4. Creates Kubernetes TLS secret for Envoy Gateway

**Important:** Restart your browser after running this script.

### 3. Configure Environment Variables

```bash
# Copy the example file
cp .env.example .env

# Edit .env with your Auth0 credentials
```

### 4. Start All Services

```bash
cd orchestration/
tilt up
```

### 5. Verify Services

```bash
# Check all pods are running
kubectl get pods -n budget-analyzer
kubectl get pods -n infrastructure

# Test gateway
curl https://api.budgetanalyzer.localhost/health

# Open frontend
open https://app.budgetanalyzer.localhost
```

## Tilt Resources

### Compile Resources

Tilt compiles services locally using Gradle, then builds Docker images:

- `service-common-publish` - Publishes shared library to Maven Local
- `transaction-service-compile` - Compiles transaction service
- `currency-service-compile` - Compiles currency service
- `permission-service-compile` - Compiles permission service
- `session-gateway-compile` - Compiles session gateway
- `token-validation-service-compile` - Compiles token validation service

### Infrastructure Resources

- `postgresql` - PostgreSQL StatefulSet
- `redis` - Redis Deployment
- `rabbitmq` - RabbitMQ StatefulSet
- `envoy-gateway` - Envoy Gateway controller
- `ingress-gateway` - Gateway and HTTPRoute resources

## Development Workflows

### Workflow 1: Full Stack via Tilt (Recommended)

**Best for:** Most development scenarios

```bash
cd orchestration/
tilt up
```

**All services in Kubernetes:**
- Live reload for all services
- Automatic rebuilds on file changes
- Unified logging in Tilt UI

### Workflow 2: Backend Service Local, Rest in Tilt

**Best for:** Debugging a specific backend service

```bash
# Start everything in Tilt
tilt up

# Scale down the service you want to debug
kubectl scale deployment transaction-service -n budget-analyzer --replicas=0

# Run locally with debugger
cd transaction-service/
./gradlew bootRun --args='--spring.profiles.active=local'
```

**Benefits:**
- Full debugging capabilities with IDE
- Breakpoints and step-through debugging
- Service still accessible via port forward

### Workflow 3: Frontend Local, Backend in Tilt

**Best for:** Frontend development with HMR

```bash
# Start backend in Tilt
tilt up

# Scale down frontend
kubectl scale deployment budget-analyzer-web -n budget-analyzer --replicas=0

# Run frontend locally
cd budget-analyzer-web/
npm install
npm run dev
```

**Benefits:**
- Faster HMR (Hot Module Replacement)
- Local debugging tools

## Database Setup

See: [database-setup.md](database-setup.md) for detailed database configuration.

**Quick reference:**
```bash
# PostgreSQL connection (via port forward)
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
| Envoy Gateway | 443 | https://app.budgetanalyzer.localhost | **Primary browser entry point** |
| Envoy Gateway | 443 | https://api.budgetanalyzer.localhost | API gateway |
| NGINX Gateway | 8080 | - | Internal (JWT validation, routing) |
| Session Gateway | 8081 | - | Internal (behind Envoy) |
| transaction-service | 8082 | http://localhost:8082 | Direct access via port forward |
| currency-service | 8084 | http://localhost:8084 | Direct access via port forward |
| permission-service | 8086 | http://localhost:8086 | Direct access via port forward |
| Token Validation | 8088 | http://localhost:8088 | Direct access via port forward |
| Frontend | 3000 | http://localhost:3000 | Direct access via port forward |
| PostgreSQL | 5432 | localhost:5432 | Database access |
| Redis | 6379 | localhost:6379 | Cache access |
| RabbitMQ | 5672/15672 | localhost:15672 | Management UI |
| Tilt UI | 10350 | http://localhost:10350 | Development dashboard |

## Environment Variables

### Backend Services (Spring Boot)

Environment variables are injected via Kubernetes secrets. For local development outside Tilt, create `application-local.yml`:

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
# API Base URL (relative, served through same origin)
VITE_API_BASE_URL=/api

# Feature flags (optional)
VITE_ENABLE_ANALYTICS=true
```

## Troubleshooting

### Port Already in Use (Tilt)

If you see this error when running `tilt up`:
```
Error: Tilt cannot start because you already have another process on port 10350
```

**Check what's using the port:**
```bash
lsof -i :10350
```

**Common cause:** VS Code port forwarding is reserving the port. If you see `code` as the process:
```
COMMAND    PID  USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
code    151299 devex   93u  IPv4 584246      0t0  TCP localhost:10350 (LISTEN)
```

**Solution:** Disable VS Code auto port forwarding in your user settings:
```json
{
  "remote.autoForwardPorts": false
}
```

Then restart VS Code. See the [Sandboxed Container Configuration](#sandboxed-container-configuration) section for more details.

### Pod Not Starting

```bash
# Check pod status and events
kubectl describe pod -n budget-analyzer <pod-name>

# Check logs
kubectl logs -n budget-analyzer <pod-name>

# Check Tilt UI for compile errors
# http://localhost:10350
```

### Database Connection Refused

```bash
# Check if PostgreSQL is running
kubectl get pods -n infrastructure | grep postgresql

# View PostgreSQL logs
kubectl logs -n infrastructure postgresql-0

# Verify port forward is active
kubectl port-forward -n infrastructure svc/postgresql 5432:5432
```

### Service Not Responding

```bash
# Check service endpoints
kubectl get endpoints -n budget-analyzer <service-name>

# Check service logs
kubectl logs -n budget-analyzer deployment/<service-name>

# Check if service is healthy
curl http://localhost:<port>/actuator/health
```

### NGINX Gateway Issues

```bash
# Check NGINX config syntax
kubectl exec -n budget-analyzer deployment/nginx-gateway -- nginx -t

# View NGINX logs
kubectl logs -n budget-analyzer deployment/nginx-gateway

# Trigger config reload
tilt trigger nginx-gateway-config
```

### Envoy Gateway Issues

```bash
# Check Envoy Gateway controller
kubectl logs -n envoy-gateway-system deployment/envoy-gateway

# Check Gateway status
kubectl get gateway -n budget-analyzer

# Check HTTPRoute status
kubectl get httproute -n budget-analyzer
```

### SSL Certificate Errors

```bash
# Re-run certificate setup on HOST
./scripts/dev/setup-k8s-tls.sh

# Verify secret exists
kubectl get secret -n budget-analyzer wildcard-tls

# Restart browser to clear certificate cache
```

## IDE Setup

> **Note:** IntelliJ IDEA is not supported. It cannot run containerized AI agents, making it unsuitable for AI-assisted development workflows.

### VS Code

**Extensions:**
- Spring Boot Extension Pack
- Gradle for Java
- ESLint (for frontend)
- Prettier (for frontend)
- Kubernetes (for cluster inspection)

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

**Sandboxed Container Configuration:**

When running VS Code in a sandboxed container (e.g., for AI agent development), disable automatic port forwarding to ensure complete isolation:

```json
// VS Code User Settings (not workspace settings)
{
  "remote.autoForwardPorts": false
}
```

**Why disable port forwarding?**
- **True isolation**: No accidental leakage between container and host
- **No port conflicts**: VS Code won't claim ports needed by Tilt or other services
- **Cleaner workflow**: No need to manage or kill processes on the host

**Note:** This setting goes in your VS Code user settings (`Ctrl/Cmd + ,`), not in the workspace `.vscode/settings.json` file.

## Next Steps

- **Database:** [database-setup.md](database-setup.md)
- **Architecture:** [../architecture/system-overview.md](../architecture/system-overview.md)
