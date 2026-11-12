# NGINX and Istio runtime lines are past or near support end

- **Severity:** Medium
- **Owner:** orchestration (NGINX gateway manifest, Istio pins); budget-analyzer-web (frontend Dockerfile base image)
- **Status:** Open
- **Source:** 2026-11-09 implementation review, existing open items; closeout open findings

## Problem

`./scripts/repo/report-runtime-support-windows.sh` flags two selected runtime
lines (as of 2026-11-12):

- **NGINX 1.29: `PAST`.** Mainline 1.29 ended when 1.30.0 stable was
  released. Fixes ship only in 1.30 stable and 1.31 mainline. It is selected in
  `kubernetes/services/nginx-gateway/deployment.yaml` and in the
  `budget-analyzer-web` Dockerfile base image.
- **Istio 1.30: `DUE`.** Upstream expects end of life around 2026-12-01. It is
  selected in `Tiltfile` and `scripts/lib/production-version-contract.sh`.

## Impact

NGINX is the API gateway on every request path and the production frontend
server. An unsupported line receives no security fixes. Istio carries ingress,
`ext_authz`, mesh mTLS and authorization policy, so it must move before its
support ends.

## Proposed fix

Follow the quarterly routine in
`docs/dependency-automation.md#operator-routine`:

- Move the NGINX gateway and the frontend base image to a supported NGINX line,
  keeping the digest pin and `linux/arm64` support.
- Move Istio to a supported line in the Tiltfile and the production version
  contract together.
- Update `scripts/lib/runtime-support-windows.txt` for each changed line.

## Acceptance

- `./scripts/repo/report-runtime-support-windows.sh` flags neither NGINX nor
  Istio.
- The static security suite, `verify-production-image-overlay.sh` and the
  local Tilt edge verifiers pass on the new lines.
