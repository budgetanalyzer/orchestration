# Backend responses carry two conflicting X-Frame-Options headers

- **Severity:** Low
- **Owner:** orchestration (NGINX edge owns frame policy)
- **Status:** Open. The closeout evidence recorded it as "not investigated."
- **Source:** 2026-11-09 implementation review, existing open items; independent implementation review C7

## Problem

Closeout observed `X-Frame-Options: DENY` and `SAMEORIGIN` on the same backend
response.

- The backends' Spring Security defaults send `DENY`.
- NGINX adds `add_header X-Frame-Options "SAMEORIGIN" always;` at line 2 of
  `nginx/includes/security-headers-{strict,dev,docs}-csp.conf`, included at
  server level.
- `add_header` does not replace upstream headers, so both values are sent.

## Impact

None in practice. Browsers ignore conflicting XFO values, and the same
includes send CSP `frame-ancestors 'self'`, which modern browsers prefer.
Affected responses are JSON.

## Proposed fix

Add `proxy_hide_header X-Frame-Options;` to
`nginx/includes/backend-headers.conf` so the edge owns frame policy in one
place. Do not change Spring defaults in service-common for this.

## Acceptance

- A backend API response through NGINX carries exactly one
  `X-Frame-Options: SAMEORIGIN`.
- The local and production NGINX configs both pick up the change through the
  shared include.
