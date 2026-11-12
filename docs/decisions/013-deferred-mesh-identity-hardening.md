# 013. Deferred Mesh Identity Hardening: Signed Identity, Internal Ports and Per-Caller Egress

**Date:** 2026-11-05
**Status:** Accepted
**Deciders:** Architecture Team

## Context

Three recommendations from the 2026-11-01 security reviews strengthen
workload identity beyond the current mesh. Each needs coordinated
cross-service design. The 2026-11-05 contested-issues review deferred all three
(items 7, 8 and 9). This record captures the deferral, its reasoning and when
to reopen it. It was written on 2026-11-12, after the hardening plans closed.

**Signed identity context.** `ext_authz` rebuilds `X-User-Id`, `X-Roles` and
`X-Permissions` from Redis, and NGINX forwards them. service-common's
claims-header authentication builds the Spring principal from those headers
after structural validation, without a signature. The mesh authenticates which
workload may call a backend, not where each claim inside the request came from.
One review required ext-authz-signed tokens before any real data. Another
deferred them because the observed failure was routing, not forgery. A third
rejected an unconditional prerequisite and asked for a threat model.

**Separate internal ports.** Session Gateway serves its public controllers and
its internal bulk-revocation endpoint on port 8081. permission-service likewise
serves internal routes beside public ones. One review proposed separate
internal listeners, on the grounds that port rules cannot be fooled by path
tricks. Others said that mesh path rules plus `;` rejection close the finding,
and that a new port isolates nothing unless the public listener no longer
serves the internal handlers.

**Per-caller egress.** `kubernetes/istio/egress-routing.yaml` uses a
PASSTHROUGH TLS listener with SNI routing, and the workload-to-gateway
DestinationRule uses `tls.mode: DISABLE`. So the egress gateway carries the
application's TLS without learning the caller's mesh identity. NetworkPolicy
admits only Session Gateway and currency-service, but it does not pair each
caller with its permitted destination. One review called switching to
`ISTIO_MUTUAL` a one-setting fix. That fails with the passthrough listener,
because mesh TLS hides the original SNI.

## Decision

Defer all three. Do not adopt them as prerequisites for current local
development or the offline production reference.

1. **Signed identity:** Keep claims-header trust. Record that a compromised
   allowed intermediary, such as NGINX, can forge or replay claims. If that
   threat becomes a requirement, only `ext_authz` may hold the signing key.
   Backends would then validate issuer, audience, expiry and key rotation.
   Shared signing keys in NGINX would defeat the purpose. The design must also
   address replay and request binding.
2. **Separate internal ports:** Keep one listener per service, and enforce
   internal access with mesh caller, method and path rules
   ([ADR 012](012-shared-nginx-routes-and-path-hardening.md)). If separate
   listeners are adopted later, the internal handlers must be absent from the
   public listener, and Service, mesh and NetworkPolicy rules must restrict the
   internal one.
3. **Per-caller egress:** Treat it as one coordinated design, not a
   DestinationRule mode change. It covers listener termination, routing, peer
   authentication and caller-to-destination authorization, while keeping
   end-to-end validation of external certificates. Istio's nested-TLS pattern
   shows this is feasible. Separate listeners per fixed destination are a
   simpler option. Keep private-range egress exclusions as independent
   containment.

Revisit when any of these happens:

- hosted deployment planning starts;
- a backend gains direct exposure;
- the compromise model changes to include an allowed intermediary;
- a full-chain test exposes a path ambiguity that the current rules do not
  resolve;
- an independently enforceable listener or egress boundary becomes a
  threat-model requirement.

## Alternatives Considered

### Alternative 1: Require ext-authz-signed identity before handling real data
**Pros:**
- Backends could reject claims that NGINX or another intermediary forged.

**Cons:**
- Needs key management, rotation and validation in every backend.
- A signature alone is still replayable by an intermediary that sees it, and
  it does not bind method or body.
- It does not protect internal endpoints outside the validating chain.

### Alternative 2: Separate internal ports now
**Cons:**
- No isolation while the handler stays reachable on the original port.
- The evidence did not require a listener redesign once mesh paths were
  narrowed.

### Alternative 3: Switch the egress DestinationRule to `ISTIO_MUTUAL`
**Cons:**
- Hides the SNI that the passthrough listener routes on. It is not a complete
  fix without listener and authorization changes.

## Consequences

**Positive:**
- The hardening work stayed on exploitable, evidenced gaps rather than
  speculative redesigns.
- Each deferral has an explicit reopen condition and a minimum design
  requirement.

**Negative:**
- A compromised allowed intermediary can forge identity headers for any user.
  This is an accepted residual risk.
- Internal and public handlers share a listener. Isolation depends on mesh path
  rules and on correct normalization.
- The egress gateway bounds where it connects, not which caller it serves. Any
  admitted caller can reach either approved external host.

**Neutral:**
- service-common's claims-header options document holds the detailed signing
  options and remains undecided.

## References
- [Security Architecture: Mesh Public/Internal Boundary](../architecture/security-architecture.md#mesh-publicinternal-boundary)
- [Security Architecture: Executive Summary](../architecture/security-architecture.md#executive-summary) (egress containment)
- [service-common: Claims-Header Trust Hardening Options](https://github.com/budgetanalyzer/service-common/blob/main/docs/plans/claims-header-trust-hardening-options.md)
- [ADR 012: Shared NGINX Route Includes, Narrow Mesh Paths and Semicolon Rejection](012-shared-nginx-routes-and-path-hardening.md)
- `kubernetes/istio/egress-routing.yaml`
- [Istio egress with nested TLS](https://istio.io/latest/blog/2023/egress-sni/)
- Source: 2026-11-05 contested-issues security review, items 7, 8 and 9. The
  record was deleted after this ADR was written; see Git history.
