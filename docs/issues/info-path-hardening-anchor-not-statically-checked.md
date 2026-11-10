# Path-hardening filter silently depends on the ext_authz anchor

- **Severity:** Info
- **Owner:** orchestration
- **Status:** Candidate for acceptance
- **Source:** [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  C8

## Observation

`kubernetes/istio/ingress-path-hardening.yaml` inserts its filter before
`envoy.filters.http.ext_authz`. If that filter is ever absent, the patch
silently does not apply.

The live edge verifier catches this (it requires path hardening ahead of
`ext_authz`). The static suite does not.

## Assessment

Acceptable as is. Losing `ext_authz` is the larger failure and would be
noticed first. No change is proposed unless the static suite gains a cheap way
to assert the anchor.
