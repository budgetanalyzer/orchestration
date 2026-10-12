# API Tests Renovate And Locked Dependency Graph Plan

**Status:** Proposed

This plan makes `budget-analyzer-api-tests` a normal dependency-automation
consumer with a reproducible, auditable Python dependency graph. PEP 621 in
`pyproject.toml` remains the direct compatibility contract, `uv.lock` becomes
the exact direct/transitive resolution, frozen installs become mandatory, and
Renovate owns reviewed manifest and lock updates under the shared orchestration
policy.

The work spans two repositories. `../budget-analyzer-api-tests` owns its Python
constraints, lock, local runner, repository workflows, evidence, Renovate
configuration, and local documentation. This orchestration repository owns the
shared Renovate policy, production scope, and evidence contract. Each phase
therefore operates in exactly one repository.

## Plan-wide decisions and boundaries

- Work from current `main`. Use the old `renovate` branch only as read-only
  source material for its audit design and documentation; do not merge or
  rebase that branch. The `dunno` branch is generated residue and is not an
  implementation input.
- Keep `pyproject.toml` authoritative for direct runtime, development, build,
  and test requirements. Give every direct requirement an intentional PEP 440
  lower and upper bound, or an exact pin when upstream compatibility does not
  support a credible interval. Derive the lower bound from a known-working
  version and the upper bound from a documented breaking-change boundary; do
  not invent bounds merely to create Renovate activity.
- Use a checked-in `uv.lock` as the exact, machine-generated graph. It must
  capture every selected direct and transitive Python distribution, source,
  marker, version, and integrity record needed by the supported Python/runtime
  contract. Never edit the lock manually.
- Pin the supported Python patch line in a standard file consumed by local and
  hosted setup. Keep the PEP 621 `requires-python` interval consistent with
  that runtime contract and make Renovate discover the runtime pin.
- Keep bootstrap and scanner tools outside the application graph but pin them
  exactly, expose them to Renovate through native managers or narrow local
  regex managers, record their versions in evidence, and review them like
  other dependency inputs.
- Make normal installs frozen. `run-tests`, CI, and audit jobs must fail when
  `pyproject.toml` and `uv.lock` disagree; they must never refresh the lock as
  an incidental side effect.
- Audit the complete selected test environment, including development/test and
  build requirements. Keep the first-party editable package, the `uv`
  bootstrap, and the `pip-audit` scanner distinguishable from the third-party
  graph so parity checks cannot silently omit or add packages.
- Treat the Playwright Python package as the owner of its coupled browser
  revision. Record the derived browser metadata in evidence without installing
  a browser in dependency-only workflows and without inventing a second
  independently updated browser version.
- Use only Node 24-ready action majors and confirm organization admission
  before adding any external `uses:` source. Prefer pinned CLI installation
  from standard package data over introducing an unapproved action.
- Preserve non-gating vulnerability findings, but fail for malformed or
  incomplete resolution, installation, inventory, SBOM, audit, lock-parity, or
  upload evidence.
- Do not contact a Budget Analyzer deployment, provision browser identities,
  install Chromium, or require application credentials in dependency CI or
  audit jobs. Live `./run-tests` remains a separate final regression gate when
  its documented local prerequisites are available.
- Do not perform GitHub or Mend administration, credential use, commits,
  pushes, or publication from an agent. The human activation gate below is a
  real prerequisite, not work to bypass from the development VM.

## Auditable-graph acceptance contract

The result is complete only when all of the following agree for the selected
Python environment:

1. bounded direct declarations in `pyproject.toml`;
2. the exact checked-in `uv.lock` resolution;
3. a frozen installed environment;
4. a stable machine-readable package inventory and dependency tree;
5. a CycloneDX SBOM and `pip-audit` dependency records;
6. Renovate extraction and lock maintenance; and
7. the repository's documented GitHub dependency-graph/Dependabot coverage.

