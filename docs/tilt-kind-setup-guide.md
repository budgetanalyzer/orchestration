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
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

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
helm version            # Expected: v3.13+
tilt version            # Expected: v0.33+
mkcert --version        # Expected: v1.4+
```

## Service Repositories

Clone all service repositories as **siblings** to the `orchestration` repo. The scripts use relative paths, so they'll work from any location.

```bash
# Go to the parent directory of orchestration
cd "$(dirname /path/to/orchestration)"

# Clone all service repos alongside orchestration
git clone https://github.com/budgetanalyzer/transaction-service.git
git clone https://github.com/budgetanalyzer/currency-service.git
git clone https://github.com/budgetanalyzer/permission-service.git
git clone https://github.com/budgetanalyzer/session-gateway.git
git clone https://github.com/budgetanalyzer/token-validation-service.git
git clone https://github.com/budgetanalyzer/budget-analyzer-web.git
```

Your directory structure should look like:
```
parent-directory/
├── orchestration/
├── transaction-service/
├── currency-service/
├── permission-service/
├── session-gateway/
├── token-validation-service/
└── budget-analyzer-web/
```

## Setup Steps

### 1. Run Pre-flight Check

```bash
cd /path/to/orchestration
./scripts/dev/check-tilt-prerequisites.sh
```

This verifies all dependencies and repositories are properly configured.

### 2. Create Kind Cluster

```bash
kind create cluster --name kind
```

Verify the cluster:
```bash
kind get clusters
kubectl cluster-info --context kind-kind
```

### 3. Configure DNS

Add entries to `/etc/hosts`:

```bash
echo '127.0.0.1  app.budgetanalyzer.localhost api.budgetanalyzer.localhost' | sudo tee -a /etc/hosts
```

### 4. Generate TLS Certificates

```bash
./scripts/dev/setup-k8s-tls.sh
```

This creates:
- Trusted certificates for `*.budgetanalyzer.localhost`
- Kubernetes TLS secret `budgetanalyzer-local-wildcard-tls`

### 5. Configure Auth0 Credentials

Set environment variables before running Tilt:

```bash
export AUTH0_CLIENT_ID="your-actual-client-id"
export AUTH0_CLIENT_SECRET="your-actual-client-secret"
export AUTH0_ISSUER_URI="https://your-tenant.auth0.com/"
```

### 6. Start Tilt

```bash
cd /path/to/orchestration
tilt up
```

Access the Tilt UI at http://localhost:10350

## Verification

### Check Tilt UI

Open http://localhost:10350 - all resources should show green status.

### Check Kubernetes Pods

```bash
# Application services
kubectl get pods -n default

# Expected output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# transaction-service-xxxxx               1/1     Running   0          2m
# currency-service-xxxxx                  1/1     Running   0          2m
# permission-service-xxxxx                1/1     Running   0          2m
# session-gateway-xxxxx                   1/1     Running   0          2m
# token-validation-service-xxxxx          1/1     Running   0          2m
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

# Permission Service
curl http://localhost:8086/actuator/health
# Expected: {"status":"UP",...}

# Token Validation Service
curl http://localhost:8088/actuator/health
# Expected: {"status":"UP",...}

# Session Gateway
curl http://localhost:8081/actuator/health
# Expected: {"status":"UP",...}
```

### Run Database Migrations

Migrations must be triggered manually after infrastructure is up:

```bash
tilt trigger run-all-migrations
```

### Access the Application

After all services are healthy:

- **Application**: https://app.budgetanalyzer.localhost
- **API Gateway**: https://api.budgetanalyzer.localhost
- **Tilt UI**: http://localhost:10350
- **RabbitMQ Management**: http://localhost:15672 (user/password)

## Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 3000 | budget-analyzer-web | Vite Dev Server |
| 5432 | PostgreSQL | Database |
| 6379 | Redis | Cache |
| 5672 | RabbitMQ | AMQP |
| 15672 | RabbitMQ | Management UI |
| 8080 | nginx-gateway | API Gateway |
| 8081 | session-gateway | BFF |
| 8082 | transaction-service | Business Logic |
| 8084 | currency-service | Business Logic |
| 8086 | permission-service | Business Logic |
| 8088 | token-validation-service | JWT Validation |
| 5005 | transaction-service | Debug (JDWP) |
| 5006 | currency-service | Debug (JDWP) |
| 5007 | permission-service | Debug (JDWP) |
| 5008 | token-validation-service | Debug (JDWP) |
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

Regenerate certificates:
```bash
rm -rf nginx/certs/k8s
./scripts/dev/setup-k8s-tls.sh
```

### Kind Cluster Issues

Delete and recreate:
```bash
kind delete cluster --name kind
kind create cluster --name kind
```

Then restart Tilt:
```bash
tilt down
tilt up
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
kind create cluster --name kind && \
echo '127.0.0.1  app.budgetanalyzer.localhost api.budgetanalyzer.localhost' | sudo tee -a /etc/hosts && \
./scripts/dev/setup-k8s-tls.sh && \
export AUTH0_CLIENT_ID="your-id" AUTH0_CLIENT_SECRET="your-secret" && \
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
kind create cluster --name kind
./scripts/dev/setup-k8s-tls.sh
tilt up
```
