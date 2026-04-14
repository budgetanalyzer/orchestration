# Service-Common Docker Build Strategy

**Status:** Supporting rationale, not the Oracle Cloud deployment source of truth.
For Oracle Cloud Phase 3 execution, use
[`oracle-cloud-deployment-plan.md`](./oracle-cloud-deployment-plan.md#phase-3-production-image--build-contract).
This document explains the `service-common` Docker build problem and the
artifact-repository options behind that plan.

## Goal

Define how Java service Docker builds should resolve `service-common`
reliably, without depending on host-only Maven state that disappears inside an
isolated `docker build`.

## Why This Plan Exists

`service-common` is already handled for some workflows, but not all of them.

What is already handled:

- host-side Gradle builds in the service repos use `mavenLocal()`
- service troubleshooting guidance already tells developers to run
  `publishToMavenLocal`
- Tilt already publishes `service-common` first, then compiles the downstream
  services on the host, then builds thin runtime images from the prebuilt JARs

Evidence:

- `../transaction-service/build.gradle.kts` includes `mavenLocal()`
- `../transaction-service/AGENTS.md` tells developers to run
  `../service-common/./gradlew clean build publishToMavenLocal`
- `Tiltfile` runs `service-common-publish` before the downstream `bootJar`
  compile resources and explicitly says the inline dev Dockerfile
  "avoids Maven dependency issues"
- `../service-common/build.gradle.kts` currently publishes only to
  `mavenLocal()`

What is **not** handled:

- raw multi-stage `docker build` inside a service repo

That build runs in an isolated builder image. It does not inherit the host
container's `~/.m2/repository`, so `publishToMavenLocal` on the host fixes
`./gradlew bootJar` but does not fix `RUN ./gradlew bootJar` inside the
Dockerfile.

## Current State

### Works Today

- `./gradlew bootJar` in service repos, after `service-common` is published to
  Maven Local
- Tilt local development, because it compiles on the host and copies the built
  JAR into a thin runtime image
- CI, because the documented workflow is "build `service-common` first, then
  build the service with Gradle", not "build the service Dockerfile in
  isolation"

### Fails Today

- `docker build -f Dockerfile .` in `transaction-service`,
  `currency-service`, `permission-service`, and `session-gateway`

Root cause:

- the service Dockerfiles invoke Gradle in a clean builder container
- that builder container has no access to the host's Maven Local repository
- `service-common` is not published to any shared remote artifact repository

## Decision To Make

Choose the contract we actually want:

1. `docker build` from a service repo should work standalone.
2. Only Tilt and CI need to work; standalone service Dockerfiles are optional.

If the answer is `1`, we need a real artifact-distribution strategy for
`service-common`. If the answer is `2`, the better move is to document the
boundary and stop pretending the current Dockerfiles are a self-contained path.

## Recommended Direction

Use a real package repository for `service-common` and treat `mavenLocal()` as
developer convenience, not as the source of truth for container builds.

This is the cleanest fix because it makes standalone Docker builds, CI, and any
future remote builder all consume the same published artifact story.

## Why The Recommended Direction Wins

- It preserves service-repo independence. A service Dockerfile can build
  without needing sibling source trees in the Docker context.
- It matches how container builds actually work. Builders should fetch
  dependencies from an artifact repository, not from a developer workstation.
- It avoids fragile workarounds like copying `.m2` into build contexts or
  requiring special `docker buildx --build-context` invocations.
- It scales if this project ever needs reproducible image builds outside the
  current devcontainer.

## Rejected Shortcuts

### Copy host Maven Local into the Docker build

Do not do this.

- It bakes workstation state into builds.
- It is easy to get stale artifacts.
- It creates large, leaky build contexts.
- It makes CI and local behavior diverge again.

### Expand Docker build context to include sibling `service-common`

Do not do this unless you deliberately abandon service independence.

- It couples service Dockerfiles to the workspace layout.
- It conflicts with the repo boundary principle.
- It makes standalone service builds depend on orchestration-specific context.

### Keep saying "run publishToMavenLocal" and call it done

This is only a host-build fix. It does not solve isolated container builds.

## Implementation Plan

### Phase 1: Freeze The Build Contract

- Decide whether standalone service Dockerfiles are required to work.
- If yes, state explicitly that `service-common` artifacts must be available
  from a non-local repository.
- Update orchestration docs so they stop implying that `publishToMavenLocal`
  covers Docker builds.

### Phase 2: Publish `service-common` Somewhere Docker Can Reach

Preferred target:

- GitHub Packages for `org.budgetanalyzer`

Required work in `service-common`:

- add a real Maven publish target alongside `mavenLocal()`
- decide snapshot/version behavior instead of relying purely on
  `0.0.1-SNAPSHOT` in local-only workflows
- document credentials and repository URL requirements

Required work in consuming services:

- add the remote repository to `repositories {}`
- keep `mavenLocal()` first if you still want fast local iteration
- ensure Docker builds can authenticate, likely via build secrets or CI env

### Phase 3: Define Snapshot/Version Discipline

Use two different rules for two different workflows:

1. Local development keeps `0.0.1-SNAPSHOT` and `publishToMavenLocal`.
2. Production image builds use immutable release or prerelease versions
   published to the remote Maven repository.

The Oracle Cloud deployment plan chooses the second rule for public demo
releases. That means `0.0.1-SNAPSHOT` remains a local convenience for the
Tilt/host-Gradle loop, but a production GHCR image must not be built against
that snapshot.

Required release rule:

- when `service-common` changes for a release, publish an immutable
  `service-common` version first
- build every consuming Java service image with that exact version
- record the `service-common` version alongside the GHCR image tag/digest in
  the release inventory
- do not require hand-editing every service's version catalog for each release;
  add a release-time override such as `-PserviceCommonVersion=<version>`

### Phase 4: Make Docker Builds Consume The Same Contract

For each Java service repo:

- keep the multi-stage Dockerfile shape
- ensure the builder stage can resolve `service-common` from the chosen remote
  repository
- add auth wiring only where required; do not hardcode tokens into Dockerfiles

Verification target:

- `docker build -f Dockerfile .` succeeds from the service repo root after the
  artifact is published remotely

### Phase 5: Align CI With The Same Story

Current CI appears to build `service-common` before the service with host-side
Gradle. Decide whether CI should:

1. keep the existing host-Gradle path for tests and add a separate image-build
   job, or
2. move fully to image builds as the primary proof

Recommendation:

- keep host-side Gradle for fast test feedback
- add an explicit image-build job only if standalone Dockerfiles are meant to
  be supported as a real contract

### Phase 6: Clean Up Documentation

Update these docs together when the implementation lands:

- `docs/development/local-environment.md`
- `docs/tilt-kind-setup-guide.md`
- `docs/ci-cd.md`
- affected service repo `README.md` or `AGENTS.md` files that currently imply
  `publishToMavenLocal` is sufficient in all cases

## Minimum Viable Alternative

If you do **not** want to introduce a remote artifact repository yet, the
honest fallback is:

- declare standalone service Dockerfiles non-portable for now
- document that Java service image builds in local development must go through
  orchestration/Tilt, not raw `docker build`
- keep `publishToMavenLocal` as the supported host-build fix

This is weaker, but it is at least truthful.

## Recommendation Summary

Recommended if you want standalone `docker build` to work:

1. Publish `service-common` to a real Maven repository.
2. Teach consuming services to resolve it there.
3. Add image-build verification once that contract exists.

For Oracle Cloud production releases, the concrete repository choices are:

1. GitHub Packages Maven registry for `service-common` artifacts.
2. GHCR for app container images.
3. Maven Local only for local development and Tilt's host-side build flow.

Recommended if you do **not** want that scope right now:

1. Keep the current Tilt and host-Gradle story.
2. Document that raw service Dockerfiles are not a supported local workflow.
3. Stop treating `publishToMavenLocal` as if it fixes isolated Docker builds.

## Done When

- the team can say clearly whether standalone Java service Dockerfiles are
  supported
- the docs match that contract
- if they are supported, `docker build -f Dockerfile .` succeeds in each Java
  service repo without relying on host-only Maven Local state
