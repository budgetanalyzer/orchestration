# Phase 3: Istio Ingress/Egress No-Shim Correctness Plan

## Context

The current Phase 3 branch should not be treated as complete just because the pods went green. The latest review found that some of the recent changes are real fixes, while others only moved the failure boundary:

- `ReferenceGrant` needed `gateway.networking.k8s.io/v1beta1` and that correction is valid
- stale Envoy-era ingress `NetworkPolicy` objects needed explicit deletion and that correction is valid
- the ingress NodePort patch had to target the actual rendered Service name and HTTPS port index, and that correction is valid
- the egress gateway selector had to match the rendered egress-gateway labels, and that correction is valid
- the original egress gateway Helm install depended on `--skip-schema-validation`, which was not acceptable as the final state
- the Istio ingress gateway selectors used in `AuthorizationPolicy` and `NetworkPolicy` do not match the live gateway pod labels
- the ingress-facing SPIFFE principals do not match the live ingress gateway ServiceAccount
- the current egress `DestinationRule` change to `tls.mode: DISABLE` restores connectivity, but it changes the security story and must be justified against the actual Istio egress pattern instead of being accepted because traffic flows
- the verifier still overclaims what it proves, and auth-path ingress throttling still needs to be treated as required behavior, not optional polish

This plan is the work required to finish Phase 3 correctly, without shims, and with documentation that matches the real security posture.

**Hard rule:** pod readiness is not a completion signal for Phase 3. The completion signal is verified policy attachment plus verified runtime behavior.

---

## Goals

1. Phase 3 applies cleanly on a fresh cluster and on an existing cluster without `--skip-schema-validation`.
2. All ingress selectors and SPIFFE principals match the rendered Istio gateway resources exactly.
3. Application egress is constrained to the actual egress gateway workload, not just an entire namespace.
4. The final egress TLS mode is chosen from a documented Istio pattern and justified by evidence, not by trial-and-error.
5. `scripts/dev/verify-phase-3-istio-ingress.sh` becomes the honest completion gate for Phase 3.
6. Setup docs and prerequisite checks describe and enforce the real supported Helm toolchain.
7. Phase 3 documentation stops claiming protections that are not actually implemented or proven.

---

## Non-Goals

- No sibling service code changes.
- No new domain features.
- No user/data ownership work.
- No permanent “just for local dev” exceptions that weaken the stated Phase 3 security model.

---

## Preserve These Fixes

These changes should stay unless later evidence proves they are wrong:

- `kubernetes/istio/tls-reference-grant.yaml` uses `gateway.networking.k8s.io/v1beta1`
- `Tiltfile` deletes renamed Envoy-era ingress `NetworkPolicy` objects before applying the new set
- `Tiltfile` patches `istio-ingress-gateway-istio` at `/spec/ports/1/nodePort`
- `kubernetes/istio/egress-routing.yaml` uses `istio: egress-gateway`
- `kubernetes/network-policies/istio-egress-allow.yaml` selects the rendered egress-gateway labels

These are implementation corrections, not temporary hacks.

---

## Required Corrections

### 1. Remove the Helm schema-validation bypass

**Problem**

`Tiltfile` previously installed the egress gateway with `--skip-schema-validation`. That was a tooling bypass, not a correct final state.

**Files to modify**

- `Tiltfile`
- `scripts/dev/check-tilt-prerequisites.sh`
- `docs/development/local-environment.md`
- `docs/tilt-kind-setup-guide.md`
- `docs/development/devcontainer-installed-software.md`
- any other doc that states the supported Helm version loosely or incorrectly

**Required work**

- Reproduce the `istio/gateway` chart failure against explicit Helm versions instead of assuming the current host version is acceptable.
- Choose a supported, documented install path that does not use `--skip-schema-validation`.
- Preferred path: pin Helm to a tested version that installs `istio/gateway` `1.24.3` cleanly, then enforce that version or version range in prerequisites and docs.
- Rejected path: keep `--skip-schema-validation` in steady-state Tilt resources.
- If no acceptable Helm 3 version installs the chart cleanly, stop using the chart path for the egress gateway and replace it with a checked-in manifest path whose provenance is documented.

