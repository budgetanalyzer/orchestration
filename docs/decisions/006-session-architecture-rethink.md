# 006. Session Architecture Rethink — Single Redis Hash, Drop BFF Label

**Date:** 2026-03-29
**Status:** Accepted
**Deciders:** Architecture Team

## Context

Session Gateway uses Spring Cloud Gateway + Spring Session with a dual-write to a separate ext_authz Redis hash. Two independent TTL mechanisms manage one logical session:

- **Spring Session** (`spring:session:sessions:{id}`): sliding-window TTL (resets on every `WebSession` access)
- **ext_authz hash** (`extauthz:session:{id}`): fixed TTL set at write time

This dual-session design causes five interconnected problems:

1. **TTL drift** — Spring Session's sliding TTL resets on gateway access, but the ext_authz key's fixed TTL never resets. If the IDP token lifetime exceeds 30 minutes, the ext_authz key dies first. The ext_authz Go service also checks an `expires_at` field within the hash, so any fix that bumps the Redis key TTL must also update that field.

2. **Dead token refresh** — `TokenRefreshGatewayFilterFactory` extends `AbstractGatewayFilterFactory` but is configured on no route. A comment in `application.yml` confirms: "TokenRelay and TokenRefresh filters are not compatible with Spring Cloud Gateway Server." The security architecture docs describe a token refresh flow that never executes.

3. **Active users get hard-logged-out at 30 minutes** — In the Istio deployment, the post-login API path is `Browser → Istio → ext_authz (Redis) → NGINX → Backend`. Nothing touches Session Gateway after login. Spring Session's TTL never resets (no requests), ext_authz TTL never resets (fixed from creation), and token refresh never fires (dead code). An active user is hard-logged-out regardless of activity.

4. **Session lifetime decoupled from IDP grant** — The Auth0 access token is never used for API authorization (ext_authz reads from Redis, backends read from injected headers). The session can outlive IDP revocation — Auth0 could revoke a user and the Redis session keeps working. The refresh token (8h-30d) sits in Redis unused.

5. **Root cause: two Redis keys for one logical session** — The dual-write exists because Go's ext_authz service can't deserialize Spring Session's `GenericJackson2JsonRedisSerializer` output (Jackson type info wrapping). This forced a separate key with plain-string fields.

Additionally, calling the architecture "BFF" sets wrong expectations. A BFF mediates between browser and backend (proxies API calls). Session Gateway doesn't do that — ext_authz handles edge enforcement, and Istio/NGINX handle routing. Session Gateway is only touched at login and logout.

## Decision

Strip Session Gateway down to a plain Spring Boot WebFlux app (no Spring Cloud Gateway, no Spring Session) with one Redis hash per session, and add a frontend heartbeat for session liveness and IDP grant validation.

### Architecture changes

1. **Drop the BFF label.** This is a session-based edge authorization architecture. Session Gateway is an authentication service (login, logout, heartbeat). ext_authz is a policy enforcement point (session validation, header injection). Redis is the session store.

2. **Single Redis hash.** One `session:{id}` key with all fields as plain strings:
   ```
   session:{uuid}
     user_id, idp_sub, email, display_name, picture,
     roles, permissions, refresh_token,
     token_expires_at, created_at, expires_at
   ```
   No Spring Session, no dual-write, no TTL drift. ext_authz reads `user_id`, `roles`, `permissions`, `expires_at` and ignores the rest.

3. **Add `offline_access` scope.** Auth0 issues refresh tokens. Stored in the session hash, used by Session Gateway for IDP grant validation during heartbeat.

4. **Frontend heartbeat.** `GET /auth/session` endpoint on Session Gateway, called every ~5 minutes during user activity. Validates the IDP grant (via refresh token exchange when near expiry), extends session TTL. On refresh failure (IDP revoked): delete session, return 401, frontend redirects to login.

5. **ext_authz stays read-only.** Session Gateway is the sole session writer. ext_authz reads and validates but does not modify session state.

6. **Remove Spring Cloud Gateway.** No routing is needed — Istio and NGINX handle that. Session Gateway becomes a plain WebFlux app with a few endpoints: OAuth2 callback, logout, user info, heartbeat, token exchange.

### Session lifetime mechanics

- **Heartbeat** (`GET /auth/session`): resets `expires_at` + Redis key TTL (sliding window from user activity)
- **Session dies when**: Redis key expires (TTL) OR `expires_at` passes (checked by ext_authz)
- **IDP revocation propagation**: bounded by heartbeat interval (~5 min). Refresh failure deletes the session immediately.
- **Inactivity**: frontend shows "session expiring" modal after N minutes of no activity. User clicks "Continue" to fire heartbeat, or session dies on Redis TTL.

## Alternatives Considered

### Alternative 1: Fix TTL drift only (Option B from analysis)
Add a Session Gateway filter that bumps the ext_authz key TTL whenever a request passes through Session Gateway.

**Pros:**
- Most targeted fix for the specific drift bug
- Keeps all write logic in one service
- Minimal code change

**Cons:**
- Only covers the Session Gateway request path, not the broader problem
- Active users still get hard-logged-out (nothing touches Session Gateway mid-session)
- Dead token refresh remains dead
- Session still outlives IDP revocation
- Dual-session complexity persists

