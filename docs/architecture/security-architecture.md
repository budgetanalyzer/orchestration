# Financial Application Security Architecture
## Design Document

**Version:** 2.0
**Date:** April 22, 2026
**Status:** Active

---

## Executive Summary

This document outlines the security architecture for a financial data application requiring maximum security to prevent unauthorized data access. The architecture implements defense-in-depth principles with clear separation of concerns across multiple security layers while maintaining identity provider independence.

Repository security posture:
- Ingress, session, and routing follow the topology described here.
- Platform security prerequisites: Kind uses Calico instead of `kindnet`, Kyverno is installed and verifiable, the retained smoke policy proves admission is alive, and the checked-in security guardrail suite enforces namespace PSA labels, workload token/`securityContext` baselines, obvious default-credential rejection, and third-party image-digest pinning with narrow system-workload exceptions.
- Credential isolation: per-service PostgreSQL, RabbitMQ, and Redis credentials with dedicated Kubernetes secrets.
- Network policies: `default`, `infrastructure`, `istio-ingress`, `istio-egress`, and `monitoring` namespaces have repo-owned deny-by-default ingress and egress with explicit allowlists. The `monitoring` namespace has its own baseline for Grafana, Prometheus, Kiali-to-Prometheus/Jaeger/Kubernetes API/Istiod-version flows, and OTLP ingress to Jaeger from approved namespaces. Only documented pod callers can reach each service. Kubelet probes and Tilt port-forwards are host-to-pod traffic and still rely on Calico's default host endpoint handling (`defaultEndpointToHostAction=Accept`), not the pod-to-pod allowlists.
- Istio ingress and egress manifests describe the intended topology: Envoy Gateway is replaced by an Istio-managed ingress gateway (inside the mesh with SPIFFE identity). Istio egress routes approved outbound traffic (Auth0, FRED API) with `REGISTRY_ONLY` blocking unapproved hosts. All ingress-facing services use STRICT mTLS and ingress-scoped `AuthorizationPolicy` rules, with one documented exception: `permission-service` may call Session Gateway only for `DELETE /internal/v1/sessions/users/{userId}` bulk revocation. Auth-sensitive paths are throttled at Istio ingress; backend API throttling remains at NGINX.
- Istio CNI runtime hardening: Tilt installs Istio CNI, enables `pilot.cni.enabled=true` for `istiod`, and reinjects existing `default` namespace workloads so new sidecar pods do not require `istio-init`.
- Non-root application workload hardening: `session-gateway`, `currency-service`, `transaction-service`, `permission-service`, and `ext-authz` disable service-account token automount, set pod `seccompProfile.type: RuntimeDefault`, and apply the planned container hardening. The Spring Boot services also mount `/tmp` and run read-only as UID/GID `1001`.
- Gateway workload hardening on the refreshed Istio `1.29.2` baseline: the auto-provisioned ingress gateway receives pod `seccompProfile.type: RuntimeDefault`, fixed NodePort ownership, and explicit service-account token retention through Gateway `spec.infrastructure.parametersRef`, and the egress gateway installs directly from the `istio/gateway` chart using checked-in values that keep `service.type=ClusterIP`, preserve the low-port binding sysctl needed by the non-root proxy, and add pod-level seccomp hardening. The ingress gateway intentionally keeps its Kubernetes API token mount for TLS secret watching, while the egress gateway currently keeps the chart-managed token behavior because this repo does not add a separate post-render patch just to remove it.
- `nginx-gateway` runtime hardening: the Deployment and ServiceAccount disable service-account token automount, the pod sets `seccompProfile.type: RuntimeDefault`, the container runs as UID/GID `101` from `nginxinc/nginx-unprivileged:1.29.4-alpine`, `readOnlyRootFilesystem: true` is enabled, and the gateway relies on an explicit writable `/tmp` mount while logging to stdout/stderr.
- Frontend runtime hardening across the orchestration and `budget-analyzer-web` repos: the frontend dev image runs Vite as UID/GID `1001`, the Kubernetes Deployment and ServiceAccount disable service-account token automount, the pod sets `seccompProfile.type: RuntimeDefault`, the container pins `runAsUser`/`runAsGroup` to `1001`, and the container applies the planned non-root baseline without forcing `readOnlyRootFilesystem` before the HMR workflow is proven on explicit writable paths.
- Redis runtime hardening: the Deployment disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, runs Redis as UID `999` / GID `1000` with a read-only root filesystem, and mounts explicit writable `emptyDir` paths for ACL bootstrap (`/tmp`) and local-dev AOF output (`/data`). That AOF storage remains intentionally ephemeral in local development; production persistence would require a PVC-backed replacement.
- PostgreSQL runtime hardening: the StatefulSet disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, pins pod and container ownership to UID/GID `70`, hardens the TLS-prep init container to the same ownership with `readOnlyRootFilesystem: true`, and keeps the main container `readOnlyRootFilesystem: true` compatible through explicit writable mounts at `/tmp` and `/var/run/postgresql`.
- RabbitMQ runtime hardening: the StatefulSet disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, runs the broker as UID/GID `999` with `fsGroup: 999`, and enables `readOnlyRootFilesystem: true` while keeping `/var/lib/rabbitmq` as the explicit PVC-backed writable path and leaving config, definitions, and TLS mounts read-only.
- Pod Security namespace enforcement: the checked-in namespace manifests declare the Pod Security `enforce` labels for `infrastructure`, `istio-ingress`, and `istio-egress`, while Tilt reapplies the `default`, `infrastructure`, and `istio-system` labels during reconciliation.
- Runtime-hardening verifier: `./scripts/smoketest/verify-phase-5-runtime-hardening.sh --regression-timeout 8m` checks the runtime-hardening baseline, including the frontend UID/GID assertions plus the PostgreSQL init-container baseline assertions. The verifier reruns remain bounded per script so failures surface instead of hanging indefinitely.
- Production-smoke frontend bundle path: Tilt runs the sibling frontend `build:prod-smoke` target, packages the resulting `dist/` bundle into a local static-asset image, and `nginx-gateway` serves that bundle at `/_prod-smoke/` through a non-root init-container copy step while `/` and `/login` remain on the Vite/HMR dev route.
- `/api-docs` security posture: the docs surface stays same-origin, read-only, and isolated behind its own docs-only CSP carve-out instead of weakening the main app or `/api/*` routes. Exact docs-surface behavior and generated outputs live in [../../docs-aggregator/README.md](../../docs-aggregator/README.md).
- Frontend strict-CSP audit: `./scripts/smoketest/audit-phase-6-session-3-frontend-csp.sh` rebuilds the sibling production-smoke bundle and checks the repo-owned strict-CSP prerequisites. The static audit passes after the sibling frontend removed the inline-style and `sonner` blockers. Manual browser-console validation is still required.
- Frontend-owned `/login` auth-path throttle: the ingress auth-path local rate limit explicitly covers the entry point, including query-string variants, while keeping `/login` routed through NGINX and leaving `/login/oauth2/*` on Session Gateway. The Istio ingress verifier proves both the low-rate frontend response and the ingress `429` marker on `/login`.
- API rate-limit identity proof: before enabling `real_ip_*`, the live NGINX capture showed `remote_addr=127.0.0.6`, `xff="<caller>,<downstream-hop>"`, and `xrealip="-"`, which proved the trust anchor is the pod-local Envoy sidecar hop rather than a guessed cluster CIDR. `nginx-gateway` trusts only `127.0.0.0/8` for `real_ip_header X-Forwarded-For`, keeps `real_ip_recursive on`, logs both the derived client identity and the trusted proxy hop, and therefore keys API `limit_req` buckets on the ingress-appended downstream client hop instead of the proxy sidecar address. `./scripts/smoketest/verify-phase-6-session-7-api-rate-limit-identity.sh` proves forged external `X-Forwarded-For` values cannot pick a new bucket and that different downstream clients do not share one bucket.
- Production frontend route cutover: `nginx/nginx.production.k8s.conf` makes the production cutover explicit by serving the built frontend bundle on `/` and `/login` under the strict CSP, returning `404` for `/_prod-smoke/`, and removing the Vite-only public paths from the production route set instead of relying on a header-only toggle over the dev graph.
- Edge and browser security verifier: `./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` combines checked-in dev/strict CSP checks for the real app paths, live header verification for `/` and `/_prod-smoke/`, warning-only `/api-docs` visibility and fail-closed probes, direct auth-edge throttling coverage for `/login`, `/auth/*`, `/logout`, and `/login/oauth2/*`, the frontend CSP audit, the API rate-limit identity verifier, and the full runtime-hardening regression cascade. Manual browser-console validation on `/_prod-smoke/` remains required before relying on the edge and browser security proof.
- Local security guardrail umbrella: `./scripts/smoketest/verify-phase-7-security-guardrails.sh` runs the static manifest/admission suite first and the live-cluster runtime proof second. The dedicated `security-guardrails.yml` workflow remains intentionally static-only, and the narrower `./scripts/smoketest/verify-phase-7-runtime-guardrails.sh` entrypoint remains available for targeted runtime-only reruns.

