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

The concrete first use case is the `v0.0.14` lockstep deployment: tag the
current Budget Analyzer repository heads, publish the matching release
artifacts, update the production image baseline, reconcile the OCI
platform/infrastructure/secret-sync baseline first, and only then roll out the
application images.

This plan does not replace the lockstep upgrade plan. The lockstep plan owns
the current dependency/platform compatibility work. This plan owns the reusable
release, checklist, and deployment automation shape that should survive this
specific upgrade.

## Target Outcome

The durable operator experience should become:

1. choose a release version, such as `v0.0.14`
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

The master script should eventually make normal future app-only releases
boring. The current `v0.0.14` release is not app-only; it follows the lockstep
path.

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

## Current v0.0.14 Lockstep Deployment Checklist

Use this checklist for the immediate deployment. It is the forward path for
`v0.0.14`; do not use the app-only path until after this lockstep upgrade is
complete and recorded.

### Phase A: AI Assistant Repo Automation

Owner: AI assistant, from the orchestration repo context.

Scope:

- Implement and validate repo-owned scripts and documentation.
- Update orchestration-owned production image, verification, and deployment
  automation.
- Update sibling repository documentation or configuration only when it is part
  of release/deployment wiring.
- Do not run git write operations, push tags, publish packages, mutate OCI, or
  run certificate-generating scripts unless the user explicitly asks from the
  correct host context.

Steps:

1. Maintain the release-image and lockstep gates:
   ```bash
   bash -n deploy/scripts/23-update-production-release-images.sh \
     deploy/scripts/24-verify-oci-upgrade-lockstep.sh \
     scripts/guardrails/verify-production-image-overlay.sh
   shellcheck deploy/scripts/23-update-production-release-images.sh \
     deploy/scripts/24-verify-oci-upgrade-lockstep.sh \
     scripts/guardrails/verify-production-image-overlay.sh
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ./scripts/guardrails/verify-production-image-overlay.sh
   ```
2. Maintain the service-common version bump helper:
   ```bash
   ./scripts/repo/update-service-common-version.sh --dry-run 0.0.14
   ./scripts/repo/update-service-common-version.sh --validate-only 0.0.14
   ```
3. When the user provides real release image refs, update the production
   baseline with:
   ```bash
   ./deploy/scripts/23-update-production-release-images.sh \
     --release-manifest tmp/releases/v0.0.14.yaml
   ```
   If no live Kubernetes context is available in the current shell, use
   `--skip-live-production-verifier` only as a temporary local limitation and
   run `./scripts/guardrails/verify-production-image-overlay.sh` before OCI
   apply.
4. Keep the plan, script catalog, and production README aligned whenever the
   workflow changes.

### Phase B: Human Release Preparation

Owner: human release manager.

Scope:

- Own git write operations, release tags, GitHub workflow approvals, package
  publication, and review/commit decisions.
- Run host-only or OCI-host-only operations from the correct host shell.
- Provide real image digests and deployment evidence.

Steps:

1. Review and commit the automation diff:
   ```bash
   git status --short
   git diff
   ```
2. Pick the release version:
   ```bash
   export RELEASE_VERSION=v0.0.14
   export IMAGE_VERSION=0.0.14
   ```
3. If service-common needs a release or next-snapshot version change, run:
   ```bash
   ./scripts/repo/update-service-common-version.sh --dry-run "${IMAGE_VERSION}"
   ./scripts/repo/update-service-common-version.sh "${IMAGE_VERSION}"
   ./scripts/repo/update-service-common-version.sh --validate-only "${IMAGE_VERSION}"
   ```
   Review and commit the resulting changes in the affected repositories before
   tagging.
4. Validate sibling repository state:
   ```bash
   ./scripts/repo/validate-repos.sh
   ```
   Resolve failures rather than tagging around them.
5. Confirm `service-common` has the intended release version in its Gradle
   metadata before tagging, because its publish workflow rejects tag/version
   mismatches.
6. Confirm the sibling service release workflows have access to
   `SERVICE_COMMON_PACKAGES_USERNAME` and `SERVICE_COMMON_PACKAGES_READ_TOKEN`.
