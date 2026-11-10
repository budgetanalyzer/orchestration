# Two NGINX Docker test harnesses duplicate setup code

- **Severity:** Info (maintenance)
- **Owner:** orchestration
- **Status:** Leave unless either script is otherwise being changed
- **Source:** [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  O5

## Observation

`scripts/guardrails/verify-nginx-backend-headers.sh` (256 lines) and
`scripts/guardrails/verify-nginx-shared-routes.sh` (259 lines) each have their
own image selection, network-less container start, cleanup trap and pass/fail
reporting.

Both tests are justified. In particular, NGINX-layer `;` rejection cannot be
observed live because the ingress rejects first.

## Assessment

Move the shared container lifecycle into `scripts/lib/` the next time either
script changes. Merging them now is churn without a defect behind it.
