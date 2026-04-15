# Release Build Decoupling Plan (`v0.0.12` Forward)

**Date:** 2026-04-15  
**Status:** Draft  
**Scope:** `service-common`, `transaction-service`, `currency-service`, `permission-service`, `session-gateway`, `budget-analyzer-web`, `orchestration` (`ext-authz`), and orchestration release/build documentation

## Goal

Starting with `v0.0.12`, make release-image builds forward-only and
predictable:

- no backward-compatibility work for older tags
- no workflow rule that says the Git tag must equal the checked-in
  `service-common` version
- manual workflow dispatch can build and publish an image from any supported
  tag without inventing special cases for old broken tags
- Java Docker builds continue to resolve `service-common` remotely through
  GitHub Packages with BuildKit secrets
- all release-image workflows, including `budget-analyzer-web` and `ext-authz`,
  separate source selection from published image tag selection

## Current Problem

The current release workflows still couple source selection and published image
identity too tightly, and the Java workflows add an extra unnecessary coupling
to `service-common`.

The Java workflows currently couple three separate concerns:

1. the Git ref being checked out
2. the image tag being published to GHCR
3. the `service-common` version used during the Gradle/Docker build

Today the workflows derive `version` from `release_ref`, then reject the build
unless that value matches `serviceCommon = "..."` in
`gradle/libs.versions.toml`. That is too strict for the actual need.

What actually matters is simpler:

- the checked-out source ref must contain a valid `service-common` version
- that `service-common` version must already be published to GitHub Packages
- the image tag published to GHCR must be chosen intentionally

Those are related, but they are not the same value and should not be treated as
the same contract.

The non-Java workflows (`budget-analyzer-web` and `ext-authz`) have the same
`release_ref` versus `image_tag` problem even though they do not consume
`service-common`: they currently assume manual dispatch only makes sense for
`v*` tags and derive the image tag directly from that naming convention.

## Decision Summary

For `v0.0.12` and later:

1. Treat `release_ref` as a source-code selector only.
2. Treat the published GHCR image tag as a separate output value.
3. In Java repos, read `service-common` version from the checked-out files and
   use that value for package preflight and Docker dependency resolution.
4. In non-Java repos, do not impose extra tag-shape restrictions on manual
   dispatch beyond "must be an existing supported tag."
5. Do not add any runtime patching, fallback logic, or ref-rewriting for
   `v0.0.8` through `v0.0.11`.
6. Standardize the fixed Dockerfile pattern across all Java services and only
   support tags created after that fix is present in the tagged source.
7. Standardize the `release_ref` / `image_tag` split across Java, web, and
   `ext-authz` release workflows.

Confirmed decisions:

- manual dispatch supports existing Git tags only, not branches or raw commit
  SHAs
- manual dispatch may target standard release tags such as `v0.1.0` or
  non-standard tags such as `testing-deployment`
- only tags created from commits under the `v0.0.12`-forward contract are
  supported for the decoupled manual release-image flow
- GitHub Packages preflight stays for now and should be standardized across all
  four Java service release workflows

## Non-Goals

- No rescue path for `v0.0.8`, `v0.0.9`, `v0.0.10`, or `v0.0.11`.
- No workflow logic that conditionally patches older tags during checkout.
- No Docker-context expansion to include sibling repositories.
- No host `.m2` copying into Docker builds.
- No change to the local contributor contract based on `tilt up` plus
  `publishToMavenLocal`.

## Recommended End State

Each release workflow should support two paths:

### Path A: Normal tag-triggered publish

- Trigger: `push` of `v*`
- Checkout: the pushed tag
- Default image tag: stripped `v` prefix from the Git tag
- Java only: `service-common` version parsed from checked-in
  `gradle/libs.versions.toml`
- No validation that Git tag equals `service-common` version

### Path B: Manual release-image build

- Trigger: `workflow_dispatch`
- Required input: `release_ref`
- Optional input: `image_tag`
- Checkout: `release_ref`
- Supported refs: existing Git tags only, under the `v0.0.12`-forward
  contract
- Default image tag:
  - if `release_ref` is a `v*` tag, use the stripped `v` value
  - otherwise use `release_ref` directly, unless `image_tag` is provided
- Java only: `service-common` version parsed from checked-in
  `gradle/libs.versions.toml`
- Java only: package preflight and Docker build use `service-common` version,
  not image tag

This keeps the workflow honest:

- Git ref selects source
- checked-in files select dependency versions where relevant
- image tag selects published container identity

## Workstreams

### Workstream 1: Forward-Only Baseline (`v0.0.12`)

Use `0.0.12` / `v0.0.12` as the first release that fully adopts this contract.

Tasks:

- bump `service-common` to `0.0.12`
- bump the four Java consumers to `serviceCommon = "0.0.12"`
- confirm the fixed Dockerfiles with BuildKit secret mounts are present before
  tagging `v0.0.12`
- update `budget-analyzer-web` and `ext-authz` release workflows to the same
  `release_ref` / `image_tag` contract
- tag only commits that already contain the fixed Dockerfiles and decoupled
  workflows

Verification:

- `service-common` `v0.0.12` publishes successfully to GitHub Packages
- `transaction-service` `v0.0.12` publishes successfully to GHCR
- one additional Java consumer proves the pattern before rolling across the
  remaining two
- `budget-analyzer-web` and `ext-authz` each prove manual dispatch from a
  supported non-standard tag

### Workstream 2: Decouple Workflow Inputs

