# GitHub Actions Coverage Gates And Enforcement Plan

Establish durable, observable code-coverage gates across the active Budget Analyzer repositories.
The implementation keeps the existing Java and frontend thresholds, adds a behavior-backed Go
threshold for `ext-authz`, puts the offline OpenAPI operation-coverage contract into GitHub
Actions, publishes native coverage artifacts, and prevents release workflows from publishing an
unverified source ref. GitHub repository settings and all git/PR operations remain human-owned.

The active implementation scope is `service-common`, `currency-service`, `permission-service`,
`transaction-service`, `session-gateway`, `budget-analyzer-web`, `ext-authz`,
`budget-analyzer-api-tests`, and `orchestration`. The archived
`token-validation-service` is explicitly excluded.

Existing percentage gates remain unchanged:

| Repository or module | Minimum coverage |
| --- | --- |
| `currency-service` | 90% line, 85% branch |
| `permission-service` | 80% line, 70% branch |
| `transaction-service` | 80% line, 75% branch |
| `session-gateway` | 90% line, 65% branch |
| `service-common/service-core` | 80% line, 70% branch |
| `service-common/service-web` | 93% line, 80% branch |
| `budget-analyzer-web` | 80% statements, 80% branches, 75% functions, 80% lines |
| `ext-authz` target | 70% Go statement coverage after behavior-focused Redis session tests |

`budget-analyzer-api-tests` uses OpenAPI operation coverage rather than source-line coverage: every
non-deferred operation in the checked-in OpenAPI snapshot must have a non-placeholder test marker.

## Human prerequisites and gates

Human work is not an execution step for an AI Session Handler phase. Stop at the relevant boundary
until the following prerequisite is satisfied.

Before Phases 2 through 6:

1. A GitHub repository administrator must confirm that
   `SERVICE_COMMON_PACKAGES_USERNAME` and `SERVICE_COMMON_PACKAGES_READ_TOKEN` remain configured
   for `currency-service`, `permission-service`, `transaction-service`, and `session-gateway`, and
   that they can read the pinned `service-common` packages. Do not expose either secret to an agent
   or record its value in an artifact. A recent successful existing build or release preflight is
   sufficient evidence.

Before Phase 11:

1. A human must review the changes from Phases 1 through 10, perform all repository-local git
   operations, open or update the pull requests, merge them, and wait for the new workflows to run
   successfully on each repository's `main`. Agents must not commit, push, create tags, or merge.
2. A Budget Analyzer organization administrator must activate rulesets or equivalent branch
   protection for `main`. For the eight code/test repositories, require the `Build / build` check.
   For `orchestration`, require `Security Guardrails / static-security-guardrails` and
   `Test Setup Script / test-summary`. The rules must require changes to pass through a pull
   request, block force pushes and branch deletion, and not grant a routine bypass that makes the
   required checks optional. An emergency organization-owner bypass, if retained, must be
   documented as exceptional use.
3. The administrator must confirm the required check names from successful runs before activating
   enforcement. If GitHub reports a different check context, correct the rule to the observed
   context rather than renaming stable workflow/job ids casually.
4. The administrator must provide the repository and ruleset URLs, or otherwise make the settings
   publicly readable, so Phase 11 can verify enforcement without administrative credentials.

No Codecov, Coveralls, Sonar, live Budget Analyzer target, identity-provider credentials, session
cookies, Kubernetes credentials, or production access is required by this plan. Coverage evidence
uses GitHub Actions artifacts with the repositories' existing seven-day retention convention.

## Phase 1: Establish The Ecosystem Coverage Policy

### Workspace

.

### Goal

Make the orchestration repository the explicit source of truth for coverage, release verification,
artifact retention, and required-check policy before changing repository-local workflows.

### Scope

Update `docs/OWNERSHIP.md`, `docs/ci-cd.md`, and the concise GitHub Actions guidance in `AGENTS.md`.
Document the current thresholds, the planned 70% `ext-authz` threshold, reusable build/release
contract, seven-day native artifact policy, OpenAPI operation-coverage distinction, ruleset target,
and human-owned activation sequence.

