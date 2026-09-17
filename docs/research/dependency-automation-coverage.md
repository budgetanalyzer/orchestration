# Dependency Automation Coverage

**Status:** Local preparation and Step 3 controls are complete, all nine trial
refs are published, and initial Step 4 hosted branch measurements completed.
The operator authorized the temporary-default orchestration pilot on
2026-09-14 after reconfirming disabled expansion gates and zero current Actions
spend. Ecosystem-wide activation, default-only acceptance, and benchmark
reconciliation remain pending. The orchestration pre-switch audit, Step 5.2
switch, and Step 5.3 dry run are complete. Post-run inspection found `main`
unprotected because the active ruleset contains a malformed combined branch
pattern; the administrator repaired it, and both refs now independently receive
all three intended rules with unchanged SHAs. Renovate-only Community
installation is complete for orchestration in Scan and Alert mode, and
Dependency Dashboard #55 is active. Representative routine PR #56 has the
correct trial base, one-file patch, successful applicable check, and explicit
no-automerge behavior. The operator reported no issue in the requested Mend
cycle/queue/lookup review, and Step 5 proposal controls passed. The public Step
6.1 audit found all eight remaining repositories initially missing protection.
The serialized `service-common` batch now has dual-branch protection, a trial
default, two operator-reported green Mend cycles, accepted 222-package graph
submission, 89 graph-backed alerts, and passing representative PR #57. All
seven remaining B1 onboarding results are green and the four Java consumer
graphs are accepted with complete internal-package coverage. The shared
three-PR vulnerability budget was published and validated before B4. Six of the
seven second cycles completed green initially; `workspace` alone reported a
`setup-trivy` package lookup warning. Workspace PR #9 published the narrow
public-Git-tag fallback at `110e5f78fd995ed281d425f9da90bc81079f651d`.
Dashboard #8 then refreshed with the exact action tag and commit and no
repository problem, and image-evidence run 35098592885 passed with zero
artifacts. Batch B and its public checkpoint are complete. Workspace PR #10 published
the trusted Batch C pull-request trigger at
`09ee0a2afecc2af6c3a216b225537c680ef68848`, and PR run 35100312719 passed. The
operator accepted the still-running post-merge run 35100778569 as successful for
the purpose of starting Batch C; the Phase 1 refresh later confirmed its public
conclusion as success. Batch C then passed: four routine PRs have the exact
trial base, intended diffs,
`dependencies` label, disabled automerge, and successful representative runs.
All four runs skipped uploads, retained zero artifacts, and have no Actions
cache entry for their PR refs. The Phase 12 completion baseline then found one
previously unrecorded failure on frontend security PR #120 and 502,562,266
non-expired public artifact bytes. The #120 patch changes only `package.json`
from Vitest 3 to 4 without updating `package-lock.json` or the grouped Vitest
companions, so `npm ci` correctly rejected it. At `2026-09-16T17:35:49Z`, the
operator identified its creation as an accidental trial-variable side effect
and accepted it as non-representative. Routine PR #122 passed the same Build
workflow. Keep #120 open and unmerged until rollback; its explicit disposition
removes it as an expansion blocker. Phase 12 completion Phase 2 accepted the
zero-spend boundary and completed the five exact no-upload measurements. Four
rows were eligible; orchestration was not because its old helper still gated on
the temporary tar. Phase 3 now corrects that gate, adds retained-size
enforcement, and provides a fixture-tested, fail-closed five-row host bridge.
Scheduled and final benchmark evidence remain pending. A fresh
all-public-repository inventory at
`2026-09-17T04:56:48Z` returned the same 17 artifacts, 502,562,266 bytes, and
zero caches. Eight obsolete `app-jar` objects contribute 501,224,156 bytes.
At `2026-09-17T05:25:38Z`, public APIs confirmed those eight IDs absent, a
1,338,110-byte public residual, zero caches, exact trial-branch heads for all
four fixes, and unchanged recorded `main` SHAs. The trial-only correction is
fully rollbackable but does not change current `main` recurrence. Uploads remain
unauthorized pending the separate Gate C phrase and publication of the reviewed
Phase 3 commit. The
`2026-09-17T10:55:04Z` public refresh found the same 9 artifacts and 1,338,110
bytes, zero caches, no `app-jar`, all eight exact IDs absent, and all nine
recorded main/trial branch pairs unchanged. The workspace helper correction is
published at
`6a6bf33fb019825b7709693a1b103c8a1dd7d726`; run `35187741819` passed at that
SHA with zero artifacts while `main` remained
`383efc840832d474cd9d60e0368ed2ded828e03c`. The Phase 3 refresh at
`2026-09-17T11:55:40Z` found that public storage state unchanged. Its
conservative current-residual-plus-one-retry-plus-future-failure model peaks at
55,097,576 bytes and leaves 469,190,424 public bytes before unknown private
usage.

**Last updated:** 2026-09-17 (Gate C stopped before upload on a host GitHub CLI
compatibility defect; reviewed retry correction, schedules, and final benchmark
dispositions remain pending)

This report records observed extraction and lookup behavior. It is not a list
of desired dependency versions. The preserved
[dependency review](dependency-update-review-2026-09-06.md) remains the
historical acceptance benchmark, and
[Dependency Automation](../dependency-automation.md) owns operating policy.

## Phase 12 branch rehearsal handoff

The A-C procedure remains in the
[revised operator plan](../plans/dependency-automation-phase-12-operator-plan.md).
After Batch C, follow the executable
[Phase 12 completion plan](../plans/dependency-automation-phase-12-completion-plan.md)
for cost, upload, schedule, rollback, and decision evidence. The operator
selected a bounded trial and
reported that neither GitHub nor Mend has a payment method. GitHub documents that
over-quota Actions use is blocked without a valid payment method, establishing a
zero-spend boundary. At `2026-09-16T17:27:55Z`, the operator reconfirmed that
GitHub has no payment method and reported an Actions billing view of `$1.07`
gross usage, a `$1.07` included-usage discount, and `$0` billed usage. At
`2026-09-16T17:32:19Z`, the operator additionally confirmed zero-dollar
budgets with **Stop usage** enabled. All nine trial refs are now published,
initial branch measurement runs completed, and default-only App, schedule, and
alert checks remain deferred.

### Phase 12 completion Phase 1 public baseline

The credential-free refresh observed public state at `2026-09-16T17:05:13Z`.
Before inspection, orchestration was on `dependency-automation-trial` at
`c9e6f31208a5f668fcccd3e7ff2fea649654443c` with the four pre-existing
dependency-automation documents modified and the completion plan untracked.
The seven service/application sibling checkouts were clean on their trial refs.
The `workspace` checkout was clean on local branch `pr-workflow` at
`bcb4991b96e4f5fad32a8ff5c305f2f09fbff94f`; public state, not that local
branch, remains authoritative for its trial ref. No sibling was changed.

All open pull requests in the table are authored by `renovate[bot]`, remain
open and unmerged against `dependency-automation-trial`, carry exactly the
listed routine or security label, and have GitHub auto-merge unset. The
`merge_commit_sha` returned for an open pull request is GitHub's synthetic test
merge and is not evidence of a merge.

| Repository | Public default | `main` SHA | Trial SHA | Current bot-PR and workflow result |
| --- | --- | --- | --- | --- |
| `orchestration` | `dependency-automation-trial` | `57089578957bae3da42587a7e2902727c5473149` | `c9e6f31208a5f668fcccd3e7ff2fea649654443c` | Routine #56 (`dependencies`); current-head run 35068922686 passed |
| `service-common` | `dependency-automation-trial` | `f31557761b80f17ce8fadc128e273b21b4fd07fe` | `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94` | Routine #57 (`dependencies`); run 34940825035 passed |
| `currency-service` | `dependency-automation-trial` | `aa432316849c9231389f8a844325dcf0d64f7335` | `93da3e3599e71cfa453ed78d41691fdfd1edadc3` | Routine #87 (`dependencies`); run 35101624894 passed |
| `permission-service` | `dependency-automation-trial` | `f2d9d55b149c1f3a00e7f2edd85bafe01a46c5f1` | `a31e7c5880a3d3e742e7224297e8226d9e7a47ff` | No bot PR; exact-trial build 35082242381 and graph run 35091521154 passed |
| `transaction-service` | `dependency-automation-trial` | `ccc459f9ea954296a4d1cea6cdbc4b3acf994e6a` | `aa439d27aec63031ab056d4f4afe70cc43e13cca` | No bot PR; exact-trial build 35082230614 and graph run 35091855229 passed |
| `session-gateway` | `dependency-automation-trial` | `a37c7a0bb832b857d3d7371e521ac82e99fc3b93` | `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5` | No bot PR; exact-trial build 35082219212 and graph run 35092673426 passed |
| `budget-analyzer-web` | `dependency-automation-trial` | `b6f0d23c38428daf8412ae055ccbc9db89ac9517` | `2cbef3f17f546fe167628b221a1cb9dec810c2bd` | Security #116-#120 (`security`) and routine #122 (`dependencies`); #116-#119 and #122 passed, but [#120 run 35069921284](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/35069921284) failed at `npm ci` |
| `ext-authz` | `dependency-automation-trial` | `917eae9c782b4b1c4d576258883c3e558a7d55a1` | `75ed2bda4de7460332a8dea656def0459064753f` | Security #1 (`security`) and routine #3 (`dependencies`); runs 35069819575 and 35103116099 passed |
| `workspace` | `dependency-automation-trial` | `383efc840832d474cd9d60e0368ed2ded828e03c` | `09ee0a2afecc2af6c3a216b225537c680ef68848` | Routine #11 (`dependencies`); PR run 35103462824 and post-merge run 35100778569 passed |

