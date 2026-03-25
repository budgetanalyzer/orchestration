# Financial Application Security Architecture
## Design Document

**Version:** 2.0
**Date:** March 10, 2026
**Status:** Active

---

## Executive Summary

This document outlines the security architecture for a financial data application requiring maximum security to prevent unauthorized data access. The architecture implements defense-in-depth principles with clear separation of concerns across multiple security layers while maintaining identity provider independence.

Current repository state:
- The ingress/session/routing topology described here is implemented.
- Local platform hardening Phase 0 is implemented: Kind uses Calico instead of `kindnet`, Kyverno plus a smoke policy are installed and verifiable, and the namespace PSA labeling flow that later graduates to the final Phase 5 enforce levels is in place.
- Phase 1 credential isolation is implemented: per-service PostgreSQL, RabbitMQ, and Redis credentials with dedicated Kubernetes secrets.
- Phase 2 network policies are enforced: `default`, `infrastructure`, `istio-ingress`, and `istio-egress` namespaces have deny-by-default ingress and egress with explicit allowlists. Only documented pod callers can reach each service. Kubelet probes and Tilt port-forwards are host-to-pod traffic and still rely on Calico's default host endpoint handling (`defaultEndpointToHostAction=Accept`), not the Phase 2 allowlists.
- Phase 3 manifests now describe the intended Istio ingress/egress topology: Envoy Gateway is replaced by an Istio-managed ingress gateway (inside the mesh with SPIFFE identity). Istio egress routes approved outbound traffic (Auth0, FRED API) with `REGISTRY_ONLY` blocking unapproved hosts. All ingress-facing services use STRICT mTLS and ingress-only `AuthorizationPolicy` rules. Auth-sensitive paths are throttled at Istio ingress; backend API throttling remains at NGINX.
- Phase 5 Session 1 is implemented in-repo: Tilt installs Istio CNI, enables `pilot.cni.enabled=true` for `istiod`, and reinjects existing `default` namespace workloads so new sidecar pods no longer require `istio-init`.
- Phase 5 Session 2 is implemented in-repo for the non-root application workloads: `session-gateway`, `currency-service`, `transaction-service`, `permission-service`, and `ext-authz` disable service-account token automount, set pod `seccompProfile.type: RuntimeDefault`, and apply the planned container hardening. The Spring Boot services also mount `/tmp` and run read-only as UID/GID `1001`.
- Phase 5 Session 3 is implemented in-repo for the gateway workloads on the refreshed Istio `1.29.1` baseline: the auto-provisioned ingress gateway now receives pod `seccompProfile.type: RuntimeDefault`, fixed NodePort ownership, and explicit service-account token retention through Gateway `spec.infrastructure.parametersRef`, and the egress gateway installs directly from the `istio/gateway` chart using checked-in values that keep `service.type=ClusterIP`, preserve the low-port binding sysctl needed by the non-root proxy, and add pod-level seccomp hardening. The ingress gateway intentionally keeps its Kubernetes API token mount for TLS secret watching, while the egress gateway currently keeps the chart-managed token behavior because this repo does not add a separate post-render patch just to remove it.
- Phase 5 Session 4 is implemented in-repo for `nginx-gateway`: the Deployment and ServiceAccount disable service-account token automount, the pod sets `seccompProfile.type: RuntimeDefault`, the container now runs as UID/GID `101` from `nginxinc/nginx-unprivileged:1.29.4-alpine`, `readOnlyRootFilesystem: true` is enabled, and the gateway relies on an explicit writable `/tmp` mount while logging to stdout/stderr.
- Phase 5 Session 5 is implemented across the orchestration and `budget-analyzer-web` repos: the frontend dev image now runs Vite as UID/GID `1001`, the Kubernetes Deployment and ServiceAccount disable service-account token automount, the pod sets `seccompProfile.type: RuntimeDefault`, the container now pins `runAsUser`/`runAsGroup` to `1001`, and the container applies the planned non-root baseline without forcing `readOnlyRootFilesystem` before the HMR workflow is proven on explicit writable paths.
- Phase 5 Session 6 is implemented in-repo for Redis: the Deployment disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, runs Redis as UID `999` / GID `1000` with a read-only root filesystem, and mounts explicit writable `emptyDir` paths for ACL bootstrap (`/tmp`) and local-dev AOF output (`/data`). That AOF storage remains intentionally ephemeral in local development; production persistence would require a PVC-backed replacement.
- Phase 5 Session 7 is implemented in-repo for PostgreSQL: the StatefulSet disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, pins pod and container ownership to UID/GID `70`, hardens the TLS-prep init container to the same ownership with `readOnlyRootFilesystem: true`, and keeps the main container `readOnlyRootFilesystem: true` compatible through explicit writable mounts at `/tmp` and `/var/run/postgresql`.
- Phase 5 Session 8 is implemented in-repo for RabbitMQ: the StatefulSet disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, runs the broker as UID/GID `999` with `fsGroup: 999`, and enables `readOnlyRootFilesystem: true` while keeping `/var/lib/rabbitmq` as the explicit PVC-backed writable path and leaving config, definitions, and TLS mounts read-only.
- Phase 5 Session 9 is implemented in-repo: the checked-in namespace manifests now declare the final Pod Security `enforce` labels for `infrastructure`, `istio-ingress`, and `istio-egress`, while Tilt reapplies the final `default`, `infrastructure`, and `istio-system` labels during reconciliation.
- Phase 5 Session 10 is complete in-repo: `./scripts/dev/verify-phase-5-runtime-hardening.sh --regression-timeout 8m` passed end-to-end twice on March 25, 2026, first at the original `166/166` baseline and again at `175/175` after adding the frontend UID/GID assertions plus the PostgreSQL init-container baseline assertions. The verifier reruns remain bounded per script so the final gate fails instead of hanging indefinitely.

