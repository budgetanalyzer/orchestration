# 015. Reset Local State Instead of Migrating While No Production Data Exists

**Date:** 2026-11-06
**Status:** Accepted
**Deciders:** Architecture Team

## Context

Budget Analyzer has no production environment and no production data. OCI is
retired, and the provider-neutral production reference is rendered offline
only. The only state that exists is local development state: browser
sessions, Redis keys, OAuth state, PostgreSQL contents and RabbitMQ volumes.

The 2026-11 security hardening changed several runtime-state formats and
cross-service contracts:

- the Redis session key format (see [ADR 011](011-hashed-session-keys-host-cookie-absolute-lifetime.md));
- the session cookie name;
- OAuth state records (see [ADR 010](010-oauth-callback-browser-binding.md));
- heartbeat and logout methods (see [ADR 009](009-exact-origin-ingress-csrf-control.md));
- the login permission-sync call.

Each change could have shipped with dual-format reads, a data migration or a
compatibility window. Each would have spanned several repositories. The rule
below was added to the hardening plans on 2026-11-06, before those changes
were implemented. This record was written on 2026-11-12, after
implementation.

## Decision

1. While no deployment holds data or sessions that must survive a release,
   breaking changes to runtime-state formats and cross-service contracts cut
   over in one coordinated change. Do not write data migrations, dual-format
   reads, fallback lookups or backward-compatibility shims for the old format.
2. Discard affected local state instead. Use `./scripts/ops/flush-redis.sh`
   for Redis and `./scripts/ops/reset-databases.sh` for PostgreSQL, or
   recreate the volume or cluster. The change documents any reset that an
   existing local cluster needs.
3. Repository merges are ordered when each step is safe on its own. Otherwise
   they are synchronized: every repository in the contract merges together.
4. This does not change how schemas evolve. Services keep making schema
   changes through versioned Flyway migrations.
5. Revisit before any environment holds data that must survive. A
   superseding ADR must then define a migration and compatibility policy.

## Alternatives Considered

### Alternative 1: Dual-format reads during a transition
For example, `ext_authz` and Session Gateway could accept both raw and hashed
session keys, or both cookie names, for one release.

**Pros:**
- No forced re-login, and each service can deploy independently.

**Cons:**
- Keeps the weaker format reachable in security-sensitive lookup paths. That
  is the property the change was meant to remove.
- Needs a second change to remove the fallback, and a test that it is gone.
- Protects no real users or data.

### Alternative 2: One-off data migration
For example, rewriting existing Redis session keys to their hashed form.

**Cons:**
- Idle sessions expire within 15 minutes, every session within 8 hours and
  OAuth state within 10 minutes. A migration saves little more than one
  re-login.
- Migration tooling for state that will never exist in production is
  untested code with no long-term owner.

## Consequences

**Positive:**
- Contract changes stay small and reviewable, with one code path per
  contract.
- No residual compatibility path keeps an old, weaker format alive.

**Negative:**
- Local users sign in again after each session-contract cutover. Developers
  must run the documented reset on an existing cluster.
- Synchronized merges couple several repositories. Tilt builds sibling
  worktrees, so the local stack is inconsistent until every part lands.
- The production reference's pinned images predate these contracts and do not
  run under the current shared manifests. The offline checks do not detect
  this. A first hosted deployment must release new images and start from
  empty state. See
  [Application And Image Baseline](../../kubernetes/production/README.md#application-and-image-baseline).

**Neutral:**
- The rule describes current circumstances, not a lasting preference against
  migrations.

## References
- [Provider-Neutral Production Reference: Application And Image Baseline](../../kubernetes/production/README.md#application-and-image-baseline)
- [Session Edge Authorization: Shared Session Contract](../architecture/session-edge-authorization-pattern.md#shared-session-contract), which documents the local resets the session cutovers need
- [Local Environment](../development/local-environment.md), which documents Redis reset and AOF behavior
- `scripts/ops/flush-redis.sh`, `scripts/ops/reset-databases.sh`
- [ADR 011: Hashed Session Keys, `__Host-` Session Cookie and Absolute Session Lifetime](011-hashed-session-keys-host-cookie-absolute-lifetime.md)
- Source: the plan-wide rule shared by the 2026-11 security hardening plans,
  added 2026-11-06. The plans were deleted after this ADR was written; see Git
  history.
