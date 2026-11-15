# Static mesh guard misses additive ALLOW policies and Session Gateway

- **Severity:** Medium
- **Owner:** orchestration
- **Status:** Closed 2026-11-15 by static checks; see [Resolution](#resolution)
- **Source:** 2026-11-09 implementation review F4; independent implementation review C2
- **Plan:** [Close Additive ALLOW Gaps in the Static Mesh Guard](../plans/static-mesh-additive-allow-guard-plan.md)

## Problem

`scan_istio_authorization_policy_contract`
(`scripts/guardrails/verify-static-security-manifests.sh:1241-1351`) checks
only two things:

1. `default/default-deny-all` exists and has an empty spec.
2. Rules that admit the nginx-gateway principal on the hardcoded
   `BACKEND_APPS` (`:1252`: transaction, currency and permission services)
   restrict paths.

These cases pass the check without being examined:

- selectorless or namespace-wide `ALLOW` policies (`app` is `None`, so the
  rule is skipped);
- `ALLOW` rules with no `from`, or with principals other than nginx-gateway;
- the Session Gateway, ext-authz and nginx-gateway policies, including the
  ingress-to-auth-lane path restriction;
- any new backend service.

Istio `ALLOW` policies are additive. An empty deny-all baseline does not stop
a later broad `ALLOW`.

## Evidence

The 2026-11-09 implementation review extracted the `AUTHZ_PY` checker body
and ran it with the repository PyYAML venv against temporary copies of the
policy documents. The full static suite was not run:

| Input | Exit |
| --- | --- |
| Unmodified policy set | `0` |
| Plus `default` namespace `ALLOW`, no selector, `rules: [{}]` | `0` |
| `to` removed from the ingress rule of `session-gateway-policy` | `0` |

This shows a verification gap. The checked-in policies themselves do not
currently grant this access.

## Proposed fix

Extend the existing Python block. Do not build an Istio policy simulator.

- Fail on any `ALLOW` policy in a mesh namespace, other than
  `default-deny-all`, that has no selector.
- Fail on any rule on a protected workload that lacks `from.source.principals`.
- Require `to.operation.paths` on Session Gateway's ingress rule and on the
  internal permission-service caller rules.
- Replace the hardcoded `BACKEND_APPS`. Deriving it from `kubernetes/services/`
  needs an explicit marker or exclusion, because not every service there is an
  NGINX backend.
- Make the documented scope of the check match what it checks.
- If the block grows, move it into a focused Python file that its fail
  fixtures can invoke directly (implementation review O2).

## Acceptance

- Both mutations above are fail fixtures and fail.
- The unmodified policy set passes.

## Resolution

The guard now lives in
[`scripts/guardrails/verify-mesh-authorization.py`](../../scripts/guardrails/verify-mesh-authorization.py).
[`scripts/guardrails/verify-static-security-manifests.sh`](../../scripts/guardrails/verify-static-security-manifests.sh)
runs it on two separate sets. The first is every local `AuthorizationPolicy`
under `kubernetes/`, with workloads from `kubernetes/services/`. The second is
the rendered production reference: the `kubernetes/production/istio`,
`istio-ingress-policies` and `apps` overlays, run with
`--environment production`. In that set only the standalone
`budget-analyzer-web` workload and policy may be absent. Scope, the caller
table and limits live in
[Static Contract Guard](../architecture/security-architecture.md#static-contract-guard).

The proposed blanket ban on selectorless `ALLOW` policies was not adopted
because it would reject the existing Envoy metrics grant. Instead, the
selectorless `default/envoy-metrics-prometheus-policy` is accepted only when
its spec equals exactly
`{"action": "ALLOW", "rules": [{"from": [{"source": {"principals": ["cluster.local/ns/monitoring/sa/prometheus-stack-kube-prom-prometheus"]}}], "to": [{"operation": {"ports": ["15090"]}}]}]}`.
The policy name exempts nothing. Every other selectorless or empty-selector
`ALLOW` fails.

Acceptance evidence, which is fixture and static evidence only:

- [`tests/security-guardrails/test-mesh-authorization.py`](../../tests/security-guardrails/test-mesh-authorization.py)
  first proves that the unmodified local policy set and the unmodified
  production render pass. It then requires both mutations above to fail with
  specific diagnostics, locally and in the production render:
  - "is a broad additive grant over namespace default"
  - "ingress -> session-gateway auth surface: has no to restriction"

  It also covers broad grants that a production-only overlay adds, a
  broadened metrics exception, and missing workloads or policies.
- The `authorization-policy-*` fail fixtures under
  `tests/security-guardrails/fixtures/fail/` run through the same helper.
- On 2026-11-15, the focused runner, `--self-test`, the full static suite,
  `bash -n` and `shellcheck` passed with the pinned PyYAML interpreter.

No live cluster was exercised for this change, and no hosted production
environment exists. The live mesh boundary proof remains
`scripts/smoketest/verify-edge-contract.sh` on local Tilt.
