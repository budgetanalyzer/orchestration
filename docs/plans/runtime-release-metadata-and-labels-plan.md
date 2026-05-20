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
- `scripts/repo/prepare-lockstep-release.sh`
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

This plan does not change Java service `project.version` values. It also does
not require the Java service repos to bump their `serviceCommon` dependency just
because the environment release version changes. Runtime deployment identity
comes from the environment release tag, release manifest, and digest-pinned
production image refs.

## Release Model

Keep these version concepts separate:

| Concept | Example | Owner | Meaning |
| --- | --- | --- | --- |
| Environment release | `v0.0.15` | orchestration release flow | One reviewed deployable Budget Analyzer environment baseline. |
| Service image identity | `ghcr.io/.../transaction-service:0.0.15@sha256:...` | service release workflow plus release manifest | The exact container image deployed for one runtime artifact. |
| Service source revision | `40-char SHA` | release manifest | The source commit used to build one artifact. |
| Shared Java library version | `serviceCommon = "0.0.14"` | service-common release flow and Java consumers | The version of the shared Java libraries a service compiles against. |
| Java project version | `0.0.1-SNAPSHOT` | service repo build metadata | Local Gradle artifact metadata unless a repo intentionally publishes Java artifacts. |
| API contract version | OpenAPI `info.version` | service API owner | API compatibility/contract metadata, not deployment identity. |

Environment releases may move forward without changing `service-common`.
`service-common` should be released only when its code changed and services need
to consume a new shared library artifact. A normal environment release must not
force every Java repo to update `gradle/libs.versions.toml` just to match the
environment version.

The existing lockstep release helper is still useful for coordinated
service-common/library releases, but it is the wrong default for ordinary
environment release validation.

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

## Environment Release Flow

Add or document a runtime-environment release preparation path that validates
repository state, release tags, workflow availability, and image publication
without requiring `serviceCommon` to equal the environment release version.

For a validation release such as `0.0.15`, the intended flow is:

1. Choose the environment release version:
   ```bash
   export RELEASE_VERSION=v0.0.15
   export IMAGE_VERSION=0.0.15
   ```
2. Validate the runtime release repository set is clean and at the intended
   commits.
3. Tag the runtime artifact repos at `v0.0.15`.
4. Let the service and frontend release workflows publish images tagged
   `0.0.15` from those source tags.
5. Keep Java consumers on their current `serviceCommon` catalog value unless
   there is an actual service-common change required for this release.
6. Generate the release manifest from the published image digests:
   ```bash
   ./scripts/repo/generate-release-manifest.sh 0.0.15 \
     --workflow-run-url transaction-service=https://github.com/budgetanalyzer/transaction-service/actions/runs/<id> \
     --workflow-run-url currency-service=https://github.com/budgetanalyzer/currency-service/actions/runs/<id> \
     --workflow-run-url permission-service=https://github.com/budgetanalyzer/permission-service/actions/runs/<id> \
     --workflow-run-url session-gateway=https://github.com/budgetanalyzer/session-gateway/actions/runs/<id> \
     --workflow-run-url budget-analyzer-web=https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/<id> \
     --workflow-run-url ext-authz=https://github.com/budgetanalyzer/orchestration/actions/runs/<id>
   ```
7. Update the production release image baseline from that manifest:
   ```bash
   ./deploy/scripts/23-update-production-release-images.sh \
     --release-manifest tmp/releases/v0.0.15.yaml
   ```
8. Deploy the reviewed environment baseline through the existing OCI deployment
   wrapper.
9. Verify `/api-docs` release metadata and live pod environment-release labels.

This path should not call `scripts/repo/update-service-common-version.sh`
unless the release intentionally includes a new `service-common` artifact.

## Script Split

Keep or introduce separate script responsibilities:

- `scripts/repo/prepare-lockstep-release.sh` remains for coordinated source and
  `service-common` library releases. It may continue to assert that
  `service-common` and Java consumers are pinned to the requested library
  release version.
- Add a runtime environment release prep helper, or add a clearly named mode to
  an existing helper, that does not validate `serviceCommon == release_version`.
  Its job is to validate the runtime repo set, tag availability, workflow links,
  and release-manifest prerequisites.
- `scripts/repo/generate-release-manifest.sh` remains the bridge from published
  artifact images to the reviewed environment baseline.
- `deploy/scripts/23-update-production-release-images.sh` remains the place
  where browser release metadata, image inventory, and deployment labels are
  generated from the reviewed manifest.

Update docs so operators do not use the lockstep/service-common helper for
ordinary environment release validation.

## Kubernetes Labels And Annotations

Add release identity to application Deployment metadata and Pod templates.
Keep environment release identity separate from service artifact or API
contract versions.

Required labels:

- `app.kubernetes.io/part-of: budget-analyzer`
- `app.kubernetes.io/name: <workload-name>`
- `budgetanalyzer.org/environment-release: vX.Y.Z`

Required annotations:

- `budgetanalyzer.org/release-version: vX.Y.Z`
- `budgetanalyzer.org/image: <digest-pinned image ref>`
- `org.opencontainers.image.version: <X.Y.Z>`

When the release manifest includes repository commit SHAs, also add:

- `org.opencontainers.image.revision: <40-char commit SHA>`

Optional service/version labels:

- `app.kubernetes.io/version` may be used only when the workload has a real
  service artifact version. Do not use it as the primary environment release
  label unless the project intentionally keeps that service artifact version in
  lockstep with the environment baseline.
- OpenAPI `info.version` remains API contract metadata and must not be
  rewritten just to match a deployment release.

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
  `budgetanalyzer.org/environment-release`
- warn when a Budget Analyzer runtime pod's environment release label differs
  from the expected release version
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
  labeled deployment and fails on missing or mismatched runtime environment
  release labels.
