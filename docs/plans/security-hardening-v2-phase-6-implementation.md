# Phase 6: Edge and Browser Hardening - Implementation Plan

## Context

Phase 5 completed on March 25, 2026 with the expanded runtime-hardening gate passing `175/175`. Phase 6 has since closed the initial CSP, docs-delivery, auth-edge, API identity, and production-route prerequisites, and Session 9 now adds the dedicated completion gate:

- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh` is implemented in-repo and proves the checked-in edge/browser contract, reruns the Session 3 and Session 7 Phase 6 verifiers, and then reruns the Phase 5 regression cascade.
- Manual browser-console validation is still required before Phase 6 can be called complete.

Phase 6 therefore could not start by flipping a stricter CSP globally, and that prerequisite work is now complete: the production-smoke seam exists, `/api/docs` is self-contained under a strict same-origin CSP, the OpenAPI download routes no longer expose wildcard CORS, and the checked-in production NGINX route variant now removes the local Vite route graph from the production surface.

Post-review follow-up plan:

- [security-hardening-v2-phase-6-corrections-implementation.md](./security-hardening-v2-phase-6-corrections-implementation.md)

## Recommended Direction

Use the following implementation strategy unless new evidence proves it wrong:

1. Add a repeatable production-smoke frontend path first so strict CSP can be verified against built assets without breaking Vite/HMR.
2. Make `/api/docs` self-contained and CSP-compatible before touching the enforced production header.
3. Keep the default dev route on the relaxed Vite-compatible CSP.
4. Keep API rate limiting in NGINX only if trusted client identity can be proven there. If not, move public API rate limiting to ingress instead of guessing.
5. Keep manual browser-console verification in scope for Phase 6 unless a separate, explicit session adds headless browser automation. Do not imply that `curl` proves browser CSP enforcement.
6. Treat the production frontend cutover as a checked-in deployment/configuration concern, not as a runtime env-var switch that only changes CSP headers while leaving the Vite route graph exposed.

## Target State

Phase 6 is complete when all of the following are true:

- Development routes keep the relaxed CSP required for Vite and HMR.
- A production-oriented frontend/docs path emits a strict enforced CSP with no `'unsafe-inline'` and no `'unsafe-eval'`.
- The `/_prod-smoke/` path remains a local-development verification seam only; production serves the built frontend on `/` and `/login` and must not expose Vite/HMR routes.
- `/api/docs` works without wildcard CORS and without third-party CDN script/style dependencies.
- Auth-edge throttling at Istio ingress covers the intended auth surface, including the `/login` entry point decision from this phase.
- Public API rate limiting keys on a trustworthy client identity rather than the proxy hop.
- Production route configuration serves the built frontend on `/` and `/login` with the strict CSP and does not expose the local Vite/HMR public routes or `/_prod-smoke/`.
- A dedicated Phase 6 gate proves the headers, throttling, and identity handling, and re-runs the Phase 5 runtime-hardening verifier as the regression cascade.

## Repo Ownership

- **orchestration-only**
  - NGINX configuration
  - Istio ingress rate limiting
  - docs aggregator assets
  - Tilt wiring
  - Phase 6 verification and documentation
- **Coordinated sibling prerequisite**
  - `budget-analyzer-web` production-build behavior and any frontend CSP violations discovered under strict policy

No `session-gateway` code changes are expected for Phase 6 unless validation exposes an auth-path behavior mismatch that cannot be solved at ingress/NGINX.

## Session Breakdown

Each session below is sized to finish in one focused work session and has an explicit stop condition when the prerequisite is not yet satisfied.

### Session 1: Add a Production-Smoke Frontend Verification Path

**Goal**

Create a repeatable way to validate strict production CSP against built frontend assets without breaking the default Vite/HMR loop.

**Owner**

Coordinated work across `orchestration` and `budget-analyzer-web`

The coordinated frontend prerequisite is now satisfied: `budget-analyzer-web` supports a production smoke build mounted under `/_prod-smoke/`, so Session 1 should implement the same-origin subpath design rather than the earlier dedicated-port fallback.

**Files**

- `Tiltfile`
- `kubernetes/services/nginx-gateway/deployment.yaml` only if extra static asset mounts are needed
- `docs-aggregator/` only if the smoke assets are mounted through the existing docs ConfigMap path
- `../budget-analyzer-web/src/main.tsx`
- `../budget-analyzer-web/vite.config.ts`
- `../budget-analyzer-web/package.json`
- `../budget-analyzer-web/Dockerfile` or a new production/smoke Dockerfile if the current dev image remains Vite-only
- nearest affected frontend docs that explain the smoke build and subpath mounting

**Changes**

- Add a production-build smoke path that serves a built frontend bundle under the same public origin without replacing the current dev route.
- Serve the smoke bundle under the dedicated same-origin path `/_prod-smoke/` so no new hostname or certificate work is required.
- Build that bundle with an explicit Vite `base` that matches the chosen smoke path.
- Keep the frontend router aligned with the Vite base path so SPA navigation and deep links work correctly under `/_prod-smoke/`.
- If the smoke path stays on the NGINX public origin, serve the built assets directly from NGINX as static files from a mounted directory. Do not model the smoke path as another `proxy_pass` to a running frontend process.
- Keep the current `/` and `/login` dev experience on Vite/HMR so inner-loop development does not regress during Phase 6.
- Document clearly that the smoke path exists only to validate production-browser policy and should not become a second long-term frontend mode with different behavior.
- Make the production cutover explicit in the docs: production serves the built frontend at `/` and `/login` under the strict CSP, and it does not ship the local Vite/HMR route set or the `/_prod-smoke/` verification path.

**Verification**

- The smoke bundle builds reproducibly from the sibling repo.
- `curl -k https://app.budgetanalyzer.localhost/_prod-smoke/` returns `200`.
- The smoke page loads its JS/CSS assets from the same origin and path prefix.
- SPA navigation and deep links under `/_prod-smoke/` resolve correctly instead of falling back to root-mounted routing assumptions.
- The default dev route still serves the existing Vite application with HMR.

