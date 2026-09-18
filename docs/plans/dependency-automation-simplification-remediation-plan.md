# Dependency Automation Simplification Remediation Plan

**Status:** Ready for implementation
**Type:** Simple working plan; not an AI Session Handler plan
**Purpose:** Remove the remaining trial-era evidence-packaging complexity and
transient documentation before the dependency-automation promotion is merged.

## Operator-owned work

The operator will handle Git and GitHub administration separately:

- squash-merge every promotion pull request;
- remove superseded dependency-automation plans while retaining the current
  human promotion checklist;
- complete branch, ruleset, repository-variable, pull-request, artifact, and
  Mend cleanup through GitHub.

Because promotion uses squash merges, this plan does not rewrite branch history
or remove files that already disappeared from the final branch trees.

## Repository changes

### 1. Remove the custom evidence-packaging layer

Treat the 24 MiB pre-upload threshold as retired trial policy. Seven-day
retention and normal GitHub artifact quota failures remain the production cost
boundary.

In `orchestration`, `budget-analyzer-web`, `ext-authz`, and `workspace`:

1. Delete `.github/scripts/prepare-dependency-evidence.sh`.
2. Delete the helper tests in `orchestration` and `workspace`.
3. Change the owning scanner workflow to upload its existing evidence paths
   directly with `actions/upload-artifact`:
   - keep exactly one artifact per workflow run;
   - keep `if: always()` so available diagnostics survive an earlier failure;
   - keep `if-no-files-found: error` and seven-day retention;
   - use normal upload-action compression;
   - remove precompressed archive paths, `compression-level: 0`, size outputs,
     `upload_allowed` or equivalent conditions, and separate size-enforcement
     steps.
4. Preserve the existing artifact names unless a name specifically describes a
   removed tarball.

Do not change scanner commands, evidence contents, schedules, workflow
permissions, concurrency, finding severity policy, or failure handling. Keep
`scripts/security/render-image-scan-inputs.sh` and
`ext-authz/scripts/run-govulncheck.sh`; they perform production scanning work and
are not packaging helpers.

For successful runs, every documented evidence path must be present in the one
artifact. Failed runs may retain the diagnostic paths produced before failure,
while the original failed step keeps the workflow unsuccessful.

### 2. Make documentation describe only the simplified production behavior

Update the canonical owner first:

- In `orchestration/docs/dependency-automation.md`, remove the custom archive
  helper, measurement-file, precompression, and 24 MiB contracts. Retain the
  semantic evidence allowlists, seven-day retention, one-artifact rule, and the
  rule that incomplete successful-run evidence is a failure.

Then update affected summaries and local owner docs:

- `orchestration/docs/ci-cd.md`
- `orchestration/scripts/README.md`
- `orchestration/AGENTS.md`, only if it names the retired contract
- `budget-analyzer-web/docs/dependency-automation.md`
- `ext-authz/docs/dependency-automation.md`
- `workspace/README.md`
- `workspace/AGENTS.md`
- `workspace/docs/dependency-automation.md`
- the retained human promotion checklist, replacing size and
  `upload_allowed=true` checks with confirmation that the expected single
  seven-day artifact exists and contains the successful-run evidence set

Remove validation commands that invoke the deleted helper tests. Do not copy a
new detailed archive contract into every repository; local docs should identify
their evidence paths and link to orchestration for shared policy.

### 3. Remove transient workspace documentation

In the `workspace` repository:

1. Remove the `tmp/dependency-automation/proposed` discovery command from
   `AGENTS.md`.
2. Remove the active-doc reference to the gitignored
   `tmp/dependency-automation/proposed/ai-agent-sandbox.patch`.
3. Remove the dated **Local baseline evidence** section and references to
   `tmp/dependency-automation/local-image-scan/`.
4. Keep durable extraction limitations, ARM64 caveats, safe local reproduction,
   and production validation commands.

No active documentation should depend on an ignored temporary file or preserve
point-in-time trial counts.

### 4. Clear the existing formatting failure

Remove the trailing whitespace from lines 3 and 4 of
`orchestration/docs/research/dependency-update-review-2026-09-06.md` without
changing the retained historical content.

## Validation

Run these checks after the edits:

1. In all nine repositories, run `git diff --check` against the promotion diff.
2. Run `actionlint` on every changed workflow.
3. Run `bash -n` and `shellcheck` on every remaining changed shell script.
4. Strictly validate the orchestration preset and all nine `renovate.json`
   files with the pinned Renovate validator.
5. Search active files, excluding `docs/archive/` and the retained human plan,
   and require no references to:
   - `dependency-automation-trial` or `DEPENDENCY_AUTOMATION_TRIAL_*`;
   - `prepare-trial-evidence` or `prepare-dependency-evidence`;
   - deleted evidence-helper tests;
   - `upload_allowed`, the 25,165,824-byte threshold, or the retired
     measurement-file contract;
   - `tmp/dependency-automation`.
6. Confirm the four deployable Java services still have no `app-jar` upload and
   retain only one-day failed-test XML.
7. Confirm the final diffs contain no dependency-version proposal, secret,
   dependency-specific `gh api` bridge, or unrelated service-code change.

## Completion criteria

The promotion is ready for operator squash merge when:

- scanner workflows upload one normal seven-day artifact without custom
  packaging or size-control scripts;
- active documentation contains no transient trial paths, measurements, or
  point-in-time workspace evidence;
- all static validation passes; and
- the final trees contain only durable production dependency automation and
  the retained human promotion checklist.
