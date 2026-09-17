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
because Renovate vulnerability alerts ignore the top-level PR limit. The shared
limit correction was published and validated, and the operator requested all
seven B4 cycles. Six completed green. `workspace` alone reported a package
lookup warning for `aquasecurity/setup-trivy`; workspace PR #9 published the
narrow public-Git-tag fallback, its automatic corrective cycle refreshed the
Dashboard without a repository problem, and image-evidence run 35098592885
passed with zero artifacts. Batch B and its agent checkpoint are complete. The
workspace pull-request evidence trigger was published through PR #10 at
`09ee0a2afecc2af6c3a216b225537c680ef68848`; pull-request run 35100312719
passed. Post-merge push run 35100778569 was still in progress when the operator
explicitly accepted its success as a Batch C starting assumption and requested
no further wait; the Phase 1 public refresh later confirmed that it completed
successfully. Batch C then passed with four routine Renovate PRs targeting the
trial branch, four successful representative workflows, disabled automerge, no
Actions cache entries for the PR refs, and zero retained artifacts. Preserve
all four routine PRs and the six existing security PRs open and unmerged. The
Phase 12 completion Phase 1 refreshed public state at
`2026-09-16T17:05:13Z`. Defaults and recorded main/trial SHAs remain stable,
but frontend security PR #120 has a failed Build run at `npm ci`. Public
inventory also now contains 502,562,266 non-expired artifact bytes, almost all
from ordinary seven-day Java build artifacts, while all nine public cache
inventories remain empty. Public inspection subsequently confirmed that #120
changes only `package.json` from Vitest 3 to 4 without updating
`package-lock.json` or the grouped Vitest companion packages, making the
`npm ci` rejection deterministic. The operator identified the PR as an
accidental trial-variable side effect and accepted it as non-representative;
routine PR #122 passed the same Build workflow. Preserve #120 open and unmerged
until rollback, but do not rerun or repair it for trial acceptance. Completion
Phase 2 subsequently accepted the zero-spend boundary and completed the five
exact no-upload rows. Four rows report `upload_allowed=true`; orchestration
reports `false` because its 74,178,560-byte temporary tar remains part of the
old helper gate even though its final gzip is 7,945,624 bytes. Phase 3 now
corrects that helper, adds retained-size enforcement, and prepares the
serialized Gate C host bridge. Private usage is recorded once as `unknown`, and
schedules remain behind their later explicit gate. A fresh
all-public-repository inventory at
`2026-09-17T04:56:48Z` returned the same total and zero caches. Eight obsolete
deploy-unconsumed `app-jar` artifacts account for 501,224,156 bytes. Their
regular-CI removal and failure-only one-day JUnit retention were merged only to
the four exact `dependency-automation-trial` refs. At
`2026-09-17T05:25:38Z`, public APIs confirmed the eight IDs absent, a
1,338,110-byte public residual, zero caches, and unchanged recorded `main` SHAs.
This preserves rollback but does not activate the correction on `main`, which
may recreate `app-jar` before promotion. The completion plan applies the
corrected rolling-storage model directly instead of creating a second
remediation meta-plan. The helper correction was subsequently published at
`6a6bf33fb019825b7709693a1b103c8a1dd7d726`; run `35187741819` passed at that
SHA with zero artifacts, and `main` remained unchanged. At
`2026-09-17T10:55:04Z`, the final Phase 2 refresh reconfirmed all 15 public
repositories, 9 artifacts totaling 1,338,110 bytes, zero caches, no `app-jar`,
all eight deleted IDs absent, and unchanged recorded branch SHAs. Uploads remain
unauthorized pending publication of the reviewed Phase 3 commit and the exact
Gate C phrase. The `2026-09-17T11:55:40Z` refresh found the same public state;
the conservative rolling peak is 55,097,576 bytes with 469,190,424 public bytes
remaining before private usage. Private artifact and package usage stays
explicitly `unknown`.