7. Confirm the production secret prerequisites from the lockstep plan are ready,
   especially any new transaction-service preview import token secret and
   RabbitMQ definitions changes.

### Phase C: Human Tag And Publish

Owner: human release manager.

Steps:

1. Use the existing tag helper only after validating that its repository set is
   correct for this release:
   ```bash
   ./scripts/repo/tag-release.sh "${RELEASE_VERSION}"
   ```
2. If `checkstyle-config` should not receive an OCI runtime release tag, update
   the helper first or tag the runtime repos explicitly with documented
   commands. Do not silently create an inconsistent release set.
3. Confirm the tag push triggered each sibling `publish-release.yml` workflow.
4. Confirm `service-common` packages published successfully before relying on
   backend service image builds.
5. Confirm the service and frontend workflows published `linux/arm64` GHCR
   images.
6. Trigger this repo's `publish-ext-authz-release.yml` for the same tag if the
   tag push does not already do so.
7. Capture the digest-pinned image refs printed by each workflow.

### Phase D: Human Release Manifest Input

Owner: human release manager, with AI assistant support allowed for file
formatting after refs are provided.

Generate `tmp/releases/v0.0.14.yaml` from the published GHCR tags:

```bash
./scripts/repo/generate-release-manifest.sh 0.0.14 \
  --workflow-run-url transaction-service=https://github.com/budgetanalyzer/transaction-service/actions/runs/<id> \
  --workflow-run-url currency-service=https://github.com/budgetanalyzer/currency-service/actions/runs/<id> \
  --workflow-run-url permission-service=https://github.com/budgetanalyzer/permission-service/actions/runs/<id> \
  --workflow-run-url session-gateway=https://github.com/budgetanalyzer/session-gateway/actions/runs/<id> \
  --workflow-run-url budget-analyzer-web=https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/<id> \
  --workflow-run-url ext-authz=https://github.com/budgetanalyzer/orchestration/actions/runs/<id>
```

The generated file has this shape:

```yaml
release:
  version: "v0.0.14"
  image_tag: "0.0.14"
repositories:
  orchestration:
    commit: "<sha>"
artifacts:
  transaction-service:
    source_repository: "transaction-service"
    workflow_run_url: "https://github.com/budgetanalyzer/transaction-service/actions/runs/<id>"
    image: "ghcr.io/budgetanalyzer/transaction-service:0.0.14@sha256:<digest>"
phase_flags:
  platform_changed: false
  infrastructure_changed: false
  secrets_changed: false
  observability_changed: false
  public_tls_reapply_required: false
```

### Phase E: AI Assistant Or Human Production Baseline Update

Owner: AI assistant may run this locally after the human supplies real image
refs; human owns review and commit.

Steps:

1. Update the checked-in production baseline:
   ```bash
   ./deploy/scripts/23-update-production-release-images.sh \
     --release-manifest tmp/releases/v0.0.14.yaml
   ```
2. Review the exact diff:
   ```bash
   git diff -- kubernetes/production/apps deploy/instance.env.template \
     kubernetes/production/README.md scripts/README.md docs/ci-cd.md
   ```
3. Run the local proof:
   ```bash
   kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ./scripts/guardrails/verify-production-image-overlay.sh
   ./deploy/scripts/09-render-phase-5-secrets.sh
   ```
   `./deploy/scripts/09-render-phase-5-secrets.sh` requires the operator
   `~/.config/budget-analyzer/instance.env`. If that file is not present in the
   current shell, stop and run this proof on the OCI host or another operator
   shell where the non-secret instance config exists.
4. Commit or otherwise review the resulting production baseline before any live
   OCI mutation.

### Phase F: Human OCI Deployment

Owner: human operator on the OCI host.

This phase upgrades the live OCI baseline in dependency order. Run
platform/controller/infrastructure/secret-sync work before applying the
`v0.0.14` app image overlay.

Steps:

1. SSH to the OCI host, update the repo checkout to the reviewed release
   baseline, confirm the non-secret operator config exists, and set:
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ```
2. Capture the live baseline:
   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A
   helm list -A
   kubectl get deploy,statefulset -A
   ```
