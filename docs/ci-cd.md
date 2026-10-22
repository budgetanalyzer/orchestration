# CI/CD Workflows

This document describes the GitHub Actions CI/CD setup for Budget Analyzer services and the orchestration repository.

## Overview

All backend services use GitHub Actions for continuous integration. Each service has its own workflow that:

- Builds on every push to `main` and pull requests
- Runs all tests (unit, integration)
- Enforces code quality (Spotless formatting, Checkstyle)
- For the four deployable Java applications, retains JUnit XML only when CI
  fails, for one day; successful regular CI retains no application artifact

## Services with CI

| Service | Status Badge |
|---------|-------------|
| service-common | [![Build](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml) |
| session-gateway | [![Build](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml) |
| transaction-service | [![Build](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml) |
| currency-service | [![Build](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml) |
| permission-service | [![Build](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml) |
| ext-authz | [![Build](https://github.com/budgetanalyzer/ext-authz/actions/workflows/build.yml/badge.svg)](https://github.com/budgetanalyzer/ext-authz/actions/workflows/build.yml) |

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
7. **Retain failure diagnostics**: For `currency-service`,
   `permission-service`, `transaction-service`, and `session-gateway`, upload
   only JUnit XML after a failed regular CI build and retain it for one day.
   Do not upload the application JAR from regular CI.

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

## Source Release And Production Reference Model

Budget Analyzer separates source tags, runtime artifact versions,
`service-common` Maven versions, image digests, and historical production
reference identity. OCI is retired and no production environment is currently
configured. The checked-in, digest-pinned state under
`kubernetes/production/apps` is an offline reference, not live cluster status.

Terminology:

- Source tags are Git tags pushed to the deployable source repositories. A
  pushed `vX.Y.Z` source tag triggers the owning repository's release-image
  workflow.
- Docker tags are registry labels used to find and inspect images. For a
  `vX.Y.Z` source tag, the release-image workflows publish Docker label
  `X.Y.Z`.
- Image digests are the deployable artifact identity.
- The production manifest and image inventory are reference files. They do not
  record lifecycle status such as `accepted`, `pending`, or `deployed`.
- The retained OCI id and artifact rows are historical provenance. Active
  metadata marks them reference-only.

There is no active production preparation, apply, upgrade, or rollback command.
Removed OCI workflow files are in the lean archive documented by
[archive/oci/README.md](../archive/oci/README.md); the complete pre-retirement
tree is at public tag `pre-oci-archive`, verified at commit
`60510f4ce9331968988516947f394152f6aa0da4`. A future hosted environment
requires a separately authorized deployment design.

The deployable Java services do not consume regular-CI Actions artifacts.
Their `publish-release.yml` workflows check out the selected source and invoke
Docker Buildx directly; each Dockerfile runs `./gradlew bootJar` in its build
stage and the workflow pushes the resulting `linux/arm64` image to GHCR. No
active workflow downloads an `app-jar` artifact. The production reference keeps
the last reviewed immutable GHCR digests. Removing regular-CI `app-jar` uploads
therefore does not change source-release behavior.

The maintained offline render map and unresolved deployment prerequisites live
in [deploy/README.md](../deploy/README.md). This document owns source-release
and artifact terminology.

The active tag helpers prepare source releases and print the owning GitHub
Actions workflow pages. They do not update production-reference image files or
deploy a cluster. Any future image-baseline update must keep the deployment
manifest, image inventory, app overlay, runtime metadata patch, and `/api-docs`
metadata consistent in one reviewed change.

### Where To Run Tag Helpers

The tag helpers create tags in each sibling repository and push them to that
repository's `origin`. A release tag triggers publish workflows only when
`origin` is GitHub, so run `repo/tag-release.sh`,
`repo/prepare-lockstep-release.sh --tag`, `repo/tag-lockstep-release.sh`, and
`repo/release-service-common-snapshot.sh tag --push` from a checkout whose
sibling repositories push to GitHub, with every repository in the selected
release set cloned side by side.

In the optional development VM, `origin` is the guest-local bare repository,
and only the personal host may publish to GitHub. Tags pushed from the guest
stay in the bare repositories, and the helpers' remote-tag checks inspect those
bare repositories instead of GitHub. Transfer the guest release branches to the
personal host as described in
[workspace branch transfer](../../workspace/docs/host-isolation.md#branch-transfer),
merge them on GitHub, and run the tag helpers on the personal host.

Do not try to make a checked-in reference manifest self-reference the commit
that contains itself. Treat per-artifact commit fields as historical image
build inputs, not proof of a live rollout.

`service-common` is a library release line, not the stack version. Release it
when `spring-platform`, `spring-cloud-platform`, `service-core`, or
`service-web` changes. Do not bump it only to ship a service image, route
change, documentation metadata fix, or production overlay update.

Tag helpers remain useful for human source management and rare named releases,
but tag names are not production correctness and do not imply deployment.

## Orchestration Workflows

Dependency update pull-request ownership, production settings, cost constraints,
evidence contracts, and failure triage live in
[Dependency Automation](dependency-automation.md). On relevant pushes and pull
requests targeting `main`, and on manual dispatch, the focused
`dependency-automation-config.yml` workflow runs Renovate's official strict
validator against the repository config and shared preset. It does not install
the App or open dependency pull requests.

On pushes to `main`, its weekly schedule, and manual dispatch, the
`exact-image-security-evidence.yml` workflow renders the checked-in production
and controller sources offline, resolves each rendered ref to an exact platform
digest, and publishes complete Trivy inventories and vulnerability reports in
one artifact retained for seven days. Its operating boundary, evidence
contract, artifact contents, and known coverage gaps are owned by
[Dependency Automation](dependency-automation.md#exact-image-security-evidence).

### `test-setup.yml` and `verify-platform-tool-releases.yml`

`test-setup.yml` runs offline: script syntax plus the focused setup fixture
suites listed in the workflow. It runs on every pull request targeting `main`,
on relevant pushes to `main` or `setup`, and on manual dispatch, and it
downloads no release artifacts.

`verify-platform-tool-releases.yml` runs
`scripts/bootstrap/verify-platform-tool-releases.sh`, which downloads the
pinned kubectl, Helm, Tilt and Kind artifacts for Linux amd64 and arm64 and
verifies them without installing or executing them. GitHub's built-in `paths`
filters limit it to pushes to `main` or `setup` and pull requests targeting
`main` that change `scripts/lib/pinned-tool-versions.sh`,
`scripts/bootstrap/install-verified-tool.sh`,
`scripts/bootstrap/verify-platform-tool-releases.sh` or the workflow itself;
manual dispatch runs it on demand. Because it is skipped on unrelated pull
requests, it must not be configured as a required status check; branch
protection and rulesets remain human-owned. The release-input contract is
owned by [Dependency Automation](dependency-automation.md#configuration-and-repository-ownership).

### `security-guardrails.yml`

The orchestration repo now has a dedicated static security workflow for the
manifest guardrail suite. It is intentionally additive beside `test-setup.yml`;
it does not reuse the stale DinD suites as current security guardrails.

It now runs on every push to `main` and every pull request targeting `main`.
The narrower path filter was removed so guarded security surfaces cannot bypass
the workflow when a new file path is added to the static scope. Its token has
read-only repository-content permission.

What it runs:

- `./scripts/guardrails/verify-static-security-manifests.sh`
- `./scripts/guardrails/verify-static-security-manifests.sh --self-test`

The workflow bootstraps repo-pinned `helm`, `kubectl`, `kubeconform`,
`kube-linter`, and `kyverno` binaries through
`scripts/bootstrap/install-verified-tool.sh`. It does not require ripgrep; the
static scans retain a `grep` fallback. Separately, it runs on the explicit
`ubuntu-24.04` runner label and uses that runner's CPython 3.12 x86_64
`python3` only to create a disposable private virtual
environment under `.cache/phase7-static-tools`, installs the exact PyYAML wheel
declared in
`scripts/guardrails/requirements-ingress-rate-limit.txt` with required hash
verification, and exports that environment's interpreter to the static gate.
The gate verifies the exact version and reports the resolved interpreter and
module path. The Python package is not installed globally and is not modeled
as a standalone release binary. The private environment is not cached. The
workflow then runs:

- schema validation for checked-in manifests, with explicit missing-schema
  allowances for checked-in CRD resources such as Istio, Gateway API, Kyverno,
  and Prometheus Operator `ServiceMonitor` objects
- rendered Kustomize schema validation for the production-reference app and
  infrastructure overlays, so partial patch files stay excluded from
  standalone validation but are still checked after render; the schema-v2
  production reference manifest is also excluded because it is artifact
  metadata, not a Kubernetes resource
- repo-specific kube-linter checks with documented exceptions
- Kyverno CLI pass/fail fixtures
- a generated Kyverno replay for representative approved local Tilt
  `:tilt-<hash>` deploy refs derived from the checked-in contract inventory
- a rendered Kyverno production-chart check that requires the reviewed chart
  and application pairing plus every immutable controller, init, migration,
  cleanup-hook, and test image from the values shared with local Tilt
- the offline ingress rate-limit configuration proof, including the local and
  production EnvoyFilter render contract, gateway diagnostics stats matchers,
  and a fail-closed scan proving blanket NGINX rate limiting remains absent
- pattern scans for image pinning, namespace PSA labels, and lingering
  pipe-to-shell guidance in active setup docs/scripts

That directory split is intentional: CI-safe checks live under
`scripts/guardrails/`, shared installer/bootstrap helpers live under
`scripts/bootstrap/`, and the live-cluster proof remains in
`scripts/smoketest/` so GitHub Actions cannot silently drift into a
static-only substitute for the local runtime gate.

Use the same command locally to reproduce workflow failures without a cluster:

```bash
python3 -m venv .cache/phase7-static-tools/pyyaml-venv
.cache/phase7-static-tools/pyyaml-venv/bin/python -I -m pip install \
  --require-hashes --no-deps --only-binary=:all: \
  -r scripts/guardrails/requirements-ingress-rate-limit.txt
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
```

For full local security guardrail proof on a live cluster, use the separate
final gate:

```bash
./scripts/smoketest/verify-security-guardrails.sh
```

That wrapper intentionally stays out of GitHub Actions because the runtime
proof depends on a live local cluster. CI for the security guardrails remains
static-only. After publishing changes to this workflow or its guardrail inputs,
the branch owner must rerun and confirm the GitHub-hosted pull-request workflow.

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
./scripts/guardrails/verify-static-security-manifests.sh
```

For the full local security guardrail proof on a running cluster:

```bash
./scripts/smoketest/verify-security-guardrails.sh
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

GitHub Packages Maven publication is a package-release path, not an Actions
artifact-retention path. Do not treat removal of a disposable service
`app-jar` Actions artifact as authority to remove or change a published
`service-common` package.

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
`post` updates Java consumers after `publish-release.yml` completes for the
tag and leaves `service-common` on the released version until it is manually
bumped back to the next snapshot. The service-common Maven release tag is
intentionally separate from lockstep source tagging
because Java consumer release workflows also run on tag pushes and must not
release from source still pinned to the snapshot dependency.

### Release Images

Release image publishing is tag-driven and owned by the source repositories:

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
- `ext-authz` publishes from
  `budgetanalyzer/ext-authz/.github/workflows/publish-release.yml`
- on `push` of a strict `vX.Y.Z` tag, the workflows publish the stripped
  numeric SemVer Docker tag and print a digest-pinned image reference for the
  production inventory step; they do not publish `latest`
- on `workflow_dispatch`, `release_ref` identifies the source ref to build; a
  SemVer tag defaults to Docker label `X.Y.Z`, while non-SemVer source refs
  require an explicit Docker-safe `docker_label`
- ad hoc Docker labels are registry labels only; artifact identity still comes
  from the digest-pinned reference recorded in the checked-in reference files
- the Java workflows read `serviceCommon` from the checked-out
  `gradle/libs.versions.toml`, use that value for GitHub Packages preflight and
  Docker dependency resolution, and do not require `release_ref` to equal the
  checked-in `serviceCommon` version
- manual release-image rebuilds are supported only for tags created under the
  `v0.0.14`-forward contract; older tags remain intentionally unsupported
- the production image inventory lives in
  `kubernetes/production/apps/image-inventory.yaml`, and
  `kubernetes/production/apps` renders the digest-pinned app image overlay
  from that inventory
- before a changed `service-common` library can be used by published Java
  images, publish the library version and update the consumers' checked-in
  `serviceCommon` value
- `./scripts/repo/tag-release.sh` is now the normal single-repository tag
  helper and requires `--repo`; it does not tag every Budget Analyzer repo by
  default, and it accepts any repo in `LOCKSTEP_RELEASE_REPOS`. Tagging a repo
  without a tag-triggered publish workflow, such as `checkstyle-config`, only
  marks the source version and does not add it to the runtime artifact set
- keep existing Java consumers on their checked-in `serviceCommon` version
  unless the shared library actually changed
- production-reference manifests record the historical reference id,
  orchestration revision,
  per-artifact source refs, source commits, artifact versions,
  `service-common` versions for Java workloads, and digest-pinned GHCR image
  refs
- `./scripts/guardrails/verify-production-image-overlay.sh` verifies the full
  checked-in production reference offline: the rendered production app overlay,
  the production infrastructure overlay, and the reviewed
  route/ingress/monitoring/egress render output. It rejects localhost hosts,
  placeholder Auth0 values, mutable image refs, and `imagePullPolicy: Never`,
  uses a client-side Kiali render with deterministic namespace-scoped RBAC,
  verifies
  the Redis StatefulSet uses a `5Gi` `redis-data` claim template, then applies
  the production image Kyverno policy from
  `kubernetes/kyverno/policies/production/`

### Manual validation from a clean environment

The GitHub Actions and tag-driven workflows cover every remote publish path that
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
3. **Test failures**: Check the failed run's `test-results` artifact. The four
   deployable Java services retain this JUnit XML for one day; successful runs
   intentionally have no regular CI artifact.
4. **GitHub Packages preflight failed**: Confirm
   `SERVICE_COMMON_PACKAGES_USERNAME` /
   `SERVICE_COMMON_PACKAGES_READ_TOKEN` are configured and that the pinned
   `serviceCommon` version in `gradle/libs.versions.toml` has been published

### Viewing Results

- Go to the repository's **Actions** tab
- Click on the failed workflow run
- For a failed deployable-Java run, download the one-day `test-results`
  artifact for detailed JUnit reports
