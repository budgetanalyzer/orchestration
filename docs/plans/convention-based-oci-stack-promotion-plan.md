# Plan: Convention-Based OCI Stack Promotion

Date: 2026-05-21
Status: Draft

Related documents:

- `docs/ci-cd.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `docs/plans/release-versioning-and-oci-deployment-flow-plan.md`
- `docs/plans/oci-repeatable-release-and-deployment-master-plan.md`
- `scripts/README.md`

## Purpose

Simplify OCI deployment around one normal operator use case:

> Run the full system locally, then push this exact intended stack to OCI.

The deployment system should snapshot the current workspace state, compare it
with the accepted OCI production baseline, leave unchanged runtime artifacts in
place, build and push only changed artifacts, and then apply one complete
production deployment snapshot.

This should replace the current highly configurable release/deployment paths
where possible. The goal is convention over configuration: production promotion
should have one clear meaning and very few partially valid states.

## Problem

The current release tooling supports too many shapes:

- full lockstep release manifests
- schema v2 deployment manifests
- app-only deployment modes
- service-scoped app deployment
- config-only and single-service style manifest generation
- tag-name-oriented release verification

Those modes have started to create contradictory contracts. Recent review
findings exposed the same underlying design issue:

- Service scoping can accidentally turn a manifest deployment into a partial
  production apply.
- Manifest generation can drop existing Java `service-common` metadata when
  only some services or config changed.
- Lockstep release helpers still point operators at a manifest shape that the
  production baseline update script no longer accepts.

These should not be treated as three isolated bugs if the desired operating
model no longer needs those paths.

## Target Operator Experience

The durable command should be a single promotion entry point, for example:

```bash
./deploy/scripts/promote-current-stack-to-oci.sh
```

The command means:

1. Discover every managed OCI workload by repo convention.
2. Snapshot the current intended local stack.
3. Read the current accepted OCI production baseline.
4. Compare desired state to production state.
5. Reuse unchanged digest-pinned images and metadata.
6. Build and push changed `linux/arm64` images.
7. Generate one complete deployment snapshot.
8. Apply the full production application set.
9. Verify production by image digests and runtime metadata.

There should be no `--services`, no deployment `--mode`, no separate
lockstep-release manifest path, and no successful partial production manifest
apply.

## Guiding Decisions

1. **The promotion unit is the full managed stack.**
   Production promotion always reasons about every managed workload, even when
   only one workload changed.

2. **Image digests are deployment truth.**
   Tags may remain useful labels for humans and registry browsing, but
   production apply and verification should use immutable image digests.

3. **Unchanged artifacts are carried forward explicitly.**
   If a service's build inputs are unchanged, the new deployment snapshot
   records the existing production digest and metadata instead of rebuilding or
   retagging it.

4. **Changed artifacts are detected by source and build inputs.**
   A changed service repository, changed frontend source, changed local
   orchestration-owned image source, or changed shared build input marks the
   affected workload for rebuild.

5. **`service-common` changes naturally affect Java services.**
   There is no special lockstep release mode. If `service-common` changes, Java
   services that consume it become changed through the snapshot dependency
   model.

6. **Runtime metadata is part of the deployment contract.**
   Source commit, dirty/content identity, image digest, artifact identity, and
   Java `service-common` identity must be preserved or recomputed for every
   workload in every complete snapshot.

7. **Live Tilt state is not the deployable artifact.**
   "Push this exact stack" means rebuild from the current workspace contents
   and deploy the resulting image digests. Tilt live-update pod filesystem
   state should not be scraped as an OCI artifact.

## Desired Snapshot Contract

The exact schema can be refined during implementation, but the complete
deployment snapshot should include:

- deployment id and creation timestamp
- target environment, initially `oci-production`
- orchestration repository commit and workspace state
- complete managed workload list
- per-workload source repository and source commit
- per-workload dirty/content identity when local changes are included
- per-workload image repository and immutable deployed digest
- per-workload build decision: `reused` or `rebuilt`
- per-Java-workload `service-common` identity
- runtime labels and annotations needed by `/api-docs` and verifiers
- production baseline input used for unchanged artifact carry-forward

The snapshot should be complete enough that `/api-docs` release metadata,
production image inventory, runtime labels, and verifier inputs all derive from
the same source.

## Design Impact On Current Review Findings

### Service Scoping Outside App-Only Deployments

Resolved by removing service-scoped production promotion.

The promotion command always generates and applies a complete production
application snapshot. Targeted local development and diagnostics can remain
separate tools, but they must not share the production promotion contract.

### Dropped `service-common` Metadata

Resolved by making shared-library identity part of the required full snapshot
contract.

For unchanged Java workloads, the promotion flow carries forward the existing
accepted production `service-common` metadata. For changed Java workloads, it
recomputes the metadata from the build inputs. A complete deployment snapshot
must never omit the field for Java services.

### Lockstep Release Manifest Compatibility

Resolved by deleting the special lockstep release input path from the normal
OCI deployment model.

If every service changed, the full-stack diff will rebuild and deploy every
service naturally. If only `service-common` changed, Java services will become
changed naturally. A separate `generate-release-manifest.sh` shape should not
remain a production deployment input unless there is a concrete future use case
that justifies it.

## Proposed Implementation Phases

### Phase 0: Freeze The Desired Contract

Status: Proposed.

Goals:

- Decide that full-stack OCI promotion is the only normal production
  deployment path.
- Mark partial production promotion, service-scoped production manifests, and
  lockstep release manifests as deprecated or removed.
- Define the complete snapshot fields required by production apply,
  `/api-docs`, image inventory, and runtime verification.

Acceptance:

- `docs/ci-cd.md`, `deploy/README.md`, and
  `kubernetes/production/README.md` describe one normal OCI promotion model.
- Existing plan docs are either superseded or clearly marked as historical
  design context.

### Phase 1: Build Snapshot And Diff Primitives

Status: Proposed.

Goals:

- Add a script that discovers the managed workload set by convention.
- Add a script that snapshots local desired state for each workload.
- Add a script that reads the accepted OCI production baseline.
- Add a diff step that decides `reused` versus `rebuilt` per workload.

Acceptance:

- The diff can run without mutating OCI or pushing images.
- The output explains why each workload is reused or rebuilt.
- Java services always include `service-common` identity in the snapshot.

### Phase 2: Generate Complete Deployment Snapshot

Status: Proposed.

Goals:

- Emit one schema for the complete OCI deployment snapshot.
- Ensure unchanged workloads carry forward existing digest and metadata.
- Ensure changed workloads reserve fields for the pushed digest produced later.
- Make `/api-docs` metadata, image inventory, and runtime labels derive from
  the same snapshot data.

Acceptance:

- A config-only orchestration change produces a full snapshot with all runtime
  image digests carried forward.
- A single service change produces a full snapshot with exactly that service
  marked for rebuild.
- A `service-common` change marks affected Java services for rebuild.

### Phase 3: Build, Push, Apply, And Verify

Status: Proposed.

Goals:

- Build and push only workloads marked `rebuilt`.
- Update the complete snapshot with registry-returned immutable digests.
- Apply the full production application overlay from the complete snapshot.
- Verify deployed workloads by digest and runtime metadata, not tag names.

Acceptance:

- The promotion command can complete a full OCI app deployment from one
  snapshot.
- Verification fails if any managed workload is missing, stale, or carrying
  incomplete Java shared-library metadata.
- No production promotion path accepts `--services`.

### Phase 4: Remove Superseded Release Paths

Status: Proposed.

Goals:

- Remove or retire lockstep manifest generation as a production deployment
  input.
- Remove production script options that create partial deployment ambiguity.
- Delete obsolete tag-name release verification that is no longer needed for
  deployment correctness.
- Keep any remaining tag helpers clearly scoped to human source-management
  workflows, not production apply correctness.

Acceptance:

- There is one documented OCI production promotion entry point.
- Old release manifest shapes are not referenced by current operator docs.
- Shell script validation passes for modified scripts:

  ```bash
  bash -n <script>
  shellcheck <script>
  ```

## Non-Goals

- Do not introduce a second OCI staging environment.
- Do not deploy directly from scraped live pod filesystem state.
- Do not preserve old manifest shapes for legacy compatibility unless a new
  concrete use case appears.
- Do not make tag names part of production correctness verification.
- Do not add orchestration-level workarounds for service-owned build or runtime
  contract defects.

## Open Decisions

- Whether dirty workspace promotion is allowed by default, rejected by default,
  or allowed only with an explicit flag.
- The exact content identity mechanism for dirty workspaces.
- Whether the accepted production baseline lives only in
  `kubernetes/production/apps/image-inventory.yaml` or in a newer complete
  snapshot file that then renders the inventory.
- Whether the promotion command runs only from the operator machine or later
  becomes a GitHub `workflow_dispatch` entry point over SSH to the OCI host.
- How aggressively to delete old release scripts versus keeping them as
  explicitly historical utilities during the transition.
