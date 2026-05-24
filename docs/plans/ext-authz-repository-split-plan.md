# Plan: Move ext-authz To A Dedicated Repository

Date: 2026-05-23

Related documents:

- `AGENTS.md`
- `README.md`
- `docs/OWNERSHIP.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/system-overview.md`
- `docs/ci-cd.md`
- `docs/dependency-notifications.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `scripts/README.md`

## Scope

Move the `ext-authz` service implementation out of this orchestration repository
and into a sibling `budgetanalyzer/ext-authz` repository.

The target boundary is:

- `ext-authz` owns Go source, Go module metadata, Dockerfile, service tests,
  service-local CI, service release image publishing, and service-local README
  content.
- `orchestration` owns Kubernetes manifests, Istio `ext_authz` wiring, Redis ACL
  bootstrap, network policies, NGINX routing, production image pinning, release
  metadata, cross-repo verifiers, and architecture documentation.

## Non-Goals

- Do not move Istio configuration into the `ext-authz` repo.
- Do not move NGINX configuration into the `ext-authz` repo.
- Do not create a separate NGINX repo as part of this split.
- Do not change the runtime request flow.
- Do not change the Redis session schema, cookie name, identity headers, ports,
  probes, or Istio fail-closed behavior.
- Do not preserve full Git history unless the operator chooses the optional
  easy path in this plan.

## Current State

The service implementation currently lives in `orchestration/ext-authz/`:

- `Dockerfile`
- `go.mod`
- `go.sum`
- `*.go`
- `*_test.go`

The orchestration repository also currently owns release publishing for the
image through `.github/workflows/publish-ext-authz-release.yml`.

The deployment and integration surface is larger than the source directory:

- local Tilt builds `ext-authz` from `ext-authz/Dockerfile`
- Kubernetes manifests live under `kubernetes/services/ext-authz/`
- Istio extension provider wiring lives in `kubernetes/istio/istiod-values.yaml`
- ingress `CUSTOM` authorization policy lives in
  `kubernetes/istio/ext-authz-policy.yaml`
- service-to-service authorization policy lives in
  `kubernetes/istio/authorization-policies.yaml`
- production overlays reference the `ext-authz` deployment and image inventory
- release scripts currently treat `ext-authz` as sourced from `orchestration`
- `scripts/smoketest/verify-session-architecture-phase-5.sh` reads
  `orchestration/ext-authz/config.go` directly for shared-session defaults
- docs and dependency inventories reference `orchestration/ext-authz`

## Recommended End State

Use `budgetanalyzer/ext-authz` as the repository name. It matches the existing
artifact, package, deployment, and image names.

Keep the image repository as:

```text
ghcr.io/budgetanalyzer/ext-authz
```

Keep the Kubernetes object names unchanged:

```text
Deployment/ext-authz
Service/ext-authz
ServiceAccount/ext-authz
```

Keep the local Tilt image name unchanged:

```text
ext-authz:latest
```

The only ownership change is the source and image build lifecycle. The runtime
Kubernetes and Istio integration remains orchestration-owned.

## Prerequisites

1. Confirm the sibling repository layout:

   ```bash
   find .. -maxdepth 1 -mindepth 1 -type d \
     \( -name '*-service' -o -name 'session-gateway' -o -name 'budget-analyzer-web' -o -name 'service-common' -o -name 'workspace' -o -name 'orchestration' \) \
     | sort
   ```

2. Confirm GitHub organization permissions:

   - ability to create `budgetanalyzer/ext-authz`
   - ability to manage Actions settings for the new repo
   - ability to grant the new repo write access to the existing
     `ghcr.io/budgetanalyzer/ext-authz` package, if GHCR does not grant it
     automatically

3. Decide repository visibility.

   Recommendation: match the rest of the public Budget Analyzer service repos.

4. Decide whether to preserve history.

   Recommendation: do not preserve history. The orchestration repository keeps
   pre-cutover history. The new repo starts clean at the cutover commit.

5. Pick the first new-repo release version.

   Recommendation: use the next normal SemVer tag, for example `v0.0.16` if the
   current deployed artifact is `0.0.15`.

## Phase 1: Create And Clone The New Repository

### Work

Create the GitHub repository.

With GitHub CLI:

```bash
cd ..
gh repo create budgetanalyzer/ext-authz --public --clone=false
```

Without GitHub CLI:

- create `budgetanalyzer/ext-authz` in the GitHub UI
- leave it empty or initialize it with only default GitHub metadata if required

Clone it as a sibling of `orchestration`:

```bash
cd ..
git clone git@github.com:budgetanalyzer/ext-authz.git
```

Expected sibling layout after cloning:

```text
../orchestration
../ext-authz
```

### Validation

```bash
test -d ../ext-authz/.git
git -C ../ext-authz remote -v
```

## Optional Phase: Preserve Directory History

Skip this by default.

If preserving the `ext-authz/` directory history is desired, the least invasive
approach is a subtree split from the orchestration repo:

```bash
git -C ../orchestration subtree split --prefix=ext-authz -b ext-authz-history
git -C ../ext-authz pull ../orchestration ext-authz-history
```

Only use this if the resulting history is clean enough to be worth the extra
coordination. Otherwise, copy the current files and rely on orchestration
history for pre-cutover archaeology.

## Phase 2: Bootstrap The ext-authz Repository

### Work

Copy only source-owned files from orchestration:

```bash
cp ../orchestration/ext-authz/Dockerfile ../ext-authz/
cp ../orchestration/ext-authz/go.mod ../ext-authz/
cp ../orchestration/ext-authz/go.sum ../ext-authz/
cp ../orchestration/ext-authz/*.go ../ext-authz/
```

Do not copy the compiled binary currently present at:

```text
../orchestration/ext-authz/ext-authz
```

Update the Go module path in `../ext-authz/go.mod`:

```text
module github.com/budgetanalyzer/ext-authz
```

Add a repo-local `.gitignore`:

```gitignore
/ext-authz
/coverage.out
/.cache/
```

Add `README.md` that covers only service-local concerns:

- purpose: Envoy/Istio HTTP external authorization service for Budget Analyzer
- local test command: `go test ./...`
- local container build command
- key environment variables:
  - `HTTP_PORT`
  - `HEALTH_PORT`
  - `REDIS_ADDR`
  - `REDIS_USERNAME`
  - `REDIS_EXT_AUTHZ_PASSWORD`
  - `REDIS_TLS`
  - `REDIS_CA_CERT`
  - `SESSION_COOKIE_NAME`
  - `SESSION_KEY_PREFIX`
  - `LOG_FORMAT`
- contract pointer back to
  `../orchestration/docs/architecture/session-edge-authorization-pattern.md`
- explicit note that Kubernetes, Istio, Redis ACLs, and production deployment
  are orchestration-owned

Add an `AGENTS.md` in the new repo with narrow repo instructions:

- archetype: service
- scope: `ext-authz` service implementation
- write surface: this repository only
- source of truth for deployment: sibling `../orchestration`
- source of truth for shared browser session contract:
  `../orchestration/docs/architecture/session-edge-authorization-pattern.md`
- do not edit orchestration manifests from the service repo except docs/config
  when explicitly coordinating deployment wiring

Add `LICENSE` if the other service repos carry one directly. Otherwise link to
the organization-level license pattern used by the existing repos.

Run formatting and tests:

```bash
cd ../ext-authz
gofmt -w *.go
go mod tidy
go test ./...
```

### Validation

```bash
cd ../ext-authz
git status --short
go test ./...
docker build -t ext-authz:local .
```

## Phase 3: Add ext-authz Repository CI And Release Workflows

### Work

Add `.github/workflows/build.yml`:

- trigger on pull requests and pushes to `main`
- set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`
- use Node 24-ready action majors
- run:
  - checkout
  - setup Go using the repo's `go.mod`
  - `gofmt` check
  - `go test ./...`
  - optional Docker build without push

Add `.github/workflows/publish-release.yml`:

- trigger on pushed `v*` tags and manual dispatch
- preserve the current release input behavior:
  - strict `vX.Y.Z` tag pushes publish Docker label `X.Y.Z`
  - manual non-SemVer refs require explicit `docker_label`
  - never publish `latest`
- use:
  - `actions/checkout@v6`
  - `docker/setup-qemu-action@v4`
  - `docker/setup-buildx-action@v4`
  - `docker/login-action@v4`
  - `docker/build-push-action@v7`
- build `linux/arm64`
- publish `ghcr.io/budgetanalyzer/ext-authz:<label>`
- set OCI labels with the new source repository:
  - `org.opencontainers.image.source=https://github.com/budgetanalyzer/ext-authz`
  - `org.opencontainers.image.revision=<commit>`
  - `org.opencontainers.image.version=<label>`

If the first publish fails with package permission errors, update the existing
GHCR package settings:

- open package `budgetanalyzer/ext-authz`
- add repository access for `budgetanalyzer/ext-authz`
- grant Actions write permission
- leave orchestration access until the cutover is complete

### Validation

Before merging:

```bash
cd ../ext-authz
go test ./...
docker build -t ext-authz:local .
```

After merging:

- verify `build.yml` passes on `main`
- create or push the first release tag when ready
- verify `publish-release.yml` prints a digest-pinned image reference

## Phase 4: Update Orchestration To Use The Sibling Source

### Work

Remove orchestration-owned service source:

- delete `ext-authz/`
- delete `.github/workflows/publish-ext-authz-release.yml`

Keep orchestration-owned deployment files:

- keep `kubernetes/services/ext-authz/serviceaccount.yaml`
- keep `kubernetes/services/ext-authz/deployment.yaml`
- keep `kubernetes/services/ext-authz/service.yaml`
- keep `kubernetes/istio/istiod-values.yaml`
- keep `kubernetes/istio/ext-authz-policy.yaml`
- keep `kubernetes/istio/authorization-policies.yaml`
- keep NGINX config in `nginx/`

Update `Tiltfile` so local development builds from the sibling repository:

```python
ext_authz_repo = get_repo_path('ext-authz')

docker_build(
    'ext-authz',
    context=ext_authz_repo,
    dockerfile=ext_authz_repo + '/Dockerfile',
)
```

Consider adding local build dependencies if Tilt does not pick them up
adequately from the external context:

```python
only=[
    'Dockerfile',
    'go.mod',
    'go.sum',
    '*.go',
]
```

Keep the Kubernetes deployment image as `ext-authz:latest` for local Tilt.
That is still the local image name Tilt rewrites to immutable `:tilt-<hash>`
refs during live deploys.

Update `scripts/smoketest/verify-session-architecture-phase-5.sh`:

- compute `PARENT_DIR="$(dirname "${REPO_ROOT}")"`
- read ext-authz defaults from `${PARENT_DIR}/ext-authz/config.go`
- fail clearly if `../ext-authz` is not cloned for static contract checks
- update the usage text from "in the orchestration repo" to "across the
  orchestration, session-gateway, and ext-authz repos"

Update image-pinning inventories:

- remove `ext-authz/Dockerfile` from
  `scripts/lib/phase-7-image-pinning-targets.txt`
- keep `kubernetes/services/ext-authz/deployment.yaml`
- keep `ext-authz:latest` in `scripts/lib/phase-7-allowed-latest.txt`

Update repo catalog and release helpers:

- `scripts/repo/repo-config.sh`
  - remove `orchestration` from `RUNTIME_IMAGE_REPOS`
  - add `ext-authz` to `RUNTIME_IMAGE_REPOS`
  - keep `orchestration` in `INFRASTRUCTURE_REPOS`
  - add `ext-authz` to `LOCKSTEP_RELEASE_REPOS`
  - add `ext-authz` to `OCI_RELEASE_SOURCE_REPOS`
  - keep `orchestration` in `OCI_RELEASE_SOURCE_REPOS`
- `scripts/repo/prepare-lockstep-release.sh`
  - change publish workflow entry from
    `orchestration:publish-ext-authz-release.yml` to
    `ext-authz:publish-release.yml`
- `scripts/repo/prepare-service-release.sh`
  - change `ARTIFACT_SOURCE_REPOS["ext-authz"]` to `ext-authz`
  - change `ARTIFACT_WORKFLOWS["ext-authz"]` to `publish-release.yml`
- `scripts/repo/generate-deployment-manifest.sh`
  - change `ARTIFACT_SOURCE_REPOS["ext-authz"]` to `ext-authz`
- `deploy/scripts/prepare-oci-manifest-from-current-stack.sh`
  - change `SOURCE_REPOS["ext-authz"]` to `ext-authz`
  - remove the special case that allows an existing orchestration tag for
    `ext-authz` to differ from the current orchestration `HEAD`
- `scripts/repo/github/add-repo-topics.sh`
  - add `ext-authz` with service/runtime/auth/istio topics, matching the
    existing style

Do not hand-edit the checked-in production desired state just to change
`source_repository` from `orchestration` to `ext-authz`. The current production
inventory should continue to describe the image that is actually deployed. The
source repository changes when a new `ext-authz` image from the new repo is
published and resolved into the production manifest.

### Validation

Run shell validation for every modified shell script:

```bash
bash -n scripts/smoketest/verify-session-architecture-phase-5.sh
bash -n scripts/repo/repo-config.sh
bash -n scripts/repo/prepare-lockstep-release.sh
bash -n scripts/repo/prepare-service-release.sh
bash -n scripts/repo/generate-deployment-manifest.sh
bash -n deploy/scripts/prepare-oci-manifest-from-current-stack.sh
bash -n scripts/repo/github/add-repo-topics.sh

shellcheck scripts/smoketest/verify-session-architecture-phase-5.sh
shellcheck scripts/repo/repo-config.sh
shellcheck scripts/repo/prepare-lockstep-release.sh
shellcheck scripts/repo/prepare-service-release.sh
shellcheck scripts/repo/generate-deployment-manifest.sh
shellcheck deploy/scripts/prepare-oci-manifest-from-current-stack.sh
shellcheck scripts/repo/github/add-repo-topics.sh
```

Run the focused static contract check:

```bash
./scripts/smoketest/verify-session-architecture-phase-5.sh --static-only
```

Run the static guardrails most likely to catch the split:

```bash
./scripts/guardrails/check-phase-7-image-pinning.sh
./scripts/guardrails/verify-phase-7-static-manifests.sh
./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
```

Run a local Tilt smoke if cluster prerequisites are present:

```bash
./scripts/bootstrap/check-tilt-prerequisites.sh
tilt up
```

Then verify:

```bash
kubectl rollout status deployment/ext-authz -n default --timeout=120s
kubectl logs deployment/ext-authz -n default --tail=100
./scripts/smoketest/verify-phase-3-istio-ingress.sh
./scripts/smoketest/verify-phase-6-session-7-api-rate-limit-identity.sh
```

## Phase 5: Update Documentation

### Work

Update orchestration documentation:

- `AGENTS.md`
  - list `../ext-authz` as an expected sibling repo
  - state that `ext-authz` service code belongs in the sibling repo
  - keep Istio, NGINX, Kubernetes, and production policy ownership here
- `README.md`
  - add `ext-authz` to Service Repositories
  - clarify that orchestration deploys it but no longer owns the Go source
- `docs/OWNERSHIP.md`
  - add a row if recurring ext-authz implementation docs need an owner:
    `ext-authz README.md` owns service-local implementation and release docs;
    orchestration docs own cross-cutting session-edge behavior
- `docs/architecture/session-edge-authorization-pattern.md`
  - update references from `orchestration/ext-authz` to sibling `../ext-authz`
  - keep the shared contract owner in orchestration
- `docs/architecture/security-architecture.md`
  - clarify source ownership if it currently implies orchestration owns the Go
    service implementation
- `docs/architecture/system-overview.md`
  - keep the runtime flow unchanged, update repository ownership wording only
- `docs/development/getting-started.md`
  - include `../ext-authz` in required sibling repos for full local Tilt
- `docs/development/local-environment.md`
  - update the live/local development explanation for the Go service build
- `docs/dependency-notifications.md`
  - move Go, go-redis, and distroless ownership from
    `orchestration/ext-authz` to `ext-authz`
- `docs/ci-cd.md`
  - state that `ext-authz` publishes from
    `budgetanalyzer/ext-authz/.github/workflows/publish-release.yml`
- `deploy/README.md`
  - remove the statement that the `ext-authz` image is sourced from
    orchestration
  - keep the desired-state review flow unchanged
- `kubernetes/production/README.md`
  - update any source-repo wording if present
- `scripts/README.md`
  - update release helper descriptions if they mention orchestration publishing
    `ext-authz`

Update ext-authz repository documentation:

- `README.md`
  - service purpose
  - local test/build commands
  - environment variables
  - release workflow
  - link to orchestration deployment docs
- `AGENTS.md`
  - repo boundaries
  - validation commands
  - pointer to orchestration for deployment

### Validation

```bash
rg -n "orchestration/ext-authz|publish-ext-authz-release|source.*orchestration|sourced from this orchestration repository" \
  AGENTS.md README.md docs deploy scripts kubernetes .github
```

Every remaining match should either be historical context in this plan or an
intentional reference to pre-cutover production metadata.

## Phase 6: Create The First Release Tag In The New Repository

### Work

After the new repo is merged and Actions are configured, create the first
release tag in `../ext-authz`. The package authority move and image publish are
handled in Phase 7 so the first post-split image is published from the
`ext-authz` package/repository surface.

```bash
cd ../ext-authz
git tag v0.0.16
git push origin v0.0.16
```

Or use the orchestration helper after it has been updated:

```bash
cd ../orchestration
./scripts/repo/prepare-service-release.sh --service ext-authz --version 0.0.16 --tag
```

### Validation

```bash
git -C ../ext-authz rev-parse --verify v0.0.16^{commit}
```

Confirm the tag points at the intended `../ext-authz` release commit.

## Phase 7: Move GHCR Package Authority And Cut Production Desired State

### Work

Move the existing `ghcr.io/budgetanalyzer/ext-authz` package so the new
repository is the package-connected source of truth before publishing the first
post-split image.

In GitHub package settings for `ext-authz`:

- connect the package to `budgetanalyzer/ext-authz`
- ensure package visibility matches the rest of the runtime image packages
- ensure `budgetanalyzer/ext-authz` Actions can publish the package through
  its own `GITHUB_TOKEN`
- remove orchestration publish/write authority from the package as part of this
  cutover, not as deferred cleanup

After this step, the package UI should no longer redirect through:

```text
https://github.com/budgetanalyzer/orchestration/pkgs/container/ext-authz
```

It should resolve from the new repository/package surface instead:

```text
https://github.com/budgetanalyzer/ext-authz/pkgs/container/ext-authz
```

Then publish or rerun the first release image from `budgetanalyzer/ext-authz`:

```text
https://github.com/budgetanalyzer/ext-authz/actions/workflows/publish-release.yml
```

For a failed tag-triggered run, rerun the failed workflow after package authority
is moved. If a manual dispatch is needed, use:

```text
release_ref: v0.0.16
docker_label: <empty>
```

The workflow must publish:

```text
ghcr.io/budgetanalyzer/ext-authz:0.0.16
```

Use the normal desired-state preparation flow after the new image exists:

```bash
cd ../orchestration
./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag v0.0.16 --plan-only
./deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag v0.0.16 --resolve-images
```

The preparation command's default changed-artifact mode should preserve the
existing `0.0.15` images for unchanged services and only move `ext-authz` to
`0.0.16`.

Review the generated diff. For `ext-authz`, the production files should now
record:

```yaml
source_repository: "ext-authz"
source_ref: "refs/tags/v0.0.16"
source_commit: "<commit from ../ext-authz>"
image: "ghcr.io/budgetanalyzer/ext-authz:0.0.16@sha256:<digest>"
```

Expected files updated by the production desired-state flow:

- `kubernetes/production/apps/deployment-manifest.yaml`
- `kubernetes/production/apps/image-inventory.yaml`
- `kubernetes/production/apps/kustomization.yaml`
- `kubernetes/production/apps/patches/runtime-release-metadata.yaml`
- `docs-aggregator/release-metadata.json`
- `kubernetes/production/docs-aggregator/release-metadata.json`

### Validation

```bash
docker buildx imagetools inspect ghcr.io/budgetanalyzer/ext-authz:0.0.16
./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

Confirm the image has a `linux/arm64` manifest and the OCI source label points
to `https://github.com/budgetanalyzer/ext-authz`.

If deploying to OCI as part of the same work:

```bash
./deploy/scripts/deploy-current-oci-manifest.sh
```

Run the relevant live verifiers after deployment:

```bash
kubectl rollout status deployment/ext-authz -n default --timeout=120s
./scripts/smoketest/verify-phase-1-credentials.sh
./scripts/smoketest/verify-phase-3-istio-ingress.sh
./scripts/smoketest/verify-session-architecture-phase-5.sh
```

## Phase 8: Verify Orchestration No Longer Publishes Ext Authz

### Work

After the package cutover, successful `ext-authz` image publish, and production
desired-state update:

- confirm the package is connected to `budgetanalyzer/ext-authz`, not
  `budgetanalyzer/orchestration`
- confirm orchestration has no package publish/write authority for
  `ghcr.io/budgetanalyzer/ext-authz`
- keep only package read access required by deployment and verification flows
- confirm orchestration no longer has an ext-authz publish workflow
- confirm release helper output points to the new workflow URL
- close or update any GitHub branch protection rules that still mention the old
  orchestration workflow
- confirm at least one local Tilt run still uses the unchanged local image name
  and Kubernetes object names

### Validation

```bash
rg -n "publish-ext-authz-release|orchestration:publish-ext-authz|orchestration/ext-authz|orchestration/pkgs/container/ext-authz" .
```

Expected remaining matches:

- this plan
- intentionally historical production metadata until the first new-source
  production cutover has been applied

## Rollback Plan

If the split breaks local development before production is changed:

1. Revert the orchestration commit that deletes `ext-authz/` and changes Tilt to
   the sibling repo.
2. Leave the new `ext-authz` repo in place but stop using it.
3. Keep production desired state unchanged because it still points at the
   existing digest-pinned image.

If the new repository publishes a bad image but production has not been updated:

1. Do not update production desired state.
2. Fix the new repo.
3. Publish a new tag.

If production is updated and the new image fails:

1. Prepare a new orchestration desired-state change that restores the previous
   digest-pinned `ext-authz` image and previous source metadata.
2. Run:

   ```bash
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ./deploy/scripts/deploy-current-oci-manifest.sh
   ```

3. Keep the rollback as a normal checked-in desired-state change. Do not patch
   the live deployment manually except as an explicitly labeled incident
   recovery action.

## Success Criteria

- `../ext-authz` exists as a sibling Git repository.
- `../ext-authz` owns the Go module, Dockerfile, tests, CI, and release
  workflow.
- orchestration no longer contains `ext-authz/` source code.
- local Tilt builds `ext-authz` from `../ext-authz`.
- Kubernetes, Istio, Redis ACLs, NGINX, and production deployment policy remain
  orchestration-owned.
- static session contract verification reads Session Gateway and ext-authz from
  sibling repos.
- release helpers treat `ext-authz` as a first-class runtime image repository.
- the first post-cutover production desired state records
  `source_repository: "ext-authz"` for the `ext-authz` artifact.
- all modified shell scripts pass `bash -n` and `shellcheck`.
- focused static and runtime verifiers pass.
