# Dependency Automation Phase 12 Completion Plan

This plan completes the bounded dependency-automation trial with agent-owned
evidence collection by default. The agent performs every public read, inventory,
calculation, comparison, wait, and documentation update that anonymous GitHub
APIs permit. The operator is not a human API client and must not be asked to
recheck public artifacts, caches, branch heads, workflow status, or previously
recorded billing facts.

Credentials remain outside the agent environment. The only operator work left
is a small set of consequential or credentialed actions: publishing reviewed
changes, running an agent-authored host helper for GitHub mutations, giving an
explicit upload or schedule authorization, restoring account settings, and
making the final GO/NO-GO/DEFER decision. Host helpers must fail closed, use the
operator's existing `gh` session without exposing its token, and write only a
sanitized machine-readable ledger under ignored `tmp/` paths that the agent can
inspect. Do not require the operator to compose checkpoint reports manually.

The completed zero-spend checkpoint is a standing invariant. Do not ask the
operator to reconfirm the absence of a payment method or paid trial. The
operator must proactively report a change before further hosted work if a
payment method, paid trial, allowance increase, or spend-stop removal is
introduced. Otherwise every phase proceeds from the recorded hard stop. Private
artifact and package usage is `unknown` unless a sanitized aggregate is already
available; record `unknown` once and do not ask the operator to investigate it
again. Unknown private usage is not zero, but under the standing hard stop a
single capped upload may be used as a fail-closed capacity probe after exact
no-upload sizing. A quota rejection fails the trial and never authorizes billing.

Keep every remediation change on the protected
`dependency-automation-trial` branches until a separate promotion plan is
approved. `main` and its recorded SHAs remain the rollback baseline. Until
promotion, an unchanged `main` workflow may recreate `app-jar`, so every agent
inventory must identify recurrence without asking the operator to do so.

Run one phase at a time with `--max-phases 1`. A phase may wait and poll public
state. It must stop only for a listed operator gate, an unavailable exact job
summary, or a genuine evidence failure. Do not manufacture a broader handoff.
The canonical policy is [Dependency Automation](../dependency-automation.md),
the evidence ledger is the
[coverage report](../research/dependency-automation-coverage.md), and completed
Batches A-C remain summarized in the
[operator plan](dependency-automation-phase-12-operator-plan.md).

## Responsibility model

| Work | Owner | Rule |
| --- | --- | --- |
| Public branch/SHA, PR, workflow, job, artifact, cache, and exact-ID reads | Agent | Query GitHub directly, paginate, timestamp, retry rate limits, and save sanitized evidence. |
| Public artifact/cache totals and `app-jar` recurrence | Agent | Recompute from APIs; never ask the operator. |
| Zero-artifact and serialized-run verification | Agent | Derive from public run, job, and artifact metadata. |
| Source/tar/gzip values in a GitHub job summary | Agent when exposed; otherwise one minimal operator extraction | GitHub does not expose custom job-summary content anonymously. Ask once only for the missing measurement rows, never for facts available through public APIs. |
| Private artifact/package totals | Agent records `unknown` | Do not ask again unless an aggregate is volunteered or already present. |
| Billing/payment/trial state | Standing historical baseline | Do not reconfirm. Stop only if the operator reports a change. |
| Workflow dispatches, repository variables, App/default/settings changes, and exact-ID deletion | Operator-side host helper | Agent authors and validates the helper; operator runs it with credentials outside the container; agent consumes its sanitized ledger. |
| Evidence analysis, arithmetic, recommendations, and documentation | Agent | Perform completely and independently. |
| Upload, schedule, and final promotion decisions | Operator | Require only the exact GO phrase defined below. |

## Standing baseline and completed work

Checkpoint A is complete: GitHub Free for organizations, no payment method,
zero-dollar Actions and Packages budgets with **Stop usage**, `$0` billed Actions
usage at the checkpoint, Mend Community/free, no paid trial, and trial expansion
variables off. These facts bound spend at zero but do not prove capacity. They
are not a recurring questionnaire.

The operator deleted the eight obsolete `app-jar` artifacts by exact ID. The
agent must verify their continued absence itself:

```text
currency-service:    10440009083 10440089489
permission-service:  10439738759 10440034884
transaction-service: 10440595892 10440114874
session-gateway:     10439454814 10441010133
```

The four regular-CI corrections are published only on their protected trial
branches. Public verification at `2026-09-17T05:25:38Z` found 1,338,110 known
public artifact bytes, zero public cache bytes, no remaining public `app-jar`,
and unchanged recorded `main` SHAs. That observation is historical; Phase 2
must refresh it.

