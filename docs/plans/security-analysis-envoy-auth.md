# Security Analysis: envoy-auth Branch

## Context

Analysis of the `envoy-auth` branch which introduces Istio service mesh with mTLS and replaces JWT-based auth with Envoy ext_authz + Redis sessions. Goal: verify the mTLS implementation and identify security gaps, particularly for infrastructure services (Redis, PostgreSQL, RabbitMQ).

**This is an analysis document — no implementation. Findings serve as a backlog.**

---

## mTLS Verification: Correctly Implemented

The branch correctly introduces Istio mTLS for all application services in the `default` namespace:

| Layer | Mechanism | File |
|-------|-----------|------|
| Mesh-wide mTLS | `PeerAuthentication` STRICT mode | `kubernetes/istio/peer-authentication.yaml` |
| Per-service access control | `AuthorizationPolicy` per service | `kubernetes/istio/authorization-policies.yaml` |
| Service identity | `ServiceAccount` per service (7 new files) | `kubernetes/services/*/serviceaccount.yaml` |
| Envoy Gateway excluded from mesh (correct — edge ingress doesn't need sidecar) | `sidecar.istio.io/inject: "false"` on proxy pod | `kubernetes/gateway/envoy-proxy-config.yaml:13` |
| Anti-header-spoofing | ext_authz strips + replaces identity headers | `ext-authz/server.go:145` |
| Fail-closed auth | `failOpen: false` on SecurityPolicy | `kubernetes/gateway/ext-authz-security-policy.yaml:12` |

**Authorization topology** (who can call whom):

```
Browser → Envoy (:443)
           ├── ext_authz ← envoy-gateway SA only
           ├── session-gateway ← envoy-gateway SA only
           └── nginx-gateway ← envoy-gateway SA only
                 ├── transaction-service ← nginx-gateway SA only
                 ├── currency-service ← nginx-gateway SA only
                 ├── permission-service ← nginx-gateway SA + session-gateway SA
                 └── budget-analyzer-web ← nginx-gateway SA only
```

This is correct. Each service only accepts traffic from its legitimate upstream caller.

---

## Security Gaps

### 1. Infrastructure Services Are Outside the Mesh — By Design, But Unsecured

`istio-injection=disabled` for the infrastructure namespace (Tiltfile line ~585). This is **correct** — in the cloud, you'd use managed services (RDS, ElastiCache, Amazon MQ) with native TLS and VPC isolation, not mesh sidecars.

The gap is that the localhost environment doesn't replicate the security those managed services provide:

| Cloud Managed Service | What It Provides | Localhost Equivalent | Current State |
|----------------------|------------------|---------------------|---------------|
| RDS / Cloud SQL | TLS in transit, IAM auth, VPC isolation, per-service users | PG native SSL, K8s Secrets, NetworkPolicies, per-DB users | **None of these** |
| ElastiCache / Memorystore | TLS in transit, AUTH/ACLs, private subnet | Redis `--tls-*` flags, AUTH, NetworkPolicies | **AUTH only** (password added, TLS disabled) |
| Amazon MQ / CloudAMQP | TLS listeners, strong credentials, private endpoints | RabbitMQ TLS config, K8s Secrets, NetworkPolicies | **None of these** |

### 2. PostgreSQL Credentials Hardcoded in Manifest

`kubernetes/infrastructure/postgresql/statefulset.yaml:28-29`:
```yaml
- name: POSTGRES_USER
  value: "budget_analyzer"
- name: POSTGRES_PASSWORD
  value: "budget_analyzer"
```

- Not using K8s Secrets (visible in `kubectl describe`, git history)
- Username = password
- Single shared user for all three databases

**Cloud equivalent**: RDS creates credentials in Secrets Manager, each service gets its own IAM-based or password-based user with grants only to its database.

### 3. RabbitMQ Default Credentials

`kubernetes/infrastructure/rabbitmq/configmap.yaml:10-11`:
```
default_user = guest
default_pass = guest
```

`guest/guest` is the well-known RabbitMQ default. Any pod that can reach port 5672 can authenticate.

**Cloud equivalent**: Amazon MQ generates credentials, stores in Secrets Manager, private VPC endpoints only.

### 4. No Network Isolation for Infrastructure

No Kubernetes NetworkPolicies exist anywhere in the cluster. Any pod can reach Redis, PostgreSQL, or RabbitMQ directly.

**Cloud equivalent**: VPC security groups restrict which compute resources can reach which data stores. Only the specific services that need a database can connect to it.

### 5. Redis TLS Disabled

`ext-authz/deployment.yaml:39`: `REDIS_TLS=false`. The Go code already supports TLS (`ext-authz/session.go:44-46`), it's just not enabled. Combined with no network isolation, session data traverses the pod network in plaintext.

### 6. No Rate Limiting on Auth Endpoints

Auth routes (`/login`, `/oauth2`, `/auth`, `/logout`) go Envoy → Session Gateway directly via `auth-httproute.yaml`, bypassing NGINX. NGINX's `limit_req` zones only cover `/api` routes. Login attempts are unlimited.

**Cloud equivalent**: WAF or API Gateway rate limiting on auth endpoints.

---

## Recommended Backlog (Production Parity)

Ordered by impact, framed as "mimic what managed cloud services give you":

### Tier 1: Credentials Hygiene
1. **PostgreSQL credentials → K8s Secrets** (like Redis already does)
2. **RabbitMQ credentials → K8s Secrets** with non-default username/password
3. **Per-service database users** in `01-init-databases.sql` — each service gets its own user with `GRANT` only to its database

### Tier 2: Network Isolation (Mimic VPC Security Groups)
4. **Kubernetes NetworkPolicies** restricting infrastructure access:
   - Redis ← ext-authz, session-gateway only
   - PostgreSQL ← transaction-service, currency-service, permission-service only
   - RabbitMQ ← transaction-service, currency-service only

### Tier 3: Transport Encryption (Mimic Managed TLS)
5. **Redis native TLS** — enable `--tls-port 6379 --tls-cert-file --tls-key-file`, flip `REDIS_TLS=true` in ext-authz
6. **PostgreSQL native SSL** — enable `ssl = on` in postgresql.conf, clients use `sslmode=require`
7. **RabbitMQ TLS** — enable TLS listener on port 5671

### Tier 4: Application-Level Gaps
8. **Rate limiting on auth endpoints** — Envoy RateLimit filter or route auth through NGINX
9. **Stronger default Redis password** — generate randomly in `setup.sh`

---

## What's Already Right

- Istio STRICT mTLS for all application services
- Granular AuthorizationPolicies matching the real call graph
- Distroless nonroot container for ext-authz
- ext_authz anti-spoofing (strips + replaces identity headers)
- failOpen: false
- Redis AUTH added (vs none on main)
- Envoy Gateway correctly excluded from mesh (`sidecar.istio.io/inject: "false"`)
- Infrastructure outside mesh (correct — matches cloud pattern)