### Non-goals

Do not edit sibling repositories, GitHub settings, archived documents, decision records, or live
infrastructure. Do not claim that branch protection or release verification is active before the
later repository phases and human prerequisite are complete.

### Required context

Read `docs/OWNERSHIP.md`, `docs/ci-cd.md`, `docs/agents-md-checkstyle.md`, `AGENTS.md`, and this plan.
Recheck the public `main` workflow inventory and branch-protection state because GitHub settings can
change independently of the worktree. If the documented threshold matrix no longer matches the
repository build configuration, stop and reconcile the discrepancy before writing policy.

### Execution steps

1. Update the CI/CD row in `docs/OWNERSHIP.md` first so `docs/ci-cd.md` clearly owns continuous
   integration, coverage gates and artifacts, required checks, and release verification as well as
   release/deployment terminology.
2. Correct any drift in `docs/ci-cd.md` between its workflow description and the checked-in public
   `main` workflows; distinguish current state, rollout state, and target state precisely.
3. Add the threshold matrix and define a meaningful gate as a command that exits nonzero below the
   threshold, not merely a generated or uploaded report.
4. Define the reusable workflow contract: workflow name `Build`, job id `build`,
   `workflow_call` support, release/publish jobs dependent on the reusable build, and no remote
   publication when verification fails.
5. Define coverage artifact contents and retention: machine-readable XML/JSON or Go profile,
   human-readable HTML/text where supported, no credentials, and seven-day retention.
6. Document the OpenAPI operation-coverage gate separately from implementation line coverage, and
   explicitly exclude live API execution from hosted CI.
7. Record the human prerequisite and required-check contexts without embedding GitHub credentials
   or instructing an agent to mutate repository settings.
8. Add only a concise, stable policy summary and source-of-truth link to `AGENTS.md`, following
   `docs/agents-md-checkstyle.md`; keep detailed inventories in `docs/ci-cd.md`.

### Implementation notes

The initial gates remain repository-global or module-global. Per-class and changed-line thresholds
are deferred until the native reports have enough history to select non-arbitrary limits. Preserve
the existing Node 24-ready action-major policy. Do not add a third-party coverage service in this
phase.

### Validation

Run `git diff --check -- AGENTS.md docs/OWNERSHIP.md docs/ci-cd.md
docs/plans/github-actions-coverage-gates-plan.md`. Verify every changed relative link and every
named repository/workflow path. Use public read-only GitHub API calls to reconfirm current
protection state; do not authenticate with an administrative token.

### Completion criteria

The ownership map names the CI/CD policy owner, the owner document accurately separates current
and target behavior, the human gates are explicit, and no sibling repository or external setting
has been changed.

## Phase 2: Gate Service Common Builds And Publishing

### Workspace

../service-common

### Goal

Make both Maven snapshot and release publishing depend on the same coverage-gated build used by
pull requests, and preserve useful JaCoCo reports as workflow artifacts.

### Scope

Update `.github/workflows/build.yml`, `.github/workflows/publish-snapshot.yml`,
`.github/workflows/publish-release.yml`, `README.md`,
`docs/versioning-and-compatibility.md`, and the closest coverage/testing documentation that
describes CI behavior.

### Non-goals

Do not change the existing module thresholds, package coordinates, checked-in version, publication
destination, source tag semantics, Java source, or remote GitHub Packages state. Do not run a
publishing task against GitHub Packages during validation.

### Required context

Read the repository `AGENTS.md`, `README.md`, `build.gradle.kts`,
`docs/versioning-and-compatibility.md`, `docs/testing-patterns.md`, and all three workflow files.
Confirm `service-core` still enforces 80% line/70% branch and `service-web` still enforces 93%/80%.
The initial human prerequisite does not require cross-repository package secrets for this phase,
but GitHub Packages write permissions must remain unchanged.

### Execution steps

1. Add `workflow_call` to `build.yml` without changing workflow name `Build` or job id `build`.
2. After the Gradle build, upload all module JaCoCo XML and HTML reports as a seven-day
   `coverage-reports` artifact. Use `if: always()` and an explicit missing-file policy so a failed
   test does not hide whatever report evidence was produced.
