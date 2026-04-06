# 007. Browser-Only Session Gateway — Refresh Token and Token Exchange Removed

**Date:** 2026-04-06
**Status:** Accepted
**Deciders:** Architecture Team

## Context

ADR 006 (Session Architecture Rethink) committed to a single Redis hash per
session and heartbeat-driven sliding TTL. As Session Gateway was rebuilt on
that decision, two follow-on facts became clear during implementation:

1. **The heartbeat does not need to call Auth0.** ADR 006 assumed the heartbeat
   would also validate the IDP grant via refresh-token exchange when near
   expiry. In practice this couples session liveness to Auth0 availability,
   makes the heartbeat code path noticeably more complex, and provides only
   bounded revocation propagation (limited to the heartbeat interval anyway).
   IDP revocation has a more direct path: explicit bulk revocation triggered
   by permission-service when a user is deactivated.

2. **`POST /auth/token/exchange` was never used.** It was added speculatively
   for native/M2M clients that never materialized. Keeping it in the codebase
   created a non-browser surface on Session Gateway that contradicted the
   "session-based edge authorization" framing and confused readers about which
   lanes the architecture actually supports.

The future stateless bearer-token lane for external/M2M access is tracked as a
draft in `docs/plans/stateless-m2m-edge-authorization-plan.md`. That lane will
not run through Session Gateway.

## Decision

Session Gateway is explicitly browser-only. Specifically:

1. **No Auth0 tokens are persisted.** The `refresh_token` and
   `token_expires_at` fields are removed from the Redis session hash. Auth0
   access tokens are used only during login to derive identity (sub, email,
   name) and discarded.
2. **Auth0 scope is `openid profile email`.** The `offline_access` scope is
   removed; Auth0 no longer issues refresh tokens to Session Gateway.
3. **`GET /auth/v1/session` is local-only.** It reads the Redis hash, extends
   the TTL and `expires_at`, and returns `{ active, userId, roles, expiresAt }`.
   It does not call Auth0. The `tokenRefreshed` response field is removed.
4. **`POST /auth/token/exchange` is removed** (controller, request/response
   DTOs, security path matcher, all tests). Session Gateway exposes no
   non-browser authentication surface.
5. **IDP revocation propagates via explicit bulk revocation.** The new
   internal endpoint `DELETE /internal/v1/sessions/users/{userId}` is callable
   only from `permission-service` (enforced by Istio AuthorizationPolicy on
   port 8081). It deletes every session for the user via a new Redis set
   index `user_sessions:{userId}`, using a Redis Lua script for atomicity.

## Consequences

**Positive:**
- Heartbeat path is dramatically simpler — no Auth0 dependency, no refresh
  threshold, no token-rewrite logic.
- Auth0 outages no longer break browser session liveness.
- Session Gateway's purpose is unambiguous: it owns the browser session
  lifecycle, nothing else.
- Revocation is now explicit and immediate, not bounded by a heartbeat
  interval.
- Reduces the credential surface — no IDP tokens at rest in Redis.

**Negative:**
- IDP revocation now requires permission-service to actively call the
  bulk-revocation endpoint. A user revoked at Auth0 but not deactivated in
  permission-service keeps their session until Redis TTL expiry.
- The explicit east-west allowance from permission-service to Session Gateway
  on port 8081 is a documented exception to the "ingress-only" pattern; it
  must be re-verified after Istio upgrades.

**Neutral:**
- The "future M2M / external API" story now lives only in the draft plan
  `docs/plans/stateless-m2m-edge-authorization-plan.md`. That lane will be a
  separate edge path, not a Session Gateway endpoint.
- ADR 006 is not superseded — its single-hash, no-BFF, no-Spring-Cloud-Gateway
  decisions still stand. ADR 006 has an appended `Subsequent Updates` section
  that points here.

## References
- [ADR 006 — Session Architecture Rethink](006-session-architecture-rethink.md)
- [Stateless M2M Edge Authorization Plan (Draft)](../plans/stateless-m2m-edge-authorization-plan.md)
- Sibling session-gateway plan: `local-session-revocation-and-refresh-token-removal.md` (executed 2026-04-05, commit 55719f2)
