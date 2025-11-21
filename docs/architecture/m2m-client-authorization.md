# Machine-to-Machine (M2M) Client Authorization

This document describes the authorization flow for third-party applications and services that need to access Budget Analyzer APIs programmatically, without user interaction.

## Overview

M2M (Machine-to-Machine) authentication allows external systems to securely access Budget Analyzer APIs using OAuth 2.0 Client Credentials flow. This is distinct from user authentication, which uses the BFF pattern with session cookies.

### When to Use M2M Authentication

| Use Case | Authentication Method |
|----------|----------------------|
| Browser-based user access | BFF pattern (Session Gateway + session cookies) |
| Third-party integrations | M2M (Client Credentials + JWT) |
| Backend service-to-service | M2M (Client Credentials + JWT) |
| Mobile apps (future) | Native Auth0 SDK or M2M proxy |
| Scheduled jobs/automation | M2M (Client Credentials + JWT) |

## Architecture Comparison

### Browser Authentication Flow (BFF Pattern)

```
Browser → app.budgetanalyzer.localhost (NGINX)
    ↓
Session Gateway (8081)
    ↓ (session cookie → JWT lookup in Redis)
NGINX (api.budgetanalyzer.localhost)
    ↓ (JWT validation)
Backend Services
```

**Characteristics:**
- Session cookies (HTTP-only, Secure, SameSite)
- JWTs stored server-side in Redis
- Stateful (session must exist)
- User-interactive OAuth2 flows

### M2M Authentication Flow

```
M2M Client → api.budgetanalyzer.localhost (NGINX)
    ↓ (JWT in Authorization header)
Token Validation Service (8088)
    ↓ (signature verification)
Backend Services
```

**Characteristics:**
- Direct JWT usage (no session cookies)
- Stateless (no Redis session)
- Client Credentials OAuth2 flow
- Scope-based permissions

## Client Credentials Flow

### Step 1: Client Registration

M2M clients are registered in Auth0 with:
- **Client ID:** Public identifier
- **Client Secret:** Confidential credential (never exposed in logs/UI)
- **Allowed Scopes:** Permissions the client can request
- **Token Lifetime:** Typically longer than user tokens (e.g., 24 hours)

### Step 2: Token Exchange

```http
POST /auth/token
Host: api.budgetanalyzer.localhost
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<client_id>
&client_secret=<client_secret>
&audience=https://api.budgetanalyzer.localhost
&scope=transactions:read currency:read
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "scope": "transactions:read currency:read"
}
```

**Flow through infrastructure:**
1. Client sends request to NGINX `/auth/token`
2. NGINX proxies to Auth0 token endpoint
3. Auth0 validates client_id/client_secret
4. Auth0 returns JWT access token
5. Client stores token securely (NOT in browser)

### Step 3: API Access

```http
GET /api/transactions
Host: api.budgetanalyzer.localhost
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
```

**Flow through infrastructure:**
1. Request arrives at NGINX
2. NGINX calls Token Validation Service (auth_request)
3. Token Validation Service verifies:
   - JWT signature (using Auth0 JWKS)
   - Issuer and audience claims
   - Expiration (exp claim)
   - Scopes match requested resource
4. NGINX proxies to backend service
5. Backend service enforces data-level authorization

## Authorization Model

### Scope-Based Permissions

M2M clients use OAuth 2.0 scopes instead of role-based permissions:

