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

  They become a dedicated public, read-only workspace entry point before
  orchestration stops invoking the old verifier. Users run it before agent
  work. Separate provisioning safety from installed readiness: a fresh VM
  must not need the tools it is about to install. Existing unsafe or partial
  installations still fail closed; ordinary runtime checks require readiness.
- **The shared Renovate preset stays.** Workspace keeps
  `extends: github>budgetanalyzer/orchestration//renovate-presets/default`.
  It is shared organization policy, not coupling to remove.
- **Orchestration is the sole owner and installer of kubectl, Helm, Tilt and
  Kind.** Its pins live in `scripts/lib/pinned-tool-versions.sh`. Its
  human-run `setup.sh` installs them through `install-verified-tool.sh` (with
  sudo). Workspace stops declaring, installing, checking and running Renovate
  for them. Applicable installation path, ownership, collision and downgrade
  safeguards, plus both-architecture release validation, move with the tools.
  Workspace retains its VM provisioner and safeguards for its remaining tools.
- **AI provider CLIs float.** Claude Code, Codex and Gemini CLI install at the
  latest published version on first install or explicit human update. Routine
  preparation retains installed versions. They have no repository-pinned
  version or integrity value and no Renovate tracking; npm's transport and
  registry integrity verification remain enabled. Each provider has a separate
  managed npm prefix, also separate from pinned Playwright. Verification keeps
  ownership and command-resolution assertions but removes exact version matching.
- **Playwright stays pinned.** Its Chromium-derived apt inputs stay coupled to
  its exact version. The npm lockfile becomes the single source for its
  version, integrity and tarball, with package-manifest consistency checked.
  Independently reviewed Chromium apt provenance must still match that selection;
  deriving the provenance label from the same lockfile is not compatibility proof.
- **One component never blocks another.** Workspace verification and
  installation become component-scoped: base VM, each provider separately, and
  agent extras. Neither a stale helper nor a missing provider can block another
  provider or the application. Shared safety checks remain mandatory.

Definition of done:

1. **No executable dependency.** No script, test, CI workflow, Tiltfile or
   manifest in either repository discovers or requires implementation files
   from the other repository, or requires the other repository's checkout. Human-
   supplied public certificate inputs are data, not a checkout dependency; they
   must work from any approved location without repository path assumptions. The
   only cross-repository configuration reference is workspace's Renovate
   `extends` of the shared orchestration preset.
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

Sequencing: Phase 1 establishes Workspace's independent boundary entry point
and pre-agent guidance. Phase 2 transfers platform-tool safeguards into
orchestration before Phases 3-4 remove its Workspace dependency. Phases 5-9
remove Workspace's dependencies and restructure its tools. Each phase executes
only in its declared repository. Preserve the existing complete verifier until
its replacement checks are tested; a verifier's existence alone is not proof
that its previous callers remain protected.

Assertion preservation baseline:

| Existing contract | Destination owner and enforcement | Required regression evidence |
| --- | --- | --- |
| kubectl/Helm/Tilt/Kind exact releases and checksums | Orchestration installer and prerequisite checker, including exact Helm matching | Wrong versions rejected; Linux amd64/arm64 release and archive checks retained |
| Safe destinations, ownership, symlinks, collisions and downgrade refusal for those binaries | Orchestration installer; equivalent checks remain in Workspace for its own tools | Unsafe installation fixtures fail before writes |
| VM/user/home, repositories, Git, denied authority and guest Docker | Workspace boundary/preparation entry points | Fresh provisioning and strict runtime cases; failures precede mutation |
| Exact local Kubernetes target and Docker transport | Orchestration bootstrap, daily checks and affected mutation entry points | Remote/wrong targets rejected before cluster changes |
| Current ingress chain and client trust | Orchestration current-leaf/system-trust check; Workspace OS/NSS convergence and browser workflow | Renewed application root versus stale client root fails |
| Provider exact versions and checked-in integrity | Intentionally removed only for Claude, Codex and Gemini | Independent updates; HTTPS, registry integrity, ownership and resolution retained |
| Playwright graph and Chromium apt compatibility | Workspace browser tooling and source validation | Exact lock, package consistency, independent apt provenance and transitive integrity |
| All other pins and assertions, including Go/actionlint/VIA/mitmproxy, Node/JDK policy and helper convergence | Existing owner, scoped to the relevant component | Existing negative cases retained or mapped to replacement tests |

Before deleting a check, record its original source/caller, destination
source/caller and named regression test in the owning repo's affected inventory
or script documentation. Expand the baseline above from the actual code, rather
than treating it as exhaustive. No assertion may disappear without an explicit
mapping; only the three provider pins are approved removals. Document intentional
changes of caller and scope separately from preservation of check semantics.

