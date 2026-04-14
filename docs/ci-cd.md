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

## Workflow Details

### Triggers

All workflows trigger on:

- **Push to main**: Runs CI on every merge/commit
- **Pull requests**: Validates changes before merge
- **Manual dispatch**: Allows manual triggering via GitHub UI

### Build Steps

1. **Checkout**: Clone the repository
2. **Setup JDK 24**: Install Temurin JDK 24
3. **Setup Gradle**: Configure Gradle with caching
4. **Build service-common**: Clone and build the shared library (for services that depend on it)
5. **Build with Gradle**: Run `./gradlew build` which includes:
   - Compile Java source
   - Run Spotless formatting check
   - Run Checkstyle validation
   - Execute all tests
   - Package JAR
6. **Upload artifacts**: Save test results and JARs

### Code Quality

The build enforces code quality via:

- **Spotless**: Google Java Format (1.32.0)
- **Checkstyle**: Style rules from [checkstyle-config](https://github.com/budgetanalyzer/checkstyle-config)

### Dependencies

Backend services depend on `service-common`. Each workflow clones and builds service-common to Maven Local before building the service itself.

## Orchestration Workflows

### `security-guardrails.yml`

The orchestration repo now has a dedicated static security workflow for Phase 7
Session 6. It is intentionally additive beside `test-setup.yml`; it does not
reuse the stale DinD suites as guardrails for this phase.

It now runs on every push to `main` and every pull request targeting `main`.
The narrower path filter was removed so guarded Phase 7 surfaces cannot bypass
the workflow when a new file path is added to the static scope.

What it runs:

- `./scripts/guardrails/verify-phase-7-static-manifests.sh`
- `./scripts/guardrails/verify-phase-7-static-manifests.sh --self-test`

The workflow bootstraps repo-pinned `kubeconform`, `kube-linter`, and
`kyverno` binaries through `scripts/bootstrap/install-verified-tool.sh`, then runs:

- schema validation for checked-in manifests, with explicit missing-schema
  allowances for checked-in CRD resources such as Istio, Gateway API, Kyverno,
  and Prometheus Operator `ServiceMonitor` objects
- repo-specific kube-linter checks with documented exceptions
- Kyverno CLI pass/fail fixtures
- a generated Kyverno replay for representative approved local Tilt
  `:tilt-<hash>` deploy refs derived from the checked-in contract inventory
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

For full local Phase 7 completion on a live cluster, use the separate final
gate:

```bash
./scripts/smoketest/verify-phase-7-security-guardrails.sh
```

That wrapper intentionally stays out of GitHub Actions because the runtime
proof depends on a live local cluster. CI for Phase 7 remains static-only.

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

For the full local Phase 7 completion gate on a running cluster:

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

`service-common` publishing is no longer a future idea. Phase 3 uses GitHub
Packages Maven as CI/release infrastructure while keeping the local
contributor flow on `mavenLocal()` plus orchestration/Tilt.

Current contract:

- `service-common` publishes checked-in `-SNAPSHOT` versions from `main` to
  GitHub Packages Maven for CI consumption, while numeric releases remain
  tag-driven
- Java release and isolated Docker builds resolve published `service-common`
  artifacts from GitHub Packages
- because Maven/Gradle packages are repository-scoped, consuming workflows
  cannot rely on per-package **Manage Actions access** grants or assume the
  workflow repo's own `GITHUB_TOKEN` can read `service-common`
- release jobs must provide a dedicated GitHub Packages username/token secret
  pair under the env names the Gradle builds expect
- Java service Dockerfiles consume those credentials through BuildKit secrets
  instead of host Maven Local state or sibling repo checkouts
- checked-in `gradle/libs.versions.toml` values remain the source of truth for
  the `service-common` version

The detailed local-vs-release resolution rules live in
[docs/development/service-common-artifact-resolution.md](development/service-common-artifact-resolution.md).

### Release Images

Phase 3 release image publishing is now wired as tag-driven repo-local
workflows:

- `transaction-service`, `currency-service`, `permission-service`, and
  `session-gateway` publish `linux/arm64` GHCR images from
  `.github/workflows/publish-release.yml`
- those Java workflows pass the dedicated
  `SERVICE_COMMON_PACKAGES_USERNAME` / `SERVICE_COMMON_PACKAGES_READ_TOKEN`
  secret pair into Docker BuildKit so the release build can resolve
  `service-common` without sibling checkouts or host Maven Local state
- `budget-analyzer-web` keeps `Dockerfile` for the local Vite/Tilt path and
  uses `Dockerfile.production` for the GHCR release image built by its own
  `.github/workflows/publish-release.yml`
- orchestration publishes `ext-authz` from
  `.github/workflows/publish-ext-authz-release.yml`
- the workflows publish only the numeric SemVer tag from the pushed `v*`
  release ref and print a digest-pinned image reference for the production
  inventory step; they do not publish `latest`
- each workflow also supports `workflow_dispatch` with a `release_ref` input so
  an already-existing tag such as `v0.0.8` can still be published even if the
  workflow file was added later on `main`

## Troubleshooting

### Build Failures

1. **Spotless check failed**: Run `./gradlew spotlessApply` locally to fix formatting
2. **Checkstyle violations**: Fix style issues reported in the build log
3. **Test failures**: Check test output in the uploaded artifacts
4. **service-common build failed**: Ensure service-common has no breaking changes

### Viewing Results

- Go to the repository's **Actions** tab
- Click on the failed workflow run
- Download the `test-results` artifact for detailed JUnit reports
