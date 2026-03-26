# Phase 6 Review: Corrections Plan

Date: March 26, 2026

## Scope

Review of the `security-hardening-v2` Phase 6 implementation in `orchestration`.
This is a review artifact, not an implementation log.

Implementation follow-up:

- [security-hardening-v2-phase-6-corrections-implementation.md](./security-hardening-v2-phase-6-corrections-implementation.md)

Validation used during this review:

- read-through of the Phase 6 NGINX, Tilt, manifest, script, and docs changes
- live `nginx -T` inspection in the running `nginx-gateway` pod
- `bash -n` on the new shell scripts
- live execution of:
  - `./scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh`
  - `./scripts/dev/verify-phase-6-edge-browser-hardening.sh --subverifier-timeout 12m --phase5-regression-timeout 8m`
- targeted live HTTP checks against `http://127.0.0.1:8080` and `https://app.budgetanalyzer.localhost`

## Findings

### 1. Blocker: the Phase 6 completion gate is not clean because the nested Phase 5 regression cascade surfaced a Phase 3 frontend forwarded-chain failure

Observed during this review:

- the Phase 6 verifier reached the nested Phase 5 regression cascade
- the nested Phase 3 verifier failed its frontend forwarded-header probe with:
  - `Frontend forwarded-chain probe returned 000 (expected 200)`
  - `NGINX log does not contain the controlled forwarded-chain probe request for frontend traffic`
- the paired API forwarded-header probe still passed in the same run

Why this matters:

- The implementation is not actually review-complete while the advertised completion gate is still red or flaky.
- Even if the root cause is verifier instability rather than product behavior, that still blocks truthful completion claims.

Relevant files:

- `scripts/dev/verify-phase-6-edge-browser-hardening.sh`
- `scripts/dev/verify-phase-5-runtime-hardening.sh`
- `scripts/dev/verify-phase-3-istio-ingress.sh`

Correction plan:

1. Reproduce the failure in isolation with the Phase 3 verifier and targeted `curl -vk` probes that send the forged `X-Forwarded-For` header to `/`.
2. Separate transport flakiness from route behavior:
   - if the frontend request is intermittently failing before it reaches NGINX, harden the verifier retry/backoff and capture the TLS failure explicitly
   - if the request reaches ingress but not NGINX, inspect ingress/auth policy handling for forged forwarded headers on frontend paths
3. Do not call Phase 6 complete until the full Phase 6 verifier passes end-to-end without the nested Phase 3 failure.

### 2. Medium: `/api/docs/*` is not hermetic; unknown docs paths fall through to the frontend catch-all and return HTML with the relaxed dev CSP

Observed during this review:

- `curl -I http://127.0.0.1:8080/api/docs/not-a-real-file` returned `200 text/html`
- `curl -I http://127.0.0.1:8080/api/docs/swagger-ui.css.map` also returned `200 text/html`
- both responses carried the relaxed frontend CSP instead of a docs-scoped `404` or a docs-scoped strict response

Why this matters:

- Missing or mistyped docs assets do not fail closed.
- The docs subtree can silently degrade into the frontend SPA with the wrong CSP.
- This weakens the Phase 6 claim that `/api/docs` is a strict, same-origin, self-contained surface.

Likely cause:

- The config defines exact/regex matches for known docs files, but there is no `/api/docs/` catch-all ahead of the general frontend `location /` block.

Relevant files:

- `nginx/nginx.k8s.conf`
- `nginx/nginx.production.k8s.conf`
- `scripts/dev/verify-phase-6-edge-browser-hardening.sh`

Correction plan:

1. Add an explicit `/api/docs/` catch-all that does not fall through to the frontend SPA.
   - preferred shape: keep exact/regex matches for allowed docs assets and return `404` for any other `/api/docs/*` path
2. Decide intentionally whether source maps should be:
   - served explicitly, or
   - stripped from the vendored asset comments, or
   - allowed to 404 cleanly under the docs subtree
