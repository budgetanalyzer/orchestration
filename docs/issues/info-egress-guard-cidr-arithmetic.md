# Egress guard uses CIDR set arithmetic

- **Severity:** Info (maintenance judgment call)
- **Owner:** orchestration
- **Status:** Leave unless the check is otherwise being changed
- **Source:** 2026-11-09 independent implementation review O3

## Observation

The egress check in `scripts/guardrails/verify-static-security-manifests.sh`
(about `:1909-2078`, with `uncovered_private` and `check_external_policy`)
computes whether any combination of additive NetworkPolicies re-allows
private ranges. It is correct, but about three times larger than the rule it
enforces.

The review proposes a simpler invariant: in `istio-egress`, only the named
external policy may carry egress `ipBlock` rules, and its `except` list must
match exactly.

## Assessment

The proposed rule alone is weaker than the current check. A rule with no
destination (`egress: [{}]`, or ports without `to`) has no `ipBlock` and
allows everything. The current code handles missing and named ports
explicitly.

A simplified version would also have to fail any egress rule without a `to`
in that namespace. With that addition, the simplification is reasonable, but
it isn't worth doing on its own.
