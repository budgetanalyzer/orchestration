# Native Agents In The Development VM

**Status:** Planned; no implementation or native runtime acceptance is implied.
**Companion:** [Human preparation and cutover](agent-vm-native-manual-plan.md).

Replace the agent container with native agent processes in the existing Ubuntu
development VM. The workspace repository will provide repeatable installation
of the full development/agent toolset previously supplied by its Dockerfile
and entrypoints. Docker remains guest-local for application image builds,
Kind, infrastructure and Testcontainers; it will not host agents or their
tooling. The personal-host security boundary remains the VM, host-enforced
network policy and exclusion of personal-host files and credentials.

This plan supersedes the original host-isolation implementation, manual setup
and container-continuation plans. It has no dependency on those files or their
runner state. Preserve prior evidence in the
[acceptance record](agent-host-isolation-acceptance.md) and workspace
`docs/host-isolation.md`; old container passes are historical evidence only.
The already provisioned VM, working/bare repositories, Docker, Kind and Tilt
are migration inputs, not things to recreate.

## Target And Ownership

- The personal host owns libvirt, its firewall, canonical GitHub clones and
  credentials, browser UI, the mkcert signing key and reviewed Git transfers.
- One normal guest development user runs native agents, AI Session Handler,
  Tilt, builds and Remote SSH terminals. Its ordinary home owns provider state,
  Maven Local, Gradle caches, Python environments and browser data. Docker-group
  access is guest-root-equivalent; a separate user or lack of `sudo` does not
  protect guest assets from an agent with unrestricted Docker access.
- Guest Docker uses the default Unix socket and `/var/lib/docker`. No DinD,
  agent Compose service, agent image, container home, socket mount or
  container-specific kubeconfig copy is part of the final daily workflow.
- Workspace owns native provisioning, tool selection, helpers and user setup.
  Orchestration owns the boundary, runtime target checks and application proof.
  Service repositories own their builds/tests and evidence.
- Keep native command sandboxing where supported. Do not disable AppArmor or
  grant blanket passwordless sudo merely to reproduce container convenience.
  Broad Docker authority remains explicit even when command sandboxing is on.

## Execution Locations And Human Gate

All runner invocations use the **same guest-local orchestration checkout**.
The existing guest agent container is a one-time authoring bridge for Phases
1–2. Human Checkpoint A first establishes that it is the actual guest container,
with same-path guest source mounts and no personal-host integration. Launch
only two phases using the companion's `--max-phases 2` command, then end the
handler and all workers. Do not install tools on the guest from that container.

At Checkpoint B the human reviews and runs the new installers from a guest OS
shell, authenticates the native provider, and stops the old guest agent. Phases
3–8 then resume the new plan's existing guest-local state from a native shell.
There is no state transfer, fabricated completion, unsupported phase-selection
flag, or resumption of an old plan. Phase 3 must stop without a complete native
handoff even if someone accidentally launches beyond Phase 2. If the bridge is
unavailable, report the prerequisite; do not substitute a Mint runner with
cross-machine access or invent a second bootstrap path.

The accepted plan bytes remain immutable during each invocation. Workers may
update owner docs, the acceptance record and the companion manual procedures,
but never this execution plan. Use the handler's normal status/retry workflow
for this new path. Every phase follows the
[canonical format](../../../ai-session-handler/docs/plan-format.md).

## Scope And Validation Rules

- Execute in exactly the declared repository; sibling sources/evidence are
  read-only. No sibling service logic changes or dependency upgrades to mask
  failures. Leave reviewable worktree changes; real Git writes and all source
  transfers remain human-owned. Disposable Git fixtures are permitted.
- No agent host administration, package installation into guest system paths,
  provider authentication, certificate generation, VM reboot, Docker restart,
  Kind recreation, `setup.sh`, Docker pruning or self-replacement. Those needed
  operations belong to the companion's human checkpoints. Named disposable
  guest test resources and normal repository builds are allowed after gating.
- Before every cluster mutation require current context and referenced cluster
  `kind-kind`, HTTPS loopback API and node `kind-control-plane`. Verify guest
  Docker identity; keep `DOCKER_HOST`, `DOCKER_CONTEXT` and
  `TESTCONTAINERS_HOST_OVERRIDE` unset. Native checks can additionally use
  `kind get clusters`. Names and marker files alone do not prove VM isolation.
- Never introduce GitHub credentials/remotes, host mounts, SSH/GPG forwarding,
  a host socket/kubeconfig, production access or TLS-verification bypasses.
  Local application credentials and provider authentication are guest-exposed
  by design; keep secrets and full environment dumps out of evidence.
