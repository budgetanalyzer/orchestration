# Exchange-rate end date has no upper bound

- **Severity:** Medium (not reproduced)
- **Owner:** currency-service
- **Status:** Open. Found while designing the
  [currency cache fix](high-currency-cache-exhausts-shared-redis.md); not
  covered by either security review.

## Problem

`GET /api/v1/exchange-rates` validates only `startDate <= endDate`
(`../currency-service/src/main/java/org/budgetanalyzer/currency/api/ExchangeRateController.java:146-149`).
`ExchangeRateService.buildDenseExchangeRates` then builds one
`ExchangeRateData` per calendar day from the effective start to `endDate`. It
forward-fills the last source rate past the end of the data, with no upper
bound.

So a range that contains at least one source rate and ends at `9999-12-31`
builds about 2.9 million entries in memory. The controller then maps them all
to responses and serializes them. The container memory limit is 512 MiB
(`kubernetes/services/currency-service/deployment.yaml`).

Any account with `currencies:read`, which the default user role has, can send
this request. The likely results are long GC pauses or an OOM-killed pod. With
the current per-range cache, the service would also try to write the huge
result to Redis.

This conclusion comes from reading the code. It has not been run.

## Proposed fix

Bound the effective end date at the service layer. Options:

- Clamp it to `min(endDate, today)`. This keeps forward-fill up to today,
  which is useful for converting recent transactions when the provider data
  lags, and caps the response by data age.
- Reject `endDate` after today with a validation error. This is clearer but
  changes the API contract for existing callers.

Either way, a maximum response is then bounded by the history length (about
20k days).

## Acceptance

- A request with a far-future `endDate` returns a bounded response or a
  `400`. It does not build one entry per day up to that date.
- The chosen behavior is documented on the endpoint and covered by a test.

## Open question

Clamp or reject? Check whether budget-analyzer-web ever requests an `endDate`
after today before deciding.
