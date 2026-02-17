# Phase 3: Infrastructure Services Implementation Plan

This document provides a step-by-step guide for completing Phase 3 of the Tilt and Kind deployment. The goal is to deploy the core infrastructure services (PostgreSQL, Redis, RabbitMQ) using Bitnami Helm charts and configure them to match the existing Docker Compose development environment.

---

## Prerequisites

- Phase 1 completed (Kind cluster running with cert-manager and Envoy Gateway)
- Phase 2 completed (Gateway API configuration in place)
- Helm 3.x installed locally

---

## Step 1: Create Infrastructure Namespace

**Objective:** To create a dedicated namespace for infrastructure services, keeping them organized and separate from application workloads.

### 1.1. Create the Namespace

**Action:** Create a namespace manifest and apply it.

```bash
mkdir -p kubernetes/infrastructure

cat <<EOF > kubernetes/infrastructure/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: infrastructure
  labels:
    app.kubernetes.io/component: infrastructure
EOF

kubectl apply -f kubernetes/infrastructure/namespace.yaml
```

### 1.2. Verify Namespace Creation

**Action:** Confirm the namespace exists.

```bash
kubectl get namespace infrastructure
```

**Expected Output:** The namespace should be listed with status `Active`.

---

## Step 2: Add Bitnami Helm Repository

**Objective:** To add the Bitnami Helm chart repository, which provides production-ready charts for PostgreSQL, Redis, and RabbitMQ.

### 2.1. Add Repository

**Action:** Add the Bitnami repository and update the local cache.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### 2.2. Verify Repository

**Action:** Confirm the repository was added successfully.

```bash
helm repo list | grep bitnami
```

**Expected Output:** You should see `bitnami` listed with the URL `https://charts.bitnami.com/bitnami`.

---

## Step 3: Deploy PostgreSQL

**Objective:** To deploy PostgreSQL using the Bitnami Helm chart with configuration matching the Docker Compose environment, including initialization scripts for creating multiple databases.

### 3.1. Create PostgreSQL Values File

**Action:** Create a Helm values file to configure PostgreSQL with the same credentials and settings as Docker Compose.

```bash
mkdir -p kubernetes/infrastructure/values

cat <<EOF > kubernetes/infrastructure/values/postgresql-values.yaml
# PostgreSQL Configuration for Budget Analyzer
# Matches docker-compose.yml settings for parity

auth:
  username: budget_analyzer
  password: budget_analyzer
  database: postgres

# Primary server configuration
primary:
  persistence:
    enabled: true
    size: 1Gi

  # Initialize multiple databases for microservices
  initdb:
    scripts:
      01-init-databases.sql: |
        -- Create separate databases for each microservice
        CREATE DATABASE budget_analyzer;
        GRANT ALL PRIVILEGES ON DATABASE budget_analyzer TO budget_analyzer;

        CREATE DATABASE currency;
        GRANT ALL PRIVILEGES ON DATABASE currency TO budget_analyzer;

        CREATE DATABASE permission;
        GRANT ALL PRIVILEGES ON DATABASE permission TO budget_analyzer;

  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

# Disable replication for local development
architecture: standalone

# Service configuration
service:
  type: ClusterIP
  ports:
    postgresql: 5432

# Metrics (disabled for local dev to save resources)
metrics:
  enabled: false
EOF
```

### 3.2. Install PostgreSQL

**Action:** Install the PostgreSQL Helm chart with the custom values.

```bash
helm install postgresql bitnami/postgresql \
  --namespace infrastructure \
  --version 16.4.1 \
  -f kubernetes/infrastructure/values/postgresql-values.yaml
```

### 3.3. Verify PostgreSQL Deployment

**Action:** Wait for the PostgreSQL pod to be ready and verify it's running.

```bash
# Check pod status
kubectl get pods -n infrastructure -l app.kubernetes.io/name=postgresql

# Wait for pod to be ready (may take 1-2 minutes)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=postgresql \
  -n infrastructure \
  --timeout=120s
```

**Expected Output:** One pod should be in `Running` state with `1/1` ready.

### 3.4. Verify Database Initialization