3. Add a reusable-build verification job to both publish workflows and make their existing publish
   jobs depend on it. Preserve the existing tag/version validation and package permissions.
4. Ensure a failed test, formatting check, Checkstyle check, or either module's JaCoCo verification
   prevents `./gradlew publish` from executing.
5. Update the README and canonical versioning/testing documentation to describe release and
   snapshot verification, artifact locations, thresholds, and local reproduction commands.
6. Keep coverage claims internally consistent; remove stale generic “80% overall” statements where
   they contradict the two module-specific thresholds.

### Implementation notes

Use a reusable workflow call rather than copying the Gradle verification steps into each publish
workflow. Keep the aggregate module gates; do not add thresholds to the two platform/BOM projects,
which contain no production bytecode. The workflow must not print package tokens.

### Validation

Run `actionlint .github/workflows/*.yml`, then the repository-required sequence
`./gradlew clean spotlessApply` and `./gradlew clean build`. Confirm the build log executes
`jacocoTestCoverageVerification` for `service-core` and `service-web`. Inspect the workflow graph
statically to prove both publish jobs have an explicit dependency on the reusable verification
job. Verify changed documentation links and run `git diff --check`. Do not run `./gradlew publish`.

### Completion criteria

Pull requests and direct build runs retain both module gates, coverage evidence is downloadable,
and neither snapshot nor release publication can start before the reusable build succeeds.

## Phase 3: Gate Currency Service Releases

### Workspace

../currency-service

### Goal

Make currency-service release images depend on its existing 90% line and 85% branch gate and expose
the JaCoCo report produced by normal builds.

### Scope

Update `.github/workflows/build.yml`, `.github/workflows/publish-release.yml`, `README.md`, and
`docs/local-development.md`.

### Non-goals

Do not change coverage minimums, provider behavior, Java source, `service-common` version,
Dockerfile semantics, release labels, target platform, GHCR state, or production manifests.

### Required context

Read the repository `AGENTS.md`, `README.md`, `docs/local-development.md`, `build.gradle.kts`, both
workflow files, and the orchestration CI/CD policy. The GitHub Packages secret human prerequisite
must be satisfied before editing; stop if it is not.

### Execution steps

1. Add `workflow_call` to `build.yml` while preserving workflow name `Build`, job id `build`, PR and
   `main` triggers, permissions, and GitHub Packages environment mapping.
2. Upload JaCoCo XML and HTML output as an always-attempted seven-day `coverage-report` artifact
   after the Gradle build.
3. Add a reusable `Build` verification job to `publish-release.yml`, inherit only the secrets the
   existing build requires, and make the image-publishing job depend on successful verification.
4. Preserve all existing release-ref validation, GitHub Packages preflight behavior, BuildKit
   secret handling, ARM64 image policy, labels, and digest reporting.
5. Update the README and local-development owner doc to explain that the same coverage gate blocks
   PR builds and release-image publication, and identify the downloadable report.

### Implementation notes

Do not move the threshold out of `build.gradle.kts`; Gradle remains the executable source of truth.
The Dockerfile may continue to use `bootJar` because the workflow now verifies the exact checked-out
source before allowing the Docker publish job to run.

### Validation

Run `actionlint .github/workflows/*.yml`, `./gradlew clean spotlessApply`, and
`./gradlew clean build`. Confirm `jacocoTestCoverageVerification` runs and the threshold literals
remain 0.90/0.85. Inspect the release job dependency and secret flow without dispatching it. Verify
changed links and run `git diff --check`.

### Completion criteria

The stable PR check remains `Build / build`, its JaCoCo evidence is retained, and every tag or
manual release image publish waits for the same 90%/85% build gate.

## Phase 4: Gate Permission Service Releases

### Workspace

../permission-service

### Goal

Make permission-service release images depend on its existing 80% line and 70% branch gate and
retain the JaCoCo evidence from CI.

### Scope

Update `.github/workflows/build.yml`, `.github/workflows/publish-release.yml`, `README.md`, and the
closest active documentation describing CI and release dependency resolution.

