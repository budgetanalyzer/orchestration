# Workspace And Orchestration Decoupling Plan

Remove the executable and prerequisite dependencies between `orchestration`
(the application platform) and `workspace` (the development-VM and AI-agent
environment) in both directions. Orchestration must set up, start and verify
the local platform without invoking or requiring workspace. Workspace must
provision, install and verify the development VM and agent tooling without
reading, invoking or requiring an orchestration checkout. Documentation links
across the two repositories, and workspace's use of orchestration's published
contracts (ports, URLs, TLS file names), remain intentional and welcome.

Recorded decisions:

- **No runtime dependency in either direction.** Orchestration stops calling
  workspace's verifier. Its own checks (exact `kind-kind` target, loopback API
  authority, no kubeconfig proxy, Ready control plane, local Docker endpoint)
  protect the application environment.
- **Workspace retains the VM boundary check.** The checks in
  `user_tools.py:preflight()` stay at their current strictness:
  - VM identity and canonical user/home;
  - guest-local repositories and bare origins;
  - Git configuration;
  - denied credential, proxy and endpoint environment;
  - credential stores and forwarded sockets;
  - guest Docker.

  They become a dedicated public, read-only workspace entry point, created
  before orchestration stops invoking the old verifier. Users run it before
  agent work. It does not require provider CLIs or agent helpers to be
  installed. First provisioning applies the same rules but treats missing
  tools as installable; unsafe existing state still fails.
- **The shared Renovate preset stays.** Workspace keeps
  `extends: github>budgetanalyzer/orchestration//renovate-presets/default`.
  It is shared organization policy, not coupling to remove.
- **Orchestration is the sole owner and installer of kubectl, Helm, Tilt and
  Kind.** Its pins live in `scripts/lib/pinned-tool-versions.sh`. Its
  human-run `setup.sh` installs them through `install-verified-tool.sh` (with
  sudo). Workspace stops declaring, installing, checking and running Renovate
  for them. Workspace's install-path, ownership, symlink and collision
  safeguards and its amd64/arm64 release validation for these four tools move
  to orchestration, including rejection of unsafe group writes and unexpected
  downgrades. Setup and the prerequisite checker enforce the exact pinned Helm
  version, matching kubectl, Tilt and Kind.
- **AI provider CLIs float.** Claude Code, Codex and Gemini CLI install at the
  latest published version on first install, or when the human explicitly
  updates them. Routine preparation keeps the installed versions. They have no
  repository-pinned version or integrity value and no Renovate tracking. npm
  HTTPS and registry integrity verification stay enabled. All three install as
  global packages into one managed provider prefix, separate from the pinned
  Playwright project; npm global installs keep each package's dependency tree
  separate. Verification keeps ownership and command-resolution checks but
  drops exact version matching.
- **Playwright stays pinned.** Its Chromium-derived apt inputs stay coupled to
  its exact version. The npm lockfile becomes the single source for its
  version, integrity and tarball. The reviewed Chromium apt provenance stays a
  separate input that must match the lockfile version; it is never derived from
  the lockfile.
- **One component never blocks another.** Workspace verification and
  installation become component-scoped: base VM, each provider separately, and
  agent extras. Neither a stale helper nor a missing provider can block another
  provider or the application. The boundary check always runs.
- **Clean install, no migration.** After this plan, the human installs agent
  tooling from a clean state. Do not write migration or compatibility code for
  previous managed state (the combined npm prefix, `managed-files.json`,
  `installation.json` or anything else).

Definition of done:

1. **No executable dependency.** No script, test, CI workflow, Tiltfile or
   manifest in either repository reads, sources, executes or validates files
   from the other repository, or requires the other repository's checkout.
   Certificate files the human passes to the trust installer are inputs, not a
   checkout dependency. The only cross-repository configuration reference is
   workspace's Renovate `extends` of the shared orchestration preset.
2. **No prerequisite dependency.** Orchestration's setup, daily startup and
   verifiers do not require workspace to be installed or verified. Workspace's
   provisioning, installation and verification do not require an orchestration
   checkout.
3. **Single ownership.** kubectl, Helm, Tilt and Kind are declared, installed
   and verified only by orchestration.
4. **Documentation links are allowed in both directions.**
   - Workspace docs may link to orchestration docs and use orchestration's
     published ports, URLs and TLS file locations. For example, the host
     tunnel forwards the ports orchestration publishes and links orchestration's
     port and observability docs.
   - Orchestration's own setup path must be self-contained, with no workspace
     command as a required step. It may link to workspace as the optional
     development-VM and agent environment.
   - Agent-runtime instructions (VM provisioning, provider launch, guest trust,
     host tunnel) live in workspace, and orchestration links to them.
   - "Workspace" used generically for the side-by-side checkout parent (for
     example `WORKSPACE` in `tilt/common.star`) is unrelated and stays.

Sequencing: Phase 1 gives workspace its own boundary entry point. Phase 2 moves
the platform-tool safeguards into orchestration. Phases 3-4 then remove
orchestration's workspace dependency, and Phases 5-9 remove workspace's
dependencies and restructure its tooling. Each phase executes only in its
declared repository. Keep workspace's existing full verifier until Phase 8
replaces it.

Checks that must survive:

| Existing check | New owner | Regression evidence |
| --- | --- | --- |
| kubectl/Helm/Tilt/Kind exact releases and checksums | Orchestration installer and prerequisite checker | Wrong versions rejected; amd64/arm64 release and archive checks |
| Install-path ownership, group/world-write, symlink, collision and downgrade safeguards for those binaries | Orchestration installer; workspace keeps its own for its remaining tools | Unsafe-path and unexpected-downgrade fixtures fail before writes |
| VM/user/home, repositories, Git, denied authority, guest Docker | Workspace boundary entry point | Existing negative cases |
| Exact local Kind target and local Docker endpoint | Orchestration setup, daily checks and mutation entry points | Remote or wrong targets rejected before cluster changes |
| Current ingress certificate trusted by the client | Orchestration supplied-leaf/system-trust check; workspace OS/NSS checks and documented browser acceptance | Renewed root not in system trust fails; exact-URL browser check after installation/renewal |
| Provider exact versions and checked-in integrity | Intentionally removed | n/a |
| Playwright lock and Chromium apt compatibility | Workspace | Lock/package mismatch and stale apt provenance fail |
| All other pins and checks (Go, actionlint, VIA, mitmproxy, Node/JDK policy, helper convergence) | Unchanged owner, scoped to a component | Existing negative cases |

