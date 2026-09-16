# Dependency Automation Phase 12 Operator Plan

**Status:** Bounded zero-spend trial in progress. Orchestration and
`service-common` completed their manual rehearsal batches, all seven remaining
repositories passed Batch A and B1, and the four B2 Java consumer graphs are
accepted with complete internal-package coverage. The first graph attempts
exposed trial controls entered as repository secrets instead of variables; the
operator corrected the repository-variable scope and replacement submissions
passed. Before B4, public verification found five automatic security PRs in
`budget-analyzer-web` and one in `ext-authz`. Their bases, labels, and no-automerge
state are correct, but the frontend exceeded the plan's three-PR stop threshold
because Renovate vulnerability alerts ignore the top-level PR limit. B4 has not
started. Resume only after the shared trial preset publishes and validates the
dedicated `vulnerabilityAlerts.prConcurrentLimit: 3` correction. Preserve the
six existing security PRs as the recovery baseline.

This is the human operator checklist for
[Phase 12](dependency-automation-plan.md#phase-12-observe-activation-and-compare-against-the-saved-review).
[Dependency Automation](../dependency-automation.md) owns policy, and the
[coverage report](../research/dependency-automation-coverage.md) owns detailed
evidence. This file deliberately avoids repeating execution transcripts.

## How to use this plan

There are three operator batches and two agent checkpoints:

1. **Batch A:** configure all seven remaining repositories.
2. **Agent checkpoint:** verify Batch A once, across all seven.
3. **Batch B:** add all seven to Mend, run four Java graphs, and request second
   Mend cycles.
4. **Agent checkpoint:** verify Batch B once and provide four exact proposals.
5. **Batch C:** create four representative bot PRs, one at a time.
6. **Agent verification:** review the complete batch and update evidence.

Do not return to the agent after each successful repository. Stop early only for
a failed/red result, a missing prerequisite, a wrong PR base, or an unexpected
PR burst.

## Trial guardrails

- The operator owns GitHub settings, App scope, workflow dispatches, credentials,
  merges, and final decisions. The agent performs public verification and
  documentation.
- Never give the agent tokens, cookies, authorization headers, package
  credentials, or Mend/GitHub session exports.
- Keep all implementation on `dependency-automation-trial`. Do not merge any
  dependency PR or trial branch.
- Keep Mend on **Only select repositories**. The final scope is exactly the nine
  repositories listed in this plan.
- Keep Renovate as the only update-PR owner and automerge disabled. Dependency
  graph and Dependabot alerts are enabled; Dependabot security-update PRs remain
  disabled.
- Keep schedules, repo-owned uploads, and optional caches set to `false` through
  Batches A–C.
- Human-dispatched GitHub workflows run one at a time. Mend may queue multiple
  repositories because Community enforces one concurrent organization job.
- The approved boundary remains no payment method, no paid trial, standard
  public-repository runners, and no new paid service. The current custom evidence
  cap remains 25 MiB with one-day retention; uploads are not yet authorized.
- Keep existing trial PRs open and unmerged:
  [orchestration #56](https://github.com/budgetanalyzer/orchestration/pull/56)
  and
  [`service-common` #57](https://github.com/budgetanalyzer/service-common/pull/57),
  plus the six security PRs listed in the B4 recovery baseline.

## Current repository state

| Repository | `main` SHA | Trial SHA | State |
| --- | --- | --- | --- |
| `orchestration` | `57089578957bae3da42587a7e2902727c5473149` | `75c907f3a89c181aab5de6b71deb0f443b6b9de7` | Manual pilot passed; alert-limit correction pending publication |
| `service-common` | `f31557761b80f17ce8fadc128e273b21b4fd07fe` | `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94` | Manual batch passed |
| `currency-service` | `aa432316849c9231389f8a844325dcf0d64f7335` | `93da3e3599e71cfa453ed78d41691fdfd1edadc3` | B3 complete: 314 packages, 108 alerts |
| `permission-service` | `f2d9d55b149c1f3a00e7f2edd85bafe01a46c5f1` | `a31e7c5880a3d3e742e7224297e8226d9e7a47ff` | B3 complete: 236 packages, 54 alerts |
| `transaction-service` | `ccc459f9ea954296a4d1cea6cdbc4b3acf994e6a` | `aa439d27aec63031ab056d4f4afe70cc43e13cca` | B3 complete: 238 packages, 54 alerts |
| `session-gateway` | `a37c7a0bb832b857d3d7371e521ac82e99fc3b93` | `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5` | B3 complete: 241 packages, 78 alerts |
| `budget-analyzer-web` | `b6f0d23c38428daf8412ae055ccbc9db89ac9517` | `2cbef3f17f546fe167628b221a1cb9dec810c2bd` | B1 green; five-PR security burst retained |
| `ext-authz` | `917eae9c782b4b1c4d576258883c3e558a7d55a1` | `75ed2bda4de7460332a8dea656def0459064753f` | B1 green; one security PR retained |
| `workspace` | `383efc840832d474cd9d60e0368ed2ded828e03c` | `d8e384474512eafb827970db8194413764b79098` | B1 green |

Completed evidence, including the `service-common` failed graph prerequisite,
7,444-byte automatic diagnostic artifact, successful 222-package graph, 89
alerts, and representative PR, is retained in the coverage report. Do not repeat
those runs.

## Batch A: configure all seven remaining repositories

**Owner: HUMAN**

Open these settings pages in separate tabs:

- [currency-service](https://github.com/budgetanalyzer/currency-service/settings)
- [permission-service](https://github.com/budgetanalyzer/permission-service/settings)
- [transaction-service](https://github.com/budgetanalyzer/transaction-service/settings)
- [session-gateway](https://github.com/budgetanalyzer/session-gateway/settings)
- [budget-analyzer-web](https://github.com/budgetanalyzer/budget-analyzer-web/settings)
- [ext-authz](https://github.com/budgetanalyzer/ext-authz/settings)
- [workspace](https://github.com/budgetanalyzer/workspace/settings)

Complete all five steps in each repository before moving to the next.

### A1. Protect both branches

In **Settings → Rules → Rulesets**, create an active branch ruleset named
`dependency-automation-trial-protection`.

Add these as three separate targets:

- **Default branch**
- `main`
- `dependency-automation-trial`

Enable only:

- **Restrict deletions**
- **Block force pushes**
- **Require a pull request before merging**

Do not enter quotes or commas. Do not add required checks or bypass actors.
Before leaving the page, visually confirm that all three targets appear as
separate entries.

### A2. Enable graph and alert settings

In **Settings → Security → Code security and analysis**:

- enable **Dependency graph**;
- enable **Dependabot alerts**; and
- leave **Dependabot security updates** disabled.

Do not enable Dependabot update PRs.

### A3. Set trial variables

In **Settings → Secrets and variables → Actions → Variables**, create or update
these repository variables with the literal value `false`:

- `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED`
- `DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED`
- `DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED`

For the four Java repositories—`currency-service`, `permission-service`,
`transaction-service`, and `session-gateway`—also set:

```text
DEPENDENCY_AUTOMATION_TRIAL_GRAPH_SUBMISSION_ENABLED=true
```

In those four Java repositories, confirm by name only that these repository
secrets exist:

- `SERVICE_COMMON_PACKAGES_USERNAME`
- `SERVICE_COMMON_PACKAGES_READ_TOKEN`

Never open, copy, replace, or report a secret value.

### A4. Change the default branch

Change only the default branch from `main` to
`dependency-automation-trial`. Do this after A1–A3 for that repository.

The public audit found no checked-in Pages, environment, release, deployment,
`workflow_run`, or `pull_request_target` trigger that follows the default. If the
operator personally knows of an out-of-band integration that does, leave only
that repository on `main` and report its name. No per-repository settings
transcript is required.

### A5. Leave Mend unchanged

Do not add any of the seven repositories to Mend during Batch A. Do not dispatch
workflows.

### Batch A handoff

After all seven repositories are processed, send one message:

```text
Batch A complete
Skipped repositories: none | names and reasons
Missing Java secret names: none | repository and missing name
```

## Checkpoint after Batch A

**Owner: AI AGENT**

Verify all seven repositories in one pass:

- default branch and both recorded SHAs;
- exact active rules on both `main` and the trial branch;
- dependency-graph API availability;
- zero unexpected PRs, branches, issues, or workflow runs; and
- explicit trial preset references.

Update the plan and coverage report once. If one repository fails, identify only
the concrete exception; do not restart successful repositories. Batch B starts
only after this checkpoint passes.

**Passed 2026-09-16.** All seven defaults and recorded SHAs, exact ruleset
targets and rules, dependency-graph API access, open-item/activity state, and
trial preset references passed public verification. The only new activity was
two automatic successful GitHub graph updates in `ext-authz`; Batch A dispatched
no repository workflow.

## Batch B: activate and exercise all seven

**Owner: HUMAN**

Complete this batch without returning after each successful repository.

### B1. Expand Mend once

Open the Mend GitHub App installation. Keep **Only select repositories** and add
all seven remaining repositories in one save. Keep `orchestration` and
`service-common` selected. Never choose **All repositories**.

Let the Mend queue drain. One concurrent organization job means queued jobs are
normal. Require one green onboarding job for every added repository. Do not
inspect logs for green jobs. Stop and report only if a repository is red.

Do not select dependency proposals yet.

#### B1 resume marker — 2026-09-16

Batch B repository expansion reached `transaction-service`, whose first
Renovate cycle reported `no-result` for these declarations in
`gradle/libs.versions.toml`:

- `org.budgetanalyzer:spring-platform`
- `org.budgetanalyzer:service-core`
- `org.budgetanalyzer:service-web`

This established that Mend's installation token did not provide the required
GitHub Packages Maven lookup. The package coordinates are not being treated as
missing. The operator reports completing the supported Mend-side correction:

- the saved package-read PAT is stored as a Mend credential; and
- an organization-level Renovate Maven host rule supplies the PAT owner's
  GitHub username and that credential only to
  `https://maven.pkg.github.com/budgetanalyzer/service-common/`.

The secret value and username are intentionally not recorded. A separate build
correction now keeps repository ownership explicit: Maven Local remains first,
the authenticated `service-common` GitHub Packages repository remains second,
and Maven Central excludes `org.budgetanalyzer`. The correction was merged into
each consumer's `main` branch and then forward into its protected trial branch.
The operator reports that the required post-merge `currency-service` Renovate
scan succeeded with no warnings. No raw log or separate per-coordinate result
was supplied; retain this as sanitized operator-reported evidence.

The routing-fix checkpoint and all seven green B1 onboarding results are
complete. No raw green-job logs or credentials are retained. These corrective
runs do not replace the B4 Dashboard cycle.

### B2. Submit the four Java graphs

Run these workflows one at a time. For each, choose branch
`dependency-automation-trial` and wait for completion before starting the next:

1. [currency-service Dependency Submission](https://github.com/budgetanalyzer/currency-service/actions/workflows/dependency-submission.yml)
2. [permission-service Dependency Submission](https://github.com/budgetanalyzer/permission-service/actions/workflows/dependency-submission.yml)
3. [transaction-service Dependency Submission](https://github.com/budgetanalyzer/transaction-service/actions/workflows/dependency-submission.yml)
4. [session-gateway Dependency Submission](https://github.com/budgetanalyzer/session-gateway/actions/workflows/dependency-submission.yml)

Stop before starting the next workflow if one fails. Do not rerun a failure.

**Completed through corrective submissions on 2026-09-16.** The first
`currency-service` run submitted successfully. The first runs in the other
three repositories generated without submitting because the trial control names
had been entered as repository secrets rather than repository variables. A
second [`permission-service` diagnostic run 35085536053](https://github.com/budgetanalyzer/permission-service/actions/runs/35085536053)
remained generation-only and exposed the scope error. After correcting the
repository variables, these accepted runs
passed on the exact trial/default SHAs with repo-owned uploads skipped and zero
artifacts:

- [`currency-service` 35083509407](https://github.com/budgetanalyzer/currency-service/actions/runs/35083509407) — 314 packages
- [`permission-service` 35091521154](https://github.com/budgetanalyzer/permission-service/actions/runs/35091521154) — 236 packages
- [`transaction-service` 35091855229](https://github.com/budgetanalyzer/transaction-service/actions/runs/35091855229) — 238 packages
- [`session-gateway` 35092673426](https://github.com/budgetanalyzer/session-gateway/actions/runs/35092673426) — 241 packages

An extra [`service-common` run 35092182970](https://github.com/budgetanalyzer/service-common/actions/runs/35092182970)
reconfirmed its existing 222-package graph and zero-artifact behavior. It was
not required by B2 and must not be repeated again for this batch.

### B3. Record four alert counts

After all graph runs pass, open these pages and record only the displayed count
or `still processing`. Do not inspect individual alerts.

- [currency-service alerts](https://github.com/budgetanalyzer/currency-service/security/dependabot)
- [permission-service alerts](https://github.com/budgetanalyzer/permission-service/security/dependabot)
- [transaction-service alerts](https://github.com/budgetanalyzer/transaction-service/security/dependabot)
- [session-gateway alerts](https://github.com/budgetanalyzer/session-gateway/security/dependabot)

**Recorded on 2026-09-16:** `currency-service=108`,
`permission-service=54`, `transaction-service=54`, and `session-gateway=78`.

### B4. Request the second Mend cycles

**Paused before execution on 2026-09-16.** Do not select a B4 checkbox until
the shared `dependency-automation-trial` preset publishes and validates
`vulnerabilityAlerts.prConcurrentLimit: 3`. Renovate vulnerability alerts use a
separate PR budget and ignore the top-level concurrent/hourly limits and
schedule by default.

Publish the correction through the protected orchestration workflow:

1. Create a non-dependency correction PR targeting
   `dependency-automation-trial` with the preset and its documentation.
2. Require the PR's **Dependency Automation Configuration** validation to pass.
3. Merge only that correction PR into the trial branch; do not merge a bot PR
   or merge the trial branch into `main`.
4. The trial-branch push will automatically start both **Dependency Automation
   Configuration** and **Exact Image Security Evidence**. Keep cache/upload
   variables `false`, start no B4 work while they run, and require both to pass
   with zero new artifacts.
5. If Mend automatically queues an orchestration scan for the preset change,
   let it drain and require green status without selecting a proposal.
6. Return the correction PR, merge SHA, and workflow URLs for public
   verification before selecting any B4 checkbox.

Preserve this pre-correction security-PR baseline open and unmerged:

- `budget-analyzer-web`: [#116](https://github.com/budgetanalyzer/budget-analyzer-web/pull/116), [#117](https://github.com/budgetanalyzer/budget-analyzer-web/pull/117), [#118](https://github.com/budgetanalyzer/budget-analyzer-web/pull/118), [#119](https://github.com/budgetanalyzer/budget-analyzer-web/pull/119), and [#120](https://github.com/budgetanalyzer/budget-analyzer-web/pull/120)
- `ext-authz`: [#1](https://github.com/budgetanalyzer/ext-authz/pull/1)

The nested limit does not close existing PRs. After publication, the frontend
must open no additional vulnerability PR while its five existing PRs exceed the
new cap. `ext-authz` may open at most two additional vulnerability PRs, and a
repository with no baseline security PR may open at most three. Stop on any PR
with the wrong base or automerge enabled.

After that prerequisite passes, open each of the seven Dependency Dashboard
issues:

- [`currency-service` #84](https://github.com/budgetanalyzer/currency-service/issues/84)
- [`permission-service` #20](https://github.com/budgetanalyzer/permission-service/issues/20)
- [`transaction-service` #84](https://github.com/budgetanalyzer/transaction-service/issues/84)
- [`session-gateway` #25](https://github.com/budgetanalyzer/session-gateway/issues/25)
- [`budget-analyzer-web` #121](https://github.com/budgetanalyzer/budget-analyzer-web/issues/121)
- [`ext-authz` #2](https://github.com/budgetanalyzer/ext-authz/issues/2)
- [`workspace` #8](https://github.com/budgetanalyzer/workspace/issues/8)

At the bottom, select only:

**Check this box to trigger a request for Renovate to run again on this
repository**

It is acceptable to queue all seven requests; Mend runs one at a time. Do not
cancel pending jobs. Wait until all seven finish green. Do not select any
dependency-update checkbox.

Security-labeled PRs may legitimately appear after graph refresh. Record them
but do not merge them. Apply the baseline-aware limits above. Stop for any PR
beyond the nested three-PR vulnerability budget, any PR targeting a branch
other than `dependency-automation-trial`, or any PR showing automerge enabled.

### Batch B handoff

Send one message after the queue drains:

```text
Batch B complete
Onboarding red repositories: none | names
Graph failures: none | repository and run URL
Alert counts: currency= ; permission= ; transaction= ; session-gateway=
Second-cycle red repositories: none | names
Unexpected PRs: none | repository and PR URL
```

## Checkpoint after Batch B

**Owner: AI AGENT**

Verify the whole batch in one pass:

- seven Dependency Dashboards and proposal controls;
- correct trial preset and default/base branches;
- four graph run URLs, exact SHAs, successful submission annotations, accepted
  SBOM package counts, and artifacts;
- internal `service-common` coordinates in all four Java graphs;
- Spring/Security/Jackson/Tomcat dependencies where applicable;
- Reactor Netty/Netty/Lettuce rather than Tomcat for `session-gateway`;
- all new PRs, branches, and Actions activity; and
- two operator-reported green Mend cycles per repository.

Try Mend's App-token Maven lookup first. If a dashboard lacks an internal
package lookup, request one narrowly scoped Mend `hostRules` correction using a
secret placeholder. Never request the credential value.

After verification, provide the operator four exact routine proposal labels for
Batch C. The operator does not choose proposals unaided.

## Batch C: four representative bot PRs

**Owner: HUMAN**, using the exact proposals supplied after Batch B.

The four representatives are selected from:

- `currency-service` — Java bot PR plus internal Maven package access;
- `budget-analyzer-web` — npm build/audit path;
- `ext-authz` — Go build/vulnerability path; and
- `workspace` — image evidence path.

Orchestration and `service-common` already have passing representative PRs. The
initial hosted builds plus Batch B graphs cover package resolution in
`permission-service`, `transaction-service`, and `session-gateway`.

For each supplied proposal:

1. Select only that one Dashboard checkbox.
2. Wait for its PR and required workflow to finish before selecting the next.
3. Stop on a failed check, wrong base, automerge, or additional unexpected PR.
4. Leave every PR open and unmerged.

After all four checks complete, send `Batch C complete`. The agent verifies and
records the four PR bases, diffs, labels, no-automerge state, workflow results,
cache behavior, and artifacts in one pass.

## Later cost and schedule batch

This section is not authorized by Batches A–C.

Keep these variables `false` in all repositories:

- `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED`
- `DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED`
- `DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED`

Manual dispatch is not cron evidence. After Batch C, the agent must reconcile
measured output/artifact sizes, the 7,444-byte automatic failure artifact,
refreshed Actions billing/storage, cache use, and the no-payment-method boundary.
The agent then writes one separate operator checklist for capped uploads and
scheduled evidence. The operator must explicitly approve that batch before any
schedule, upload, cache, or allowance increase is enabled.

## Stop and rollback

Use this after success, a failure, or an early stop:

1. Pause/remove trial Mend access first.
2. Cancel queued/running trial jobs.
3. Set schedule, upload, cache, and graph-submission trial variables to `false`.
4. Record artifact IDs and expiry before deleting only operator-selected trial
   artifacts. Deletion stops future storage accrual but does not erase accrued
   usage.
5. Close trial PRs only after evidence is recorded. Do not merge them.
6. Restore original defaults to `main` and verify the recorded `main` SHAs.
7. Keep both branch protections until rollback verification completes.
8. Record residual dashboards, alerts, artifacts, caches, and PR history;
   restoring a default does not erase repository-wide state.

Do not improvise a service-code workaround, weaken a security control, add a
payment method, buy capacity, or expose credentials to recover a failed trial.

## Final decision and promotion

Passing Batches A–C is trial evidence, not merge approval or ongoing-installation
approval. Report these separately:

- trial acceptance;
- ongoing installation; and
- historical benchmark parity.

Promotion requires a separate explicit operator decision after reviewing costs,
failures, schedules, alerts, package access, and the final diff. Restore the
original defaults before the merge decision. If approved, merge the orchestration
shared preset first and consumers afterward using the normal preset reference.
Do not include bot dependency updates in the promotion change.

`NO-GO` or `DEFER` leaves implementation on recoverable trial branches with App
access and execution gates paused.
