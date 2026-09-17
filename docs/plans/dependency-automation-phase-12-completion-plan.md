# Dependency Automation Phase 12 Completion Plan

This plan completes the bounded dependency-automation trial without treating
ordinary Java CI artifacts as deployment inputs. The public-baseline and
original cost-reconciliation work are completed historical checkpoints. This
executable plan starts by removing the workspace helper's false
intermediate-tar blocker. It records the operator-completed trial-branch
publication and exact-ID cleanup, obtains exact no-upload measurements, and
then makes a fresh one-at-a-time upload decision.

The agent never receives credentials or performs authenticated GitHub mutations.
The operator owns publication, exact-ID deletion, workflow dispatches, settings,
App access, and final decisions. Keep uploads, schedules, optional caches, and
unapproved graph submission `false` unless the exact checkpoint below explicitly
authorizes one action. No payment method, paid trial, or allowance increase is
allowed.

Keep every remediation change on the protected dependency-automation trial
branch until the final promotion decision. `main` and its recorded SHAs are the
rollback baseline. Trial publication proves that the change is reviewable and
recoverable; it does not activate the corrected recurring-storage model on
`main`. Until promotion, a new `main` build may recreate `app-jar`, so every
inventory refresh must check for recurrence. A `NO-GO` or `DEFER` restores the
original defaults/settings and leaves `main` unchanged; removal of trial refs is
considered only after rollback verification.

Rollback applies to repository refs, workflow behavior, variables, schedules,
caches, App access, and defaults. The completed deletion of an Actions artifact
is not reversible: its old artifact ID cannot be restored. Preserve the exact
deletion ledger as the audit record. This does not impair release or deployment
rollback because no active release or deployment path consumed `app-jar`; if a
diagnostic copy were ever needed, the old workflow can regenerate equivalent
JARs from the recorded source SHA without restoring the deleted object.

Run one phase at a time with `--max-phases 1`. Do not cross an operator
checkpoint in one invocation: Phase 2 requires Checkpoint B, Phase 3 requires
Checkpoint C, Phase 4 requires Checkpoint D, Phase 6 requires Checkpoint E, and
Phase 7 requires Checkpoint F. Stop with a concrete handoff when the required
checkpoint record is absent or incomplete.

The canonical policy is [Dependency Automation](../dependency-automation.md),
the evidence ledger is the
[coverage report](../research/dependency-automation-coverage.md), and completed
Batches A-C remain summarized in the
[operator plan](dependency-automation-phase-12-operator-plan.md).

## Current disposition

The completed original cost reconciliation recorded **DO NOT AUTHORIZE
UPLOADS** under the old recurring-storage model. The corrected model removes
deploy-unconsumed `app-jar` uploads and keeps
failure-only JUnit XML for one day. A public refresh at
`2026-09-17T04:56:48Z` still found the old objects: 17 non-expired artifacts,
502,562,266 bytes, and zero caches across all 15 public organization
repositories. Eight exact `app-jar` artifacts contribute 501,224,156 bytes.

After exact-ID cleanup, known public residual storage is 1,338,110 bytes. A
rolling trial window containing one 25 MiB retained artifact
and one retry would peak at 53,766,910 public bytes, but this is not authority to
upload. Public verification at `2026-09-17T05:25:38Z` confirms all eight IDs are
absent, no public `app-jar` remains, public caches remain zero, and the four
service corrections are on exact `dependency-automation-trial` heads
`cca334840a5ad812f4745621e7196c281541393d`,
`943edf82fa6fe55e625a70dc7b51bd26424bd3de`,
`c8e2b4ccef37e059357d01aed937e93894a85485`, and
`923637aadb8be5d9f87a9f88799bd7d6dd4905d7` in currency, permission,
transaction, and session order. Their recorded `main` SHAs remain unchanged.
The zero-artifact successful-CI projection is therefore a promotion projection,
not current `main` behavior. The four other required archive sizes and
account-private usage remain unknown, and the workspace helper correction is
not implemented.

## Operator checkpoint A: completed zero-spend baseline

Checkpoint A is complete. Preserve its historical record: GitHub Free for
organizations, no payment method, zero-dollar Actions and Packages budgets with
**Stop usage**, `$0` billed Actions usage, Mend Community/free, no paid trial,
and all upload/schedule/cache variables off. These controls bound spend at zero;
they do not prove storage headroom.

## Operator checkpoint B: publish, clean up, and measure without uploads

Perform this checkpoint only after Phase 1 validates the workspace correction.
This checkpoint does not authorize an evidence upload.