### Non-goals

Do not change coverage minimums, authorization behavior, seed data, Java source,
`service-common` version, Dockerfile semantics, release labels, GHCR state, or deployment wiring.

### Required context

Read the repository `AGENTS.md`, `README.md`, `build.gradle.kts`, both workflows, and the active
CI/release dependency-resolution documentation. The GitHub Packages secret human prerequisite must
be satisfied before editing; stop if it is not.

### Execution steps

1. Add `workflow_call` to the existing `Build / build` workflow without changing its normal
   triggers or package credential mapping.
2. Upload JaCoCo XML and HTML as an always-attempted seven-day `coverage-report` artifact.
3. Call the reusable build from `publish-release.yml` and make the image-publishing job depend on
   it, inheriting the existing package-read secrets without logging them.
4. Preserve release-ref validation, package preflight behavior, BuildKit secret handling, ARM64
   publishing, labels, and digest reporting.
5. Update the nearest documentation to describe the required release verification and retained
   coverage report.

### Implementation notes

Keep the aggregate Gradle rule and threshold literals in `build.gradle.kts`. Do not add trivial
tests or exclusions merely to create additional headroom.

### Validation

Run `actionlint .github/workflows/*.yml`, followed by `./gradlew clean spotlessApply` and
`./gradlew clean build`. Inspect the full output for warnings, confirm
`jacocoTestCoverageVerification` executes at 0.80/0.70, inspect release job dependencies, verify
changed links, and run `git diff --check`. Do not dispatch or publish a release.

### Completion criteria

The required build context remains stable, coverage reports are available for diagnosis, and no
permission-service image can be published by the release workflow before the 80%/70% build passes.

## Phase 5: Gate Transaction Service Releases

### Workspace

../transaction-service

### Goal

Make transaction-service release images depend on its existing 80% line and 75% branch gate and
retain CI coverage evidence.

### Scope

Update `.github/workflows/build.yml`, `.github/workflows/publish-release.yml`, `README.md`, and
`docs/configuration.md` where it describes CI/release artifact resolution.

### Non-goals

Do not modify domain behavior, migrations, Java source, statement-import behavior,
`service-common` version, coverage minimums, Dockerfile behavior, release labels, GHCR state, or
production desired state.

### Required context

Read the repository `AGENTS.md`, `README.md`, `docs/configuration.md`, `build.gradle.kts`, and both
workflow files. The GitHub Packages secret human prerequisite must be satisfied before editing;
stop if it is not. If local `service-common` artifacts are missing, follow the repository-owned
artifact-resolution prerequisite rather than weakening the build.

### Execution steps

1. Add `workflow_call` to `build.yml` while retaining workflow name `Build`, job id `build`, and
   existing PR, `main`, permission, and package-secret behavior.
2. Upload JaCoCo XML and HTML as an always-attempted seven-day `coverage-report` artifact.
3. Add reusable build verification to the release workflow and make the existing image publish job
   depend on it with the existing package-read secrets inherited safely.
4. Preserve release-ref checks, package preflight, BuildKit secret usage, ARM64 publication,
   labeling, and digest output.
5. Update repository documentation so the release verification and coverage artifact are locally
   reproducible and accurately described.

### Implementation notes

Keep this phase limited to CI/release configuration and documentation. Do not use orchestration
environment overrides to compensate for a failing service build or test.

### Validation

Run `actionlint .github/workflows/*.yml`, then the required
`./gradlew clean spotlessApply` and `./gradlew clean build` sequence. Confirm the full build runs
JaCoCo verification at 0.80/0.75 and contains no in-scope warnings. Inspect release dependencies,
verify changed links, and run `git diff --check`. Do not run the release workflow.

### Completion criteria

Normal builds retain their coverage gate and report artifact, and all transaction-service release
publishing paths wait for successful reusable verification.

## Phase 6: Gate Session Gateway Releases

### Workspace

../session-gateway

### Goal

Make Session Gateway release images depend on its existing 90% line and 65% branch gate and retain
the JaCoCo evidence from CI.

### Scope