- Use tracked fixtures for repeatable installer/environment tests. Scratch
  files belong in `tmp/`. All changed shell files require `bash -n` and
  ShellCheck without unexplained suppressions. Validate links, portable paths
  and `git diff --check`; use AGENTS checkstyle for instruction changes.
- Each phase records revision/dirty inputs, execution location/user, commands,
  exit statuses, reports and limitations in its owner doc. Host evidence must
  be attributed to the human. Required tests cannot be skipped or replaced by
  stale DinD suites, cached results or existing artifact presence.

## Phase 1: Build The Native Guest Tool Installer

### Workspace

../workspace

### Goal

Provide a reviewable, repeatable system installer and a complete tool migration
inventory without changing the running guest or container.

### Scope

Guest provisioner, checked-in tool inputs, installer fixtures, README and
`docs/host-isolation.md`. Execute in the existing guest container only.

### Non-goals

No live installation, guest administration, container rebuild, certificate
generation, source transfer, runtime cleanup or service changes.

### Required context

Read `AGENTS.md`, `README.md`, `docs/host-isolation.md`,
`docs/local-budget-analyzer-tls.md`, `scripts/provision-agent-vm-guest.sh`, the
Dockerfile, both entrypoints, shell aliases, settings overlay and all installed
helpers under `ai-agent-sandbox/`. Read orchestration's boundary and verified
tool contract in `scripts/README.md`, and workspace dependency-automation docs
before changing dependency extraction or evidence configuration.

### Execution steps

1. Verify Checkpoint A and guest-local source/runtime identity. Discover the
   complete Dockerfile/entrypoint tool surface, including actual helper
   dependencies and startup side effects. Record every item's native owner,
   installation method, version/update policy and validation command. Inspect
   checked-in source rather than treating an old image or ignored staged file
   as the authoritative inventory.
2. Cover system utilities, compiler/build tools, Git, curl/wget, jq, ripgrep,
   tree, editors, archive/PDF/image tools, DNS/network diagnostics, OpenSSL and
   NSS tools, ShellCheck/actionlint, Python/pipx/venv/PyYAML, Node/npm, JDK/Maven,
   Go, Docker client/Compose, kubectl/Kind/Tilt/Helm, bubblewrap, all three agent
   CLIs, AI Session Handler, Playwright/Chromium, VIA, mitmproxy and all launch,
   trust, inspection and skill/hook helpers. Distinguish installed capability
   from optional activation; do not silently drop proxy/image/browser tools.
3. Extend `scripts/provision-agent-vm-guest.sh --docker-user USER` as the single
   system-provisioning entry point. Separate its privileged OS work from the
   normal-user installer in Phase 2. Validate Ubuntu release, actual VM rather
   than a container, user/home, architecture and any existing Docker endpoint
   before mutation. A fresh VM may lack Docker, but must pass the OS/VM and
   no-remote-endpoint checks before first installation. Explicitly reject the
   Mint personal host and remote endpoints;
   a user-supplied marker alone is not adequate evidence. Existing Docker and
   healthy workloads must not be reinstalled, restarted or recreated merely
   because the provisioner runs again.
4. Use a checked-in manifest or equivalent source of truth for reviewed
   versions, signed repository inputs and release checksums. Reconcile the
   Dockerfile's Helm selection with orchestration's supported Helm contract;
   do not blindly copy conflicting versions. Preserve required major lines;
   require explicit refresh for moving agent releases and report resolved
   versions. Use architecture-correct verified downloads; do not reproduce the
   Dockerfile's architecture-specific unverified Go download or pipe downloads
   to a privileged shell. Keep orchestration tool ownership discoverable
   without invoking destructive `setup.sh` to install a binary.
5. Install Python packages through apt, pipx or isolated virtual environments,
   never system `pip --break-system-packages`. Do not copy container sudoers,
   recursively chown repositories, rewrite Git origins, auto-clone from GitHub,
   or generate/trust a proxy CA as an installation side effect. Preserve the
   existing user's shell/config and stop on ownership collisions.
6. Add tracked installer fixtures with mocked privileged/download commands.
   Prove rejection before mutation on wrong OS/container/endpoint/user, checksum
   failure handling, repeat runs, missing dependencies and path quoting. Record
   that real apt/browser installation remains Checkpoint B evidence.

### Implementation notes

