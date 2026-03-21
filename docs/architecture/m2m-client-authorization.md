# Machine-to-Machine (M2M) Client Authorization

This document describes the authorization flow for third-party applications and services that need to access Budget Analyzer APIs programmatically, without user interaction.

## Overview

M2M (Machine-to-Machine) authentication allows external systems to securely access Budget Analyzer APIs using token exchange via Session Gateway. Clients exchange their identity provider tokens for opaque session bearer tokens, which are validated per-request by Envoy ext_authz.

### When to Use M2M Authentication

| Use Case | Authentication Method |
|----------|----------------------|
| Browser-based user access | BFF pattern (Session Gateway + session cookies) |
| Third-party integrations | M2M (Token exchange → opaque bearer token) |
| Backend service-to-service | Network isolation (mTLS planned) |
| Mobile apps (future) | Native Auth0 SDK + token exchange |
| Scheduled jobs/automation | M2M (Token exchange → opaque bearer token) |

## Architecture Comparison

### Browser Authentication Flow (BFF Pattern)

```
Browser → Envoy (app.budgetanalyzer.localhost, :443)
    ↓ (auth paths)
Session Gateway (8081)
    ↓ (session cookie → dual-write to Redis)
Envoy ext_authz
    ↓ (session validation, header injection)
NGINX → Backend Services
```

**Characteristics:**
- Session cookies (HTTP-only, Secure, SameSite)
- Session data stored server-side in Redis (Spring Session + ext_authz schema)
- Stateful (session must exist in Redis)
- User-interactive OAuth2 flows

### M2M Authentication Flow

```
M2M Client → POST /auth/token/exchange (via Session Gateway)
    ↓ (IDP access token → opaque session bearer token)
M2M Client → Envoy (:443) with Bearer token
    ↓
ext_authz (:9002) validates session from Redis
    ↓ (X-User-Id, X-Roles, X-Permissions headers injected)
NGINX → Backend Services
```

**Characteristics:**
- Opaque bearer tokens (not JWTs on the wire)
- Server-managed session in Redis (ext_authz schema)
- Token exchange creates session with scoped permissions
- Instant revocation via Redis key deletion

## Token Exchange Flow

### Step 1: Client Registration

M2M clients are registered in Auth0 with:
- **Client ID:** Public identifier
- **Client Secret:** Confidential credential (never exposed in logs/UI)
- **Allowed Scopes:** Permissions the client can request
- **Token Lifetime:** Auth0 token used only for exchange (not for API access)

### Step 2: Obtain IDP Token

```http
POST /oauth/token
Host: your-auth0-tenant.auth0.com
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<client_id>
&client_secret=<client_secret>
&audience=https://app.budgetanalyzer.localhost
```

### Step 3: Token Exchange

```http
POST /auth/token/exchange
Host: app.budgetanalyzer.localhost
Content-Type: application/json

{
  "accessToken": "<IDP access token>"
}
```

**Response:**
```json
{
  "token": "<opaque-session-id>",
  "expiresIn": 1800,
  "tokenType": "Bearer"
}
```

**Flow through infrastructure:**
1. Client sends IDP access token to Session Gateway via `/auth/token/exchange`
2. Session Gateway validates token against IDP userinfo endpoint
3. Session Gateway fetches permissions from permission-service
4. Session Gateway creates session and dual-writes to ext_authz Redis schema
5. Session Gateway returns opaque session bearer token
6. Client stores token securely (NOT in browser)

### Step 4: API Access

```http
GET /api/v1/transactions
Host: app.budgetanalyzer.localhost
Authorization: Bearer <opaque-session-id>
```

**Flow through infrastructure:**
1. Request arrives at Envoy (:443)
2. Envoy calls ext_authz (:9002)
3. ext_authz looks up session in Redis (`extauthz:session:{token}`)
4. ext_authz validates session (checks expiry, reads permissions)
5. ext_authz injects `X-User-Id`, `X-Roles`, `X-Permissions` headers
6. Envoy routes to NGINX (:8080) with injected headers
7. NGINX routes to backend service
8. Backend service enforces data-level authorization

## Authorization Model

### Scope-Based Permissions