1. Record the four merged PR URLs and merge SHAs. Verify they landed on the exact
   protected `dependency-automation-trial` ref expected by the workflow guards;
   if the operator used a differently named dependency-automation branch, stop
   and reconcile the ref before running measurements. Confirm `main` and its
   recorded SHAs remain unchanged. Do not promote these changes to `main` during
   the trial.
2. Review and publish the Phase 1 workspace correction at a recorded source SHA.
   Publish it only to `dependency-automation-trial`; keep `main` unchanged and
   keep uploads, schedules, and optional caches `false`.
3. Verify the eight recorded artifact IDs are absent. Preserve their repository,
   run, source SHA, name, API size, expiry, and the operator's exact-ID deletion
   record. If any ID still exists, stop and reconcile it rather than issuing a
   broad or repeated cleanup.
4. The completed deletion target list is retained below for audit and rollback
   evidence. Do not rerun these commands against an unverified or reused ID.

```bash
gh api --method DELETE repos/budgetanalyzer/currency-service/actions/artifacts/10440009083
gh api --method DELETE repos/budgetanalyzer/currency-service/actions/artifacts/10440089489
gh api --method DELETE repos/budgetanalyzer/permission-service/actions/artifacts/10439738759
gh api --method DELETE repos/budgetanalyzer/permission-service/actions/artifacts/10440034884
gh api --method DELETE repos/budgetanalyzer/transaction-service/actions/artifacts/10440595892
gh api --method DELETE repos/budgetanalyzer/transaction-service/actions/artifacts/10440114874
gh api --method DELETE repos/budgetanalyzer/session-gateway/actions/artifacts/10439454814
gh api --method DELETE repos/budgetanalyzer/session-gateway/actions/artifacts/10441010133
```

5. Obtain a fresh public artifact/cache inventory after deletion. Expected public
   residual, if no unrelated run occurred, is 1,338,110 artifact bytes and zero
   cache bytes. Record changed reality instead of forcing that expectation, and
   explicitly identify any new `app-jar` created by an unchanged `main` workflow.
6. With uploads, schedules, and optional caches still `false`, run the five
   candidate workflows one at a time only to obtain fresh job-summary
   measurements. Record repository, workflow/run URL, source SHA, source bytes,
   temporary tar bytes, final gzip bytes, `upload_allowed`, allowlist/target
   count, and zero retained artifacts. The five rows are `govulncheck`, npm
   audit, representative Java graph, workspace image, and platform image.
7. In the operator's trusted environment, record a sanitized aggregate of
   current private-repository artifact and package bytes and counts. Do not send
   tokens, repository names, raw private API responses, cookies, or logs to the
   agent. If GitHub cannot expose a trustworthy aggregate, report private usage
   as unknown.
8. Confirm again that no payment method or paid trial was added and every upload,
   schedule, and optional-cache variable remains `false`.
9. Send the sanitized checkpoint record:

```text
Checkpoint B complete
Observed UTC: TIMESTAMP
Published regular-CI correction SHAs: REPOSITORY=SHA ...
Published workspace correction SHA: SHA
Trial branch verified as dependency-automation-trial: yes | no, actual ref
Recorded main SHAs unchanged: yes | no, details
Deleted artifact IDs verified absent: 10440009083, 10440089489, 10439738759, 10440034884, 10440595892, 10440114874, 10439454814, 10441010133 | mismatch details
Fresh public artifact bytes/count: BYTES / COUNT
Fresh public cache bytes/count: BYTES / COUNT
Private artifact aggregate: BYTES / COUNT | unknown
Private package aggregate: BYTES / COUNT | unknown
govulncheck: RUN | SHA | SOURCE | TAR | GZIP | ALLOWED | ZERO_ARTIFACTS
npm audit: RUN | SHA | SOURCE | TAR | GZIP | ALLOWED | ZERO_ARTIFACTS
Java graph: RUN | SHA | SOURCE | TAR | GZIP | ALLOWED | ZERO_ARTIFACTS
workspace image: RUN | SHA | SOURCE | TAR | GZIP | ALLOWED | ZERO_ARTIFACTS
platform image: RUN | SHA | SOURCE | TAR | GZIP | ALLOWED | ZERO_ARTIFACTS
Uploads/schedules/caches: false / false / false
Payment method or paid trial added: no
Unexpected condition: none | sanitized description
```

## Operator checkpoint C: controlled one-at-a-time uploads

