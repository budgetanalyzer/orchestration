# Security Hardening v2 - Phase 2 Review Fix Plan

## Goal

Fix the issues found in the post-implementation review of Phase 2 so the runtime proof is repeatable, the operator docs match the deployed objects, and the architecture docs describe the actual enforcement boundary precisely.

This follow-up is complete when:

1. `./scripts/dev/verify-phase-2-network-policies.sh` passes repeatedly on a healthy cluster without false negatives.
2. Every explicit Phase 2 non-edge called out in the implementation plan is covered by the verifier.
3. The troubleshooting commands in the docs work as written against the live cluster.
4. The architecture docs describe the real Phase 2 posture, including the host-to-pod exception under Calico's default behavior.
5. The existing Phase 2 implementation plan no longer overstates Session 5 completion.

## Review Findings To Fix

### 1. Phase 2 verifier is not deterministic

Observed on March 22, 2026:

- `./scripts/dev/verify-phase-2-network-policies.sh` failed twice against a healthy live cluster.
- The failures were not stable:
  - run 1 failed `nginx-gateway -> currency-service:8084`
  - run 2 failed `envoy -> nginx-gateway:8080`, `nginx-gateway -> transaction-service:8082`, and `nginx-gateway -> currency-service:8084`
- Manual retests from matching probe pods and from the real `nginx` container succeeded, so the script is producing false negatives.

Impact:

- Session 5's "repeatable runtime proof" criterion is not met.
- Current docs imply a stronger verification story than the repo actually has.

### 2. Troubleshooting docs reference objects that do not exist

Observed on March 22, 2026:

- `kubectl get networkpolicy -n default -l purpose=dns-egress` returned no resources.
- `kubectl get networkpolicy allow-istiod-egress -n default -o yaml` returned `NotFound`.

Current live object names:

- `allow-default-dns-egress`
- `allow-default-istiod-egress`

Impact:

- Operators following the runbook will get misleading results while debugging real outages.

### 3. Verifier misses two explicit blocked edges from the Phase 2 contract

The implementation plan explicitly says these paths must stay blocked:

- `session-gateway` -> `nginx-gateway:8080`
- `ext-authz:8090`

Current verifier coverage does not test either path.

Observed on March 22, 2026:

- Manual probe confirmed `session-gateway` -> `nginx-gateway:8080` is blocked.
- Manual probe confirmed Envoy-labeled probe -> `ext-authz:8090` is blocked.

Impact:

- A future policy regression on either edge would not be caught by the official Phase 2 proof.

### 4. Architecture docs overstate the NetworkPolicy boundary

The current architecture docs say only documented callers can reach protected services, but the runbook correctly notes that kubelet probes and Tilt port-forwards are host-to-pod traffic and rely on Calico's default host endpoint handling.

Impact:

- The docs currently mix the pod-to-pod enforcement story with a stronger claim than the platform actually guarantees.

### 5. Phase 2 plan status needs correction

The implementation breakdown currently says Session 5 is complete in authoring scope, but the live review disproved the repeatability claim.

Impact:

- The plan no longer reflects actual repository state.

## Scope And Constraints

- Write scope stays in this repo.
- Keep the verifier focused on Phase 2 `NetworkPolicy` behavior, not full Istio end-to-end authorization.
- Do not widen policies to make the verifier pass.
- Validate fixes against the live cluster, not just with static review.
- Update docs in the same work as code/script changes.

## Files To Update

Required:

- `scripts/dev/verify-phase-2-network-policies.sh`
- `docs/runbooks/tilt-debugging.md`
- `docs/architecture/port-reference.md`
- `docs/architecture/security-architecture.md`
- `docs/plans/security-hardening-v2-phase-2-implementation.md`

Likely:

- `scripts/README.md`

Optional if wording needs adjustment after implementation:

- `docs/development/getting-started.md`
- `docs/development/local-environment.md`

## Session Breakdown

### Session 1: Stabilize The Verifier

Goal:

- Eliminate false negatives so the Phase 2 verifier is trustworthy.

Tasks:

1. Reproduce the current false negatives in the live cluster and isolate the unstable part of the script:
   - current single-shot positive assertions
   - current TCP probe primitive
   - immediate post-`Ready` execution timing
2. Replace the current "one attempt and fail" logic with explicit stability semantics:
   - allowed paths should pass within a bounded retry window
   - denied paths should fail consistently across repeated attempts
3. Keep the probe honest:
   - do not weaken negative assertions
   - do not change policies to fit probe behavior
4. If BusyBox `nc` is still unstable after adding retry/warmup logic, switch to a different probe strategy rather than accepting flaky results.
   - acceptable outcomes:
     - keep BusyBox and use a proven stable command pattern
     - keep BusyBox but add a stronger readiness/warmup phase
     - change the verifier image/tool if BusyBox cannot produce repeatable results in this cluster
