# Exchange-rate end date has no upper bound

- **Severity:** Medium (not reproduced)
- **Owner:** currency-service
- **Status:** Resolved and verified live on 2026-11-14 during the Redis
  session/cache split. Found while designing the
  [currency cache fix](high-currency-cache-exhausts-shared-redis.md); not
  covered by either security review.

## Problem

The analysis below describes the code before the fix.

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

- Clamp it to a near-future cap such as `min(endDate, tomorrow)`. This keeps
  forward-fill up to the cap, which is useful for converting recent
  transactions when the provider data lags, and caps the response by data age.
- Reject `endDate` after the cap with a validation error. This is clearer but
  changes the API contract for existing callers.

Either way, a maximum response is then bounded by the history length (about
20k days).

## Resolution

Clamp, as recorded in
[ADR 017](../decisions/017-exchange-rate-end-date-cap.md). currency-service
now bounds the range at the service layer:

- The effective end date is `min(endDate, tomorrow)`. "Tomorrow" is the UTC
  date from an injected `java.time.Clock` plus one day.
- The cap is tomorrow, not today, because transaction-service accepts
  transaction dates through tomorrow, and the web client requests rates
  through its latest transaction date.
- A missing `endDate` means today; it previously meant the last source rate.
- When both dates are supplied, `startDate > endDate` is still a
  `400 INVALID_REQUEST`, checked against the dates as sent, before the cap is
  applied.
- A range with no source rate inside it returns an empty list, including a
  valid future range that becomes empty after the cap.
- After the last source rate, the last rate is forward-filled only up to the
  effective end date.

A maximum response is therefore bounded by the history length, and the
response is sliced from the per-currency cached series, so the end date no
longer creates cache keys either. Clamping was chosen over rejection because
it keeps existing callers working and keeps forward-fill up to the cap for
converting recent transactions when provider data lags. The endpoint contract
lives in currency-service
[docs/api/README.md](https://github.com/budgetanalyzer/currency-service/blob/main/docs/api/README.md#get-v1exchange-rates).
The generated unified API docs (`docs-aggregator/openapi.{json,yaml}` and the
web client's `docs/api/budget-analyzer-api.yaml`) carry the new `endDate`
description.

### Live verification (2026-11-14)

This verification predates the tomorrow cap and exercised the earlier cap at
today. On the local Tilt/Kind stack, THB requests through the ingress returned:

- no `endDate`: `200` with 16,753 daily entries ending today (2026-11-14);
- `startDate=2026-06-01&endDate=2099-12-31`: `200` with 167 entries ending
  today, not one entry per day up to 2099;
- `startDate=2090-01-01&endDate=2099-12-31`: `200` with an empty list.

None of these requests created a cache key other than the single
per-currency series.

## Acceptance

- A request with a far-future `endDate` returns a response bounded by
  tomorrow.
  It does not build one entry per day up to that date.
- The chosen behavior is documented on the endpoint and covered by a test.
