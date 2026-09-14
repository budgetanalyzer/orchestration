# Dependency Automation Phase 12 Operator Plan

**Status:** Bounded zero-spend trial approved on 2026-09-14. Trial branches are
published and the initial Step 4 hosted branch measurements completed. The
operator reconfirmed disabled expansion gates and zero current Actions spend,
then authorized the Step 5 temporary-default orchestration pilot. The
orchestration pre-switch audit, human-administered switch, and Step 5.3
trial-default dry run are complete. Post-run inspection found that a malformed
ruleset branch pattern left `main` unprotected after the switch. Repair and
verify both protected refs before Step 5.4; do not install Mend yet.

This is an interactive operator checklist, outside AI Session Handler, for
[Phase 12](dependency-automation-plan.md#phase-12-observe-activation-and-compare-against-the-saved-review).
[Dependency Automation](../dependency-automation.md) owns policy. Record results
in the [coverage report](../research/dependency-automation-coverage.md).
The plan does not create branches or authorize merges, workflow triggers, or
settings changes; those remain human-owned even when local controls are complete.

## Current session handoff — 2026-09-14

Resume at the **Step 5 protection remediation**, immediately before Step 5.4.
Do not repeat the completed branch measurements, pre-switch audit,
default-branch switch, or successful Step 5.3 dry run.

Completed:

- Step 1 bounded-trial approval is recorded. The operator reconfirmed zero
  current GitHub Actions spend, no payment method, and disabled orchestration
  cache, schedule, and upload gates immediately before Step 5.
- All nine `dependency-automation-trial` refs are published. Step 3 workflow
  controls and local validation are complete.
- Step 4's initial no-upload hosted branch measurements completed successfully
  in all nine repositories. Public metadata showed zero uploaded artifacts. The
  publication-triggered jobs overlapped instead of remaining one at a time; this
  is a recorded process deviation, and all remaining work must be serialized.
- Hosted Renovate run
  [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973)
  passed its structural gates at source/preset ref
  `24ffc8e36bf87a730bb6a25961059becbdb67d72`: 109 dependencies in 37 package
  files, exact trial base, dry-run mutation simulation, and repository result
  `done` without `ERROR` or `FATAL` records. Aqua Security GitHub lookups and
  anonymous Docker Hub pagination remain incomplete; do not call this clean
  lookup acceptance.
- The orchestration pre-switch audit is complete: zero open PRs; Pages absent;
  no deployment, release, environment, reusable-workflow, or `workflow_run`
  surface; the only schedule is trial-gated off; all scoped preset consumers pin
  the explicit trial ref; and Renovate/Mend has no current orchestration access.
- No protection existed initially. The human created active ruleset
  `dependency-automation-trial-protection`, intending to cover both `main` and
  `dependency-automation-trial`, require pull requests, and block deletion and
  force pushes without unavailable required checks. The pre-switch review
  incorrectly accepted its malformed combined branch pattern; the later API
  audit established that only the dynamic default target matched.
- Immediately before handoff, `main` was still the default at
  `dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5`; protected trial head was
  `24ffc8e36bf87a730bb6a25961059becbdb67d72` (eight commits ahead, zero behind).
- The human changed only orchestration's default branch to
  `dependency-automation-trial`. Credential-free post-switch verification at
  `2026-09-14T14:28Z` confirmed that default/trial SHA
  `24ffc8e36bf87a730bb6a25961059becbdb67d72` and `main` SHA
  `dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5` were unchanged. Open PRs and
  issues remained zero, and the newest visible Actions run remained pre-switch
  run `34848193973` from `2026-09-14T13:16:09Z`; no switch-time workflow or
  visible bot activity occurred. The unauthenticated artifact API was rate
  limited, but no post-switch workflow existed that could have uploaded an
  artifact.
- Step 5.3 manual-dispatch run
  [34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322)
  passed on the exact trial/default SHA. Strict config validation and the hosted
  full-dry-run job passed sequentially in 2 minutes 27 seconds. The workflow's
  hard gates establish matching source/preset ref, exact trial base, mutation
  simulation, repository result `done`, and no `ERROR`/`FATAL` records. Both
  upload paths were skipped and the run reported zero artifacts. Existing Aqua
  Security and Docker Hub lookup gaps remain pending.
- Post-run inspection found active rules only on the trial branch and none on
  `main`. Ruleset `dependency-automation-trial-protection` contains
  `~DEFAULT_BRANCH` plus malformed literal pattern
  `refs/heads/"main", "dependency-automation-trial"`; only the dynamic default
  target currently matches. Both branch SHAs remain unchanged, so no drift was
  observed, but the required persistent `main` protection is not effective.

Next actions:

1. **HUMAN:** Edit ruleset `dependency-automation-trial-protection`. Replace the
   malformed combined pattern with separate `refs/heads/main` and
   `refs/heads/dependency-automation-trial` include entries. Keep deletion,
   non-fast-forward, and required-pull-request rules active; do not weaken them.
2. **AI AGENT:** Verify both branches independently receive all three active
   rules and that both SHAs remain unchanged.
3. Install Mend Community only on orchestration after that repair passes; then
   continue Steps 5.4–5.6. Keep schedules, uploads, and optional caches off.

Still pending after the default switch: detailed no-upload report review,
upload-size values, Aqua Security and Docker Hub lookup remediation, App
installation, dashboard/proposals, dependency graph and Dependabot settings,
bot-PR checks, scheduled evidence, benchmark reconciliation, and the final
rollback/merge decision. Uploads must remain disabled until sizes are reviewed.

## Objective and trial modes

Keep the implementation on branches in all nine repositories. Measure hosted
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
`useBaseBranchConfig=merge` can only layer a same-named base-branch config over
a config already discovered on the default branch; it cannot bootstrap this
trial while `main` has no Renovate config. The hosted branch-only dry run instead
loads the reviewed trial `renovate.json` through a generated one-repository
self-hosted wrapper, bypasses onboarding with `requireConfig=optional`, and
forces the exact trial update base. This does not model normal default-branch
config discovery. Neither approach makes GitHub schedules run on a non-default
branch.

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

### Recorded trial decision — 2026-09-14

- **Decision:** `TRIAL GO`; keep `main` as the default branch and defer
  default-only acceptance.
- **Financial boundary:** the operator reports no payment method on GitHub or
  Mend and no paid Mend trial. GitHub's current Actions billing documentation
  states that usage is blocked when an account without a valid payment method
  exhausts its quota. Do not add a payment method during this trial.
- **Mend boundary:** Community remains the selected free service. Public
  documentation still lists one concurrent organization job, approximately
  four-hour scheduling, 1 vCPU, 3 GB memory, 15 GB disk, and a 30-minute timeout.
- **Public artifact observation:** the unauthenticated API was paginated across
  all 15 publicly visible organization repositories at
  `2026-09-14T01:45:30Z`. It returned 1,191 historical artifact records and zero
  unexpired artifacts, for zero currently retained public artifact bytes.
- **Access gap:** private repositories exist, but the observed authenticated UI
  did not provide a practical per-artifact inventory. Private retained bytes and
  upload headroom therefore remain unknown. This can block trial uploads but
  cannot create a charge under the confirmed no-payment-method boundary.
- **Trial cap:** one hosted job at a time; schedules and uploads initially off;
  at most one concurrently retained 25 MiB evidence bundle with one-day
  retention after measurement and review.
- **Review/expiry:** review this approval by `2026-09-21`; any larger retained
  total, paid feature, payment method, or continuation beyond that date requires
  a new operator decision.

This decision establishes the cost guardrail only. Package visibility, required
Maven secret names, rollback settings, workflow controls, preset resolution, and
hosted behavior still require their separately listed evidence.

## Step 2: Prepare branches and the rollback ledger

**Owner: HUMAN** for git/publication; **AI AGENT** for diff review.

The executable
[trial-ref and ignore remediation plan](dependency-automation-trial-ref-and-ignore-remediation-plan.md)
has corrected the focused preset-reference and `.gitignore` defects locally.
Human clean-history review and publication remain pending before the broader
Step 3 workflow adaptations can run remotely.

Use the exact branch name `dependency-automation-trial` in all nine repositories.
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

1. Refresh status, upstream, and outgoing-history inspection in every checkout.
   Old ahead counts and dirty-file notes are historical. Preserve unrelated work
   and stage explicit paths.
2. Verify `.ai-session-handler/**` is ignored and absent from **all history being
   published**, not only the tip. Deleting transcripts in a later commit does
   not remove earlier outgoing copies. The operator owns clean-history work.
   Preserve the actual implementation and saved research.
3. Record original default branches, `main` SHAs, trial SHAs, workflow states,
   rulesets, App scope, security settings, and integrations in a rollback ledger.
4. Publish orchestration's trial preset before consumers. All nine trial configs
   should use
   `github>budgetanalyzer/orchestration//renovate-presets/default#dependency-automation-trial`.
   Verify resolution with the pinned validator/hosted lookup, record the resolved
   preset SHA, and freeze the ref during each evidence batch.

Do not push before Step 3's trigger/upload controls are reviewed. Publication
moves trial refs only. Verify the recorded `main` SHAs afterward.

## Step 3: Implement the trial workflow controls in each owning repo

**Owner: AI AGENT in the owning context**, followed by human publication.

**Local implementation status:** Complete. All nine repositories now carry the
exact trial push/base guards, disabled-by-default repository-variable gates,
cache-disabled initial measurement, capped one-day sealed uploads, and local
workflow documentation. The five Java repositories use generation-only Gradle
graphs until both the graph-submission variable is enabled and the protected
trial ref is the current default. On 2026-09-14, Node 24 strict Renovate
validation and local extraction, `actionlint`, `bash -n`, ShellCheck, helper
smoke validation, and the local event/ref case review passed. Hosted execution
and human publication remain separate evidence below.

The completed control set is listed below. Read local instructions and keep the
nearest dependency-automation docs aligned with any later change.

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
   generate a one-repository self-hosted wrapper from the exact checked-out trial
   `renovate.json`, use `requireConfig=optional`, force the exact trial base, and
   preserve all repository extraction rules. A checkout ref,
   `baseBranchPatterns`, or `useBaseBranchConfig=merge` alone does not bootstrap
   a config absent from `main`. Prove the config/source/preset SHAs in debug logs.
   Keep `--dry-run=full`, read-only ephemeral job-token permissions, and no
   credentials in agent output. Fail the job unless extraction, trial-base
   selection, dry-run mutation simulation, and `Repository result: done` are all
   present; also fail on Renovate `ERROR` or `FATAL` records even when its process
   exits zero.
8. Run strict Renovate validation and `actionlint`. For changed shell scripts
   run `bash -n` and `shellcheck`. Review manual trial, scheduled trial, PR into
   trial, ordinary main, and unrelated-ref cases. Verify no publishing or
   privileged submission jobs execute on dependency PRs.

New manual workflows may need a reviewed branch push for their first run.
GitHub documents default-branch registration and API/CLI dispatch after a workflow
has run; verify actual discovery instead of assuming `--ref` bootstraps it.
Do not merge a bootstrap workflow to `main` or use `pull_request_target`.

For the orchestration workflow, GitHub does not display **Run workflow** while
`dependency-automation-config.yml` exists only on the non-default trial branch.
The UI-independent fallback is a reviewed push to the exact trial branch whose
head commit message contains `[run-hosted-renovate-dry-run]`. The push must change
the configuration workflow, `renovate.json`, or `renovate-presets/**` so the
workflow's path filter admits it. This marker starts the same read-only full dry
run and suppresses the exact-image measurement for that push, preserving the
one-job-at-a-time trial boundary. An unmarked push still runs validation but not
the hosted dry run. The marker grants no write permission and must not appear in
ordinary commits.

## Step 4: Measure hosted behavior before expanding

**Owner: HUMAN** triggers; **AI AGENT** reviews sanitized results.

1. Validate and run the read-only full Renovate dry run against orchestration's
   trial input. Retain preset resolution, extraction, lookup, simulated file
   changes, duration, and failures. Prefer **Run workflow** with
   `run_hosted_dry_run=true` when GitHub exposes it. While the workflow remains
   absent from `main`, use the exact commit-message fallback documented above;
   the resulting push run is the operator-triggered run. A green workflow that
   reports `disabled-no-config`, performs zero extraction/lookups, or lacks
   dry-run mutation records is a failed measurement, not acceptance.
2. Run smaller audits first: frontend `dependency-audit.yml` and ext-authz
   `go-vulnerability-check.yml`. Then run orchestration
   `exact-image-security-evidence.yml` and workspace
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

### Recorded Step 4 disposition and Step 5 authorization — 2026-09-14

- All nine trial refs are published. Public run metadata records successful
  branch executions for the frontend audit, Go vulnerability check,
  orchestration and workspace image evidence, all five Java builds, and all five
  generation-only Java graph jobs. The relevant runs uploaded no artifacts.
- Orchestration's successful full dry run used source and preset ref
  `24ffc8e36bf87a730bb6a25961059becbdb67d72`, extracted 109 dependencies from
  37 package files, selected the exact trial base, simulated dry-run mutations,
  and returned `Repository result: done` without `ERROR` or `FATAL` records.
  Aqua Security GitHub lookups and anonymous Docker Hub pagination remained
  incomplete and must not be reported as clean lookup acceptance.
- The initial publication-triggered measurement jobs overlapped across
  repositories instead of honoring the one-hosted-job-at-a-time trial rule.
  Preserve this as a process deviation; do not repeat successful runs merely to
  make their timing sequential. Serialize all remaining trial work.
- The operator reconfirmed that orchestration's trial cache, schedule, and upload
  gates are off and that current GitHub Actions billing is zero. Upload sizing
  remains pending and uploads must stay disabled until it is reviewed.
- The operator authorized the temporary-default orchestration rehearsal. This
  is not the default-branch change itself: complete Step 5.1, preserve `main`
  protection, and require the human administrator to perform and verify the
  switch.

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

### Orchestration pre-change audit — 2026-09-14

Public repository and checkout evidence currently establishes:

- `main` remains the default at
  `dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5`; the trial ref is
  `24ffc8e36bf87a730bb6a25961059becbdb67d72`, eight commits ahead and zero
  behind `main`.
- The repository has zero open pull requests. Changing the default will
  therefore change the suggested base for future PRs but will not retarget an
  existing PR.
- No workflow uses `workflow_run`, `workflow_call`, a GitHub Environment, Pages,
  package publication, release publication, or deployment. Existing release
  tags are repository history, not an active workflow integration.
- The only schedule is the exact-image scanner. Its trial schedule requires
  `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED == 'true'`, which the operator
  confirmed is off. Do not manually dispatch it during the one-job pilot.
- All nine scoped Renovate configurations reference the explicit
  `#dependency-automation-trial` preset ref. Cross-repository documentation
  links generally pin `blob/main`, so they continue to resolve; generic links
  to the repository root will temporarily display trial content. The only local
  unrefed preset consumer discovered was `budget-analyzer-api-tests`, whose
  `renovate.json` returned HTTP 404 on its public `main` ref and is not a
  published consumer.
- The repository has no checked-in Dependabot configuration. Renovate remains
  the intended sole update-PR owner, but installed Apps, repository security
  settings, Pages settings, webhooks, environments, and rulesets are
  administrator-only state and cannot be inferred from the checkout.

The operator reported that no repository rulesets or classic branch-protection
rules exist. There is no dynamic default-branch rule to migrate, but the trial
ref was initially unprotected and did not satisfy Step 5.2. The human
administrator then activated `dependency-automation-trial-protection`, intending
to target both `main` and `dependency-automation-trial`, block deletion and force
pushes, and require pull requests without unavailable status checks. Record
the current installed-App scope and confirm that Renovate/Mend cannot act before
the intended post-switch installation. This administrator-only App-scope check
was completed: the operator confirmed that Renovate/Mend had no access to
orchestration. Immediately before the switch, public refs still showed `main` as
default at `dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5` and the trial at
`24ffc8e36bf87a730bb6a25961059becbdb67d72`. The review treated the intended
dual-branch target as effective and left the default change as the next
human-administered action. Post-run inspection established that this protection
conclusion was incorrect because the explicit combined branch pattern was
malformed.

### Orchestration post-switch verification — 2026-09-14

The human administrator reported changing only the default branch to
`dependency-automation-trial`. Credential-free Git and public HTML checks at
`2026-09-14T14:28Z` verified:

- `HEAD` advertises `dependency-automation-trial` at
  `24ffc8e36bf87a730bb6a25961059becbdb67d72`;
- `main` remains at `dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5`;
- open pull requests and open issues remain zero; and
- the newest visible Actions run remains successful pre-switch dry run
  [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973),
  started at `2026-09-14T13:16:09Z` on the trial SHA.

The default change therefore produced no workflow run, PR, issue, or visible bot
activity. Since there was no post-switch workflow, there was no new run that
could upload an artifact. GitHub's unauthenticated artifact API returned the
shared-IP rate-limit response during verification, so direct artifact inventory
is recorded as unavailable rather than inferred from an authenticated view.
Step 5.3 manual-dispatch run
[34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322)
subsequently passed on this exact source/default revision. Both jobs succeeded
sequentially in 2 minutes 27 seconds, the workflow's structural hard gates
passed, both upload paths were skipped, and GitHub reports zero run artifacts.

Post-run ruleset inspection nevertheless blocks Step 5.4. The active ruleset's
conditions include `~DEFAULT_BRANCH` and malformed literal pattern
`refs/heads/"main", "dependency-automation-trial"`. The trial branch currently
receives deletion, non-fast-forward, and pull-request rules only because it is
default; `main` receives none. Both SHAs remain unchanged. Repair the include
conditions to separate explicit branch refs and verify both rule sets before
installing Mend.

## Step 6: Expand and collect full rehearsal evidence

**Owner: HUMAN**, with **AI AGENT** evidence review.

1. Repeat the default/settings audit per consumer before expanding App access.
   Restrict access to the nine scoped repos. Verify trial/main/preset SHAs and
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
5. Retain complete manual reports for all four scanners and real bot-PR
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
   The dry-run push fallback has no persistent switch: stop using its exact
   commit-message marker and it remains dormant.
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
   activation timing are accepted. Remove both temporary
   `[run-hosted-renovate-dry-run]` clauses: the push arm in
   `dependency-automation-config.yml` and the matching exact-image suppression.
   Retain `workflow_dispatch`; once the workflow exists on the restored default
   branch, GitHub exposes the normal **Run workflow** control.
2. Merge orchestration's shared preset to its restored default first, then
   consumers with the normal preset reference. Include no bot dependency changes,
   unrelated work, or execution transcripts.
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
