# Dependency Automation Phase 12 Completion Plan

Finish the bounded dependency-automation rehearsal after Batch C with the
agent doing all public inspection, reconciliation, calculations, documentation,
and decision preparation. Human work is limited to authenticated GitHub and Mend
controls that cannot be delegated: confirming account-level billing state,
changing repository variables, dispatching or rerunning workflows, waiting for
real cron events, pausing the App, restoring defaults, closing bot pull requests,
and making the final decision. No credential, cookie, token, secret value, or
private log is ever supplied to an agent.

The canonical policy is [Dependency Automation](../dependency-automation.md),
the current evidence ledger is the
[coverage report](../research/dependency-automation-coverage.md), and the
completed A-C procedure is the
[Phase 12 operator plan](dependency-automation-phase-12-operator-plan.md).
This plan owns the remaining path to a trial decision. An explicit `GO` will
cause the agent to write a separate promotion plan because promotion requires
repo-local work and fresh authorization; it is not pre-authorized here.

## Execution protocol and safety boundary

- Run exactly one phase at a time. Use `--max-phases 1`; do not run this plan
  unattended across a human checkpoint.
- Start the next phase only after completing the intervening operator checkpoint
  and sending the requested sanitized handoff.
- The agent performs every unauthenticated/public GitHub inspection, reads local
  sibling repositories, calculates storage projections, reviews evidence, and
  updates orchestration documentation. The agent never asks the operator to
  transcribe information that public APIs or public run pages expose.
- The operator performs authenticated GitHub/Mend UI changes and workflow
  dispatches. Do not provide screenshots containing private repository names,
  billing identifiers, credentials, tokens, cookies, authorization headers, or
  secret values. Sanitized text and public run URLs are sufficient.
- Keep every scoped repository on `dependency-automation-trial` as its temporary
  default until the rollback checkpoint. Keep all current bot PRs open and
  unmerged until instructed otherwise.
- Until an approved checkpoint says otherwise, keep
  `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED`,
  `DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED`, and
  `DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED` set to `false` everywhere.
  Keep the Java graph-submission variable at its already accepted value until
  rollback.
- Never add a payment method, accept a paid trial, buy capacity, weaken a cap,
  expose a secret, merge a dependency update, or count a manual dispatch as cron
  evidence.
- Stop immediately on a wrong ref/base, a failed workflow, an archive over the
  24 MiB payload limit, a missing expected artifact, an unexpected cache or PR,
  automerge, a payment prompt, or evidence that spending is possible.

## Completion states

This plan distinguishes three outcomes:

1. **Trial assessment ready:** controlled uploads, scheduled evidence, cost
   reconciliation, benchmark dispositions, and rollback are complete.
2. **Decision recorded:** the operator chooses `GO`, `NO-GO`, or `DEFER`.
3. **Ongoing installation complete:** possible only after `GO`, execution of a
   separately reviewed promotion plan, and fresh final hosted evidence. A
   `NO-GO` or `DEFER` completes this decision plan but intentionally leaves
   ongoing installation unclaimed.

## Operator checkpoint A: authenticated cost confirmation

Perform this only after Phase 1 supplies its refreshed public baseline. These
steps are read-only. Do not change a budget, payment method, plan, retention,
cache, variable, or App setting.

