# Security Enhancements Roadmap

This document tracks planned and proposed security enhancements for the Budget Analyzer platform. Items are organized by priority and component.

## High Priority

### Session Gateway: Bulk Session Revocation API

**Current Gap:** No API endpoint to invalidate all sessions for a user. Requires direct Redis access.

**Proposed Solution:**
```http
DELETE /api/sessions/user/{userId}
Authorization: Bearer <admin-token>
```

**Benefits:**
- Enables admin UI for session management
- Scriptable for automated threat response
- Audit trail for session revocations

**Implementation Notes:**
- Query Redis for all sessions matching user_id
- Delete matching session keys
- Return count of invalidated sessions
- Log to security audit trail

**Estimated Effort:** 2-3 days

---

### Token Validation Service: JWT Blacklist Support

**Current Gap:** Issued JWTs cannot be revoked before expiration. Session deletion blocks new requests but existing JWTs remain valid.

**Proposed Solution:**
```
Redis key: jwt:blacklist:{jti} or jwt:blacklist:user:{user_id}
TTL: Match JWT expiration time (auto-cleanup)
Check: Token Validation Service queries before signature validation
```

**Trade-offs:**
- **Pro:** Instant revocation for active attacks
- **Con:** Redis lookup on every API request (performance overhead)
- **Con:** Adds complexity to Token Validation Service

**When Needed:**
- Regulatory requirement for instant revocation
- High-value account compromise with suspected active attack
- Compliance audits requiring demonstrable revocation capability

**Estimated Effort:** 3-5 days

---

## Medium Priority

### Permission-Service: M2M Client Audit Integration

**Current Gap:** M2M clients use Auth0 scopes but don't appear in permission-service audit logs. No unified view of all access.

**Proposed Solution:**
- Track M2M client registrations in permission-service
- Log M2M access events to same audit tables as user access
- Enable queries like "who accessed resource X" to include both users and M2M clients

**Benefits:**
- Unified audit trail
- Consistent access reviews
- Better compliance reporting

**Estimated Effort:** 5-7 days

---

### Permission-Service: Explicit Suspension Status

**Current Gap:** User suspension uses soft-delete, which loses the distinction between "suspended temporarily" and "deleted permanently."

**Proposed Solution:**
- Add `suspended_at` and `suspension_expires_at` columns
- Separate status from soft-delete
- Auto-restore when suspension expires

**Benefits:**
- Temporary suspensions without losing history
- Automatic expiration for time-limited blocks
- Clearer audit trail (suspended vs deleted)

**Estimated Effort:** 3-4 days

---

### NGINX: Per-Client Rate Limiting for M2M

**Current Gap:** Rate limiting is per-IP, not per-client_id. High-volume M2M clients from same IP share limits.

**Proposed Solution:**
```nginx
# Extract client_id from JWT for rate limiting
map $jwt_client_id $rate_limit_key {
    default $binary_remote_addr;
    ~.+     $jwt_client_id;
}

limit_req_zone $rate_limit_key zone=api_limit:10m rate=100r/s;
```

**Benefits:**
- Fair rate limiting per integration
- Prevent one client from exhausting limits
- Better traffic management

**Estimated Effort:** 2-3 days

---

## Lower Priority / Under Consideration

### Mutual TLS (mTLS) for M2M

**Description:** Additional layer of client authentication using client certificates.

**Use Case:** Highest-security integrations (financial partners, regulatory systems).

**Trade-offs:**
- **Pro:** Strong client authentication (cryptographic proof)
- **Con:** Certificate management complexity
- **Con:** Client must manage certificates

**Status:** Under consideration for specific high-security partners.

---

### Short-Lived M2M Tokens

**Description:** Reduce M2M token lifetime from hours to minutes with automatic refresh.

**Benefits:**
- Reduced exposure window if token compromised
- Better principle of least privilege
- More frequent validation

**Trade-offs:**
- **Con:** More token refresh traffic
- **Con:** Client must implement refresh logic

**Status:** Under consideration for future security hardening.

---

### Dynamic Rate Limiting

**Description:** Automatically adjust rate limits based on client behavior patterns.

**Features:**
- Detect anomalous patterns
- Automatic throttling for suspicious activity
- Gradual limit recovery

**Status:** Research phase. May integrate with Auth0 anomaly detection.

---

### M2M Client Portal

**Description:** Self-service portal for M2M client operators.

**Features:**
- Credential rotation without admin involvement
- Usage dashboards and analytics
- Scope request workflow

**Status:** Future roadmap item. Depends on client volume.

---

### Scope Delegation for M2M

**Description:** Allow M2M clients to request a subset of their authorized scopes per token.

**Example:**
```http
POST /auth/token
scope=transactions:read  # Only request read, even though write is authorized
```

**Benefits:**
- Better principle of least privilege
- Reduced blast radius if token compromised

**Status:** Under consideration. Auth0 supports this natively.

---

## Implementation Dependencies

```
Session Revocation API ──────────────────┐
                                         │
JWT Blacklist ───────────────────────────┼──→ Complete Threat Response
                                         │
Permission-Service M2M Audit ────────────┘

Permission-Service Suspension ───────────────→ Better User Management

Per-Client Rate Limiting ────────────────────→ M2M Scalability
```

## Related Documentation

- [BFF Security Benefits](../architecture/bff-security-benefits.md) - Threat mitigation scenarios
- [M2M Client Authorization](../architecture/m2m-client-authorization.md) - M2M authentication flow
- [Security Architecture](../architecture/security-architecture.md) - Overall security design
- [Permission Service Implementation Plan](permission-service-implementation-plan.md) - Authorization service
