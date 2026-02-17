# Phase 5: Tiltfile Configuration Implementation Plan

This document provides a step-by-step guide for completing Phase 5 of the Tilt and Kind deployment. The goal is to create a comprehensive Tiltfile that enables live reload development for all services with fast iteration cycles.

---

## Prerequisites

- Phase 1 completed (Kind cluster running with cert-manager and Envoy Gateway)
- Phase 2 completed (Gateway API configuration with HTTPRoutes)
- Phase 3 completed (Infrastructure services: PostgreSQL, Redis, RabbitMQ)
- Phase 4 completed (Core services deployed: nginx-gateway, session-gateway, token-validation-service, backend microservices)
- All service repositories cloned in `/workspace/`:
  - `/workspace/session-gateway`
  - `/workspace/token-validation-service`
  - `/workspace/transaction-service`
  - `/workspace/currency-service`
  - `/workspace/permission-service`
  - `/workspace/budget-analyzer-web`
- Tilt installed on your system

---

## Overview

Phase 5 sets up Tilt for rapid local development with these key features:

1. **Live Reload**: Automatic rebuilds and deployments when code changes
2. **Parallel Builds**: Multiple services compile simultaneously for faster iteration
3. **Hot Module Replacement**: React frontend updates without page refresh
4. **Remote Debugging**: Debug Spring Boot services from your IDE
5. **Infrastructure Management**: Helm charts managed through Tilt UI

---

## Step 1: Install Tilt

**Objective:** To install Tilt on your development machine.

### 1.1. Install Tilt CLI

**Action:** Install Tilt using the appropriate method for your OS.

**macOS:**
```bash
brew install tilt-dev/tap/tilt
```

**Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
```

**Windows:**
```powershell
iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.ps1'))
```

### 1.2. Verify Installation

**Action:** Confirm Tilt is installed correctly.

```bash
tilt version
```

**Expected Output:** Version information (v0.33.x or later recommended).

---

## Step 2: Create Tiltfile Project Structure

**Objective:** To organize Tilt configuration in a modular structure for maintainability.

### 2.1. Create Directory Structure

**Action:** Create the tilt configuration directory.

```bash
mkdir -p tilt
```

### 2.2. Create Common Configuration File

**Action:** Create a shared configuration file with constants and reusable functions.

```bash
cat <<'EOF' > tilt/common.star
# Common configuration and helper functions for Budget Analyzer Tiltfile

# Workspace root where all repositories are cloned
WORKSPACE = '/workspace'

# Namespaces
DEFAULT_NAMESPACE = 'default'
INFRA_NAMESPACE = 'infrastructure'

# Service ports (matching deployment manifests)
SERVICE_PORTS = {
    'transaction-service': 8082,
    'currency-service': 8084,
    'permission-service': 8086,
    'token-validation-service': 8088,
    'session-gateway': 8081,
    'nginx-gateway': 8080,
    'budget-analyzer-web': 3000,
}

# Debug ports (each service gets unique local port)
DEBUG_PORTS = {
    'transaction-service': 5005,
    'currency-service': 5006,
    'permission-service': 5007,
    'token-validation-service': 5008,
    'session-gateway': 5009,
}

def get_repo_path(service_name):
    """Get the full path to a service repository."""
    return WORKSPACE + '/' + service_name
EOF
```

---

## Step 3: Create Main Tiltfile

**Objective:** To create the main Tiltfile that orchestrates all services with live reload.

### 3.1. Create Tiltfile

**Action:** Create the main Tiltfile in the orchestration repository root.

```bash
cat <<'EOF' > Tiltfile
# ============================================================================
# Budget Analyzer - Tiltfile
# Phase 5: Complete Local Development Environment with Live Reload
# ============================================================================

# Load extensions
load('ext://helm_resource', 'helm_resource', 'helm_repo')
load('ext://restart_process', 'docker_build_with_restart')
load('ext://uibutton', 'cmd_button', 'location')
load('ext://secret', 'secret_from_dict')
load('ext://configmap', 'configmap_create')