Operationally, those ingress-facing policies depend on the rendered gateway label `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway` and the rendered principal `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`. The egress `DestinationRule` uses `tls.mode: DISABLE` on the workload-to-egress hop so the original external TLS/SNI reaches the egress gateway's `PASSTHROUGH` listener; external TLS remains end-to-end, but that intra-cluster hop is not additionally wrapped in mesh mTLS. `./scripts/smoketest/verify-security-prereqs.sh` proves the platform security prerequisites. Treat Istio ingress and egress hardening as verified only after `./scripts/smoketest/verify-phase-3-istio-ingress.sh` and the live validation checklist pass. Treat edge and browser security as verified only after `./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` passes and the manual browser-console validation on `/_prod-smoke/` is done; `/api-docs` warnings remain visible but non-blocking.

---

## Component Naming

**Session Gateway** - The component that manages user authentication flows and session lifecycle via session-based edge authorization. This name clearly indicates its purpose: managing user sessions at the gateway boundary between frontend clients and backend services.

---

## Architecture Overview

The detailed browser request flow, route ownership, and shared browser session
contract are owned by
[session-edge-authorization-pattern.md](session-edge-authorization-pattern.md).
This document focuses on the security boundaries that flow creates.

At a security-boundary level, the runtime looks like this:

```
Browser
   │ HTTPS + session cookie
   ▼
Istio Ingress Gateway
   ├─ Auth lane → Session Gateway → Redis session writes
   └─ API lane → ext_authz → NGINX → Backend services
                                   │
                                   ├─ PostgreSQL
                                   ├─ Redis
                                   └─ RabbitMQ
```

