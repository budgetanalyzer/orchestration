# Service-Common Artifact Resolution

This document explains the split between local `mavenLocal()` resolution and
the GitHub Packages path used by GitHub Actions and release builds.

## Local Contributor Flow

The supported side-by-side workspace flow must stay credential-free.

If you follow [getting-started.md](getting-started.md) and run local
development through orchestration and Tilt:

- clone the repos side by side
- open `/workspace/orchestration`
- run `./setup.sh`
- run `tilt up`

you should not need `GITHUB_ACTOR`, `GITHUB_TOKEN`, or a personal access token
just to start the app locally.

That works because the local build path stays local-first:

- Java service repos keep `mavenLocal()` first
- Tilt runs the `service-common-publish` resource first
- `service-common-publish` runs `publishToMavenLocal`
- downstream host-side Gradle builds then resolve `service-common` from Maven
  Local

If you hit a local `service-common` resolution error while working in the full
workspace, republish it locally and rerun the service build:

```bash
cd ../service-common
./gradlew clean build publishToMavenLocal
```

## When GitHub Packages Credentials Are Required

GitHub Packages credentials are a CI/release concern, not a getting-started
prerequisite.

You need GitHub Packages credentials when all of these are true:

- the build is not using the local orchestration/Tilt path
- `service-common` is not already available through Maven Local
- the build must resolve the published `org.budgetanalyzer` artifacts remotely
  from `https://maven.pkg.github.com/budgetanalyzer/service-common`

Typical examples:

- default GitHub Actions `build.yml` runs in `transaction-service`,
  `currency-service`, `permission-service`, and `session-gateway`
- release-version Docker builds
- isolated CI or clean-builder image builds
- manual clean-shell verification of remote published artifacts

`service-common` itself now refreshes the current checked-in snapshot from
`main` through its `publish-snapshot.yml` workflow. That remote snapshot path
exists to support isolated CI/release builds; it does not change the local
contributor contract.

For the Java consumer repos, the default build workflow contract is now:

- read the pinned `serviceCommon` version from `gradle/libs.versions.toml`
- fail fast if `SERVICE_COMMON_PACKAGES_USERNAME` or
  `SERVICE_COMMON_PACKAGES_READ_TOKEN` is missing
- preflight the versioned `service-core` and `service-web` POM URLs in GitHub
  Packages
- run `./gradlew build` with `GITHUB_ACTOR` / `GITHUB_TOKEN` exported from
  that same secret pair

## GitHub Actions Environment

When a workflow intentionally resolves `service-common` remotely from GitHub
Packages, Gradle needs both a token and a package username.

For cross-repo private Maven/Gradle consumption, do not assume the workflow
repo's own `GITHUB_TOKEN` can read `service-common`. GitHub still treats these
packages as repository-scoped, so the consuming workflow needs an explicit
GitHub Packages credential.

In GitHub Actions, the current repo wiring expects:

```yaml
env:
  GITHUB_ACTOR: ${{ secrets.SERVICE_COMMON_PACKAGES_USERNAME }}
  GITHUB_TOKEN: ${{ secrets.SERVICE_COMMON_PACKAGES_READ_TOKEN }}
```

`GITHUB_ACTOR` here means the username that owns the GitHub Packages credential,
not necessarily `${{ github.actor }}`. `GITHUB_TOKEN` here means the secret used
for remote package reads, not necessarily the workflow repo's default token.
This requirement applies to the remote GitHub Packages path used by default
`build.yml` and release workflows. It does not apply to the normal `tilt up`
contributor flow.

## Containerized Release Builds

The Java service Dockerfiles now support remote `service-common` resolution for
release and isolated CI builds without copying host `.m2` state into the build
context and without checking out sibling source trees.

Pass the workflow credentials into BuildKit as secrets:

```bash
docker build \
  --secret id=github_actor,env=GITHUB_ACTOR \
  --secret id=github_token,env=GITHUB_TOKEN \
  -f Dockerfile .
```

In GitHub Actions, the release job should still expose those same credential
values under the env names the current Gradle builds read:

```yaml
env:
  GITHUB_ACTOR: ${{ secrets.SERVICE_COMMON_PACKAGES_USERNAME }}
  GITHUB_TOKEN: ${{ secrets.SERVICE_COMMON_PACKAGES_READ_TOKEN }}
```

The Dockerfiles read those values only inside the Gradle builder-stage `RUN`
steps, so the credentials are not written into the image, filesystem layers, or
checked-in repo files.

## Why Public Package Visibility Does Not Remove This

Making the `service-common` Maven packages public in the GitHub UI does not
remove the Maven/Gradle authentication requirement.

Keep the package-visibility and workflow-access cleanup in Phase 3, but do not
treat it as the fix for local contributor UX. The fix for local contributor UX
is keeping the side-by-side workspace and Tilt flow local-first and
credential-free.