The table is a starting point, not a complete list. Every phase that moves or
removes a check names, in its final report, the check, its new owner and the
test that proves it. The tests are the durable record; do not add permanent
assertion inventories to documentation. Only the three provider pins may be
removed without a replacement.

Workspace validation: run `check_install_inputs.py --publication proposed` for
uncommitted work. `--publication committed` compares against
`git archive HEAD`, so it belongs to publication CI and the human handoff after
commit. Never commit just to satisfy it.

Safety constraints for every phase:

- no git write operations;
- no certificate or key generation;
- no trust-store writes;
- no execution of human-only workspace preparation or trust installers;
- no live personal-host access;
- no staging or production access.

Agent workers may run offline tests, static checks and read-only local checks.
After Phase 9, the human performs a clean install of the agent tooling and runs
the trust installer with the new interfaces. That handoff is documented in
workspace, not executed by an agent.

## Phase 1: Workspace VM Boundary Entry Point

### Workspace

../workspace

### Goal

Give agent work its own boundary check before orchestration stops calling
workspace's verifier.

### Scope

- Extract the boundary checks shared by `user_tools.py:preflight()` and
  `provision.py:preflight()` without changing what they accept or reject.
- Add `scripts/check-agent-vm-boundary.sh`, a read-only check that runs from
  the checkout. It requires healthy guest Docker but not provider CLIs, AI
  Session Handler, agent helpers, platform binaries or an orchestration
  checkout.
- First provisioning uses the same rules, but a missing Docker or system tool
  is installable rather than a failure. Unsafe existing state (wrong owner,
  symlinks, collisions, partial installs) still fails before any write.
- Document the pre-agent invocation in `docs/host-isolation.md`,
  `docs/native-user-tools.md` and `AGENTS.md`.

### Non-goals

- Removing platform tools or changing provider policy.
- Component-scoped installation and verification (Phase 8).
- Removing the existing full verifier.
- Installing anything live.
- Changes in orchestration.

### Required context

- `AGENTS.md`, `docs/host-isolation.md`, `docs/native-user-tools.md`
- `scripts/native/provision.py`, `scripts/native/user_tools.py`, `tests/native/`
- `../orchestration/docs/agents-md-checkstyle.md` for the `AGENTS.md` edit

### Execution steps

1. Identify which checks in the two `preflight()` functions are boundary
   checks and which are installed-tool or agent-component checks.
2. Extract the boundary checks into a shared function and add the wrapper.
3. Make provisioning, install and check entry points run the boundary checks
   first. Offline source validators and human-host utilities stay unchanged.
4. Add tests and update the docs and the workflow syntax/lint lists.

### Implementation notes

Workspace remains the owner of VM, normal-user, repository, credential and
Docker provisioning policy. "Missing" and "unsafe" are different results:
missing tools may be installed, unsafe state never is.

### Validation

- `python3 -m unittest discover -s tests/native -v` and the other source
  validators from `.github/workflows/native-dependency-validation.yml`.
- `py_compile` for changed Python; `bash -n` and ShellCheck for the wrapper.
- Fixtures show the wrapper passes without providers, helpers, AI Session
  Handler or orchestration, and fails on every existing identity/authority
  negative case.
- A fresh-system fixture reaches provisioning without Docker, Node or Java
  installed; the runtime wrapper still fails when guest Docker is missing.

### Completion criteria

`scripts/check-agent-vm-boundary.sh` exists, is documented as the pre-agent
check and is tested. Provisioning does not require the tools it installs. The
full verifier still passes.

## Phase 2: Orchestration Platform Tool Safeguards

### Workspace

.

### Goal

Make orchestration's installer and prerequisite checker enforce everything
workspace currently enforces for kubectl, Helm, Tilt and Kind, so workspace can
drop them in Phase 5.

### Scope

- `scripts/bootstrap/install-verified-tool.sh` and its pin helpers.
- `setup.sh` and `scripts/bootstrap/check-tilt-prerequisites.sh`: exact Helm
  version enforcement, replacing both independent supported-range checks.
- Install safeguards: destination and parent ownership, no group- or
  world-writable root-owned destinations or parents, no symlinked parents or
  destinations, no collision with an unexpected existing file, and refusal
  to downgrade an installed version newer than the selected pin. User-owned
  `--install-dir` paths used by CI keep working with owner-appropriate checks.
- amd64/arm64 release-download, checksum and archive validation for all four
  tools in orchestration's own tests or CI.
- `docs/OWNERSHIP.md` first, then `scripts/README.md` and
  `docs/dependency-automation.md`.

### Non-goals

