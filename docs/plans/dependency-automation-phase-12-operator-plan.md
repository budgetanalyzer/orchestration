# Dependency Automation Phase 12 Operator Plan

**Status:** Mend account created (operator report). Branch rehearsal design is
prepared; workflow adaptations, billing verification, publication, and hosted
evidence remain pending.

This is an interactive operator checklist, outside AI Session Handler, for
[Phase 12](dependency-automation-plan.md#phase-12-observe-activation-and-compare-against-the-saved-review).
[Dependency Automation](../dependency-automation.md) owns policy. Record results
in the [coverage report](../research/dependency-automation-coverage.md).
This revision updates documentation; it does not implement workflow changes,
create branches, or authorize merges or settings changes.

## Objective and trial modes

Keep the implementation on branches in all ten repositories. Measure hosted
builds/scans, report sizes, cache use, billing, and Mend limits before deciding
whether to merge into `main`. Approving a bounded trial and accepting ongoing
operation are separate decisions. Account creation satisfies only account
creation; it does not verify the free tier, billing, or package access.

A full rehearsal without merging into `main` is possible if the operator accepts
temporarily making the trial branch each repository's default. If `main` must
remain default throughout, run the branch checks and defer default-only
acceptance. The operator chooses before any default-branch changes; silence is
not consent.

| Capability | Trial branch; main remains default | Trial branch temporarily default |
| --- | --- | --- |
| Shared preset | Publish and reference an explicit trial ref | Same; no merge needed |
| Builds, scanner logic, output sizing | Scoped branch push/PR triggers | Scoped triggers and normal manual dispatch |
| New manual workflow discovery | Do not assume dispatch with a ref bootstraps a branch-only file | Workflow exists on default; normal registration |
| Read-only full Renovate dry run | Explicit trial base/config overrides and verified logs | Normal default discovery; verify trial SHA |
| Mend onboarding, dashboards, real PRs | Branch config alone is insufficient; normal discovery reads default | Normal onboarding; PRs target trial default |
| Java graph generation | Reviewed branch code can resolve/generate; non-default submission does not prove default alert behavior | Submit against actual trial default and inspect alerts |
| Actual GitHub cron execution | Deferred; schedules run only on default | Real scheduled cycles can be tested |

Sources: GitHub [workflow events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows),
Renovate [preset refs](https://docs.renovatebot.com/config-presets/),
[baseBranchPatterns](https://docs.renovatebot.com/configuration-options/#basebranchpatterns),
and [useBaseBranchConfig](https://docs.renovatebot.com/configuration-options/#usebasebranchconfig).
Selecting update bases does not bootstrap a missing default-branch config.
`useBaseBranchConfig=merge` layers branch config over default config. Neither
setting makes GitHub schedules run on a non-default branch.

## Ownership and boundaries

- **HUMAN:** all git operations, workflow triggers, account/billing/security
  settings, App scope, default-branch changes, credentials, and final decisions.
- **AI AGENT:** local preparation in the owning repo context, public research,
  sanitized evidence review, and documentation. No sibling service logic changes.
- Credentials stay in GitHub/Mend or the operator's trusted environment. Never
  provide tokens, cookies, secret values, or credential exports to an agent.
- Keep Renovate the sole update-PR owner and automerge off. No dependency update
  merges, release tags, package/image pushes, live API tests, or deployment.
- Use Mend Community and standard public-repository GitHub runners. No paid
  subscriptions, trial conversions, larger runners, or paid cache expansion.
- Branches do not isolate billing, credentials, issues, alerts, artifacts, or
  caches. App access is repository-wide, not restricted to a branch.

## Step 1: Verify the account and approve a bounded trial

**Owner: HUMAN**, with public inventory/projections prepared by the agent.

1. Use the existing Mend profile to verify Community in the
   [Developer Portal](https://developer.mend.io/). Review current
   [limits](https://docs.renovatebot.com/mend-hosted/overview/),
   [App permissions](https://github.com/apps/renovate), and
   [credential support](https://docs.renovatebot.com/mend-hosted/credentials/).
   Previously documented limits were one concurrent organization job, roughly
   four-hour cycles, 1 vCPU, 3 GB RAM, 15 GB disk, and a 30-minute timeout.
   Record current values; enhanced OSS resources must not be prerequisites.
2. Confirm administrator access and public repo visibility. Inspect
   [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
   and [Packages billing](https://docs.github.com/en/billing/concepts/product-billing/github-packages).
   Record plan, billing dates, included allowance, current/accrued usage, package
   visibility, payment-method state, and effective spend-stopping controls.
   Notification-only budgets are insufficient. Check caches separately from
   pooled artifact/Packages storage; do not enable paid cache expansion.
3. Inventory unexpired artifacts across the organization, including non-trial
   repos: names, `size_in_bytes`, creation/expiry, totals, observation time,
   pagination, and access gaps. Public APIs may not expose everything; the
   operator supplies sanitized authenticated inventory where necessary.
   Retained bytes are not the accrued billing total.
4. Confirm by name only that `SERVICE_COMMON_PACKAGES_USERNAME` and
   `SERVICE_COMMON_PACKAGES_READ_TOKEN` exist in the four Java consumers.
   Public Maven packages still require authentication to install.
5. Record dated `TRIAL GO` or `NO-GO`, trial mode, maximum retained bytes, and
   review/expiry date. Initial policy: one hosted job at a time, uploads and
   schedules off, then at most one 25 MiB evidence bundle per measurement run
   with one-day retention. Lower the cap if headroom requires it. Every increase
   needs an operator decision supported by measurements. Per-run caps do not
   replace account controls or a total trial allowance.

Free hosting has no perpetual-free guarantee. Self-hosting would require a
separate decision. No-go stops hosted work; local preparation can continue.
Unknown local output sizes call for a bounded measurement run, not a merge.

## Step 2: Prepare branches and the rollback ledger

**Owner: HUMAN** for git/publication; **AI AGENT** for diff review.

Use the exact branch name `dependency-automation-trial` in all ten repositories.
Use the same name in workflow triggers, trusted-ref guards, preset references,
and the rollback ledger. Include the complete prepared repository state needed
by CI.

| Repository | Trial workloads |
| --- | --- |
| orchestration | Shared preset, validator/full dry run, exact-image evidence, relevant PR checks |
| service-common | Renovate, build/tests, dependency graph |
| currency-service | Renovate, build/tests/Maven access, dependency graph |
| permission-service | Renovate, build/tests/Maven access, dependency graph |
| transaction-service | Renovate, build/tests/Maven access, dependency graph |
| session-gateway | Renovate, build/tests/Maven access, dependency graph |
| budget-analyzer-web | Renovate, build, npm audit |
| ext-authz | Renovate, build, govulncheck |
| workspace | Renovate, workspace build/Trivy evidence |
| budget-analyzer-api-tests | Renovate, installed-environment Python audit; no live tests |

1. Refresh status, upstream, and outgoing-history inspection in every checkout.
   Old ahead counts and dirty-file notes are historical. Preserve unrelated work
   and stage explicit paths. The API-test trial must include the complete
   prepared `initial-import` state or a reviewed equivalent; its eventual merge
   path into `main` can remain undecided.
2. Verify `.ai-session-handler/**` is ignored and absent from **all history being
   published**, not only the tip. Deleting transcripts in a later commit does
   not remove earlier outgoing copies. The operator owns clean-history work.
   Preserve the actual implementation and saved research.
3. Record original default branches, `main` SHAs, trial SHAs, workflow states,
   rulesets, App scope, security settings, and integrations in a rollback ledger.
4. Publish orchestration's trial preset before consumers. All ten trial configs
   should use
   `github>budgetanalyzer/orchestration//renovate-presets/default#dependency-automation-trial`.
   Verify resolution with the pinned validator/hosted lookup, record the resolved
   preset SHA, and freeze the ref during each evidence batch.

Do not push before Step 3's trigger/upload controls are reviewed. Publication
moves trial refs only. Verify the recorded `main` SHAs afterward.

## Step 3: Implement the trial workflow controls in each owning repo

**Owner: AI AGENT in the owning context**, followed by human publication.

These are prerequisites still to implement; read local instructions and update
nearest dependency-automation docs with each change.

1. Add exact trial-branch push triggers for initial measurement where needed.
   Extend relevant `pull_request.branches: [main]` builds to accept the trial
   **base**, so real Renovate PRs receive checks. Keep snapshot/release publishing
   workflows outside these changes. Never globally replace `main`.
2. All five Java submission jobs currently require
   `github.ref == 'refs/heads/main'`. Preserve production behavior and add a
   narrowly gated path for the exact protected trial ref. Full-rehearsal
   submission must also verify it is the current default. Never submit from PR
   merge refs or arbitrary dispatch refs. With `main` still default, use Gradle's
   standard generation-only path. Preserve separate package-read and submission
   tokens, complete dependency resolution, and strict failure behavior.
3. Gate trial schedules, uploads, and automatic graph submission with repository
   variables, all off when unset. Guard trusted jobs by event and exact ref too.
   Changing defaults must not start privileged or uploading jobs before review.
4. Add a measurement mode that performs the complete build/scan, measures the
   exact upload paths, and reports bytes/compression estimates in the job summary
   with uploads off. Include failure output. Full reports remain runner-local
   until a later permitted upload; size-only evidence is not scan acceptance.
5. Enforce a total per-run upload cap before every upload, including failure
   paths. Bound the exact allowlist conservatively using uncompressed size plus
   archive overhead, or upload only a measured sealed archive with overhead
   headroom. Start at Step 1's cap and one-day retention. Exclude image layers,
   scanner databases, dependency caches, and unrelated files. If the complete
   bundle exceeds the cap, skip upload and report an evidence-delivery failure;
   do not silently trim findings or claim complete acceptance.
6. Include bot-PR JARs, test results, frontend builds, and action-generated graph
   artifacts in the controls. Inspect action defaults for implicit uploads and
   cache saves. Disable optional caches for initial measurement, then measure the
   intended normal cache behavior separately. The workspace job uploads reports
   and build logs, not its Docker image; runner-local layers are not artifacts.
7. For orchestration's GitHub-platform dry run while `main` remains default,
   explicitly configure supported trial base/config overrides and preserve all
   repository extraction rules. A checkout ref alone does not retarget Renovate.
   Prove the config/source/preset SHAs in debug logs. Keep `--dry-run=full`,
   read-only ephemeral job-token permissions, and no credentials in agent output.
8. Run strict Renovate validation and `actionlint`. For changed shell scripts
   run `bash -n` and `shellcheck`. Review manual trial, scheduled trial, PR into
   trial, ordinary main, and unrelated-ref cases. Verify no publishing or
   privileged submission jobs execute on dependency PRs.

New manual workflows may need a reviewed branch push for their first run.
GitHub documents default-branch registration and API/CLI dispatch after a workflow
has run; verify actual discovery instead of assuming `--ref` bootstraps it.
Do not merge a bootstrap workflow to `main` or use `pull_request_target`.

## Step 4: Measure hosted behavior before expanding

**Owner: HUMAN** triggers; **AI AGENT** reviews sanitized results.

1. Validate and run the read-only full Renovate dry run against orchestration's
   trial input. Retain preset resolution, extraction, lookup, simulated file
   changes, duration, and failures.
2. Run smaller audits first: frontend `dependency-audit.yml`, ext-authz
   `go-vulnerability-check.yml`, API-test `python-dependency-audit.yml`.
   Then run orchestration `exact-image-security-evidence.yml` and workspace
   `workspace-image-security-evidence.yml`, one at a time. No live cluster,
   image start/push, or package publication is needed.
3. Run all five Java builds and complete graph generation with existing Maven
   access. Measure JAR/test/graph output. A preflight, ordinary green build, or
   partial snapshot is insufficient proof of a complete remotely resolved graph.
4. Review sizes before enabling each capped upload. Query every artifact in the
   run; record total actual `size_in_bytes`, retention, expiry, and producer.
   Retain complete sanitized reports before one-day expiry. No-upload runs prove
   sizing/operation only where their logs support it, not detailed scan parity.
5. Recalculate trial and steady-state use:
   `sum(bytes / 2^30 * retained_hours)` GiB-hours, plus existing accrual and
   expected organization use. Include retries, overlapping runs, bot-PR builds,
   and graph artifacts. Project intended seven-day retention separately from
   one-day trial retention. Report cache allowance/use separately.
6. Review refreshed billing after reporting delay; GitHub currently documents
   6–12 hours for artifact usage. Deletion stops future accrual but does not erase
   past usage. Keep cron and App expansion off until measured headroom passes.

The operator can stop here without any merge. If `main` stays default, report
branch results and pending default-only checks. Continue to Step 5 only after
the operator selects the temporary-default full rehearsal.

## Step 5: Pilot orchestration with the trial branch as default

**Owner: HUMAN.** This changes repository administration, not `main` history.

1. Audit new PR bases, existing PRs, rulesets/required checks, environment
   restrictions, Pages/release integrations, consumers following default refs,
   schedules, `workflow_run` chains, and other bots. Preserve main protection and
   apply equivalent relevant protection to the trial. Record settings to restore.
   Pause unrelated publishing/deployment paths that could follow the new default;
   do not dispatch publish workflows.
2. Verify schedule/upload/submission gates are off, choose a window away from
   cron, and set orchestration's default to the protected trial. Verify main SHA.
3. Manually validate/dry-run the trial default. Prove actual default, source,
   selected base, and preset agree.
4. Install Mend Community only on orchestration. Verify tier/permissions, enable
   dependency graph/Dependabot alerts, grant alert-read access where available,
   and disable competing Dependabot update PRs.
5. Verify normal onboarding, resolved policy, dashboard, proposal bases,
   representative real bot-PR checks, queueing, timeouts, and lookup errors.
   Any required onboarding/config merge targets the trial branch and remains
   human-owned. No dependency update is merged.
6. Confirm routine schedules/limits, approval gates for major/chart/stateful/
   platform/checksum changes, maintained-line updates, digest/flavor preservation,
   vulnerability behavior, no automerge, and no first-party promotion.

Vulnerability-fix proposals can bypass routine PR limits/schedules; those are
not cost caps. Keep upload controls effective and pause App access if load exceeds
the trial allowance. Do not expand after wrong PR bases, timeouts, or unresolved
policy/lookup errors.

## Step 6: Expand and collect full rehearsal evidence

**Owner: HUMAN**, with **AI AGENT** evidence review.

1. Repeat the default/settings audit per consumer before expanding App access.
   Restrict access to the ten scoped repos. Verify trial/main/preset SHAs and
   proposal bases in each.
2. Try App-token Maven host rules first. If necessary, the operator stores an
   existing scoped credential in supported Mend settings and references secret
   placeholders. Never commit plaintext or repository-config encrypted secrets.
3. Enable/manual-run graph submission on each trusted trial default, in order:
   service-common, currency-service, permission-service, transaction-service,
   session-gateway. Retain complete application/runtime/test graphs, actual
   ref/SHA, and GitHub acceptance per repo. Inspect internal coordinates and
   inherited Spring/Security/Jackson/Tomcat/Netty as applicable. The reactive
   gateway requires Reactor Netty/Netty/Lettuce, not Tomcat. An incomplete
   87-coordinate snapshot or green generator alone is insufficient.
4. Verify graph-backed alerts separately from update discovery. Record default
   ref and refresh timing; alert processing may be asynchronous.
5. Retain complete manual reports for all five scanners and real bot-PR
   checks/package access. Reuse earlier evidence only when source/config and
   relevant behavior match; rerun checks affected by changes.
6. After measured headroom passes, enable schedules deliberately one workload at
   a time. Observe two successful Mend cycles per repo and one actual scheduled
   run for every scheduled scanner and Java graph workflow. A skipped job, manual
   dispatch, local run, or dry run is not cron evidence. Weekly schedules and
   Community queueing can require multiple days.
7. Record durations, errors, cache use, artifact bytes/expiry, and refreshed
   billing for scheduled and PR runs. Preserve failures; do not omit dependencies
   or buy a workaround to satisfy the trial.

## Step 7: Pause, restore, and make the merge decision

**Owner: HUMAN** for rollback; **AI AGENT** for assessment.

Perform this pause after success, failure, or an early stop:

1. Pause/remove trial App access first; disable trial schedules/submissions/
   uploads. Confirm the stop and cancel queued/running trial jobs before restoring
   defaults so bots/jobs cannot act unexpectedly on restored refs.
2. Export sanitized evidence and record artifact IDs/expiry. Close trial PRs
   explicitly as appropriate. Keep branch work recoverable. Delete only
   operator-selected trial artifacts/caches after export if needed; deletion
   cannot erase accrued billing.
3. Restore original defaults and changed settings/integrations from the ledger.
   Verify main SHAs, default refs, App scope, workflow state, and remaining
   schedules. Restore unrelated automation only to its recorded prior state.
4. Allow graph/alert state to refresh and record residual issues, PR history,
   alerts, artifacts, and caches. Default restoration does not erase repo-wide
   state. Retain explicit preset refs on trial branches so they remain resolvable.

Report **trial acceptance**, **ongoing installation**, and **benchmark parity**
separately. Ongoing installation remains pending after a paused trial. Assign
each deferred check passed/failed/pending with evidence. Assign each historical
baseline/advisory exactly one classification: reproduced, superseded by a newer
applicable finding, false positive with evidence, or missing.

Preserve Redis/Temurin/controller inventory gaps, offline Istio `image: auto`,
checksum/ARM64 limits, and workspace Node 24 as an operator-applied baseline.
The historical review must retain SHA-256
`3c0c4075e021884227d5ecbd0861a9c4f18471e184b8fbbf8cecc1ac8014c347`.

The merge recommendation includes measured bytes/durations, normal-retention
and bot-PR volume projections, billing evidence, Mend queue/timeout results,
coverage gaps, and a reviewable promotion diff. `NO-GO` or `DEFER` leaves the
implementation on branches and automation paused. Passing tests is not merge
approval.

## Step 8: Promote only after explicit operator approval

**Owner: HUMAN**, after reviewing the concrete results and promotion diff.

1. Prepare the final diff: remove trial refs/triggers and temporary gates as
   appropriate, restore intended retention, and keep useful durable cost controls.
   Validate affected behavior. Keep final schedules disabled until costs and
   activation timing are accepted.
2. Merge orchestration's shared preset to its restored default first, then
   consumers with the normal preset reference. Resolve the API-test integration
   path explicitly. Include no bot dependency changes, unrelated work, or
   execution transcripts.
3. Verify final preset resolution, trusted-ref guards, onboarding, package access,
   graph acceptance, PR checks, and scheduled behavior after reactivation.
   Trial evidence carries forward only where behavior is unchanged; changed
   refs/configuration and main-push paths need fresh evidence.
4. Declare ongoing installation complete only after required hosted checks pass
   on the final configuration. Report benchmark parity independently.

## Evidence handoff

Provide sanitized results after each operator batch:

```text
Repository and trial mode:
Original/current default branch:
Main SHA before/after:
Trial source SHA and resolved preset SHA:
Action/workflow, event, and actual ref:
Started/completed UTC and duration:
Public or sanitized URL:
Result: passed | failed | pending | skipped
Complete graph/scan/proposal evidence:
Artifact IDs, bytes, retention, expiry:
Cache usage and billing observation time:
Warnings, missing evidence, next operator action:
```

Never include secret values, authorization headers, cookies, job tokens,
encrypted credential payloads, or raw private configuration.