**Implementation note**

- Helm `v3.20.1` reproduces the chart-schema failure for the required `service.type=ClusterIP` override, so Session 1 adopts the checked-in manifest fallback.

**Validation**

- no steady-state Tilt resource uses `--skip-schema-validation`
- `kubernetes/istio/egress-gateway.yaml` exists with documented provenance from `istio/gateway` `1.24.3`
- `./scripts/dev/check-tilt-prerequisites.sh` rejects unsupported Helm versions
- setup docs and installed-software docs agree on the actual supported Helm version

### 2. Fix ingress gateway selectors everywhere they are currently wrong

**Problem**

The live ingress gateway pod is labeled with `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway`, but Phase 3 manifests currently target `istio.io/gateway-name=istio-ingress-gateway`. That means the intended policies are not attached to the live gateway pod.

**Files to modify**

- `kubernetes/istio/ext-authz-policy.yaml`
- `kubernetes/network-policies/istio-ingress-allow.yaml`
- `kubernetes/network-policies/default-allow.yaml`
- `docs/plans/security-hardening-v2-phase-3-implementation.md`
- verifier and runbook docs that refer to the old label

**Required work**

- Replace the incorrect ingress selector key with the rendered key actually used by the Istio Gateway API controller.
- Verify every policy that references the ingress gateway uses the same selector basis.
- Re-check the ingress `NetworkPolicy` external port against the live Service target port. The current live Service targets `443`, so the hard-coded `8443` must be treated as suspect until proven.

**Validation**

- `kubectl get pods -n istio-ingress --show-labels`
- `kubectl get svc -n istio-ingress -o yaml`
- policy manifests select the live pod labels exactly
- external traffic and gateway-to-service traffic continue to work after the selector correction

### 3. Fix ingress-facing SPIFFE principals

**Problem**

The ingress-facing `AuthorizationPolicy` resources currently allow `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway`, but the live ingress gateway runs as ServiceAccount `istio-ingress-gateway-istio`.

**Files to modify**

- `kubernetes/istio/authorization-policies.yaml`
- `docs/plans/security-hardening-v2-phase-3-implementation.md`
- verifier logic that checks ingress identity policy behavior

**Required work**

- Update the ingress-facing policies for `nginx-gateway`, `ext-authz`, and `session-gateway` to the actual ingress gateway ServiceAccount.
- Treat the rendered ServiceAccount name as an implementation fact that must be verified during rollout, not guessed from the Gateway name.

**Validation**

- `kubectl get deploy,sa -n istio-ingress -o yaml`
- wrong-identity probe is denied at HTTP level
- real ingress traffic is still allowed through the expected identity

### 4. Tighten application-to-egress `NetworkPolicy`

**Problem**

`allow-session-gateway-egress` and `allow-currency-service-egress` currently allow port `443` to the entire `istio-egress` namespace. That is broader than necessary.

**Files to modify**

- `kubernetes/network-policies/default-allow.yaml`
- verifier checks covering application egress scope

**Required work**

- Narrow session-gateway and currency-service egress to `istio-egress` namespace plus the rendered egress gateway pod labels.
- Keep the policy aligned with the actual Helm-rendered labels instead of assuming a name.

**Validation**

- `kubectl get pods -n istio-egress --show-labels`
- login still works through Auth0
- allowed FRED calls still work
- arbitrary egress remains blocked under `REGISTRY_ONLY`

### 5. Decide the final egress TLS mode by evidence, not convenience

**Problem**

Changing the egress `DestinationRule` to `tls.mode: DISABLE` may be the right fit for the chosen PASSTHROUGH pattern, or it may be masking a misconfiguration. It must be decided against the documented Istio model, not against pod health.

**Files to modify**

- `kubernetes/istio/egress-routing.yaml`
- `docs/plans/security-hardening-v2-phase-3-implementation.md`
- `docs/architecture/security-architecture.md`
- verifier logic and troubleshooting docs that describe the egress path

**Required work**