- Changing pinned releases or checksums.
- Removing anything from workspace.
- Copying workspace's VM provisioner or OS policy.
- A shared installer framework.
- Running privileged installation.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`, `scripts/README.md`
- `docs/dependency-automation.md`, `scripts/lib/pinned-tool-versions.sh`
- `scripts/bootstrap/install-verified-tool.sh`, `setup.sh`
- `scripts/bootstrap/check-tilt-prerequisites.sh`
- Read only: `../workspace/scripts/native/provision.py`,
  `../workspace/scripts/native/verify_release_inputs.py`

### Execution steps

1. List the four-tool checks in workspace's `provision.py` and
   `verify_release_inputs.py`.
2. Implement each in orchestration, or record why it does not apply.
3. Use `check_pinned_tool_version` for Helm prerequisites and exact pinned-tool
   enforcement in `setup.sh` instead of `ensure_supported_helm`. A newer
   installed release must fail before replacement, not silently downgrade.
4. Add offline fixtures and the two-architecture release validation.
5. Update the docs.

### Implementation notes

Workspace keeps the same kind of filesystem checks for its own tools.
Duplicating a handful of checks in two independently owned installers is
preferable to a cross-repository dependency.

### Validation

- `bash -n` and `shellcheck -x` on changed shell files; `actionlint` on changed
  workflows.
- Fixtures: non-pinned Helm fails prerequisites and is not accepted by setup;
  group/world-writable root-owned destinations or parents, symlinked parents,
  destination collisions and unexpected downgrades fail before writes.
- Fixtures: checksum mismatch and missing archive member.
- Two-architecture release validation passes without privileged writes,
  cluster changes or executing foreign binaries.

### Completion criteria

Every workspace check for the four tools has an orchestration implementation
and test, listed in the final report. All four tools are checked against exact
pins.

## Phase 3: Orchestration Runtime Decoupling

### Workspace

.

### Goal

Remove every executable dependency from orchestration on workspace while
keeping the application-environment safety checks that orchestration
previously got from workspace's verifier.

### Scope

- `scripts/bootstrap/check-agent-vm-prerequisites.sh`: delete it and replace it
  with an orchestration-owned read-only `scripts/bootstrap/check-local-runtime.sh`
  that requires a local Docker endpoint, a reachable Docker daemon and the exact
  local Kind target.
- `scripts/lib/local-kubernetes-target.sh`: add a reusable local Docker endpoint
  assertion beside `assert_local_kind_target`.
- `setup.sh`: remove the workspace verifier call. Remove help text and
  messages that make workspace preparation or guest trust a prerequisite;
  they may link to workspace docs instead. Keep the container-execution
  rejection and Phase 2's install safeguards. Run the Docker endpoint assertion
  before any cluster deletion or creation.
- `scripts/bootstrap/check-tilt-prerequisites.sh`: remove `--guest-local` and
  the workspace preflight. Use one mode that checks Docker, the pinned
  platform tools, OpenSSL, Java, Node and npm, the Docker daemon, the local
  Docker endpoint, the exact Kind target when a cluster exists, and the three
  ingress TLS files. Add a client-trust check: the current ingress leaf must
  verify for `app.budgetanalyzer.localhost` against the system trust bundle,
  not only against the supplied `_mkcert-rootCA.pem`. A failure links to the
  trust documentation. mkcert is not a platform prerequisite; only the
  certificate-preparation script needs it, and that script checks for itself.
- `scripts/bootstrap/install-imported-ingress-tls.sh`: remove the retired
  `--install-system-trust` option and its workspace command text, so unknown
  options fail generically.
- `scripts/guardrails/check-tilt-resource-roots.sh`: keep the guard that Tilt
  never generates browser TLS or installs trust. The workspace trust-installer
  name may stay in its deny list, because a deny-list string is a guard rather
  than a dependency. Drop the retired `--install-system-trust` option.
- Tests: delete `tests/native-preflight-wrapper/`. Add an offline fixture test
  for `check-local-runtime.sh` and the Docker endpoint assertion. Update
  `tests/imported-ingress-tls/` to drop the workspace-specific expectations and
  the `BUDGET_ANALYZER_*_PARENT` variables; keep a generic unknown-option test
  that proves no trust write happens. Update `.github/workflows/test-setup.yml`
  to run the new test.
- Existing "personal host", "development VM" or "guest" wording in other
  scripts (for example the TLS preparation scripts) may stay as long as it
  does not invoke or require a workspace command.

### Non-goals

- Documentation outside script help text and messages (Phase 4).
- Any change in `../workspace`.
- Changing pinned versions, checksums or Phase 2's installer safeguards.
- Renaming the generic `WORKSPACE`/`WORKSPACE_DIR` checkout-parent variables.
- Removing `setup-k8s-tls.sh` as a compatibility entry point.

### Required context

- `AGENTS.md` (Shell Script Validation, Image Pinning, SSL/TLS constraints)
- `scripts/README.md`
- `scripts/lib/local-kubernetes-target.sh` and
  `tests/local-kubernetes-target/test-local-kubernetes-target.sh`
- `docs/architecture/autonomous-ai-execution.md` (exact local target rules)

### Execution steps

1. Inventory executable references with
   `rg -n '\.\./workspace/scripts|workspace/scripts/|check-agent-vm|install-agent-vm|budget-analyzer-native|BUDGET_ANALYZER_(WORKTREE|BARE)_PARENT|guest-local|install-system-trust|NATIVE_PREFLIGHT' --glob '!docs/**' --glob '!archive/**' --glob '!tmp/**'`.
2. Add the Docker endpoint assertion to `scripts/lib/local-kubernetes-target.sh`.
   It rejects a non-`unix://` `DOCKER_HOST`, a `DOCKER_CONTEXT` or current
   context whose endpoint is not a local Unix socket, conflicting
   `DOCKER_HOST`/`DOCKER_CONTEXT` settings, and an unreachable daemon. It must
   check the same endpoint the Docker CLI and Kind will actually use.
3. Create `scripts/bootstrap/check-local-runtime.sh`, a read-only check that
   runs the Docker endpoint assertion and `assert_local_kind_target`, then
   delete `check-agent-vm-prerequisites.sh` and its test directory.
4. Update `setup.sh`, `check-tilt-prerequisites.sh`,
   `install-imported-ingress-tls.sh` and `check-tilt-resource-roots.sh` as
   scoped above.
5. Add the new offline fixture test, update the imported-TLS test and update
   `test-setup.yml`.
6. Rerun the step 1 inventory with
   `--glob '!scripts/guardrails/check-tilt-resource-roots.sh'` added. The only
   acceptable hits are the generic unknown-option test input and links to
   `../workspace/docs/...`. Do not delete negative tests to get a clean search.