Operationally, those ingress-facing policies depend on the rendered gateway label `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway` and the rendered principal `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`. The egress `DestinationRule` uses `tls.mode: DISABLE` on the workload-to-egress hop so the original external TLS/SNI reaches the egress gateway's `PASSTHROUGH` listener; external TLS remains end-to-end, but that intra-cluster hop is not additionally wrapped in mesh mTLS. `./scripts/dev/verify-security-prereqs.sh` proves the Phase 0 platform baseline. Treat Phase 3 as complete only after `./scripts/dev/verify-phase-3-istio-ingress.sh` and the live validation checklist pass.

---

## Component Naming

**Session Gateway** - The Backend-for-Frontend (BFF) component that manages user authentication flows and session lifecycle. This name clearly indicates its purpose: managing user sessions at the gateway boundary between frontend clients and backend services.

---

## Architecture Overview

### Request Flow

**All browser traffic enters through the Istio ingress gateway.** It handles SSL termination, auth-path throttling, and ext_authz enforcement within the service mesh.

```
Browser → Istio Ingress (:443) → ext_authz validates session → NGINX (:8080) → Services
Auth paths: Browser → Istio Ingress (:443) → Session Gateway (:8081)
```

### Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT LAYER                              │
├─────────────────────────────────────────────────────────────────┤
│  React Web App          iOS/Android App       3rd Party Client  │
│  (Port 3000)            (Native)              (External API)    │
└────────┬───────────────────────┬──────────────────────┬─────────┘
         │                       │                      │
         │ Session Cookie        │ Bearer Token          │ Bearer Token
         │ (HTTPS)               │ (HTTPS)              │ (HTTPS)
         ▼                       ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│              Istio Ingress Gateway (Port 443, HTTPS)             │
