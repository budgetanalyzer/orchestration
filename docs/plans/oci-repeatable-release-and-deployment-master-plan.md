# Plan: OCI Repeatable Release And Deployment Automation

Date: 2026-05-20
Status: Draft

Related documents:

- `docs/plans/oci-deployment-upgrade-lockstep-plan.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `scripts/README.md`
- `scripts/repo/tag-release.sh`
- `kubernetes/production/apps/image-inventory.yaml`
- `scripts/guardrails/verify-production-image-overlay.sh`

## Scope

Create a repeatable OCI deployment operating model that supports both:

- one-off infrastructure upgrades required by the current lockstep upgrade
  plan
- the normal "deploy this reviewed release version" path for future releases

The concrete first use case is tagging the current Budget Analyzer repository
heads, publishing the matching release artifacts, updating the production image
baseline, and deploying that baseline to OCI.

This plan does not replace the lockstep upgrade plan. The lockstep plan owns
the current dependency/platform compatibility work. This plan owns the reusable
release, checklist, and deployment automation shape that should survive this
specific upgrade.

## Target Outcome

The durable operator experience should become:

1. choose a release version, such as `v0.0.13`
2. validate all participating repositories are clean, on `main`, and at the
   intended commits
3. tag and push the same release tag across the release repository set
4. let GitHub release workflows publish all `linux/arm64` artifacts
5. collect digest-pinned release image refs into one release manifest
6. update the production image baseline from that manifest
7. run static production and lockstep verifiers
8. run one master OCI deployment script in a selected mode
9. complete a concise deployment checklist with evidence links and rollback
   notes

The master script should make normal app-only releases boring, while still
allowing explicit platform, infrastructure, secrets, observability, and public
TLS phases when a lockstep upgrade requires them.

## Can GitHub Trigger OCI Deployments?

Yes. GitHub can trigger OCI deployments, but the deployment authority has to be
designed deliberately because the live k3s cluster is reachable through the OCI
host, not from ordinary local Tilt tooling.

Viable patterns:

| Pattern | How it works | Fit for this repo |
| --- | --- | --- |
| GitHub Actions over SSH to the OCI host | A `workflow_dispatch` job uses a protected GitHub Environment, SSH key secret, and host allow-listing to run the checked-in master deployment script on the OCI instance. | Best first automation target after the local/host script is stable. It preserves the current repo-owned scripts and avoids teaching a GitHub-hosted runner direct cluster access. |
| Self-hosted GitHub runner on the OCI host | The runner lives on the OCI instance and runs deployment scripts locally with `/etc/rancher/k3s/k3s.yaml`. | Powerful but riskier. It creates a long-lived GitHub-controlled execution path on the production host and should only be considered after runner hardening, labels, environment approvals, and a service account model are documented. |
| OCI DevOps deployment pipeline triggered by GitHub | GitHub triggers an OCI-native deployment pipeline or build/deploy stage. | Plausible later if the project wants OCI-native audit and IAM boundaries. It is heavier than needed for the second deployment. |
| GitHub Actions with OCI CLI credentials | A workflow uses OCI credentials to mutate cloud resources and then uses SSH or another remote-execution mechanism for k3s operations. | Useful for future NLB, DNS, Vault, or instance orchestration. It does not remove the need for a safe host-side Kubernetes deployment path. |

Recommended sequence:

1. First create the reusable host-side master script and checklist.
2. Use it manually for the second deployment.
3. Add a `workflow_dispatch` GitHub workflow that can run the same master script
   over SSH with environment approval.
4. Defer a self-hosted runner or OCI DevOps pipeline until the deployment
   contract is boring and the risk is worth the operational benefit.

## Release Repository Set

The deployment release set is:

- `orchestration`
- `service-common`
- `transaction-service`
- `currency-service`
- `permission-service`
- `session-gateway`
- `budget-analyzer-web`

`ext-authz` is published from this repository and must be included in the OCI
application image set even though it is not a sibling repository.

`checkstyle-config` is currently included in `scripts/repo/repo-config.sh`, but
it is not an OCI runtime artifact. Before using the all-repo tag script for a
production deployment, decide whether it remains part of the shared release tag
contract or whether the script needs a release-runtime mode that excludes
non-runtime tooling repositories.

## Current Second Deployment Checklist

Use this checklist for the immediate deployment, even before all automation in
this plan exists.

### 1. Pre-Release Validation

- Confirm the current branches are the intended release heads.
- Run the relevant local validation from the lockstep upgrade plan.
- Run `./scripts/repo/validate-repos.sh` and resolve failures rather than
  tagging around them.
- Confirm `service-common` has the intended release version in its Gradle
  metadata before tagging, because its publish workflow rejects tag/version
  mismatches.
- Confirm the sibling service release workflows have access to
  `SERVICE_COMMON_PACKAGES_USERNAME` and `SERVICE_COMMON_PACKAGES_READ_TOKEN`.
- Confirm the production secret prerequisites from the lockstep plan are ready,
  especially any new transaction-service preview import token secret and
  RabbitMQ definitions changes.

### 2. Tag The Release

- Choose the version, for example `v0.0.13`.
- Use the existing tag helper only after validating that its repository set is
  correct for this release:
  ```bash
  ./scripts/repo/tag-release.sh v0.0.13
  ```
- If `checkstyle-config` should not receive an OCI runtime release tag, update
  the helper first or tag the runtime repos explicitly with documented commands.
  Do not silently create an inconsistent release set.

### 3. Publish Release Artifacts

- Confirm the tag push triggered each sibling `publish-release.yml` workflow.
- Confirm `service-common` packages published successfully before relying on
  backend service image builds.
- Confirm the service and frontend workflows published `linux/arm64` GHCR
  images.
- Trigger this repo's `publish-ext-authz-release.yml` for the same tag if the
  tag push does not already do so.
- Capture the digest-pinned image refs printed by each workflow.

### 4. Update The Production Baseline

- Create a release manifest in a temporary or future checked-in location with
  the release version, source commits, workflow run URLs, and six application
  image refs.
- Use the production image update helper from the lockstep plan once it exists.
  Until then, update the same files manually and keep the diff small:
  - `kubernetes/production/apps/image-inventory.yaml`
  - `kubernetes/production/apps/kustomization.yaml`
  - `scripts/guardrails/verify-production-image-overlay.sh`
- Run:
  ```bash
  kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
  ./scripts/guardrails/verify-production-image-overlay.sh
  ./deploy/scripts/09-render-phase-5-secrets.sh
  ```
- Run `./deploy/scripts/24-verify-oci-upgrade-lockstep.sh` after that verifier
  exists.

### 5. Deploy To OCI

- Capture the live baseline before applying changes:
  ```bash
  kubectl get nodes -o wide
  kubectl get pods -A
  helm list -A
  kubectl get deploy,statefulset -A
  ```
- Execute only the deployment phases required by the release:
  - platform phases when k3s, Gateway API, Istio, cert-manager, External
    Secrets Operator, Kyverno, Kiali, or Prometheus chart pins changed
  - infrastructure phases when PostgreSQL, RabbitMQ, Redis, storage, or
    bootstrap definitions changed
  - secret-sync phases when Vault inventory, ExternalSecret wiring, or
    non-secret IDP config changed
  - app phases for every release image update
  - observability phases when monitoring, Jaeger, or Kiali changed
  - public TLS phase immediately after any phase that intentionally reverts the
    ingress Gateway to the phase-4 HTTP-only baseline
- Verify rollouts and run the production checks listed in the lockstep plan.

## Reusable Automation Work

### Phase 1: Release Manifest Contract

Add a release manifest format that can be produced manually at first and later
by GitHub automation.

Proposed path:

- `tmp/releases/<version>.yaml` for operator-generated local output
- optional future checked-in `deploy/releases/<version>.yaml` only if release
  manifests become reviewed deployment inputs

Required fields:

- release version, with both `vX.Y.Z` tag and `X.Y.Z` image tag forms
- repository name to commit SHA mapping
- workflow run URL for each published artifact
- digest-pinned image ref for:
  - `transaction-service`
  - `currency-service`
  - `permission-service`
  - `session-gateway`
  - `budget-analyzer-web`
  - `ext-authz`
- platform/infrastructure phase flags inferred by the operator, such as
  `platform_changed`, `infrastructure_changed`, `secrets_changed`,
  `observability_changed`, and `public_tls_reapply_required`

Validation rules:

- every image ref must be under `ghcr.io/budgetanalyzer/`
- every application image ref must include the release image tag and
  `@sha256:<digest>`
- no image ref may use `:latest`, `:tilt-`, or a mutable tag without a digest
- the manifest must include all runtime application images exactly once

### Phase 2: Release Preparation Helper

Add a local helper for the release manager.

Proposed script:

- `scripts/repo/prepare-lockstep-release.sh`

Responsibilities:

- validate the release repository set
- print current commit SHAs for all participating repositories
- verify every repository is clean and up to date
- verify the requested tag does not already exist remotely except for
  documented skip cases
- verify `service-common` checked-in version matches the requested tag version
- optionally call `scripts/repo/tag-release.sh` after a confirmation prompt
- print GitHub workflow URLs to monitor after tags are pushed

This script should not deploy to OCI. Its boundary is source release
preparation.

### Phase 3: Production Image Update Helper

Implement the helper already required by the lockstep plan:

- `deploy/scripts/23-update-production-release-images.sh`

Extend it to accept either explicit image arguments or a release manifest:

```bash
./deploy/scripts/23-update-production-release-images.sh \
  --release-manifest tmp/releases/v0.0.13.yaml
