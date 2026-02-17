# Budget Analyzer Authentication & Authorization Implementation Plan

**Version:** 1.0
**Date:** November 10, 2025
**Status:** In Progress - Phase 5 (Completed) → Next: Phase 6 Testing

---~

## Current Progress

### ✅ Phase 1: Infrastructure Setup - COMPLETED
- Redis added to Docker Compose
- Session Gateway service created
- Token Validation Service created
- Auth0 account set up
- Docker Compose updated

### ✅ Phase 2: Session Gateway Implementation - COMPLETED
- OAuth2 Client configured
- Session management with Redis configured
- Token relay implemented
- Proactive token refresh implemented
- Logout endpoint implemented

### ✅ Phase 3: NGINX Configuration - COMPLETED
- Task 3.1: Auth0 abstraction endpoints configured (JWKS and discovery endpoints ready for production)
- Task 3.2: JWT validation with auth_request configured (Token Validation Service integration)
- Task 3.3: All API routes protected with JWT validation (auth_request directive on all /api/* routes)
- Task 3.4: Rate limiting applied to all API routes (100 req/min per user/IP with configurable burst limits)
- Task 3.5: Security headers configured (X-Content-Type-Options, X-Frame-Options, CSP, etc.)
- **Note**: CORS not needed - same-origin architecture (Session Gateway is entry point)

### ✅ Phase 4: Backend Service Authorization - COMPLETED
- Task 4.1: OAuth2 Resource Server added to Transaction Service
- Task 4.2: JWT validation configured in Transaction Service
- Task 4.3: Data-level authorization implemented in Transaction Service
- Task 4.4: Method-level security added
- Task 4.5: Currency Service configured with OAuth2 Resource Server

### ✅ Phase 5: React Frontend Integration - COMPLETED
- Task 5.1: No direct Auth0 integration to remove (confirmed clean)
- Task 5.2: Login flow implemented (redirects to Session Gateway OAuth flow)
- Task 5.3: Logout flow implemented (calls Session Gateway /logout endpoint)
- Task 5.4: Frontend base URL configured (all requests go through Session Gateway port 8081)
- Task 5.5: Session state management implemented (calls /user endpoint)
- Task 5.6: Development vs production settings documented
- **Key changes:**
  - `useAuth` hook refactored for session-based auth
  - API client configured with `withCredentials: true`
  - Login page created with Auth0 redirect
  - User types updated to match Session Gateway response
  - Session Gateway configured with frontend route
  - Comprehensive authentication documentation created

### 🚧 Phase 6: Testing & Validation - IN PROGRESS

**Issue #1: CORS Errors on Unauthenticated API Requests - RESOLVED**

- **Symptom**: Frontend at `localhost:8081` making XHR request to `/api/v1/transactions` received CORS error when redirected to Auth0
- **Root Cause Discovery Process**:
  1. **Initial hypothesis**: Spring Security WebFlux's `.oauth2Login()` overrides custom exception handling
  2. **First attempt**: Created custom `ApiOrBrowserAuthenticationEntryPoint` class → Failed (never invoked)
  3. **Second attempt**: Used `DelegatingServerAuthenticationEntryPoint` with `HttpStatusServerEntryPoint` → Failed (still redirected)
  4. **Breakthrough with logging**: Added comprehensive logging that revealed:
     - DelegatingServerAuthenticationEntryPoint WAS matching `/api/**` correctly ✓
     - Custom lambda WAS executing ✓
     - `HttpStatusServerEntryPoint.commence()` WAS setting 401 status ✓
     - **BUT** OAuth2 filter was still redirecting to Auth0 ✗
  5. **Root cause identified**: `HttpStatusServerEntryPoint.commence()` sets status code but **does NOT commit the response**
     - In Spring WebFlux, uncommitted responses can be modified by subsequent filters
     - OAuth2 login filter runs after the entry point and overwrites 401 with 302 redirect
     - The redirect to Auth0 causes CORS error in browser
- **Solution Implemented**:
  - Use `DelegatingServerAuthenticationEntryPoint` with explicit path matchers ✓
  - For `/api/**` requests: **Manually set status AND commit response**:
    ```java
    exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
    return exchange.getResponse().setComplete(); // ← Critical: commits response
    ```
  - For other requests: `RedirectServerAuthenticationEntryPoint` redirects to OAuth2
  - **Key insight**: `setComplete()` commits the response, preventing OAuth2 filter from modifying it
- **Technical Deep Dive**:
  - `HttpStatusServerEntryPoint.commence()` returns `Mono.fromRunnable(() → setStatusCode())`
  - This sets the status but does NOT call `setComplete()`
  - Response remains uncommitted → mutable by subsequent filters
  - OAuth2AuthorizationRequestRedirectFilter sees unauthenticated request and redirects
  - Solution: Explicitly commit response with `exchange.getResponse().setComplete()`
- **Why Previous Approaches Failed**:
  1. **Custom `ApiOrBrowserAuthenticationEntryPoint`**: Never invoked due to oauth2Login precedence
  2. **`DelegatingServerAuthenticationEntryPoint` + `HttpStatusServerEntryPoint`**: Matched correctly but didn't commit response
  3. **Final working solution**: `DelegatingServerAuthenticationEntryPoint` + manual status + `setComplete()`
- **References**:
  - Spring Security Issue #9266: "WebFlux security should not overwrite the default entry point"
  - Spring Security Issue #6812: "oauth2Login does not auto-redirect for XHR request"
  - Spring WebFlux `ServerHttpResponse.setComplete()` JavaDoc: "Indicate that message handling is complete"
- **Files Modified**:
  - Modified: `/workspace/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/SecurityConfig.java`
    - Replaced `HttpStatusServerEntryPoint.commence()` with manual status + `setComplete()`
    - Removed unused `HttpStatusServerEntryPoint` import
    - Added logging to verify execution flow
    - Updated JavaDoc to explain response commitment requirement
  - Deleted: `/workspace/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/ApiOrBrowserAuthenticationEntryPoint.java`
  - Created (for debugging): `/workspace/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/RequestLoggingFilter.java`

**Issue #2: OAuth2 Redirect Loop at Auth0 Consent Screen - IN PROGRESS**

- **Symptom**: User authenticates with Auth0 (social login: Google/Apple/Facebook), sees consent screen, accepts consent, then gets stuck in a loop back to consent screen
- **URL stuck at**: `https://dev-gcz1r8453xzz0317.us.auth0.com/u/consent?state=...`
- **Configuration verified**:
  - Auth0 Client ID: `Pd4L6ijQmJhqx8tgqpuTiRRg5uKKAVyh`
  - Auth0 Domain: `dev-gcz1r8453xzz0317.us.auth0.com`
  - Callback URL already configured in Auth0: `https://app.budgetanalyzer.localhost/login/oauth2/code/auth0`
  - Social providers enabled: Google, Apple, Facebook
- **Debugging approach**:
  - User wants to debug with consent ENABLED (not skip) to understand the full flow
  - Added comprehensive logging to trace OAuth2 callback flow
- **Files Modified**:
  - Modified: `/workspace/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/OAuth2ClientConfig.java`
    - Added logging to show exact redirect_uri being sent to Auth0
    - Wrapped authorization request resolver to log final authorization request
  - Modified: `/workspace/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/SecurityConfig.java`
    - Enhanced success/failure handlers with detailed logging
    - Added request URI logging to trace callback
  - Created: `/workspace/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/RequestLoggingWebFilter.java`
    - Logs all OAuth2-related incoming requests
  - Fixed: `/workspace/session-gateway/.env`
    - Changed `AUTH0_LOGOUT_RETURN_TO` from `http://localhost:8080` to `https://app.budgetanalyzer.localhost`
- **Understanding Two Consent Screens**:
  - **Social Provider Consent** (Google/Apple/Facebook): "Allow Budget Analyzer to access your Google profile?" - REQUIRED, CANNOT be skipped, controlled by social provider
  - **Auth0 Application Consent**: "Allow Budget Analyzer to access your email?" - OPTIONAL, can be skipped for first-party apps, controlled by Auth0 "Skip User Consent" setting
  - User preference: Debug with both consent screens enabled to understand full flow

**Next Steps**:
- User will rebuild Session Gateway and test
- Check logs for exact redirect_uri being sent to Auth0
- Check logs for callback request from Auth0
- Verify callback is reaching `/login/oauth2/code/auth0`
- Check for authentication success/failure messages
- If callback is failing, investigate why Spring Security isn't processing it

---

## Architecture Summary

This plan implements the security architecture defined in `security-architecture.md` with the following components:

### Component Overview

- **NGINX Gateway**: Port 443 (HTTPS) - SSL termination, validates JWTs, routes to microservices, serves React frontend
- **Session Gateway (BFF)**: Spring Cloud Gateway on port 8081 (internal) - manages OAuth flows, stores tokens in Redis, issues session cookies
- **Token Validation Service**: Port 8088 (internal) - validates JWT signatures for NGINX (auth_request)
- **Auth0**: Identity provider (abstracted behind NGINX /auth/* endpoints)
- **Backend Services**: Transaction Service (8082), Currency Service (8084) - enforce data-level authorization

### BFF + API Gateway Hybrid Pattern

This architecture implements a **hybrid BFF + API Gateway pattern**, which is the industry-standard approach for securing browser-based applications while supporting multiple client types:

**BFF (Backend for Frontend) Layer:**
- Session Gateway handles web browser-specific concerns
- OAuth2/OIDC authentication flows
- Session management (HTTP-only cookies)
- Token lifecycle (refresh, expiration)
- Proxies authenticated requests to API Gateway

**API Gateway Layer:**
- NGINX handles shared infrastructure concerns
- JWT validation (all requests)
- Request routing to microservices
- Rate limiting and DDoS protection
- Static file serving (React frontend)
- Load balancing

**Why This Hybrid Approach:**
- **Separation of Concerns**: BFF handles client-specific auth, Gateway handles shared routing/security
- **Multiple Client Support**: Web browsers use BFF (session cookies), M2M clients use Gateway directly (JWTs)
- **Defense in Depth**: Multiple validation layers (BFF → Gateway → Services)
- **Industry Standard**: Recommended pattern from Auth0, Duende, Curity, and other OAuth2 experts

### Complete Request Flow Documentation

#### **Flow 1: Web Browser Authentication & API Request**

This is the primary flow for browser-based users accessing the application:

```
┌─────────┐
│ Browser │
└────┬────┘
     │ 1. User navigates to https://app.budgetanalyzer.localhost
     ├──────────────────────────────────────────────────────────────┐
     │                                                               │
     ▼                                                               │
┌─────────────────────────┐                                         │
│  Session Gateway :8081  │  (Spring Cloud Gateway - BFF Pattern)  │
│  ───────────────────    │                                         │
│  • OAuth2 flows         │                                         │
│  • Session cookies      │                                         │
│  • Token storage (Redis)│                                         │
└────┬────────────────────┘                                         │
     │ 2. If not authenticated → redirect to Auth0                 │
     │ 3. After Auth0 → JWT stored in Redis session               │
     │ 4. Frontend proxies to NGINX (serves React app)            │
     ├──────────────────────────────────────────────────────────┐  │
     │                                                           │  │
     │ 5. API Request: GET /api/v1/transactions                 │  │
     │    Cookie: SESSION=<session-id>                           │  │
     │    Session Gateway looks up JWT from Redis                │  │
     │    Adds: Authorization: Bearer <jwt>                      │  │
     │                                                           │  │
     ▼                                                           │  │
┌───────────────────────────┐                                   │  │
│   NGINX Gateway :8080     │  (API Gateway + Reverse Proxy)   │  │
│   ─────────────────       │                                   │  │
│   • Receives JWT          │                                   │  │
│   • auth_request enabled  │                                   │  │
└────┬──────────────────────┘                                   │  │
     │ 6. NGINX makes internal subrequest for JWT validation    │  │
     │    auth_request /auth/validate                           │  │
     │    Forwards: Authorization: Bearer <jwt>                 │  │
     │              X-Original-URI: /api/v1/transactions        │  │
     │                                                           │  │
     ▼                                                           │  │
┌─────────────────────────────────┐                             │  │
│ Token Validation Service :8088  │  (JWT Validator)           │  │
│ ───────────────────────────     │                             │  │
│ • Validates JWT signature       │                             │  │
│ • Checks expiration             │                             │  │
│ • Validates issuer (Auth0)      │                             │  │
│ • Validates audience            │                             │  │
│ • Fetches JWKS from Auth0       │                             │  │
└────┬────────────────────────────┘                             │  │
     │ 7. Returns:                                               │  │
     │    200 OK with X-JWT-User-Id: <user-id>   (valid JWT)   │  │
     │    OR 401 Unauthorized (invalid JWT)                     │  │
     │                                                           │  │
     ▼                                                           │  │
┌───────────────────────────┐                                   │  │
│   NGINX Gateway :8080     │                                   │  │
│   ─────────────────       │                                   │  │
│   • If 200: continue      │                                   │  │
│   • If 401: return 401    │                                   │  │
│   • Extracts user ID:     │                                   │  │
│     auth_request_set      │                                   │  │
│     $jwt_user_id          │                                   │  │
└────┬──────────────────────┘                                   │  │
     │ 8. Forwards to backend service                           │  │
     │    Authorization: Bearer <jwt>                           │  │
     │    X-User-Id: <user-id>                                  │  │
     │                                                           │  │
     ▼                                                           │  │
┌──────────────────────────┐                                    │  │
│ Transaction Service :8082│  (Business Logic)                  │  │
│ ────────────────────     │                                    │  │
│ • Receives validated JWT │                                    │  │
│ • JWT already validated  │ ◄─ DEFENSE IN DEPTH:              │  │
│   by Token Validation    │    Backend services CAN validate   │  │
│   Service                │    JWTs but NGINX already did it   │  │
│ • Enforces data-level    │                                    │  │
│   authorization          │                                    │  │
│ • Returns data           │                                    │  │
└────┬─────────────────────┘                                    │  │
     │ 9. Response flows back                                   │  │
     │                                                           │  │
     │ Backend → NGINX → Session Gateway → Browser             │  │
     └───────────────────────────────────────────────────────────┘  │
                                                                    │
Response arrives at browser ◄───────────────────────────────────────┘
```

#### **Flow 2: M2M Client Direct API Access**

Machine-to-machine clients bypass Session Gateway and use JWT directly:

```
┌──────────────┐
│ M2M Client   │
│ (API Client) │
└──────┬───────┘
       │ 1. Obtains JWT from Auth0 (Client Credentials flow)
       │    POST /auth/token with client_id & client_secret
       │    Response: { access_token: <jwt> }
       │
       │ 2. Makes API request with JWT
       │    GET /api/v1/transactions
       │    Authorization: Bearer <jwt>
       │
       ▼
┌───────────────────────────┐
│   NGINX Gateway :8080     │
│   ─────────────────       │
│   • Receives JWT          │
│   • auth_request /auth/validate
└────┬──────────────────────┘
       │ 3. Same validation flow as browser
       │    (Token Validation Service validates JWT)
       ▼
┌──────────────────────────┐
│ Backend Service          │
│ • Returns data           │
└──────────────────────────┘
```

#### **Key Architectural Points**

1. **Token Validation Service is the SINGLE source of truth for JWT validation**
   - NGINX delegates ALL JWT validation to this service via `auth_request`
   - Backend services receive pre-validated JWTs
   - Defense in depth: Backend services CAN validate JWTs but shouldn't need to

2. **Session Gateway is ONLY for browser-based authentication**
   - Handles OAuth2 flows (Auth0 redirects)
   - Stores JWTs in Redis (not in browser)
   - Issues HTTP-only session cookies
   - M2M clients bypass this entirely

3. **NGINX acts as the central gateway**
   - Routes ALL API requests (browser and M2M)
   - Validates JWTs before proxying to backend
   - Extracts user ID and forwards to backend
   - Handles rate limiting and security headers

4. **Port Summary**
   - **443**: NGINX Gateway - HTTPS entry point (app.budgetanalyzer.localhost / api.budgetanalyzer.localhost)
   - **8081**: Session Gateway - Internal (behind NGINX)
   - **8088**: Token Validation Service - JWT validator (internal)
   - **8082**: Transaction Service - Business logic (internal)
   - **8084**: Currency Service - Business logic (internal)
   - **3000**: React Dev Server - Frontend (dev only, internal)

#### **Web Browser Request Flow (Detailed Steps)**

1. **Browser → Session Gateway (8081)**
   - User navigates to `https://app.budgetanalyzer.localhost`
   - If not authenticated, redirect to Auth0 OAuth flow
   - After authentication, JWT stored in Redis, session cookie issued

2. **Browser → Session Gateway (8081) - API Request**
   - Browser makes API call: `GET https://app.budgetanalyzer.localhost/api/v1/transactions`
   - Includes session cookie: `Cookie: SESSION=<session-id>`

3. **Session Gateway → Redis**
   - Looks up session by session ID
   - Retrieves JWT from Redis session

4. **Session Gateway → NGINX (8080)**
   - Proxies request to NGINX
   - Adds JWT: `Authorization: Bearer <jwt>`
   - Forwards original path: `GET http://localhost:8080/api/v1/transactions`

5. **NGINX → Token Validation Service (8088) - Internal Subrequest**
   - NGINX directive: `auth_request /auth/validate;`
   - Makes internal GET request: `GET http://localhost:8088/auth/validate`
   - Forwards: `Authorization: Bearer <jwt>`, `X-Original-URI: /api/v1/transactions`

6. **Token Validation Service Processing**
   - Spring Security OAuth2 Resource Server validates JWT:
     - Signature validation using Auth0 JWKS
     - Expiration check
     - Issuer validation (Auth0 domain)
     - Audience validation (API identifier)
   - If valid: Returns `200 OK` with `X-JWT-User-Id: <user-id>`
   - If invalid: Returns `401 Unauthorized` with error details

7. **NGINX Processing**
   - If Token Validation Service returns 401 → NGINX returns 401 to Session Gateway
   - If Token Validation Service returns 200:
     - NGINX directive: `auth_request_set $jwt_user_id $upstream_http_x_jwt_user_id;`
     - Extracts user ID from response header
     - Continues to backend service

8. **NGINX → Backend Service (8082/8084)**
   - Forwards request with headers:
     - `Authorization: Bearer <jwt>` (original JWT)
     - `X-User-Id: <user-id>` (extracted by NGINX)
   - Backend receives pre-validated JWT

9. **Backend Service Processing**
   - JWT already validated by Token Validation Service
   - Enforces data-level authorization (e.g., `WHERE user_id = :userId`)
   - Returns response

10. **Response Chain**
    - Backend → NGINX → Session Gateway → Browser
    - Browser receives API response

**Key Insight:** Session Gateway is NOT a replacement for NGINX - it's a complementary layer specifically for browser-based authentication security.

### Machine-to-Machine (M2M) Authentication

**M2M clients bypass the Session Gateway** and use OAuth2 Client Credentials flow directly with NGINX:

**Flow:**
1. M2M client calls NGINX `/auth/token` endpoint with `client_id` and `client_secret`
2. NGINX proxies request to Auth0 token endpoint
3. Auth0 validates credentials and returns JWT access token
4. M2M client makes API requests to NGINX with JWT in Authorization header
5. NGINX validates JWT (via Token Validation Service) and routes to backend services

**Key Differences from Browser Flow:**
- No session cookies (stateless)
- No Session Gateway involvement
- Direct JWT usage (not hidden behind BFF)
- Scoped permissions instead of user roles
- Longer token lifetime (configured in Auth0)

**Production Access:**
- M2M clients use `api.budgetanalyzer.com` hostname
- Load balancer routes to NGINX (8080) directly
- Separate from web browser traffic (`budgetanalyzer.com` → Session Gateway)

**Security:**
- Client credentials stored securely (not in browser)
- Token Validation Service validates JWT signatures
- Rate limiting applied per client_id
- NGINX enforces API authorization independent of Session Gateway

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
- Port: 8088

### Task 1.4: Set Up Auth0 Account
- Create Auth0 account and tenant
- Create Application: "budget-analyzer-web" (Regular Web Application)
- Configure Allowed Callback URLs: https://app.budgetanalyzer.localhost/login/oauth2/code/auth0
- Configure Allowed Logout URLs: https://app.budgetanalyzer.localhost/, https://app.budgetanalyzer.localhost
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
- **Configure frontend route**: / → http://nginx-gateway:8080/ (proxy to React app served by NGINX)

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
- Proxy /auth/token → Auth0 token endpoint (for M2M Client Credentials flow)
- Proxy /.well-known/openid-configuration → Auth0 discovery (for Token Validation Service)
- Proxy /.well-known/jwks.json → Auth0 JWKS (for JWT signature verification)
- **Note**: Session Gateway handles OAuth flows for browsers (/oauth2/authorization, /login/oauth2/code, /logout)
- **Note**: M2M clients use /auth/token on NGINX directly (bypassing Session Gateway)

### Task 3.2: Configure JWT Validation with auth_request
- Add internal location `/auth/validate`
- Configure auth_request to call Token Validation Service (port 8088)
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

### Task 3.5: Configure Security Headers
- Add security headers: HSTS, X-Content-Type-Options, X-Frame-Options, X-XSS-Protection
- Configure CSP (Content Security Policy) headers
- Configure Referrer-Policy headers
- **Note**: CORS not needed - Session Gateway (8081) is single entry point for browsers (same-origin)

---

## Phase 4: Backend Service Authorization (Week 4)

### Task 4.1: Add OAuth2 Resource Server to Transaction Service
- Add spring-security-oauth2-resource-server dependency
- Configure JWT decoder with Auth0 issuer URI
- Create SecurityConfig with JWT authentication

### Task 4.2: Configure JWT Validation in Transaction Service
- Set issuer-uri in application.yml
- Configure audience validation (budget-analyzer-api)
- Extract roles/scopes from JWT claims
- Map to Spring Security authorities

### Task 4.3: Implement Data-Level Authorization in Transaction Service
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
- Redirect to Session Gateway: `window.location.href = 'https://app.budgetanalyzer.localhost/oauth2/authorization/auth0'`
- Session Gateway handles OAuth flow, sets session cookie, redirects back to frontend

### Task 5.3: Implement Logout Flow
- Create logout function
- Call Session Gateway logout endpoint: `https://app.budgetanalyzer.localhost/logout`
- Clear any local state
- Redirect to home page

### Task 5.4: Configure Frontend Base URL
- **All requests go through NGINX to Session Gateway**
- Frontend base URL: `https://app.budgetanalyzer.localhost`
- API calls: `https://app.budgetanalyzer.localhost/api/*` (Session Gateway adds JWT, forwards to NGINX API)
- Static files: `https://app.budgetanalyzer.localhost/` (NGINX → Session Gateway → NGINX API → React)
- Include credentials in fetch: `credentials: 'include'` (for session cookies)
- **No CORS configuration needed** - same-origin (all requests to app.budgetanalyzer.localhost)

### Task 5.5: Implement Session State Management
- Check session status on app load
- Call `/user` endpoint to get current user info: `https://app.budgetanalyzer.localhost/user`
- Handle 401 responses (redirect to login)
- Display user info in UI

### Task 5.6: Development vs Production Configuration
- **Development**: Frontend accessed via `https://app.budgetanalyzer.localhost`
  - NGINX (443) handles SSL and proxies to Session Gateway (8081)
  - Session Gateway proxies API requests to NGINX API (api.budgetanalyzer.localhost)
  - NGINX API proxies to Vite dev server (3000) for React app
  - Hot module reload (HMR) works through proxy chain
- **Production**: Frontend accessed via load balancer (port 80/443)
  - Load balancer routes to NGINX (443)
  - NGINX routes to Session Gateway or API based on subdomain
  - NGINX serves static React build artifacts
- **Environment variable**: `VITE_API_BASE_URL` should be relative (`/api`)

---

## Phase 6: Testing & Validation (Week 6)

### Task 6.1: Test OAuth Flow - ✅ COMPLETED
- Test login flow end-to-end
- Verify session cookie is set (HttpOnly, Secure)
- Verify JWT is stored in Redis (not browser)
- Test logout clears session

### Task 6.2: Test JWT Validation - ✅ COMPLETED
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
- Test same-origin enforcement (all requests through Session Gateway)
- Load test with realistic user patterns
- Test M2M client flow (direct NGINX access with Client Credentials)

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

### Task 8.1: Enable HTTPS and Load Balancer Configuration
- **Load Balancer Setup**:
  - Configure GCP Load Balancer (or AWS ALB) on port 80/443
  - SSL/TLS termination at load balancer
  - Generate SSL certificates (Let's Encrypt or GCP-managed certificates)
- **Two Entry Points**:
  - `budgetanalyzer.com` → Load Balancer → Session Gateway (8081) - for web browsers
  - `api.budgetanalyzer.com` → Load Balancer → NGINX (8080) - for M2M clients
- **Internal Service Configuration**:
  - Session Gateway remains on port 8081 (internal)
  - NGINX remains on port 8080 (internal)
  - No port 80 conflict - load balancer handles external ports
- **Security Headers**:
  - Enable HSTS headers at load balancer or NGINX
  - Configure Secure flag on session cookies (HTTPS only)

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
- Review same-origin enforcement (Session Gateway entry point)
- Review rate limiting rules
- Review NGINX security headers
- Review M2M client access controls

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
- Updated: `transaction-service` - OAuth2 Resource Server
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