1. Open the organization
   [Billing and licensing usage page](https://github.com/organizations/budgetanalyzer/settings/billing/usage).
   If GitHub redirects, use **Organization settings → Billing and licensing →
   Usage**. Set the current billing cycle if the UI offers a date selector.
2. Record only these sanitized values:
   organization plan name; current Actions billed amount; Actions included and
   used minutes if displayed; current artifact/storage usage; current Packages
   storage usage; and whether any quota or usage warning is visible. Do not copy
   billing IDs or private repository names.
3. Open
   [Payment information](https://github.com/organizations/budgetanalyzer/settings/billing/payment_information).
   Confirm whether a payment method exists. Do not add or edit one. If a payment
   method exists, stop and report only `payment method present`; do not continue
   until an effective spend-stopping control is identified.
4. Open
   [Budgets and alerts](https://github.com/organizations/budgetanalyzer/settings/billing/budgets).
   Record whether Actions and Packages have an effective hard stop. A
   notification-only budget is not a hard stop. Do not create or edit a budget.
5. Open the Mend Developer Portal at
   [developer.mend.io](https://developer.mend.io/). Record only whether the
   organization remains on Community/free service, whether any paid trial or
   payment method is present, and whether the active organization job count is
   zero. Do not copy credentials, host-rule values, private logs, or account IDs.
6. Open the organization
   [Installed GitHub Apps page](https://github.com/organizations/budgetanalyzer/settings/installations),
   select the Mend Renovate installation, and confirm **Only select
   repositories** still names exactly the nine scoped repositories. Do not save
   or change the installation.
7. Send this exact handoff, replacing every value:

```text
Checkpoint A complete
Observed UTC: YYYY-MM-DDTHH:MM:SSZ
GitHub organization plan: VALUE
Actions billed amount this cycle: VALUE
Actions included/used minutes: VALUE | not displayed
Artifact/storage usage: VALUE | not displayed
Packages storage usage: VALUE | not displayed
Quota or usage warning: none | sanitized description
GitHub payment method: absent | present
Actions hard spend stop: no-payment-method block | other control | none
Packages hard spend stop: no-payment-method block | other control | none
Mend tier: Community/free | other
Mend paid trial or payment method: absent | present
Mend active organization jobs: 0 | VALUE
Mend repository scope: exact nine | mismatch: sanitized description
Unexpected condition: none | sanitized description
```

## Operator checkpoint B: controlled one-at-a-time uploads

Do not perform this checkpoint until Phase 2 records a safe cost projection and
the operator explicitly replies `UPLOAD BATCH GO`. Phase 2 will publish the
smallest sufficient ordered run matrix; do not infer that every candidate below
must run.

For each approved row, complete the full sequence before touching the next row:

1. Open that repository's **Actions variables** link from the repository table
   below.
2. Select `DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED`, choose **Edit**, set the
   literal value `true`, and save.
3. Confirm `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED=false` and
   `DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED=false`. In Java repositories,
   leave `DEPENDENCY_AUTOMATION_TRIAL_GRAPH_SUBMISSION_ENABLED=true`.
4. Open the exact approved workflow link. Choose **Run workflow**, select
   `dependency-automation-trial`, preserve the approved inputs, and run it. If
   Phase 2 identifies an existing bot-PR run instead, open that public run and
   use **Re-run jobs → Re-run all jobs**; do not push, synchronize, or merge the
   PR merely to trigger a run.
5. Wait for the run to finish. Do not start another repository while it is
   queued or running.
6. Return immediately to **Actions variables**, set
   `DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED=false`, and save—even if the run
   failed.
7. Send only the public run URL and final conclusion. The agent obtains public
   artifact IDs, API `size_in_bytes`, expiry, source SHA, duration, and job data.
   If an artifact or report is not public, provide a sanitized text summary of
   the finding counts and tool/database versions, not the artifact contents.
8. Stop the batch on any safety condition from this plan. Do not delete an
   artifact; one-day retention supplies automatic cleanup.

Candidate workflows, subject to Phase 2 minimization:

| Repository | Workflow |
| --- | --- |
| `orchestration` | [Dependency Automation Configuration](https://github.com/budgetanalyzer/orchestration/actions/workflows/dependency-automation-config.yml) and [Exact Image Security Evidence](https://github.com/budgetanalyzer/orchestration/actions/workflows/exact-image-security-evidence.yml) |
| `service-common` | [Build](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml) and [Dependency Submission](https://github.com/budgetanalyzer/service-common/actions/workflows/dependency-submission.yml) |
| `currency-service` | [Build](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml) and [Dependency Submission](https://github.com/budgetanalyzer/currency-service/actions/workflows/dependency-submission.yml) |
| `permission-service` | [Build](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml) and [Dependency Submission](https://github.com/budgetanalyzer/permission-service/actions/workflows/dependency-submission.yml) |
| `transaction-service` | [Build](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml) and [Dependency Submission](https://github.com/budgetanalyzer/transaction-service/actions/workflows/dependency-submission.yml) |
| `session-gateway` | [Build](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml) and [Dependency Submission](https://github.com/budgetanalyzer/session-gateway/actions/workflows/dependency-submission.yml) |
| `budget-analyzer-web` | [Build](https://github.com/budgetanalyzer/budget-analyzer-web/actions/workflows/build.yml) and [Dependency Audit](https://github.com/budgetanalyzer/budget-analyzer-web/actions/workflows/dependency-audit.yml) |
| `ext-authz` | [Build](https://github.com/budgetanalyzer/ext-authz/actions/workflows/build.yml) and [Go Vulnerability Check](https://github.com/budgetanalyzer/ext-authz/actions/workflows/go-vulnerability-check.yml) |
| `workspace` | [Workspace Image Security Evidence](https://github.com/budgetanalyzer/workspace/actions/workflows/workspace-image-security-evidence.yml) |

Repository Actions-variable pages:

| Repository | Variables |
| --- | --- |
| `orchestration` | [Actions variables](https://github.com/budgetanalyzer/orchestration/settings/variables/actions) |
| `service-common` | [Actions variables](https://github.com/budgetanalyzer/service-common/settings/variables/actions) |
| `currency-service` | [Actions variables](https://github.com/budgetanalyzer/currency-service/settings/variables/actions) |
| `permission-service` | [Actions variables](https://github.com/budgetanalyzer/permission-service/settings/variables/actions) |
| `transaction-service` | [Actions variables](https://github.com/budgetanalyzer/transaction-service/settings/variables/actions) |
| `session-gateway` | [Actions variables](https://github.com/budgetanalyzer/session-gateway/settings/variables/actions) |
| `budget-analyzer-web` | [Actions variables](https://github.com/budgetanalyzer/budget-analyzer-web/settings/variables/actions) |
| `ext-authz` | [Actions variables](https://github.com/budgetanalyzer/ext-authz/settings/variables/actions) |
| `workspace` | [Actions variables](https://github.com/budgetanalyzer/workspace/settings/variables/actions) |

After the last approved run, send:

```text
Checkpoint B complete
Run URLs, in order:
- PUBLIC_URL
All upload variables restored to false: yes
Unexpected condition: none | sanitized description
```

## Operator checkpoint C: real scheduled events

Do not perform this checkpoint until Phase 3 accepts the controlled uploads and
the operator explicitly replies `SCHEDULE BATCH GO`. Uploads and optional caches
remain disabled during scheduled acceptance.

1. For each repository in the schedule table, open its **Actions variables**
   link, edit `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED` to `true`, and save.
   Confirm upload/cache variables remain `false`. Confirm the Java graph variable
   remains `true` in the five Java repositories.
2. Enable the variables before the listed UTC window. GitHub cron can be delayed;
   the listed time is the earliest expected start, not a deadline.
3. Wait for an Actions run whose event is explicitly `schedule`. A manual
   dispatch, rerun, push, dynamic graph update, or Mend cycle does not count.
4. After that repository's scheduled run finishes, immediately restore its
   schedule variable to `false`.
5. Send the public run URL. The agent verifies event, source/default ref, SHA,
   result, duration, packages or findings, artifacts, and cache behavior.
6. Stop on a failed/skipped workflow, wrong ref, unexpected artifact/cache, or
   missing package/scanner evidence. Do not substitute a manual run.

| UTC cron | Repository | Scheduled workflow |
| --- | --- | --- |
| Saturday 04:23 | `orchestration` | [Exact Image Security Evidence](https://github.com/budgetanalyzer/orchestration/actions/workflows/exact-image-security-evidence.yml) |
| Saturday 04:41 | `workspace` | [Workspace Image Security Evidence](https://github.com/budgetanalyzer/workspace/actions/workflows/workspace-image-security-evidence.yml) |
| Monday 05:17 | `ext-authz` | [Go Vulnerability Check](https://github.com/budgetanalyzer/ext-authz/actions/workflows/go-vulnerability-check.yml) |
| Monday 05:23 | `service-common` | [Dependency Submission](https://github.com/budgetanalyzer/service-common/actions/workflows/dependency-submission.yml) |
| Monday 05:31 | `currency-service` | [Dependency Submission](https://github.com/budgetanalyzer/currency-service/actions/workflows/dependency-submission.yml) |
| Monday 05:37 | `permission-service` | [Dependency Submission](https://github.com/budgetanalyzer/permission-service/actions/workflows/dependency-submission.yml) |
| Monday 05:43 | `transaction-service` | [Dependency Submission](https://github.com/budgetanalyzer/transaction-service/actions/workflows/dependency-submission.yml) |
| Monday 05:43 | `session-gateway` | [Dependency Submission](https://github.com/budgetanalyzer/session-gateway/actions/workflows/dependency-submission.yml) |
| Monday 06:17 | `budget-analyzer-web` | [Dependency Audit](https://github.com/budgetanalyzer/budget-analyzer-web/actions/workflows/dependency-audit.yml) |

The two 05:43 Java jobs may overlap because the checked-in schedules coincide.
That is cron behavior, not a human-dispatch serialization violation; record the
actual overlap and queueing for the cost model.

Send:

```text
Checkpoint C complete
Scheduled run URLs:
- orchestration: PUBLIC_URL
- workspace: PUBLIC_URL
- ext-authz: PUBLIC_URL
- service-common: PUBLIC_URL
- currency-service: PUBLIC_URL
- permission-service: PUBLIC_URL
- transaction-service: PUBLIC_URL
- session-gateway: PUBLIC_URL
- budget-analyzer-web: PUBLIC_URL
All schedule variables restored to false: yes
All upload/cache variables remained false: yes
Unexpected condition: none | sanitized description
```

## Operator checkpoint D: pause and restore before the decision

Perform this only after Phase 5 says the evidence ledger is complete enough for
rollback. This checkpoint intentionally pauses the trial before the merge
decision.

1. Open [developer.mend.io](https://developer.mend.io/), select the
   `budgetanalyzer` organization, and open its repository/installation settings.
   If the portal offers an explicit reversible **Pause**, **Disable**, or
   equivalent control for all Renovate jobs, use it and verify the active job
   count reaches zero. If it does not, open the organization
   [Installed GitHub Apps page](https://github.com/organizations/budgetanalyzer/settings/installations),
   choose **Configure** for Mend Renovate, scroll to **Danger zone**, and choose
   **Uninstall** to remove trial access. The rollback procedure explicitly
   authorizes pausing or removing access; do not alter credentials or install a
   replacement App. If neither UI offers a clear pause/removal control, stop and
   report the visible option labels without selecting one.
2. Open each repository's **Actions** page and cancel only queued/running trial
   work. Do not cancel unrelated workflows.
3. On every repository's Actions-variable page, set schedule, upload, and cache
   variables to `false`. On the five Java repositories, also set
   `DEPENDENCY_AUTOMATION_TRIAL_GRAPH_SUBMISSION_ENABLED=false`.
4. Do not delete artifacts. The agent records IDs, sizes, and expiries; the
   one-day trial artifacts may expire naturally. The existing automatic
   7,444-byte diagnostic artifact remains historical evidence.
5. Close, but do not merge, the trial bot PRs below. Add the comment
   `Closing after Phase 12 trial evidence capture; no dependency update was merged.`
   Do not delete bot branches manually.
   - [orchestration #56](https://github.com/budgetanalyzer/orchestration/pull/56)
   - [service-common #57](https://github.com/budgetanalyzer/service-common/pull/57)
   - [currency-service #87](https://github.com/budgetanalyzer/currency-service/pull/87)
   - [budget-analyzer-web #116](https://github.com/budgetanalyzer/budget-analyzer-web/pull/116),
     [#117](https://github.com/budgetanalyzer/budget-analyzer-web/pull/117),
     [#118](https://github.com/budgetanalyzer/budget-analyzer-web/pull/118),
     [#119](https://github.com/budgetanalyzer/budget-analyzer-web/pull/119),
     [#120](https://github.com/budgetanalyzer/budget-analyzer-web/pull/120), and
     [#122](https://github.com/budgetanalyzer/budget-analyzer-web/pull/122)
   - [ext-authz #1](https://github.com/budgetanalyzer/ext-authz/pull/1) and
     [#3](https://github.com/budgetanalyzer/ext-authz/pull/3)
   - [workspace #11](https://github.com/budgetanalyzer/workspace/pull/11)
6. Restore the default branch in every repository. Open **Settings → General →
   Default branch**, choose the switch/edit control, select `main`, acknowledge
   the warning, and confirm. Do not rename or delete either branch.
   - [orchestration settings](https://github.com/budgetanalyzer/orchestration/settings)
   - [service-common settings](https://github.com/budgetanalyzer/service-common/settings)
   - [currency-service settings](https://github.com/budgetanalyzer/currency-service/settings)
   - [permission-service settings](https://github.com/budgetanalyzer/permission-service/settings)
   - [transaction-service settings](https://github.com/budgetanalyzer/transaction-service/settings)
   - [session-gateway settings](https://github.com/budgetanalyzer/session-gateway/settings)
   - [budget-analyzer-web settings](https://github.com/budgetanalyzer/budget-analyzer-web/settings)
   - [ext-authz settings](https://github.com/budgetanalyzer/ext-authz/settings)
   - [workspace settings](https://github.com/budgetanalyzer/workspace/settings)
7. Leave `dependency-automation-trial-protection` active with both `main` and
   `dependency-automation-trial` targets until Phase 6 verifies rollback.
8. Send:

```text
Checkpoint D complete
Mend App: paused | removed | could not pause/remove: sanitized visible options
Queued/running trial jobs after cleanup: 0 | VALUE
All schedule/upload/cache variables false: yes
All five Java graph-submission variables false: yes
Trial bot PRs closed and unmerged: yes | exceptions
Defaults restored to main: all nine | exceptions
Branches or artifacts manually deleted: none
Unexpected condition: none | sanitized description
```

## Operator checkpoint E: final decision

After Phase 6 publishes the evidence-backed decision package, reply with exactly
one of the following and an optional short rationale:

```text
PHASE 12 DECISION: GO
```

```text
PHASE 12 DECISION: NO-GO
```

```text
PHASE 12 DECISION: DEFER
```

`GO` authorizes Phase 7 to write a separate promotion plan; it does not authorize
merges, App resumption, settings changes, or promotion by itself. `NO-GO` and
`DEFER` leave trial branches protected and recoverable, with App access paused
or removed and all execution gates off.

## Phase 1: Refresh the public baseline and repair the evidence ledger

### Workspace

.

### Goal

Establish a current, source-ref-aware post-Batch-C baseline using public data and
turn every remaining evidence claim into an explicit passed, pending, superseded,
or stale-ledger item before asking the operator for authenticated information.

### Scope

Read all nine local repositories and their instructions, inspect public GitHub
repository metadata, refs, defaults, rulesets where public, open PRs/issues,
workflow runs, artifacts, caches where public, accepted dependency graphs, and
current plan/coverage claims. Update only orchestration documentation.

### Non-goals

No authenticated access, UI changes, dispatches, variable changes, App changes,
PR changes, branch changes, sibling writes, benchmark conclusions, promotion, or
rollback.

### Required context

Read `AGENTS.md`, `docs/dependency-automation.md`,
`docs/plans/dependency-automation-plan.md`,
`docs/plans/dependency-automation-phase-12-operator-plan.md`, this plan, and
`docs/research/dependency-automation-coverage.md`. Read each sibling `AGENTS.md`
before inspecting that sibling. Ignore archived documents.

### Execution steps

1. Record the dirty-worktree baseline in orchestration and every sibling; never
   overwrite unrelated or user-owned changes.
2. Discover current public defaults and main/trial SHAs for all nine repositories
   and compare them with the recorded table. Verify current bot PRs, bases,
   authors, labels, merge/automerge state, and workflow conclusions.
3. Enumerate the exact trial upload producers, archive allowlists, measured-size
   summary fields, 24 MiB enforcement, retention, cache gates, scheduled
   workflows, cron values, and event/ref guards directly from checked-in files.
4. Use public GitHub APIs/pages to inventory current artifacts and cache entries,
   including artifact `10383564434`, without asking the operator for public data.
   Preserve rate-limit or visibility gaps honestly.
5. Reconcile the coverage rows for `permission-service`,
   `transaction-service`, and `session-gateway` bot-PR evidence with Batch C's
   explicitly approved representative sampling. Do not create extra bot PRs
   merely because stale rows still say “no hosted evidence.” If a repository has
   a genuinely distinct untested package/build path, retain a concrete gap;
   otherwise update the row to explain the accepted evidence chain.
6. Update the canonical policy summary first if the current public state changes
   an operating fact, then update the coverage report and the completed operator
   plan summary/cross-links. Do not rewrite historical transcripts.
7. Produce a compact Checkpoint A handoff naming only authenticated values that
   remain unavailable after public inspection.

### Implementation notes

Prefer `rg`, targeted reads, `curl`/public GitHub endpoints, and existing public
links. Do not use agent/subagent exploration. Public API rate limiting is an
evidence gap, not permission to request a token. Treat the six-repository
representative-PR design in Batch C as intentional unless a unique workflow path
is actually unproved.

### Validation

Check every changed Markdown link and verify that all nine repositories, five
Java graphs, four scheduled scanners, known bot PRs, upload producers, and
remaining gaps appear exactly once in the appropriate ledger. Run any existing
documentation/link validation that is targeted and credential-free. Review the
diff for accidental changes to user-owned work.

### Completion criteria

The public baseline is current, stale evidence rows are corrected, all remaining
authenticated unknowns are explicit, no protected state changed, and the
operator can perform Checkpoint A without researching what the agent could have
discovered itself.

## Phase 2: Reconcile cost and publish the minimal upload matrix

### Workspace

.

### Goal

Combine Checkpoint A with measured runner summaries and public artifact evidence,
calculate bounded trial and seven-day operating projections, and publish the
smallest sufficient controlled-upload sequence.

### Scope

Cost/storage/cache accounting, output-size reconciliation, controlled-upload
selection, stop thresholds, and updates to canonical dependency-automation
documentation and the coverage ledger.

### Non-goals

No variable changes, dispatches, uploads, schedules, App/settings changes,
artifact deletion, dependency PRs, promotion, or assumption that missing account
evidence equals zero.

### Required context

Read Phase 1's resulting diff and evidence, the operator's complete Checkpoint A
handoff, the cost boundary in `docs/dependency-automation.md`, the cross-repo
administrator gates and repository deferred checks in the coverage report, and
the workflow/helper files identified by Phase 1.

### Execution steps

1. Validate the Checkpoint A handoff against the zero-spend boundary. Stop with a
   concrete blocker if a payment method or paid Mend state exists without an
   effective hard stop, the Mend scope is not exactly nine, or account evidence
   is internally inconsistent.
2. Extract every available compressed-byte measurement from public run summaries
   or operator-supplied sanitized summary text. Keep uncompressed, compressed,
   wrapper/API, and retained sizes distinct. Include the 7,444-byte automatic
   diagnostic artifact and existing ordinary main-path artifacts/caches.
3. Calculate one-day trial GiB-hours and projected weekly seven-day GiB-hours as
   `sum(bytes / 2^30 * retained_hours)`. Include expected PR frequency, one
   retry, overlapping scheduled runs, existing non-trial use, and unknown private
   headroom as an explicit uncertainty rather than zero.
4. Decide the smallest upload set that proves API size, detailed scanner/audit
   evidence, Java graph evidence, representative build outputs, success paths,
   and the already observed failure path. Reuse one artifact when it proves
   multiple requirements; do not run all candidates mechanically.
5. Order the selected rows one at a time, beginning with the smallest expected
   complete archive. State exact workflow inputs or existing PR run to rerun,
   expected artifact name, source ref, and stop condition for each.
6. Record whether caches stay disabled. Do not enable a cache solely to complete
   the trial; if ongoing operation does not require it, account for zero optional
   trial cache use and leave it off.
7. Update policy first if the approved cost envelope changes, then the coverage
   report and operator-plan cross-link. Publish an explicit recommendation:
   `SAFE TO REQUEST UPLOAD BATCH GO` or `DO NOT AUTHORIZE UPLOADS`, with reasons.

### Implementation notes

The absence of a payment method limits financial exposure but does not prove
upload capacity. A quota rejection is a failed trial result, not a reason to add
billing information. One-day trial retention must not be used as the production
projection. The selected matrix must remain useful even if GitHub's UI does not
expose private per-artifact inventory.

### Validation

Independently recalculate all byte/GiB-hour arithmetic, verify every selected
workflow has a complete allowlist and cap enforcement, and verify the operator
steps leave schedules and caches off. Confirm the matrix contains no duplicate
evidence run and no unauthorized dependency proposal.

### Completion criteria

The cost ledger contains known values and explicit unknowns, the zero-spend
boundary is accepted or concretely blocked, and a minimal ordered upload matrix
with exact UI targets and stop conditions is ready for the operator's separate
`UPLOAD BATCH GO` decision.

## Phase 3: Verify controlled uploads and reconcile detailed findings

### Workspace

.

### Goal

Verify Checkpoint B's one-at-a-time uploads, replace estimates with actual API
bytes, inspect available detailed evidence, and decide whether scheduled
acceptance can safely proceed.

### Scope

Public run/artifact verification, sanitized private finding summaries, artifact
cost reconciliation, scanner/audit/graph/build evidence, benchmark mapping, and
documentation updates.

### Non-goals

No authenticated downloads, credentials, new dispatches, variable changes,
artifact deletion, schedules, caches, App changes, PR changes, or promotion.

### Required context

Read the approved Phase 2 upload matrix, the operator's complete Checkpoint B
handoff, all linked run pages, the historical benchmark, and current coverage
tables. Do not request artifact contents that expose private information.

### Execution steps

1. For every supplied run URL, verify workflow, event, source SHA/ref, conclusion,
   duration, serialization, artifact count/name/ID/API bytes/expiry, and absence
   of unexpected caches or PRs using public metadata.
2. Confirm each archive stayed below 24 MiB before wrapper metadata and below the
   25 MiB approved cap in retained API bytes. Reconcile wrapper overhead and any
   discrepancy with the measured summary.
3. Review public reports and sanitized finding summaries for completeness,
   scanner/database/tool versions, package counts, and failure-path behavior.
   Never equate a successful workflow with zero vulnerabilities.
4. Map hosted evidence to every applicable deferred-check row and historical
   benchmark item. Use only `reproduced`, `superseded`, `false positive with
   evidence`, or `missing` for final advisory dispositions; leave unresolved
   items pending until Phase 5 if schedule evidence matters.
5. Refresh current billing/storage projection with actual bytes and one-day
   expiries. Record any UI lag and verify every upload variable returned to
   `false` publicly where possible or by operator attestation where not.
6. Update the canonical policy summary first if observed behavior changes policy,
   then the coverage report and operator-plan status. Publish
   `SAFE TO REQUEST SCHEDULE BATCH GO` or a concrete stop/recovery handoff.

### Implementation notes

Do not rerun a successful upload simply to improve timestamps. Missing detailed
content is an evidence gap even when artifact metadata is public. Preserve
unexpected findings and failed attempts rather than editing acceptance rules.

### Validation

Cross-check the sum of artifact API bytes against the cost table, verify one-day
retention, check every run belongs to the intended trial source, and verify no
upload/cache/schedule gate remains enabled. Review all benchmark mappings for
unsupported “passed” language.

### Completion criteria

Every approved upload has source-aware metadata and a disposition, actual bytes
replace estimates, detailed evidence gaps are explicit, all upload gates are
off, and scheduled acceptance is either safely recommended or concretely
blocked.

## Phase 4: Verify all real scheduled workflow cycles

### Workspace

.

### Goal

Verify one genuine cron-triggered cycle for each of the five Java dependency
graphs and four scheduled scanner/audit workflows.

### Scope

Public workflow-event verification, source/default refs, results, timing,
queueing/overlap, packages/findings, artifacts/caches, alert counts, and cost
model updates.

### Non-goals

No manual substitute for cron, variable or settings changes, dispatches,
artifact deletion, App changes, PR changes, benchmark finalization, rollback, or
promotion.

### Required context

Read the operator's complete Checkpoint C handoff, the nine linked run pages,
Phase 3's accepted artifact/cost ledger, current default/trial SHAs, and the
scheduled acceptance requirements in the canonical plan.

### Execution steps

1. Verify all nine URLs report event `schedule`, use the then-current protected
   trial default and expected SHA, and correspond to the checked-in workflow.
2. Verify each Java graph resolved complete runtime/test dependencies, retained
   internal coordinates where applicable, submitted successfully, and left an
   accepted graph/alert surface. Compare package counts with prior accepted runs.
3. Verify each scanner/audit completed all required download, inventory, and
   analysis stages. Record tool/database versions and findings without treating
   findings themselves as workflow failure.
4. Record start/end times, durations, queueing, the intentional 05:43 overlap,
   any other overlap, artifact count, and cache behavior. Confirm uploads and
   optional caches remained disabled.
5. Publicly verify schedule variables returned to `false` where possible; retain
   operator attestation where settings are private. Check for unexpected bot PRs,
   branches, issues, or workflow runs caused by the window.
6. Update the cost projection with actual cron durations and overlap, then update
   the coverage report and current-status summaries once.

### Implementation notes

GitHub cron delay is normal; a wrong event, skipped guard, wrong ref, or failed
resolution is not. Do not count platform-generated dependency-graph events as
repository cron. Do not ask the operator to expose private logs when a sanitized
error category is enough to preserve the failure.

### Validation

Require exactly nine accepted schedule-event records or explicit failed rows.
Cross-check source SHAs against public refs and compare graph package counts and
alert counts for unexplained regressions. Verify the documentation does not call
a manual or skipped run scheduled evidence.

### Completion criteria

All nine scheduled workflows have accepted source-aware cron evidence, or the
phase records a concrete failed workflow that must be corrected in its owning
repository before Phase 12 can proceed. Schedule, upload, and cache gates are off.

## Phase 5: Complete benchmark dispositions and prepare rollback

### Workspace

.

### Goal

Finish the historical benchmark comparison from all hosted evidence, state trial
acceptance honestly, and prepare a source-aware rollback ledger for the operator.

### Scope

Deferred-check closure, high-priority advisory classifications, maintained-line
and migration visibility, known tooling limitations, trial acceptance, cost
summary, and exact pre-rollback state.

### Non-goals

No authenticated UI work, App suspension, variable/default/PR changes, artifact
deletion, dependency merge, promotion decision, lifecycle-policy decision, or
claim of full parity when evidence is missing.

### Required context

Read the saved September 6 review, its recorded hash, all current coverage
tables, Phases 1-4 evidence, the canonical policy, and the rollback section of
the completed A-C operator plan.

### Execution steps

1. Reconcile every deferred check with source-ref-aware evidence and eliminate
   stale “pending” rows whose proof is already accepted.
2. Classify every benchmark category and named high-priority advisory as
   `reproduced`, `superseded`, `false positive with evidence`, or `missing`.
   Preserve missing Redis, External Secrets, Prometheus, offline Istio, checksum,
   ARM64, unversioned-package, VIA, and lifecycle limits unless evidence truly
   resolves them.
3. Confirm maintained patches remain visible alongside major migrations and that
   Node 24 remains an operator-applied prerequisite rather than bot discovery.
4. Summarize measured Actions duration, retained bytes, projected weekly
   GiB-hours, cache use, Mend queueing, failures/recoveries, PR-limit behavior,
   package access, graph counts, and zero-spend controls.
5. Report `trial acceptance`, `ongoing installation`, and `historical benchmark
   parity` separately. Partial benchmark coverage does not automatically fail a
   useful trial, but it must not be called full parity.
6. Capture the exact pre-rollback ledger: nine defaults and main/trial SHAs,
   App state/scope, four variable values, open bot PRs, artifacts/expiries,
   caches, dashboards, alerts, and queued/running jobs.
7. Update canonical policy/status first, then the coverage report and operator
   plan. Tell the operator whether Checkpoint D may proceed.

### Implementation notes

Lifecycle and exploitability decisions remain human work. Do not weaken the
benchmark to convert a missing finding into success. Rollback is required before
the merge decision even when trial acceptance is positive.

### Validation

Verify the historical review hash, check every advisory row has one allowed
classification, compare the rollback ledger with public refs and PRs, and verify
all cost arithmetic. Review links and ensure no archived or ADR file changed.

### Completion criteria

The trial has an evidence-backed acceptance statement, benchmark parity is
honestly full or partial, cost and known limits are explicit, and Checkpoint D
has an exact rollback baseline.

## Phase 6: Verify rollback and publish the decision package

### Workspace

.

### Goal

Prove the temporary rehearsal is paused and restored safely, then give the
operator a concise GO/NO-GO/DEFER decision package.

### Scope

Public post-rollback verification, operator attestations for private settings,
main SHA/default checks, PR closure, residual-state inventory, rollback ledger,
recommendation, and documentation updates.

### Non-goals

No App/settings/variable/default/PR changes by the agent, no artifact deletion,
branch deletion, merges, promotion, dependency updates, or assumption that
restoration erased repository-wide state.

### Required context

Read the operator's complete Checkpoint D handoff, Phase 5's pre-rollback ledger,
the recorded main SHAs, public repository metadata, artifact/cache state, and
the final decision criteria in the canonical Phase 12 plan.

### Execution steps

1. Verify every repository again advertises `main` as default at the recorded
   unchanged main SHA and retains the protected trial branch at its recorded SHA.
2. Verify all twelve named bot PRs are closed and unmerged, no unexpected bot PR
   opened, and no dependency update reached `main`.
3. Verify no trial workflow is queued/running, no post-rollback schedule fired,
   and public artifact/cache state matches the ledger. Record expired artifacts
   rather than treating them as never having existed.
4. Retain the operator's sanitized attestations that Mend access is paused or
   removed and all four variable gates are false where those controls are not
   public.
5. Record residual dashboards, alerts, PR history, artifacts, caches, App
   installation state, graph data, and accrued usage. Confirm both branch targets
   remain protected.
6. Publish a decision package containing trial result, benchmark result, costs,
   operational burden, failures/recoveries, unresolved gaps, proposed promotion
   scope/order, rollback result, and a reasoned recommendation.
7. Update canonical policy/status first, then coverage and operator-plan status.
   Request exactly the Checkpoint E decision; do not imply that a recommendation
   is authorization.

### Implementation notes

If a main SHA changed, a bot PR merged, App access cannot be paused/removed, or
a gate remains active, stop with the exact exception. Do not repair authenticated
state or rewrite history from the agent environment.

### Validation

Compare all nine repositories against both pre-trial and pre-rollback ledgers,
verify PR merge SHAs are absent, verify current defaults independently, and
review the decision package for separation of trial acceptance, benchmark
parity, and ongoing installation.

### Completion criteria

Rollback is proven or has one concrete operator-owned exception, and the
operator has enough evidence to choose GO, NO-GO, or DEFER without another
research pass.

## Phase 7: Record the decision and create the authorized next plan

### Workspace

.

### Goal

Record Checkpoint E without exceeding its authority and produce the correct
durable next state: a repo-by-repo promotion plan for GO, or a closed/deferred
trial record for NO-GO/DEFER.

### Scope

Decision recording, final status updates, and—only for GO—creation of a separate
AI Session Handler promotion plan with repository-specific phases, validation,
human merge/App UI checkpoints, and final hosted acceptance.

### Non-goals

No branch/configuration edits in sibling repositories, PR creation, merges, App
resumption, variable/default changes, workflow dispatches, dependency updates,
releases, deployment, or claim that GO itself completed ongoing installation.

### Required context

Read the exact Checkpoint E response, Phase 6 decision package, current rollback
state, `../ai-session-handler/docs/plan-format.md`, every scoped repository's
`AGENTS.md`, and the canonical Phase 12 promotion requirements.

### Execution steps

1. Validate that the response is exactly GO, NO-GO, or DEFER and record its UTC
   date plus optional rationale without embellishment.
2. For NO-GO or DEFER, update the canonical status and coverage conclusion,
   leaving App access paused/removed, false gates, protected trial branches, and
   ongoing installation explicitly unclaimed. Do not create unnecessary
   implementation work.
3. For GO, inspect each main-versus-trial diff read-only and inventory the exact
   promotion edits: publish shared preset first; replace trial preset refs with
   normal refs; remove or retire trial-only wiring deliberately; preserve caps,
   retention, no-automerge, PR limits, package access, security ownership, and
   Node 24 Actions policy; exclude every bot dependency update.
4. Create a new executable promotion plan under `docs/plans/` using the canonical
   AI Session Handler template. Use one repository workspace per repo-local edit,
   never combine repository writes in one phase, put human PR/merge and Mend/App
   actions behind explicit checkpoints, and require fresh final evidence across
   all nine repositories including graphs, App/PR behavior, main-path builds,
   costs, and scheduled workflows.
5. Add exact compare/settings/Actions links and sanitized operator handoff
   templates to the promotion plan, but do not perform those actions.
6. Update cross-links from the canonical dependency-automation docs and coverage
   report. Preserve the saved review, archives, and ADRs.

### Implementation notes

GO is authority to plan promotion, not to merge or mutate external state. The
new plan must honor each sibling repository's instructions and the hard phase
boundary for repository switching. If trial diffs include unrelated work, stop
and isolate it in the promotion design rather than proposing a broad branch
merge.

### Validation

For GO, validate the new plan with AI Session Handler's parser/inspection command,
confirm every phase has exactly one relative workspace and complete canonical
sections, and review all repository diffs and links. For NO-GO/DEFER, verify no
promotion plan or activation claim was added. In all cases, check documentation
links and the final diff.

### Completion criteria

The operator decision is durably recorded. NO-GO/DEFER leaves a safe paused
trial and closes this decision plan. GO leaves a validated, separately reviewable
promotion plan and does not claim Phase 12 ongoing installation complete.
