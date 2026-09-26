# Guest-Local Development VM Implementation Plan

**Status:** Proposed implementation; no VM migration has been performed.

**Companion:** [Manual VM setup and operator checkpoints](agent-host-isolation-manual-plan.md).

Protect the personal workstation and its GitHub credentials by keeping agent
source, builds and runtime state on a development VM. Preserve a native host
editor window and browser, normal GitHub pull-request review, and ordinary Git
branches without sharing the host workspace or giving the guest GitHub write
credentials.

## Agreed design

```text
Personal workstation: Linux Mint 22.1
  GitHub credentials and canonical clones stay here
  VS Code UI -- Remote SSH --------------------------> guest-local working clones
  browser -> host loopback HTTPS forward ------------> guest ingress
  git push/fetch through host-initiated SSH ----------> guest bare repositories
  host-owned firewall denies new guest-to-host connections

Ubuntu Server 24.04 LTS VM: KVM/QEMU managed by libvirt and virt-manager
  guest-local bare repositories and working clones; no shared host workspace
  guest-local OS, Docker storage, build caches and persistent volumes
  one Docker daemon: Kind + Testcontainers + workspace agent container
  Tilt/build tools run in the guest; agent tools run in the guest container
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
  alter or destroy all guest repositories and development credentials. Retain
  the agent container for tool packaging, remove DinD, and allow **guest** host
  networking to preserve localhost access. No privileged container or nested
  daemon is needed.
- Permit normal Internet access. Deny new guest-initiated connections to all
  personal-host addresses with host-enforced IPv4/IPv6 rules; allow established
  replies and narrowly scoped DNS/DHCP if provided by the host. Internet
  destination allowlists and additional LAN/VPN isolation are outside this plan.
- Use the personal browser with a dedicated development profile and identities.
  Its profile and debugging interface are not shared. Forward host loopback
  HTTPS to the guest; keep Docker, Kubernetes and observability private to the
  guest.
- Development server keys and infrastructure CA material may remain in the
  guest. Keep the personal host's mkcert signing key outside it. Copy only the
  existing host-trusted development leaf certificate/key and public CA into the
  guest through a human-operated transfer; never require the personal browser to
  trust a guest-controlled signing CA or bypass TLS verification.
- VM snapshots and guest deletion recover guest-local state, but they do not
  protect committed secrets already present in transferred repository history.
  Host GitHub credentials remain outside the guest; host branch protections and
  review remain necessary before publishing agent-authored code or workflows.

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
   current checked-out branch when different. Do not mirror all refs, tags,
   hooks, host Git configuration or uncommitted files.
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

## Execution and handoff

This plan follows the [AI Session Handler format](../../../ai-session-handler/docs/plan-format.md).
Each phase runs only in its declared repository. Do not edit this plan during
an active invocation. Execution does not authorize GitHub writes, production
changes, automatic personal-host administration or service-logic changes.
Disposable local Git fixtures explicitly required by a phase are allowed; all
real host and guest branch-transfer commands remain human checkpoints.

1. The human completes **Steps 1–5** of the manual plan and supplies its handoff
   record. Resolve missing VM, storage, SSH and firewall prerequisites before
   implementation.
2. Run **Phases 1–2** to prepare reviewable orchestration and workspace changes.
   These are offline authoring phases and may run in the current environment;
   do not launch the guest profile or administer the host. End the invocation
   after Phase 2.
3. The human completes **Checkpoint A**: run the reviewed one-time repository
   setup script, transfer approved TLS material, install guest prerequisites,
   launch the runtime and bootstrap the guest application.
4. Run **Phases 3–6 inside the VM**, with each worker in its declared repository.
5. The human completes **Checkpoint B** for host-browser acceptance and cutover.

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
   concise instruction links as needed. Distinguish the current container from
   the proposed guest-local VM profile. Remove shared-workspace assumptions and
   document the host-only GitHub credential boundary, VM-local bare remotes,
   Remote SSH editor model and remaining guest/code risks.
2. Define personal host, development VM and agent container consistently.
   Preserve the existing host workflow while introducing an explicit guest
   bootstrap path that selects only the guest-local Docker daemon. Reject remote
   Docker endpoints and keep `kind-kind`, loopback API and
   `kind-control-plane` checks before agent-authorized mutations. A marker or
   environment variable is an accidental-mislaunch check, not proof of isolation.
3. Add an explicit ingress certificate import/reuse path: validate the public
   CA, hostname, validity, leaf/key match and required guest files; publish the
   public root and install the TLS Secret without invoking mkcert or altering
   host trust. Document the human-operated host-to-guest copy and installation
   of the public root into guest trust stores. Preserve the lazy container trust
   helper and human-owned infrastructure certificate generation in the guest.
4. Keep Kind, Calico, ingress, security policies, persistence and Tilt behavior
   intact. Preserve the atomic frontend production-smoke image target. Add useful
   image-pull diagnostics before CNI readiness if bootstrap fails.
5. Document the operator's exact Checkpoint A commands and prerequisites. State
   prominently that `setup.sh` recreates Kind and is not a daily VM-start
   command. Record the manual handoff and pending acceptance checks.

### Implementation notes

The personal host's signing key must not enter the guest. The development
leaf/key and public root may serve both old and guest environments during
transition. Missing or expired material goes to the human certificate workflow,
not an insecure connection or agent-generated replacement. Git transport does
not carry ignored TLS or environment files; copy and configure them explicitly.

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
script and launch instructions for Checkpoint A.

### Scope

Devcontainer/Compose/Dockerfile/entrypoint wiring, guest prerequisite helpers,
the host-run repository setup script, reference configuration and workspace
documentation.

### Non-goals

No launch on the personal host, repository transfer, host package installation,
firewall changes, hypervisor administration, GitHub operation, daily sync or
publication command, or application service change.

### Required context

Read workspace `AGENTS.md`, `README.md`, `.devcontainer/`,
`ai-agent-sandbox/`, `scripts/sync-all.sh`,
`docs/local-budget-analyzer-tls.md`, and dependency policy before changing
pinned inputs. Read the orchestration contract, manual handoff and Phase 1's
bootstrap instructions.

### Execution steps

1. Remove the DinD feature and obsolete lock entry from the VM profile. Retain
   the tool image; configure only the guest Docker socket and guest host
   networking. Remove unnecessary privileged mode/capabilities. Document that
   socket access still permits complete guest administration.
2. Mount the guest-local common working-clone parent into the agent at an
   identical path as seen by the guest Docker daemon so bind mounts resolve.
   Derive the path from reviewed guest configuration; do not hardcode an
   operator path. Mount only the exact guest Kind kubeconfig. Do not mount a
   personal-host workspace, home directory or credential path.
3. Disable credential, SSH-agent and GitHub-auth forwarding. Provide a Remote
   SSH workflow in which the host UI connects to guest-local files while remote
   extensions, terminals, tasks and language servers execute in the guest. Do
   not require host Reopen in Container or automatic port forwarding.
4. Add `scripts/setup-agent-vm-repositories.sh` implementing the plan-wide
   repository transport contract. Keep it host-run, interactive and limited to
   one-time discovery, VM bare/working repository creation, host `vm` remote
   configuration and initial branch seeding. Do not add rsync, GitHub access,
   daily transfer wrappers, commit automation, force pushes or PR publication.
5. Prepare repeatable guest provisioning for Docker and the prerequisites Tilt
   runs outside the agent container: Java, Node/npm, Git, OpenSSL and browser
   trust utilities as required by owner docs. Verify the setup script discovers
   every immediate sibling Git repository selected by the operator, including
   `ext-authz`, without encoding a static repository inventory.
6. Record the actual VM/storage/network setup supplied by the operator as
   minimal, reproducible reference configuration. Keep trusted host launch and
   SSH settings outside guest-writable storage; updates require human review and
   installation. Do not automatically apply reference artifacts to the host.
7. Write `docs/host-isolation.md` with install/start/stop instructions, the
   one-time setup contract, exact daily branch transfer in both directions,
   Docker/Testcontainers endpoint discovery, credential handling, recovery and
   the handoff to Checkpoint A. Update README and affected instructions.

### Implementation notes

Guest host networking is deliberate: agent localhost reaches guest Kind,
ingress and test ports while there is one Docker networking owner. Keep source,
Git databases, Docker data, database volumes and build caches on guest disk.
The setup script transfers committed Git objects, not host `.git` configuration,
hooks, uncommitted files or credentials. Never silently launch this profile
against the personal-host daemon.

### Validation

Render the effective Dev Container/Compose configuration, including feature
metadata; check mounts, namespaces, absence of DinD and endpoint fallback.
Test the setup script against disposable host/guest Git fixtures covering
repository discovery, names with safe supported characters, initial `main`, a
different current branch, partial rerun, mismatched `vm` remote, non-empty guest
destination, no-force behavior and failure cleanup. Prove fixture guest clones
have only guest-local origins and receive no host hooks or Git configuration.
Run `bash -n` and ShellCheck on every changed shell script, check documentation
links and run `git diff --check`. Do not contact GitHub or a real VM.

### Completion criteria

The operator can review and install a complete guest runtime and run one script
to establish every selected ecosystem repository. Static and disposable-fixture
checks pass, no GitHub or daily publication capability is introduced, and no
live validation is claimed. Stop the invocation for manual Checkpoint A.

## Phase 3: Verify Repository Transport And Guest Runtime Isolation

### Workspace

../workspace

### Goal

Prove the repository transport and guest runtime work after manual Checkpoint A.

### Scope

Guest repository topology, local Git round trip, runtime checks, focused
workspace verifiers and implementation evidence.

### Non-goals

No personal-host firewall or VM changes, GitHub operation, real personal-data
probe, host Docker fallback, service code edit, rsync or publication automation.

### Required context

Read workspace instructions, `docs/host-isolation.md`, the completed manual
handoff and Checkpoint A evidence, and the orchestration boundary contract.

### Execution steps

1. Verify every selected repository has one guest-local bare repository and one
   working clone whose `origin` resolves only to that bare repository. Confirm
   the agent sees the intended guest working-clone parent, exact guest
   kubeconfig and guest Docker socket, with no personal-host workspace,
   credential mount, GitHub remote or forwarded authentication socket.
2. Inspect Checkpoint A evidence for the human-run host-to-VM push and VM-to-host
   fetch. In a disposable guest fixture, verify working-clone commits push to the
   guest bare repository and preserve commit identity, additions, deletions and
   executable bits. Do not perform or claim a GitHub push.
3. Start disposable test containers; verify published-port reachability,
   bind-path resolution and cleanup. Use Checkpoint A's agent restart evidence
   and a disposable runtime copy for further lifecycle checks; do not terminate
   the executing worker. Confirm Kind and uncached pulls stay healthy.
4. Inspect Checkpoint A's Remote SSH save evidence and verify a representative
   build plus Tilt file detection occurs entirely on guest-local storage. Record
   measured build behavior without reviving shared-folder watcher tests.
5. Combine host-side dummy-listener evidence with guest probes: prove new
   connections to host addresses are denied while DNS, downloads and
   host-initiated SSH/Git connections work. Cover IPv4/IPv6 and inspect the
   operator's after-restart evidence. Probe known dummy targets only.
6. Record actual results and unresolved issues in `docs/host-isolation.md`.

### Implementation notes

Firewall evidence must include a working positive control; refusal from an
absent listener does not demonstrate filtering. A VM marker alone does not
prove socket or credential isolation. Guest repository loss is recoverable by
rerunning reviewed setup and pushing branches from the host, but unreturned
guest commits remain disposable.

### Validation

Run the focused checks above and shell/Compose validation for any fixes.
Confirm host evidence supports the branch round trip and network boundary.
Keep credentials, personal paths and certificate metadata out of recorded
output.

### Completion criteria

Repository transfer, guest-local editing, Docker lifecycle, guest networking
and host-access denial are verified with reproducible evidence. Any failed
credential, remote, Docker or firewall boundary remains a cutover blocker.

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

## Phase 6: Verify The Application And Publish The Daily Workflow

### Workspace

.

### Goal

Verify the full guest stack and prepare host-browser acceptance and cutover.

### Scope

Application/security smoke checks, owner documentation and final acceptance
record. Read other phase evidence without modifying its owning repositories.

### Non-goals

No automatic host cutover, GitHub push or PR creation, deletion of the old
environment, host firewall edit, certificate generation or production change.

### Required context

Read orchestration instructions, getting-started and local-environment docs,
`scripts/README.md`, the port and observability references, the manual handoff,
and workspace/service validation evidence.

### Execution steps

1. Confirm Checkpoint A and Phases 3–5 evidence. Check exact local cluster/API/node
   identity before mutations. Run the prerequisite checker and aggregate
   `./scripts/smoketest/smoketest.sh` after Tilt is healthy, plus focused security
   and internal-only observability checks required by changed behavior.
2. Inspect Checkpoint A's Remote SSH edit evidence and corresponding guest
   rollouts for Java live update and frontend development and production-smoke
   paths. Verify fresh image pulls and application HTTPS after agent restart.
   Do not modify sibling service source to manufacture evidence.
3. Update owner docs first, then README/AGENTS summaries as needed. Describe
   one-time repository setup, guest bootstrap versus daily startup, guest-local
   editing, exact bidirectional branch transfer, host-only GitHub publication,
   HTTPS forwarding, resource use and recovery.
4. Document the daily Git workflow without a wrapper: host updates `main`,
   creates a feature branch and pushes it to `vm`; the guest fetches/switches,
   the agent commits and pushes only to its local bare `origin`; the host fetches
   `vm`, fast-forwards the same branch, reviews, then independently pushes to
   GitHub and creates the PR. Do not automate host commit, GitHub push or PR
   creation, and do not add rsync.
5. Document human certificate renewal and safe recovery: recreate guest bare and
   working repositories from reviewed setup, re-push host branches, restore
   guest runtime from reviewed configuration and avoid rerunning destructive
   cluster setup for ordinary Git or networking issues.
6. Record verified results and remaining human browser/cutover checks. Prepare
   the exact Checkpoint B sequence; do not claim host acceptance until the human
   supplies results. Runtime migration remains pending until that checkpoint.

### Implementation notes

Daily use is VM start, guest Tilt/agent start, Remote SSH editing, explicit Git
branch transfer and host HTTPS forwarding. The one-time setup script is not a
daily launcher. GitHub Actions and workflow files transfer like all committed
files, but the host remains the only GitHub writer and PR publisher.

### Validation

Run relevant smoke/guardrail checks, documentation links and `git diff --check`.
Report actual results and material limitations; do not treat stale retained
DinD test suites as acceptance gates.

### Completion criteria

The guest implementation and tests pass, the credential-isolated Git workflow
and daily runtime are documented, and the human has concrete Checkpoint B
instructions. Overall cutover is complete only when the acceptance record
includes the operator's final confirmation.
