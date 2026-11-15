# 016. Separate Session and Cache Redis Instances With a Bounded, Fail-Open Currency Cache

**Date:** 2026-11-15
**Status:** Accepted
**Deciders:** Architecture Team

## Context

Before this change one Redis instance, `redis`, held two kinds of data:

- sessions, session indexes and OAuth state for Session Gateway and
  `ext-authz`;
- the currency-service exchange-rate cache.

The instance ran `--maxmemory 128mb --maxmemory-policy noeviction` with AOF on
a PVC, because auth data must not be evicted.

The cache was `@Cacheable` on `ExchangeRateService.getExchangeRates`, keyed by
`currency:startDate:endDate`. Each distinct range stored its own dense,
forward-filled copy of the overlapping rates, serialized with Jackson default
typing. The caller chose the keys, and an all-time THB entry measured 5.24 MB.
During the 2026-11 hardening measurement, one user with the default
`currencies:read` permission filled the budget with about 100 ordinary reads.
After that, heartbeats returned `503`, login initiation redirected to
`/oops`, and uncached exchange-rate reads returned `500` because Spring's
default cache error handler rethrew the rejected write.

The shared instance could not be configured to contain this:

- An eviction policy cannot distinguish cache keys from auth keys.
  `volatile-*` policies evict any key with a TTL, and sessions have TTLs.
- Logical DBs share one `maxmemory` and policy. ACLs limit commands and keys,
  not bytes, and key prefixes are only naming.
- Raising `maxmemory` moves the threshold but leaves the key space unbounded.

The full problem analysis lives in
[the currency cache issue](../issues/high-currency-cache-exhausts-shared-redis.md).

## Decision

### 1. Two Redis instances with separate roles

| | `redis-session` | `redis-cache` |
|---|---|---|
| Holds | Sessions, session indexes, OAuth state | Only the currency-service cache |
| Workload | StatefulSet (the former `redis`, renamed) | Deployment, one replica |
| Persistence | PVC-backed `/data`, `--appendonly yes` | `emptyDir` `/data`, `--appendonly no`, `--save ""` |
| Memory | `--maxmemory 128mb`, `noeviction` | `--maxmemory 64mb`, `allkeys-lru`; container request 96Mi, limit 128Mi |
| Application ACL users | `session-gateway`, `ext-authz` | `currency-service` |
| Admits traffic from | Session Gateway, `ext-authz` | currency-service |

- Each instance has its own ACL ConfigMap, bootstrap Secret
  (`redis-{session,cache}-bootstrap-credentials`), TLS leaf from the
  infrastructure CA (`infra-tls-redis-{session,cache}`), NetworkPolicy, Tilt
  resource and verifier coverage.
- Every application user exists on exactly one instance. The `default` and
  `redis-ops` users exist on both, with separate passwords:
  `REDIS_SESSION_DEFAULT_PASSWORD`, `REDIS_SESSION_OPS_PASSWORD`,
  `REDIS_CACHE_DEFAULT_PASSWORD` and `REDIS_CACHE_OPS_PASSWORD`. The
  `currency-service` ACL rule set moved to `redis-cache` unchanged.
- Both Services listen on `6379`. Tilt forwards VM-loopback `6379` to
  `redis-session` and `6380` to `redis-cache`.
- The production reference includes `redis-cache` through the shared base. It
  has no storage patch, because the cache has no storage.
- Redis ops tooling has no default instance. `scripts/ops/flush-redis.sh` and
  `scripts/ops/redis-browse.sh` require `session` or `cache`, and
  `scripts/lib/redis-cli.sh` accepts only `redis-session` or `redis-cache`.
  Flushing the cache skips the AOF rewrite that the session flush performs.

`redis-cache` uses `emptyDir` on purpose: it is a cache, not a stateful data
store. The manifest says so in a comment, so the guardrail against replacing
StatefulSets with `emptyDir` does not apply.

### 2. One cache entry per currency

The cache key is bounded by data, not by request parameters.

