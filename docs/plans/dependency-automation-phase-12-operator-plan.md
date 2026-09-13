# Dependency Automation Phase 12 Operator Plan

**Status:** Ready for operator preparation; hosted activation evidence is pending.

This plan completes Phase 12 of the broader
[dependency automation plan](dependency-automation-plan.md) outside AI Session
Handler. It is an interactive operator checklist for publishing the prepared
configuration, activating the free hosted services, collecting sanitized
evidence, and completing the benchmark comparison.

The canonical operating policy and activation requirements remain in
[Dependency Automation](../dependency-automation.md). Record results in the
[dependency automation coverage report](../research/dependency-automation-coverage.md).
If this checklist conflicts with either source, follow the canonical guide and
the executable dependency automation plan.

## Objective

Demonstrate that the free dependency automation is active across all ten scoped
repositories, reconcile every deferred authenticated check, and report
installation status separately from benchmark parity.

Phase 12 is complete only after:

- the shared preset and all consumer configurations are on their default branches;
- the free Renovate Community App is active only on the scoped repositories;
- every deferred hosted workflow and authenticated lookup has successful evidence;
- all five Java dependency graphs are complete and accepted by GitHub;
- each repository has two successful Renovate cycles;
- every prepared scanner has one successful scheduled cycle, in addition to any
  initial manual run; and
- the coverage report gives every baseline area and named high-priority advisory
  a final disposition.

This cannot necessarily finish in one sitting. Mend Community scheduling may
take approximately four hours, and the acceptance criteria require observation
of actual scheduled scanner runs.

## Ownership legend

- **HUMAN** owns authenticated account inspection, billing and repository
  settings, App administration, workflow dispatch, credential configuration,
  and every git commit, push, merge, or branch operation. The AI agent may
  prepare local changes, perform public research, and review sanitized evidence
  for these steps, but cannot complete them independently.
- **AI AGENT** owns checkout-based analysis, evidence reconciliation,
  documentation updates, and the final assessment when the required public or
  sanitized evidence has been supplied. The human still publishes resulting
  documentation changes through the normal git workflow.

## Safety and ownership boundaries

- The operator performs all commits, pushes, merges, workflow dispatches, GitHub
  settings changes, App installation, and Mend administration.
- Never provide GitHub, Maven, image-registry, package-registry, or Mend
  credentials to an agent.
- Provide agents only public evidence or sanitized URLs, logs, snapshots, and
  settings confirmations.
- Do not commit tokens or plaintext credentials in host rules. Do not use
  `pull_request_target` to expose trusted credentials to dependency branches.
- Use only Mend Renovate Community and standard GitHub-hosted runners within the
  approved zero-spend boundary. Stop if a required capability needs a paid plan,
  trial, server, or Actions overage.
- Do not merge dependency updates as part of activation.
- Keep Renovate as the sole update-PR owner. Keep automerge disabled, including
  for vulnerability fixes.

## Scoped repositories

1. `orchestration`
2. `service-common`
3. `currency-service`
4. `permission-service`
5. `transaction-service`
6. `session-gateway`
7. `budget-analyzer-web`
8. `ext-authz`
9. `workspace`
10. `budget-analyzer-api-tests`

## Current publication blockers

Resolve these before publishing prepared files:

1. The local orchestration branch `monitor-dependency-notifications` is two
   commits ahead of `origin/main` and has no upstream. Its Phase 12 preparation
   commit includes approximately 349,000 lines of `.ai-session-handler` prompts,
   transcripts, outcomes, and state. Do not publish those execution artifacts.
   Prepare a clean branch or clean replacement commit that retains the actual
   implementation and excludes `.ai-session-handler/**`. Add an appropriate
   ignore rule so later runner output is not staged accidentally.
2. The prepared changes in all nine consumer repositories are uncommitted.
   Review and publish them only after the orchestration shared preset is on the
   orchestration default branch.
