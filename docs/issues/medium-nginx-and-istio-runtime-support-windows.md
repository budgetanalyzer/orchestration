# NGINX runtime line is past support end

- **Severity:** Medium
- **Owner:** orchestration (NGINX gateway manifest); budget-analyzer-web (frontend Dockerfile base image)
- **Status:** Open
- **Source:** 2026-11-09 implementation review, existing open items; closeout open findings

## Problem

`./scripts/repo/report-runtime-support-windows.sh` flags one selected runtime
line (as of 2026-11-16):

- **NGINX 1.29: `PAST`.** Mainline 1.29 ended when 1.30.0 stable was
  released. Fixes ship only in 1.30 stable and 1.31 mainline. It is selected in
  `kubernetes/services/nginx-gateway/deployment.yaml` and in the
  `budget-analyzer-web` Dockerfile base image.

## Impact

NGINX is the API gateway on every request path and the production frontend
server. An unsupported line receives no security fixes.

## Proposed fix

Follow the quarterly routine in
`docs/dependency-automation.md#operator-routine`:

- Move the NGINX gateway and the frontend base image to a supported NGINX line,
  keeping the digest pin and `linux/arm64` support.
- Update the NGINX row in `scripts/lib/runtime-support-windows.txt`.

## Acceptance

- `./scripts/repo/report-runtime-support-windows.sh` does not flag NGINX.
- The static security suite, `verify-production-image-overlay.sh` and the
  local Tilt edge verifiers pass on the new line.