**Stop if**

- The checked-in web prerequisite regresses and the frontend can no longer be served under `/_prod-smoke/` without breaking routing or asset resolution.
- If that happens, stop and fix the subpath support in `budget-analyzer-web` rather than introducing a dedicated verification port/service workaround.

### Session 2: Make `/api/docs` Strict-CSP Compatible

**Goal**

Remove the orchestration-owned blockers that would make a strict production CSP fail immediately on the shared docs page.

**Owner**

`orchestration`

Current implementation status for March 25, 2026:

- Session 2 is implemented in-repo: `docs-aggregator/index.html` now loads only same-origin assets, the inline bootstrap/styles moved to `docs-aggregator.js` and `docs-aggregator.css`, Swagger UI `5.11.0` is pinned in-repo behind `./scripts/refresh-swagger-ui-assets.sh`, and `nginx-gateway` now copies the docs bundle from a static-asset image instead of trying to fit the large vendor JS in a ConfigMap.

**Files**

- `docs-aggregator/index.html`
- `docs-aggregator/README.md`
- `docs-aggregator/` pinned local Swagger UI assets or an equivalent checked-in asset-update flow
- `Tiltfile`

**Changes**

- Remove inline `<style>` and inline `<script>` from `docs-aggregator/index.html`.
- Stop loading Swagger UI assets from `https://unpkg.com`.
- Vendor or otherwise pin the Swagger UI assets locally so `/api/docs` can run under `script-src 'self'` and `style-src 'self'`.
- Resolve the existing Swagger UI version drift between `docs-aggregator/README.md` and `docs-aggregator/index.html` when vendoring.
- Keep the docs UI same-origin. Do not introduce a cross-origin docs hosting pattern just to keep the old page structure.
- Set Swagger UI submit behavior explicitly so "Try it out" is disabled independent of upstream defaults. Use `supportedSubmitMethods: []`, and set `tryItOutEnabled: false` as a clarity signal if the config keeps that option.
- Remove debug logging from the docs bootstrap if it no longer adds operational value.

**Verification**

- `/api/docs` renders with only same-origin JS/CSS requests.
- Browser developer tools show no network dependency on `unpkg.com`.
- The docs selector still loads the service OpenAPI specs through the public gateway path.

