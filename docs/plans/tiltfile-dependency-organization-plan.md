# Plan: Tiltfile Dependency Organization

Date: 2026-05-06
Status: Implemented

Related documents:

- `Tiltfile`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`

## Context

Static evaluation with `tilt alpha tiltfile-result --context kind-kind` showed
that every Tilt resource currently has at least one label. The remaining
"unorganized" items are dependency roots: resources with no `resource_deps`.
Those should not all be forced into a single chain just to make the UI tree
look tidier.

The first concrete cleanup is complete in the Tiltfile: the `infrastructure`
namespace is now a first-class `infrastructure-namespace` resource. PostgreSQL,
Redis, RabbitMQ, namespace labeling, and core NetworkPolicy application now
depend on it instead of relying on the namespace being implicitly attached to
the PostgreSQL resource.

The second concrete cleanup is also complete: PostgreSQL, Redis, and RabbitMQ
now depend on `infra-tls-prerequisites`, a host-owned Tilt local resource that
runs the internal transport-TLS setup and post-check before those StatefulSets
are applied. This preserves the `setup.sh` contract even after a Tilt namespace
recreation removes namespace-scoped infrastructure secrets.

## Current Intentional Roots

Leave these as roots unless a real runtime dependency appears:

- `infrastructure-namespace`: owns the namespace that infrastructure services
  and policies mutate.
- `service-common-publish`: backend build root for Maven Local publication.
- `budget-analyzer-web-prod-smoke-build`: frontend production-smoke bundle root
  consumed by `nginx-gateway`.
- `gateway-api-crds`: cluster-scoped prerequisite for Gateway API resources.
- `istio-base`: mesh installation root.
- `monitoring-namespace`: namespace prerequisite for monitoring resources.
- `mkcert-tls-secret`: host-owned browser TLS setup; do not run certificate
  generation from the AI container.
- `envoy-gateway-cleanup`: temporary migration cleanup root. Remove it when
  old Envoy Gateway resources are no longer expected in developer clusters.

## Cleanup Plan

1. Keep true roots in the root bucket. Do not add no-op aggregate resources or
   artificial dependencies solely for display.
2. Promote shared namespaces to first-class resources when multiple Tilt
   resources create, label, or apply policies to them.
3. Add dependency edges only when they prevent a real race, such as applying
   namespace labels or NetworkPolicies before the target namespace exists.
4. Revisit `mkcert-tls-secret`. The setup docs say TLS generation belongs to
   host bootstrap before `tilt up`; if Tilt continues to own this resource,
   keep it as an explicit host-owned root. If not, replace it with a read-only
   prerequisite check and move certificate creation entirely out of Tilt.
5. Revisit `envoy-gateway-cleanup` after the migration window. If retained,
   document why the cleanup still needs to run on every local Tilt startup.
6. Add a small static verifier if this keeps drifting: evaluate the Tiltfile,
   list resources with empty `resource_deps`, and compare them to the
   intentional-root allowlist above.

Implemented verifier:

- `scripts/lib/tilt-intentional-root-resources.txt` is the executable
  intentional-root allowlist.
- `scripts/guardrails/check-tilt-resource-roots.sh` evaluates the Tiltfile
  with `tilt alpha tiltfile-result` and fails when root resources drift from
  that allowlist. It is a targeted local guardrail because Tiltfile evaluation
  requires the standard side-by-side workspace checkout with sibling service
  repositories.
- `scripts/bootstrap/check-infra-tls-secrets.sh` is the focused runtime
  prerequisite proof used by `setup.sh` and Tilt before the infrastructure
  StatefulSets start.

## Validation

Use these checks after each Tiltfile dependency cleanup:

```bash
./scripts/guardrails/check-tilt-resource-roots.sh
```

For runtime validation, use the supported local path in
`docs/development/getting-started.md` and the targeted verifiers in
`scripts/README.md`.
