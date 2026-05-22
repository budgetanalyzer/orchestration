# Plan: OCI Deployment Simplification

Date: 2026-05-22

Related documents:

- `docs/ci-cd.md`
- `deploy/README.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `kubernetes/production/apps/deployment-manifest.yaml`
- `kubernetes/production/apps/image-inventory.yaml`
- `deploy/scripts/promote-current-stack-to-oci.sh`
- `deploy/scripts/23-update-production-release-images.sh`
- `deploy/scripts/25-deploy-oci-release.sh`

## Intent

Simplify, simplify, simplify.

The OCI deployment path has accumulated too many concepts: promotion-specific
image tags, local Docker builds, generated deployment snapshots, manifest
statuses such as `accepted`, local-to-OCI kubeconfig coupling, and overlapping
scripts whose boundaries are hard to explain.

This plan intentionally favors deletion over compatibility. Do not preserve the
current promotion workflow behind aliases, compatibility flags, or migration
layers unless a concrete production safety requirement proves it is necessary.
The goal is a smaller operator model that is easy to explain and hard to misuse.

## Desired Operator Workflow

The durable workflow should be:

```text
Local workstation:
  1. Run one script that declares the intended OCI deployment.
  2. The script creates and pushes any missing source tags.
  3. GitHub Actions builds the required images.
  4. The script waits for the images, reads their GHCR digests, and updates the
     orchestration production manifest locally.
  5. The operator reviews, commits, and pushes the orchestration diff.

OCI host:
  1. Pull the latest orchestration repo.
  2. Run one script that deploys the checked-in manifest.
  3. The script verifies that live pods match the checked-in manifest.
