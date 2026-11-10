# Edge verifier counter checks are flaky under concurrent traffic

- **Severity:** Low
- **Owner:** orchestration
- **Status:** Open
- **Source:** [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  C5

## Problem

`scripts/smoketest/verify-edge-contract.sh` compares global counters before
and after a probe window:

- `rbac.denied` must rise by exactly the probe count (`:726`, `:1032`).
- The NGINX and Session Gateway sidecars must record no requests from the
  ingress (`:731`, `:736`, `:1037`, `:1042`, `:1315`).

`sidecar_requests_from_ingress` (`:620-634`) sums every `istio_requests_total`
series from the ingress workload. It filters only on the source workload, not on path or request. An open
SPA tab sending heartbeats or API calls during the window fails the run. So
does a sidecar restart that resets the counters.

## Assessment

- The NGINX sidecar equality checks are redundant where a marker-based NGINX
  log check follows (for example `:740`), and marker checks ignore concurrent
  traffic.
- `rbac.denied` exact equality is less fragile than the review implies. Normal
  browser traffic does not trigger semicolon or Origin denials, so it mainly
  breaks when two verifiers run at once. Keep it exact and rely on the
  verifier lock from the
  [fixture ownership issue](medium-edge-verifier-deletes-existing-loadtest-fixture.md)
  instead of relaxing it to "at least N".
- The Session Gateway counter check has no marker-based equivalent.

## Proposed fix

- Drop the NGINX sidecar equality checks wherever a marker check exists.
- Keep `rbac.denied` exact.
- For Session Gateway, either filter the counter by something the probes
  control, or state in the verifier header that the check needs a quiet stack.

## Acceptance

- An idle SPA tab open during the run does not fail the verifier.
- A probe that reaches NGINX still fails it.
