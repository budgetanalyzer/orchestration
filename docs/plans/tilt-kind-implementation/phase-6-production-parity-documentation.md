# Phase 6: Production Parity Documentation

This document provides comprehensive documentation for deploying Budget Analyzer to Google Kubernetes Engine (GKE), covering the differences from local Kind development, CI/CD pipeline templates, and the mTLS upgrade path for production.

**Related Documents:**
- [deployment-architecture-gcp.md](../../architecture/deployment-architecture-gcp.md) - Detailed GKE architecture decisions
- [deployment-architecture-gcp-demo-mode.md](../../architecture/deployment-architecture-gcp-demo-mode.md) - Cost-optimized demo deployment
- [authentication-implementation-plan.md](../authentication-implementation-plan.md) - OAuth2 + BFF implementation

---

## Step 1: GKE Deployment Differences

**Objective:** Document the key differences between local Kind development and GKE production deployment.

### 1.1 Infrastructure Component Mapping

**Reference Table:** Use this table to understand how each local component maps to GKE.

| Component | Local Kind | GKE Production | Lock-In Level |
|-----------|-----------|----------------|---------------|
| **TLS Certificates** | cert-manager + self-signed ClusterIssuer | Google-managed certificates (Let's Encrypt) | Minimal |
| **Gateway** | Envoy Gateway | GKE Gateway API (gke-l7-global-external-managed) | Moderate |
| **Load Balancer** | Kind port mapping (localhost:80, 443) | GCP L7 Global External Load Balancer | Moderate |
| **DNS** | /etc/hosts entries | Cloud DNS (budgetanalyzer.com) | Minimal |
| **PostgreSQL** | Bitnami Helm chart (StatefulSet) | Cloud SQL (HA, automated backups) | Minimal |
| **Redis** | Bitnami Helm chart | Memorystore Redis (HA, automatic failover) | Minimal |
| **RabbitMQ** | Bitnami Helm chart (3-node StatefulSet) | Self-managed StatefulSet on GKE | None |
| **Secrets** | Kubernetes Secrets (in-cluster) | Google Secret Manager (audit logging) | Moderate |
| **Container Registry** | Local Docker images (imagePullPolicy: Never) | Google Artifact Registry | Moderate |
| **Frontend** | Vite dev server proxied through NGINX | Cloud Run (NGINX serving static build) | Moderate |
| **Monitoring** | None configured | Cloud Monitoring + Prometheus/Grafana | Minimal |

### 1.2 Gateway API Configuration for GKE

**Objective:** Configure the GKE-managed Gateway API implementation.

**Action:** The Gateway resource changes from Envoy Gateway to GKE Gateway Controller.

**Local Kind Gateway (for reference):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: budgetanalyzer-gateway
  namespace: default
spec:
  gatewayClassName: eg  # Envoy Gateway
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - name: budgetanalyzer-local-wildcard-tls
```

**GKE Production Gateway:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: budgetanalyzer-gateway
  namespace: default
  annotations:
    networking.gke.io/certmap: budgetanalyzer-certmap
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
  - name: https-app
    protocol: HTTPS
    port: 443
    hostname: app.budgetanalyzer.com
  - name: https-api
    protocol: HTTPS
    port: 443
    hostname: api.budgetanalyzer.com
  addresses:
  - type: NamedAddress
    value: budgetanalyzer-static-ip
```

**Differences:**
- `gatewayClassName`: `gke-l7-global-external-managed` instead of `eg`
- TLS managed via Certificate Manager certificate map (annotation)
- Static IP address for DNS configuration
- Hostname-based listeners instead of wildcard certificate

### 1.3 Cloud SQL Configuration

**Objective:** Configure Cloud SQL PostgreSQL to replace the local Bitnami Helm chart.

**Action:** Update Spring Boot services to connect via Cloud SQL Auth Proxy.

**Step 1: Create Cloud SQL Instance**
```bash
# Create Cloud SQL instance with private IP
gcloud sql instances create budgetanalyzer-db \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=us-central1 \
  --network=default \
  --no-assign-ip \
  --storage-type=SSD \
  --storage-size=10GB \
  --backup-start-time=02:00 \
  --availability-type=REGIONAL

# Create databases
gcloud sql databases create transaction_service --instance=budgetanalyzer-db
gcloud sql databases create currency_service --instance=budgetanalyzer-db
gcloud sql databases create permission_service --instance=budgetanalyzer-db
```

**Step 2: Deploy Cloud SQL Auth Proxy as Sidecar**
```yaml
# Example deployment with Cloud SQL Auth Proxy sidecar
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transaction-service
spec:
  template:
    spec:
      serviceAccountName: transaction-service-sa
      containers:
      - name: transaction-service
        image: gcr.io/PROJECT_ID/transaction-service:TAG
        env:
        - name: SPRING_DATASOURCE_URL
          value: jdbc:postgresql://127.0.0.1:5432/transaction_service
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: cloudsql-credentials
              key: username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: cloudsql-credentials
              key: password
      - name: cloud-sql-proxy
        image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0
        args:
        - --structured-logs
        - --auto-iam-authn
        - PROJECT_ID:REGION:budgetanalyzer-db
        securityContext:
          runAsNonRoot: true
```

**Key Differences from Local:**
- No direct database host - connect via 127.0.0.1 (proxy sidecar)
- Authentication via Workload Identity (recommended) or credentials secret
- Automatic SSL/TLS encryption to Cloud SQL
- Connection pooling handled by Cloud SQL

### 1.4 Memorystore Redis Configuration

**Objective:** Configure Memorystore Redis to replace the local Bitnami Helm chart.

**Action:** Update Session Gateway and Currency Service to connect to Memorystore.

**Step 1: Create Memorystore Instance**
```bash
# Create Memorystore Redis with HA
gcloud redis instances create budgetanalyzer-redis \
  --size=1 \
  --region=us-central1 \
  --redis-version=redis_7_0 \
  --tier=STANDARD_HA \
  --network=default

# Get the host and port
gcloud redis instances describe budgetanalyzer-redis --region=us-central1 \
  --format="value(host,port)"
```

**Step 2: Update Service Configuration**
```yaml
# Session Gateway application-prod.yml
spring:
  data:
    redis:
      host: ${REDIS_HOST}  # Memorystore private IP
      port: 6379
      ssl:
        enabled: false  # Private network, SSL not needed
  session:
    store-type: redis
    redis:
      namespace: spring:session
```

**Key Differences from Local:**
- No password by default (use AUTH if required)
- Private IP only (not accessible from internet)
- Automatic failover to replica
- No cluster mode needed for 1GB instance

### 1.5 Secret Manager Integration

**Objective:** Migrate from Kubernetes Secrets to Google Secret Manager for audit logging.

**Action:** Configure Workload Identity and mount secrets from Secret Manager.

**Step 1: Create Secrets in Secret Manager**
```bash
# Create secrets
echo -n "your-db-password" | gcloud secrets create db-password --data-file=-
echo -n "your-auth0-client-secret" | gcloud secrets create auth0-client-secret --data-file=-
echo -n "your-fred-api-key" | gcloud secrets create fred-api-key --data-file=-

# Grant access to service account
gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:transaction-service-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Step 2: Use External Secrets Operator or Direct Mount**

**Option A: External Secrets Operator (Recommended)**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: transaction-service-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: gcp-secret-store
    kind: ClusterSecretStore
  target:
    name: transaction-service-secrets
  data:
  - secretKey: db-password
    remoteRef:
      key: db-password
```

**Option B: CSI Driver (GKE Native)**
```yaml
apiVersion: v1
kind: Pod
spec:
  volumes:
  - name: secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: gcp-secrets
```

### 1.6 Frontend Deployment on Cloud Run

**Objective:** Deploy React frontend to Cloud Run instead of Vite dev server.

**Action:** Build production assets and deploy as NGINX container.

**Step 1: Create Dockerfile for Production**
```dockerfile
# Dockerfile.prod (in budget-analyzer-web repository)
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

**Step 2: NGINX Configuration for React Router**
```nginx
# nginx.conf
server {
    listen 8080;
    root /usr/share/nginx/html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
}
```

**Step 3: Deploy to Cloud Run**
```bash
# Build and push image
gcloud builds submit --tag gcr.io/PROJECT_ID/budget-analyzer-web

# Deploy to Cloud Run
gcloud run deploy budget-analyzer-web \
  --image gcr.io/PROJECT_ID/budget-analyzer-web \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 10
```

### 1.7 Network Architecture Differences

**Local Kind:**
```
Browser → localhost:443 → Kind Node → Envoy Gateway → Services
```

**GKE Production:**
```
Browser → Cloud Armor → GCP Load Balancer → GKE Gateway → Services
                                        ↘ Cloud Run (frontend)
```

**Key Networking Changes:**
- VPC-native cluster (Pod IPs routable in VPC)
- Private Google Access for managed services
- Cloud Armor for DDoS protection and WAF
- All managed services (Cloud SQL, Memorystore) on private IPs

---

## Step 2: CI/CD Pipeline Templates

**Objective:** Provide ready-to-use GitHub Actions workflows for building, testing, and deploying to GKE.

### 2.1 Workload Identity Federation Setup

**Objective:** Configure keyless authentication from GitHub Actions to GCP.

**Action:** Set up Workload Identity Federation (no long-lived service account keys).

**Step 1: Create Workload Identity Pool**
```bash
# Create workload identity pool
gcloud iam workload-identity-pools create github-actions \
  --location=global \
  --display-name="GitHub Actions Pool"

# Create provider for GitHub
gcloud iam workload-identity-pools providers create-oidc github \
  --location=global \
  --workload-identity-pool=github-actions \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant access to service account
gcloud iam service-accounts add-iam-policy-binding \
  ci-cd-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/attribute.repository/YOUR_ORG/YOUR_REPO"
```

**Required GitHub Secrets:**
```
GCP_PROJECT_ID: your-gcp-project-id
GCP_WORKLOAD_IDENTITY_PROVIDER: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github
GCP_SERVICE_ACCOUNT: ci-cd-sa@PROJECT_ID.iam.gserviceaccount.com
GKE_CLUSTER: budgetanalyzer-cluster
GKE_ZONE: us-central1-a
```

### 2.2 Build and Test Pipeline Template

**Action:** Create `.github/workflows/ci.yml` for pull request validation.

```yaml
name: CI - Build and Test

on:
  pull_request:
    branches: [main]

jobs:
  test-backend:
    name: Test Backend Services
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [transaction-service, currency-service, permission-service, session-gateway, token-validation-service]
    steps:
    - uses: actions/checkout@v4

    - name: Set up JDK 21
      uses: actions/setup-java@v4
      with:
        java-version: '21'
        distribution: 'temurin'
        cache: gradle

    - name: Run tests
      working-directory: ../${{ matrix.service }}
      run: ./gradlew test

    - name: Upload test results
      uses: actions/upload-artifact@v4
      if: always()
      with:
        name: test-results-${{ matrix.service }}
        path: ../${{ matrix.service }}/build/reports/tests/

  test-frontend:
    name: Test Frontend
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
      with:
        repository: budgetanalyzer/budget-analyzer-web

    - name: Set up Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '20'
        cache: 'npm'

    - name: Install dependencies
      run: npm ci

    - name: Run lint
      run: npm run lint

    - name: Run tests
      run: npm run test

  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Run Trivy vulnerability scanner
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: '.'
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy scan results
      uses: github/codeql-action/upload-sarif@v3
      with:
        sarif_file: 'trivy-results.sarif'
```

### 2.3 Image Build Pipeline Template

**Action:** Create `.github/workflows/build-images.yml` for building and pushing Docker images.

```yaml
name: Build and Push Images

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  REGION: us-central1
  REGISTRY: ${{ secrets.GCP_PROJECT_ID }}

jobs:
  build-backend:
    name: Build Backend Services
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    strategy:
      matrix:
        service: [transaction-service, currency-service, permission-service, session-gateway, token-validation-service]
    steps:
    - uses: actions/checkout@v4
      with:
        repository: budgetanalyzer/${{ matrix.service }}

    - name: Set up JDK 21
      uses: actions/setup-java@v4
      with:
        java-version: '21'
        distribution: 'temurin'
        cache: gradle

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
        service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2

    - name: Configure Docker for Artifact Registry
      run: gcloud auth configure-docker ${{ env.REGION }}-docker.pkg.dev

    - name: Build and push with Jib
      run: |
        ./gradlew jib \
          -Djib.to.image=${{ env.REGION }}-docker.pkg.dev/${{ env.REGISTRY }}/budgetanalyzer/${{ matrix.service }}:${{ github.sha }} \
          -Djib.to.tags=latest,${{ github.sha }}

  build-frontend:
    name: Build Frontend
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
    - uses: actions/checkout@v4
      with:
        repository: budgetanalyzer/budget-analyzer-web

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
        service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2

    - name: Build and push image
      run: |
        gcloud builds submit \
          --tag ${{ env.REGION }}-docker.pkg.dev/${{ env.REGISTRY }}/budgetanalyzer/budget-analyzer-web:${{ github.sha }}

  build-nginx:
    name: Build NGINX Gateway
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
    - uses: actions/checkout@v4

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
        service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2

    - name: Build and push image
      run: |
        gcloud builds submit \
          --tag ${{ env.REGION }}-docker.pkg.dev/${{ env.REGISTRY }}/budgetanalyzer/nginx-gateway:${{ github.sha }} \
          ./nginx
```

### 2.4 Deployment Pipeline Template

**Action:** Create `.github/workflows/deploy.yml` for deploying to GKE.

```yaml
name: Deploy to GKE

on:
  workflow_run:
    workflows: ["Build and Push Images"]
    types: [completed]
    branches: [main]
  workflow_dispatch:
    inputs:
      image_tag:
        description: 'Image tag to deploy'
        required: true
        default: 'latest'

env:
  REGION: us-central1

jobs:
  deploy:
    name: Deploy to GKE
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch' }}
    permissions:
      contents: read
      id-token: write
    steps:
    - uses: actions/checkout@v4

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
        service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

    - name: Set up Cloud SDK
      uses: google-github-actions/setup-gcloud@v2

    - name: Get GKE credentials
      uses: google-github-actions/get-gke-credentials@v2
      with:
        cluster_name: ${{ secrets.GKE_CLUSTER }}
        location: ${{ secrets.GKE_ZONE }}

    - name: Set image tag
      id: set-tag
      run: |
        if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
          echo "tag=${{ github.event.inputs.image_tag }}" >> $GITHUB_OUTPUT
        else
          echo "tag=${{ github.sha }}" >> $GITHUB_OUTPUT
        fi

    - name: Deploy with Kustomize
      run: |
        cd kubernetes/overlays/production
        kustomize edit set image \
          transaction-service=${{ env.REGION }}-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/budgetanalyzer/transaction-service:${{ steps.set-tag.outputs.tag }} \
          currency-service=${{ env.REGION }}-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/budgetanalyzer/currency-service:${{ steps.set-tag.outputs.tag }} \
          session-gateway=${{ env.REGION }}-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/budgetanalyzer/session-gateway:${{ steps.set-tag.outputs.tag }}
        kubectl apply -k .

    - name: Wait for rollout
      run: |
        kubectl rollout status deployment/transaction-service --timeout=300s
        kubectl rollout status deployment/currency-service --timeout=300s
        kubectl rollout status deployment/session-gateway --timeout=300s

    - name: Verify deployment
      run: |
        kubectl get pods -l app.kubernetes.io/part-of=budgetanalyzer
        kubectl get services

  deploy-frontend:
    name: Deploy Frontend to Cloud Run
    runs-on: ubuntu-latest
    if: ${{ github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch' }}
    permissions:
      contents: read
      id-token: write
    steps:
    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
        service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

    - name: Deploy to Cloud Run
      uses: google-github-actions/deploy-cloudrun@v2
      with:
        service: budget-analyzer-web
        region: us-central1
        image: ${{ env.REGION }}-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/budgetanalyzer/budget-analyzer-web:${{ github.sha }}
```

### 2.5 Environment Configuration with Kustomize

**Action:** Create Kustomize overlays for different environments.

**Directory Structure:**
```
kubernetes/
├── base/
│   ├── kustomization.yaml
│   ├── transaction-service/
│   ├── currency-service/
│   └── session-gateway/
└── overlays/
    ├── development/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── production/
        └── kustomization.yaml
```

**Production Overlay Example:**
```yaml
# kubernetes/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

resources:
- ../../base

patches:
- patch: |-
    - op: replace
      path: /spec/replicas
      value: 3
  target:
    kind: Deployment
    name: ".*"

configMapGenerator:
- name: app-config
  behavior: merge
  literals:
  - SPRING_PROFILES_ACTIVE=production
  - LOG_LEVEL=INFO

images:
- name: transaction-service
  newName: us-central1-docker.pkg.dev/PROJECT_ID/budgetanalyzer/transaction-service
- name: currency-service
  newName: us-central1-docker.pkg.dev/PROJECT_ID/budgetanalyzer/currency-service
- name: session-gateway
  newName: us-central1-docker.pkg.dev/PROJECT_ID/budgetanalyzer/session-gateway
```

---

## Step 3: mTLS Upgrade Path for Production

**Objective:** Document the migration path from HTTP-only internal traffic to mTLS encryption.

### 3.1 Current State Documentation

**Current Architecture (Kind Development):**
- All internal service-to-service traffic is HTTP (unencrypted)
- Security relies on:
  - Network isolation (Kubernetes namespace)
  - Gateway API with JWT validation (external traffic)
  - Service-level authorization (backend services)

**Traffic Flow:**
```
External: Browser → Gateway (HTTPS) → Services (HTTP)
Internal: Service A → Service B (HTTP)
```

**Acceptable For:**
- Local development
- Private GKE clusters with VPC isolation
- Internal traffic only (no sensitive data in transit)

### 3.2 Migration Triggers

**When to Implement mTLS:**

| Trigger | Description | Priority |
|---------|-------------|----------|
| **5+ microservices** | Complexity justifies service mesh | HIGH |
| **Compliance requirements** | PCI-DSS, SOC 2, HIPAA mandate encryption | CRITICAL |
| **Multi-tenant cluster** | Shared cluster with other applications | HIGH |
| **Zero-trust architecture** | Organization security policy | MEDIUM |
| **Certificate rotation burden** | Manual TLS certs becoming unmanageable | MEDIUM |

**Budget Analyzer Recommendation:**
- **Current (2-3 services):** HTTP acceptable with VPC isolation
- **Future (5+ services):** Implement Linkerd service mesh

### 3.3 Option A: Manual mTLS Implementation

**Use Case:** Quick implementation for < 5 services before adopting service mesh.

**Step 1: Generate Certificates**
```bash
# Install certstrap
brew install certstrap  # macOS
# or: go install github.com/square/certstrap@latest

# Create Certificate Authority
certstrap init --common-name "BudgetAnalyzer CA" --expires "10 years"

# Generate service certificates
certstrap request-cert --common-name transaction-service --domain transaction-service.default.svc.cluster.local
certstrap sign transaction-service --CA "BudgetAnalyzer CA"

certstrap request-cert --common-name currency-service --domain currency-service.default.svc.cluster.local
certstrap sign currency-service --CA "BudgetAnalyzer CA"
```

**Step 2: Create Kubernetes Secrets**
```bash
# Create TLS secrets from generated certs
kubectl create secret tls transaction-service-tls \
  --cert=out/transaction-service.crt \
  --key=out/transaction-service.key

kubectl create secret generic ca-bundle \
  --from-file=ca.crt=out/BudgetAnalyzer_CA.crt
```

**Step 3: Configure Spring Boot for mTLS**
```yaml
# application-mtls.yml
server:
  ssl:
    enabled: true
    key-store: /etc/tls/keystore.p12
    key-store-password: ${KEYSTORE_PASSWORD}
    key-store-type: PKCS12
    client-auth: need
    trust-store: /etc/tls/truststore.p12
    trust-store-password: ${TRUSTSTORE_PASSWORD}

# RestClient configuration for outbound calls
spring:
  ssl:
    bundle:
      jks:
        client:
          keystore:
            location: /etc/tls/keystore.p12
            password: ${KEYSTORE_PASSWORD}
          truststore:
            location: /etc/tls/truststore.p12
            password: ${TRUSTSTORE_PASSWORD}
```

**Step 4: Configure NGINX Gateway for mTLS**
```nginx
# Upstream with mTLS
upstream transaction_service {
    server transaction-service:8082;
}

server {
    location /api/v1/transactions {
        proxy_pass https://transaction_service;
        proxy_ssl_certificate /etc/nginx/certs/nginx-gateway.crt;
        proxy_ssl_certificate_key /etc/nginx/certs/nginx-gateway.key;
        proxy_ssl_trusted_certificate /etc/nginx/certs/ca.crt;
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 2;
    }
}
```

**Rotation Schedule:**
- Quarterly certificate rotation (90-day lifetime)
- Document rotation runbook (see Step 5.3)

### 3.4 Option B: Linkerd Service Mesh (Recommended)

**Use Case:** Production deployment with 5+ services, automatic mTLS.

**Benefits:**
- **Automatic mTLS:** Zero configuration for encryption
- **24-hour certificates:** Automatic rotation
- **No code changes:** Transparent proxy injection
- **Observability:** Built-in metrics, tracing
- **FREE:** Open source, CNCF project

**Step 1: Install Linkerd**
```bash
# Install CLI
curl -fsL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Validate cluster
linkerd check --pre

# Install CRDs and control plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Verify installation
linkerd check
```

**Step 2: Inject Linkerd Proxy into Services**
```bash
# Inject into namespace (all deployments)
kubectl get deploy -n default -o yaml | linkerd inject - | kubectl apply -f -

# Or inject specific deployment
kubectl get deploy transaction-service -o yaml | linkerd inject - | kubectl apply -f -
```

**Step 3: Verify mTLS**
```bash
# Check mTLS status
linkerd viz edges deployment

# View encrypted traffic
linkerd viz tap deploy/transaction-service
```

**Step 4: Enable Strict Mode (Optional)**
```yaml
# Require mTLS for all traffic to service
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: transaction-service
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: transaction-service
  port: 8082
  proxyProtocol: TLS
```

**Migration from Manual mTLS to Linkerd:**
1. Install Linkerd control plane
2. Inject proxies into one service at a time
3. Verify mTLS established with `linkerd viz edges`
4. Remove manual certificate configuration
5. Delete manual TLS secrets

### 3.5 Defense-in-Depth Security Model

**Two-Layer Security Architecture:**

```
┌─────────────────────────────────────────────────┐
│            Transport Layer (mTLS)                │
│  • Cryptographic service identity verification   │
│  • Encrypted all traffic (TLS 1.3)              │
│  • Prevents network eavesdropping               │
│  • Automatic certificate rotation               │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│           Application Layer (OAuth2)             │
│  • Authorizes specific actions (scopes)          │
│  • User context propagation                      │
│  • Fine-grained access control                   │
│  • Audit logging of operations                   │
└─────────────────────────────────────────────────┘
```

**Why Both Layers:**
- **mTLS alone:** Verifies service identity but not action authorization
- **OAuth2 alone:** Authorizes actions but traffic could be intercepted
- **Together:** Maximum security - verified identity + authorized action + encrypted transport

---

## Step 4: Deployment Mode Documentation

**Objective:** Document the two deployment modes and when to use each.

### 4.1 Demo Mode (~$35-45/month)

**Use Case:** Intermittent demonstration, development testing, portfolios.

**Configuration:**
| Component | Demo Mode Specification |
|-----------|------------------------|
| GKE | Autopilot (pay per pod) |
| Cloud SQL | Shared CPU, no HA |
| Memorystore | Basic tier, smallest |
| Load Balancer | Standard tier |
| Nodes | Scale to zero when idle |

**Cost Breakdown:**
- GKE Autopilot: $0 (cluster) + ~$20-30 (pods when running)
- Cloud SQL: ~$10/month (db-f1-micro, no HA)
- Memorystore: ~$5-10/month (1GB basic)
- Load Balancer: $18/month
- **Total:** ~$35-45/month

**Limitations:**
- Cold start latency (scale from zero)
- No high availability
- Not suitable for production traffic

**Documentation:** See [deployment-architecture-gcp-demo-mode.md](../../architecture/deployment-architecture-gcp-demo-mode.md)

### 4.2 Production Mode (~$420-440/month)

**Use Case:** 24/7 availability, real users, production traffic.

**Configuration:**
| Component | Production Specification |
|-----------|-------------------------|
| GKE | Standard cluster, 2+ nodes |
| Cloud SQL | Standard tier, regional HA |
| Memorystore | Standard tier, automatic failover |
| Load Balancer | Global external, Cloud Armor |
| Replicas | 2+ per service |

**Cost Breakdown:**
- GKE Standard: $72 (cluster) + $60 (nodes)
- Cloud SQL: $126/month (Standard HA)
- Memorystore: $126/month (Standard HA)
- Load Balancer: $18/month
- Secret Manager: $2/month
- Bandwidth: $10-20/month
- **Total:** ~$420-440/month

**Benefits:**
- High availability across zones
- Automatic failover
- Production SLAs
- Cloud Armor DDoS protection

**Documentation:** See [deployment-architecture-gcp.md](../../architecture/deployment-architecture-gcp.md)

### 4.3 Decision Guide

**Choose Demo Mode When:**
- Building portfolio/demonstration
- Development/testing environment
- Intermittent usage (few hours/week)
- Budget constraints are primary concern

**Choose Production Mode When:**
- Serving real users
- Financial data (compliance requirements)
- 24/7 availability required
- Need HA and automatic failover

---

## Step 5: Operational Runbooks

**Objective:** Provide operational procedures for common tasks.

### 5.1 Monitoring and Alerting Setup

**Cloud Monitoring Dashboards:**

**Action:** Create monitoring dashboard for Budget Analyzer.

```bash
# Create dashboard from JSON definition
gcloud monitoring dashboards create --config-from-file=monitoring/dashboard.json
```

**Key Metrics to Monitor:**

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| HTTP Error Rate | GKE Gateway | > 1% for 5 minutes |
| Request Latency (P99) | GKE Gateway | > 2 seconds |
| Pod Restarts | GKE | > 3 in 5 minutes |
| Database Connections | Cloud SQL | > 80% max |
| Redis Memory | Memorystore | > 80% |
| RabbitMQ Queue Depth | RabbitMQ | > 1000 messages |

**Alert Policy Example:**
```yaml
# monitoring/alerts/error-rate.yaml
displayName: High Error Rate
conditions:
- displayName: HTTP 5xx Error Rate
  conditionThreshold:
    filter: metric.type="loadbalancing.googleapis.com/https/request_count" AND metric.labels.response_code_class="500"
    aggregations:
    - alignmentPeriod: 300s
      perSeriesAligner: ALIGN_RATE
    comparison: COMPARISON_GT
    thresholdValue: 0.01
    duration: 300s
notificationChannels:
- projects/PROJECT_ID/notificationChannels/CHANNEL_ID
```

### 5.2 Backup and Recovery Procedures

**Cloud SQL Automated Backups:**

**Configuration:**
- Daily automated backups at 02:00 UTC
- 7-day retention
- Point-in-time recovery enabled

**Manual Backup:**
```bash
# Create on-demand backup
gcloud sql backups create --instance=budgetanalyzer-db

# List backups
gcloud sql backups list --instance=budgetanalyzer-db
```

**Restore from Backup:**
```bash
# Restore to new instance (recommended)
gcloud sql instances clone budgetanalyzer-db budgetanalyzer-db-restored \
  --point-in-time "2025-01-15T10:00:00.000Z"

# Restore to same instance (destructive)
gcloud sql backups restore BACKUP_ID \
  --restore-instance=budgetanalyzer-db
```

**Export for Migration:**
```bash
# Export database to Cloud Storage
gcloud sql export sql budgetanalyzer-db gs://BUCKET_NAME/backup.sql \
  --database=transaction_service

# Import to new database
gcloud sql import sql NEW_INSTANCE gs://BUCKET_NAME/backup.sql \
  --database=transaction_service
```

### 5.3 Certificate Rotation Runbook (Manual mTLS)

**Quarterly Rotation Procedure:**

**Step 1: Generate New Certificates**
```bash
# Generate new certs (30 days before expiration)
certstrap request-cert --common-name transaction-service-new
certstrap sign transaction-service-new --CA "BudgetAnalyzer CA"
```

**Step 2: Create New Secrets**
```bash
# Create new secret (don't delete old yet)
kubectl create secret tls transaction-service-tls-new \
  --cert=out/transaction-service-new.crt \
  --key=out/transaction-service-new.key
```

**Step 3: Update Deployment**
```bash
# Update deployment to use new secret
kubectl patch deployment transaction-service -p '
{
  "spec": {
    "template": {
      "spec": {
        "volumes": [{
          "name": "tls",
          "secret": {
            "secretName": "transaction-service-tls-new"
          }
        }]
      }
    }
  }
}'
```

**Step 4: Verify and Cleanup**
```bash
# Verify new cert is being used
kubectl exec -it deploy/transaction-service -- \
  openssl s_client -connect localhost:8082 < /dev/null 2>&1 | grep "subject"

# Delete old secret after verification
kubectl delete secret transaction-service-tls
```

### 5.4 Scaling Procedures

**Horizontal Pod Autoscaler:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: transaction-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: transaction-service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

**Manual Scaling:**
```bash
# Scale deployment
kubectl scale deployment transaction-service --replicas=5

# Scale node pool
gcloud container clusters resize budgetanalyzer-cluster \
  --node-pool default-pool \
  --num-nodes 4
```

### 5.5 Rollback Procedures

**Kubernetes Deployment Rollback:**
```bash
# View rollout history
kubectl rollout history deployment/transaction-service

# Rollback to previous version
kubectl rollout undo deployment/transaction-service

# Rollback to specific revision
kubectl rollout undo deployment/transaction-service --to-revision=2

# Check rollback status
kubectl rollout status deployment/transaction-service
```

**Cloud Run Rollback:**
```bash
# List revisions
gcloud run revisions list --service=budget-analyzer-web

# Route traffic to previous revision
gcloud run services update-traffic budget-analyzer-web \
  --to-revisions=budget-analyzer-web-00002=100
```

---

## Acceptance Criteria

**Phase 6 Documentation Complete When:**

- [ ] GKE deployment differences documented with configuration examples
- [ ] CI/CD pipeline templates ready to copy/adapt with placeholder markers
- [ ] mTLS upgrade path documented with clear decision criteria
- [ ] Demo vs Production mode documented with cost breakdowns
- [ ] Operational runbooks for backup, scaling, rollback, and certificate rotation
- [ ] Cross-references to existing detailed documentation verified
- [ ] All YAML examples validated for syntax correctness

---

## Next Steps After Phase 6

1. **Implement Authentication** (Critical prerequisite for production)
   - Session Gateway must be built before public deployment
   - See [authentication-implementation-plan.md](../authentication-implementation-plan.md)

2. **Test CI/CD Pipelines**
   - Set up GitHub repository secrets
   - Run pipeline on staging environment first

3. **Deploy to GKE (Private Network)**
   - Validate infrastructure before adding authentication
   - Use mock data only until Session Gateway is deployed

4. **Security Audit**
   - Penetration testing before public access
   - Review Cloud Armor rules

---

**End of Phase 6 Documentation**
