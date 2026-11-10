# Exact-inventory assertions in the edge and static verifiers

- **Severity:** Low
- **Owner:** orchestration
- **Status:** Open, partly disputed
- **Source:** [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  C6

## Problem as reported

- **Live:** `scripts/smoketest/verify-edge-contract.sh:605-613` requires the
  enforcing RBAC filters to be exactly `{path-hardening,
  envoy.filters.http.rbac}`, and Istio's RBAC filter to carry only the
  exact-Origin policy. Any new ingress `AuthorizationPolicy`, even an
  unrelated `DENY`, fails the semicolon section with a message that blames
  path hardening.
- **Static:** `scripts/guardrails/verify-static-security-manifests.sh:1691`
  requires the path-hardening `typed_config` keys to be exactly
  `{"@type", "rules"}`. The exact-Origin scan (`:1768-1907`) also pins exact
  key sets.

The review recommends asserting properties instead (filter present, ahead of
`ext_authz`, denies and allows the right vectors).

## Assessment

- **Static side: keep the exact key set.** The static suite cannot send
  requests, so an exact key set is its stand-in for "this filter still
  enforces." The in-code comment at `:1692-1693` shows the review's
  "harmless" examples are not harmless:
  `shadow_rules` do not enforce, and a `stat_prefix` hides denials from the
  gateway stats matcher, which exports only `*rbac.denied`.
- **Live side: the inventory check is redundant, and its message misleads.** Live probes already prove
  behavior. An unrelated new ingress policy should not fail with a
  path-hardening message.

## Proposed fix

- Leave the static exact-key checks as they are.
- On the live side, keep "path-hardening present and ahead of `ext_authz`" and
  the behavioral probes. Either drop the exact-filter-list requirement, or
  keep it and report "unexpected additional ingress RBAC policy: <name>"
  instead of blaming path hardening.

## Acceptance

- Adding an unrelated ingress `DENY` policy produces an accurate message, or
  no failure.
- Removing path hardening, or moving it after `ext_authz`, still fails.
