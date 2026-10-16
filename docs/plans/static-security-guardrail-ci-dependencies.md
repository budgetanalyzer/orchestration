# Static Security Guardrail CI Dependency Closure

Make the ingress rate-limit configuration proof a first-class, reproducible
static guardrail instead of relying on tools that happen to exist in the
development VM or GitHub's mutable `ubuntu-latest` image. Remove the unnecessary
hard ripgrep dependency, distinguish a clean negative search from missing or
unreadable inputs, and give the embedded Python YAML checks an explicit,
integrity-verified dependency environment.

All work stays in this repository and is non-mutating with respect to
Kubernetes. Do not access a live or production cluster, change rate-limit
semantics, perform TLS writes, modify archived documentation or ADRs, or run Git
write operations. Keep the checked-in static gate as the local and hosted-CI
entry point. Run `bash -n` and ShellCheck on every changed shell script and fix
every finding. The human retains ownership of publishing the branch and
confirming the resulting GitHub-hosted workflow run.

Do not edit this plan during an active AI Session Handler invocation. When the
script move updates active plan references, exclude this immutable execution
plan; its Phase 1 references intentionally name the pre-move source path.

## Phase 1: Make the rate-limit configuration guardrail portable and fail closed

### Workspace

.

### Goal

Remove the accidental ripgrep requirement and ensure the NGINX cutover scan
cannot mistake a missing, unreadable, or failed input search for a successful
absence check.

### Scope

The offline ingress rate-limit configuration verifier, its location in the
script hierarchy, callers of that verifier, and focused negative-search
behavior.

### Non-goals

