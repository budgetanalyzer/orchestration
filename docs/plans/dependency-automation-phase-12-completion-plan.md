# Dependency Automation Direct Promotion Plan

This plan replaces the rollback-heavy Phase 12 completion sequence with a direct
production conversion of the already verified dependency-automation implementation.
The accepted trial evidence is sufficient: Gate C controlled-upload work, Gate D
schedule proving, rollback rehearsal, and a second promotion plan are waived. The
implementation is retained; trial-only branch wiring, variables, evidence collection,
GitHub CLI bridges, mock GitHub CLI tests, resume machinery, and active trial runbooks
are removed.

The executable phases make repository-local file changes only. They do not commit,
push, open or merge pull requests, change GitHub settings, dispatch hosted workflows,
delete branches or artifacts, or call GitHub APIs. The operator-owned prerequisite and
post-plan sections below contain those actions so that AI Session Handler workers do
not need GitHub credentials and do not cross the repository's Git ownership boundary.

## Accepted decision and target state

- Treat the successful trial branch builds, dependency submissions, Mend cycles,
  representative Renovate pull requests, and scanner runs as sufficient promotion
  evidence.
- Waive the remaining Gate C and Gate D evidence work. Do not finish or replace the
  controlled-upload runner.
- Promote the implementation already present on the nine
  `dependency-automation-trial` branches. Do not merge any Renovate-created dependency
  update pull request as part of promotion.
- Make `main` the sole durable branch target. Every repository's `renovate.json` must
  extend `github>budgetanalyzer/orchestration//renovate-presets/default` without an
  explicit branch suffix.
- Remove `dependency-automation-trial`, every
  `DEPENDENCY_AUTOMATION_TRIAL_*` workflow reference, and every trial-only event,
  cache, upload, graph-submission, or evidence condition from active configuration and
  documentation.
- Remove the orchestration Gate C/baseline shell automation, its mock `gh`, its tests,
  exact-ID resume behavior, and all dependency-automation-specific shell calls to
  `gh api`. Existing non-trial GitHub CLI use in unrelated release/package workflows
  is out of scope.
- Preserve the shared Renovate preset, repository-specific Renovate extraction, the
  official Gradle dependency-submission workflows, npm audit, `govulncheck`, exact
  image scanning, and the workspace image build-and-scan workflow.
- Preserve the four Java consumers' Maven Central exclusion for
  `org.budgetanalyzer`, the workspace `setup-trivy` public `git-tags` fallback, and all
  other corrections made while proving the trial.
- Preserve the regular-CI storage correction: `currency-service`,
  `permission-service`, `transaction-service`, and `session-gateway` must not upload
  `app-jar`; they retain JUnit XML only after a failed build and only for one day.
  `service-common`'s package/library JAR artifacts and the frontend's `dist` artifact
  are different contracts and remain.
- Keep short-lived scanner evidence, but enforce its size before upload without a
  GitHub API round trip. The reusable evidence helper has a production name, creates
  one allowlisted gzip archive, rejects a compressed payload above 24 MiB
  (25,165,824 bytes), and leaves one MiB of headroom below the old 25 MiB retained-size
  threshold. Production scanner artifacts retain for seven days with upload-action
  compression disabled because the payload is already compressed.
- Keep schedules and workflow permissions least-privileged. Never add paid Mend
  features, automerge, a self-hosted Renovate bot, a payment method, or a credential to
  a repository file.

## Repository conversion map

| Repository | Durable automation retained | Trial-only surface removed |
| --- | --- | --- |
| `orchestration` | Shared preset, config validation, exact-image scanning, image rendering | Hosted trial dry run, Gate C/baseline scripts, mock `gh`, upload resume protocol, trial branch/variables |
| `service-common` | Renovate and Gradle graph submission; normal library/test artifacts | Trial build evidence, graph generation-only gate, trial branch/variables |
| `currency-service` | Renovate, authenticated Gradle graph submission, failed-test XML | Trial evidence and gates; regular-CI `app-jar` stays removed |
| `permission-service` | Renovate, authenticated Gradle graph submission, failed-test XML | Trial evidence and gates; regular-CI `app-jar` stays removed |
| `transaction-service` | Renovate, authenticated Gradle graph submission, failed-test XML | Trial evidence and gates; regular-CI `app-jar` stays removed |
| `session-gateway` | Renovate, authenticated reactive Gradle graph submission, failed-test XML | Trial evidence and gates; regular-CI `app-jar` stays removed |
| `budget-analyzer-web` | Renovate, normal build artifact, npm audit reports | Trial build/audit branches, caches, variables, and dual evidence paths |
| `ext-authz` | Renovate and reachable `govulncheck` reports | Trial build/scanner branches, caches, variables, and dual evidence paths |
| `workspace` | Renovate and no-start workspace image scanning | Trial PR/base checks, variables, post-upload `gh api` measurement, and dual evidence paths |

`budget-analyzer-api-tests` is not one of the nine trial branches and is not modified
by this plan. Its existing production Renovate configuration remains independent.

## Manual prerequisite before Phase 1

The operator must complete or confirm these items before starting AI Session Handler:

1. Record the promotion decision in the change/PR description: the remaining Gate C
   and Gate D work and rollback rehearsal are intentionally waived, and the direct
   production conversion is authorized.
2. Pause Mend Renovate processing for the nine scoped repositories, or otherwise
   prevent new bot branches and pull requests during conversion. Do not remove the App,
   Maven host rule, or package credential needed by the final production test.