Validation convention: use `check_install_inputs.py --publication proposed`
during uncommitted implementation, including explicit reviewed new inputs.
Keep `--publication committed` in publication CI and the human handoff after
commit; it compares `git archive HEAD` with current inputs and cannot certify
an uncommitted lockfile change. Never commit merely to satisfy that gate.

Safety constraints for every phase:

- no git write operations;
- no certificate or key generation;
- no trust-store writes;
- no execution of human-only workspace preparation or trust installers;
- no live personal-host access;
- no staging or production access.

Agent workers may run offline tests, static checks and read-only local checks.
After Phase 9, the human re-runs workspace preparation and the trust installer
using the new interfaces. That handoff is documented in workspace, not executed
by an agent.

## Phase 1: Workspace Boundary Entry Point And Preservation Inventory

### Workspace

../workspace

### Goal

Give agent work an independent boundary check before orchestration removes
the old caller, and distinguish provisioning safety from installed readiness.

### Scope

- Extract shared boundary checks from `user_tools.py:preflight()` and
  `provision.py:preflight()` without changing their accepted security boundary.
- Add `scripts/check-agent-vm-boundary.sh`, runnable from the reviewed checkout
  without installed provider helpers. Runtime mode requires healthy guest Docker,
  but does not require provider CLIs, AI Session Handler or platform binaries.
- Provisioning uses the same identity/authority rules with explicit handling
  for absent Docker/system tools. Reject unsafe existing or partial installations;
  validate installed readiness after provisioning.
- Document the independent pre-agent invocation in `docs/host-isolation.md`,
  `docs/native-user-tools.md` and `AGENTS.md`; preserve the full verifier.
- Record the current pin/assertion inventory in `docs/native-tool-inventory.md`,
  including checks that will transfer to orchestration.

### Non-goals

- Removing platform tools, changing provider policy or installing anything live.
- Implementing component-scoped installed-state management.
- Changes in orchestration.

### Required context

- `AGENTS.md`, `docs/host-isolation.md`, `docs/native-user-tools.md`
- `docs/native-tool-inventory.md`, `scripts/native/provision.py`
- `scripts/native/user_tools.py`, `tests/native/`
- `../orchestration/docs/agents-md-checkstyle.md` for the instruction edit

### Execution steps

1. Inventory existing assertions, their callers and tests; distinguish boundary,
   installed-system, platform-tool, trust and agent-component responsibilities.
2. Extract shared checks and add the runtime boundary wrapper. Keep required
   checkout membership scoped to the caller; audit existing repository transport
   without requiring an unused agent or application repository.
3. Wire Workspace's guest provisioning/install/check entry points to the
   appropriate safety stage. Offline source validators and human-host utilities
   must not acquire a guest-runtime prerequisite.
4. Test fresh provisioning, partial/unsafe Docker, runtime Docker absence and
   unchanged negative identity/authority cases. Keep the full verifier passing.
5. Update the inventory, daily guidance and workflow trigger/lint lists for the
   new wrapper. Record stable interfaces for the later phases.

### Implementation notes

The public runtime boundary check and the pre-provisioning check share rules,
but are not interchangeable readiness gates. Missing tools may be installable;
unsafe existing state is never treated as missing. Workspace remains the owner
of Ubuntu/VM, normal-user, repository, credential and Docker provisioning policy.

### Validation

- Native unit tests and existing source validators, using proposed publication.
- Bash syntax and ShellCheck on modified wrappers; Python compilation.
- Fixtures prove the boundary wrapper runs without providers, agent helpers,
  AI Session Handler or orchestration, and fails on unsafe identity/authority.
- A fresh-system fixture reaches staging without already-installed Docker,
  Node or Java; runtime mode still rejects missing required runtime resources.

### Completion criteria

Independent boundary invocation is documented and tested before the old caller
is removed. Provisioning has no installed-readiness circular dependency. The
current assertion inventory and full verifier remain available for migration.

## Phase 2: Orchestration Platform Tool Safeguards And Exact Pins

### Workspace

.

### Goal

Make orchestration ready to assume installation and validation of the four
platform binaries without losing Workspace's applicable safeguards.

### Scope

- `install-verified-tool.sh`, its pin helpers, setup and prerequisite checks.
- Exact Helm enforcement alongside kubectl, Tilt and Kind.
- Installation filesystem/ownership, collision and downgrade protections.
- Linux amd64/arm64 release-download, checksum and archive validation in
  orchestration's own tests/CI, with bounded evidence.
