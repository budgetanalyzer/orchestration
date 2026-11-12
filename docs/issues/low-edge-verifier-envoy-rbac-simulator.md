# Edge verifier re-implements Envoy RBAC matching in Python

- **Severity:** Low (maintenance)
- **Owner:** orchestration
- **Status:** Open
- **Source:** 2026-11-09 independent implementation review O1

## Problem

`ingress_origin_config_problem`
(`scripts/smoketest/verify-edge-contract.sh:800-933`, about 130 lines) parses
the live config dump and re-evaluates the exact-Origin RBAC policy with a
hand-written model of Envoy's string and header matching. It checks a fixed
set of must-deny and must-allow vectors and reports `unmodelled matcher`
(`:927`) for anything it does not understand.

The same section then sends the same Origin cases to the real Envoy. The
simulator proves nothing the live probes do not, and after an Envoy upgrade it
is the code most likely to disagree with Envoy.

## Proposed fix

Replace the simulator with a structural check: the exact-Origin policy is
present on every ingress pod. Rely on the live probes for behavior.

## Acceptance

- The live Origin probes still pass on a correct stack and fail when the
  exact-Origin policy is removed.
- The embedded matcher model is deleted.