# Load common configuration
load('./tilt/common.star',
     'WORKSPACE',
     'DEFAULT_NAMESPACE',
     'INFRA_NAMESPACE',
     'SERVICE_PORTS',
     'DEBUG_PORTS',
     'get_repo_path')

# ============================================================================
# GLOBAL SETTINGS
# ============================================================================

# Restrict to our Kind cluster for safety
allow_k8s_contexts('kind-kind')

# Performance tuning
update_settings(
    max_parallel_updates=5,
    k8s_upsert_timeout_secs=120,
)

# Docker image pruning
docker_prune_settings(
    max_age_mins=360,
    num_builds=10,
    keep_recent=3,
)

# ============================================================================
# INFRASTRUCTURE SERVICES (Helm Charts)
# ============================================================================

# Add Bitnami Helm repository
helm_repo('bitnami', 'https://charts.bitnami.com/bitnami')

# PostgreSQL
helm_resource(
    'postgresql',
    'bitnami/postgresql',
    namespace=INFRA_NAMESPACE,
    flags=[
        '--create-namespace',
        '--values=kubernetes/infrastructure/values/postgresql-values.yaml',
    ],
    port_forwards=[
        port_forward(5432, 5432, name='PostgreSQL'),
    ],
    labels=['infrastructure', 'database'],
    resource_deps=['bitnami']
)

# Redis
helm_resource(
    'redis',
    'bitnami/redis',
    namespace=INFRA_NAMESPACE,
    flags=[
        '--values=kubernetes/infrastructure/values/redis-values.yaml',
    ],
    port_forwards=[
        port_forward(6379, 6379, name='Redis'),
    ],
    labels=['infrastructure', 'cache'],
    resource_deps=['bitnami']
)

# RabbitMQ
helm_resource(
    'rabbitmq',
    'bitnami/rabbitmq',
    namespace=INFRA_NAMESPACE,
    flags=[
        '--values=kubernetes/infrastructure/values/rabbitmq-values.yaml',
    ],
    port_forwards=[
        port_forward(5672, 5672, name='AMQP'),
        port_forward(15672, 15672, name='Management UI'),
    ],
    labels=['infrastructure', 'messaging'],
    resource_deps=['bitnami']
)

# ============================================================================
# SECRETS
# ============================================================================

# PostgreSQL credentials for services
secret_from_dict(
    'postgresql-credentials',
    namespace=DEFAULT_NAMESPACE,
    inputs={
        'username': 'budget_analyzer',
        'password': 'budget_analyzer',
        'budget-analyzer-url': 'jdbc:postgresql://postgresql.' + INFRA_NAMESPACE + ':5432/budget_analyzer',
        'currency-url': 'jdbc:postgresql://postgresql.' + INFRA_NAMESPACE + ':5432/currency',
        'permission-url': 'jdbc:postgresql://postgresql.' + INFRA_NAMESPACE + ':5432/permission',
    }
)

# Redis credentials
secret_from_dict(
    'redis-credentials',
    namespace=DEFAULT_NAMESPACE,
    inputs={
        'host': 'redis-master.' + INFRA_NAMESPACE,
        'port': '6379',
    }
)

# RabbitMQ credentials
secret_from_dict(
    'rabbitmq-credentials',
    namespace=DEFAULT_NAMESPACE,
    inputs={
        'host': 'rabbitmq.' + INFRA_NAMESPACE,
        'amqp-port': '5672',
        'username': 'user',
        'password': 'password',
    }
)

# ============================================================================
# SPRING BOOT SERVICE BUILD PATTERN
# ============================================================================