3. `budget-analyzer-api-tests` is currently prepared on `initial-import`, while
   the repository's default branch is `main`. Decide and execute the intended
   merge path so the complete repository and dependency-automation files reach
   the default branch. Installing Renovate against the old one-commit `main`
   branch would not activate the prepared coverage.
4. `workspace/ai-agent-sandbox/scripts/codex-lean.sh` has an unrelated local
   modification and trailing whitespace. Keep it out of the dependency-
   automation publication unless it is separately reviewed and intentionally
   included. Stage explicit paths instead of sweeping every workspace change
   into one commit.

After cleanup, preserve a sanitized list of the default-branch revisions used
for activation.

## Step 1: Confirm the zero-spend and credential prerequisites

**Owner: HUMAN.** The AI agent may inventory facts available from the checkouts
or public sources and prepare the evidence table. The human must confirm the
existing GitHub Actions secret names. If repository visibility changes, the
human must also check private-repository Actions billing. No Mend login or App
installation is required in this step.

Complete this before publishing files that trigger hosted workflows.

For every scoped repository:

1. Record whether it is public or private.
2. For every private repository, confirm that included GitHub Actions usage is
   sufficient and paid overages are disabled.
3. Confirm from Mend's public documentation that Renovate Community supports
   the repository type within the free service's published job limits.

The unauthenticated GitHub repository API confirmed at `2026-09-09T08:51:48Z`
that all ten scoped repositories are public and use `main` as their default
branch. While that remains true, the private-repository Actions allowance and
paid-overage check is not applicable; do not add a payment method or enable
billing for this rollout.

For the existing Maven-access prerequisite:

1. Confirm from Mend's public documentation that Community supports hosted
   credentials, GitHub Packages host rules, and Maven lookup. Do not attempt to
   prove account-specific access before App installation; Step 7 owns the actual
   authenticated lookup proof. Mend no longer supports repository-config
   encrypted secrets.
2. Confirm, by name only, that these existing GitHub Actions secrets are present
   in `currency-service`, `permission-service`, `transaction-service`, and
   `session-gateway`:
   `SERVICE_COMMON_PACKAGES_USERNAME` and
   `SERVICE_COMMON_PACKAGES_READ_TOKEN`.
3. Do not reveal, copy, rotate, or test the secret values in an agent environment.

Retain public proof of repository visibility and Mend free-tier support plus
sanitized confirmation of secret-name presence. The public checks above are
already satisfied by the recorded API result and Mend documentation; the human
secret-name confirmation is the only remaining action while all repositories
stay public. Stop and discuss any paid or unsupported requirement.

## Step 2: Clean and publish orchestration first

**Owner: HUMAN.** The AI agent may prepare local file changes, run checks, and
review the proposed diff. The human owns the history cleanup, branch operations,
commit, push, review, and merge.

1. Remove `.ai-session-handler/**` from the unpublished change history that will
   be pushed. Do not publish the runner transcripts merely because the runner
   created them.
2. Retain both intended orchestration changes:
   - the saved review and archived notification document from commit `643ed80`;
   - the dependency automation configuration, workflows, scripts, active docs,
     plan, and coverage report from the later implementation.
3. Review the resulting diff against `origin/main` and verify that it contains
   no credentials or execution transcripts.
4. Re-run the applicable local checks if cleanup changes implementation files.
5. Publish through the repository's normal review path and merge to `main`.
6. Record the merged revision and pull-request or merge URL.
7. Confirm these shared-preset URLs are publicly or appropriately accessible to
   consumers:
   - `renovate-presets/default.json`
   - `renovate.json`
   - `.github/workflows/dependency-automation-config.yml`

Do not publish a consumer `renovate.json` before the shared preset is available
from orchestration's default branch.

## Step 3: Run the orchestration hosted dry run

**Owner: HUMAN.** The human dispatches the authenticated GitHub workflow and
provides its public or sanitized output. The AI agent may analyze that output
and identify blockers.

