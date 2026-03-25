# Tilt-Kind Setup Guide

Complete guide for setting up the Budget Analyzer local development environment using Tilt with Kind (Kubernetes in Docker).

## Host Machine Dependencies

### apt-get Packages

```bash
# Install base packages (excluding Docker if already installed)
sudo apt-get update && sudo apt-get install -y \
  curl \
  wget \
  git \
  build-essential \
  unzip \
  jq \
  libnss3-tools

# Install Docker only if not already present
# This works with both docker.io (Ubuntu) and docker-ce (Docker official)
if ! command -v docker &> /dev/null; then
  sudo apt-get install -y docker.io
  sudo usermod -aG docker $USER
  newgrp docker  # Apply immediately without logout
else
  echo "Docker already installed: $(docker --version)"
fi
```

> **Note**: If you have `docker-ce` (Docker's official packages) installed, that works fine too. The commands above will detect it and skip installation.

### KIND (Kubernetes in Docker)

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### kubectl

```bash
# Download and install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
```

### Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v3.20.1 bash
```

Use Helm `3.20.x` for this repo. Helm 4 is not supported. The repo now uses
Helm for `istio/base`, `istio/cni`, `istio/istiod`, `istio/gateway`, and
`kyverno`. Gateway API CRDs are pinned to `v1.4.0`, ingress gateway hardening
is declared through Gateway `spec.infrastructure.parametersRef`, and the egress
gateway uses checked-in Helm values to keep `service.type=ClusterIP`.

### Tilt

```bash
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
```

### mkcert

```bash
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-*
sudo mv mkcert-* /usr/local/bin/mkcert
```

### Verify Installation

```bash
docker --version        # Expected: Docker 20.10+
kind --version          # Expected: kind v0.20+
kubectl version --client # Expected: v1.28+
helm version            # Expected: v3.20.x
tilt version            # Expected: v0.33+
mkcert --version        # Expected: v1.4+
```

## Service Repositories

Clone all service repositories as **siblings** to the `orchestration` repo. The scripts use relative paths, so they'll work from any location.

```bash
# Go to the parent directory of orchestration
cd "$(dirname /path/to/orchestration)"

# Clone all service repos alongside orchestration
git clone https://github.com/budgetanalyzer/service-common.git
git clone https://github.com/budgetanalyzer/transaction-service.git
git clone https://github.com/budgetanalyzer/currency-service.git
git clone https://github.com/budgetanalyzer/session-gateway.git
git clone https://github.com/budgetanalyzer/budget-analyzer-web.git
git clone https://github.com/budgetanalyzer/permission-service.git
```

Your directory structure should look like:
```
parent-directory/
├── orchestration/
├── service-common/
├── transaction-service/
├── currency-service/
├── session-gateway/
├── permission-service/
└── budget-analyzer-web/
```

## Setup Steps

If you want the supported happy path, run `./setup.sh` from the orchestration root on the host machine. It now deletes any existing `kind` cluster, recreates it from scratch, and installs Helm `v3.20.1` automatically if your current Helm is missing or unsupported. The steps below spell out the same flow manually for debugging and learning.

### 1. Run Pre-flight Check

```bash
cd /path/to/orchestration
./scripts/dev/check-tilt-prerequisites.sh
```

This verifies all dependencies and repositories are properly configured.

### 2. Publish service-common to Maven Local

The backend services depend on `service-common`. Publish it to your local Maven repository:

```bash
cd /path/to/service-common
./gradlew publishToMavenLocal
```

### 3. Create Kind Cluster

**Important**: Use the config file. It now does three critical things:

- Enables HTTPS port mapping
- Pins the Kind node image for reproducibility
- Disables Kind default CNI (`kindnet`) so `NetworkPolicy` can be enforced with Calico

```bash
cd /path/to/orchestration
kind create cluster --config kind-cluster-config.yaml
./scripts/dev/install-calico.sh
```

This creates a cluster with port mappings:
- Port 80 → reserved host mapping
- Port 443 → HTTPS (via NodePort 30443)

Verify the cluster:
```bash
kind get clusters
kubectl cluster-info --context kind-kind

# Verify the Kind node image matches kind-cluster-config.yaml
docker inspect kind-control-plane --format '{{.Config.Image}}'

# Verify port mappings
docker port kind-control-plane
# Expected: 30443/tcp -> 0.0.0.0:443

# Verify default CNI is disabled and Calico is active
kubectl get daemonset kindnet -n kube-system || true   # Expected: NotFound
kubectl get daemonset calico-node -n kube-system
```

### 4. Configure DNS

Add entries to `/etc/hosts`:

```bash
echo '127.0.0.1  app.budgetanalyzer.localhost' | sudo tee -a /etc/hosts
```

### 5. Generate Browser TLS Certificates

```bash
./scripts/dev/setup-k8s-tls.sh
```

This creates:
- Trusted certificates for `*.budgetanalyzer.localhost`
- Kubernetes TLS secret `budgetanalyzer-localhost-wildcard-tls`

### 6. Generate Internal Transport TLS Secrets

`setup.sh` handles this automatically. To regenerate standalone:

```bash
./scripts/dev/setup-infra-tls.sh
```

This creates:
- `infra-ca` in the `default` and `infrastructure` namespaces
- `infra-tls-redis`
- `infra-tls-postgresql`
- `infra-tls-rabbitmq`

### 7. Configure Auth0 Credentials

Create `.env` from `.env.example`, then set the required values before running Tilt.

```bash
[ -f .env ] || cp .env.example .env
vim .env
```

### 8. Start Tilt

```bash
cd /path/to/orchestration
tilt up
```

Access the Tilt UI at http://localhost:10350

### 9. Run Security Verifiers

After core platform resources are up (`istiod`, Kyverno, smoke policy), run:

```bash
./scripts/dev/verify-security-prereqs.sh
./scripts/dev/verify-phase-4-transport-encryption.sh
```

These provide deterministic runtime proof for the Phase 0 platform baseline and
the Phase 4 transport-TLS cutover.

## Verification

### Check Tilt UI

Open http://localhost:10350 - all resources should show green status.

### Check Kubernetes Pods

```bash
# Application services
kubectl get pods -n default

# Expected output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# ext-authz-xxxxx                         1/1     Running   0          2m
# permission-service-xxxxx                1/1     Running   0          2m
# transaction-service-xxxxx               1/1     Running   0          2m
# currency-service-xxxxx                  1/1     Running   0          2m
# session-gateway-xxxxx                   1/1     Running   0          2m
# nginx-gateway-xxxxx                     1/1     Running   0          2m
# budget-analyzer-web-xxxxx               1/1     Running   0          2m

# Infrastructure
kubectl get pods -n infrastructure

# Expected output:
# NAME                      READY   STATUS    RESTARTS   AGE
# postgresql-0              1/1     Running   0          3m
# redis-master-0            1/1     Running   0          3m
# rabbitmq-0                1/1     Running   0          3m
```

### Check Helm Releases

```bash
helm list -n infrastructure

# Expected:
# NAME         NAMESPACE      STATUS    CHART
# postgresql   infrastructure deployed  postgresql-13.x.x
# redis        infrastructure deployed  redis-17.x.x
# rabbitmq     infrastructure deployed  rabbitmq-12.x.x
```

### Test Service Health

```bash
# NGINX Gateway
curl http://localhost:8080/health
# Expected: healthy

# Transaction Service
curl http://localhost:8082/actuator/health
# Expected: {"status":"UP",...}

# Currency Service
curl http://localhost:8084/actuator/health
# Expected: {"status":"UP",...}

# Session Gateway
curl http://localhost:8081/actuator/health
# Expected: {"status":"UP",...}
```

### Access the Application

After all services are healthy:

- **Application**: https://app.budgetanalyzer.localhost
- **API Docs**: https://app.budgetanalyzer.localhost/api/docs
- **Tilt UI**: http://localhost:10350
- **RabbitMQ Management**: http://localhost:15672 (`rabbitmq-admin` / value from `RABBITMQ_BOOTSTRAP_PASSWORD`)

## Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 443 | Istio Ingress Gateway | HTTPS entry point (via NodePort 30443) |
| 80 | Kind host mapping | Reserved host mapping in the Kind config |
| 3000 | budget-analyzer-web | Vite Dev Server |
| 5432 | PostgreSQL | Database |
| 6379 | Redis | TLS-only cache/session storage |
| 5671 | RabbitMQ | AMQPS |
| 15672 | RabbitMQ | Management UI |
| 8080 | nginx-gateway | API Gateway (internal) |
| 8081 | session-gateway | BFF (internal) |
| 8082 | transaction-service | Business Logic |
| 8084 | currency-service | Business Logic |
| 5005 | transaction-service | Debug (JDWP) |
| 5006 | currency-service | Debug (JDWP) |
| 5009 | session-gateway | Debug (JDWP) |

## Troubleshooting

### Pre-flight Check Fails

Run the check script and address each error:
```bash
./scripts/dev/check-tilt-prerequisites.sh
```

### Pods in CrashLoopBackOff

Check pod logs:
```bash
kubectl logs -f deployment/<service-name>
kubectl describe pod <pod-name>
```

Common causes:
- Missing database (run migrations)
- Invalid Auth0 credentials
- Missing environment variables

### Database Connection Refused

1. Check PostgreSQL is running:
   ```bash
   kubectl get pods -n infrastructure | grep postgresql
   ```

2. Verify port forward:
   ```bash
   kubectl port-forward -n infrastructure svc/postgresql 5432:5432
   ```

### Auth0 401 Unauthorized

1. Verify credentials are set:
   ```bash
   kubectl get secret auth0-credentials -o jsonpath='{.data.client-id}' | base64 -d
   ```

2. Check session-gateway logs:
   ```bash
   kubectl logs -f deployment/session-gateway
   ```

### TLS Certificate Errors

Regenerate browser-facing wildcard certificates:
```bash
rm -rf nginx/certs/k8s
./scripts/dev/setup-k8s-tls.sh
```

Regenerate internal transport-TLS material:
```bash
rm -rf nginx/certs/infra
./scripts/dev/setup-infra-tls.sh
```

### Kind Cluster Issues

Delete and recreate with the config file:
```bash
kind delete cluster --name kind
kind create cluster --config kind-cluster-config.yaml
./scripts/dev/install-calico.sh
docker inspect kind-control-plane --format '{{.Config.Image}}'
```

Then restart Tilt:
```bash
tilt down
tilt up
```

### Gradle Build Failures (service-web not found)

If services fail to build with "Could not find org.budgetanalyzer:service-web":
```bash
cd /path/to/service-common
./gradlew publishToMavenLocal
```

Then trigger rebuilds in Tilt:
```bash
tilt trigger transaction-service
tilt trigger currency-service
# ... etc
```

## Cleanup

### Stop Tilt

```bash
# Ctrl+C in Tilt terminal, or:
tilt down
```

### Delete Kind Cluster

```bash
kind delete cluster --name kind
```

### Remove DNS Entries

Edit `/etc/hosts` and remove lines containing `budgetanalyzer.localhost`.

## Quick Reference

### One-liner Setup (after dependencies installed)

```bash
# First, publish service-common (run once)
cd /path/to/service-common && ./gradlew publishToMavenLocal && cd /path/to/orchestration

# Then run the setup (creates cluster, installs Calico, generates all certs, creates .env)
./setup.sh && \
vim .env && \
tilt up
```

### Daily Development

```bash
cd /path/to/orchestration
tilt up
# Work on code - changes auto-reload
# Ctrl+C to stop
```

### Full Reset

```bash
tilt down
kind delete cluster --name kind
./setup.sh    # Recreates cluster, Calico, all certs, .env
tilt up
```