Changing the EnvoyFilter, token buckets, route ownership, NGINX behavior,
production render semantics, live-cluster verification, or the Python package
environment addressed in Phase 2.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`
- `scripts/README.md`
- `docs/ci-cd.md`
- `scripts/guardrails/verify-static-security-manifests.sh`
- `scripts/smoketest/verify-ingress-rate-limit-config.sh`
- `scripts/smoketest/verify-ingress-rate-limits.sh`
- `scripts/smoketest/verify-edge-browser-hardening.sh`
- `nginx/nginx.k8s.conf`, `nginx/nginx.production.k8s.conf`
- `kubernetes/production/nginx/nginx.production.k8s.conf`

### Execution steps

1. Move the offline verifier to
   `scripts/guardrails/verify-ingress-rate-limit-config.sh`, because it renders
   and inspects checked-in inputs without a cluster. Update the static parent,
   live-verifier callers, active documentation, and active plan references to
   the canonical path; exclude this execution plan while it is active, and do
   not retain two implementations or update archived material.
2. Remove `rg` from the verifier's required-command list. Use GNU/POSIX tooling
   already in the base shell contract, with `grep -nE` for the existing
   `limit_req`, `limit_req_zone`, and `limit_req_status` expression. Do not add
   ripgrep to the verified-tool installer for this single search.
3. Require every expected NGINX input to exist as a regular readable file
   before searching it. Capture and classify the search status explicitly:
   status 0 is a forbidden match, status 1 is the only successful no-match
   result, and every other status is an operational failure.
4. Keep matched lines in failure diagnostics without printing unrelated file
   contents. Preserve cleanup of all temporary render directories on every
   exit path.
5. Add a focused, disposable fixture path or self-test that proves all three
   outcomes: no forbidden directive passes, a matching directive fails, and a
   missing or unreadable input fails. The test must not edit the checked-in
   NGINX files.

### Implementation notes

The parent static guardrail already treats ripgrep as an optional acceleration
with a `grep` fallback. The focused verifier needs no ripgrep-only behavior, so
making `rg` another downloaded tool would add release/checksum maintenance
without improving the assertion. Keep the search expression segment unchanged
so comments or unrelated words do not broaden the NGINX policy check.

### Validation

- Run the verifier's disposable search self-test or fixture cases.
- Run `./scripts/guardrails/verify-ingress-rate-limit-config.sh` against the
  checked-in local and production inputs.
- Confirm an active-source search finds no remaining reference to the former
  `scripts/smoketest/verify-ingress-rate-limit-config.sh` path and no direct
  `rg` invocation in the moved verifier.
- Run `bash -n` and `shellcheck` on every shell script changed in this phase.
- Run `git diff --check`.

### Completion criteria

The offline verifier lives with the CI-safe guardrails, has no ripgrep
dependency, fails closed on absent or unreadable NGINX inputs, rejects a
forbidden limiter fixture, and passes against the checked-in configuration.

## Phase 2: Establish a reproducible Python and PyYAML contract

### Workspace

.

### Goal

Ensure hosted CI executes the structural YAML proof with a repository-declared
PyYAML version instead of inheriting an undeclared module from the runner.

### Scope

The static guardrail's Python interpreter selection, an exact hash-verified
PyYAML requirement, a private CI virtual environment, dependency update
metadata, and clear prerequisite failures for direct local invocation.

### Non-goals

Turning orchestration into a Python application, adopting the API-test
repository's full `uv` application contract, adding an external setup action,
installing packages globally, or rewriting the structural proof in another
language.

### Required context

- `AGENTS.md`
- `docs/dependency-automation.md`
- `docs/ci-cd.md`
- `scripts/README.md`
- `.github/workflows/security-guardrails.yml`
- `scripts/guardrails/verify-static-security-manifests.sh`
- `scripts/guardrails/verify-ingress-rate-limit-config.sh`
- `scripts/bootstrap/install-verified-tool.sh`
- `scripts/lib/pinned-tool-versions.sh`
- Phase 1's final verifier and validation results

### Execution steps

1. Add a narrowly named requirements input under `scripts/guardrails/` with
   one exact PyYAML version and the reviewed upstream artifact hashes needed by
   the supported CI platform. Add the appropriate Renovate annotation or
   native-manager-compatible declaration without weakening the repository's
   approval and non-automerge policy.
2. Add a workflow setup step that uses the runner's `python3` only to create a
   private virtual environment under the existing static-tools cache area.
   Install the requirement with `python -m pip --require-hashes`, without
   `sudo`, global installation, inherited user-site packages, or an external
   GitHub Action.
3. Export the virtual environment's interpreter path to later workflow steps.
   Teach the focused verifier to honor one narrowly named interpreter override
   and otherwise default to `python3` for the managed development VM. Use that
   selected interpreter for both the import preflight and the embedded
   structural checker.
4. Make the import preflight verify the expected PyYAML version and report the
   selected interpreter plus a canonical setup hint on failure. In hosted CI,
   also prove the imported module resolves inside the private environment so a
   runner-global PyYAML cannot mask a broken install.
5. Keep the dependency bootstrap separate from the repository's verified
   standalone-binary installer. Do not represent a Python package as a release
   binary or add unrelated Python project metadata.
6. Update dependency-automation guidance to identify this as a bounded static
   tooling dependency, distinct from the ecosystem's Python application/test
   consumer, and document its update and hash-review expectations.

### Implementation notes

The virtual environment is disposable CI state and must not be committed or
uploaded as evidence. A hash-verified one-package requirement is sufficient for
this bounded tooling use; do not copy the API-test repository's broader lock,
SBOM, or audit machinery. If the selected PyYAML release has platform-specific
wheels, record every accepted hash needed by the declared CI platform and
retain a reviewed source artifact only when building it is intentional.

### Validation

- Create a fresh temporary virtual environment and install the requirement
  using `--require-hashes`; confirm installation fails when a disposable copy
  contains an incorrect hash.
- Run the focused verifier with its interpreter override pointing at that
  environment and confirm the reported PyYAML module path is inside it.
- Run once with an empty environment or interpreter lacking PyYAML and confirm
  the failure is immediate and actionable.
- Run Renovate configuration validation if dependency extraction or annotations
  change.
- Run `bash -n` and `shellcheck` on every shell script changed in this phase.
- Run `git diff --check`.

### Completion criteria

The workflow creates an isolated, hash-verified PyYAML environment, the
verifier consistently uses the selected interpreter, ambient runner packages
cannot satisfy the contract accidentally, and dependency ownership is
documented without introducing a new application-level Python stack.

## Phase 3: Close workflow coverage and documentation drift

### Workspace

.

### Goal

Make the hosted workflow and local documentation accurately cover the new
static guardrail, then run the complete CI-equivalent acceptance suite.

### Scope

Workflow shell validation, static-guardrail and script-catalog documentation,
active cross-references, and final integrated static validation.

### Non-goals

Running live-cluster smoketests, changing security policy, adding CI artifacts
or caches, modifying organization settings, publishing the branch, or
administering GitHub Actions.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`
- `docs/ci-cd.md`, `docs/dependency-automation.md`
- `scripts/README.md`
- `.github/workflows/security-guardrails.yml`
- `scripts/guardrails/verify-static-security-manifests.sh`
- `scripts/guardrails/verify-ingress-rate-limit-config.sh`
- final files and validation results from Phases 1-2