From the orchestration repository's Actions page:

1. Select **Dependency Automation Configuration**.
2. Choose **Run workflow** on `main`.
3. Enable `run_hosted_dry_run`.
4. Dispatch the workflow.

The workflow must use only GitHub's ephemeral job token, its declared read-only
permissions, and Renovate `--dry-run=full`. Do not export its token.

Retain:

- workflow URL, source revision, start time, duration, and result;
- strict validation output for `renovate.json` and
  `renovate-presets/default.json`;
- proof that `github>budgetanalyzer/orchestration//renovate-presets/default`
  resolves;
- extraction and lookup logs;
- simulated branch/file changes from the full dry run;
- PostgreSQL, Grafana, config-reloader, Kiali, GitHub-release, and Docker lookup
  results; and
- every authentication, timeout, rate-limit, or registry failure.

Stop before App activation if the preset does not resolve, validation fails, or
the run has an unexplained fatal/error result.

## Step 4: Prepare GitHub security settings

**Owner: HUMAN.** These are authenticated repository-administration changes.
The AI agent may review sanitized settings evidence after the changes.

For each scoped repository:

1. Enable the dependency graph.
2. Enable Dependabot alerts.
3. Keep Dependabot version updates disabled; do not add `dependabot.yml`.
4. Disable automatic Dependabot security-update pull requests so they do not
   overlap Renovate's vulnerability-fix proposals.
5. Confirm GitHub Actions has the permissions required by the checked-in
   workflows, particularly dependency submission from trusted default-branch
   code.

Retain sanitized screenshots or exports showing the effective settings. Do not
record cookies, tokens, secret values, or unrelated account information.

## Step 5: Publish the consumer repositories

**Owner: HUMAN.** The AI agent may review each checkout, prepare local file
changes, and run local validation. The human owns all commits, pushes, reviews,
merges, and default-branch decisions.

Review, commit, and publish the prepared files in each consumer repository only
after Step 2 has made the shared preset resolvable.

For the five Java repositories, publish the repository-local `renovate.json`,
dependency-submission workflow, nearest dependency-automation documentation,
and README link:

- `service-common`
- `currency-service`
- `permission-service`
- `transaction-service`
- `session-gateway`

For the remaining repositories, publish their prepared Renovate configuration,
scanner workflow or helper, and nearest documentation:

- `budget-analyzer-web`
- `ext-authz`
- `workspace`
- `budget-analyzer-api-tests`

Use explicit file staging in `workspace` so the unrelated `codex-lean.sh` edit
is not included accidentally. Resolve the `budget-analyzer-api-tests` default-
branch mismatch before treating its configuration as published.

For every repository, retain the merged revision and pull-request or merge URL.
Review any workflow automatically triggered by publication, but rerun it later
if the required dependency-graph or credential configuration was not yet active.

## Step 6: Pilot Renovate on orchestration

**Owner: HUMAN.** App installation, permission grants, and Mend administration
require the human. The AI agent may assess public or sanitized pilot evidence.

1. Open the Mend developer portal and sign in with GitHub OAuth if the App flow
   requires it. This may create a free Mend portal profile; do not create a paid
   subscription, start a trial, or provide a payment method.
2. On GitHub's App installation screen, confirm the repositories are selectable,
   then install the free Mend Renovate Community GitHub App with access
   restricted to `orchestration` first.
3. Grant read access to Dependabot alerts when that permission is available.
4. Run or observe onboarding for orchestration.
5. Inspect the resolved configuration, extraction logs, Dependency Dashboard,
   proposed branches, duration, and all rate-limit or timeout messages.
6. Confirm:
   - the shared preset is applied;
   - `automerge` is false;
   - routine limits and schedules are effective;
   - vulnerability fixes are not constrained by the routine schedule;
   - major, chart, stateful, platform, and checksum-coupled changes require
     dashboard approval;
   - maintained-line patches remain visible alongside later major lines;
   - digest updates preserve immutable digests and flavor suffixes; and
   - first-party production promotion paths are not modified.