The workspace evidence correction is now published on
`dependency-automation-trial` at
`6a6bf33fb019825b7709693a1b103c8a1dd7d726`. Its publication-triggered
[workflow run](https://github.com/budgetanalyzer/workspace/actions/runs/35187741819)
completed successfully with zero artifacts. `main` remains
`383efc840832d474cd9d60e0368ed2ded828e03c`. The known regression bundle was
42,276,809 source bytes, a 42,301,440-byte temporary tar, and a 5,754,918-byte
gzip; a fresh source-exact summary still replaces those historical measurements
when available.

## Minimal operator gates

These are the only permissible operator gates. No gate asks the operator to
verify public state or restate the standing billing baseline.

### Gate B: credentialed no-upload execution, only if needed

Phase 2 first searches for source-exact successful trial runs. If one or more
candidate runs are absent, the agent supplies one exact host command that
dispatches only the missing workflows on `dependency-automation-trial`, waits
for each to finish before starting the next, and never changes upload, schedule,
graph-submission, or cache variables. The five candidates are:

1. `budgetanalyzer/ext-authz`: `go-vulnerability-check.yml`
2. `budgetanalyzer/budget-analyzer-web`: `dependency-audit.yml`
3. `budgetanalyzer/service-common`: `dependency-submission.yml`
4. `budgetanalyzer/workspace`: `workspace-image-security-evidence.yml`
5. `budgetanalyzer/orchestration`: `exact-image-security-evidence.yml`

The operator runs that command in an authenticated host shell. The agent then
discovers the runs, jobs, SHAs, conclusions, and zero-artifact results through
public APIs. If GitHub still hides custom summary content, the only manual input
allowed is one five-row extraction containing `SOURCE`, `TAR`, `GZIP`,
`ALLOWED`, and allowlist/target count. Do not request branch checks, artifact
checks, private totals, variable confirmations, or billing confirmations.

### Gate C: controlled uploads

Phase 3 may publish `SAFE TO REQUEST UPLOAD BATCH GO` with an exact matrix and
an agent-authored host helper. The operator must reply exactly:

```text
UPLOAD BATCH GO
```

The operator then runs the helper once. It preflights exact SHAs and false
schedule/cache gates, enables uploads for one repository at a time, dispatches
and waits, restores the upload gate in a trap, downloads the exact artifact into
ignored `tmp/` evidence, records API metadata and a checksum, and deletes only
that exact artifact after the local copy is complete if the matrix authorizes
deletion. It stops on any mismatch and emits a sanitized JSON ledger. The agent
performs every subsequent verification and report analysis.

### Gate D: real scheduled events

Phase 4 may publish `SAFE TO REQUEST SCHEDULE BATCH GO` with exact enable and
restore commands. The operator must reply exactly:

```text
SCHEDULE BATCH GO
```

The operator runs the agent-authored host helper to enable only the approved
trial schedule variables. The agent monitors public APIs until one real cron
event for every required workflow is accepted or a timeout/blocker is proven.
The operator then runs the helper's restore command; the agent verifies all
public consequences and consumes the sanitized settings ledger. No manual run
report is required.

### Gate E: pause and restore

After Phase 5 publishes an exact restore manifest and validated host helper, the
operator runs it in the trusted host environment. The helper pauses/removes Mend
trial access, cancels queued trial jobs, restores original defaults/settings,
sets every trial variable false, and emits a sanitized ledger. The agent verifies
all public state and does not ask for a prose attestation.

### Gate F: final decision

After Phase 6 publishes the complete decision package, the operator replies
with exactly one:

```text
PHASE 12 DECISION: GO
PHASE 12 DECISION: NO-GO
PHASE 12 DECISION: DEFER
```

`GO` authorizes Phase 7 to write a separate promotion plan. It does not
authorize merges, App resumption, schedules, uploads, caches, releases, or
deployment.

## Phase 1: Verify the completed workspace evidence correction

### Workspace

../workspace

### Goal

Treat the published Phase 1 correction as completed work and verify its
fail-closed behavior and public result without changing it again.

### Scope

The workspace helper/workflow, focused tests, nearest documentation, published
trial SHA, and publication-triggered workflow metadata.

### Non-goals

No new implementation, dispatch, upload, schedule/cache change, authenticated
API action, image push/start, merge, or `main` change.

### Required context

Read workspace `AGENTS.md`, `.github/scripts/prepare-trial-evidence.sh`,
`.github/scripts/test-prepare-trial-evidence.sh`,
`.github/workflows/workspace-image-security-evidence.yml`, and
`docs/dependency-automation.md`.

### Execution steps

1. Verify public trial SHA `6a6bf33fb019825b7709693a1b103c8a1dd7d726`
   contains the correction and `main` remains at the recorded rollback SHA.
2. Verify run `35187741819` completed successfully and retained zero artifacts.
3. Confirm eligibility depends only on a final gzip no larger than 25,165,824
   bytes, upload compression remains zero, and the exact retained ceiling is
   26,214,400 bytes.
4. Confirm the workflow still passes the complete `workspace-image-scan`
   allowlist and every expansion gate remains conditional.
5. Run the focused helper tests, `bash -n`, `shellcheck`, `actionlint`, and
   `git diff --check` if the published source is present locally.

### Implementation notes

The temporary tar is compressor input, not retained payload. Do not create
another remediation PR when the published correction and checks already pass.

### Validation

Cross-check public ref/run/artifact APIs and local tests. Record any changed
public state directly; do not ask the operator to verify it.

### Completion criteria

The correction is accepted as published, its run is green with zero artifacts,
and `main` remains unchanged.

## Phase 2: Collect the post-publication baseline and no-upload measurements

### Workspace

.

### Goal

Perform all public Checkpoint B work, obtain the five exact no-upload rows, and
produce a machine-readable evidence ledger without recurring operator
attestations.

### Scope

Credentialless GitHub API collection, optional repo-owned collection scripts,
public run/job/artifact/cache verification, exact size rows, and canonical
documentation.

### Non-goals

No upload, artifact deletion, schedule/cache/graph enablement, App/settings
change, assumption that private usage is zero, or billing reconfirmation.

### Required context

Read the standing baseline and Gate B above, canonical policy, coverage report,
operator-plan summary, the five candidate workflows, and `scripts/README.md`
before adding a collector or host helper.

### Execution steps

1. Query all public organization repositories with pagination. Verify the eight
   deleted IDs return absent, inventory every non-expired artifact and cache,
   total bytes/counts, and identify any new `app-jar` with repository, run, SHA,
   expiry, and size.
2. Verify the four regular-CI correction trial heads, the workspace correction
   head, every recorded `main` rollback SHA, and exact branch names directly.
3. Discover the newest source-exact candidate runs. Verify event, trial ref,
   source SHA, result, job steps, serialization, skipped upload/cache paths, and
   zero artifacts through public APIs.
4. If a candidate run is absent, prepare the exact serialized Gate B host
   command and stop only for its execution. After execution, discover and verify
   the runs yourself; do not ask for a checkpoint narrative.
5. Record source, tar, gzip, `upload_allowed`, and allowlist/target count from
   accessible evidence. If custom summaries remain inaccessible anonymously,
   request only the five missing measurement rows once, then own all validation
   and transcription.
6. Record private artifact and package totals as `unknown` unless a sanitized
   aggregate already exists. Carry the standing zero-spend baseline forward
   without asking for confirmation.
7. Save a sanitized ledger under ignored `tmp/dependency-automation/` and update
   `docs/dependency-automation.md` first, then the coverage report and
   operator-plan status.

### Implementation notes

Anonymous GitHub APIs expose public branches, runs, jobs, artifacts, caches,
and exact artifact IDs. They do not expose custom job-summary content. Treat
that API limitation narrowly; it does not justify delegating the rest of the
checkpoint to the operator. A rate limit is a retry/wait condition, not a reason
to request manual verification.

### Validation

Independently re-sum public bytes and counts, verify pagination and timestamps,
cross-check every run against its branch head, run `bash -n` and `shellcheck` on
new shell helpers, and run `git diff --check`.

### Completion criteria

All public baseline facts and five exact size rows are recorded, private usage
is a single explicit `unknown` if necessary, zero artifacts are proven, and the
operator has not been asked to reconfirm billing or public state.

## Phase 3: Recompute headroom and prepare the controlled-upload bridge

### Workspace

.

### Goal

Use Phase 2 evidence to decide whether a fail-closed one-at-a-time upload probe
is safe and prepare its exact operator-side automation.

### Scope

Storage arithmetic, candidate minimization, exact matrix, stop thresholds,
agent-authored host helper, canonical policy, and evidence summaries.

### Non-goals

No upload, dispatch, variable mutation, deletion, schedule/cache enablement,
credential access, or promotion.

### Required context

Read Phase 2's sanitized ledger, current public inventory, exact five-row
measurements, standing hard-stop policy, and exact-ID deletion rules.

### Execution steps

1. Recalculate known public bytes and separate any current `main` recurrence
   from the trial-only corrected projection.
2. Enforce the 24 MiB final-payload target for each row and model retained bytes
   conservatively up to 25 MiB until API values replace estimates.
3. Compute the rolling peak with one retry, current non-trial bytes, and expected
   failure diagnostics. Keep private usage explicitly unknown and treat quota
   rejection as a safe trial failure under the standing hard stop.
4. Minimize the upload matrix to evidence that cannot be accepted from the
   no-upload runs. Do not upload merely because a row exists.
5. Create or update a repo-owned host helper that preflights exact SHAs and
   gates, serializes rows, restores variables with a trap, downloads each exact
   artifact to ignored `tmp/`, verifies its checksum, captures API metadata,
   optionally deletes only the exact captured ID, and writes a sanitized JSON
   ledger without credentials or raw private API responses.
6. Update canonical policy first, then coverage and status summaries. Publish
   either `SAFE TO REQUEST UPLOAD BATCH GO` with the exact Gate C command or
   `DO NOT AUTHORIZE UPLOADS` with concrete evidence blockers.

### Implementation notes

Unknown private usage no longer causes another operator inquiry. It remains a
capacity uncertainty bounded by the standing no-spend control; the first quota
failure ends the batch. The helper must never add billing, broaden deletion, or
continue after a failed restore.

### Validation

Reperform every byte calculation independently. Dry-run the host helper against
fixtures or mocked `gh` output, run `bash -n`, `shellcheck`, focused tests, and
`git diff --check`. Confirm no document or helper bypasses Gate C.

### Completion criteria

The upload recommendation is evidence-backed and, if positive, the operator's
entire credentialed task is one reviewed helper invocation after one exact GO.

## Phase 4: Verify controlled uploads and detailed evidence

### Workspace

.

### Goal

After Gate C, verify the helper's one-at-a-time batch, inspect downloaded
evidence, and decide whether real scheduled events are warranted.

### Scope

Sanitized helper ledger, public run/job/artifact APIs, downloaded evidence under
ignored `tmp/`, rolling storage reconciliation, and documentation.

### Non-goals

No manual dispatch, new variable mutation, broad deletion, schedule enablement,
promotion, or billing inquiry.

### Required context

Read Phase 3's matrix and helper, the exact `UPLOAD BATCH GO`, the sanitized
Gate C ledger, and downloaded artifact checksums/content.

### Execution steps

1. Verify each run's ref, SHA, event, result, serialization, artifact ID/name,
   API bytes, expiry, and restored upload gate from public APIs and the ledger.
2. Inspect every downloaded archive for the complete allowlist, scanner/tool
   metadata, target counts, and required row-specific findings. Treat a URL
   alone as insufficient evidence.
3. Confirm every retained artifact was at most 25 MiB and reconcile wrapper
   overhead against its final gzip measurement.
4. Verify each optional deletion used only the recorded exact ID after a local
   checksummed copy was complete; recompute the rolling envelope between rows.
5. Refresh all public artifacts/caches and identify unexpected PRs, caches,
   artifacts, or ref changes yourself.
6. Update canonical policy, coverage, and status summaries. Publish either
   `SAFE TO REQUEST SCHEDULE BATCH GO` with exact Gate D commands or a concrete
   stop disposition.

### Implementation notes

If the bridge was not authorized because Phase 3 returned `DO NOT AUTHORIZE`,
record controlled uploads and schedule rehearsal as intentionally skipped and
continue to rollback preparation; do not keep requesting approval.

### Validation

Cross-check public/API byte sums, local checksums, archive contents, retained
windows, one-retry calculations, and all evidence dispositions. Run
`git diff --check`.

### Completion criteria

All authorized rows are accepted or have one concrete blocker, all upload gates
are off, and the schedule recommendation requires no operator-written report.

## Phase 5: Verify scheduled cycles and prepare exact restoration

### Workspace

.

### Goal

After Gate D, monitor real cron events agent-side, complete benchmark
dispositions, and prepare the exact Gate E restore package.

### Scope

Public scheduled-run monitoring, cache/artifact accounting, benchmark coverage,
frozen refs/settings, restore manifest, and host helper.

### Non-goals

No unauthorised settings mutation, rerun, upload, cache, App change, merge,
branch deletion, or final decision.

### Required context

Read Gate D's sanitized settings ledger, Phase 4 evidence, all nine workflow
guards, the September 6 review, current coverage tables, and original
main/default/settings ledger.

### Execution steps

1. Poll public APIs until all required runs use the `schedule` event on frozen
   trial refs and execute substantive jobs; record queueing, duration, overlap,
   result, artifacts, caches, findings/package counts, and exact source SHA.
2. Ask only for the Gate D restore command to be run after the public completion
   condition is met. Verify public consequences and consume its sanitized
   settings ledger; do not request a prose confirmation.
3. Classify every benchmark row as reproduced, superseded, false positive with
   evidence, intentionally skipped, or missing. Separate trial acceptance,
   ongoing-installation readiness, and benchmark parity.
4. Reconcile final trial storage and compute under the standing hard stop
   without another billing question.
5. Prepare the exact Gate E restore manifest and host helper for App access,
   queued jobs, variables, defaults, settings, PR disposition, and branch
   protection. Include expected-before and expected-after values and fail on
   drift.

### Implementation notes

Manual dispatch is not cron evidence. If schedules were not authorized, mark the
rows intentionally skipped and preserve that limitation in the final decision
package. Do not claim full parity while a high-priority row is missing.

### Validation

Verify timestamps/events from public metadata, the saved review hash, every
benchmark disposition, every restore target, and the host helper with fixtures.
Run shell validation and `git diff --check`.

### Completion criteria

Scheduled evidence is accepted or explicitly skipped/blocked, and restoration
is reduced to one reviewed operator-side helper invocation.

## Phase 6: Verify rollback and publish the decision package

### Workspace

.

### Goal

After Gate E, independently verify restored state and produce the final
evidence-backed decision package.

### Scope

Public state verification, sanitized restore ledger, residual-state inventory,
and GO/NO-GO/DEFER recommendation.

### Non-goals

No mutation, merge, branch deletion, artifact cleanup, App reactivation,
promotion plan, or billing reconfirmation.

### Required context

Read Gate E's sanitized ledger, Phase 5 restore manifest, recorded main SHAs,
standing baseline, and current public repository state.

### Execution steps

1. Verify original defaults/main SHAs, public PR dispositions, trial refs, and
   branch protections directly. Consume the sanitized ledger for private
   settings that public APIs cannot expose.
2. Inventory residual public artifacts, caches, dashboards, alerts, workflows,
   and history yourself. Record inaccessible private surfaces once without
   asking the operator to inspect them again.
3. Reconcile all acceptance, parity, cost, schedule, credential-boundary, and
   rollback evidence.
4. Publish separate trial-acceptance, ongoing-installation, and benchmark-parity
   conclusions with a GO, NO-GO, or DEFER recommendation.

### Implementation notes

Restoring defaults does not erase repository history or accrued usage. The
standing baseline remains valid unless the operator previously reported a
change.

### Validation

Cross-check public API state, sanitized helper ledgers, every decision criterion,
and all byte calculations. Run `git diff --check`.

### Completion criteria

Rollback is verified or has one concrete exception, and Gate F can be answered
without another research pass or repeated account questionnaire.

## Phase 7: Record the decision and create the authorized next plan

### Workspace

.

### Goal

Record Gate F and, only after `GO`, create a separate promotion plan.

### Scope

Decision documentation and a promotion plan limited to the approved outcome.

### Non-goals

No merge, App/settings mutation, schedule/upload/cache enablement, dependency
upgrade, release, deployment, or claim that `GO` completed installation.

### Required context

Read the exact Gate F response, Phase 6 package, current rollback state, and the
AI Session Handler plan format.

### Execution steps

1. Record `GO`, `NO-GO`, or `DEFER` exactly and preserve the evidence links.
2. For `NO-GO` or `DEFER`, document recoverable state and stop.
3. For `GO`, create a separate plan that publishes the shared preset first,
   removes trial-only wiring through reviewed repo-owned phases, and reactivates
   each repository deliberately with fresh final evidence.
4. Keep ordinary CI artifact policy, exact-ID cleanup rules, credential
   boundaries, and rolling evidence retention in promotion acceptance criteria.

### Implementation notes

The promotion plan must keep one workspace per phase and must not bundle bot
dependency updates with infrastructure promotion.

### Validation

Validate plan structure, links, phase numbering, workspace paths, and decision
wording. Run `git diff --check`.

### Completion criteria

The exact decision is durable. `GO` has a reviewable next plan; `NO-GO` or
`DEFER` leaves execution paused without implying ongoing installation.