| Scope | Description | Resources |
|-------|-------------|-----------|
| `transactions:read` | Read transaction data | GET /api/transactions |
| `transactions:write` | Create/update transactions | POST/PUT /api/transactions |
| `currency:read` | Read currency/exchange rates | GET /api/currencies |
| `currency:write` | Update exchange rates | POST/PUT /api/currencies |
| `admin:read` | Read admin data | GET /api/admin/* |
| `admin:write` | Admin operations | POST/PUT/DELETE /api/admin/* |

### Scope Enforcement

**Token Validation Service:**
- Verifies requested scopes are present in JWT
- Returns 403 Forbidden if scope missing

**Backend Services:**
- Extract scopes from JWT claims
- Enforce business logic constraints
- Scope-based query filtering (e.g., read-only clients can't write)

### Integration with Permission-Service

**Current State:**
- M2M clients use Auth0 scopes (not permission-service roles)
- Permission-service manages user permissions only

**Future Considerations:**
- Track M2M client access in permission-service audit logs
- Map scopes to permission-service permissions for unified auditing
- Client-level rate limiting via permission-service

## Threat Mitigation for M2M Clients

### Client Credential Compromise

**Detection:**
- Unusual API patterns (rate, geographic origin, resource access)
- Multiple concurrent sessions from same client
- Access to resources outside normal scope

**Immediate Response:**

1. **Disable client in Auth0**
   - Revokes ability to obtain new tokens
   - Existing tokens remain valid until expiration (unlike browser sessions)

2. **JWT Blacklist (if implemented)**
   - Add client_id to Redis blacklist
   - Token Validation Service rejects all tokens for client
   - Timeline: Immediate

3. **Credential Rotation**
   - Generate new client_secret in Auth0
   - Distribute to legitimate client operator
   - Old secret invalidated

### Scope Abuse

If client accesses resources outside intended scope:

1. **Reduce scopes in Auth0**
   - Remove unauthorized scopes from client configuration
   - Next token request returns reduced scopes

2. **Audit log review**
   - Query access logs for unauthorized resource access
   - Determine extent of unauthorized access

### Rate Limiting

M2M clients have separate rate limits:

| Client Type | Rate Limit | Rationale |
|------------|------------|-----------|
| Default M2M | 1000 req/min | Higher than user (no UI delays) |
| High-volume integration | 10000 req/min | Pre-approved partners |
| Admin operations | 100 req/min | Sensitive operations |

**Implementation:**
- NGINX rate limiting by client_id (extracted from JWT)
- Different limits per scope/endpoint

## Security Best Practices

### Credential Management

1. **Never log client secrets**
   - Mask in all logs
   - Don't include in error messages

2. **Rotate credentials regularly**
   - Recommended: Every 90 days
   - Required: After any suspected compromise

3. **Use environment variables**
   - Don't hardcode secrets in source code
   - Use secure secret management (e.g., HashiCorp Vault)

4. **Separate credentials per environment**
   - Different client_id/secret for dev, staging, production
   - Prevents accidental cross-environment access

### Scope Minimization

1. **Principle of least privilege**
   - Grant only required scopes
   - Review and reduce scopes periodically

2. **Separate clients for different purposes**
   - Read-only client for analytics
   - Write client for integrations
   - Admin client for operations

### Token Handling

1. **Secure storage**
   - Store tokens encrypted at rest
   - Never store in browser localStorage
   - Use OS credential stores when possible

2. **Token refresh strategy**
   - Refresh before expiration (e.g., at 80% lifetime)
   - Handle refresh failures gracefully
   - Don't retry failed auth excessively (may trigger rate limits)

3. **Transport security**
   - Always use HTTPS
   - Verify TLS certificates
   - Don't disable certificate validation

### Monitoring and Alerting

1. **Authentication failures**
   - Alert on repeated auth failures
   - May indicate credential stuffing or compromise

2. **Unusual patterns**
   - Geographic anomalies
   - Time-of-day anomalies
   - Volume spikes

3. **Scope violations**
   - Attempts to access unauthorized resources
   - May indicate misconfiguration or attack

## Audit Logging

### What's Logged

| Event | Log Entry |
|-------|-----------|
| Token request | client_id, scopes requested, success/failure |
| API access | client_id, endpoint, method, response code |
| Rate limit trigger | client_id, endpoint, limit hit |
| Scope violation | client_id, requested resource, missing scope |

### Log Format

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "event": "api_access",
  "client_id": "abc123",
  "client_type": "m2m",
  "endpoint": "/api/transactions",
  "method": "GET",
  "response_code": 200,
  "scopes": ["transactions:read"],
  "request_id": "req-xyz-789"
}
```

### Audit Queries

- "What resources did client X access in the last 24 hours?"
- "Which clients accessed resource Y?"
- "What's the API usage pattern for client X?"

## NGINX Configuration

M2M traffic routes are defined in `nginx/nginx.dev.conf`:

```nginx
# Token exchange endpoint (M2M only)
location /auth/token {
    proxy_pass https://auth0.com/oauth/token;
    # Rate limiting per IP
    limit_req zone=auth_limit burst=5 nodelay;
}

# API endpoints (both user and M2M)
location /api/ {
    # JWT validation for all requests
    auth_request /auth/validate;

    # Extract client_id for rate limiting
    auth_request_set $client_id $upstream_http_x_client_id;

    # Route to backend
    proxy_pass http://backend;
}
```

## Client Onboarding Process

### For Third-Party Integrations

1. **Agreement:** Legal/business agreement with third party
2. **Registration:** Create M2M client in Auth0 with appropriate scopes
3. **Credentials:** Securely transfer client_id and client_secret
4. **Documentation:** Provide API documentation and examples
5. **Testing:** Test in sandbox environment
6. **Production:** Enable production scopes after successful testing
7. **Monitoring:** Set up alerts for the client

### For Internal Services

1. **Request:** Service team requests M2M client
2. **Approval:** Security team approves scopes
3. **Registration:** DevOps creates client in Auth0
4. **Deployment:** Credentials deployed via secret management
5. **Verification:** Service tests authentication

## Comparison with User Authentication

| Aspect | User (BFF) | M2M Client |
|--------|-----------|------------|
| **Auth flow** | Authorization Code + PKCE | Client Credentials |
| **Token storage** | Redis (server-side) | Client application |
| **Token lifetime** | 15-30 minutes | 1-24 hours |
| **Refresh tokens** | Yes (in Redis) | Optional |
| **Session cookies** | Yes (HTTP-only) | No |
| **Rate limiting** | Per user | Per client_id |
| **Permissions** | Role-based (permission-service) | Scope-based (Auth0) |
| **Revocation** | Delete Redis session | Disable client in Auth0 |

## Future Enhancements

See [Security Enhancements Roadmap](../plans/security-enhancements-roadmap.md) for planned improvements including:
- Permission-service M2M audit integration
- Per-client rate limiting
- Mutual TLS (mTLS) for high-security integrations
- Short-lived M2M tokens
- M2M client portal
- Scope delegation