- `docs/OWNERSHIP.md` first, then `scripts/README.md` and dependency automation
  documentation for ownership, validation and the assertion mapping.

### Non-goals

- Changing selected releases/checksums or removing Workspace declarations yet.
- Moving Workspace's VM provisioner, OS policy or guest-isolation logic here.
- Creating a shared installer framework or running privileged installation.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`, `scripts/README.md`
- `docs/dependency-automation.md`, `scripts/lib/pinned-tool-versions.sh`
- `scripts/bootstrap/install-verified-tool.sh`, `setup.sh`
- `scripts/bootstrap/check-tilt-prerequisites.sh`
- Read-only: `../workspace/scripts/native/provision.py`,
  `../workspace/scripts/native/verify_release_inputs.py` and the native inventory

### Execution steps

1. Map every applicable four-tool installation/release assertion from Workspace
   to an orchestration implementation and named regression test before removal.
2. Preserve exact releases and both Linux architecture checksums. Enforce exact
   Helm selection in setup and prerequisites; any supported-range policy is
   compatibility documentation, not a substitute for pin enforcement.
3. Add safe destination/parent ownership, writable-path, symlink and collision
   checks, and refusal of unrequested downgrades before replacement. Preserve
   supported user-owned `--install-dir` CI/cache installs with equivalent
   owner-appropriate checks; do not require root ownership for those paths.
4. Retain HTTPS download, checksum and archive safeguards, staging before writes,
   and post-install command resolution/version verification. Provide a focused
   tool-refresh path that does not recreate Kind or run `setup.sh`.
5. Add offline unsafe-path/version/archive fixtures and CI validation of all
   four releases for Linux amd64/arm64 without executing foreign binaries.
   Preserve existing supported installer platforms.
6. Update ownership, script and evidence documentation and the assertion mapping.

### Implementation notes

Workspace keeps installation protections for its remaining tools. Similar
filesystem checks in independently owned installers do not justify a new
cross-repository executable dependency. Do not copy VM-specific policy here.

### Validation

- Bash syntax and ShellCheck for all affected shell files; workflow actionlint.
- Fixtures for exact Helm rejection, unsafe parents/symlinks, destination
  collisions, unexpected newer versions and post-install resolution.
- Fixtures for checksum mismatch and malformed/missing archive members.
- Both-architecture download validation through the repo-owned verifier;
  no privileged writes, cluster changes or foreign-binary execution.

### Completion criteria

Every transferred installation/release assertion has an orchestration owner
and regression test. Exact pins remain enforced for all four tools and both
Linux architectures remain validated before Workspace removes its coverage.

## Phase 3: Orchestration Runtime Decoupling

### Workspace

.

### Goal

Remove every executable dependency from orchestration on workspace while
preserving the application-environment safety checks that orchestration
previously obtained indirectly from workspace's verifier.

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
  rejection and Phase 2's exact pin/install safeguards. Run the Docker endpoint
  assertion before any cluster deletion or creation, even when no cluster exists.
- `scripts/bootstrap/check-tilt-prerequisites.sh`: remove `--guest-local` and
  the workspace preflight. Use one mode that checks Docker, the pinned
  platform tools, OpenSSL, Java, Node and npm, the Docker daemon, the local
  Docker endpoint and the exact Kind target when a cluster exists, and the
  three ingress TLS files. Verify the current application leaf for the exact
  hostname through the caller's system trust, separately from validation against
  the supplied root; never accept a caller-supplied CA as proof of installed
  client trust. Setup may validate imported files before trust is established;
  readiness for HTTPS client work must report missing/stale trust. mkcert is not
  a platform prerequisite. Only the certificate-preparation script needs it,
  and that script checks for itself.
- `scripts/bootstrap/install-imported-ingress-tls.sh`: remove the retired
  `--install-system-trust` option and its workspace command text, so unknown
  options fail generically.
- `scripts/guardrails/check-tilt-resource-roots.sh`: keep the guard that Tilt
  never generates browser TLS or installs trust. The workspace trust-installer
  name may stay in its deny list, because a deny-list string is a guard rather
  than a dependency. Drop the retired `--install-system-trust` option.
- Tests: delete `tests/native-preflight-wrapper/`. Add an offline fixture test
  for `check-local-runtime.sh` and the Docker endpoint assertion. Update
  `tests/imported-ingress-tls/` to remove Workspace-specific error expectations
  and the `BUDGET_ANALYZER_*_PARENT` variables, while retaining a generic
  unknown-option rejection test proving no trust write occurs. Update
  `.github/workflows/test-setup.yml` to run the new test.
- Existing "personal host", "development VM" or "guest" wording in other
  scripts (for example the TLS preparation scripts) may stay as long as it
  does not invoke or require a workspace command.
- Update nearest operational docs and the agent boundary pointer with the
  interface change; Phase 4 handles the broader documentation sweep.

### Non-goals

- Broad documentation cleanup outside affected interfaces (Phase 4).
- Any change in `../workspace`.
- Changing pinned versions/checksums or undoing Phase 2's installer safeguards.
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
   Classify live dependencies separately from documentation and negative-test
   strings. The Tilt resource-root deny list and generic unknown-option fixture
   remain guards, not executable dependencies.
2. Add the Docker endpoint assertion to `scripts/lib/local-kubernetes-target.sh`.
   It should reject a non-`unix://` `DOCKER_HOST`, a `DOCKER_CONTEXT` or
   current context whose endpoint is not a local Unix socket, and an
   unreachable daemon. Resolve effective Docker selection consistently with the
   actual commands, including environment/context precedence. Reject conflicting
   selection rather than checking one daemon and operating on another.
