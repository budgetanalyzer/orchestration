# Load Testing With Synthetic Users Plan

Date: 2026-04-09

## Scope Revision

Track 1 is now the synthetic data-fixture track only for local work. The
immediate need is full local data load, including Redis session hashes and
`user_sessions:{userId}` indexes, so flows like user deactivation and session
revocation can be exercised without generating local load.

Active Track 1 scope:

- item 1: synthetic users plus synthetic sessions
- item 2: per-user transaction amplification
- item 5: unified teardown
- Track 1 documentation for the seed/verify/teardown flow

Deferred for later:

- item 3: local k6 or any other traffic driver
- item 4: real-Auth0 login smoke track

## Goal

Give Budget Analyzer a repeatable way to load realistic local synthetic users,
sessions, and per-user data volume without depending on Auth0.

After this work:

1. a single script seeds N synthetic users into `permission-service` with the
   same `id` / `idp_sub` shape that `UserSyncService` would produce at JIT time
2. the same script writes real `session:{id}` hashes and
   `user_sessions:{userId}` index entries into Redis so `ext-authz` validates
   traffic from synthetic users exactly as it validates real sessions
3. a companion script populates `transaction-service` with parameterized
   per-user data volumes so fixtures reflect realistic shapes
4. a single teardown script removes everything synthetic in one pass by a
   `loadtest` prefix, touching no real data
5. the seeding flow emits a reusable session-pool file at a known path so any
   later traffic driver can consume the same synthetic sessions without
   redefining fixture generation

## Non-Goals

- Do not build a generic load-testing platform. This plan targets local Tilt
  and kind, not CI or production. The active Track 1 work stops at data
  loading; it does not check in a local load driver yet.
- Do not attempt to load-test Auth0. The real-Auth0 track is a smoke track for
  the login flow, not a throughput test.
- Do not change `UserSyncService`, `session-gateway`, `ext-authz`, or any
  backend service code. Everything lands in fixtures, scripts, and docs.
- Do not introduce a new test data seeder abstraction inside the Spring Boot
  services. Fixtures go in via direct SQL against the dev databases.
- Do not ship synthetic session writers as anything other than a local dev
  tool. Production Redis must never receive bulk-seeded sessions.
- Do not attempt to hide the `loadtest` prefix or tag the synthetic users as
  real users. The prefix is intentional so cleanup and auditing stay trivial.

## Current State

- `permission-service.users` is created JIT at first login by
  [`UserSyncService.java`](/workspace/permission-service/src/main/java/org/budgetanalyzer/permission/service/UserSyncService.java)
  using `usr_<uuid-hex>` ids and the default `USER` role. Direct inserts must
  match this shape and populate the audit columns from
  [`V1__initial_schema.sql`](/workspace/permission-service/src/main/resources/db/migration/V1__initial_schema.sql).
- `transaction-service.transaction.owner_id` was added in
  [`V10__add_owner_id.sql`](/workspace/transaction-service/src/main/resources/db/migration/V10__add_owner_id.sql)
  and is a soft reference to `permission-service.users.id`. No cross-database
  foreign key exists, so fixture scripts must use the same id in both places.
- `session-gateway` writes Redis session hashes on real logins. `ext-authz`
  reads those hashes per request and does not care how they were written —
  confirmed by the existing
  [`scripts/ops/seed-ext-authz-session.sh`](../../scripts/ops/seed-ext-authz-session.sh)
  which bypasses Auth0 entirely for a single test session.
- The session data path depends on a companion `user_sessions:{userId}` Redis
  set used by `DELETE /internal/v1/sessions/users/{userId}` for bulk
  revocation. The current single-session seeder does not populate this index.
- `scripts/dev/seed-loadtest-users.sh` now covers the bulk synthetic-user path:
  it seeds permission-service users, matching Redis session hashes, and the
  required `user_sessions:{userId}` index entries in one pass.
- `scripts/dev/seed-loadtest-transactions.sh` now covers deterministic
  per-user transaction amplification for those synthetic users.
