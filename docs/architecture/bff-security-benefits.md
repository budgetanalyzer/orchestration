## Primary Security Benefits Of BFF (Backend-for-Frontend) architecture

### 1. **XSS Attack Protection**
**The Critical Advantage:** JWTs never reach the browser's JavaScript environment at all.

- **BFF Pattern:** Session Gateway stores JWTs server-side in Redis. Browser only receives HTTP-only session cookies that JavaScript cannot access.
- **Direct JWT:** Browser must store JWT in localStorage or sessionStorage, making it vulnerable to XSS attacks. Any malicious script can steal the token.

**Impact:** Even if an attacker injects malicious JavaScript, they cannot steal authentication credentials.

### 2. **Defense in Depth - Multiple Validation Layers**

The BFF architecture creates 4 independent security layers:

1. **Session Gateway** - Validates session cookies, manages token lifecycle
2. **NGINX** - Independently validates JWT signatures (doesn't trust Session Gateway)
3. **Token Validation Service** - Cryptographic verification
4. **Backend Services** - Data-level authorization

**Why this matters:** If one layer is compromised, others still protect the system. Direct JWT to NGINX eliminates the first critical layer.

### 3. **Automatic Token Refresh Without Browser Involvement**

- **BFF Pattern:** Session Gateway proactively refreshes tokens 5 minutes before expiration. Browser never sees or handles refresh tokens.
- **Direct JWT:** Browser must store refresh tokens (even more sensitive than access tokens) and handle refresh logic in JavaScript, exposing another attack surface.

**Security implication:** Refresh tokens are long-lived (8 hours to 30 days). Exposing them to XSS dramatically increases breach window.

### 4. **Cookie Security Attributes**

Session cookies use triple protection:
- **HttpOnly:** JavaScript cannot access
- **Secure:** Only transmitted over HTTPS
- **SameSite: Strict:** Protection against CSRF attacks

JWTs in Authorization headers don't have these browser-level protections.

### 5. **Reduced Attack Surface**

**BFF Pattern:**
```
Browser → Session Cookie → Session Gateway → JWT → NGINX
```
JWT exists only in server-to-server communication over internal network.

**Direct JWT:**
```
Browser → JWT → NGINX
```
JWT traverses the entire public internet and browser environment.

## Financial Application Context

Lines 10-12 emphasize this is for a **financial data application requiring maximum security**. For financial apps:

- Regulatory compliance often requires server-side session management
- Audit trails must show server-side validation (lines 453-471)
- Token theft could enable fraudulent transactions
- The additional complexity is justified by the security gains

## The Key Insight

> **Decision: Use BFF pattern**
> **Rationale: Maximum security for browser-based financial application**

The BFF pattern trades architectural complexity for eliminating the entire class of XSS-based token theft attacks, which is appropriate for high-security financial applications.

## Threat Mitigation Scenarios

This section describes how the BFF architecture enables rapid response when a user account becomes a threat (compromised, malicious activity, or policy violation).

### User Account Compromise Response

When a user account is identified as compromised or malicious, the response involves both **authentication revocation** (Session Gateway) and **authorization revocation** (permission-service):

**Immediate Actions:**

1. **Session Invalidation (Authentication Layer)**
   - Delete all Redis sessions for the user
   - Session Gateway rejects subsequent requests with invalid/missing session
   - User must re-authenticate to obtain new session
   - **Timeline:** Immediate (next request fails)

2. **Permission Revocation (Authorization Layer)**
   - Soft-delete user in permission-service (cascades to all roles, permissions, delegations)
   - Publish cache invalidation event via Redis pub/sub
   - **Timeline:** 1-6 minutes (L1 cache: 1 min, L2 cache: 5 min)

3. **Audit Trail Query**
   - Query permission-service audit logs for recent activity
   - Identify what resources were accessed during compromise window
   - Temporal queries show point-in-time permissions

**Why Both Layers Matter:**

| Action | Effect | Timeline | Gap Coverage |
|--------|--------|----------|--------------|
| Session deletion | User cannot make new authenticated requests | Immediate | Primary response |
| Permission revocation | Even if session somehow persists, authorization fails | 1-6 min | Defense in depth |

### Token Revocation Options

The BFF architecture supports two approaches to token revocation, each with different trade-offs:

#### Option A: Session Deletion (Recommended)

**How it works:**
- Delete user's session(s) from Redis
- Session cookie becomes invalid (no matching session)
- Existing JWT in Session Gateway memory becomes orphaned
- User redirected to login

**Advantages:**
- Simple implementation
- No additional infrastructure
- No performance overhead on every request

**Limitations:**
- JWT technically remains valid until expiration (15-30 min)
- If attacker obtained JWT directly (unlikely in BFF), they could use it until expiration
- Mitigated by: JWTs never exposed to browser in BFF pattern

**When to use:** Default approach for account compromise, user-initiated logout, password changes.

#### Option B: JWT Blacklist (For Instant Revocation)

**How it works:**
- Maintain a blacklist of revoked JWTs or user IDs in Redis
- Token Validation Service checks blacklist before validating signature
- Revoked tokens immediately rejected

**Implementation approach:**
```
Redis key: jwt:blacklist:{jti} or jwt:blacklist:user:{user_id}
TTL: Match JWT expiration time (auto-cleanup)
Check: Token Validation Service queries before signature validation
```

**Advantages:**
- Instant revocation (next request fails)
- Works even if attacker obtained JWT
- Useful for high-security scenarios

**Limitations:**
- Performance overhead: Redis lookup on every API request
- Complexity: Token Validation Service must be modified
- Memory: Blacklist entries consume Redis memory until expiration

**When to use:** Suspected active attack, regulatory requirement for instant revocation, high-value account compromise.

### Comparison: Authentication vs Authorization Revocation

Understanding when each approach applies:

| Scenario | Primary Action | Secondary Action |
|----------|---------------|------------------|
| Account compromise | Session deletion (immediate) | Permission soft-delete (audit trail) |
| Policy violation | Permission revocation (specific permissions) | Optional session deletion |
| Role change (demotion) | Permission update (cache invalidates) | No session action needed |
| Temporary suspension | Permission soft-delete | Session deletion (force re-auth) |
| Permanent ban | Permission hard-delete | Session deletion + Auth0 block |

### Suspicious Activity Response

For detected anomalies (rate limit triggers, unusual access patterns):

1. **Immediate:** Rate limiting already in effect at NGINX (100 req/min default)
2. **Short-term:** Temporary permission suspension via permission-service
3. **Investigation:** Query audit logs for access patterns
4. **Resolution:** Either restore access or escalate to full revocation

### Future Enhancements

See [Security Enhancements Roadmap](../plans/security-enhancements-roadmap.md) for planned improvements including:
- Session Gateway bulk revocation API
- JWT blacklist support in Token Validation Service
- Permission-service suspension status

## Permission-Service Integration

The permission-service provides fine-grained authorization control that complements the BFF's authentication security.

### Architecture Overview

```
┌─ Permission Management (Admin Operations) ─┐
│  permission-service (port 8086)             │
│  • CRUD for roles, permissions, delegations │
│  • User suspension/soft-delete              │
│  • Audit log queries                        │
│  • Cache invalidation publishing            │
└──────────────────────────────────────────────┘
                    ↓
           PostgreSQL (source of truth)
                    ↓
           Redis pub/sub (invalidation events)
                    ↓
┌─ Permission Evaluation (Request Path) ─────┐
│  service-common library (in each service)   │
│  • L1 cache: Caffeine (1 min TTL)          │
│  • L2 cache: Redis (5 min TTL)             │
│  • Database fallback                        │
└──────────────────────────────────────────────┘
```

### Cache Invalidation Flow

When permissions are revoked:

1. **Admin action:** API call to permission-service
2. **Database update:** PostgreSQL `revoked_at` timestamp set
3. **Event publish:** Redis pub/sub message sent
4. **Cache eviction:**
   - All service instances receive event
   - L1 (Caffeine) entries evicted immediately
   - L2 (Redis) entries deleted
5. **Next request:** Cache miss → database query → denial

**Worst-case propagation time:**
- If request arrives just before cache invalidation: up to 6 minutes (1 min L1 + 5 min L2)
- Typical propagation: < 1 second (pub/sub is fast)

### Soft Delete Cascade

When a user is soft-deleted (threat response):

```sql
-- permission-service cascade behavior
UPDATE users SET deleted_at = NOW() WHERE id = ?;
-- Triggers cascade:
UPDATE user_roles SET revoked_at = NOW() WHERE user_id = ?;
UPDATE resource_permissions SET revoked_at = NOW() WHERE user_id = ?;
UPDATE delegations SET revoked_at = NOW() WHERE delegator_id = ? OR delegatee_id = ?;
```

**Benefits:**
- Single API call revokes all access
- Audit trail preserved (soft delete, not hard delete)
- Can restore user by clearing `deleted_at`
- Point-in-time queries show historical permissions

### Integration with Threat Response

**For account compromise:**

```
1. Session Gateway: Delete Redis sessions (immediate auth block)
2. Permission-service: Soft-delete user (authorization block + audit)
3. Result: User blocked at both layers within seconds
```

**For permission abuse (legitimate user, wrong permissions):**

```
1. Permission-service: Revoke specific role or permission
2. Cache invalidation propagates (1-6 min worst case)
3. No session action needed (user can still authenticate)
4. Result: User loses specific capability, maintains access
```

### Audit Capabilities

The permission-service provides forensic capabilities for threat investigation:

- **Point-in-time queries:** "What permissions did user X have at time T?"
- **Change history:** "When was this permission granted/revoked?"
- **Access patterns:** "Who accessed resource Y in the last 24 hours?"
- **Delegation chains:** "How did user X obtain permission Z?"

These capabilities are critical for:
- Incident investigation
- Compliance reporting
- Access reviews
- Forensic analysis after breach
