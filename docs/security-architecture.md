# Financial Application Security Architecture
## Design Document

**Version:** 1.0  
**Date:** November 10, 2025  
**Status:** Design Proposal

---

## Executive Summary

This document outlines the security architecture for a financial data application requiring maximum security to prevent unauthorized data access. The architecture implements defense-in-depth principles with clear separation of concerns across multiple security layers while maintaining identity provider independence.

---

## Component Naming

**Session Gateway** - The Backend-for-Frontend (BFF) component that manages user authentication flows and session lifecycle. This name clearly indicates its purpose: managing user sessions at the gateway boundary between frontend clients and backend services.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT LAYER                              │
├─────────────────────────────────────────────────────────────────┤
│  React Web App          iOS/Android App       3rd Party Client  │
│  (Port 3000)            (Native)              (External API)    │
└────────┬───────────────────────┬──────────────────────┬─────────┘
         │                       │                      │
         │ Session Cookie        │ JWT                  │ JWT
         │                       │                      │
┌────────▼───────────────────────┼──────────────────────┼─────────┐
│     Session Gateway            │                      │         │
│     (Spring Cloud Gateway)     │                      │         │
│     Port 8081                  │                      │         │
│     • OAuth Flow Management    │                      │         │
│     • Session Management       │                      │         │
│     • Token Lifecycle          │                      │         │
└────────┬───────────────────────┴──────────────────────┴─────────┘
         │ JWT in Authorization header
         │
┌────────▼─────────────────────────────────────────────────────────┐
│                    NGINX API Gateway                             │
│                    Port 8080                                     │
│                    • Request Routing                             │
│                    • JWT Validation                              │
│                    • Rate Limiting                               │
│                    • Load Balancing                              │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ├──────► Token Validation Service (Port 8090)
         │        • JWT signature verification
         │        • Claims validation
         │
         └──────► Backend Microservices
                  • Budget API (8082)
                  • Currency Service (8084)
                  • Data-level authorization

         ┌─────────────────────────────┐
         │   Identity Provider         │
         │   (Auth0/Keycloak/Other)    │
         │   • Token Issuance          │
         │   • User Management         │
         └─────────────────────────────┘
```

---

## Component Responsibilities

### 1. Session Gateway (BFF Layer)

**Purpose:** Authentication boundary for browser-based clients

**Responsibilities:**
- Manage OAuth 2.0/OIDC flows with identity provider
- Store JWTs server-side (Redis session store)
- Issue HTTP-only, secure session cookies to browsers
- Proactive token refresh before expiration
- Session lifecycle management (login/logout)
- Proxy authenticated requests to NGINX with JWT

**Technology:** Spring Cloud Gateway with Spring Security OAuth2 Client

**Why Spring Cloud Gateway:**
- Minimal custom code (primarily configuration)
- Native OAuth 2.0/OIDC support
- Built-in session management with Redis
- TokenRelay filter automatically forwards JWTs
- Team expertise in Spring ecosystem
- Production-grade for financial applications

**Does NOT:**
- Validate JWT signatures (NGINX responsibility)
- Route between microservices (NGINX responsibility)
- Enforce data-level permissions (service responsibility)

---

### 2. NGINX API Gateway

**Purpose:** Internal API gateway and security perimeter for backend services

**Responsibilities:**
- Route requests to appropriate microservices
- Validate JWT signatures using cached public keys
- Verify JWT claims (issuer, audience, expiration)
- Rate limiting per user/client
- Load balancing across service instances
- SSL/TLS termination
- WAF integration points
- Circuit breaking and retry logic

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
- Enforce data-level permissions (service responsibility)

---

### 3. Token Validation Service

**Purpose:** Validate JWT authenticity and claims

**Responsibilities:**
- Verify JWT signatures against identity provider's public keys
- Cache public keys from JWKS endpoint
- Validate issuer, audience, expiration claims
- Distinguish between user tokens and M2M tokens
- Return user/client context to NGINX

**Technology:** Spring Boot microservice

**Integration:** Called by NGINX via `auth_request` directive

---

### 4. Backend Microservices

**Purpose:** Business logic and data access

**Responsibilities:**
- Enforce data-level authorization
- Verify user owns requested data
- Scope all queries by authenticated user ID
- Audit logging of data access
- Business logic execution

**Critical Security Rule:** Always validate that the authenticated user (from JWT claims) has permission to access the specific data being requested.

**Example:**
```
Request: GET /api/budget/accounts/12345
JWT Claims: { "sub": "user-abc-123", ... }