3. Confirm all four trial expansion variables remain `false` in every repository while
   conversion is in progress. Do not run the Gate C helper again.
4. Update the local refs under the user's Git workflow, then confirm in each of the nine
   checkouts that `main` is an ancestor of the checked-out
   `dependency-automation-trial` branch. Resolve divergence before running the plan;
   an AI worker must not merge, rebase, reset, or switch branches.
5. Resolve or deliberately preserve every pre-existing worktree change. In particular,
   `../workspace/docs/dependency-automation.md` is already modified at plan-authoring
   time and overlaps Phase 10. The operator must either incorporate that edit into the
   promotion change or save it elsewhere; workers must never overwrite it blindly.
6. Keep all credentials outside the agent environment. The implementation phases need
   no authenticated `gh`, Mend, package, registry, billing, or repository-settings
   access.

If any prerequisite is not true, stop before Phase 1. Do not recreate trial machinery
to work around it.

## Implementation guardrails

- At the start of every phase, read that workspace's `AGENTS.md`, inspect `git status
  --short`, confirm the current branch, and verify `git merge-base --is-ancestor main
  HEAD`. Preserve unrelated changes and stop on an overlapping edit that cannot be
  reconciled safely.
- Use no Git write command. The operator owns commits, pushes, pull requests, merges,
  branch/default changes, rulesets, variables, App settings, and cleanup of hosted
  resources.
- A phase edits and validates only its declared workspace. It may rely on earlier
  phases' completion criteria but must not modify or validate a sibling checkout.
- Do not change dependency versions, lockfiles, image pins, action pins, application
  code, service behavior, or deployment manifests except where an existing retained
  dependency-automation correction already changed a declaration.
- Do not weaken a scanner or dependency graph to make production conversion pass.
  Findings remain non-gating where the existing policy says they are non-gating, but
  malformed output, failed resolution, failed submission, and incomplete scans remain
  failures.
- Apply `docs/agents-md-checkstyle.md` before editing an `AGENTS.md`. Keep active docs
  production-focused and move no new operational detail into `AGENTS.md` when the
  nearest dependency-automation guide already owns it.
- The source plan is immutable during an AI Session Handler invocation. No phase may
  edit or delete this file. Superseded plans and evidence documents named by Phase 11
  may be removed because they are different files.

## Manual post-plan promotion and acceptance

After all executable phases complete, the operator performs the GitHub and Git work in
this order:

1. Review all nine final diffs. Confirm they contain the retained implementation plus
   production conversion only, no dependency-version proposal from a bot, no secret,
   no trial variable/reference in active files, no dependency-automation `gh api`
   bridge, and no `app-jar` upload in the four deployable Java services.
2. Commit and push the production-conversion changes on the existing trial branches
   using the user's normal Git workflow. Open promotion pull requests against `main`.
3. Merge orchestration first. Require **Dependency Automation Configuration** to pass,
   confirm the shared preset exists on `main`, and wait for the production
   exact-image workflow triggered by the merge (or dispatch it once if the final
   trigger design is schedule/manual only).
4. Merge `service-common`, then the remaining seven consumer repositories. Keep Mend
   paused until every consumer can resolve the shared preset from orchestration's
   `main`. A concrete production failure is fixed in its owning repository; do not
   restore trial gates or execute a blanket rollback.
5. In each repository, make `main` the default branch immediately after its promotion
   merge is verified. Confirm normal `main` protection before removing the temporary
   trial ruleset. Close, without merging, every Renovate PR whose base is
   `dependency-automation-trial`; then delete the remote trial branch when it is no
   longer the default or a PR base.
6. Delete the four `DEPENDENCY_AUTOMATION_TRIAL_*` repository variables through the
   GitHub settings UI. Delete any remaining trial-only artifact through the Actions UI
   if it has not already expired. Do not use or restore the removed shell/`gh` helpers.
7. Confirm GitHub's dependency graph and Dependabot alerts remain enabled, Dependabot
   version-update and overlapping security-update PR creation remain disabled, and the
   Mend Maven host rule remains scoped to the `service-common` GitHub Packages path.
8. Re-enable Mend only after all nine defaults are `main`. Confirm Mend uses each
   repository's default branch and does not retain an explicit trial base. Let one
   normal cycle complete in every scoped repository; every newly created Renovate PR
   must target `main`, obey the routine/vulnerability concurrency limits, carry the
   expected label, and have automerge disabled. A repository with no proposal may
   prove health through a clean Dependency Dashboard/log; do not force a dependency
   update solely to create a PR.
9. Verify the production workflows on `main`:
   - require one successful normal Build run in each of `currency-service`,
     `permission-service`, `transaction-service`, and `session-gateway`; successful
     runs must have no `app-jar` and no test-results artifact;
   - require one accepted dependency submission from `service-common` and each of the
     four Java consumers;
   - require one successful npm audit, `govulncheck`, orchestration exact-image scan,
     and workspace image scan;
   - confirm each scanner artifact contains the complete allowlist, is at or below the
     24 MiB compressed-payload cap, and expires after seven days; and
   - confirm no dependency-automation workflow uses a trial variable, trial ref, or
     shell-based GitHub API measurement.
10. When the checks pass, record the rollout complete. If one fails, fix that concrete
    production defect and repeat only the affected check. The waived evidence gates,
    rollback protocol, and trial branches are not reopened.

## Phase 1: Convert orchestration configuration and scanner workflows

### Workspace

.

### Goal

Make orchestration's Renovate configuration and exact-image workflow production-only,
while retaining a small reusable pre-upload size guard and deleting the hosted trial
dry-run path.

### Scope

`renovate.json`, `.github/workflows/dependency-automation-config.yml`,
`.github/workflows/exact-image-security-evidence.yml`, and the evidence archive helper
and its focused test under `.github/scripts/`.

### Non-goals

No shared-preset policy changes, dependency/image/action updates, GitHub dispatches,
hosted evidence review, Gate C script cleanup, broad documentation rewrite, or sibling
repository edits.

### Required context

Read `AGENTS.md`, `docs/dependency-automation.md`, `docs/ci-cd.md`,
`renovate-presets/default.json`, both changed workflows, the existing trial evidence
helper/test, `scripts/security/render-image-scan-inputs.sh`, and this plan's accepted
target state.

### Execution steps

1. Perform the plan-wide branch, ancestry, and dirty-worktree checks. Treat every
   non-targeted branch change as retained user work.
2. Change the root `renovate.json` preset reference to
   `github>budgetanalyzer/orchestration//renovate-presets/default`. Preserve all local
   manager/extraction configuration and the shared preset itself.
