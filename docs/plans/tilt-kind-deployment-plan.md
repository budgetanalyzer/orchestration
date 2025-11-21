# Tilt + Kind Deployment Plan

## Architecture Overview

```
Kind Cluster
├── Envoy Gateway (Gateway API implementation)
│   ├── TLS termination via cert-manager
│   ├── app.budgetanalyzer.local → session-gateway
│   └── api.budgetanalyzer.local → nginx-gateway
│
├── nginx-gateway (Deployment, HTTP only)
│   ├── auth_request → token-validation-service
│   └── Routes to backend services via K8s DNS
│
├── session-gateway (Deployment)
│   └── Proxies to http://nginx-gateway:8080
│
├── Backend Services
│   ├── transaction-service
│   ├── currency-service
│   └── permission-service
│
└── Infrastructure (Bitnami Helm)
    ├── PostgreSQL
    ├── Redis
    └── RabbitMQ
```

## How This Resolves SSL Divergence

**Current problem**: Dev NGINX handles TLS + routing with mkcert certs, requiring completely different config from production.

**Solution**: Move TLS termination to Envoy Gateway. NGINX becomes HTTP-only and environment-agnostic:
- Same `nginx.conf` works in dev (Kind) and prod (GKE)
- Only difference: upstream service names (ConfigMap/env vars)
- Session Gateway calls `http://nginx-gateway:8080` (no JVM truststore hassle)

---

## Implementation Phases

### Phase 1: Foundation Setup
1. Install Kind cluster with port mappings (80, 443)
2. Install cert-manager + self-signed ClusterIssuer
3. Install Envoy Gateway via Helm
4. Generate wildcard certificate for `*.budgetanalyzer.local`
5. Configure `/etc/hosts` or local DNS for `*.budgetanalyzer.local`

### Phase 2: Gateway API Configuration
1. Create `Gateway` resource with HTTPS listeners
2. Create `HTTPRoute` for `app.budgetanalyzer.local` → session-gateway
3. Create `HTTPRoute` for `api.budgetanalyzer.local` → nginx-gateway
4. Configure Envoy external authorization (ext_authz) for future mTLS path

### Phase 3: Infrastructure Services
1. Deploy PostgreSQL via Bitnami Helm chart
2. Deploy Redis via Bitnami Helm chart
3. Deploy RabbitMQ via Bitnami Helm chart
4. Create Kubernetes Secrets for credentials

### Phase 4: Core Services
1. Create unified `nginx.conf` template (no SSL, K8s service names)
2. Deploy nginx-gateway with ConfigMap
3. Deploy token-validation-service
4. Deploy session-gateway (update URI to `http://nginx-gateway:8080`)
5. Deploy backend services (transaction, currency, permission)

### Phase 5: Tiltfile Configuration
1. Create `Tiltfile` with live reload for all services
2. Configure `local_resource` for Helm chart dependencies
3. Set up port-forwards for debugging
4. Configure React dev server with HMR

### Phase 6: Production Parity Documentation
1. Document GKE deployment differences (managed certs, Cloud SQL, etc.)
2. Create CI/CD pipeline templates
3. Document mTLS upgrade path for production

---

## Key Files to Create

```
kubernetes/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── secrets/
├── gateway/
│   ├── gateway.yaml
│   ├── httproutes.yaml
│   └── certificate.yaml
├── services/
│   ├── nginx-gateway/
│   ├── session-gateway/
│   ├── token-validation-service/
│   ├── transaction-service/
│   ├── currency-service/
│   └── permission-service/
├── infrastructure/
│   └── values/ (Helm value overrides)
└── overlays/
    ├── kind/
    └── gke/
Tiltfile
nginx/nginx.k8s.conf  (unified config, no SSL)
```

---

## Benefits of This Approach

1. **Single NGINX config** - Works in both Kind and GKE
2. **Future-proof** - Gateway API is the Kubernetes standard
3. **Production parity** - Same traffic flow as GCP architecture
4. **Simplified SSL** - cert-manager handles all certificate lifecycle
5. **Clear upgrade path** - ext_authz ready for mTLS when needed
6. **Fast iteration** - Tilt provides live reload for all services