Stop before expanding App access if the pilot times out, exceeds the free job
boundary, cannot resolve required dependencies, or applies the wrong policy.

## Step 7: Expand Renovate to the remaining repositories

**Owner: HUMAN.** The human changes App scope and configures encrypted Maven
credentials. The AI agent may review sanitized job, dashboard, extraction, and
lookup evidence without receiving credentials.

After the orchestration pilot passes:

1. Expand the same App installation to only the other nine scoped repositories.
2. Do not grant access to unrelated repositories.
3. Confirm every repository resolves the published preset and creates a
   Dependency Dashboard.
4. Confirm no competing Dependabot update PRs or another update bot are active.
5. First use Mend's App-token GitHub Packages host rules. If separate private
   Maven credentials are required, the human stores them only in Mend App
   settings and references them from `hostRules` using secret placeholders.
6. Verify authenticated Maven lookups for the internal `org.budgetanalyzer`
   coordinates without exposing credentials.

Record each repository's App job URL, revision, duration, extracted dependency
count, lookup failures, dashboard URL, and first proposal URLs.

## Step 8: Submit all five Java dependency graphs

**Owner: HUMAN.** The human dispatches workflows from trusted default branches
and supplies sanitized run and graph evidence. The AI agent may evaluate graph
completeness and document gaps.

Run `.github/workflows/dependency-submission.yml` from trusted default-branch
code in this order:

1. `service-common`
2. `currency-service`
3. `permission-service`
4. `transaction-service`
5. `session-gateway`

For each repository, retain:

- workflow URL and exact source revision;
- successful package-access preflight where applicable;
- a complete application/runtime/test snapshot or equivalent detailed graph
  artifact;
- proof that GitHub accepted the submission; and
- evidence that expected inherited dependencies are represented.

Expected graph review includes Spring Framework, Spring Security, Jackson,
Tomcat, and Netty where applicable. Also verify service-specific trees described
in each repository's `docs/dependency-automation.md`. Tomcat is not expected in
the reactive `session-gateway`; Reactor Netty, Netty, Jackson, Security, and
Lettuce are expected there.

A green ordinary build, package preflight, generator exit code, or partial
87-coordinate snapshot is not sufficient.

## Step 9: Run the prepared scanner workflows manually

**Owner: HUMAN.** The human confirms the Actions cost boundary and dispatches
the workflows. The AI agent may inspect public or sanitized logs and artifacts.

Dispatch these workflows from their trusted default branches for immediate
feedback:

1. `orchestration`: `exact-image-security-evidence.yml`
2. `budget-analyzer-web`: `dependency-audit.yml`
3. `ext-authz`: `go-vulnerability-check.yml`
4. `workspace`: `workspace-image-security-evidence.yml`
5. `budget-analyzer-api-tests`: `python-dependency-audit.yml`

Before dispatching the workspace image scan, reconfirm its potentially larger
no-cache build fits the zero-spend Actions boundary.

For every run, retain the URL, revision, duration, artifact URL, tool/database
versions, completion status, and operational failures. Findings may be
non-blocking, but failed installation, resolution, database download, inventory,
or report generation is an operational failure and cannot be reported as a clean
scan.

## Step 10: Review actual hosted behavior

**Owner: AI AGENT.** The human supplies sanitized evidence for private or
account-only views, including billing confirmation and private package access.
The AI agent reconciles the evidence, identifies failures or gaps, and prepares
coverage-report updates.

For every repository, inspect and retain evidence for:

- resolved Renovate configuration and extraction/lookup logs;
- Dependency Dashboard and representative patch, minor, major, digest, and
  migration proposals where applicable;
- representative bot-PR checks and private package access;
- Dependabot alerts separately from update proposals;
- no automerge and no duplicate update-PR service;
- no paid feature or unintended Actions overage;
- no first-party production artifact promotion by Renovate; and
- no timeout, queue, authentication, registry, or rate-limit failure hidden as a
  successful run.

