# 017. Cap Exchange-Rate End Dates at Tomorrow

**Date:** 2026-11-15
**Status:** Accepted
**Deciders:** Architecture Team

## Context

`GET /v1/exchange-rates` returns one entry per calendar day. After the last
source rate, it forward-fills that rate. Before this change, the only date
check was `startDate <= endDate`, and nothing bounded `endDate`. A range that
contained one source rate and ended at `9999-12-31` would build about
2.9 million entries in a pod with a 512 MiB limit. Any account with the default
`currencies:read` permission could send that request. An omitted `endDate`
meant the last source rate.

The [Redis split](016-separate-session-and-cache-redis.md) replaced the
range-keyed cache with one cached series per currency. That change removed the
end date from cache keys, but left the response size unbounded.

Two callers depend on the end date:

- The web client requests rates through its latest transaction date
  (`useCurrencies.ts`).
- transaction-service accepts transaction dates through tomorrow
  (`TransactionService.maxAllowedTransactionDate` and
  `ConfigurableCsvStatementExtractor`). Both compute `LocalDate.now().plusDays(1)`.

The full problem analysis lived in the issue "Exchange-rate end date has no
upper bound", which was deleted after this ADR was written; see Git history.

## Decision

Clamp the effective end date in currency-service's `ExchangeRateService`
instead of rejecting large values:

- "Today" is `LocalDate.now(clock)` from the injected `Clock`. In production
  this is `Clock.systemUTC()`.
- An omitted `endDate` means today.
- An explicit `endDate` after tomorrow (today plus one day) is treated as
  tomorrow. Earlier values are used as sent.
- An omitted `startDate` means the first date of the cached series. A
  `startDate` before it is still `START_DATE_OUT_OF_RANGE`.
- If both dates are supplied, `startDate > endDate` is rejected on the dates as
  sent, before the cap is applied:
  - the controller returns `400 INVALID_REQUEST`;
  - the service throws `IllegalArgumentException` for direct callers.

  A reversed range is never turned into an empty response by clamping.
- The result is an empty list when the effective start is after the effective
  end, or when no source rate falls in the effective range. A valid range that
  starts after tomorrow is one example.
- After the last source rate, the last rate and its published date are
  forward-filled up to the effective end date.

The cached series ends at the last source rate. The cap is applied per
request, so the cached value does not change at midnight.

The cap is tomorrow, not today, because a transaction dated tomorrow is valid
in transaction-service. The web client then asks for a rate on that date.

## Alternatives Considered

### Alternative 1: Reject an `endDate` after the cap
**Pros:**
- Explicit. The caller knows the range was not served as requested.

**Cons:**
- Breaks existing callers that pass a future or open-ended date.

### Alternative 2: Cap at today
**Pros:**
- Never forward-fills to a date that has not started in UTC.
- Matches the omitted-`endDate` default.

**Cons:**
- A transaction dated tomorrow, which transaction-service accepts, gets no
  rate.
- This was the first implementation, verified live on 2026-11-14. The
  2026-11-15 review replaced it with tomorrow.

### Alternative 3: Paginate or limit the number of entries
**Cons:**
- A larger contract change for every caller. The history length already
  bounds the response once the end date is capped.

## Consequences

**Positive:**
- The largest response is bounded by the history length plus one day. The
  longest local series, JPY from 1971-01-04, is about 20,400 days.
- Tomorrow-dated transactions receive a forward-filled rate.
- Existing callers keep working. A far-future `endDate` is truncated, not
  rejected.

**Negative:**
- The omitted-`endDate` behavior changed from the last source rate to today.
- Truncation is silent. A caller can detect it only from the last returned
  date.
- The defaults are asymmetric: an omitted `endDate` means today, while an
  explicit one may reach tomorrow.
- The cap copies transaction-service's bound without a shared contract. If
  either bound changes, both services must change.
  - transaction-service uses the JVM default time zone, while currency-service
    uses UTC.
  - The two agree only while transaction-service runs in UTC, which is the
    container default.

**Neutral:**
- The contract is documented in currency-service's API docs and OpenAPI
  `endDate` description. It also appears in the generated unified API docs,
  the web client's `getExchangeRates` comments, and the API tests
  `test_get_exchange_rates_caps_future_end_date_at_tomorrow` and
  `test_get_exchange_rates_defaults_omitted_end_date_to_today`.

## References
- [currency-service `GET /v1/exchange-rates`](https://github.com/budgetanalyzer/currency-service/blob/main/docs/api/README.md#get-v1exchange-rates)
- [ADR 016: Separate Session and Cache Redis Instances](016-separate-session-and-cache-redis.md)
- Source: the Redis session/cache split plan, which set the cap at today, and
  its 2026-11-15 review remediation plan, which moved it to tomorrow. Both
  plans were deleted after this ADR was written; see Git history.