**Stop if**

- The chosen Swagger asset approach requires an unreviewable or drifting download path.
- If that happens, add a pinned asset-refresh script and keep the generated/static assets reviewable in-repo.

### Session 3: Audit Frontend CSP Violations Under the Smoke Path

**Goal**

Use the new production-smoke path to find the real frontend blockers before the strict production CSP is enforced and to document the sibling prerequisite cleanly.

**Owner**

`orchestration` stop-gate, with `budget-analyzer-web` as a coordinated prerequisite

Current implementation status for March 25, 2026:

- Session 3 stop-gate tooling and findings are now implemented in-repo.
- `./scripts/dev/audit-phase-6-session-3-frontend-csp.sh` rebuilds the sibling `build:prod-smoke` bundle and checks the current repo-owned evidence for same-origin smoke assets, eval-like bundle tokens, React inline style props, and the current `sonner` runtime CSS injection path.
- As of March 26, 2026, the coordinated sibling prerequisite is satisfied: the frontend removed the inline-style and `sonner` blockers, and the repo-owned static audit now passes. Manual browser-console validation remains required; see `docs/plans/security-hardening-v2-phase-6-session-3-frontend-csp-audit.md`.

**Files**

- nearest affected orchestration docs that capture the prerequisite and findings
- sibling application code remains read-only from this repo

**Changes**

- Run the built frontend under a strict candidate CSP and capture the actual violations instead of guessing.
- Use `Content-Security-Policy-Report-Only` on the production-smoke path only if that materially improves violation capture during this stop-gate. Do not confuse that temporary probe with final enforcement.
- Start with likely hot spots:
  - inline-style call sites currently visible in `EditableTransactionRow.tsx`, `TransactionTable.tsx`, `ViewTransactionTable.tsx`, and `YearSelector.tsx`
  - any runtime-generated style/script behavior that only appears in the production bundle
- Record the exact violations and the frontend changes required to remove any production dependency on `'unsafe-inline'` or `'unsafe-eval'`.
- Treat those frontend changes as a sibling prerequisite. Do not plan to edit `budget-analyzer-web` application code from this repo.
- Do not use nonce/hash exceptions as a casual shortcut for application code. The target state for the production app is a clean strict policy, not a patchwork of exceptions.

**Verification**

- The production-smoke frontend loads and navigates without CSP console violations.
- Login flow initiation from the smoke frontend still reaches `/oauth2/authorization/idp`.
- Manual browser-console validation is required here unless a separate scoped session adds browser automation and wires it into the Phase 6 verifier.

**Stop if**

- A third-party dependency requires eval or inline behavior in production and no supported strict-CSP path exists.
- If that happens, stop and decide explicitly whether the dependency must be replaced or the route needs a documented exception.

### Session 4: Wire the Dev/Production CSP Split into NGINX

**Goal**

Move from one global dev-grade CSP to an explicit split between relaxed development behavior and strict production-oriented behavior.

**Owner**

`orchestration`

Current implementation status for March 26, 2026:

- Session 4 is implemented in-repo.
- `nginx-gateway` now uses checked-in dev and strict security-header include files instead of a single global CSP line.
- The relaxed Vite/HMR-compatible CSP remains the default for `/`, `/login`, and the dev asset routes.
- A strict enforced CSP with no `'unsafe-inline'` and no `'unsafe-eval'` now applies to `/_prod-smoke/`, `/api/docs`, the same-origin docs asset files, and the OpenAPI download routes.
- The docs and OpenAPI routes now re-include the full security header set in their `location` blocks so route-specific `add_header` directives no longer drop the non-CSP headers accidentally.

**Files**

- `nginx/nginx.k8s.conf`
- `nginx/includes/` new CSP include files if the config is split there
- `Tiltfile` only if config assembly changes
- `nginx/README.md`
- `docs/development/local-environment.md`

**Changes**