Exact set and version parity must be machine-checked. A report that silently
misses one selected distribution is an operational failure, not clean
evidence. If GitHub does not natively ingest the complete `uv.lock` graph,
record that limitation explicitly; the repository-owned inventory, SBOM, and
audit remain mandatory, and a separate reviewed dependency-submission design
is required before claiming complete hosted graph coverage.

## Human activation gate

Run Phases 1 through 5 as the preparation sequence and stop. The human then
publishes the reviewed changes and performs these host/administrator-owned
actions before Phase 6:

1. Add `budgetanalyzer/budget-analyzer-api-tests` to the free Mend Renovate
   Community App scope. The current Developer Portal has no repository-level
   "Scan and Alert" or automerge controls; installation enables execution,
   while GitHub and the checked-in Renovate configuration own default-branch,
   dashboard, scheduling, and automerge behavior.
2. Enable GitHub's dependency graph and Dependabot alerts. Keep Dependabot
   version updates and automatic security-update pull requests disabled so
   Renovate remains the only update-PR owner.
3. Run the normal CI and dependency-evidence workflows from trusted `main` and
   confirm both succeed.
4. Run Renovate successfully in Mend Renovate Community Cloud and confirm that
   it creates or updates the Dependency Dashboard.
5. Confirm that GitHub's dependency graph is populated and Dependabot alerts
   are enabled. Explicit human administrator confirmation plus public workflow,
   dashboard, and revision references is sufficient activation evidence; do
   not transfer private logs, tokens, cookies, or administrator credentials
   into the guest.