3. Restrict **Dependency Automation Configuration** push and pull-request triggers to
   `main`, retain manual validation, and keep only strict validation of
   `renovate.json` and `renovate-presets/default.json`. Remove the
   `run_hosted_dry_run` input and the complete `hosted-renovate-dry-run` job, including
   its trial checkout, branch assertions, log parsing, permissions, and evidence
   upload.
4. Rename/generalize `.github/scripts/prepare-trial-evidence.sh` as a production
   dependency-evidence archive helper. Remove trial terminology while retaining its
   allowlisted relative-path checks, missing-input failure, measurement file, gzip
   archive, 25,165,824-byte payload ceiling, outputs, and summary. Rename/update the
   focused helper test to the production name; it must make no GitHub request.
5. Convert **Exact Image Security Evidence** to production `main` events. Retain the
   intended `main` push, weekly schedule, and manual dispatch unless the canonical
   policy documents a narrower production trigger. Remove the trial-message exclusion,
   schedule/cache/upload variables, exact trial ref checks, and redundant job event
   expression once event scoping makes it unnecessary.
6. Preserve offline rendering, exact platform resolution, Trivy inventories,
   vulnerability reports, incomplete-scan failure, and the existing allowlist. Replace
   the production/trial dual upload paths with one archive prepared by the generalized
   helper and one seven-day artifact upload using compression level zero.
7. Remove `actions: read`, `GH_TOKEN`, the post-upload `gh api` retained-size query,
   trial artifact IDs/links, and every trial-specific enforcement step. Keep a summary
   link to the single production artifact when the upload action supplies one.
8. Remove the old helper/test names after every retained reference uses the production
   names. Do not touch `scripts/security/render-image-scan-inputs.sh` or the verified
   tool-installation changes that support the scanner.

### Implementation notes

The pre-upload archive cap is the durable storage guard. It intentionally does not
claim an exact GitHub-retained byte count and requires no `actions: read` permission or
GitHub CLI. Preserve one MiB of headroom and fail rather than trim evidence. The
scanner's vulnerability backlog remains non-gating, but an incomplete scan or missing
allowlisted output remains a failure.

### Validation

Run the renamed helper test, `bash -n` and `shellcheck` on both changed shell files,
and `actionlint` on both workflows. Under Node 24, run Renovate's strict validator
against the repository config and local preset. Run `git diff --check`. Use targeted
`rg` checks to prove the changed files contain no `dependency-automation-trial`,
`DEPENDENCY_AUTOMATION_TRIAL`, `prepare-trial-evidence`, `gh api`, `GH_TOKEN`, Gate C,
or hosted trial dry-run reference.

### Completion criteria

Orchestration validates the production preset, the image scanner has only production
events and one capped short-lived artifact path, the generalized helper/test pass, and
no changed workflow performs a GitHub CLI/API call or contains trial branch logic.

## Phase 2: Delete orchestration Gate C and baseline automation

### Workspace

.

### Goal

Remove the abandoned cross-repository GitHub shell automation and all tests and
documentation entries that existed only for the controlled trial protocol.

### Scope

`scripts/repo/collect-dependency-automation-phase-12-baseline.sh`,
`scripts/repo/run-dependency-automation-upload-batch.sh`,
`scripts/repo/test-run-dependency-automation-upload-batch.sh`,
`scripts/repo/test-fixtures/dependency-automation-upload-batch-gh`, and their entries in
`scripts/README.md`.

### Non-goals

No deletion of general repository tooling, exact-image rendering, package-release
cleanup, the production evidence archive helper, workflow changes from Phase 1,
documentation consolidation, or GitHub-side cleanup.

### Required context

Read `AGENTS.md`, `scripts/README.md`, the four scoped scripts/fixtures, and Phase 1's
completed diff. Search for every reference to the scoped filenames before deleting
them.

### Execution steps

1. Recheck the workspace state and preserve Phase 1 plus unrelated user changes.
2. Delete the public baseline collector, the 690-line upload-batch/Gate C runner, the
   fixture GitHub CLI, and the runner's test. Remove an empty dedicated fixture
   directory if no unrelated fixture remains.
3. Remove their catalog entries and Gate C/resume/compatibility guidance from
   `scripts/README.md`. Keep the `scripts/security/` description and all unrelated
   script catalog entries.