Update `.github/workflows/build.yml`, `.github/workflows/publish-release.yml`, `README.md`, and
`docs/local-development.md`.

### Non-goals

Do not change browser session behavior, Redis schema, OAuth2 behavior, authorization contracts,
coverage minimums, Java source, `service-common` version, Dockerfile behavior, GHCR state, or
orchestration wiring.

### Required context

Read the repository `AGENTS.md`, `README.md`, `docs/local-development.md`, `build.gradle.kts`, both
workflow files, and the shared session-contract pointer. The GitHub Packages secret human
prerequisite must be satisfied before editing; stop if it is not. Follow the documented Maven Local
prerequisite if local `service-common` resolution fails.

### Execution steps

1. Add `workflow_call` to `build.yml` without changing workflow name `Build`, job id `build`, normal
   triggers, permissions, or package credential mapping.
2. Upload JaCoCo XML and HTML as an always-attempted seven-day `coverage-report` artifact.
3. Add reusable build verification to `publish-release.yml` and make its image publish job depend
   on verification, with existing package-read secrets inherited safely.
4. Preserve release-ref validation, package preflight, BuildKit secret behavior, ARM64 output,
   labels, and digest reporting.
5. Update the closest documentation to describe coverage-gated release publishing and report
   retrieval without duplicating the orchestration-wide policy.

### Implementation notes

The relatively lower branch threshold is an existing explicit baseline, not permission to weaken
tests. Keep threshold changes outside this plan and preserve the direct Session Gateway ownership
of browser session behavior.

### Validation

Run `actionlint .github/workflows/*.yml`, `./gradlew clean spotlessApply`, and
`./gradlew clean build` in that order. Confirm JaCoCo verification executes at 0.90/0.65, inspect
all warnings, verify release job dependencies and changed documentation links, and run
`git diff --check`. Do not publish an image.

### Completion criteria

The stable build check retains its thresholds and downloadable report, and Session Gateway release
publishing cannot begin until the reusable build succeeds.

## Phase 7: Make Frontend Release Verification Explicit

### Workspace

../budget-analyzer-web

### Goal

Retain the frontend's four existing Vitest thresholds as native artifacts and make release
verification an explicit workflow dependency rather than relying only on a nested Docker build.

### Scope

Update `.github/workflows/build.yml`, `.github/workflows/publish-release.yml`,
`docs/testing-guide.md`, and `docs/development.md`. Update `README.md` or `AGENTS.md` only if their
workflow summary must change to remain accurate.

### Non-goals

Do not change coverage thresholds or exclusions, application code, CSP policy, Playwright scope,
Node baseline, Docker runtime behavior, target architecture, release labeling, or GHCR state.

### Required context

Read the repository `AGENTS.md`, `docs/testing-guide.md`, `docs/development.md`, `package.json`,
`vitest.config.ts`, `Dockerfile.production`, and both workflows. Preserve the user-owned development
server boundary; no Vite or Tilt server is needed.

### Execution steps

1. Add `workflow_call` to the existing workflow while preserving workflow name `Build`, job id
   `build`, normal triggers, Node 22 setup, lint, coverage, CSP production-smoke, and bundle steps.
2. Upload the `coverage/` text-summary data and HTML/JSON outputs as an always-attempted seven-day
   `coverage-report` artifact after `npm run test:coverage`.
3. Add a reusable build verification job to `publish-release.yml` and require it before the image
   publish job.
4. Keep `Dockerfile.production`'s coverage-gated `npm run build` unless measured workflow cost and a
   separate reviewed change justify removing the defense-in-depth rerun; do not silently replace it
   with `build:bundle` in this phase.
5. Document the explicit release dependency, retained artifact, duplicate defense-in-depth check,
   and existing global threshold/exclusion semantics in the existing owner documents.

### Implementation notes

Do not add source-map or bundled application artifacts to the coverage upload beyond what the
existing V8 reporters generate. The four thresholds remain global rather than per-file. Do not add
a hosted coverage vendor.

### Validation