3. Create `scripts/bootstrap/check-local-runtime.sh`, a read-only check that
   runs the Docker endpoint assertion and `assert_local_kind_target`, then
   delete `check-agent-vm-prerequisites.sh` and its test directory.
4. Update `setup.sh`, `check-tilt-prerequisites.sh`,
   `install-imported-ingress-tls.sh` and `check-tilt-resource-roots.sh` as
   scoped above. Ensure endpoint checks precede mutations and all cluster reads
   that assume the selected target. Retain the exact Kind checks wherever they
   already gate mutation. Add current-leaf/system-trust validation and the
   required pre-agent Workspace documentation pointer.
5. Add the new offline fixture test, update the imported-TLS test and update
   `test-setup.yml`.
6. Rerun the step 1 inventory with
   `--glob '!scripts/guardrails/check-tilt-resource-roots.sh'` added and
   resolve hits against the permitted documentation links, unknown-option test
   and deny-list exceptions; do not delete negative tests to satisfy a search.

### Implementation notes

The Docker endpoint assertion checks the selected local Unix-socket transport
and daemon reachability; it does not prove VM or guest-daemon isolation.
Workspace retains that stronger responsibility. Do not
add a fallback that silently accepts remote Docker endpoints. Keep the helper
pattern used by `check-agent-vm-prerequisites.sh` and `local-kubernetes-target.sh`
(failures print a reason and return non-zero).

### Validation

- `bash -n` and `shellcheck -x` on every added or changed shell script,
  including `setup.sh` and the tests.
- `./tests/local-kubernetes-target/test-local-kubernetes-target.sh`
- `./tests/imported-ingress-tls/test-install-imported-ingress-tls.sh`
- The new `check-local-runtime.sh` fixture test.
- Fixtures prove remote/conflicting Docker selection fails before cluster
  deletion/creation, a fresh bootstrap does not require an existing cluster,
  and daily checks reject absent or wrong Kind targets.
- A fixture with valid imported root/leaf B and system trust containing only
  root A must fail client readiness. Preserve expired/hostname-mismatch cases.
- Run orchestration's focused offline checks from a disposable source tree
  without a Workspace sibling, using fixtures for external runtime dependencies.
- `actionlint .github/workflows/test-setup.yml` if available locally.
- If the live local cluster is up, run `./scripts/bootstrap/check-local-runtime.sh`
  and `./scripts/bootstrap/check-tilt-prerequisites.sh` and record the outcome.
  Do not run `setup.sh`.

### Completion criteria

No orchestration script, test, workflow or Tiltfile invokes, sources or
requires a workspace file, command or workspace-managed environment variable.
The Tilt resource-root deny-list string and links to `../workspace/docs/...`
in help text are the only permitted workspace mentions. The
offline setup contracts pass. Daily and bootstrap prerequisite checks are
orchestration-owned and enforce the local Docker endpoint and the exact Kind
target.

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
    split in one or two sentences with links.
    Keep a mandatory pointer for native agent sessions to Workspace's documented
    pre-agent boundary check; this is an agent duty, not an application startup
    dependency. Phase 1 established that interface before removal of the caller.
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

  Document build prerequisites and the distinction between valid imported TLS
  files and established client trust. Before HTTPS client/API work, run the
  orchestration current-certificate/system-trust readiness check. Keep browser
  OS/NSS preparation in the linked environment-specific documentation.

  Add a short "Running in the workspace development VM" note that links to
  workspace for VM provisioning, three-file transfer, guest trust, the host
  tunnel and agent launch. Remove the inline agent launch, provider, AI
  Session Handler and native-shell instructions.