### Execution steps

1. Add the moved ingress configuration verifier and any new shell bootstrap
   helper to the workflow's explicit `bash -n` step. Keep ShellCheck as a
   required implementation validation unless a separately pinned and reviewed
   hosted ShellCheck installation is introduced; do not create another
   undeclared runner dependency.
2. Update `scripts/README.md` first as the script-catalog owner. Describe the
   verifier as an offline guardrail, its NGINX fail-closed scan, its selected
   Python contract, and its relationship to the live ingress rate-limit
   verifier.
3. Update `docs/ci-cd.md` so the static workflow's declared tool/dependency list
   and check inventory include the rate-limit render proof and isolated PyYAML
   setup. Preserve the boundary that hosted CI performs no live-cluster proof.
4. Update other active summaries and cross-links affected by the script move or
   prerequisite contract. Do not copy detailed commands outside their owner
   documents, and do not edit `docs/archive/` or `docs/decisions/`.
5. Run the complete static manifest gate and its intentional-bad-fixture
   self-test from a clean cache. Confirm the normal run reaches and passes the
   ingress rate-limit configuration section instead of stopping on a missing
   host tool.
6. Review the final workflow for read-only permissions, absence of external
   package setup actions, no global package writes, and no reliance on
   `ubuntu-latest` providing ripgrep or PyYAML. Record that the user must rerun
   the GitHub-hosted PR workflow after publishing the implementation.

### Implementation notes

Do not make the hosted workflow invoke the live
`verify-ingress-rate-limits.sh` test. The static configuration proof and the
runtime exhaustion/isolation proof remain complementary gates with different
authority and prerequisites. Avoid caching the virtual environment until a
separate cache-integrity and invalidation design is justified.

### Validation

- Run `bash -n` for every shell script named by the workflow and every shell
  script changed by the plan.
- Run `shellcheck` on every changed shell script and fix all findings.
- Run `./scripts/guardrails/verify-ingress-rate-limit-config.sh` using the
  isolated interpreter contract.
- Point `PHASE7_STATIC_TOOLS_DIR` at a fresh temporary directory, then run
  `./scripts/guardrails/verify-static-security-manifests.sh`; clean up only
  that explicitly created temporary directory afterward.
- Run `./scripts/guardrails/verify-static-security-manifests.sh --self-test`.
- Search active files for stale verifier paths, an `rg` prerequisite in the
  offline guardrail, and documentation that omits the rate-limit configuration
  stage.
- Run the repository's Renovate configuration validator when dependency
  metadata changed.
- Run `git diff --check` and inspect `git status --short` for unintended files.

### Completion criteria

The local CI-equivalent static gate and its rejection self-test pass from a
clean cache, the workflow syntax-checks every changed shell entry point, active
documentation describes the real dependency and script ownership model, and
no static check relies on ambient ripgrep or PyYAML. The implementation is
ready for the user-owned GitHub workflow rerun.