5. Improve failure output so a failed assertion shows enough detail to debug quickly.

Recommended implementation direction:

- Split the current helpers into "allow eventually" and "deny consistently" semantics instead of treating both as single-shot checks.
- Add a short stabilization period after probe pod readiness before the first positive checks run.
- Require multiple consecutive clean runs before calling the verifier fixed.

Done when:

- The verifier passes repeatedly on the same healthy cluster without varying failures.

### Session 2: Close Verifier Coverage Gaps

Goal:

- Ensure every explicit blocked edge in the Phase 2 contract is exercised by the official verifier.

Tasks:

1. Add a negative test for `session-gateway` -> `nginx-gateway:8080`.
2. Add a negative test for Envoy-labeled probe -> `ext-authz:8090`.
3. Re-read the explicit Phase 2 non-edge list and confirm every listed blocked path has a matching verifier assertion.
4. Update any inline comments, test counts, or summary text that changed after coverage is expanded.

Done when:

- The verifier would fail if either blocked edge is accidentally reopened in the future.

### Session 3: Fix Runbook Commands And Re-Verify Them Live

Goal:

- Make the troubleshooting docs operational instead of approximate.

Tasks:

1. Replace nonexistent label/name references with the real object names or robust commands:
   - DNS policy lookup must match `allow-default-dns-egress`
   - istiod policy lookup must match `allow-default-istiod-egress`
2. Re-run every command in the new Phase 2 troubleshooting section against the live cluster.
3. Prefer explicit namespace flags in commands where that removes ambiguity.
4. Keep the troubleshooting guidance aligned with the actual policy manifests, not a hypothetical naming scheme.

Done when:

- Every command in the Phase 2 troubleshooting section succeeds or returns the intended diagnostic signal on the live cluster.

### Session 4: Correct The Architecture Narrative

Goal:

- Make the architecture docs precise about what Phase 2 does and does not enforce.

Tasks:

1. Update `docs/architecture/port-reference.md` to state clearly that the Phase 2 caller matrix applies to pod-to-pod traffic.
2. Add the Calico host-to-pod exception where it materially changes the interpretation:
   - kubelet probes
   - Tilt port-forwards
3. Update `docs/architecture/security-architecture.md` so the summary of Phase 2 enforcement is accurate without overstating the boundary.
4. Keep the Phase 3 hostname-aware egress limitation language intact.

Done when:

- The architecture docs and runbook tell the same story about Phase 2 enforcement scope.

### Session 5: Correct The Existing Phase 2 Plan Status

Goal:

- Bring the existing implementation breakdown back in sync with reality.

Tasks:

1. Update `docs/plans/security-hardening-v2-phase-2-implementation.md` to reflect that Session 5 is not complete until the verifier is repeatable.
2. Record the review findings that triggered this follow-up:
   - verifier false negatives
   - runbook object-name mistakes
   - missing negative coverage
3. Update the completion text only after the verifier and docs are fixed and re-validated.

Done when:

- The implementation breakdown no longer claims completion ahead of the actual repo state.

## Verification

Minimum verification after implementation:

```bash
bash -n scripts/dev/verify-phase-2-network-policies.sh
./scripts/dev/verify-phase-2-network-policies.sh
./scripts/dev/verify-phase-2-network-policies.sh
./scripts/dev/verify-phase-2-network-policies.sh
kubectl get networkpolicy allow-default-dns-egress -n default
kubectl get networkpolicy allow-default-istiod-egress -n default
```

Additional verification:

- Re-run the commands in the Phase 2 troubleshooting section exactly as documented.
- Confirm the verifier now includes negative checks for:
  - `session-gateway` -> `nginx-gateway:8080`
  - Envoy-labeled probe -> `ext-authz:8090`

## Risks To Watch

1. Do not "fix" flakiness by loosening expectations so much that real regressions slip through.
2. Do not widen network policies to satisfy the verifier.
3. Keep the verifier's scope narrow: it should prove Phase 2 `NetworkPolicy`, not become a mixed Istio + app-health test suite.
4. If the verifier depends on a more stable probe tool than BusyBox provides, document that tradeoff explicitly rather than hiding it.

## Definition Of Done

This follow-up is done when all of the following are true:

1. The Phase 2 verifier passes multiple consecutive runs on a healthy cluster.
2. The verifier covers the explicit `session-gateway` -> `nginx-gateway:8080` and `ext-authz:8090` blocked edges.
3. The Phase 2 troubleshooting commands in the runbook match live object names and work as written.
4. The architecture docs explicitly distinguish pod-to-pod enforcement from the Calico host-to-pod exception.
5. The existing Phase 2 implementation breakdown reflects the corrected status of Session 5.