4. Search active scripts and workflows for the deleted names, `UPLOAD BATCH GO`, exact
   trial artifact resume IDs, and dependency-automation-specific `gh api`/`gh
   variable` compatibility logic. Remove only references owned by the deleted trial
   machinery.
5. Explicitly leave unrelated GitHub CLI use in `service-common` release/package
   workflows out of scope; this phase must not make a broad ecosystem-wide claim that
   `gh` is forbidden.

### Implementation notes

This is deletion, not refactoring. Do not replace the runner with another abstraction,
REST wrapper, resumable protocol, or new test harness. Production workflow execution
uses normal GitHub events and upload actions.

### Validation

Run `git diff --check`. Confirm all four scoped paths are absent. Confirm
`scripts/README.md`, `.github/`, and `scripts/repo/` contain no reference to the
deleted paths, Gate C, `UPLOAD BATCH GO`, or dependency-automation upload resume logic.
Re-run Phase 1's helper test and workflow `actionlint` to prove the retained production
path does not depend on a deleted file.

### Completion criteria

The Gate C runner, baseline collector, mock GitHub CLI, runner tests, and resume
protocol are gone, while the production scanner helper and unrelated repository tools
still validate.

## Phase 3: Convert service-common to production dependency automation

### Workspace

../service-common

### Goal

Retain service-common Renovate and resolved Gradle graph submission on `main` while
removing all trial build and graph evidence behavior.

### Scope

`renovate.json`, `.github/workflows/build.yml`,
`.github/workflows/dependency-submission.yml`,
`.github/scripts/prepare-trial-evidence.sh`, `docs/dependency-automation.md`, and the
nearest `AGENTS.md`/README references.

### Non-goals

No BOM/library upgrade, package publication change, module/build redesign, removal of
normal service-common JAR artifacts, GitHub settings, or sibling edits.

### Required context

Read this repository's `AGENTS.md`, README, dependency-automation guide, both workflows,
Gradle project structure, and `renovate.json`. Read the orchestration shared-preset
contract from the accepted target embedded in this plan; do not modify orchestration
from this phase.

### Execution steps

1. Perform the branch/ancestry/worktree checks and preserve unrelated changes.
2. Point `renovate.json` at the normal shared preset without a branch suffix.
3. Restore **Build** to `main` push/PR/manual events and normal Gradle caching. Remove
   the trial-only job expression, evidence log/archive steps, variables, and helper
   call. Preserve service-common's normal test-results and library JAR uploads and its
   `publishToMavenLocal` check.
4. Simplify **Dependency Submission** to trusted `main` pushes, its weekly schedule,
   and manual dispatch. Generate and submit directly with the official Gradle action,
   `cache-provider: basic`, `contents: write`, and `--no-configuration-cache`. Remove
   trial full-build measurement, generation-only/default-branch variable logic,
   cache/upload gates, and artifact upload steps.
5. Delete `.github/scripts/prepare-trial-evidence.sh`; no production workflow in this
   repository needs a scanner evidence archive.
6. Rewrite the repo-local guide as a durable description of shared-preset inheritance,
   full resolved graph coverage, trusted `main` submission, inherited-dependency
   limits, and bot PR review. Remove Phase 12, activation-handoff, trial branch,
   variable, and trial artifact sections. Update `AGENTS.md` language from trial
   controls to stable production workflow ownership, applying the checkstyle.

### Implementation notes

Service-common's JAR artifacts are a library/package validation contract, not the
deployable-service `app-jar` waste corrected elsewhere. Do not remove them under the
cross-repository storage cleanup.

### Validation

Run repository-required Gradle validation from `AGENTS.md`, strict Renovate config
validation, `actionlint` on both workflows, and `git diff --check`. Confirm no active
file outside historical/plan material contains the trial branch, trial variables, or
the deleted helper. Confirm dependency submission still has only `contents: write` at
job scope and the Build workflow still retains its normal service-common artifacts.

### Completion criteria

Service-common has a production preset reference, `main`-only build and graph events,
direct graph submission, no trial helper or evidence path, accurate production docs,
and unchanged package/library behavior.

## Phase 4: Convert currency-service and preserve the storage correction

### Workspace

../currency-service

### Goal

Promote currency-service Renovate and authenticated Gradle graph submission to `main`
without restoring the unused regular-CI application JAR artifact.

### Scope

`renovate.json`, `.github/workflows/build.yml`,
`.github/workflows/dependency-submission.yml`,
`.github/scripts/prepare-trial-evidence.sh`, `docs/dependency-automation.md`, and the
nearest instruction/setup documentation affected by the production behavior.

### Non-goals

No dependency upgrade, service logic, release workflow, secret value, Maven repository
redesign, or sibling edit.

### Required context

Read local `AGENTS.md`, `README.md`, `build.gradle.kts`, both workflows,
`docs/dependency-automation.md`, `docs/local-development.md`, and `renovate.json`.
Identify the retained Maven Central `excludeGroup("org.budgetanalyzer")` correction
before editing.

### Execution steps

1. Perform the standard branch/ancestry/worktree checks.
2. Remove the branch suffix from the shared-preset reference.
3. Make **Build** `main` push/PR/manual only with normal Gradle caching and a normal
   `./gradlew build`. Remove trial logging, branch expressions, variables, helper calls,
   and trial uploads. Keep the build-step outcome ID needed to upload JUnit XML only on
   failure, retain that artifact for one day, and keep `app-jar` absent.