```

The local script must not build Docker images. The OCI script must not inspect
sibling source repositories. Neither script should need to understand
`promotion-*` images or manifest lifecycle statuses.

## Principles

- GitHub Actions builds OCI images.
- Local deployment preparation updates desired state, not live OCI.
- OCI deployment applies checked-in desired state, not local workspace state.
- The production manifest is a desired-state file, not an approval workflow.
- Deployment status is live cluster state: the manifest is deployed or it is not.
- Digest-pinned image references remain mandatory.
- Human review of the orchestration diff remains mandatory before OCI applies it.
- Remove legacy terminology and scripts instead of documenting around them.

## Target Commands

Local workstation:

```bash
./deploy/scripts/prepare-oci-manifest-from-current-stack.sh
```

OCI host:

```bash
git pull
./deploy/scripts/deploy-current-oci-manifest.sh
```

The final script names can change, but the boundary should not:

- prepare locally
- review and commit
- deploy on OCI

## Local Preparation Script

The local script should:

1. Validate that the expected sibling repositories exist.
2. Validate source workspace cleanliness, unless an explicit dirty-source mode
   is intentionally retained for development-only testing.
3. Determine the intended source ref for each deployable artifact:
   - `transaction-service`
   - `currency-service`
   - `permission-service`
   - `session-gateway`
   - `budget-analyzer-web`
   - `ext-authz` from this repo
4. Create and push missing source tags when a new image build is needed.
5. Trigger or rely on the existing GitHub image-build workflows for those tags.
6. Wait until the expected GHCR image tags exist.
7. Resolve each expected image to an immutable digest.
8. Update the checked-in production desired-state files:
   - `kubernetes/production/apps/deployment-manifest.yaml`
   - `kubernetes/production/apps/image-inventory.yaml`
   - `kubernetes/production/apps/kustomization.yaml`
   - `kubernetes/production/apps/patches/runtime-release-metadata.yaml`
   - `kubernetes/production/docs-aggregator/release-metadata.json`
9. Run the static production verifiers that do not require OCI mutation.
10. Stop and tell the operator to review, commit, and push the diff.

The local script should not:

- require Docker
- require Docker Buildx
- require QEMU/binfmt
- push GHCR images directly
- deploy to OCI
- require OCI kubeconfig access
- require SSH tunneling to OCI
- write `promotion-*` image tags
- write deployment lifecycle status fields such as `accepted`

## OCI Deployment Script

The OCI script should:

1. Read the checked-in production manifest.
2. Validate that the manifest and image inventory agree.
3. Render/apply the production route, ingress policy, egress, and app overlay
   that are already repo-owned.
4. Wait for managed application rollouts.
5. Verify live runtime metadata and live images against the checked-in manifest.
6. Print the small post-deploy verification checklist.

The OCI script should not:

- require sibling service repositories
- create source tags
- build images
- push images
- mutate the production manifest
- understand local workspace dirty state
- perform certificate generation
- preserve the old promotion snapshot model

## Concepts To Remove

Remove these from the normal deployment path:

- `promotion-*` Docker tags
- local Docker image builds for OCI app promotion
- `deployment.status: accepted`
- "promotion plan" as the primary operator artifact
- one command that both prepares local desired state and deploys live OCI
- local workstation kubeconfig tunneling as a normal deployment prerequisite
- OCI host source-repo discovery for deployable services
- duplicate lower-level scripts that only exist to support the promotion model

If any old script remains temporarily during the cleanup, mark it deprecated and
remove it before the plan is considered complete.

## Manifest Shape

The manifest should describe desired state only:

- deployment identifier or manifest version
- generated timestamp, if useful for review
- orchestration source revision, if useful for traceability
- per-artifact source repository
- per-artifact source ref or tag
- per-artifact source commit
- per-artifact digest-pinned image
- per-artifact `service-common` version for Java services

Avoid status fields unless they describe observed live cluster state in a
separate runtime report. A checked-in desired-state file should not claim that a
deployment is `accepted`, `pending`, or `deployed`.

## GitHub Workflow Requirements

The service and frontend repositories should continue to own their image builds.
The orchestration local preparation script can wait on GHCR, not on a sibling
repo writing back to orchestration.

Minimum requirement:

- pushed source tag causes the owning repo's workflow to publish a GHCR image
- image tags are predictable from the source tag
- images are published for `linux/arm64`
- Java image builds resolve published `service-common` through GitHub Packages
- the local preparation script can resolve the final digest from GHCR

Do not introduce sibling-repo write access to orchestration as part of this
cleanup.

## Implementation Phases

### Phase 1: Freeze The Target Model

Status: Complete as of 2026-05-22.

- Update `docs/ci-cd.md` so the canonical deployment model matches this plan.
- Update `deploy/README.md` to present the two-command workflow only.
- Update the OCI checklist so it records manifest preparation, commit, pull,
  deploy, and verification.
- Remove or clearly mark promotion terminology as obsolete in active docs.

### Phase 2: Build The Local Preparation Command

Status: Complete as of 2026-05-22.

- Create the local preparation script.
- Reuse existing tag helpers where they fit the simplified model.
- Reuse existing manifest writers only if they can be simplified without
  carrying promotion concepts forward.
- Add focused validation for missing tags, missing GHCR images, digest format,
  manifest/image inventory agreement, and production overlay rendering.

### Phase 3: Build The OCI Apply Command

Status: Complete as of 2026-05-22.

- Create the OCI deployment script that applies the checked-in manifest.
- Keep it free of source repo discovery and image publishing behavior.
- Keep live verification strict: if pods do not match the manifest, fail.

### Phase 4: Delete The Promotion Path

Status: Complete as of 2026-05-22.

- Remove or retire `deploy/scripts/promote-current-stack-to-oci.sh`.
- Remove generated promotion-plan language from active docs.
- Remove `promotion-*` image tag handling.
- Remove manifest status fields from generated desired-state files.
- Delete lower-level helpers that only remain to support the old combined
  prepare-and-deploy command.

### Phase 5: Tighten Verification

- Make the production manifest, image inventory, kustomization, runtime metadata
  patch, and release metadata agreement checks the main gate.
- Keep the live verifier focused on one question: does OCI match the checked-in
  manifest?
- Update scripts and docs so the happy path is short and the failure messages
  name the missing prerequisite directly.

## Completion Criteria

- A local operator can prepare an OCI manifest without Docker, Buildx, QEMU,
  GHCR push credentials, OCI kubeconfig, or SSH tunnels.
- The local preparation command produces a reviewable orchestration diff.
- OCI deployment requires only the orchestration repo, cluster access, and the
  existing non-secret instance config.
- No active documentation tells operators to use `promotion-*` tags or a
  combined local-build/live-deploy command.
- The checked-in production manifest has no lifecycle status field.
- Live deployment verification proves deployed-or-not by comparing OCI pods to
  the checked-in manifest.
