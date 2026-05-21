# Plan: Release Versioning And OCI Deployment Flow Separation

Date: 2026-05-21
Status: Draft

Related documents:

- `docs/plans/oci-repeatable-release-and-deployment-master-plan.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `docs/ci-cd.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `docs/development/service-common-artifact-resolution.md`
- `../service-common/docs/versioning-and-compatibility.md`

## Purpose

Separate the concepts that the first repeatable OCI release flow intentionally
treated as one lockstep unit:

- source tags
- service artifact versions
- `service-common` Maven versions
- deployment/environment identity
- GitHub Releases or release notes

The `v0.0.14` flow proved the system can produce digest-pinned release images,
update the production image baseline, and deploy through a repeatable OCI
script. That remains the right model for rare lockstep releases. It should not
remain the only normal deployment model for a microservice system.

This plan evolves the current lockstep release machinery toward:

- config-only orchestration deployments
- single-service release and rollback
- tag-required OCI candidate deployments
- later commit-SHA candidate deployments
- eventual continuous deployment after independent black-box gates are strong
  enough

## Constraints

- There is one OCI Free Tier instance. It is both the staging proving ground and
  the production runtime.
- Do not add a second paid staging instance.
- Do not hide service-owned contract failures with orchestration workarounds.
- Production deployment state must remain repo-owned, repeatable, and
  digest-pinned.
- Observability remains internal-only.
- Certificate generation remains host-only and must not run from the AI
  container.
- Git write operations remain human-owned unless explicitly requested.

## Terms

Use these terms consistently in scripts and docs.

| Term | Meaning |
| --- | --- |
| `service-common` version | Maven coordinate for the shared Java libraries, for example `0.0.14` or `0.0.15-SNAPSHOT`. |
| Artifact version | A deployable runtime artifact version for one service or frontend image. This may be SemVer, a candidate tag, or later a commit-derived image tag. |
| Source ref | The Git ref used to build an artifact: SemVer tag, candidate tag, or commit SHA. |
| Image digest | The immutable container image identity used for deployment. This is the real deployable artifact identity. |
| Deployment manifest | The reviewed record of exactly which artifact digests, source refs, config flags, and orchestration revision are intended for OCI. |
| Deployment revision | The environment state identifier for OCI. It may contain mixed service versions. |
| Release tag | A SemVer tag such as `v0.0.15` that marks a named release. |
| Candidate tag | A non-SemVer tag that marks a deployable test candidate, for example `candidate-transaction-service-20260521-abc123`. |
| OCI staging window | A controlled period where the single OCI production slot runs candidate state for verification before it is recorded as accepted production state or rolled back. |
| Promotion | Recording a tested deployment manifest as the accepted production baseline. On one OCI instance, promotion may be metadata-only because the tested bits are already live. |

## Guiding Decisions

1. **Image digests are deployment truth.**
   Tags select source and name artifacts, but OCI deploys digest-pinned images.

2. **The production environment can contain mixed artifact versions.**
   A single global `release-version` is not a durable model once services are
   released independently.

3. **`service-common` is a library, not the stack version.**
   Do not bump `service-common` for a service release unless the shared library
   changed or the service intentionally consumes a newer shared-library
   version.

4. **Tags remain useful, but not every tag is a release.**
   SemVer tags are named releases. Candidate tags are deployable source
   selectors. Later, commit SHAs can become deployable source selectors after
   the independent test harness is strong enough.

5. **One OCI instance means staging is a workflow, not a second environment.**
   The first durable step is a controlled staging window on the same production
   slot. A second namespace or parallel stack can be considered later only if
   the cost in Auth0, TLS, data isolation, and resource pressure is justified.

6. **Continuous deployment is a maturity target, not the starting point.**
   The system should not auto-promote service-local test results alone. CD
   requires independent black-box API and security gates that exercise the real
   edge path.

## Target Deployment Manifest Shape

The next manifest contract should support mixed artifact versions and
deployment identity. Exact YAML can change during implementation, but it should
carry this information:

