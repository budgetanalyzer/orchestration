# Service-Common Artifact Resolution

This document explains when Budget Analyzer services resolve `service-common`
from Maven Local and when they need GitHub Packages credentials.

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

GitHub Packages credentials are a release and isolated-build concern, not a
getting-started prerequisite.

You need GitHub Packages credentials when all of these are true:

- the build is not using the local orchestration/Tilt path
- `service-common` is not already available through Maven Local
- the build must resolve the published `org.budgetanalyzer` artifacts remotely
  from `https://maven.pkg.github.com/budgetanalyzer/service-common`

Typical examples:

- release-version Docker builds
- isolated CI or clean-builder image builds
- manual clean-shell verification of remote published artifacts

## GitHub Actions Environment

When a workflow intentionally resolves `service-common` remotely from GitHub
Packages, Gradle needs both a token and a package username.

In GitHub Actions, set:

```yaml
env:
  GITHUB_ACTOR: ${{ github.actor }}
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Without `GITHUB_ACTOR`, the remote-resolution path is incomplete even if
`GITHUB_TOKEN` exists. This requirement applies only to the remote
GitHub-Packages path, not to the normal `tilt up` contributor flow.

## Why Public Package Visibility Does Not Remove This

Making the `service-common` Maven packages public in the GitHub UI does not
remove the Maven/Gradle authentication requirement.

Keep the package-visibility and workflow-access cleanup in Phase 3, but do not
treat it as the fix for local contributor UX. The fix for local contributor UX
is keeping the side-by-side workspace and Tilt flow local-first and
credential-free.