Use new native-owned source paths for reusable helpers as needed. Preserve the
executing container and transitional Mint configuration until the human gates.
Do not confuse the availability of a tool in the authoring container with its
installation on the guest. Pinning and a tool manifest are for reproducibility;
do not turn this migration into unrelated dependency modernization.

### Validation

Run tracked fixtures, shell syntax/ShellCheck, manifest validation, applicable
dependency extraction tests and documentation/diff checks. Review the complete
parity inventory against Dockerfile COPY/RUN/ENV and both entrypoints.

### Completion criteria

The system installer is ready for human review, repeatable without implicit
runtime destruction, and every former capability has an explicit disposition.
No guest package, trust store, Docker service or executing agent was changed.

## Phase 2: Installable User Environment And Native Helpers

### Workspace

../workspace

### Goal

Finish a normal-user installer and read-only verifier so the human can launch
the full agent toolset directly in the guest after this phase.

### Scope

Native user provisioning, command wrappers, trust integration, skills/hooks,
fixtures and exact handoff instructions. Continue in the same guest container.

### Non-goals

No live user-home installation, authentication, guest sudo changes, provider
state extraction, proxy activation or native-runtime acceptance claims.

### Required context

Read Phase 1's workspace inventory/results, the aliases and helper sources,
`settings-overlay.json`, local TLS docs, the AI Session Handler README and plan
format, and the companion's Checkpoint B. Inspect actual script dependencies,
not merely their command names.

### Execution steps

1. Implement `scripts/install-agent-vm-user-tools.sh --worktree-parent PATH
   --bare-parent PATH`, invoked as the normal guest development user after
   system provisioning, and `scripts/check-agent-vm-tools.sh` with the same
   path inputs. Derive the user/home rather than assuming a container account.
   Reject wrong owners, absent local clones/bare origins and credential bridges
   without printing secrets or silently repairing Git configuration.
2. Install all agent CLIs and editable AI Session Handler from its guest-local
   checkout, plus the globally discoverable high-reasoning wrapper and `ai-run`.
   Use per-user managed environments. Verify handler import origin and command
   resolution. Preserve explicit model choices; no default launcher may gain
   new permission bypass flags as a migration side effect.
3. Port path-dependent helpers and Python modules to discover native installed
   resources and sibling repos. Preserve plain provider commands, optional lean
   and proxy launchers, conversation skill, hooks, VIA and flow-inspection
   tools. Replace container-home/workspace assumptions. Merge only managed
   config keys, avoid duplicate hooks, preserve user state and never overwrite
   credentials. Install a small documented environment fragment that works in
   fresh login shells, Remote SSH terminals and noninteractive handler workers;
   do not rely on aliases alone or source an entire interactive shell startup.
4. Define one guest development home for Maven Local, Gradle, provider state,
   NSS and browser cache. Verify writable paths without copying container
   caches or mounting them. Playwright must resolve the installed package and
   Chromium from a fresh shell; install its OS dependencies in Phase 1's
   privileged stage and its browser payload through the reviewed user flow.
5. Adapt the local CA helpers for native execution. Human installation imports
   only the approved ingress public root into system trust and the native
   user's NSS store; agents can diagnose and use established trust without
   blanket sudo. Cover curl, Python, Node and Playwright clients with verified
   HTTPS and preserve public roots. If a system trust change is needed later,
   fail with the exact human command; never silently require `sudo -n` granted
   to every command. Keep the existing application root-signing key host-only.
6. Install mitmproxy and proxy wrappers as optional tools. Keep normal agent
   sessions unproxied. Document human-only initialization of a separate
   guest-owned inspection CA if the operator wants interception, loopback-only
   binding, private flow storage, scoped trust and cleanup. Do not carry over
   upstream TLS bypasses, globally activate proxy variables, trust the proxy
   CA everywhere, or copy any signing key from the personal host/container.
   Fixture-test optional launchers without initiating certificate generation.
7. Verify native Codex sandbox prerequisites against current official docs,
   including Ubuntu's bubblewrap/AppArmor profile where required. Provide
   narrowly scoped human setup; do not disable AppArmor globally. Document
   the actual permissions used by provider wrappers and the handler rather
   than claiming a sandbox exists when a launcher bypasses it.
8. Test user setup against disposable homes and mocked commands: rerun without
   credential/config loss, paths with spaces, wrong-origin rejection, fresh
   shell PATH, settings/hook idempotence and missing trust/browser prerequisites.
   Update workspace instructions with the explicit native-install exception to
   the old container-only workflow. Complete exact Checkpoint B commands and
   the workspace handoff record; then end the handler at the two-phase limit.