Run `actionlint .github/workflows/*.yml`, `npm run lint:fix`, `npm run test:coverage`, and
`npm run build`. Confirm statements/branches/functions/lines remain 80/80/75/80 and the JSON summary
is present. Verify the release workflow dependency, changed documentation links, and
`git diff --check`. Do not run a development server or publish an image.

### Completion criteria

The `Build / build` context remains stable, the V8 report is downloadable, and the release workflow
cannot publish before an explicit successful frontend build while the production Docker build
retains its independent gate.

## Phase 8: Build Ext Authz Coverage To A Meaningful Floor

### Workspace

../ext-authz

### Goal

Raise `ext-authz` from its measured 23.9% statement baseline to at least 70% through meaningful
session-store and configuration behavior tests, and leave one reproducible local gate ready for CI.

### Scope

Add focused Go tests for previously uncovered Redis session behavior and log-level parsing, add a
reproducible local coverage-check script, update the local testing guidance in `README.md`, and
update `go.mod`/`go.sum` only for a focused in-process Redis test dependency if required.

### Non-goals

Do not change the shared Redis session schema, cookie or identity-header contract, production retry
or TLS semantics, ports, probes, Istio fail-closed behavior, Docker image contract, or release
labels. Do not add tests for percentage alone or exclude production files to manufacture 70%.

### Required context

Read the complete repository `AGENTS.md`, `README.md`, all production and test Go files, `go.mod`,
and both workflows. Read the orchestration shared session contract before testing Redis fields.
Record the current `go test -cover ./...` baseline before editing. If the baseline has fallen below
23.9% or the session contract differs, stop and diagnose the discrepancy.

### Execution steps

1. Add behavior-focused tests for successful session lookup, absent sessions, malformed expiry,
   expired sessions, resolved identity fields, and Redis health checks using an in-process Redis
   implementation or another deterministic test boundary that does not require a live cluster.
2. Cover `NewSessionStore` success and safe configuration/TLS validation paths without waiting
   through production retry delays or weakening retry behavior. Test `parseLogLevel` variants.
3. Add a small local coverage command under `scripts/` that runs all Go tests with a temporary or
   caller-selected profile, prints `go tool cover -func` output, and exits nonzero below 70.0%
   total statement coverage. Make parsing locale-independent and fail closed when the total is
   absent or malformed. Give the script a deterministic `--self-test` mode that proves below-floor
   and malformed totals are rejected without changing the checked-in minimum.
4. Document the 70% floor, local command, current coverage interpretation, and ratchet policy in
   `README.md` without claiming hosted or release enforcement yet.

### Implementation notes

An in-process Redis library is acceptable only as a test dependency and only when its semantics
cover the commands used by `SessionStore`. Prefer tests around observable results over mocks of the
Redis client. Keep `main()` in the measured package; do not exclude it to reach the target. If 70%
cannot be reached without a production refactor, stop with the uncovered function report and
propose the smallest behavior-preserving seam instead of lowering the threshold.

### Validation

Run `gofmt -w` on changed Go files, `go mod tidy`, `bash -n` and `shellcheck` on the new coverage
script, its `--self-test`, the normal local coverage command, and `go test ./...`. Confirm total
statement coverage is at least 70%, verify documentation links, and run `git diff --check`.

### Completion criteria

Previously untested session behavior has deterministic tests and the repository has one
reproducible, self-tested 70% statement gate without changing production contracts. The worktree is
a coherent checkpoint even though hosted workflow enforcement belongs to the next phase.

## Phase 9: Enforce Ext Authz Coverage In Build And Release CI

### Workspace

../ext-authz

### Goal

Use the completed local 70% gate in normal GitHub builds and require the same reusable build before
any ext-authz release image can publish.

### Scope

Update `.github/workflows/build.yml`, `.github/workflows/publish-release.yml`, `README.md`, and
`AGENTS.md`. Generate and retain Go coverage profile, function-summary, and HTML evidence.

### Non-goals

Do not change the 70% floor established in Phase 8, add tests solely for CI behavior, alter service
contracts, modify Dockerfile semantics, publish an image, change release labels, or mutate GitHub
settings.

### Required context