**Action:** Connect to PostgreSQL and verify all databases were created.

```bash
# Get the postgres password
export POSTGRES_PASSWORD=$(kubectl get secret --namespace infrastructure postgresql -o jsonpath="{.data.password}" | base64 -d)

# Port-forward to access PostgreSQL
kubectl port-forward --namespace infrastructure svc/postgresql 5432:5432 &

# Wait a moment for port-forward to establish
sleep 3

# List databases (requires psql client)
PGPASSWORD=$POSTGRES_PASSWORD psql -h 127.0.0.1 -U budget_analyzer -d postgres -c "\l"

# Kill the port-forward
kill %1
```

**Expected Output:** You should see `budget_analyzer`, `currency`, and `permission` databases in the list.

---

## Step 4: Deploy Redis

**Objective:** To deploy Redis using the Bitnami Helm chart with AOF persistence enabled, matching the Docker Compose configuration.

### 4.1. Create Redis Values File

**Action:** Create a Helm values file to configure Redis.

```bash
cat <<EOF > kubernetes/infrastructure/values/redis-values.yaml
# Redis Configuration for Budget Analyzer
# Matches docker-compose.yml settings for parity

# Standalone architecture (no replication for local dev)
architecture: standalone

# Authentication disabled to match docker-compose
auth:
  enabled: false

# Master configuration
master:
  persistence:
    enabled: true
    size: 1Gi

  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 300m

  # Enable AOF persistence (appendonly yes)
  configuration: |
    appendonly yes
    appendfsync everysec

# Service configuration
service:
  type: ClusterIP
  ports:
    redis: 6379

# Disable replica for local development
replica:
  replicaCount: 0

# Metrics (disabled for local dev)
metrics:
  enabled: false
EOF
```

### 4.2. Install Redis

**Action:** Install the Redis Helm chart with the custom values.

```bash
helm install redis bitnami/redis \
  --namespace infrastructure \
  --version 20.6.0 \
  -f kubernetes/infrastructure/values/redis-values.yaml
```

### 4.3. Verify Redis Deployment

**Action:** Wait for the Redis pod to be ready.

```bash
# Check pod status
kubectl get pods -n infrastructure -l app.kubernetes.io/name=redis

# Wait for pod to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=redis \
  -n infrastructure \
  --timeout=120s
```

**Expected Output:** One pod should be in `Running` state with `1/1` ready.

### 4.4. Test Redis Connectivity

**Action:** Verify Redis is accepting connections.

```bash
# Port-forward to Redis
kubectl port-forward --namespace infrastructure svc/redis-master 6379:6379 &

# Wait for port-forward
sleep 3

# Test connection (requires redis-cli)
redis-cli ping

# Kill port-forward
kill %1
```

**Expected Output:** Redis should respond with `PONG`.

---

## Step 5: Deploy RabbitMQ

**Objective:** To deploy RabbitMQ using the Bitnami Helm chart with management UI enabled, matching the Docker Compose configuration.

### 5.1. Create RabbitMQ Values File

**Action:** Create a Helm values file to configure RabbitMQ.

```bash
cat <<EOF > kubernetes/infrastructure/values/rabbitmq-values.yaml
# RabbitMQ Configuration for Budget Analyzer
# Matches docker-compose.yml settings for parity

# Authentication
auth:
  username: guest
  password: guest

# Persistence
persistence:
  enabled: true
  size: 1Gi

# Resource limits for local development
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m

# Service configuration
service:
  type: ClusterIP
  ports:
    amqp: 5672
    manager: 15672

# Enable management plugin
plugins: "rabbitmq_management rabbitmq_peer_discovery_k8s"

# Community plugins (none needed for basic setup)
communityPlugins: ""

# Metrics (disabled for local dev)
metrics:
  enabled: false

# Clustering disabled for local dev
clustering:
  enabled: false

# Replica count
replicaCount: 1
EOF
```

### 5.2. Install RabbitMQ

**Action:** Install the RabbitMQ Helm chart with the custom values.