M2M clients use scopes resolved from permission-service:

| Scope | Description | Resources |
|-------|-------------|-----------|
| `transactions:read` | Read transaction data | GET /api/v1/transactions |
| `transactions:write` | Create/update transactions | POST/PUT /api/v1/transactions |
| `currency:read` | Read currency/exchange rates | GET /api/v1/currencies |
| `currency:write` | Update exchange rates | POST/PUT /api/v1/currencies |

### Scope Enforcement

**ext_authz Service:**
- Injects permissions as `X-Permissions` header
- Backend services read permissions from header

**Backend Services:**
- Extract permissions from `X-Permissions` header
- Enforce business logic constraints
- Scope-based query filtering (e.g., read-only clients can't write)

## Threat Mitigation for M2M Clients

### Client Credential Compromise

**Detection:**
- Unusual API patterns (rate, geographic origin, resource access)
- Multiple concurrent sessions from same client
- Access to resources outside normal scope

**Immediate Response:**

1. **Session Revocation**
   - Delete ext_authz Redis sessions for the compromised client
   - Next request immediately fails at ext_authz
   - **Timeline:** Immediate (next request rejected)

2. **Disable client in Auth0**
   - Revokes ability to obtain new IDP tokens
   - Cannot exchange for new session tokens

3. **Credential Rotation**
   - Generate new client_secret in Auth0
   - Distribute to legitimate client operator
   - Old secret invalidated

### Scope Abuse

If client accesses resources outside intended scope:

1. **Reduce scopes in permission-service**
   - Remove unauthorized permissions from client configuration
   - Next token exchange returns reduced permissions

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
- NGINX rate limiting by client identifier (from X-User-Id header)
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
   - Store opaque bearer tokens encrypted at rest
   - Never store in browser localStorage
   - Use OS credential stores when possible

2. **Token refresh strategy**
   - Exchange for new session token before expiration (at 80% lifetime)
   - Handle exchange failures gracefully
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
| Token exchange | client identifier, scopes resolved, success/failure |
| API access | client identifier, endpoint, method, response code |
| Rate limit trigger | client identifier, endpoint, limit hit |
| Scope violation | client identifier, requested resource, missing scope |

### Log Format

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "event": "api_access",
  "client_id": "abc123",
  "client_type": "m2m",
  "endpoint": "/api/v1/transactions",
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

## Client Onboarding Process

### For Third-Party Integrations

1. **Agreement:** Legal/business agreement with third party
2. **Registration:** Create M2M client in Auth0 with appropriate scopes
3. **Credentials:** Securely transfer client_id and client_secret
4. **Documentation:** Provide API documentation, token exchange examples
5. **Testing:** Test token exchange and API access in sandbox environment
6. **Production:** Enable production scopes after successful testing
7. **Monitoring:** Set up alerts for the client

### For Internal Services

1. **Request:** Service team requests M2M client
2. **Approval:** Security team approves scopes
3. **Registration:** DevOps creates client in Auth0
4. **Deployment:** Credentials deployed via secret management
5. **Verification:** Service tests token exchange and API access

## Comparison with User Authentication

| Aspect | User (BFF) | M2M Client |
|--------|-----------|------------|
| **Auth flow** | Authorization Code + PKCE | Client Credentials → Token Exchange |
| **Token on wire** | Session cookie (opaque) | Bearer token (opaque) |
| **Session storage** | Redis (Spring Session + ext_authz) | Redis (ext_authz) |
| **Token lifetime** | 30 minutes (sliding) | 30 minutes |
| **Refresh** | Proactive (Session Gateway) | Re-exchange before expiry |
| **Session cookies** | Yes (HTTP-only) | No |
| **Rate limiting** | Per user | Per client identifier |
| **Permissions** | Role-based (permission-service) | Scope-based (permission-service) |
| **Revocation** | Delete Redis session (instant) | Delete Redis session (instant) |

## Future Enhancements

See [Security Hardening Plan v2](../plans/security-hardening-v2.md) for planned improvements including:
- Per-client rate limiting
- Mutual TLS (mTLS) for high-security integrations
- Short-lived M2M tokens
- M2M client portal
- Scope delegation
