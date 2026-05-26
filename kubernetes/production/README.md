# Production Manifests

This directory contains the checked-in production baseline for the Oracle Cloud
deployment path. The existing app overlay is paired with the reviewed
production route, monitoring, storage, and verification inputs.

## Production Baseline

`apps/` already renders the repo-managed application workloads with GHCR images
pinned by digest from `kubernetes/production/apps/image-inventory.yaml`. The
reviewed schema v2 deployment record is
`kubernetes/production/apps/deployment-manifest.yaml`.

The production baseline is allowed to contain mixed runtime artifact versions.
The digest-pinned image inventory is the deployment truth. The normal way to
change it is the local desired-state preparation command:

```bash
./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --plan-only
./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --push-tags

# After GitHub Actions publishes the expected GHCR tags
./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --resolve-images
```

The local command previews tag actions, creates and pushes missing source tags
only in `--push-tags` mode, and intentionally stops before reading GHCR. After
the owning GitHub Actions workflows publish the expected image tags,
`--resolve-images` reads those tags once, updates the checked-in manifest,
inventory, app overlay, release metadata, and runtime metadata patch, then
stops for review. Apply the reviewed desired state on the OCI host with:

```bash
./deploy/scripts/deploy-current-oci-manifest.sh
```

`service-common` versions are library coordinates consumed by Java services.
Do not bump `service-common` or rebuild every Java runtime just because this
overlay, `/api-docs` metadata, routing, policy, or other orchestration config
changed.

That overlay already:

- keeps the production app route on the `nginx/nginx.production.k8s.conf`
  contract, with the production-owned copy committed at
  `kubernetes/production/nginx/nginx.production.k8s.conf`
- generates `nginx-gateway-config`, `nginx-gateway-includes`, and
  `nginx-gateway-docs` from committed files under `kubernetes/production/`
- serves `/api-docs/release-metadata.json` from the reviewed deployment
  metadata generated alongside the production image inventory
- applies `apps/patches/runtime-release-metadata.yaml` so app Deployments and
  Pods carry deployment id labels, per-artifact versions, source commits, and
  digest-pinned image annotations
- patches `nginx-gateway` to serve the released `budget-analyzer-web` static
  bundle instead of the local `budget-analyzer-web-prod-smoke` image or the
  Vite dev server
- intentionally does **not** manage `ConfigMap/session-gateway-idp-config`;
  the production non-secret IDP config stays owned by the secret-sync
  render/apply path so the apps overlay cannot overwrite it with the
  checked-in fallback localhost values

Render it with:

```bash
kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
```

Apply it with server-side apply:

```bash
kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone | kubectl apply --server-side -f -
```

The generated `nginx-gateway-docs` ConfigMap is too large for client-side apply
because `kubectl apply` would try to store the full manifest in the
`kubectl.kubernetes.io/last-applied-configuration` annotation.

Verify the current production baseline with:

```bash
kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
./scripts/guardrails/check-secrets-only-handling.sh
./scripts/guardrails/verify-production-image-overlay.sh
./deploy/scripts/09-render-phase-5-secrets.sh
```

The lower-level baseline renderer is still available when a complete schema v2
desired-state manifest has already been reviewed:

```bash
./deploy/scripts/23-update-production-release-images.sh \
  --deployment-manifest tmp/deployments/oci-YYYYMMDD.N.yaml
```

The deployment manifest records deployment id, orchestration revision,
per-artifact source refs, source commits, artifact versions, `service-common`
versions for Java workloads, and digest-pinned image refs.
The update helper copies the reviewed manifest to
`apps/deployment-manifest.yaml` and regenerates
`docs-aggregator/release-metadata.json`,
`kubernetes/production/docs-aggregator/release-metadata.json`, and
`apps/patches/runtime-release-metadata.yaml` so browser metadata and live pod
labels cannot drift from the reviewed deployment baseline.

The production image verifier now:

- renders `apps/`, the broad production infrastructure overlay, and the
  reviewed production route/ingress/monitoring/egress output
- rejects `:latest`, `:tilt-<hash>`, `imagePullPolicy: Never`,
  `budgetanalyzer.localhost`, and `auth0-issuer.placeholder.invalid` anywhere
  in that checked-in production path
- verifies the production NGINX/public-route contract is coming from
  `nginx.production.k8s.conf`, not the local `nginx.k8s.conf` path