Security-critical implications:

- All browser traffic enters through the Istio ingress gateway.
- Session Gateway owns login, logout, and browser session renewal.
- `ext_authz` turns the Redis-backed session into trusted upstream identity
  headers on every browser API request.
- Backend services still own data-level authorization after ingress validation.
- Exact service ports and exposure rules live in
  [port-reference.md](port-reference.md).

---

## Component Responsibilities

### 1. Session Gateway (Auth Layer)

**Purpose:** Authentication boundary for browser-based clients

**Responsibilities:**
- Manage OAuth 2.0/OIDC flows with identity provider
- Write session data (userId, roles, permissions, idp_sub, email, display_name) as Redis hashes — no Auth0 tokens are stored
- Write session data (userId, roles, permissions) as Redis hashes (`session:{id}`) — ext_authz reads the same hashes for ingress-layer authorization
- Issue HTTP-only, secure session cookies to browsers
- Provide browser session endpoints (`GET /auth/v1/session`, `GET /auth/v1/user`) for heartbeat and session inspection
- Session lifecycle management (login/logout)
- Call permission-service to resolve roles/permissions, passing `email` and `displayName` extracted from the OAuth2 principal

**Technology:** Spring WebFlux with Spring Security OAuth2 Client

**Why Spring WebFlux:**
- Minimal custom code (primarily configuration)
- Native OAuth 2.0/OIDC support
- Custom Redis hash session management (single hash per session)
- Permission enrichment on login and token refresh
- Team expertise in Spring ecosystem
- Production-grade for financial applications

**Does NOT:**
- Route between microservices (NGINX responsibility)
- Enforce data-level permissions (service responsibility)
- Validate sessions per-request (ext_authz responsibility)

**Why Session-Based Edge Authorization:**
The Session Gateway implements session-based edge authorization specifically for maximum security in a financial application. For detailed analysis of the security advantages, see [Session Security Benefits](session-security-benefits.md).

---

### 2. ext_authz Service