3. Run the OCI pre-apply gates:
   ```bash
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ./scripts/guardrails/verify-production-image-overlay.sh
   ```
4. Reconcile the platform and controller baseline before touching app images:
   ```bash
   ./deploy/scripts/01-install-k3s.sh
   ./deploy/scripts/02-bootstrap-cluster.sh
   ./deploy/scripts/04-install-istio.sh
   ./deploy/scripts/05-install-platform-controllers.sh
   ```
   If the live cluster already has public TLS and Istio must be reconciled,
   pass `--acknowledge-public-tls-downgrade` to
   `./deploy/scripts/04-install-istio.sh` only when the phase 11 public TLS
   manifests will be reapplied immediately in step 5.
5. If step 4 intentionally reconciled Istio over an already-public TLS host,
   immediately reapply the phase 11 public TLS manifests:
   ```bash
   ./deploy/scripts/16-render-phase-11-public-tls-manifests.sh
   kubectl apply -f tmp/phase-11/cluster-issuer.yaml
   kubectl apply -f tmp/phase-11/public-certificate.yaml
   kubectl apply -f tmp/phase-11/reference-grant.yaml
   kubectl apply -f tmp/phase-11/ingress-gateway-config.yaml
   kubectl apply -f tmp/phase-11/istio-gateway.yaml
   ```
6. Reapply and verify network policies before workloads:
   ```bash
   ./deploy/scripts/07-apply-network-policies.sh
   ./deploy/scripts/08-verify-network-policy-enforcement.sh
   ```
7. Reconcile secret synchronization and internal TLS before deploying app
   images that depend on the new secret contract. For `v0.0.14`, RabbitMQ
   definitions changed: `currency-service` now uses
   `exchange-rate.import.requested`, and the former `currency.created`
   destination must not be carried forward in the OCI definitions secret.
   ```bash
   set -euo pipefail
   ./deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh
   ./deploy/scripts/12-update-rabbitmq-definitions-secret.sh
   ./deploy/scripts/09-render-phase-5-secrets.sh
   ./deploy/scripts/10-apply-phase-5-secrets.sh
   kubectl get clustersecretstore budget-analyzer-oci-vault
   kubectl get externalsecret -A
   kubectl get externalsecret -n infrastructure rabbitmq-bootstrap-credentials
   kubectl get secret -n infrastructure rabbitmq-bootstrap-credentials
   kubectl get externalsecret -n default transaction-service-preview-import-token-credentials
   kubectl get secret -n default transaction-service-preview-import-token-credentials
   kubectl get secret -n infrastructure rabbitmq-bootstrap-credentials \
     -o jsonpath='{.data.definitions\.json}' \
     | base64 -d \
     | grep -F 'exchange-rate\\.import\\.requested'
   ! kubectl get secret -n infrastructure rabbitmq-bootstrap-credentials \
     -o jsonpath='{.data.definitions\.json}' \
     | base64 -d \
     | grep -F 'currency\\.created'
   ```
   The first grep must show the new `exchange-rate.import.requested`
   permissions. The second command must produce no `currency.created` entries.
   If internal PostgreSQL, Redis, or RabbitMQ TLS secrets are missing or
   intentionally rotating, run
   `./deploy/scripts/11-generate-phase-5-infra-tls.sh` from the OCI host.