- Session TTL defaults to 15 minutes. Long test runs must either refresh via
  `GET /auth/v1/session` heartbeat or accept session churn.
- `scripts/dev/teardown-loadtest.sh` now provides surgical teardown for the
  synthetic fixture set, while `scripts/ops/reset-databases.sh` still exists
  for wholesale resets of the three local databases.
- Auth0 free tier Management API is capped at 2 req/s with burst 10. Paid
  tenants get 15 req/s with burst 50. Bulk import jobs are limited to two
  concurrent jobs per tenant and 500KB per file. Free tier MAU cap is 25K per
  month. Tenant-wide login rate limits and anomaly detection will throttle any
  direct-to-Auth0 load test unless disabled in a dedicated test tenant.

## Design Decision

Load testing Budget Analyzer is two separate problems, and this plan treats
them as two separate tracks.

**Track 1 — data path (primary).** Real production traffic is ~99% API calls
on existing sessions, not logins. `ext-authz` validates any session hash in
Redis regardless of provenance. Pre-seeding users plus synthetic Redis
sessions gives full coverage of Istio ingress → `ext-authz` → NGINX → backends
→ databases with zero dependency on Auth0. This is the primary track because
it exercises the path that carries the real load and because it is not capped
by any external rate limit.

**Track 2 — login path (narrow smoke).** `session-gateway` and the OAuth flow
still need coverage. A small pool of real Auth0 users in a dedicated test
tenant exercises the login code path under modest concurrency. This track is
explicitly not a throughput test — it is a correctness track.

A direct-to-database-only approach (no Redis sessions) is rejected. It leaves
`session-gateway`, `ext-authz`, Istio ingress, and NGINX uncovered and tends
to hide the bottlenecks that matter most.

A direct-to-Auth0-only approach is also rejected. Auth0's tenant-wide rate
limits will cap throughput before Budget Analyzer's own limits surface, and
the MAU quota is a real cost.

Track 1 and Track 2 must use disjoint id spaces:

- Track 1 users: `id = usr_loadtest_<n>`, `idp_sub = loadtest|<n>`,
  `email = loadtest-<n>@budgetanalyzer.invalid`
- Track 2 users: real Auth0 subs, JIT-provisioned by `UserSyncService`

Track 1 synthetic sessions must maintain the `user_sessions:{userId}` index,
or bulk revocation tests will silently break.

All synthetic data must be identifiable by a `loadtest` marker — the id
prefix for users, a dedicated `idp_sub` prefix, and a per-row marker on
transactions (for example `description LIKE 'LOADTEST:%'` or a dedicated
`created_by = 'LOADTEST'`). Teardown relies on these markers.

Scaling shape must be two-dimensional: `N users × M transactions/user`. A
10K-user × 1-transaction fixture and a 100-user × 10K-transaction fixture
stress different parts of the system and neither subsumes the other.

## Implementation Status

Implemented in orchestration:

- `scripts/lib/loadtest-common.sh` — shared kind-only guard, PostgreSQL
  helpers, Redis helpers, and loadtest constants
- `scripts/dev/seed-loadtest-users.sh` — synthetic users, roles, Redis session
  hashes, Redis `user_sessions:{userId}` indexes, and `.loadtest/session-pool.txt`
- `scripts/dev/seed-loadtest-transactions.sh` — deterministic per-user
  transaction amplification for the seeded synthetic users
- `scripts/dev/teardown-loadtest.sh` — surgical cleanup for Redis, PostgreSQL,
  and the generated pool file

Deferred:

- `tests/loadtest/*` data-path driver work
- Auth0 login-smoke tooling and tenant-hardening guide

## Work Plan

### 1. Seed synthetic users and sessions (Track 1)

Add a new script that bulk-creates permission-service users and matching
Redis session hashes in one pass.

Files to change:

- `scripts/dev/seed-loadtest-users.sh` (new)
- `scripts/lib/` — a shared helper for the permission-service psql exec
  and for redis `HSET` writes in a loop, if one does not already exist
- `scripts/README.md`

Required outcomes:

- `./scripts/dev/seed-loadtest-users.sh --count 1000` inserts 1000 rows into
  `permission-service.users` with `id = usr_loadtest_<n>`,
  `idp_sub = loadtest|<n>`, `email = loadtest-<n>@budgetanalyzer.invalid`,
  populated audit columns, and `status = ACTIVE`
- the same run inserts 1000 matching rows in `user_roles` granting `USER`
- the same run writes 1000 `session:loadtest_<n>` hashes into Redis with
  `user_id`, `roles`, `permissions`, `created_at`, `expires_at`, matching the
  shape `session-gateway` produces for real logins
- the same run adds every synthetic session id to the corresponding
  `user_sessions:usr_loadtest_<n>` Redis set
- the script is idempotent: a second run at the same count is a no-op, and a
  larger count extends without rewriting existing rows
- the script refuses to run against anything that is not the local Tilt
  cluster (explicit context check)
- the script supports an optional `--admin-count` flag that grants `ADMIN`
  instead of `USER` to the first K users, for admin-path coverage
- the script supports a `--session-ttl` flag so long runs can extend TTL past
  the default 15 minutes for the duration of a single test
- the script emits a session-cookie pool file at a known path
  (`.loadtest/session-pool.txt`, gitignored) that the load driver consumes

### 2. Per-user data amplifier (Track 1)

Add a second script that generates realistic per-user transaction volume
against the already-seeded synthetic users.

Files to change:

- `scripts/dev/seed-loadtest-transactions.sh` (new)
- `scripts/README.md`

Required outcomes:

- `./scripts/dev/seed-loadtest-transactions.sh --per-user 100` inserts 100
  transactions per synthetic user into `transaction-service.transaction` with
  `owner_id = usr_loadtest_<n>`, a deterministic `description` carrying a
  `LOADTEST:` marker, and reasonable date / amount / currency distributions
- the script operates only on users whose id matches the `usr_loadtest_`
  prefix — it never touches real users' data
- the script is idempotent at a given `--per-user` value and extends without
  rewriting on increase
- the script fails cleanly if `seed-loadtest-users.sh` has not run first
- the script supports a `--shape` flag to switch between common shapes:
  `uniform`, `heavy-tail` (few users with 10× volume), and `sparse` (most
  users with near-zero volume)
- the script refuses to run against anything that is not the local Tilt
  cluster

### 3. Deferred load driver integration

This item is intentionally deferred. Keep the session-pool file contract so a
later data-path driver can reuse the seeded sessions without revisiting the
fixture scripts.

Files to change:

- `tests/loadtest/k6-data-path.js` (new)
- `tests/loadtest/README.md` (new)

Required outcomes:

- the k6 script reads `.loadtest/session-pool.txt`, assigns one session per
  virtual user, and drives a small endpoint mix against `/api/*` that
  covers a read-heavy pattern, a write pattern, and a paginated list pattern
- the k6 script implements the `GET /auth/v1/session` heartbeat so sessions
  survive stages longer than the Redis TTL
- the k6 script emits stage-level P50 / P95 / P99 per endpoint and overall
  error rate, formatted for manual review
- the README documents the required Tilt state, the seeding order, and how
  to interpret ext-authz and Istio throttle counters during a run
- the k6 script has a dry-run mode that validates the session pool without
  sending real traffic

### 4. Login-path smoke track (Track 2, deferred)

Document the small real-Auth0 pool and add a tenant-hardening checklist.

Files to change:

- `docs/setup/auth0-load-test-tenant.md` (new)
- `tests/loadtest/k6-login-path.js` (new)
- `tests/loadtest/README.md`

Required outcomes:

- a documented procedure for provisioning ~20 pre-registered Auth0 users in a
  dedicated test tenant via the Management API, with a shared known password
- the test tenant's Brute Force Protection, Suspicious IP Throttling, and
  anomaly detection are explicitly disabled, documented, and called out as
  unsafe to apply to the production tenant
