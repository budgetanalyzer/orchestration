# Plan: Stateless M2M Edge Authorization

Date: 2026-04-02
Updated: 2026-04-06

Status: Draft

Related documents:

- `docs/architecture/security-architecture.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/m2m-client-authorization.md`
- `docs/decisions/006-session-architecture-rethink.md`
- [`../../../session-gateway/docs/plans/local-session-revocation-and-refresh-token-removal.md`](../../../session-gateway/docs/plans/local-session-revocation-and-refresh-token-removal.md)

## Scope

This plan covers the future stateless bearer-token lane for machine-to-machine and external API
access.

It does not restate Session Gateway's browser-lane cleanup. That service-specific work now lives in
the linked Session Gateway plan and should stay there.

## Session Gateway Dependency

This plan's prerequisites on Session Gateway are now satisfied (as of
2026-04-06, executed via the sibling session-gateway plan
`local-session-revocation-and-refresh-token-removal.md` and recorded in ADR
[`007-browser-only-session-gateway.md`](../decisions/007-browser-only-session-gateway.md)):

- Session Gateway is explicitly browser-only.
- Browser-session validity is local and Redis-based, not Auth0-refresh-based.
- Local bulk revocation exists via
  `DELETE /internal/v1/sessions/users/{userId}`.
- `POST /auth/token/exchange` has been removed.

The remainder of this plan therefore describes a new, independent lane.
It no longer has a blocking precondition on Session Gateway.

## Problem Statement

Two realities currently conflict:

- the deployed edge authorization path is cookie-based for browser traffic
- older docs implied a Redis-backed opaque bearer flow via Session Gateway for M2M/native callers
- future external API access actually needs a stateless bearer-token lane

That old token-exchange story is not a credible target architecture. It mixed browser-session
infrastructure with non-browser traffic and made the edge harder to explain honestly.

## Architectural Decision

The architecture should separate the lanes explicitly:

- browser lane: Istio -> Session Gateway -> Redis session -> ext_authz -> services
- bearer lane: client -> Istio/ext_authz bearer validation -> services

Core rules:

- Session Gateway is not the runtime path for non-browser traffic.
- bearer-authenticated requests do not create Redis sessions
- edge enforcement remains centralized
- bearer-token validation should stay local where possible, using JWT verification with cached JWKS

## Goals

1. Keep the browser architecture honest by treating the Session Gateway plan as the source of truth
   for browser-lane cleanup.
2. Define a future stateless bearer-token lane for M2M and external API traffic.
3. Preserve edge enforcement so backend services do not talk directly to Auth0.
4. Allow future selective external exposure of services such as `currency-service`.
5. Avoid a design that calls Auth0 or Session Gateway on every bearer-authenticated request.

## Non-Goals

- Re-specify Session Gateway browser-session cleanup that already lives in the linked service plan.
- Implement a full external developer platform now.
- Expose every service externally.
- Force Session Gateway back into the hot path for API traffic.
- Keep the old token-exchange shape alive just to preserve stale docs.

## Recommended Direction

Use a separate stateless bearer-token lane for future external API access.

The preferred shape is:

```text
Browser -> Istio -> Session Gateway -> Redis session -> ext_authz -> services

M2M Client -> Auth0 client_credentials (or future native-user bearer token)
           -> Istio/ext_authz bearer-token validation
           -> services
```

Core properties of the recommended direction:

- bearer tokens are validated at the edge
- validation is local where possible, using JWT verification with cached JWKS
- edge code extracts claims and scopes, then forwards normalized internal identity headers
- browser cookie logic and bearer-token logic stay separate

## Why This Direction Wins

- It matches the actual shape of browser traffic versus M2M traffic.
- It avoids fake server-side sessions for stateless clients.
- It avoids putting Session Gateway back into the hot path for every API request.
- It keeps Auth0 integration centralized at the edge without turning every request into a network
  round trip to Auth0.
- It is a more credible showcase for exposing `currency-service` as a standalone API.

## Rejected Approaches

### Reuse `POST /auth/token/exchange` To Create Redis Sessions For M2M

Do not do this. That cleanup belongs to the Session Gateway plan, and the end state should be
removal rather than preservation.

- M2M traffic is not session-oriented.
- it couples service principals to browser-session infrastructure
- it makes the architecture harder to explain honestly

### Route Every M2M API Request Through Session Gateway

Do not do this.

- it reintroduces a BFF-style hot path that the current architecture removed
- it adds latency and an unnecessary scaling bottleneck
- it blurs the browser lane and the API lane again

### Call Auth0 Live On Every M2M Request

Do not do this if local JWT validation is possible.

- it adds latency and an external dependency to every request
- it creates failure modes unrelated to the protected service itself
- it is unnecessary for standard JWT access tokens with JWKS validation

## Decision Points Still Open

### 1. Where JWT Validation Lives

