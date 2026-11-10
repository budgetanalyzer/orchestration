# CSP form-action and the IdP logout URL override are not linked

- **Severity:** Low
- **Owner:** session-gateway docs; orchestration CSP docs
- **Status:** Open
- **Source:** [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  C8

## Problem

CSP `form-action` allows only the issuer origin
(`deploy/scripts/render/render-csp.py`). Session Gateway's logout URL defaults
to the issuer, but `IDP_LOGOUT_URL_TEMPLATE` can override it
(`../session-gateway/src/main/resources/application.yml:92`).

If the override points to a different origin, the logout form POST and 303
redirect to the IdP would be blocked by CSP. Nothing checks that the two
agree.

No orchestration manifest sets `IDP_LOGOUT_URL_TEMPLATE` today, so this is a
latent constraint, not a current break.

## Proposed fix

Document the constraint next to the override in session-gateway, and in the
orchestration doc that owns the CSP renderer. Add a check only if
orchestration ever starts setting the override.

## Acceptance

Both docs state that a logout URL override must stay on the issuer origin,
or the CSP must be updated to match.