- `ExchangeRateSeriesService.getExchangeRateSeries` is the only `@Cacheable`
  method. It uses the cache `exchangeRateSeries`, keyed by currency code, and
  returns the dense, forward-filled series from the currency's first source
  rate to its last. The method sits on a separate bean so that calls from
  `ExchangeRateService` pass through the caching proxy.
- `ExchangeRateService.getExchangeRates` is not cached. It checks on every
  call that the currency is enabled, then slices the requested range from the
  cached series in Java.
- The cached value is the compact `ExchangeRateSeries` record: the constant
  fields once, the start date, one USD-based rate per day and one
  published-date offset per day.
- A `JacksonJsonRedisSerializer` bound to `ExchangeRateSeries` writes the
  values. It uses a copy of the application `JsonMapper` with pretty printing
  disabled, and writes no type ids.
- Entries have a one-hour TTL and are filled lazily on a miss, with no warm-up.
  Imports keep `@CacheEvict(allEntries = true)`, which runs after commit.
- A read that queried the database before an import committed can write a
  stale series after the eviction. A failed after-commit eviction leaves the
  previous series in place. The TTL bounds both, and there are no versioned
  keys.

### 3. The cache fails open

- `CacheConfig` overrides `RedisCacheManager.decorateCache`, so each cache is
  `TransactionAwareCacheDecorator(FailOpenCache(RedisCache))`. Deferred
  after-commit `put`, `evict` and `clear` calls also pass through the fail-open
  layer, regardless of interceptor order.
- `FailOpenCache` treats only `DataAccessException` and Spring Data Redis
  `SerializationException` as cache failures. In the async `retrieve` paths, it
  checks the cause inside `CompletionException` and `ExecutionException`.
  - A failed read is a miss, and a failed write or eviction does nothing.
  - Any other exception propagates. A value-loader exception also propagates,
    including a database `DataAccessException` thrown by the loader.
  - A failure is logged at `WARN` without a stack trace, and at `DEBUG` with
    it.
- The writer uses `immediateWrites()` and clears with `SCAN`/`DEL` in batches
  of 1000, so the ACL user needs no `KEYS`.
- The custom cache manager is registered when `spring.cache.type` is `redis`
  or unset. If unset matched nothing, Spring Boot would build a plain Redis
  cache manager that is neither fail-open nor transaction-aware. Tests that set
  `spring.cache.type=none` get Boot's no-op manager.
- currency-service uses `spring.data.redis.timeout: 1s` and
  `connect-timeout: 1s`. Its readiness group is `readinessState,db`, so Redis
  is not part of currency-service readiness.

Fail-open applies only to this cache. Session Gateway keeps `redis` in its
readiness group, because `redis-session` is required for authentication.

## Alternatives Considered

### Alternative 1: Bound the cache key but keep one shared instance
**Pros:**
- No new instance, TLS leaf, Secret, policy or verifier coverage.
- The per-currency footprint can be calculated, so it fits the shared budget.

**Cons:**
- The cache and auth data still share one `noeviction` budget, so a cache
  defect or a future cache can cause an auth outage again.
- `currency-service`'s `+scan` grant could still list session key names.
- This was the issue's preferred option until review. It was rejected because
  isolation, not only a bounded size, keeps a cache fault from becoming an
  authentication outage.

### Alternative 2: Change the eviction policy or partition the shared instance
**Cons:**
- `allkeys-*` or `volatile-*` policies can evict sessions and OAuth state.
- Logical DBs, key prefixes and ACLs do not isolate memory.

### Alternative 3: In-process cache (Caffeine)
**Pros:**
- No Redis dependency for the cache.

**Cons:**
- With more than one replica, an import evicts only the local cache, and other
  pods serve stale data for up to the TTL. A shared `redis-cache` evicts once
  for all replicas.

### Alternative 4: Remove the cache
**Pros:**
- Removes a dependency and the stale-write race.

**Cons:**
- No measurement of the uncached query was recorded. The cache was kept, and
  the bounded key and fail-open behavior make the cost of keeping it
  predictable.

