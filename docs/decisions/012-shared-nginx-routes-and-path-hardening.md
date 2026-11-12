# 012. Shared NGINX Route Includes, Narrow Mesh Paths and Semicolon Rejection

**Date:** 2026-11-05
**Status:** Accepted
**Deciders:** Architecture Team

## Context

The 2026-11-01 security reviews found two related edge problems.

**Path ambiguity.** Local and production-reference NGINX rewrite
`/api/v1/users/...` into `/permission-service/v1/...`, and neither rejected
`;`. The mesh admitted the NGINX identity on backends without path
restrictions. Backends relied on mesh caller enforcement for their internal
routes. Isolated Envoy 1.38 probes with `normalize_path: true` showed the
parser difference behind the concern:

| Input to Envoy | Path after normalization |
| --- | --- |
| `/permission-service/v1/users/..;/..;/internal/v1/users/u1/authorization` | `/permission-service/internal/v1/users/u1/authorization` |
| `/a/b/..%3b/c` | Unchanged |
| `/a/b/%2e%2e;/c` | `/a/b/..;/c`, so a later hop can collapse it |

So a backend firewall such as Spring's `StrictHttpFirewall` can receive an
already-clean internal path. The reviews disagreed on whether that firewall
stops the attack, whether a failed reproduction justified Low severity, and
whether `;` should be rejected. Nobody reproduced the full
ingress/NGINX/sidecar/Spring chain. The checked-in OpenAPI document declared 29
paths, none containing `;`.

**Route duplication.** The two NGINX configurations carried 11 `/api` and five
`/api-docs` location blocks each. They were identical after stripping comments
and whitespace. One review proposed generating both files from one source,
and an earlier plan proposed a custom parity parser.

The 2026-11-05 contested-issues review settled both (items 3 and 12). Hardening
plan 01 implemented them. This record was written on 2026-11-12, after
implementation.

## Decision

1. **Narrow mesh caller, method and path rules now.** Removing known excess
   authority does not wait for a full exploit reproduction. Backend policies
   admit NGINX only on the exact upstream resource paths that NGINX rewrites
   to, with no version-wide wildcards, under an explicit `default-deny-all`.
   Internal routes stay reachable only by their named callers.
2. **Reject `;` in layers.**
   - An ingress RBAC path filter runs before `ext_authz` and denies a literal
     `;` or `%3b` at any percent-encoding depth before the query string. It
     runs before routing, so it covers the NGINX lane and the direct Session
     Gateway lane, which NGINX does not protect.
   - The shared NGINX include keeps a server-level
     `if ($uri ~ ";") { return 400; }` on the decoded path as a second layer.
   - Matrix-parameter syntax is not supported.
3. **Share route blocks rather than generate or police them.** Every `/api`
   location, both unknown-route rejections and the semicolon rule live once in
   `nginx/includes/api-routes.conf`. The `/api-docs` locations live in
   `nginx/includes/api-docs-routes.conf`. Both NGINX configurations include
   both files. Intentional frontend-serving differences stay in each
   configuration.
4. **Prove the boundary by behavior.** Use static checks and live probes rather
   than a general NGINX parser or a firewall unit test. Probe literal, encoded,
   mixed-case, double-encoded and multi-hop forms on both lanes, and assert
   that internal handlers have no side effects, not just a non-200 response.

[Mesh Public/Internal Boundary](../architecture/security-architecture.md#mesh-publicinternal-boundary)
and [Ingress Path Hardening](../architecture/security-architecture.md#ingress-path-hardening)
own the current rules and verifiers.
[`nginx/README.md`](../../nginx/README.md#includes) owns the include layout,
and [Adding a New Resource Route](../../nginx/README.md#adding-a-new-resource-route)
owns the procedure.

## Alternatives Considered

### Alternative 1: Rely on Spring's `StrictHttpFirewall`, pinned by a test
**Cons:**
- Envoy normalization can collapse `..;` before Spring sees it, so the firewall
  never fires on the attack path.
- A unit test is useful defense in depth, but it does not prove the boundary.

### Alternative 2: Wait for a full-chain reproduction before acting
**Cons:**
- Leaves known excessive mesh authority in place.
- A failed reproduction is "not reproduced", not evidence of safety, and must
  not lower severity on its own.

### Alternative 3: Reject `;` at NGINX only
**Cons:**
- Does not cover the direct Session Gateway lane.

### Alternative 4: Generate both NGINX route files from one source
**Cons:**
- Adds a generator and a build step for 16 small blocks that can simply be
  shared.

### Alternative 5: A custom NGINX parity parser
**Cons:**
- Polices duplication that an include removes. A general NGINX parser is
  costly to maintain for this small route set.

## Consequences

**Positive:**
- Local and production-reference route edits cannot drift.
- A dot-segment traversal inside an allowed prefix is denied by the sidecar on
  the normalized path, whatever NGINX forwards.
- Adding a public resource without its mesh path fails closed with `403`.

**Negative:**
- Every new public resource needs both an NGINX location and a mesh path.
- Clients cannot use matrix parameters. The OpenAPI document supports this, but
  it does not prove compatibility for every client.
- Including servers still supply server-level settings, security headers and
  location precedence, so shared blocks do not guarantee identical behavior.
- A successful finite probe set supports the current configuration. It does not
  prove that future parser or route changes are safe.
- The static mesh guard and path-filter anchor have known gaps. See
  [`medium-static-mesh-guard-misses-additive-allow`](../issues/medium-static-mesh-guard-misses-additive-allow.md)
  and [`info-path-hardening-anchor-not-statically-checked`](../issues/info-path-hardening-anchor-not-statically-checked.md).

**Neutral:**
- Separate internal listeners were considered and deferred. See
  [ADR 013](013-deferred-mesh-identity-hardening.md).

## References
- [Security Architecture: Mesh Public/Internal Boundary](../architecture/security-architecture.md#mesh-publicinternal-boundary)
- [Security Architecture: Ingress Path Hardening](../architecture/security-architecture.md#ingress-path-hardening)
- [NGINX README: includes](../../nginx/README.md#includes)
- [ADR 002: Resource-Based Routing](002-resource-based-routing.md)
- `kubernetes/istio/authorization-policies.yaml`, `kubernetes/istio/ingress-path-hardening.yaml`
- [NGINX `location` matching](https://nginx.org/en/docs/http/ngx_http_core_module.html#location)
- [Istio path normalization](https://istio.io/latest/docs/reference/config/security/normalization/)
- Source: 2026-11-05 contested-issues security review, items 3 and 12. The
  record was deleted after this ADR was written; see Git history.