Do not perform this checkpoint unless Phase 2 publishes
`SAFE TO REQUEST UPLOAD BATCH GO` with an exact matrix and the operator then
replies `UPLOAD BATCH GO`.

For each approved row, complete the entire sequence before touching the next:

1. Verify the source SHA and exact archive estimate still match Phase 2.
2. Keep schedules and optional caches `false`. Enable uploads only in that one
   repository; preserve graph-submission state exactly as the matrix requires.
3. Dispatch the exact approved workflow on `dependency-automation-trial` and
   wait for completion. Do not overlap rows.
4. Immediately restore uploads to `false`.
5. Record artifact ID, repository, run URL, source SHA, name, API
   `size_in_bytes`, expiry, tool/database versions, target counts, and all
   row-specific findings. Stop if the retained artifact exceeds 25 MiB, the
   evidence is incomplete, the ref changed, a cache or PR appeared, or the run
   failed/skipped.
6. Recompute current storage with one retry. After all required findings are
   recorded, the operator may delete that exact artifact ID or wait for one-day
   expiry before the next row. Never use a broad cleanup.

Candidate order, subject to Phase 2 minimization:

1. `ext-authz` Go Vulnerability Check
2. `budget-analyzer-web` Dependency Audit
3. `service-common` Dependency Submission
4. `workspace` Workspace Image Security Evidence
5. `orchestration` Exact Image Security Evidence

## Operator checkpoint D: real scheduled events

Do not enable schedules unless Phase 3 accepts the controlled evidence and the
operator replies `SCHEDULE BATCH GO`. Keep uploads and optional caches `false`.
Enable only the documented trial schedule variables, observe one real cron event
for each of the nine scheduled workflows, then restore all schedule variables to
`false`. Record run URL, source SHA, scheduled event, start/end timestamps,
queueing, result, findings/package counts, and zero unexpected artifacts/caches.

## Operator checkpoint E: pause and restore

After Phase 5 prepares rollback, pause/remove Mend trial access, cancel queued
trial jobs, set every trial variable `false`, restore original defaults and
settings, preserve recorded evidence, and leave branch protection in place until
Phase 6 verifies restoration. Verify every recorded `main` SHA is unchanged and
that none of the trial-only artifact-policy or workspace-helper changes reached
`main`. Do not merge dependency PRs or manually delete an artifact whose
required findings are not recorded. Consider removal of trial refs only after
Phase 6 accepts rollback.

## Operator checkpoint F: final decision

After Phase 6 publishes the decision package, reply with exactly one:

```text
PHASE 12 DECISION: GO
PHASE 12 DECISION: NO-GO
PHASE 12 DECISION: DEFER
```

`GO` authorizes Phase 7 to write a separate promotion plan. It does not authorize
merges, App resumption, schedules, uploads, caches, releases, or deployment.

## Phase 1: Correct workspace evidence eligibility

### Workspace

../workspace

### Goal

Remove the self-imposed intermediate-tar blocker while preserving complete
workspace image evidence and both upload-size ceilings.

### Scope

The workspace evidence helper/workflow, focused tests, and nearest workspace
dependency-automation documentation, all on `dependency-automation-trial`.

### Non-goals

No scanner-target trimming, upload, schedule, cache enablement, dispatch,
authenticated API action, image push/start, or unrelated workspace change.

### Required context

Read workspace `AGENTS.md`, `.github/scripts/prepare-trial-evidence.sh`,
`.github/workflows/workspace-image-security-evidence.yml`, and
`docs/dependency-automation.md`. Use the measured 42,276,809 source bytes,
42,301,440-byte tar, and 5,754,918-byte gzip as the known regression case.

### Execution steps

1. Keep source, tar, and gzip measurements, but make `upload_allowed` depend only
   on the final `.tar.gz` being at most 25,165,824 bytes.
2. Preserve the complete `workspace-image-scan` allowlist and fail on archive
   creation, missing inputs, traversal, or compressed payload overflow.
3. Keep upload compression level zero and add a post-upload exact-ID API check
   that fails if retained `size_in_bytes` exceeds 26,214,400 bytes.
4. Add focused synthetic coverage for a tar above 24 MiB whose gzip is below
   24 MiB, and for a gzip above 24 MiB that remains rejected.
5. Update workspace documentation with the payload-versus-retained distinction.
6. Record the starting `main` and trial SHAs and leave `main` unchanged. Prepare
   the correction as trial-only work for an operator-owned PR/merge.

### Implementation notes

