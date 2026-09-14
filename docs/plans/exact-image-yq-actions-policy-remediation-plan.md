# Exact-Image yq Actions Policy Remediation Plan

Replace the organization-rejected `mikefarah/yq` GitHub Action in the exact-image
security-evidence workflow with the same `yq` release installed through the
repository's checksum-verified tool contract. Preserve YAML extraction and scan
behavior while leaving the Budget Analyzer organization Actions policy unchanged.

The observed trial-branch run was rejected before execution because SHA pinning
does not make an external action an organization-authorized action source. This
plan treats the failure as an implementation defect, not as a reason to widen the
organization allowlist. It requires no credentials, GitHub settings changes,
Mend changes, live cluster, image publication, deployment, or SSL write operation.
All git operations and hosted workflow triggers remain human-owned.

After Phase 2, a human must review, commit, and push the fix to
`dependency-automation-trial`, then provide the exact-image workflow run URL and
sanitized outcome before Phase 3 begins. Do not provide tokens, cookies, private
configuration, or authorization headers. A hosted run that passes action-policy
admission but fails later must preserve that later failure as separate evidence.

## Phase 1: Add yq To The Verified Tool Contract

### Workspace

.

### Goal

Make the exact `yq` CLI version previously supplied by the action available through
the repository-owned installer with checked-in release URLs and SHA-256 values for
every platform already supported by that installer.

### Scope

Update `AGENTS.md`, `scripts/README.md`,
`scripts/lib/pinned-tool-versions.sh`, and
`scripts/bootstrap/install-verified-tool.sh`. Keep the existing Linux and macOS,
AMD64 and ARM64 installer matrix intact.

### Non-goals