Two plausible options:

- extend `ext_authz` to support both cookie-based browser sessions and bearer JWT validation
- use Istio JWT validation for bearer lanes and keep `ext_authz` focused on header normalization
  and policy checks

Current recommendation:

- prefer one edge decision point if the implementation stays simple
- do not accept a design that performs remote Auth0 calls per request

### 2. External API Surface Shape

Decide whether the future external API should use:

- a dedicated hostname such as `api.<domain>`
- a dedicated path subset on the existing ingress

Recommendation:

- prefer a dedicated hostname or clearly separate route contract so browser concerns and external
  API concerns do not bleed into each other

### 3. Identity Header Contract

The system needs a stable internal contract for bearer-authenticated callers, for example:

- subject
- principal type (`user` vs `client`)
- client ID
- scopes or permissions

The current browser-oriented `X-User-Id` contract is not sufficient by itself for service
principals.

### 4. Authorization Data Model For Service Principals

The current permission-service model is centered on `users`.

A real M2M implementation needs an explicit decision:

- treat service principals as a first-class separate concept
- or deliberately map them into the existing user model with documented constraints

Recommendation:

- do not silently overload human-user semantics onto service principals

## High-Level Change Plan

### Phase 1: Make Current-State Docs Honest

### Work

- point Session Gateway browser-lane cleanup at the linked Session Gateway plan instead of copying
  it here
- remove orchestration-language that implies Redis-backed opaque bearer sessions are implemented
  today
- document that the currently deployed edge is browser-cookie-based for the main application
- keep future bearer-token work described as future architecture until it actually exists

### Rationale

There is no value in repeating service-specific cleanup in two repos. One source of truth is enough.

### Phase 2: Define The Future External Bearer Lane

### Work

- add or update high-level architecture docs for stateless external API access
- define which APIs are candidates for future exposure
- start with `currency-service` as the reference example
- decide whether exposure happens via:
  - the existing ingress on a separate path contract, or
  - a dedicated external API host

### Rationale

The showcase use case is selective external exposure, not a generic M2M story for every internal
route.

### Phase 3: Add Stateless Bearer Validation At The Edge

### Work

- accept `Authorization: Bearer <token>` on the external API lane
- validate bearer tokens at the edge without creating Redis sessions
- use local JWT verification with issuer, audience, and JWKS caching
- normalize claims into internal headers for upstream services

### Rationale

This keeps the bearer lane stateless while preserving centralized enforcement.

### Phase 4: Define The Upstream Identity Contract

### Work

- define the internal headers that upstream services may trust for bearer-authenticated requests
- distinguish browser-user identity from service-principal identity
- decide whether permissions are represented as:
  - raw Auth0 scopes/permissions from the JWT
  - normalized internal permissions derived at the edge

### Rationale

Without an explicit contract, services will infer incompatible meanings from headers such as
`X-User-Id`.

### Phase 5: Decide The Role Of Permission Service

### Work

- decide whether future M2M authorization should rely only on JWT scopes
- or whether service principals also need internal role/permission enrichment
- if internal enrichment is required, define a service-principal model rather than forcing all
  callers through the human-user `users` table shape

### Rationale

This is the main domain-model question once the fake session-based M2M story is gone.

### Phase 6: Route, Rate-Limit, And Secure The External API Lane

### Work

- define ingress routing for the external API lane
- define rate limits that differ from browser/user traffic
- define which headers are forwarded to auth checks
- keep browser session cookies irrelevant to bearer-authenticated requests
- ensure the external lane does not inherit browser-only redirects or heartbeat semantics

### Rationale

The external API lane should behave like an API product, not like a browser application route.

### Phase 7: Verification Strategy

### Work

- add verification that the browser cookie lane still works unchanged after the Session Gateway plan
  lands
- add verification that the external bearer lane validates tokens correctly
- prove that bearer requests do not require Redis sessions
- prove that browser routes still do not accept bearer-only traffic by accident
- verify rate limits and routing separately for browser and external lanes

### Rationale

Once the architecture splits into two auth lanes, the main regression risk is in the boundaries
between them.

## Minimum Honest Outcome

If no M2M implementation is planned soon, the minimum acceptable change set is:

1. reference the linked Session Gateway plan as the source of truth for browser-lane cleanup
2. remove orchestration claims that the current edge validates opaque bearer session tokens
3. describe the future bearer-token edge pattern as design only, not as a fake implemented feature

This is weaker than building the external API lane, but it is honest.

## Recommendation Summary

Recommended next steps, in order:

1. Land the Session Gateway browser-only cleanup tracked in the linked service plan.
2. Make the current orchestration docs truthful about today's cookie-based deployed edge.
3. If future external API access matters, design it as a separate stateless bearer-token lane.
4. Put JWT validation at the edge, not in Session Gateway, and not via live Auth0 calls per
   request.