- verifies the production docs bundle, application gateway route render, loopback
  Grafana override, Auth0 egress render, and Redis StatefulSet `5Gi`
  claim-template path all stay present
- applies the production image Kyverno policy at
  `../kyverno/policies/production/50-require-third-party-image-digests.yaml`

Before deploying a transaction-service image that requires
`PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET`, confirm the phase 5 secret-sync path
has produced the preview import token credentials Secret:

```bash
kubectl get externalsecret -n default transaction-service-preview-import-token-credentials
kubectl get secret -n default transaction-service-preview-import-token-credentials
```

## Production Admission Path

The repo-owned production admission path lives under `deploy/` and installs the
checked-in Kyverno controller values and the production-only policy set.

- `deploy/helm-values/kyverno.values.yaml` pins the Kyverno production values
  instead of relying on mutable chart defaults.
- `deploy/scripts/14-install-phase-7-kyverno.sh` creates or relabels the
  `kyverno` namespace for baseline Pod Security admission, then installs the
  pinned Kyverno chart version with those checked-in values.
- `deploy/scripts/15-apply-phase-7-policies.sh` reruns
  `./scripts/guardrails/verify-production-image-overlay.sh` and then applies
  the shared admission policies plus the production-only `50` variant.

That split is intentional: the checked-in production verifier stays the static
gate for the production image/render baseline, while the policy apply script is
the operator-owned live-cluster step that activates the same production-only
image policy on OCI.

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
The production overlay stages those docs assets into the same writable web
assets volume as the frontend bundle during init-container startup rather than
mounting a second volume beneath `/usr/share/nginx/html`.

The preserved public route contract is:

- `/api/*`, `/api-docs`, `/login`, and `/` stay on `nginx-gateway`
- `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, and `/logout` stay direct to
  `session-gateway` through the Gateway API auth route
- the docs/download surface stays same-origin and the production docs bundle
  now advertises `https://demo.budgetanalyzer.org/api`

## Production Routing And Monitoring Inputs

This directory keeps the production hostname cutover in reviewed, committed
artifacts:

- `istio/authorization-policies.yaml` is the OCI production
  `AuthorizationPolicy` baseline. It intentionally omits
  `budget-analyzer-web-policy` because production serves the frontend bundle
  from `nginx-gateway` instead of a standalone `budget-analyzer-web`
  Deployment.

- `gateway-routes/` renders the production `HTTPRoute` objects with
  `demo.budgetanalyzer.org`, while leaving the shared localhost dev manifests
  untouched for Tilt
- `istio-ingress-policies/` renders the production `/api/*`
  `AuthorizationPolicy` and the ingress local-rate-limit object. Host ownership
  stays on the production `HTTPRoute` overlay, while the rate-limit filter still
  matches `demo.budgetanalyzer.org`.
- `monitoring/prometheus-stack-values.override.yaml` overrides the Grafana
  server domain and root URL for loopback port-forward access while preserving
  the checked-in `prometheus-stack` Helm release name contract that yields the
  `prometheus-stack-grafana` Service
- `deploy/scripts/13-render-phase-6-production-manifests.sh` renders the
  production outputs under `tmp/phase-6/`, including the Auth0/FRED Istio
  egress manifests derived from the production `AUTH0_ISSUER_URI`

The checked-in production monitoring overlay in this directory stays narrow:

- `monitoring/prometheus-stack-values.override.yaml` is still only the Grafana
  loopback override layered onto the existing `prometheus-stack` Helm release
- production Grafana is internal-only; access it through the shared local and
  production operator contract:
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-grafana 3300:80`
- production Prometheus is also internal-only:
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090`
- keep observability port-forwards loopback-bound; do not use `--address 0.0.0.0`
- the production Helm install must keep the release name `prometheus-stack`
  and layer the production override on top of
  `kubernetes/monitoring/prometheus-stack-values.yaml`
- the production Helm install must also keep using
  `scripts/ops/post-render-prometheus-stack.sh` so the Prometheus Operator
  RBAC stays on the repo-owned least-privilege split instead of the chart's
  upstream broad cluster role
- reapply the full internal monitoring stack with
  `./deploy/scripts/22-apply-production-monitoring.sh`; use
  `--skip-jaeger-kiali` for a Prometheus/Grafana-only refresh or
  `--verify-runtime` when the rollout should also prove the dashboard input
  metrics