Do not edit GitHub workflows in this phase. Do not upgrade `yq` beyond the version
represented by the rejected action, weaken checksum verification, change the
organization Actions policy, add a package-manager installation, or alter any
existing pinned tool version.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`, `docs/agents-md-checkstyle.md`,
`scripts/README.md`, `scripts/lib/pinned-tool-versions.sh`,
`scripts/bootstrap/install-verified-tool.sh`, and the current
`.github/workflows/exact-image-security-evidence.yml`. Confirm from the rejected
action's source pin and upstream release metadata that the intended CLI version is
`v4.53.6`. Confirm that upstream publishes the required binary for all four
supported platform keys and that trustworthy SHA-256 evidence is available. Stop
instead of inventing a checksum or silently reducing platform support if any
artifact or checksum cannot be established.

### Execution steps

1. Update the GitHub Actions baseline in `AGENTS.md`, following
   `docs/agents-md-checkstyle.md`, with a stable rule that action-source admission
   and commit pinning are separate controls. Require checking the organization
   policy before introducing an external `uses:` reference, and prefer the
   repository's checksum-verified CLI installer when an external action is not
   authorized. Do not copy the current organization allowlist into `AGENTS.md`.
2. Update the canonical script catalog in `scripts/README.md` so
   `install-verified-tool.sh` explicitly includes `yq` and describes the same
   checksum-verification contract as the other supported release binaries.
3. Add a Renovate-annotated `mikefarah/yq` release version, platform-specific
   upstream release URLs, and checked-in SHA-256 values to
   `scripts/lib/pinned-tool-versions.sh`. Cover `linux-amd64`, `linux-arm64`,
   `darwin-amd64`, and `darwin-arm64`; preserve fail-closed behavior for unknown
   tools and platforms.
4. Extend version lookup, URL lookup, checksum lookup, and install-hint behavior
   for `yq` without changing the existing tool contracts.
5. Extend `scripts/bootstrap/install-verified-tool.sh` usage, input validation,
   and installation dispatch to install the verified standalone `yq` binary with
   executable permissions. Reuse the existing temporary-directory cleanup,
   download, checksum, and destination helpers.
6. Review the diff for accidental changes to existing versions, checksums, URLs,
   certificate behavior, install defaults, or platform normalization.

### Implementation notes

Use the standalone release binary rather than Docker, a package manager, or an
unpinned network installer. A checksum calculated only from the downloaded binary
is not provenance evidence; compare the checked-in value with upstream release
metadata and then prove the downloaded artifact matches it. Retain the existing
function names and `phase7_` compatibility unless a focused refactor is necessary.
The new `AGENTS.md` rule should remain pattern-based and point to
`scripts/bootstrap/install-verified-tool.sh` and `scripts/README.md` rather than
listing volatile versions or allowed-action patterns.

### Validation

Run `bash -n scripts/lib/pinned-tool-versions.sh` and
`bash -n scripts/bootstrap/install-verified-tool.sh`. Run ShellCheck on both files
and fix every warning. Source the version library in a read-only validation shell
and verify non-empty, correctly shaped version, URL, and 64-character lowercase
SHA-256 results for all four `yq` platform keys. Download each supported release
artifact into a uniquely created temporary directory and verify it against the
corresponding checked-in checksum; execute only the current-platform binary.
Install `yq` into another temporary directory through
`install-verified-tool.sh`, run `yq --version`, and prove it reports `v4.53.6`.
Run `git diff --check` on the changed files and review the `AGENTS.md` addition
against `docs/agents-md-checkstyle.md`.

### Completion criteria

The verified installer installs and runs `yq v4.53.6` on the current platform,
all four supported release artifacts match their checked-in checksums, existing
tool metadata remains unchanged, shell validation is clean, and the durable
action-admission rule is documented without duplicating the organization
allowlist.

## Phase 2: Replace The Rejected Action And Validate Extraction

### Workspace

.

### Goal

Remove the disallowed external action from the exact-image workflow and prove that
the repository-managed `yq` binary preserves the existing rendered-image target
extraction behavior.

### Scope

Update `.github/workflows/exact-image-security-evidence.yml` and the nearest
dependency-automation implementation evidence in
`docs/research/dependency-automation-coverage.md`. Update
`docs/dependency-automation.md` only if an operator-visible workflow contract must
change; the intended scan scope, failure semantics, upload controls, and retention
must remain unchanged.

### Non-goals

Do not change scan targets, image platforms, Trivy version or setup, artifact
contents, trial triggers, schedules, caches, upload gates, retention, permissions,
or vulnerability-result semantics. Do not add an Actions-policy exception or
replace `yq` with ad hoc YAML parsing.

### Required context

Read the completed Phase 1 files,
`.github/workflows/exact-image-security-evidence.yml`,
`scripts/security/render-image-scan-inputs.sh`,
`docs/dependency-automation.md`,
`docs/research/dependency-automation-coverage.md`, and
`docs/plans/dependency-automation-phase-12-operator-plan.md`. Inspect the hosted
failure text and distinguish this workflow from the separate Dependency Automation
Configuration workflow started by the same branch push.

### Execution steps

1. Add `yq` to the existing pinned render-tool installation step and expose the
   same temporary tools directory through `GITHUB_PATH`.
2. Replace `uses: mikefarah/yq@...` and its action-specific `with.cmd` wrapper
   with an ordinary Bash `run` step. Preserve strict failure handling, all YAML
   traversal expressions, multi-document handling, special controller-argument
   extraction, first-party image exclusion, source paths, platform labels,
   deduplication, and the `scan-work/raw-targets.tsv` output contract.
3. Confirm no `mikefarah/yq` Actions reference remains. Retain the
   `mikefarah/yq` Renovate identity only in the checksum-coupled tool inventory
   introduced in Phase 1.
4. Rerun local Renovate extraction and update
   `docs/research/dependency-automation-coverage.md` with measured counts rather
   than assuming they are unchanged. Reclassify `yq` from a native GitHub Action
   dependency to a checksum-coupled GitHub release tool and keep the hosted
   exact-image run pending until Phase 3.
5. Review `docs/dependency-automation.md` for accuracy. Do not add low-level tool
   inventory there when its existing operator-visible exact-image contract remains
   correct.

### Implementation notes

The intended change is source delivery, not YAML semantics. Keep `yq v4.53.6` so
the migration does not combine an authorization fix with a parser upgrade. A shell
step invoking a verified downloaded binary is compatible with the organization
action-source policy because it introduces no external `uses:` reference; checksum
verification remains the repository's executable supply-chain control.

### Validation

Run `actionlint .github/workflows/exact-image-security-evidence.yml`. Run
`bash -n` and ShellCheck on every shell file changed in Phases 1 and 2. Install
Helm, kubectl, and `yq` into a temporary tools directory through
`install-verified-tool.sh`; add only that directory to the validation process's
`PATH`. Run `scripts/security/render-image-scan-inputs.sh` without a Kubernetes
API, then execute the workflow's exact extraction and target-manifest steps
locally. Compare the generated target set with the pre-change contract: both
platforms are represented, the known `image: auto` marker remains visible,
controller argument images are included, first-party Budget Analyzer images are
excluded, and duplicate platform/reference pairs collapse without losing source
paths. Run strict Renovate configuration validation and local extraction to prove
the new release annotation is recognized and the removed action is absent. Run
the relevant static security guardrails, `git diff --check`, and
`rg -n 'uses:[[:space:]]*mikefarah/yq' .github/workflows`; the final command must
return no matches. Record any unavailable public download or registry lookup as a
validation failure rather than weakening the checks.

### Completion criteria

The workflow contains no rejected `mikefarah/yq` action, obtains `yq` only through
the verified installer, passes workflow and shell validation, and locally produces
the same complete deduplicated image-target contract. Dependency extraction and
coverage documentation accurately represent `yq` as a checksum-coupled release
tool, while hosted acceptance remains explicitly pending.

## Phase 3: Record Hosted Policy And Workflow Acceptance

### Workspace

.

### Goal

Confirm that the fixed trial workflow is admitted by the organization Actions
policy and record the hosted result without conflating policy admission with full
scanner success.

### Scope

Review the human-triggered or branch-push run for
`.github/workflows/exact-image-security-evidence.yml` and update
`docs/research/dependency-automation-coverage.md` plus
`docs/plans/dependency-automation-phase-12-operator-plan.md` with sanitized,
source-revision-specific evidence.

### Non-goals

Do not trigger workflows, push commits, change repository or organization
settings, install Mend, enable trial uploads/caches/schedules, delete artifacts,
or hide later render, registry, database, resolution, inventory, or scan failures.

### Required context

Read the completed Phase 2 diff, `docs/dependency-automation.md`, the Phase 12
operator plan, and the coverage report. Require the human-provided workflow URL,
event, trial source SHA, start/completion time, and sanitized job outcome. Confirm
the run used the commit containing the fix. If those prerequisites are absent,
stop and request them instead of treating local validation as hosted acceptance.

### Execution steps

1. Verify from the hosted run that GitHub admitted the job and did not report an
   organization action-source rejection for `mikefarah/yq` or another unchanged
   dependency.
2. Confirm the verified installer downloaded `yq v4.53.6`, checksum verification
   passed, and execution reached and completed the rendered-image extraction step.
3. Assess the remainder of the run independently. Record target count, platforms,
   known `image: auto` limitation, duration, measured evidence bytes, Trivy and
   database metadata, and every incomplete render/resolution/scan result available
   without secrets. Do not call the full scanner accepted merely because the
   Actions-policy defect is fixed.
4. Update the coverage report's exact-image handoff row and narrative with the run
   URL, source SHA, and accurate disposition. Update the Phase 12 operator plan's
   status and next action without rewriting historical local evidence.
5. If policy admission and `yq` extraction pass but a later independent stage
   fails, mark this remediation accepted and keep exact-image hosted acceptance
   pending on the later defect. If policy admission or `yq` extraction still
   fails, preserve the failure and do not mark this plan complete.

### Implementation notes

GitHub job admission, successful tool installation, successful YAML extraction,
and complete security scanning are separate assertions. The evidence should make
those boundaries obvious. Do not include raw debug output that contains tokens,
authorization headers, private configuration, or credential-bearing URLs.

### Validation

Verify every recorded URL and SHA against the sanitized operator evidence. Run
`git diff --check` on the changed documentation, verify relative links, and search
for contradictory claims that the exact-image hosted run is both pending and
accepted. Confirm the plan status distinguishes a repaired action-policy defect
from any remaining scan failure.

### Completion criteria

A source-matched hosted run proves organization-policy admission and successful
checksum-verified `yq` extraction, the evidence documents later workflow results
honestly, and the Phase 12 status names the correct next action. No external
settings, credentials, or unrelated workflow behavior have changed.