### Implementation notes

The Docker endpoint assertion checks the selected Unix-socket transport and
daemon reachability. It does not prove the daemon behind that socket is local
or that the machine is a VM; workspace retains the stronger guest-isolation
checks. Do not add a fallback that silently accepts remote Docker endpoints.
Keep the helper pattern used by
`local-kubernetes-target.sh` (failures print a reason and return non-zero).
`setup.sh` does not call `check-tilt-prerequisites.sh`, so the client-trust
check does not block bootstrap before trust is installed.

### Validation

- `bash -n` and `shellcheck -x` on every added or changed shell script,
  including `setup.sh` and the tests.
- `./tests/local-kubernetes-target/test-local-kubernetes-target.sh`
- `./tests/imported-ingress-tls/test-install-imported-ingress-tls.sh`
- The new `check-local-runtime.sh` fixture test, covering remote and
  conflicting Docker selection and absent or wrong Kind targets.
- A fixture where the supplied root and leaf are valid but the system bundle
  lacks that root fails the client-trust check.
- `actionlint .github/workflows/test-setup.yml` if available locally.
- If the live local cluster is up, run `./scripts/bootstrap/check-local-runtime.sh`
  and `./scripts/bootstrap/check-tilt-prerequisites.sh` and record the outcome.
  Do not run `setup.sh`.

### Completion criteria

No orchestration script, test, workflow or Tiltfile invokes, sources or
requires a workspace file, command or workspace-managed environment variable.
The Tilt resource-root deny-list string and links to `../workspace/docs/...`
in help text are the only permitted workspace mentions. The offline setup
contracts pass. Daily and bootstrap prerequisite checks are
orchestration-owned and enforce the local Docker endpoint, the exact Kind
target and client trust of the current ingress certificate.

## Phase 4: Orchestration Documentation Decoupling

### Workspace

.

### Goal

Make orchestration's own setup, startup and verification documentation
self-contained, with no workspace command as a required step. Move
agent-runtime instructions out of orchestration and link to workspace for
them. Keep cross-repository documentation links where they help readers.

### Scope

- `docs/OWNERSHIP.md` first:
  - keep the workspace rows as cross-links for concerns workspace owns
    (development VM, host isolation and audit, guest trust, host tunnel,
    agent tooling);
  - remove any row or wording that makes workspace verification an
    orchestration prerequisite;
  - add rows for the new orchestration-owned `check-local-runtime.sh` and the
    ingress TLS file contract where needed;
  - keep orchestration as the owner of its loopback publication contract
    (ports, URLs, health, authentication) that the workspace host tunnel
    consumes.
- `AGENTS.md`, edited under `docs/agents-md-checkstyle.md`:
  - Operating Context: compress the development-VM, personal-host, host-trust
    and agent-runtime paragraphs into a short pointer to workspace for the
    agent environment. Keep the guest-publication versus host-tunnel ownership
    split in one or two sentences with links. Keep a required pointer telling
    native agent sessions to run workspace's
    `scripts/check-agent-vm-boundary.sh` before agent work; this is an agent
    duty, not an application startup dependency.
  - Development Workflow: replace the `check-agent-vm-prerequisites.sh` and
    `--guest-local` instructions with `check-local-runtime.sh` and
    `check-tilt-prerequisites.sh`.
  - SSL/TLS: remove the rule about the retired `--install-system-trust`
    interface. Keep a link to workspace for guest OS/NSS trust instead of
    restating its procedure.
  - Keep the application rules: the exact `kind-kind` target before
    agent-authorized cluster mutation, no staging or production credentials or
    administration from agent sessions, no agent certificate generation, and
    local development secrets not hidden from agents.
  - Keep the Discovery `find` list, Source Of Truth links to workspace docs,
    and the GitHub Actions baseline coordination unchanged unless they
    describe the removed preflight.
- `README.md`, `CONTRIBUTING.md`, `docs/development/getting-started.md`,
  `docs/development/local-environment.md`,
  `docs/architecture/autonomous-ai-execution.md`,
  `docs/architecture/observability.md`, `docs/tilt-kind-setup-guide.md`,
  `docs/runbooks/` and `scripts/README.md`: replace references to the
  removed preflight, `--guest-local`, `--native-runtime`, the workspace
  verifier and workspace scripts as required steps.
- Getting started: describe one self-contained path with no workspace command
  in it:
  - install Docker;
  - prepare ingress TLS with `renew-host-ingress-tls.sh` on the machine whose
    browser will be used, and if Kind runs on another machine, place the three
    files in `nginx/certs/k8s/` there;
  - run `setup.sh`, which installs the pinned platform tools and recreates
    Kind;
  - run `tilt up`;
  - daily startup is `check-local-runtime.sh` followed by `tilt up`.

  State that valid TLS files are not the same as client trust, and that
  `check-tilt-prerequisites.sh` reports whether the system trusts the supplied
  current ingress leaf. It does not establish which certificate the running
  ingress serves or whether Chromium's NSS database trusts it. Link to the
  environment-specific trust docs and their exact-URL browser acceptance check.

  Add a short "Running in the workspace development VM" note that links to
  workspace for VM provisioning, three-file transfer, guest trust, the host
  tunnel and agent launch. Remove the inline agent launch, provider, AI
  Session Handler and native-shell instructions.
- `docs/dependency-automation.md`: no change to the shared preset's consumer
  scope. Workspace remains a consumer.

### Non-goals

- Files in `docs/archive/`, `archive/`, `docs/decisions/`, `docs/research/` and
  `docs/plans/`.
- Any change in `../workspace`.
- Removing informational links to workspace docs.
- Changing the shared Renovate preset.
- Rewriting unrelated documentation or changing technical behavior.

### Required context