- Jaeger and Kiali have a separate reviewed OCI rollout path through
  `deploy/scripts/20-render-phase-7-observability.sh` and
  `deploy/scripts/21-apply-phase-7-observability.sh`; those scripts reuse the
  shared `kubernetes/monitoring/jaeger/*.yaml`,
  `kubernetes/monitoring/kiali-values.yaml`, and
  `scripts/ops/post-render-kiali-server.sh` inputs instead of adding a second
  production-only observability manifest tree
- when installed through that path, both stay in `monitoring`, stay
  `ClusterIP`-only, and use loopback-bound `kubectl port-forward`:
  `svc/jaeger-query 16686:16686` for Jaeger and `svc/kiali 20001:20001` for
  Kiali
- workstation access to production observability uses the same OCI-host
  loopback port-forwards plus the local SSH tunnel helper:
  `./scripts/ops/start-observability-ssh-tunnels.sh <oci-host>`. The helper
  also accepts `OCI_INSTANCE_IP` when the argument is omitted, assumes
  `ubuntu` and `~/.ssh/oci-budgetanalyzer`, and forwards the canonical `3300`,
  `9090`, `16686`, and `20001` ports to OCI host loopback.
- do not introduce `grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, or
  `jaeger.budgetanalyzer.org`

Render and review the current production hostname/egress slice with:

```bash
./deploy/scripts/13-render-phase-6-production-manifests.sh
sed -n '1,260p' tmp/phase-6/gateway-routes.yaml
sed -n '1,220p' tmp/phase-6/istio-ingress-policies.yaml
sed -n '1,120p' tmp/phase-6/prometheus-stack-values.override.yaml
sed -n '1,260p' tmp/phase-6/istio-egress.yaml
```

If a live OCI cluster was previously applied from an older observability render,
explicitly delete any stale observability route after applying the current
application route render:

```bash
kubectl delete httproute -n monitoring grafana-route prometheus-route kiali-route jaeger-route --ignore-not-found
```

The same "delete stale drift once, then rely on the repo-owned baseline"
principle also applies to Istio authz. If an older OCI cluster still has
`AuthorizationPolicy/default/budget-analyzer-web-policy`, delete it after
reconciling with `./deploy/scripts/04-install-istio.sh`; that script now
reapplies the production-specific authz baseline that excludes the
frontend-only policy.

## Production Infrastructure Input

Production infrastructure now renders from the broad
`kubernetes/production/infrastructure` overlay. That target reuses the shared
`kubernetes/infrastructure` baseline for PostgreSQL, RabbitMQ, and Redis, then
patches the Redis StatefulSet storage request for the OCI production shape.

That production overlay includes:

- `Namespace/infrastructure`
- `StatefulSet/postgresql`, `StatefulSet/rabbitmq`, and `StatefulSet/redis`
- `Service/postgresql`, `Service/rabbitmq`, and `Service/redis`
- `ConfigMap/postgresql-init`, `ConfigMap/rabbitmq-config`, and
  `ConfigMap/redis-acl-bootstrap`
- Redis `volumeClaimTemplates.metadata.name: redis-data`
- Redis `volumeClaimTemplates` storage request `5Gi`, expected to bind to the
  k3s `local-path` default storage class on the OCI host

Render it for review with:

```bash
./deploy/scripts/17-render-production-infrastructure.sh
sed -n '1,260p' tmp/production-infrastructure/infrastructure.yaml
```

On a new or already migrated cluster, apply that rendered target with:

```bash
./deploy/scripts/18-apply-production-infrastructure.sh
```

Use these repo-owned scripts as the production infrastructure path. They render
the overlay with Kustomize load restrictions disabled so the production target
can reuse the shared `kubernetes/infrastructure` baseline without duplicating
PostgreSQL, RabbitMQ, or Redis manifests.

The old production-only Redis Deployment/PVC overlay under
`kubernetes/production/infrastructure/redis/` has been removed, and the
one-time migration to the shared Redis StatefulSet baseline has been completed.
New or already migrated OCI clusters should use the normal production
infrastructure render/apply scripts. If an unexpected host still has the old
Redis Deployment plus standalone `redis-data` PVC shape, treat replacement as
incident recovery because Redis session/cache data may be destroyed.

## Production Verification

Recorded verifier output:

```text
Production verification passed for the app overlay, rendered production output, and production infrastructure overlay.
```

The repo-owned production policy install/apply surface is now checked in under
`deploy/`. The route, egress, infrastructure, and observability apply paths are
intentionally kept separate so operators can review each mutation slice before
touching the OCI cluster.
