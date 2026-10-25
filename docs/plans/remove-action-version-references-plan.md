# Remove GitHub Actions Version References From Documentation

Workflow files are the only source of truth for which GitHub Actions versions
are in use. Renovate owns those refs: each external `uses:` is pinned to a full
commit SHA with a trailing `# vX` release comment that Renovate keeps current.
Documentation, `AGENTS.md`, and Renovate pull-request notes must not repeat
action versions or action-runtime majors, because every Renovate major forces
an unrelated documentation edit. The active `AGENTS.md` standard already
forbids version inventories (`docs/agents-md-checkstyle.md`, rules AG001 and
AG005). The orchestration `AGENTS.md` GitHub Actions Baseline list violates it.

Inventory taken 2026-10-25 across all sibling repositories. Every
Renovate-scoped repository SHA-pins all of its external `uses:` refs. No
script, test, or guardrail asserts an action version, so this is a
documentation and Renovate-note change only.

Removal targets:

| Repository | Location | Reference |
| --- | --- | --- |
| `orchestration` | `AGENTS.md` GitHub Actions Baseline | "Node 24-ready action majors" plus the list of `actions/checkout`, `docker/setup-qemu-action`, `docker/setup-buildx-action`, `docker/login-action`, `docker/build-push-action` versions and `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` |
| `orchestration` | `docs/dependency-automation.md` workflow matrix row and "Validation and changes" | "under Node 24"; "Node 24-ready action baseline" |
| `budget-analyzer-api-tests` | `docs/dependency-contract.md` Hosted CI and Dependency evidence | "forces JavaScript actions onto Node 24"; `actions/checkout@v7`, `actions/setup-python@v7`; "Node 24-ready first-party action majors"; `actions/upload-artifact@v7` |
| `budget-analyzer-api-tests` | `docs/dependency-automation.md` triage list | "retain Node 24-ready majors" |
| `budget-analyzer-api-tests` | `renovate.json` github-actions `prBodyNotes` | "approved Node 24-ready majors" |
| `workspace` | `docs/dependency-automation.md` evidence workflow paragraph | "Node 24 action baseline" |

Out of scope:

- Workflow `uses:` lines and their trailing `# vX` comments, which Renovate owns.
- Action names without versions, such as `actions/setup-node` or
  `gradle/actions/dependency-submission`, where the name explains behavior.
- `runs-on: ubuntu-24.04` in orchestration `AGENTS.md`. It is a deliberate
  constraint tied to the PyYAML wheel-hash contract, not a tracked version.
- Tool versions that are not GitHub Actions, such as `rhysd/actionlint` in
  workspace `native/toolchain.json` and Node 24 as a native tool runtime.
- `docs/decisions/` and `docs/archive/`, which are not active implementation
  surfaces. ADR 003's `actions/checkout@v3` is an illustrative example.
- `ai-session-handler`, which is outside the Renovate scope and uses tag refs
  without SHA pins. Raise that separately.
- Removing `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` from workflows. Whether the
  override is still needed is a separate workflow decision.

Acceptance: after all phases, the search in each phase's Validation section
finds no action version or action-runtime major outside workflow `uses:`
lines in the three repositories. The canonical rule lives once in
orchestration `docs/dependency-automation.md`, and the other docs link to it
instead of restating it.

## Phase 1: Orchestration canonical rule and AGENTS.md baseline

### Workspace

.

### Goal

Record the "workflows are the source of truth for action versions" rule once
in the dependency-automation owner doc. Replace the version list in the
`AGENTS.md` GitHub Actions Baseline with a pattern rule and a discovery
command.

### Scope

- `docs/dependency-automation.md`: add the canonical rule to "Ownership and
  update policy". Reword the workflow-matrix "under Node 24" cell and the
  "Validation and changes" Node 24 sentence without a version.
- `AGENTS.md` GitHub Actions Baseline: remove the "Node 24-ready action majors"
  sentence and the per-action version bullets. Replace them with the rule
  "external `uses:` refs are full-SHA pinned with a Renovate-managed release
  comment; do not cite action versions or runtime majors in docs". Add a
  discovery command and a link to the owner doc. Keep the workflow-scope
  JavaScript-actions runtime override requirement without naming a Node major.
  Keep the `runs-on: ubuntu-24.04` constraint, the action-source admission
  paragraph, and the cross-repo coordination sentence.

### Non-goals

- Editing any workflow file, `renovate.json`, or the shared preset.
- Editing `docs/decisions/` or `docs/archive/`.
- Changing the `ubuntu-24.04` runner constraint.

### Required context

- `AGENTS.md` (GitHub Actions Baseline section)
- `docs/agents-md-checkstyle.md` (rules AG001 and AG005; apply it to every
  `AGENTS.md` edit)
- `docs/dependency-automation.md`
- `docs/OWNERSHIP.md` (dependency automation policy owner row)

### Execution steps

1. Add a short paragraph to "Ownership and update policy" in
   `docs/dependency-automation.md`. It states that GitHub Actions refs are
   Renovate-owned, that workflow files are the only record of selected action
   versions, and that docs and Renovate notes name an action only when needed
   for behavior and never cite its version or runtime major.
2. In the same doc, reword the Dependency Automation Configuration matrix cell
   and the final "Validation and changes" sentence so neither names a Node
   major. For example, refer to "the workflow-declared Node runtime" and "the
   repository's current action baseline as declared in its workflows".
