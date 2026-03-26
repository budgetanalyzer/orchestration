# Phase 6 Post-Review Corrections - Final Implementation Plan

Date: March 26, 2026

## Context

Two review perspectives were consolidated for the Phase 6 implementation:

- the checked-in review artifact in
  [security-hardening-v2-phase-6-review-corrections.md](./security-hardening-v2-phase-6-review-corrections.md)
- a second review that judged the implementation broadly correct and called out
  one missing proof: the Phase 6 verifier does not directly probe `/login`
  inside its own auth-edge section even though `/login` was Session 6's primary
  change

A fresh repo review should keep this correction set narrow and evidence-based.

## Review Consolidation

### Keep

These items are real and should remain in the correction plan:

1. `/api/docs/*` does not fail closed today.
   Unknown docs paths still fall through to the frontend SPA and inherit the
   relaxed dev CSP.
2. `nginx/nginx.production.k8s.conf` is only text-checked by the Phase 6 gate.
   The verifier does not run a real syntax check against that production
   variant.
3. The `/_prod-smoke/` local build contract is underspecified.
   Tilt does not watch the sibling frontend `.env*` inputs used by Vite, and
   the orchestration docs do not state clearly that the sibling frontend needs
   local npm dependencies available for `npm run build:prod-smoke`.
4. The Phase 6 verifier should directly prove `/login` ingress throttling in
   its own auth-edge section.
   The overall Phase 6 gate still covers `/login` today through the nested
   Phase 3 regression, but Session 6's phase-specific `/login` change should be
   self-proving in the Phase 6 section instead of depending only on that
   regression cascade.

### Do Not Keep

Do not keep the earlier review's specific "Phase 3 frontend forwarded-header
failure" item as a Phase 6 correction workstream.

Reason:

- a fresh rerun did not reproduce that exact claimed failure mode
- the current live gate can still be red for broader runtime/verifier drift,
  but that is not evidence of a Phase 6 implementation defect
- we should not expand this correction plan around a stale hypothesis

If a forwarded-header failure reproduces again against current checked-in
manifests, track it as a separate regression investigation with fresh evidence.

## Goal

Land the smallest set of checked-in orchestration changes needed to close the
real Phase 6 review gaps without widening scope into unrelated runtime drift.

## Non-Goals

- no new product features
- no service-repo application code changes from this repo
- no attempt to replace the manual browser-console validation requirement with
  `curl`-only claims
- no speculative verifier hardening for stale or unreproduced Phase 3 failures
- no re-design of the ingress architecture unless a fresh reproduced failure
  proves the current approach is wrong

## Repo Ownership

- **orchestration-only**
  - `nginx/nginx.k8s.conf`
  - `nginx/nginx.production.k8s.conf`
  - `Tiltfile`
  - `scripts/dev/verify-phase-6-edge-browser-hardening.sh`
  - nearest affected docs in `README.md`, `docs/`, and `nginx/README.md`
- **coordinated sibling prerequisite**
  - any frontend fix in `budget-analyzer-web` needed to remove browser-console
    noise such as `/vite.svg` or other smoke-build output issues

## Workstreams

### Workstream 1: Make `/api/docs/*` Fail Closed

**Goal**

Ensure the docs subtree is a deliberate strict-CSP surface instead of a partial
route set that can fall through to the frontend SPA.

**Files**

- `nginx/nginx.k8s.conf`
- `nginx/nginx.production.k8s.conf`
- `scripts/dev/verify-phase-6-edge-browser-hardening.sh`
- `nginx/README.md`
- `docs/development/local-environment.md`
- `docs/architecture/security-architecture.md`

**Changes**

- Add an explicit `/api/docs/` catch-all in both dev and production NGINX
  variants so unknown docs paths do not fall through to `location /`.
- Keep the existing exact/regex matches for the known docs shell, docs assets,
  and OpenAPI downloads.
- Return `404` for any other `/api/docs/*` request unless there is a deliberate,
  checked-in reason to serve it.
- Decide intentionally how to handle source maps:
  - either serve the expected map files explicitly
  - or strip `sourceMappingURL` comments from vendored assets
  - or let those requests return docs-scoped `404`
- Extend the Phase 6 verifier with negative assertions:
  - unknown `/api/docs/*` paths return `404`
  - missing docs assets do not return frontend HTML
  - missing docs assets do not inherit the relaxed dev CSP

**Verification**

- `curl -I http://127.0.0.1:8080/api/docs/not-a-real-file`
- `curl -I http://127.0.0.1:8080/api/docs/swagger-ui.css.map`
- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh`

**Stop if**

- the chosen sourcemap handling approach would require an opaque or drifting
  vendoring process
- if that happens, prefer clean `404` handling over hidden asset sprawl

### Workstream 2: Add Real Syntax Validation for the Production NGINX Variant

**Goal**

Prevent the production route cutover from drifting into a file that looks right
in text but does not parse.

**Files**

- `scripts/dev/verify-phase-6-edge-browser-hardening.sh`
- possibly a small helper in `scripts/dev/` if the syntax test needs reuse
- `nginx/README.md`
- `docs/development/local-environment.md`

**Changes**

- Add a real syntax check for `nginx/nginx.production.k8s.conf` to the Phase 6
  verifier.
- Reuse the running `nginx-gateway` pod or another controlled NGINX runtime so
  the test executes with the include files the config expects.
- Fail clearly if:
  - the production config does not parse
  - the required include files are missing
  - the validation path depends on undeclared runtime assumptions
- Keep the existing text assertions for route ownership, but do not rely on
  text inspection alone.

**Verification**

- explicit syntax check of the production variant inside automation
- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh`

