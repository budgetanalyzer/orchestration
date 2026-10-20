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

  They become a dedicated public, read-only workspace entry point. Every
  workspace install and check runs it first, and users run it before agent
  work. Only the caller changes: orchestration no longer invokes it.
- **The shared Renovate preset stays.** Workspace keeps
  `extends: github>budgetanalyzer/orchestration//renovate-presets/default`.
  It is shared organization policy, not coupling to remove.
- **Orchestration is the sole owner and installer of kubectl, Helm, Tilt and
  Kind.** Its pins live in `scripts/lib/pinned-tool-versions.sh`. Its
  human-run `setup.sh` installs them through `install-verified-tool.sh` (with
  sudo). Workspace stops declaring, installing, checking and running Renovate
  for them.
- **AI provider CLIs float.** Claude Code, Codex and Gemini CLI install at the
  latest published version. They have no pinned version, integrity value or
  Renovate tracking, and the human updates them manually. Verification checks
  only that each provider is present and runs.
- **Playwright stays pinned.** Its Chromium-derived apt inputs stay coupled to
  its exact version. The npm lockfile becomes the single source for its
  version, integrity and tarball.
- **One component never blocks another.** Workspace verification and
  installation become component-scoped: base VM, each provider separately, and
  agent extras. Neither a stale helper nor a missing provider can block another
  provider or the application.

Definition of done:

1. **No executable dependency.** No script, test, CI workflow, Tiltfile or
   manifest in either repository reads, sources, executes or validates files
   from the other repository, or requires the other repository's checkout. The
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

Sequencing: orchestration removes its dependency first (Phases 1-2). Workspace
then removes its dependencies and restructures its own tooling (Phases 3-7).
Each phase executes only in its declared repository. Between Phase 1 and
Phase 6, workspace's existing complete verifier still enforces the VM boundary
for workspace users. The boundary is never unenforced inside workspace.

Safety constraints for every phase:

- no git write operations;
- no certificate or key generation;
- no trust-store writes;
- no execution of human-only workspace preparation or trust installers;
- no live personal-host access;
- no staging or production access.

Agent workers may run offline tests, static checks and read-only local checks.
After Phase 7, the human re-runs workspace preparation and the trust installer
using the new interfaces. That handoff is documented in workspace, not executed
by an agent.

## Phase 1: Orchestration Runtime Decoupling

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
  rejection. Keep `ensure_pinned_tool` and Helm installation as the sole
  kubectl/Helm/Tilt/Kind installer.
- `scripts/bootstrap/check-tilt-prerequisites.sh`: remove `--guest-local` and
  the workspace preflight. Use one mode that checks Docker, the pinned
  platform tools, OpenSSL, Java, Node and npm, the Docker daemon, the local
  Docker endpoint and the exact Kind target when a cluster exists, and the
  three ingress TLS files. mkcert is not a platform prerequisite. Only the
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
  `tests/imported-ingress-tls/` to drop the retired-trust-writer case and the
  `BUDGET_ANALYZER_*_PARENT` variables. Update
  `.github/workflows/test-setup.yml` to run the new test.
- Existing "personal host", "development VM" or "guest" wording in other
  scripts (for example the TLS preparation scripts) may stay as long as it
  does not invoke or require a workspace command.

### Non-goals

- Documentation outside script help text and messages (Phase 2).
- Any change in `../workspace`.
- Changing pinned versions, checksums or the verified installer's behavior.
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
   The only expected surviving hit is the Tilt resource-root deny-list string
   in `scripts/guardrails/check-tilt-resource-roots.sh`.
2. Add the Docker endpoint assertion to `scripts/lib/local-kubernetes-target.sh`.
   It should reject a non-`unix://` `DOCKER_HOST`, a `DOCKER_CONTEXT` or
   current context whose endpoint is not a local Unix socket, and an
   unreachable daemon.
3. Create `scripts/bootstrap/check-local-runtime.sh`, a read-only check that
   runs the Docker endpoint assertion and `assert_local_kind_target`, then
   delete `check-agent-vm-prerequisites.sh` and its test directory.
4. Update `setup.sh`, `check-tilt-prerequisites.sh`,
   `install-imported-ingress-tls.sh` and `check-tilt-resource-roots.sh` as
   scoped above.