- Factor the CSP policy out of the single server-level header so dev and production-oriented routes can differ intentionally.
- Fix the existing NGINX header-inheritance bug first: `add_header` inside the `/api/docs` and OpenAPI download `location` blocks currently overrides the server-level security header set. Use `add_header_inherit merge`, repeated checked-in includes, or an equivalent structure that preserves the full header set on those routes before the CSP split lands.
- Keep the relaxed policy on the default Vite/HMR development routes.
- Apply the strict enforced policy to:
  - the production-smoke frontend path from Session 1
  - `/api/docs` once Session 2 is complete
- Use `Content-Security-Policy-Report-Only` temporarily only if it materially helps close violations in the same session. Do not leave report-only as the final posture.
- Make the final strict production policy explicit in the docs. It should remove both `'unsafe-inline'` and `'unsafe-eval'`.
- Document the production route outcome explicitly: this session keeps the relaxed dev policy only for local Vite/HMR, while production applies the strict frontend CSP on the normal app routes instead of preserving `/_prod-smoke/`.

**Verification**

- `curl -kI` shows different CSP headers for the dev route and the production-smoke/docs routes.
- The default dev frontend still keeps HMR working.
- The strict routes do not silently inherit the relaxed development CSP.
- `/api/docs` and `/api/docs/openapi.{json,yaml}` still emit the non-CSP security headers expected from the server-level policy after the route-specific header work.

**Stop if**

- The config split becomes dependent on ad-hoc manual patching or undocumented environment mutation.
- If that happens, move to explicit checked-in config variants or includes rather than hidden runtime templating.

### Session 5: Remove Wildcard CORS from Docs Assets

**Goal**

Delete the unnecessary `Access-Control-Allow-Origin: *` exposure from the OpenAPI download endpoints.

**Owner**

`orchestration`

Current implementation status for March 26, 2026:

- Session 5 is implemented in-repo: `/api/docs/openapi.json` and `/api/docs/openapi.yaml` no longer emit `Access-Control-Allow-Origin: *`, the downloads remain same-origin through `nginx-gateway`, and the docs now treat any future cross-origin exception as an explicit allowlist decision that must be documented.

**Files**

- `nginx/nginx.k8s.conf`
- `nginx/README.md`
- `docs-aggregator/README.md`

**Changes**

- Remove `Access-Control-Allow-Origin "*"` from `/api/docs/openapi.json` and `/api/docs/openapi.yaml`.
- Keep the docs and downloads same-origin by default.
- If a real cross-origin consumer still exists, replace the wildcard with a documented explicit allowlist and explain why the same-origin model is insufficient for that case.

**Verification**

- `/api/docs` still loads and download links still work from the shared docs UI.
- A same-origin fetch of the OpenAPI assets still succeeds.
- A cross-origin probe no longer receives the wildcard CORS header unless an explicit allowlist was intentionally introduced and documented.
- The OpenAPI download routes still emit the expected security headers after the CORS cleanup.

### Session 6: Expand Auth-Edge Throttling at Istio Ingress

**Goal**

Ensure auth-sensitive browser entry points are rate limited at the actual edge, not only after routing decisions deeper in the stack.

**Owner**

`orchestration`

**Files**

- `kubernetes/istio/ingress-rate-limit.yaml`
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- `nginx/README.md`
- `docs/architecture/bff-api-gateway-pattern.md`
- `docs/development/local-environment.md`

**Changes**

- Extend the ingress auth-path matcher so the `/login` entry point is covered intentionally.
- Recommended minimum: cover exact `/login` plus query-string variants while keeping `/login/oauth2/*` under the auth-sensitive bucket.
- Only broaden to `PathPrefix /login/` if the actual frontend route structure needs it. Do not throttle unrelated SPA routes by accident.
- Preserve the current `x-local-rate-limit: auth-sensitive` response marker so the runtime proof remains precise.
- Keep route ownership unchanged: `/login` stays frontend-owned, and `/oauth2/*`, `/login/oauth2/*`, `/auth/*`, `/logout`, and `/user` stay on Session Gateway.

**Verification**

- Repeated requests to `/login`, `/oauth2/authorization/idp`, and `/user` trigger ingress `429` responses with the expected marker.
- Normal, low-rate requests to `/login` still return the frontend page.
- The callback prefix `/login/oauth2/*` still routes to Session Gateway.

