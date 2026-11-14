# Currency cache can exhaust the shared Redis budget

- **Severity:** High
- **Owner:** currency-service and orchestration (Redis storage was split)
- **Status:** Resolved and verified live on 2026-11-14 in Phase 9 of
  [split-redis-session-and-cache.md](../plans/split-redis-session-and-cache.md).
  Previously known (plans 03 P11/P13, 04 P1)
- **Source:** 2026-11-09 implementation review F1; independent implementation review C1

## Problem

The analysis below describes the code and topology before the fix. File paths
and line numbers refer to that state.

`ExchangeRateService.getExchangeRates` is `@Cacheable` with a key of
`currency:startDate:endDate`
(`../currency-service/src/main/java/org/budgetanalyzer/currency/service/ExchangeRateService.java:90-95`).
It returns a daily, forward-filled series, so each distinct range stores its
own full copy of the overlapping rates.

- The number of possible keys is roughly (number of days)² per currency, and
  the caller chooses them.
- Entries are large. The hardening Redis budget measurement recorded 5.24 MB
  for an all-time THB entry and 2.6 MB for 2000 to today. Jackson default typing (`NON_FINAL`) in
  `CacheConfig.redisSerializer` probably adds per-value type ids. This
  overhead has not been measured.
- Each entry has a one-hour TTL (`CacheConfig.EXCHANGE_RATES_TTL`). Nothing
  bounds the entry count or the total size.

These entries share the `--maxmemory 128mb --maxmemory-policy noeviction`
instance with sessions and OAuth state
(then `start-redis.sh` of the single shared instance). During the hardening
Redis budget measurement, a single user with the default `currencies:read`
permission filled the budget with about 100 ordinary exchange-rate reads.
Large ranges were rejected first with `500`, and small ranges then used up the
remainder. After that:

- heartbeats return `503`;
- login initiation redirects to `/oops`, intermittently, as expiring keys free
  small amounts of memory;
- uncached exchange-rate reads return `500`.

The effect lasts up to the cache TTL. Deleting the `currency-service:*` keys
as `redis-ops` restored login and heartbeat immediately. That is a recovery
step, not a fix.

For scale, the same measurement found that the 128 MB budget holds about
75,000–87,000 sessions with their indexes, about 37,600 maximum-size
OAuth-state records, or about 25 all-time exchange-rate entries.

A second defect: when Redis rejects the cache write, the request returns
`500`, even though the database read succeeded. Neither currency-service nor
service-common defines a `CacheErrorHandler` or `CachingConfigurer`, so
Spring's default `SimpleCacheErrorHandler` rethrows cache errors.

## Why the usual shared-cache pattern breaks here

Sharing one cache Redis across services is normal when that instance runs an
eviction policy such as `allkeys-lru`. In that setup a key flood lowers the hit
rate; it doesn't cause an outage. This instance is different:

- It holds sessions and OAuth state, so it must run `noeviction`. A full
  instance rejects writes, and session creation and heartbeat extension are
  writes.
- No eviction policy can separate cache keys from auth keys. `volatile-*`
  policies evict any key with a TTL, and sessions have TTLs.
- Redis has no per-partition memory isolation. Logical DBs share one
  `maxmemory` and policy. ACLs limit commands and keys, not bytes. Key prefixes
  are naming only. Cluster sharding is for scaling, not tenant isolation. Only
  a separate instance has its own budget and policy.
- Moving cache eviction from `KEYS` to `SCAN` changed iteration, not capacity.

This is not a Spring cache limitation. `@Cacheable` memoizes a method by its
arguments. The issue is that it sits on a method whose arguments are
user-chosen ranges.

## Fix options

The goal is to bound the cache's footprint by data, not by user input, so it
fits the shared budget by design. Options 2 and 3 bound how much the cache can
use; they do not isolate its memory from auth data. That is sufficient for this
service.

