# Dependency Automation Human Promotion Plan

**Status:** Ready for operator execution
**Audience:** Human repository and organization administrator
**Purpose:** Promote the completed dependency-automation work directly from
the existing `dependency-automation-trial` branches to `main`, then remove all
trial-era GitHub state.

This is a human checklist, not an AI Session Handler plan. Do not run it with
AI Session Handler. Where its GitHub order differs from the manual post-plan
section of `dependency-automation-phase-12-completion-plan.md`, this checklist
governs the remaining human promotion work. The completion plan remains the
immutable record of the repository conversion.

The promotion uses no intermediate branch. Each repository has exactly one
promotion pull request:

```text
dependency-automation-trial -> main
```

The trial branch is temporarily retained only to carry that pull request. It
is deleted after the pull request merges and production verification passes.

## Repositories

Complete this checklist for:

- `orchestration`
- `service-common`
- `currency-service`
- `permission-service`
- `transaction-service`
- `session-gateway`
- `budget-analyzer-web`
- `ext-authz`
- `workspace`

Do not merge a Renovate-created dependency update as part of this promotion.
Do not create a `dependency-automation-promotion` branch or any other
intermediate branch.

## 1. Retire the GitHub trial control plane

### Suspend Mend Renovate

- [ ] Open the
  [Budget Analyzer GitHub App installations](https://github.com/organizations/budgetanalyzer/settings/installations).
- [ ] Configure the Mend Renovate installation and select **Suspend**.
- [ ] Confirm the installation reports that it is suspended.
- [ ] Do not uninstall the App, remove repository access, delete the Maven host
  rule, or remove its package-read credential.

Keep Mend suspended until every promotion pull request has merged, all nine
default branches are `main`, and the production checks below have passed.

### Complete one repository administration pass at a time

Do not make separate nine-repository passes for defaults, rules, variables,
and pull requests. Pick one repository from this table, open its three settings
links in separate tabs, and finish the checklist below before moving to the
next repository. Open the Rules page once for that repository and make all of
its ruleset changes together.

| Repository | Default-branch settings | Rules | Actions variables | Known trial-base Renovate pull requests |
| --- | --- | --- | --- | --- |
| `orchestration` | [Settings](https://github.com/budgetanalyzer/orchestration/settings) | [Rules](https://github.com/budgetanalyzer/orchestration/settings/rules) | [Variables](https://github.com/budgetanalyzer/orchestration/settings/variables/actions) | [#56](https://github.com/budgetanalyzer/orchestration/pull/56) |
| `service-common` | [Settings](https://github.com/budgetanalyzer/service-common/settings) | [Rules](https://github.com/budgetanalyzer/service-common/settings/rules) | [Variables](https://github.com/budgetanalyzer/service-common/settings/variables/actions) | [#57](https://github.com/budgetanalyzer/service-common/pull/57) |
| `currency-service` | [Settings](https://github.com/budgetanalyzer/currency-service/settings) | [Rules](https://github.com/budgetanalyzer/currency-service/settings/rules) | [Variables](https://github.com/budgetanalyzer/currency-service/settings/variables/actions) | [#87](https://github.com/budgetanalyzer/currency-service/pull/87) |
| `permission-service` | [Settings](https://github.com/budgetanalyzer/permission-service/settings) | [Rules](https://github.com/budgetanalyzer/permission-service/settings/rules) | [Variables](https://github.com/budgetanalyzer/permission-service/settings/variables/actions) | None when this plan was written |
| `transaction-service` | [Settings](https://github.com/budgetanalyzer/transaction-service/settings) | [Rules](https://github.com/budgetanalyzer/transaction-service/settings/rules) | [Variables](https://github.com/budgetanalyzer/transaction-service/settings/variables/actions) | None when this plan was written |
| `session-gateway` | [Settings](https://github.com/budgetanalyzer/session-gateway/settings) | [Rules](https://github.com/budgetanalyzer/session-gateway/settings/rules) | [Variables](https://github.com/budgetanalyzer/session-gateway/settings/variables/actions) | None when this plan was written |
| `budget-analyzer-web` | [Settings](https://github.com/budgetanalyzer/budget-analyzer-web/settings) | [Rules](https://github.com/budgetanalyzer/budget-analyzer-web/settings/rules) | [Variables](https://github.com/budgetanalyzer/budget-analyzer-web/settings/variables/actions) | [#116](https://github.com/budgetanalyzer/budget-analyzer-web/pull/116), [#117](https://github.com/budgetanalyzer/budget-analyzer-web/pull/117), [#118](https://github.com/budgetanalyzer/budget-analyzer-web/pull/118), [#119](https://github.com/budgetanalyzer/budget-analyzer-web/pull/119), [#120](https://github.com/budgetanalyzer/budget-analyzer-web/pull/120), [#122](https://github.com/budgetanalyzer/budget-analyzer-web/pull/122) |
| `ext-authz` | [Settings](https://github.com/budgetanalyzer/ext-authz/settings) | [Rules](https://github.com/budgetanalyzer/ext-authz/settings/rules) | [Variables](https://github.com/budgetanalyzer/ext-authz/settings/variables/actions) | [#1](https://github.com/budgetanalyzer/ext-authz/pull/1), [#3](https://github.com/budgetanalyzer/ext-authz/pull/3) |
| `workspace` | [Settings](https://github.com/budgetanalyzer/workspace/settings) | [Rules](https://github.com/budgetanalyzer/workspace/settings/rules) | [Variables](https://github.com/budgetanalyzer/workspace/settings/variables/actions) | [#11](https://github.com/budgetanalyzer/workspace/pull/11) |

For each repository:

1. On the Rules page, inspect every active ruleset and classic branch-protection
   rule before changing anything. Establish that `main` is explicitly protected
   or that the intended protection follows the repository's default branch.
   The resulting `main` protection must require pull-request changes and block
   deletion and force pushes. If the existing rules do not establish that
   result, correct the `main` target before continuing.
2. On the repository Settings page, change **Default branch** from
   `dependency-automation-trial` to `main`.
3. Return to the already-open Rules page and make the complete trial cleanup:

   - delete or disable each rule that targets only
     `dependency-automation-trial`;
   - when a rule targets both branches, remove only
     `refs/heads/dependency-automation-trial`; and
   - preserve a rule targeting `main` or the default branch, including its
     pull-request, deletion, and force-push protections.
4. Save all rule changes before leaving the Rules page, then confirm the
   effective rules protect `main` and no ruleset or classic protection rule
   names or targets the trial branch.
5. On the Actions variables page, delete these four repository variables:

   ```text
   DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED
   DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED
   DEPENDENCY_AUTOMATION_TRIAL_GRAPH_SUBMISSION_ENABLED
   DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED
   ```

6. Leave package credentials and production secrets unchanged.
7. Close every open Renovate pull request whose base is
   `dependency-automation-trial` without merging it. The table is the known
   starting inventory; filter the repository's open pull requests by the trial
   base and Renovate author so a newer pull request is not missed.
8. Confirm the repository home page identifies `main` as the default branch,
   then mark that repository complete:

- [ ] `orchestration`
- [ ] `service-common`
- [ ] `currency-service`
- [ ] `permission-service`
- [ ] `transaction-service`
- [ ] `session-gateway`
- [ ] `budget-analyzer-web`
- [ ] `ext-authz`
- [ ] `workspace`

Mend is suspended during this transition because `main` does not yet contain
the production conversion. Do not manually dispatch dependency automation on
the old `main` revision.

Do not delete the remote trial branch yet. Removing its protection allows the
existing local conversion commit to be pushed directly. The branch remains
only until its promotion pull request merges and production verification
passes.

## 2. Publish the completed conversion on the existing trial branches

Run Git commands from the orchestration checkout and use these repository
paths:

```text
.
../service-common
../currency-service
../permission-service
../transaction-service
../session-gateway
../budget-analyzer-web
../ext-authz
../workspace
```

Handle one repository at a time. Confirm the current branch and review all
work before pushing:

```bash
repo=.
git -C "$repo" branch --show-current
git -C "$repo" status --short
git -C "$repo" diff --check
git -C "$repo" diff main --
```

The branch must be `dependency-automation-trial`. If the production conversion
is not committed yet, stage and inspect the complete promotion:

```bash
git -C "$repo" add -A
git -C "$repo" diff --cached --check
git -C "$repo" diff --cached main --
git -C "$repo" commit -m "Promote dependency automation to production"
```

If it is already committed, inspect the local-only commits instead:

```bash
git -C "$repo" log --oneline origin/dependency-automation-trial..HEAD
git -C "$repo" diff --check origin/dependency-automation-trial..HEAD
git -C "$repo" diff --stat main...HEAD
```

Before pushing, confirm the complete `main...HEAD` change contains no bot
dependency proposal, secret, active trial variable or ref, dependency-specific
`gh api` bridge, or `app-jar` upload in the four deployable Java services.

Push the existing branch directly:

```bash
git -C "$repo" push origin dependency-automation-trial
```

If GitHub rejects the push, do not create another branch. Read the ruleset
named in the error and remove only its remaining restriction on
`dependency-automation-trial`; preserve every `main` protection.

- [ ] All nine existing trial branches contain the reviewed production
  conversion.

## 3. Open one direct promotion pull request per repository

Every pull request must show `base: main` and
`compare: dependency-automation-trial`.

| Repository | Direct promotion pull request |
| --- | --- |
| `orchestration` | [Open comparison](https://github.com/budgetanalyzer/orchestration/compare/main...dependency-automation-trial?expand=1) |
| `service-common` | [Open comparison](https://github.com/budgetanalyzer/service-common/compare/main...dependency-automation-trial?expand=1) |
| `currency-service` | [Open comparison](https://github.com/budgetanalyzer/currency-service/compare/main...dependency-automation-trial?expand=1) |
| `permission-service` | [Open comparison](https://github.com/budgetanalyzer/permission-service/compare/main...dependency-automation-trial?expand=1) |
| `transaction-service` | [Open comparison](https://github.com/budgetanalyzer/transaction-service/compare/main...dependency-automation-trial?expand=1) |
| `session-gateway` | [Open comparison](https://github.com/budgetanalyzer/session-gateway/compare/main...dependency-automation-trial?expand=1) |
| `budget-analyzer-web` | [Open comparison](https://github.com/budgetanalyzer/budget-analyzer-web/compare/main...dependency-automation-trial?expand=1) |
| `ext-authz` | [Open comparison](https://github.com/budgetanalyzer/ext-authz/compare/main...dependency-automation-trial?expand=1) |
| `workspace` | [Open comparison](https://github.com/budgetanalyzer/workspace/compare/main...dependency-automation-trial?expand=1) |

Record this decision in each pull-request description:

> Directly promotes the verified dependency-automation implementation to
> production. The remaining Gate C controlled-upload work, Gate D scheduled-run
> evidence, and rollback rehearsal were intentionally waived. No
> Renovate-created dependency update is included.

- [ ] Nine direct trial-to-`main` promotion pull requests are open.
- [ ] No intermediate promotion branch or pull request exists.

## 4. Merge orchestration first

- [ ] Require
  [Dependency Automation Configuration](https://github.com/budgetanalyzer/orchestration/actions/workflows/dependency-automation-config.yml)
  to pass on the promotion pull request.
- [ ] Merge the orchestration pull request into `main`.
- [ ] Confirm the
  [shared preset](https://github.com/budgetanalyzer/orchestration/blob/main/renovate-presets/default.json)
  exists on `main` without a trial-branch suffix.
- [ ] Require a successful production
  [Exact Image Security Evidence](https://github.com/budgetanalyzer/orchestration/actions/workflows/exact-image-security-evidence.yml)
  run on `main`.
- [ ] Confirm exactly one `exact-image-security-evidence-<run-id>` artifact
  exists, has seven-day retention, and contains the complete successful-run
  evidence set declared in the workflow.
- [ ] Delete orchestration's remote `dependency-automation-trial` branch.

Keep Mend suspended.

## 5. Merge service-common second

- [ ] Merge the `service-common` promotion pull request into `main`.
- [ ] Require a successful production
  [Build](https://github.com/budgetanalyzer/service-common/actions/workflows/build.yml).
- [ ] Require a successful
  [Dependency Submission](https://github.com/budgetanalyzer/service-common/actions/workflows/dependency-submission.yml).
- [ ] Confirm the accepted graph on the
  [Dependency graph](https://github.com/budgetanalyzer/service-common/network/dependencies).
- [ ] Delete `service-common`'s remote trial branch.

`service-common` intentionally retains its library JAR and test-result
artifacts. The deployable-service `app-jar` prohibition does not apply to this
library.

## 6. Merge and verify the remaining consumers

Merge the remaining seven pull requests only after orchestration and
`service-common` have passed.

### Deployable Java services

| Repository | Build | Dependency submission | Dependency graph |
| --- | --- | --- | --- |
| `currency-service` | [Runs](https://github.com/budgetanalyzer/currency-service/actions/workflows/build.yml) | [Runs](https://github.com/budgetanalyzer/currency-service/actions/workflows/dependency-submission.yml) | [Graph](https://github.com/budgetanalyzer/currency-service/network/dependencies) |
| `permission-service` | [Runs](https://github.com/budgetanalyzer/permission-service/actions/workflows/build.yml) | [Runs](https://github.com/budgetanalyzer/permission-service/actions/workflows/dependency-submission.yml) | [Graph](https://github.com/budgetanalyzer/permission-service/network/dependencies) |
| `transaction-service` | [Runs](https://github.com/budgetanalyzer/transaction-service/actions/workflows/build.yml) | [Runs](https://github.com/budgetanalyzer/transaction-service/actions/workflows/dependency-submission.yml) | [Graph](https://github.com/budgetanalyzer/transaction-service/network/dependencies) |
| `session-gateway` | [Runs](https://github.com/budgetanalyzer/session-gateway/actions/workflows/build.yml) | [Runs](https://github.com/budgetanalyzer/session-gateway/actions/workflows/dependency-submission.yml) | [Graph](https://github.com/budgetanalyzer/session-gateway/network/dependencies) |

For each service:

- [ ] Merge the promotion pull request.
- [ ] Require one successful normal Build run on `main`.
- [ ] Open that run's **Artifacts** section. A successful run must have no
  `app-jar` and no `test-results` artifact. The latter uploads only after a
  failed build.
- [ ] Require one successful dependency submission and confirm that GitHub
  accepted the graph.
- [ ] Delete the remote trial branch.

### Frontend

- [ ] Merge the `budget-analyzer-web` promotion pull request.
- [ ] Require a successful production
  [Build](https://github.com/budgetanalyzer/budget-analyzer-web/actions/workflows/build.yml).
- [ ] Manually dispatch
  [Dependency Audit](https://github.com/budgetanalyzer/budget-analyzer-web/actions/workflows/dependency-audit.yml)
  on `main` and require operational success.
- [ ] Confirm exactly one `npm-audit-reports` artifact exists, has seven-day
  retention, and contains the complete successful-run evidence set declared in
  the workflow.
- [ ] Delete the remote trial branch.

### External authorization service

- [ ] Merge the `ext-authz` promotion pull request.
- [ ] Require a successful production
  [Build](https://github.com/budgetanalyzer/ext-authz/actions/workflows/build.yml).
- [ ] Require a successful
  [Go Vulnerability Check](https://github.com/budgetanalyzer/ext-authz/actions/workflows/go-vulnerability-check.yml)
  on `main`.
- [ ] Confirm exactly one `govulncheck-<sha>` artifact exists, has seven-day
  retention, and contains the complete successful-run evidence set declared in
  the workflow.
- [ ] Delete the remote trial branch.

### Workspace image

- [ ] Merge the `workspace` promotion pull request.
- [ ] Require a successful
  [Workspace Image Security Evidence](https://github.com/budgetanalyzer/workspace/actions/workflows/workspace-image-security-evidence.yml)
  run on `main`.
- [ ] Confirm exactly one `workspace-image-security-evidence-<run-id>` artifact
  exists, has seven-day retention, and contains the complete successful-run
  evidence set declared in the workflow.
- [ ] Delete the remote trial branch.

Valid vulnerability findings remain reportable and non-gating. Missing output,
failed dependency resolution or submission, malformed scanner output, or an
incomplete scan is a failed production check.

## 7. Audit the final GitHub state

For all nine repositories, confirm:

- [ ] `main` is the default branch.
- [ ] `main` retains its intended pull-request, deletion, and force-push
  protections.
- [ ] No remote `dependency-automation-trial` branch remains.
- [ ] No ruleset or classic protection rule names or targets the trial branch.
- [ ] No `DEPENDENCY_AUTOMATION_TRIAL_*` Actions variable remains.
- [ ] No open pull request targets the trial branch.
- [ ] No trial-only artifact remains; delete any unexpired one from its Actions
  run page.
- [ ] GitHub's dependency graph and Dependabot alerts are enabled.
- [ ] Dependabot version updates and automatic security-update pull requests
  remain disabled so Renovate is the sole update-PR owner.
- [ ] The Mend Maven host rule remains scoped exactly to
  `https://maven.pkg.github.com/budgetanalyzer/service-common/`.

## 8. Resume Mend on production defaults

- [ ] Return to the
  [GitHub App installations](https://github.com/organizations/budgetanalyzer/settings/installations)
  and unsuspend Mend Renovate.
- [ ] Confirm Mend follows each repository's default branch and has no explicit
  trial base.
- [ ] Confirm Scan and Alert behavior remains enabled and automerge remains
  disabled.
- [ ] Let one normal Mend cycle complete in each repository.
- [ ] Review the organization
  [Dependency Dashboards](https://github.com/search?q=org%3Abudgetanalyzer+is%3Aissue+%22Dependency+Dashboard%22&type=issues).
- [ ] Review
  [Renovate pull requests targeting main](https://github.com/search?q=org%3Abudgetanalyzer+is%3Apr+author%3Aapp%2Frenovate+base%3Amain&type=pullrequests).

New routine proposals must target `main`, carry the expected `dependencies`
label, obey the three-PR routine limit, and have automerge disabled.
Vulnerability proposals must target `main`, carry the `security` label, obey
their separate three-PR limit, and have automerge disabled. A repository with
no proposal may establish health through a clean Dependency Dashboard or Mend
log; do not force an update solely to create a pull request.

## 9. Record completion

Add a final acceptance comment to the orchestration promotion pull request or
its associated change record. Include:

- [ ] Links to all nine merged promotion pull requests.
- [ ] Links to the required production workflow runs.
- [ ] Confirmation that all nine defaults are `main`.
- [ ] Confirmation that all trial branches, branch rules, variables,
  trial-base pull requests, and trial-only artifacts are gone.
- [ ] Confirmation that Mend completed a normal cycle against `main` with
  automerge disabled.

Do not edit the immutable AI Session Handler completion plan to store live
acceptance evidence.