│                    • SSL Termination (all traffic)               │
│                    • ext_authz enforcement on /api/* paths       │
│                    • Routes /auth/*, /oauth2/*, /login/oauth2/*, │
│                      /logout, /user → Session Gateway            │
│                    • Routes /api/*, /* → NGINX                   │
│                    • Local rate limiting on auth-sensitive paths │
│                    • Mesh identity (SPIFFE) for mTLS             │
└────────┬───────────────────────┬──────────────────────┬─────────┘
         │                       │                      │
         ▼                       │                      │
┌────────────────────────┐       │                      │
│   ext_authz HTTP       │       │                      │
│   Port 9002            │       │                      │
│   • Session lookup     │       │                      │
│     in Redis           │       │                      │
│   • Header injection   │       │                      │
│     (X-User-Id, etc.)  │       │                      │
└────────────────────────┘       │                      │
                                 │                      │
         ┌───────────────────────┴──────────────────────┘
         │ Validated headers (X-User-Id, X-Roles, X-Permissions)
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NGINX API Gateway (Port 8080, HTTP)           │
│                    • Request Routing                             │
│                    • Backend/API Rate Limiting                   │
│                    • Load Balancing                              │
└────────┬────────────────────────────────────────────────────────┘
         │
         └──────► Backend Microservices
                  • Transaction Service (8082)
                  • Currency Service (8084)
                  • Permission Service (8086)
                  • Data-level authorization

┌────────────────────────┐       ┌─────────────────────────────┐
│   Session Gateway      │       │   Identity Provider         │
│   Port 8081 (HTTP)     │       │   (Auth0/Keycloak/Other)    │
│   • OAuth Flow Mgmt    │       │   • User Authentication     │
│   • Session lifecycle  │       │   • User Management         │
│   • ext_authz dual-    │       └─────────────────────────────┘
│     write to Redis     │
│   • Token exchange     │
└────────────────────────┘
```

---

## Component Responsibilities

### 1. Session Gateway (BFF Layer)

**Purpose:** Authentication boundary for browser-based clients

**Responsibilities:**
- Manage OAuth 2.0/OIDC flows with identity provider
- Store Auth0 tokens in Redis for refresh
- Dual-write session data (userId, roles, permissions) to ext_authz Redis schema for ingress-layer authorization
- Issue HTTP-only, secure session cookies to browsers
- Proactive token refresh before expiration
- Session lifecycle management (login/logout)
- Call permission-service to resolve roles/permissions, passing `email` and `displayName` extracted from the OAuth2 principal
- Provide token exchange endpoint for native PKCE/M2M clients (`POST /auth/token/exchange`)

**Technology:** Spring Cloud Gateway with Spring Security OAuth2 Client

**Why Spring Cloud Gateway:**
- Minimal custom code (primarily configuration)
- Native OAuth 2.0/OIDC support
- Built-in session management with Redis
- Permission enrichment on login and token refresh
- Team expertise in Spring ecosystem
- Production-grade for financial applications

**Does NOT:**
- Route between microservices (NGINX responsibility)
- Enforce data-level permissions (service responsibility)
- Validate sessions per-request (ext_authz responsibility)

**Why BFF Pattern:**
The Session Gateway implements the Backend-for-Frontend (BFF) pattern specifically for maximum security in a financial application. For detailed analysis of the security advantages, see [BFF Security Benefits](bff-security-benefits.md).

---

### 2. ext_authz Service

**Purpose:** Per-request session validation at the Istio ingress layer

**Responsibilities:**
- Validate session tokens by looking up ext_authz Redis hash (`extauthz:session:{id}`)
- Inject `X-User-Id`, `X-Roles`, `X-Permissions` headers into authorized requests
- Reject unauthorized requests before they reach NGINX or backend services

**Technology:** Go HTTP service implementing Envoy ext_authz protocol

**Why HTTP mode over gRPC:** Istio's `meshConfig.extensionProviders` with `envoyExtAuthzHttp` provides `headersToUpstreamOnAllow` — an infrastructure-level allowlist that controls which response headers from ext_authz are forwarded to upstream services. This is anti-spoofing at the ingress layer: even if a client sends `X-User-Id` in the original request, the Envoy ext_authz filter overwrites it with the value from ext_authz's response. Only headers listed in `headersToUpstreamOnAllow` are forwarded upstream.

**Integration:** Called by the Istio ingress gateway on every request to `/api/*` paths via `AuthorizationPolicy` with `action: CUSTOM`

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

## Authentication Flows

### User Login Flow (Web Browser)

```
1. User clicks "Login" in React app
2. React routes to the frontend login page at `/login`
3. Frontend initiates `GET /oauth2/authorization/idp`
4. Session Gateway redirects to Auth0 authorize endpoint
5. User authenticates at Auth0 (enters credentials)
6. Auth0 redirects to Session Gateway `/login/oauth2/code/idp` with authorization code
7. Session Gateway exchanges code for tokens (access + refresh)
8. Session Gateway stores Auth0 tokens in Redis
9. Session Gateway calls permission-service to resolve roles/permissions
10. Session Gateway dual-writes session data to ext_authz Redis schema
11. Session Gateway sets HTTP-only session cookie in browser
12. Browser redirected to application home page
```

**Security Benefits:**
- Tokens never exposed to browser JavaScript
- Tokens immune to XSS attacks
- Session cookie has HttpOnly, Secure, SameSite attributes
- ext_authz session enables per-request validation at the Istio ingress layer

---

### API Request Flow (Authenticated User)

```
1. Browser sends request with session cookie → Istio Ingress (:443)
2. Istio ingress calls ext_authz HTTP service (:9002)
3. ext_authz looks up session in Redis (extauthz:session:{id})
4. If valid: ext_authz injects X-User-Id, X-Roles, X-Permissions headers
5. Istio ingress routes to NGINX (:8080) with injected headers
6. NGINX routes to appropriate microservice
7. Microservice reads identity from headers, validates user has permission for specific data
8. Response flows back through NGINX → Istio Ingress → Browser
```

**Key Points:**
- ext_authz validates every request (defense in depth)
- Session revocation is instant — delete Redis key, next request fails
- Microservices enforce data-level permissions
- No cryptographic verification at runtime — Redis is trusted internal infrastructure

---

### Token Refresh Flow

```
1. Session Gateway detects Auth0 access token will expire soon (5 min threshold)
2. Session Gateway → Auth0 token endpoint with refresh token
3. Auth0 returns new access token (and optionally new refresh token)
4. Session Gateway updates Redis session with new Auth0 tokens
5. Session Gateway re-fetches permissions from permission-service
6. Session Gateway updates ext_authz Redis hash with refreshed session data
7. Session Gateway continues request
```

**Refresh Strategy:** Proactive refresh 5 minutes before expiration to avoid request failures

---

### Mobile App Authentication

**Status:** Under Consideration

Mobile app authentication strategy is still being evaluated. We will assess the following options when mobile development begins:

**Option 1: Direct Auth0 Integration**
- Mobile app uses Auth0 native SDKs
- Tokens stored in secure OS storage (Keychain/Keystore)
- Token exchange via Session Gateway (`POST /auth/token/exchange`)
- Simpler implementation with proven SDKs

**Option 2: Session Gateway Proxy Pattern**
- Mobile app calls Session Gateway auth endpoints through Istio ingress
- Session Gateway proxies to Auth0
- Maintains identity provider abstraction
- Consistent with overall architecture principles

**Decision Factors:**
- Security requirements for mobile vs web
- Native OS token storage capabilities
- Operational complexity vs abstraction benefits
- Team expertise with mobile OAuth implementations

The mobile authentication approach will be finalized during mobile application design phase, weighing the trade-offs between simplicity and architectural consistency.

---

### Client Credentials Flow (M2M)

```
1. External client obtains Auth0 access token via client_credentials grant
2. Client exchanges Auth0 token for opaque session via POST /auth/token/exchange
3. Session Gateway validates token, creates session, writes ext_authz Redis hash
4. Client uses opaque bearer token for API calls
5. Istio ingress ext_authz validates bearer token from Redis
6. If valid: routes to backend service with identity headers
```

**Security:**
- Token exchange creates a server-managed session — no long-lived tokens on wire
- ext_authz validates every request
- Scoped permissions resolved from permission-service

---

### Internal Service-to-Service Authentication

Internal services rely on network isolation enforced by Kubernetes NetworkPolicy. Permission-service is called directly by Session Gateway without bearer authentication — NetworkPolicy allowlists restrict which pods can reach it.

**Current approach:**
- Session Gateway calls permission-service via internal Kubernetes DNS
- No bearer token or cryptographic proof of caller identity
- NetworkPolicy enforces that only Session Gateway pods can reach permission-service (Phase 2)
- Backend services only accept traffic from their documented pod callers (NGINX for transaction/currency/web, Session Gateway for permission-service)
- Kubelet probes and Tilt port-forwards remain host-to-pod exceptions under Calico's default host endpoint handling

**Implemented:** mTLS via Istio service mesh. STRICT for all traffic in the default namespace — no PERMISSIVE exceptions. With Istio-managed ingress, the ingress gateway has a mesh identity (SPIFFE), so ingress-facing services (nginx-gateway, ext-authz, session-gateway) have AuthorizationPolicies restricting callers to the ingress gateway identity only. Provides cryptographic caller authentication without application-level token management.

---

## Identity Provider Abstraction Strategy

### Design Goal
Prevent vendor lock-in by abstracting identity provider behind Session Gateway. Clients never directly interact with Auth0 or know which provider is used.

### Implementation

**All authentication protocol endpoints go through Session Gateway:**
- `/auth/*` - Auth lifecycle endpoints
- `/oauth2/*` - OAuth2 callback and continuation endpoints
- `/login/oauth2/*` - OAuth2 callback path
- `/logout` - End session
- `/user` - Session inspection for the browser client
- `/auth/token/exchange` - Token exchange for native/M2M clients

The browser-facing `/login` page is frontend-owned. It starts the OAuth2 flow by calling `/oauth2/authorization/idp`, but it is not itself a Session Gateway route.

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
- Clients: No changes (still use session cookies or token exchange)
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

**Opaque Session Token** (cookie or bearer token):
- Lifetime: 30 minutes (sliding expiration)
- Format: Opaque session ID (no sensitive data encoded)
- Storage: Redis (Spring Session + ext_authz hash)
- Validated by: ext_authz service via Redis lookup

**ext_authz Redis Hash** (`extauthz:session:{id}`):
- Fields: `user_id`, `roles` (comma-joined), `permissions` (comma-joined), `created_at`, `expires_at`
- TTL: Matches Spring Session timeout (30 minutes)
- Written by: Session Gateway on login, token refresh, and token exchange

**Refresh Token:**
- Lifetime: 8 hours (web), 30 days (mobile)
- Rotation: Issue new refresh token on each use
- Storage: Redis (web), Secure storage (mobile)
- Revocation: Supported via token introspection

**Session Cookie:**
- HttpOnly: true (prevents JavaScript access)
- Secure: true (HTTPS only)
- SameSite: Strict (CSRF protection)
- Max-Age: 30 minutes (matches session timeout)

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

---

## Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Session Gateway | Spring Cloud Gateway | Team expertise; minimal code; OAuth 2.0 native support |
| ext_authz | Go HTTP service | Lightweight; Envoy-native protocol; low latency |
| API Gateway | NGINX | Industry standard; proven reliability; operational maturity |
| Session Store | Redis | Fast; distributed; Spring Session integration; ext_authz schema |
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
- Session replication across nodes (Spring Session + ext_authz schema)
- Automatic failover

**NGINX:**
- Multiple instances
- Health checks to backend services
- Consistent hashing for sticky sessions (if needed)

---

## Operational Considerations

### Monitoring and Observability

**Metrics to Track:**
- Session Gateway: Active sessions, token refresh rate, OAuth flow success/failure
- ext_authz: Validation latency, hit/miss ratio, rejection rate
- NGINX: Request rate, error rate, latency percentiles
- Services: Authorization failures, data access patterns

**Alerting Thresholds:**
- ext_authz rejection rate spike > 5% (may indicate session store issues)
- Session Gateway error rate > 0.5%
- Redis connection failures
- Unauthorized data access attempts

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
- Spring Session key pattern: `spring:session:sessions:{session-id}`
- ext_authz key pattern: `extauthz:session:{session-id}`
- TTL: 30 minutes (sliding expiration)
- Eviction policy: allkeys-lru
- Persistence: AOF for crash recovery

**Session Cleanup:**
- Expired sessions automatically removed by Redis TTL
- Explicit session invalidation on logout (both Spring Session and ext_authz keys)
- Bulk session revocation capability for security incidents

---

## Migration and Rollout Plan

### Phase 1: Infrastructure Setup
1. Deploy Redis cluster
2. Deploy Session Gateway (Spring Cloud Gateway)
3. Deploy ext_authz HTTP service
4. Configure Istio ingress gateway with ext_authz
5. Set up monitoring and alerting

### Phase 2: Authentication Integration
1. Configure Session Gateway with Auth0
2. Test OAuth flows (authorization code + PKCE)
3. Test token refresh mechanism with ext_authz dual-write
4. Verify session management

### Phase 3: API Integration
1. Update React app to use Session Gateway
2. Test authenticated API calls through ext_authz
3. Verify header injection and backend service authorization
4. Test session expiration and refresh

### Phase 4: Security Validation
1. Penetration testing
2. Session lifecycle testing
3. Session fixation testing
4. Authorization bypass testing
5. Load testing with realistic user patterns

### Phase 5: Production Rollout
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
| Use BFF pattern | Maximum security for browser-based financial application |
| Keep NGINX as API gateway | Industry standard; operational maturity; team familiarity |
| Spring Cloud Gateway for BFF | Team expertise; minimal code; native OAuth support |
| Abstract identity provider | Prevent vendor lock-in; centralized control |
| Opaque session tokens | Instant revocation via Redis delete; no expiry window |
| Istio ext_authz for validation | Per-request enforcement at ingress; Envoy-native protocol via meshConfig |
| 30 min session timeout | Balance security vs user experience |
| Proactive token refresh | Avoid request failures due to expiration |
| Service-layer authorization | Defense in depth; protect against gateway bypass |
| Redis for sessions | Performance; distributed architecture; Spring integration |
| Network isolation for internal M2M | Simplicity; mTLS implemented via Istio for cryptographic authentication |

---

## Document Approval

**Prepared by:** Senior Software Architect
**Review Required:** Security Team, DevOps Team, Engineering Leadership
**Next Review Date:** Upon architecture changes or security incidents

---

**End of Document**