The temporary tar is compressor input, not retained payload. Do not precompress
or remove reports merely to reduce the tar measurement. If the retained-size
check fails after upload, stop; the operator handles any exact-ID deletion after
recording the artifact.

### Validation

Run focused helper tests, `bash -n`, `shellcheck`, `actionlint`, and
`git diff --check`. Verify the complete allowlist is unchanged and the known
5,754,918-byte gzip becomes eligible without changing its contents.

### Completion criteria

The workspace owns a reviewed fail-closed correction with a 24 MiB final-payload
target, 25 MiB retained ceiling, complete evidence, no enabled upload, and an
unchanged `main` rollback baseline.

## Phase 2: Recompute headroom and publish the upload recommendation

### Workspace

.

### Goal

Use Checkpoint B's post-cleanup inventory, exact no-upload sizes, one retry, and
private-usage aggregate to decide whether an upload batch may be requested.

### Scope

Read-only public verification, arithmetic, canonical policy, coverage ledger,
and current-status summaries.

### Non-goals

No workflow dispatch, upload, artifact deletion, schedule/cache enablement,
authenticated API action, or assumption that unknown private usage is zero.

### Required context

Read the complete Checkpoint B handoff, fresh public API inventory, exact five-row
measurement summaries, canonical policy, coverage report, and operator-plan
summary.

### Execution steps

1. Verify the eight IDs are absent or record exact exceptions; confirm no new
   ordinary `app-jar` appeared.
2. Recalculate known public bytes. Report current `main` recurrence separately
   from the trial-only corrected projection; do not claim the corrected model is
   active until a later promotion changes `main`.
3. For each candidate, use its exact final gzip estimate and enforce the 24 MiB
   payload target. Model retained bytes conservatively up to 25 MiB until API
   bytes replace the estimate.
4. Compute a rolling one-at-a-time peak with one retry, current non-trial bytes,
   expected ordinary failure diagnostics, and explicit private artifact/package
   usage. Keep caches at zero.
5. Reject the batch if any size is missing, private usage is unknown or consumes
   the envelope, evidence is incomplete, or zero-spend controls changed.
6. Update `docs/dependency-automation.md` first, then the coverage report and
   operator-plan status. Publish either `SAFE TO REQUEST UPLOAD BATCH GO` with an
   exact matrix and stop thresholds, or `DO NOT AUTHORIZE UPLOADS` with exact
   remaining blockers.

### Implementation notes

Do not require all five artifacts to coexist. The rolling model permits exact-ID
cleanup after findings are recorded and therefore scales to later repositories.

### Validation

Reperform every byte calculation independently, verify links and timestamps, and
run `git diff --check`. Confirm no text itself authorizes an upload.

### Completion criteria

The corrected model has a current evidence-backed recommendation. Checkpoint C
remains unavailable until a separate `UPLOAD BATCH GO` response.

## Phase 3: Verify controlled evidence uploads

### Workspace

.

### Goal

Verify the operator-authorized one-at-a-time upload batch and reconcile actual
retained bytes and findings.

### Scope

Public run/artifact verification, sanitized private findings, rolling storage
accounting, and documentation.

### Non-goals

No dispatch, variable mutation, deletion, schedule/cache enablement, or promotion.

### Required context

Read Phase 2's matrix and the complete Checkpoint C handoff.

### Execution steps

1. Verify each run's ref, SHA, event, result, serialization, artifact ID/name/API
   bytes/expiry, and restored upload gate.
2. Confirm complete row-specific reports and required findings; leave missing
   content as an evidence gap.
3. Confirm every retained artifact is at most 25 MiB and reconcile wrapper
   overhead against its final gzip estimate.
4. Verify any deletion targeted only the recorded exact ID after findings were
   captured, then recompute the next-row retry envelope.
5. Update canonical policy first, then coverage and status summaries. Recommend
   or reject Checkpoint D.

### Implementation notes

An expired or deleted artifact can still count when its metadata and required
findings were recorded before deletion. A URL alone is not detailed evidence.

### Validation

Cross-check API-byte sums, retained windows, one-retry calculations, and all five
evidence dispositions. Run `git diff --check`.

### Completion criteria

All approved rows are accepted or have a concrete blocker, gates are off, and
scheduled acceptance has an explicit recommendation.

## Phase 4: Verify real scheduled cycles

### Workspace

.

### Goal

Verify one real cron event for every scheduled trial workflow after Checkpoint D.

### Scope

Public run verification, sanitized private summaries, schedule/cost accounting,
and documentation.

### Non-goals

No schedule mutation, rerun, upload, cache, App change, or promotion.