- `docs/dependency-automation.md`: no change to the shared preset's consumer
  scope. Workspace remains a consumer.
- Keep link validation independent of sibling availability: validate local
  targets in standalone CI, allow the intentional sibling-document links, and
  check those targets separately when both repositories are present.

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
  returns no unexplained hits. Links to `../workspace/docs/...` and the negative
  unknown-option fixture are allowed; retain safety tests rather than erasing
  their test inputs for a clean search.
- Every relative Markdown link in changed files resolves. Check with a short
  `rg`/`test -e` loop or an existing link checker.
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

### Execution steps

1. Inventory with
   `rg -n -i 'kubectl|helm|tilt|\bkind\b|orchestration' native scripts tests renovate.json .github`.
   Confirm Phase 2's destination implementations/tests cover every transferred
   assertion before deleting Workspace's declarations or release validation.
2. Remove the four tool records, Renovate managers and reviewed-source entries.
3. Remove the related provisioner, verifier and release-input handling, and the
   required orchestration checkout.
4. Update tests, the CI invocation and the two inventory and automation docs.

### Implementation notes

Leave the generic `downloads` machinery intact for the remaining system tools
(actionlint, Go, VIA). Do not add a replacement check for the removed tools;
orchestration verifies them now.

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
trust helper handled in Phase 6. Existing installation protections for all
remaining Workspace tools are preserved. All source-validation checks pass.

## Phase 6: Workspace Trust Helper Uses Explicit Inputs

### Workspace

../workspace

### Goal

Remove the trust helper's dependency on orchestration's
`nginx/certs/k8s/` paths. The human trust installer receives the CA and leaf
explicitly, and the read-only check compares installed trust to workspace-owned
recorded state. That check proves store convergence, not freshness against a
changed application certificate; retain a separate current-application proof.

### Scope

- `scripts/native/local_ca.py` and its wrapper
  `scripts/install-agent-vm-local-ca-trust.sh`:
  - the human installer takes `--ca-file` and `--leaf-file`, while retaining
    the exact hostname `app.budgetanalyzer.localhost`; do not broaden the
    accepted hostname as part of decoupling;
  - it keeps every current safety check: no private key, a valid unexpired CA,
    `CA:TRUE`, hostname-aware leaf verification, NSS ownership checks and
    exact-fingerprint system import;
  - preserve legacy duplicate-root detection/convergence, exact NSS fingerprint
    and `C,,` flags, bundle validation, safe paths and Python/Node trust exports;
  - record the approved public root and validated public leaf under the native
    root only after successful convergence; use staged/atomic record writes and
    reject missing, malformed or partially migrated state. Ordinary checks may
    never approve a new root or repair stores.
- `check-budget-analyzer-local-ca-trust`: verify OS and NSS trust against the
  recorded approved root and revalidate recorded certificate expiry/hostname.
  Do not derive any application checkout path. Optionally supplied current
  CA/leaf inputs must be checked against the approved root, never silently
  adopted; this permits explicit diagnosis after renewal.
- Preserve the Workspace browser workflow's verified HTTPS probe of exactly
  `https://app.budgetanalyzer.localhost` using its normal NSS-backed browser.
  This is application-specific readiness, not a prerequisite for base/provider
  checks or generic Workspace installation. It must detect the current
  application becoming untrusted even if recorded-root convergence passes.
- `tests/native/test_local_ca.py`: replace orchestration fixture paths with
  explicit-input fixtures.
- `docs/local-budget-analyzer-tls.md` and the trust sections of
  `docs/native-user-tools.md`: document the explicit-input human command. The
  documented command may pass orchestration's published TLS file locations
  (for example
  `"$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration/nginx/certs/k8s/_mkcert-rootCA.pem"`)
  and link orchestration's TLS docs. Only the code must not derive those
  paths.

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
3. Update the tests to cover explicit inputs, rejected inputs (private key,
   expired root/leaf, non-CA, hostname mismatch), missing/partial recorded state,
   legacy duplicates, NSS flags/fingerprints and trust environment failures.
   Include approved root A versus supplied/current application root B: the
   current-application check fails until the human reconciles trust. Test failed
   installation without falsely advancing recorded approval.
4. Update the two docs.

### Implementation notes

The recorded approved root is public material. Store it with permissions
consistent with the native root. A missing recorded root must fail closed and
print the human install command. Never generate certificates or call `mkcert`.
Reuse approved public test fixtures or mocks; do not generate certificates for
tests. Phase 3 owns the current application leaf/system-trust assertion;
Workspace owns OS/NSS convergence and browser-client proof. Installing trust
must not depend on a successful trust check or the complete extras component.

