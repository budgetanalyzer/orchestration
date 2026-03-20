# Security Hardening Plan v2

## Context

Revised security hardening plan for the orchestration repository, incorporating review feedback and additional repository validation.

Key corrections from v1:

- **Header spoofing (external)**: Already mitigated by ext_authz `headersToBackend` allowlist. Envoy replaces client-supplied identity headers before forwarding to NGINX.
- **Istio AuthorizationPolicy on ingress-facing services**: Not feasible in the current topology. Envoy Gateway is outside the Istio mesh and has no SPIFFE identity.
- **Internal service TLS**: Still feasible, but it must be treated as host-side certificate generation for pod-to-pod trust, not browser trust.

Additional execution assumptions for this repository:

- This app is unreleased. Hardening can assume a **destructive rebuild** of local stateful workloads and volumes instead of in-place migration.
- This plan addresses **orchestration-layer controls**: trust boundaries, credential segmentation, network isolation, transport security, pod hardening, and edge hardening.
- This plan does **not** solve service/domain authorization questions such as "can user X view transaction Y?" That remains a sibling-service concern.

The in-cluster bypass risk remains the primary orchestration-layer gap:

```text
Compromised pod -> nginx-gateway:8080 directly -> spoofed X-User-Id/X-Roles/X-Permissions
```

That path is addressed primarily by NetworkPolicies in Phase 2.

---

## Phase 1: Credential Hardening

### 1a. Per-service PostgreSQL users

Create dedicated DB users with grants scoped to their own database only:

- `transaction_service` -> `budget_analyzer`
- `currency_service` -> `currency`
- `permission_service` -> `permission`

Files to modify:

- `kubernetes/infrastructure/postgresql/configmap.yaml` - init script creates 3 users with per-DB grants
- `Tiltfile` - generate 3 separate credential secrets instead of one shared secret
- `kubernetes/services/transaction-service/deployment.yaml` - reference `transaction-db-credentials`
- `kubernetes/services/currency-service/deployment.yaml` - reference `currency-db-credentials`
- `kubernetes/services/permission-service/deployment.yaml` - reference `permission-db-credentials`

Rollout note:

- Because the project is unreleased, the supported rollout is to recreate PostgreSQL state from scratch after changing the init scripts and secrets.

### 1b. Per-service RabbitMQ users and permissions

Remove `guest/guest`. Create **one RabbitMQ user per service**, not one shared "app user."

Target model:

- `transaction-service` user with only the write/read permissions it needs
- `currency-service` user with only the write/read permissions it needs

Broker scoping approach:

- Prefer separate vhosts if the event topology stays simple
- If a shared vhost is required for exchange bindings, still use separate users with scoped `configure`, `write`, and `read` permissions for the required exchanges/queues only

Files to modify:

- `kubernetes/infrastructure/rabbitmq/configmap.yaml` - define users, vhosts, and permissions
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml` - mount credentials/config
- `Tiltfile` - generate RabbitMQ credentials from env vars with strong defaults
- Service deployments for transaction-service and currency-service - reference service-specific RabbitMQ secrets

Rollout note:

- Because the project is unreleased, the supported rollout is to recreate RabbitMQ state from scratch after changing broker configuration.

### 1c. Per-service Redis ACL users

Replace the single shared Redis password with **Redis ACL users** for each Redis consumer:

- `session-gateway`
- `ext-authz`
- `currency-service`

Scope access by key namespace where feasible:

- `session-gateway`: read/write Spring Session keys and ext_authz session keys
- `ext-authz`: read-only access to ext_authz session keys
- `currency-service`: access only its cache namespace

Files to modify:

- New file: `kubernetes/infrastructure/redis/configmap.yaml` - Redis ACL configuration
- `kubernetes/infrastructure/redis/deployment.yaml` - mount ACL config
- `Tiltfile` - generate service-specific Redis credentials from env vars with strong defaults
- `kubernetes/services/ext-authz/deployment.yaml` - add Redis username/password
- `kubernetes/services/session-gateway/deployment.yaml` - add Redis username/password
- `kubernetes/services/currency-service/deployment.yaml` - add Redis username/password
- `setup.sh` - generate strong random defaults in `.env` if not set

---

## Phase 2: Network Isolation

Default-deny NetworkPolicies for both namespaces, plus explicit allowlists. This is the primary control for the in-cluster bypass gap.

### 2a. Default namespace policies

New file: `kubernetes/network-policies/default-deny.yaml`

New file: `kubernetes/network-policies/default-allow.yaml`

Allow rules:

- `nginx-gateway` <- Envoy Gateway proxy pods only
- `ext-authz` <- Envoy Gateway proxy pods only
- `session-gateway` <- Envoy Gateway proxy pods only
- `nginx-gateway` -> backend services, budget-analyzer-web
- `session-gateway` -> Redis, permission-service, external HTTPS to the configured identity provider
- `ext-authz` -> Redis
- `transaction-service` -> PostgreSQL, RabbitMQ
- `currency-service` -> PostgreSQL, RabbitMQ, Redis, external HTTPS to FRED
- `permission-service` -> PostgreSQL
- All pods -> DNS

Implementation notes:

- Do not rely on namespace name strings alone. Match the Envoy Gateway namespace via namespace labels that are actually present, or use `kubernetes.io/metadata.name` if supported by the cluster/CNI.
- Prefer pod label selectors in addition to namespace selectors so "Envoy Gateway namespace" does not implicitly trust every pod in that namespace.

### 2b. Infrastructure namespace policies

New file: `kubernetes/network-policies/infrastructure-deny.yaml`

New file: `kubernetes/network-policies/infrastructure-allow.yaml`

Allow rules:

- `redis` <- `session-gateway`, `ext-authz`, `currency-service` only
- `postgresql` <- `transaction-service`, `currency-service`, `permission-service` only
- `rabbitmq` <- `transaction-service`, `currency-service` only
- Infrastructure pods -> DNS only, unless a concrete exception is required

### 2c. Tiltfile integration and verification

Add NetworkPolicy manifests to Tiltfile so they are applied during `tilt up`.

Add repeatable verification scripts:

- Temporary unauthorized pod in `default` cannot reach `nginx-gateway:8080`
- Temporary unauthorized pod cannot reach Redis/PostgreSQL/RabbitMQ
- Authorized service paths remain functional

---

## Phase 3: In-cluster Transport Encryption

Apply this phase **after** Phase 2. Network isolation closes the largest gap first.

Certificate constraints:

- Internal certs must be generated by a **host-side script** invoked by the user, not inside the container sandbox
- Browser trust is irrelevant for this phase; these certs are only for pod-to-pod traffic
- Keep internal service certs separate from the wildcard browser cert material unless there is a strong reason to share issuance

### 3a. Redis TLS

Highest-value transport-encryption target because it carries session and identity data.

Files to modify:

- `scripts/dev/setup-k8s-tls.sh` - generate internal cert for Redis and create K8s secret in `infrastructure`
- `kubernetes/infrastructure/redis/deployment.yaml` - enable Redis TLS listener and mount certs
- `kubernetes/services/ext-authz/deployment.yaml` - set `REDIS_TLS=true`, mount CA cert, add username/password config
- `kubernetes/services/session-gateway/deployment.yaml` - enable Spring Redis SSL and mount trust material
- `kubernetes/services/currency-service/deployment.yaml` - enable Spring Redis SSL and mount trust material

### 3b. RabbitMQ TLS

Files to modify:

- `scripts/dev/setup-k8s-tls.sh` - generate internal cert for RabbitMQ and create K8s secret
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml` - enable TLS listener and mount certs
- `kubernetes/infrastructure/rabbitmq/configmap.yaml` - add TLS configuration
- Service deployments for transaction-service and currency-service - enable Spring RabbitMQ SSL and mount trust material

### 3c. PostgreSQL TLS

Files to modify:

- `scripts/dev/setup-k8s-tls.sh` - generate internal cert for PostgreSQL and create K8s secret
- `kubernetes/infrastructure/postgresql/statefulset.yaml` - enable PostgreSQL SSL and mount certs
- `Tiltfile` - generate JDBC URLs/config for TLS
- Service deployments - mount CA/trust material

Security requirement:

- If the goal is authenticated TLS, use certificate verification with hostname validation (for example `verify-full` semantics with certs matching `postgresql.infrastructure`)
- Do **not** describe `sslmode=require` as full server authentication; that is encryption-only

Cross-repo note:

- Spring Boot services may need mounted trust material and JVM/application SSL properties, but this should still be achievable through orchestration and configuration rather than service code changes

---

## Phase 4: Runtime Hardening

### 4a. Pod securityContext baseline

Apply a common baseline to **all compatible workloads**:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

Use `readOnlyRootFilesystem: true` only where validated. Do not force it onto infra/stateful workloads without testing.

Execution order:

- Start with Spring Boot services and ext-authz
- Validate NGINX separately
- Validate PostgreSQL, Redis, and RabbitMQ individually and document any exceptions

Files to modify:

- `kubernetes/services/nginx-gateway/deployment.yaml`
- `kubernetes/services/ext-authz/deployment.yaml`
- `kubernetes/services/transaction-service/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`
- `kubernetes/services/permission-service/deployment.yaml`
- `kubernetes/services/session-gateway/deployment.yaml`
- `kubernetes/services/budget-analyzer-web/deployment.yaml`
- `kubernetes/infrastructure/postgresql/statefulset.yaml`
- `kubernetes/infrastructure/redis/deployment.yaml`
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`

### 4b. Service account token automount

Set `automountServiceAccountToken: false` on all service accounts and pod specs that do not need Kubernetes API access.

Expected scope in this architecture:

- All application and infrastructure workloads should default to `false` unless a concrete Kubernetes API dependency is introduced later

Files to modify:

- All `serviceaccount.yaml` files under `kubernetes/services/*/`
- Any workload manifests that need explicit pod-level `automountServiceAccountToken: false`

---

## Phase 5: Edge and Browser Hardening

### 5a. CSP: dev/prod split

Add a production-ready CSP that removes `unsafe-inline` and `unsafe-eval`, while preserving a looser dev profile for Vite/HMR.

Files to modify:

- `nginx/nginx.k8s.conf` - conditional CSP based on `$csp_mode`
- `kubernetes/services/nginx-gateway/deployment.yaml` - add `CSP_MODE` env var (default: `dev`)
- `docs/architecture/security-architecture.md` - document prod and dev CSP behavior

### 5b. CORS on docs endpoint

Remove wildcard CORS on docs assets unless a concrete cross-origin requirement exists. Same-origin is the default architecture here.

File to modify:

- `nginx/nginx.k8s.conf`

### 5c. Auth endpoint rate limiting at Envoy Gateway

Auth paths route through Envoy directly to Session Gateway, not through NGINX. Rate limiting for auth-sensitive paths belongs at the Envoy layer.

Target:

- Add route-level rate limiting for `/auth/*`, `/login/*`, `/oauth2/*`, `/logout`, and `/user`
- Prefer **local rate limiting first** for the current single-replica dev topology
- Add global/distributed rate limiting only if Envoy Gateway scaling or product requirements justify the extra complexity

Files to modify:

- New file: `kubernetes/gateway/auth-rate-limit-policy.yaml`

### 5d. API rate-limiting identity review

Current NGINX rate limiting uses the connection source address. Because NGINX sits behind Envoy, validate that limits are keyed on the intended client identity rather than the Envoy proxy IP.

Options:

- Configure trusted real-IP handling in NGINX for Envoy-forwarded headers
- Or move edge-facing rate limiting to Envoy where client identity is already known at the ingress boundary

Files to modify:

- `nginx/nginx.k8s.conf`
- `docs/architecture/security-architecture.md`

---

## Phase 6: Supply Chain and Guardrails

### 6a. Pin external images and base images

Pin third-party runtime images and build base images to concrete patch-level tags.

Scope:

- Infrastructure images: PostgreSQL, Redis, RabbitMQ, NGINX
- Build/runtime base images referenced from Tiltfile and Dockerfiles

Note:

- Local service images tagged `:latest` by Tilt are local build artifacts, not remote floating dependencies. The supply-chain risk is in their base images, not the local tag itself.

### 6b. Install script hardening

Replace pipe-to-shell installer hints with checksum-verified download instructions where possible.

File to modify:

- `scripts/dev/check-tilt-prerequisites.sh`

### 6c. Manifest guardrails

Add repeatable local/CI validation for:

- required securityContext fields
- `automountServiceAccountToken: false`
- absence of default credentials
- image pinning for third-party dependencies
- presence of required NetworkPolicies

---

## Future Work (Separate Plan): Istio Gateway API Migration

Not part of this plan, but still the cleanest long-term architecture:

- Replace Envoy Gateway with Istio's native Gateway API controller
- Ingress proxy becomes a mesh workload with SPIFFE identity
- Ingress-facing services move from PERMISSIVE to STRICT mTLS
- AuthorizationPolicies apply everywhere
- NetworkPolicies remain as defense in depth

This removes the "non-mesh ingress talking to mesh workloads" seam. Until then, NetworkPolicies are the correct orchestration-layer control.

---

## Cross-Repo Dependencies

Most changes remain orchestration-only. Expected sibling-repo coordination:

- Local-dev defaults in service `application.yml` files should be updated for consistency with new credentials
- TLS phases may require mounted trust material and SSL property wiring through environment/config
- CSP tightening may require frontend adjustments if production mode removes unsafe directives

No service business-logic changes are implied by this plan.

---

## Verification

1. **Clean rebuild**: destructive rebuild from empty state succeeds after credential and TLS changes
2. **Credential isolation**: each PostgreSQL/RabbitMQ/Redis credential can only access its intended resource scope
3. **Network isolation**: temporary unauthorized pod in `default` cannot reach `nginx-gateway:8080` or infra services
4. **Header spoofing**: bypass pod calling nginx-gateway directly with spoofed identity headers is blocked by policy
5. **TLS**: Redis/RabbitMQ/PostgreSQL reject plaintext where TLS is enabled and accept trusted TLS clients
6. **Rate limiting**: auth endpoints are limited at Envoy; API limits use intended client identity
7. **Pod hardening**: workloads meet baseline or have explicit documented exceptions
8. **Regression**: `tilt up`, login flow, core API flows, docs routes, and startup health checks all remain functional

---

## Residual Risk Outside Orchestration

This plan can harden:

- caller identity provenance at the ingress/gateway boundary
- least-privilege infra credentials
- network reachability
- pod runtime restrictions
- transport encryption

This plan cannot decide business ownership rules inside services.

Examples of residual service/domain concerns:

- whether `transaction-service` filters every query by the authenticated user
- whether a user can only see their own transactions
- how organization-level isolation or multi-tenancy is enforced

If a backend service receives a correctly authenticated `X-User-Id` header and still returns someone else's data, that is a service/domain authorization defect, not an orchestration defect.
