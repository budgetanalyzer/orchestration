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
- Local platform hardening Phase 0 is implemented: Kind uses Calico instead of `kindnet`, namespace PSA labels are staged in `warn`/`audit`, and Kyverno plus a smoke policy are installed and verifiable.
- Application `NetworkPolicy` allowlists, credential hardening, and ingress unification remain later phases.

---

## Component Naming

**Session Gateway** - The Backend-for-Frontend (BFF) component that manages user authentication flows and session lifecycle. This name clearly indicates its purpose: managing user sessions at the gateway boundary between frontend clients and backend services.

---

## Architecture Overview

### Request Flow

**All browser traffic enters through Envoy.** Envoy handles SSL termination and ext_authz enforcement.

```
Browser → Envoy (:443) → ext_authz validates session → NGINX (:8080) → Services
Auth paths: Browser → Envoy (:443) → Session Gateway (:8081)
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
│                    Envoy Gateway (Port 443, HTTPS)               │
│                    • SSL Termination (all traffic)               │
│                    • ext_authz enforcement on /api/* paths       │
│                    • Routes /auth/*, /login/*, /logout →         │
│                      Session Gateway                             │
│                    • Routes /api/*, /* → NGINX                   │
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
│                    • Rate Limiting                               │
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
- Dual-write session data (userId, roles, permissions) to ext_authz Redis schema for Envoy-based authorization
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

**Purpose:** Per-request session validation at the Envoy layer

**Responsibilities:**
- Validate session tokens by looking up ext_authz Redis hash (`extauthz:session:{id}`)
- Inject `X-User-Id`, `X-Roles`, `X-Permissions` headers into authorized requests
- Reject unauthorized requests before they reach NGINX or backend services

**Technology:** Go HTTP service implementing Envoy ext_authz protocol

**Why HTTP mode over gRPC:** Envoy Gateway's HTTP ext_authz mode provides `headersToBackend` — an infrastructure-level allowlist in the SecurityPolicy that controls which response headers from ext_authz are forwarded to upstream services. This is anti-spoofing at the Envoy layer: even if a client sends `X-User-Id` in the original request, only headers explicitly listed in `headersToBackend` (and returned by ext_authz) reach the backend. The gRPC ext_authz mode lacks this infrastructure-level allowlist, requiring the ext_authz service itself to handle header stripping.

**Integration:** Called by Envoy on every request to `/api/*` paths

---

### 3. NGINX API Gateway

**Purpose:** Internal API gateway for routing and rate limiting

**Responsibilities:**
- Route requests to appropriate microservices
- Rate limiting per user/client
- Load balancing across service instances
- WAF integration points
- Circuit breaking and retry logic

**Note:** SSL/TLS termination is handled by Envoy Gateway, not NGINX. Session validation is handled by ext_authz at the Envoy layer — NGINX receives pre-validated requests with identity headers already injected.

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
2. React → Session Gateway /login endpoint
3. Session Gateway redirects to Auth0 authorize endpoint
4. User authenticates at Auth0 (enters credentials)
5. Auth0 redirects to Session Gateway /callback with authorization code
6. Session Gateway exchanges code for tokens (access + refresh)
7. Session Gateway stores Auth0 tokens in Redis
8. Session Gateway calls permission-service to resolve roles/permissions
9. Session Gateway dual-writes session data to ext_authz Redis schema
10. Session Gateway sets HTTP-only session cookie in browser
11. Browser redirected to application home page
```

**Security Benefits:**
- Tokens never exposed to browser JavaScript
- Tokens immune to XSS attacks
- Session cookie has HttpOnly, Secure, SameSite attributes
- ext_authz session enables per-request validation at the Envoy layer

---

### API Request Flow (Authenticated User)

```
1. Browser sends request with session cookie → Envoy (:443)
2. Envoy calls ext_authz HTTP service (:9002)
3. ext_authz looks up session in Redis (extauthz:session:{id})
4. If valid: ext_authz injects X-User-Id, X-Roles, X-Permissions headers
5. Envoy routes to NGINX (:8080) with injected headers
6. NGINX routes to appropriate microservice
7. Microservice reads identity from headers, validates user has permission for specific data
8. Response flows back through NGINX → Envoy → Browser
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

**Option 2: NGINX Proxy Pattern**
- Mobile app calls NGINX /auth/* endpoints
- NGINX proxies to Auth0
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
5. Envoy ext_authz validates bearer token from Redis
6. If valid: routes to backend service with identity headers
```

**Security:**
- Token exchange creates a server-managed session — no long-lived tokens on wire
- ext_authz validates every request
- Scoped permissions resolved from permission-service

---

### Internal Service-to-Service Authentication

Internal services currently rely on network isolation for authentication. Permission-service is called directly by Session Gateway without bearer authentication — Kubernetes network policies restrict access.

**Current approach:**
- Session Gateway calls permission-service via internal Kubernetes DNS
- No bearer token or cryptographic proof of caller identity
- Security relies on network isolation (only Session Gateway can reach permission-service)

**Implemented:** mTLS via Istio service mesh. STRICT for east-west traffic, PERMISSIVE for ingress-facing services. Provides cryptographic caller authentication without application-level token management.

---

## Identity Provider Abstraction Strategy

### Design Goal
Prevent vendor lock-in by abstracting identity provider behind Session Gateway. Clients never directly interact with Auth0 or know which provider is used.

### Implementation

**All authentication flows go through Session Gateway:**
- `/auth/*` - Auth lifecycle endpoints
- `/login/*` - OAuth2 login initiation
- `/logout` - End session
- `/auth/token/exchange` - Token exchange for native/M2M clients

**Benefits:**
1. **Provider Independence:** Swap Auth0 → Okta → Keycloak without client changes
2. **Centralized Control:** Rate limiting and audit logging at your boundary
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

**Layer 2: ext_authz (Envoy)**
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
| Credential stuffing | Rate limiting at NGINX; Auth0 anomaly detection |
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
│                    Envoy Gateway (443)                          │
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
4. Configure Envoy Gateway with ext_authz
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
| Envoy ext_authz for validation | Per-request enforcement at ingress; Envoy-native protocol |
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
