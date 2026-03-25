# Phase 6: Edge and Browser Hardening - Implementation Plan

## Context

Phase 5 completed on March 25, 2026 with the expanded runtime-hardening gate passing `175/175`. Phase 6 starts from a materially stronger cluster baseline, but the edge and browser posture still has six concrete gaps:

- `nginx/nginx.k8s.conf` currently serves one server-wide CSP that still allows both `'unsafe-inline'` and `'unsafe-eval'`.
- `docs-aggregator/index.html` is not compatible with a strict self-only CSP today. It contains inline `<style>` and `<script>` blocks and pulls Swagger UI assets from `https://unpkg.com`.
- The local stack still runs the frontend through the Vite dev server from `../budget-analyzer-web/Dockerfile`. There is no checked-in production-bundle smoke path in this repo yet, so a strict production CSP cannot be validated honestly by tightening headers on the dev route alone.
- `kubernetes/istio/ingress-rate-limit.yaml` currently throttles `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`, and `/user`, but not bare `/login` or other `/login/*` paths.
- `nginx/nginx.k8s.conf` still keys `limit_req_zone` on `$binary_remote_addr` without any trusted-proxy `real_ip_*` handling, so API buckets are based on the proxy hop instead of a proven client identity.
- `/api/docs/openapi.json` and `/api/docs/openapi.yaml` still return `Access-Control-Allow-Origin: *` even though the shared docs UI is same-origin.

Phase 6 therefore cannot start by flipping a stricter CSP globally. The production verification seam has to exist first, and the known docs/CSP blockers have to be removed before enforcement is credible.

## Recommended Direction

Use the following implementation strategy unless new evidence proves it wrong:

1. Add a repeatable production-smoke frontend path first so strict CSP can be verified against built assets without breaking Vite/HMR.
2. Make `/api/docs` self-contained and CSP-compatible before touching the enforced production header.
3. Keep the default dev route on the relaxed Vite-compatible CSP.
4. Keep API rate limiting in NGINX only if trusted client identity can be proven there. If not, move public API rate limiting to ingress instead of guessing.

## Target State

Phase 6 is complete when all of the following are true:

- Development routes keep the relaxed CSP required for Vite and HMR.
- A production-oriented frontend/docs path emits a strict enforced CSP with no `'unsafe-inline'` and no `'unsafe-eval'`.
- `/api/docs` works without wildcard CORS and without third-party CDN script/style dependencies.
- Auth-edge throttling at Istio ingress covers the intended auth surface, including the `/login` entry point decision from this phase.
- Public API rate limiting keys on a trustworthy client identity rather than the proxy hop.
- A dedicated Phase 6 gate proves the headers, throttling, and identity handling, and re-runs the Phase 3 ingress verifier as a regression.

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

**Files**

- `Tiltfile`
- `kubernetes/services/nginx-gateway/deployment.yaml` only if extra static asset mounts are needed
- `docs-aggregator/` only if the smoke assets are mounted through the existing docs ConfigMap path
- `../budget-analyzer-web/vite.config.ts`
- `../budget-analyzer-web/package.json`
- `../budget-analyzer-web/Dockerfile` or a new production/smoke Dockerfile if the current dev image remains Vite-only

**Changes**

- Add a production-build smoke path that serves a built frontend bundle under the same public origin without replacing the current dev route.
- Recommended first choice: serve the smoke bundle under a dedicated path such as `/_prod-smoke/` so no new hostname or certificate work is required.
- Build that bundle with an explicit Vite `base` that matches the chosen smoke path.
- Keep the current `/` and `/login` dev experience on Vite/HMR so inner-loop development does not regress during Phase 6.
- Document clearly that the smoke path exists only to validate production-browser policy and should not become a second long-term frontend mode with different behavior.

**Verification**

- The smoke bundle builds reproducibly from the sibling repo.
- `curl -k https://app.budgetanalyzer.localhost/_prod-smoke/` returns `200`.
- The smoke page loads its JS/CSS assets from the same origin and path prefix.
- The default dev route still serves the existing Vite application with HMR.

**Stop if**

- The frontend cannot be served under a subpath without breaking routing or asset resolution.
- If that happens, use a dedicated verification port/service instead of faking production validation on the dev route.

### Session 2: Make `/api/docs` Strict-CSP Compatible

**Goal**

Remove the orchestration-owned blockers that would make a strict production CSP fail immediately on the shared docs page.

**Owner**

`orchestration`

**Files**

- `docs-aggregator/index.html`
- `docs-aggregator/README.md`
- `docs-aggregator/` pinned local Swagger UI assets or an equivalent checked-in asset-update flow
- `Tiltfile`

**Changes**

- Remove inline `<style>` and inline `<script>` from `docs-aggregator/index.html`.
- Stop loading Swagger UI assets from `https://unpkg.com`.
- Vendor or otherwise pin the Swagger UI assets locally so `/api/docs` can run under `script-src 'self'` and `style-src 'self'`.
- Keep the docs UI same-origin. Do not introduce a cross-origin docs hosting pattern just to keep the old page structure.
- Remove debug logging from the docs bootstrap if it no longer adds operational value.

**Verification**

- `/api/docs` renders with only same-origin JS/CSS requests.
- Browser developer tools show no network dependency on `unpkg.com`.
- The docs selector still loads the service OpenAPI specs through the public gateway path.

**Stop if**

- The chosen Swagger asset approach requires an unreviewable or drifting download path.
- If that happens, add a pinned asset-refresh script and keep the generated/static assets reviewable in-repo.

### Session 3: Audit and Fix Frontend CSP Violations Under the Smoke Path

**Goal**

Use the new production-smoke path to find the real frontend blockers before the strict production CSP is enforced.

**Owner**