def spring_boot_service(name, deps=[]):
    """
    Build pattern for Spring Boot services with live reload.

    Args:
        name: Service name (must match repository name)
        deps: Additional resource dependencies
    """
    repo_path = get_repo_path(name)
    port = SERVICE_PORTS[name]
    debug_port = DEBUG_PORTS.get(name)

    # Step 1: Local Gradle compilation
    local_resource(
        name + '-compile',
        cmd='cd ' + repo_path + ' && ./gradlew bootJar --parallel --build-cache -x test',
        deps=[
            repo_path + '/src',
            repo_path + '/build.gradle.kts',
        ],
        labels=['compile'],
        allow_parallel=True,
        auto_init=True
    )

    # Step 2: Docker build with restart capability
    docker_build_with_restart(
        name,
        context=repo_path,
        dockerfile=repo_path + '/Dockerfile',
        only=[
            'build/libs/*.jar',
            'Dockerfile',
        ],
        entrypoint=[
            'java',
            '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005',
            '-jar',
            '/app/app.jar'
        ],
        live_update=[
            sync(repo_path + '/build/libs', '/app'),
        ]
    )

    # Step 3: Load Kubernetes manifests
    k8s_yaml([
        'kubernetes/services/' + name + '/deployment.yaml',
        'kubernetes/services/' + name + '/service.yaml',
    ])

    # Step 4: Configure resource with port forwards and dependencies
    port_forwards_list = [
        port_forward(port, port, name='HTTP'),
    ]
    if debug_port:
        port_forwards_list.append(port_forward(debug_port, 5005, name='Debug'))

    base_deps = ['postgresql', 'rabbitmq'] if name in ['transaction-service', 'currency-service', 'permission-service'] else []

    k8s_resource(
        name,
        port_forwards=port_forwards_list,
        labels=['backend'] if name in ['transaction-service', 'currency-service', 'permission-service'] else ['gateway'],
        resource_deps=base_deps + deps,
        objects=[name + '-compile']
    )

# ============================================================================
# BACKEND MICROSERVICES
# ============================================================================

# Transaction Service
spring_boot_service('transaction-service')

# Currency Service
spring_boot_service('currency-service')

# Permission Service
spring_boot_service('permission-service')

# ============================================================================
# GATEWAY SERVICES
# ============================================================================

# Token Validation Service
spring_boot_service('token-validation-service', deps=['redis'])

# Session Gateway
repo_path = get_repo_path('session-gateway')

local_resource(
    'session-gateway-compile',
    cmd='cd ' + repo_path + ' && ./gradlew bootJar --parallel --build-cache -x test',
    deps=[
        repo_path + '/src',
        repo_path + '/build.gradle.kts',
    ],
    labels=['compile'],
    allow_parallel=True
)

docker_build_with_restart(
    'session-gateway',
    context=repo_path,
    dockerfile=repo_path + '/Dockerfile',
    only=[
        'build/libs/*.jar',
        'Dockerfile',
    ],
    entrypoint=[
        'java',
        '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005',
        '-jar',
        '/app/app.jar'
    ],
    live_update=[
        sync(repo_path + '/build/libs', '/app'),
    ]
)

k8s_yaml([
    'kubernetes/services/session-gateway/deployment.yaml',
    'kubernetes/services/session-gateway/service.yaml',
    'kubernetes/services/session-gateway/configmap.yaml',
])

k8s_resource(
    'session-gateway',
    port_forwards=[
        port_forward(8081, 8081, name='HTTP'),
        port_forward(5009, 5005, name='Debug'),
    ],
    labels=['gateway'],
    resource_deps=['redis', 'token-validation-service']
)

# ============================================================================
# NGINX GATEWAY
# ============================================================================

# Create ConfigMap from NGINX configuration with auto-reload
configmap_create(
    'nginx-gateway-config',
    namespace=DEFAULT_NAMESPACE,
    from_file=['nginx.conf=nginx/nginx.k8s.conf'],
    watch=True
)

configmap_create(
    'nginx-gateway-includes',
    namespace=DEFAULT_NAMESPACE,
    from_file=[
        'api-protection.conf=nginx/includes/api-protection.conf',
        'admin-api-protection.conf=nginx/includes/admin-api-protection.conf',
        'backend-headers.conf=nginx/includes/backend-headers.conf',
    ],
    watch=True
)

k8s_yaml([
    'kubernetes/services/nginx-gateway/deployment.yaml',
    'kubernetes/services/nginx-gateway/service.yaml',
])

k8s_resource(
    'nginx-gateway',
    port_forwards=[
        port_forward(8080, 8080, name='HTTP'),
    ],
    labels=['gateway'],
    resource_deps=['session-gateway', 'token-validation-service']
)

