# Guest-Local Development VM Implementation Plan

**Status:** Manual host preparation is in progress; clean implementation is
proposed and no runtime migration is planned.

**Companion:** [Manual VM setup and operator checkpoints](agent-host-isolation-manual-plan.md).

Protect the personal workstation and its GitHub credentials by keeping agent
source, builds and runtime state on a development VM. Preserve a native host
editor window and browser, normal GitHub pull-request review, and ordinary Git
branches without sharing the host workspace or giving the guest GitHub write
credentials.

The guest starts clean. Do not copy, export, import or reconstruct host Docker
images, containers, volumes, Kind clusters, databases, application data or
build caches. Create a new guest Docker daemon, Kind cluster and application
state from the reviewed configuration. The only host-to-guest inputs are
committed Git objects and the approved browser-trusted development TLS files.

Implement on feature branches from the existing working Mint-hosted workspace
devcontainer. It is defined by sibling workspace
`.devcontainer/devcontainer.json` and `ai-agent-sandbox/docker-compose.yml` and
remains the implementation runner through Phases 1–6 and Checkpoint B. Phase 2
adds a separate guest runtime at
`ai-agent-sandbox/docker-compose.agent-vm.yml`; it must not convert, replace or
silently select guest wiring for the Mint devcontainer. Do not retire Mint
Docker merely because the guest agent starts successfully. The human performs
the one explicit retirement step only afterward in manual Checkpoint C,
producing the final guest-only Docker architecture and removing the
transitional host-Docker firewall integration. Do not add saved images or
recovery drills.

## Agreed design

```text
Personal workstation: Linux Mint 22.1
  GitHub credentials and canonical clones stay here
  Docker hosts implementation agents through Phase 6 and Checkpoint B only
  final state has no Docker daemon, socket, CLI, runtime data or Docker rules
  libvirt storage pool -> /data/libvirt/agent-vm-images
  VS Code UI -- Remote SSH --------------------------> guest-local working clones
  browser -> host loopback HTTPS forward ------------> guest ingress
  git push/fetch through host-initiated SSH ----------> guest bare repositories
  host-owned firewall denies new guest-to-host connections

Ubuntu Server 24.04 LTS VM: KVM/QEMU managed by libvirt and virt-manager
  guest-local bare repositories and working clones; no shared host workspace
  guest-local OS, Docker storage, build caches and persistent volumes
  one Docker daemon: Kind + Testcontainers + target guest agent container
  guest agent supports bootstrap validation and becomes the post-cutover runtime
  working-clone origin -> guest-local bare repository, never GitHub
```

- The personal host pulls private or public repositories from GitHub. A
  host-initiated Git push over SSH sends a selected branch to a bare repository
  inside the VM. The guest working clone fetches from and pushes to that local
  bare repository. The host later fetches the agent commits from the same VM
  remote, fast-forwards its branch, and alone pushes to GitHub or creates a PR.
- Do not introduce rsync, shared folders, automated publication, a GitHub fork,
  or a Git credential proxy. The setup script establishes VM remotes once; daily
  branch transfer uses ordinary explicit Git commands.
- The guest receives no GitHub write credential, SSH/GPG agent, host credential
  helper, authenticated GitHub browser state, host Git metadata, host Docker or
  libvirt socket, host kubeconfig, or personal home-directory mount. Private
  repositories need no guest GitHub credential because the host supplies Git
  objects through the VM remote.
- Use VS Code Remote SSH for a native host UI with files, extension host,
  terminals, tasks and language servers in the guest. Disable SSH-agent, X11,
  credential and automatic port forwarding. Do not expose host GitHub sessions
  to remote extensions.
- Assume the agent can administer the guest through its Docker socket and can
  alter or destroy all guest repositories and development credentials. Build
  and run the tool-packaging agent container in the guest, remove DinD, and
  allow **guest** host networking to preserve localhost access. No privileged
  container or nested daemon is needed.
- Permit normal Internet access. Deny new guest-initiated connections to all
  personal-host addresses with host-enforced IPv4/IPv6 rules; allow established
  replies and narrowly scoped DNS/DHCP if provided by the host. Internet
  destination allowlists and additional LAN/VPN isolation are outside this plan.