```yaml
schema_version: 2
deployment:
  id: "oci-20260521.1"
  environment: "oci-production"
  status: "candidate"
  orchestration_repository:
    commit: "<orchestration-sha>"
    source_ref: "refs/heads/main"
artifacts:
  transaction-service:
    source_repository: "transaction-service"
    source_ref: "refs/tags/v0.0.15"
    source_commit: "<sha>"
    artifact_version: "0.0.15"
    image: "ghcr.io/budgetanalyzer/transaction-service:0.0.15@sha256:<digest>"
    service_common_version: "0.0.14"
  currency-service:
    source_repository: "currency-service"
    source_ref: "refs/tags/v0.0.14"
    source_commit: "<sha>"
    artifact_version: "0.0.14"
    image: "ghcr.io/budgetanalyzer/currency-service:0.0.14@sha256:<digest>"
    service_common_version: "0.0.14"
phase_flags:
  platform_changed: false
  infrastructure_changed: false
  secrets_changed: false
  observability_changed: false
  public_tls_reapply_required: false
verification:
  required_gates:
    - production-image-overlay
    - network-policy
    - api-black-box
    - security-black-box
```

The browser-visible `/api-docs/release-metadata.json` should be generated from
this data and report:

- deployment id
- deployment status or accepted production timestamp
- orchestration revision
- per-artifact version, source ref, source commit, and digest-pinned image
- Java services' consumed `service-common` version

It should not imply that every service is on one stack version when the
deployment is mixed.

## Immediate Policy For The `/api-docs` Patch

The `/api-docs` metadata patch after `v0.0.14` should be treated as an
orchestration/config deployment on top of the `v0.0.14` runtime artifact set.

Do not bump every service or `service-common` only to ship metadata and
manifest/config changes. The existing `0.0.14` image inventory can remain the
runtime artifact baseline while the orchestration checkout moves forward and
reapplies the production app overlay.

Evidence to capture:

- orchestration commit containing the `/api-docs` metadata fix
- current production image inventory still pinned to the `0.0.14` runtime
  digests
- rendered production overlay includes the updated ConfigMap content
- `curl -fsS https://demo.budgetanalyzer.org/api-docs/release-metadata.json`
  shows the intended metadata

## Phases

### Phase 0: Document The New Operating Model

Status: Implemented.

Goals:

- Make the terminology above the shared language for future script and runbook
  changes.
- Keep the current lockstep flow documented as one supported mode, not the only
  mode.
- Explicitly document the one-OCI staging-window model.
- Record that `service-common` is released only when the shared library changes.

Docs to update:

- `docs/ci-cd.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `docs/development/service-common-artifact-resolution.md`
- `../service-common/docs/versioning-and-compatibility.md`

Acceptance:

- Docs distinguish lockstep release, single-service release, config-only
  deployment, candidate deployment, and promotion.
- Docs no longer imply that every production deployment must bump
  `service-common` or every runtime artifact.

### Phase 1: Split Repository Sets And Deprecate All-Repo Tags For Normal Releases

Status: Implemented.

Goals:

- Keep all-repo lockstep tags available for rare coordinated stack releases.
- Add explicit repo-set names for normal workflows.
- Remove `checkstyle-config` from OCI runtime release assumptions.
- Make service-specific release preparation possible without touching
  unrelated repos.

Script changes:

- Update `scripts/repo/repo-config.sh` with separate arrays:
  - runtime image repos
  - Java runtime repos
  - infrastructure/orchestration repo
  - shared library repo
  - tooling repos
  - lockstep release repos
- Rename or wrap `scripts/repo/tag-release.sh` so the default normal path is no
  longer "tag every repository."
- Keep a clearly named lockstep helper, such as
  `scripts/repo/tag-lockstep-release.sh`, for rare coordinated releases.
- Add a service release preparation helper, such as
  `scripts/repo/prepare-service-release.sh --service transaction-service
  --version 0.0.15`.

Acceptance:

- A normal single-service release can validate and tag one service repo without
  validating or tagging unrelated runtime repos.
- Lockstep release tooling still exists and remains explicit.
- `checkstyle-config` is not treated as an OCI runtime artifact.
- Lockstep tagging can preview and apply only the tags missing from the
  current local deployable repo state.

### Phase 2: Add Deployment Manifest V2 And Mixed Artifact Metadata

Status: Implemented.

Goals:

- Replace the single global production `release-version` assumption with a
  deployment manifest that allows mixed artifact versions.
- Keep digest-pinned image inventory and Kustomize render behavior.
- Generate `/api-docs/release-metadata.json` from the new manifest shape.
- Verify pods against expected per-workload metadata, not one global version.

Script changes:

- Add `scripts/repo/generate-deployment-manifest.sh`.
- Update `deploy/scripts/23-update-production-release-images.sh`, or replace it
  with a clearer `deploy/scripts/23-update-production-deployment-baseline.sh`,
  to:
  - start from the existing production inventory
  - update one or more artifact images
  - preserve unchanged artifact digests
  - write deployment metadata
  - write runtime labels and annotations per workload
- Update `scripts/ops/show-pod-version-labels.sh` to accept a deployment
  manifest and verify per-workload expected labels/annotations.
- Update `deploy/scripts/25-deploy-oci-release.sh` to require
  `--deployment-manifest`; the v1 release-manifest deployment path is removed.

Manifest and metadata changes:

- Add `schema_version: 2`.
- Add deployment id/status fields.
- Add per-artifact `source_ref`, `source_commit`, `artifact_version`,
  `image`, and optional `service_common_version`.
- Add orchestration commit and source ref.
- Update `docs-aggregator/release-metadata.json` and
  `kubernetes/production/docs-aggregator/release-metadata.json` generation.

Acceptance:

- A manifest with `transaction-service: 0.0.15` and other artifacts still on
  `0.0.14` renders successfully.
- Production verifiers reject missing digests, mutable image refs, mismatched
  runtime metadata, and stale `/api-docs/release-metadata.json`.
- `/api-docs/release-metadata.json` shows mixed artifact versions accurately.

### Phase 3: Implement Single-Service Release And Rollback

Goals:

- Make "release one service" a first-class path.
- Allow OCI app-only deployment to roll one or more selected workloads.
- Preserve rollback to the previous digest for that service.

Workflow:

1. Merge a service change to the service repo's `main`.
2. Tag that service repo with a SemVer tag, for example `v0.0.15`.
3. Let that repo's release workflow publish a `linux/arm64` image by digest.
4. Generate a deployment manifest that changes only that service image and
   preserves every other image from the existing production baseline.
5. Update the production deployment baseline from the manifest.
6. Run static verifiers.
7. Open an OCI staging window and run app-only deploy for the selected
   workload.
8. Run focused black-box smoke tests plus the existing production verifiers.
9. Record the manifest as accepted production state.

Script changes:

- Add `--service` or `--artifact` selection to manifest generation.
- Add `--services transaction-service,currency-service` to
  `deploy/scripts/25-deploy-oci-release.sh` for app-only rollout and rollout
  status checks.
- Add rollback helper support for one service, for example:
  `deploy/scripts/26-rollback-oci-artifact.sh --service transaction-service
  --to-manifest <previous-manifest>`.

Runbook changes:

- Add `docs/runbooks/oci-single-service-release.md`.
- Add `docs/runbooks/oci-single-service-rollback.md`.
- Update `docs/runbooks/oci-release-deployment-checklist.md` so the evidence
  table supports mixed versions.

Acceptance:

- A one-service manifest updates only the selected service image and metadata.
- Deploying that manifest rolls only the selected app workload plus any
  required edge workload such as `nginx-gateway` when docs/frontend assets
  changed.
- Rollback can restore the previous digest for one service without reverting
  unrelated artifacts.

### Phase 4: Add Tag-Required Candidate Deployments

Goals:

- Allow OCI candidate deployments before SemVer release tags.
- Keep source selection immutable and auditable.
- Avoid arbitrary branch deploys until independent gates are strong enough.

Candidate tag policy:

- Candidate tags are Git tags, not GitHub Releases.
- Candidate tags must not start with `v`.
- Candidate tags should encode service, date, and short commit:
  `candidate-transaction-service-20260521-abc123`.
- Candidate images use Docker-safe tags derived from the candidate tag:
  `candidate-transaction-service-20260521-abc123`.
- Candidate manifests set deployment status to `candidate`.
- Candidate tags may be cleaned up only after the manifest and workflow evidence
  are no longer needed.

Workflow changes:

- Extend runtime image workflows to support tag patterns:
  - `v*` for SemVer releases
  - `candidate-*` for candidate images
- Keep `workflow_dispatch` restricted to existing tags in this phase.
- Do not publish `latest`.
- Do not create a GitHub Release for candidate tags.
- Print digest-pinned image refs exactly as release workflows do today.

Runbook changes:

- Add `docs/runbooks/oci-candidate-deployment.md`.
- Document the staging-window protocol:
  - announce candidate window
  - capture preflight state
  - deploy candidate manifest
  - run gates
  - accept and record, or roll back
  - capture post-window state

Acceptance:

- A non-SemVer candidate tag can build and publish a digest-pinned image.
- OCI can deploy a candidate manifest with status `candidate`.
- The candidate can be accepted without rebuilding if the digest is the same
  image intended for production, or retagged/rebuilt as a SemVer release if a
  named release artifact is required.

### Phase 5: Build Independent Black-Box API And Security Gates

Goals:

- Create the test foundation needed before branch or commit-driven deployment.
- Keep deployment gates outside the service codebase being tested.
- Exercise the real edge path rather than in-process service internals.

Repository placement decision:

- Short term: orchestration can own the cross-service deployment gate because it
  already owns platform wiring and OCI deployment scripts.
- Longer term: consider a dedicated sibling repository such as
  `budget-analyzer-api-tests` if the test harness becomes large enough to
  deserve independent ownership, release cadence, and CI.

Test scope:

- Public edge tests through `https://demo.budgetanalyzer.org`.
- Auth/session lifecycle through Session Gateway where applicable.
- Representative `/api/...` workflows through NGINX and Istio `ext_authz`.
- Role and permission negative tests.
- Header spoofing and unauthenticated request negative tests.
- OpenAPI contract availability and basic schema compatibility.
- Data setup/teardown through public APIs or documented operator fixtures, not
  service-private implementation hooks.