```

The explicit image-argument form remains useful for quick operator repair. The
manifest form becomes the normal path.

### Phase 4: OCI Lockstep Static Verifier

Implement the verifier already required by the lockstep plan:

- `deploy/scripts/24-verify-oci-upgrade-lockstep.sh`

This verifier is the main safety gate before any master script mutates the OCI
cluster.

### Phase 5: Master OCI Deployment Script

Add a single operator-facing master script.

Proposed script:

- `deploy/scripts/25-deploy-oci-release.sh`

Inputs:

- `--release-version <version>`
- `--release-manifest <path>`
- `--mode app-only|lockstep|platform-only|infrastructure-only|verify-only`
- `--dry-run`
- `--skip-platform`
- `--skip-infrastructure`
- `--skip-secrets`
- `--skip-observability`
- `--reapply-public-tls`
- `--acknowledge-public-tls-downgrade`, passed through only to the Istio
  reconcile step when required

Default behavior:

- require `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` or an explicit
  `--kubeconfig`
- refuse to run from the AI/container workspace when a step includes forbidden
  certificate generation
- load `~/.config/budget-analyzer/instance.env`
- run static verifiers before live apply
- capture a live preflight snapshot
- run selected deploy phases in the same reviewed order as `deploy/README.md`
- wait for every rollout it touches
- capture a post-deploy snapshot
- print a concise completion checklist

Mode behavior:

- `app-only` updates workloads from the already-reviewed production image
  baseline and verifies rollouts.
- `lockstep` runs platform, infrastructure, secret-sync, application,
  admission, observability, and optional public TLS phases according to explicit
  flags and the release manifest.
- `platform-only` reconciles k3s, Gateway API, Istio, platform controllers,
  network policies, Kyverno, and monitoring without applying app images unless
  requested.
- `infrastructure-only` renders/applies PostgreSQL, RabbitMQ, Redis, and
  related secret-sync changes without changing app images.
- `verify-only` runs static and live verification without applying changes.

The script should compose the existing numbered scripts rather than duplicate
their implementation.

### Phase 6: Checklist And Run Log Template

Add a concise deployment checklist template after the second deployment proves
which evidence is useful.

Proposed path:

- `docs/runbooks/oci-release-deployment-checklist.md`

The checklist should include:

- release version
- source commit table
- GitHub workflow run links
- digest-pinned image refs
- selected deployment mode
- preflight cluster snapshot
- scripts run
- rollout results
- smoke test results
- rollback notes

Keep exact recurring command sequences in the runbook or script help. Keep this
plan focused on implementation sequencing.

### Phase 7: GitHub-Triggered Deployment

After the host-side master script has been used successfully at least once, add
a GitHub workflow in this repository.

Proposed workflow:

- `.github/workflows/deploy-oci-release.yml`

Trigger:

```yaml
on:
  workflow_dispatch:
    inputs:
      release_version:
        required: true
        type: string
      orchestration_ref:
        required: true
        type: string
      mode:
        required: true
        type: choice
        options:
          - verify-only
          - app-only
          - lockstep
          - platform-only
          - infrastructure-only
      dry_run:
        required: true
        type: boolean
