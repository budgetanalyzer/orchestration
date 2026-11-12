# ext_authz denial check parses YAML with grep and awk

- **Severity:** Low (maintenance)
- **Owner:** orchestration
- **Status:** Open
- **Source:** 2026-11-09 independent implementation review O2

## Problem

`scan_istio_ext_authz_denial_contract`
(`scripts/guardrails/verify-static-security-manifests.sh:1149-1235`) reads
`istiod-values.yaml` with `grep -Ec` and `awk` at fixed indentation, for
example `'^    - name:[[:space:]]*ext-authz-http[[:space:]]*$'`. The other
new Istio checks in the same script use PyYAML.

Re-indenting the values file or moving the provider block produces a
confusing failure even when the config is still correct.

## Proposed fix

Port the check to the PyYAML pattern used by the neighboring checks. It
should take about 30 lines.

## Acceptance

- The check passes on the current values.
- The existing fail fixtures still fail.
- Re-indenting the values file without changing semantics still passes.