### Implementation notes

Fresh authentication by the human is the default. Existing container volumes
remain untouched until native acceptance and human retirement. Optional proxy
activation is not required for ordinary native execution; its installation and
offline wrapper checks are required tool parity. Do not edit this plan to
record the handoff. Record results in workspace docs and update the companion.

### Validation

Run tracked installer/environment/helper fixtures, shell syntax/ShellCheck,
relevant Python checks and links/diff checks. Prove no fixture uses the actual
provider home or changes trust. Live installation and provider calls stay in B.

### Completion criteria

Both installers, the read-only verifier and portable helper environment are
ready; the full tool inventory is accounted for; the human has exact review,
installation, trust, authentication and native-launch instructions. The next
phase is blocked by the human handoff, not by invented runner state.

## Phase 3: Prove Native Workspace Execution

### Workspace

../workspace

### Goal

Prove native agents and tools work from the guest OS independently of the old
agent container, and finish workspace-owned migration defects.

### Scope

Native runtime checks, portable helper fixes, tracked fixtures, workspace docs
and repository source cleanup. Native execution only.

### Non-goals

No package/trust installation, provider login, self-upgrade, container removal,
application bootstrap, service logic or personal-host administration.

### Required context

Read workspace instructions, Phase 1–2 evidence, Checkpoint B's native handoff,
the boundary contract, native tool manifest/installers and TLS documentation.

### Execution steps

1. Require completed native handoff evidence and no old agent worker/container
   running. Verify current process/user/home and VM identity using guest OS
   facts and operator evidence, absence of a container runtime for this process,
   guest socket/daemon, repository paths and native command resolution.
   Check the handler state is this plan in the same guest checkout. Never
   treat successful container execution as a substitute.
2. Run the native read-only tool verifier in a fresh environment, check provider
   command availability without printing authentication material, and prove
   handler/wrapper import origin, sandbox behavior for the selected mode,
   browser launch and trust. Verify a deliberately disallowed write for a
   sandboxed mode; do not claim that mode's protection for unrestricted runs.
3. Repeat credential/remote boundary checks, including effective system/global/
   local Git settings, included helpers, push URLs, URL rewriting and askpass.
   In `tmp/`, run disposable bare/working Git fixtures proving commit identity,
   additions, deletions and executable-bit preservation. Real Git writes remain
   human-owned; do not create a guest SSH identity for host access.
4. Run named disposable guest Docker bind-path and published-port checks using
   a reviewed pinned image. Record uncached pull/download proof when available;
   never delete live images to manufacture it. Remove only fixture resources.
   Verify Kind/Tilt health before and afterward.
5. Fix actual native helper defects through tracked source and fixtures. If a
   fix needs reinstall, privilege or restarting the current worker, stop for
   the documented human refresh and resume normally. Do not replace running
   executables mid-run or use Docker to evade native installation boundaries.
6. Remove retired guest-agent Compose/entrypoint/lifecycle source only after B
   records the agent stopped and preserves the information needed for human
   resource cleanup. Retain shared assets still used by the transitional Mint
   devcontainer. Native tooling must have no dependency on that container or
   image. Update README, AGENTS, tool ownership, dependency-discovery surfaces
   when affected, and current operational docs; keep prior evidence historical.

### Implementation notes

Stopping an agent process must not stop Tilt, Kind or Docker. Native launch
needs no new daemon/lifecycle framework. Terminal sessions or a normal process
supervisor are sufficient; document process ownership and shutdown explicitly.

### Validation

Run the native tool verifier, workspace fixtures, Git/Docker proofs, verified
HTTPS/browser checks and changed-source validation. Preserve Mint configuration
until C; render it if shared assets changed. Attribute host checks to the human.

### Completion criteria

Native tooling passes, old guest agent execution is unnecessary, no required
capability was silently lost, and durable workspace evidence is ready for
orchestration. Guest Docker hosts workloads and tests only.

## Phase 4: Align Orchestration With The Native Guest

### Workspace

.

### Goal

Make native guest preflight, boundary documentation and daily operation the
coherent supported path without rebuilding the healthy application stack.

### Scope

Orchestration prerequisite checks, docs, instruction guardrails and focused
configuration/verifier fixes.

### Non-goals