1. **Fail open on cache errors (do this regardless).** Register a
   `CachingConfigurer` whose `errorHandler()` logs `get`, `put`, `evict` and
   `clear` failures instead of rethrowing. A rejected write then returns the
   database result.
2. **Remove the cache if it doesn't pay off.** There are roughly 6k–20k rows
   per currency, read by an indexed range scan. Measure the uncached query
   before keeping the cache. The javadoc's 50–200 ms miss estimate may be
   mostly serialization and forward-fill, not the database.
3. **Cache per currency, filter in Java.** Put `@Cacheable(key =
   "#currencyCode")` on a method that returns that currency's raw rows,
   without forward-fill. Then filter by range and forward-fill in memory. The key space becomes the number of enabled
   currencies, and the worst-case footprint can be calculated and budgeted.
   Notes:
   - Call the cached method through the Spring proxy (a separate bean or
     self-injection). A plain `this.` call skips caching.
   - Measure one per-currency entry. Consider a leaner value shape or
     serializer if default typing makes it large.
   - The existing `@CacheEvict(allEntries = true)` on import still applies.
4. **Separate cache Redis (only if a large or general-purpose cache is later
   needed).** This is the standard production pattern: no PVC, no AOF,
   `allkeys-lru`. Here it also needs its own ACLs, TLS, network policies,
   production overlay entry, image pinning and verifier coverage. It is more
   than this one cache justifies, and it would still store overlapping ranges
   wastefully.

Keep `noeviction` on the auth instance. Do not compensate in orchestration by
raising `maxmemory` or changing the eviction policy.

## Resolution

The implemented design combines option 1, a variant of option 3 and option 4.
Option 4 was chosen after all, because isolation, not only a bounded cache
size, is what keeps a cache fault from becoming an authentication outage.

### Dedicated cache instance

The single instance is now two:

- `redis-session` is the former instance, renamed. It holds only sessions,
  session indexes and OAuth state for Session Gateway and `ext-authz`, and
  keeps the PVC-backed `/data`, AOF and `noeviction`.
- `redis-cache` is new. It holds only the currency-service cache and is shared
  by every currency-service replica. It is disposable: no PVC, no AOF, no RDB
  snapshots, `allkeys-lru`. Its ACL has only the `currency-service`, `default`
  and `redis-ops` users, its NetworkPolicy admits only currency-service, and it
  has its own TLS leaf, bootstrap Secret, production render and verifier
  coverage.