Update release workflows in:

- `transaction-service`
- `currency-service`
- `permission-service`
- `session-gateway`
- `budget-analyzer-web`
- `orchestration` for `ext-authz`

Required changes:

- remove the check that rejects the build when `release_ref` does not match the
  checked-in `serviceCommon` version
- parse `image_tag` separately from the checked-out ref
- continue to fail fast when `release_ref` is malformed or secrets are missing
- continue to print the digest-pinned final image reference
- do not treat the Git tag as the source of truth for `service-common`
  dependency version
- in Java repos, parse `service_common_version` from
  `gradle/libs.versions.toml`
- in non-Java repos, remove the current assumption that manual dispatch must be
  a `v*` tag to produce an image tag

Recommended workflow outputs:

- `image_tag`
- `service_common_version` for Java repos only
- `commit_sha`

Recommended dispatch inputs:

- `release_ref` required
- `image_tag` optional

Recommended logic:

- on tag push:
  - `image_tag="${GITHUB_REF_NAME#v}"`
- on manual dispatch:
  - verify `release_ref` resolves to an existing tag
  - if `release_ref` looks like `v*` and `image_tag` is empty, use stripped `v`
  - if `release_ref` is not a `v*` tag and `image_tag` is empty, use
    `release_ref` directly
  - if `image_tag` is provided, use it as an explicit override

### Workstream 3: Package Preflight Policy

`transaction-service` currently has a temporary GitHub Packages preflight step
that proved useful during debugging.

There are two clean end states:

1. keep that preflight as a permanent fast-fail check and standardize it across
   all four Java service release workflows
2. remove it from `transaction-service` and rely on the Docker build itself

Recommendation:

- keep the preflight, but standardize it across all four Java services

Reason:

- it fails in seconds instead of after a long Docker build
- it validates the exact published `service-common` version from the checked-out
  files
- it is not a backward-compatibility workaround; it is a useful release
  guardrail

If the team prefers a leaner workflow, remove the `transaction-service`-only
version rather than leaving one repo special-cased.

This workstream does not apply to `budget-analyzer-web` or `ext-authz`.

### Workstream 4: Remove Temporary Strict-Coupling Language From Docs

Once the workflows are updated, align the docs with the new contract.

Update:

- `docs/plans/oracle-cloud-deployment-plan.md`
- `docs/ci-cd.md`
- `docs/development/service-common-artifact-resolution.md`
- affected service READMEs where release workflow behavior is described

Required documentation changes:

- stop saying that release workflows must have `tag == serviceCommon version`
- say that the checked-out ref controls source, while checked-in build files
  control the `service-common` version used during the build
- document manual release-image dispatch as a supported path for any supported
  tag from `v0.0.12` forward, including non-standard tags such as
  `testing-deployment`
- explicitly state that older tags before the fixed Dockerfile/workflow contract
  are unsupported for manual release-image rebuilds
- document that the same `release_ref` / `image_tag` split applies to
  `budget-analyzer-web` and `ext-authz`, even though they do not consume
  `service-common`

### Workstream 5: Service Rollout Order

Recommended order:

1. `service-common`
2. `transaction-service`
3. `currency-service`
4. `permission-service`
5. `session-gateway`
6. `budget-analyzer-web`
7. `orchestration` (`ext-authz`)

Reason:

- `transaction-service` is already the best-understood proving ground
- once `transaction-service` is clean, the remaining three Java services are
  mostly parallel workflow cleanup plus version alignment
- `budget-analyzer-web` and `ext-authz` share the same release-ref decoupling
  problem but do not depend on the Java package work, so they can follow after
  the Java pattern is settled

## Execution Sequence

1. Align `service-common` and all four Java consumers to `0.0.12`.
2. Update all four Java release workflows to separate `image_tag` from
   `service_common_version`.
3. Update `budget-analyzer-web` and `ext-authz` release workflows to the same
   `release_ref` / `image_tag` contract.
4. Decide whether package preflight is permanent and either standardize it or
   remove it.
5. Tag and publish `service-common` `v0.0.12`.
6. Tag and publish `transaction-service` `v0.0.12`.
7. Verify the release-image flow on one additional Java consumer.
8. Verify manual dispatch for `budget-analyzer-web` or `ext-authz` from a
   supported non-standard tag.
9. Roll the same pattern to the remaining services.
10. Update orchestration and service docs to match the forward-only contract.

## Explicitly Rejected Approaches

- patching old tags at workflow runtime
- reading fixed Dockerfiles from `main` while building older tags
- keeping the strict `release_ref == serviceCommon version` check
- adding repo-specific exceptions for `transaction-service` only
- treating temporary debug additions as permanent unless they are standardized
- leaving `budget-analyzer-web` or `ext-authz` on a separate release-ref
  contract once the new pattern is adopted

## Deliverables

- four Java service release workflows with decoupled `release_ref`,
  `service_common_version`, and `image_tag`
- `budget-analyzer-web` and `ext-authz` release workflows with decoupled
  `release_ref` and `image_tag`
- four Java service Dockerfiles validated as compatible with BuildKit secrets
- `service-common` `v0.0.12` published to GitHub Packages
- `transaction-service` `v0.0.12` image published as the first forward-only
  proof
- `budget-analyzer-web` and `ext-authz` proven to support manual dispatch from
  supported non-standard tags
- documentation updated to describe the `v0.0.12`-forward contract

## Open Questions

No open design questions are required before implementation. The remaining work
is execution and documentation alignment.
