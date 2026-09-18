# Dependency Automation Rollout Completion Record

**Status:** Completed
**Purpose:** Record the accepted rollout outcome without preserving obsolete
activation or recovery procedures.

The dependency-automation rollout is complete. Phases 1–10 implemented the
shared Renovate policy, repository-owned extraction, dependency submission,
ecosystem scanners, and production evidence paths across `orchestration`,
`service-common`, `currency-service`, `permission-service`,
`transaction-service`, `session-gateway`, `budget-analyzer-web`, `ext-authz`,
and `workspace`.

Hosted rehearsal results were accepted as sufficient promotion evidence. They
included successful build and scanner paths, complete Java dependency graph
submissions, Mend cycles, representative Renovate pull requests, package access,
and no-automerge behavior. The remaining controlled-artifact, scheduled-run,
and rollback-rehearsal evidence was intentionally waived. No dependency-update
pull request was accepted as part of the production conversion.

## Durable outcome

- Renovate is the sole dependency-update pull-request owner and automerge stays
  disabled. Routine and vulnerability proposals have separate concurrency
  limits, and sensitive updates remain approval-gated.
- Every repository resolves the shared preset from orchestration's normal
  default branch. Repository-specific managers and workflow implementation stay
  in the repository that owns each dependency declaration.
- GitHub dependency graph submissions, npm audit, `govulncheck`, exact-image
  scanning, and workspace image scanning remain active production controls.
- Scanner evidence uses one complete allowlisted gzip archive, a 24 MiB
  pre-upload payload cap, disabled upload-action compression, and seven-day
  retention.
- The four deployable Java services retain no regular-CI application JAR. They
  upload only failed-build JUnit XML for one day. `service-common` library
  artifacts and the frontend `dist` artifact retain their separate build
  contracts.
- The Java consumers preserve authenticated `service-common` package access and
  exclude `org.budgetanalyzer` from Maven Central. Workspace preserves the
  public `git-tags` fallback for `aquasecurity/setup-trivy`.
- The free Mend Community and GitHub included-usage boundary remains in force.
  No paid feature, payment method, self-hosted bot, credential, or automerge
  behavior was added by the rollout.

The canonical production policy, workflow matrix, evidence allowlists, settings,
operator routine, and failure triage live in
[Dependency Automation](../dependency-automation.md). The preserved
[September 6 dependency review](../research/dependency-update-review-2026-09-06.md)
remains a historical benchmark, not a version target.

## Completion authority

The direct production conversion and operator-owned merge/hosted acceptance
sequence are governed by the
[completion plan](dependency-automation-phase-12-completion-plan.md). That plan
is the immutable execution record for the conversion; this file contains no
active activation, rollback, branch-management, or hosted-operations procedure.

Repository changes alone do not perform Git or GitHub administration. The
operator owns commits, pushes, pull requests, merges, default-branch and ruleset
changes, bot settings, and hosted production acceptance.
