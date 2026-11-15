# 019. Structural Caller-Contract Guard for Mesh AuthorizationPolicies

**Date:** 2026-11-15
**Status:** Accepted
**Deciders:** Architecture Team

## Context

The mesh public/internal boundary depends on Istio `AuthorizationPolicy`
resources in `default`. `default-deny-all` makes denial the default, and one
`ALLOW` policy per workload admits its approved callers. Istio `ALLOW`
policies are additive. A request is allowed when any `ALLOW` policy that
applies to the workload matches it. An empty deny-all baseline therefore does
not stop a broad `ALLOW` added later.

The static gate's check was an inline Python block in
`verify-static-security-manifests.sh`. It read only
`kubernetes/istio/authorization-policies.yaml` and checked two things:

1. `default/default-deny-all` exists and has an empty spec.
2. Rules that admit the `nginx-gateway` principal on a hardcoded
   `BACKEND_APPS` tuple restrict paths without service- or version-wide
   wildcards.

It skipped selectorless or namespace-wide `ALLOW` policies, rules with no
`from` or with other principals, the Session Gateway, `ext-authz` and
`nginx-gateway` policies, policy files other than that one, and any new
backend. Review reproduced two mutations that passed it:

- a `default` namespace `ALLOW` with no selector and `rules: [{}]`;
- `session-gateway-policy` with `to` removed from its ingress rule.

The checked-in policies did not grant this access. The gap was in
verification, not in the deployed boundary.

## Decision

Replace the inline block with a structural caller-contract guard,
`scripts/guardrails/verify-mesh-authorization.py`. The shell gate calls it as
an adapter. It is not an Istio request simulator.

- **Every granting branch is checked.** Each additional policy, each rule,
  each `from` alternative, each principal and each `to` alternative must fit
  an explicit contract. Each rule needs a non-empty `from`, and each `from`
  alternative needs explicit, non-wildcard `source.principals`. Each principal
  must be an approved caller of every workload that the policy selects. Each
  `to` alternative must satisfy the contract of every approved principal in
  the rule. There is no first-match shortcut.
- **Small explicit caller table.** The table covers ingress to `nginx-gateway`
  and `ext-authz` (caller-only), `nginx-gateway` to the local frontend
  (caller-only), ingress to the Session Gateway auth surface,
  `permission-service` to Session Gateway revocation, Session Gateway to the
  two internal `permission-service` pairs, `nginx-gateway` to backends with
  restricted paths, and Prometheus to Spring Boot metrics. Each lane must
  remain represented.
- **New workloads are NGINX backends by default.** Workloads are discovered
  from `kubernetes/services/`, using pod labels for selector matching and
  service accounts for principals. Any workload without a reasoned
  `SPECIAL_ROLES` entry must have a path-restricted NGINX rule. This removes
  the hardcoded backend tuple.
- **The selectorless Envoy metrics grant is an exact exception.** Rejecting
  every selectorless `ALLOW` except `default-deny-all` would reject
  `default/envoy-metrics-prometheus-policy`, which the observability contract
  needs. That policy is accepted only when its spec equals one `ALLOW` rule
  for the Prometheus principal on the sole port `15090`. Its name exempts
  nothing. Every other selectorless or empty-selector `ALLOW` fails, including
  in the mesh root namespace.
- **Unsupported forms fail closed.** These include `ALLOW` policies outside
  the declared mesh namespaces, `targetRef`/`targetRefs` attachment, selectors
  that match no discovered workload, duplicate policy identities, workloads
  that share a service account, and malformed input.
- **Local and production are checked separately.** The local set is every
  `AuthorizationPolicy` under `kubernetes/` except `kubernetes/production/`
  and Kustomize patch fragments, evaluated together as one set. The
  production set is the offline render of `kubernetes/production/istio`,
  `istio-ingress-policies` and `apps`, run with `--environment production`.
  Only the documented standalone frontend may be absent there.