The supervising human administrator explicitly confirmed during activation
that revision `45aa5835fb5acda29d51f252a116fe2d33b693ce` was published to
`main`, the repository was added to Mend Renovate Community Cloud, the hosted
Mend job succeeded, the GitHub dependency graph and Dependabot-alert settings
were saved with automatic Dependabot updates disabled, the graph is populated,
and the alerts page is enabled. Public corroboration includes the successful
[CI run](https://github.com/budgetanalyzer/budget-analyzer-api-tests/actions/runs/38258164820),
[Python Dependency Evidence run](https://github.com/budgetanalyzer/budget-analyzer-api-tests/actions/runs/38258164896),
native uv graph-update run, and open
[Dependency Dashboard](https://github.com/budgetanalyzer/budget-analyzer-api-tests/issues/4).
This explicit confirmation is the Phase 6 human input; no private or detailed
evidence bundle is required.

Run the first invocation with a phase cap that stops before Phase 6. Resume the
same plan only after the human explicitly confirms the hosted activation
results. Phase 6 must stop rather than infer that activation succeeded when
confirmation or public results are absent.

## Phase 1: Define And Lock The Python Dependency Contract

### Workspace

../budget-analyzer-api-tests

### Goal

Replace unbounded Python declarations with an intentional compatibility
contract and add an exact `uv.lock` graph for the supported Python runtime.

### Scope

`pyproject.toml`, the standard Python runtime pin, `uv.lock`, bootstrap/scanner
tool declarations needed to create or inspect the lock, focused dependency
documentation, and deterministic tests or checks for the declaration policy.

### Non-goals

Do not change API behavior, test coverage, authentication, environment policy,
or OpenAPI snapshots. Do not add CI, audit workflows, or activate Renovate in
this phase. Do not reuse a historical version merely because it appeared on the
old branch.

### Required context

- `AGENTS.md`
- `pyproject.toml`
- `README.md`
- `run-tests`
- the installed environment and package metadata, if present, as discovery
  evidence rather than a source of truth
- `../orchestration/docs/dependency-automation.md`
- `../orchestration/renovate-presets/default.json`
- read-only `git show renovate:renovate.json` and
  `git show renovate:docs/dependency-automation.md` for historical intent

### Execution steps

1. Inventory every direct runtime, test/development, and build requirement and
   the exact versions selected by a fresh successful Python 3.12 environment.
   Record which imports, tools, and test paths justify each direct dependency;
   remove a declaration only when repository usage proves it unnecessary.
2. Select and document the supported Python 3.12 patch release. Add the
   standard exact runtime pin consumed by local setup and GitHub Actions, and
   align `requires-python` to the supported 3.12 compatibility interval.
3. Choose current reviewed versions for the `uv` bootstrap and `pip-audit`
   scanner. Keep their exact pins in one discoverable declarative location or
   workflow environment field rather than duplicating mutable values.
4. Give every direct Python requirement an intentional bounded interval or
   exact pin. Use the verified installed version as the initial lower bound;
   use the next documented breaking line as the upper boundary. Treat 0.x
   libraries according to their actual compatibility policy rather than
   assuming the next major is safe.
5. Ensure the selected build backend is part of the locked/audited tool set.
   If editable installation would otherwise create an untracked isolated build
   environment, make the locked build requirement explicit and use the
   documented no-build-isolation path backed by that locked requirement.
6. Generate `uv.lock` from `pyproject.toml` with the pinned Python/runtime
   contract. Inspect sources, markers, optional groups, hashes, and selected
   versions; reject undeclared indexes, VCS/path dependencies, unresolved
   local state, or missing build/test packages.
7. Add a deterministic repository check that rejects bare unbounded direct
   requirements, inconsistent Python constraints, a stale lock, missing
   expected dependency groups, and accidental nonstandard package sources.
   Keep reusable logic in typed source code and tool entrypoints thin, in line
   with repository standards.
8. Document why the manifest uses ranges while the lock uses exact versions,
   how to intentionally refresh the lock, and which files reviewers must
   examine together. Mark hosted automation as not yet active.

### Implementation notes

Prefer PEP 621 and standard dependency groups supported by the pinned `uv` and
Renovate versions. Do not retain `dev` as a publishable extra merely for
historical convenience if a PEP 735 development group expresses the real
contract better; if it is migrated, update every consumer atomically. Keep the
lock universal where `uv` supports that representation, while defining one
exact selected runtime for parity and audit evidence.

Do not hand-author expected transitive versions in tests. Tests should derive
the selected graph from `uv`'s stable export/inventory interfaces and compare
sets and versions.

### Validation

- Parse `pyproject.toml` and the runtime/tool pin files with their native
  parsers.
- Run the repository's dependency-contract check.
- Run `uv lock --check` with the pinned `uv` and Python versions.
- Export the complete selected graph in a stable requirements form and verify
  that every selected requirement is exact and carries the expected integrity
  metadata.
- Run focused unit tests for new dependency validation logic.
- Run Ruff formatting/checking and strict mypy for all changed Python code.

### Completion criteria

Every direct dependency has a reviewed compatibility rationale, the supported
Python and dependency tools have exact discoverable pins, `uv.lock` is current
and free of unexpected sources, and automated checks fail for an unbounded or
stale declaration. No hosted or live-system prerequisite is required to prove
this phase.

## Phase 2: Make Local Execution Consume The Frozen Graph

### Workspace

../budget-analyzer-api-tests

### Goal

Make the supported local setup and dependency inventory reproduce and verify
the checked-in lock instead of resolving the newest admissible packages on each
run.

### Scope

`run-tests`, local dependency inventory/reporting, any narrowly required
bootstrap helper, unit tests, ignored markers/artifacts, and local setup
documentation.

### Non-goals

Do not add hosted workflows or Renovate configuration. Do not alter live API
test semantics, environment selection, TLS verification, account provisioning,
or browser installation ownership.

### Required context

- Phase 1 outcome and changed dependency files
- `AGENTS.md`
- `run-tests`
- `src/api_tests/local_runner.py`
- local runner and tool tests under `tests/unit/`
- `README.md`
- `.gitignore`

### Execution steps

1. Change the local bootstrap to install/use the exact reviewed `uv` version
   and synchronize the project environment from `uv.lock` in frozen mode. A
   changed manifest, runtime pin, tool pin, or lock must invalidate the local
   readiness marker; ordinary execution must never regenerate the lock.
2. Preserve the existing exact Python 3.12 guard and strengthen it to match the
   checked-in runtime pin where appropriate. Emit a clear prerequisite error
   when that interpreter is unavailable instead of silently selecting another
   interpreter or downloading one without an explicit repository contract.
3. Keep the project importable from its `src/` layout using the locked build
   requirements. Ensure the bootstrap tool and editable first-party project do
   not masquerade as third-party graph members.
4. Preserve Playwright Chromium's lazy local installation after the frozen
   Python sync. Derive it from the locked Playwright package and do not run that
   installation in dependency-only checks.
5. Replace the unconstrained `pip freeze` inventory with stable evidence that
   records the runtime, `uv` version, lock identity, installed package set, and
   exact lock-versus-environment parity. Keep generated outputs inside the
   existing ignored run-artifact directory.
6. Add tests for first install, unchanged reuse, manifest/lock/tool/runtime
   invalidation, stale-lock failure, failed synchronization, and inventory
   mismatch. Mock subprocess and filesystem boundaries; unit tests must not
   download packages or browsers.
7. Update README setup and troubleshooting so intentional dependency updates
   use the documented lock-refresh command while normal `./run-tests` remains
   frozen.

### Implementation notes

Bootstrap convenience must not weaken reproducibility. It is acceptable for a
first local run to download the exact pinned `uv` and locked packages, but the
selected versions and sources must come from checked-in declarations. Do not
write credentials, package-index tokens, cookies, or request authorization into
dependency artifacts.

### Validation

- `sh -n run-tests`
- `shellcheck run-tests` and every changed shell helper, with no unexplained
  suppression
- focused unit tests for bootstrap and inventory behavior
- a clean temporary virtual environment synchronized with frozen lock mode
- the repository dependency-contract and lock/environment parity checks
- `.venv/bin/python -m pytest tests/unit --env local`
- `.venv/bin/python -m pytest tests/api --env local --collect-only`
- `.venv/bin/python -m pytest tests/api --env production -m "readonly and production_safe" --collect-only`
- `.venv/bin/python -m ruff format --check .`
- `.venv/bin/python -m ruff check .`
- `.venv/bin/python -m mypy src tests`

### Completion criteria

A clean local bootstrap installs exactly the checked-in graph, a stale lock
fails before test execution, repeated runs reuse only a matching environment,
and local inventory proves exact lock/environment parity without contacting a
Budget Analyzer deployment.

## Phase 3: Add Locked CI And Complete Dependency Evidence

### Workspace

../budget-analyzer-api-tests

### Goal

Add hosted checks that enforce the frozen graph on every change and produce one
bounded, reviewable artifact proving complete resolution and vulnerability
scan coverage.

### Scope

GitHub Actions CI, the Python dependency-evidence workflow, repository-owned
evidence generation/validation code, exact artifact allowlists, tests, and
workflow documentation required to operate those paths.

### Non-goals

Do not activate Mend Renovate or change repository settings. Do not run live
API tests, install browsers, use staging/production credentials, or make
vulnerability findings merge-gating without a separate policy decision.

### Required context

- Phases 1 and 2 outcomes
- `AGENTS.md`
- `.github/workflows/` and current absence/presence of hosted checks
- `../orchestration/docs/dependency-automation.md`
- `../budget-analyzer-web/.github/workflows/dependency-audit.yml`
- `../ext-authz/.github/workflows/go-vulnerability-check.yml`
- read-only
  `git show renovate:.github/workflows/python-dependency-audit.yml`
- the current organization action-source and Node 24 baseline

### Execution steps

1. Add normal CI for pushes to and pull requests targeting `main`, plus manual
   dispatch. Use the exact runtime/tool pins, perform a frozen sync, run the
   dependency contract/parity verifier, deterministic unit tests, both required
   API collection gates, Ruff, and strict mypy. Keep live gateway execution out
   of untrusted CI.
2. Add a scheduled/manual dependency-evidence workflow, and run it on trusted
   `main` changes that affect dependency declarations, locks, scanners, or the
   evidence implementation. Give it read-only token permissions and isolated
   bootstrap, project, and scanner environments.
3. Generate stable evidence for the selected graph: runtime and tool metadata,
   the exact exported lock selection, installed package inventory, dependency
   tree, lock/environment parity result, CycloneDX SBOM, `pip-audit` JSON and
   human-readable findings, scanner stderr/exit status, Playwright-derived
   browser metadata, diagnostics, and an overall completion record.
4. Compare exact normalized package names and versions across lock export,
   installed inventory, SBOM, and `pip-audit` dependencies. Define and document
   narrow exclusions for only the first-party editable package and isolated
   bootstrap/scanner tools. Fail for any other missing, extra, duplicated, or
   mismatched distribution.
5. Accept vulnerability exit status only when valid complete output explains
   it. Keep findings visible and non-gating; fail for resolver, index,
   installation, schema, parity, SBOM, scanner-service, or unexpected-exit
   errors.
6. Upload exactly one seven-day artifact under `if: always()` with an explicit
   file allowlist and `if-no-files-found: error`. Validate that every declared
   successful-run output exists before upload; a failed run may retain only the
   diagnostics produced before the original failure and must remain failed.
7. Use Node 24-ready first-party action majors. Do not introduce an external
   action unless the effective organization policy is first proven to admit
   it; use pinned CLI contracts when equivalent.
8. Add deterministic tests for graph normalization, exact-set comparison,
   malformed scanner output, findings versus operational failure, incomplete
   evidence, and redaction. Update repository docs with events, permissions,
   artifact contents, retention, and failure interpretation.

### Implementation notes

The checked-in lock is durable evidence; the workflow artifact proves what a
specific hosted run selected, installed, inventoried, and scanned. Preserve
both. Avoid broad directory uploads: the artifact path list is a semantic
allowlist, not a convenience glob.

If `pip-audit` can emit the chosen CycloneDX form directly without losing the
normal vulnerability report, use its pinned supported interface. Otherwise use
a separately pinned standard tool and give it the same Renovate and evidence
treatment; do not write an ad hoc SBOM format.

### Validation

- Parse every workflow as YAML and run `actionlint` with no findings.
- Run `bash -n` and `shellcheck` on extracted or repository-owned shell code.
- Run focused unit tests for evidence generation and completeness enforcement.
- Execute the dependency-evidence implementation locally against a fresh
  frozen environment without contacting Budget Analyzer, and inspect every
  allowed output for completeness and secrets.
- Run all CI commands locally with the pinned runtime and frozen graph.
- Verify workflow permissions, events, concurrency, retention, and action
  majors by direct inspection.

### Completion criteria

Every pull request is gated by a frozen install and deterministic quality
checks, and a credential-free local reproduction produces one complete,
bounded evidence set whose lock, environment, SBOM, and vulnerability records
have exact package/version parity.

## Phase 4: Define The Pending Consumer In Shared Policy

### Workspace

.

### Goal

Extend the canonical dependency-automation policy with the Python locked-graph
contract while honestly recording `budget-analyzer-api-tests` as prepared but
not yet activated.

### Scope

`docs/dependency-automation.md` as canonical owner, `docs/OWNERSHIP.md` only if
ownership genuinely changes, and narrow orchestration cross-links or shared
preset changes proven necessary by the new consumer.

### Non-goals

Do not edit API-tests files from this phase. Do not claim the repository is in
production Mend scope, change external settings, broaden credentials, or add a
shared rule that belongs only to this Python test harness.

### Required context

- `AGENTS.md`
- `docs/OWNERSHIP.md`
- `docs/dependency-automation.md`
- `renovate-presets/default.json`
- `.github/workflows/dependency-automation-config.yml`
- Phases 1 through 3 outcomes and API-tests evidence contract

### Execution steps

1. Update the canonical policy first with a pending-consumer section for
   `budget-analyzer-api-tests`. Define PEP 621 ownership, bounded direct ranges,
   `uv.lock`, frozen installation, exact graph parity, scanner/SBOM evidence,
   Playwright-derived metadata, and the repository-owned CI/audit boundaries.
2. Define the future workflow-matrix and artifact-contract rows, clearly marked
   pending until hosted activation evidence is accepted. Keep the current
   active production-scope count truthful.
3. Define Renovate ownership for PEP 621 declarations, Python/runtime and tool
   pins, GitHub Actions, uv lock updates, and lock-file maintenance. Preserve
   automerge-off, weekly scheduling, major-update approval, and sole update-PR
   ownership.
4. Add Python-specific failure triage for stale locks, incomplete resolution,
   marker/platform mismatches, index/source drift, graph parity, SBOM/audit
   omissions, and bot lock-update failures.
5. Change the shared preset only if a rule is genuinely reusable across scoped
   repositories. Keep API-specific manager enablement, grouping, and notes in
   the consumer config.
6. Confirm the human activation checklist covers Mend scope, GitHub dependency
   graph and alerts, Dependabot PR settings, hosted workflow evidence, and
   complete graph reconciliation without exposing credentials.

### Implementation notes

This phase establishes the owner contract before the API repository publishes
its summary. A pending row is deliberately not an active production claim.
Do not copy exact API workflow commands into the central owner when the
repository-local document is the closer implementation source.

### Validation

- Review the updated policy against `docs/OWNERSHIP.md` for one canonical
  owner and nonduplicated summaries.
- Validate Markdown links and references with repository-supported checks.
- If the shared preset changes, run the pinned strict Renovate validator from
  `.github/workflows/dependency-automation-config.yml` and run `actionlint` on
  that workflow.
- Confirm active versus pending repository counts and workflow rows are
  internally consistent.

### Completion criteria

The central owner defines the complete Python locked-graph and activation
contract, labels API tests as pending rather than active, and leaves the shared
preset valid and no broader than necessary.

## Phase 5: Add Renovate Configuration And Finish Pre-activation Validation

### Workspace

../budget-analyzer-api-tests

### Goal

Make the locked graph fully Renovate-compatible, document repository-local
operation, and produce a clean pre-activation handoff for the human gate.

### Scope

`renovate.json`, local dependency-automation documentation, README and
`AGENTS.md` summaries, Renovate-aware tool/runtime annotations, lock maintenance
rules, final static/workflow validation, and the operator handoff.

### Non-goals

Do not merge the old branch, activate the Mend App, change GitHub settings, use
credentials, or describe hosted checks as successful before evidence exists.

### Required context

- Phases 1 through 4 outcomes
- `AGENTS.md`
- `README.md`
- `docs/` ownership and current workflow documentation
- `../orchestration/docs/dependency-automation.md`
- `../orchestration/renovate-presets/default.json`
- `../orchestration/.github/workflows/dependency-automation-config.yml`
- read-only versions of the five files added by commit `renovate` for ideas,
  not patches
- `../orchestration/docs/agents-md-checkstyle.md` before editing `AGENTS.md`

### Execution steps

1. Add `renovate.json` extending exactly
   `github>budgetanalyzer/orchestration//renovate-presets/default`. Use native
   PEP 621, uv/lock, Python/runtime, and GitHub Actions managers first; disable
   irrelevant managers only when the pinned extractor proves an overlap.
2. Enable weekly lock-file maintenance so admissible transitive updates receive
   review even when direct ranges do not change. Add narrow package rules for
   dependencies that must move together, such as coupled test/tool families;
   inherit major approval and automerge-off from the shared preset.
3. Add narrow regex managers only for exact bootstrap/scanner values that no
   native manager discovers. Match one owned declaration, use a standard
   datasource and versioning scheme, and prove extraction with the pinned
   Renovate engine.
4. Add review notes requiring manifest, lock, runtime compatibility, full CI,
   graph evidence, and Playwright browser coupling to remain aligned. Do not
   let Renovate independently rewrite generated evidence artifacts.
5. Validate the repository config strictly with the exact Renovate version and
   Node major owned by orchestration. Run a credential-free local extraction
   and lookup against public sources; require discovery of all direct
   declarations, the lock, runtime/tool pins, and Actions with no duplicate or
   unexplained identities. Record anonymous lookup limitations rather than
   calling them success.
6. Update the repository dependency-automation document as the local source of
   truth for files, commands, graph semantics, workflow events, evidence,
   Renovate behavior, lock-refresh review, and failure triage. Link to the
   central policy for scheduling, service, cost, credentials, and activation.
7. Update README usage and `AGENTS.md` consultation/validation triggers without
   copying volatile version inventories. Apply the orchestration checkstyle and
   preserve all existing API-test constraints.
8. Run the complete non-live quality suite and evidence workflow locally. If
   exact local application/TLS/account prerequisites are present, run the full
   no-selector `./run-tests`; otherwise record the prerequisite stop honestly
   and do not bypass HTTPS or authentication.
9. Produce a concise human handoff listing the exact branch/revision, expected
   workflows, Mend/GitHub settings, evidence files, effective managers, known
   anonymous lookup limitations, and pass/fail criteria for hosted acceptance.

### Implementation notes

The old branch's five-file structure is useful, but its documentation,
unbounded-install model, broad artifact upload, and inactive Phase 12 language
are stale. Recreate the intent against current `main`; do not cherry-pick it.

Do not hardcode historical extraction counts or vulnerability totals as future
success criteria. Validate package identities and exact set parity so expected
counts are derived from current declarations.

### Validation

- Strict Renovate config validation with the orchestration-owned pinned engine
  and `--no-global` behavior.
- Credential-free Renovate extraction/dry-run logs reviewed for managers,
  identities, duplicate extraction, lock maintenance, warnings, and errors.
- `actionlint` for every workflow.
- dependency contract, `uv lock --check`, frozen clean sync, and exact graph
  parity/evidence generation.
- all deterministic pytest collection/unit gates, Ruff formatting/linting, and
  strict mypy from the repository instructions.
- shell syntax and ShellCheck for changed scripts.
- optional full `./run-tests` only under its exact documented prerequisites.
- final `git diff --check` and confirmation that generated environments,
  reports, credentials, and session data are untracked.

### Completion criteria

The repository is technically ready for activation: Renovate can discover and
maintain every owned dependency surface, all normal installs are frozen,
CI/evidence checks pass locally, docs remain explicitly pre-activation, and the
human has an exact non-secret hosted acceptance checklist.

## Phase 6: Review Hosted Activation And Close The API Repository

### Workspace

../budget-analyzer-api-tests

### Goal

Accept human-supplied hosted evidence, resolve any repository-owned gaps, and
mark the API-tests dependency automation active only when the complete contract
has been demonstrated.

### Scope

Read-only review of explicitly supplied redacted GitHub/Mend evidence,
repository-owned corrections revealed by that evidence, rerun validation, and
final API-tests documentation status.

### Non-goals

Do not access or alter GitHub/Mend settings, use administrator credentials,
publish changes, weaken checks, or accept a partial graph because a hosted tool
returned success.

### Required context

- All prior phase outcomes
- the human activation-gate confirmation: published revision, successful CI
  and dependency workflow outcomes, successful hosted Mend run, Dependency
  Dashboard behavior, GitHub settings confirmation, and a populated dependency
  graph
- `AGENTS.md`
- repository dependency-automation documentation
- `../orchestration/docs/dependency-automation.md`

### Execution steps

1. Stop immediately if explicit human administrator confirmation or the public
   hosted results are absent. Do not request credentials, private logs, or a
   downloaded evidence bundle, and do not infer activation from local files.
2. Verify that hosted CI performed a frozen install and all deterministic
   checks on the published revision and that the dependency-evidence workflow
   succeeded under its checked-in fail-closed artifact and parity contract.
3. Confirm the hosted Mend job succeeded. Verify from checked-in configuration
   that the shared preset is selected, `main` is the GitHub default branch,
   automerge is off, expected native and regex managers are configured, and
   weekly uv lock maintenance is enabled.
4. Confirm that Renovate created or updated the Dependency Dashboard, GitHub's
   native dependency graph is populated, and Dependabot alerts are enabled.
   Record any observed native `uv.lock` ingestion limitation without claiming
   broader coverage than GitHub displays.
5. Fix only repository-owned configuration, workflow, documentation, or
   evidence defects revealed by hosted execution, then rerun the proportionate
   local gates. If a fix needs another hosted run, leave status pending until
   the human supplies its evidence.
6. Once every acceptance condition passes, change the repository-local
   dependency-automation status from prepared/pending to active and record
   durable, non-secret acceptance references and the recurring operator
   routine.

### Implementation notes

Vulnerability findings are not activation failures when the hosted evidence
workflow succeeds. A failed workflow, empty dependency graph, failed Mend job,
or Renovate configuration failure is an activation failure.

### Validation

- Run strict Renovate validation, workflow `actionlint`, and `git diff --check`
  after documentation-only activation changes. Repeat frozen lock sync, graph
  parity/evidence generation, deterministic Python quality gates, and shell
  validation if repository code, dependency, or workflow configuration is
  corrected; otherwise the successful hosted workflows validate the published
  revision with the pinned runtime.
- Verify documentation says active only after the final hosted evidence passes.
- Confirm no redacted evidence file containing private operational data was
  added to the repository.

### Completion criteria

Human administrator confirmation and public hosted results prove that the
published repository uses its checked-in shared preset, Renovate is the sole
non-automerge update-PR owner, CI consumes the frozen lock, the dependency
evidence workflow succeeds, GitHub's graph is populated, alerts are enabled,
and repository-local documentation is truthfully active.

## Phase 7: Promote API Tests Into Active Ecosystem Policy

### Workspace

.

### Goal

Finalize orchestration's canonical policy so the activated API-tests repository
is part of the production dependency-automation scope and recurring operator
contract.

### Scope

`docs/dependency-automation.md`, narrow ownership/cross-link updates if needed,
and shared configuration validation. No sibling-repository writes occur in this
phase.

### Non-goals

Do not repeat API implementation details, alter hosted settings, or mark the
consumer active without Phase 6's accepted evidence.

### Required context

- Phase 6 accepted outcome and non-secret hosted evidence references
- `AGENTS.md`
- `docs/OWNERSHIP.md`
- `docs/dependency-automation.md`
- `renovate-presets/default.json`
- `.github/workflows/dependency-automation-config.yml`

### Execution steps

1. Require Phase 6's completed acceptance record. If API-tests still says
   pending, stop and leave central active scope unchanged.
2. Move `budget-analyzer-api-tests` from pending rollout into the active
   production scope and update the repository count, repository-family
   ownership table, production workflow matrix, evidence artifact contract,
   GitHub/Mend settings routine, and failure triage consistently.
3. Summarize the Python contract—bounded PEP 621 declarations, exact uv lock,
   frozen CI, complete parity/SBOM/audit evidence, and Renovate lock
   maintenance—and link to the API repository for exact commands and files.
4. Record any verified GitHub native dependency-graph limitation without
   weakening the repository-owned complete evidence requirement. Keep
   Dependabot alerts and Renovate update ownership described as separate
   controls.
5. Remove obsolete pending language and ensure no active-policy table or count
   contradicts the accepted hosted state.

### Implementation notes

This is the durable ecosystem handoff. The plan itself remains implementation
history; recurring operation belongs in `docs/dependency-automation.md` and the
API repository's local owner document.

### Validation

- Review canonical ownership and every active scope/count/matrix reference for
  consistency.
- Validate Markdown links with repository-supported checks.
- Run the pinned strict Renovate validator and workflow `actionlint` if any
  shared configuration or validation workflow changed.
- Run `git diff --check` and confirm no archived decision or historical file
  was modified.

### Completion criteria

The canonical policy truthfully lists API tests as an active consumer, points
to the repository-owned implementation details, preserves the free Mend and
automerge-off boundaries, and defines recurring review of its locked,
auditable, Renovate-compatible dependency graph.