**Purpose:** Per-request session validation at the Istio ingress layer

**Responsibilities:**
- Validate session tokens by looking up Redis session hash (`session:{id}`)
- Inject `X-User-Id`, `X-Roles`, `X-Permissions` headers into authorized requests
- Reject unauthorized requests before they reach NGINX or backend services

**Technology:** Go HTTP service implementing Envoy ext_authz protocol

**Why HTTP mode over gRPC:** Istio's `meshConfig.extensionProviders` with `envoyExtAuthzHttp` provides `headersToUpstreamOnAllow` — an infrastructure-level allowlist that controls which response headers from ext_authz are forwarded to upstream services. This is anti-spoofing at the ingress layer: even if a client sends `X-User-Id` in the original request, the Envoy ext_authz filter overwrites it with the value from ext_authz's response. Only headers listed in `headersToUpstreamOnAllow` are forwarded upstream.

**Integration:** Called by the Istio ingress gateway on `/api/*` requests via `AuthorizationPolicy` with `action: CUSTOM`. Host ownership stays on the Gateway API `HTTPRoute` objects (`app.budgetanalyzer.localhost` locally, `demo.budgetanalyzer.org` in production) so Kiali does not misread the external app hostname as a missing service-registry host.

---

### 3. NGINX API Gateway

**Purpose:** Internal API gateway for routing and backend/API rate limiting

**Responsibilities:**
- Route requests to appropriate microservices
- Rate limit backend-facing API paths after ingress validation
- Load balancing across service instances
- WAF integration points
- Circuit breaking and retry logic

**Note:** SSL/TLS termination is handled by the Istio ingress gateway, not NGINX. Session validation is handled by ext_authz at the Istio ingress layer — NGINX receives pre-validated requests with identity headers already injected.

**Technology:** NGINX (industry standard)

**Why NGINX:**
- Industry standard with proven operational maturity
- Extensive operational knowledge and tooling
- High performance and reliability at scale
- Large community and ecosystem
- Easy to hire engineers with NGINX expertise
- Well-understood failure modes and monitoring

**Does NOT:**
- Manage user sessions (Session Gateway responsibility)
- Handle OAuth flows (Session Gateway responsibility)
- Validate sessions or tokens (ext_authz responsibility)
- Enforce data-level permissions (service responsibility)

---

### 4. Backend Microservices

**Purpose:** Business logic and data access

**Responsibilities:**
- Enforce data-level authorization
- Verify user owns requested data
- Scope all queries by authenticated user ID
- Audit logging of data access
- Business logic execution

**Critical Security Rule:** Always validate that the authenticated user (from `X-User-Id` header injected by ext_authz) has permission to access the specific data being requested.

**Example:**
```
Request: GET /api/budget/accounts/12345
Headers: X-User-Id: user-abc-123, X-Roles: ROLE_USER, X-Permissions: transactions:read

Service Logic:
1. Extract user ID from X-User-Id header: "user-abc-123"
2. Query: SELECT * FROM accounts WHERE id = 12345 AND user_id = 'user-abc-123'
3. If no rows: return 403 Forbidden
4. Otherwise: return account data
```

---

## Authentication And Session Boundaries

The exact login, API-request, and heartbeat walkthroughs live in
[session-edge-authorization-pattern.md](session-edge-authorization-pattern.md).
From a security perspective, the important boundaries are:

- Browser login and callback traffic stays on the Session Gateway auth lane.
  Access tokens are used only inside Session Gateway and are not persisted or
  exposed to browser JavaScript.
- Every browser `/api/*` request is revalidated by `ext_authz`, which rebuilds
  the trusted identity headers from Redis before NGINX forwards the request.
- Active-session renewal happens on `GET /auth/v1/session`. Session Gateway
  extends the Redis-backed session, while the frontend decides when to call the
  heartbeat based on user activity.
- IDP revocation does not depend on the heartbeat path. Bulk revocation
  propagates explicitly through
  `DELETE /internal/v1/sessions/users/{userId}` against the user-session index
  in Redis.

Internal services rely on Istio mTLS, ingress-scoped `AuthorizationPolicy`
rules, and Kubernetes `NetworkPolicy` allowlists. Browser session cookies are
not reused for east-west service calls. The one explicit cross-service session
exception is `permission-service` calling Session Gateway for bulk session
revocation. Kubelet probes and Tilt port-forwards remain host-to-pod exceptions
under Calico's default host endpoint handling.