- Reproduce and document the failure mode with `ISTIO_MUTUAL`.
- Compare the current configuration against the official Istio HTTPS-through-egress-gateway pattern.
- Choose one final state:
  - restore mesh mTLS on the workload-to-egress hop if a documented, working pattern exists for this topology
  - or keep `DISABLE` only if the documented PASSTHROUGH pattern requires the original TLS stream to reach the egress gateway unchanged
- If `DISABLE` remains, document the exact security consequence precisely: external TLS remains end-to-end, but the hop from workload sidecar to egress gateway is not additionally wrapped in mesh mTLS.

**Validation**

- login flow works end to end
- FRED API access works through the egress gateway
- an unregistered external host still fails under `REGISTRY_ONLY`
- the chosen TLS mode is explained consistently in manifests, verifier output, and docs

### 6. Keep the manifest-level and migration corrections honest

**Problem**

Two earlier corrections are required for correctness but still need to remain part of the final validation story:

- `ReferenceGrant` must stay on `v1beta1`
- stale Envoy-era ingress policies must be removed during upgrades from older clusters

**Files to verify or modify**

- `kubernetes/istio/tls-reference-grant.yaml`
- `Tiltfile`
- migration and setup docs

**Required work**

- Keep the `ReferenceGrant` correction in place.
- Keep the explicit delete of renamed Envoy-era policies in place.
- Include both checks in the completion gate so they are not re-broken later.

**Validation**

- `kubectl apply --dry-run=server -f kubernetes/istio/tls-reference-grant.yaml`
- live cluster migration leaves only the Istio-era ingress policies in `default`

### 7. Make the verifier prove behavior, not just configuration

**Problem**

The current verifier still has brittle preflight logic and several checks that only prove configuration exists, not that the protections actually work.

**Files to modify**

- `scripts/dev/verify-phase-3-istio-ingress.sh`
- possibly `nginx/nginx.k8s.conf` if forwarded-header detail is still insufficient

**Required work**

- Replace brittle preflight and cleanup logic.
- Check named required resources instead of relying on exact counts.
- Upgrade mTLS and ingress-identity tests to HTTP-level proofs.
- Add an end-to-end header-sanitization proof using a seeded session and a temporary echo backend.
- Verify the forwarded client identity chain directly from controlled requests and logs.

**Validation**

- `bash -n scripts/dev/verify-phase-3-istio-ingress.sh`
- full run of the verifier succeeds on the corrected Phase 3 deployment

### 8. Treat auth-path ingress throttling as a required Phase 3 control

**Problem**

`/login`, `/auth/*`, `/oauth2/*`, `/logout`, and `/user` bypass NGINX. Phase 3 is incomplete until ingress-layer throttling for those paths is real and verified.

**Files to modify**

- `kubernetes/istio/ingress-rate-limit.yaml`
- `Tiltfile`
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- relevant architecture and operations docs

**Required work**

- Keep ingress-layer auth throttling in Phase 3 scope.
- Verify `429` behavior for `/login` and at least one routed auth path.
- Remove any warning-only fallback in the verifier.

**Validation**

- repeated auth-path requests are throttled at ingress
- verifier treats missing throttling as a hard failure

### 9. Align the docs and prerequisite story with the real implementation

**Problem**

The docs currently mix stale claims, loose Helm requirements, and implementation details that no longer match the live rendered resources.

**Files to modify**

- `docs/plans/security-hardening-v2-phase-3-implementation.md`
- `docs/plans/security-hardening-v2.md`
- `README.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/bff-api-gateway-pattern.md`
- `docs/architecture/port-reference.md`
- `docs/development/local-environment.md`
- `docs/development/devcontainer-installed-software.md`
- `docs/tilt-kind-setup-guide.md`
- `docs/runbooks/tilt-debugging.md`
- `nginx/README.md`

**Required work**

- Remove any claim that Phase 3 is complete before the corrected verifier passes.
- Document the real supported Helm version and installation path.
- Distinguish NGINX API-path throttling from Istio ingress auth-path throttling.
- Describe the real ingress label key and ingress gateway ServiceAccount that policies depend on.
- Document the final egress TLS choice precisely.

