# Renovate Dashboard Usability Rollout Plan

Date: 2026-10-17

Fix all ten Budget Analyzer Dependency Dashboards through the shared
orchestration preset. The consumer repositories already extend that preset and
do not need repository-local edits unless validation finds a real local
conflict.

The current problem is configuration-driven: global
`separateMultipleMinor: true` and `separateMultipleMajor: true` settings make
Renovate list every intervening release stream. The result is 260
branch-specific controls in orchestration issue #55, 266 in frontend issue
`#121`, and 781 across the ten Dashboards. Those issues are update inventories,
not usable decision queues, and they do not tell an operator what is
security-critical.

This rollout must:

- show only the latest patch, minor, and major target by default instead of
  every intervening stream;
- keep patch, minor, and major updates distinguishable;
- visually categorize routine, major, Helm/platform, stateful, chart-image,
  and checksum-coupled work;
- state clearly that the Dashboard is not severity-ranked and direct operators
  to Dependabot alerts, `security`-labelled Renovate PRs, and scanner evidence;
- preserve all existing approval gates, automerge prohibition, schedules, PR
  limits, digest pinning, image exclusions, vulnerability handling, extraction,
  and repository-specific package coupling; and
- avoid new scripts, per-repository rollout documents, sibling-repository
  edits, or manual acceptance checklists unless a concrete validation failure
  proves one is necessary.

There is one unavoidable human action: after Phase 1 passes, review and merge
the normal orchestration change so the Mend app can read the new preset from
`main`. No separate handoff record or per-repository approval is required.
Phase 2 discovers the published revision and Dashboard timestamps itself.

## Phase 1: Simplify the shared Dashboard policy

### Workspace

.

### Goal

Correct the shared preset and canonical operator guidance with the smallest
change that makes every inheriting Dashboard usable.

### Scope

`renovate-presets/default.json`, `docs/dependency-automation.md`, and the
existing dependency-automation configuration validation.

### Non-goals