- Adopt UFW as the Mint host's persistent native-input manager with its recorded
  deny-incoming, allow-outgoing and deny-routed defaults. During implementation,
  the discovered host Docker `iptables-nft` backend is protected through IPv4
  and IPv6 `DOCKER-USER` rules reapplied after Docker starts and UFW reloads.
  Those Docker rules and hooks are transitional: manual Checkpoint C removes
  them after every implementation agent has finished and Mint Docker is
  uninstalled. The native UFW `virbr1` boundary remains permanent. Do not use
  raw nftables, legacy-iptables or a saved copy of Docker/libvirt-generated
  rules. The companion manual plan owns the exact host-specific commands,
  bridge/network evidence and final cleanup.
- Use the personal browser with a dedicated development profile and identities.
  Its profile and debugging interface are not shared. Forward host loopback
  HTTPS to the guest; in the final architecture keep Docker, Kubernetes and
  observability private to the guest.
- Development server keys and infrastructure CA material may remain in the
  guest. Keep the personal host's mkcert signing key outside it. Copy only the
  existing host-trusted development leaf certificate/key and public CA into the
  guest through a human-operated transfer; never require the personal browser to
  trust a guest-controlled signing CA or bypass TLS verification.
- Treat guest runtime state as disposable and rebuild it from reviewed
  configuration. Do not use VM snapshots or Docker exports to carry host runtime
  state into the guest. Host GitHub credentials remain outside the guest; host
  branch protections and review remain necessary before publishing agent-authored
  code or workflows.

## Repository transport contract

Phase 2 creates a reviewed host-run one-time script at
`../workspace/scripts/setup-agent-vm-repositories.sh`. The script must:

1. Discover immediate sibling Git repositories under a human-selected common
   parent instead of maintaining a static ecosystem inventory.
2. Print the exact repository set and guest destination and require human
   confirmation before changing either side.
3. Require clean host repositories with a local `main` and reject detached
   heads, duplicate basenames, unresolved paths and an existing `vm` remote that
   points somewhere else.
4. Use a caller-supplied SSH host alias and guest root; preserve SSH host-key
   verification and never enable agent forwarding.
5. Create one guest bare repository and one guest working clone per discovered
   repository, add the `vm` remote to each host clone, and seed `main` plus the
   current checked-out branch when different. Check out that selected branch
   in the guest working clone so bootstrap uses the implementation changes.
   Do not mirror all refs, tags, hooks, host Git configuration or uncommitted
   files.
6. Configure each guest working clone's `origin` as its guest-local bare
   repository. Do not add a GitHub remote or copy any GitHub credential into the
   guest.
7. Refuse force pushes, replacement of non-empty destinations and silent remote
   rewrites. Be safely repeatable for an already matching partial setup.
8. Stop after setup. Do not add daily sync, commit, GitHub push, PR creation or
   publication behavior.

The script is stored in an agent-writable repository for review and versioning,
but the human runs a reviewed copy on the host. The guest cannot invoke it on
the host. All later host-to-VM and VM-to-host transfers are explicit Git pushes
and fetches initiated at the appropriate side.

Phase 2 also creates reviewed guest-run lifecycle helpers for the agent
container. These helpers are operational wrappers, not repository-transfer or
publication automation. They must:

1. Provide stable start, stop, restart, status and interactive-shell entry
   points under the workspace `scripts/` directory.
2. Resolve the workspace and Compose paths relative to the installed helper;
   do not depend on the caller's current directory or hardcode the common
   parent path.
3. Use `agent-vm.env`, `docker-compose.agent-vm.yml` and, for normal daily
   operation, `docker-compose.agent-vm-kubeconfig.yml` together so operators do
   not have to reconstruct a shell array in every SSH session.
4. Require the reviewed guest-local Docker endpoint and exact kubeconfig input
   for normal start, restart and shell operations. If pre-Kind bootstrap needs
   the base Compose file alone, expose that only through a distinctly named,
   explicit bootstrap option that cannot become the accidental daily path.
