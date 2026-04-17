# Production Manifests

This directory contains the checked-in production baseline for the Oracle Cloud
deployment plan. Phase 6 starts from the existing app overlay here and then
finishes the remaining production route, hostname, storage, and verification
work around it.

## Current Starting Point

`apps/` already renders the repo-managed application workloads with the
`0.0.12` GHCR release images pinned by digest from
`kubernetes/production/apps/image-inventory.yaml`.

Status as of 2026-04-17: Phase 6 Chunk 1 is complete, Chunk 2 Step 4
("Finish the production image and frontend overlay path" in the plan) is
complete, and Chunk 2 Step 5 ("Create or finish the production NGINX ConfigMap
path") is now encoded in the checked-in production assets below.

That overlay already:

- keeps the production app route on the `nginx/nginx.production.k8s.conf`
  contract, with the production-owned copy committed at
  `kubernetes/production/nginx/nginx.production.k8s.conf`
- generates `nginx-gateway-config`, `nginx-gateway-includes`, and
  `nginx-gateway-docs` from committed files under `kubernetes/production/`
- patches `nginx-gateway` to serve the released `budget-analyzer-web` static
  bundle instead of the local `budget-analyzer-web-prod-smoke` image or the
  Vite dev server

Render it with:

```bash
kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
```

Verify the current overlay slice with:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

That verifier renders `apps/`, rejects local `:latest` refs, local
`:tilt-<hash>` refs, unqualified local repos, and `imagePullPolicy: Never`,
checks that production does not reference `budget-analyzer-web-prod-smoke` or
`nginx/nginx.k8s.conf`, and applies the production image Kyverno policy at
`../kyverno/policies/production/50-require-third-party-image-digests.yaml`.

## Production NGINX ConfigMap Inputs

The production overlay now owns the NGINX ConfigMap source files directly under
this directory:

- `nginx-gateway-config` renders from
  `kubernetes/production/nginx/nginx.production.k8s.conf`
- `nginx-gateway-includes` renders from
  `kubernetes/production/nginx/includes/`
- `nginx-gateway-docs` renders from
  `kubernetes/production/docs-aggregator/`

That keeps the production cutover reviewable without depending on Tilt-created
ConfigMaps, the Vite dev server, or the mutable top-level local-dev docs path.

The preserved public route contract is:

- `/api/*`, `/api-docs`, `/login`, and `/` stay on `nginx-gateway`
- `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, and `/logout` stay direct to
  `session-gateway` through the Gateway API auth route
- the docs/download surface stays same-origin and the production docs bundle
  now advertises `https://demo.budgetanalyzer.org/api`

## Still Open In Phase 6

The checked-in production baseline is not complete yet. Remaining repo-owned
production blockers are:

- localhost hostnames still appear in the gateway, Istio, monitoring, and
  checked-in session-gateway fallback config paths
- `kubernetes/istio/egress-service-entries.yaml` and
  `kubernetes/istio/egress-routing.yaml` still carry the
  `auth0-issuer.placeholder.invalid` placeholder
- Redis still uses `emptyDir` for `/data` in the shared infrastructure
  deployment, so production persistence is not yet encoded
- the current verifier only covers the app image overlay and not the broader
  Phase 6 production render path

The next open implementation step in the plan is the human review in Chunk 2
Step 6, followed by Chunk 2 Step 7 for the production hostname and Auth0
egress render path.

Jaeger and Kiali remain out of scope for Phase 6. Keep the production docs and
manifests honest about the current baseline: Prometheus and Grafana are the
repo-owned monitoring deliverables now, while Jaeger and Kiali stay deferred to
Phase 10.