Service Logic:
1. Extract user ID from JWT: "user-abc-123"
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
7. Session Gateway stores tokens in Redis
8. Session Gateway sets HTTP-only session cookie in browser
9. Browser redirected to application home page
```

**Security Benefits:**
- JWT never exposed to browser JavaScript
- Tokens immune to XSS attacks
- Session cookie has HttpOnly, Secure, SameSite attributes

---

### API Request Flow (Authenticated User)

```
1. Browser sends request with session cookie → Session Gateway
2. Session Gateway looks up session in Redis
3. Session Gateway retrieves JWT from session
4. Session Gateway checks JWT expiration (local check)
5. If expired: Session Gateway refreshes token with Auth0
6. If valid: Session Gateway adds JWT to Authorization header
7. Session Gateway → NGINX with JWT
8. NGINX validates JWT via Token Validation Service
9. Token Validation Service verifies signature and claims
10. If valid: NGINX routes to appropriate microservice
11. Microservice validates user has permission for specific data
12. Response flows back through NGINX → Session Gateway → Browser
```

**Key Points:**
- Auth0 only contacted when tokens need refresh (every 15-30 min)
- NGINX validates every request (defense in depth)
- Microservices enforce data-level permissions

---

### Token Refresh Flow

```
1. Session Gateway detects access token will expire soon (5 min threshold)
2. Session Gateway → Auth0 token endpoint with refresh token
3. Auth0 returns new access token (and optionally new refresh token)
4. Session Gateway updates Redis session with new tokens
5. Session Gateway continues request with new access token
```

**Refresh Strategy:** Proactive refresh 5 minutes before expiration to avoid request failures

---

### Mobile App Authentication

**Status:** Under Consideration

Mobile app authentication strategy is still being evaluated. We will assess the following options when mobile development begins:

**Option 1: Direct Auth0 Integration**
- Mobile app uses Auth0 native SDKs
- Tokens stored in secure OS storage (Keychain/Keystore)
- Direct API calls to NGINX (bypasses Session Gateway)
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
1. 3rd party → NGINX /auth/token with client_id/client_secret
2. NGINX proxies to Auth0 token endpoint
3. Auth0 validates credentials and returns access token
4. NGINX returns token to 3rd party
5. 3rd party → NGINX /api/* with JWT (bypasses Session Gateway)
6. NGINX validates JWT and routes to services
```

**Security:**
- Separate token validation logic for M2M vs user tokens
- M2M tokens have different claims structure
- Scoped permissions instead of user roles

---

## Identity Provider Abstraction Strategy

### Design Goal
Prevent vendor lock-in by abstracting identity provider behind NGINX endpoints. Clients never directly interact with Auth0 or know which provider is used.

### Implementation