# ============================================================================
# FRONTEND (React/Vite with HMR)
# ============================================================================

frontend_repo = get_repo_path('budget-analyzer-web')

docker_build(
    'budget-analyzer-web',
    context=frontend_repo,
    dockerfile=frontend_repo + '/Dockerfile.dev',
    live_update=[
        # Sync source files for instant HMR
        sync(frontend_repo + '/src', '/app/src'),
        sync(frontend_repo + '/public', '/app/public'),
        sync(frontend_repo + '/index.html', '/app/index.html'),
        # Reinstall dependencies if package.json changes
        run(
            'cd /app && npm install',
            trigger=[frontend_repo + '/package.json', frontend_repo + '/package-lock.json']
        ),
    ]
)

k8s_yaml([
    'kubernetes/services/budget-analyzer-web/deployment.yaml',
    'kubernetes/services/budget-analyzer-web/service.yaml',
])

k8s_resource(
    'budget-analyzer-web',
    port_forwards=[
        port_forward(3000, 3000, name='Vite Dev Server'),
    ],
    labels=['frontend'],
    resource_deps=['nginx-gateway'],
    links=[
        link('https://app.budgetanalyzer.localhost', 'Application'),
    ]
)

# ============================================================================
# GATEWAY API RESOURCES
# ============================================================================

k8s_yaml([
    'kubernetes/gateway/gateway.yaml',
    'kubernetes/gateway/httproutes.yaml',
])

k8s_resource(
    'budgetanalyzer-gateway',
    labels=['gateway-api'],
    new_name='envoy-gateway-routes'
)

# ============================================================================
# UI ENHANCEMENTS
# ============================================================================

# Custom buttons for common operations
cmd_button(
    'rebuild-all-backend',
    argv=['bash', '-c', 'cd /workspace && for d in transaction-service currency-service permission-service; do (cd $d && ./gradlew bootJar --parallel) & done; wait'],
    resource='transaction-service',
    icon_name='build',
    text='Rebuild All Backend'
)

cmd_button(
    'run-tests',
    argv=['./gradlew', 'test'],
    resource='transaction-service-compile',
    icon_name='science',
    text='Run Tests',
    location=location.RESOURCE
)

cmd_button(
    'db-migrate',
    argv=['./gradlew', 'flywayMigrate'],
    resource='transaction-service-compile',
    icon_name='storage',
    text='Run Migrations',
    location=location.RESOURCE
)

# ============================================================================
# LOCAL RESOURCES FOR DEVELOPMENT TASKS
# ============================================================================

# Database migration runner
local_resource(
    'run-all-migrations',
    cmd='''
        cd /workspace/transaction-service && ./gradlew flywayMigrate -Pflyway.url=jdbc:postgresql://localhost:5432/budget_analyzer -Pflyway.user=budget_analyzer -Pflyway.password=budget_analyzer && \
        cd /workspace/currency-service && ./gradlew flywayMigrate -Pflyway.url=jdbc:postgresql://localhost:5432/currency -Pflyway.user=budget_analyzer -Pflyway.password=budget_analyzer && \
        cd /workspace/permission-service && ./gradlew flywayMigrate -Pflyway.url=jdbc:postgresql://localhost:5432/permission -Pflyway.user=budget_analyzer -Pflyway.password=budget_analyzer
    ''',
    labels=['database'],
    resource_deps=['postgresql'],
    trigger_mode=TRIGGER_MODE_MANUAL,
    auto_init=False
)

# Kind image loader (for manual reloads)
local_resource(
    'load-images-to-kind',
    cmd='''
        for img in transaction-service currency-service permission-service token-validation-service session-gateway budget-analyzer-web; do
            kind load docker-image $img:latest 2>/dev/null || true
        done
    ''',
    labels=['setup'],
    trigger_mode=TRIGGER_MODE_MANUAL,
    auto_init=False
)
EOF
```

---

## Step 4: Create Frontend Development Dockerfile

**Objective:** To create a Dockerfile optimized for Vite development with HMR support.

### 4.1. Create Dockerfile.dev

**Action:** Create a development Dockerfile in the budget-analyzer-web repository.

```bash
cat <<'EOF' > /workspace/budget-analyzer-web/Dockerfile.dev
# Development Dockerfile for React/Vite with HMR
FROM node:20-alpine