Phase 8 must be complete and its local coverage command and self-test must pass. Read the complete
repository `AGENTS.md`, `README.md`, the coverage script, both workflows, and the orchestration
CI/CD policy. If current coverage is below 70%, return to the Phase 8 defect instead of weakening
the workflow or threshold.

### Execution steps

1. Add `workflow_call` to `build.yml` while preserving workflow name `Build`, job id `build`, normal
   triggers, read-only permissions, formatting check, and Docker build.
2. Replace bare `go test ./...` with the repository coverage command and generate profile, text,
   and HTML evidence for an always-attempted seven-day `coverage-report` artifact.
3. Keep formatting and Docker-build checks after coverage so a failed gate prevents the image build
   inside normal CI.
4. Add reusable build verification to `publish-release.yml` and make remote image publishing depend
   on it without changing release-ref validation, target platform, labels, or digest output.
5. Update `README.md` with artifact and release-enforcement behavior, and update `AGENTS.md` because
   the repository quality gate and workflow changed, applying the shared AGENTS.md standard.

### Implementation notes

Do not duplicate threshold parsing in YAML; call the repository script. Artifact upload may run
after a failure, but Docker build and release publishing may not. The release workflow needs no
live Redis or Kubernetes target.

### Validation

Run the local coverage command and its self-test, `go test ./...`,
`actionlint .github/workflows/*.yml`, and `docker build -t ext-authz:coverage-plan .`. Inspect the
workflow graph to prove release publishing depends on reusable verification. Verify documentation
links and run `git diff --check`; do not dispatch a release.

### Completion criteria

`Build / build` enforces and retains evidence for the 70% statement floor, its existing formatting
and Docker checks still run, and no tag or manual release can publish before reusable verification.

## Phase 10: Put OpenAPI Operation Coverage In Hosted CI

### Workspace

../budget-analyzer-api-tests

### Goal

Create the repository's first GitHub Actions build so offline quality checks and complete
non-placeholder OpenAPI operation-marker coverage become a stable required check without needing a
live Budget Analyzer deployment or credentials.

### Scope

Add `.github/workflows/build.yml`, add `docs/continuous-integration.md`, and update `README.md` and
`AGENTS.md`. Use the existing Python 3.12 project, Ruff, mypy, pytest harness tests, OpenAPI coverage
tools, snapshot, and deferred-operation inventory.

### Non-goals

Do not run live gateway, browser-login, mutation, destructive, staging, or production tests in
GitHub-hosted CI. Do not add sessions or identity-provider secrets, weaken TLS, broaden production
permissions, change deferred admin operations, or introduce Python source-line coverage in place of
the OpenAPI contract gate.

### Required context

Read the complete repository `AGENTS.md`, `README.md`, `pyproject.toml`, the pytest plugin,
`tests/contract/test_openapi_coverage.py`, the coverage CLI implementations, and the checked-in
OpenAPI/deferred schemas. Ensure Python 3.12 and the repository-local development environment can
install `.[dev]`; if installation prerequisites are missing, stop rather than dropping quality
steps.

### Execution steps

1. Add a Node 24-ready `Build` workflow with job id `build`, read-only contents permission, and
   push-to-`main`, pull-request-to-`main`, `workflow_dispatch`, and `workflow_call` triggers.
2. Set up Python 3.12, install `.[dev]`, and run `ruff format --check`, `ruff check`, and strict mypy
   across `src` and `tests`.
3. Run test collection and the deterministic offline contract/tool test files that exercise marker
   policy, OpenAPI coverage, environment policy, schema assertions, request builders, and coverage
   CLIs. Name exact paths; do not select the live unknown-route or public API tests accidentally.
4. Run `tools/check-openapi-coverage.py --env local --source snapshot --fail-missing
   --fail-placeholder` so a new undocumented or placeholder-only operation fails the workflow.
5. Export `artifacts/openapi-coverage.json` from the snapshot and upload it as an always-attempted
   seven-day `openapi-coverage` artifact. Confirm it contains no environment secrets or sessions.
6. Document hosted CI scope, local reproduction, artifact schema pointer, required check name, and
   the deliberate separation between offline operation coverage and credentialed live acceptance.