3. Extend the Phase 6 verifier with negative assertions:
   - unknown `/api/docs/*` paths return `404`
   - missing docs assets do not inherit the relaxed frontend CSP

### 3. Medium: the production-only NGINX route variant is grep-checked, not syntax-checked, by the Phase 6 gate

Observed during this review:

- `scripts/dev/verify-phase-6-edge-browser-hardening.sh` validates `nginx/nginx.production.k8s.conf` by text inspection only
- it does not run `nginx -t` or equivalent against that file
- I had to validate it manually by copying the production config and includes into the running `nginx-gateway` pod before `nginx -t` would prove it parses

Why this matters:

- The production route cutover is a major Phase 6 deliverable.
- A syntax error in `nginx/nginx.production.k8s.conf` would evade the current completion gate entirely.

Relevant files:

- `scripts/dev/verify-phase-6-edge-browser-hardening.sh`
- `nginx/nginx.production.k8s.conf`

Correction plan:

1. Add a real syntax check for `nginx/nginx.production.k8s.conf` to the Phase 6 verifier.
2. Reuse the running NGINX pod or a disposable NGINX container so the check runs with the same include files the config expects.
3. Fail the Phase 6 gate if either:
   - the config does not parse, or
   - required include files for that production variant are missing

### 4. Medium: the `/_prod-smoke/` build path relies on local frontend prerequisites that are not fully declared or documented

Observed during this review:

- Tilt now runs `npm run build:prod-smoke` from the sibling `budget-analyzer-web` repo as a `local_resource`
- the deps list does not include Vite env files such as `.env*`
- the quick-start docs in this repo do not state that the sibling frontend must have local npm dependencies installed for the smoke build path to work
- the sibling frontend does read Vite env at build/runtime (`VITE_API_BASE_URL`)

Why this matters:

- A clean workspace can fail the smoke-build resource even though the normal frontend pod still has its own containerized install path.
- Local env changes can leave `/_prod-smoke/` stale because the resource watch list does not include the env files Vite consumes.

Relevant files:

- `Tiltfile`
- `README.md`
- `docs/development/local-environment.md`
- sibling read-only evidence: `../budget-analyzer-web/src/api/client.ts`

Correction plan:

1. Expand the smoke-build `local_resource` watch list to include the actual Vite build inputs, including `.env*` files used by the sibling frontend.
2. Document the local prerequisite clearly in orchestration docs:
   - the sibling `budget-analyzer-web` repo needs local npm dependencies available for the Phase 6 smoke build path
3. Consider wrapping the smoke build with a clearer preflight check so the failure mode is explicit instead of surfacing as a generic Tilt/local build failure.

## Residual Risk

These are worth correcting, but they are secondary to the four items above:

- The smoke build currently references `/vite.svg`, but the reviewed smoke bundle only contained `index.html` and hashed assets. That is likely to produce avoidable browser noise during the required manual validation and will need a sibling frontend fix rather than an orchestration code change.
- The vendored Swagger UI assets still contain `sourceMappingURL` comments. Once the `/api/docs/*` catch-all is fixed, decide whether to vendor the maps or strip the comments to keep browser-console validation quiet.

## Recommended Execution Order

1. Fix the `/api/docs/*` catch-all leak and add verifier coverage for the negative path.
2. Add real syntax validation for `nginx/nginx.production.k8s.conf` in the Phase 6 verifier.
3. Make the `/_prod-smoke/` local build prerequisites explicit in Tilt/docs and include `.env*` in the watch set.
4. Re-run the full Phase 6 gate and investigate the remaining Phase 3 forwarded-chain instability until the advertised completion gate is green.

## Exit Criteria

Treat this review as closed only when all of the following are true:

- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh` passes end-to-end
- the nested Phase 5 regression cascade is clean
- unknown `/api/docs/*` paths fail closed instead of falling into the frontend SPA
- `nginx/nginx.production.k8s.conf` is syntax-checked by automation, not just by text inspection
- the `/_prod-smoke/` build prerequisites are documented and reliably tracked by Tilt