3. Rewrite the `AGENTS.md` GitHub Actions Baseline list as described in Scope.
   Use a discovery command such as
   `rg -n 'uses:' .github/workflows` to show current refs, and link to the
   new `docs/dependency-automation.md` paragraph.
4. Check the result against `docs/agents-md-checkstyle.md`.

### Implementation notes

Keep the `AGENTS.md` section pattern-based and short. The env var
`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` lives in the workflows; describe the
requirement as the workflow-scope JavaScript-actions runtime override, not by
its versioned name.

### Validation

```bash
rg -n -iP '(actions|docker|aquasecurity|gradle)/[a-z0-9_./-]+@v?[0-9]|node ?24|action majors' \
  AGENTS.md docs/dependency-automation.md
```

The search must return nothing except the intentional `ubuntu-24.04` line, if
it matches. Confirm the `AGENTS.md` discovery command runs and lists the
workflow `uses:` refs.

### Completion criteria

- The owner doc contains the canonical rule exactly once.
- `AGENTS.md` contains no action versions or Node runtime majors and links to
  the owner doc.
- No workflow, Renovate configuration, decision, or archive file changed.

## Phase 2: budget-analyzer-api-tests docs and Renovate note

### Workspace

../budget-analyzer-api-tests

### Goal

Remove action versions and action-runtime majors from the repository's
dependency docs and its github-actions Renovate pull-request note.

### Scope

- `docs/dependency-contract.md` Hosted CI and Dependency evidence paragraphs
- `docs/dependency-automation.md` "For Action changes" triage bullet
- `renovate.json` github-actions `prBodyNotes` text only

### Non-goals

- Workflow files, `pyproject.toml`, `uv.lock`, source code, and tests.
- Any other Renovate rule, matcher, or manager setting.
- The hard-coded `uv` version examples in `AGENTS.md` and
  `docs/dependency-automation.md`. They are a separate tool-version concern.

### Required context

- `AGENTS.md`
- `docs/dependency-contract.md`
- `docs/dependency-automation.md`
- `renovate.json`
- `../orchestration/docs/dependency-automation.md` (canonical rule from
  Phase 1; link to it instead of restating it)

### Execution steps

1. In `docs/dependency-contract.md` Hosted CI, replace "forces JavaScript
   actions onto Node 24" and the versioned `actions/checkout`/`actions/setup-python`
   wording with versionless descriptions. Name the actions only where the name
   explains behavior.
2. In Dependency evidence, replace "Node 24-ready first-party action majors as
   CI plus `actions/upload-artifact@v7`" with a versionless description, such
   as "the same first-party actions as CI plus `actions/upload-artifact`".
3. In `docs/dependency-automation.md`, reword the "For Action changes" bullet
   to keep least-privilege permissions, bounded artifact upload, and
   `actionlint`, without "Node 24-ready majors".
4. In `renovate.json`, reword the github-actions `prBodyNotes` entry without a
   Node major. For example: "Review the action release notes for runtime and
   input changes, then run actionlint plus the complete non-live quality
   suite."

### Implementation notes

Change text only. Preserve JSON structure and key order in `renovate.json`.

### Validation

```bash
rg -n -iP '(actions|docker|gradle)/[a-z0-9_./-]+@v?[0-9]|node ?24|action majors' \
  docs AGENTS.md renovate.json
actionlint .github/workflows/*.yml
```

The search must return nothing. Run the strict Renovate validator documented
in `docs/dependency-automation.md`, with `RENOVATE_VERSION` set from
`../orchestration/.github/workflows/dependency-automation-config.yml`:

```bash
npx --yes --package="renovate@${RENOVATE_VERSION}" \
  renovate-config-validator --strict --no-global renovate.json
```

### Completion criteria

- No action versions or Node runtime majors remain in the targeted docs or
  Renovate notes.
- The strict Renovate validator passes.
- No workflow, lockfile, source, or test file changed.

## Phase 3: workspace dependency doc

### Workspace

../workspace

### Goal

Remove the action-runtime major from workspace's evidence-workflow
description.

### Scope

- `docs/dependency-automation.md`: the `native-dependency-validation.yml`
  paragraph that says "uses the Node 24 action baseline".

### Non-goals

- Workflow files, `renovate.json`, `native/toolchain.json`, and native npm
  inputs.
- Node 24 references that describe the native tool runtime, such as
  `docs/native-user-tools.md`.
- Running the provisioner or any live-VM check.

### Required context

- `AGENTS.md`
- `docs/dependency-automation.md`
- `../orchestration/docs/dependency-automation.md` (canonical rule from
  Phase 1)

### Execution steps

1. Reword the sentence so it states the workflow's permissions and exclusions
   without naming a Node major or action version. For example: "It has only
   `contents: read`, follows the shared Actions baseline, and never invokes
   ...".
2. Search the rest of workspace's docs and `AGENTS.md` for any other action
   version or action-runtime major, and remove those too.

### Implementation notes

Workspace scripts, tests, and workflows must not read or require an
orchestration checkout. A Markdown link to the orchestration owner doc is
fine.

### Validation

```bash
rg -n -iP '(actions|docker|gradle)/[a-z0-9_./-]+@v?[0-9]|node 24 action|action baseline.*[0-9]|action majors' \
  docs AGENTS.md README.md
```

The search must return nothing. Run any documentation-link checks that
workspace `AGENTS.md` requires for docs changes.

### Completion criteria

- No action versions or action-runtime majors remain in workspace docs.
- Native tool runtime references are unchanged.
- No workflow, manifest, or Renovate configuration changed.