```

Controls:

- use a protected GitHub Environment such as `oci-production`
- require manual approval for non-`verify-only` runs
- use `actions/checkout@v6`
- set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`
- store SSH host, user, port, and deploy key as environment secrets
- pin the remote host key, do not disable host key checking
- run the checked-in master script on the OCI host over SSH
- upload command logs as workflow artifacts with secret redaction

The workflow should not contain deployment logic. It should only select a
version, transfer or select the reviewed repository checkout, and invoke
`deploy/scripts/25-deploy-oci-release.sh`.

## GitHub Workflow Boundaries

Allowed for the first GitHub-triggered deployment workflow:

- manual `workflow_dispatch`
- protected environment approval
- checkout of a reviewed orchestration ref
- SSH command execution on the OCI host
- `verify-only` and `app-only` modes after the host-side script has already
  been tested manually

Not allowed until separately planned:

- automatic production deploy on every tag push
- unmanaged self-hosted runner with broad repository access
- writing certificate material from a GitHub-hosted runner
- storing secret payloads in repository variables, checked-in manifests, or
  workflow logs
- GitHub workflow logic that bypasses the repo-owned deployment scripts

## Rollback Model

The reusable deployment path should support rollback by reapplying a previously
reviewed production image baseline and, when safe, rerunning the app-only mode.

Rollback limitations:

- database schema or data migrations need service-owned rollback plans
- RabbitMQ destination removal needs an explicit queue migration or discard
  decision
- platform downgrades are not normal rollback and require separate review
- public TLS and NLB changes should be restored through the checked-in scripts,
  not manual live drift

The release manifest contract should make image rollback fast by preserving the
previous digest-pinned image refs.

## Completion Criteria

This plan is complete when:

- the second deployment has a recorded release version, source commits, image
  digests, and deployment evidence
- `deploy/scripts/23-update-production-release-images.sh` exists and is
  validated
- `deploy/scripts/24-verify-oci-upgrade-lockstep.sh` exists and is validated
- `deploy/scripts/25-deploy-oci-release.sh` exists and composes the existing
  deploy scripts
- a runbook checklist exists for future releases
- a GitHub-triggered workflow exists or is explicitly deferred with rationale
- all modified shell scripts pass `bash -n` and `shellcheck`
- production image overlay and lockstep verifiers pass before OCI apply