`budget-analyzer-web` prerequisite, coordinated from this repo

**Files**

- `../budget-analyzer-web/src/**/*`
- `../budget-analyzer-web/index.html`
- `../budget-analyzer-web/vite.config.ts`
- nearest affected docs in `../budget-analyzer-web/README.md` or sibling docs as needed

**Changes**

- Run the built frontend under a strict candidate CSP and capture the actual violations instead of guessing.
- Start with likely hot spots:
  - inline-style call sites currently visible in `EditableTransactionRow.tsx`, `TransactionTable.tsx`, `ViewTransactionTable.tsx`, and `YearSelector.tsx`
  - any runtime-generated style/script behavior that only appears in the production bundle
- Remove or rework any frontend pattern that requires `'unsafe-inline'` or `'unsafe-eval'` in production.
- Do not use nonce/hash exceptions as a casual shortcut for application code. The target state for the production app is a clean strict policy, not a patchwork of exceptions.

**Verification**

- The production-smoke frontend loads and navigates without CSP console violations.
- Login flow initiation from the smoke frontend still reaches `/oauth2/authorization/idp`.
- If a browser-based automated check is available, use it here. If not, keep manual browser console validation as an explicit gate instead of pretending `curl` proves browser enforcement.

**Stop if**

- A third-party dependency requires eval or inline behavior in production and no supported strict-CSP path exists.
- If that happens, stop and decide explicitly whether the dependency must be replaced or the route needs a documented exception.

### Session 4: Wire the Dev/Production CSP Split into NGINX

**Goal**

Move from one global dev-grade CSP to an explicit split between relaxed development behavior and strict production-oriented behavior.

**Owner**

`orchestration`

**Files**

- `nginx/nginx.k8s.conf`
- `nginx/includes/` new CSP include files if the config is split there
- `Tiltfile` only if config assembly changes
- `nginx/README.md`
- `docs/development/local-environment.md`

**Changes**

- Factor the CSP policy out of the single server-level header so dev and production-oriented routes can differ intentionally.
- Keep the relaxed policy on the default Vite/HMR development routes.
- Apply the strict enforced policy to:
  - the production-smoke frontend path from Session 1
  - `/api/docs` once Session 2 is complete
- Use `Content-Security-Policy-Report-Only` temporarily only if it materially helps close violations in the same session. Do not leave report-only as the final posture.
- Make the final strict production policy explicit in the docs. It should remove both `'unsafe-inline'` and `'unsafe-eval'`.

**Verification**

- `curl -kI` shows different CSP headers for the dev route and the production-smoke/docs routes.
- The default dev frontend still keeps HMR working.
- The strict routes do not silently inherit the relaxed development CSP.

**Stop if**

- The config split becomes dependent on ad-hoc manual patching or undocumented environment mutation.
- If that happens, move to explicit checked-in config variants or includes rather than hidden runtime templating.

### Session 5: Remove Wildcard CORS from Docs Assets

**Goal**

Delete the unnecessary `Access-Control-Allow-Origin: *` exposure from the OpenAPI download endpoints.

**Owner**

`orchestration`

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

**Files**

- `nginx/nginx.k8s.conf`
- `nginx/includes/backend-headers.conf` only if header handling changes
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- new Phase 6 verifier in `scripts/dev/`
- `nginx/README.md`

**Changes**

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

### Session 8: Add the Final Phase Gate and Finish Documentation

**Goal**

Treat Phase 6 as complete only when the edge/browser controls are proven and the ingress regressions still pass.

**Owner**

`orchestration`

**Files**

- `scripts/dev/verify-phase-6-edge-browser-hardening.sh` (new)
- `scripts/dev/verify-phase-3-istio-ingress.sh` if shared assertions are factored there
- nearest affected docs in `docs/`, `README.md`, and `nginx/README.md`
- `docs/plans/security-hardening-v2.md`

**Changes**

- Add a dedicated Phase 6 verifier that proves:
  - relaxed dev CSP is still present where Vite/HMR needs it
  - strict CSP is enforced on the production-smoke/docs routes and does not include `'unsafe-inline'` or `'unsafe-eval'`
  - `/api/docs/openapi.json` and `/api/docs/openapi.yaml` no longer expose wildcard CORS unless an explicit documented allowlist replaced it
  - ingress throttling covers the final auth-edge path set
  - API rate limiting keys on the corrected identity model or has been moved to ingress intentionally
- Re-run [`verify-phase-3-istio-ingress.sh`](/workspace/orchestration/scripts/dev/verify-phase-3-istio-ingress.sh) as a regression from the Phase 6 gate.
- Update the operational docs in the same sessions as the changes:
  - `nginx/README.md`
  - `docs/development/local-environment.md`
  - `docs/architecture/bff-api-gateway-pattern.md`
  - `docs/architecture/security-architecture.md` if the edge-responsibility narrative changes

**Verification**

- `./scripts/dev/verify-phase-6-edge-browser-hardening.sh`

## Verification Gate

The Phase 6 completion gate should be a new verifier:

```bash
./scripts/dev/verify-phase-6-edge-browser-hardening.sh
```

That gate is expected to prove:

- the production-smoke/docs routes emit the strict CSP contract
- the default dev route keeps the relaxed CSP required for Vite/HMR
- `/api/docs` no longer depends on third-party CDN assets or wildcard CORS
- auth-edge ingress throttling covers the final path set for `/login`, `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`, and `/user`
- API rate limiting no longer keys on the proxy hop
- the Phase 3 ingress gate still passes as a regression

For browser-enforcement validation, do not claim completion based on `curl` alone. Either automate the browser check or keep an explicit manual browser-console check in the completion criteria for the production-smoke frontend and `/api/docs`.

Do not declare Phase 6 complete until that verifier and the browser validation both pass.
