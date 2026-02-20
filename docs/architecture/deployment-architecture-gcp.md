# Deployment Architecture - Google Cloud Platform (GCP)

**Status:** Draft
**Last Updated:** 2025-11-16
**Target Environment:** Google Cloud Platform (GCP)
**Primary Goal:** Minimize vendor lock-in while leveraging managed services for operational efficiency

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Component Decisions](#component-decisions)
4. [Vendor Lock-In Analysis](#vendor-lock-in-analysis)
5. [Cost Estimates](#cost-estimates)
6. [Critical Risks & Challenges](#critical-risks--challenges)
7. [Deployment Best Practices (2025)](#deployment-best-practices-2025)
8. [Phased Deployment Roadmap](#phased-deployment-roadmap)
9. [Migration Guide: NGINX to Gateway API](#migration-guide-nginx-to-gateway-api)
10. [Operational Runbooks](#operational-runbooks)

---

## Executive Summary

This document defines the deployment architecture for Budget Analyzer on Google Cloud Platform (GCP), prioritizing **minimal vendor lock-in** while leveraging managed services where operational burden outweighs portability risks.

### Key Principles

1. **Portability First:** Choose vendor-neutral technologies when operational complexity is manageable
2. **Managed Services for Undifferentiated Heavy Lifting:** Use GCP managed services for databases, caching, secrets where expertise is scarce
3. **Production Parity:** Match local development patterns in production
4. **Cost-Conscious:** Optimize for small team budget (~$420-440/month estimated)
5. **Security-Focused:** Financial application requires audit logging, encryption, HA

### Recommended Stack Summary

| Component | Choice | Lock-In Level | Monthly Cost |
|-----------|--------|---------------|--------------|
| Container Orchestration | GKE Standard | ✅ None | $72 + compute |
| Database | Cloud SQL PostgreSQL | ⚠️ Minimal | $126 |
| Session Storage | Memorystore Redis | ⚠️ Minimal | $126 |
| Message Queue | RabbitMQ on GKE | ✅ None | Included |
| Ingress/Load Balancing | Gateway API + GCP LB | ⚠️ Moderate | $18 |
| Frontend Hosting | Cloud Run (NGINX) | ⚠️ Moderate | $5-10 |
| Secrets Management | Secret Manager | ⚠️ Moderate | $2 |
| CI/CD | GitHub Actions | ✅ None | Free tier |
| Monitoring | Hybrid (Cloud + Prometheus) | ⚠️ Minimal | Free tier |
| Service Mesh | Linkerd (future) | ✅ None | Deferred |

**Total Estimated Cost:** ~$420-440/month (baseline, scales with traffic)

### Critical Blockers

🚨 **CRITICAL: Cannot deploy to production without Session Gateway implementation**
- Authentication layer not yet built
- Estimated 8 weeks to implement full OAuth2 + BFF pattern
- Must deploy to private network only until authentication is ready

📅 **HIGH: NGINX Ingress Controller retiring March 2026**
- Must migrate to Gateway API before retirement
- Plan migration as part of initial deployment

---

## Architecture Overview

### Current State (Local Development)

```
┌─────────────────────────────────────────────────────────────┐
│                        Local Development                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Browser → NGINX (8080) → Backend Services                   │
│              │                                                │
│              ├─→ transaction-service (8082)                   │
│              └─→ currency-service (8084)                      │
│                                                               │
│  Infrastructure:                                              │
│  ├─ PostgreSQL (per-service schemas)                          │
│  ├─ Redis (currency caching)                                  │
│  └─ RabbitMQ (Spring Modulith events)                         │
└─────────────────────────────────────────────────────────────┘
```

### Target State (GCP Deployment with Authentication)

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Production (GCP)                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Internet                                                             │
│      │                                                                │
│      ↓                                                                │
│  [Cloud Armor]─→ GCP Load Balancer                                   │
│                      │                                                │
│                      ├──→ Gateway API (HTTPS/TLS)                    │
│                      │        │                                       │
│                      │        ├─→ budget-analyzer-web (Cloud Run)    │
│                      │        │                                       │
│                      │        └─→ Session Gateway (GKE, port 8081)   │
│                      │                    │                           │
│                      │                    ↓                           │
│                      │            [HTTP-only Cookie]                  │
│                      │            [JWT in Redis]                      │
│                      │                    │                           │
│                      │                    ↓                           │
│                      └──→ NGINX Gateway (GKE, port 8080)             │
│                                  │                                    │
│                                  ├──→ [Token Validation Service]      │
│                                  │                                    │
│                                  ├─→ transaction-service (GKE)        │
│                                  └─→ currency-service (GKE)           │
│                                                                       │
│  Managed Services:                                                    │
│  ├─ Cloud SQL (PostgreSQL) ─── per-service schemas                   │
│  ├─ Memorystore (Redis) ────── sessions + currency cache             │
│  └─ RabbitMQ (StatefulSet) ─── Spring Modulith events                │
│                                                                       │
│  Observability:                                                       │
│  ├─ Cloud Monitoring (infrastructure)                                 │
│  └─ Prometheus + Grafana (application metrics)                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Service Topology

Based on [docker-compose.yml](../../docker-compose.yml):

**Frontend:**
- `budget-analyzer-web`: React 19 + TypeScript SPA

**Backend Microservices:**
- `transaction-service`: Spring Boot - transactions, budgets, CSV import (port 8082)
- `currency-service`: Spring Boot - exchange rates, FRED API integration (port 8084)
- `session-gateway`: Spring Cloud Gateway - OAuth2/session management (port 8081, **not yet implemented**)

**Infrastructure:**
- PostgreSQL: Per-service schemas (transaction_service, currency_service)
- Redis: Currency caching + session storage
- RabbitMQ: Async messaging via Spring Modulith transactional outbox

**Gateway Layer:**
- NGINX Gateway: Resource-based routing (`/api/v1/transactions` → transaction-service)
- Token Validation Service: JWT validation for NGINX (port 8088, **not yet implemented**)

---

## Component Decisions

### 1. Container Orchestration

#### Decision: **Google Kubernetes Engine (GKE) Standard**

**Rationale:**
- **Zero vendor lock-in** - Standard Kubernetes works on any cloud (AWS EKS, Azure AKS, on-prem)
- Financial application needs full control over security configuration
- Team has Docker/container experience (current Docker Compose setup)
- Cost optimization possible with spot instances, custom node pools
- Medium complexity justifies operational investment

**Alternatives Considered:**

##### GKE Autopilot (NOT Recommended)
**Pros:**
- Fully managed - Google handles nodes, upgrades, scaling
- Control plane fee included in pod pricing
- Minimal operational overhead

**Cons:**
- 🔒 **Significant vendor lock-in** - GCP-specific pod resource model
- Applications optimized for Autopilot don't transfer to other clouds
- Can be 60-191% more expensive than Standard for some workloads
- Less control over node configuration

**Cost Comparison:**
- Standard: $72/month cluster + VM costs (e2-medium ~$30/node)
- Autopilot: No cluster fee but higher per-pod costs

##### Cloud Run (NOT Recommended for Backend Services)
**Pros:**
- Serverless, scale to zero
- Pay per request
- Extreme simplicity

**Cons:**
- 🔒 **Extreme vendor lock-in** - Cloud Run specific platform
- Stateful Session Gateway complex (requires external session storage anyway)
- Limited control over networking, service mesh
- Migration requires architectural changes

**Verdict:** **GKE Standard** provides best balance of portability and control for financial application.

---

### 2. Database Hosting

#### Decision: **Cloud SQL for PostgreSQL (Managed)**

**Rationale:**
- ⚠️ **Minimal vendor lock-in** - Standard PostgreSQL, easy to export with `pg_dump`
- Small team should focus on application features, not database operations
- Automated backups, patching, HA, failover included
- Financial application needs reliable backups and disaster recovery
- Cost premium (~30-50%) justified by reduced operational burden

**Configuration:**
- **Tier:** Standard (HA with automatic failover)
- **Version:** PostgreSQL 15 or latest stable
- **Size:** Start with 5GB, auto-scale storage
- **Backups:** Automated daily backups, 7-day retention, point-in-time recovery
- **Networking:** Private IP only (VPC peering with GKE)

**Migration Path:**
- Regular exports via `pg_dump` to Google Cloud Storage
- Test restore procedures monthly
- Document egress costs for potential migration (charged per GB)

**Alternative Considered:**

##### Self-Managed PostgreSQL on GKE (StatefulSet)
**Pros:**
- ✅ **Zero vendor lock-in** - Pure open source
- Lower direct compute costs
- Full control over configuration, extensions, versions

**Cons:**
- **High operational overhead** - You manage backups, patching, HA, monitoring
- Requires PostgreSQL expertise
- Disaster recovery is your responsibility
- StatefulSet complexity (persistent volumes, clustering)

**Cost Comparison:**
- Cloud SQL: ~$126/month (5GB Standard tier)
- Self-managed: ~$60/month (compute) + ops time

**Verdict:** **Cloud SQL** - Operational reliability more valuable than cost savings for financial data.

---

### 3. Redis Hosting (Session Storage + Caching)

#### Decision: **Memorystore for Redis (Managed)**

**Rationale:**
- ⚠️ **Minimal vendor lock-in** - Standard Redis protocol (easy to migrate)
- Session Gateway requires HA for production (cannot lose user sessions)
- Standard tier provides automatic failover
- Small dataset (sessions + currency cache) = low cost
- Financial application cannot afford session loss

**Configuration:**
- **Tier:** Standard (HA with automatic failover)
- **Version:** Redis 7.x
- **Size:** 5GB (start small, can scale)
- **Networking:** Private IP only (VPC peering with GKE)

**Use Cases:**
1. **Session storage** (Session Gateway): User sessions, JWT tokens
2. **Currency caching** (currency-service): Exchange rate API responses

**Alternative Considered:**

##### Self-Managed Redis on GKE (StatefulSet)
**Pros:**
- ✅ **Zero vendor lock-in** - Open source Redis
- Lower direct costs (share GKE resources)
- Full control over configuration

**Cons:**
- Operational overhead - manage replication, failover, backups
- Session Gateway requires HA (Redis Cluster setup)
- Need Redis expertise for clustering

**Cost Comparison:**
- Memorystore: ~$126/month (5GB Standard tier)
- Self-managed: Included in GKE node costs + ops time

**Verdict:** **Memorystore** - Automatic failover critical for session management.

---

### 4. Message Queue

#### Decision: **RabbitMQ on GKE (Self-Managed StatefulSet)**

**Rationale:**
- ✅ **Zero vendor lock-in** - Open source RabbitMQ, portable
- Already integrated with Spring Modulith (transactional outbox pattern)
- Same technology as local dev (production parity)
- Current usage is low volume (scheduled currency imports)
- AMQP protocol support required by Spring AMQP

**Configuration:**
- **Deployment:** StatefulSet with 3-node cluster
- **Version:** RabbitMQ 3.12+
- **Persistence:** Persistent volumes for message durability
- **Networking:** ClusterIP service (internal only)
- **Management UI:** Port-forward for debugging (not publicly exposed)

**Current Usage:**
- Spring Modulith transactional outbox → RabbitMQ
- Currency import events (low volume, scheduled)
- Future: User notification events, budget alerts

**Alternative Considered:**

##### Cloud Pub/Sub (Managed)
**Pros:**
- Fully managed, scales to millions of messages/sec
- Native GCP integration
- Pay per message (no idle costs)
- SLA guarantees

**Cons:**
- 🔒 **Significant vendor lock-in** - GCP-specific API and patterns
- **Different semantics** than RabbitMQ (push vs pull, no routing keys)
- **Would require refactoring Spring Modulith event system**
- No AMQP protocol support (Spring AMQP incompatible)

**Migration Path:** If RabbitMQ operations become burdensome, consider Pub/Sub migration when:
- Message volume exceeds 1M+/day
- Need global distribution
- Operational cost of RabbitMQ > Pub/Sub fees

**Verdict:** **RabbitMQ on GKE** - Portability and existing integration outweigh operational overhead.

---

### 5. Ingress / Load Balancing

#### Decision: **Gateway API + GCP Load Balancer**

**Rationale:**
- 🚨 **CRITICAL:** NGINX Ingress Controller retiring (no updates after March 2026)
- Gateway API is Kubernetes standard (better portability than GCP-specific solutions)
- Must migrate from current NGINX config anyway
- Native GCP features valuable: Cloud Armor (DDoS), automatic SSL certs, global LB

**Configuration:**
- **Gateway Class:** GKE-managed Gateway (uses GCP Load Balancer)
- **Protocol:** HTTPS with automatic Let's Encrypt certificates
- **Routes:** HTTPRoutes for resource-based routing (replaces NGINX location blocks)
- **Security:** Cloud Armor policies for rate limiting, DDoS protection

**Migration Required:** Current NGINX config → Gateway API HTTPRoutes (see [Migration Guide](#migration-guide-nginx-to-gateway-api))

**Alternatives Considered:**

##### NGINX Ingress Controller (NOT Recommended)
**Pros:**
- Same configuration as current local dev
- Team already familiar with NGINX config

**Cons:**
- 🚨 **CRITICAL DEPRECATION:** No updates after March 2026 (security risk)
- Must migrate anyway before retirement
- No security patches after March 2026

##### Identity-Aware Proxy (IAP) (NOT Recommended)
**Pros:**
- Fully managed authentication
- Zero-trust security model

**Cons:**
- 🔒 **Extreme vendor lock-in** - GCP-only solution
- **Cannot replicate Session Gateway BFF pattern**
- Different auth model than planned OAuth2 architecture
- Would require complete security redesign

**Verdict:** **Gateway API** - Kubernetes standard + must migrate from NGINX anyway.

**Cost:** ~$18/month for L7 load balancer + forwarding rules

---

### 6. React Frontend Hosting

#### Decision: **Cloud Run (NGINX Container)**

**Rationale:**
- ⚠️ **Moderate vendor lock-in** (Cloud Run specific, but static files portable)
- Same pattern as local dev (NGINX serving React SPA)
- No SEO issues (proper NGINX `try_files` for React Router)
- Can include security headers, CSP policies in NGINX config
- Very low cost for static serving (scales to zero)
- Easy rollback (container versions)

**Configuration:**
- **Container:** Multi-stage Docker (Node build → NGINX serve)
- **NGINX Config:** Handle React Router (`try_files $uri /index.html`)
- **Security Headers:** X-Frame-Options, X-Content-Type-Options, CSP
- **Port:** 8080 (standard Cloud Run)
- **Scaling:** Min 0, max 10 instances

**Alternatives Considered:**

##### Cloud Storage + Cloud CDN (NOT Recommended)
**Pros:**
- Very low cost (pennies for storage)
- Global CDN included

**Cons:**
- **SEO issues:** React Router requires 404 → index.html workaround (returns 404 status)
- Less control over security headers
- HTTPS requires Load Balancer anyway (~$18/month)

##### Firebase Hosting (NOT Recommended)
**Pros:**
- Dead simple deployment
- Handles React Router correctly
- Free tier available

**Cons:**
- ⚠️ **Moderate vendor lock-in** - Firebase/Google specific
- Less control than custom NGINX

**Verdict:** **Cloud Run (NGINX)** - Production parity with local dev + proper routing.

**Cost:** ~$5-10/month (minimal for static serving, pay per request)

---

### 7. Secrets Management

#### Decision: **Google Secret Manager**

**Rationale:**
- ⚠️ **Moderate vendor lock-in** (GCP-specific API, but secrets are portable)
- Financial application needs **audit logging** for compliance
- Versioning and rotation support built-in
- Native GKE integration (mount as volumes or env vars)
- Small number of secrets = low cost (~$1-2/month)

**Configuration:**
- **Secrets Stored:**
  - Database connection strings (Cloud SQL)
  - Redis password (Memorystore)
  - Auth0 client secrets (Session Gateway)
  - FRED API key (currency-service)
  - GitHub tokens (CI/CD)
- **Access:** IAM-based, service account per microservice
- **Rotation:** Manual for now, automate when using Vault

**Alternative Considered:**

##### Kubernetes Secrets (with etcd encryption)
**Pros:**
- ✅ **Zero vendor lock-in** - Standard Kubernetes
- No per-access costs
- Works anywhere Kubernetes runs

**Cons:**
- No built-in audit logging (need sidecar)
- Rotation requires manual process
- Secrets stored in cluster (not external vault)

**Migration Path:** Can migrate to HashiCorp Vault later if compliance requires (Secret Manager is minimal lock-in)

**Verdict:** **Secret Manager** - Audit logging critical for financial application.

**Cost:** ~$0.06 per secret version/month + $0.03 per 10K access operations = ~$2/month

---

### 8. CI/CD Pipeline

#### Decision: **GitHub Actions**

**Rationale:**
- ✅ **Zero vendor lock-in** - Works with any cloud (AWS, Azure, on-prem)
- Team already uses GitHub for source control
- Huge marketplace of actions (Docker build, Kubernetes deploy, etc.)
- Free tier: 2,000 minutes/month for private repos
- Same pipeline can deploy to multiple clouds without rewriting

**Configuration:**
- **Workflows:**
  - Build & test on PR (Spring Boot tests, React lint/test)
  - Build Docker images on merge to main (Jib for Spring Boot, multi-stage for React)
  - Push images to Google Artifact Registry
  - Deploy to GKE (kubectl apply -f kubernetes/)
- **Authentication:** Workload Identity Federation (no long-lived keys)
- **Secrets:** GitHub Secrets for GCP credentials

**Alternative Considered:**

##### Cloud Build + Artifact Registry
**Pros:**
- Native integration with GKE, Secret Manager, IAM
- Fast builds (regional build agents)
- Automatic Docker image scanning
- Free tier: 120 build-minutes/day

**Cons:**
- ⚠️ **Moderate vendor lock-in** - `cloudbuild.yaml` is GCP-specific
- Pipeline changes required to migrate to other clouds
- Less flexible than GitHub Actions

**Verdict:** **GitHub Actions** - Cloud-agnostic, same pipeline for multi-cloud.

**Cost:** Free tier sufficient (2,000 minutes/month)

---

### 9. Monitoring and Observability

#### Decision: **Hybrid Approach (Cloud Monitoring + Prometheus + Grafana)**

**Rationale:**
- Balance convenience (GCP native) and portability (open source)
- Infrastructure monitoring via Cloud Monitoring (GKE, Cloud SQL, network)
- Application metrics via Prometheus (Spring Boot, custom business metrics)
- Can migrate fully to self-hosted later if needed

**Configuration:**

**Cloud Monitoring (Infrastructure):**
- GKE cluster metrics (CPU, memory, disk)
- Cloud SQL metrics (connections, queries, replication lag)
- Memorystore metrics (memory usage, evictions)
- Load Balancer metrics (requests, latency, errors)
- **Cost:** Free tier then pay per GB ingested

**Prometheus + Grafana (Application Metrics):**
- Deploy Prometheus in GKE (scrape `/actuator/prometheus` from Spring Boot)
- Deploy Grafana in GKE (dashboards for business metrics)
- Custom metrics: transaction count, budget alerts, currency import failures
- Portable to any environment
- **Cost:** GKE compute + storage (minimal)

**Spring Boot Configuration:**
```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
```

**Alternative Considered:**

##### Cloud Monitoring Only
**Pros:**
- Single pane of glass
- No management overhead

**Cons:**
- 🔒 **Significant vendor lock-in** - Dashboards, alerts are GCP-specific
- Limited visualization compared to Grafana

##### Prometheus + Grafana + Loki Only
**Pros:**
- ✅ **Zero vendor lock-in** - Fully portable
- Rich ecosystem

**Cons:**
- Must manage all components (Prometheus, Grafana, Loki, exporters)
- Higher operational overhead

**Verdict:** **Hybrid** - Use Cloud Monitoring for convenience, Prometheus for portability.

**Cost:** Free tier + minimal GKE resources (~$5/month)

---

### 10. Service Mesh (Future Consideration)

#### Decision: **Linkerd (Defer until 5+ services)**

**Rationale:**
- ✅ **Zero vendor lock-in** - CNCF open source project
- FREE - No licensing costs (unlike Istio commercial offerings)
- Lightweight (minimal performance overhead)
- Automatic mTLS between services
- 24-hour certificate rotation
- **Not needed yet:** Only 2 backend services currently

**When to Implement:**
- 5+ microservices (complexity justifies mesh)
- Need service-to-service authentication (mTLS)
- Need advanced traffic management (canary deployments, circuit breakers)
- Documented in [authentication-implementation-plan.md](authentication-implementation-plan.md) as future migration

**Alternative Considered:**

##### Anthos Service Mesh (Istio-based)
**Pros:**
- Fully managed by Google
- Native GCP integration

**Cons:**
- 🔒 **Moderate vendor lock-in** - GCP-managed control plane
- Higher cost
- More complex than Linkerd

**Verdict:** **Linkerd (future)** - Defer until service count justifies, then use open source.

---

## Vendor Lock-In Analysis

### Lock-In Levels

| Level | Description | Migration Effort | Examples |
|-------|-------------|------------------|----------|
| ✅ **None** | Standard open source, works anywhere | Low (hours) | GKE Standard, RabbitMQ, GitHub Actions |
| ⚠️ **Minimal** | Standard protocol/API, easy export | Low-Medium (days) | Cloud SQL (PostgreSQL), Memorystore (Redis) |
| ⚠️ **Moderate** | Some GCP-specific features, portable with work | Medium (weeks) | Gateway API, Secret Manager, Cloud Run |
| 🔒 **Significant** | GCP-specific APIs, requires refactoring | High (months) | Pub/Sub, Cloud Build |
| 🔒 **Extreme** | Platform-specific, architectural changes needed | Very High (redesign) | IAP, Firebase Functions |

### Summary by Component

| Component | Lock-In Level | Mitigation Strategy |
|-----------|---------------|---------------------|
| GKE Standard | ✅ None | Standard Kubernetes manifests work on any K8s |
| Cloud SQL | ⚠️ Minimal | Regular pg_dump exports, document restore |
| Memorystore | ⚠️ Minimal | Standard Redis protocol, backup via RDB |
| RabbitMQ | ✅ None | Self-managed, portable StatefulSet |
| Gateway API | ⚠️ Moderate | K8s standard, but GCP implementation specifics |
| Cloud Run | ⚠️ Moderate | Static files portable, re-containerize for K8s |
| Secret Manager | ⚠️ Moderate | Export secrets, migrate to Vault if needed |
| GitHub Actions | ✅ None | Cloud-agnostic workflows |
| Prometheus/Grafana | ✅ None | Open source, portable |
| Linkerd | ✅ None | CNCF project, works on any K8s |

### Migration Cost Estimates (if leaving GCP)

**Low Effort (< 1 week):**
- GKE → EKS/AKS: Change kubectl context, update image registry
- RabbitMQ: Re-deploy StatefulSet to new cluster
- GitHub Actions: Update cloud provider credentials

**Medium Effort (1-2 weeks):**
- Cloud SQL → RDS/self-hosted: pg_dump export, restore, update connection strings
- Memorystore → ElastiCache/self-hosted: RDB backup, restore, update config
- Secret Manager → AWS Secrets Manager/Vault: Export secrets, update manifests

**Higher Effort (2-4 weeks):**
- Gateway API → AWS ALB/Azure App Gateway: Rewrite HTTPRoutes for new provider
- Cloud Run → EKS/AKS: Deploy frontend to Kubernetes instead

**Total Migration Estimate:** 4-6 weeks for full cloud migration (primarily testing and validation)

---

## Cost Estimates

### Monthly Baseline (USD)

**Fixed Infrastructure:**
| Service | Configuration | Monthly Cost |
|---------|---------------|--------------|
| GKE Standard Cluster | Control plane fee | $72 |
| Cloud SQL PostgreSQL | 5GB Standard tier (HA) | $126 |
| Memorystore Redis | 5GB Standard tier (HA) | $126 |
| GCP Load Balancer | L7 HTTPS load balancer | $18 |
| Secret Manager | ~10 secrets, low access | $2 |
| **Subtotal** | | **$344** |

**Variable Compute:**
| Service | Configuration | Monthly Cost |
|---------|---------------|--------------|
| GKE Nodes | 2x e2-medium (2 vCPU, 4GB each) | $60 |
| Cloud Run (frontend) | Static serving, low traffic | $5-10 |
| RabbitMQ | Included in GKE nodes | $0 |
| Bandwidth | Egress to internet | $10-20 |
| **Subtotal** | | **$75-90** |

**Total Baseline:** ~$420-440/month

### Scaling Scenarios

**Low Traffic (MVP, < 100 users):**
- 2 GKE nodes (e2-medium)
- Minimal bandwidth
- **Cost:** ~$420/month

**Medium Traffic (1,000 users):**
- 3-4 GKE nodes (e2-standard-2)
- Increased bandwidth
- Larger Cloud SQL instance (10GB)
- **Cost:** ~$650-750/month

**High Traffic (10,000 users):**
- 8-10 GKE nodes (e2-standard-4)
- Multi-region deployment
- Larger database/cache instances
- Cloud CDN enabled
- **Cost:** ~$1,500-2,000/month

### Cost Optimization Strategies

1. **Committed Use Discounts:** 1-year commitment = 25% discount, 3-year = 40% discount
2. **Spot Instances:** Use for non-critical workloads (currency import jobs)
3. **Autoscaling:** Scale down during off-hours (GKE node autoscaling)
4. **Cloud CDN:** Cache static frontend assets (reduce bandwidth costs)
5. **Regional Deployment:** Single region initially (avoid cross-region costs)

### Hidden Costs to Watch

- **Egress Bandwidth:** Data leaving GCP (charged per GB)
- **Load Balancer Forwarding Rules:** Per rule charges
- **Cloud SQL Backups:** Storage costs for automated backups
- **Persistent Volumes:** GKE persistent disks (for RabbitMQ, Prometheus)
- **Log Ingestion:** Cloud Logging beyond free tier (10GB/month)

---

## Critical Risks & Challenges

### 1. 🚨 CRITICAL: Deploying Before Session Gateway Exists

**Risk Level:** CRITICAL - **Cannot deploy to production**

**Problem:**
- Session Gateway (BFF pattern) not yet implemented
- No authentication or authorization layer exists
- All API endpoints are publicly accessible without JWT validation
- Financial data (transactions, budgets) completely unprotected

**Architecture Gap:**

Current state (local dev):
```
Browser → NGINX Gateway → Backend Services (no auth)
```

Required for production:
```
Browser → Session Gateway → NGINX Gateway → Backend Services
         [Session Cookie]  [JWT Header]
```

**Components Not Yet Built:**
1. Session Gateway (Spring Cloud Gateway with OAuth2)
2. Token Validation Service (port 8088)
3. Auth0 tenant configuration
4. NGINX JWT validation via auth_request
5. Backend OAuth2 Resource Server configuration
6. Redis session storage integration

**Impact:**
- **Cannot deploy with real user data**
- **Cannot allow public internet access**
- Suitable only for internal testing with mock data
- Estimated 8 weeks to implement full authentication (see [authentication-implementation-plan.md](authentication-implementation-plan.md))

**Mitigation Options:**

**Option A: Phased Deployment (Recommended)**

**Phase 1 (Immediate):** Deploy to GCP with **private network only**
- VPC with no public internet gateway
- Access via Cloud VPN or Identity-Aware Proxy for developers
- Load only test/mock data (no real financial information)
- Purpose: Validate infrastructure, test deployment procedures
- **Critical:** No public access whatsoever

**Phase 2 (8 weeks):** Implement authentication architecture
1. Week 1-2: Session Gateway + Token Validation Service
2. Week 3-4: Auth0 integration + NGINX JWT validation
3. Week 5-6: Backend OAuth2 Resource Server configuration
4. Week 7-8: Testing, security audit, penetration testing

**Phase 3 (Production):** Public deployment
- Enable public internet access
- Real user data
- Production monitoring and alerting
- Incident response procedures

**Option B: Delay GCP Deployment**
- Wait until Session Gateway is implemented
- Continue local development only
- Deploy entire stack at once when auth is ready
- **Pros:** Lower risk, no premature cloud costs
- **Cons:** Delays learning GCP, no infrastructure validation

**Recommendation:** **Phased Deployment** - Deploy to private network now to validate infrastructure, implement auth in parallel.

**Acceptance Criteria for Production:**
- [ ] Session Gateway deployed and tested
- [ ] Token Validation Service operational
- [ ] Auth0 tenant configured with production settings
- [ ] NGINX Gateway validating JWTs via auth_request
- [ ] All backend services configured as OAuth2 Resource Servers
- [ ] Redis cluster for session storage with HA
- [ ] End-to-end authentication flow tested
- [ ] Security audit completed
- [ ] Penetration testing passed

---

### 2. 📅 HIGH: NGINX Ingress Controller Retirement

**Risk Level:** HIGH - Security/maintenance risk

**Problem:**
- NGINX Ingress Controller stops receiving updates **March 2026**
- Current local dev architecture uses NGINX heavily (resource-based routing)
- No security patches, bug fixes, or Kubernetes compatibility updates after retirement
- Current NGINX config in [nginx/nginx.dev.conf](../../nginx/nginx.dev.conf) cannot be directly used in production

**Impact:**
- Must migrate to Gateway API before March 2026
- All NGINX routing configuration must be rewritten as HTTPRoutes
- Team must learn new Kubernetes Gateway API concepts
- Migration required regardless of cloud provider choice

**Timeline:**
- **Today → Phase 1 Deployment:** Continue using NGINX Gateway in GKE (short-term acceptable)
- **Before Production (Phase 3):** Complete migration to Gateway API
- **Hard Deadline:** March 2026 (no updates after)

**Mitigation Strategy:**

1. **Plan Gateway API migration as part of initial deployment**
2. **Run both in parallel during transition** (NGINX + Gateway API)
3. **Complete migration before production launch** (Phase 3)
4. **Test extensively** (see [Migration Guide](#migration-guide-nginx-to-gateway-api))

**Resource-Based Routing Pattern Migration:**

Current NGINX pattern:
```nginx
location /api/v1/transactions {
    rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
    proxy_pass http://transaction_service;
}
```

Gateway API equivalent:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: transaction-route
spec:
  parentRefs:
  - name: api-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1/transactions
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /transaction-service/v1/transactions
    backendRefs:
    - name: transaction-service
      port: 8082
```

**Benefits of Migration:**
- Gateway API is Kubernetes standard (less vendor-specific than Ingress)
- Better support for advanced routing (header-based, weighted routing)
- Native integration with GCP features (Cloud Armor, SSL certs)
- Future-proof (actively developed by Kubernetes community)

---

### 3. ⚠️ MEDIUM: Session Affinity for Session Gateway

**Risk Level:** MEDIUM - User experience impact

**Problem:**
- Session Gateway will run with multiple replicas (HA requirement)
- If session stored in-memory only, user could lose session when routed to different instance
- GCP Ingress/Gateway API has limited session affinity support (cookie-based affinity not guaranteed)

**Impact:**
- Users might experience "logged out" behavior if routed to different Session Gateway instance
- Session cookies become invalid mid-session

**Mitigation Strategy:**

**1. Use Redis for ALL session storage (not in-memory)**
```yaml
# application.yml (Session Gateway)
spring:
  session:
    store-type: redis
    redis:
      namespace: spring:session
  data:
    redis:
      host: MEMORYSTORE_IP
      port: 6379
```

**2. Configure all Session Gateway instances to share same Redis cluster**
- All instances read/write from Memorystore (single source of truth)
- No in-memory session caching

**3. Test with multiple replicas**
```yaml
# kubernetes/session-gateway-deployment.yaml
spec:
  replicas: 2  # Test with multiple instances
```

**4. Monitor session distribution**
- Track which Session Gateway instance handles each request
- Verify session persistence across instances
- Alert on session store failures

**Result:** User session persists regardless of which Session Gateway instance handles request.

---

### 4. ⚠️ MEDIUM: RabbitMQ Clustering on Kubernetes

**Risk Level:** MEDIUM - Operational complexity

**Problem:**
- RabbitMQ clustering on Kubernetes requires StatefulSets with persistent storage
- Spring Modulith transactional outbox depends on RabbitMQ availability
- Broker failover must be handled gracefully
- Need quorum for cluster decisions (3-node minimum recommended)

**Current Usage:**
- Spring Modulith event publication → RabbitMQ exchanges
- Currency import completion events
- Future: Budget alert notifications, transaction events

**Impact:**
- Event delivery could fail during RabbitMQ downtime
- Messages could be lost if persistence not configured
- Need robust retry and dead-letter handling

**Mitigation Strategy:**

**1. Deploy RabbitMQ with 3-node cluster (StatefulSet)**
```yaml
# kubernetes/rabbitmq-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rabbitmq
spec:
  replicas: 3
  serviceName: rabbitmq-headless
  template:
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.12-management-alpine
        env:
        - name: RABBITMQ_DEFAULT_USER
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: username
        - name: RABBITMQ_DEFAULT_PASS
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: password
        volumeMounts:
        - name: rabbitmq-data
          mountPath: /var/lib/rabbitmq
  volumeClaimTemplates:
  - metadata:
      name: rabbitmq-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

**2. Enable persistent storage for message durability**
- Persistent volumes for RabbitMQ data
- Durable queues in Spring AMQP configuration
- Publisher confirms enabled

**3. Configure Spring Modulith to retry failed event publishing**
```java
// Event publication retry config
@Configuration
public class EventPublicationConfiguration {
    @Bean
    public EventPublicationRetryListener retryListener() {
        return new EventPublicationRetryListener(
            3,  // max retries
            Duration.ofMinutes(5)  // retry interval
        );
    }
}
```

**4. Monitor event_publication table for stuck events**
- Spring Modulith stores unpublished events in `event_publication` table
- Alert if events stuck > 1 hour
- Manual intervention procedure documented

**5. Dead-letter exchange for failed events**
```yaml
# RabbitMQ dead-letter exchange config
spring:
  rabbitmq:
    listener:
      simple:
        retry:
          enabled: true
          max-attempts: 3
        default-requeue-rejected: false
```

**When to Consider Migration to Pub/Sub:**
- Message volume exceeds 1M+/day
- RabbitMQ operational burden becomes unsustainable
- Need global message distribution
- Operational cost of RabbitMQ cluster > Pub/Sub fees

---

### 5. ⚠️ LOW: Database Migration Exit Costs

**Risk Level:** LOW - Future flexibility concern

**Problem:**
- Cloud SQL has per-GB egress costs for data export
- Large database migration from GCP could be expensive
- Need to export data to leave GCP

**Impact:**
- Vendor lock-in is minimal (PostgreSQL standard) but **exit cost exists**
- Budget must account for potential migration egress fees

**Egress Pricing (GCP to Internet):**
- First 1GB/month: Free
- 1GB - 10TB/month: $0.12/GB
- 10TB - 150TB/month: $0.11/GB

**Example Migration Costs:**
- 10GB database: ~$1.20
- 100GB database: ~$12
- 1TB database: ~$120

**Mitigation Strategy:**

**1. Document backup and export procedures**
```bash
# Regular pg_dump exports
pg_dump -h CLOUD_SQL_IP -U postgres -Fc budget_analyzer > backup_$(date +%Y%m%d).dump

# Test restore locally
pg_restore -d test_db backup_20251116.dump
```

**2. Test database export regularly (monthly)**
- Validate backup integrity
- Measure export time
- Estimate egress costs based on current size

**3. Size backups to estimate migration cost**
```bash
# Check backup size
ls -lh backup_*.dump

# Estimate egress cost ($0.12/GB)
echo "scale=2; $(du -m backup.dump | cut -f1) * 0.12 / 1024" | bc
```

**4. Use Google Cloud Storage for backups (cheaper than egress)**
- Store backups in GCS bucket
- Download to local when needed (still incurs egress)
- Keep 30-day backup retention

**5. Consider logical replication for zero-downtime migration**
- PostgreSQL logical replication to target database
- Sync data continuously
- Cutover when ready (minimal downtime)

**Verdict:** Low risk - PostgreSQL is standard, migration is straightforward, exit costs are predictable and reasonable.

---

## Deployment Best Practices (2025)

### Spring Boot Microservices on GCP

#### 1. Containerization with Jib (No Dockerfile Needed)

**Why Jib:**
- No Docker daemon required for builds
- Reproducible builds (deterministic layer generation)
- Fast incremental builds (only changed layers uploaded)
- Native Gradle/Maven integration

**Configuration:**

```gradle
// build.gradle
plugins {
    id 'org.springframework.boot' version '3.2.0'
    id 'io.spring.dependency-management' version '1.1.4'
    id 'java'
    id 'com.google.cloud.tools.jib' version '3.4.0'
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

jib {
    from {
        image = 'eclipse-temurin:21-jre-alpine'
        platforms {
            platform {
                architecture = 'amd64'
                os = 'linux'
            }
        }
    }
    to {
        image = "us-central1-docker.pkg.dev/${project.findProperty('gcp.project')}/budget-analyzer/${project.name}"
        tags = ['latest', project.version]
    }
    container {
        jvmFlags = [
            '-XX:+UseContainerSupport',
            '-XX:MaxRAMPercentage=75.0',
            '-Djava.security.egd=file:/dev/./urandom'
        ]
        ports = ['8082']
        labels = [
            'org.opencontainers.image.source': 'https://github.com/budgetanalyzer/transaction-service',
            'org.opencontainers.image.version': project.version
        ]
        creationTime = 'USE_CURRENT_TIMESTAMP'
    }
}
```

**Build and Push:**
```bash
# Build and push to Artifact Registry
./gradlew jib --image=us-central1-docker.pkg.dev/PROJECT_ID/budget-analyzer/transaction-service:1.0.0

# Build to Docker daemon (for local testing)
./gradlew jibDockerBuild
```

---

#### 2. Health Checks with Spring Boot Actuator

**Configuration:**

```yaml
# application.yml
management:
  endpoints:
    web:
      base-path: /actuator
      exposure:
        include: health,info,prometheus,metrics
  endpoint:
    health:
      probes:
        enabled: true
      show-details: when-authorized
  health:
    livenessState:
      enabled: true
    readinessState:
      enabled: true
    db:
      enabled: true
    redis:
      enabled: true
```

**Kubernetes Probes:**

```yaml
# kubernetes/transaction-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transaction-service
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
      - name: transaction-service
        image: us-central1-docker.pkg.dev/PROJECT_ID/budget-analyzer/transaction-service:VERSION
        ports:
        - containerPort: 8082
          name: http
          protocol: TCP
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "production"
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: transaction-service-url
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8082
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8082
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8082
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 30
```

**Health Check Behavior:**
- **Liveness:** Application is running (JVM healthy)
- **Readiness:** Application can accept traffic (DB connected, dependencies available)
- **Startup:** Application is initializing (grace period for slow startup)

---

#### 3. Structured JSON Logging

**Why JSON Logging:**
- Easier parsing by Cloud Logging
- Structured fields for filtering
- Better integration with log aggregation tools
- Trace correlation support

**Configuration:**

```xml
<!-- logback-spring.xml -->
<configuration>
    <springProfile name="production">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <fieldNames>
                    <timestamp>timestamp</timestamp>
                    <message>message</message>
                    <logger>logger</logger>
                    <thread>thread</thread>
                    <level>level</level>
                    <levelValue>[ignore]</levelValue>
                </fieldNames>
                <throwableConverter class="net.logstash.logback.stacktrace.ShortenedThrowableConverter">
                    <maxDepthPerThrowable>30</maxDepthPerThrowable>
                    <maxLength>4096</maxLength>
                </throwableConverter>
            </encoder>
        </appender>
        <root level="INFO">
            <appender-ref ref="CONSOLE"/>
        </root>
    </springProfile>
</configuration>
```

```gradle
// build.gradle
dependencies {
    implementation 'net.logstash.logback:logstash-logback-encoder:7.4'
}
```

**Output Example:**
```json
{
  "timestamp": "2025-11-16T10:30:45.123Z",
  "level": "INFO",
  "logger": "com.budgetanalyzer.transaction.service.TransactionService",
  "message": "Created transaction",
  "thread": "http-nio-8082-exec-1",
  "transaction_id": "txn_12345",
  "user_id": "user_67890",
  "amount": 45.67
}
```

---

#### 4. Metrics with Micrometer Prometheus

**Configuration:**

```yaml
# application.yml
management:
  metrics:
    export:
      prometheus:
        enabled: true
    distribution:
      percentiles-histogram:
        http.server.requests: true
    tags:
      application: ${spring.application.name}
      environment: ${ENVIRONMENT:dev}
```

```gradle
// build.gradle
dependencies {
    implementation 'io.micrometer:micrometer-registry-prometheus'
}
```

**Custom Metrics:**

```java
@Service
public class TransactionService {
    private final Counter transactionCounter;
    private final Timer transactionTimer;

    public TransactionService(MeterRegistry meterRegistry) {
        this.transactionCounter = Counter.builder("transactions.created")
            .description("Total transactions created")
            .tag("service", "transaction-service")
            .register(meterRegistry);

        this.transactionTimer = Timer.builder("transactions.processing.time")
            .description("Transaction processing time")
            .register(meterRegistry);
    }

    public Transaction createTransaction(TransactionRequest request) {
        return transactionTimer.record(() -> {
            Transaction tx = // ... create transaction
            transactionCounter.increment();
            return tx;
        });
    }
}
```

**Prometheus Scrape Config:**

```yaml
# prometheus-config.yaml
scrape_configs:
  - job_name: 'transaction-service'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: transaction-service
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
```

---

#### 5. Configuration Management

**Externalized Configuration Pattern:**

```yaml
# application.yml (checked into source control, no secrets)
spring:
  application:
    name: transaction-service
  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
    hikari:
      maximum-pool-size: 10
      connection-timeout: 30000
  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
  data:
    redis:
      host: ${REDIS_HOST}
      port: ${REDIS_PORT:6379}
  rabbitmq:
    host: ${RABBITMQ_HOST}
    port: ${RABBITMQ_PORT:5672}
    username: ${RABBITMQ_USERNAME}
    password: ${RABBITMQ_PASSWORD}

fred:
  api:
    key: ${FRED_API_KEY}
    base-url: https://api.stlouisfed.org/fred
```

**Kubernetes ConfigMap (non-sensitive config):**

```yaml
# kubernetes/transaction-service-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: transaction-service-config
data:
  REDIS_HOST: "MEMORYSTORE_IP"
  REDIS_PORT: "6379"
  RABBITMQ_HOST: "rabbitmq-headless"
  RABBITMQ_PORT: "5672"
```

**Kubernetes Secret (sensitive config):**

```yaml
# kubernetes/transaction-service-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: transaction-service-secret
type: Opaque
stringData:
  DATABASE_URL: "jdbc:postgresql://CLOUD_SQL_IP:5432/budget_analyzer?currentSchema=transaction_service"
  DATABASE_USERNAME: "transaction_service_user"
  DATABASE_PASSWORD: "CHANGE_ME"  # Reference from Secret Manager
  RABBITMQ_USERNAME: "admin"
  RABBITMQ_PASSWORD: "CHANGE_ME"  # Reference from Secret Manager
  FRED_API_KEY: "CHANGE_ME"  # Reference from Secret Manager
```

**Deployment with Secret Manager Integration:**

```yaml
# kubernetes/transaction-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: transaction-service-sa
      containers:
      - name: transaction-service
        envFrom:
        - configMapRef:
            name: transaction-service-config
        env:
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: transaction-service-secret
              key: DATABASE_PASSWORD
        # Or use Secret Manager volume mount
        volumeMounts:
        - name: secrets
          mountPath: /secrets
          readOnly: true
      volumes:
      - name: secrets
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "transaction-service-secrets"
```

---

### React Application Deployment on GCP

#### 1. Multi-Stage Docker Build

**Dockerfile:**

```dockerfile
# Stage 1: Build React application
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package.json package-lock.json ./

# Install dependencies (use ci for reproducible builds)
RUN npm ci --only=production

# Copy source code
COPY . .

# Build arguments for environment variables
ARG REACT_APP_API_URL
ARG REACT_APP_ENV
ENV REACT_APP_API_URL=$REACT_APP_API_URL
ENV REACT_APP_ENV=$REACT_APP_ENV

# Build production bundle
RUN npm run build

# Stage 2: Serve with NGINX
FROM nginx:1.25-alpine

# Copy custom NGINX configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy built React app from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Security: Run as non-root user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
```

---

#### 2. NGINX Configuration for React Router

**nginx.conf:**

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript
               application/x-javascript application/xml+rss
               application/javascript application/json;

    server {
        listen 8080;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # Content Security Policy (adjust based on your needs)
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://api.budgetanalyzer.com;" always;

        # Handle React Router (SPA routing)
        location / {
            try_files $uri $uri/ /index.html;
        }

        # Cache static assets
        location /static/ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # Cache images
        location ~* \.(jpg|jpeg|png|gif|ico|svg|webp)$ {
            expires 30d;
            add_header Cache-Control "public, immutable";
        }

        # Cache CSS/JS
        location ~* \.(css|js)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
```

---

#### 3. Cloud Run Deployment

**Build and Deploy:**

```bash
# Build with build arguments
docker build \
  --build-arg REACT_APP_API_URL=https://api.budgetanalyzer.com \
  --build-arg REACT_APP_ENV=production \
  -t us-central1-docker.pkg.dev/PROJECT_ID/budget-analyzer/budget-analyzer-web:1.0.0 \
  .

# Push to Artifact Registry
docker push us-central1-docker.pkg.dev/PROJECT_ID/budget-analyzer/budget-analyzer-web:1.0.0

# Deploy to Cloud Run
gcloud run deploy budget-analyzer-web \
  --image us-central1-docker.pkg.dev/PROJECT_ID/budget-analyzer/budget-analyzer-web:1.0.0 \
  --platform managed \
  --region us-central1 \
  --port 8080 \
  --min-instances 0 \
  --max-instances 10 \
  --memory 256Mi \
  --cpu 1 \
  --allow-unauthenticated \
  --set-env-vars="ENVIRONMENT=production"
```

**Cloud Run Service YAML (for GitOps):**

```yaml
# kubernetes/cloud-run/budget-analyzer-web.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: budget-analyzer-web
  namespace: default
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0"
        autoscaling.knative.dev/maxScale: "10"
    spec:
      containerConcurrency: 80
      containers:
      - image: us-central1-docker.pkg.dev/PROJECT_ID/budget-analyzer/budget-analyzer-web:VERSION
        ports:
        - containerPort: 8080
          name: http1
        resources:
          limits:
            cpu: 1000m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
```

---

#### 4. Environment-Specific Builds

**package.json scripts:**

```json
{
  "scripts": {
    "build": "vite build",
    "build:dev": "REACT_APP_ENV=development vite build",
    "build:staging": "REACT_APP_ENV=staging vite build",
    "build:production": "REACT_APP_ENV=production vite build"
  }
}
```

**Environment configuration:**

```typescript
// src/config/environment.ts
const env = import.meta.env.VITE_APP_ENV || 'development';

const configs = {
  development: {
    apiUrl: 'http://localhost:8080/api',
    auth0Domain: 'dev-budgetanalyzer.auth0.com',
    auth0ClientId: 'DEV_CLIENT_ID',
  },
  staging: {
    apiUrl: 'https://staging-api.budgetanalyzer.com/api',
    auth0Domain: 'staging-budgetanalyzer.auth0.com',
    auth0ClientId: 'STAGING_CLIENT_ID',
  },
  production: {
    apiUrl: 'https://api.budgetanalyzer.com/api',
    auth0Domain: 'budgetanalyzer.auth0.com',
    auth0ClientId: 'PROD_CLIENT_ID',
  },
};

export const config = configs[env as keyof typeof configs];
```

---

## Phased Deployment Roadmap

### Phase 0: GCP Project Setup

**Timeline:** 1-2 days
**Prerequisites:** GCP account, billing enabled, project quota approved

**Tasks:**

1. **Create GCP Project**
   ```bash
   gcloud projects create budget-analyzer-prod --name="Budget Analyzer Production"
   gcloud config set project budget-analyzer-prod
   ```

2. **Enable Required APIs**
   ```bash
   gcloud services enable \
     container.googleapis.com \
     compute.googleapis.com \
     sqladmin.googleapis.com \
     redis.googleapis.com \
     secretmanager.googleapis.com \
     artifactregistry.googleapis.com \
     cloudresourcemanager.googleapis.com \
     iam.googleapis.com
   ```

3. **Create Artifact Registry**
   ```bash
   gcloud artifacts repositories create budget-analyzer \
     --repository-format=docker \
     --location=us-central1 \
     --description="Budget Analyzer Docker images"
   ```

4. **Set Up GitHub Actions with Workload Identity**
   ```bash
   # Create service account
   gcloud iam service-accounts create github-actions \
     --display-name="GitHub Actions Service Account"

   # Grant permissions
   gcloud projects add-iam-policy-binding budget-analyzer-prod \
     --member="serviceAccount:github-actions@budget-analyzer-prod.iam.gserviceaccount.com" \
     --role="roles/container.developer"

   gcloud projects add-iam-policy-binding budget-analyzer-prod \
     --member="serviceAccount:github-actions@budget-analyzer-prod.iam.gserviceaccount.com" \
     --role="roles/artifactregistry.writer"

   # Configure Workload Identity Federation
   gcloud iam workload-identity-pools create github-pool \
     --location=global \
     --display-name="GitHub Actions Pool"

   gcloud iam workload-identity-pools providers create-oidc github-provider \
     --location=global \
     --workload-identity-pool=github-pool \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --attribute-condition="assertion.repository_owner=='budget-analyzer'"
   ```

5. **Create Initial Secrets in Secret Manager**
   ```bash
   # Database password
   echo -n "STRONG_PASSWORD_HERE" | gcloud secrets create db-password \
     --data-file=- \
     --replication-policy=automatic

   # RabbitMQ password
   echo -n "RABBITMQ_PASSWORD_HERE" | gcloud secrets create rabbitmq-password \
     --data-file=- \
     --replication-policy=automatic

   # FRED API key
   echo -n "FRED_API_KEY_HERE" | gcloud secrets create fred-api-key \
     --data-file=- \
     --replication-policy=automatic
   ```

**Deliverables:**
- [ ] GCP project created and configured
- [ ] APIs enabled
- [ ] Artifact Registry ready
- [ ] GitHub Actions authentication configured
- [ ] Initial secrets stored in Secret Manager

---

### Phase 1: Private Network Deployment (Infrastructure Testing)

**Timeline:** 1-2 weeks
**Purpose:** Validate infrastructure, test deployment procedures, NO public access
**Data:** Test/mock data only, no real financial information

**Tasks:**

#### Week 1: Core Infrastructure

1. **Create GKE Standard Cluster**
   ```bash
   gcloud container clusters create budget-analyzer-cluster \
     --region us-central1 \
     --num-nodes 1 \
     --machine-type e2-medium \
     --disk-size 30 \
     --enable-autoscaling \
     --min-nodes 1 \
     --max-nodes 4 \
     --enable-autorepair \
     --enable-autoupgrade \
     --no-enable-basic-auth \
     --no-issue-client-certificate \
     --enable-ip-alias \
     --network default \
     --subnetwork default \
     --enable-stackdriver-kubernetes \
     --addons HorizontalPodAutoscaling,HttpLoadBalancing \
     --workload-pool=budget-analyzer-prod.svc.id.goog
   ```

2. **Deploy Cloud SQL PostgreSQL**
   ```bash
   gcloud sql instances create budget-analyzer-db \
     --database-version=POSTGRES_15 \
     --tier=db-custom-2-4096 \
     --region=us-central1 \
     --availability-type=regional \
     --backup-start-time=03:00 \
     --enable-bin-log \
     --retained-backups-count=7 \
     --network=default \
     --no-assign-ip

   # Create database
   gcloud sql databases create budget_analyzer \
     --instance=budget-analyzer-db

   # Create database user
   gcloud sql users create budget_user \
     --instance=budget-analyzer-db \
     --password=PASSWORD_FROM_SECRET_MANAGER
   ```

3. **Deploy Memorystore Redis**
   ```bash
   gcloud redis instances create budget-analyzer-redis \
     --size=5 \
     --region=us-central1 \
     --tier=standard \
     --redis-version=redis_7_0
   ```

4. **Deploy RabbitMQ to GKE**
   ```bash
   kubectl apply -f kubernetes/rabbitmq/
   ```

#### Week 2: Application Deployment

5. **Migrate NGINX Config to Gateway API**
   - Convert [nginx/nginx.dev.conf](../../nginx/nginx.dev.conf) to Gateway API HTTPRoutes
   - See [Migration Guide](#migration-guide-nginx-to-gateway-api)
   - Deploy Gateway and HTTPRoutes to GKE

6. **Deploy Backend Services**
   ```bash
   # Build and push images
   cd transaction-service
   ./gradlew jib --image=us-central1-docker.pkg.dev/budget-analyzer-prod/budget-analyzer/transaction-service:1.0.0

   cd ../currency-service
   ./gradlew jib --image=us-central1-docker.pkg.dev/budget-analyzer-prod/budget-analyzer/currency-service:1.0.0

   # Deploy to GKE
   kubectl apply -f kubernetes/transaction-service/
   kubectl apply -f kubernetes/currency-service/
   ```

7. **Deploy Frontend to Cloud Run**
   ```bash
   cd budget-analyzer-web
   docker build \
     --build-arg REACT_APP_API_URL=https://LOAD_BALANCER_IP/api \
     -t us-central1-docker.pkg.dev/budget-analyzer-prod/budget-analyzer/budget-analyzer-web:1.0.0 \
     .
   docker push us-central1-docker.pkg.dev/budget-analyzer-prod/budget-analyzer/budget-analyzer-web:1.0.0

   gcloud run deploy budget-analyzer-web \
     --image us-central1-docker.pkg.dev/budget-analyzer-prod/budget-analyzer/budget-analyzer-web:1.0.0 \
     --platform managed \
     --region us-central1 \
     --no-allow-unauthenticated  # PRIVATE ONLY
   ```

8. **Configure Private Networking**
   ```bash
   # Restrict access via VPC
   # No public ingress allowed
   # Access only via Cloud VPN or IAP for testing
   ```

9. **Testing**
   - Access via Cloud VPN or Identity-Aware Proxy
   - Load test data (mock transactions, fake users)
   - Validate:
     - Database connectivity
     - Redis caching
     - RabbitMQ event processing
     - Gateway routing
     - Health checks
     - Logging and monitoring

**Deliverables:**
- [ ] GKE cluster running with 2+ nodes
- [ ] Cloud SQL database accessible from GKE
- [ ] Memorystore Redis accessible from GKE
- [ ] RabbitMQ cluster (3 nodes) running in GKE
- [ ] Gateway API configured with HTTPRoutes
- [ ] Backend services deployed and healthy
- [ ] Frontend deployed to Cloud Run (private)
- [ ] Monitoring dashboards configured
- [ ] **CRITICAL:** No public internet access configured

**Success Criteria:**
- All services report healthy status
- Can create/read transactions via API (authenticated via VPN)
- Currency service caches exchange rates in Redis
- RabbitMQ processes Spring Modulith events
- Logs flowing to Cloud Logging
- Prometheus metrics scraped and visible in Grafana

---

### Phase 2: Authentication Implementation (Required for Production)

**Timeline:** 8 weeks
**Purpose:** Implement full OAuth2 + BFF security architecture
**Blocker:** Cannot deploy to public internet until complete

**Reference:** See detailed timeline in [authentication-implementation-plan.md](authentication-implementation-plan.md)

**Summary Tasks:**

#### Weeks 1-2: Session Gateway + Token Validation Service
- Implement Spring Cloud Gateway with Spring Security OAuth2
- Configure OAuth2 Client for Auth0 integration
- Implement token validation service (port 8088)
- Store JWTs in Redis, issue HTTP-only session cookies
- Proactive token refresh (5 min before expiration)

#### Weeks 3-4: Auth0 Integration + NGINX JWT Validation
- Configure Auth0 tenant (production settings)
- Set up Auth0 application (SPA + API)
- Update Gateway API with JWT validation via auth_request
- Proxy `/auth/*` endpoints to Auth0 via NGINX

#### Weeks 5-6: Backend OAuth2 Resource Server Configuration
- Add Spring Security OAuth2 Resource Server to transaction-service
- Add Spring Security OAuth2 Resource Server to currency-service
- Configure JWT validation against Auth0 JWKS endpoint
- Implement data-level authorization (query scoping by user ID)

#### Weeks 7-8: Testing, Security Audit, Penetration Testing
- End-to-end authentication flow testing
- Session management testing (logout, expiration, refresh)
- Security audit (OWASP Top 10 check)
- Penetration testing (hire external auditor)
- Fix any vulnerabilities discovered

**Deliverables:**
- [ ] Session Gateway deployed to GKE
- [ ] Token Validation Service deployed to GKE
- [ ] Auth0 tenant configured (production)
- [ ] Gateway API validating JWTs
- [ ] Backend services configured as OAuth2 Resource Servers
- [ ] Redis cluster for session storage (HA)
- [ ] End-to-end auth flow tested
- [ ] Security audit passed
- [ ] Penetration testing passed

**Success Criteria:**
- User can sign up/login via Auth0
- JWT stored in Redis, never exposed to browser
- Session cookie (HTTP-only, Secure, SameSite=Strict) issued
- NGINX Gateway validates JWT before proxying to backends
- Backend services reject requests without valid JWT
- User can only access their own transactions (data-level authorization)
- Token refresh works seamlessly (no user interruption)

---

### Phase 3: Production Launch (Public Deployment)

**Timeline:** 2-3 weeks
**Prerequisites:** Phase 2 complete, security audit passed

**Tasks:**

#### Week 1: Production Hardening

1. **Enable Cloud Armor (DDoS Protection)**
   ```bash
   gcloud compute security-policies create budget-analyzer-policy \
     --description="DDoS protection for Budget Analyzer"

   gcloud compute security-policies rules create 1000 \
     --security-policy budget-analyzer-policy \
     --expression="evaluatePreconfiguredExpr('sqli-stable')" \
     --action=deny-403

   gcloud compute security-policies rules create 1001 \
     --security-policy budget-analyzer-policy \
     --expression="evaluatePreconfiguredExpr('xss-stable')" \
     --action=deny-403

   # Rate limiting
   gcloud compute security-policies rules create 2000 \
     --security-policy budget-analyzer-policy \
     --expression="request.path.matches('/api/v1/')" \
     --action=rate-based-ban \
     --rate-limit-threshold-count=1000 \
     --rate-limit-threshold-interval-sec=60

   # Attach to load balancer backend service
   gcloud compute backend-services update BACKEND_SERVICE_NAME \
     --security-policy budget-analyzer-policy
   ```

2. **Enable Cloud CDN**
   ```bash
   gcloud compute backend-services update budget-analyzer-web-backend \
     --enable-cdn \
     --cache-mode=CACHE_ALL_STATIC \
     --default-ttl=3600 \
     --max-ttl=86400
   ```

3. **Configure SSL/TLS Certificates**
   ```bash
   # Google-managed certificate
   gcloud compute ssl-certificates create budget-analyzer-cert \
     --domains=budgetanalyzer.com,www.budgetanalyzer.com \
     --global

   # Attach to load balancer
   gcloud compute target-https-proxies update PROXY_NAME \
     --ssl-certificates budget-analyzer-cert
   ```

4. **Set Up Monitoring and Alerting**
   ```yaml
   # monitoring/alerting-policies.yaml
   - name: High Error Rate
     conditions:
       - threshold: 5%
         duration: 5m
         metric: http_requests_total{status=~"5.."}
     notification_channels: [email, pagerduty]

   - name: High Latency
     conditions:
       - threshold: 2s
         duration: 5m
         metric: http_request_duration_seconds{quantile="0.95"}
     notification_channels: [email]

   - name: Database Connection Pool Exhausted
     conditions:
       - threshold: 90%
         duration: 2m
         metric: hikaricp_connections_active / hikaricp_connections_max
     notification_channels: [email, pagerduty]

   - name: Session Storage Unavailable
     conditions:
       - threshold: 1
         duration: 1m
         metric: redis_up == 0
     notification_channels: [pagerduty]
   ```

5. **Create Runbooks**
   - Incident response procedures
   - Database backup/restore procedures
   - Rollback procedures
   - Scaling procedures

#### Week 2: Load Testing

6. **Load Testing with k6**
   ```javascript
   // loadtest/scenario.js
   import http from 'k6/http';
   import { check, sleep } from 'k6';

   export let options = {
     stages: [
       { duration: '5m', target: 100 },  // Ramp up to 100 users
       { duration: '10m', target: 100 }, // Stay at 100 users
       { duration: '5m', target: 500 },  // Ramp up to 500 users
       { duration: '10m', target: 500 }, // Stay at 500 users
       { duration: '5m', target: 0 },    // Ramp down
     ],
     thresholds: {
       http_req_duration: ['p(95)<2000'], // 95% of requests < 2s
       http_req_failed: ['rate<0.05'],    // Error rate < 5%
     },
   };

   export default function () {
     // Login
     let loginRes = http.post('https://api.budgetanalyzer.com/auth/login', {
       username: 'testuser@example.com',
       password: 'testpassword',
     });
     check(loginRes, { 'login successful': (r) => r.status === 200 });
     let sessionCookie = loginRes.cookies['SESSION'];

     // Get transactions
     let txRes = http.get('https://api.budgetanalyzer.com/api/v1/transactions', {
       cookies: { SESSION: sessionCookie },
     });
     check(txRes, { 'transactions fetched': (r) => r.status === 200 });

     sleep(1);
   }
   ```

   ```bash
   k6 run --vus 100 --duration 30m loadtest/scenario.js
   ```

7. **Analyze Results**
   - Identify bottlenecks (database, cache, CPU)
   - Optimize queries, add indexes
   - Tune JVM settings, connection pools
   - Scale GKE nodes if needed

#### Week 3: Go Live

8. **Enable Public Access**
   ```bash
   # Update DNS records to point to load balancer IP
   # Update Cloud Run to allow unauthenticated (behind auth gateway)
   gcloud run services update budget-analyzer-web \
     --allow-unauthenticated
   ```

9. **Gradual Rollout**
   - Beta launch to small user group (10-50 users)
   - Monitor for 3-5 days
   - Fix any issues
   - Expand to larger group (100-500 users)
   - Monitor for 1 week
   - Full public launch

10. **Post-Launch Monitoring**
    - 24/7 on-call rotation (PagerDuty)
    - Daily review of error logs
    - Weekly performance review
    - Monthly cost review and optimization

**Deliverables:**
- [ ] Cloud Armor policies active
- [ ] Cloud CDN enabled
- [ ] SSL/TLS certificates configured
- [ ] Monitoring and alerting operational
- [ ] Runbooks documented
- [ ] Load testing completed and passed
- [ ] Public DNS pointing to load balancer
- [ ] Production launch complete

**Success Criteria:**
- p95 latency < 2 seconds
- Error rate < 1%
- Uptime > 99.9%
- All security controls active
- Users can successfully sign up, login, manage transactions
- No data loss or corruption
- On-call team responds to incidents within 15 minutes

---

## Migration Guide: NGINX to Gateway API

### Overview

**Context:** NGINX Ingress Controller retiring March 2026 (no updates after)
**Target:** Kubernetes Gateway API (v1, stable)
**Effort:** Medium (2-3 days for initial migration, 1 week for full testing)

### Key Concepts

**NGINX Ingress:**
- Single Ingress resource with routing rules
- `nginx.conf` style annotations
- Limited to HTTP/HTTPS

**Gateway API:**
- Separation of concerns: Gateway (infrastructure) + HTTPRoute (application)
- More expressive routing (headers, query params, weights)
- Support for TCP/UDP, gRPC, TLS routing
- Role-based access control (RBAC) for different teams

### Architecture Comparison

**Current (NGINX Ingress):**
```
Load Balancer → NGINX Ingress Controller → Backend Services
                (routing via Ingress resource)
```

**Target (Gateway API):**
```
Load Balancer → Gateway (GKE-managed) → Backend Services
                (routing via HTTPRoute resources)
```

### Step-by-Step Migration

#### Step 1: Install Gateway API CRDs (GKE 1.26+)

```bash
# GKE 1.26+ includes Gateway API by default
# Verify installation
kubectl get crd gateways.gateway.networking.k8s.io

# If not installed, apply CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
```

#### Step 2: Create Gateway Resource

**Gateway = Infrastructure layer (like load balancer + TLS termination)**

```yaml
# kubernetes/gateway/api-gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: api-gateway
  namespace: default
spec:
  gatewayClassName: gke-l7-global-external-managed  # GCP-managed load balancer
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: api-gateway-tls
    allowedRoutes:
      namespaces:
        from: Same
---
# Managed certificate (Google-managed)
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: api-gateway-cert
spec:
  domains:
  - api.budgetanalyzer.com
  - budgetanalyzer.com
```

#### Step 3: Migrate NGINX Routes to HTTPRoutes

**Current NGINX Config** ([nginx/nginx.dev.conf](../../nginx/nginx.dev.conf)):

```nginx
# Transaction service routing
location /api/v1/transactions {
    rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
    proxy_pass http://transaction_service:8082;
}

# Currency service routing
location /api/v1/currencies {
    rewrite ^/api/v1/(.*)$ /currency-service/v1/$1 break;
    proxy_pass http://currency_service:8084;
}

# Exchange rates routing
location /api/v1/exchange-rates {
    rewrite ^/api/v1/(.*)$ /currency-service/v1/$1 break;
    proxy_pass http://currency_service:8084;
}
```

**Gateway API HTTPRoutes:**

```yaml
# kubernetes/gateway/transaction-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: transaction-route
  namespace: default
spec:
  parentRefs:
  - name: api-gateway
    namespace: default
  hostnames:
  - "api.budgetanalyzer.com"
  rules:
  # Transactions
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1/transactions
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /transaction-service/v1/transactions
    backendRefs:
    - name: transaction-service
      port: 8082
      weight: 100
  # Budgets
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1/budgets
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /transaction-service/v1/budgets
    backendRefs:
    - name: transaction-service
      port: 8082
      weight: 100
---
# kubernetes/gateway/currency-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: currency-route
  namespace: default
spec:
  parentRefs:
  - name: api-gateway
    namespace: default
  hostnames:
  - "api.budgetanalyzer.com"
  rules:
  # Currencies
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1/currencies
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /currency-service/v1/currencies
    backendRefs:
    - name: currency-service
      port: 8084
      weight: 100
  # Exchange rates
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1/exchange-rates
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /currency-service/v1/exchange-rates
    backendRefs:
    - name: currency-service
      port: 8084
      weight: 100
```

#### Step 4: Add JWT Validation (Session Gateway Integration)

**Current NGINX (auth_request pattern):**

```nginx
location /api/ {
    auth_request /validate_token;
    # ... proxy to backend
}

location /validate_token {
    internal;
    proxy_pass http://token_validation_service:8088/validate;
}
```

**Gateway API with GCP Backend Service:**

```yaml
# kubernetes/gateway/authenticated-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: authenticated-transaction-route
  namespace: default
  annotations:
    # GCP-specific: Cloud Armor security policy
    cloud.google.com/armor-config: '{"budget-analyzer-policy": "enabled"}'
spec:
  parentRefs:
  - name: api-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1/transactions
    filters:
    # Request header modification (add JWT from session)
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Forwarded-For
          value: "{client-ip}"
    backendRefs:
    # First: Validate token
    - name: token-validation-service
      port: 8088
      weight: 0  # Not actually routing here, using for auth
      filters:
      - type: RequestHeaderModifier
        requestHeaderModifier:
          set:
          - name: X-Auth-Request-Redirect
            value: "/api/v1/transactions"
    # Then: Route to backend
    - name: transaction-service
      port: 8082
      weight: 100
```

**Note:** Gateway API doesn't have native `auth_request` equivalent. Options:

**Option A: Use External Authorization (recommended):**

Deploy Envoy Gateway or similar with external authorization filter:

```yaml
# Using Envoy Gateway (more portable than GCP-specific)
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: jwt-validation
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: transaction-route
  extAuth:
    grpc:
      backendRef:
        name: token-validation-service
        port: 8088
```

**Option B: Use Service Mesh (Linkerd, future):**

Linkerd with external authorization policy:

```yaml
apiVersion: policy.linkerd.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: jwt-required
spec:
  targetRef:
    group: ""
    kind: Service
    name: transaction-service
  requiredAuthenticationRefs:
  - name: jwt-auth
    kind: MeshTLSAuthentication
```

**Recommendation for Phase 1:** Deploy NGINX Gateway in GKE (containerized) with auth_request until service mesh is implemented in Phase 2.

#### Step 5: Frontend Routing

**Frontend needs to access both Session Gateway and API Gateway:**

```yaml
# kubernetes/gateway/frontend-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: frontend-route
  namespace: default
spec:
  parentRefs:
  - name: api-gateway
  hostnames:
  - "budgetanalyzer.com"
  - "www.budgetanalyzer.com"
  rules:
  # Session Gateway (authentication endpoints)
  - matches:
    - path:
        type: PathPrefix
        value: /auth/
    backendRefs:
    - name: session-gateway
      port: 8081
  # API endpoints (authenticated)
  - matches:
    - path:
        type: PathPrefix
        value: /api/
    backendRefs:
    - name: nginx-gateway  # Internal NGINX for resource routing + JWT validation
      port: 8080
  # Frontend SPA (Cloud Run)
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - kind: Service
      name: budget-analyzer-web
      port: 80
      group: cloud.google.com  # Cloud Run service
```

#### Step 6: Deploy and Test

```bash
# Deploy Gateway
kubectl apply -f kubernetes/gateway/api-gateway.yaml

# Deploy HTTPRoutes
kubectl apply -f kubernetes/gateway/transaction-route.yaml
kubectl apply -f kubernetes/gateway/currency-route.yaml
kubectl apply -f kubernetes/gateway/frontend-route.yaml

# Check Gateway status
kubectl get gateway api-gateway
kubectl describe gateway api-gateway

# Check HTTPRoutes
kubectl get httproute
kubectl describe httproute transaction-route

# Get load balancer IP
kubectl get gateway api-gateway -o jsonpath='{.status.addresses[0].value}'

# Test routing
curl -v http://LOAD_BALANCER_IP/api/v1/transactions
curl -v http://LOAD_BALANCER_IP/api/v1/currencies
```

#### Step 7: Parallel Testing (Recommended)

**Run NGINX and Gateway API in parallel during migration:**

```yaml
# Temporary: Deploy both NGINX Ingress and Gateway API
# Route % of traffic to Gateway API, monitor for issues

apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: transaction-route-canary
spec:
  parentRefs:
  - name: api-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api/v1/transactions
    backendRefs:
    - name: transaction-service
      port: 8082
      weight: 10  # 10% traffic to Gateway API
    - name: nginx-gateway
      port: 8080
      weight: 90  # 90% traffic to NGINX (fallback)
```

Gradually increase weight to Gateway API as confidence grows.

#### Step 8: Cutover

**Once Gateway API is validated:**

1. Update DNS to point to Gateway API load balancer IP
2. Monitor for 24 hours
3. If stable, decommission NGINX Ingress Controller
4. Remove NGINX Ingress resources

```bash
# Remove NGINX Ingress
kubectl delete ingress --all
kubectl delete deployment nginx-ingress-controller
```

### Migration Checklist

**Pre-Migration:**
- [ ] Gateway API CRDs installed in GKE cluster
- [ ] GatewayClass available (gke-l7-global-external-managed)
- [ ] Managed certificate created for domain
- [ ] HTTPRoutes written for all current NGINX locations

**Migration:**
- [ ] Gateway resource deployed
- [ ] HTTPRoutes deployed
- [ ] Load balancer IP assigned to Gateway
- [ ] DNS records updated (if testing)
- [ ] Routing tested (all paths work)
- [ ] JWT validation tested (if applicable)
- [ ] CORS headers verified
- [ ] SSL/TLS working
- [ ] Health checks passing

**Post-Migration:**
- [ ] Monitor error rates (should be < 1%)
- [ ] Monitor latency (should be similar to NGINX)
- [ ] Verify Cloud Armor policies active
- [ ] Load testing completed
- [ ] Documentation updated
- [ ] Team trained on Gateway API debugging

### Common Issues and Solutions

**Issue 1: Gateway stuck in "Pending" status**
```bash
# Check Gateway status
kubectl describe gateway api-gateway

# Common causes:
# - GatewayClass not found (check: kubectl get gatewayclass)
# - Invalid certificate reference
# - Insufficient IAM permissions for GKE to create load balancer
```

**Issue 2: HTTPRoute not attaching to Gateway**
```bash
# Check HTTPRoute status
kubectl describe httproute transaction-route

# Look for "Accepted: False" condition
# Common causes:
# - Gateway and HTTPRoute in different namespaces
# - Gateway listener doesn't allow HTTPRoute namespace
# - Hostname mismatch
```

**Issue 3: 404 errors on valid paths**
```bash
# Verify HTTPRoute matches
kubectl get httproute transaction-route -o yaml

# Common causes:
# - PathPrefix doesn't match actual request path
# - URLRewrite incorrect (test with curl -v)
# - Backend service doesn't exist or wrong port
```

**Issue 4: CORS errors from browser**
```yaml
# Add CORS headers via ResponseHeaderModifier
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
spec:
  rules:
  - filters:
    - type: ResponseHeaderModifier
      responseHeaderModifier:
        add:
        - name: Access-Control-Allow-Origin
          value: "https://budgetanalyzer.com"
        - name: Access-Control-Allow-Methods
          value: "GET, POST, PUT, DELETE, OPTIONS"
        - name: Access-Control-Allow-Headers
          value: "Content-Type, Authorization"
```

### Gateway API Resources

**Official Documentation:**
- https://gateway-api.sigs.k8s.io/
- https://cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities

**Comparison Guide:**
- https://gateway-api.sigs.k8s.io/guides/migrating-from-ingress/

**GKE-Specific:**
- https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api

---

## Operational Runbooks

### Runbook 1: Database Backup and Restore

**Purpose:** Recover from database corruption, accidental deletion, or disaster

**Backup Procedures:**

**Automated Backups (Cloud SQL):**
```bash
# Verify automated backups enabled
gcloud sql instances describe budget-analyzer-db --format="value(settings.backupConfiguration.enabled)"

# List available backups
gcloud sql backups list --instance=budget-analyzer-db

# Backup retention: 7 days (configured)
```

**Manual On-Demand Backup:**
```bash
# Create manual backup
gcloud sql backups create \
  --instance=budget-analyzer-db \
  --description="Pre-migration backup $(date +%Y-%m-%d)"

# Export to Cloud Storage (for external backup)
gcloud sql export sql budget-analyzer-db \
  gs://budget-analyzer-backups/manual-backup-$(date +%Y%m%d).sql \
  --database=budget_analyzer
```

**Restore Procedures:**

**Option A: Point-in-Time Recovery (within 7 days):**
```bash
# Restore to specific timestamp
gcloud sql backups restore BACKUP_ID \
  --backup-instance=budget-analyzer-db \
  --instance=budget-analyzer-db-restored

# Verify restored data
gcloud sql connect budget-analyzer-db-restored --user=postgres
```

**Option B: Restore from Manual Backup:**
```bash
# Create new instance
gcloud sql instances create budget-analyzer-db-restored \
  --database-version=POSTGRES_15 \
  --tier=db-custom-2-4096 \
  --region=us-central1

# Import from Cloud Storage
gcloud sql import sql budget-analyzer-db-restored \
  gs://budget-analyzer-backups/manual-backup-20251116.sql \
  --database=budget_analyzer
```

**Option C: Export to Local (Migration/Debugging):**
```bash
# Export via Cloud SQL Proxy
gcloud sql instances describe budget-analyzer-db --format="value(connectionName)"
# CONNECTION_NAME = budget-analyzer-prod:us-central1:budget-analyzer-db

# Start Cloud SQL Proxy
cloud_sql_proxy -instances=CONNECTION_NAME=tcp:5432 &

# Export with pg_dump
pg_dump -h 127.0.0.1 -U postgres -Fc budget_analyzer > local-backup.dump

# Restore locally
pg_restore -d local_budget_analyzer local-backup.dump
```

**Validation:**
```sql
-- Connect to restored database
psql -h INSTANCE_IP -U postgres -d budget_analyzer

-- Check record counts
SELECT 'transactions' AS table_name, COUNT(*) FROM transaction_service.transactions
UNION ALL
SELECT 'budgets', COUNT(*) FROM transaction_service.budgets
UNION ALL
SELECT 'exchange_rates', COUNT(*) FROM currency_service.exchange_rates;

-- Check latest transaction timestamp
SELECT MAX(created_at) FROM transaction_service.transactions;
```

---

### Runbook 2: Service Rollback

**Purpose:** Quickly revert to previous version after bad deployment

**Kubernetes Rollback (GKE):**

```bash
# Check deployment history
kubectl rollout history deployment/transaction-service

# Rollback to previous version
kubectl rollout undo deployment/transaction-service

# Rollback to specific revision
kubectl rollout undo deployment/transaction-service --to-revision=3

# Monitor rollback progress
kubectl rollout status deployment/transaction-service

# Verify pods running previous version
kubectl get pods -l app=transaction-service -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Cloud Run Rollback:**

```bash
# List revisions
gcloud run revisions list --service=budget-analyzer-web --region=us-central1

# Rollback to specific revision
gcloud run services update-traffic budget-analyzer-web \
  --region=us-central1 \
  --to-revisions=budget-analyzer-web-00042-abc=100

# Verify traffic routing
gcloud run services describe budget-analyzer-web \
  --region=us-central1 \
  --format="value(status.traffic)"
```

**Validation:**

```bash
# Check service health
kubectl get pods -l app=transaction-service
kubectl logs -l app=transaction-service --tail=100

# Test API endpoint
curl -v https://api.budgetanalyzer.com/api/v1/transactions

# Check error rate in monitoring
# (verify < 1% after rollback)
```

**Post-Rollback:**
- [ ] Notify team in Slack/incident channel
- [ ] Document reason for rollback
- [ ] Create bug ticket for issue
- [ ] Review deployment process (CI/CD, testing gaps)

---

### Runbook 3: Scaling for Traffic Spikes

**Purpose:** Handle unexpected traffic increases (viral growth, marketing campaigns)

**GKE Node Autoscaling:**

```bash
# Check current node count
kubectl get nodes

# Check node pool autoscaling config
gcloud container node-pools describe default-pool \
  --cluster=budget-analyzer-cluster \
  --region=us-central1 \
  --format="value(autoscaling)"

# Update autoscaling limits (if needed)
gcloud container node-pools update default-pool \
  --cluster=budget-analyzer-cluster \
  --region=us-central1 \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=10

# Monitor node provisioning
kubectl get nodes -w
```

**Horizontal Pod Autoscaling (HPA):**

```yaml
# kubernetes/transaction-service-hpa.yaml
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
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

```bash
# Deploy HPA
kubectl apply -f kubernetes/transaction-service-hpa.yaml

# Monitor HPA status
kubectl get hpa transaction-service-hpa -w

# Check current replicas
kubectl get deployment transaction-service
```

**Database Connection Pool Scaling:**

```yaml
# Increase max connections temporarily
# application.yml (transaction-service)
spring:
  datasource:
    hikari:
      maximum-pool-size: 20  # Increase from 10
      minimum-idle: 5
```

**Redeploy with increased pool size:**
```bash
kubectl set env deployment/transaction-service HIKARI_MAX_POOL_SIZE=20
kubectl rollout status deployment/transaction-service
```

**Cloud SQL Scaling:**

```bash
# Increase CPU/memory temporarily
gcloud sql instances patch budget-analyzer-db \
  --tier=db-custom-4-8192 \
  --activation-policy=ALWAYS

# Monitor database performance
gcloud sql operations list --instance=budget-analyzer-db
```

**Monitoring During Spike:**

```bash
# Watch pod metrics
kubectl top pods -l app=transaction-service

# Watch node metrics
kubectl top nodes

# Check Cloud Monitoring dashboard
# (CPU, memory, request rate, latency, error rate)
```

**Post-Spike:**
- [ ] Scale down resources to baseline (reduce costs)
- [ ] Review autoscaling thresholds (too aggressive? too slow?)
- [ ] Analyze cost impact
- [ ] Document lessons learned

---

### Runbook 4: Database Connection Issues

**Purpose:** Diagnose and resolve database connectivity problems

**Symptoms:**
- Logs: "Unable to acquire JDBC Connection"
- 500 errors from backend services
- Health checks failing

**Diagnosis:**

```bash
# Check service logs
kubectl logs -l app=transaction-service --tail=100 | grep -i "connection"

# Check database status
gcloud sql instances describe budget-analyzer-db --format="value(state)"

# Check connection count
gcloud sql operations list --instance=budget-analyzer-db --limit=10

# Connect to Cloud SQL via proxy
cloud_sql_proxy -instances=CONNECTION_NAME=tcp:5432 &
psql -h 127.0.0.1 -U postgres -d budget_analyzer

# Check active connections
SELECT
  count(*) AS total_connections,
  count(*) FILTER (WHERE state = 'active') AS active,
  count(*) FILTER (WHERE state = 'idle') AS idle
FROM pg_stat_activity;

# Check connection limits
SELECT setting FROM pg_settings WHERE name = 'max_connections';

# Identify long-running queries
SELECT
  pid,
  now() - pg_stat_activity.query_start AS duration,
  query,
  state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
ORDER BY duration DESC;
```

**Common Causes and Fixes:**

**Cause 1: Connection pool exhausted**
```yaml
# Increase HikariCP pool size
# application.yml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20  # Increase from 10
      connection-timeout: 30000
      leak-detection-threshold: 60000  # Detect connection leaks
```

**Cause 2: Database max_connections reached**
```sql
-- Increase max_connections (requires restart)
ALTER SYSTEM SET max_connections = 200;  -- From 100

-- Check current usage
SELECT count(*) FROM pg_stat_activity;
```

Or via gcloud:
```bash
gcloud sql instances patch budget-analyzer-db \
  --database-flags=max_connections=200
```

**Cause 3: Network connectivity (VPC peering, firewall)**
```bash
# Check VPC peering
gcloud compute networks peerings list --network=default

# Check firewall rules
gcloud compute firewall-rules list --filter="name~budget-analyzer"

# Test connectivity from GKE pod
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -- \
  psql -h CLOUD_SQL_IP -U postgres -d budget_analyzer
```

**Cause 4: Cloud SQL instance down/restarting**
```bash
# Check instance status
gcloud sql instances describe budget-analyzer-db --format="value(state)"

# Check recent operations
gcloud sql operations list --instance=budget-analyzer-db --limit=10

# Restart instance (last resort)
gcloud sql instances restart budget-analyzer-db
```

**Cause 5: Connection leak (application bug)**
```bash
# Enable connection leak detection in HikariCP
# application.yml
spring:
  datasource:
    hikari:
      leak-detection-threshold: 60000  # 60 seconds

# Check logs for leak warnings
kubectl logs -l app=transaction-service | grep "Connection leak detection"

# Identify leaking code path from stack trace
# Fix: Ensure @Transactional or try-with-resources used correctly
```

**Validation:**
```bash
# Check service health
kubectl get pods -l app=transaction-service

# Test database query
curl https://api.budgetanalyzer.com/api/v1/transactions

# Monitor connection pool metrics
# (Prometheus: hikaricp_connections_active, hikaricp_connections_max)
```

---

### Runbook 5: Session Storage (Redis) Unavailable

**Purpose:** Recover from Redis outages affecting user sessions

**Symptoms:**
- Users logged out unexpectedly
- "Session expired" errors
- 500 errors from Session Gateway
- Health checks failing

**Diagnosis:**

```bash
# Check Memorystore Redis status
gcloud redis instances describe budget-analyzer-redis \
  --region=us-central1 \
  --format="value(state)"

# Check Session Gateway logs
kubectl logs -l app=session-gateway --tail=100 | grep -i "redis"

# Test Redis connectivity from GKE pod
kubectl run -it --rm redis-test --image=redis:7-alpine --restart=Never -- \
  redis-cli -h MEMORYSTORE_IP ping
```

**Common Causes and Fixes:**

**Cause 1: Memorystore instance unavailable**
```bash
# Check instance status
gcloud redis instances describe budget-analyzer-redis \
  --region=us-central1

# Check recent operations
gcloud redis operations list --region=us-central1

# Failover to replica (Standard tier only)
gcloud redis instances failover budget-analyzer-redis \
  --region=us-central1 \
  --data-protection-mode=limited-data-loss
```

**Cause 2: Network connectivity**
```bash
# Check VPC peering
gcloud compute networks peerings list --network=default

# Check firewall rules (Redis port 6379)
gcloud compute firewall-rules list --filter="targetTags:redis"

# Test from GKE pod
kubectl run -it --rm debug --image=redis:7-alpine --restart=Never -- \
  redis-cli -h MEMORYSTORE_IP -p 6379 INFO
```

**Cause 3: Memory eviction (out of memory)**
```bash
# Check memory usage
gcloud redis instances describe budget-analyzer-redis \
  --region=us-central1 \
  --format="value(currentLocationId,memorySizeGb,redisMemoryUsage)"

# Connect and check evicted keys
redis-cli -h MEMORYSTORE_IP INFO stats | grep evicted

# Increase memory (temporary fix)
gcloud redis instances update budget-analyzer-redis \
  --size=10 \
  --region=us-central1

# Long-term: Implement TTL on sessions
# Session Gateway application.yml
spring:
  session:
    timeout: 1h  # Auto-expire sessions after 1 hour
```

**Cause 4: Session Gateway configuration error**
```yaml
# Verify Session Gateway Redis config
# application.yml
spring:
  data:
    redis:
      host: ${REDIS_HOST}  # Memorystore IP
      port: 6379
      timeout: 2000ms
      lettuce:
        pool:
          max-active: 10
          max-idle: 5
          min-idle: 2
  session:
    store-type: redis
    redis:
      namespace: spring:session
```

**Temporary Mitigation (If Redis is down):**

**Option A: Restart Session Gateway with in-memory sessions (NOT RECOMMENDED for production)**
```yaml
# Emergency only: Switch to in-memory sessions
spring:
  session:
    store-type: none  # WARNING: Sessions lost on pod restart
```

**Option B: Redirect users to login page**
```yaml
# Session Gateway: Fail gracefully
spring:
  session:
    redis:
      flush-mode: on-save
      namespace: spring:session
      configure-action: none  # Don't fail on Redis unavailable
```

**Validation:**
```bash
# Check Redis connectivity
redis-cli -h MEMORYSTORE_IP ping
# Expected: PONG

# Test session creation
curl -v -X POST https://api.budgetanalyzer.com/auth/login \
  -d '{"username":"test@example.com","password":"password"}' \
  -H "Content-Type: application/json"
# Expected: Set-Cookie: SESSION=... header

# Check session stored in Redis
redis-cli -h MEMORYSTORE_IP KEYS "spring:session:sessions:*"

# Monitor error rate (should drop to < 1%)
```

**Post-Incident:**
- [ ] Root cause analysis (why did Redis fail?)
- [ ] Review Redis memory limits and eviction policies
- [ ] Consider increasing Redis instance size
- [ ] Document session recovery procedures
- [ ] Test failover procedures regularly (quarterly)

---

## Conclusion

This deployment architecture prioritizes **portability and minimal vendor lock-in** while leveraging GCP managed services where operational burden justifies the tradeoff. The recommended stack balances cost (~$420-440/month baseline), security (Secret Manager, Cloud Armor), and operational simplicity (Cloud SQL, Memorystore) with the ability to migrate to other clouds if needed (estimated 4-6 weeks for full migration).

**Critical Success Factors:**

1. **Authentication Implementation:** Cannot deploy to production until Session Gateway + OAuth2 is complete (8 weeks)
2. **Gateway API Migration:** Must migrate from NGINX Ingress before March 2026 retirement
3. **Monitoring and Alerting:** Essential for detecting and responding to incidents
4. **Runbooks and Documentation:** Team must be prepared to handle common operational issues
5. **Cost Management:** Regular review and optimization to stay within budget

**Next Steps:**

1. Review this document with team
2. Approve deployment architecture decisions
3. Begin Phase 0 (GCP project setup)
4. Execute Phase 1 (private deployment for infrastructure testing)
5. Implement Phase 2 (authentication) in parallel
6. Plan Phase 3 (production launch) once Phase 2 is complete

**Questions or Changes:**

If requirements change (e.g., need for multi-region deployment, different cloud provider, higher scale), revisit component decisions and update this document accordingly. This is a living document that should evolve with the project.

---

**Document Version:** 1.0
**Author:** Budget Analyzer Team
**Approved By:** [TBD]
**Next Review Date:** [TBD]