WORKDIR /app

# Install dependencies first for better caching
COPY package*.json ./
RUN npm install

# Copy source code
COPY . .

# Expose Vite dev server port
EXPOSE 3000

# Configure environment for container
ENV NODE_ENV=development
ENV VITE_HOST=0.0.0.0

# Start Vite dev server
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "3000"]
EOF
```

### 4.2. Update Vite Configuration for Kubernetes

**Action:** Ensure the Vite configuration supports HMR through port forwarding.

Create or update `/workspace/budget-analyzer-web/vite.config.ts`:

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 3000,
    strictPort: true,
    watch: {
      // Use polling for Docker/Kubernetes file watching
      usePolling: true,
      interval: 1000,
    },
  },
})
```

---

## Step 5: Create IDE Debug Configurations

**Objective:** To set up remote debugging configurations for IDEs.

### 5.1. VS Code Launch Configuration

**Action:** Create a launch.json file for debugging Spring Boot services.

```bash
mkdir -p .vscode
cat <<'EOF' > .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "Debug transaction-service",
      "request": "attach",
      "hostName": "localhost",
      "port": 5005
    },
    {
      "type": "java",
      "name": "Debug currency-service",
      "request": "attach",
      "hostName": "localhost",
      "port": 5006
    },
    {
      "type": "java",
      "name": "Debug permission-service",
      "request": "attach",
      "hostName": "localhost",
      "port": 5007
    },
    {
      "type": "java",
      "name": "Debug token-validation-service",
      "request": "attach",
      "hostName": "localhost",
      "port": 5008
    },
    {
      "type": "java",
      "name": "Debug session-gateway",
      "request": "attach",
      "hostName": "localhost",
      "port": 5009
    }
  ]
}
EOF
```

### 5.2. IntelliJ Configuration

**Explanation:** For IntelliJ IDEA, create Remote JVM Debug configurations manually:

1. Go to Run → Edit Configurations
2. Add New Configuration → Remote JVM Debug
3. Set Host: `localhost`
4. Set Port: `5005` (or appropriate debug port from the list)
5. Name it after the service (e.g., "Debug transaction-service")

---

## Step 6: Verify Tiltfile Syntax

**Objective:** To ensure the Tiltfile has no syntax errors before running.

### 6.1. Check Tiltfile Syntax

**Action:** Run Tilt's config validation.

```bash
tilt config
```

**Expected Output:** No errors. If there are errors, they will be displayed with line numbers.

### 6.2. List Resources

**Action:** View all resources that will be managed by Tilt.

```bash
tilt get resources
```

**Expected Output:** List of all defined resources (services, local_resources, etc.).

---

## Step 7: Start Tilt Development Environment

**Objective:** To launch the complete development environment with live reload.

### 7.1. Start Tilt

**Action:** Launch Tilt from the orchestration directory.

```bash
cd /workspace/orchestration
tilt up
```

**Expected Output:** Tilt starts and opens the web UI at http://localhost:10350

### 7.2. Access Tilt UI

**Action:** Open the Tilt dashboard in your browser.

```bash
# Tilt automatically opens the UI, or access it manually:
open http://localhost:10350
```

### 7.3. Wait for Services to Start

**Action:** Monitor the Tilt UI until all resources show green (healthy) status.

The startup order will be:
1. Infrastructure (PostgreSQL, Redis, RabbitMQ) - ~2-3 minutes
2. Gateway services (token-validation, session-gateway, nginx) - ~1-2 minutes
3. Backend services (transaction, currency, permission) - ~1-2 minutes
4. Frontend (budget-analyzer-web) - ~30 seconds

**Total expected startup time:** 5-8 minutes on first run, 1-2 minutes on subsequent runs.

---

## Step 8: Verify Development Environment