A cache key flood now lowers the cache hit rate; it cannot reject session or
OAuth-state writes. The `currency-service` `+scan` grant also no longer sees
session key names, because those keys are on another instance. Topology and
operations live in
[system-overview.md](../architecture/system-overview.md#shared-infrastructure-and-observability),
[port-reference.md](../architecture/port-reference.md#local-infrastructure-forwards)
and [local-environment.md](../development/local-environment.md#environment-variables).

### Per-currency series

`ExchangeRateSeriesService.getExchangeRateSeries` is the only `@Cacheable`
method. It caches one dense, forward-filled series per currency in the cache
`exchangeRateSeries`, keyed by the currency code. `ExchangeRateService` is no
longer cached: it checks that the currency is enabled on every call and slices
the requested range in Java, so request date ranges never create cache keys.
The old `exchangeRates` cache and its range key are gone.

The cached value is compact: the base currency, target currency and
`providerSeriesId` once, the series start date, one USD-based rate per day and
one published-date offset per day (0 marks a source rate on that day). A
Jackson serializer bound to that type writes it without default typing or type
ids, and the cache mapper copy disables pretty printing. Entries have a
one-hour TTL, and imports keep `@CacheEvict(allEntries = true)` after commit.
The cache is filled lazily on a miss; there is no warm-up.

A read that queried the database before an import committed can write a stale
series after the eviction, and a failed after-commit eviction leaves the
previous series in place. The one-hour TTL bounds both.

### Fail open

Each cache is `TransactionAwareCacheDecorator(FailOpenCache(RedisCache))`.
`FailOpenCache` logs `get`, `put`, `evict` and `clear` failures and does not
rethrow, so a failed read is served from PostgreSQL and a successful database
operation never fails because of the cache, including deferred after-commit
writes and evictions. A `CacheErrorHandler` was not used because it does not
cover those after-commit operations. Redis connect and command timeouts are
short, and Redis is not part of currency-service readiness.

The end-date bound from the
[unbounded end date issue](medium-exchange-rate-end-date-unbounded-response.md)
was decided as part of the same change.

The authoritative behavior lives in currency-service
[configuration.md](https://github.com/budgetanalyzer/currency-service/blob/main/docs/configuration.md#caching).

### Live measurement (Phase 9, 2026-11-14)

Measured on the local Tilt/Kind stack after the cutover, with `redis-cache`
restarted empty (`maxmemory 64mb`, `allkeys-lru`):

- Baseline `used_memory` `1,091,840` bytes, `evicted_keys` `0`.
- Only THB is enabled locally. Its full range, a 2001 sub-range, a range ending
  in 2099 and a future-only range returned `200` and left exactly one key,
  `currency-service:exchangeRateSeries::THB`, with a one-hour TTL. The range
  ending in 2099 stopped at today and the future-only range was empty.
  `redis-session` held no `currency-service:*` key.
- `MEMORY USAGE` of the THB entry (1981-01-02 to 2026-11-06, 16,745 days):
  `196,696` bytes, a `167,590`-byte value. That is the sum and the largest
  entry. Final `used_memory` `1,462,648` bytes, `evicted_keys` still `0`. The
  previous all-time THB range entry was 5.24 MB.
- `N = 23` rows in `currency_series`. Worst case
  `W = baseline used_memory + N × largest entry = 1,091,840 + 23 × 196,696 =
  5,615,848` bytes (about 5.4 MiB), below half of the `64mb` `maxmemory`
  (`33,554,432` bytes). `maxmemory` stays `64mb` and the container request and
  limit stay 96Mi and 128Mi. JPY data starts in 1971; at the measured
  11.7 bytes per day its entry would be about 240 KB, and `W` about 6.6 MB.
- With `redis-cache` scaled to 0, exchange-rate reads returned `200`
  (about 2.1 to 2.4 seconds, bounded by the short command timeout),
  currency-service stayed Ready with no restarts, `FailOpenCache` logged each
  `get` and deferred `put` failure, and login initiation (`302`), heartbeat
  (`200`) and `/auth/v1/user` (`200`) worked. `redis-cache` was scaled back to
  one Ready replica afterwards.
- Focused verifiers passed: credential isolation 84/84, network policies
  77/77, transport encryption 22/22 and runtime hardening 191/191. The
  pinned-PyYAML smoketest passed (see the plan's Phase 9 outcome).

### Alternative considered

An in-process cache (Caffeine through the same Spring cache abstraction)
would take the cache out of Redis entirely. With more than one replica, an
import evicts only the local cache, and other pods serve stale data up to the
TTL. A shared `redis-cache` keeps one eviction for all replicas. ShedLock does
not need Redis; it uses its JDBC provider and the PostgreSQL `shedlock` table.

## Acceptance

Verified statically by Phases 1 to 8 of the plan and live in Phase 9 (above).

- Requests with arbitrary date ranges never create new cache keys. The key
  count is at most the number of enabled currencies.
- The cache has its own memory budget and `allkeys-lru` policy, so it cannot
  fill the `redis-session` budget. The measured worst-case cache size is about
  5.4 MiB against the 64 MB `redis-cache` budget.
- A failed cache operation returns the database result, not `500`.
- A currency disabled after its series was cached is rejected immediately.
- The existing `ExchangeRateServiceIntegrationTest` cases pass, except for
  deliberate changes from the end-date decision, which update the affected
  tests explicitly.