5. Add the new offline fixture test, update the imported-TLS test and update
   `test-setup.yml`.
6. Rerun the step 1 inventory with
   `--glob '!scripts/guardrails/check-tilt-resource-roots.sh'` added and
   confirm it returns no hits.

### Implementation notes

The Docker endpoint assertion replaces the guest Docker checks orchestration
previously received from workspace. Keep it minimal and environment-neutral: it
proves Kind will run on a local daemon, not that the machine is a VM. Do not
add a fallback that silently accepts remote Docker endpoints. Keep the helper
pattern used by `check-agent-vm-prerequisites.sh` and `local-kubernetes-target.sh`
(failures print a reason and return non-zero).

### Validation

- `bash -n` and `shellcheck -x` on every added or changed shell script,
  including `setup.sh` and the tests.
- `./tests/local-kubernetes-target/test-local-kubernetes-target.sh`
- `./tests/imported-ingress-tls/test-install-imported-ingress-tls.sh`
- The new `check-local-runtime.sh` fixture test.
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

## Phase 2: Orchestration Documentation Decoupling

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
- `scripts/README.md` (as updated in Phase 1)

### Execution steps

1. Update `docs/OWNERSHIP.md`.
2. Update `AGENTS.md` under the checkstyle.
3. Update the remaining documents listed in scope. If an anchor is renamed,
   fix every inbound link. Workspace docs that link to renamed anchors are
   handled in Phase 7, so record any renamed anchors in the final report.
4. Run the reference checks below and resolve every hit.

### Implementation notes

The following agent-runtime rules belong in workspace. Orchestration may
summarize them in one sentence with a link, but must not be their only home.
Phase 7 confirms that workspace states them:

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
  returns no hits. Links to `../workspace/docs/...` are allowed.
- Every relative Markdown link in changed files resolves. Check with a short
  `rg`/`test -e` loop or an existing link checker.
- Rerun the Phase 1 offline tests to confirm script help text and docs agree.

### Completion criteria

Orchestration's documented setup, daily startup and verification path runs
without any workspace command or workspace verification. Agent-runtime
procedures are linked rather than restated. The reference and link checks
pass. `AGENTS.md` conforms to the checkstyle.

## Phase 3: Workspace Removes Orchestration Platform Tools And Checkout Dependency

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
  checkouts are `workspace`, plus `ai-session-handler` until Phase 6 scopes it
  to its component.
- Update tests under `tests/native/` that construct orchestration fixtures for
  these paths. `test_local_ca.py` stays until Phase 4.
- Update `docs/native-tool-inventory.md` and `docs/dependency-automation.md`
  sections that describe the four tools or the cross-repo contract.

### Non-goals

- The trust helper's orchestration certificate path (Phase 4).
- AI provider or Playwright changes (Phase 5).
- Component-scoped verification (Phase 6).
- Remaining documentation and Renovate preset changes (Phase 7).
- Any change in orchestration.

### Required context

- `AGENTS.md` (workspace validation rules)
- `docs/native-tool-inventory.md`
- `docs/dependency-automation.md`
- `.github/workflows/native-dependency-validation.yml`

### Execution steps

1. Inventory with
   `rg -n -i 'kubectl|helm|tilt|\bkind\b|orchestration' native scripts tests renovate.json .github`.
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
- `check_install_inputs.py --publication committed`;
- `check_user_environment.py`;
- the bash syntax and ShellCheck lists.

Also run `py_compile` for changed Python files and `actionlint` for the changed
workflow.

### Completion criteria

Workspace contains no kubectl/Helm/Tilt/Kind declarations, Renovate rules or
checks. No code path requires or reads an orchestration checkout, except the
trust helper handled in Phase 4. All source-validation checks pass.

## Phase 4: Workspace Trust Helper Uses Explicit Inputs

### Workspace

../workspace

### Goal

Remove the trust helper's dependency on orchestration's
`nginx/certs/k8s/` paths. The human trust installer receives the CA and leaf
explicitly, and the read-only check compares installed trust to workspace-owned
recorded state.

### Scope

