# Split Local And Production Kyverno Image Policy Plan

Date: 2026-03-27

## Goal

Remove the theoretical production hole in the Phase 7 image-admission policy by
separating the local Tilt-only image exceptions from the production-safe
default posture.

After this work:

1. local `tilt up` still admits the seven approved local app images
2. the repo contains an explicit production-safe policy variant that rejects
   local `:latest` and `:tilt-<hash>` refs
3. the local and production policy contracts are both tested so this does not
   regress silently

## Non-Goals

- Do not define the full production deployment pipeline for the seven app
  images. That remains a separate concern.
- Do not add a production installer/bootstrap path in this change.
- Do not broaden any image exceptions beyond the existing seven local app repos.

## Current State

- The current local cluster installs Kyverno only through the local
  [`Tiltfile`](/workspace/orchestration/Tiltfile).
- The current image policy file
  [`kubernetes/kyverno/policies/50-require-third-party-image-digests.yaml`](/workspace/orchestration/kubernetes/kyverno/policies/50-require-third-party-image-digests.yaml)
  now allows:
  - checked-in approved local `:latest` refs with `imagePullPolicy: Never`
  - approved local `:tilt-<hash>` refs with `imagePullPolicy: IfNotPresent` or
    `Never`
- That is correct for local Tilt, because Tilt rewrites managed local-image
  workloads before apply.
- That same checked-in file is not production-safe. If someone later reused it
  in production unchanged, it would admit the seven approved repos with
  `:tilt-<hash>` tags.

## Design Decision

Do not try to solve this with an additive Kyverno "overlay" policy.

Kyverno deny rules are additive. A production-safe base rule that rejects local
refs cannot be relaxed by a second "allow local Tilt refs" policy. The correct
approach is to maintain two mutually exclusive variants of the image policy and
apply exactly one per environment.

Recommended structure:

```text
kubernetes/kyverno/policies/shared/
  00-smoke-disallow-privileged.yaml
  10-require-namespace-pod-security-labels.yaml
  20-require-workload-automount-disabled.yaml
  30-require-workload-security-context.yaml
  40-disallow-obvious-default-credentials.yaml

kubernetes/kyverno/policies/local/
  50-require-third-party-image-digests.yaml

kubernetes/kyverno/policies/production/
  50-require-third-party-image-digests.yaml
```

Policy behavior by variant:

- `shared/`: identical between local and production
- `local/50...`: keep the seven approved local-image exceptions needed for
  `tilt up`
- `production/50...`: allow only digest-pinned third-party images plus the
  existing system-workload exceptions; reject all local `:latest` and
  `:tilt-<hash>` refs

Use the same `metadata.name` for the local and production `50...` variants so
operational references stay stable. Never apply both variants to the same
cluster.

## Work Plan

### 1. Restructure the Kyverno policy layout

Move the common policies into a shared directory and split the current `50...`
policy into two variants.

Files to change:

- `kubernetes/kyverno/policies/`
- `kubernetes/kyverno/README.md`

Required outcomes:

- there is no longer a single ambiguous `50...` file carrying both local and
  production meaning
- the local-only exception lives in a path whose purpose is explicit
- the production-safe variant exists as a first-class checked-in artifact

### 2. Make Tilt apply the local variant explicitly

Update the local Kyverno bootstrap in [`Tiltfile`](/workspace/orchestration/Tiltfile)
so local dev applies:

- `shared/00...40...`
- `local/50...`

Do not have Tilt apply the production `50...` variant.

Files to change:

- `Tiltfile`

Required outcomes:

- local `tilt up` behavior stays unchanged from the developer point of view
- the local cluster no longer relies on a production-ambiguous policy file

### 3. Add a production-safe test suite

Split the current Kyverno test coverage so both variants are exercised
explicitly.

Recommended structure:

```text
kubernetes/kyverno/tests/local/
kubernetes/kyverno/tests/production/
```

Local suite requirements:

- checked-in approved local `:latest` refs pass only with `Never`
- approved local `:tilt-<hash>` refs pass with `IfNotPresent`
- approved local `:tilt-<hash>` init-container case passes
- unapproved local mutable refs still fail

Production suite requirements:

- digest-pinned third-party images pass
- approved local `:latest` refs fail
- approved local `:tilt-<hash>` refs fail
- unapproved local mutable refs fail

Files to change:

- `kubernetes/kyverno/tests/pass/**`
- `kubernetes/kyverno/tests/fail/**`
- or replace that layout entirely with `tests/local/**` and `tests/production/**`
- `scripts/dev/verify-phase-7-static-manifests.sh`

Required outcomes:

- local and production contracts are both executable and version-controlled
- the generated Tilt replay runs only against the local policy variant

### 4. Add guardrails so the hole cannot reappear quietly

Static verification should fail if the local exception leaks back into the
production variant.

Recommended checks:

- assert the production `50...` variant does not contain the approved-local
  repo allowlist or `tilt-[a-f0-9]{16}`
- assert the local replay test points only at the local policy path
- assert `Tiltfile` applies the local variant and not the production variant

Primary file:

- `scripts/dev/verify-phase-7-static-manifests.sh`

This is the part that keeps "we'll remember later" from turning into drift.

### 5. Update the contract and operator docs

The current Phase 7 contract now mixes "what local Tilt needs" with "what
production should allow." Split that language clearly.

Files to change:

- `docs/plans/security-hardening-v2-phase-7-session-1-contract.md`
- `docs/plans/security-hardening-v2.md`
- `README.md`
- `AGENTS.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/ci-cd.md`
- `scripts/README.md`
- `kubernetes/kyverno/README.md`

Required wording changes:

- local dev installs the local variant
- production should use the production variant
- the local `:latest` / `:tilt-<hash>` exception is not part of the
  production-safe posture

### 6. Verify both paths before closing

Local verification:

1. run `./scripts/dev/verify-phase-7-static-manifests.sh`
2. run a fresh local flow:
   - `./setup.sh`
   - `tilt up`
   - `./scripts/dev/verify-clean-tilt-deployment-admission.sh`

Production-safe verification:

1. server-side dry-run a representative local `:latest` manifest against the
   production policy variant and confirm rejection
2. server-side dry-run a representative `:tilt-<hash>` manifest against the
   production policy variant and confirm rejection
3. confirm digest-pinned third-party examples still pass

## Recommended Implementation Order

1. Restructure the policy directories.
2. Create the production `50...` variant.
3. Move the current local contract into the local `50...` variant.
4. Update `Tiltfile` to apply `shared + local`.
5. Split and expand the Kyverno tests.
6. Add static guardrails that enforce the separation.
7. Update the contract and operator docs.
8. Run the local and production-safe verification matrix.

## Risks And Constraints

- The biggest risk is trying to express this as additive policies. That will not
  work cleanly because the production deny would still fire.
- Reusing the same policy name across variants is correct, but only if each
  environment applies exactly one variant.
- The current repo has no production Kyverno install path. That is why the hole
  is theoretical today, but the point of this change is to make accidental reuse
  harder later.
- The clean-start verification script checks for local-cluster violations in the
  current namespace history. Use a fresh run for the final admission proof.

## Success Criteria

- The local cluster still admits the seven approved app deployments after a
  fresh `./setup.sh` + `tilt up`.
- The repo contains a production-safe checked-in image policy variant that
  rejects approved local `:latest` and `:tilt-<hash>` refs.
- The static verification suite tests both variants and fails if the local
  exception leaks into the production variant.
