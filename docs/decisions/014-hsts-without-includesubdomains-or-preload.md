# 014. Ingress-Owned HSTS Without `includeSubDomains` or `preload`

**Date:** 2026-11-05
**Status:** Accepted
**Deciders:** Architecture Team

## Context

The browser application and its auth lane are served from
`app.budgetanalyzer.localhost`. The 2026-11-01 security reviews agreed that
the ingress should own `Strict-Transport-Security`. They disagreed on the
flags.

- One review asked for `includeSubDomains`, plus `preload` in production,
  arguing that HSTS also stops a network attacker planting cookies.
- Another said `includeSubDomains` needs an intentional domain policy and that
  preload is not a default prerequisite.

The 2026-11-05 contested-issues review (item 11) checked primary sources:

- Under [RFC 6797 §8.2](https://www.rfc-editor.org/rfc/rfc6797.html#section-8.2),
  `includeSubDomains` on the application host covers its descendants, not
  siblings such as `other.budgetanalyzer.localhost`. So it does not stop
  sibling-domain cookie injection. The host-only `__Host-` session cookie
  ([ADR 011](011-hashed-session-keys-host-cookie-absolute-lifetime.md))
  addresses that.
- Public [preload submission](https://hstspreload.org/#submission-requirements)
  requires the registrable base domain with `includeSubDomains`. The Chromium
  checker rejects automated subdomain submissions. The `preload` token alone
  puts nothing in browsers' lists.
- Spring Security's reactive HSTS writer defaults to one year with
  `includeSubDomains`, but writes only when the application sees an HTTPS
  scheme. Session Gateway could therefore emit a value that differs from, or
  duplicates, the ingress value on the auth lane.

Hardening plan 01 implemented the result. This record was written on
2026-11-12, after implementation.

## Decision

1. Every rule in the app, API and auth HTTPRoutes sets one
   `Strict-Transport-Security: max-age=31536000` response header. The `set`
   filter replaces any upstream value, including Spring's on the auth lane.
2. Use neither `includeSubDomains` nor `preload` by default.
3. Revisit both only with an owned hosted registrable domain, an inventory of
   its descendants and an explicit long-term HTTPS commitment. That is an
   operational choice, not a security prerequisite.

[Ingress Header Ownership](../architecture/security-architecture.md#ingress-header-ownership)
owns the current header and its verifier.

## Alternatives Considered

### Alternative 1: Add `includeSubDomains`
**Cons:**
- Does not cover sibling hosts, so it does not address the cookie-planting
  argument.
- Commits every future descendant host to HTTPS without a domain policy.

### Alternative 2: Add `preload` in production
**Cons:**
- A subdomain cannot be self-submitted, and the token alone has no effect.
- Preload is hard to reverse, and there is no owned hosted domain to commit.

### Alternative 3: Leave HSTS to each upstream
**Cons:**
- Values could be missing, duplicated or conflicting across lanes.
- Spring writes HSTS only when it sees HTTPS, which depends on forwarded-scheme
  handling.

## Consequences

**Positive:**
- One consistent HSTS value on every routed response on both lanes.
- No commitment for hosts the project does not own.

**Negative:**
- Dynamic HSTS does not protect the first visit before a browser learns the
  policy. Only preload membership would.
- Responses generated at the ingress, such as `ext_authz` denials and
  rate-limit replies, may omit HSTS.

**Neutral:**
- The same HTTPRoute filters remove caller-supplied forwarding headers. That
  is a separate control, documented in the same live section.

## References
- [Security Architecture: Ingress Header Ownership](../architecture/security-architecture.md#ingress-header-ownership)
- [ADR 011: Hashed Session Keys, `__Host-` Session Cookie and Absolute Session Lifetime](011-hashed-session-keys-host-cookie-absolute-lifetime.md)
- `kubernetes/gateway/app-httproute.yaml`, `kubernetes/gateway/auth-httproute.yaml`
- [RFC 6797](https://www.rfc-editor.org/rfc/rfc6797.html)
- [HSTS preload submission requirements](https://hstspreload.org/#submission-requirements)
- [Chromium HSTS preload checker](https://github.com/chromium/hstspreload/blob/main/domain.go)
- Source: 2026-11-05 contested-issues security review, item 11. The record was
  deleted after this ADR was written; see Git history.