**Stop if**

- the syntax-validation approach requires a bespoke one-off container workflow
  that is harder to trust than the config itself
- if that happens, use the running NGINX pod with copied config/includes
  instead of inventing another execution surface

### Workstream 3: Add Direct `/login` Coverage to the Phase 6 Auth-Edge Verifier

**Goal**

Make Session 6's `/login` rate-limit expansion self-proving inside the Phase 6
verifier rather than relying only on the nested Phase 3 regression.

**Files**

- `scripts/dev/verify-phase-6-edge-browser-hardening.sh`
- `docs/architecture/security-architecture.md`
- nearest affected docs that enumerate direct Phase 6 auth-edge coverage

**Changes**

- Add one direct `require_ingress_rate_limit_from_probe "/login" "/login"`
  assertion in `verify_auth_edge_runtime`.
- Keep the existing direct Phase 6 probes for `/auth/*`, `/logout`, and
  `/login/oauth2/*`.
- Do not duplicate the Phase 3 external-caller proofs for
  `/oauth2/authorization/idp` and `/user` unless a fresh coverage gap is found.
- Update the docs that describe the direct Phase 6 Session 9 auth-edge
  coverage so `/login` is listed there too.

**Verification**

- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh`
- confirm the "Auth Edge Runtime Coverage" section includes `/login`

**Stop if**

- the `/login` probe exposes an unexpected route-ownership or redirect behavior
  mismatch
- if that happens, fix the verification model without weakening the claim that
  Session 6 must directly prove its own `/login` change

### Workstream 4: Make the `/_prod-smoke/` Local Build Contract Explicit

**Goal**

Remove hidden local assumptions from the smoke-build path so Tilt and the docs
match what Phase 6 actually depends on.

**Files**

- `Tiltfile`
- `README.md`
- `docs/development/local-environment.md`
- `nginx/README.md`

**Changes**

- Expand the smoke-build `local_resource` dependency/watch set to include the
  actual sibling Vite build inputs, including `.env*` files used at build time.
- Document the local prerequisite explicitly in orchestration docs:
  - the sibling `budget-analyzer-web` repo needs local npm dependencies
    available for `npm run build:prod-smoke`
- If needed, add a lightweight preflight check so the failure mode is explicit
  when the sibling repo is present but not installed.
- Keep the distinction clear between:
  - the normal frontend pod, which installs and runs inside its image
  - the local smoke-build path, which currently depends on host/devcontainer npm
    state

**Verification**

- edit a tracked smoke-build input and confirm Tilt rebuilds the smoke asset
  path
- change a relevant `.env*` input and confirm the smoke build is re-triggered
- verify the docs state the prerequisite unambiguously

**Stop if**

- the only reliable fix would require writing application code in the sibling
  frontend repo from this repository
- if that happens, document the required sibling change and stop at the
  boundary

## Follow-Up Candidate: Browser-Noise Cleanup

This is not part of the first correction set, but it should stay visible after
the primary workstreams are closed:

- investigate the smoke bundle's `/vite.svg` reference and coordinate the fix
  in `budget-analyzer-web` if it still produces browser-console noise
- decide whether vendored Swagger UI sourcemap comments should remain after the
  docs catch-all is fixed

## Execution Order

1. Workstream 1: make `/api/docs/*` fail closed and extend verifier coverage
2. Workstream 2: add real syntax validation for the production NGINX variant
3. Workstream 3: add direct `/login` coverage to the Phase 6 auth-edge section
4. Workstream 4: declare the smoke-build contract in Tilt and docs
5. Re-run the full Phase 6 gate
6. If the gate is still red for reasons outside these four workstreams, open a
   separate regression investigation instead of widening this correction plan

## Success Criteria

### Correction-Set Complete

Treat this post-review correction effort as complete when all of the following
are true:

- unknown `/api/docs/*` requests return docs-scoped `404` instead of frontend
  HTML
- the Phase 6 verifier syntax-checks `nginx/nginx.production.k8s.conf`
- the Phase 6 verifier directly probes `/login` inside its own auth-edge
  section
- the smoke-build local prerequisite is documented and the relevant Vite build
  inputs are tracked by Tilt

### Phase 6 Operational Closure

Phase 6 itself is operationally closed only when all of the following are true:

- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh` passes end-to-end
- manual browser-console validation on `/_prod-smoke/` and `/api/docs` is still
  completed
- any remaining gate failure outside this correction set is either fixed by
  separate work or captured explicitly as a separate follow-up instead of being
  retrofitted into this plan without fresh evidence