### Validation

- `python3 -m unittest discover -s tests/native -v` (mocked; under `tmp/`;
  never touches real trust stores)
- `py_compile` for changed Python
- `bash -n` and ShellCheck for the wrapper
- `check_user_environment.py`
- `rg -n 'orchestration' scripts native tests` returns no derived trust paths
- Run trust and boundary fixtures with no orchestration sibling and inputs in
  an arbitrary fixture directory. Record the exact-origin browser acceptance
  check for the human handoff if a live check cannot yet run.

### Completion criteria

No workspace code reads orchestration paths for trust. The human installer and
the read-only check work from explicit inputs and workspace-owned state.
Store convergence is not reported as current application readiness. Existing
trust assertions and renewed-root failure cases pass their mocked tests.

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
    `package-lock.json`;
  - remove their version, integrity and tarball fields;
  - add a floating method (for example `npm-latest`) that resolves `@latest`
    on first installation or explicit human update into a separate managed
    prefix for each provider, outside the pinned Playwright project;
  - routine preparation retains installed providers; updating one provider
    must not change another provider or Playwright's package/lock/installed graph;
  - verification checks presence and `--version` exit status only, with no
    version match, while retaining ownership, path and fresh-shell resolution
    checks. Record observed versions as diagnostic evidence, not desired pins;
  - provide a documented manual update path, either a `--update-providers`
    option or a documented npm command.
- Playwright: remove duplicated release fields from `toolchain.json`.
  `validate_lock()` and Chromium selection consume the exact lockfile entry;
  assert package.json and package-lock.json agree. Keep independently reviewed
  `chromium_apt_source` provenance and compare it to that selection. A lock-only
  upgrade must fail until apt compatibility is independently reviewed or
  mechanically verified from the selected upstream release. Do not synthesize
  the provenance label from the version being checked.
- `renovate.json`: Renovate must ignore the three providers. Removing them from
  `package.json` is sufficient if nothing else declares them. Keep Renovate
  for Playwright and update its review note for the new ownership/provenance.
- Inspect actual release-input and npm evidence paths: the binary release
  verifier covers system downloads, while npm input/audit checks cover the npm
  graph. Remove only provider pin expectations from their actual consumers;
  preserve Playwright graph checks and all remaining system-release evidence.
- Migrate the existing combined npm prefix through a human-run, repeatable
  transition: stage replacements, verify them before switching wrappers, and
  preserve credentials/settings and recoverable old package state until success.
  The current installer rejects changed package/lock inputs; add an explicit
  managed-state migration rather than bypassing arbitrary collision checks.
- Update `docs/native-tool-inventory.md`, `docs/native-user-tools.md` and
  `docs/dependency-automation.md` for the floating policy and the Playwright
  single source.

### Non-goals

- Component-scoped verification and installation (Phase 8).
- Changing helpers, settings overlays or skills.
- Changing Go, actionlint, VIA, mitmproxy or Node/JDK major policy.

### Required context

- `docs/native-tool-inventory.md`
- `docs/native-user-tools.md`
- `docs/dependency-automation.md`
- `scripts/native/provision.py`, `scripts/native/user_tools.py`,
  `scripts/native/verify_release_inputs.py`

### Execution steps

1. Split the manifest and narrow `provision.py:load_manifest()` to system
   inputs.
2. Implement separate prefixes, explicit provider updates and version-unpinned
   verification; retain HTTPS and registry integrity verification.
3. Make the Playwright lockfile authoritative and remove the duplicated
   fields.
4. Implement and test migration from the old shared prefix, including partial
   failure and rerun behavior. Preserve the pinned Playwright graph.
5. Update Renovate, the affected release/npm evidence checks, workflow path
   filters, tests and docs. Do not imply provider graphs remain covered by the
   pinned dependency evidence after their deliberate exclusion.

### Implementation notes

Floating is a deliberate human decision; record it in the inventory doc as
policy, not as a gap. Keep the transitive-lock HTTPS/integrity checks for the
pinned Playwright graph. Provider installation must still use the managed
prefixes and registry HTTPS, and must not use `sudo`. Registry integrity
verification remains enabled even though provider integrity is no longer a
checked-in pin. Shared caches are acceptable; shared dependency graphs are not.

### Validation

- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`, including
  `renovate-config-validator --strict` and `check_install_inputs.py`.
- `py_compile` for changed Python.
- `actionlint` for changed workflows.
- `rg -n 'claude-code|@openai/codex|gemini-cli' native/npm renovate.json`
  returns no hits.
- Fixtures verify a provider update preserves the other provider prefixes and
  Playwright graph, Playwright `npm ci` preserves providers, routine preparation
  does not resolve new provider versions, and an interrupted migration is
  recoverable without changing credentials/settings.
- Lock-only Playwright upgrades fail stale apt provenance; malformed URLs,
  missing transitive integrity and package/lock disagreement remain failures.

### Completion criteria

System provisioning no longer loads or validates agent-tool declarations. The
three providers are unpinned and untracked by Renovate, with isolated updates
and a tested old-prefix migration. Playwright release metadata has one authority
and independent apt compatibility evidence. All source-validation checks pass.

## Phase 8: Workspace Component-Scoped Installation And Verification

### Workspace

../workspace

### Goal

Make the base VM, each AI provider and the agent extras independently
installable and verifiable, so that a failure in one component never blocks
another component or the application.

### Scope

- Components:
  - `base`: installed-system readiness and shared environment resources,
    distinct from Phase 1's independently callable security-boundary checks;
  - `claude`, `codex`, `gemini`: each provider CLI, plus that provider's
    settings, skills and wrappers (for example the Claude settings overlay and
    skill belong to `claude`; `codex-lean` belongs to `codex`);
  - `extras`: AI Session Handler, `ai-run`, proxy and mitm helpers,
    Playwright/Chromium, the statusline, `via-annotator` and trust helpers.
    Distinguish installing helpers from verifying established trust: installation
    can precede the human trust step. Browser/application readiness remains a
    focused explicit check.
- Move the agent-specific checks currently inside `preflight()` into their
  components:
  - the AI Session Handler checkout requirement;
  - `chromium_apt` packages;
  - the `CODEX_HOME`, `GEMINI_CLI_HOME`, `CLAUDE_CONFIG_DIR` and Playwright
    environment checks;
  - the provider and Playwright home paths.
- CLI: `check` and `install` accept repeatable `--component NAME`. With no
  component, they cover all components. `check` reports every component's
  result and exits non-zero if any selected component fails. Boundary checks
  always run; installed prerequisites are checked only where required. Do not
  make every provider require all unrelated system tools merely because they
  share a system provisioner.
- Keep Phase 1's public `scripts/check-agent-vm-boundary.sh` independent of full
  installed-system readiness; it is not an alias for `check --component base`.
  Guest-runtime installers/checkers invoke the appropriate shared boundary
  stage. Source validators, first provisioning and human-host tools retain
  their distinct execution contracts.
- Byte-for-byte managed-file convergence is scoped to the files owned by the
  selected components. Use component-owned state or an ownership-aware merge of
  state; absence from a selected plan must not retire another component's files.
  Assign shared environment files and engine code explicitly; avoid copying an
  entire agent manifest into base state so unrelated edits invalidate base.
- Migrate legacy `managed-files.json` and `installation.json` safely. Retire
  only selected-component files whose prior recorded bytes still match, preserve
  unselected records and user settings/authentication, and keep partial failure
  recoverable. Handle the old combined npm state consistently with Phase 7.
- Update the public wrappers, `scripts/prepare-agent-vm-native.sh`, the
  tests and `docs/native-user-tools.md` and `docs/host-isolation.md` to match.

### Non-goals

- Weakening any base boundary check (VM identity, repository transport, Git
  configuration, denied environment, credential stores, guest Docker).
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
3. Add the `--component` CLI, preserve the existing independent boundary wrapper,
   and update preparation and helper wrappers. Map actual helper dependencies
   explicitly, such as proxy extras used by an optional provider wrapper; core
   provider verification must not require optional integrations.
4. Add tests showing that:
   - a failing `codex` component does not fail `--component claude`;
   - a stale extras helper does not fail `base`;
   - boundary failures fail every guest-runtime selection;
   - the boundary wrapper runs boundary checks without full base readiness;
   - selecting one component preserves all unselected files and state records;
   - legacy state migrates repeatably and interruption preserves recoverability;
   - user settings/authentication survive migration;
   - changing provider-specific source does not invalidate unrelated convergence;
   - fresh provisioning and trust installation do not require their own
     successful post-install readiness checks.
5. Update the docs.

### Implementation notes

Keep the shared security boundary exactly as strict as before. Fresh-shell
command-resolution checks apply only to selected components and their necessary
shared resources. The boundary wrapper must remain usable from checkout even
when installed helper state needs migration. Installation cleanup must never
interpret "not selected" as "uninstalled."

### Validation

- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`.
- `py_compile` for changed Python.
- `bash -n` and ShellCheck for changed shell scripts.