7. Update `AGENTS.md` because quality gates and workflow discovery changed, applying the shared
   AGENTS.md authoring standard.

### Implementation notes

Use `actions/checkout@v6` and `actions/setup-python@v6` with
`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`. Do not install Playwright browsers because no browser
test is selected. Prefer an explicit offline pytest path list until the repository has a reliable
`offline` marker; do not use broad deselection that could silently admit a network fixture later.

### Validation

Run `actionlint .github/workflows/build.yml`. In the repository-local virtual environment run
`ruff format .`, `ruff check . --fix`, `mypy src tests`, pytest collection, every exact offline test
path selected by the workflow, the OpenAPI coverage check with both failure flags, and the export command. Inspect
the JSON for secrets, verify documentation links, and run `git diff --check`. Do not invoke a live
target or install a browser.

### Completion criteria

The repository exposes stable `Build / build` CI, all selected checks run without network or
credentials, missing and placeholder OpenAPI operation coverage fails CI, and a safe coverage
artifact is retained.

## Phase 11: Verify Human Enforcement And Finalize Documentation

### Workspace

.

### Goal

Prove that the completed repository workflows are actually required on `main`, reconcile the
orchestration documentation with live GitHub state, and leave an auditable operator-facing policy.

### Scope

Perform read-only GitHub settings and workflow-run verification, then update `docs/ci-cd.md`,
`docs/OWNERSHIP.md` if its wording still needs reconciliation, and the concise `AGENTS.md` summary
if necessary. Record repository/check coverage without copying volatile run histories.

### Non-goals

Do not create or edit rulesets, branch protection, secrets, pull requests, tags, releases, GitHub
Packages, GHCR images, Kubernetes resources, or production systems. Do not use an administrative
token. Do not declare success from workflow YAML alone.

### Required context

All four “Before Phase 11” human prerequisites must be complete. Read the final
`docs/OWNERSHIP.md`, `docs/ci-cd.md`, `AGENTS.md`, this plan, and the human-provided GitHub ruleset or
repository URLs. If any active repository has not merged and successfully run its workflow, or any
required rule is not active, stop and report the missing human prerequisite rather than editing
documentation to predict future state.

### Execution steps

1. Query each active repository's public `main` branch metadata and require `protected=true`.
2. Inspect the applied rules for the eight code/test repositories and prove `Build / build` is a
   required status check. Inspect orchestration rules for
   `Security Guardrails / static-security-guardrails` and `Test Setup Script / test-summary`.
3. Confirm the applied rules require pull requests and block force pushes/deletion, and document
   any emergency bypass exactly as approved by the human administrator.
4. Inspect one successful post-merge build per repository to confirm coverage execution and native
   artifact publication. For each publish workflow, inspect its graph or a non-publishing test
   execution and prove the publish job depends on reusable verification; do not trigger a release.
5. Update `docs/ci-cd.md` from rollout language to active policy only for controls proven in the
   prior steps. Keep detailed thresholds and check contexts in this canonical owner.
6. Reconcile the ownership row and concise `AGENTS.md` pointer if needed, removing any stale claim
   that coverage or release verification is merely planned.
7. Record the read-only verification commands and interpretation rules, not transient workflow run
   ids or an inventory likely to drift.

### Implementation notes

Public GitHub API evidence is preferred because it does not expose administrative credentials.
Respect unauthenticated API rate limits and stop with a clear retry prerequisite if exhausted.
Ruleset evaluation mode is not enforcement; require active enforcement. A successful workflow that
is not a required check is not a completed gate.

### Validation

Run the documented read-only protection/rules queries and require successful assertions for every
active repository. Verify each changed link and named check context, then run
`git diff --check -- AGENTS.md docs/OWNERSHIP.md docs/ci-cd.md
docs/plans/github-actions-coverage-gates-plan.md`. Compare the final policy against this plan's
threshold table and completion criteria.

### Completion criteria

Every active `main` branch is protected, the intended required checks are enforced, release and
publish jobs demonstrably depend on coverage-gated verification, coverage evidence is retrievable,
and the canonical documentation describes proven current behavior without requiring secret or
production access.