4. Make **Dependency Submission** `main` push/weekly/manual only. Preserve the
   `service-common` package-access preflight and separate package-read credentials from
   `${{ github.token }}`. Configure the official Gradle action to generate-and-submit
   directly with the basic cache and `contents: write`; remove generation-only,
   default-branch, cache, evidence, and upload gates.
5. Delete the trial evidence helper. Preserve the Maven repository correction in
   `build.gradle.kts` and its nearest setup documentation.
6. Reduce the repo-local dependency guide and `AGENTS.md` references to durable
   production behavior: update discovery, authenticated graph submission, no
   regular-CI application artifact, failure-only XML, and bot PR review. Remove all
   Phase 12 and trial handoff material.

### Implementation notes

Do not turn package-read credentials into submission credentials and do not use
`pull_request_target`. The main-path graph must fail on missing package access rather
than silently omitting `service-common`.

### Validation

Run repository-required Gradle checks, strict Renovate config validation, `actionlint`
on both workflows, and `git diff --check`. Statically prove `build.gradle.kts` still
excludes `org.budgetanalyzer` from Maven Central, `build.yml` contains no `app-jar` or
application-JAR upload, failed-test XML retains for one day, and active files contain
no trial ref/variable/helper.

### Completion criteria

Currency-service is production-only on `main`, submits a complete authenticated graph,
keeps the Maven-routing and no-`app-jar` fixes, and has no trial evidence machinery or
stale active instructions.

## Phase 5: Convert permission-service and preserve the storage correction

### Workspace

../permission-service

### Goal

Promote permission-service dependency automation to `main` while preserving package
resolution and failure-only CI artifacts.

### Scope

`renovate.json`, `.github/workflows/build.yml`,
`.github/workflows/dependency-submission.yml`, the trial evidence helper,
`docs/dependency-automation.md`, `AGENTS.md`, and README links.

### Non-goals

No dependency/version change, service authorization logic, package publication,
release change, credential handling, or sibling edit.

### Required context

Read local `AGENTS.md`, README, `build.gradle.kts`, both workflows, the repo-local
dependency guide, and `renovate.json`. Identify the Maven Central exclusion and current
package-secret names before changing workflows.

### Execution steps

1. Perform the standard branch/ancestry/worktree checks.
2. Use the normal shared-preset reference with no branch suffix.
3. Convert **Build** to simple `main` push/PR/manual behavior and normal Gradle cache;
   remove trial logging/evidence/gates while preserving one-day failed-test XML and the
   absence of `app-jar`.
4. Convert **Dependency Submission** to direct generate-and-submit on `main`
   push/weekly/manual events. Preserve the authenticated `service-common` POM preflight,
   package-read secret boundary, basic cache provider, and job-scoped `contents: write`.
5. Delete the trial evidence helper. Preserve the `org.budgetanalyzer` Maven Central
   exclusion and all non-trial README/setup corrections.
6. Rewrite active dependency docs and `AGENTS.md` wording for the production graph,
   build-artifact behavior, and bot review; remove trial/Phase 12 handoffs and variables.

### Implementation notes

Use the same production contract as currency-service, but verify this repository's own
secret names, tasks, and docs rather than copying unexamined text.

### Validation

Run local required Gradle validation, strict Renovate validation, `actionlint`, and
`git diff --check`. Assert the Maven exclusion, failed-test-only artifact, no
`app-jar`, direct graph submission, least privilege, and absence of active trial terms.

### Completion criteria

Permission-service retains the proven Maven and graph behavior on `main`, keeps the
storage correction, and contains no trial helper, variable, event, or active handoff.

## Phase 6: Convert transaction-service and preserve the storage correction

### Workspace

../transaction-service

### Goal

Promote transaction-service dependency automation to `main` without regressing Maven
routing or regular-CI artifact storage.

### Scope

`renovate.json`, `.github/workflows/build.yml`,
`.github/workflows/dependency-submission.yml`, the trial evidence helper,
`docs/dependency-automation.md`, `AGENTS.md`, README, and existing configuration docs
that describe package resolution.

### Non-goals

No service/domain code, dependency update, release, package credential, configuration
semantic change, or sibling edit.

### Required context

Read local `AGENTS.md`, README, `build.gradle.kts`, both workflows,
`docs/dependency-automation.md`, `docs/configuration.md`, and `renovate.json`. Locate the
retained Maven Central exclusion and remote package source wording first.

### Execution steps

1. Perform the standard branch/ancestry/worktree checks.
2. Remove the trial suffix from the shared Renovate preset.
3. Simplify **Build** to `main` push/PR/manual with normal caching and no trial
   logging/archive path. Preserve one-day JUnit XML only on a failed build and keep the
   unused `app-jar` upload removed.
4. Simplify **Dependency Submission** to direct `main` generate-and-submit for push,
   weekly schedule, and dispatch. Preserve package POM preflight, separate package-read
   secrets, basic caching, complete configurations, and job-scoped `contents: write`.
5. Delete the trial evidence helper and retain the Maven routing correction and its
   configuration documentation.
6. Make the dependency guide and instructions production-focused; remove trial branch,
   Phase 12, variable, upload, and activation-handoff text while keeping bot PR review
   requirements.

### Implementation notes

Do not conceal failed internal package resolution with Maven Local, configuration
filters, or a Maven Central fallback.

### Validation

Run repository-required Gradle validation, strict Renovate validation, `actionlint`,
and `git diff --check`. Verify the Maven exclusion, direct graph submission, no
`app-jar`, one-day failed XML, and no active trial/helper references.