- `docs/OWNERSHIP.md`
- `docs/agents-md-checkstyle.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/architecture/autonomous-ai-execution.md`
- `docs/architecture/observability.md`
- `scripts/README.md` (as updated in Phases 2-3)

### Execution steps

1. Update `docs/OWNERSHIP.md`.
2. Update `AGENTS.md` under the checkstyle.
3. Update the remaining documents listed in scope. If an anchor is renamed,
   fix every inbound link. Workspace docs that link to renamed anchors are
   handled in Phase 9, so record any renamed anchors in the final report.
4. Run the reference checks below and resolve every hit.

### Implementation notes

The following agent-runtime rules belong in workspace. Orchestration may
summarize them in one sentence with a link, but must not be their only home.
Phase 9 confirms that workspace states them:

- agents run only as the normal user in the development VM, and retired
  runtimes are not reconstructed;
- GitHub credentials and publication stay on the personal host;
- no personal-host credential, mount, Docker/libvirt socket or kubeconfig is
  exposed to the guest;
- no staging or production kubeconfig, cloud credential, user credential or
  session cookie is exposed to the guest;
- a VM marker does not prove personal-host isolation;
- only the human accesses the personal host;
- guest OS/NSS trust is installed only by the human workspace installer.

Keep orchestration's own statements about agent authority over its local
application environment.

### Validation

- `rg -n '\.\./workspace/scripts|workspace/scripts/|check-agent-vm|install-agent-vm|prepare-agent-vm|provision-agent-vm|check-budget-analyzer-local-ca-trust|budget-analyzer-native|BUDGET_ANALYZER_(WORKTREE|BARE)_PARENT|guest-local|native-runtime|install-system-trust' --glob '!docs/archive/**' --glob '!archive/**' --glob '!docs/decisions/**' --glob '!docs/research/**' --glob '!docs/plans/**' --glob '!tmp/**' --glob '!scripts/guardrails/check-tilt-resource-roots.sh'`
  returns only links to `../workspace/docs/...`, the `AGENTS.md` pointer to
  the workspace boundary check and the unknown-option test input.
- Every relative Markdown link in changed files resolves. Check with a short
  `rg`/`test -e` loop.
- Rerun the Phase 3 offline tests to confirm script help text and docs agree.

### Completion criteria

Orchestration's documented setup, daily startup and verification path runs
without any workspace command or workspace verification. Agent-runtime
procedures are linked rather than restated. The reference and link checks
pass. `AGENTS.md` conforms to the checkstyle.

## Phase 5: Workspace Removes Orchestration Platform Tools And Checkout Dependency

### Workspace

../workspace

### Goal

Stop workspace from declaring, installing, checking or tracking kubectl, Helm,
Tilt and Kind, and remove every code-level requirement for an orchestration
checkout.

### Scope

- `native/toolchain.json`: remove the `downloads.kubectl`, `downloads.helm`,
  `downloads.tilt` and `downloads.kind` records and the
  `reviewed_sources.helm_contract` and `reviewed_sources.orchestration_tools`
  entries.
- `renovate.json`: remove the four regex managers and their package names from
  the checksum-review rule.
- `tests/native/check_manifest.py`: remove the sibling-orchestration comparison
  and the `--workspace-only` distinction if nothing else needs it. Update the
  CI invocation in `.github/workflows/native-dependency-validation.yml` to
  match.
- `scripts/native/provision.py`, `scripts/native/verify_release_inputs.py` and
  `scripts/native/user_tools.py`: remove any handling specific to the four
  tools. Remove `orchestration` from the required-checkout list. Required
  checkouts are `workspace`, plus `ai-session-handler` until Phase 8 scopes it
  to its component.
- Update tests under `tests/native/` that construct orchestration fixtures for
  these paths. `test_local_ca.py` stays until Phase 6.
- Update `docs/native-tool-inventory.md` and `docs/dependency-automation.md`
  sections that describe the four tools or the cross-repo contract.

### Non-goals

- The trust helper's orchestration certificate path (Phase 6).
- AI provider or Playwright changes (Phase 7).
- Component-scoped verification (Phase 8).
- Remaining documentation and Renovate preset changes (Phase 9).
- Any change in orchestration.

### Required context

- `AGENTS.md` (workspace validation rules)
- `docs/native-tool-inventory.md`
- `docs/dependency-automation.md`
- `.github/workflows/native-dependency-validation.yml`
- Read only: `../orchestration/scripts/bootstrap/install-verified-tool.sh` and
  its tests, to confirm Phase 2 covers each check removed here

### Execution steps

1. Inventory with
   `rg -n -i 'kubectl|helm|tilt|\bkind\b|orchestration' native scripts tests renovate.json .github`.
2. For each four-tool check about to be removed, confirm orchestration now
   has an equivalent check and test. Stop and report any gap.
3. Remove the four tool records, Renovate managers and reviewed-source entries.
4. Remove the related provisioner, verifier and release-input handling, and the
   required orchestration checkout.
5. Update tests, the CI invocation and the two inventory and automation docs.

### Implementation notes

Leave the generic `downloads` machinery intact for the remaining system tools
(actionlint, Go, VIA), including its install-path safeguards. Do not add a
replacement check for the removed tools; orchestration verifies them now.

### Validation

Run the source-validation commands from
`.github/workflows/native-dependency-validation.yml`:

- `renovate-config-validator --strict` at the pinned Renovate version;
- `python3 -m unittest discover -s tests/native -v`;
- `check_manifest.py`;
- `check_install_inputs.py --publication proposed`;
- `check_user_environment.py`;
- the bash syntax and ShellCheck lists.

Also run `py_compile` for changed Python files and `actionlint` for the changed
workflow.

### Completion criteria

Workspace contains no kubectl/Helm/Tilt/Kind declarations, Renovate rules or
checks. No code path requires or reads an orchestration checkout, except the
trust helper handled in Phase 6. Install safeguards for the remaining
workspace tools are unchanged. All source-validation checks pass.