Check maintained-line and later-release visibility for the named acceptance
areas in the coverage report, including Redis, PostgreSQL, Temurin, Spring,
controllers, frontend transitive packages, and Go dependencies.

## Step 11: Observe the required cycles

**Owner: HUMAN.** The human observes the authenticated GitHub and Mend views
over the required elapsed time and supplies sanitized cycle evidence. The AI
agent may evaluate each supplied cycle and track what remains pending.

1. Record at least two successful Renovate bot cycles for each of the ten
   repositories.
2. Record one actual scheduled run, not merely a manual dispatch, for every
   prepared scheduled scanner workflow.
3. Capture timestamps, revisions, job duration, queueing, and any Mend 30-minute
   timeout or single-concurrency effect.
4. Do not broaden activation or omit dependencies to work around a timeout.

Keep Phase 12 open while any required cycle or scheduled run is pending.

## Step 12: Complete the benchmark comparison

**Owner: AI AGENT.** Using the public and sanitized evidence supplied during the
earlier steps, the AI agent updates the coverage report and assigns only the
evidence-supported classifications below. The human publishes the resulting
documentation change.

Update `docs/research/dependency-automation-coverage.md` using hosted evidence.
For every deferred-check row, record:

- repository;
- command or workflow;
- affected package or configuration;
- source revision and timestamp;
- sanitized URL or artifact;
- observed result; and
- final `passed`, `failed`, or `pending` disposition.

For every saved-review baseline item and named advisory, use exactly one final
classification:

- `reproduced`;
- `superseded by a newer applicable finding`;
- `false positive with evidence`; or
- `missing`.

Evaluate update discovery, advisory detection, and lifecycle assessment
separately. Do not require obsolete target versions or an identical vulnerability
count. Record the user-applied workspace Node 24 change as baseline context, not
as a Renovate discovery.

Prominently retain any unresolved standard-tool limitations, including image
inventories that cannot identify Redis, Temurin, or controller application
versions and the offline Istio gateway `image: auto` limitation.

## Step 13: Close Phase 12

**Owner: AI AGENT.** The AI agent audits the assembled evidence and reports the
installation and benchmark outcomes separately. The human supplies any missing
account-only confirmation and publishes the final documentation change.

Before declaring completion, verify:

1. All ten repositories have active, correctly resolved Renovate configuration.
2. Every deferred hosted check has successful evidence or remains explicitly
   failed; no required evidence remains merely pending.
3. All five Java graphs are complete and accepted.
4. Every scanner has a successful manual run and required scheduled-cycle
   evidence.
5. Every repository has two successful bot cycles.
6. Every baseline row and high-priority advisory has a final disposition.
7. The historical review remains unchanged with SHA-256
   `3c0c4075e021884227d5ecbd0861a9c4f18471e184b8fbbf8cecc1ac8014c347`.
8. The guide and coverage report contain no credentials or sensitive exports.
9. Renovate remains the sole update-PR owner, automerge remains off, and no paid
   feature or unintended production promotion was introduced.

Report two outcomes separately:

- **Installation status:** whether the free automation is demonstrably active
  and operational across all scoped repositories.
- **Benchmark parity:** whether every high-priority saved-review finding was
  reproduced or superseded with evidence.

Installation may be complete while benchmark parity remains partial. Do not
describe a known miss as success merely because the selected standard tools are
working as designed.

## Evidence handoff format

After each operator action, provide only sanitized evidence in this form:

```text
Repository:
Action or workflow:
Source revision:
Started/completed UTC:
Public or sanitized URL:
Result: passed | failed | pending
Relevant extracted packages or findings:
Operational warnings/errors:
Notes or known limitation:
```

Never include secret values, authorization headers, session cookies, workflow
tokens, encrypted payloads, or raw private credential configuration.