### Completion criteria

Transaction-service has the production dependency automation contract on `main`, with
the proven Maven and storage corrections intact and the trial layer removed.

## Phase 7: Convert session-gateway and preserve reactive graph coverage

### Workspace

../session-gateway

### Goal

Promote session-gateway dependency automation to `main`, preserving complete reactive
dependency coverage and the regular-CI storage correction.

### Scope

`renovate.json`, `.github/workflows/build.yml`,
`.github/workflows/dependency-submission.yml`, the trial evidence helper,
`docs/dependency-automation.md`, `docs/local-development.md`, `AGENTS.md`, and README
links.

### Non-goals

No session/auth logic, dependency upgrade, Tomcat expectation, release change,
credential change, or sibling edit.

### Required context

Read local `AGENTS.md`, README, `build.gradle.kts`, both workflows, local development
and dependency-automation docs, and `renovate.json`. Identify the Maven Central
exclusion and the WebFlux/Reactor Netty graph requirements.

### Execution steps

1. Perform the standard branch/ancestry/worktree checks.
2. Change the Renovate preset reference to the normal default-branch form.
3. Convert **Build** to `main` push/PR/manual, normal cache, and normal build output.
   Remove all trial logging/evidence and retain only one-day failed JUnit XML; keep
   `app-jar` absent.
4. Convert **Dependency Submission** to direct `main` graph submission on push,
   weekly schedule, and dispatch. Preserve package access, basic cache, complete
   configurations, the submission token boundary, and job-scoped `contents: write`.
5. Delete the trial evidence helper. Preserve Maven Central exclusion and local package
   resolution documentation.
6. Rewrite active dependency instructions for production operation and reactive graph
   review, retaining Reactor Netty/Netty expectations and removing trial/Phase 12
   handoffs.

### Implementation notes

Do not copy a servlet/Tomcat coverage requirement into this reactive service. Graph
acceptance remains based on the packages the service actually resolves.

### Validation

Run required Gradle checks, strict Renovate validation, `actionlint`, and
`git diff --check`. Verify the Maven exclusion, reactive graph action inputs, direct
submission, no `app-jar`, failure-only XML, and absence of trial references.

### Completion criteria

Session-gateway runs production dependency automation only on `main`, retains reactive
graph and Maven correctness, keeps the artifact fix, and has no trial machinery.

## Phase 8: Convert frontend Renovate and npm audit to production

### Workspace

../budget-analyzer-web

### Goal

Retain frontend Renovate, normal CI, and full/production npm audit evidence on `main`
without trial cache, branch, variable, or dual-upload logic.

### Scope

`renovate.json`, `.github/workflows/build.yml`,
`.github/workflows/dependency-audit.yml`, the evidence archive helper,
`docs/dependency-automation.md`, `docs/README.md`, `AGENTS.md`, and README links.

### Non-goals

No package or lockfile update, `npm audit fix`, UI code, CSP/build-gate change,
dependency PR repair, or sibling edit.

### Required context

Read local `AGENTS.md`, README, docs index, dependency guide, `package.json`, both
workflows, the evidence helper, and `renovate.json`. Apply the local distinction between
vulnerability findings and audit operational failures.

### Execution steps

1. Perform the standard branch/ancestry/worktree checks and ensure neither package file
   is already modified unexpectedly.
2. Use the production shared-preset reference while preserving frontend-specific
   React/Vitest grouping, lockfile maintenance, approval rules, and managers.
3. Restore **Build** to `main` push/PR/manual with one cached Node setup. Remove the
   trial job expression, evidence log/archive, variables, and branch-only upload
   condition. Preserve lint, coverage, CSP smoke, bundle build, and the normal
   seven-day `dist` artifact.
4. Convert **Dependency Audit** to production `main` events. Retain full and
   production-only JSON reports, operational-error classification, non-gating findings,
   schedule/manual execution, and concurrency. Remove trial branch/cache/schedule/upload
   conditions.
5. Generalize the evidence helper to the production name/wording and use it to package
   only `dependency-audit-reports` under the 24 MiB cap. Upload that single gzip artifact
   for seven days with upload compression disabled. No post-upload API measurement is
   introduced.
6. Rewrite active docs/instructions for production update discovery, lockfile policy,
   audit operation, capped report retention, and bot PR checks. Remove trial evidence,
   Phase 12, and activation handoffs while preserving useful manager and audit limits.

### Implementation notes

The known malformed trial PR is not repaired in this phase and no bot dependency diff
is adopted. It is closed manually during post-plan cleanup. Findings with valid npm
audit JSON remain reports; registry, install, malformed JSON, or command-status
inconsistency remains a workflow failure.

### Validation

Run `bash -n` and `shellcheck` on the generalized helper, strict Renovate validation,
`actionlint` on both workflows, and the applicable frontend gates from `AGENTS.md`.
Run both npm audit scopes against the unchanged lockfile and classify findings
separately from operational failure. Run `git diff --check`; verify `package.json` and
`package-lock.json` are unchanged and active files contain no trial ref/variable/helper
name.

### Completion criteria

Frontend CI and audit workflows target `main`, audit evidence has one capped seven-day
path, dependency selections are unchanged, and all trial controls and instructions are
gone.

## Phase 9: Convert ext-authz Renovate and govulncheck to production

### Workspace

../ext-authz

### Goal