## Phase 6: Workspace Trust Helper Uses Explicit Inputs

### Workspace

../workspace

### Goal

Remove the trust helper's dependency on orchestration's
`nginx/certs/k8s/` paths. The human trust installer receives the CA and leaf
explicitly, and the read-only check compares installed trust to a
workspace-owned record of the approved root.

### Scope

- `scripts/native/local_ca.py` and its wrapper
  `scripts/install-agent-vm-local-ca-trust.sh`:
  - the human installer takes `--ca-file` and `--leaf-file`. The hostname
    stays fixed at `app.budgetanalyzer.localhost`;
  - it keeps every current safety check, including: no private key, a valid
    unexpired CA, `CA:TRUE`, hostname-aware leaf verification, NSS ownership
    and flag checks, and exact-fingerprint system import;
  - it records the approved public root under the native root only after the
    install succeeds.
- `check-budget-analyzer-local-ca-trust`: verify OS and NSS trust against the
  recorded root, and that the recorded root has not expired. Do not read any
  application checkout path. It reports store state, not whether the running
  application's current certificate is trusted. Orchestration's
  `check-tilt-prerequisites.sh` verifies the supplied current ingress leaf
  against system trust (Phase 3); it does not prove browser trust or the
  certificate actually served by ingress.
- `tests/native/test_local_ca.py`: replace orchestration fixture paths with
  explicit-input fixtures.
- `docs/local-budget-analyzer-tls.md` and the trust sections of
  `docs/native-user-tools.md`: document the explicit-input human command. The
  documented command may pass orchestration's published TLS file locations
  (for example
  `"$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration/nginx/certs/k8s/_mkcert-rootCA.pem"`)
  and link orchestration's TLS docs. Only the code must not derive those
  paths. After a certificate renewal, the human reruns the installer.
  After initial installation and each renewal, document an acceptance check
  opening exactly `https://app.budgetanalyzer.localhost` in the normal
  Workspace Chromium/Playwright browser using its NSS store. Require a
  successful HTTPS load without certificate exceptions or verification
  bypasses. A system bundle trusting roots A and B while NSS trusts only A
  must not be reported as browser-ready for an application serving root B.
  This needs a documented browser check, not a new trust framework or stored
  leaf state.

### Non-goals

- Executing the installer or touching any real trust store.
- Changing certificate generation, which is human-only and orchestration's
  concern.
- Changes in orchestration.

### Required context

- `docs/local-budget-analyzer-tls.md`
- `docs/native-user-tools.md`
- `docs/host-isolation.md` (trust and isolation rules)
- `scripts/native/local_ca.py` and `tests/native/test_local_ca.py`

### Execution steps

1. Change the CLI and record-and-check flow in `local_ca.py` and the wrapper.
2. Update the managed helper wiring in `user_tools.py` if the check helper's
   arguments or state location change.
3. Update the tests: explicit inputs, rejected inputs (private key, expired
   root or leaf, non-CA, hostname mismatch), missing record, and a failed
   install that leaves no record.
4. Update the two docs with the separate store, supplied-leaf/system-trust and
   live-browser acceptance checks, including the installation/renewal sequence.

### Implementation notes

The recorded approved root is public material. Store it with permissions
consistent with the native root. A missing recorded root fails closed and
prints the human install command. Never generate certificates or call
`mkcert`; reuse existing public test fixtures or mocks.

### Validation

- `python3 -m unittest discover -s tests/native -v` (mocked; under `tmp/`;
  never touches real trust stores)
- `py_compile` for changed Python
- `bash -n` and ShellCheck for the wrapper
- `check_user_environment.py`
- `rg -n 'orchestration' scripts native tests` returns no trust-related paths

### Completion criteria

No workspace code reads orchestration paths for trust. The human installer and
the read-only check work from explicit inputs and workspace-owned state. All
current trust safety checks keep their tests.
The documented exact-URL browser check covers the live ingress and NSS trust;
successful store or system-leaf checks alone are not called browser acceptance.

## Phase 7: Workspace Manifest Split, Floating Providers And Single-Source Playwright Pin

### Workspace

../workspace

### Goal

Separate system-provisioning inputs from agent-tool inputs. Make Claude Code,
Codex and Gemini float at the latest version with no Renovate tracking. Keep
Playwright exactly pinned, with the npm lockfile as its single version and
integrity source.

### Scope

- `native/toolchain.json`: split it so `scripts/native/provision.py` loads and
  validates only system inputs (OS, architectures, apt, repositories, system
  downloads). Agent tools live in a separate section or file that the system
  provisioner neither loads nor validates. `chromium_apt` stays with the system
  inputs because the system provisioner installs it, but its consistency check
  against the Playwright version moves to the user-tools side.
- Providers:
  - remove `@anthropic-ai/claude-code`, `@openai/codex` and
    `@google/gemini-cli` from `native/npm/package.json` and
    `package-lock.json`, along with their version, integrity and tarball
    fields;
  - install them with `npm install -g` into one managed provider prefix,
    separate from the Playwright project in `native/npm`, at `@latest` when a
    provider is missing or the human asks for an update;
  - routine preparation leaves installed providers at their current versions;
  - verification checks presence, `--version` exit status, ownership and
    fresh-shell command resolution, with no version match;
  - provide an update command, for example `--update-provider NAME`.
- Update every provider-path consumer in this phase to the managed global
  prefix's `bin` directory: generated CLI wrappers, helper launch paths and
  `scripts/native/proxy.py`, including Claude's direct invocation and
  `CODEX_REAL_BIN`. Playwright keeps its separate project path. Do not leave
  proxy/optional-helper paths pointing into the old combined npm project.
- Playwright: remove the duplicated release fields from `toolchain.json`.
  `validate_lock()` and the Chromium selection read the version from the
  lockfile, and `package.json` must agree with it. `chromium_apt_source` stays
  a separately reviewed value that must match the lockfile version, so a
  lockfile-only upgrade fails until the apt inputs are reviewed.