**Stop if**

- Broad `/login/*` matching catches normal frontend asset/navigation traffic and creates false positives.
- If that happens, narrow the matcher to exact `/login` and the already-owned `/login/oauth2/*` callback prefix.

### Session 7: Fix API Rate-Limit Identity Correctness

**Goal**

Make API throttling key on a trustworthy client identity instead of the current proxy hop.

**Owner**

`orchestration`

Current implementation status for March 26, 2026:

- Session 7 is implemented in-repo: a live pre-change capture showed NGINX receiving ingress traffic as `remote_addr=127.0.0.6` with `xff="<caller>,<downstream-hop>"` and `xrealip="-"`, so the trust anchor is the pod-local sidecar path rather than a guessed cluster CIDR. `nginx-gateway` now applies `real_ip_header X-Forwarded-For`, `real_ip_recursive on`, and `set_real_ip_from 127.0.0.0/8`, logs both the derived client IP and the trusted proxy hop, and therefore keys API `limit_req` buckets on the ingress-appended downstream client hop. `./scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` proves forged external `X-Forwarded-For` values cannot select a new bucket and that distinct downstream clients do not share one API limiter bucket.

**Files**

- `nginx/nginx.k8s.conf`
- `nginx/includes/backend-headers.conf` only if header handling changes
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- new Phase 6 verifier in `scripts/dev/`
- `nginx/README.md`

**Changes**

- Discovery prerequisite:
  - capture the actual `$remote_addr`, `$http_x_forwarded_for`, and `$http_x_real_ip` values NGINX sees on a sample request before choosing any `real_ip_*` configuration
  - treat the observed ingress or sidecar source path as the trust anchor, not a guessed CIDR
- Primary path:
  - configure NGINX trusted-proxy handling with `real_ip_header`, `real_ip_recursive on`, and a narrow `set_real_ip_from` scope based on the proven ingress/mesh source path
  - switch the `limit_req_zone` key from the raw proxy hop to the derived client IP
  - add explicit logging of both the derived client identity and the raw forwarded chain so verification can prove the trust model
- Do not trust broad source ranges unless the enforcement story proves that only the intended ingress path can reach NGINX.
- Fallback path:
  - if NGINX cannot derive a trustworthy client identity cleanly, move public API rate limiting to ingress and remove the edge-facing NGINX limiters rather than shipping a false sense of protection

**Verification**

- A forged external `X-Forwarded-For` value does not let the caller select an arbitrary rate-limit bucket.
- Requests from the same real client exhaust the same bucket consistently.
- Requests from different real clients do not share the same bucket just because they traverse the same proxy hop.
- Existing forwarded-header-chain verification still passes.

**Stop if**

- The only way to make NGINX trust the client IP is to trust an unbounded set of in-cluster sources with no strong enforcement proof.
- If that happens, stop and move the public API limiter to ingress instead.

### Session 8: Define the Production Frontend Route Cutover

**Goal**

Make the production route shape explicit so the local `/_prod-smoke/` seam and Vite/HMR routes are not left behind in production deployments.

**Owner**

`orchestration`

Current implementation status for March 26, 2026:

- Session 8 is implemented in-repo: `nginx/nginx.production.k8s.conf` now defines the production frontend cutover explicitly. `/` and `/login` serve the built frontend bundle from NGINX under the strict CSP, `/@vite/client`, `/src`, and `/node_modules` return `404`, and `/_prod-smoke/` is kept local-only by returning `404` in the production variant instead of remaining a public route.

**Files**

- production-facing NGINX configuration or checked-in production overlay for `nginx-gateway`
- frontend deployment wiring only if production still references the Vite pod today
- nearest affected docs in `docs/` and `nginx/README.md`
- `docs/plans/security-hardening-v2.md`

**Changes**

- Define a checked-in production route variant that serves the built frontend bundle on `/` and `/login`.
- Remove Vite-only public routes from the production route set, including `/@vite/client`, `/src`, and `/node_modules`.
- Ensure the strict frontend CSP applies on the normal production app routes rather than preserving `/_prod-smoke/`.
- Treat `/_prod-smoke/` as local verification plumbing only; do not require it in production manifests or public routing.
- If a deployment overlay is used, keep it explicit and checked in. Do not rely on undocumented env-var templating or runtime patching to mutate the route graph.