- `scripts/native/local_ca.py` and its wrapper
  `scripts/install-agent-vm-local-ca-trust.sh`:
  - the human installer takes `--ca-file`, `--leaf-file` and `--hostname`
    (default `app.budgetanalyzer.localhost`);
  - it keeps every current safety check: no private key, a valid unexpired CA,
    `CA:TRUE`, hostname-aware leaf verification, NSS ownership checks and
    exact-fingerprint system import;
  - it records the approved root in a workspace-owned location under the
    native root.
- `check-budget-analyzer-local-ca-trust`: verify OS and NSS trust against the
  recorded approved root. Do not read any application checkout.
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
   expired root, non-CA, hostname mismatch) and a missing recorded root.
4. Update the two docs.

### Implementation notes

The recorded approved root is public material. Store it with permissions
consistent with the native root. A missing recorded root must fail closed and
print the human install command. Never generate certificates or call `mkcert`.

### Validation

- `python3 -m unittest discover -s tests/native -v` (mocked; under `tmp/`;
  never touches real trust stores)
- `py_compile` for changed Python
- `bash -n` and ShellCheck for the wrapper
- `check_user_environment.py`
- `rg -n 'orchestration' scripts native tests` returns no trust-related hits

### Completion criteria

No workspace code reads orchestration paths for trust. The human installer and
the read-only check work from explicit inputs and workspace-owned state.
Mocked tests pass.

## Phase 5: Workspace Manifest Split, Floating Providers And Single-Source Playwright Pin

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
  - add a floating method (for example `npm-latest`) that installs `@latest`
    into the managed native npm prefix at install time;
  - verification checks presence and `--version` exit status only, with no
    version match;
  - provide a documented manual update path, either a `--update-providers`
    option or a documented npm command.
- Playwright: remove the duplicated `version`, `integrity` and `tarball` fields
  from `toolchain.json`. `validate_lock()`, `chromium_apt_source` and the
  Chromium selection derive the pinned version from the lockfile.
- `renovate.json`: Renovate must ignore the three providers. Removing them from
  `package.json` is sufficient if nothing else declares them. Keep Renovate
  for Playwright with its existing review note.
- `scripts/native/verify_release_inputs.py` and the evidence workflow: drop
  provider release-input verification and keep Playwright's.
- Update `docs/native-tool-inventory.md`, `docs/native-user-tools.md` and
  `docs/dependency-automation.md` for the floating policy and the Playwright
  single source.

### Non-goals

- Component-scoped verification and installation (Phase 6).
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
2. Implement floating provider installation and presence-only verification.
3. Make the Playwright lockfile authoritative and remove the duplicated
   fields.
4. Update Renovate, the release-input verifier, the evidence workflow, tests
   and docs.

### Implementation notes

Floating is a deliberate human decision; record it in the inventory doc as
policy, not as a gap. Keep the transitive-lock HTTPS/integrity checks for the
pinned Playwright graph. Provider installation must still use the managed
prefix and registry HTTPS, and must not use `sudo`.

### Validation

- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`, including
  `renovate-config-validator --strict` and `check_install_inputs.py`.
- `py_compile` for changed Python.
- `actionlint` for changed workflows.
- `rg -n 'claude-code|@openai/codex|gemini-cli' native/npm renovate.json`
  returns no hits.

### Completion criteria

System provisioning no longer loads or validates agent-tool declarations. The
three providers are unpinned and untracked by Renovate. Playwright is pinned
from one source. All source-validation checks pass.

## Phase 6: Workspace Component-Scoped Installation And Verification

### Workspace

../workspace

### Goal

Make the base VM, each AI provider and the agent extras independently
installable and verifiable, so that a failure in one component never blocks
another component or the application.

### Scope

- Components:
  - `base`: the security boundary and system checks from
    `user_tools.py:preflight()` and `system_checks()`;
  - `claude`, `codex`, `gemini`: each provider CLI, plus that provider's
    settings, skills and wrappers (for example the Claude settings overlay and
    skill belong to `claude`; `codex-lean` belongs to `codex`);
  - `extras`: AI Session Handler, `ai-run`, proxy and mitm helpers,
    Playwright/Chromium, the statusline, `via-annotator` and the trust check.
- Move the agent-specific checks currently inside `preflight()` into their
  components:
  - the AI Session Handler checkout requirement;
  - `chromium_apt` packages;
  - the `CODEX_HOME`, `GEMINI_CLI_HOME`, `CLAUDE_CONFIG_DIR` and Playwright
    environment checks;
  - the provider and Playwright home paths.
- CLI: `check` and `install` accept repeatable `--component NAME`. With no
  component, they cover all components. `check` reports every component's
  result and exits non-zero if any selected component fails. `base` always
  runs because the other components depend on its boundary.
- VM boundary entry point: add a dedicated public read-only wrapper, for
  example `scripts/check-agent-vm-boundary.sh`, equivalent to
  `check --component base`. It is the documented check to run before agent
  work and the replacement for the daily boundary re-check that orchestration
  used to trigger. `install-agent-vm-local-ca-trust.sh` and every
  other public workspace install or check entry point must also run the
  boundary first.
- Byte-for-byte managed-file convergence is scoped to the files owned by the
  selected components.
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
3. Add the `--component` CLI and the VM boundary wrapper, and update the other
   wrappers and the preparation script.
4. Add tests showing that:
   - a failing `codex` component does not fail `--component claude`;
   - a stale extras helper does not fail `base`;
   - `base` boundary failures fail every selection;
   - the boundary wrapper runs exactly the `base` checks.
5. Update the docs.

### Implementation notes

Keep the security boundary in `base` exactly as strict as before. The goal is
isolating failures, not relaxing checks. Fresh-shell command-resolution checks
apply only to the names owned by the selected components.

### Validation

- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`.
- `py_compile` for changed Python.
- `bash -n` and ShellCheck for changed shell scripts.