### Completion criteria

Each component can be installed and checked with only its actual prerequisites.
The independent boundary entry point and staged provisioning checks remain
intact. Isolation, fresh-install and legacy-state migration tests pass without
weakening any boundary assertion.

## Phase 9: Workspace Documentation, Boundary Guidance And Final Decoupling Check

### Workspace

../workspace

### Goal

Update workspace documentation for the decoupled interfaces:
- workspace no longer serves as orchestration's startup verifier;
- the VM boundary check has its own entry point;
- components are scoped, providers float and trust takes explicit inputs.

Also confirm that workspace owns the agent-runtime rules orchestration moved
out, and leave a human handoff for re-preparation.

### Scope

- `renovate.json`: keep the shared orchestration preset `extends`. Phases 5 and
  7 already cover the only Workspace Renovate changes.
- `README.md`, `AGENTS.md`, `docs/host-isolation.md`,
  `docs/native-user-tools.md`, `docs/native-tool-inventory.md`,
  `docs/local-budget-analyzer-tls.md` and `docs/dependency-automation.md`:
  - remove statements that orchestration invokes workspace's verifier, for
    example "Sibling orchestration calls this same interface", and any
    instruction that orchestration startup depends on workspace checks;
  - document `scripts/check-agent-vm-boundary.sh`, established in Phase 1,
    as the check to run before agent work, after reboot and when
    diagnosing isolation, plus the component-scoped checks;
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
- Add a human handoff section to `docs/native-user-tools.md`:
  1. after review and stopping affected workers, re-run human-only preparation
     through the tested legacy-state migration; retain installed provider
     versions unless explicitly selecting updates;
  2. re-run the trust installer with the new explicit inputs;
  3. run the VM boundary, selected component and exact-origin browser checks;
     distinguish local store convergence from current application trust;
  4. after the human commits, run committed-source validation and publication CI.
- Reconcile the assertion inventory with final implementations, callers and
  named tests. Every non-provider pin/assertion has a destination; identify
  changes in execution stage or component scope without claiming their former
  callers still execute them.
- Update source-validation/link checking so allowed sibling documentation links
  do not require a sibling checkout in hosted CI. Preserve validation of local
  links and separately check cross-repository targets when available.
- Add a standalone source-tree test without orchestration, including offline
  provisioning, component and explicit-trust-input fixtures. Update workflow
  trigger, syntax-check, evidence-input and lint lists for all new files.

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
- `../orchestration/docs/development/getting-started.md`,
  `../orchestration/docs/OWNERSHIP.md` and `../orchestration/scripts/README.md`,
  read only, to confirm current link targets and command names

### Execution steps

1. Update the documents in scope.
2. Confirm or add the agent-runtime rules listed above.
3. Add the human handoff.
4. Reconcile the assertion mapping and add standalone source validation; retain
   the intentional shared Renovate preset without introducing a local checkout
   dependency.
5. Run the final checks below.

### Implementation notes

Keep the security properties of the host tunnel intact: explicit,
host-loopback-only and human-run. Do not restate orchestration procedures that
a link already covers.

### Validation

- `rg -n '\.\./orchestration|orchestration/' scripts native tests .github`
  returns no executable checkout dependencies. Allow intentional sibling-doc
  link classification in validators; an absence-of-checkout test may name the
  sibling without depending on it. No code derives application trust paths.
- `rg -n 'check-agent-vm-prerequisites|guest-local|native-runtime' --glob '!tmp/**' --glob '!docs/plans/**'`
  returns no hits that describe orchestration commands.
- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`, including
  `renovate-config-validator --strict`, using proposed publication for the
  uncommitted worktree. Keep committed validation as the later publication gate.
- Relative Markdown links in changed files resolve, and links into
  `../orchestration/` point to existing files when checking the complete local
  ecosystem. Their absence in standalone CI is not a failure.
- Run the source-validation suite and dependency fixtures in a disposable
  Workspace source tree without an orchestration sibling. Use prepared test
  fixtures for required resources; do not invoke live installers.
- Verify the completed inventory includes negative tests for every retained
  boundary, installation, trust, pin and managed-file assertion.

### Completion criteria

Workspace has no executable or prerequisite dependency on orchestration. It
keeps the shared Renovate preset and its documentation links. The VM boundary
check is documented as workspace's own entry point. Workspace owns every
agent-runtime rule orchestration moved out. All source-validation and isolated
checkout checks pass, with no unmapped assertion removals. The human handoff
for migration, trust/browser verification and committed-source validation is
documented; those human actions are not claimed as executed by this plan.