- `renovate.json`: Renovate must ignore the three providers. Removing them from
  `package.json` is sufficient if nothing else declares them. Keep Renovate
  for Playwright and update its review note.
- Release-input and npm evidence checks: remove provider expectations only.
  Keep the Playwright graph checks and all system-release evidence.
- Update `docs/native-tool-inventory.md`, `docs/native-user-tools.md` and
  `docs/dependency-automation.md` for the floating policy and the Playwright
  single source.

### Non-goals

- Component-scoped verification and installation (Phase 8).
- Migrating or cleaning up the old combined npm prefix; the human does a
  clean install.
- Unrelated helper behavior changes, settings overlay changes or skill changes.
  Provider-path wiring needed by the new prefix is in scope.
- Changing Go, actionlint, VIA, mitmproxy or Node/JDK major policy.

### Required context

- `docs/native-tool-inventory.md`
- `docs/native-user-tools.md`
- `docs/dependency-automation.md`
- `scripts/native/provision.py`, `scripts/native/user_tools.py`,
  `scripts/native/verify_release_inputs.py`, `scripts/native/proxy.py`
- Provider launch helpers and their existing argument/environment fixture tests.

### Execution steps

1. Split the manifest and narrow `provision.py:load_manifest()` to system
   inputs.
2. Implement the provider prefix, update command and version-free
   verification. Update generated wrappers and all helper/proxy path consumers
   together; preserve their existing argument and environment behavior.
3. Make the Playwright lockfile authoritative and remove the duplicated
   fields.
4. Update Renovate, the evidence checks, workflow path filters, tests and docs.

### Implementation notes

Floating is a deliberate human decision; record it in the inventory doc as
policy, not as a gap. Provider installation uses the managed prefix and
registry HTTPS, keeps npm integrity verification on and never uses `sudo`.
Keep the transitive-lock HTTPS/integrity checks for the Playwright graph.

### Validation

- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`, including
  `renovate-config-validator --strict` and
  `check_install_inputs.py --publication proposed`.
- `py_compile` for changed Python.
- `actionlint` for changed workflows.
- `rg -n 'claude-code|@openai/codex|gemini-cli' native/npm renovate.json`
  returns no hits.
- Fixtures: updating one provider leaves the others and the Playwright
  project unchanged; Playwright `npm ci` leaves providers unchanged; routine
  preparation does not fetch new provider versions.
- Wrapper and proxy fixtures prove Claude and Codex launches resolve through
  the new provider prefix, including `CODEX_REAL_BIN`, while retaining their
  existing argv/environment assertions. No provider launch uses the old
  `npm/node_modules/.bin` path; Playwright still uses its pinned project.
- Fixtures: a lockfile-only Playwright upgrade fails on stale apt provenance;
  package/lock disagreement and missing transitive integrity fail.

### Completion criteria

System provisioning no longer loads or validates agent-tool declarations. The
three providers are unpinned, untracked by Renovate and updated one at a time
on request. Playwright's version comes from one source, and its apt inputs
stay separately reviewed. All source-validation checks pass.

## Phase 8: Workspace Component-Scoped Installation And Verification

### Workspace

../workspace

### Goal

Make the base VM, each AI provider and the agent extras independently
installable and verifiable, so that a failure in one component never blocks
another component or the application.

### Scope

- Components:
  - `base`: installed system tools and shared environment files;
  - `claude`, `codex`, `gemini`: each provider CLI, plus that provider's
    settings, skills and wrappers (for example the Claude settings overlay and
    skill belong to `claude`; `codex-lean` belongs to `codex`);
  - `extras`: AI Session Handler, `ai-run`, proxy and mitm helpers,
    Playwright/Chromium, the statusline, `via-annotator` and the trust
    helpers. Installing the trust helpers does not require trust to be
    installed yet.
- Move the agent-specific checks currently inside `preflight()` into their
  components:
  - the AI Session Handler checkout requirement;
  - `chromium_apt` packages;
  - the `CODEX_HOME`, `GEMINI_CLI_HOME`, `CLAUDE_CONFIG_DIR` and Playwright
    environment checks;
  - the provider and Playwright home paths.
- CLI: `check` and `install` accept repeatable `--component NAME`. With no
  component, they cover all components. `check` reports every component's
  result and exits non-zero if any selected component fails. The Phase 1
  boundary check always runs first. Each component checks only its own
  prerequisites.
- `scripts/check-agent-vm-boundary.sh` stays the Phase 1 boundary check; it is
  not an alias for `check --component base`.
- Managed-file convergence and state records are per component. Installing
  one component never removes or rewrites another component's files or
  records.
- `check` with no `--component` is the full verifier; the existing public
  check wrapper keeps working as that full check.
- Update the public wrappers, `scripts/prepare-agent-vm-native.sh`, the
  tests and `docs/native-user-tools.md` and `docs/host-isolation.md` to match.

### Non-goals

- Weakening any boundary check (VM identity, repository transport, Git
  configuration, denied environment, credential stores, guest Docker).
- Migrating state written by the previous installer; the human does a clean
  install.
- New providers or helpers.
- Changes in orchestration.

### Required context

- `docs/native-user-tools.md`
- `docs/host-isolation.md`
- `scripts/native/user_tools.py` and `tests/native/test_user_tools.py`
- `native/helpers/` ownership as declared in the manifest

### Execution steps

1. Assign every managed file, helper, setting and check to exactly one
   component in the manifest.
2. Restructure `user_tools.py` around components and move the agent-specific
   preflight checks.
3. Add the `--component` CLI and update the preparation and helper wrappers.
   Where a provider wrapper uses an optional extra (for example the proxy),
   the provider's own check must not require that extra.
4. Add tests showing that:
   - a failing `codex` component does not fail `--component claude`;
   - a stale extras helper does not fail `base`;
   - a boundary failure fails every selection;
   - installing one component leaves other components' files and records
     unchanged.
5. Update the docs.

### Implementation notes

Keep the security boundary exactly as strict as before. The goal is isolating
failures, not relaxing checks. Fresh-shell command-resolution checks apply
only to the names owned by the selected components. "Not selected" never means
"uninstalled".

### Validation

- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`.
- `py_compile` for changed Python.
- `bash -n` and ShellCheck for changed shell scripts.