### Completion criteria

Each component can be installed and checked alone. The VM boundary check has
its own public entry point, and every workspace install and check runs it
first. The new isolation tests pass. The base boundary checks are unchanged in
strictness.

## Phase 7: Workspace Documentation, Boundary Guidance And Final Decoupling Check

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

- `renovate.json`: keep the shared orchestration preset `extends`. Phase 3 and
  Phase 5 already cover the only Renovate changes.
- `README.md`, `AGENTS.md`, `docs/host-isolation.md`,
  `docs/native-user-tools.md`, `docs/native-tool-inventory.md`,
  `docs/local-budget-analyzer-tls.md` and `docs/dependency-automation.md`:
  - remove statements that orchestration invokes workspace's verifier, for
    example "Sibling orchestration calls this same interface", and any
    instruction that orchestration startup depends on workspace checks;
  - document `scripts/check-agent-vm-boundary.sh` (or the name chosen in
    Phase 6) as the check to run before agent work, after reboot and when
    diagnosing isolation, plus the component-scoped checks;
  - keep the links to orchestration docs, and update any that point to
    orchestration anchors or commands renamed in Phases 1-2, such as
    `check-agent-vm-prerequisites.sh --native-runtime`, which becomes
    orchestration's `check-local-runtime.sh`;
  - the host tunnel keeps forwarding the ports orchestration publishes and
    keeps linking orchestration's port, getting-started and observability
    docs.
- Confirm that workspace `AGENTS.md`, `docs/host-isolation.md` or the managed
  agent system prompt (`native/helpers/system-prompt.md`) states each
  agent-runtime rule orchestration moved out in Phase 2. Add any that are
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
  1. re-run the human-only preparation;
  2. re-run the trust installer with the new explicit inputs;
  3. run the VM boundary check and the component checks.

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
4. Run the final checks below.

### Implementation notes

Keep the security properties of the host tunnel intact: explicit,
host-loopback-only and human-run. Do not restate orchestration procedures that
a link already covers.

### Validation

- `rg -n '\.\./orchestration|orchestration/' scripts native tests .github`
  returns no hits. Workspace code, tests and CI do not read or require
  orchestration.
- `rg -n 'check-agent-vm-prerequisites|guest-local|native-runtime' --glob '!tmp/**' --glob '!docs/plans/**'`
  returns no hits that describe orchestration commands.
- The full source-validation command set from
  `.github/workflows/native-dependency-validation.yml`, including
  `renovate-config-validator --strict`.
- Relative Markdown links in changed files resolve, and links into
  `../orchestration/` point to existing files.

### Completion criteria

Workspace has no executable or prerequisite dependency on orchestration. It
keeps the shared Renovate preset and its documentation links. The VM boundary
check is documented as workspace's own entry point. Workspace owns every
agent-runtime rule orchestration moved out. All source-validation checks pass.
The human handoff for re-preparation is documented.