Retain ext-authz dependency discovery and reachable Go vulnerability evidence on
`main`, removing trial build/scanner instrumentation.

### Scope

`renovate.json`, `.github/workflows/build.yml`,
`.github/workflows/go-vulnerability-check.yml`, the evidence archive helper,
`scripts/run-govulncheck.sh`, `docs/dependency-automation.md`, `AGENTS.md`, and README.

### Non-goals

No module/toolchain update, `go.mod`/`go.sum` change, service logic, Docker behavior,
release change, or sibling edit.

### Required context

Read local `AGENTS.md`, README, both workflows, `scripts/run-govulncheck.sh`, the
dependency guide, `go.mod`, `go.sum`, and `renovate.json`. Distinguish the durable
scanner wrapper from the disposable trial archive wrapper.

### Execution steps

1. Perform the standard branch/ancestry/worktree checks and record clean module files.
2. Use the production shared-preset reference while preserving Go, Docker, Actions,
   and scanner-version extraction.
3. Restore **Build** to `main` push/PR/manual with normal Go caching, formatting,
   tests, and Docker build. Remove evidence log/archive, trial cache expressions,
   variables, and helper calls.
4. Convert **Go Vulnerability Check** to production `main` push/weekly/manual events
   with normal cache. Preserve the separate analysis toolchain, pinned scanner version,
   readable/machine-readable results, `continue-on-error` evidence capture, and final
   scanner-completion enforcement.
5. Generalize the archive helper and use it for one capped gzip containing
   `govulncheck-results`, retained for seven days with upload compression disabled.
   Remove dual production/trial uploads and every branch/variable condition.
6. Keep `scripts/run-govulncheck.sh`; it is durable scanner behavior and does not call
   GitHub. Rewrite active docs/instructions for production events, reachability limits,
   report retention, and bot review, removing trial/Phase 12 handoffs.

### Implementation notes

Do not confuse removal of GitHub CLI trial automation with removal of the local
`govulncheck` wrapper. The latter is the tested scanner interface and stays.

### Validation

Run `bash -n` and `shellcheck` on changed shell scripts, `actionlint`, strict Renovate
validation, `gofmt -l` checks, `go test ./...`, and the repository's documented
`govulncheck` wrapper where network/tool prerequisites are available. Run
`git diff --check`; confirm `go.mod`/`go.sum` are unchanged and no active trial terms
remain.

### Completion criteria

Ext-authz build and vulnerability workflows are production-only on `main`, retain
reachable-call evidence with one capped artifact, and contain no trial instrumentation
or dependency change.

## Phase 10: Convert workspace Renovate and image scanning to production

### Workspace

../workspace

### Goal

Retain workspace dependency extraction and the no-start image security scan on `main`,
while removing trial PR targeting, variables, dual artifacts, and post-upload GitHub
API measurement.

### Scope

`renovate.json`, `.github/workflows/workspace-image-security-evidence.yml`, the
evidence archive helper/test, `docs/dependency-automation.md`, `AGENTS.md`, and README.

### Non-goals

No Dockerfile/tool/image upgrade, Node baseline change, architecture fix, sandbox
write, container start/push, certificate operation, GitHub setting, or sibling edit.

### Required context

Read local `AGENTS.md`, README, the complete workflow, `renovate.json`, the existing
helper/test, and the current worktree version of `docs/dependency-automation.md`.
Resolve the pre-existing overlapping doc change according to the manual prerequisite.
Identify the `setup-trivy` `git-tags` fallback and digest-only Ubuntu manager before
editing.

### Execution steps

1. Perform the standard branch/ancestry/worktree checks. Stop rather than overwrite an
   unresolved pre-existing documentation edit.
2. Use the normal orchestration shared-preset reference. Preserve every workspace
   custom manager, checksum/architecture guard, digest-only Ubuntu behavior, and the
   public `git-tags` fallback for `aquasecurity/setup-trivy`.
3. Convert **Workspace Image Security Evidence** to `main` push, same-repository PRs
   targeting `main`, weekly schedule, and manual dispatch. Preserve the same-repository
   PR restriction, read-only contents permission, no-start/no-push build, exact Ubuntu
   index checks, no-cache image build, tool inventory, Trivy scan, timeout, and
   concurrency.
4. Remove trial/default-branch event expressions, schedule/cache/upload variables, and
   trial branch tests. Use normal Trivy caching in production.
5. Rename/generalize the archive helper and focused test. Package the complete existing
   `workspace-image-scan` allowlist into one gzip below the 24 MiB payload cap and
   retain it for seven days with upload compression disabled.
6. Remove `actions: read`, `GH_TOKEN`, the artifact-ID `gh api` call, exact retained
   byte comparison, trial artifact/link steps, and dual upload paths. Keep one summary
   link to the production artifact.
7. Rewrite active docs and `AGENTS.md` for the production `main`/same-repository PR
   contract, pre-upload cap, scan limits, and validation commands. Remove references to
   trial variables, trial branches, exact retained-size APIs, Phase 12 handoff, and the
   old helper/test names. Preserve durable ARM64 and floating-package limitations.

### Implementation notes

The helper's compressed-payload cap replaces the API-observed retained-size check; the
docs must describe that distinction accurately. Do not claim that an amd64 workspace
build proves full ARM64 support.

### Validation