### Completion criteria

Each component can be installed and checked alone, needing only its own
prerequisites. The boundary check runs first for every selection and is
unchanged in strictness. The isolation tests pass.

## Phase 9: Workspace Documentation, Boundary Guidance And Final Decoupling Check

### Workspace

../workspace

### Goal

Update workspace documentation for the decoupled interfaces:
- workspace no longer serves as orchestration's startup verifier;
- the VM boundary check has its own entry point;
- components are scoped, providers float and trust takes explicit inputs.

Also confirm that workspace owns the agent-runtime rules orchestration moved
out, prove workspace works without an orchestration checkout, and leave a
human handoff for the clean install.

### Scope

- `renovate.json`: keep the shared orchestration preset `extends`. Phases 5 and
  7 already cover the only workspace Renovate changes.
- `README.md`, `AGENTS.md`, `docs/host-isolation.md`,
  `docs/native-user-tools.md`, `docs/native-tool-inventory.md`,
  `docs/local-budget-analyzer-tls.md` and `docs/dependency-automation.md`:
  - remove statements that orchestration invokes workspace's verifier, for
    example "Sibling orchestration calls this same interface", and any
    instruction that orchestration startup depends on workspace checks;
  - document `scripts/check-agent-vm-boundary.sh` as the check to run before
    agent work, after reboot and when diagnosing isolation, plus the
    component-scoped checks;
  - keep the links to orchestration docs, and update any that point to
    orchestration anchors or commands renamed in Phases 3-4, such as
    `check-agent-vm-prerequisites.sh --native-runtime`, which becomes
    orchestration's `check-local-runtime.sh`;
  - the host tunnel keeps forwarding the ports orchestration publishes and
    keeps linking orchestration's port, getting-started and observability
    docs.
- Confirm that workspace `AGENTS.md`, `docs/host-isolation.md` or the managed
  agent system prompt (`native/helpers/system-prompt.md`) states each
  agent-runtime rule orchestration moved out in Phase 4. Add any that are
  missing. The rules are:
  - agents run only as the normal user in the development VM, and retired
    runtimes are not reconstructed;
  - GitHub credentials and publication stay on the personal host;
  - no personal-host credential, mount, Docker/libvirt socket or kubeconfig is
    exposed to the guest;
  - no staging or production kubeconfig, cloud credential, user credential or
    session cookie is exposed to the guest;
  - a VM marker does not prove personal-host isolation;
  - only the human accesses the personal host;
  - guest OS/NSS trust is installed only by the human workspace installer.
- `tests/native/check_manifest.py` link check: links into `../orchestration/`
  must not fail when the sibling is absent (hosted CI). Local links are still
  checked, and orchestration links are checked when the sibling exists.
- Add a CI or test step that runs the source-validation suite from a copy of
  the workspace tree with no orchestration sibling.
- Add a human handoff section to `docs/native-user-tools.md`:
  1. perform a clean install of the agent tooling with the new preparation
     command (no in-place upgrade from the previous layout);
  2. run the trust installer with the explicit inputs;
  3. run the boundary check, the component checks and orchestration's
     `check-tilt-prerequisites.sh`, then perform the documented exact-URL
     Chromium/Playwright browser acceptance check; repeat the trust/browser
     acceptance sequence after certificate renewal;
  4. after the human commits, run `check_install_inputs.py --publication
     committed` and publication CI.

### Non-goals

- Running human-only preparation, trust installation or any live personal-host
  action.
- Removing documentation links to orchestration.
- Replacing or inlining the shared Renovate preset.
- Changes in orchestration.
- Editing `docs/plans/` history.

### Required context

- `AGENTS.md`
- `README.md`
- `docs/host-isolation.md`
- `docs/local-budget-analyzer-tls.md`
- `docs/native-user-tools.md`
- `docs/native-tool-inventory.md`
- `docs/dependency-automation.md`
- `native/helpers/system-prompt.md`
- `tests/native/check_manifest.py`
- `../orchestration/docs/development/getting-started.md`,
  `../orchestration/docs/OWNERSHIP.md` and `../orchestration/scripts/README.md`,
  read only, to confirm current link targets and command names

### Execution steps

1. Update the documents in scope.
2. Confirm or add the agent-runtime rules listed above.
3. Update the link check and add the no-sibling validation step.
4. Add the human handoff.
5. Run the final checks below.

### Implementation notes

Keep the security properties of the host tunnel intact: explicit,
host-loopback-only and human-run. Do not restate orchestration procedures that
a link already covers.

### Validation

- `rg -n '\.\./orchestration|orchestration/' scripts native tests .github`
  returns no hits that read, source or require an orchestration checkout.
  The link checker's handling of sibling links is allowed.
- `rg -n 'check-agent-vm-prerequisites|guest-local|native-runtime' --glob '!tmp/**' --glob '!docs/plans/**'`
  returns no hits that describe orchestration commands.
- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`, including
  `renovate-config-validator --strict` and
  `check_install_inputs.py --publication proposed`.
- The same suite passes from a workspace copy with no orchestration sibling.
- Relative Markdown links in changed files resolve, and links into
  `../orchestration/` point to existing files when the sibling is present.

### Completion criteria

Workspace has no executable or prerequisite dependency on orchestration. It
keeps the shared Renovate preset and its documentation links. The VM boundary
check is documented as workspace's own entry point. Workspace owns every
agent-runtime rule orchestration moved out. All source-validation checks pass,
including without an orchestration sibling. The human clean-install handoff is
documented; this plan does not claim it was executed.
