# 010. OAuth Callback Browser Binding and Single-Consumer State

**Date:** 2026-11-05
**Status:** Accepted
**Deciders:** Architecture Team

## Context

Session Gateway stores each pending OAuth authorization request, including its
PKCE verifier and nonce, in Redis under `oauth2:state:<state>`. Before this
decision the callback found the record from the `state` query parameter alone.
Nothing tied the record to the browser that started login. Removal read and
then deleted the record, without requiring the delete to succeed, so concurrent
callbacks could each obtain the same request.
[RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1) requires
transaction-specific PKCE and nonce material to be bound to the initiating user
agent. The IdP's single-use authorization code does not provide that binding and
does not make the local record single-consumer.

All four 2026-11-01 security reviews agreed that a correlation cookie was
needed. They differed on atomic consumption. One called it hygiene, because the
IdP rejects a reused code. Another required it and noted that `MULTI` around an
earlier read is not atomic. They also differed on whether parallel login tabs
need per-transaction cookies. The 2026-11-05 contested-issues review settled
it, and hardening plans 02.1 and 02.2 implemented it. This record was written
on 2026-11-12, after implementation.

## Decision

1. **One reusable browser-binding cookie.** Login initiation reuses a valid
   high-entropy `__Host-BA_OAUTH_BINDING` cookie, or creates one. It is
   `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/`, with no `Domain` and a
   browser-session lifetime. It is not the session token and cannot be derived
   from `state`. It survives callback completion so parallel tabs share it.
2. **Hash stored with immutable state.** Each state record stores the binding's
   SHA-256 hash next to its own random state, PKCE verifier and nonce. Records
   are write-once, never reused or recreated, and keep their short TTL.
3. **Validate, then single-winner delete.** The callback reads the record and
   compares the binding hash in constant time. Only then does it delete that
   exact key, and it proceeds only if `DEL` returns `1`. A return of `0`, a
   Redis error, or a missing, malformed, duplicate or wrong binding fails
   closed. This runs before code exchange and session issuance, and also on
   the IdP error callback. A wrong binding never reaches deletion, so it cannot
   consume the legitimate browser's state.
4. **No Lua and no `GETDEL` format change.** Because records are immutable, a
   non-atomic compare followed by a counted `DEL` has exactly one winner. If
   records ever become replaceable, use an atomic compare-and-delete instead.

Session Gateway's
[OAuth Callback Browser Binding](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/security.md#oauth-callback-browser-binding)
and orchestration's
[Session Gateway - Auth Layer](../architecture/session-edge-authorization-pattern.md#session-gateway---auth-layer)
own the current behavior and its live verifier.

## Alternatives Considered

### Alternative 1: A cookie per login transaction
**Pros:**
- Simultaneous first logins in different tabs cannot race on cookie storage.

**Cons:**
- Needs per-tab cookie naming, counting and eviction.
- Solves only a rare UX race that already fails closed.

### Alternative 2: A Lua compare-and-delete, or `GETDEL`
**Pros:**
- Comparison and deletion are one atomic operation.

**Cons:**
- Not needed while state records are immutable.
- `GETDEL` would force a record-format change for no security gain.

### Alternative 3: Rely on the IdP's single-use code
**Cons:**
- Does not bind the transaction to the initiating browser, which is the
  RFC 9700 requirement.
- Does not make the local record single-consumer.

### Alternative 4: Clear or rotate the binding cookie after each callback
**Cons:**
- Invalidates other tabs' pending logins.

## Consequences

**Positive:**
- A leaked or enumerated `state` cannot complete a login from another browser.
  This is what makes Redis key-name visibility of state records acceptable in
  [ADR 011](011-hashed-session-keys-host-cookie-absolute-lifetime.md).
- Exactly one callback wins, with no scripting.
- The cookie is SameSite `Lax`, which suits the top-level `GET` callback.

**Negative:**
- Two simultaneous first logins in a browser without the cookie can set
  different bindings. The tab that loses fails closed and must restart login.
- Losing the cookie invalidates pending callbacks.
- In-flight requests created before the cutover needed a fresh login. No legacy
  state format is accepted.
- One reusable cookie does not bound how many pending state records an
  anonymous client can create. Anonymous OAuth-state growth remains an accepted
  availability exposure, limited by TTL and the ingress login rate limits.

**Neutral:**
- The binding is separate from authenticated-request CSRF, which
  [ADR 009](009-exact-origin-ingress-csrf-control.md) covers. `Lax` does not
  send the cookie on a cross-site POST, so a future POST callback would need an
  explicit contract change.
- The binding cookie alone never authenticates an application request.

## References
- [Session Edge Authorization: Session Gateway - Auth Layer](../architecture/session-edge-authorization-pattern.md#session-gateway---auth-layer)
- [Session Gateway security: OAuth Callback Browser Binding](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/security.md#oauth-callback-browser-binding)
- [Session Gateway: OAuth2 State TTL](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md#oauth2-state-ttl)
- `scripts/smoketest/verify-oauth-browser-binding.py`
- [RFC 9700 §2.1.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1)
- [Redis `DEL`](https://redis.io/docs/latest/commands/del/)
- Source: 2026-11-05 contested-issues security review, item 4. The record was
  deleted after this ADR was written; see Git history.