5. Preserve provider configuration volumes on stop/restart, avoid rebuilding
   unless explicitly requested, and never start or restart Kind, Tilt, the VM,
   host forwarding or a nested Docker daemon as a side effect.
6. Fail clearly when the environment file, Compose files, Docker endpoint,
   kubeconfig or agent service is missing or invalid. Print the effective
   operation without printing credentials or full environment contents.

## Execution and handoff

This plan follows the [AI Session Handler format](../../../ai-session-handler/docs/plan-format.md).
Each phase runs only in its declared repository. Do not edit this plan during
an active invocation. Execution does not authorize GitHub writes, production
changes, automatic personal-host administration or service-logic changes.
Disposable local Git fixtures explicitly required by a phase are allowed; all
real host and guest branch-transfer commands remain human checkpoints.

1. The human completes **Steps 1–5** of the manual plan and supplies its handoff
   record. This includes the deliberate UFW adoption, persistent IPv4/IPv6
   `DOCKER-USER` policy and native/Docker positive and negative tests recorded
   in Step 4. Resolve missing VM, storage, SSH and firewall prerequisites before
   implementation.
2. Run **Phases 1–2** to prepare reviewable orchestration and workspace changes.
   Run them from the existing Mint-hosted workspace devcontainer. These are
   offline authoring phases; do not launch the guest agent-container
   configuration or administer the host. Preserve the current Mint
   devcontainer as a working implementation runner and end the invocation after
   Phase 2.
3. The human completes **Checkpoint A**: run the reviewed one-time repository
   setup script, transfer approved TLS material, install guest prerequisites,
   and launch and authenticate the guest agent before bootstrapping Kind/Tilt
   and fresh application state. The agent is available to help diagnose bootstrap.
4. Run **Phases 3–6** from the same existing Mint-hosted workspace devcontainer.
   The separately launched guest agent container proves and diagnoses the target
   runtime; it does not run the implementation plan. Guest-runtime validation
   commands and evidence must still come from the VM through the reviewed guest
   access path. Host residency does not authorize a host Docker fallback for
   guest tests. Do not disable or uninstall Mint Docker during any
   implementation phase.
5. The human completes **Checkpoint B** for host-browser, restart and
   daily-workflow acceptance while Mint Docker and its transitional protection
   remain available to the implementation agents.
6. After the Phase 1–6 run and Checkpoint B are complete and every
   implementation-agent session has ended, the human completes **Checkpoint C**
   to uninstall Mint Docker, delete its approved retired runtime state, remove
   the Docker-specific firewall helper/hooks and accept the guest-only Docker
   final architecture.

Keep a redacted acceptance record at
`docs/plans/agent-host-isolation-acceptance.md` in this repository, created in
Phase 1. Workspace phases keep implementation evidence in workspace
`docs/host-isolation.md`; service phases record results in their nearest active
development docs. Cross-repo evidence is read-only to other phases. Record
pending checks honestly; missing evidence is not success.

## Phase 1: Prepare The Guest Bootstrap And Boundary Contract

### Workspace

.

### Goal

Prepare orchestration bootstrap and canonical documentation for the guest-local
repository model without changing the running stack.

### Scope

Architecture contract, setup/prerequisite/TLS wiring, related documentation,
and the acceptance record.

### Non-goals

