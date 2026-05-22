# Plan: Simplify Release Tags And Promotion Labels

Date: 2026-05-21
Status: In Progress

Related documents:

- `docs/ci-cd.md`
- `docs/OWNERSHIP.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `docs/runbooks/oci-candidate-deployment.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `scripts/README.md`
- `docs/plans/release-versioning-and-oci-deployment-flow-plan.md`
- `docs/plans/oci-repeatable-release-and-deployment-master-plan.md`

## Purpose

Remove unnecessary release-flow concepts now that OCI deployment correctness is
based on full-stack deployment snapshots and immutable image digests.

The target model should be easy to explain:

- Git tags are optional source bookmarks for named releases.
- Docker tags are temporary or human-readable registry labels.
- Image digests are the deployable artifact identity.
- Deployment snapshots are the production contract.
- Promotion labels exist only to push and trace images built by the promotion
  command.

Candidate-specific tags and candidate deployment status are not part of the
normal operator model. There is no retained accept/reject candidate workflow.

## Problem

The current repository still carries two candidate concepts that should be
removed:

- tag-driven release workflows accept `candidate-*` Git tags and publish the
  same value as the Docker image tag
- the full-stack OCI promotion command records deployment status with
  `--status candidate`

That creates confusion because the new production path does not need a source
tag prefix to know whether a deployment is a candidate. The full-stack
deployment snapshot already records status, source refs, image digests, content
identity, and build decisions.

The remaining `candidate-*` release workflow behavior is policy, not a
technical requirement. It prevents arbitrary tag names, but it also implies that
"candidate" is a special release artifact category. That is no longer a useful
default unless there is an explicit operational process around it.

## Target Model

### Normal OCI Promotion

The normal command remains:

```bash
./deploy/scripts/promote-current-stack-to-oci.sh
```

The command may keep generating Docker tags like:

```text
promotion-<deployment-id>-<content-hash>
```

Those tags are registry labels used to push images and retrieve immutable
digests. They are not release versions and should not be described as release
tags.

Production manifests and verifiers must continue to use digest-pinned image
references.

### Named Releases

Named source releases use SemVer Git tags:

```text
vX.Y.Z
```

Tag-driven image publishing may continue to map `vX.Y.Z` to Docker tag
`X.Y.Z`, but those images are still deployed by digest when they enter OCI.

### Ad Hoc Image Labels

Ad hoc Docker tags are acceptable when they are:

- Docker-safe
- unique enough for the intended scope
- never treated as production truth
- resolved to digest before deployment

Ad hoc labels should not require the word `candidate`.

### Deployment Status

Promotion snapshots should always represent the accepted intended OCI state.
Remove operator-facing candidate status and make promotion status always
`accepted`.

## Guiding Decisions

1. **Do not encode deployment lifecycle in source tag prefixes.**
   Deployment state belongs in the deployment snapshot.

2. **Keep promotion image tags structured.**
   `promotion-...` tags are useful because they are unique, traceable, and tied
   to a deployment id/content identity. They replace random registry labels for
   the promotion path, but they do not define deployment correctness.

3. **Keep SemVer tags for named releases only.**
   A SemVer Git tag should mean a human intentionally named a release. It should
   not be required for ordinary OCI promotion.

4. **Allow arbitrary ad hoc labels only outside the production contract.**
   If a workflow accepts a free-form Docker tag, it must still print or record
   the digest-pinned reference and must not publish `latest`.

5. **Remove candidate-specific ceremony.**
   Candidate tags and candidate deployment status add vocabulary without an
   active accept/reject process. They should be removed rather than retained as
   unused options.

## Proposed Implementation

### Phase 1: Documentation Simplification

Goals:

- Update `docs/ci-cd.md` as the canonical terminology owner.
- Define Git tags, Docker tags, image digests, deployment snapshots, and
  promotion labels in one place.
- State that `promotion-...` Docker tags are push/trace labels, not release
  identifiers.
- Remove or sharply narrow docs that recommend `candidate-*` tags.
- Remove docs that present candidate deployment status as an active option.
- Update superseded runbooks to point at the full-stack promotion command
  without presenting candidate tags or candidate status as normal.

Acceptance:

- A reader can explain the release/deployment model without using the word
  `candidate`.
- Current docs do not imply that OCI production promotion requires Git tags.
- Current docs do not imply that a Docker tag is production truth.
- Current docs do not present candidate status as an active deployment mode.

### Phase 2: Workflow Policy Cleanup

Goals:

- Remove `candidate-*` push triggers from tag-driven publish workflows.
- Decide whether manual `workflow_dispatch` should accept only SemVer Git tags
  or also an explicit ad hoc Docker label.
- Decision: retain ad hoc manual labels as a `docker_label` input. `release_ref`
  identifies the source ref to build; non-SemVer source refs require
  `docker_label`.
- If ad hoc labels are retained, name the input as a Docker label, not a release
  ref, and validate it as Docker-safe.
- Keep `latest` disallowed.
- Keep digest-pinned output in every publish workflow.

Acceptance:

- Release workflows no longer require `candidate-*` naming for non-SemVer test
  images.
- Any accepted ad hoc label is clearly documented as a Docker label, not a
  release.
- SemVer release behavior remains intact.

### Phase 3: Script Cleanup

Status: Completed 2026-05-22.

Goals:

- Remove or retire `scripts/repo/prepare-candidate-deployment.sh`.
- Update `scripts/README.md` to remove candidate-tag prep from the active
  script catalog.
- Remove `promote-current-stack-to-oci.sh --status candidate`.
- Remove the operator-facing `--status` option entirely unless another accepted
  status value has a concrete use.
- Always emit `status: "accepted"` in generated deployment snapshots.

Acceptance:

- There is no active script whose main purpose is creating candidate Git tags.
- The promotion command has one clear status model: accepted.
- Removed scripts are replaced by short superseded stubs only if needed for
  discoverability.

### Phase 4: Cross-Repo Alignment

Goals:

- Apply the workflow cleanup consistently in:
  - `../transaction-service`
  - `../currency-service`
  - `../permission-service`
  - `../session-gateway`
  - `../budget-analyzer-web`
  - this repository's `publish-ext-authz-release.yml`
- Keep workflow action versions aligned with the Node 24-ready baseline.
- Keep Java workflows' `service-common` package resolution behavior unchanged.

Acceptance:

- All publish workflows use the same release-ref and Docker-label language.
- All publish workflows reject `latest`.
- All publish workflows print digest-pinned image references.

### Phase 5: Verification

Goals:

- Validate modified shell scripts with:

  ```bash
  bash -n <script>
  shellcheck <script>
  ```

- Validate workflow syntax with the available local tooling.
- Run a non-mutating promotion diff:

  ```bash
  ./deploy/scripts/promote-current-stack-to-oci.sh --plan-only
  ```

Acceptance:

- The promotion dry run still produces a full-stack plan.
- The plan remains digest-oriented and complete for all managed workloads.
- No verifier or doc refers to candidate Git tags or candidate deployment
  status as an active production deployment step.

## Non-Goals

- Do not remove digest pinning.
- Do not publish `latest`.
- Do not require Git tags for normal OCI promotion.
- Do not make random Docker tags part of production correctness.
- Do not change service logic in sibling repositories.
- Do not add a second OCI environment.

## Open Decisions

1. Should manual publish workflows support ad hoc Docker labels, or should they
   accept only SemVer Git release tags?
2. If ad hoc labels are supported, should the label format be fully free-form
   Docker-safe text or a constrained prefix such as `manual-...`?
3. Should retired candidate scripts be deleted outright or replaced with
   superseded stubs for operator discoverability?