**Verification**

- The production route definition does not proxy `/` or `/login` to the Vite pod.
- The production route definition does not expose Vite-only public endpoints.
- The production route definition applies the strict frontend CSP on `/` and `/login`.
- The local development route definition still keeps Vite/HMR working.

**Stop if**

- The only proposed cutover mechanism is a header-only env-var toggle that leaves the dev route graph reachable in production.
- If that happens, stop and move to an explicit checked-in production config or overlay instead.

### Session 9: Add the Final Phase Gate and Finish Documentation

**Goal**

Treat Phase 6 as complete only when the edge/browser controls are proven and the Phase 5 regression cascade still passes.

**Owner**

`orchestration`

Current implementation status for March 26, 2026:

- Session 9 is implemented in-repo: `./scripts/dev/verify-phase-6-edge-browser-hardening.sh` now proves the checked-in dev/strict CSP split, the local-production route contract, same-origin docs delivery without wildcard CORS, direct auth-edge throttling coverage for `/login`, `/auth/*`, `/logout`, and `/login/oauth2/*`, reruns the Session 3 frontend CSP audit, reruns the Session 7 API rate-limit identity verifier, and then reruns the Phase 5 runtime-hardening cascade. Manual browser-console validation on `/_prod-smoke/` and `/api/docs` still remains open completion work.

**Files**

- `scripts/dev/verify-phase-6-edge-browser-hardening.sh` (new)
- `scripts/dev/verify-phase-3-istio-ingress.sh` if shared assertions are factored there
- nearest affected docs in `docs/`, `README.md`, and `nginx/README.md`
- `docs/plans/security-hardening-v2.md`

**Changes**

- Add a dedicated Phase 6 verifier that proves:
  - relaxed dev CSP is still present where Vite/HMR needs it
  - strict CSP is enforced on the production-smoke/docs routes and does not include `'unsafe-inline'` or `'unsafe-eval'`
  - the documented production route shape serves the built frontend on `/` and `/login` instead of exposing the local Vite route set
  - `/api/docs/openapi.json` and `/api/docs/openapi.yaml` no longer expose wildcard CORS unless an explicit documented allowlist replaced it
  - ingress throttling covers the final auth-edge path set
  - API rate limiting keys on the corrected identity model or has been moved to ingress intentionally
- Re-run [`verify-phase-5-runtime-hardening.sh`](/workspace/orchestration/scripts/dev/verify-phase-5-runtime-hardening.sh) as the regression cascade from the Phase 6 gate.
- Keep browser enforcement honest in the completion criteria: manual browser-console validation remains required unless a separate scoped session adds headless automation and wires it into the verifier.
- Update the operational docs in the same sessions as the changes:
  - `nginx/README.md`
  - `docs/development/local-environment.md`
  - `docs/architecture/bff-api-gateway-pattern.md`
  - `docs/architecture/security-architecture.md` if the edge-responsibility narrative changes

**Verification**

- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh`

## Verification Gate

The Phase 6 completion gate is the verifier:

```bash
./scripts/dev/verify-phase-6-edge-browser-hardening.sh
```

That gate proves:

- the production-smoke/docs routes emit the strict CSP contract
- the default dev route keeps the relaxed CSP required for Vite/HMR
- the production route definition no longer exposes the local Vite/HMR public path set
- `/api/docs` no longer depends on third-party CDN assets or wildcard CORS
- auth-edge ingress throttling covers the final path set for `/login`, `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`, and `/user`
- API rate limiting no longer keys on the proxy hop
- the Phase 5 runtime-hardening gate still passes as the regression cascade

For browser-enforcement validation, do not claim completion based on `curl` alone. Keep an explicit manual browser-console check in the completion criteria for the production-smoke frontend and `/api/docs` unless a separate scoped session adds headless browser automation and wires it into the Phase 6 verifier.

Do not declare Phase 6 complete until that verifier and the browser validation both pass.