**Objective:** To confirm all services are running and accessible.

### 8.1. Check All Resources

**Action:** View resource status in Tilt UI or CLI.

```bash
tilt get resources
```

**Expected Output:** All resources should show `ok` or `running` status.

### 8.2. Test Application Access

**Action:** Access the application through the browser.

```bash
# Application entry point
curl -k https://app.budgetanalyzer.localhost

# API health check
curl -k https://api.budgetanalyzer.localhost/health
```

### 8.3. Test Service Health Endpoints

**Action:** Verify individual service health via port forwards.

```bash
# Transaction Service
curl http://localhost:8082/actuator/health

# Currency Service
curl http://localhost:8084/actuator/health

# Permission Service
curl http://localhost:8086/actuator/health

# Token Validation Service
curl http://localhost:8088/actuator/health

# Session Gateway
curl http://localhost:8081/actuator/health
```

**Expected Output:** All services return `{"status":"UP"}` or similar healthy response.

### 8.4. Test Live Reload

**Action:** Make a small change to verify live reload works.

```bash
# Make a change to a Java file
echo "// Test change $(date)" >> /workspace/transaction-service/src/main/java/com/budgetanalyzer/transaction/TransactionServiceApplication.java

# Watch the Tilt UI - it should automatically:
# 1. Detect the change
# 2. Run Gradle compile
# 3. Rebuild Docker image
# 4. Restart the pod

# Revert the change
git -C /workspace/transaction-service checkout src/
```

### 8.5. Test Frontend HMR

**Action:** Verify React hot module replacement works.

```bash
# Open the frontend in browser
open http://localhost:3000

# Make a change to a React component
# The browser should update without full page refresh
```

---

## Step 9: Common Development Workflows

**Objective:** To document common development tasks with Tilt.

### 9.1. Viewing Logs

**Action:** View logs for a specific service.

```bash
# Via CLI
tilt logs transaction-service

# Or use the Tilt UI - click on a resource to see its logs
```

### 9.2. Restarting a Service

**Action:** Manually trigger a rebuild/restart.

```bash
# Via CLI
tilt trigger transaction-service

# Or click the "Trigger Update" button in Tilt UI
```

### 9.3. Running Database Migrations

**Action:** Execute database migrations.

```bash
# Click the "Run Migrations" button in Tilt UI
# Or trigger manually:
tilt trigger run-all-migrations
```

### 9.4. Attaching Debugger

**Action:** Connect your IDE debugger to a running service.

1. Ensure the service is running (green in Tilt UI)
2. Open your IDE (VS Code or IntelliJ)
3. Start the debug configuration for the service
4. Set breakpoints in your code
5. Make a request to trigger the breakpoint

### 9.5. Stopping Tilt

**Action:** Gracefully shut down the development environment.

```bash
# Press Ctrl+C in the terminal running tilt up
# Or:
tilt down
```

---

## Troubleshooting

### Resource Stuck in "Pending" State

**Symptom:** A resource shows as pending and never starts.

**Solution:** Check for missing dependencies or failed prerequisite resources.

```bash
# View resource details
tilt describe <resource-name>

# Check logs for errors
tilt logs <resource-name>
```

### Image Pull Errors

**Symptom:** Pod shows `ImagePullBackOff` or `ErrImagePull`.

**Solution:** Ensure images are loaded into Kind cluster.

```bash
# Check if image exists locally
docker images | grep <service-name>

# Load into Kind
kind load docker-image <service-name>:latest

# Verify in Kind
docker exec -it kind-control-plane crictl images | grep <service-name>
```

### Gradle Build Failures

**Symptom:** Compilation fails with dependency errors.

**Solution:** Check Gradle configuration and network access.

```bash
# Run build manually to see full error
cd /workspace/<service-name>
./gradlew bootJar --info

# Clear Gradle cache if needed
./gradlew clean
rm -rf ~/.gradle/caches
```

### HMR Not Working for Frontend

**Symptom:** React changes don't trigger hot reload.

**Solution:** Check Vite configuration and file watching.