```bash
helm install rabbitmq bitnami/rabbitmq \
  --namespace infrastructure \
  --version 15.1.2 \
  -f kubernetes/infrastructure/values/rabbitmq-values.yaml
```

### 5.3. Verify RabbitMQ Deployment

**Action:** Wait for the RabbitMQ pod to be ready.

```bash
# Check pod status
kubectl get pods -n infrastructure -l app.kubernetes.io/name=rabbitmq

# Wait for pod to be ready (RabbitMQ takes longer to initialize)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=rabbitmq \
  -n infrastructure \
  --timeout=180s
```

**Expected Output:** One pod should be in `Running` state with `1/1` ready.

### 5.4. Test RabbitMQ Management UI

**Action:** Verify the management UI is accessible.

```bash
# Port-forward to RabbitMQ management UI
kubectl port-forward --namespace infrastructure svc/rabbitmq 15672:15672 &

# Wait for port-forward
sleep 3

# Test management API
curl -u guest:guest http://localhost:15672/api/overview | jq .cluster_name

# Kill port-forward
kill %1
```

**Expected Output:** Should return the cluster name (e.g., `"rabbit@rabbitmq-0.rabbitmq-headless.infrastructure.svc.cluster.local"`).

---

## Step 6: Create Application Secrets

**Objective:** To create Kubernetes Secrets in the default namespace that application services can use to connect to infrastructure. This allows services to reference credentials without hardcoding them.

### 6.1. Create Secrets Manifest

**Action:** Create a manifest file with all infrastructure credentials.

```bash
mkdir -p kubernetes/base/secrets

cat <<EOF > kubernetes/base/secrets/infrastructure-secrets.yaml
# Infrastructure Secrets for Application Services
# These secrets allow services in the default namespace to connect to infrastructure

apiVersion: v1
kind: Secret
metadata:
  name: postgresql-credentials
  namespace: default
  labels:
    app.kubernetes.io/component: infrastructure
type: Opaque
stringData:
  username: budget_analyzer
  password: budget_analyzer
  host: postgresql.infrastructure.svc.cluster.local
  port: "5432"
  # Database URLs for each service
  budget-analyzer-url: "jdbc:postgresql://postgresql.infrastructure.svc.cluster.local:5432/budget_analyzer"
  currency-url: "jdbc:postgresql://postgresql.infrastructure.svc.cluster.local:5432/currency"
  permission-url: "jdbc:postgresql://postgresql.infrastructure.svc.cluster.local:5432/permission"
---
apiVersion: v1
kind: Secret
metadata:
  name: redis-credentials
  namespace: default
  labels:
    app.kubernetes.io/component: infrastructure
type: Opaque
stringData:
  host: redis-master.infrastructure.svc.cluster.local
  port: "6379"
  url: "redis://redis-master.infrastructure.svc.cluster.local:6379"
---
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-credentials
  namespace: default
  labels:
    app.kubernetes.io/component: infrastructure
type: Opaque
stringData:
  username: guest
  password: guest
  host: rabbitmq.infrastructure.svc.cluster.local
  amqp-port: "5672"
  management-port: "15672"
  url: "amqp://guest:guest@rabbitmq.infrastructure.svc.cluster.local:5672"
EOF
```

### 6.2. Apply Secrets

**Action:** Apply the secrets to the cluster.

```bash
kubectl apply -f kubernetes/base/secrets/infrastructure-secrets.yaml
```

### 6.3. Verify Secrets

**Action:** Confirm all secrets were created.

```bash
kubectl get secrets -l app.kubernetes.io/component=infrastructure
```

**Expected Output:** You should see three secrets: `postgresql-credentials`, `redis-credentials`, and `rabbitmq-credentials`.

---

## Step 7: Create Service References (Optional)

**Objective:** To create ExternalName services in the default namespace that point to infrastructure services. This simplifies service discovery for applications that don't want to use the full DNS name.

### 7.1. Create Service References Manifest

**Action:** Create ExternalName services for easier access.

