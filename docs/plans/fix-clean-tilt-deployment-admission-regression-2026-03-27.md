# Clean Tilt Deployment Admission Regression Plan

Date: 2026-03-27

## Goal

Make the supported clean-start flow reproducible:

1. delete existing local containers / cluster state
2. run `./setup.sh`
3. run `tilt up`
4. reach an all-green application deployment without manual cluster patching

This plan is scoped to fixing the repository so the failure does not recur on the
next clean rebuild.

## Current Findings

Cluster-side evidence from the current deployment:

- `kubectl get all -n default` shows only `Service` objects for the application
  workloads. There are no application `Deployment`, `ReplicaSet`, or `Pod`
  objects in `default`.
- `kubectl get events -n default --sort-by=.lastTimestamp` shows repeated
  `PolicyViolation` events from
  `clusterpolicy/phase7-require-third-party-image-digests`.
- The denials affect more than `nginx-gateway` and `ext-authz`. The same policy
  is blocking `transaction-service`, `currency-service`, and
  `permission-service` as well.
- A direct server-side dry run of the checked-in manifests succeeds:
  - `kubectl apply --dry-run=server -f kubernetes/services/ext-authz/deployment.yaml`
  - `kubectl apply --dry-run=server -f kubernetes/services/nginx-gateway/deployment.yaml`
- That means the checked-in manifests are not what Kyverno is rejecting at
  runtime. Something in the live apply path is changing the image references.

## Root Cause Hypothesis

The most likely root cause is a contract mismatch between Tilt and the Phase 7
Kyverno policy:

- The checked-in manifests use the seven approved local images as `:latest`.
- The Kyverno policy only allows those local images when they exactly match the
  hard-coded `:latest` regex.
- Tilt rewrites built image references to immutable deploy tags during apply.
- Kyverno therefore sees a Tilt-injected image ref instead of the checked-in
  `:latest` ref and denies the workload.

This hypothesis fits all current evidence:

- static/dry-run manifest admission passes
- live Tilt-created deployments are denied
- the failures are systemic across Tilt-built workloads, not isolated to one
  service

## Fix Strategy

### 1. Capture the exact Tilt-rendered image refs

Status: complete on March 27, 2026.

Captured from the failing host-side Tilt state via `tilt dump engine`:

- `ext-authz` -> `ext-authz:tilt-752304df648dc1e1`
- `nginx-gateway` init container `budget-analyzer-web-prod-smoke` ->
  `budget-analyzer-web-prod-smoke:tilt-d1622efb13cae97b`
- `transaction-service` -> `transaction-service:tilt-f3207b6e83858452`

Additional evidence from the same Tilt webview logs:

- Docker canonicalized the same local images while loading them into Kind as
  `docker.io/library/<repo>:tilt-<16 hex>`.

Conclusion:

- the live deploy pattern is `<approved-local-repo>:tilt-[0-9a-f]{16}`
- the existing Kyverno contract is too narrow because it only accepts literal
  checked-in `:latest` refs

## 2. Redefine the Phase 7 local-image contract

Status: complete on March 27, 2026.

Contract update landed in:

- `docs/plans/security-hardening-v2-phase-7-session-1-contract.md`
- `scripts/dev/lib/phase-7-allowed-latest.txt`
- `AGENTS.md`
- `docs/dependency-notifications.md`
- `docs/plans/security-hardening-v2.md`
- `scripts/README.md`

Contract outcome:

- keep the exception scope limited to the same seven local Tilt-built repos
- treat checked-in `:latest` refs as the manifest literals that static checks
  validate
- treat live Tilt deploy refs as immutable `:tilt-<16 hex>` tags for those same
  repos
- keep `imagePullPolicy: Never` as part of the local-image contract
- do not broaden the exception to arbitrary registries or arbitrary mutable tags

## 3. Fix the Kyverno policy to match the real deploy path

Update `kubernetes/kyverno/policies/50-require-third-party-image-digests.yaml`
so the allowlist matches both:

- the checked-in local manifest refs
- the actual Tilt-injected deploy refs for the same seven local images

The policy should still reject:

- any third-party image without `@sha256:`
- any non-approved local repo name
- approved local repos that do not satisfy the local pull-policy constraint

Special attention:

- cover both `containers` and `initContainers`
- keep the Istio sidecar exception behavior unchanged

## 4. Expand policy tests so this cannot regress silently

The current Kyverno fixture suite passes while real `tilt up` fails. That is a
gap in the test contract.

Update the Kyverno fixtures to include:

- a pass case that uses a real or representative Tilt-style tag for an approved
  local image
- a pass case for `budget-analyzer-web-prod-smoke` as an init container
- a fail case proving that an unapproved local image with a mutable tag is still
  denied

Files to update:

- `kubernetes/kyverno/tests/pass/workloads.yaml`
- `kubernetes/kyverno/tests/pass/kyverno-test.yaml`
- `kubernetes/kyverno/tests/fail/workloads.yaml`
- `kubernetes/kyverno/tests/fail/kyverno-test.yaml`

## 5. Close the static verification gap

Status: complete on March 27, 2026.

Implemented in:

- `scripts/dev/check-phase-7-image-pinning.sh`
- `scripts/dev/verify-phase-7-static-manifests.sh`
- `scripts/README.md`
- `README.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/ci-cd.md`
- `kubernetes/kyverno/README.md`

The static image-pinning checker currently validates only the checked-in refs.
That is still useful, but it does not prove that the deploy-time image mutation
remains compatible with the admission policy.

Add one of these guards:

- preferred: a lightweight verifier that renders or inspects Tilt deploy refs
  and checks them against the same approved-local-image contract
- acceptable fallback: a documented regression test that replays the captured
  Tilt tag pattern against the Kyverno CLI tests

Targets:

- `scripts/dev/check-phase-7-image-pinning.sh`
- `scripts/dev/verify-phase-7-static-manifests.sh`
- corresponding docs in `scripts/README.md` and development docs

## 6. Re-run the full clean-start proof

Status: automation landed on March 27, 2026; host-side rerun still required.

Implemented in:

- `scripts/dev/verify-clean-tilt-deployment-admission.sh`
- `README.md`
- `AGENTS.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`

After the repo fix lands, validate the exact user workflow:

1. remove existing local containers / cluster state on the host
2. run `./setup.sh`
3. run `tilt up`
4. confirm all app deployments in `default` are admitted and become Ready

Minimum Kubernetes checks:

- `kubectl get deploy -n default`
- `kubectl get pods -n default`
- `kubectl get events -n default --sort-by=.lastTimestamp | tail -n 100`

Success criteria:

- no Kyverno `PolicyViolation` events for approved local Tilt-built workloads
- `nginx-gateway` and `ext-authz` pods exist and become Ready
- the other Tilt-built application workloads are also admitted

## Risks And Constraints

- This environment can inspect the cluster through `kubectl`, but it does not
  currently expose the host-side Tilt API server or Docker runtime. The policy
  fix therefore must be validated against the host-side `tilt up` path, not
  only from inside this shell.
- Do not patch the live cluster to bypass Kyverno. That would hide the real
  contract failure and would not survive the next clean rebuild.
- Keep the exception narrow. The point is to align the policy with local
  development mechanics, not to weaken digest enforcement for third-party
  images.

## Recommended Execution Order

1. Capture the exact Tilt-rendered image refs from the host-side failure.
2. Update the Phase 7 contract doc.
3. Update the Kyverno policy.
4. Update the Kyverno fixtures and static verifier.
5. Re-run `./scripts/dev/verify-phase-7-static-manifests.sh`.
6. Re-run the full clean-start host workflow until `tilt up` is green.