Each repository's public open-issue count reconciles exactly to the listed PRs
plus its one known Dependency Dashboard (#55, #56, #84, #20, #84, #25, #121,
#2, and #8 in table order); no additional open issue is visible.

Public rules pages revalidated active
`dependency-automation-trial-protection` rulesets `23314213`, `23413311`,
`23529702`, `23529744`, `23529779`, `23529892`, `23529959`, `23529991`, and
`23530015` in repository-table order. Every ruleset has no bypass actor, exact
default, `main`, and trial targets, and only deletion, non-fast-forward, and
pull-request rules. Public SBOM downloads freshly reconfirmed 222, 314, 236,
238, and 241 packages for the five Java repositories, the exact trial document
version, and all applicable internal coordinates in the four consumers.

The pre-cleanup public artifact and cache inventory was materially different
from the pre-trial zero-byte snapshot. The Java artifacts in this historical
table were ordinary seven-day main-path artifacts created by the routing-fix PR
and resulting `main` push; they were not repo-owned trial uploads. Every scoped
repository reported zero Actions cache entries.

| Repository | Non-expired public artifacts | Public bytes | Expiry/source note |
| --- | ---: | ---: | --- |
| `orchestration` | 0 | 0 | None |
| `service-common` | 1 | 7,444 | Graph diagnostic `10383564434`; expires `2026-12-14T06:40:17Z` |
| `currency-service` | 4 | 167,095,599 | Two `app-jar` and two `test-results`; expire 2026-09-23 |
| `permission-service` | 4 | 120,455,809 | Two `app-jar` and two `test-results`; expire 2026-09-23 |
| `transaction-service` | 4 | 129,237,896 | Two `app-jar` and two `test-results`; expire 2026-09-23 |
| `session-gateway` | 4 | 85,765,518 | Two `app-jar` and two `test-results`; expire 2026-09-23 |
| `budget-analyzer-web` | 0 | 0 | None |
| `ext-authz` | 0 | 0 | None |
| `workspace` | 0 | 0 | None |
| **Historical total before exact-ID cleanup** | **17** | **502,562,266** | About 480 MiB; included in the Phase 2 reconciliation below |

A second unauthenticated refresh at `2026-09-17T04:56:48Z` queried all 15
public organization repositories, not only the nine trial repositories. It
returned the same 17 non-expired artifacts and 502,562,266 bytes; every public
cache inventory remained empty. The exact obsolete-artifact cleanup ledger is:

| Repository | Artifact ID | Workflow run | Source SHA | Name | Bytes | Expires UTC | Findings required before deletion |
| --- | ---: | ---: | --- | --- | ---: | --- | --- |
| `currency-service` | `10440009083` | [`35081217647`](https://github.com/budgetanalyzer/currency-service/actions/runs/35081217647) | `cb7307b64ae58206b002c69f399debf260eb116f` | `app-jar` | 83,249,543 | `2026-09-23T09:48:32Z` | None; deploy-unconsumed regular-CI JAR |
| `currency-service` | `10440089489` | [`35081538971`](https://github.com/budgetanalyzer/currency-service/actions/runs/35081538971) | `aa432316849c9231389f8a844325dcf0d64f7335` | `app-jar` | 83,249,543 | `2026-09-23T09:52:05Z` | None; deploy-unconsumed regular-CI JAR |
| `permission-service` | `10439738759` | [`35081266394`](https://github.com/budgetanalyzer/permission-service/actions/runs/35081266394) | `21485067384b4c0c671df28c8aa27ad4ff4f1410` | `app-jar` | 60,193,521 | `2026-09-23T09:48:29Z` | None; deploy-unconsumed regular-CI JAR |
| `permission-service` | `10440034884` | [`35081774841`](https://github.com/budgetanalyzer/permission-service/actions/runs/35081774841) | `f2d9d55b149c1f3a00e7f2edd85bafe01a46c5f1` | `app-jar` | 60,193,521 | `2026-09-23T09:53:50Z` | None; deploy-unconsumed regular-CI JAR |
| `transaction-service` | `10440595892` | [`35081302881`](https://github.com/budgetanalyzer/transaction-service/actions/runs/35081302881) | `79e16d1bcdd028b7fc772890d62e2f773d3db5db` | `app-jar` | 64,327,198 | `2026-09-23T09:49:29Z` | None; deploy-unconsumed regular-CI JAR |
| `transaction-service` | `10440114874` | [`35081809881`](https://github.com/budgetanalyzer/transaction-service/actions/runs/35081809881) | `ccc459f9ea954296a4d1cea6cdbc4b3acf994e6a` | `app-jar` | 64,327,198 | `2026-09-23T09:55:03Z` | None; deploy-unconsumed regular-CI JAR |
| `session-gateway` | `10439454814` | [`35081330601`](https://github.com/budgetanalyzer/session-gateway/actions/runs/35081330601) | `ba1011cc225864f215d2de30ab8ddfa87b35374b` | `app-jar` | 42,841,816 | `2026-09-23T09:48:57Z` | None; deploy-unconsumed regular-CI JAR |
| `session-gateway` | `10441010133` | [`35081846285`](https://github.com/budgetanalyzer/session-gateway/actions/runs/35081846285) | `a37c7a0bb832b857d3d7371e521ac82e99fc3b93` | `app-jar` | 42,841,816 | `2026-09-23T09:54:36Z` | None; deploy-unconsumed regular-CI JAR |
| **Total** |  |  |  |  | **501,224,156** |  | **99.735220% of ordinary retained Java CI bytes** |

The release path does not download these artifacts: each owning release
workflow builds its container from source, each Dockerfile runs `bootJar`, and
orchestration deploys the digest-pinned GHCR image. The JUnit artifacts total
1,330,666 bytes and contain XML reports, not test classes or dependencies.
Removing future `app-jar` uploads and deleting these exact IDs therefore leaves
release images, deployment, and `service-common` GitHub Packages unchanged.

The operator subsequently deleted those eight exact IDs. An unauthenticated
refresh at `2026-09-17T05:25:38Z` found no public `app-jar`; a fresh cache query
across all 15 public repositories also found zero entries and zero bytes. The
remaining public artifact inventory is:

| Repository | Non-expired public artifacts | Public bytes | Contents |
| --- | ---: | ---: | --- |
| `currency-service` | 2 | 596,513 | Historical `test-results` XML |
| `permission-service` | 2 | 68,767 | Historical `test-results` XML |
| `transaction-service` | 2 | 583,500 | Historical `test-results` XML |
| `session-gateway` | 2 | 81,886 | Historical `test-results` XML |
| `service-common` | 1 | 7,444 | Graph diagnostic; separate from regular Java CI |
| All other public organization repositories | 0 | 0 | None |
| **Current total** | **9** | **1,338,110** | No public `app-jar` |

GitHub's current
[Actions billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions#storage-measurement-units)
defines its storage units as binary: 1 GB is 2^30 bytes and 1 MB is 2^20
bytes. The Free-for-organizations allowance is therefore 524,288,000 bytes.
The public artifact total is 479.280725 MiB, or 95.856145% of that current
allowance, leaving 21,725,734 bytes (20.719275 MiB) of instantaneous public
headroom. It is below, not above, the 500 MB allowance; the apparent excess
exists only when the artifact total is incorrectly compared with 500,000,000
decimal bytes.

The 502,554,822-byte ordinary Java artifact set expires after seven days. A
full seven-day lifetime contributes 78.630829 GiB-hours, equivalent to
111.830513 MiB-month in a 720-hour month, or 22.366103% of the monthly 500 MiB
allowance. The long-lived 7,444-byte diagnostic is negligible at this scale.
This distinguishes the current retained-byte peak from GitHub's hourly accrued
monthly storage calculation.

Public organization inspection shows ten packages: six Container Registry
packages and four public `service-common` Maven packages. GitHub's current
[Packages billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-packages)
states that public packages are free and that Container Registry storage and
bandwidth are currently free. These ten public packages therefore add no
metered package-storage usage. Account-private artifact or package usage remains
unobservable without authenticated billing data and is not reported as zero.
The operator's `$1.07` gross Actions usage, matching `$1.07` discount, `$0`
billed usage, and absent payment method establish that no storage or runner
overage is currently billed. The safe conclusion is: known public storage is
within the free allowance and no paid overage exists, but additional upload
capacity remains unproved; keep trial uploads disabled.

#### Trial upload and schedule inventory

All nine copies of `.github/scripts/prepare-trial-evidence.sh` are byte-identical
at SHA-256
`6511fbe339319e1fa53b5ba6857ae45f8e83d2cfb30bb6bd87771d046bc31774`.
The helper includes its generated measurement file in each sealed archive,
rejects absolute or parent-traversal paths, and measures
`source_bytes`, `uncompressed_tar_bytes`, `compressed_archive_bytes`, and
`upload_allowed` against 25,165,824 bytes (24 MiB). The job summary emits the
same source, tar, compressed, cap, and allowed fields. Every producer requires
`DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED=true` and
`upload_allowed=true`, uploads the already-compressed archive with compression
level zero and one-day retention, and fails delivery when uploads are enabled
but the complete archive exceeds the cap.

| Repository/workflow | Sealed archive | Exact allowlisted inputs |
| --- | --- | --- |
| `orchestration` / `dependency-automation-config.yml` | `renovate-evidence.tar.gz` | `dependency-automation-revisions.log`; `dependency-automation-evidence/renovate-trial-global-config.json`; `dependency-automation-evidence/renovate-debug.log` |
| `orchestration` / `exact-image-security-evidence.yml` | `image-security-evidence.tar.gz` | `scan-work/evidence`; `rendered`; `scanner`; `raw-targets.tsv`; `targets.json`; `scan-status.json` |
| `service-common` / `build.yml` | `build-evidence.tar.gz` | `dependency-automation-evidence/build.log`; `spring-platform/build/libs`; `spring-platform/build/test-results/test`; `spring-cloud-platform/build/libs`; `spring-cloud-platform/build/test-results/test`; `service-core/build/libs`; `service-core/build/test-results/test`; `service-web/build/libs`; `service-web/build/test-results/test` |
| `service-common` / `dependency-submission.yml` | `dependency-graph-evidence.tar.gz` | `dependency-automation-evidence/dependency-resolution.log`; `dependency-automation-evidence/dependency-graph` |
| `currency-service` / `build.yml` | `build-evidence.tar.gz` | `dependency-automation-evidence/build.log`; `build/libs`; `build/test-results/test` |
| `currency-service` / `dependency-submission.yml` | `dependency-graph-evidence.tar.gz` | `dependency-automation-evidence/dependency-resolution.log`; `dependency-automation-evidence/dependency-graph` |
| `permission-service` / `build.yml` | `build-evidence.tar.gz` | `dependency-automation-evidence/build.log`; `build/libs`; `build/test-results/test` |
| `permission-service` / `dependency-submission.yml` | `dependency-graph-evidence.tar.gz` | `dependency-automation-evidence/dependency-resolution.log`; `dependency-automation-evidence/dependency-graph` |
| `transaction-service` / `build.yml` | `build-evidence.tar.gz` | `dependency-automation-evidence/build.log`; `build/libs`; `build/test-results/test` |
| `transaction-service` / `dependency-submission.yml` | `dependency-graph-evidence.tar.gz` | `dependency-automation-evidence/dependency-resolution.log`; `dependency-automation-evidence/dependency-graph` |
| `session-gateway` / `build.yml` | `build-evidence.tar.gz` | `dependency-automation-evidence/build.log`; `build/libs`; `build/test-results/test` |
| `session-gateway` / `dependency-submission.yml` | `dependency-graph-evidence.tar.gz` | `dependency-automation-evidence/dependency-resolution.log`; `dependency-automation-evidence/dependency-graph` |
| `budget-analyzer-web` / `build.yml` | `build-evidence.tar.gz` | `dependency-automation-evidence/build.log`; `dist`; `coverage` |
| `budget-analyzer-web` / `dependency-audit.yml` | `audit-evidence.tar.gz` | `dependency-audit-reports` |
| `ext-authz` / `build.yml` | `build-evidence.tar.gz` | `dependency-automation-evidence/build.log` |
| `ext-authz` / `go-vulnerability-check.yml` | `govulncheck-evidence.tar.gz` | `govulncheck-results` |
| `workspace` / `workspace-image-security-evidence.yml` | `workspace-image-evidence.tar.gz` | `workspace-image-scan` |

The five Java build producers plus the frontend and Go build producers accept
only push/dispatch on `main` or the trial ref and pull requests whose base is
one of those refs; trial measurement is limited to the trial ref/base. The
orchestration dry-run producer requires the exact trial ref plus either an
opted-in dispatch or the reviewed marked-push fallback. The scheduled producers
use these checked-in guards:

| Repository/workflow | UTC cron | Trial schedule guard |
| --- | --- | --- |
| `orchestration` / Exact Image Security Evidence | Saturday 04:23 | Exact trial ref and schedule variable `true`; main accepts schedule/dispatch; trial also accepts reviewed push/dispatch |
| `workspace` / Workspace Image Security Evidence | Saturday 04:41 | Exact trial ref and schedule variable `true`; main accepts schedule/dispatch; same-repository PRs must target the trial ref |
| `ext-authz` / Go Vulnerability Check | Monday 05:17 | Exact trial ref and schedule variable `true`; main and trial also accept guarded push/dispatch |
| `service-common` / Dependency Submission | Monday 05:23 | Exact trial ref and schedule variable `true`; main and trial also accept guarded push/dispatch |
| `currency-service` / Dependency Submission | Monday 05:31 | Exact trial ref and schedule variable `true`; main and trial also accept guarded push/dispatch |
| `permission-service` / Dependency Submission | Monday 05:37 | Exact trial ref and schedule variable `true`; main and trial also accept guarded push/dispatch |
| `transaction-service` / Dependency Submission | Monday 05:43 | Exact trial ref and schedule variable `true`; main and trial also accept guarded push/dispatch |
| `session-gateway` / Dependency Submission | Monday 05:43 | Exact trial ref and schedule variable `true`; main and trial also accept guarded push/dispatch |
| `budget-analyzer-web` / Dependency Audit | Monday 06:17 | Exact trial ref and schedule variable `true`; main accepts schedule/dispatch; trial also accepts guarded push/dispatch |

Optional trial caches remain gated by
`DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED`; Java submission additionally
requires the accepted graph-submission variable and the trial ref to remain the
repository default before it submits rather than only generates.

Checkpoint A is complete with authenticated account and installation facts:

```text
Checkpoint A complete
Observed UTC: 2026-09-16T17:35:49Z
GitHub organization plan: GitHub Free for organizations (500 MiB allowance)
Actions billed amount this cycle: $0 (operator reported $1.07 gross usage and $1.07 discount at 2026-09-16T17:27:55Z)
Actions included/used minutes: not displayed
Artifact/storage usage: 502,562,266 public bytes (479.280725 MiB, 95.856145% of the 500 MiB allowance); account-private aggregate not displayed
Packages storage usage: ten public packages add no metered usage under GitHub policy; account-private aggregate not displayed
Quota or usage warning: none reported
GitHub payment method: absent
Actions hard spend stop: $0 Stop-usage budget plus no-payment-method block
Packages hard spend stop: $0 Stop-usage budget plus no-payment-method block
Mend tier: Community/free
Mend paid trial or payment method: absent
Mend active organization jobs: 0
Mend repository scope: exact nine
Unexpected condition: budget-analyzer-web PR #120 is a malformed accidental trial proposal retained open and unmerged until rollback; explicitly accepted as non-representative
```

Do not supply credentials, cookies, billing identifiers, private repository
names, or private logs. Checkpoint A was read-only. The failed public run is now
explicitly dispositioned; uploads and schedules remain off until their separate
plan gates.

Public metadata for the initial branch runs records successful frontend audit,
Go vulnerability, orchestration/workspace image, Java build, and generation-only
graph jobs, with no uploaded artifacts. Those publication-triggered runs
overlapped across repositories, contrary to the one-job-at-a-time trial rule.
The overlap is a retained process deviation; successful jobs will not be rerun
solely to alter their timing. Remaining human-dispatched Actions work stays
serialized, while non-triggering administration uses the operator plan's Batch
A.
The operator reconfirmed disabled orchestration cache, schedule, and upload gates
and zero current Actions spend before authorizing the Step 5 temporary-default
orchestration pilot. At that checkpoint upload sizing was still pending, so
uploads remained off; the completion Phase 2 reconciliation below later closed
that question with a **DO NOT AUTHORIZE UPLOADS** result.
The operator subsequently reported that orchestration has no repository
rulesets or classic branch-protection rules. The absence removes default-target
migration risk but initially left the trial ref unprotected. The operator then
activated `dependency-automation-trial-protection`, intending to cover both
`main` and the trial ref, block deletion and force pushes, and require pull
requests without unavailable status checks. The pre-switch review incorrectly
accepted the malformed combined target as effective. The operator confirmed
that Renovate/Mend had no
access to orchestration before the switch. Public refs then still showed `main`
as default at `dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5` and the protected trial at
`24ffc8e36bf87a730bb6a25961059becbdb67d72`; the pre-switch audit is complete.
The human then changed only the orchestration default to the protected trial
branch. Credential-free verification at `2026-09-14T14:28Z` confirmed the new
default/trial SHA and unchanged `main` SHA, zero open PRs and issues, and no
post-switch workflow or visible bot activity. The newest visible Actions run
remained pre-switch run `34848193973`. The unauthenticated artifact API was rate
limited during this check; because no post-switch workflow ran, there was no new
run capable of uploading an artifact, but a direct artifact inventory is not
claimed.
Manual-dispatch run
[34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322)
then passed on the exact trial/default SHA. Its strict validation and hosted
dry-run jobs succeeded sequentially in 2 minutes 27 seconds; hard gates establish
the matching preset ref, exact trial base, mutation simulation, repository
result `done`, and no `ERROR`/`FATAL` records. Both upload paths skipped and the
run artifact count was zero. Existing Aqua Security and Docker Hub lookup gaps
remain unresolved.

Post-run public API inspection found a ruleset defect: the initial include
conditions were `~DEFAULT_BRANCH` and one malformed combined literal. The first
remediation split the condition but retained quotes, yielding
`refs/heads/"main"` and `refs/heads/"dependency-automation-trial"`. Those values
still match neither branch. The trial receives the three intended rules only as
the current default, while `main` receives no active rule. Both SHAs remain
unchanged. Remove the literal quotes and verify both branches before installing
Mend.
The administrator then saved unquoted patterns. Verification at
`2026-09-14T15:00:04Z` found exact `refs/heads/main` and
`refs/heads/dependency-automation-trial` conditions and all three rules on both
branches. Both SHAs, the successful run list, and zero-open-PR state remained
unchanged; the Step 5.4 protection blocker is cleared.
The operator then installed Renovate-only Mend Community in Scan and Alert mode
for orchestration only and reports graph/alerts enabled with competing Dependabot
update PRs disabled. Renovate opened
[Dependency Dashboard #55](https://github.com/budgetanalyzer/orchestration/issues/55)
with 95 approval-gated and 75 schedule-gated entries. No PR, branch, commit, or
Actions run accompanied onboarding.
The operator then selected only routine proposal `renovate/renovate-44.66.x`.
[PR #56](https://github.com/budgetanalyzer/orchestration/pull/56) opened at
`2026-09-14T15:13:39Z` into `dependency-automation-trial` from head
`a12888e1d19309eb79bde14d06f673e4ab683479`. Its one-commit, one-file diff
changes only the workflow's Renovate pin from `44.65.5` to `44.66.1`.
[Run 34860772186](https://github.com/budgetanalyzer/orchestration/actions/runs/34860772186)
passed the applicable config validation in 37 seconds overall, correctly skipped
the manual-only hosted dry run, and uploaded no artifact. The PR body explicitly
reports automerge disabled by config. Public refs and the dashboard show no
second Renovate PR or branch. The operator reviewed both Mend cycles and
reported no issue in the requested status, queueing, timeout, rate-limit,
authentication, or lookup fields; exact portal timestamps/durations were not
transcribed. Dashboard/config review confirmed routine schedule/limits,
approval-gated sensitive categories, maintained-line and flavor-preserving
digest proposals, and no first-party image proposal. No live
vulnerability-fix PR was available, so graph-backed alert behavior remains Step
6 evidence.

The subsequent public Step 6.1 audit found all eight remaining repositories
still on `main`, with zero open PRs, clean local checkouts whose main/trial SHAs
match public refs, and explicit trial-preset references. Trial refs are two or
three commits ahead and zero behind. No repository has a ruleset or classic
branch protection on either ref, so protection was the next prerequisite. Trial
schedules, uploads, graph submissions, and optional caches remain gated off;
default changes do not trigger the observed release/snapshot workflows. The
initial expansion therefore began with `service-common` after protecting both
refs and confirming its administrator-only integration state.

That `service-common` batch is now complete through its manual acceptance
surface. Active ruleset `23413311` independently protects `main` and
`dependency-automation-trial`; the human switched only the default and public
checks preserved main at `f31557761b80f17ce8fadc128e273b21b4fd07fe` and the
trial/default at `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94`. Mend onboarding
created [Dashboard #56](https://github.com/budgetanalyzer/service-common/issues/56)
without a PR burst. Its public content proves Gradle/catalog/wrapper/Actions and
explicit trial-preset discovery with no visible config warning; the operator
reported both the onboarding cycle and a post-graph manual cycle green. The
operator canceled one pending scheduled Mend job before expansion to preserve
serialization; that canceled cycle is retained but does not count as a success.

The first attempt of manual dependency-submission
[run 34937981854](https://github.com/budgetanalyzer/service-common/actions/runs/34937981854)
preserved a real prerequisite failure: complete dependency resolution passed,
but GitHub rejected submission because Dependency graph was disabled. The
Gradle action automatically uploaded failure artifact `10383564434` (7,444
bytes; expiry `2026-12-14T06:40:17Z`) even though the repo-owned upload step was
off. After the human enabled Dependency graph and Dependabot alerts while
leaving competing Dependabot update PRs disabled, attempt 2 passed on the exact
trial/default SHA. GitHub's accepted SBOM contains 222 packages and the operator
reported 89 graph-backed alerts. The repo-owned upload paths remained skipped;
do not classify the run itself as zero-artifact because the attempt-1 diagnostic
remains attached.

The second green Mend cycle created no automatic vulnerability-fix PR. The
operator then selected only routine Gradle `9.5.0` to `9.5.1`.
[PR #57](https://github.com/budgetanalyzer/service-common/pull/57) targets the
trial default, has one commit and one changed wrapper-properties line, and
states automerge is disabled. Its
[build 34940825035](https://github.com/budgetanalyzer/service-common/actions/runs/34940825035)
passed in 2 minutes 13 seconds with trial cache disabled, all upload steps
skipped, and zero artifacts. Keep PR #57 open. Batch A now configures all seven
remaining repositories together; cron and detailed upload-size acceptance
remain pending.

The operator checklist was simplified after the `service-common` batch exposed
that per-repository conversational handoffs do not scale. The remaining seven
repositories now use one non-triggering setup batch followed by one agent
verification checkpoint, then one Mend/graph activation batch. Mend's Community
organization concurrency remains one job, and human-dispatched GitHub graph
workflows remain sequential within the batch. This changes coordination, not
the credential, no-merge, no-upload, no-schedule, or zero-spend boundaries.

The 2026-09-16 Batch A public checkpoint passed after correcting one malformed
`transaction-service` branch target, activating the prepared `session-gateway`
ruleset, and switching the `ext-authz` default. All seven repositories retain
their recorded `main` and trial SHAs, advertise the trial ref as default, and
have an active no-bypass ruleset with exact default, `main`, and trial targets
and only deletion, non-fast-forward, and pull-request rules. Their dependency
graph SBOM endpoints and exact trial-preset references resolve, with no open
issues or pull requests and no new repository-defined workflow. GitHub
automatically ran successful `ext-authz` graph updates for the old and new
defaults while graph/default settings changed; these were platform-generated
`dynamic` events rather than operator-dispatched workflows.

Batch B App expansion then reached `transaction-service`. Its first Renovate
cycle reported `no-result` for `org.budgetanalyzer:spring-platform`,
`org.budgetanalyzer:service-core`, and `org.budgetanalyzer:service-web` in
`gradle/libs.versions.toml`. This is preserved as evidence that Mend's
installation token did not satisfy the authenticated GitHub Packages Maven
lookup; it is not evidence that the published coordinates are absent. The
operator reports storing the previously retained package-read PAT in Mend and
configuring an organization-level Renovate Maven host rule for only
`https://maven.pkg.github.com/budgetanalyzer/service-common/`, using the PAT
owner's GitHub username. No secret value or username is recorded here. The
durable repository correction and post-merge scan result are recorded below.
All seven B1 green onboarding outcomes still need confirmation before B2.

### Internal Maven routing correction

All four Java consumers previously declared Maven Local, the authenticated
`service-common` GitHub Packages repository, and an unrestricted Maven Central
repository. The durable correction preserves that order and excludes
`org.budgetanalyzer` from Maven Central, so internal coordinates resolve only
from Maven Local or GitHub Packages. It deliberately does not use Gradle
`exclusiveContent`, which would prevent the intended Maven Local fallback. No
dependency version, credential, Renovate configuration, workflow, or
`service-common` artifact changed.

The correction was merged into each `main` branch and then forward into the
protected trial branch:

| Repository | `main` pull request and resulting SHA | Trial pull request and resulting SHA |
| --- | --- | --- |
| `orchestration` | [#59](https://github.com/budgetanalyzer/orchestration/pull/59) — `57089578957bae3da42587a7e2902727c5473149` | [#60](https://github.com/budgetanalyzer/orchestration/pull/60) — `dab623ea7517e12cf9d08d8ea570529e745ecd3a` |
| `currency-service` | [#85](https://github.com/budgetanalyzer/currency-service/pull/85) — `aa432316849c9231389f8a844325dcf0d64f7335` | [#86](https://github.com/budgetanalyzer/currency-service/pull/86) — `93da3e3599e71cfa453ed78d41691fdfd1edadc3` |
| `permission-service` | [#21](https://github.com/budgetanalyzer/permission-service/pull/21) — `f2d9d55b149c1f3a00e7f2edd85bafe01a46c5f1` | [#22](https://github.com/budgetanalyzer/permission-service/pull/22) — `a31e7c5880a3d3e742e7224297e8226d9e7a47ff` |
| `transaction-service` | [#85](https://github.com/budgetanalyzer/transaction-service/pull/85) — `ccc459f9ea954296a4d1cea6cdbc4b3acf994e6a` | [#86](https://github.com/budgetanalyzer/transaction-service/pull/86) — `aa439d27aec63031ab056d4f4afe70cc43e13cca` |
| `session-gateway` | [#26](https://github.com/budgetanalyzer/session-gateway/pull/26) — `a37c7a0bb832b857d3d7371e521ac82e99fc3b93` | [#27](https://github.com/budgetanalyzer/session-gateway/pull/27) — `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5` |

Local validation passed `clean spotlessApply`, `clean build`, and
`git diff --check` in all four consumers. The operator subsequently ran the
required post-merge `currency-service` Renovate scan and reported that it
succeeded with no warnings. No raw Mend log or separate per-coordinate result
was supplied, so this records the sanitized operator report without claiming
independent inspection of the scan transcript. The routing-fix checkpoint is
complete; the operator subsequently confirmed all seven B1 onboarding outcomes
green.

### Batch B graph and security-PR checkpoint

The first B2 graph pass exposed a control-scope error rather than a dependency
failure. The operator had created the trial control names as repository secrets,
but the workflows intentionally read non-sensitive controls from the `vars`
context. [`currency-service` run 35083509407](https://github.com/budgetanalyzer/currency-service/actions/runs/35083509407)
submitted successfully after its graph control was corrected. The first
`permission-service`, `transaction-service`, and `session-gateway` runs stayed
in generation-only mode while still passing their package-access and build
checks. Those non-submitting runs were
[`permission-service` 35083948086](https://github.com/budgetanalyzer/permission-service/actions/runs/35083948086),
[`transaction-service` 35084259266](https://github.com/budgetanalyzer/transaction-service/actions/runs/35084259266), and
[`session-gateway` 35084554215](https://github.com/budgetanalyzer/session-gateway/actions/runs/35084554215).
A second
[`permission-service` diagnostic run 35085536053](https://github.com/budgetanalyzer/permission-service/actions/runs/35085536053)
also remained generation-only and made the mistaken scope explicit. These
successful generation-only runs are retained and are not counted as accepted
submissions.

After the operator created the required repository variables, replacement runs
passed sequentially on the exact trial/default SHAs:

| Repository | Accepted run | Trial SHA | Accepted SBOM packages | Open alerts |
| --- | --- | --- | ---: | ---: |
| `currency-service` | [35083509407](https://github.com/budgetanalyzer/currency-service/actions/runs/35083509407) | `93da3e3599e71cfa453ed78d41691fdfd1edadc3` | 314 | 108 |
| `permission-service` | [35091521154](https://github.com/budgetanalyzer/permission-service/actions/runs/35091521154) | `a31e7c5880a3d3e742e7224297e8226d9e7a47ff` | 236 | 54 |
| `transaction-service` | [35091855229](https://github.com/budgetanalyzer/transaction-service/actions/runs/35091855229) | `aa439d27aec63031ab056d4f4afe70cc43e13cca` | 238 | 54 |
| `session-gateway` | [35092673426](https://github.com/budgetanalyzer/session-gateway/actions/runs/35092673426) | `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5` | 241 | 78 |

Public SBOM inspection found `org.budgetanalyzer:spring-platform`,
`org.budgetanalyzer:service-core`, and `org.budgetanalyzer:service-web` where
applicable in all four consumer graphs. The graphs also expose Spring Framework
6.2.18 and Jackson Databind 2.21.2 throughout; the servlet services include
Tomcat 10.1.54, while `session-gateway` contains WebFlux, Reactor Netty/Netty,
and Lettuce with no Tomcat package. Every accepted run used `workflow_dispatch`
on `dependency-automation-trial`, completed successfully, skipped the repo-owned
upload paths, and has zero artifacts. The operator also ran
[`service-common` 35092182970](https://github.com/budgetanalyzer/service-common/actions/runs/35092182970),
which reconfirmed its existing 222-package graph and 89 alerts with zero
artifacts. That refresh was not required by B2 and must not be repeated for this
batch.

Before B4, public inspection found six automatic vulnerability-fix PRs created
during the initial onboarding cycles. `budget-analyzer-web` opened
[#116](https://github.com/budgetanalyzer/budget-analyzer-web/pull/116),
[#117](https://github.com/budgetanalyzer/budget-analyzer-web/pull/117),
[#118](https://github.com/budgetanalyzer/budget-analyzer-web/pull/118),
[#119](https://github.com/budgetanalyzer/budget-analyzer-web/pull/119), and
[#120](https://github.com/budgetanalyzer/budget-analyzer-web/pull/120), while
`ext-authz` opened [#1](https://github.com/budgetanalyzer/ext-authz/pull/1).
All six target `dependency-automation-trial`, carry the `security` label, and
have GitHub auto-merge disabled. The five-PR frontend burst crossed the plan's
three-PR stop threshold.

This is a shared-policy defect, not evidence that the top-level routine limit
failed. Renovate vulnerability-alert PRs ignore top-level
`branchConcurrentLimit`, `commitHourlyLimit`, `prConcurrentLimit`,
`prHourlyLimit`, and schedule by default. Their default dedicated concurrent
limit is zero, meaning unlimited. The shared preset correction adds
`vulnerabilityAlerts.prConcurrentLimit: 3`, retaining an unrestricted security
schedule and `automerge: false` while giving vulnerability fixes a separate
three-PR budget. It does not close the six existing PRs. The corrected trial
preset was published and validated before B4; preserve those PRs open and
unmerged and use them as the baseline for the seven second cycles.

The correction was published through
[orchestration PR #62](https://github.com/budgetanalyzer/orchestration/pull/62)
at `c9e6f31208a5f668fcccd3e7ff2fea649654443c`.
[Configuration run 35095610585](https://github.com/budgetanalyzer/orchestration/actions/runs/35095610585)
and
[image-evidence run 35095610628](https://github.com/budgetanalyzer/orchestration/actions/runs/35095610628)
both passed with zero artifacts. The operator then requested all seven B4
cycles. Six completed green. `workspace` alone reported `no-result` for the
native `github-tags` lookup of `aquasecurity/setup-trivy` in
`.github/workflows/workspace-image-security-evidence.yml`. Public Git refs prove
that tag `v0.3.1` maps exactly to the checked-in commit
`81e514348e19b6112ce2a7e3ecbafe19c1e1f567`; the dependency is not missing.
The prepared consumer correction disables only that native record and adds a
regex manager using Renovate's `git-tags` datasource against the public Git
repository. Local Renovate 44.65.5 strict validation passed, and the direct
lookup resolved the current tag and digest without a warning or proposed
change. Post-cycle public inspection found the five frontend security PRs and
one `ext-authz` security PR unchanged, with no open PR in the other five B4
repositories. Workspace PR #9 subsequently published the correction at
`110e5f78fd995ed281d425f9da90bc81079f651d`. Its automatic corrective cycle
refreshed Dashboard #8 with the exact setup-trivy record and no repository
problem, while image-evidence run 35098592885 passed with uploads skipped and
zero artifacts. This completed the seventh B4 cycle without repeating the other
six.

The completed trial-ref and ignore remediation work owns the local
preset-reference and generated-state ignore corrections. The reviewed trial
refs are published; keep them recoverable and frozen during each evidence
batch.
Record source/default refs, main SHAs, actual artifact bytes and retention, cache
use, billing observations, and detailed report evidence alongside existing
deferred checks. Report trial acceptance, ongoing installation, and benchmark
parity separately. A paused successful trial does not mean ongoing activation.

### Phase 12 completion Phase 2 cost and upload reconciliation

Checkpoint A is accepted for the zero-spend boundary. GitHub has no payment
method, Actions and Packages each have a zero-dollar **Stop usage** budget, the
operator reported no quota warning and `$0` billed Actions usage, and Mend is
Community/free with no paid trial or payment method, zero active jobs, and the
exact nine-repository scope. Those controls prevent spend; they do not establish
available storage. Account-private artifact and package usage remains unknown
and is not treated as zero.

The completion plan's workspace-correction verification passed at
`2026-09-17T10:14:02Z`. Public refs resolved
`dependency-automation-trial` to
`6a6bf33fb019825b7709693a1b103c8a1dd7d726` and `main` to the unchanged
rollback SHA `383efc840832d474cd9d60e0368ed2ded828e03c`. Push run
`35187741819` completed successfully at the corrected trial SHA with the image
build, complete scan, and sealed-allowlist measurement steps successful; upload,
enforcement, retained-size, and artifact-link steps were skipped, and the run
retained zero artifacts. Local focused helper tests, `bash -n`, `shellcheck`,
`actionlint`, and `git diff --check` all passed. The helper gates only the final
gzip at 25,165,824 bytes, the upload action uses compression level zero, the
post-upload check enforces 26,214,400 retained bytes, and every schedule, cache,
and upload expansion remains conditional.

The old and corrected recurring models must not be mixed:

| Surface | Old recurring model | Corrected recurring model |
| --- | --- | --- |
| Four deployable Java services, successful regular CI | 251,277,411 bytes per four-service cycle, retained seven days; the current PR cycle plus `main` cycle total 502,554,822 bytes | Zero retained bytes |
| Four deployable Java services, failed regular CI | Same JAR-plus-XML behavior as success | JUnit XML only, one day; 665,333 bytes for one measured four-service cycle and 1,330,666 bytes with one same-size retry |
| Controlled Phase 12 evidence | Separate gated archive, initially off | Still separate, one at a time, one-day retention, 24 MiB payload target and 25 MiB retained ceiling |
| `service-common` packages | GitHub Packages release/snapshot publishing | Unchanged; not an Actions-artifact cleanup target |

The pre-cleanup public total was 502,562,266 bytes. Exact-ID removal of the
eight `app-jar` artifacts reduced known public retained bytes by 501,224,156.
The Phase 2 credential-free refresh completed at `2026-09-17T10:55:04Z` across
all 15 public organization repositories and found the resulting 1,338,110-byte
residual unchanged: 1,330,666 bytes of JUnit XML plus the 7,444-byte
`service-common` graph diagnostic. It found 9 non-expired artifacts, zero cache
entries and bytes, and no `app-jar`; all eight deleted artifact endpoints
returned HTTP 404. Nominal public headroom is therefore 522,949,890 bytes before
private usage. Removing future uploads alone did not produce this headroom; the
old objects had to expire or be deleted by the operator.

The complete evidence-size ledger keeps source, temporary tar, final gzip, and
GitHub-retained bytes distinct:

| Evidence | Source bytes | Temporary tar bytes | Final gzip bytes | Current disposition |
| --- | ---: | ---: | ---: | --- |
| `govulncheck` — run [34823939945](https://github.com/budgetanalyzer/ext-authz/actions/runs/34823939945) | 422,874 | 430,080 | 52,560 | `upload_allowed=true`; one allowlisted path |
| npm audit — run [34823959669](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/34823959669) | 48,474 | 61,440 | 6,164 | `upload_allowed=true`; one allowlisted path |
| Representative Java graph — run [35092182970](https://github.com/budgetanalyzer/service-common/actions/runs/35092182970) | 145,362 | 153,600 | 18,457 | `upload_allowed=true`; two allowlisted paths |
| Complete workspace-image allowlist — run [35187741819](https://github.com/budgetanalyzer/workspace/actions/runs/35187741819) | 44,614,250 | 44,636,160 | 6,314,072 | `upload_allowed=true`; one allowlisted path and one image target |
| Platform-image allowlist — run [35095610628](https://github.com/budgetanalyzer/orchestration/actions/runs/35095610628) | 73,905,036 | 74,178,560 | 7,945,624 | `upload_allowed=false`; six allowlisted paths and 32 image/platform targets |

The corrected workspace helper properly treats its 44,636,160-byte tar as
temporary compressor input and gates only the 6,314,072-byte gzip. The
orchestration helper still applies the old tar-and-gzip gate: its gzip is below
24 MiB, but its tar exceeds 25,165,824 bytes by 49,012,736, so the source-exact
summary correctly reports `upload_allowed=false` under the then-published logic.
No target or report may be trimmed merely to change that result. At the Phase 2
close, Phase 3 therefore had to resolve this concrete eligibility blocker
before recommending any upload batch; the correction is recorded below.

The selected `ext-authz` and frontend publication-triggered runs overlapped by
17 seconds. This is the already-recorded publication-batch serialization
deviation, not a new Phase 2 dispatch; the other three selected runs did not
overlap. Every selected job succeeded, every repo-owned upload step was skipped,
the public run pages report zero artifacts, and the current public inventory has
no artifact from any selected run. No Gate B dispatch was needed.

The rolling model does not require all five records, or future repositories'
records, to remain retained concurrently. After recording an artifact's exact
ID, run, SHA, name, API size, expiry, and required findings, the operator may
delete that exact artifact or wait for its one-day expiry before continuing.
With the 1,338,110-byte public residual and one active artifact plus one retry at
the full 25 MiB retained ceiling, the conservative public peak is 53,766,910
bytes and the remaining allowance is 470,521,090 bytes before private usage.
Actual exact bundle sizes must replace the ceiling in the pre-upload decision.
Optional caches remain disabled and contribute zero.

The five no-upload rows are complete. Phase 3 will decide which
non-duplicative retained records, if any, remain necessary; their candidate
order is:

| Order | Variables and workflow UI | Frozen trial source | Expected artifact | Row-specific stop condition |
| ---: | --- | --- | --- | --- |
| 1 | [`ext-authz` variables](https://github.com/budgetanalyzer/ext-authz/settings/variables/actions); [Go Vulnerability Check](https://github.com/budgetanalyzer/ext-authz/actions/workflows/go-vulnerability-check.yml), no inputs | `dependency-automation-trial` at `75ed2bda4de7460332a8dea656def0459064753f` | `trial-govulncheck-evidence-RUN_ID` | Stop unless the complete archive is eligible and contains the scanner/database metadata and full result |
| 2 | [`budget-analyzer-web` variables](https://github.com/budgetanalyzer/budget-analyzer-web/settings/variables/actions); [Dependency Audit](https://github.com/budgetanalyzer/budget-analyzer-web/actions/workflows/dependency-audit.yml), no inputs | `dependency-automation-trial` at `2cbef3f17f546fe167628b221a1cb9dec810c2bd` | `trial-npm-audit-evidence-RUN_ID` | Stop unless the full and production audit reports are complete and eligible |
| 3 | [`service-common` variables](https://github.com/budgetanalyzer/service-common/settings/variables/actions); [Dependency Submission](https://github.com/budgetanalyzer/service-common/actions/workflows/dependency-submission.yml), no inputs | `dependency-automation-trial` at `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94` | `trial-dependency-graph-evidence-RUN_ID` | Stop unless resolution and the complete graph are eligible; keep graph submission enabled |
| 4 | [`workspace` variables](https://github.com/budgetanalyzer/workspace/settings/variables/actions); [Workspace Image Security Evidence](https://github.com/budgetanalyzer/workspace/actions/workflows/workspace-image-security-evidence.yml), no inputs | `dependency-automation-trial` at corrected SHA `6a6bf33fb019825b7709693a1b103c8a1dd7d726` | `trial-workspace-image-evidence-RUN_ID` | Stop unless the complete allowlist is unchanged and the final archive is eligible |
| 5 | [`orchestration` variables](https://github.com/budgetanalyzer/orchestration/settings/variables/actions); [Exact Image Security Evidence](https://github.com/budgetanalyzer/orchestration/actions/workflows/exact-image-security-evidence.yml), no inputs | `dependency-automation-trial` at `c9e6f31208a5f668fcccd3e7ff2fea649654443c` | `trial-exact-image-security-evidence-RUN_ID` | Stop unless all rendered targets remain allowlisted and the fresh no-upload summary reports an eligible final archive |

For every row, select the exact trial branch, leave schedule and cache variables
`false`, enable uploads only for that one serialized run, and restore uploads to
`false` immediately after completion. Stop on a changed/unreviewed SHA, wrong
ref, failed or skipped job, `upload_allowed != true`, an unexpected artifact or
cache, an API artifact size above the remaining verified headroom, or any new PR.
After each row, record required findings before any exact-ID deletion, replace
the estimate with the artifact API's `size_in_bytes`, and recalculate the
remaining one-retry envelope before proceeding.

This matrix was conditional Phase 2 documentation, not an executable
authorization. At the Phase 2 close, the decision remained **DO NOT AUTHORIZE
UPLOADS**: exact-ID cleanup and the
four trial-only merges plus the workspace correction are verified and the five
final-archive measurements are complete, but orchestration currently reports
`upload_allowed=false`. Private-repository usage also remains `unknown`. `main`
remains unchanged for rollback and may recreate `app-jar`; do not count the
corrected projection as active. The Phase 3 section below supersedes that
temporary stop after reconciling the one-retry envelope and resolving the
orchestration blocker. Private
artifact and package usage remains `unknown`; do not ask the operator to
re-investigate it.

### Phase 12 completion Phase 3 controlled-upload bridge

The credential-free Phase 3 refresh completed at `2026-09-17T11:55:40Z`. It
again enumerated all 15 public organization repositories and found 9
non-expired artifacts totaling 1,338,110 bytes, zero public caches, no
`app-jar`, all eight deleted artifact IDs absent, and every Phase 2 branch SHA
unchanged. There is therefore no current `main` recurrence to add to the
baseline. The correction remains trial-only, so any later `app-jar` recurrence
is a hard stop for the Gate C helper rather than part of the corrected
projection.

The conservative upload envelope is:

| Component | Bytes |
| --- | ---: |
| Current known public artifacts | 1,338,110 |
| One retained artifact at the 25 MiB ceiling | 26,214,400 |
| One same-size retry | 26,214,400 |
| Separate future four-service failure-diagnostic reserve | 1,330,666 |
| **Conservative public peak** | **55,097,576** |
| **Remaining against 524,288,000 bytes** | **469,190,424** |

This deliberately reserves a new failure-diagnostic window in addition to the
currently retained diagnostics. Private artifact and package bytes remain
`unknown`. The standing no-payment-method and stop-usage controls bound spend,
not capacity; a quota rejection stops the trial and never authorizes billing.

No row can be removed from the upload matrix. The five no-upload summaries
prove exact source execution, allowlist shape, and payload sizing, but GitHub's
public APIs do not expose the detailed retained contents needed to disposition
the hosted `govulncheck`, npm audit, Java graph, workspace-image, or platform-
image findings. The minimized matrix is therefore all five rows, serialized in
that order. The first four frozen SHAs remain those in the Phase 2 table. The
orchestration SHA is the clean reviewed commit containing the Phase 3 change;
the helper resolves it locally and requires the remote trial ref to match it
exactly before changing any variable.

| Order | Repository and workflow | Exact source rule | Expected artifact | Delete after local checksummed copy |
| ---: | --- | --- | --- | --- |
| 1 | `ext-authz` / `go-vulnerability-check.yml` | `75ed2bda4de7460332a8dea656def0459064753f` | `trial-govulncheck-evidence-RUN_ID` | Yes, exact captured ID only |
| 2 | `budget-analyzer-web` / `dependency-audit.yml` | `2cbef3f17f546fe167628b221a1cb9dec810c2bd` | `trial-npm-audit-evidence-RUN_ID` | Yes, exact captured ID only |
| 3 | `service-common` / `dependency-submission.yml` | `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94` | `trial-dependency-graph-evidence-RUN_ID` | Yes, exact captured ID only |
| 4 | `workspace` / `workspace-image-security-evidence.yml` | `6a6bf33fb019825b7709693a1b103c8a1dd7d726` | `trial-workspace-image-evidence-RUN_ID` | Yes, exact captured ID only |
| 5 | `orchestration` / `exact-image-security-evidence.yml` | Clean local Phase 3 HEAD must exactly equal the published trial head | `trial-exact-image-security-evidence-RUN_ID` | Yes, exact captured ID only |

The orchestration evidence helper now follows the accepted workspace behavior:
it measures source, temporary tar, and final gzip bytes, but uses only the final
gzip for the 25,165,824-byte payload decision. Missing allowlisted paths fail
instead of silently producing a partial archive. The workflow also checks the
uploaded artifact through the exact ID returned by `upload-artifact` and fails
above 26,214,400 retained bytes. Focused tests cover a compressible tar larger
than the payload cap, an incompressible payload overflow, a missing allowlisted
path, and traversal rejection.

`scripts/repo/run-dependency-automation-upload-batch.sh` is the complete Gate C
operator bridge. From a clean checkout it uses the existing authenticated `gh`
session without exposing its token. It preflights exact SHAs, trial defaults,
and false schedule/cache/upload variables for every row; inventories all public
artifacts and caches; refuses `app-jar` recurrence; enables only one upload gate;
dispatches and waits; restores that gate before run acceptance; requires one
successful source-exact run and one exact named artifact within the retained
cap; downloads the exact artifact ID; verifies the wrapper shape and SHA-256 of
both wrapper and payload; then deletes only that captured ID. It records only
selected run/artifact metadata and local checksums in an ignored sanitized JSON
ledger. A trap restores the active upload gate on every exit. Fixture tests
prove the five-row success path and failure-stop restoration.

The Phase 3 recommendation is **SAFE TO REQUEST UPLOAD BATCH GO** only after the
reviewed Phase 3 commit is published to orchestration's protected trial branch.
The operator must reply exactly `UPLOAD BATCH GO` before running:

```bash
./scripts/repo/run-dependency-automation-upload-batch.sh --confirm 'UPLOAD BATCH GO'
```

Until that separate Gate C authorization, all upload, schedule, and cache
variables remain `false`; this section records readiness, not execution.

### Phase 12 completion Phase 4 Gate C preflight stop

The operator supplied the exact `UPLOAD BATCH GO` authorization and invoked the
published bridge from orchestration source
`208c2cc96169454f2b96302c623aafe5ceeb6fd0`. The resulting sanitized ledger at
`tmp/dependency-automation/gate-c-20260917T123144Z/ledger.json` records:

- start `2026-09-17T12:31:44Z` and finish `2026-09-17T12:31:46Z`;
- `status=failed` and `failure.phase=preflight`;
- zero accepted rows and no downloaded archives;
- the unchanged five-row matrix and 26,214,400-byte retained cap; and
- `final_upload_gate_restore_succeeded=true`.

The host GitHub CLI reported `unknown flag: --json` for
`gh variable get --json`. Because this occurred while reading preflight state,
the helper dispatched no workflow and enabled no upload row. Public checks
immediately after the stop found every frozen trial SHA and trial default still
exact, including orchestration at `208c2cc96169454f2b96302c623aafe5ceeb6fd0`.
The existing service-common manual runs predate Gate C; they are not controlled-
upload evidence.

The corrected bridge uses `gh api` for repository-variable reads and PATCHes,
interfaces already required by the helper for refs, runs, artifacts, and exact-
ID deletion. The fixture now rejects any `gh variable` command, and both the
five-row success path and failed-run restoration path pass with the REST-backed
implementation. Publish the reviewed correction, verify its exact trial head,
then require a fresh `UPLOAD BATCH GO` for the retry. Until that succeeds, all
five detailed rows and the Phase 4 schedule recommendation remain pending;
**DO NOT AUTHORIZE SCHEDULES**.

## Phase 1 pilot evidence

Renovate `44.65.5` was initially run under Node `24.13.0` and rerun under the
workspace baseline Node `24.20.0` against a plain copy of the checkout. The
unpublished shared preset and repository configuration were merged in memory,
repository config discovery was suppressed, and local platform dry-run mode
was used with debug logging. This avoids resolving the not-yet-published GitHub
preset and includes newly created, untracked files.

The final extraction rerun found 98 occurrences in 34 package files:

| Manager | Files | Occurrences | Evidence |
| --- | ---: | ---: | --- |
| Dockerfile | 1 | 1 | `nginx/Dockerfile.prod-smoke-assets` -> `alpine` |
| GitHub Actions | 3 | 11 | Both existing workflows plus the new validator workflow; checkout, setup-node, Node input, and runner identities were recognized. |
| Helm values | 2 | 13 | Kyverno digest overrides and five kube-prometheus-stack image identities were recognized. |
| Kubernetes | 11 | 29 | Stateful infrastructure, Jaeger, service init images, gateway images, local first-party images, and Kubernetes API kinds were recognized. |
| Regex | 17 | 44 | Shell/Tilt chart pins, tool releases, Kind, Kiali, inline Temurin, probe images, Playwright, and the Renovate validator were recognized. |

Three of the GitHub Actions occurrences come from the manual hosted-dry-run job
and repeat already-covered runner, setup-node, and Node identities; they do not
add a new dependency surface.

The first lookup run completed in about 34 seconds and reported 57 distinct
dependency records, 31 outdated records, and 104 candidate branches before
routine limits and dashboard approvals. Live lookups succeeded for all six
configured Helm repositories, npm, and most container registries. The final
rerun completed lookup and returned 101 candidate branches, with the expected
missing-GitHub-token warning and an anonymous Docker token warning. Registry
lookup failures are retained below instead of being presented as a clean scan.

Renovate's documented local platform supports `extract` and `lookup`, not a
true `full` dry run. Passing `--dry-run=full` falls back to lookup behavior.
Therefore extraction and live lookup are demonstrated locally, but branch-file
mutation and the published preset resolution still require a no-write hosted
observation after publication. No GitHub token was available in this worker,
by design, so GitHub-backed identities were extracted with
`github-token-required` and were not looked up. Those lookups are deferred to
the user-triggered Phase 12 job, which receives its ephemeral read-only token
inside GitHub Actions.

## Phase 2 exact-image evidence

With generated `tmp/` output excluded, a Node 24 Renovate `44.65.5` extraction
rerun against the locally merged repository configuration found 108 occurrences
across 36 manager package-file records (34 distinct paths): two Dockerfile, 19
GitHub Actions, 13 Helm-values, 29 Kubernetes, and 45 regex-managed occurrences.
The same command against the pre-remediation snapshot also found 108
occurrences. This measured rerun supersedes the earlier 104-occurrence, 35-file
count, which did not reproduce.

The workflow now contributes six native GitHub Actions occurrences: checkout,
the pinned Trivy setup action, the pinned Trivy CLI input, two artifact-upload
references, and the runner identity. `mikefarah/yq` moved from one native
GitHub Actions occurrence to one `github-releases` occurrence in
`scripts/lib/pinned-tool-versions.sh`; no yq Actions occurrence remains. Its
version and complete platform checksum table remain coupled through the verified
tool contract.

The verified installer supplied Helm, kubectl, and yq `v4.53.6` for a local
offline rerun of the workflow's exact render, extraction, and target-manifest
steps. It produced the unchanged 32 distinct image/platform targets from
checked-in sources: 28 scannable production/controller refs for `linux/arm64`,
three local-only refs for `linux/amd64`, and the Istio gateway chart's unresolved
`image: auto` marker for `linux/arm64`. The workflow scans each registry ref only
after resolving the platform child digest. The `auto` marker is explicitly
unscannable without the live Istio injector, so the workflow retains it as a
known gap without turning that expected limitation into a scan error. Unexpected
render, resolution, database, and Trivy failures do fail. The render included
controller hooks, the cert-manager solver argument, the Prometheus
config-reloader argument, and all five explicit monitoring image overrides;
first-party Budget Analyzer refs remained excluded.

The previous hosted exact-image job was rejected before step execution because
the organization Actions policy did not authorize the `mikefarah/yq` action
source. That job is distinct from the Dependency Automation Configuration
workflow started by the same branch push. Local remediation does not establish
hosted admission: a replacement exact-image run, source revision, and sanitized
outcome remain pending.

Representative scans used Trivy `0.74.0` with vulnerability DB version 2,
updated `2026-09-06 07:00:11 UTC`. These observed artifact digests are evidence
for this run, not desired-version inputs:

| Baseline item | Exact platform artifact and inventory evidence | Advisory comparison |
| --- | --- | --- |
| Redis | The checked-in index selected `redis@sha256:d6550289...` for ARM64. Trivy identified Alpine 3.21.7 and 17 OS packages, but did not identify the Redis server binary/version; the only Go binary inventory was `gosu`. | `GHSA-c8h9-259x-jff4` is **missing** because the affected Redis application was not inventoried. The scan cannot prove Redis 7.4.8 or remediation. |
| Tilt Temurin base | The checked-in index selected `eclipse-temurin@sha256:609c3d51...` for AMD64. Trivy identified Alpine 3.23.4 and 44 OS packages but no OpenJDK/Temurin/JDK package or application component. | The review's JDK 25.0.3+9 observation is **missing** from scanner evidence. A successful Alpine scan does not establish the Java CPU level. |
| External Secrets | The rendered mutable tag resolved through index `sha256:876e627d...` to ARM64 artifact `ghcr.io/external-secrets/external-secrets@sha256:c2649798...`. Trivy found Debian 13.4, five OS packages, and 377 Go packages, but the primary module had an empty version. | `GHSA-r2pg-r6h7-crf3` and `GHSA-wv26-88m5-6h59` are **missing**. The unversioned primary module prevents a supported affected-version match. |
| Kyverno | The checked-in index selected `reg.kyverno.io/kyverno/kyverno@sha256:875beb24...` for ARM64. Trivy found the primary Go module as `v1.18.0+dirty`. | `GHSA-79gf-7frw-68m9` is **reproduced** as `CVE-2026-54523`; the GHSA URL is retained in the finding references and the fixed version is 1.18.2. |
| Prometheus | The checked-in index selected `quay.io/prometheus/prometheus@sha256:65acbbb6...` for ARM64. The image exposed no OS metadata, but Trivy inventoried the Go module as 3.11.1. | Stored XSS `GHSA-vffh-x6r8-xx99` is **reproduced** as `CVE-2026-40179`. Remote-read DoS `GHSA-8rm2-7qqf-34qm` is **missing** from this scan. |

The missing rows remain acceptance gaps, not clean results or false positives.
Raw inventories, vulnerability JSON, resolver manifests, stderr, and database
metadata are the authoritative workflow artifacts. Job summaries deliberately
separate OS-package and application-package counts and identify mutable source
refs; they do not infer embedded versions from tags.

## Orchestration extraction map

| Surface and source paths | Extracted identities | Lookup evidence or gap |
| --- | --- | --- |
| Production chart contract: `deploy/scripts/lib/version-contract.sh` | `base`, `external-secrets`, `cert-manager`, `kyverno`, `kube-prometheus-stack`, `kiali-server`; real Helm repository URL attached to each | All six repositories returned release metadata. Istio showed maintained-line and 1.30 proposals; later lines were also visible for the other charts. Every chart proposal is approval-gated. |
| Local chart commands: `Tiltfile` | Istio `base`, `cni`, `istiod`, and `gateway`; `kyverno`, `kube-prometheus-stack`, `kiali-server` | Lookups succeeded and repeated declarations resolve to the same datasource identities without native-manager duplication. Istio declarations are grouped per repository. |
| Production platform releases: `deploy/scripts/lib/version-contract.sh` | `k3s-io/k3s`, `kubernetes-sigs/gateway-api` | Extracted, including the literal `v` prefix and K3s `+k3sN` build component. Authenticated lookup is deferred to the Phase 12 hosted job. `PHASE4_POD_SECURITY_VERSION` is intentionally not extracted. |
| Checksum-coupled tools: `scripts/lib/pinned-tool-versions.sh` | `kubernetes/kubernetes`, `helm/helm`, `tilt-dev/tilt`, `FiloSottile/mkcert`, `kubernetes-sigs/kind`, `yannh/kubeconform`, `stackrox/kube-linter`, `kyverno/kyverno`, `mikefarah/yq`, `kubernetes-sigs/gateway-api`, `projectcalico/calico` | All identities extracted; Tilt's absent `v` and Kyverno CLI's release prefix are explicit. Authenticated lookup is deferred to the Phase 12 hosted job. Proposals are approval-gated and state that Renovate cannot regenerate the checksum table. |
| Kind node: `kind-cluster-config.yaml` | `kindest/node:v1.35.0` plus its current digest | Docker lookup succeeded and exposed separate 1.35, 1.36, and 1.37 lines. Platform/ARM64 review is approval-gated. The stale setup-flow Kind image is excluded. |
| Stateful services: `kubernetes/infrastructure/{postgresql,rabbitmq,redis}/statefulset.yaml` and annotated probe scripts listed in `scripts/lib/image-pinning-targets.txt` | `postgres:16-alpine`, `rabbitmq:3.13-management`, `redis:7-alpine`, plus exact digests | Redis lookup exposed a maintained broad-tag digest refresh and Redis 8; RabbitMQ exposed RabbitMQ 4. PostgreSQL lookup timed out in the pilot. All are approval-gated. Broad tags do not identify the embedded Redis/PostgreSQL patch, so Redis 7.4.11 parity is **missing** until a separately reviewed explicit alias or image inventory proves it. |
| Edge and utility images: service manifests, `nginx/Dockerfile.prod-smoke-assets`, and annotated smoke scripts | `nginxinc/nginx-unprivileged`, `swaggerapi/swagger-ui`, `busybox`, `alpine`, `curlimages/curl`, `mendhak/http-https-echo`, `python` | Lookups exposed later NGINX maintained/minor lines, Swagger UI lines, and updates for the probe images. Exact digest refreshes were resolved. Repeated probe refs share identities. |
| Runtime JDK: inline Dockerfile in `Tiltfile` | `eclipse-temurin:25-jre-alpine` plus digest | Digest lookup succeeded, but the broad tag exposes only digest movement and not the embedded JDK patch. JDK patch/support parity is an explicit **gap** pending image inventory/scanning. |
| Jaeger: `kubernetes/monitoring/jaeger/deployment.yaml` | `cr.jaegertracing.io/jaegertracing/jaeger:2.17.0` plus digest | Lookup exposed 2.18, 2.19, and 2.20 lines. The matching literal in `scripts/guardrails/verify-production-image-overlay.sh` remains an intentional validation companion; Renovate does not silently rewrite that assertion. |
| Monitoring image overrides: `kubernetes/monitoring/prometheus-stack-values.yaml` | `docker.io/grafana/grafana`, `registry.k8s.io/kube-state-metrics/kube-state-metrics`, `quay.io/prometheus/prometheus`, and both Prometheus Operator images | Native Helm-values extraction found all five tags. Kube-state-metrics, Prometheus, and Operator lookups produced later lines; Grafana and config-reloader had registry timeouts on repeat validation. The chart's nonstandard `sha` fields are not associated with tags by the native manager, so complete tag-plus-digest mutation is an explicit **gap** and must fail review until handled as a companion change. |
| Kiali override: `kubernetes/monitoring/kiali-values.yaml` | `quay.io/kiali/kiali:v2.24.0` plus digest | Nonstandard keys are covered by an adjacent regex annotation. Lookup was not completed because the repeat run stopped on registry host errors; chart lookup did succeed. |
| Production controller overrides: `deploy/helm-values/{cert-manager,external-secrets,kyverno}.values.yaml` | Seven Kyverno image repositories/digests; cert-manager and External Secrets are chart-only | Kyverno's digest-only structure was extracted but lacks a trustworthy tag and must not be refreshed from `latest`; all chart-value image proposals are approval-gated. Cert-manager and External Secrets omit repository/tag keys, so native image extraction cannot identify them. Rendering and exact-image scanning must close this **gap** in the later security-evidence phase. |
| GitHub Actions: `.github/workflows/*.yml` | `actions/checkout`, `actions/setup-node`, Node 24, `renovate`, and the exact-image workflow's Trivy setup/CLI and artifact upload inputs | Extraction succeeded, including all scanner inputs. yq is now extracted only as a checksum-coupled GitHub release tool, not an action. Authenticated lookups are deferred to the Phase 12 hosted job. All workflows retain `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`; runner labels are not update targets. |
| Temporary Playwright runner: `scripts/ops/grafana-ui-playwright-debug.sh` | `@playwright/test` | npm lookup succeeded. Generated runner directories remain excluded. |
| First-party local and production images | Seven approved local repositories; synchronized GHCR production artifacts under `kubernetes/production/apps` | Local names are extracted by Kubernetes but disabled by package policy. Production promotion paths are excluded so Renovate cannot desynchronize the release-owned manifest, inventory, overlays, or metadata. |

## Coverage contract status

| Baseline area implemented in orchestration | Update discovery | Security/support evidence |
| --- | --- | --- |
| Redis, PostgreSQL, RabbitMQ, NGINX, Temurin, Jaeger, Swagger UI, and other deployed third-party images | Demonstrated except the noted PostgreSQL/Grafana/config-reloader/Kiali retry gaps. Both maintained and later lines appeared where the tag encoded a version. | Exact platform scan path implemented. Representative Redis and Temurin scans retained their missing primary-application metadata instead of inferring patch levels. The remaining images are targets in the weekly/manual workflow. |
| External Secrets, Kyverno, cert-manager, Istio, kube-prometheus-stack, and Kiali charts | Demonstrated against each real chart name and repository. | Offline exact-image path implemented for rendered controllers and hooks. Kyverno advisory parity was reproduced; External Secrets advisories remain missing, and the Istio gateway `auto` image remains explicitly unscannable offline. |
| Prometheus, Grafana, Prometheus Operator, and kube-state-metrics overrides | All identities extracted; most lookups demonstrated. | All five overrides are workflow targets, including the rendered config-reloader argument. Representative Prometheus scanning reproduced stored XSS but missed the remote-read advisory. |
| K3s, Kind, Kubernetes tooling, Gateway API, Calico, Helm, Tilt, and pinned guardrail tools | Extraction demonstrated, including prefixes/suffixes; Kind lookup demonstrated. GitHub lookups are deferred to the Phase 12 hosted job. | Checksum and ARM64 compatibility remain human approval requirements. |
| GitHub Actions | Native extraction demonstrated, including the new workflow. | GitHub lookup and hosted workflow URL are deferred to Phase 12 after publication. |
| Lifecycle decisions for K3s/Kubernetes, Istio, RabbitMQ, NGINX, and image runtimes | Later release lines are visible for non-GitHub sources; GitHub-backed lines await authenticated lookup. | No automated EOL claim. Quarterly upstream lifecycle review remains required. |

The repository-specific preparation phases are now complete. Their local
evidence and every authenticated handoff are consolidated below. Local results
remain preparation evidence: they do not prove that the published preset
resolves, GitHub accepted a graph submission, a hosted scanner completed, or
the Mend App is active.

## Phase 12 activation evidence

The 2026-09-14 operator report and subsequent public checks establish the
bounded trial's zero-spend control, published trial refs, initial hosted branch
measurements, all nine Dependency Dashboards, five accepted Java graphs, alert
counts, and twelve live bot PRs. The orchestration dry run and branch
build/scan/generation jobs are linked below. All consumer second cycles passed:
workspace's automatic corrective cycle refreshed Dashboard #8 without a
repository problem, and its associated image-evidence workflow passed with zero
artifacts. Batch C added four passing routine representative PRs without an
unexpected PR or retained artifact. The completion-baseline refresh then found
one failed build on existing frontend security PR #120 and 502,562,266 current
public artifact bytes. The #120 patch changes only `package.json` while leaving
the lockfile and grouped Vitest companions unchanged, so its `npm ci` failure is
the expected rejection of a malformed proposal. The operator accepted it as a
non-representative accidental trial side effect; routine PR #122 passed the same
workflow. Phase 12 completion Phase 2 reconciled cost and found no safe complete
upload batch; detailed uploads remain unauthorized. Scheduled scanner runs and
final benchmark reconciliation remain pending behind their explicit gates. The
nested vulnerability limit and workspace lookup correction are published and
validated.

The operator must follow the ordered
[activation procedure](../dependency-automation.md#activation-procedure) and
provide public links or sanitized exports. Do not provide credentials, job
tokens, secret values, cookies, or private registry responses. Evidence should
identify the repository, source revision, UTC run time, workflow or bot-cycle
URL, tool/database version where applicable, and the final status.

### Cross-repository administrator gates

| Repository or scope | Check and configuration | Reason deferred | Operator action and required evidence | Disposition |
| --- | --- | --- | --- | --- |
| All organization repositories and 9 scoped repositories | Visibility and GitHub Actions billing/storage | The operator deleted the eight exact obsolete `app-jar` IDs. The `2026-09-17T11:55:40Z` credential-free refresh found 9 non-expired artifacts, 1,338,110 bytes, zero public caches, no public `app-jar`, and all eight IDs absent. The four regular-CI corrections remain only on exact `dependency-automation-trial` refs, while the recorded `main` SHAs remain unchanged as the rollback baseline. Public packages remain separate and unmetered under current policy. Private artifact/package usage is recorded as unknown. No payment method, `$0` billed Actions usage, and Stop-usage budgets bound spend but do not prove headroom. | Phase 3 computes a 55,097,576-byte conservative peak and leaves 469,190,424 public bytes before unknown private usage. Publish the reviewed orchestration correction, then require the exact Gate C phrase and fail-closed host helper; do not promote service fixes to `main`, add billing, or treat a quota rejection as acceptance. | **Cleanup, sizing, headroom, and controlled-upload bridge verified — Gate C pending** |
| All 9 scoped repositories | Free Mend Community support, portal profile, durability decision, and App scope | Mend's public documentation confirms that Community is free for unlimited public and private repositories, with one concurrent organization job, four-hour active scheduling, a 30-minute timeout, and hosted credential settings. The App listing says no paid plan is required. The operator reports no Mend payment method and no paid trial. Neither source promises a perpetual free tier, grandfathering, SLA, or Community helpdesk support. | The operator recorded `TRIAL GO` on `2026-09-14`, initially kept `main` default, then authorized and performed the temporary-default orchestration switch after the pre-change audit. The cap remains one 25 MiB one-day bundle and the review date remains `2026-09-21`. The discovered `main` protection defect is repaired, and the operator restricted initial App access to orchestration. Prove hosted lookup behavior before expansion. | **Bounded Community trial, orchestration switch, protection, and pilot App scope passed — hosted lookup pending** |
| Orchestration | Persistent protection for `main` and `dependency-automation-trial` during the temporary-default pilot | The operator intended active deletion, non-fast-forward, and pull-request rules on both refs. Post-run inspection found only the dynamic default target effective. The first remediation retained quoted patterns; the final saved repair uses exact unquoted refs. | Public verification at `2026-09-14T15:00:04Z` showed exact `refs/heads/main` and `refs/heads/dependency-automation-trial` conditions. Both branches independently receive deletion, non-fast-forward, and pull-request rules; both SHAs remain unchanged. Preserve the ruleset through pilot rollback. | **Passed — both branches independently protected before Step 5.4** |
| All 9 scoped repositories | Phase 12 branch workflow controls | The trial required exact branch/base triggers, trusted-ref guards, generation-only Java graphs, disabled schedules/uploads/submissions/caches, complete output measurement, and a total upload cap before publication. | Local implementation uses the exact `dependency-automation-trial` ref, four disabled-by-default repository variables, generation-only Java graph runs until both submission gates pass, cache-controlled build/scan jobs, a shared-shape sealed-archive helper in each repo, a 24 MiB payload ceiling beneath the approved 25 MiB artifact cap, and one-day trial retention. Phase 2 completed all five exact rows. Phase 3 aligns orchestration with the final-gzip gate, adds exact-ID retained-size enforcement, and supplies a fixture-tested serialized host helper that restores uploads on failure. The two initial publication-triggered consumer jobs overlapped; preserve that recorded deviation and serialize remaining work. | **Trial controls, exact measurements, and Gate C bridge passed locally — reviewed publication and explicit authorization pending** |
| Orchestration, then all consumers | Shared preset publication order | Consumer `renovate.json` files resolve the explicit orchestration trial ref. | Orchestration source and preset ref `24ffc8e36bf87a730bb6a25961059becbdb67d72` resolved successfully in hosted dry-run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973); all nine trial refs are publicly resolvable. Keep the preset ref frozen during each evidence batch. | **Trial preset publication and hosted resolution passed** |
| Orchestration | `.github/workflows/dependency-automation-config.yml`, manual dispatch with `run_hosted_dry_run=true` or the trial-only marked-push fallback | Local platform mode cannot perform a true full dry run or GitHub lookups. Before the temporary-default switch, GitHub did not expose **Run workflow**, so the branch-only workflow used its reviewed one-repository wrapper. The temporary default now permits normal manual dispatch without changing that read-only execution contract. | Marked-push run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973) established 109 dependencies in 37 package files and retained the Aqua Security IP-allow-list and anonymous Docker Hub page-11 gaps. Trial-default manual run [34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322) then passed on the same exact source/preset SHA: both jobs succeeded sequentially in 2 minutes 27 seconds, all structural hard gates passed, uploads skipped, and artifact count was zero. | **Trial-default hosted mechanics passed — individual Aqua Security and Docker Hub lookup coverage remains incomplete** |
| All 9 scoped repositories | Renovate Community App, Dependency Dashboard, dependency graph, Dependabot alerts, and update-PR ownership | Installation and settings changes are administrator-owned. | Mend is restricted to all nine selected repositories and all nine Dashboards exist. The operator reports all seven consumer onboarding jobs green after the narrowly scoped Maven correction. Five consumer graphs are accepted and graph-backed alert counts are recorded. Six representative routine PRs and six consumer vulnerability PRs use the trial base and have automerge disabled. The dedicated vulnerability limit was published through orchestration PR #62. Workspace PR #9 corrected its isolated action lookup, after which Dashboard #8 refreshed with no repository problem. | **All repositories onboarded; Batch B Dashboard and Batch C representative-PR acceptance passed** |
| Four Java consumers | Mend App-settings GitHub Packages access | Public inspection on `2026-09-13` showed all four published `service-common` Maven packages in GitHub's public-package filter. GitHub Packages still requires authentication to install public Maven packages; agents cannot inspect or receive the existing credential. | The operator stored the existing package-read credential in Mend and configured an organization-level Maven host rule scoped only to `https://maven.pkg.github.com/budgetanalyzer/service-common/`. All four Dashboards now list their applicable internal coordinates, B1 completed green, and the accepted SBOMs independently prove package resolution in Actions. | **Authenticated hosted lookup and graph package resolution passed — credential details intentionally not retained** |
| All 9 scoped repositories | Two successful Renovate cycles and one scheduled scanner cycle | Public effects show orchestration and `service-common` onboarding plus dashboard-triggered second cycles; the operator reviewed those Mend cycles without reporting an issue, but exact private timestamps/durations were not transcribed. The seven remaining repositories have one green onboarding cycle each. | The operator requested all seven B4 cycles after the shared-limit correction. Six were green initially. Workspace PR #9 corrected the only reported lookup problem; its automatic corrective cycle updated Dashboard #8 with the exact setup-trivy record and no repository problem. Do not repeat the successful Batch B cycles. Scheduled scanner cycles remain a later, separately authorized batch. | **Two-cycle Batch B acceptance passed for all nine repositories — scheduled scans pending** |
| All 9 scoped repositories | No paid features, automerge, duplicate PR owner, or first-party production promotion | Effective hosted behavior required live App evidence. | Renovate-only Community remains the sole PR owner. The operator reports Dependabot update PRs disabled. All six representative routine PRs and six consumer security PRs use the trial base with GitHub auto-merge disabled. The security burst is retained as evidence and does not authorize merge or paid features. | **No duplicate owner or automerge observed — Batches A-C passed** |

### Repository deferred-check reconciliation

| Repository | Check/workflow and affected surface | Reason deferred | Operator action and expected proof | Disposition |
| --- | --- | --- | --- | --- |
| `orchestration` | Hosted Renovate full dry run for charts, release/tool pins, Actions, Docker/Helm/Kubernetes inputs, and registry retries | GitHub token, published preset, and true full-dry-run behavior are hosted-only. | Marked-push run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973) validated the trial wrapper and preset, extracted 109 dependencies from 37 package files, selected the trial base, simulated mutations, and returned `done`. Preserve the Aqua Security IP-allow-list failures and anonymous Docker Hub page-11 failures as incomplete lookups; do not classify them as a clean lookup pass. | **Hosted mechanics passed — Aqua Security and Docker Hub lookup gaps pending** |
| `orchestration` | `.github/workflows/exact-image-security-evidence.yml` for 32 rendered targets | The prior hosted job was rejected before execution because organization policy did not authorize the yq action source. The action was replaced by the checksum-verified yq CLI. | Push run [34831702464](https://github.com/budgetanalyzer/orchestration/actions/runs/34831702464) passed on source `be9ed6b936c4e35f31d58f7056b9771918bf9889`; the exact-image workflow and scan inputs are unchanged through the current trial source. It uploaded no artifact. Retain detailed findings separately and observe one scheduled run later. | **Hosted admission and no-upload measurement passed — detailed report and scheduled evidence pending** |
| `orchestration` | Dashboard/proposals and required checks | App/settings were previously inactive. | [Dashboard #55](https://github.com/budgetanalyzer/orchestration/issues/55) proves normal onboarding and surfaces maintained-line, digest, chart, platform, checksum, and major proposals under approval/schedule controls. Representative [PR #56](https://github.com/budgetanalyzer/orchestration/pull/56) targets `dependency-automation-trial`, changes only the Renovate `44.65.5` to `44.66.1` pin, passed [run 34860772186](https://github.com/budgetanalyzer/orchestration/actions/runs/34860772186), and explicitly reports automerge disabled. The operator reported both Mend cycles looked good. Keep the PR unmerged. Live vulnerability and sustained-limit behavior remain broader-trial evidence. | **Step 5 pilot passed — later scheduled/alert evidence pending** |
| `service-common` | Hosted Renovate lookup for Gradle/catalog/wrapper/Actions | Actions and published-preset lookups require hosted GitHub access. | [Dashboard #56](https://github.com/budgetanalyzer/service-common/issues/56) shows Gradle, catalog, wrapper, Actions, maintained Spring-line and Spring 4/test-stack proposals, plus the explicit trial preset, with no visible config warning. The operator reported onboarding and post-graph cycles green. | **Passed for dashboard discovery — private log details not transcribed** |
| `service-common` | `.github/workflows/dependency-submission.yml` | The complete 216-coordinate local snapshot was not submitted. | Trial push run [34823856894](https://github.com/budgetanalyzer/service-common/actions/runs/34823856894) passed generation-only mode. Manual [run 34937981854](https://github.com/budgetanalyzer/service-common/actions/runs/34937981854) attempt 1 exposed disabled Dependency graph and automatically retained 7,444-byte artifact `10383564434` through `2026-12-14`; after enablement, attempt 2 submitted successfully at `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94`. GitHub's accepted SBOM has 222 packages. | **Accepted complete graph passed — scheduled submission pending** |
| `service-common` | Representative bot PR `build.yml`, graph/alerts, and dashboard | No App, PR, or administrator evidence was previously available. | The operator reported 89 graph-backed Dependabot alerts. Representative [PR #57](https://github.com/budgetanalyzer/service-common/pull/57) targets the trial default, changes only Gradle `9.5.0` to `9.5.1`, states automerge is disabled, and passed [build 34940825035](https://github.com/budgetanalyzer/service-common/actions/runs/34940825035) with cache and uploads off. No second PR or security-fix PR appeared. | **Manual rehearsal passed — scheduled and live vulnerability-fix PR evidence pending** |
| `currency-service` | Hosted Renovate lookup for 57 extracted records, including internal `org.budgetanalyzer` coordinates and Actions | Authenticated Maven and GitHub lookups were intentionally unavailable locally. | The post-routing-fix scan was operator-reported green with no warnings, Dashboard #84 lists the applicable internal packages through the explicit trial preset, and the operator reported the B4 cycle green. | **Hosted internal Maven lookup and second cycle passed by sanitized operator report and Dashboard evidence** |
| `currency-service` | `.github/workflows/dependency-submission.yml` | Local output had only 87 build/tool coordinates because `serviceCommon` 0.0.16 could not resolve. | Manual [run 35083509407](https://github.com/budgetanalyzer/currency-service/actions/runs/35083509407) passed at `93da3e3599e71cfa453ed78d41691fdfd1edadc3`. GitHub's accepted SBOM has 314 packages, including all applicable internal coordinates; the operator reported 108 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete graph passed — detailed advisory mapping and scheduled submission pending** |
| `currency-service` | Representative bot PR `build.yml`, graph/alerts, and settings | Historical ordinary build `34027551741` predates submission automation and is insufficient. | Routine [PR #87](https://github.com/budgetanalyzer/currency-service/pull/87) targets the trial branch, changes only Spring Boot `3.5.14` to `3.5.16`, carries the `dependencies` label, and reports automerge disabled. Internal-package-aware [build 35101624894](https://github.com/budgetanalyzer/currency-service/actions/runs/35101624894) passed at `6ee3464e7009162a2d87f8f72fd252839edfc56f`; uploads skipped, zero artifacts were retained, and the PR ref has no Actions cache entry. No second PR appeared. | **Batch C representative build and package access passed** |
| `permission-service` | Hosted Renovate lookup for 45 extracted records, including three internal coordinates and Actions | Authenticated Maven and GitHub lookups were deferred. | The operator reported green B1 onboarding and B4 cycles, and Dashboard #20 lists all three internal packages through the explicit trial preset. | **Hosted internal Maven lookup and second cycle passed by operator report and Dashboard evidence** |
| `permission-service` | `.github/workflows/dependency-submission.yml` | Local 87-coordinate graph omitted internal and application runtime/test trees. | After correcting the secret/variable scope, manual [run 35091521154](https://github.com/budgetanalyzer/permission-service/actions/runs/35091521154) passed at `a31e7c5880a3d3e742e7224297e8226d9e7a47ff`. GitHub's accepted SBOM has 236 packages and all three internal coordinates; the operator reported 54 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete graph passed — detailed advisory mapping and scheduled submission pending** |
| `permission-service` | Representative bot PR `build.yml`, graph/alerts, and settings | The original row expected one bot PR per Java consumer, but Batch C intentionally selected one representative from the four consumers. | All four consumer `build.yml` files are byte-identical. `permission-service` independently passed exact-trial build 35082242381 and accepted graph run 35091521154 with internal packages; its B4 cycle was green. Currency PR #87 proves the shared PR-event, no-trial-cache, measurement, and package-access path. No distinct `permission-service` workflow path remains untested. | **Superseded — accepted by the approved Batch C shared-workflow sample; no extra bot PR required** |
| `transaction-service` | Hosted Renovate lookup for 43 extracted records, including three internal coordinates and Actions | The first onboarding cycle returned `no-result` before the scoped Mend credential and Maven routing correction. | The operator reported post-correction green B1 and B4 results, and Dashboard #84 lists all three internal packages through the explicit trial preset. | **Hosted internal Maven lookup and second cycle passed after correction** |
| `transaction-service` | `.github/workflows/dependency-submission.yml` | Local 91-coordinate graph omitted internal, PostgreSQL, and Testcontainers trees. | After correcting the secret/variable scope, manual [run 35091855229](https://github.com/budgetanalyzer/transaction-service/actions/runs/35091855229) passed at `aa439d27aec63031ab056d4f4afe70cc43e13cca`. GitHub's accepted SBOM has 238 packages and all three internal coordinates; the operator reported 54 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete graph passed — detailed advisory mapping and scheduled submission pending** |
| `transaction-service` | Representative bot PR `build.yml`, graph/alerts, and settings | The original row expected one bot PR per Java consumer, but Batch C intentionally selected one representative from the four consumers. | All four consumer `build.yml` files are byte-identical. `transaction-service` independently passed exact-trial build 35082230614 and accepted graph run 35091855229 with internal packages; its corrected B1 and B4 cycles were green. Currency PR #87 proves the shared PR-event, no-trial-cache, measurement, and package-access path. No distinct `transaction-service` workflow path remains untested. | **Superseded — accepted by the approved Batch C shared-workflow sample; no extra bot PR required** |
| `session-gateway` | Hosted Renovate lookup for 39 extracted records, including internal coordinates, Actions, and images | Authenticated Maven and GitHub lookups were deferred. | The operator reported green B1 onboarding and B4 cycles, and Dashboard #25 lists its internal packages through the explicit trial preset. | **Hosted internal Maven lookup and second cycle passed by operator report and Dashboard evidence** |
| `session-gateway` | `.github/workflows/dependency-submission.yml` | Local 87-coordinate graph omitted the reactive application tree after a GitHub Packages HTTP 401. | After correcting the secret/variable scope, manual [run 35092673426](https://github.com/budgetanalyzer/session-gateway/actions/runs/35092673426) passed at `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5`. GitHub's accepted SBOM has 241 packages and all three internal coordinates; the operator reported 78 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete reactive graph passed — detailed advisory mapping and scheduled submission pending** |
| `session-gateway` | Representative bot PR `build.yml`, graph/alerts, and settings | The original row expected one bot PR per Java consumer, but Batch C intentionally selected one representative from the four consumers. | All four consumer `build.yml` files are byte-identical. `session-gateway` independently passed exact-trial build 35082219212 and accepted reactive graph run 35092673426 with internal packages; its B4 cycle was green. Currency PR #87 proves the shared PR-event, no-trial-cache, measurement, and package-access path. Its reactive dependency distinction is already covered by its own build and graph, not by an extra PR trigger. | **Superseded — accepted by the approved Batch C shared-workflow sample; no extra bot PR required** |
| `budget-analyzer-web` | Hosted Renovate lookup for 65 npm/lockfile/Dockerfile/Actions records | Actions and published preset were hosted-only; local Docker token acquisition repeatedly failed for Node and NGINX. | The operator reported the B4 cycle green. Retain Dashboard evidence for npm, lockfile, Node, NGINX, Actions, and setup-node proposals; detailed private lookup results were not transcribed. | **Hosted second cycle passed by operator report — detailed lookup evidence pending** |
| `budget-analyzer-web` | `.github/workflows/dependency-audit.yml` | Local audits reproduced findings, but hosted install/registry/audit execution was unobserved. | Trial push run [34823959669](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/34823959669) passed at `2cbef3f17f546fe167628b221a1cb9dec810c2bd` with uploads disabled. Retain/reconcile the detailed reports before claiming finding parity, and observe one scheduled run later. | **Hosted no-upload measurement passed — detailed report and scheduled evidence pending** |
| `budget-analyzer-web` | Representative bot PR `build.yml`, graph/alerts, and settings | Onboarding opened five vulnerability PRs before the planned representative routine proposal. | Security PRs #116–#120 remain the exact open baseline. Routine [PR #122](https://github.com/budgetanalyzer/budget-analyzer-web/pull/122) targets the trial branch, changes only `package-lock.json` for `@radix-ui/react-checkbox` `1.3.3` to `1.3.11` and its resolved Radix dependencies, carries the `dependencies` label, and reports automerge disabled. [Build 35102606776](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/35102606776) passed at `59318aa42f06a395b50f0cce50c923a923fc20f2` using the no-trial-cache path; uploads skipped, zero artifacts were retained, and the PR ref has no Actions cache entry. The Phase 1 refresh found [security PR #120 run 35069921284](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/35069921284) failed after 11 seconds at `npm ci`; its later gates skipped, the measurement step passed, and upload/enforcement steps skipped. Public diff inspection shows that #120 changes only `package.json` from Vitest 3 to 4 without updating `package-lock.json` or grouped Vitest companion packages. The operator identified it as an accidental trial-variable side effect and accepted it as non-representative. Preserve it open and unmerged until rollback; do not rerun or repair it for trial acceptance. | **Batch C routine sample passed; malformed accidental security PR #120 explicitly dispositioned** |
| `ext-authz` | Hosted Renovate lookup for 21 Go/Dockerfile/Actions/scanner records | GitHub lookups and the Go builder Docker lookup were incomplete locally. | The operator reported the B4 cycle green. Retain Dashboard evidence for preset, Actions, Go input, `golang:1.24-alpine`, modules, and scanner proposals; detailed private lookup results were not transcribed. | **Hosted second cycle passed by operator report — detailed lookup evidence pending** |
| `ext-authz` | `.github/workflows/go-vulnerability-check.yml` | Local `govulncheck` reproduced GO-2025-3540, but the hosted scanner/database path was unobserved. | Trial push run [34823939945](https://github.com/budgetanalyzer/ext-authz/actions/runs/34823939945) passed at `75ed2bda4de7460332a8dea656def0459064753f` with uploads disabled. Retain/reconcile the detailed finding before claiming advisory parity, and observe one scheduled run later. | **Hosted no-upload measurement passed — detailed finding and scheduled evidence pending** |
| `ext-authz` | Representative bot PR `build.yml`, graph/alerts, and settings | Onboarding opened a vulnerability PR before the planned representative routine proposal. | Security PR #1 remains the exact open baseline. Routine [PR #3](https://github.com/budgetanalyzer/ext-authz/pull/3) targets the trial branch, changes only `GOVULNCHECK_VERSION` from `v1.7.0` to `v1.8.0`, carries the `dependencies` label, and reports automerge disabled. [Build 35103116099](https://github.com/budgetanalyzer/ext-authz/actions/runs/35103116099) passed at `148adfc33bea6ddbff9e530b22fa6802cfddab85`; uploads skipped, zero artifacts were retained, and the PR ref has no Actions cache entry. | **Batch C representative Go build passed; bounded security baseline retained** |
| `workspace` | Hosted Renovate lookup for Dockerfile/ARG/download/Actions records | Published preset and GitHub release lookups are hosted-only. | The first B4 cycle reported `no-result` only for native `github-tags` package `aquasecurity/setup-trivy`. Workspace PR #9 disabled that one native record and added the public `git-tags` manager at `110e5f78fd995ed281d425f9da90bc81079f651d`. The automatic corrective cycle refreshed Dashboard #8 with `v0.3.1` and the exact pinned commit and no repository problem. Continue to require digest-only Ubuntu syntax and approval-gated checksum proposals. | **Hosted setup-trivy correction and Batch B second-cycle acceptance passed** |
| `workspace` | `.github/workflows/workspace-image-security-evidence.yml`, cost, and public downloads | The no-cache build may consume substantial Actions time; hosted download/build/scan paths were previously unobserved. | Trial push run [34823984859](https://github.com/budgetanalyzer/workspace/actions/runs/34823984859) passed at `d8e384474512eafb827970db8194413764b79098` in about six minutes. Corrective [run 35098592885](https://github.com/budgetanalyzer/workspace/actions/runs/35098592885) passed at `110e5f78fd995ed281d425f9da90bc81079f651d` in about four minutes. Workspace PR #10 published the same-repository trial-PR trigger at `09ee0a2afecc2af6c3a216b225537c680ef68848`, and [PR run 35100312719](https://github.com/budgetanalyzer/workspace/actions/runs/35100312719) passed. The operator accepted post-merge [run 35100778569](https://github.com/budgetanalyzer/workspace/actions/runs/35100778569) as successful without waiting; Phase 1 later confirmed its public conclusion as success. Routine [PR #11](https://github.com/budgetanalyzer/workspace/pull/11) targets the trial branch and changes only `MITMPROXY_VERSION` from `12.2.2` to `12.2.3`; [image-evidence run 35103462824](https://github.com/budgetanalyzer/workspace/actions/runs/35103462824) passed at `e44419a4c580ee81bfd611646886cd610e330887`. Upload steps skipped, zero artifacts were retained, and the PR ref has no Actions cache entry. Source-exact run [35187741819](https://github.com/budgetanalyzer/workspace/actions/runs/35187741819) measured 44,614,250 source bytes, a 44,636,160-byte temporary tar, and a 6,314,072-byte eligible gzip under the corrected helper. Retain/review the detailed inventory and scan report before claiming parity, and observe one scheduled run later. | **Batch C representative image build and scan passed; Phase 2 exact sizing complete — detailed report and scheduled evidence pending** |
| `workspace` | Graph/alerts, dashboard, and settings | Administrator settings are not visible locally. | Retain sanitized settings, dashboard/proposal and alert evidence, including explicit unversioned apt/npm/PyPI, VIA, Go amd64-only, and lifecycle limitations. | **Pending — no hosted evidence** |

## Benchmark comparison status

The user-applied workspace Node 24 rebuild is baseline context, not a Renovate
finding or bot-applied update. The active container reported Node `24.20.0`
during Phases 1–10. The historical review is unchanged; its SHA-256 is
`3c0c4075e021884227d5ecbd0861a9c4f18471e184b8fbbf8cecc1ac8014c347`.

The categories below describe preparation evidence only. Final Phase 12
dispositions require hosted URLs/artifacts and must use `reproduced`,
`superseded`, `false positive with evidence`, or `missing`.

| Baseline area | Local preparation evidence | Phase 12 disposition |
| --- | --- | --- |
| Spring Boot, Cloud, Modulith, SpringDoc, Testcontainers, and other Java dependencies | Native extraction exists in all five Java repos. GitHub now has accepted complete graphs for `service-common` and all four consumers, including internal packages and the expected servlet/reactive runtime split. | **Accepted graph coverage passed; pending** per-advisory alert mapping, maintained-line proposals, and Spring 4 migration visibility across the B4 Dashboards. |
| Frontend direct/transitive packages and toolchain majors | Renovate extracted npm/lockfile inputs; both local audits reproduced the benchmark's 20 full-tree and four production findings by package identity. | **Pending** hosted audit, alerts, dashboard, maintained patches, later majors, and bot PR checks. |
| `go-redis` and Go runtime | Local Renovate lookup found go-redis 9.7.3 and later v9 lines; local govulncheck reproduced reachable GO-2025-3540. | **Pending** hosted scanner/database evidence, alerts, Go builder lookup, and Go lifecycle migration proposal. |
| Deployed third-party images | Extraction and an exact-platform scan path exist. Redis and Temurin primary versions were not inventoried; some registry retries failed. | **Pending** full hosted image artifact and proposals; Redis, Temurin, and PostgreSQL patch parity is not established. |
| External Secrets, Kyverno, cert-manager, Istio, kube-prometheus-stack, and Kiali | Chart extraction succeeded. Representative scans reproduced Kyverno but missed both External Secrets advisories; Istio gateway `image: auto` remains offline-unscannable. | **Pending** hosted rendered scan and dashboard. Current missing advisories remain prominently unresolved. |
| Prometheus, Grafana, Operator, and kube-state-metrics | Overrides were extracted; representative Prometheus scan reproduced stored XSS but missed remote-read DoS. Grafana/config-reloader lookups timed out. | **Pending** hosted lookup/scan evidence and alert comparison. |
| K3s, Kind, Kubernetes tools, Gateway API, Calico, Helm, Tilt, and pinned tools | Extraction succeeded and Kind lookup showed maintained/later lines; GitHub-backed lookups were deferred. | **Pending** hosted lookup, checksum-complete proposals, and ARM64 review evidence. |
| Workspace base image, Node/Go/Zulu, and installed packages | Local no-cache build and Trivy scan identified Node, Zulu, and Go; Ubuntu digest-only update behavior was extracted. Unversioned installs, VIA, and Go amd64-only remain gaps. | **Pending** zero-spend approval and complete hosted build/scan. Node 24 is prerequisite context, not bot discovery. |
| EOL decisions | Some later release lines appeared locally. | **Pending** dashboard evidence and quarterly human lifecycle review; automation is not an EOL authority. |

### Named high-priority advisory reconciliation

| Advisory | Affected area | Local preparation evidence | Final disposition |
| --- | --- | --- | --- |
| `GHSA-c8h9-259x-jff4` | Redis 7.4.8 | Redis binary/version absent from Trivy inventory. | **Missing; hosted evidence pending** |
| `GHSA-7m2p-62gw-p8qq` | Spring Framework 6.2.18 | Accepted graphs expose Spring 6.2.18 in all four consumers; aggregate alert counts are recorded. | **Pending per-advisory alert mapping** |
| `GHSA-5m62-pw8w-7w9f` | Tomcat 10.1.54 | Accepted servlet-service graphs expose Tomcat 10.1.54; `session-gateway` correctly has no Tomcat package. | **Pending per-advisory alert mapping and applicability review** |
| `GHSA-9xv2-5v5q-p794` | Tomcat 10.1.54 | Accepted servlet-service graphs expose Tomcat 10.1.54; `session-gateway` correctly has no Tomcat package. | **Pending per-advisory alert mapping and applicability review** |
| `GHSA-38f8-5428-x5cv` | Netty 4.1.132 | The accepted `session-gateway` graph exposes Reactor Netty/Netty 4.1.132 and Lettuce. | **Pending per-advisory alert mapping** |
| `GHSA-8c42-7qj2-3j46` | Netty 4.1.132 | The accepted `session-gateway` graph exposes Reactor Netty/Netty 4.1.132 and Lettuce. | **Pending per-advisory alert mapping** |
| `GHSA-j3rv-43j4-c7qm` | Jackson 2.21.2 | Accepted graphs expose Jackson Databind 2.21.2 in all four consumers; aggregate alert counts are recorded. | **Pending per-advisory alert mapping** |
| `GHSA-r2pg-r6h7-crf3` | External Secrets 2.2.0 | Primary Go module had no version in representative image inventory. | **Missing; hosted evidence pending** |
| `GHSA-wv26-88m5-6h59` | External Secrets 2.2.0 | Primary Go module had no version in representative image inventory. | **Missing; hosted evidence pending** |
| `GHSA-79gf-7frw-68m9` | Kyverno 1.18.0 | Reproduced locally as `CVE-2026-54523`; fixed version 1.18.2. | **Pending hosted reproduction/supersession proof** |
| Frontend advisory set | npm lockfile | Local full and production audits reproduced the saved package identities and counts. | **Pending hosted reports/alerts and per-advisory mapping** |
| `GO-2025-3540` | go-redis 9.7.0 | Reproduced locally with a reachable `Ping` to `initConn` call path; fixed in 9.7.3. | **Pending hosted reproduction/supersession proof** |
| `GHSA-qm8v-g4f9-qhjx` | Istio 1.29.2 | Maintained Istio updates were discoverable; checked-in configuration has no `BackendTLSPolicy`. | **Pending advisory evidence and applicability record** |
| `GHSA-vffh-x6r8-xx99` | Prometheus 3.11.1 | Reproduced locally as `CVE-2026-40179`. | **Pending hosted reproduction/supersession proof** |
| `GHSA-8rm2-7qqf-34qm` | Prometheus 3.11.1 | Not reported by the representative Trivy scan. | **Missing; hosted evidence pending** |

Redis 7.4.11, Temurin 25.0.4.1, PostgreSQL 16.15, Istio 1.29.7,
maintained Spring patches, controller updates, and later migration lines must
remain visible alongside majors in the hosted dashboard. Broad image tags and
digest-only proposals are not proof of those embedded patch versions.

## Current outcome

Ecosystem-wide installation and benchmark parity are both **not established**.
The orchestration Step 5 pilot and `service-common` rehearsal passed. All seven
remaining repositories passed Batch A and B1, and all four consumer Java graphs
are accepted with complete internal-package coverage and recorded alert counts.
The graph run exposed and corrected repository controls mistakenly entered as
secrets instead of variables. The nested three-PR vulnerability limit was
published and validated before B4. Six second cycles completed green initially;
`workspace` alone exposed a hosted `setup-trivy` tag-lookup failure. Workspace
PR #9 published the public-Git-tag fallback, its corrective Dashboard cycle
showed no repository problem, and run 35098592885 passed with zero artifacts.
Batch B and its public checkpoint are complete. Batch C also passed with the
four exact routine proposals, intended diffs, successful representative runs,
disabled automerge, no PR-ref cache entries, and zero artifacts. The refreshed
baseline supersedes the stale per-repository PR rows for `permission-service`,
`transaction-service`, and `session-gateway`: their byte-identical build
workflow, own exact-trial build/graph evidence, and the approved currency PR
sample leave no unique untested PR workflow. It also records the separate
frontend security PR #120 `npm ci` failure and the 502,562,266-byte historical
public artifact peak. PR #120 is now explicitly dispositioned as a malformed,
non-representative accidental trial proposal; routine PR #122 proves the same
workflow's accepted path. Phase 2 completed the original upload sizing and cost
reconciliation with uploads unauthorized. The 2026-09-17 refresh showed that
eight deploy-unconsumed `app-jar` artifacts were 99.735220% of ordinary retained
Java CI bytes. The operator deleted those exact IDs and merged their
future-upload removal only to the four protected trial branches. Recorded
`main` SHAs remain the rollback baseline, so the corrected recurring model is
not active there and a new `main` run may recreate `app-jar`. Phase 3 resolved
the helper eligibility defect and completed the conservative headroom analysis
plus the fail-closed operator bridge. Controlled uploads now depend on
publication of that reviewed orchestration commit and the separate exact Gate C
phrase. Private usage remains explicitly `unknown` under the standing
zero-spend hard stop.
Scheduled scan cycles and final benchmark dispositions remain pending.
Existing local misses remain gaps; lifecycle and exploitability assessment
remain human work.
