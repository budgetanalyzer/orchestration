# 011. Hashed Session Keys, `__Host-` Session Cookie and Absolute Session Lifetime

**Date:** 2026-11-05
**Status:** Accepted
**Deciders:** Architecture Team

## Context

ADR 006 stores each browser session in one Redis hash, `session:{id}`, keyed
by the raw cookie token. Its expiry slides forward on each heartbeat. The
2026-11-01 security reviews raised three related problems with that contract.

1. **Enumeration.** Redis ACL key patterns do not filter `KEYS` or `SCAN`
   results. An isolated Redis 7.4 probe confirmed that a user limited to
   `~currency-service:*` with `+keys +scan` got `NOPERM` on
   `GET session:<id>`, but could list session and user-index key names.
   currency-service had both grants, because Spring Data Redis clears a cache
   with `KEYS` then `DEL` by default. With raw tokens as key suffixes, a listed
   name was a replayable bearer cookie.
2. **Cookie tossing.** The `BA_SESSION` cookie could carry a `Domain`
   override. Both consumers used the first matching cookie, so a planted
   longer-path or sibling-domain cookie could take precedence.
3. **No age limit.** Continued successful heartbeats renewed a session
   indefinitely. An unattended session still expired.

The reviews proposed several overlapping remedies: hash the keys, remove
`+keys +scan`, use versioned cache prefixes, split Redis, and reject duplicate
cookies. The 2026-11-05 contested-issues review chose the smallest set that
covers each property (items 2 and 5). Hardening plans 02.4, 02.5 and 02.6 and
plan 03 implemented it. This record was written on 2026-11-12, after
implementation.

This decision supersedes ADR 006's raw `session:{id}` key format and its
sliding-only expiry. ADR 006's single-hash design still stands.

## Decision

1. **Hashed session keys.** The raw random token stays only in the cookie.
   Session Gateway and `ext_authz` both key sessions as
   `session:{sha256(token)}`, and the `user_sessions:{userId}` index stores the
   same digests. There is one format, with no raw-key fallback or dual-format
   migration.
2. **Keep one shared Redis, and accept key-name visibility.** Any credential
   that can `SCAN` still sees session digests, user IDs, session counts and
   in-flight OAuth state names. It gets no replayable token, and
   [ADR 010](010-oauth-callback-browser-binding.md) stops a listed state from
   completing a login. A separate auth Redis remains an availability-isolation
   option, not a prerequisite.
3. **Incremental cache clearing.** currency-service keeps its cache-wide
   `@CacheEvict(allEntries = true)` and its one-hour TTL. It clears with a
   `SCAN` batch strategy and bounded `DEL` batches, and its ACL drops `+keys`
   and keeps `+scan`.
4. **`__Host-BA_SESSION` cookie.** The `__Host-` prefix makes conforming
   browsers require `Secure`, `Path=/` and no `Domain`. This closes the
   longer-path and sibling-domain tossing cases. The `Domain` override is
   removed. Rejecting duplicate session cookies is optional hardening after
   the rename, not a separate milestone, and is not implemented.
5. **Absolute lifetime at the writer.** Session Gateway caps each heartbeat at
   `created_at + SESSION_MAX_LIFETIME_SECONDS` and refuses to start if the
   maximum is below the sliding TTL. `ext_authz` enforces the cap only
   transitively, by rejecting a passed `expires_at` or a missing session.

[Shared Session Contract](../architecture/session-edge-authorization-pattern.md#shared-session-contract)
and [Absolute Session Lifetime](../architecture/session-edge-authorization-pattern.md#absolute-session-lifetime)
own the current behavior, values and verifiers. Session Gateway's
[session configuration](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md)
owns the derivation, golden vector and cookie attributes.

## Alternatives Considered

### Alternative 1: Remove enumeration with versioned cache-generation keys
**Pros:**
- currency-service would need neither `+keys` nor `+scan`.

**Cons:**
- Adds a generation-key scheme to fix metadata exposure that hashing already
  makes non-replayable.

### Alternative 2: TTL-only cache expiry, with no eviction
**Cons:**
- Imports would serve stale exchange rates for up to the TTL. That changes
  freshness behavior to remove one grant.

### Alternative 3: Split Redis into auth and cache instances now
**Pros:**
- Isolates memory, eviction policy and administrative blast radius.

**Cons:**
- Needs a new service, ACLs and human-supplied TLS material.
- Does not replace hashing, OAuth binding or limits on auth-state capacity.
  Separate logical database numbers would not give a process boundary.

### Alternative 4: Reject duplicate session cookies as the main fix
**Cons:**
- `__Host-` already stops a conforming browser from storing the cited
  cookies. Arbitrary HTTP clients can send duplicates, but that gives an
  attacker no victim credential.

### Alternative 5: A second, independently configured lifetime cap in `ext_authz`
**Cons:**
- Two settings to keep in step. The writer cap plus the `expires_at` check
  already enforces the limit.

## Consequences

**Positive:**
- A credential that can list keys no longer obtains session tokens. Neither
  does a reader of the append-only file or the logs.
- currency-service no longer blocks Redis with a full `KEYS` pass on the
  instance that `ext_authz` reads on every request.
- Sessions have a hard age limit without an Auth0 call on the heartbeat.

**Negative:**
- Key-name metadata stays visible to any credential with `SCAN`. Revisit if
  Redis is split for other reasons or that metadata becomes sensitive.
- `SCAN` clearing is not a point-in-time delete. A stale write racing an
  import stays cached until the one-hour TTL, as before.
- Authenticated cache growth can still exhaust the shared Redis that sessions
  depend on. See
  [`high-currency-cache-exhausts-shared-redis`](../issues/high-currency-cache-exhausts-shared-redis.md).
- The cutover invalidated existing sessions and cookies. Users signed in again,
  and local Redis was flushed rather than migrated.
- `__Host-` is a browser storage rule. It does not isolate ports on one host
  or protect against a compromised same-host service.
- The lifetime cap is not account-wide revocation.

**Neutral:**
- The 2026-11-01 reviews flagged the unused permission-service `deleteUser`
  method, which soft-deleted without revoking sessions. It was removed rather
  than fixed. Deactivation, which does revoke sessions, remains the only
  exposed lifecycle action. If deletion is exposed later, specify session
  revocation and re-registration semantics first.

## References
- [Session Edge Authorization: Shared Session Contract](../architecture/session-edge-authorization-pattern.md#shared-session-contract)
- [Session Edge Authorization: Absolute Session Lifetime](../architecture/session-edge-authorization-pattern.md#absolute-session-lifetime)
- [Session Gateway: Hashed Session Keys](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md#hashed-session-keys)
- [Session Gateway: Cookie Behavior](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md#cookie-behavior)
- [ADR 006: Session Architecture Rethink](006-session-architecture-rethink.md), whose key format and sliding-only expiry this supersedes
- [ADR 010: OAuth Callback Browser Binding](010-oauth-callback-browser-binding.md)
- `kubernetes/infrastructure/redis/start-redis.sh` (ACL grants)
- [HTTP cookies draft: the `__Host-` prefix](https://httpwg.org/http-extensions/draft-ietf-httpbis-rfc6265bis.html#name-the-host-prefix)
- Source: 2026-11-05 contested-issues security review, items 2, 5 and 10, and
  its settled finding on unbounded session renewal. The record was deleted
  after this ADR was written; see Git history.
