# Plan: Runtime Release Metadata And Labels

Date: 2026-05-20
Status: Draft

Related documents:

- `docs-aggregator/README.md`
- `docs/architecture/port-reference.md`
- `docs/ci-cd.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `kubernetes/production/apps/image-inventory.yaml`
- `deploy/scripts/23-update-production-release-images.sh`
- `scripts/repo/generate-release-manifest.sh`
- `scripts/README.md`

## Scope

Add browser-visible release identity to the repo-owned `/api-docs` surface and
add Kubernetes runtime labels and annotations that make deployed release identity
easy to inspect from `kubectl`.

This plan covers two changes:

- `/api-docs` shows the current release version and serves a small
  machine-readable release metadata document.
- Application Deployments and Pods carry release labels and image metadata
  annotations derived from the production release manifest and image inventory.

This plan does not change Java service `project.version` values. The runtime
deployment identity continues to come from the shared release tag, release
manifest, and digest-pinned production image refs.

## Target Outcome

After a release baseline update and deployment, an operator can verify the
running version in two ways:

1. Open `https://app.budgetanalyzer.localhost/api-docs` or the production
   equivalent and see the deployed release version in the page header.
2. Run an operator script that lists pod release labels and warns when Budget
   Analyzer runtime pods are missing the expected release label or have a
   different value.

The browser-facing metadata should be non-secret and cache-disabled like the
existing `/api-docs` assets.

## Metadata Contract

Add a checked-in generated file:

- `docs-aggregator/release-metadata.json`

Recommended shape:

```json
{
  "release": {
    "version": "v0.0.14",
    "imageTag": "0.0.14"
  },
  "artifacts": {
    "transaction-service": {
      "image": "ghcr.io/budgetanalyzer/transaction-service:0.0.14@sha256:..."
    }
  }
}
```

Rules:

- `release.version` uses the Git tag form, `vX.Y.Z`.
- `release.imageTag` uses the container tag form, `X.Y.Z`.
- Artifact image refs must stay digest-pinned.
- Do not include secrets, tokens, private hostnames, kubeconfigs, or raw
  environment payloads.
- Do not use OpenAPI `info.version` for deployment version. That field remains
  API contract metadata.

## API Docs Implementation

1. Add `release-metadata.json` to the local and production NGINX docs
   ConfigMaps.
2. Add a `/api-docs/release-metadata.json` NGINX route in both:
   - `nginx/nginx.k8s.conf`
   - `nginx/nginx.production.k8s.conf`
3. Keep the route on the existing docs-only CSP profile and `Cache-Control:
   no-store`.
4. Update `docs-aggregator/index.html` and the existing docs script/CSS so the
   page fetches `/api-docs/release-metadata.json` and renders a compact release
   label in the header.
5. Keep the page useful when metadata is temporarily missing in local
   development; show a neutral fallback rather than failing the Swagger UI page.

## Generation Flow

The durable source of truth is the production image baseline, not Java Gradle
project versions.

Update `deploy/scripts/23-update-production-release-images.sh` so the release
baseline update also rewrites:

- `docs-aggregator/release-metadata.json`
- `kubernetes/production/docs-aggregator/release-metadata.json`, if the
  production copy remains separate

The script already validates full release manifests and writes
`kubernetes/production/apps/image-inventory.yaml`. Reuse that validated data so
the browser metadata and the production image inventory cannot drift.

If local Tilt needs a development fallback, keep it explicit, for example:

- version: `local`
- imageTag: `local`
- artifacts: omitted or local-only

## Kubernetes Labels And Annotations

Add release identity to application Deployment metadata and Pod templates.

Required labels:

- `app.kubernetes.io/part-of: budget-analyzer`
- `app.kubernetes.io/name: <workload-name>`
- `app.kubernetes.io/version: <X.Y.Z>`

Required annotations:

- `budgetanalyzer.org/release-version: vX.Y.Z`
- `budgetanalyzer.org/image: <digest-pinned image ref>`
- `org.opencontainers.image.version: <X.Y.Z>`

When the release manifest includes repository commit SHAs, also add:

- `org.opencontainers.image.revision: <40-char commit SHA>`

Apply these to the six production runtime artifacts:

- `transaction-service`
- `currency-service`
- `permission-service`
- `session-gateway`
- `budget-analyzer-web`
- `ext-authz`

For production, `nginx-gateway` serves the frontend bundle, so it should also
carry the release labels for browser verification even though its main runtime
container image is the pinned NGINX base image. Store the frontend bundle image
ref in the `budgetanalyzer.org/image` annotation for `nginx-gateway`.

## Verification

Add lightweight operator verification first, then promote to a smoke or
guardrail gate after the labels are present in manifests.

Initial helper:

```bash
./scripts/ops/show-pod-version-labels.sh
```

Expected behavior:

- list namespace, pod, app label, version label, part-of label, and images
- read the expected version from
  `kubernetes/production/apps/image-inventory.yaml` by default
- warn when a Budget Analyzer runtime pod is missing
  `app.kubernetes.io/version`
- warn when a Budget Analyzer runtime pod's version label differs from the
  expected release version
- exit non-zero only when called with `--strict`

Later gate:

- add a focused runtime verifier after the labels are part of the deployment
  contract
- compare live pod labels against the release manifest or image inventory
- include the proof in `docs/runbooks/oci-release-deployment-checklist.md`

## Documentation Updates

Update the nearest documentation with the implementation:

- `docs-aggregator/README.md` for the browser metadata route
- `scripts/README.md` for the operator label inspection helper
- `docs/ci-cd.md` for release metadata generation
- `docs/runbooks/oci-release-deployment-checklist.md` for deployment evidence

## Success Criteria

- `/api-docs` shows the release version without breaking Swagger UI.
- `/api-docs/release-metadata.json` returns non-secret release metadata with
  no browser caching.
- Production app manifests render release labels and image metadata
  annotations.
- `./scripts/ops/show-pod-version-labels.sh --strict` passes after a correctly
  labeled deployment and fails on missing or mismatched runtime app labels.