### Alternative 5: `CacheErrorHandler` instead of a decorator
**Cons:**
- `TransactionAwareCacheDecorator` runs deferred `put`, `evict` and `clear` in
  `afterCommit`, outside the annotation-level handler. A failure there would
  reach the caller after the database had committed.

## Consequences

**Positive:**
- A cache key flood lowers the cache hit rate. It cannot reject session or
  OAuth-state writes.
- The number of cache keys is at most the number of `currency_series` rows. The
  recomputed worst case is about 6.6 MiB against the 64 MB budget; see
  [Redis Memory Budgets](../architecture/security-architecture.md#redis-memory-budgets).
- With `redis-cache` scaled to 0, exchange-rate reads still returned `200`.
  They took about 2.1 to 2.4 seconds, bounded by the command timeout, and
  currency-service stayed Ready. Login and heartbeat were unaffected.
- `verify-credential-isolation.sh` asserts each instance's exact `maxmemory`,
  eviction policy, `appendonly` and `save` values. It also asserts that
  foreign application users do not exist on either instance.

**Negative:**
- There is more infrastructure to keep aligned: a second TLS leaf, bootstrap
  Secret, ACL, NetworkPolicy, Tilt resource, image-pinning entry and verifier
  coverage, plus two more `.env` passwords.
- Every request reads and deserializes the currency's whole series, about
  197 KB for THB, even for a one-day range.
- The serializer is bound to `ExchangeRateSeries`, so the cache manager can
  hold only that type. A second cache with a different value type needs its
  own configuration.
- A Redis outage adds up to the command timeout to each cache call.
- The cutover deleted the old instance and its PVC, which logged everyone out
  once, under [ADR 015](015-reset-local-state-instead-of-migrating.md).
  - The Tiltfile deletes the pre-split NetworkPolicy
    `allow-redis-ingress-from-approved-default-workloads`.
  - The removed `REDIS_DEFAULT_PASSWORD` and `REDIS_OPS_PASSWORD` keys would
    otherwise be ignored silently. Instead, the Tiltfile warns about any
    `.env` key that `.env.example` does not declare, naming keys only.

**Neutral:**
- `redis-cache` restarts empty. Pod replacement is a cache reset, while
  `redis-session` keeps its PVC-backed data.
- currency-service's `application.yml` port default stays `6379`. The
  Kubernetes deployment sets the host, and the local `bootRun` workflow sets
  port `6380`.

## Changes During Implementation

The plan's design changed in two places during implementation, and this ADR
records the implemented behavior.

- The plan registered the custom cache manager only when
  `spring.cache.type=redis`. It was widened to match an unset property, so
  Spring Boot cannot silently fall back to a plain Redis cache manager.
- The first `FailOpenCache` absorbed every `RuntimeException` and logged stack
  traces at `WARN`. The 2026-11-15 review narrowed it to the two
  cache-infrastructure exception families listed above. It also moved stack
  traces to `DEBUG`, so an outage does not log one per request.

## References
- [Currency cache can exhaust the shared Redis budget](../issues/high-currency-cache-exhausts-shared-redis.md), which records the problem, the resolution and the live measurements
- [Redis Memory Budgets](../architecture/security-architecture.md#redis-memory-budgets)
- [Port Reference: Local Infrastructure Forwards](../architecture/port-reference.md#local-infrastructure-forwards)
- [Local Environment: Redis Local Access](../development/local-environment.md#redis-local-access)
- [currency-service caching](https://github.com/budgetanalyzer/currency-service/blob/main/docs/configuration.md#caching)
- [service-common Redis Distributed Caching pattern](https://github.com/budgetanalyzer/service-common/blob/main/docs/advanced-patterns.md#redis-distributed-caching)
- [ADR 015: Reset Local State Instead of Migrating](015-reset-local-state-instead-of-migrating.md)
- [ADR 017: Cap Exchange-Rate End Dates at Tomorrow](017-exchange-rate-end-date-cap.md), decided in the same change
- Source: the Redis session/cache split plan and its 2026-11-15 review
  remediation plan. Both plans were deleted after this ADR was written; see
  Git history.