8. Apply production infrastructure before app images. On a new or already
   migrated cluster, use the normal infrastructure apply path:
   ```bash
   ./deploy/scripts/17-render-production-infrastructure.sh
   sed -n '1,260p' tmp/production-infrastructure/infrastructure.yaml
   ./deploy/scripts/18-apply-production-infrastructure.sh
   ```
   If this OCI cluster still has the old Redis Deployment plus standalone
   `redis-data` PVC, run the guarded migration instead of the normal apply:
   ```bash
   ./deploy/scripts/19-migrate-production-redis-statefulset.sh --confirm-destroy-redis --restart-redis-clients
   ```
   Before deploying the matching `currency-service` image, remove obsolete
   empty RabbitMQ queues from the former destination. Check message counts
   first:
   ```bash
   kubectl exec -n infrastructure statefulset/rabbitmq -- rabbitmqctl list_queues -p / name messages \
     | grep 'currency.created.exchange-rate-import-service' || true
   kubectl exec -n infrastructure statefulset/rabbitmq -- rabbitmqctl delete_queue -p / currency.created.exchange-rate-import-service
   kubectl exec -n infrastructure statefulset/rabbitmq -- rabbitmqctl delete_queue -p / currency.created.exchange-rate-import-service.dlq
   ```
   Do not delete non-empty queues without an explicit migration or discard
   decision.
9. Apply the production route, ingress-policy, and Auth0 egress render output:
   ```bash
   ./deploy/scripts/13-render-phase-6-production-manifests.sh
   kubectl apply -f tmp/phase-6/gateway-routes.yaml
   kubectl apply -f tmp/phase-6/istio-ingress-policies.yaml
   kubectl apply -f tmp/phase-6/istio-egress.yaml
   ```
10. Apply the `v0.0.14` production app image overlay:
   ```bash
   kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone \
     | kubectl apply --server-side -f -
   kubectl rollout status deployment/transaction-service --timeout=300s
   kubectl rollout status deployment/currency-service --timeout=300s
   kubectl rollout status deployment/permission-service --timeout=300s
   kubectl rollout status deployment/session-gateway --timeout=300s
   kubectl rollout status deployment/ext-authz --timeout=300s
   kubectl rollout status deployment/nginx-gateway --timeout=300s
   ```
11. Reapply production admission and observability after image refs and platform
   resources converge:
   ```bash
   ./deploy/scripts/14-install-phase-7-kyverno.sh
   ./deploy/scripts/15-apply-phase-7-policies.sh
   ./deploy/scripts/22-apply-production-monitoring.sh --verify-runtime
   ```
12. Run focused production verification:
   ```bash
   kubectl get pods -A
   kubectl get gateway,httproute -A
   kubectl get peerauthentication,authorizationpolicy -A
   kubectl get networkpolicy -A
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ./scripts/guardrails/verify-production-image-overlay.sh
   ./deploy/scripts/08-verify-network-policy-enforcement.sh
   ./scripts/smoketest/verify-observability-port-forward-access.sh
   ./scripts/smoketest/verify-monitoring-runtime.sh --wait-timeout 180
   ```
13. From a workstation, verify the public route:
   ```bash
   curl -I https://demo.budgetanalyzer.org/
   curl -I https://demo.budgetanalyzer.org/api-docs
   ```

Do not run certificate-generating scripts from the AI container. If public TLS
or infra TLS has to be generated or rotated, run those host-side only.

## Reusable Automation Work

This section is future automation work. It is not the live `v0.0.14` runbook.

### Phase 1: Release Manifest Contract

Status: Implemented for local operator-generated manifests.

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

Status: Implemented as `scripts/repo/prepare-lockstep-release.sh`.

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

Status: Implemented for explicit image arguments and release manifest input.

Implement the helper already required by the lockstep plan:

- `deploy/scripts/23-update-production-release-images.sh`

Extend it to accept either explicit image arguments or a release manifest:

```bash
./deploy/scripts/23-update-production-release-images.sh \
  --release-manifest tmp/releases/v0.0.14.yaml
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

## Follow-Up: Runtime Service Version Metadata

The Java runtime service repos currently keep their Gradle project versions at
`0.0.1-SNAPSHOT`, while release workflows derive deployable image identity from
the shared release tag and publish digest-pinned images. That is acceptable for
this deployment path, because production deploys consume immutable image refs,
not service Gradle project versions.

After the repeatable release path is proven, decide whether to:

- document Java service `project.version` values as local build metadata only
- derive service build metadata from the release tag during CI
- update service Gradle project versions as part of a coordinated release
  preparation helper

Do not make this a Phase B blocker unless runtime endpoints, JAR metadata, or
operator evidence need the services themselves to report the exact release
version.