Run the renamed helper test, `bash -n` and `shellcheck` on helper/test,
`actionlint` on the workflow, strict Renovate validation, and `git diff --check`.
Confirm the workflow/helper/docs contain no `gh api`, `GH_TOKEN`, trial ref/variable,
or old helper name. Confirm `renovate.json` still contains the setup-trivy fallback and
the Dockerfile/tool declarations are unchanged. The expensive hosted no-cache build
and scan is deliberately deferred to the manual post-plan production cycle.

### Completion criteria

Workspace automation targets production `main`, same-repository PR checks remain
safe, the scan retains one capped short-lived artifact without GitHub API calls, all
custom extraction fixes remain, and the pre-existing doc edit is preserved or
deliberately integrated.

## Phase 11: Replace trial operations documentation with the production contract

### Workspace

.

### Goal

Make orchestration's canonical documentation describe the final production system,
remove superseded trial runbooks/evidence ceremony, and record the original rollout
plan as complete.

### Scope

`docs/OWNERSHIP.md`, `docs/dependency-automation.md`, `AGENTS.md`, `README.md`,
`docs/ci-cd.md`, `scripts/README.md`,
`docs/plans/dependency-automation-plan.md`,
`docs/plans/dependency-automation-phase-12-operator-plan.md`, and
`docs/research/dependency-automation-coverage.md`. This active completion plan is
read-only.

### Non-goals

No edit to `docs/archive/`, `docs/decisions/`, the saved September dependency review,
the active plan source, workflow/config changes already owned by earlier phases,
sibling repository edits, or GitHub operations.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`, `docs/agents-md-checkstyle.md`, the current
canonical dependency guide, `docs/ci-cd.md`, the original rollout plan, the superseded
operator plan, the coverage report, the preserved dependency review, and the completed
Phase 1/2 diffs.

### Execution steps

1. Recheck the workspace and preserve all completed orchestration phases. Update
   `docs/OWNERSHIP.md` first so it continues to name `docs/dependency-automation.md` as
   the canonical operating-policy owner but no longer implies an unfinished trial or
   future promotion plan.
2. Replace the canonical guide's large point-in-time trial status and Gate C/D material
   with a compact durable production guide covering:
   - Renovate ownership, shared preset, no-automerge policy, routine and vulnerability
     limits, approval-gated updates, and ARM64/checksum review;
   - the free Mend boundary, GitHub Actions/storage boundary, and no-paid-expansion
     rule;
   - the normal default-branch preset reference and repository-specific manager
     ownership;
   - the production workflow/event matrix, dependency graph permissions and package
     credentials, four deployable-Java `app-jar` rule, scanner evidence allowlists,
     24 MiB pre-upload cap, and seven-day scanner retention;
   - GitHub/Mend activation settings on `main`, Dependabot alert-only behavior, and
     Maven host-rule scope; and
   - ongoing dashboard review, PR review, scanner/graph failure triage, and support-
     lifecycle review.
3. Remove every active procedure for trial defaults, trial rulesets, trial variables,
   Gate B/C/D/E/F phrases, controlled uploads, exact artifact deletion/resume,
   rollback-to-main, or deferred Phase 12 evidence.
4. Apply the AGENTS checkstyle and replace orchestration `AGENTS.md` trial/Phase 12
   instructions with a stable pointer to the production policy and workflows. Preserve
   the useful action-source admission/checksum rule introduced by the rollout.
5. Update README and `docs/ci-cd.md` summaries to match the final events and artifact
   behavior. Reconcile `scripts/README.md` with Phase 2 deletion while retaining the
   exact-image render helper and generalized production archive-helper ownership where
   it is documented.
6. Replace the original rollout plan's unfinished Phase 12/trial decision material with
   a concise completion record: phases 1-10 implementation and hosted trial checks were
   accepted, remaining evidence gates were waived, and direct promotion is governed by
   this completion plan. Remove instructions that could be mistaken for an active
   rollback or activation procedure.
7. Delete the superseded Phase 12 operator plan and the giant point-in-time coverage
   report after transferring only durable conclusions needed by the canonical guide.
   Retain `docs/research/dependency-update-review-2026-09-06.md` as the historical
   benchmark; do not rewrite or promote its observed versions into targets.
8. Search all active orchestration docs/config/scripts, excluding this immutable plan
   and `docs/archive/`, for deleted filenames and trial-only terms. Resolve every hit or
   explain why it is a durable historical reference; active operational instructions
   receive no exception.

### Implementation notes

The goal is not to preserve the abandoned protocol in a shorter runbook. Durable
policy belongs in the canonical guide; point-in-time trial mechanics and raw evidence
are deleted. Keep the guide discovery-first and avoid a new inventory of transient
run IDs, SHAs, PR numbers, artifact IDs, or billing snapshots.

### Validation

Run `git diff --check` and any repository documentation/link checker already present.
Confirm no active file references the deleted operator plan, coverage report, Gate C
runner, baseline collector, mock GitHub CLI, or their commands. Excluding this active
plan and `docs/archive/`, require zero matches for `dependency-automation-trial`,
`DEPENDENCY_AUTOMATION_TRIAL`, `UPLOAD BATCH GO`, `SAFE TO REQUEST`,
`prepare-trial-evidence`, or the deleted Gate C filenames. Re-run strict Renovate
validation, the generalized helper test, shell validation, and `actionlint` for the two
orchestration workflows so documentation cleanup cannot mask a broken retained path.

### Completion criteria

The canonical docs describe only production dependency automation, the original
rollout is recorded complete, superseded trial operations/evidence documents are gone,
all orchestration validation passes, and the repository is ready for the operator's
orchestration-first merge and hosted production acceptance sequence.
