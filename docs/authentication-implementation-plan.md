# Budget Analyzer Authentication & Authorization Implementation Plan

**Version:** 1.0
**Date:** November 10, 2025
**Status:** Implementation Plan

---

## Architecture Summary

This plan implements the security architecture defined in `security-architecture.md` with the following components:

- **Session Gateway (BFF)**: Spring Cloud Gateway on port 8081 - manages OAuth flows, stores tokens in Redis, issues session cookies
- **NGINX Gateway**: Port 8080 - validates JWTs, routes to microservices
- **Token Validation Service**: Port 8090 - validates JWT signatures for NGINX (auth_request)
- **Auth0**: Identity provider (abstracted behind NGINX /auth/* endpoints)
- **Backend Services**: Budget API (8082), Currency Service (8084) - enforce data-level authorization

---

## Phase 1: Infrastructure Setup (Week 1)

### Task 1.1: Add Redis to Docker Compose
- Add Redis container for session storage
- Configure persistence (AOF) for crash recovery
- Set eviction policy: allkeys-lru
- Expose port 6379 for Session Gateway

### Task 1.2: Create Session Gateway Service
- Generate new Spring Boot project with Spring Cloud Gateway
- Add dependencies: spring-cloud-gateway, spring-security-oauth2-client, spring-session-data-redis
- Configure basic gateway routing to NGINX (port 8080)
- Configure Redis session management
- Port: 8081

### Task 1.3: Create Token Validation Service
- Generate new Spring Boot project
- Add dependencies: spring-security-oauth2-resource-server, spring-boot-starter-web
- Create `/auth/validate` endpoint for NGINX auth_request
- Configure JWT decoder with Auth0 issuer URI
- Port: 8090

### Task 1.4: Set Up Auth0 Account
- Create Auth0 account and tenant
- Create Application: "budget-analyzer-web" (Regular Web Application)
- Configure Allowed Callback URLs: http://localhost:8081/login/oauth2/code/auth0
- Configure Allowed Logout URLs: http://localhost:8081/, http://localhost:3000
- Note down: Domain, Client ID, Client Secret
- Create API: "budget-analyzer-api" with identifier (audience)

### Task 1.5: Update Docker Compose
- Add redis service
- Add session-gateway service
- Add token-validation-service
- Update network configuration
- Add environment variables for Auth0 credentials (use .env file)

---

## Phase 2: Session Gateway Implementation (Week 2)

### Task 2.1: Configure OAuth2 Client in Session Gateway
- Configure Auth0 as OAuth2 provider in application.yml
- Set up Authorization Code + PKCE flow
- Configure client-id, client-secret, scopes (openid, profile, email)
- Set redirect-uri to /login/oauth2/code/auth0

### Task 2.2: Configure Session Management
- Configure Spring Session with Redis
- Set session timeout: 30 minutes
- Configure session cookie: HttpOnly, Secure, SameSite=Strict
- Enable session persistence to Redis

### Task 2.3: Configure Token Relay
- Add TokenRelay filter to automatically forward JWTs to downstream services
- Configure routes to NGINX gateway (port 8080)
- Set up path rewriting: /api/* → http://nginx-gateway:8080/api/*

### Task 2.4: Implement Proactive Token Refresh
- Create custom filter to check token expiration (5 min threshold)
- Implement refresh logic using OAuth2AuthorizedClientManager
- Update Redis session with new tokens
- Handle refresh token rotation

### Task 2.5: Implement Logout Endpoint
- Create /logout endpoint
- Invalidate Redis session
- Clear session cookie
- Redirect to Auth0 logout (then back to app)

---

## Phase 3: NGINX Configuration (Week 3)

### Task 3.1: Abstract Auth0 Behind NGINX
- Add NGINX location blocks for /auth/* endpoints
- Proxy /auth/authorize → Auth0 authorize endpoint
- Proxy /auth/token → Auth0 token endpoint
- Proxy /auth/callback → Auth0 callback (or Session Gateway handles this)
- Proxy /auth/logout → Auth0 logout
- Proxy /auth/.well-known/openid-configuration → Auth0 discovery

### Task 3.2: Configure JWT Validation with auth_request
- Add internal location `/auth/validate`
- Configure auth_request to call Token Validation Service (port 8090)
- Set proxy_pass_request_body off for efficiency
- Forward Authorization header to validation service

### Task 3.3: Update API Route Protection
- Add auth_request directive to all /api/* location blocks
- Configure auth_request_set for user context variables
- Forward JWT in Authorization header to backend services
- Handle 401 responses from validation service

### Task 3.4: Add Rate Limiting
- Configure rate limiting per IP/user
- Set reasonable limits (e.g., 100 req/min per user)
- Return 429 Too Many Requests on violations

### Task 3.5: Configure CORS and Security Headers
- Set CORS headers for frontend (port 3000)
- Add security headers: HSTS, X-Content-Type-Options, X-Frame-Options
- Configure CSP headers

---

## Phase 4: Backend Service Authorization (Week 4)

### Task 4.1: Add OAuth2 Resource Server to Budget API
- Add spring-security-oauth2-resource-server dependency
- Configure JWT decoder with Auth0 issuer URI
- Create SecurityConfig with JWT authentication

### Task 4.2: Configure JWT Validation in Budget API
- Set issuer-uri in application.yml
- Configure audience validation (budget-analyzer-api)
- Extract roles/scopes from JWT claims
- Map to Spring Security authorities

### Task 4.3: Implement Data-Level Authorization in Budget API
- Extract user ID from JWT (sub claim)
- Update repository queries to scope by user ID
- Example: SELECT * FROM transactions WHERE user_id = :userId
- Throw 403 Forbidden if user doesn't own requested resource

### Task 4.4: Add Method-Level Security
- Enable @EnableMethodSecurity
- Add @PreAuthorize annotations to service methods
- Define role-based access: @PreAuthorize("hasRole('USER')")
- Test authorization enforcement

### Task 4.5: Repeat for Currency Service
- Add OAuth2 Resource Server configuration
- Configure JWT validation
- Implement data-level authorization (if applicable)
- Add method-level security

---

## Phase 5: React Frontend Integration (Week 5)

### Task 5.1: Remove Direct Auth0 Integration (if exists)
- Remove any existing Auth0 libraries
- Frontend will NOT directly interact with Auth0
- All auth flows go through Session Gateway

### Task 5.2: Implement Login Flow
- Create Login component with "Login" button
- Redirect to Session Gateway: window.location.href = 'http://localhost:8081/oauth2/authorization/auth0'
- Session Gateway handles OAuth flow, sets session cookie, redirects back

### Task 5.3: Implement Logout Flow
- Create logout function
- Call Session Gateway logout endpoint
- Clear any local state
- Redirect to home page

### Task 5.4: Update API Calls
- Change API base URL from direct backend to Session Gateway
- From: http://localhost:8080/api/*
- To: http://localhost:8081/api/*
- Session Gateway adds JWT, forwards to NGINX
- Include credentials in fetch: credentials: 'include' (for cookies)

### Task 5.5: Implement Session State Management
- Check session status on app load
- Call /user endpoint to get current user info
- Handle 401 responses (redirect to login)
- Display user info in UI

---

## Phase 6: Testing & Validation (Week 6)

### Task 6.1: Test OAuth Flow
- Test login flow end-to-end
- Verify session cookie is set (HttpOnly, Secure)
- Verify JWT is stored in Redis (not browser)
- Test logout clears session

### Task 6.2: Test JWT Validation
- Test valid JWT allows API access
- Test expired JWT returns 401
- Test missing JWT returns 401
- Test tampered JWT returns 401
- Test invalid audience returns 401

### Task 6.3: Test Token Refresh
- Wait until token near expiration (or mock expiration)
- Verify Session Gateway refreshes automatically
- Verify user session continues without interruption
- Test refresh token rotation

### Task 6.4: Test Data-Level Authorization
- Create two test users in Auth0
- User A creates transaction
- User B attempts to access User A's transaction (should fail 403)
- Verify service layer enforces user_id scoping

### Task 6.5: Test Edge Cases
- Test concurrent requests during token refresh
- Test session timeout (30 min idle)
- Test rate limiting triggers 429
- Test CORS from frontend origin
- Load test with realistic user patterns

---

## Phase 7: Service-to-Service Auth Design (Future - No Implementation Yet)

**NOTE:** No service-to-service traffic currently exists. This phase is design-only to ensure current implementation doesn't preclude future requirements.

### Task 7.1: Document Service-to-Service Strategy
- Document OAuth2 Client Credentials flow for future
- Document mTLS layer for future (manual → Linkerd)
- Create architecture diagram showing future state
- No code implementation - just design documentation

### Task 7.2: Design Client Credentials Flow
- Document how services will register as OAuth2 clients in Auth0
- Define scopes for service-to-service calls (e.g., currency:read)
- Document Spring Boot OAuth2 client configuration (for future)
- Document RestClient configuration with OAuth2 interceptor (for future)

### Task 7.3: Design mTLS Layer
- Document manual mTLS approach for initial implementation
- Document certificate generation process (CA, service certs)
- Document Spring Boot mTLS configuration
- Document NGINX mTLS configuration
- Create certificate rotation runbook

### Task 7.4: Design Linkerd Migration Path
- Document when to migrate to Linkerd (5+ services, Kubernetes production)
- Document Linkerd installation process
- Document service injection strategy
- Document automatic mTLS verification
- Note: Linkerd is FREE (open source), no license costs

### Task 7.5: Update Security Architecture Document
- Add service-to-service section with layered approach (mTLS + OAuth2)
- Document defense-in-depth: transport layer (mTLS) + application layer (OAuth2)
- Add decision log for future service-to-service implementation
- Document that implementation is deferred until needed

---

## Phase 8: Production Hardening (Week 7-8)

### Task 8.1: Enable HTTPS
- Generate SSL certificates (Let's Encrypt for production)
- Configure NGINX SSL termination
- Update Session Gateway to require HTTPS
- Update frontend to use HTTPS
- Enable HSTS headers

### Task 8.2: Implement Monitoring
- Add metrics for Session Gateway (active sessions, token refresh rate)
- Add metrics for NGINX (request rate, error rate, latency)
- Add metrics for Token Validation Service (validation failures)
- Add audit logging for authentication events
- Set up alerting thresholds

### Task 8.3: Implement Audit Logging
- Log all login/logout events
- Log all authorization failures (401, 403)
- Log sensitive data access (with user context)
- Use structured JSON logging format
- Configure log retention policies

### Task 8.4: Security Review
- Review token lifetimes (access: 15-30 min, refresh: 8 hours)
- Review session configuration (HttpOnly, Secure, SameSite)
- Review CORS policies
- Review rate limiting rules
- Review NGINX security headers

### Task 8.5: Documentation
- Document architecture for team
- Create runbooks for common operations
- Document troubleshooting guides
- Document Auth0 configuration
- Document local development setup

---

## Deliverables

### Code Repositories
- `session-gateway` - Spring Cloud Gateway BFF (new repo)
- `token-validation-service` - JWT validator for NGINX (new repo)
- Updated: `budget-analyzer` - Docker Compose with all services
- Updated: `budget-analyzer-api` - OAuth2 Resource Server
- Updated: `currency-service` - OAuth2 Resource Server
- Updated: `budget-analyzer-web` - Session Gateway integration

### Configuration
- Auth0 tenant configured
- Redis cluster for sessions
- NGINX with auth_request and IdP abstraction
- Environment variables and secrets management

### Documentation
- Security architecture (updated)
- Service-to-service design (for future)
- API authentication guide
- Troubleshooting guide
- Runbooks for operations

---

## Key Design Principles

1. **BFF Pattern**: Session Gateway protects tokens from browser (XSS protection)
2. **Defense in Depth**: Session Gateway → NGINX validation → Service authorization
3. **IdP Abstraction**: All auth flows through NGINX /auth/* (can swap Auth0 later)
4. **Data-Level Security**: Services always scope queries by authenticated user
5. **Service-to-Service**: Designed but not implemented (deferred until needed)
6. **Zero Trust**: Every layer validates, no implicit trust

---

## Service-to-Service Authentication (Future Design)

### Current State
- No service-to-service communication currently exists
- Implementation deferred until needed
- Design documented to ensure compatibility

### Future Architecture: Layered Security

When services need to communicate, implement **both** layers:

#### Layer 1: OAuth2 Client Credentials (Application Layer)
**Purpose:** Authorizes "what" the service can do

**Flow:**
1. Service A requests token from Auth0 using client_id/client_secret
2. Auth0 issues access token with specific scopes (e.g., `currency:read`)
3. Service A includes token in Authorization header when calling Service B
4. Service B validates token and checks scopes

**Implementation:**
```java
// Spring Boot OAuth2 Client configuration
@Configuration
public class OAuth2ClientConfig {
    @Bean
    public RestClient restClient(OAuth2AuthorizedClientManager clientManager) {
        // Automatic token management
    }
}
```

**Scopes:**
- `transactions:read` - Read transaction data
- `transactions:write` - Create/update transactions
- `currency:read` - Read currency data
- `currency:write` - Update exchange rates
- `admin:all` - Full administrative access

#### Layer 2: mTLS (Transport Layer)
**Purpose:** Authenticates "who" the service is

**Initial Implementation: Manual mTLS**
- Generate CA and service certificates using OpenSSL or certstrap
- Configure Spring Boot with keystore/truststore
- Configure NGINX for bidirectional mTLS
- Quarterly certificate rotation (initially)

**Future Migration: Linkerd Service Mesh**
- When: 5+ services or Kubernetes production deployment
- Automatic mTLS with zero configuration
- 24-hour certificate lifetime with automatic rotation
- Built-in observability

**Migration Trigger Points:**
- Growing to 5+ microservices
- Certificate management becomes burden
- Moving to Kubernetes for production
- Need for service mesh observability

### Why Both Layers?

**Defense-in-Depth Security:**
```
mTLS Layer (Transport)
├─ Verifies cryptographic service identity
├─ Encrypts all traffic
└─ Prevents unauthorized services from connecting

OAuth2 Layer (Application)
├─ Granular permission control (scopes)
├─ Dynamic access management
└─ Token-based authorization per request
```

**Together:** Maximum security with operational flexibility

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
| Future Service Mesh | Linkerd | Free; lightweight; automatic mTLS; simple |

---

## Timeline Summary

- **Weeks 1-2**: Infrastructure + Session Gateway (BFF)
- **Weeks 3-4**: NGINX + Backend Services
- **Week 5**: React Frontend
- **Week 6**: Testing & Validation
- **Week 7**: Service-to-Service Design (documentation only)
- **Week 8**: Production Hardening

**Total**: ~8 weeks for complete production-ready authentication & authorization

---

## Implementation Notes

### Auth0 Costs
- Free tier: 7,000 Monthly Active Users (MAU)
- Paid plans: Starting at $35/month for 1,000 MAU
- Budget Analyzer likely fits free tier initially

### Linkerd Costs
- **FREE** - Open source software, no licensing fees
- Only cost is infrastructure (CPU/memory for proxies)
- Extremely lightweight compared to Istio

### Security Compliance
- Auth0 manages: SOC 2, ISO 27001, GDPR compliance
- You remain responsible for: Application security, data protection, audit logging
- Audit logging requirements for financial data addressed in Phase 8

### Development Environment
- Docker Compose for local development
- All services run locally on host.docker.internal
- Kubernetes manifests for production (future)

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Auth0 vendor lock-in | Abstract behind NGINX /auth/* endpoints |
| Session hijacking | HttpOnly, Secure, SameSite cookies; short timeouts |
| Token exposure | BFF pattern keeps tokens server-side |
| Unauthorized data access | Service-layer authorization by user ID |
| Service-to-service auth | Designed for layered security (OAuth2 + mTLS) |
| Certificate management | Document migration to Linkerd when needed |

---

## Success Criteria

### Phase 1-6 (Must Have)
- [ ] Users can log in via Auth0 through Session Gateway
- [ ] JWTs never exposed to browser JavaScript
- [ ] Session cookies are HttpOnly, Secure, SameSite
- [ ] NGINX validates all API requests
- [ ] Backend services enforce data-level authorization
- [ ] Token refresh happens automatically
- [ ] Logout invalidates sessions
- [ ] Rate limiting prevents abuse
- [ ] All authentication events are logged

### Phase 7 (Design Only)
- [ ] Service-to-service authentication strategy documented
- [ ] OAuth2 Client Credentials flow designed
- [ ] mTLS implementation approach documented
- [ ] Linkerd migration path defined
- [ ] No breaking changes to current implementation

### Phase 8 (Production Ready)
- [ ] HTTPS enabled everywhere
- [ ] Monitoring and alerting configured
- [ ] Audit logs capture all security events
- [ ] Security review completed
- [ ] Documentation complete
- [ ] Load testing validates performance

---

## References

- [security-architecture.md](./security-architecture.md) - Overall security design
- [service-layer-architecture.md](./service-layer-architecture.md) - Service implementation patterns
- [CLAUDE.md](../CLAUDE.md) - Overall project context

---

**End of Document**
