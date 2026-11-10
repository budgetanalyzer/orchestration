# Currency cache can exhaust the shared Redis budget

- **Severity:** High
- **Owner:** currency-service (orchestration only if Redis storage is split)
- **Status:** Open, previously known (plans 03 P11/P13, 04 P1)
- **Source:** [review](../research/security-hardening-implementation-review-2026-11-09.md)
  F1; [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  C1

## Problem

`ExchangeRateService.getExchangeRates` is `@Cacheable` with a key of
`currency:startDate:endDate`
(`../currency-service/src/main/java/org/budgetanalyzer/currency/service/ExchangeRateService.java:90-95`).
It returns a daily, forward-filled series, so each distinct range stores its
own full copy of the overlapping rates.

- The number of possible keys is roughly (number of days)² per currency, and
  the caller chooses them.
- Entries are large. The evidence record measured 5.24 MB for an all-time THB
  entry and 2.6 MB for 2000 to today. Jackson default typing (`NON_FINAL`) in
  `CacheConfig.redisSerializer` probably adds per-value type ids. This
  overhead has not been measured.
- Each entry has a one-hour TTL (`CacheConfig.EXCHANGE_RATES_TTL`). Nothing
  bounds the entry count or the total size.

These entries share the `--maxmemory 128mb --maxmemory-policy noeviction`
instance with sessions and OAuth state
(`kubernetes/infrastructure/redis/start-redis.sh`). The
[plan 04 measurement](../research/security-consensus-hardening-evidence.md#shared-cache-growth-reported-not-changed)
shows a single user with default `currencies:read` filling the budget in
about 100 reads. After that:

- heartbeats return `503`;
- login initiation redirects to `/oops`;
- uncached exchange-rate reads return `500`.

The effect lasts up to the cache TTL.

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

## Chosen approach

Option 1, plus a variant of option 3: a separate bean builds the
forward-filled (dense) series for one currency and caches it per currency.
`ExchangeRateService` stops being `@Cacheable` and slices the requested range
from the cached series.

### Shape

- **Series bean** (for example `ExchangeRateSeriesProvider`):
  - `@Cacheable(cacheNames = "exchangeRateSeries", key = "#currencyCode")`,
    `@Transactional(readOnly = true)`.
  - Loads every rate for the currency in date order and builds the dense
    series from the first source rate to the last.
  - Being a separate bean also avoids the self-invocation proxy bypass.
  - Use a new cache name. Old range entries under `exchangeRates` cannot
    collide with the new keys, but a new name makes leftover entries obvious;
    they expire within the old 1-hour TTL.
- **`ExchangeRateService.getExchangeRates`** (no longer cached):
  1. Checks the currency is enabled, uncached. Today the check sits inside the
     cached method, so a currency disabled after its range was cached is served
     for up to the TTL.
  2. Fetches the cached series.
  3. Rejects a `startDate` before the series start with the existing
     `START_DATE_OUT_OF_RANGE` error.
  4. Slices the requested range.
- **Eviction:** the existing `@CacheEvict(allEntries = true)` on import
  applies unchanged; the cache name it targets must be updated.

### Semantics to preserve

`ExchangeRateServiceIntegrationTest` locks these in:

- A null `startDate` means the first source rate. A null `endDate` means the
  last source rate.
- If no source rate (an entry whose `publishedDate == date`) falls inside the
  requested range, return an empty list. This covers future ranges and
  ranges inside a data gap (`queryForFutureDateRangeReturnsEmptyList`,
  `queryForDateRangeWithNoDataReturnsEmptyList`,
  `emptyResultIsDistinctFromNoDataException`). A dense slice would otherwise
  return forward-filled values for these.
- If the range contains a source rate but ends after the last source rate,
  the current code forward-fills the last rate up to `endDate`. Slicing alone
  stops at the series end, so the slice has to be extended. This is where the
  [unbounded end date issue](medium-exchange-rate-end-date-unbounded-response.md)
  must be decided, rather than carrying the unbounded behavior over.
- Lookback for a `startDate` on a non-rate day and `publishedDate`
  preservation come for free from the dense series.

### Cached value must be compact

A dense series of `ExchangeRateData` written with the current serializer is
roughly the measured all-time entry: about 5 MB per currency. With all 23
seeded currencies enabled, that is about 120 MB, over the 128 MB budget.
Every request, even a one-week range, would also fetch and deserialize the
whole series from Redis.

Cache a compact value instead:

- the constant per-currency fields once (base, target, `providerSeriesId`);
- the series start date;
- one rate per day;
- one published-date offset per day.

The slice index is then `date - startDate`. Measure one all-time entry and
record the worst case (all currencies enabled) against the Redis budget.

### Alternative considered

An in-process cache (Caffeine through the same Spring cache abstraction)
would take the cache out of Redis entirely. currency-service runs one
replica today. With more replicas, an import evicts only the local cache, and
other pods serve stale data up to the TTL. That is the same staleness the
existing read-during-import race already accepts. ShedLock still needs Redis,
so the currency-service Redis credential would stay.

## Acceptance

- Requests with arbitrary date ranges never create new cache keys. The key
  count is at most the number of enabled currencies.
- The recorded worst-case total cache size fits inside the Redis budget
  alongside the session and OAuth-state allowance.
- A rejected cache write (Redis at `maxmemory`) returns the database result,
  not `500`.
- A currency disabled after its series was cached is rejected immediately.
- The existing `ExchangeRateServiceIntegrationTest` cases pass. The only
  exceptions are deliberate changes from the end-date decision, and those
  update the affected tests explicitly.