### Required context

Read Checkpoint D's handoff, the nine workflow guards, and Phase 3's ledger.

### Execution steps

1. Verify all nine runs used `schedule` on the frozen trial refs and did not skip
   their substantive jobs.
2. Record duration, queueing, overlap, findings/package counts, artifacts, and
   cache behavior.
3. Confirm all schedule, upload, and cache variables returned to `false`.
4. Update canonical policy, coverage, and current-status summaries.

### Implementation notes

Manual dispatch is not cron evidence. Keep the two 05:43 jobs' intentional
overlap visible in compute accounting.

### Validation

Verify timestamps/events from public metadata and reconcile all nine rows.

### Completion criteria

All scheduled workflows have accepted source-aware evidence or one explicit
blocker, and every execution gate is off.

## Phase 5: Complete benchmark dispositions and prepare rollback

### Workspace

.

### Goal

Finish the historical comparison and prepare an exact restore ledger.

### Scope

Coverage dispositions, cost summary, frozen refs/settings, and Checkpoint E
handoff.

### Non-goals

No settings mutation, App removal, PR change, branch deletion, merge, or final
GO/NO-GO/DEFER decision.

### Required context

Read the saved September 6 review, current coverage tables, current completion
plan evidence through Phase 4, and the original main/default/settings ledger.

### Execution steps

1. Classify every benchmark row as reproduced, superseded, false positive with
   evidence, or missing.
2. Separate trial acceptance, ongoing-installation readiness, and benchmark
   parity.
3. Reconcile final trial storage/compute with no-spend controls.
4. Prepare exact Checkpoint E restore targets and stop conditions.

### Implementation notes

Do not claim full parity while a high-priority row is missing.

### Validation

Verify the review hash, every disposition, and every restore target.

### Completion criteria

The evidence and rollback ledgers are complete enough for operator restoration.

## Phase 6: Verify rollback and publish the decision package

### Workspace

.

### Goal

Verify Checkpoint E and produce the final evidence-backed decision package.

### Scope

Public state verification, sanitized authenticated attestations, residual-state
ledger, and decision recommendation.

### Non-goals

No mutation, merge, branch deletion, artifact cleanup, App reactivation, or
promotion plan.

### Required context

Read Checkpoint E's handoff, Phase 5's restore ledger, recorded main SHAs, and
current public repository state.

### Execution steps

1. Verify original defaults/main SHAs, paused App/jobs, closed or preserved PRs
   as specified, false variables, and active protections.
2. Inventory residual artifacts, caches, dashboards, alerts, and history.
3. Reconcile all acceptance, parity, cost, credential, schedule, and rollback
   evidence.
4. Publish separate trial-acceptance, ongoing-installation, and benchmark-parity
   conclusions with a GO, NO-GO, or DEFER recommendation.

### Implementation notes

Restoring defaults does not erase repository-wide state or accrued usage.

### Validation

Cross-check public API state, sanitized operator attestations, and every decision
criterion. Run `git diff --check`.

### Completion criteria

Rollback is verified or has one concrete exception, and Checkpoint F can be
answered without another research pass.

## Phase 7: Record the decision and create the authorized next plan

### Workspace

.

### Goal

Record Checkpoint F and, only after `GO`, create a separate promotion plan.

### Scope

Decision documentation and a promotion plan limited to the approved outcome.

### Non-goals

No merge, App/settings mutation, schedule/upload/cache enablement, dependency
upgrade, release, deployment, or claim that `GO` completed installation.

### Required context

Read the exact Checkpoint F response, Phase 6 package, current rollback state,
and the AI Session Handler plan format.

### Execution steps

1. Record `GO`, `NO-GO`, or `DEFER` exactly and preserve the evidence links.
2. For `NO-GO` or `DEFER`, document recoverable state and stop.
3. For `GO`, create a separate plan that publishes the shared preset first,
   removes trial-only wiring through reviewed repo-owned phases, and reactivates
   each repository deliberately with fresh final evidence.
4. Keep ordinary CI artifact policy, exact-ID cleanup rules, and rolling evidence
   retention in the promotion acceptance criteria.

### Implementation notes

The promotion plan must keep one workspace per phase and must not bundle bot
dependency updates with infrastructure promotion.

### Validation

Validate plan structure, links, phase numbering, workspace paths, and decision
wording. Run `git diff --check`.

### Completion criteria

The exact decision is durable. `GO` has a reviewable next plan; `NO-GO` or
`DEFER` leaves execution paused without implying ongoing installation.
