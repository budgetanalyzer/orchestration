# Phase 6 Session 3: Frontend CSP Audit Under the Smoke Path

## Status

Static stop-gate audit implemented on March 25, 2026 in `orchestration`.

This session is intentionally **not** the strict-CSP enforcement change. It is
the coordinated prerequisite audit that proves whether the sibling frontend is
still blocking that enforcement.

As of March 26, 2026, the static prerequisite is satisfied: the sibling
frontend no longer uses JSX inline style props in production code paths, no
longer imports `sonner`, and the repo-owned audit now passes. Manual
browser-console validation is still required before Phase 6 can be declared
complete.

## Repeatable audit command

Run the repo-owned stop-gate with:

```bash
./scripts/dev/audit-phase-6-session-3-frontend-csp.sh
```

The script:

- rebuilds the sibling production-smoke bundle with `npm run build:prod-smoke`
- confirms the built HTML still references same-origin `/_prod-smoke/assets/*`
- checks the built bundle for literal `eval(` and `new Function` tokens
- fails if the frontend source still contains JSX inline `style={...}` props
- fails if the frontend still imports `sonner` and that package path still pulls runtime CSS injection into the bundle

Manual browser-console validation is still required by the Phase 6 plan. This
script only makes the repo-owned static audit repeatable.

## Findings

### 1. The smoke bundle builds cleanly and stays same-origin

- The March 26, 2026 audit still shows `npm run build:prod-smoke` succeeding in
  the sibling repo.
- `dist/index.html` loads `/_prod-smoke/assets/index-*.js` and `/_prod-smoke/assets/index-*.css`, so the smoke path is still a valid same-origin verification seam.

### 2. No obvious `unsafe-eval` dependency was found in the built bundle

- The March 26, 2026 audit found no literal `eval(` or `new Function` tokens in `dist/`.
- That does **not** prove the full browser CSP story by itself, but it means the current stop-gate is dominated by style-policy blockers rather than an obvious eval dependency.

### 3. The inline-style blocker has been removed from the sibling frontend

- The repo-owned audit now checks only JSX/TSX sources for `style={{ ... }}`
  usage, which removes the earlier false positive from comments in helper
  utilities.
- The current sibling source tree no longer contains JSX inline style props in
  production code paths, so the strict `style-src 'self'` prerequisite is
  satisfied at the static-audit level.

### 4. The `sonner` blocker has been removed from the sibling frontend

- The current sibling source tree no longer imports `sonner`.
- The stop-gate now handles the package being absent from `node_modules`
  cleanly instead of treating that removal as a script failure.
- The built smoke bundle no longer exposes the prior `sonner` runtime CSS
  insertion markers checked by the audit.

## Remaining requirement before program-level closure

Manual browser-console validation is still required on `/_prod-smoke/` under the
enforced strict policy. The static audit is a prerequisite proof, not a browser
enforcement proof.

## Stop-gate outcome

Phase 6 Session 3 is **implemented in orchestration as a stop-gate**, and the
repo-owned static prerequisite now passes. Session 4 can enforce the strict
production CSP split, but Phase 6 still requires manual browser-console
validation before the broader hardening program can be called complete.