- Focused smoke coverage for `/api-docs/release-metadata.json`.

Script and CI changes:

- Add `scripts/smoketest/verify-oci-api-black-box.sh` or a dedicated test
  runner wrapper.
- Add CI support to run the suite against local Tilt/Kind for fast feedback.
- Add OCI candidate-window support to run the same suite against the public OCI
  endpoint.
- Store non-secret evidence in the deployment checklist.

Acceptance:

- The suite can fail a bad deployment without relying on service-local tests.
- It runs against both local full-stack and OCI candidate deployments.
- It proves auth, routing, and representative business workflows from outside
  the service code under test.

### Phase 6: Support Commit-SHA Candidate Images After Gates Mature

Goals:

- Move from tag-required candidates toward source commits as deployable inputs.
- Preserve immutable auditability through commit SHA and image digest.
- Keep arbitrary branch deployment out of the production path until governance
  is explicit.

Initial allowed source refs:

- exact commit SHA on `main`
- optionally exact commit SHA from a protected release branch
- not arbitrary moving branch names

Workflow changes:

- Add workflow input for `source_sha`.
- Verify the SHA belongs to an allowed protected ref before building.
- Publish image tags such as `sha-abc1234`, with digest as deployment truth.
- Generate candidate deployment manifests with `source_ref: <sha>`.

Acceptance:

- A `main` commit SHA can produce a digest-pinned candidate image without a Git
  tag.
- The deployment manifest records the exact source SHA and image digest.
- The black-box gate is mandatory before acceptance.

### Phase 7: Promote Tested Manifests And Prepare For Continuous Deployment

Goals:

- Make promotion an explicit operation on a tested deployment manifest.
- Preserve rollback history.
- Prepare the path where every passing `main` commit can deploy automatically.

Promotion model on one OCI instance:

- Deploying a candidate changes the live slot.
- Promotion records the already-tested live manifest as the accepted production
  baseline.
- Rejection rolls the live slot back to the previous accepted manifest.

Script changes:

- Add a promotion helper, for example:
  `deploy/scripts/27-promote-oci-deployment-manifest.sh`.
- Add a manifest history location if reviewed manifests become checked-in
  release evidence, such as `deploy/releases/` or `deploy/deployments/`.
- Add rollback lookup by previous accepted manifest.

CI/CD changes:

- Add protected GitHub Environment approval for candidate deploy and promotion
  when GitHub-triggered deployment is enabled.
- Later, allow automatic promotion only when:
  - source ref is an allowed `main` commit
  - image build succeeded
  - static guardrails passed
  - black-box API/security gates passed
  - rollback manifest is known

Acceptance:

- Operators can answer "what is production running?" from the accepted
  deployment manifest and live pod metadata.
- A candidate can be rejected and rolled back from manifest history.
- CD can be enabled later by changing policy, not by redesigning the deployment
  manifest.

## `service-common` Version Policy

Do not bump `service-common` after every service or deployment release.

Normal cases:

- **Service release, `service-common` unchanged:** keep the service's
  `gradle/libs.versions.toml` pinned to the existing released
  `serviceCommon` version.
- **Config-only orchestration deployment:** do not change `service-common`.
- **Shared library development starts:** bump `service-common` to the next
  `X.Y.Z-SNAPSHOT`, publish snapshots from `main`, and have only services that
  need the new library opt into that version during development.