### Alternative 2: ext_authz bumps TTL on read (Option A)
ext_authz writes `EXPIRE` + `HSET expires_at` on every successful `HGETALL`.

**Pros:**
- ext_authz sees every API request — covers the active-use case
- `EXPIRE` + `HSET` is O(1), sub-ms

**Cons:**
- Turns ext_authz from read-only to reader+writer
- Doesn't address IDP revocation (session still outlives revoked grant)
- Dual-session complexity persists

### Alternative 3: Derive ext_authz TTL from access token expiry (Option C)
Set ext_authz key TTL to `token.expiresAt - now` instead of fixed 1800s.

**Pros:**
- Couples session to IDP timeline

**Cons:**
- Doesn't fix drift, just shifts the window
- If token is long-lived, ext_authz outlives Spring Session (security issue in reverse)
- Couples session lifetime to IDP config

### Alternative 4: Embed ext_authz fields in Spring Session hash
Write additional plain-string `extauthz:*` fields into the `spring:session:sessions:{id}` hash. Go reads only those fields. One key, one TTL.

**Pros:**
- Eliminates dual-write and TTL drift
- No separate key management

**Cons:**
- API activity still doesn't touch Session Gateway, so Spring Session's sliding TTL never resets either
- Unified key still expires after 30 minutes of pure API use
- Depends on Spring Session not deleting unknown fields (implementation detail)
- Still carries Spring Session and Spring Cloud Gateway complexity

### Alternative 5: Keep full BFF with Session Gateway in the hot path
Route all API calls through Session Gateway so it can check tokens on every request.

**Pros:**
- Textbook BFF pattern — refresh trigger is every API call
- Session sliding window works naturally

**Cons:**
- Adds latency to every API request (extra hop through Session Gateway)
- Session Gateway becomes a scaling bottleneck
- Would just read the same Redis hash that ext_authz already reads
- Istio + ext_authz already handles edge enforcement — this duplicates it

## Consequences

**Positive:**
- Single Redis hash eliminates TTL drift entirely
- Session lifetime coupled to IDP grant via heartbeat refresh — revocation propagates within ~5 minutes
- Removing Spring Cloud Gateway and Spring Session eliminates significant complexity (dead routes, filter factories, Jackson serialization, dual-write logic)
- Architecture label matches reality — "session-based edge authorization" describes what actually happens
- Session Gateway stays out of the API hot path — handles only login, logout, and heartbeat
- ext_authz remains read-only and stateless (aside from Redis reads)
- Clean inactivity UX with warning modal

**Negative:**
- Significant implementation effort — rewrites OAuth2 flow, session management, all controllers
- Requires custom OAuth2 authorization request storage (Redis-backed, replacing Spring Session's)
- Frontend must implement heartbeat and inactivity detection
- Auth0 application settings need `offline_access` allowed and refresh token rotation configured

**Neutral:**
- Redis ACLs need updating for new key prefix (`session:*` replaces `spring:session:*` and `extauthz:session:*`)
- All documentation referencing "BFF" needs updating across repos
- Token exchange endpoint (`POST /auth/token/exchange`) stores no refresh token — M2M/native clients hold their own IDP tokens and handle revocation themselves

## Implementation Notes

Implementation is phased across repos:
- **session-gateway**: Phases 1-4 (strip, rebuild OAuth2 flow, endpoints, heartbeat) — sequential
- **orchestration**: Phase 5 (Redis ACLs, ext_authz config) — Redis ACLs must be applied before new session-gateway code deploys
- **all repos**: Phase 6 (documentation — replace BFF terminology)
- **budget-analyzer-web**: Phase 7 (frontend heartbeat and inactivity warning)

## References
- [Session Edge Authorization Pattern](../architecture/session-edge-authorization-pattern.md)
- [Security Architecture](../architecture/security-architecture.md)
- [Port Reference](../architecture/port-reference.md)

## Subsequent Updates

**2026-04-06** — Parts of this decision have been refined after implementation
experience. The core architecture (single Redis hash, no Spring Cloud Gateway,
no Spring Session, heartbeat-driven sliding TTL, ext_authz read-only) stands.
The following points have changed and are captured in the new ADR
[`007-browser-only-session-gateway.md`](007-browser-only-session-gateway.md):

- **No refresh token in the session hash.** The `refresh_token` and
  `token_expires_at` fields have been removed from `session:{id}`. The session
  hash no longer holds any Auth0 tokens.
- **No `offline_access` scope.** Auth0 scope is now `openid profile email`.
  Auth0 issues no refresh token to Session Gateway.
- **Heartbeat is local-only.** `GET /auth/v1/session` extends the Redis TTL
  and returns `{ active, userId, roles, expiresAt }`. It no longer calls Auth0
  or attempts a refresh-token exchange. IDP revocation propagates via explicit
  bulk-revocation calls from permission-service to the new
  `DELETE /internal/v1/sessions/users/{userId}` endpoint.
- **`POST /auth/token/exchange` has been removed.** Session Gateway is
  explicitly browser-only. There is no M2M surface on Session Gateway.
