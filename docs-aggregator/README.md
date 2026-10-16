# API Documentation Aggregator

`/api-docs` is the human-friendly developer page for viewing the shared Budget
Analyzer API documentation. It is intentionally separate from the main app and
`/api/*` browser-hardening contract.

The machine-readable contract stays first-class on the same public route:

- `/api-docs/openapi.json` is the unified JSON contract
- `/api-docs/openapi.yaml` is the unified YAML contract
- `/api-docs/release-metadata.json` is non-secret reference metadata that also
  drives the visible deployment-shape table on the docs page

## Overview

The docs page serves a checked-in wrapper from this repository, stages stock
Swagger UI `5.11.0` assets from a pinned `swaggerapi/swagger-ui` init
container, and points the browser at the same-origin checked-in unified spec at
`/api-docs/openapi.json`.

Local Tilt and the production overlay mount the wrapper assets, JSON contract,
YAML contract, and release metadata through split ConfigMaps before the init
container stages them into the NGINX docs directory. Keep that split in place
when the generated contracts grow; a single large ConfigMap can exceed
Kubernetes' apply-annotation size limit.

Local Tilt serves `.tilt/api-docs/release-metadata.json`, generated when the
Tiltfile is evaluated. That local metadata keeps the maintained production
reference rows, sets `deployment.environment` to `local-development`, adds
`deployment.runtime: tilt`, records the historical reference id as
`productionReferenceId`, and adds a static `localSource` state for each runtime
repo. Normal service live updates do not regenerate this file.

The production overlay serves
`kubernetes/production/docs-aggregator/release-metadata.json`. It is a checked-in
historical, reference-only baseline; it is not generated from or compared with
a live production environment.

The route is intentionally read-only:

- Swagger UI runs with `supportedSubmitMethods: []`
- the wrapper hides the authorize button
- raw JSON and YAML downloads remain first-class on the same route for tooling
  and direct download use
- the deployment-shape section renders the reviewed reference-manifest metadata
  for every managed artifact repository, including source refs, source commits,
  artifact versions, service-common versions where applicable, and digest-pinned
  image refs

The generated unified downloads remain checked in here:

- `docs-aggregator/openapi.json`
- `docs-aggregator/openapi.yaml`

Those files are refreshed by `./scripts/repo/generate-unified-api-docs.sh`.
That generator lives under `scripts/repo/` because it coordinates live-cluster
OpenAPI fetches with optional sibling-repo docs updates rather than acting as a
service-local verifier.

The default mode regenerates the unified JSON/YAML files and copies both the
unified and filtered Session Gateway specs into the sibling frontend docs
directory. When only the Session Gateway snapshot is owned by the caller, use
the explicit single-output mode:

```bash
./scripts/repo/generate-unified-api-docs.sh \
  --session-gateway-only /path/to/session-gateway-api.yaml
```

That mode accepts exactly one `.yaml` or `.yml` output path, applies the same
`/internal/*` filter as default mode, and writes no unified or frontend output
implicitly. The output directory must already exist.

## Public Outputs

- `/api-docs` is the human docs page backed by self-hosted Swagger UI.
- `/api-docs/openapi.json` is the machine-readable JSON contract.
- `/api-docs/openapi.yaml` is the machine-readable YAML contract.
- `/api-docs/release-metadata.json` is the machine-readable deployment
  identity document used by the page header and deployment-shape table.

## Runtime Shape

```
Browser
    ↓
https://app.budgetanalyzer.localhost/api-docs
    ↓
Receives self-hosted Swagger UI assets from nginx-gateway
    ↓
Fetches `/api-docs/openapi.json` from the same public origin
```

The direct downloads at `/api-docs/openapi.json` and `/api-docs/openapi.yaml`
remain available for browser download, local inspection, or tooling use.
`/api-docs/release-metadata.json` is served on the same docs-only CSP profile
with `Cache-Control: no-store` and is intentionally limited to non-secret
deployment identity and digest-pinned artifact image refs. It does not report
live deployment lifecycle status. The page fetches that metadata once and
renders its environment, orchestration revision, and full managed artifact
manifest. In local Tilt the page labels the historical production id as a
reference, not a deployed baseline.

`/api-docs` now carries its own docs-only relaxed CSP include. That profile is
limited to what the self-hosted Swagger UI bundle needs and does not change the
main app or `/api/*` posture.

## Files

- `index.html` contains the wrapper page and same-origin asset references.
- `swagger-initializer.js` holds the small Swagger UI bootstrap configuration.
- `swagger-ui-overrides.css` contains the wrapper styling and minor UI overrides.
- `openapi.json` and `openapi.yaml` are generated unified OpenAPI outputs.
- `release-metadata.json` is the maintained reference-only source copied into
  the production overlay; local Tilt generates its own ignored derivative
  under `.tilt/api-docs/`.

## Adding a New Microservice

1. Update `./scripts/repo/generate-unified-api-docs.sh` so it fetches and merges the new service spec into the unified output.
2. Rerun `./scripts/repo/generate-unified-api-docs.sh` to refresh the checked-in `openapi.json` and `openapi.yaml` artifacts.
3. Only update NGINX docs routing if you intentionally want to expose that service's raw live `v3/api-docs` endpoint for some separate non-browser use case.

## Dependencies

- stock Swagger UI `5.11.0` assets, staged from pinned `swaggerapi/swagger-ui:v5.11.0`
- split ConfigMaps for wrapper assets, `openapi.json`, and `openapi.yaml`
- NGINX serving the checked-in wrapper files and generated OpenAPI downloads
- `kubectl` access to the running local cluster for either generator mode
- `jq` plus a YAML converter (`yq` or Python with PyYAML)