```bash
cat <<EOF > kubernetes/base/secrets/infrastructure-services.yaml
# ExternalName services for simplified access to infrastructure
# Allows services to use short names like "postgres" instead of full DNS

apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: default
spec:
  type: ExternalName
  externalName: postgresql.infrastructure.svc.cluster.local
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: default
spec:
  type: ExternalName
  externalName: redis-master.infrastructure.svc.cluster.local
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: default
spec:
  type: ExternalName
  externalName: rabbitmq.infrastructure.svc.cluster.local
EOF
```

### 7.2. Apply Service References

**Action:** Apply the ExternalName services.

```bash
kubectl apply -f kubernetes/base/secrets/infrastructure-services.yaml
```

### 7.3. Verify Service References

**Action:** Confirm the services were created.

```bash
kubectl get svc postgres redis rabbitmq
```

**Expected Output:** Three services of type `ExternalName` should be listed.

---

## Step 8: Final Verification

**Objective:** To perform a comprehensive check that all infrastructure services are running and accessible.

### 8.1. Check All Pods

**Action:** List all pods in the infrastructure namespace.

```bash
kubectl get pods -n infrastructure
```

**Expected Output:** Three pods (postgresql, redis-master, rabbitmq) should all be in `Running` state.

### 8.2. Check All Services

**Action:** List all services in the infrastructure namespace.

```bash
kubectl get svc -n infrastructure
```

**Expected Output:** Services for postgresql, redis-master, redis-headless, rabbitmq, and rabbitmq-headless should be listed.

### 8.3. Check PersistentVolumeClaims

**Action:** Verify persistent storage was provisioned.

```bash
kubectl get pvc -n infrastructure
```

**Expected Output:** Three PVCs (for postgresql, redis, rabbitmq) should be in `Bound` state.

### 8.4. Summary Check

**Action:** Run a complete status check.

```bash
echo "=== Infrastructure Status ==="
echo ""
echo "Pods:"
kubectl get pods -n infrastructure -o wide
echo ""
echo "Services:"
kubectl get svc -n infrastructure
echo ""
echo "Secrets (in default namespace):"
kubectl get secrets -l app.kubernetes.io/component=infrastructure
echo ""
echo "PVCs:"
kubectl get pvc -n infrastructure
```

---

## Troubleshooting

### PostgreSQL Pod Not Starting

**Symptom:** PostgreSQL pod stuck in `Pending` or `CrashLoopBackOff`.

**Solution:**
```bash
# Check pod events
kubectl describe pod -n infrastructure -l app.kubernetes.io/name=postgresql

# Check logs
kubectl logs -n infrastructure -l app.kubernetes.io/name=postgresql
```

Common causes:
- Insufficient storage: Kind may not have default storage class. Install local-path-provisioner.
- Insufficient resources: Reduce resource requests in values file.

### Redis Connection Refused

**Symptom:** Cannot connect to Redis.

**Solution:**
```bash
# Check Redis pod logs
kubectl logs -n infrastructure -l app.kubernetes.io/name=redis

# Verify service endpoints
kubectl get endpoints -n infrastructure redis-master
```

### RabbitMQ Slow to Start

**Symptom:** RabbitMQ takes a long time to become ready.

**Explanation:** This is normal. RabbitMQ performs extensive initialization. Wait up to 3 minutes.

### Secrets Not Found

**Symptom:** Application cannot find infrastructure secrets.

**Solution:** Ensure secrets are in the correct namespace (default):
```bash
kubectl get secrets -n default | grep credentials
```

---

## Next Steps

After completing Phase 3, you have a fully functional infrastructure layer. Proceed to:

- **Phase 4: Core Services** - Deploy nginx-gateway, session-gateway, token-validation-service, and backend microservices
- These services will use the secrets created in Step 6 to connect to infrastructure

---

## Cleanup

To remove all infrastructure services (for fresh start or troubleshooting):

```bash
# Uninstall Helm releases
helm uninstall postgresql -n infrastructure
helm uninstall redis -n infrastructure
helm uninstall rabbitmq -n infrastructure

# Delete secrets and services
kubectl delete -f kubernetes/base/secrets/

# Delete namespace (removes PVCs)
kubectl delete namespace infrastructure
```

**Note:** Deleting the namespace will also delete all PersistentVolumeClaims and their data.
