# GCP Demo Deployment Architecture - Cost-Optimized

**Status:** Draft
**Last Updated:** 2025-11-16
**Target Environment:** Google Cloud Platform (GCP)
**Use Case:** Intermittent demo deployments (~100 hours/month)
**Primary Goal:** Minimize costs for low-utilization scenarios while maintaining production-ready patterns

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Cost Analysis: Standard vs Demo Mode](#cost-analysis-standard-vs-demo-mode)
3. [Architecture Comparison](#architecture-comparison)
4. [Component Decisions](#component-decisions)
5. [Deployment Automation](#deployment-automation)
6. [Trade-offs and Considerations](#trade-offs-and-considerations)
7. [Migration Path](#migration-path)

---

## Executive Summary

### The Problem

The standard GCP deployment architecture (documented in [deployment-architecture-gcp.md](./deployment-architecture-gcp.md)) is optimized for **continuous production usage** with managed services providing high availability and operational efficiency.

However, for **demo-only deployments** running ~100 hours/month (14% uptime):
- Standard architecture costs: **~$355/month**
- Full-time architecture costs: **~$420/month**
- **You pay 85% of full-time costs for 14% uptime**

### The Solution

**Demo Mode Architecture** eliminates fixed-cost managed services and replaces them with self-hosted alternatives on GKE:

| Change | Monthly Savings | Trade-off |
|--------|----------------|-----------|
| Cloud SQL → PostgreSQL StatefulSet | -$126 | Manual backups, no automatic failover |
| Memorystore Redis → Redis StatefulSet | -$126 | Manual persistence configuration |
| GKE Standard → GKE Autopilot | -$72 | Different scaling model |
| **Total Fixed Cost Reduction** | **-$324** | **Added operational complexity** |

**New Cost Structure (100 hours/month):**
```
Fixed costs:              ~$20-25/month  (Load Balancer, Secret Manager, Cloud Run)
Variable costs:           ~$15-20/month  (Compute, bandwidth for 100 hrs)
────────────────────────────────────────
TOTAL Demo Mode:          ~$35-45/month  (87-90% savings vs standard)
```

### Key Benefits

✅ **87-90% cost reduction** for intermittent usage
✅ **Automated deploy/destroy** scripts minimize manual work
✅ **Production-ready patterns** maintained (StatefulSets, persistence, etc.)
✅ **Easy migration path** to standard architecture when usage increases

### Key Trade-offs

⚠️ **Longer startup time**: ~10-15 minutes (database restore from backup)
⚠️ **Manual operations**: Backups, monitoring, upgrades require scripting
⚠️ **No automatic HA**: Single-instance PostgreSQL/Redis (acceptable for demos)
⚠️ **Requires automation**: Must script backup/restore workflows

---

## Cost Analysis: Standard vs Demo Mode

### Monthly Cost Breakdown

| Component | Standard (24/7) | Demo Mode (100 hrs) | Savings | Notes |
|-----------|-----------------|---------------------|---------|-------|
| **Fixed Costs** |
| GKE Control Plane | $72 | $0 | $72 | Autopilot eliminates fee |
| Cloud SQL PostgreSQL | $126 | $0 | $126 | Self-hosted on GKE |
| Memorystore Redis | $126 | $0 | $126 | Self-hosted on GKE |
| Load Balancer | $18 | $18 | $0 | Required for ingress |
| Secret Manager | $2 | $2 | $0 | Required for credentials |
| **Fixed Subtotal** | **$344** | **$20** | **$324** | **94% reduction** |
| **Variable Costs** |
| GKE Compute (Autopilot) | $60 | ~$8-10 | ~$50 | Scales to zero |
| Cloud Run (Frontend) | $5-10 | ~$0.70-1.40 | ~$8 | Scales to zero |
| Bandwidth/Egress | $10-20 | ~$1.40-2.80 | ~$16 | Usage-based |
| Persistent Storage | ~$5 | ~$5 | $0 | Backups + PVs |
| **Variable Subtotal** | **$80-95** | **$15-20** | **$70** | **82% reduction** |
| **TOTAL MONTHLY COST** | **$420-440** | **$35-45** | **$385** | **87-90% savings** |

### Cost Per Hour Analysis

| Scenario | Standard (per hour) | Demo Mode (per hour) | Notes |
|----------|--------------------|--------------------|-------|
| Running (active) | ~$0.58 | ~$0.15-0.20 | Compute + bandwidth |
| Idle (shut down) | ~$0.47 | ~$0.03 | Fixed costs only |
| **100 hours/month** | **~$355** | **~$35-45** | **87% cheaper** |
| **730 hours/month (24/7)** | **~$420** | **~$135-165** | **65% cheaper** |

### Break-Even Analysis

Demo Mode is more cost-effective when:
- **Running < 300 hours/month (41% uptime)**: Demo Mode saves money
- **Running > 300 hours/month**: Standard architecture becomes competitive (managed services worth the cost)

---

## Architecture Comparison

### Standard Architecture (Managed Services)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Standard GCP Deployment                     │
│                     (Optimized for 24/7 uptime)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Internet → Cloud Armor → GCP Load Balancer                     │
│                              │                                    │
│                              ↓                                    │
│                          Gateway API                              │
│                              │                                    │
│              ┌───────────────┴───────────────┐                   │
│              ↓                               ↓                   │
│         [GKE Standard Cluster]        [Cloud Run]                │
│         (Backend Services)            (Frontend - NGINX)         │
│              │                                                    │
│              ├─→ transaction-service                             │
│              ├─→ currency-service                                │
│              └─→ rabbitmq (StatefulSet)                          │
│                                                                   │
│  Managed Services (External):                                    │
│  ├─ Cloud SQL PostgreSQL (HA)        ← $126/month               │
│  ├─ Memorystore Redis (HA)           ← $126/month               │
│  └─ Secret Manager                    ← $2/month                │
│                                                                   │
│  Fixed Monthly Cost: $344                                        │
└─────────────────────────────────────────────────────────────────┘
```

### Demo Mode Architecture (Self-Hosted on GKE)

```
┌─────────────────────────────────────────────────────────────────┐
│                      Demo Mode GCP Deployment                    │
│                   (Optimized for intermittent use)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Internet → Cloud Armor → GCP Load Balancer ($18/mo)            │
│                              │                                    │
│                              ↓                                    │
│                          Gateway API                              │
│                              │                                    │
│              ┌───────────────┴───────────────┐                   │
│              ↓                               ↓                   │
│       [GKE Autopilot Cluster]         [Cloud Run]                │
│       (All Services Self-Hosted)      (Frontend - NGINX)         │
│              │                                                    │
│              ├─→ transaction-service                             │
│              ├─→ currency-service                                │
│              ├─→ postgresql (StatefulSet)     ← Self-hosted     │
│              ├─→ redis (StatefulSet)          ← Self-hosted     │
│              └─→ rabbitmq (StatefulSet)                          │
│                                                                   │
│  Backups (Cloud Storage):                                        │
│  ├─ PostgreSQL automated backup          ← ~$1-2/month          │
│  └─ Secret Manager (credentials)         ← $2/month             │
│                                                                   │
│  Fixed Monthly Cost: ~$20-25                                     │
│  Variable Cost (100 hrs): ~$15-20                                │
│  TOTAL: ~$35-45/month                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Decisions

### 1. PostgreSQL: Cloud SQL → StatefulSet

**Decision:** Deploy PostgreSQL as a StatefulSet on GKE Autopilot

**Configuration:**
```yaml
# kubernetes/demo-mode/postgresql-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
spec:
  serviceName: postgresql
  replicas: 1  # Single instance for demo mode
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:16-alpine
        env:
        - name: POSTGRES_DB
          value: "postgres"
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-credentials
              key: password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgresql
        volumeMounts:
        - name: postgresql-data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgresql-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
      storageClassName: standard-rwo  # GKE standard persistent disk
```

**Backup Strategy:**
- **Automated**: Pre-teardown script dumps database to Cloud Storage
- **Retention**: 30-day retention for demo backups
- **Restore**: Automated restore from latest backup on deployment
- **Cost**: ~$0.02/GB/month for Cloud Storage (~$0.20-0.40/month for 10-20GB)

**Trade-offs:**
- ✅ Saves $126/month
- ✅ Standard PostgreSQL (fully portable)
- ⚠️ No automatic HA (single pod)
- ⚠️ Manual backup/restore (scripted)
- ⚠️ ~2-5 minute restore time on deployment

---

### 2. Redis: Memorystore → StatefulSet

**Decision:** Deploy Redis as a StatefulSet on GKE Autopilot

**Configuration:**
```yaml
# kubernetes/demo-mode/redis-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command:
        - redis-server
        - --appendonly yes
        - --requirepass $(REDIS_PASSWORD)
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: password
        ports:
        - containerPort: 6379
          name: redis
        volumeMounts:
        - name: redis-data
          mountPath: /data
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "250m"
        livenessProbe:
          exec:
            command:
            - redis-cli
            - --pass
            - $(REDIS_PASSWORD)
            - ping
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - --pass
            - $(REDIS_PASSWORD)
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 5Gi
      storageClassName: standard-rwo
```

**Persistence Strategy:**
- **AOF (Append-Only File)**: Enabled for durability
- **Backup**: Optional (cache data is ephemeral, sessions can be recreated)
- **Restore**: Fresh start acceptable for demos (no user sessions to preserve)

**Trade-offs:**
- ✅ Saves $126/month
- ✅ Standard Redis protocol (fully portable)
- ✅ Minimal operational overhead (cache/session data is ephemeral)
- ⚠️ No automatic HA
- ⚠️ Sessions lost on teardown (acceptable for demos)

---

### 3. GKE: Standard → Autopilot

**Decision:** Use GKE Autopilot instead of Standard to eliminate $72/month control plane fee

**Configuration:**
```bash
gcloud container clusters create-auto budget-analyzer-demo \
  --region=us-central1 \
  --release-channel=regular \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=10
```

**Benefits:**
- ✅ **No control plane fee** ($72/month savings)
- ✅ **Scales to zero**: No compute costs when idle
- ✅ **Fully managed**: Automatic upgrades, security patches
- ✅ **Per-pod billing**: Pay only for pod resources requested

**Trade-offs:**
- ⚠️ Less control over node configuration
- ⚠️ Cannot use DaemonSets or HostPath volumes
- ⚠️ Pod resource requests must be within Autopilot limits
- ✅ For demo workloads, these limitations are acceptable

**Cost Comparison (100 hours/month):**
- Standard: $72 fixed + $60 compute = $132/month → ~$18/month for 100 hrs
- Autopilot: $0 fixed + pod resources → ~$8-10/month for 100 hrs

---

### 4. Components Unchanged

These components remain the same in both architectures:

| Component | Cost | Reason |
|-----------|------|--------|
| **GCP Load Balancer** | $18/month | Required for HTTPS ingress |
| **Secret Manager** | $2/month | Required for secure credential storage |
| **Cloud Run (Frontend)** | ~$1-2/month | Scales to zero, minimal cost |
| **RabbitMQ** | Included | Already runs on GKE (no managed service) |
| **Cloud Armor** | Optional | Can add for DDoS protection (~$10-15/month) |

---

## Deployment Automation

### Automated Deployment Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   Deployment Workflow                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. Run: ./scripts/gcp-demo-deploy.sh                       │
│     ↓                                                         │
│  2. Create GKE Autopilot cluster (~5 min)                   │
│     ↓                                                         │
│  3. Deploy StatefulSets (PostgreSQL, Redis, RabbitMQ)       │
│     ↓                                                         │
│  4. Restore PostgreSQL from latest Cloud Storage backup     │
│     ↓                                                         │
│  5. Deploy backend services (transaction, currency)         │
│     ↓                                                         │
│  6. Deploy frontend (Cloud Run)                             │
│     ↓                                                         │
│  7. Configure Gateway API + Load Balancer                   │
│     ↓                                                         │
│  ✅ Ready in ~10-15 minutes                                  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Automated Teardown Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   Teardown Workflow                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. Run: ./scripts/gcp-demo-teardown.sh                     │
│     ↓                                                         │
│  2. Backup PostgreSQL to Cloud Storage                      │
│     ↓                                                         │
│  3. Delete GKE cluster (all services destroyed)             │
│     ↓                                                         │
│  4. Delete Load Balancer + Gateway API                      │
│     ↓                                                         │
│  5. Retain: Backups, Secret Manager, Cloud Run (stopped)    │
│     ↓                                                         │
│  ✅ Complete in ~3-5 minutes                                 │
│     Monthly cost reduced to ~$2-5 (storage + secrets only)  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Scripts Overview

| Script | Purpose | Duration |
|--------|---------|----------|
| `gcp-demo-deploy.sh` | Full deployment from scratch | ~10-15 min |
| `gcp-demo-teardown.sh` | Complete teardown with backup | ~3-5 min |
| `gcp-demo-backup.sh` | Manual PostgreSQL backup | ~1-2 min |
| `gcp-demo-restore.sh` | Manual PostgreSQL restore | ~2-5 min |
| `gcp-demo-cost-estimate.sh` | Preview estimated costs | <1 min |

---

## Trade-offs and Considerations

### When to Use Demo Mode

✅ **Use Demo Mode when:**
- Running < 300 hours/month (41% uptime)
- Demo/staging environments only
- Development/testing workloads
- Cost is primary concern
- Acceptable to have 10-15 minute startup time
- No SLA requirements

❌ **Do NOT use Demo Mode when:**
- Running > 300 hours/month (standard is cheaper)
- Production workloads requiring HA
- SLA requirements (99.9% uptime)
- Real-time user sessions must persist
- Can't tolerate 10-15 minute startup delays

### Operational Complexity

| Task | Standard Architecture | Demo Mode | Complexity Delta |
|------|----------------------|-----------|------------------|
| Deploy from scratch | Manual Terraform | Run script | ✅ Simpler |
| Teardown | Delete resources manually | Run script | ✅ Simpler |
| Database backup | Automatic (Cloud SQL) | Scripted (pre-teardown) | ⚠️ More complex |
| Database restore | Automatic failover | Scripted (on deploy) | ⚠️ More complex |
| Monitoring | Cloud Monitoring | Self-hosted Prometheus | ⚠️ More complex |
| Upgrades | Automatic (managed) | Manual kubectl apply | ⚠️ More complex |
| Scaling | Automatic (managed) | Manual StatefulSet edit | ⚠️ More complex |

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Data loss on teardown | Low | High | Automated backup script + validation |
| Backup restore failure | Low | High | Test restore on every deployment |
| StatefulSet pod crash | Medium | Medium | Persistent volumes + restart policy |
| Backup storage costs grow | Medium | Low | 30-day retention policy + lifecycle rules |
| Manual operation errors | Medium | Medium | Automation scripts + documentation |

---

## Migration Path

### Demo Mode → Standard Architecture

When usage increases (> 300 hours/month), migrate to standard architecture:

1. **Deploy standard architecture in parallel**
   - Create Cloud SQL instance
   - Create Memorystore Redis instance
   - Keep GKE Autopilot (or migrate to Standard)

2. **Migrate data**
   - Export from PostgreSQL StatefulSet
   - Import to Cloud SQL
   - Update service configurations to point to Cloud SQL

3. **Switch traffic**
   - Update backend services to use Cloud SQL/Redis endpoints
   - Verify functionality
   - Delete StatefulSets

4. **Estimated migration time:** 2-4 hours (mostly database migration)

### Standard Architecture → Demo Mode

If usage decreases, downgrade to demo mode:

1. **Backup Cloud SQL data**
   - Use Cloud SQL export to Cloud Storage

2. **Deploy demo mode architecture**
   - Run `gcp-demo-deploy.sh`
   - Restore from Cloud SQL backup

3. **Delete managed services**
   - Delete Cloud SQL instance
   - Delete Memorystore instance

4. **Estimated migration time:** 1-2 hours

---

## Next Steps

1. ✅ Review this architecture document
2. ⚠️ Implement deployment automation scripts
3. ⚠️ Create Kubernetes manifests (StatefulSets)
4. ⚠️ Test deploy → teardown → deploy cycle
5. ⚠️ Document operational runbooks
6. ⚠️ Set up cost monitoring/alerting

---

## Appendix: Cost Calculation Details

### Autopilot Pricing (100 hours/month)

**Pod Resources Required:**
- transaction-service: 512Mi RAM, 250m CPU
- currency-service: 512Mi RAM, 250m CPU
- postgresql: 1Gi RAM, 500m CPU
- redis: 512Mi RAM, 100m CPU
- rabbitmq: 512Mi RAM, 250m CPU

**Total:** ~3.5Gi RAM, 1.35 vCPU

**Autopilot Costs (us-central1):**
- vCPU: $0.0445/vCPU-hour
- RAM: $0.0049/GB-hour

**Monthly cost (100 hours):**
- vCPU: 1.35 × $0.0445 × 100 = $6.00
- RAM: 3.5 × $0.0049 × 100 = $1.72
- **Total compute: ~$7.72/month**

**With overhead (monitoring, etc.):** ~$10-12/month

### Cloud Storage Backup Costs

**Assumptions:**
- Database size: 10-20GB (compressed ~5-10GB)
- Retention: 30 days
- Daily backups: 30 snapshots

**Costs:**
- Storage: $0.02/GB/month
- 30 backups × 8GB average = 240GB
- **Total: 240GB × $0.02 = $4.80/month**

**Retrieval (restore):**
- Class A operations (restore): $0.05 per 1,000 operations (~negligible)
- Egress: Free (same region)

---

**Document Version:** 1.0
**Author:** Claude Code
**Last Reviewed:** 2025-11-16
