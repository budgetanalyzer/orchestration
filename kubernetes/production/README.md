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
complete, Chunk 2 Step 5 ("Create or finish the production NGINX ConfigMap
path") is encoded in the checked-in production assets below, and Chunk 2 Step 7
("Add the production hostname and egress render path") is now implemented
through the production gateway-route overlay, ingress-policy overlay,
monitoring override, and Phase 6 render script.

That overlay already:

- keeps the production app route on the `nginx/nginx.production.k8s.conf`
  contract, with the production-owned copy committed at
  `kubernetes/production/nginx/nginx.production.k8s.conf`
- generates `nginx-gateway-config`, `nginx-gateway-includes`, and
  `nginx-gateway-docs` from committed files under `kubernetes/production/`
- patches `nginx-gateway` to serve the released `budget-analyzer-web` static
  bundle instead of the local `budget-analyzer-web-prod-smoke` image or the
  Vite dev server
- intentionally does **not** manage `ConfigMap/session-gateway-idp-config`;
  the production non-secret IDP config stays owned by the Phase 5 render/apply
  path so the apps overlay cannot overwrite it with the checked-in fallback
  localhost values

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

## Production Routing And Monitoring Inputs

Phase 6 now keeps the production hostname cutover in reviewed, committed
artifacts:

- `gateway-routes/` renders the production `HTTPRoute` objects with
  `demo.budgetanalyzer.org` and `grafana.budgetanalyzer.org`, while leaving the
  shared localhost dev manifests untouched for Tilt
- `istio-ingress-policies/` renders the production `AuthorizationPolicy` and
  ingress local-rate-limit objects with the demo hostname, separately from the
  gateway routes so Phase 9 can still defer those policy applies until
  `ext-authz` is ready
- `monitoring/prometheus-stack-values.override.yaml` overrides the Grafana
  server domain and root URL to the production monitoring hostname
- `../deploy/scripts/13-render-phase-6-production-manifests.sh` renders the
  Phase 6 production outputs under `tmp/phase-6/`, including the Auth0/FRED
  Istio egress manifests derived from the production `AUTH0_ISSUER_URI`

Render and review the current production hostname/egress slice with:

```bash
./deploy/scripts/13-render-phase-6-production-manifests.sh
sed -n '1,260p' tmp/phase-6/gateway-routes.yaml
sed -n '1,220p' tmp/phase-6/istio-ingress-policies.yaml
sed -n '1,120p' tmp/phase-6/prometheus-stack-values.override.yaml
sed -n '1,260p' tmp/phase-6/istio-egress.yaml
```

## Still Open In Phase 6

The checked-in production baseline is not complete yet. Remaining repo-owned
production blockers are:

- Redis still uses `emptyDir` for `/data` in the shared infrastructure
  deployment, so production persistence is not yet encoded
- the current verifier only covers the app image overlay and not the broader
  Phase 6 production render path

The next open implementation step in the plan is the human review in Chunk 2
Step 8, followed by Chunk 2 Step 9 for the production monitoring/storage
baseline.

Jaeger and Kiali remain out of scope for Phase 6. Keep the production docs and
manifests honest about the current baseline: Prometheus and Grafana are the
repo-owned monitoring deliverables now, while Jaeger and Kiali stay deferred to
Phase 10.