Do not edit sibling repositories, update dependencies, approve Dashboard
entries, create dependency PRs, add a new validation framework, enable
automerge, enable Dependabot PR creation, or weaken review and scanner policy.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`, `docs/dependency-automation.md`,
`renovate-presets/default.json`, `renovate.json`, and
`.github/workflows/dependency-automation-config.yml`. Inspect orchestration
issue #55 as the representative failure case. Confirm any added Renovate keys
against the current Renovate documentation and the repository-pinned release.

### Execution steps

1. Set or restore `separateMultipleMinor` and `separateMultipleMajor` to their
   false default. Keep `separateMajorMinor` and `separateMinorPatch` enabled so
   the latest patch, minor, and major choices remain separate.
2. Add concise `dependencyDashboardCategory` values to the existing general
   and approval-gated package rules. Order overlapping rules so specific
   categories such as stateful, platform/Helm, chart-image, and checksum work
   win over routine or generic-major categories without changing approval.
3. Add a short shared `dependencyDashboardHeader`. Explain that approval means
   “create a PR for review,” not “this is urgent” or “merge this.” State that
   bulk approval should not be used and identify the separate security signals.
4. Update the canonical `docs/dependency-automation.md` operator section with
   the same distinction between update complexity and security severity. Keep
   the durable detail there rather than turning the Dashboard header into a
   second runbook.
5. Verify the complete diff preserves vulnerability scheduling and labels,
   automerge prohibition, routine scheduling, concurrency limits, digest
   pinning, ignored paths, first-party exclusions, grouped updates, ARM64
   review, checksum notes, and every existing approval gate.

### Implementation notes

Dashboard categories only change visual organization; they do not group or
merge branches. Do not add a global sequential-stream exception. If a future
package has a proven stepwise-upgrade requirement, it can receive a narrow,
documented package rule then. Do not enable the experimental OSV Dashboard
summary as a substitute for the repository's existing advisory and scanner
sources.

### Validation

Run JSON parsing and the existing repository-pinned strict validator against
both `renovate.json` and `renovate-presets/default.json`. Use focused `jq`
assertions to confirm the two multi-stream options are false, every rule with
`dependencyDashboardApproval: true` has a meaningful category, the header is
present, and vulnerability/automerge controls are unchanged. Run the existing
Dependency Automation Configuration workflow through normal pull-request CI.
Treat validator warnings and migrations as failures.

### Completion criteria

The shared preset and canonical guide implement latest-target, categorized,
security-honest Dashboard behavior; existing safety and extraction policy is
unchanged; strict validation and normal CI pass; and no sibling repository or
hosted Dashboard has been manually altered. The change is ready for ordinary
human review and merge.

## Phase 2: Confirm all hosted Dashboards inherited the fix

### Workspace

.

### Goal

Use one automated, read-only ecosystem check to confirm that all ten public
Dashboards regenerated from the published shared preset.

### Scope

The public GitHub API, the published orchestration preset and workflow result,
and these existing Dashboard issues:

- orchestration #55
- service-common #56
- currency-service #84
- permission-service #20
- transaction-service #84
- session-gateway #25
- budget-analyzer-web #121
- ext-authz #2
- workspace #8
- budget-analyzer-api-tests #4

### Non-goals

Do not require a user-authored handoff, manually inspect every dependency,
modify consumer repositories, use GitHub credentials, trigger Mend through an
issue checkbox, approve updates, or claim that concise Dashboards prove there
are no vulnerabilities.

### Required context

Read `AGENTS.md`, the published `renovate-presets/default.json`, the successful
Dependency Automation Configuration workflow result, and the canonical
dependency-automation guide. Require the Phase 1 change on orchestration's
default branch. If it has not been published yet, report only that prerequisite;
do not ask for additional evidence or documentation.

### Execution steps

1. Resolve the published preset revision and its publication time through
   unauthenticated GitHub endpoints.
2. Fetch all ten Dashboard issues programmatically. Accept only issue bodies
   updated after the preset publication and containing the new shared header.
   If Mend has not refreshed an issue yet, wait for its normal run rather than
   asking the user to perform a repository-specific ceremony.
3. Count branch-specific approval, schedule, and recreation controls and scan
   the bodies for categories and repeated release families.
4. Confirm no dependency family lists every intervening minor or major stream.
   Normally a family may expose at most one patch, one minor, and one major
   target. Confirm issue #55 no longer contains long runs of Renovate,
   External Secrets, Kiali, Prometheus, Swagger UI, or curl versions, and issue
   #121 no longer contains the equivalent npm stream explosion.
5. Confirm the repository-specific contracts still appear where applicable:
   React/Vitest groups, Istio and Prometheus Operator groups, workspace
   checksum approvals, API-test Python coupling, ext-authz govulncheck, and
   orchestration's stateful/platform/Helm gates.
6. Review public Renovate status for configuration warnings, migrations,
   lookup failures, or lost extraction. Escalate only a concrete failing
   repository; do not create ten routine handoffs.

### Implementation notes

This is coordinator-level, read-only validation from orchestration; it does not
execute or write in sibling repositories. Dashboard timestamps and the unique
header marker establish that the hosted issues consumed the new preset. Counts
will vary as releases appear, so structural consolidation is the primary
acceptance test rather than an exact fixed total.

### Validation

Require all ten issues to have post-publication provenance, the shared guidance
and categories, no intermediate-stream flood, and no extraction/configuration
errors. Orchestration and frontend should each shrink materially from their
260- and 266-control baselines; if either still exceeds 75 branch-specific
controls, identify the remaining repeated families and adjust the shared rules
only when the fix remains general and does not weaken review policy.

### Completion criteria

All ten existing Dashboards demonstrably inherit the published preset, are
organized around review decisions rather than version inventory, retain their
repository-specific dependency coverage and approval rules, and clearly direct
security triage to the appropriate evidence. No further user action or rollout
document is required.