---

## Identity Provider Abstraction Strategy

### Design Goal
Prevent vendor lock-in by abstracting identity provider behind Session Gateway. Clients never directly interact with Auth0 or know which provider is used.

### Implementation

All browser authentication protocol endpoints stay on the Session Gateway auth
lane documented in
[session-edge-authorization-pattern.md](session-edge-authorization-pattern.md).
The browser-facing `/login` page remains frontend-owned. It starts the OAuth2
flow, is rate-limited as an auth-sensitive entry point, and stays separate from
the versioned Session Gateway JSON endpoints.

**Benefits:**
1. **Provider Independence:** Swap Auth0 → Okta → Keycloak without client changes
2. **Centralized Control:** Auth-path throttling at ingress, API throttling at NGINX, and audit logging at your boundary
3. **Versioning:** Evolve authentication APIs independently
4. **Security:** Additional validation layer before external provider
5. **Compliance:** Keep authentication flows within your infrastructure boundary

### Migration Path

**Current:** Auth0
**Future Options:** Okta, Keycloak, Azure AD, custom solution

**Migration Impact:**
- Clients: No changes (still use session cookies)
- Session Gateway: Update OAuth configuration
- ext_authz: No changes (reads from Redis, provider-independent)
- Services: No changes (read identity from headers, provider-independent)

---

## Security Considerations

### Defense in Depth Layers

**Layer 1: Session Gateway**
- Manages user authentication lifecycle
- Prevents token exposure to browser
- HTTP-only, Secure, SameSite cookies
- Session timeout and absolute expiration

**Layer 2: ext_authz (Istio Ingress)**
- Per-request session validation from Redis
- Header injection (X-User-Id, X-Roles, X-Permissions)
- Rejects unauthorized requests before they reach backend services

**Layer 3: Backend Services**
- Data-level authorization
- Query scoping by authenticated user
- Audit logging of sensitive data access
- Database row-level security (optional)

### Token Configuration

**Opaque Session Token** (browser cookie value):
- Lifetime: 15 minutes (sliding expiration via `GET /auth/v1/session` heartbeat; frontend gates calls on user activity — idle users get no heartbeat and session expires naturally)
- Format: Opaque session ID (no sensitive data encoded)
- Storage: Redis session hash (`session:{id}`)
- Validated by: ext_authz service via Redis lookup

**Session Redis Hash** (`session:{id}`):
- Fields: user_id, idp_sub, email, display_name, picture, roles (comma-joined), permissions (comma-joined), created_at, expires_at
- TTL: 15 minutes (configurable via `session.ttl-seconds`)
- Written by: Session Gateway on login and session heartbeat
- Read by: ext_authz for per-request validation (reads `user_id`, `roles`, `permissions`, `expires_at`)
- Companion index: `user_sessions:{userId}` — a Redis set of session IDs for that user, used by `DELETE /internal/v1/sessions/users/{userId}` for bulk revocation

**IDP Access Token** (Auth0):
- Obtained by Session Gateway during the OAuth2 authorization code exchange
- Used only to derive the user identity (sub, email, name) and permissions during login
- Not persisted. Not used for any upstream API call after login.
- Not exposed to the browser.

