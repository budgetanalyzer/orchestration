# CI/CD Workflows

This document describes the GitHub Actions CI/CD setup for Budget Analyzer services and the orchestration repository.

## Overview

All backend services use GitHub Actions for continuous integration. Each service has its own workflow that:

- Builds on every push to `main` and pull requests
- Runs all tests (unit, integration)
- Enforces code quality (Spotless formatting, Checkstyle)
- Uploads test results and build artifacts

## Services with CI

| Service | Status Badge |
|---------|-------------|
| service-common | [![Build](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml) |
| session-gateway | [![Build](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml) |
| transaction-service | [![Build](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml) |
| currency-service | [![Build](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml) |
| permission-service | [![Build](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml) |

## Workflow Details

### Triggers

All workflows trigger on:

- **Push to main**: Runs CI on every merge/commit
- **Pull requests**: Validates changes before merge
- **Manual dispatch**: Allows manual triggering via GitHub UI

### Build Steps

1. **Checkout**: Clone the repository
2. **Setup JDK 25**: Install Temurin JDK 25
3. **Setup Gradle**: Configure Gradle with caching
4. **Resolve pinned `serviceCommon` version**: Read `gradle/libs.versions.toml`
5. **Validate GitHub Packages access**: Fail fast if
   `SERVICE_COMMON_PACKAGES_USERNAME` /
   `SERVICE_COMMON_PACKAGES_READ_TOKEN` are missing or cannot read the pinned
   `service-core` / `service-web` POMs
6. **Build with Gradle**: Run `./gradlew build` with
   `GITHUB_ACTOR` / `GITHUB_TOKEN` exported from those same secrets, which
   includes:
   - Compile Java source
   - Run Spotless formatting check
   - Run Checkstyle validation
   - Execute all tests
   - Package JAR
7. **Upload artifacts**: Save test results and JARs

### Code Quality

The build enforces code quality via:

- **Spotless**: Google Java Format (1.32.0)
- **Checkstyle**: Style rules from [checkstyle-config](https://github.com/budgetanalyzer/checkstyle-config)

### Dependencies

The Java service repos depend on `service-common`, but local development and
GitHub Actions intentionally use different resolution paths:

- local contributor builds stay `mavenLocal()`-first and rely on
  `publishToMavenLocal` plus orchestration/Tilt
- default GitHub Actions `build.yml` workflows resolve the pinned published
  `service-common` artifact version from GitHub Packages
- release workflows use the same GitHub Packages credential pair and the same
  remote artifact source

The checked-in `serviceCommon` entry in each consumer repo's
`gradle/libs.versions.toml` remains the source of truth for the version that CI
expects to exist remotely.

## Orchestration Workflows

### `security-guardrails.yml`

The orchestration repo now has a dedicated static security workflow for the
manifest guardrail suite. It is intentionally additive beside `test-setup.yml`;
it does not reuse the stale DinD suites as current security guardrails.

It now runs on every push to `main` and every pull request targeting `main`.
The narrower path filter was removed so guarded security surfaces cannot bypass
the workflow when a new file path is added to the static scope.

What it runs:

- `./scripts/guardrails/verify-phase-7-static-manifests.sh`
- `./scripts/guardrails/verify-phase-7-static-manifests.sh --self-test`

The workflow bootstraps repo-pinned `helm`, `kubeconform`, `kube-linter`, and
`kyverno` binaries through `scripts/bootstrap/install-verified-tool.sh`, then runs:

- schema validation for checked-in manifests, with explicit missing-schema
  allowances for checked-in CRD resources such as Istio, Gateway API, Kyverno,
  and Prometheus Operator `ServiceMonitor` objects
- repo-specific kube-linter checks with documented exceptions
- Kyverno CLI pass/fail fixtures
- a generated Kyverno replay for representative approved local Tilt
  `:tilt-<hash>` deploy refs derived from the checked-in contract inventory
- a rendered Kyverno production-chart check that rejects mutable controller and
  hook image refs from `deploy/helm-values/kyverno.values.yaml`
- pattern scans for image pinning, namespace PSA labels, and lingering
  pipe-to-shell guidance in active setup docs/scripts

That directory split is intentional: CI-safe checks live under
`scripts/guardrails/`, shared installer/bootstrap helpers live under
`scripts/bootstrap/`, and the live-cluster proof remains in
`scripts/smoketest/` so GitHub Actions cannot silently drift into a
static-only substitute for the local runtime gate.

Use the same command locally to reproduce workflow failures without a cluster:

```bash
./scripts/guardrails/verify-phase-7-static-manifests.sh
```

For full local security guardrail proof on a live cluster, use the separate
final gate:

```bash
./scripts/smoketest/verify-phase-7-security-guardrails.sh
```

That wrapper intentionally stays out of GitHub Actions because the runtime
proof depends on a live local cluster. CI for the security guardrails remains
static-only.

## Running Locally

To run the same checks locally:

```bash
# Full build with all checks
./gradlew build

# Just run tests
./gradlew test

# Check formatting (without fixing)
./gradlew spotlessCheck

# Fix formatting automatically
./gradlew spotlessApply

# Run checkstyle
./gradlew checkstyleMain checkstyleTest
```

For orchestration static security guardrails:

```bash
./scripts/guardrails/verify-phase-7-static-manifests.sh
```

For the full local security guardrail proof on a running cluster:

```bash
./scripts/smoketest/verify-phase-7-security-guardrails.sh
```

## Future Enhancements

### Release Automation

Planned improvements include:

- **Semantic versioning** with [release-please](https://github.com/googleapis/release-please)
- **Automated changelog** generation from conventional commits
- **Release orchestration around the existing GHCR publish workflows**

### GitHub Packages

`service-common` publishing is no longer a future idea. Release workflows use GitHub
Packages Maven as CI/release infrastructure while keeping the local
contributor flow on `mavenLocal()` plus orchestration/Tilt.

Current contract:

- `service-common` publishes checked-in `-SNAPSHOT` versions from `main` to
  GitHub Packages Maven for CI consumption, while numeric releases remain
  tag-driven
- default Java `build.yml` workflows resolve published pinned `service-common`
  artifacts from GitHub Packages instead of cloning sibling source
- Java release and isolated Docker builds resolve published `service-common`
  artifacts from GitHub Packages through the same credential model
- because Maven/Gradle packages are repository-scoped, consuming workflows
  cannot rely on per-package **Manage Actions access** grants or assume the
  workflow repo's own `GITHUB_TOKEN` can read `service-common`
- Java build and release jobs must provide a dedicated GitHub Packages
  username/token secret pair under the env names the Gradle builds expect
- Java build workflows now read `serviceCommon` from the checked-in version
  catalog and preflight the remote `service-core` / `service-web` POM URLs
  before starting the slower Gradle build
- Java service Dockerfiles consume those credentials through BuildKit secrets
  instead of host Maven Local state or sibling repo checkouts
- checked-in `gradle/libs.versions.toml` values remain the source of truth for
  the `service-common` version

The detailed local-vs-release resolution rules live in
[docs/development/service-common-artifact-resolution.md](development/service-common-artifact-resolution.md).

Use `./scripts/repo/release-service-common-snapshot.sh` from the orchestration
repo to drive the current manual `service-common` release flow. `prepare`
reads the checked-in `service-common` snapshot, verifies all Java consumers use
that exact same snapshot, strips `-SNAPSHOT`, and runs the required Gradle
validation. `tag --push` pushes the matching `vMAJOR.MINOR.PATCH` tag from
`service-common` main after verifying local `main` matches `origin/main`.
`post` updates `service-common` plus Java consumers after `publish-release.yml`
completes for the tag. The service-common Maven release tag is intentionally
separate from the all-repository `repo/tag-release.sh` flow because Java
consumer release workflows also run on tag pushes and must not release from
source still pinned to the snapshot dependency.

### Release Images

Release image publishing is now wired as tag-driven repo-local
workflows:

- `transaction-service`, `currency-service`, `permission-service`, and
  `session-gateway` publish `linux/arm64` GHCR images from
  `.github/workflows/publish-release.yml`
- those Java workflows pass the dedicated
  `SERVICE_COMMON_PACKAGES_USERNAME` / `SERVICE_COMMON_PACKAGES_READ_TOKEN`
  secret pair into Docker BuildKit so the release build can resolve
  `service-common` without sibling checkouts or host Maven Local state
- those same Java workflows also run an explicit GitHub Packages preflight
  against the versioned `service-core` / `service-web` POM URLs before the
  Docker build, so secret-scope or credential failures surface before the
  slower image build step starts
- `budget-analyzer-web` keeps `Dockerfile` for the local Vite/Tilt path and
  uses `Dockerfile.production` for the GHCR release image built by its own
  `.github/workflows/publish-release.yml`
- orchestration publishes `ext-authz` from
  `.github/workflows/publish-ext-authz-release.yml`
- on `push` of a `v*` tag, the workflows publish the stripped numeric SemVer
  image tag and print a digest-pinned image reference for the production
  inventory step; they do not publish `latest`
- on `workflow_dispatch`, `release_ref` selects the existing Git tag to check
  out and optional `image_tag` selects the published container tag; if
  `release_ref` is `v*` and `image_tag` is omitted the workflows strip the
  leading `v`, otherwise they use the raw tag name
- the Java workflows read `serviceCommon` from the checked-out
  `gradle/libs.versions.toml`, use that value for GitHub Packages preflight and
  Docker dependency resolution, and do not require `release_ref` to equal the
  checked-in `serviceCommon` version
- manual release-image rebuilds are supported only for tags created under the
  `v0.0.12`-forward contract; older tags remain intentionally unsupported
- the production image inventory lives in
  `kubernetes/production/apps/image-inventory.yaml`, and
  `kubernetes/production/apps` renders the digest-pinned app image overlay
  using those `0.0.12` GHCR refs
- `./scripts/guardrails/verify-production-image-overlay.sh` verifies the full
  checked-in production baseline: the rendered production app overlay,
  the production infrastructure overlay, and the reviewed
  route/ingress/monitoring/egress render output. It rejects localhost hosts,
  placeholder Auth0 values, mutable image refs, and `imagePullPolicy: Never`,
  uses a live Helm server-side dry run for the Kiali production render so the
  reviewed RBAC matches the namespace-scoped live install footprint, verifies
  the Redis StatefulSet uses a `5Gi` `redis-data` claim template, then applies
  the production image Kyverno policy from
  `kubernetes/kyverno/policies/production/`

### Manual validation from a clean environment

The snapshot and tag-driven workflows cover every remote publish path that
contributors consume. For a one-off manual validation that the remote publish
path still works from a clean environment (for example, reproducing a CI
failure without sibling-repo state), check out `service-common`, export
GitHub Packages credentials, and run `./gradlew publish`:

```bash
export GITHUB_ACTOR=<your-github-username>
export GITHUB_TOKEN=<token-with-packages-write-access>
./gradlew publish
```

This uses the checked-in version literal from `build.gradle.kts` (for example,
`0.0.1-SNAPSHOT`) and publishes both `service-core` and `service-web`. It is
not part of the standard contributor workflow — GitHub Packages publishing
is a CI/release concern — and should only be used to diagnose remote-publish
issues that cannot be reproduced through the CI workflows.

## Troubleshooting

### Build Failures

1. **Spotless check failed**: Run `./gradlew spotlessApply` locally to fix formatting
2. **Checkstyle violations**: Fix style issues reported in the build log
3. **Test failures**: Check test output in the uploaded artifacts
4. **GitHub Packages preflight failed**: Confirm
   `SERVICE_COMMON_PACKAGES_USERNAME` /
   `SERVICE_COMMON_PACKAGES_READ_TOKEN` are configured and that the pinned
   `serviceCommon` version in `gradle/libs.versions.toml` has been published

### Viewing Results

- Go to the repository's **Actions** tab
- Click on the failed workflow run
- Download the `test-results` artifact for detailed JUnit reports
