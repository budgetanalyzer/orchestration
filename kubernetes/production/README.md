# Provider-Neutral Production Reference

**Status:** Maintained offline Kubernetes reference; no production environment
is currently configured

This directory composes shared Kubernetes inputs into a production-shaped
reference while keeping local Kind/Tilt manifests unchanged. The overlays are
maintained and statically validated, but they are not evidence of a running or
currently tested production deployment.

The former OCI deployment implementation is frozen under
[archive/oci/](../../archive/oci/README.md). Active tooling must not source or
execute that snapshot.

## Maintained Inputs

- `apps/` composes the repo-managed application workloads with immutable GHCR
  image refs, the canonical production NGINX configuration, and production
  API-docs inputs.
- `gateway-routes/` and `istio-ingress-policies/` retain the reviewed public
  routing and ingress security shape.
- `istio/` removes only the local standalone-frontend policy from the shared
  workload authorization source. `istio-ingress-gateway/` retains shared pod
  security and diagnostics without selecting a production publication type.
- `infrastructure/` reuses the shared PostgreSQL, RabbitMQ, and Redis StatefulSet
  baseline and applies the production Redis storage request.
- `monitoring/` contains the internal-only Grafana override layered onto the
  shared monitoring values.
- `docs-aggregator/` contains production-reference browser documentation
  inputs.

The retained hostname and identity-provider values are non-secret historical
reference values. They do not identify live endpoints. A future deployment
must explicitly choose publication, DNS, identity, storage, secret, and TLS
inputs before applying any rendered resource.

## Parity Contract

Near-identical means that application behavior and controls come from shared
inputs, with the bounded differences below. It does not mean a hosted
production environment has been exercised.

| Area | Shared source | Intentional reference difference | Available validation |
| --- | --- | --- | --- |
| Workloads | `kubernetes/services/` | Digest-pinned release images and metadata; frontend image is copied into NGINX | App Kustomize render and production-reference verifier |
| Ingress and security | Shared gateway pod hardening, authorization policies, `ext-authz`, and rate-limit filter | Kind NodePort is local-only; production publication is unspecified; standalone frontend authorization is deleted | Exact rate-limit comparison plus gateway and authorization structural checks |
| Routing | `kubernetes/gateway/` and the canonical NGINX variants/includes | Public hostname and static frontend route variant | Route render comparison permits only the hostname change; NGINX routing checks use the canonical files |
| Persistence | `kubernetes/infrastructure/` StatefulSets and security contexts | Redis request is `5Gi` instead of `1Gi`; storage class and capacity remain unresolved | Infrastructure render comparison permits only Redis sizing |
| Observability | Shared Prometheus, Jaeger, and Kiali inputs | Loopback-oriented Grafana values; no public routes | Offline render checks enforce internal-only Services and namespace-scoped Kiali RBAC |
| Images | Shared workloads and pinned third-party inputs | Historical app release refs are immutable and reference-only | Image overlay, Kyverno, pinning, and scan-input checks |
| Frontend delivery | Shared `nginx/nginx.production.k8s.conf` and includes | Production serves built static assets; local keeps Vite plus the atomic `/_prod-smoke/` proof | Production app render, edge checks, and the local frontend smoke path when runtime prerequisites exist |

## Application And Image Baseline

`apps/deployment-manifest.yaml`, `apps/image-inventory.yaml`,
`apps/patches/runtime-release-metadata.yaml`, and
`docs-aggregator/release-metadata.json` describe one immutable historical OCI
baseline. Active metadata marks it `reference-only` and retains the old OCI id
only as provenance. It must not be interpreted as current deployment status.

There is no active command that updates or applies this baseline. Changing the
reference requires an explicitly reviewed maintenance decision that updates
the manifest, inventory, runtime metadata patch, docs metadata, and app
Kustomization consistently. It does not require publishing new application
releases merely to retire OCI.

Render the app overlay offline with:

```bash
kubectl kustomize kubernetes/production/apps \
  --load-restrictor=LoadRestrictionsNone
```

The overlay intentionally serves the released frontend bundle from
`nginx-gateway`, keeps browser auth routes on Session Gateway, and keeps API
traffic on the NGINX lane. It does not manage production secret values or the
environment-specific `session-gateway-idp-config` ConfigMap.

## Offline Render Commands

Use the maintained render-only entry points:

```bash
./deploy/scripts/render/production-routes.sh
./deploy/scripts/render/production-infrastructure.sh
./deploy/scripts/render/observability.sh
```

The route renderer includes the production `HTTPRoute` objects, shared ingress
policies, shared workload authorization with the frontend-only omission,
shared ingress gateway pod configuration, internal-only monitoring override,
and Istio egress reference. The
infrastructure renderer composes the shared stateful services. The
observability renderer keeps Jaeger and Kiali internal-only and expands Kiali's
approved namespace RBAC without a live Helm lookup.

These commands do not load cloud or instance configuration and do not inspect
or contact a Kubernetes cluster. They may fetch pinned Helm chart content.
Generated review output is ignored below `tmp/` unless another output directory
is supplied.

## Validation

The main production-reference gate is fully offline with respect to Kubernetes:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

It verifies:

- digest-pinned app images and source provenance;
- app, infrastructure, route, authorization, ingress-policy, gateway pod,
  egress, and observability renders;
- production NGINX and `/api-docs` wiring;
- route parity except for the declared hostname, authorization parity except
  for the standalone frontend, and infrastructure parity except for Redis
  sizing;
- absence of local-only image refs and placeholder hosts;
- internal-only observability exposure and namespace-scoped Kiali RBAC;
- Redis StatefulSet persistence and its `5Gi` reference request; and
- the production Kyverno image policy against the rendered app overlay.

Also run the static security and image-evidence paths when their inputs change:

```bash
./scripts/guardrails/verify-static-security-manifests.sh
./scripts/security/render-image-scan-inputs.sh --help
```

Exact verifier and evidence contracts live in
[scripts/README.md](../../scripts/README.md) and
[docs/dependency-automation.md](../../docs/dependency-automation.md).

## Unresolved Deployment Prerequisites

The reference deliberately does not provide a generic deployment lifecycle.
Any future hosted environment must separately define and verify:

- Kubernetes distribution and ARM64 node support;
- ingress publication, client-address preservation, DNS, and firewall policy;
- storage classes, capacity, backups, and recovery;
- secret provisioning and production identity-provider configuration;
- browser and infrastructure TLS issuance and renewal; and
- apply, rollout, rollback, runtime verification, and operator access.

Do not encode assumptions for a hypothetical provider or revive retired OCI
commands to fill these gaps.
