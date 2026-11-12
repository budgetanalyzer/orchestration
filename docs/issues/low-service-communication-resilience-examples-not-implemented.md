# Service-communication resilience examples describe code that does not exist

- **Severity:** Low (documentation accuracy, outside the security scope)
- **Owner:** orchestration (`docs/architecture/service-communication.md`)
- **Status:** Open
- **Source:** closeout open findings

## Problem

The "Resilience Patterns" section of
`docs/architecture/service-communication.md` presents a FRED
`@CircuitBreaker(name = "fred-api", fallbackMethod = "fallbackRates")`
example and `resilience4j` `retry` and `timelimiter` configuration as the
implementation. currency-service has no `@CircuitBreaker` and no resilience4j
dependency or configuration. The "Key Metrics to Monitor" list also names
circuit-breaker state.

What currency-service actually does: `FredClient` applies a per-request
timeout from `currency-service.exchange-rate-import.fred.timeout-seconds`, and
the scheduled import retries through its own
`currency-service.exchange-rate-import.retry` settings (`max-attempts`,
`delay-minutes`) in `application.yml`.

## Impact

Readers and agents take the example as the existing pattern and may expect a
fallback or circuit-breaker metrics that do not exist.

## Proposed fix

Describe the implemented timeout and scheduled-import retry, and link to the
currency-service configuration docs. Either remove the circuit-breaker example
or label it clearly as a pattern that is not implemented. Drop circuit-breaker
state from the metrics list unless one is added.

## Acceptance

- `docs/architecture/service-communication.md` claims no resilience mechanism
  that currency-service lacks.
