# Two python3 calls run without isolated mode

- **Severity:** Low
- **Owner:** orchestration
- **Status:** Open
- **Source:** 2026-11-09 independent implementation review C8

## Problem

These calls invoke `render-csp.py` with plain `python3`:

- `deploy/scripts/render/production-routes.sh:77`
- `scripts/smoketest/verify-edge-browser-hardening.sh:624`

The Tiltfile and the other new call sites use `python3 -I`, which ignores
`PYTHON*` environment variables and user site-packages, and does not put the
script's directory on `sys.path`.

`render-csp.py` imports only the standard library, so adding `-I` is safe.

## Proposed fix

Add `-I` to both calls.

## Acceptance

- Both call sites use `python3 -I`.
- The production route render and the edge browser hardening verifier still
  pass.
- `bash -n` and `shellcheck` are clean.