The scope, caller table and limits are documented in
[Security Architecture: Static Contract Guard](../architecture/security-architecture.md#static-contract-guard).

## Alternatives Considered

### Alternative 1: Reject every selectorless ALLOW except `default-deny-all`
**Pros:**
- One simple rule that closes the namespace-wide reproduction.

**Cons:**
- It rejects the existing Envoy metrics grant, so the observability contract
  would need to change or the guard would need a name-based exemption.
- It does nothing for a broad rule on a selected workload, such as a missing
  `from`, an extra principal or an unrestricted `to`.

### Alternative 2: Simulate Istio request evaluation
**Pros:**
- It could answer the question "can caller X reach path Y?" directly.

**Cons:**
- Istio matching semantics (path templates, normalization, `when`
  conditions, negative fields) would have to be reproduced and kept current.
  The live edge verifier already proves runtime behavior.
- It would be a larger and less reviewable maintenance surface than a small
  caller table.

### Alternative 3: Mark NGINX backends with an explicit label or marker
**Pros:**
- Classification would be visible in each workload's manifest.

**Cons:**
- A new workload without the marker would silently skip the backend check.
  Treating new workloads as backends by default fails closed instead.

### Alternative 4: Keep extending the inline shell heredoc
**Pros:**
- No new file.

**Cons:**
- The fail fixtures and regression cases could not call the checker directly,
  and the block was already too large to review inline.

### Alternative 5: Derive allowed backend paths from NGINX routes
**Pros:**
- It would prove exact public-route membership.

**Cons:**
- It requires an NGINX parser. [ADR 012](012-shared-nginx-routes-and-path-hardening.md)
  rejected one for a related check. The wildcard heuristic plus the live
  edge verifier cover the current risk.

## Consequences

**Positive:**
- Both reproductions fail with specific diagnostics, locally and in the
  production render.
- A new policy file, an additional policy, a non-`app` selector, an extra
  principal or `from` alternative, or an unrestricted `to` alternative cannot
  silently pass.
- A new backend cannot be added without a path-restricted NGINX rule, and a
  production render cannot drop a shared workload or required policy.

**Negative:**
- The caller table and the Session Gateway auth paths are copied into the
  guard. Adding an auth route, a caller lane or a non-backend workload
  requires a guard change as well as a policy change.
- Production coverage is limited to the three rendered overlays. A
  production-only `AuthorizationPolicy` added to another overlay under
  `kubernetes/production/`, such as `istio-ingress-gateway`, is outside both
  the local and production sets.
- The four `authorization-policy-*` fail fixtures are full copies of the
  policy file with one defect each. They will drift from the source, although
  their `# expect:` diagnostics keep them failing for the intended reason.
- `--self-test` now ensures the pinned `kubectl` so that it can render the
  production cases.

**Neutral:**
- The guard checks structure only. It does not compare policy paths with
  `nginx/includes/api-routes.conf`, evaluate `when` conditions or negative
  fields, or inspect live cluster state. The live boundary proof remains
  `scripts/smoketest/verify-edge-contract.sh` on local Tilt.
- Separate internal listeners remain deferred; see
  [ADR 013](013-deferred-mesh-identity-hardening.md).

## Verification

All results are from 2026-11-15 and are offline static evidence only. No
live cluster or hosted environment was exercised.

- `tests/security-guardrails/test-mesh-authorization.py` passed 54 local cases
  and 16 production cases, plus the four fail fixtures. Each case first proves
  that the unmodified input passes.
- `verify-static-security-manifests.sh` and its `--self-test` passed with the
  pinned PyYAML interpreter.
- `bash -n` and `shellcheck` passed on the changed gate script.

## References
- [Security Architecture: Static Contract Guard](../architecture/security-architecture.md#static-contract-guard)
- [Security Architecture: Mesh Public/Internal Boundary](../architecture/security-architecture.md#mesh-publicinternal-boundary)
- [NGINX README](../../nginx/README.md)
- [Production reference: application and image baseline](../../kubernetes/production/README.md#application-and-image-baseline)
- [ADR 012: Shared NGINX Route Includes, Narrow Mesh Paths and Semicolon Rejection](012-shared-nginx-routes-and-path-hardening.md)
- [ADR 013: Deferred Mesh Identity Hardening](013-deferred-mesh-identity-hardening.md)
- `scripts/guardrails/verify-mesh-authorization.py`,
  `tests/security-guardrails/test-mesh-authorization.py`,
  `kubernetes/istio/authorization-policies.yaml`
- Source: 2026-11-09 implementation review F4 and independent implementation
  review C2. The issue and its implementation plan were deleted after this
  ADR was written; see Git history.