No guest OS installation, bootstrap, certificate generation, service code,
production changes, VM/host administration or changes to this execution plan.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`, architecture boundary, getting-started and
local-environment guides, `scripts/README.md`, local Docker helpers, guest
preflight and imported-TLS scripts, workspace native results and acceptance.

### Execution steps

1. Validate B/Phase 3 identity and current guest state. Run guest-OS preflight
   from this native process, plus direct Docker/Kind/Tilt checks. Preserve exact
   local target selection; remove requirements that exist only to launch an
   agent container, without removing Compose when other supported tools need it.
2. Align prerequisite documentation and checks with the workspace tool manifest
   and native user/home. Remove duplicate-agent Maven setup, container mounting,
   base/override Compose startup and container trust assumptions from the active
   native workflow. Keep initial bootstrap/clean rebuild explicitly destructive
   and human-owned; daily commands must not rerun it.
3. Update canonical owner docs first, then README, AGENTS, ownership map and
   scripts index. Preserve host-only GitHub, mkcert and production exclusions,
   local development credentials, native sandbox qualifications, exact API
   targets and internal-only observability. Discover references across sibling
   docs read-only and report any remaining owner changes for their contexts.
4. Exercise changed preflight/target checks using fixtures for wrong Docker
   endpoints, wrong cluster/context, nonloopback API, missing node, container
   versus native execution and credential leakage. Do not relax identity checks
   to pass a fixture or claim a marker proves the personal-host boundary.
5. Record direct results and the remaining library/test prerequisites in the
   acceptance record. Inspect current Maven coordinates read-only; leave library
   publication and service tests to their owning phases.

### Implementation notes

The original container setup is historical/transitional, not an alternative
native completion path. Keep guest-owned data/persistence intact. Any genuine
service-owned failure must retain its owner and reproduction.

### Validation

Run guest preflight, affected tracked fixtures, shell checks, relevant static
security guardrails and documentation/diff checks. No cluster recreation or
package installation is needed to validate documentation and target selection.

### Completion criteria

Native runtime prerequisites and docs agree, healthy guest state is preserved,
and the service phases can use one inspected guest user/home and Docker daemon.

## Phase 5: Verify Shared Libraries In Native Maven Local

### Workspace

../service-common

### Goal

Verify shared-library build and local publication using the same native guest
home as Tilt and service test workers.

### Scope

Existing build/publication and evidence in active repository documentation.

### Non-goals

No library logic/dependency changes, remote publication, credentials, container
cache transfer or consumer execution.

### Required context

Read repository instructions, build/catalog files, testing docs, workspace
native evidence and orchestration's service-common artifact-resolution guide.
Read the two consumer catalogs only to compare required coordinates.

### Execution steps

1. Verify native identity, JDK, local Docker selection, writable build/cache
   paths and Maven Local resolution. Check Tilt and this worker actually use
   the same home/configuration; merely having the same username is insufficient.
   Require producer coordinates to match both consumers without version bumps.
2. Run `./gradlew clean build publishToMavenLocal --no-build-cache` as the
   normal guest user. Inspect fresh tests and selected BOM/POM/module/JAR
   artifacts. Do not run remote `publish` or introduce package credentials.
3. Record source inputs, user/runtime, local repository location expressed
   portably, command, test counts and artifact coordinates in owner docs.
   Explain that stopping a native agent does not discard Maven Local.

### Implementation notes

Normal local publication is allowed. A coordinate mismatch or build defect is
a prerequisite/owner failure, not permission to modify consumers or library
behavior under an environment migration.

### Validation

Require the build, tests and local publication to succeed. Inspect fresh
reports and artifact metadata; validate documentation links and diff hygiene.

### Completion criteria

Both consumers' required shared coordinates are available in native Maven
Local with successful build evidence, independent of old container caches.

## Phase 6: Verify Native Currency Service Testcontainers

### Workspace

../currency-service

### Goal

Prove PostgreSQL, Redis and RabbitMQ integration tests work from the native
agent environment against guest Docker.

### Scope

Existing tests and results in `docs/local-development.md`.

### Non-goals

No service logic/dependency changes, skipped required coverage, shared-library
publication, GitHub credentials or host/container fallback.

### Required context

Read repository instructions, local-development docs, Gradle/Testcontainers
configuration and the workspace/shared-library native evidence.

### Execution steps

1. Confirm native user/home, JDK, guest socket, unset endpoint overrides and
   local shared artifacts. Do not rerun another repository's prerequisite.
2. Run `./gradlew test --rerun-tasks --no-build-cache`, capturing scoped actual
   test-container starts, mapped-port connectivity and test-owned cleanup.
3. Identify required infrastructure cases from source and fresh JUnit reports.
   Record passing/failing/skipped counts, commands, source inputs and reports;
   distinguish unrelated justified skips from missing required Docker coverage.
   Verify Kind/Tilt remain healthy after testing.

### Implementation notes

Healthy application infrastructure or cached test output is not Testcontainers
proof. Diagnose service-owned failures and stop without orchestration workarounds.

### Validation

Require the fresh suite and required Docker cases to pass, plus documentation
links and `git diff --check`.

### Completion criteria

Native tests and actual lifecycle evidence pass and are available to Phase 8.

## Phase 7: Verify Native Session Gateway Testcontainers

### Workspace

../session-gateway

### Goal

Prove a second consumer's Redis tests work from the same native environment.

### Scope

Existing tests and results in `docs/local-development.md`.

### Non-goals

No service logic/dependency changes, weakened tests, personal sessions, shared
library publication or container/host fallback.

### Required context

Read repository instructions, local-development docs, Gradle/Testcontainers
settings and workspace/shared-library native evidence.

### Execution steps

1. Verify native identity, guest Docker and required local artifacts.
2. Run `./gradlew test --rerun-tasks --no-build-cache` with scoped lifecycle
   evidence. Prove Redis startup, dynamic connectivity and cleanup.
3. Inspect fresh reports, account for required coverage and skipped cases,
   record counts/commands/source/runtime/report paths, and check Kind/Tilt health.

### Implementation notes

This covers a second representative consumer, not every service. Record genuine
failures and ownership rather than broadening the migration scope.

### Validation

Require the fresh suite, actual Redis lifecycle, links and diff checks to pass.

### Completion criteria

The native suite passes with durable evidence for Phase 8.

## Phase 8: Verify The Application And Finish Cutover Evidence

### Workspace

.

### Goal

Finish native runtime acceptance and concrete human procedures for browser,
live updates, reboot persistence and retirement of agent-container resources.

### Scope

Application/security/observability checks, owner docs, acceptance record and
the companion's final human procedures.

### Non-goals

No host administration, package installation, certificates, service-source
edits, runtime deletion/restart, Git publication or changes to this plan.

### Required context

Read orchestration instructions, all native owner evidence, the boundary,
getting-started/local-environment docs, scripts catalog, observability/port
references and companion Checkpoints C/D.

### Execution steps

1. Require all prior results, current runtime identity and adequate attributed
   firewall evidence. Verify existing Tilt/pod health without reinitializing
   anything. Report genuine unsupported prerequisites rather than weakening
   preflight or installing packages from the worker.
2. Verify native HTTPS trust for exactly the local app origin; run
   `./scripts/smoketest/smoketest.sh` and focused security/observability checks
   relevant to changes. Use loopback-only forwards and remove only this run's
   fixtures. Fix only orchestration-owned configuration/verifier defects.
3. Read current Java/frontend sources and Tilt wiring to specify one harmless,
   reversible fixture for each live-update proof. Put exact file, edit, expected
   behavior/update, restoration and post-restoration checks in the companion.
   The human performs those edits; test/build success is not save evidence.
4. Finalize native daily commands and process lifecycle proof in owner docs and
   the companion: fresh SSH shell, ordinary agent/handler launch, agent exit
   without stopping the application, reentry with provider state/caches intact,
   then host/guest reboot acceptance after this handler ends. Specify user/home,
   PATH/trust resolution and the no-container checks.
5. Supply scoped cleanup inventories for old guest agent container/image/provider
   volumes and Mint Docker retirement; never delete live resources. Retain
   application images, PVC data, Docker daemon and test/build capability. Ensure
   operator-installed host firewall files are outside guest-writable source.
6. Reconcile active docs and links across the owned surface. Link to sibling
   evidence; do not edit sibling service docs here. Distinguish installed tool
   parity, optional proxy activation, representative tests, worker completion
   and pending human acceptance in the native section of the acceptance record.

### Implementation notes

C/D remain human gates even when all phases pass. Guest authority is broad;
the final protection claim covers the personal host under the stated boundary,
not guest data, all LAN/VPN peers or unrestricted Internet exfiltration.

### Validation

Require aggregate/relevant focused runtime checks, fresh evidence review,
changed-source validation and valid links. Confirm the manual procedures are
concrete and do not require the three superseded plans or an agent container.

### Completion criteria

All eight phases have durable passing evidence. Native agents work independently
of Docker-based tooling, application behavior is preserved, and C/D provide
reviewable human acceptance/retirement steps. Overall migration acceptance stays
pending until those human checkpoints pass and reviewed work returns to the host.
