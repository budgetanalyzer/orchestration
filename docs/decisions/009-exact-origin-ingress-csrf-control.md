# 009. Exact-Origin Ingress Rule as the Primary CSRF Control

**Date:** 2026-11-05
**Status:** Accepted
**Deciders:** Architecture Team

## Context

The browser credential is a session cookie that every browser request carries
automatically. Its configured `SameSite=Strict` default keeps it off cross-site
requests, but not off same-site cross-origin requests, such as a form on a
sibling `*.budgetanalyzer.localhost` host. Strict also does not stop a
top-level response from clearing the cookie. Before this decision:

- Session Gateway disabled Spring Security CSRF, and nothing else checked the
  request origin.
- The `ext_authz` provider did not forward `Origin` or `Sec-Fetch-Site`, and its
  `CUSTOM` policy covered only `/api/*`. OAuth, `/auth/*` and `/logout` reach
  Session Gateway directly.
- Heartbeat (`GET /auth/v1/session`, from ADR 007) refreshed stored
  authorization through a GET.
- Logout was a GET that cleared the cookie even when none arrived, and
  redirected to the IdP.

The 2026-11-01 security reviews disagreed on the remedy. One proposed CSRF
tokens plus exact-origin checks. Another proposed `Sec-Fetch-Site` in
`ext_authz`, with `Origin` as fallback. A third proposed Fetch Metadata with no
tokens, allowing requests that carry neither header. The fourth required both
lanes to be covered and missing headers to be specified rather than waived.
The 2026-11-05 contested-issues review settled it. Hardening plans 02.7 and
02.8 implemented the result. This record was written on 2026-11-12, after
implementation.

This decision supersedes the `GET /auth/v1/session` heartbeat method in
ADR 007. The rest of ADR 007 still stands.

## Decision

1. **One exact-Origin rule at the shared ingress.** A native Istio `DENY`
   AuthorizationPolicy on the ingress gateway, restricted to the browser
   application host, denies every method other than `GET`, `HEAD` and
   `OPTIONS` unless `Origin` is exactly the configured serialized application
   origin. Absent, empty, `null`, foreign, suffixed and repeated values fail
   closed. The trusted value is fixed in the policy, never derived from `Host`
   or forwarding headers. Fetch Metadata grants no exception.
2. **Both lanes.** The NGINX `/api/*` lane and the direct Session Gateway lane
   share the host, so one policy covers both. No Go or Java Origin check is
   added.
3. **No unsafe GETs.** Heartbeat moves to `POST /auth/v1/session`. Logout is a
   same-origin top-level form `POST /logout` that returns a
   server-constructed `303` to the IdP logout URL. `GET` and `HEAD` on both
   return `405` without side effects. One frontend helper serves all logout
   callers.
4. **CSP `form-action`** allows `'self'` plus the environment's exact HTTPS
   IdP origin, so the logout redirect works without a wildcard.
5. **Scope.** The rule is CSRF provenance for the cookie credential, not
   authentication. Requests carrying `Authorization` get no exemption on the
   application host. A future machine-to-machine API belongs on its own
   hostname with a non-cookie credential, outside this rule.

The OAuth callback stays a top-level `GET` protected by browser binding
([ADR 010](010-oauth-callback-browser-binding.md)), not by this rule.

[Exact-Origin Ingress Rule](../architecture/session-edge-authorization-pattern.md#exact-origin-ingress-rule)
owns the current behavior, rejected cases, verifiers and callers.
[Content Security Policy Posture](../architecture/security-architecture.md#content-security-policy-posture)
owns `form-action`.

## Alternatives Considered

### Alternative 1: Synchronizer or double-submit CSRF tokens
**Pros:**
- Independent of browser header behavior.

**Cons:**
- Needs token issuance, storage and validation on both lanes, across Go and
  Java.
- Adds nothing over an exact-Origin check for a single-origin application whose
  supported browsers always send `Origin` on these requests.

### Alternative 2: Fetch Metadata (`Sec-Fetch-Site`) as the main control, `Origin` as fallback
**Pros:**
- Expresses same-origin, same-site and cross-site directly.

**Cons:**
- Two rules with different missing-header semantics. One proposal allowed
  requests that carry neither header, which weakens the control.
- Would require forwarding new headers to `ext_authz` and adding a separate
  check on the Session Gateway lane.

### Alternative 3: Origin checks inside `ext_authz` and Session Gateway
**Pros:**
- Each service enforces its own lane.

**Cons:**
- Two implementations of one contract in two languages, which can drift.
- `ext_authz` does not see the auth lane at all.

### Alternative 4: A permissive `ALLOW` policy for the configured origin
**Cons:**
- Istio `ALLOW` policies are additive, so another `ALLOW` would reopen access.
  A `DENY` cannot be widened by a later policy.

### Alternative 5: Change GET to POST only
**Cons:**
- A hostile cross-origin form can still submit a POST.

## Consequences

**Positive:**
- One declarative control covers both browser lanes and is checked statically
  against the local and production renders.
- A hostile form `POST /logout` gets the ingress `403` with no `Set-Cookie`, so
  cross-site logout by navigation is closed.
- No token state, and no per-service CSRF code.

**Negative:**
- Correctness depends on the mesh keeping browsers from reaching NGINX or
  Session Gateway except through the ingress.
- Correctness depends on browsers sending `Origin`. A form POST under a
  `no-referrer` policy sends `null`, so the referrer policy must stay
  `strict-origin-when-cross-origin` or similar.
- Non-browser clients, the API tests and verifiers among them, must send the
  configured `Origin` on unsafe methods.
- A future safe-method response that clears the session cookie would reopen
  cross-site logout by navigation.
- `form-action` couples the CSP to the IdP logout origin. See
  [`low-csp-form-action-logout-url-coupling`](../issues/low-csp-form-action-logout-url-coupling.md).
- Strict CSP redirect behavior was verified only in Chromium.

**Neutral:**
- A future POST OAuth callback would need an explicit contract change.

## References
- [Session Edge Authorization: Exact-Origin Ingress Rule](../architecture/session-edge-authorization-pattern.md#exact-origin-ingress-rule)
- [Security Architecture: Threat Mitigation](../architecture/security-architecture.md#threat-mitigation)
- [ADR 007: Browser-Only Session Gateway](007-browser-only-session-gateway.md), whose GET heartbeat this changes
- [ADR 010: OAuth Callback Browser Binding](010-oauth-callback-browser-binding.md)
- `kubernetes/istio/ingress-exact-origin.yaml`
- [Fetch standard: `Origin` header](https://fetch.spec.whatwg.org/#origin-header)
- [Istio AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
- Source: 2026-11-05 contested-issues security review, item 1. The record was
  deleted after this ADR was written; see Git history.