- a k6 login-path script that exercises the real OAuth flow against
  `session-gateway` at modest concurrency (single-digit req/s) and verifies
  successful session issuance plus `ext-authz` acceptance on a follow-up
  `/api/*` call
- the login-path track is never run with Track 1 credentials and never
  touches `loadtest|*` ids

### 5. Unified teardown

Add one teardown script that removes every synthetic artifact by the
`loadtest` marker.

Files to change:

- `scripts/dev/teardown-loadtest.sh` (new)
- `scripts/README.md`

Required outcomes:

- `./scripts/dev/teardown-loadtest.sh` deletes every `session:loadtest_*` key
  and every `user_sessions:usr_loadtest_*` key from Redis
- the same run deletes every `transaction` row where `owner_id` begins with
  `usr_loadtest_` and every row with the `LOADTEST:` marker
- the same run deletes every `user_roles` row and every `users` row where
  `idp_sub` begins with `loadtest|`
- the script is idempotent and safe to run without any synthetic data
  present
- the script refuses to run against anything that is not the local Tilt
  cluster
- the script prints a summary row count per table / per Redis key pattern
  so operators can sanity-check cleanup

### 6. Documentation

Update the relevant documentation in the same work as the scripts.

Files to change:

- `docs/development/local-environment.md`
- `scripts/README.md`
- `AGENTS.md` if any guardrail or discovery command changes

Required outcomes:

- the local environment guide points to the active seeding and teardown
  scripts with one concrete example command per step
- the scripts README covers the full seed-verify-teardown cycle end-to-end
- deferred Track 1 driver docs and Track 2 tenant-hardening cross-links land
  only when items 3 or 4 resume

## Execution Order

Implement in stages that keep the active data-fixture work separate from the
deferred traffic-generation work.

1. **Current stage — Track 1 data fixtures:** items 1, 2, 5 plus the parts of
   item 6 that cover seeding, verification, and teardown. This unblocks local
   deactivation/session-revocation testing with realistic data.
2. **Deferred stage — Track 1 traffic driver:** item 3 when we actually want
   local throughput generation.
3. **Deferred stage — Track 2:** item 4 plus the Auth0 cross-links in item 6.

## Open Questions

- Does the load driver need to run from inside the Tilt cluster (to bypass
  the dev TLS setup and avoid `localhost` ingress quirks), or is an
  out-of-cluster k6 run against `https://app.budgetanalyzer.localhost`
  acceptable? Default assumption: out-of-cluster against the real ingress,
  because that is what the test is actually measuring.
- Should the synthetic session writer go through `session-gateway`'s Redis
  client config (credentials, TLS, key naming) or talk to Redis directly like
  `seed-ext-authz-session.sh` does today? Default assumption: direct, because
  it is consistent with the existing seeder and avoids coupling the fixture
  to Spring Boot startup.
- Should the plan cover Grafana dashboard additions for load-test runs?
  Default assumption: no, observability stack changes are out of scope for
  this plan and tracked separately.

## References

- [`docs/architecture/security-architecture.md`](../architecture/security-architecture.md)
  — session hash shape, `ext-authz` contract, bulk revocation index
- [`docs/setup/auth0-setup.md`](../setup/auth0-setup.md) — real tenant setup,
  which this plan explicitly does not modify
- [`scripts/ops/seed-ext-authz-session.sh`](../../scripts/ops/seed-ext-authz-session.sh)
  — single-session seeder that proves the direct-to-Redis pattern works
- [`permission-service/src/main/java/.../UserSyncService.java`](/workspace/permission-service/src/main/java/org/budgetanalyzer/permission/service/UserSyncService.java)
  — authoritative user id / role shape
- [`transaction-service/src/main/resources/db/migration/V10__add_owner_id.sql`](/workspace/transaction-service/src/main/resources/db/migration/V10__add_owner_id.sql)
  — `owner_id` contract
- Auth0 Management API rate limits:
  https://auth0.com/docs/troubleshoot/customer-support/operational-policies/rate-limit-policy
- Auth0 bulk import schema and limits:
  https://auth0.com/docs/manage-users/user-migration/bulk-user-import-schema
