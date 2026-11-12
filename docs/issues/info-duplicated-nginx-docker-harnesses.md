# Two NGINX Docker test harnesses duplicate setup code

- **Severity:** Info (maintenance)
- **Owner:** orchestration
- **Status:** Leave unless either script is otherwise being changed
- **Source:** 2026-11-09 independent implementation review O5

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