This is the human operator checklist for
[Phase 12](dependency-automation-plan.md#phase-12-observe-activation-and-compare-against-the-saved-review).
[Dependency Automation](../dependency-automation.md) owns policy, and the
[coverage report](../research/dependency-automation-coverage.md) owns detailed
evidence. Batches A-C are complete; the
[Phase 12 completion plan](dependency-automation-phase-12-completion-plan.md)
owns the remaining cost, upload, schedule, rollback, and decision sequence.
This file deliberately avoids repeating execution transcripts.

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
| `orchestration` | `57089578957bae3da42587a7e2902727c5473149` | `c9e6f31208a5f668fcccd3e7ff2fea649654443c` | Manual pilot passed; alert-limit correction published and validated |
| `service-common` | `f31557761b80f17ce8fadc128e273b21b4fd07fe` | `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94` | Manual batch passed |
| `currency-service` | `aa432316849c9231389f8a844325dcf0d64f7335` | `93da3e3599e71cfa453ed78d41691fdfd1edadc3` | Batch C PR #87 passed; graph has 314 packages and 108 alerts |
| `permission-service` | `f2d9d55b149c1f3a00e7f2edd85bafe01a46c5f1` | `a31e7c5880a3d3e742e7224297e8226d9e7a47ff` | B4 green: 236 packages, 54 alerts |
| `transaction-service` | `ccc459f9ea954296a4d1cea6cdbc4b3acf994e6a` | `aa439d27aec63031ab056d4f4afe70cc43e13cca` | B4 green: 238 packages, 54 alerts |
| `session-gateway` | `a37c7a0bb832b857d3d7371e521ac82e99fc3b93` | `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5` | B4 green: 241 packages, 78 alerts |
| `budget-analyzer-web` | `b6f0d23c38428daf8412ae055ccbc9db89ac9517` | `2cbef3f17f546fe167628b221a1cb9dec810c2bd` | Batch C PR #122 passed; malformed accidental security PR #120 is explicitly dispositioned and retained unmerged until rollback |
| `ext-authz` | `917eae9c782b4b1c4d576258883c3e558a7d55a1` | `75ed2bda4de7460332a8dea656def0459064753f` | Batch C PR #3 passed; one security PR retained |
| `workspace` | `383efc840832d474cd9d60e0368ed2ded828e03c` | `09ee0a2afecc2af6c3a216b225537c680ef68848` | Batch C PR #11 image-evidence run passed; post-merge run 35100778569 publicly confirmed successful |

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

**Completed on 2026-09-16.** The shared
`dependency-automation-trial` preset now publishes
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

This prerequisite passed through
[PR #62](https://github.com/budgetanalyzer/orchestration/pull/62) at
`c9e6f31208a5f668fcccd3e7ff2fea649654443c`.
[Dependency Automation Configuration run 35095610585](https://github.com/budgetanalyzer/orchestration/actions/runs/35095610585)
and
[Exact Image Security Evidence run 35095610628](https://github.com/budgetanalyzer/orchestration/actions/runs/35095610628)
both passed with zero artifacts.

Preserve this pre-correction security-PR baseline open and unmerged:

- `budget-analyzer-web`: [#116](https://github.com/budgetanalyzer/budget-analyzer-web/pull/116), [#117](https://github.com/budgetanalyzer/budget-analyzer-web/pull/117), [#118](https://github.com/budgetanalyzer/budget-analyzer-web/pull/118), [#119](https://github.com/budgetanalyzer/budget-analyzer-web/pull/119), and [#120](https://github.com/budgetanalyzer/budget-analyzer-web/pull/120)
- `ext-authz`: [#1](https://github.com/budgetanalyzer/ext-authz/pull/1)

The nested limit does not close existing PRs. After publication, the frontend
must open no additional vulnerability PR while its five existing PRs exceed the
new cap. `ext-authz` may open at most two additional vulnerability PRs, and a
repository with no baseline security PR may open at most three. Stop on any PR
with the wrong base or automerge enabled.

After that prerequisite passed, the operator opened each of the seven
Dependency Dashboard issues:

- [`currency-service` #84](https://github.com/budgetanalyzer/currency-service/issues/84)
- [`permission-service` #20](https://github.com/budgetanalyzer/permission-service/issues/20)
- [`transaction-service` #84](https://github.com/budgetanalyzer/transaction-service/issues/84)
- [`session-gateway` #25](https://github.com/budgetanalyzer/session-gateway/issues/25)
- [`budget-analyzer-web` #121](https://github.com/budgetanalyzer/budget-analyzer-web/issues/121)
- [`ext-authz` #2](https://github.com/budgetanalyzer/ext-authz/issues/2)
- [`workspace` #8](https://github.com/budgetanalyzer/workspace/issues/8)

At the bottom, the operator selected only:

**Check this box to trigger a request for Renovate to run again on this
repository**

All seven requests were queued and Mend ran them one at a time. No
dependency-update checkbox was selected. Six completed green; the workspace
exception and its isolated recovery are recorded below.

Security-labeled PRs may legitimately appear after graph refresh. Record them
but do not merge them. Apply the baseline-aware limits above. Stop for any PR
beyond the nested three-PR vulnerability budget, any PR targeting a branch
other than `dependency-automation-trial`, or any PR showing automerge enabled.

#### B4 workspace recovery

The operator requested all seven cycles. `currency-service`,
`permission-service`, `transaction-service`, `session-gateway`,
`budget-analyzer-web`, and `ext-authz` completed green and must not be rerun.
`workspace` alone reported:

```text
Failed to look up github-tags package aquasecurity/setup-trivy: no-result
```

Public post-cycle inspection found `budget-analyzer-web` PRs #116–#120 and
`ext-authz` PR #1 unchanged, all still targeting the trial branch with the
`security` label and auto-merge disabled. The other five B4 repositories have
no open pull request, so the dedicated vulnerability limit caused no additional
burst.

The action pin is valid: public tag `v0.3.1` resolves to the exact checked-in
commit `81e514348e19b6112ce2a7e3ecbafe19c1e1f567`. This is a hosted native
`github-tags` lookup failure, not a missing dependency. The prepared workspace
correction disables only that native action record and tracks the same
commit-pinned line through Renovate's `git-tags` datasource over public Git
refs. It adds no credential and does not suppress updates.

Publish the correction through the protected workspace trial branch:

1. Create a non-dependency correction PR in `budgetanalyzer/workspace` targeting
   `dependency-automation-trial`; include `renovate.json` and
   `docs/dependency-automation.md`.
2. Confirm the diff contains only the setup-trivy manager fallback and its
   documentation. Do not change the action pin or Trivy CLI version.
3. Merge only that correction PR into the trial branch. Do not merge a bot PR
   or merge the trial branch into `main`.
4. The trial-branch push automatically starts **Workspace Image Security
   Evidence**. Keep uploads and caches `false`; require it to pass with zero
   artifacts.
5. If Mend automatically starts a workspace cycle for the default-branch push,
   let it finish and use it as the corrective B4 cycle. Otherwise open
   [`workspace` Dashboard #8](https://github.com/budgetanalyzer/workspace/issues/8)
   and select only the manual-run checkbox.
6. Require the corrective workspace cycle to finish without the setup-trivy
   lookup warning. Stop and report any new repository problem; do not rerun the
   other six repositories.

Workspace [PR #9](https://github.com/budgetanalyzer/workspace/pull/9) completed
that recovery at `110e5f78fd995ed281d425f9da90bc81079f651d`. The automatic
corrective cycle refreshed Dashboard #8, detected
`aquasecurity/setup-trivy v0.3.1` at the exact checked-in commit, and exposed no
repository problem. The resulting
[Workspace Image Security Evidence run 35098592885](https://github.com/budgetanalyzer/workspace/actions/runs/35098592885)
passed with its optional cache and uploads disabled and zero artifacts. Public
post-recovery inspection found no additional dependency PR and the retained six
security PRs unchanged.

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

Recorded result: onboarding red repositories `none`; graph failures `none`;
alert counts `currency=108`, `permission=54`, `transaction=54`, and
`session-gateway=78`; second-cycle red repositories `none` after the isolated
workspace correction; unexpected dependency PRs `none` beyond the retained six
security PRs.

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

**Passed 2026-09-16.** All seven Dashboards and proposal controls, trial
defaults and bases, accepted graph runs and package counts, internal package and
runtime coverage, public PR/activity state, and the operator-reported Mend
cycles passed. Workspace's isolated lookup failure was corrected through PR #9;
Dashboard #8 and run 35098592885 provide the public corrective evidence. The
exact Batch C proposals are:

- `currency-service`: **Update dependency org.springframework.boot to v3.5.16**
- `budget-analyzer-web`: **Update dependency @radix-ui/react-checkbox to v1.3.11**
- `ext-authz`: **Update module golang.org/x/vuln to v1.8.0**
- `workspace`: **Update dependency mitmproxy to v12.2.3**

These are the individual awaiting-schedule routine proposals visible at the
checkpoint. If one is no longer present when its turn arrives, stop and return
for a new exact selection rather than choosing a replacement.

## Batch C: four representative bot PRs

**Owner: HUMAN**, using the exact proposals supplied after Batch B.

**Ready to start.** Workspace
[PR #10](https://github.com/budgetanalyzer/workspace/pull/10) published the
same-repository, trial-targeted pull-request path at
`09ee0a2afecc2af6c3a216b225537c680ef68848`.
[Pull-request run 35100312719](https://github.com/budgetanalyzer/workspace/actions/runs/35100312719)
passed. The operator explicitly chose not to wait for post-merge
[run 35100778569](https://github.com/budgetanalyzer/workspace/actions/runs/35100778569)
and accepted its success and zero-artifact behavior as the starting assumption.
Do not recheck that run in the new session unless the operator reports a
failure. If a failure is reported, stop before selecting another proposal and
return to this prerequisite.

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

**Passed 2026-09-16.** Public verification found exactly the four requested
routine PRs, all open and unmerged on `dependency-automation-trial`, created by
`renovate[bot]` from same-repository branches, labelled `dependencies`, cleanly
mergeable, and explicitly configured with automerge disabled:

- `currency-service` [PR #87](https://github.com/budgetanalyzer/currency-service/pull/87)
  changes only `springBoot` from `3.5.14` to `3.5.16` in
  `gradle/libs.versions.toml`. Its internal-package-aware
  [Build run 35101624894](https://github.com/budgetanalyzer/currency-service/actions/runs/35101624894)
  passed at `6ee3464e7009162a2d87f8f72fd252839edfc56f`.
- `budget-analyzer-web` [PR #122](https://github.com/budgetanalyzer/budget-analyzer-web/pull/122)
  changes only `package-lock.json`, updating `@radix-ui/react-checkbox` from
  `1.3.3` to `1.3.11` and its lockfile-resolved Radix dependencies.
  [Build run 35102606776](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/35102606776)
  passed at `59318aa42f06a395b50f0cce50c923a923fc20f2`.
- `ext-authz` [PR #3](https://github.com/budgetanalyzer/ext-authz/pull/3)
  changes only `GOVULNCHECK_VERSION` from `v1.7.0` to `v1.8.0`.
  [Build run 35103116099](https://github.com/budgetanalyzer/ext-authz/actions/runs/35103116099)
  passed at `148adfc33bea6ddbff9e530b22fa6802cfddab85`.
- `workspace` [PR #11](https://github.com/budgetanalyzer/workspace/pull/11)
  changes only `MITMPROXY_VERSION` from `12.2.2` to `12.2.3` in the workspace
  Dockerfile. [Workspace Image Security Evidence run 35103462824](https://github.com/budgetanalyzer/workspace/actions/runs/35103462824)
  passed at `e44419a4c580ee81bfd611646886cd610e330887`.

In all four runs, complete evidence measurement passed, trial upload steps were
skipped, the run artifact count is zero, and the PR ref has no Actions cache
entry. No unexpected routine or security PR appeared: the five existing
frontend security PRs and one existing `ext-authz` security PR remain the exact
recovery baseline. Do not merge or close any of these PRs before the later
evidence and rollback decision.

## Later cost and schedule batch

This section is not authorized by Batches A–C.

The executable post-Batch-C sequence, authenticated UI checkpoints, controlled
upload procedure, nine-workflow cron acceptance, rollback verification, and
decision preparation now live in the
[Phase 12 completion plan](dependency-automation-phase-12-completion-plan.md).
Run that plan one phase at a time across its explicit human checkpoints; do not
infer authorization from this cross-link.

Keep these variables `false` in all repositories:

- `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED`
- `DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED`
- `DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED`

Manual dispatch is not cron evidence. After Batch C, the agent must reconcile
measured output/artifact sizes, the 7,444-byte automatic failure artifact,
refreshed Actions billing/storage, cache use, and the no-payment-method boundary.
That reconciliation is now recorded in the coverage report's
[Phase 2 cost and upload section](../research/dependency-automation-coverage.md#phase-12-completion-phase-2-cost-and-upload-reconciliation).
Phase 3's
[controlled-upload bridge](../research/dependency-automation-coverage.md#phase-12-completion-phase-3-controlled-upload-bridge)
supersedes its temporary stop. It corrects the orchestration final-payload gate,
reserves one active artifact, one retry, and a separate future failure-
diagnostic window, and concludes that all five detailed artifacts remain
necessary. The reviewed Phase 3 commit must be published first. Keep every
upload, schedule, and cache variable `false` until the operator replies exactly
`UPLOAD BATCH GO`, then run the one repo-owned helper command documented there.

The first authorized invocation stopped during preflight before any dispatch or
upload because the host GitHub CLI did not support `gh variable get --json`.
The sanitized ledger contains zero rows and confirms final upload-gate
restoration. The bridge now uses `gh api` repository-variable endpoints and has
fixture coverage that rejects the incompatible command path. Publish that
reviewed correction and obtain a fresh exact `UPLOAD BATCH GO` before retrying.
Schedules remain unauthorized until Phase 4 accepts the downloaded evidence.

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