- **Shared library release:** release `service-common` as its own Maven
  coordinate, then update consumers intentionally.
- **Security or platform-wide shared-library fix:** use an explicit lockstep or
  coordinated consumer update because all affected services should consume the
  new shared library.

Required script changes:

- Keep `scripts/repo/release-service-common-snapshot.sh` focused on
  `service-common` Maven releases.
- Replace broad "update all consumers" defaults with explicit modes:
  - validate all consumers on a required shared-library version
  - update selected consumers
  - update all consumers for a declared lockstep shared-library rollout
- Update docs so leaving `service-common` on the released version after
  `v0.0.14` is considered valid until new shared-library work begins.

## GitHub Release Policy

Git tags and GitHub Releases should not be assumed to be the same thing.

Recommended policy:

- SemVer `v*` tags can create GitHub Releases and changelog entries.
- Candidate tags do not create GitHub Releases.
- Commit-SHA deployments do not create GitHub Releases by default.
- Deployment manifests and OCI run logs are the operational release evidence.
- GitHub Releases are human-facing named milestones, not the only production
  deployment record.

## Runbooks To Add Or Update

Add:

- `docs/runbooks/oci-single-service-release.md`
- `docs/runbooks/oci-single-service-rollback.md`
- `docs/runbooks/oci-candidate-deployment.md`
- `docs/runbooks/oci-config-only-deployment.md`

Update:

- `docs/runbooks/oci-release-deployment-checklist.md`
- `docs/ci-cd.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `scripts/README.md`
- `docs/development/service-common-artifact-resolution.md`
- `../service-common/docs/versioning-and-compatibility.md`

## Script And Workflow Inventory

Expected script changes:

| Path | Change |
| --- | --- |
| `scripts/repo/repo-config.sh` | Split repository sets by purpose. |
| `scripts/repo/tag-release.sh` | Deprecate as the default normal release path or make lockstep explicit. |
| `scripts/repo/prepare-lockstep-release.sh` | Keep for rare lockstep releases; update docs to stop using it for normal service releases. |
| `scripts/repo/prepare-service-release.sh` | New helper for one service's release validation and tag guidance. |
| `scripts/repo/generate-deployment-manifest.sh` | Generate deployment-manifest v2 records and partial artifact updates. |
| `deploy/scripts/23-update-production-release-images.sh` | Extend or replace to update mixed artifact production baselines. |
| `deploy/scripts/25-deploy-oci-release.sh` | Accept deployment-manifest v2, selected services, and candidate status. |
| `scripts/ops/show-pod-version-labels.sh` | Verify per-workload manifest metadata instead of one global expected version. |
| `scripts/smoketest/verify-oci-api-black-box.sh` | New independent deployment-facing API/security gate. |

Expected workflow changes:

- Runtime service `publish-release.yml` workflows accept `v*` and
  `candidate-*` tags.
- Candidate workflow runs do not create GitHub Releases.
- Later workflow versions accept allowed commit SHAs after Phase 5 gates exist.
- Any GitHub-triggered OCI deployment workflow uses protected environments and
  calls repo-owned deploy scripts rather than duplicating deployment logic.

## Risks

- Candidate deployments on the single OCI instance can briefly expose candidate
  behavior to real users of the demo endpoint.
- Mixed versions can hide compatibility problems if the black-box gate is weak.
- Candidate tag cleanup can destroy useful evidence if manifests and workflow
  links are not retained.
- Partial service rollback is unsafe when the release includes schema, data, or
  message-contract migrations without a service-owned rollback plan.
- Supporting both old lockstep manifests and new deployment manifests during
  migration can create script complexity; keep compatibility temporary and
  documented.

## Completion Criteria

This plan is complete when:

- The docs define and consistently use separate terms for library version,
  artifact version, deployment revision, source ref, tag, release, and
  promotion.
- The production baseline can represent mixed artifact versions.
- `/api-docs/release-metadata.json` reports deployment identity and per-artifact
  metadata accurately.
- A single service can be released, deployed, verified, and rolled back without
  bumping unrelated services.
- Candidate tags can produce deployable digest-pinned images without creating
  GitHub Releases.
- The OCI staging-window runbook exists and has been used at least once.
- Independent black-box API/security gates exist and are required before
  commit-SHA candidate deployment.
- The system can later move to continuous deployment without redesigning the
  manifest contract.