**All authentication endpoints proxied through NGINX:**
- `/auth/authorize` - Initiate OAuth flow
- `/auth/token` - Token exchange and refresh
- `/auth/callback` - OAuth callback handler
- `/auth/logout` - End session
- `/auth/jwks` - Public keys (optional)

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
- Clients: No changes (still call NGINX /auth/*)
- Session Gateway: Update OAuth configuration
- NGINX: Update proxy_pass destinations
- Services: No changes (still validate JWT signatures)

---

## Security Considerations

### Defense in Depth Layers

**Layer 1: Session Gateway**
- Manages user authentication lifecycle
- Prevents token exposure to browser
- HTTP-only, Secure, SameSite cookies
- Session timeout and absolute expiration

**Layer 2: NGINX API Gateway**
- Independent JWT validation (don't trust upstream)
- Rate limiting per user/client
- Request sanitization
- DDoS protection

**Layer 3: Token Validation Service**
- Cryptographic signature verification
- Claims validation (issuer, audience, expiration)
- Cached public key rotation handling

**Layer 4: Backend Services**
- Data-level authorization
- Query scoping by authenticated user
- Audit logging of sensitive data access
- Database row-level security (optional)

### Token Configuration

**Access Token:**
- Lifetime: 15-30 minutes
- Algorithm: RS256 (asymmetric)
- Claims: sub, iss, aud, exp, iat, roles/scopes

**Refresh Token:**
- Lifetime: 8 hours (web), 30 days (mobile)
- Rotation: Issue new refresh token on each use
- Storage: Redis (web), Secure storage (mobile)
- Revocation: Supported via token introspection

**Session Cookie:**
- HttpOnly: true (prevents JavaScript access)
- Secure: true (HTTPS only)
- SameSite: Strict (CSRF protection)
- Max-Age: 30 minutes (matches access token)

### Threat Mitigation

| Threat | Mitigation |
|--------|-----------|
| XSS token theft | Tokens never in browser; HTTP-only cookies |
| Token replay | Short expiration; signature validation |
| CSRF | SameSite cookies; CSRF tokens on state changes |
| Unauthorized data access | Service-layer authorization by user ID |
| Credential stuffing | Rate limiting at NGINX; Auth0 anomaly detection |
| Token tampering | RSA signature verification |
| Man-in-the-middle | HTTPS/TLS everywhere; HSTS headers |

---

## Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Session Gateway | Spring Cloud Gateway | Team expertise; minimal code; OAuth 2.0 native support |
| API Gateway | NGINX | Industry standard; proven reliability; operational maturity |
| Session Store | Redis | Fast; distributed; Spring Session integration |
| Identity Provider | Auth0 (abstracted) | Managed service; swappable via NGINX proxy |
| Token Validation | Spring Boot | Consistent with microservices; Spring Security JWT |
| Backend Services | Spring Boot | Existing architecture; team expertise |

---

## Deployment Architecture

### High Availability Configuration

```
┌──────────────────────────────────────────────────────────────┐
│                    Load Balancer (ALB)                        │
└────────┬────────────────────────────┬──────────────────────────┘
         │                            │
    ┌────▼────┐                  ┌────▼────┐
    │ Session │                  │ Session │
    │ Gateway │◄────────────────►│ Gateway │
    │   (1)   │   Redis Cluster  │   (2)   │
    └────┬────┘                  └────┬────┘
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

**Metrics to Track:**
- Session Gateway: Active sessions, token refresh rate, OAuth flow success/failure
- NGINX: Request rate, error rate, latency percentiles
- Token Validation: Validation failures, public key cache hits
- Services: Authorization failures, data access patterns

**Alerting Thresholds:**
- Token validation failure rate > 1%
- Session Gateway error rate > 0.5%
- JWT expiration before refresh > 0.1%
- Unauthorized data access attempts

### Logging Strategy

**Audit Logging (Required for Financial Data):**
- All authentication events (login, logout, token refresh)
- All authorization failures
- All sensitive data access with user context
- Token validation failures

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
- Key pattern: `spring:session:sessions:{session-id}`
- TTL: 30 minutes (sliding expiration)
- Eviction policy: allkeys-lru
- Persistence: AOF for crash recovery

**Session Cleanup:**
- Expired sessions automatically removed by Redis TTL
- Explicit session invalidation on logout
- Bulk session revocation capability for security incidents

---

## Migration and Rollout Plan

### Phase 1: Infrastructure Setup
1. Deploy Redis cluster
2. Deploy Session Gateway (Spring Cloud Gateway)
3. Configure NGINX proxy rules
4. Set up monitoring and alerting

### Phase 2: Authentication Integration
1. Configure Session Gateway with Auth0
2. Test OAuth flows (authorization code + PKCE)
3. Test token refresh mechanism
4. Verify session management

### Phase 3: API Integration
1. Update React app to use Session Gateway
2. Test authenticated API calls
3. Verify JWT forwarding to NGINX
4. Test token expiration and refresh

### Phase 4: Security Validation
1. Penetration testing
2. Token lifecycle testing
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
4. **Token Binding:** Bind tokens to specific devices/channels
5. **GraphQL Gateway:** Add GraphQL layer for frontend aggregation

### Scalability Considerations
1. **Geo-distributed Redis:** Multi-region session replication
2. **Edge Deployment:** Deploy Session Gateway closer to users
3. **Token Caching:** Cache validated tokens to reduce validation overhead
4. **API Gateway Sharding:** Split NGINX by service domain

---

## Appendix: Key Decision Log

| Decision | Rationale |
|----------|-----------|
| Use BFF pattern | Maximum security for browser-based financial application |
| Keep NGINX as API gateway | Industry standard; operational maturity; team familiarity |
| Spring Cloud Gateway for BFF | Team expertise; minimal code; native OAuth support |
| Abstract identity provider | Prevent vendor lock-in; centralized control |
| RS256 token algorithm | Asymmetric signing; public key distribution |
| 15-30 min access token lifetime | Balance security vs user experience |
| Proactive token refresh | Avoid request failures due to expiration |
| Service-layer authorization | Defense in depth; protect against gateway bypass |
| Redis for sessions | Performance; distributed architecture; Spring integration |

---

## Document Approval

**Prepared by:** Senior Software Architect  
**Review Required:** Security Team, DevOps Team, Engineering Leadership  
**Next Review Date:** Upon architecture changes or security incidents

---

**End of Document**