1. Verify `usePolling: true` in vite.config.ts
2. Check that port 3000 is correctly forwarded
3. Ensure the sync paths in live_update match your project structure

```bash
# Check frontend logs
tilt logs budget-analyzer-web

# Restart the frontend
tilt trigger budget-analyzer-web
```

### Service Cannot Connect to Database

**Symptom:** Backend service fails with database connection errors.

**Solution:** Verify PostgreSQL is running and credentials are correct.

```bash
# Check PostgreSQL status
tilt get postgresql

# Test connection
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=postgresql -n infrastructure -o jsonpath='{.items[0].metadata.name}') -n infrastructure -- psql -U budget_analyzer -d postgres -c "\l"

# Check secret
kubectl get secret postgresql-credentials -o yaml
```

### Port Forward Conflicts

**Symptom:** Port already in use errors.

**Solution:** Find and kill the process using the port.

```bash
# Find process using port
lsof -i :8082

# Kill process
kill -9 <PID>

# Or use different local ports in Tiltfile
```

### Tilt UI Not Loading

**Symptom:** Cannot access http://localhost:10350

**Solution:** Check if Tilt is running and the port is available.

```bash
# Check if tilt is running
ps aux | grep tilt

# Check port availability
lsof -i :10350

# Try a different port
tilt up --port 10351
```

---

## Performance Optimization Tips

### 1. Use Gradle Build Cache

Ensure your `gradle.properties` has caching enabled:

```properties
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.daemon=true
```

### 2. Skip Tests During Development

The Tiltfile already includes `-x test` in Gradle builds. Run tests manually when needed:

```bash
tilt trigger run-tests
```

### 3. Increase Docker Resources

Ensure Docker has adequate resources:
- Memory: At least 8GB
- CPUs: At least 4

### 4. Use Selective Sync

Only sync necessary files in live_update to reduce I/O:

```python
live_update=[
    sync(repo_path + '/build/libs', '/app'),  # Only the JAR
]
```

### 5. Parallel Compilation

The Tiltfile enables `allow_parallel=True` for compile resources to build services simultaneously.

---

## Next Steps

After completing Phase 5, you have a fully functional development environment with:

- Live reload for all services
- Remote debugging support
- HMR for React frontend
- Database access and migrations
- Organized UI with resource grouping

Proceed to:

- **Phase 6: Production Parity Documentation** - Document GKE deployment differences and CI/CD pipeline templates

---

## Cleanup

To completely remove the Tilt-managed resources:

```bash
# Stop Tilt and remove resources
tilt down

# Delete all Kubernetes resources (optional - keeps infrastructure)
kubectl delete deployment,service,configmap -l app.kubernetes.io/managed-by=tilt

# Delete infrastructure (optional - removes databases)
helm uninstall postgresql -n infrastructure
helm uninstall redis -n infrastructure
helm uninstall rabbitmq -n infrastructure
kubectl delete namespace infrastructure
```

---

## Quick Reference

### Common Commands

| Command | Description |
|---------|-------------|
| `tilt up` | Start development environment |
| `tilt down` | Stop and clean up resources |
| `tilt logs <resource>` | View logs for a resource |
| `tilt trigger <resource>` | Manually trigger rebuild |
| `tilt get resources` | List all resources |
| `tilt describe <resource>` | Get detailed resource info |

### Port Forwards

| Service | HTTP Port | Debug Port |
|---------|-----------|------------|
| transaction-service | 8082 | 5005 |
| currency-service | 8084 | 5006 |
| permission-service | 8086 | 5007 |
| token-validation-service | 8088 | 5008 |
| session-gateway | 8081 | 5009 |
| nginx-gateway | 8080 | - |
| budget-analyzer-web | 3000 | - |
| postgresql | 5432 | - |
| redis | 6379 | - |
| rabbitmq | 5672, 15672 | - |

### URLs

| URL | Description |
|-----|-------------|
| http://localhost:10350 | Tilt UI |
| https://app.budgetanalyzer.localhost | Application |
| https://api.budgetanalyzer.localhost | API Gateway |
| http://localhost:15672 | RabbitMQ Management |