> **Auth0 tenant settings** that produce these token lifetimes and session behavior are documented in [Recommended Auth0 Settings](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/auth0-settings.md) (authoritative values, tied to SESSION_TTL_SECONDS and heartbeat cadence) and [Auth0 Setup Guide — Security Configuration](../setup/auth0-setup.md#6-security-configuration) (quickstart context).

**Session Cookie:**
- HttpOnly: true (prevents JavaScript access)
- Secure: true (HTTPS only)
- SameSite: Strict (CSRF protection)
- Max-Age: 15 minutes (matches session timeout)

### Threat Mitigation

| Threat | Mitigation |
|--------|-----------|
| XSS token theft | Tokens never in browser; HTTP-only cookies |
| Token replay | Short session expiration; server-side session validation |
| CSRF | SameSite cookies; CSRF tokens on state changes |
| Unauthorized data access | Service-layer authorization by user ID |
| Credential stuffing | Auth-path rate limiting at Istio ingress; API throttling at NGINX; Auth0 anomaly detection |
| Session hijacking | Opaque session IDs; Redis-backed validation |
| Man-in-the-middle | HTTPS/TLS everywhere; HSTS headers |
| Instant revocation | Delete Redis session — next request fails immediately |

### Content Security Policy Posture

NGINX serves distinct CSP profiles by route. The main application and `/api/*`
routes use the strict production-oriented policy. `/api-docs` keeps a separate
docs-only CSP because stock Swagger UI requires inline styles that the main app
policy intentionally forbids.

The security boundary is the important point here:

- the docs relaxation is isolated to `/api-docs`
- the main app and `/api/*` routes do not inherit it
- the docs/download flow stays same-origin by default

Exact `/api-docs` behavior, generated outputs, and read-only UI details live in
[../../docs-aggregator/README.md](../../docs-aggregator/README.md). The
checked-in CSP split is implemented in
`nginx/includes/security-headers-{strict,dev,docs}-csp.conf`; see
[nginx/README.md — CSP Split](../../nginx/README.md#csp-split) for the NGINX
profile comparison.

---

## Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Session Gateway | Spring WebFlux | Team expertise; minimal code; OAuth 2.0 native support |
| ext_authz | Go HTTP service | Lightweight; Envoy-native protocol; low latency |
| API Gateway | NGINX | Industry standard; proven reliability; operational maturity |
| Session Store | Redis | Fast; distributed; single hash per session; shared by Session Gateway and ext_authz |
| Identity Provider | Auth0 (abstracted) | Managed service; swappable via Session Gateway |
| Backend Services | Spring Boot | Existing architecture; team expertise |

---

## Deployment Architecture

### High Availability Configuration

```
┌──────────────────────────────────────────────────────────────┐
│                 Istio Ingress Gateway (443)                     │
│                    • SSL Termination                           │
│                    • ext_authz enforcement                     │
└────────┬────────────────────────────┬──────────────────────────┘
         │                            │
    ┌────▼────┐                  ┌────▼────┐
    │ Session │                  │ Session │
    │ Gateway │◄────────────────►│ Gateway │
    │   (1)   │   Redis Cluster  │   (2)   │
    └─────────┘                  └─────────┘
         │                            │
    ┌────▼────────────────────────────▼────┐
    │          NGINX Cluster                │
    │      (with health checks)             │
    └────┬──────────┬──────────┬────────────┘
         │          │          │
    ┌────▼────┐ ┌──▼────┐ ┌───▼────┐
    │ Budget  │ │Currency│ │  ...   │
    │   API   │ │Service │ │Services│
    └─────────┘ └────────┘ └────────┘
```

**Session Gateway:**
- Multiple instances behind load balancer
- Stateless (sessions in Redis)
- Graceful shutdown with connection draining

**Redis Cluster:**
- 3-node cluster with sentinel
- Session replication across nodes
- Automatic failover

**NGINX:**
- Multiple instances
- Health checks to backend services
- Consistent hashing for sticky sessions (if needed)

---

## Operational Considerations

### Monitoring and Observability

The observability stack (Prometheus, Grafana, kube-state-metrics) runs in the
`monitoring` namespace and meets the same security requirements as all other
workloads — no namespace exceptions. All images are digest-pinned, all pods
disable `automountServiceAccountToken`, and workloads that need Kubernetes API
access use explicit projected service-account token volumes. See
[Observability Architecture](observability.md) for full details.

Operator access is internal-only in both local Tilt and production OCI/k3s.
Keep observability access loopback-bound through Kubernetes port-forwards or
the repo-owned helper scripts documented in
[observability.md](observability.md). Grafana authentication remains enabled,
anonymous access stays disabled, and the repo does not expose public
observability hostnames.

**Metrics currently collected:**
- Spring Boot JVM metrics (memory, GC, threads) via `/actuator/prometheus`
- Spring Boot HTTP metrics (request rates, latencies, error rates) via Micrometer
- Istio control plane metrics via istiod ServiceMonitor
- Envoy sidecar metrics (per-service traffic) via PodMonitor on `:15090`
- Kubernetes resource metrics via kube-state-metrics

**Security-relevant metrics to watch:**
- `http_server_requests_seconds_count{status="401"}` — authorization failures
- `http_server_requests_seconds_count{status="429"}` — rate limiting triggers
- `up{namespace="default", application!=""}` — Spring service availability

**Alerting**: Not yet configured. Dashboards are the current observability
surface; alerting rules are a future follow-up.

### Logging Strategy

**Audit Logging (Required for Financial Data):**
- All authentication events (login, logout, token refresh)
- All authorization failures
- All sensitive data access with user context
- ext_authz validation failures

**Log Format:**
```json
{
  "timestamp": "2025-11-10T10:15:30Z",
  "event_type": "data_access",
  "user_id": "user-abc-123",
  "client_type": "web",
  "resource": "/api/budget/accounts/12345",
  "action": "read",
  "result": "success",
  "ip_address": "203.0.113.45"
}
```

### Session Management

**Redis Configuration:**
- Session key pattern: `session:{session-id}`
- User session index pattern: `user_sessions:{userId}` (SET of session IDs for bulk revocation)
- TTL: 15 minutes (configurable via `session.ttl-seconds`)
- Eviction policy: allkeys-lru
- Persistence: AOF for crash recovery

**Session Cleanup:**
- Expired sessions automatically removed by Redis TTL
- Explicit session invalidation on logout (session hash deleted, entry removed from user session index)
- Bulk session revocation via `DELETE /internal/v1/sessions/users/{userId}` — uses the user session index to delete all sessions without scanning, and the mesh only allows this route from the `permission-service` workload identity

---

## Migration and Rollout Plan

### Infrastructure Setup
1. Deploy Redis cluster
2. Deploy Session Gateway (Spring WebFlux)
3. Deploy ext_authz HTTP service
4. Configure Istio ingress gateway with ext_authz
5. Set up monitoring and alerting

### Authentication Integration
1. Configure Session Gateway with Auth0
2. Test OAuth flows (authorization code + PKCE)
3. Test token refresh mechanism with session hash update
4. Verify session management

### API Integration
1. Update React app to use Session Gateway
2. Test authenticated API calls through ext_authz
3. Verify header injection and backend service authorization
4. Test session expiration and refresh

### Security Validation
1. Penetration testing
2. Session lifecycle testing
3. Session fixation testing
4. Authorization bypass testing
5. Load testing with realistic user patterns

### Production Rollout
1. Blue-green deployment
2. Gradual traffic migration (10% → 50% → 100%)
3. Monitor error rates and latency
4. 24-hour observation period

---

## Future Enhancements

### Potential Improvements
1. **Step-up Authentication:** Require re-authentication for sensitive operations
2. **Device Fingerprinting:** Track and alert on suspicious device changes
3. **Behavioral Analytics:** Detect anomalous access patterns
4. **Token Binding:** Bind sessions to specific devices/channels
5. **GraphQL Gateway:** Add GraphQL layer for frontend aggregation

### Scalability Considerations
1. **Geo-distributed Redis:** Multi-region session replication
2. **Edge Deployment:** Deploy Session Gateway closer to users
3. **Session Caching:** Cache validated sessions at ext_authz layer to reduce Redis lookups
4. **API Gateway Sharding:** Split NGINX by service domain

---

## Appendix: Key Decision Log

| Decision | Rationale |
|----------|-----------|
| Use session-based edge authorization | Maximum security for browser-based financial application |
| Keep NGINX as API gateway | Industry standard; operational maturity; team familiarity |
| Spring WebFlux for Session Gateway | Team expertise; minimal code; native OAuth support |
| Abstract identity provider | Prevent vendor lock-in; centralized control |
| Opaque session cookies | Instant revocation via Redis delete; no expiry window |
| Istio ext_authz for validation | Per-request enforcement at ingress; Envoy-native protocol via meshConfig |
| 15 min session timeout | Favor shorter default session windows for browser sessions |
| Service-layer authorization | Defense in depth; protect against gateway bypass |
| Redis for sessions | Performance; distributed architecture; single hash per session |
| East-west caller authentication | Istio mTLS plus AuthorizationPolicy for service-to-service traffic |

---

## Document Approval

**Prepared by:** Senior Software Architect
**Review Required:** Security Team, DevOps Team, Engineering Leadership
**Next Review Date:** Upon architecture changes or security incidents

---

**End of Document**