---

## Execution Order

### Session 1: Toolchain and install-path correction

1. Reproduce the `istio/gateway` schema failure against explicit Helm versions.
2. Pick the no-shim install path.
3. Remove `--skip-schema-validation`.
4. Enforce the supported Helm version in prerequisites and setup docs.

### Session 2: Ingress policy attachment correction

1. Fix all ingress gateway selectors.
2. Re-verify the correct external ingress port in `NetworkPolicy`.
3. Fix ingress-facing SPIFFE principals.
4. Prove the corrected policies attach to the live ingress gateway resources.

### Session 3: Egress least-privilege correction

1. Tighten application egress policies to the actual egress gateway pod.
2. Reproduce the `ISTIO_MUTUAL` failure mode.
3. Decide the final egress TLS mode from the documented Istio pattern.
4. Update manifests and docs to match that final decision.

### Session 4: Verifier hardening

1. Remove brittle preflight and cleanup behavior.
2. Replace exact-count checks with named-resource checks.
3. Upgrade mTLS, ingress identity, header sanitization, and forwarded-header checks to runtime proofs.

### Session 5: Auth-path throttling completion

1. Finish ingress auth-path rate limiting.
2. Make the verifier treat throttling as mandatory.

### Session 6: Documentation closure

1. Update architecture, setup, runbook, and plan docs.
2. Mark Phase 3 complete only after all validations pass.

**Closure note**

The repo docs now need to describe the final Helm `3.20.x` plus checked-in egress-manifest path, the split between Istio ingress auth-path throttling and NGINX backend/API throttling, the rendered ingress selector `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway`, the ingress principal `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`, and the final egress choice of `tls.mode: DISABLE` for the `PASSTHROUGH` pattern. This session does not by itself declare Phase 3 complete; completion remains blocked on the validation checklist below.

---

## Success Criteria

Phase 3 is complete only when all of the following are true:

- no Tilt resource or documented steady-state command uses `--skip-schema-validation`
- the supported Helm version is documented and enforced
- ingress `NetworkPolicy` and `AuthorizationPolicy` selectors match the live ingress gateway labels
- ingress-facing `AuthorizationPolicy` principals match the live ingress gateway ServiceAccount
- application egress targets the actual egress gateway workload, not just the namespace
- the final egress TLS mode is justified by a documented Istio pattern and verified behavior
- `scripts/dev/verify-phase-3-istio-ingress.sh` passes and proves the intended controls at runtime
- the docs describe the real behavior instead of the intended-but-unimplemented behavior

---

## Validation Checklist

- `bash -n scripts/dev/verify-phase-3-istio-ingress.sh`
- `kubectl apply --dry-run=server` for:
  - ingress manifests
  - egress manifests
  - network policies
  - ingress throttling manifests
- `kubectl get pods -n istio-ingress --show-labels`
- `kubectl get deploy,sa -n istio-ingress -o yaml`
- `kubectl get svc -n istio-ingress -o yaml`
- `kubectl get pods -n istio-egress --show-labels`
- live cluster check that old `allow-*-from-envoy` policies are removed
- fresh-cluster and existing-cluster `tilt up` both succeed
- full run of `./scripts/dev/verify-phase-3-istio-ingress.sh`

---

## Expected File Inventory

**Must modify**

- `Tiltfile`
- `scripts/dev/check-tilt-prerequisites.sh`
- `kubernetes/istio/ext-authz-policy.yaml`
- `kubernetes/istio/authorization-policies.yaml`
- `kubernetes/istio/egress-routing.yaml`
- `kubernetes/network-policies/istio-ingress-allow.yaml`
- `kubernetes/network-policies/default-allow.yaml`
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- the documentation files listed above

**Must keep correct**

- `kubernetes/istio/tls-reference-grant.yaml`

**Likely new or expanded**

- ingress rate-limiting manifest details under `kubernetes/istio/`
- verifier helper resources for header-sanitization proof

**May need modification depending on verifier implementation**

- `nginx/nginx.k8s.conf`