No live cluster mutation, certificate generation, repository transfer, VM
creation, firewall edits, GitHub writes or sibling implementation.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`,
`docs/architecture/autonomous-ai-execution.md`, `setup.sh`, `scripts/README.md`,
the bootstrap TLS scripts, `docs/development/getting-started.md`, and
`docs/development/local-environment.md`, especially the frontend build section.
Read the manual plan and operator handoff; inspect workspace configuration
read-only for the current Docker and mount behavior.

### Execution steps

1. Update the canonical architecture contract first, then the ownership map and
   concise instruction links as needed. Define the separate guest agent-container
   configuration and its clean-start rule without calling it a VM or Mint
   profile. Remove shared-workspace assumptions and
   document the host-only GitHub credential boundary, VM-local bare remotes,
   Remote SSH editor model and remaining guest/code risks.
2. Define personal host, development VM and agent container consistently.
   Keep host GitHub publication separate from an explicit guest bootstrap path
   that selects only the guest-local Docker daemon. Reject remote
   Docker endpoints and keep `kind-kind`, loopback API and
   `kind-control-plane` checks before agent-authorized mutations. A marker or
   environment variable is an accidental-mislaunch check, not proof of isolation.
3. Add an explicit ingress certificate installation path: validate the public
   CA, hostname, validity, leaf/key match and required guest files; publish the
   public root and install the TLS Secret without invoking mkcert or altering
   host trust. Document the human-operated host-to-guest copy and installation
   of the public root into guest trust stores. Preserve the lazy container trust
   helper and human-owned infrastructure certificate generation in the guest.
   Document host-only certificate renewal without running `setup.sh` or
   recreating the host cluster.
4. Keep Kind, Calico, ingress, security policies, persistence and Tilt behavior
   intact. Preserve the atomic frontend production-smoke image target. Add useful
   image-pull diagnostics before CNI readiness if bootstrap fails.
5. Document the operator's exact Checkpoint A commands and prerequisites. State
   prominently that `setup.sh` recreates Kind and is not a daily VM-start
   command. Record the manual handoff and pending acceptance checks.

### Implementation notes

The personal host's signing key must not enter the guest. Missing or expired
development TLS material goes to the human certificate workflow, not an
insecure connection or agent-generated replacement. Git transport does not
carry ignored TLS or environment files; copy and configure them explicitly.
Do not add any host-runtime export or guest import path.

### Validation

Run `bash -n` and ShellCheck for every changed shell script; fix all warnings.
Use focused non-generating fixtures for certificate validation and endpoint
selection, plus relevant static guardrails. Check documentation links and
`git diff --check`. No live-bootstrap claim is made in this phase.

### Completion criteria

The guest bootstrap path is reviewable and statically verified; Checkpoint A
has exact operator commands. Owner docs accurately describe implemented versus
pending behavior and the host-only GitHub credential boundary.

## Phase 2: Prepare The Guest Runtime And Repository Setup Script

### Workspace

../workspace

### Goal

Provide a reproducible guest runtime, the one-time ecosystem repository setup
script, concise agent-container lifecycle helpers and launch instructions for
Checkpoint A while preserving the existing Mint-hosted devcontainer as the
Phase 1–6 implementation runner.

### Scope

The existing Mint Dev Container contract, a separate guest Compose runtime,
shared Dockerfile and guest-specific entrypoint wiring, guest prerequisite
helpers, guest-run agent-container lifecycle helpers, the host-run repository
setup script, reference configuration and workspace documentation.

### Non-goals

No launch on the personal host, conversion or retirement of the working Mint
devcontainer, repository transfer, host package installation, firewall changes,
hypervisor administration, GitHub operation, daily sync or publication command,
application service change, or a helper that implicitly starts the VM, Kind,
Tilt or host SSH forwarding.

### Required context

Read workspace `AGENTS.md`, `README.md`, `.devcontainer/`,
`ai-agent-sandbox/`, `scripts/sync-all.sh`,
`docs/local-budget-analyzer-tls.md`, and dependency policy before changing
pinned inputs. Read the orchestration contract, manual handoff and Phase 1's
bootstrap instructions.

### Execution steps

1. Preserve `.devcontainer/devcontainer.json`, its DinD feature lock and
   `ai-agent-sandbox/docker-compose.yml` as the working Mint-hosted
   implementation environment. Add the distinct guest runtime at
   `ai-agent-sandbox/docker-compose.agent-vm.yml`; do not add a second VS Code
   profile or describe it as a “VM profile.” Build the shared tool image on the
   guest daemon, mount only the guest Docker socket and use guest host
   networking. Do not use a DinD feature, privileged mode or unnecessary
   capabilities in the guest runtime. Document that guest Docker-socket access
   still permits complete guest administration.
2. Mount the guest-local common working-clone parent into the agent at an
   identical path as seen by the guest Docker daemon so bind mounts resolve.
   Also mount the guest bare-repository parent read/write at its identical
   guest path so local `origin` URLs work inside the container.
   Derive the path from reviewed guest configuration; do not hardcode an
   operator path. Allow agent startup before Kind exists, without a kubeconfig
   mount; after bootstrap, recreate the container with only the exact guest Kind
   kubeconfig mounted. Do not mount a personal-host workspace, home directory or
   credential path. Add guest-specific entrypoint behavior, launchers and hooks
   for the configured working-clone parent, including AI Session Handler
   installation. Preserve the existing Mint devcontainer's startup contract.
   Guest startup must not clone from GitHub or rewrite origins; it reports
   missing repositories instead.
3. Disable credential, SSH-agent and GitHub-auth forwarding for the guest.
   Provide a Remote SSH workflow in which the host UI connects to guest-local
   files while remote extensions, terminals, tasks and language servers execute
   in the guest. Make clear that the `Budget Analyzer VM` VS Code profile is
   editor configuration only, whereas the guest agent container is started
   from `docker-compose.agent-vm.yml`. Do not require Reopen in Container from
   the Remote SSH window or automatic port forwarding. These guest rules do not
   change how the existing Mint devcontainer hosts implementation agents.
4. Add `scripts/setup-agent-vm-repositories.sh` implementing the plan-wide
   repository transport contract. Keep it host-run, interactive and limited to
   one-time discovery, VM bare/working repository creation, host `vm` remote
   configuration and initial branch seeding. Do not add rsync, GitHub access,
   daily transfer wrappers, commit automation, force pushes or PR publication.
5. Add guest-run agent-container lifecycle helpers implementing the plan-wide
   helper contract. Provide stable start, stop, restart, status and interactive
   shell commands backed by one shared implementation so the Compose file list,
   environment-file selection and validation cannot drift between entry points.
   Normal daily commands must use the kubeconfig override and must work from
   any current directory. Keep a pre-Kind base-only mode explicit and visibly
   bootstrap-only. Do not couple these helpers to repository transfer, Kind,
   Tilt, VM lifecycle, host forwarding, provider login or image rebuilds.
6. Prepare repeatable guest provisioning for Docker and the prerequisites Tilt
   runs outside the agent container: Java, Node/npm, Git, OpenSSL and browser
   trust utilities as required by owner docs. Verify the setup script discovers
   every immediate sibling Git repository selected by the operator, including
   `ext-authz`, without encoding a static repository inventory.
   Document launching and authenticating the guest agent before application
   bootstrap, using only its provider credentials, with no GitHub login.
7. Record the actual VM/storage/network setup supplied by the operator as
   minimal, reproducible reference configuration. Keep trusted host launch and
   SSH settings outside guest-writable storage; updates require human review and
   installation. Do not automatically apply reference artifacts to the host.
8. Write `docs/host-isolation.md` with the canonical helper interface and
   install/start/stop/restart/status/shell instructions, the one-time setup
   contract, exact daily branch transfer in both directions,
   Docker/Testcontainers endpoint discovery, credential handling, clean-rebuild
   procedure and the handoff to Checkpoint A. Update README and affected
   instructions. Operator-facing daily instructions must call the helpers
   instead of duplicating the multi-file Compose invocation.

### Implementation notes

Guest host networking is deliberate: agent localhost reaches guest Kind,
ingress and test ports while there is one Docker networking owner. Keep source,
Git databases, Docker data, database volumes and build caches on guest disk.
The setup script transfers committed Git objects, not host `.git` configuration,
hooks, uncommitted files or credentials. Never launch the guest Compose
configuration against the personal-host daemon, and never select it implicitly
from the existing Mint Dev Container configuration. Do not implement host
Docker/Kind state export, import, volume copy or application-data migration.

When authoring from the existing Mint devcontainer, follow workspace
instructions for staging edits to its read-only sandbox directory under `tmp/`;
the human applies those reviewed files before committing the feature branch for
Checkpoint A.

### Validation

Render the existing Mint Dev Container/Compose configuration and prove it still
selects `ai-agent-sandbox/docker-compose.yml`, retains its required feature
metadata and remains usable as the implementation runner. Separately render
`docker-compose.agent-vm.yml`; check working/bare repository mounts,
namespaces, guest Docker-socket selection, absence of DinD, startup without
kubeconfig and endpoint fallback. Check guest startup preserves local origins
and resolves helper paths from the configured workspace root.
Exercise every lifecycle helper against disposable Compose fixtures from a
working directory outside the workspace. Prove normal start, restart, status
and shell operations select the base and kubeconfig files, while the explicit
bootstrap-only mode selects only the base file. Prove stop/restart preserve
named provider volumes, do not rebuild images, and do not change the Kind node
container or invoke Tilt. Cover missing/invalid environment, kubeconfig,
Docker endpoint and service failures without exposing environment contents.
Test the setup script against disposable host/guest Git fixtures covering
repository discovery, names with safe supported characters, initial `main`, a
different current branch selected in the guest, partial rerun, mismatched `vm`
remote, non-empty guest destination, no-force behavior and failure cleanup.
Prove fixture guest clones
have only guest-local origins and receive no host hooks or Git configuration.
Run `bash -n` and ShellCheck on every changed shell script, check documentation
links and run `git diff --check`. Do not contact GitHub or a real VM.

### Completion criteria

The existing Mint devcontainer remains a working implementation runner. The
operator can separately review and install the complete guest runtime and run
one script to establish every selected ecosystem repository. The operator can
manage the guest agent container through concise, validated lifecycle helpers
without reconstructing Compose arguments. Static and disposable-fixture checks
pass, no GitHub or daily publication capability is introduced, and no live
validation is claimed. Stop the invocation for manual Checkpoint A.

## Phase 3: Verify Repository Transport And Guest Runtime Isolation

### Workspace

../workspace

### Goal

Implement the lifecycle-helper requirement added after the original Phase 2
run, then prove the repository transport and guest runtime work after manual
Checkpoint A.

### Scope

Guest-run agent-container lifecycle helpers, guest repository topology, local
Git round trip, runtime checks, focused workspace verifiers and implementation
evidence.

### Non-goals

No personal-host firewall or VM changes, GitHub operation, real personal-data
probe, host Docker fallback, service code edit, rsync or publication automation.

### Required context

Read workspace instructions, `docs/host-isolation.md`, the completed manual
handoff and Checkpoint A evidence, and the orchestration boundary contract.

### Execution steps

1. Implement the plan-wide agent-container lifecycle-helper contract and its
   disposable fixtures in the workspace repository. The original Phase 2 run
   predates this requirement, so absence at Checkpoint A is expected for this
   invocation. Provide stable start, stop, restart, status and interactive-shell
   commands backed by one shared implementation, update the canonical workspace
   documentation, and run the Phase 2 helper validation. Do not modify the
   one-time repository-transfer contract or couple the helpers to Kind, Tilt,
   VM lifecycle, host forwarding, provider login or image rebuilds.
2. Verify every selected repository has one guest-local bare repository and one
   working clone whose `origin` resolves only to that bare repository. Confirm
   the agent sees the intended guest working-clone and bare-repository parents,
   exact guest kubeconfig and guest Docker socket, with no personal-host
   workspace, credential mount, GitHub remote or forwarded authentication socket.
3. Inspect Checkpoint A evidence for the human-run host-to-VM push and VM-to-host
   fetch. From inside the agent container, use a disposable guest fixture to
   verify working-clone commits push to the guest bare repository and preserve
   commit identity, additions, deletions and
   executable bits. Do not perform or claim a GitHub push.
4. Start disposable test containers; verify published-port reachability,
   bind-path resolution and cleanup. Use Checkpoint A's agent restart evidence
   and a separate disposable fixture for further lifecycle checks; do not
   terminate the executing worker. Confirm Kind and uncached pulls stay healthy.
5. Inspect Checkpoint A's Remote SSH evidence. The operator deferred the Java
   and frontend smoke edits to Checkpoint B, so do not manufacture or claim save
   evidence in this phase. Verify a representative build and read-only Tilt file
   detection occur entirely on guest-local storage, record measured behavior,
   and preserve the two named live-update checks as explicit Checkpoint B
   blockers without reviving shared-folder watcher tests.
6. Combine host-side native and Docker-published dummy-listener evidence with
   guest probes: prove new connections to host services and host containers are
   denied across UFW INPUT and IPv4/IPv6 `DOCKER-USER` paths while DNS,
   downloads and host-initiated SSH/Git connections work. Confirm the recorded
   `virbr1` input rules, Docker `docker0`/`br-+` output matches, Docker-start
   hook and UFW-reload hook are present and idempotent. Cover IPv4/IPv6 and
   inspect the operator's evidence; host-reboot verification remains Checkpoint
   B. Probe known dummy targets only.
7. Record actual results and unresolved issues in `docs/host-isolation.md`.

### Implementation notes

Firewall evidence must include a working positive control; refusal from an
absent listener does not demonstrate filtering. A VM marker alone does not
prove socket or credential isolation. Guest repositories can be recreated by
rerunning reviewed setup and pushing branches from the host, but unreturned
guest commits remain disposable. Guest runtime state is rebuilt cleanly rather
than restored from the host.

### Validation

Run the focused checks above, the lifecycle-helper disposable fixtures,
`bash -n` and ShellCheck for every changed shell script, and shell/Compose
validation for any fixes. Confirm host evidence supports the branch round trip
and network boundary. Keep credentials, personal paths and certificate metadata
out of recorded output.

### Completion criteria

The required lifecycle helpers are implemented and documented; repository
transfer, guest-local editing, Docker lifecycle, guest networking and
host-access denial are verified with reproducible evidence. Any failed
credential, remote, Docker or firewall boundary remains an acceptance blocker.

## Phase 4: Verify Currency Service Testcontainers

### Workspace

../currency-service

### Goal

Validate representative PostgreSQL, Redis and RabbitMQ integration tests.

### Scope

Existing service tests and a concise result in the service's active development
documentation.

### Non-goals

No service logic changes, dependency upgrades, skipped Docker tests, personal
credentials, GitHub operation or orchestration workaround.

### Required context

Read service instructions, development docs, Gradle and Testcontainers settings,
and workspace `docs/host-isolation.md`.

### Execution steps

1. Check Java and shared-library prerequisites and verify guest Docker selection.
2. Run the existing `./gradlew test` suite with real container startup; verify
   dynamic ports and lifecycle cleanup. Do not accept cached output as proof.
3. Record JUnit results and runtime identity without secrets. Report
   service-owned failures separately instead of editing logic under this plan.

### Implementation notes

Read sibling prerequisites for context only. If shared-library preparation is
missing, return to the documented bootstrap prerequisite rather than executing
work in a second repository from this phase.

### Validation

Inspect JUnit reports and actual container lifecycle; required tests must not be
skipped because Docker is unavailable.

### Completion criteria

The suite passes using the guest daemon, with evidence available to Phase 6.

## Phase 5: Verify Session Gateway Testcontainers

### Workspace

../session-gateway

### Goal

Verify the second representative integration-test consumer.

### Scope

Existing Redis-backed tests and a concise result in active service docs.

### Non-goals

No service logic changes, weakened tests, personal browser credentials,
GitHub operation or personal-host runtime fallback.

### Required context

Read service instructions, development docs, Gradle and Testcontainers settings,
and workspace `docs/host-isolation.md`.

### Execution steps

1. Verify local prerequisites and guest Docker selection.
2. Run `./gradlew test` with real Redis startup, dynamic connectivity and cleanup.
3. Record actual JUnit and runtime results without credential values.

### Implementation notes

This proves a second configuration, not every service in the ecosystem.

### Validation

Inspect test reports and container lifecycle; reject skipped or cached results
as the sole Docker integration evidence.

### Completion criteria

The suite passes using the guest daemon, with evidence available to Phase 6.

## Phase 6: Verify The Application And Document The Daily Workflow

### Workspace

.

### Goal

Verify the full guest stack and prepare host-browser, daily-workflow and final
guest-only Docker acceptance.

### Scope

Application/security smoke checks, owner documentation and acceptance-record
preparation. Read other phase evidence without modifying its owning
repositories.

### Non-goals

No automatic host changes, GitHub push or PR creation, host-runtime migration
or deletion, host firewall edit, certificate generation or production change.

### Required context

Read orchestration instructions, getting-started and local-environment docs,
`scripts/README.md`, the port and observability references, the manual handoff,
and workspace/service validation evidence.

### Execution steps

1. Confirm Checkpoint A and Phases 3–5 evidence. Check exact local cluster/API/node
   identity before mutations. Run the prerequisite checker and aggregate
   `./scripts/smoketest/smoketest.sh` after Tilt is healthy, plus focused security
   and internal-only observability checks required by changed behavior.
2. Inspect Checkpoint A's Remote SSH evidence and corresponding guest runtime.
   The operator deferred the Java and frontend smoke edits, so prepare their
   exact Checkpoint B procedure and retain them as acceptance blockers rather
   than modifying sibling service source to manufacture evidence. Verify fresh
   image pulls and application HTTPS after agent restart.
3. Update owner docs first, then README/AGENTS summaries as needed. Describe
   one-time repository setup, guest bootstrap versus daily startup, guest-local
   editing, the canonical agent-container lifecycle helpers, exact bidirectional
   branch transfer, host-only GitHub publication, HTTPS forwarding, resource
   use and clean rebuild. Daily operator instructions must use the helpers and
   must not repeat the raw multi-file Compose command.
4. Document the daily Git workflow without a wrapper: host updates `main`,
   creates a feature branch and pushes it to `vm`; the guest fetches/switches,
   the agent commits and pushes only to its local bare `origin`; the host fetches
   `vm`, fast-forwards the same branch, reviews, then independently pushes to
   GitHub and creates the PR. Do not automate host commit, GitHub push or PR
   creation, and do not add rsync.
5. Document human certificate renewal and clean rebuild: recreate guest bare and
   working repositories from reviewed setup, re-push host branches, and create
   guest runtime state from reviewed configuration. Do not restore or import
   host Docker, Kind, volume, database, cache or application state.
6. Inspect Phase 3's lifecycle-helper fixture evidence and prepare the exact
   Checkpoint B commands for live use after the human-owned Git workflow carries
   the implementation into the guest. Require the operator to run the helpers
   from a fresh guest SSH session and a working directory outside the workspace,
   verify start, restart, status and shell access preserve the exact guest
   kubeconfig mount and provider state while leaving Kind and Tilt healthy, and
   verify stop affects only the agent service before restoring it with start.
7. Record verified results and remaining human browser checks. Prepare the
   exact Checkpoint B sequence and the separate post-plan Checkpoint C cutover.
   Checkpoint C must preserve host Docker until all implementation workers have
   ended, then remove the host daemon, socket, CLI, approved runtime data and
   transitional Docker firewall integration without removing the permanent UFW
   VM boundary. Do not claim final acceptance until the human supplies both
   checkpoint results.

### Implementation notes

Daily use is VM start, helper-driven guest agent-container lifecycle, guest
Tilt start, Remote SSH editing, explicit Git branch transfer and host HTTPS
forwarding. The one-time repository setup script is not a daily launcher. The
lifecycle helpers do not start the VM, Kind, Tilt or host forwarding. GitHub
Actions and workflow files transfer like all committed files, but the host
remains the only GitHub writer and PR publisher.

### Validation

Run relevant smoke/guardrail checks, documentation links and `git diff --check`.
Report actual results and material limitations; do not treat stale retained
DinD test suites as acceptance gates.

### Completion criteria

The guest implementation and tests pass, the credential-isolated Git workflow
and helper-driven daily runtime are documented and fixture-validated, and the
human has concrete Checkpoint B live-helper and Checkpoint C instructions. The
implementation run ends before host Docker retirement.
Overall acceptance is complete only when the acceptance record includes the
operator's post-reboot Checkpoint C proof that Mint Docker and its transitional
workarounds are gone while guest Docker and the permanent host boundary remain
healthy.
