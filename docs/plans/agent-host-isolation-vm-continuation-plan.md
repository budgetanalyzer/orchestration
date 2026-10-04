# Guest Agent Host-Isolation Continuation

**Status:** Ready for review; execution requires the manual continuation
handoff. No result is implied by this plan's creation.

Finish the guest-local runtime verification and implementation left after the
original plan's Phases 1–2 and partial Phase 3. Run every phase below inside the
already bootstrapped VM's **guest agent container**. Source, Docker, Kind,
builds, test reports and worker state stay on guest storage. Mint Docker stays
available through Checkpoint B and is retired only by the human in Checkpoint C.

This is a new AI Session Handler plan with independent phase numbering and
fresh generated state. Do not resume, edit or migrate the original plan's
state. The [original plan](agent-host-isolation-plan.md) and its Phase 3 record
in workspace `docs/host-isolation.md` are prior-work evidence, not the runner
contract for this invocation. Keep the original plan bytes unchanged. This
plan follows the [canonical format](../../../ai-session-handler/docs/plan-format.md).

## Entry Gate And Evidence Ownership

The human completes the
[manual continuation handoff](agent-host-isolation-manual-plan.md#continuation-handoff-start-the-vm-execution-plan)
before launching this plan. It requires reviewed source transfer, current
guest-OS preflight, host firewall evidence with positive controls, the exact
post-Kind agent configuration, working provider/handler commands, and a healthy
guest stack. Read the resulting **VM Continuation Handoff** in
[the acceptance record](agent-host-isolation-acceptance.md). Missing handoff
evidence is a prerequisite failure, not an invitation to administer Mint.

| Evidence | Owner and execution location |
| --- | --- |
| Mint firewall rules/hooks, native/Docker listeners, paired guest denials, host-initiated SSH/Git | Human, collected before launch; workers inspect the recorded commands/results |
| Guest-OS bootstrap prerequisites and healthy Tilt | Human guest shell before launch; workers inspect the record and query Tilt/Kind directly |
| Agent mounts, origins, credentials, Docker fixtures and helper fixtures | Phase 1, guest agent, workspace repository |
| Agent-local shared Maven artifacts | Phase 2, guest agent, service-common repository |
| Actual service Testcontainers suites | Phases 3–4, guest agent, respective service repositories |
| Application/security/observability checks and consolidated acceptance | Phase 5, guest agent, orchestration repository |
| Browser, Remote SSH saves, live helper restart/stop and reboot persistence | Human Checkpoint B after the handler ends |
| Mint Docker retirement and final boundary proof | Human Checkpoint C |

Completed Checkpoint A repository/TLS/restart evidence remains valid unless
the relevant inputs changed. Java/frontend save checks remain explicitly
deferred to Checkpoint B. This run needs neither a worker SSH key nor active
host dummy listeners. Do not repeat host probes against listeners that have
been removed. Accept sufficiently detailed operator evidence for host-owned
checks; repeat guest-owned fixtures and tests directly. If the network or host
policy changes after the handoff, stop for renewed evidence instead of treating
old results as current. An unreachable IPv6 route is not a filtering pass.

## Execution Contract

- Each phase executes only in its declared repository. Sibling sources and
  evidence are read-only. Record results in the owning repository so later
  phases can read the same guest files without a Git transfer.
- Read the declared repository's instructions and
  [the boundary contract](../architecture/autonomous-ai-execution.md). Preserve
  guest-local origins, no GitHub authority, no personal-host mounts or sockets,
  and the production exclusion. Do not request package credentials.
- This plan permits disposable Git fixture operations required by Phase 1,
  local builds/Maven publication and scoped guest test/runtime operations.
  Real repository commits, pushes, fetches, branch changes and all host/guest
  branch transfers remain human-owned. Leave implementation and evidence as
  reviewable worktree changes; no commit is required between phases.
- Before Kubernetes mutations, require current context and referenced cluster
  `kind-kind`, an HTTPS loopback API, and `kind-control-plane`. Verify Docker
  remains the inspected guest daemon at the default Unix socket; leave
  `DOCKER_HOST`, `DOCKER_CONTEXT` and `TESTCONTAINERS_HOST_OVERRIDE` unset.
- Never run `setup.sh`, generate certificates, recreate Kind, restart Tilt,
  rebuild/recreate/stop the executing agent, or prune Docker state. Use named
  disposable resources and remove only the fixtures created by this run.
  Live lifecycle acceptance stays in Checkpoint B. If a necessary fix requires
  replacing the running agent image, record the exact operator prerequisite
  and stop; do not attempt self-replacement.
- Guest-OS checks that require systemd, the guest hostname or the guest user's
  home run in the manual handoff. Do not invoke
  `check-agent-vm-prerequisites.sh` or the guest-OS
  `check-tilt-prerequisites.sh --guest-local` from inside this container or relax
  their checks. In-agent proof uses the inspected mounts/socket and cluster
  checks. Guest-OS Tilt and agent Gradle have separate Maven Local repositories.
- Allowed fixes are repository-owned runtime, environment, verifier and
  documentation fixes within the phase's scope. No service logic changes,
  dependency upgrades, relaxed security controls, skipped required tests, host
  fallback or orchestrator compensation for a service defect. Diagnose genuine
  failures and report the owner and reproduction rather than widening scope.
- Keep evidence concise and reproducible: source revision and relevant dirty
  inputs, execution location, commands, exit status, test counts/reports,
  runtime identity and limitations. Keep credentials, private URLs, certificate
  metadata and full environment/inspection dumps out of recorded output.
- Do not edit this plan during an invocation. Shell changes require `bash -n`
  and ShellCheck with all warnings resolved; also validate affected links and
  `git diff --check`. Do not use stale retained DinD suites as acceptance gates.

## Phase 1: Verify The Guest Agent And Complete Workspace Fixtures

### Workspace

../workspace

### Goal

Prove the executing agent has the intended guest-local environment, and finish
the lifecycle and repository fixtures left by the original Phase 3.

### Scope

Workspace helpers, reusable fixture tests, repository/runtime isolation and
workspace evidence. Inspect prior implementation before changing it.

### Non-goals

No host administration, host SSH key, live agent restart, service build,
repository synchronization, certificate generation or personal-data probe.

### Required context

Read `AGENTS.md`, `README.md`, `docs/host-isolation.md`,
`docs/local-budget-analyzer-tls.md`, guest Compose/entrypoint configuration,
`scripts/agent-vm-container-*.sh`, the orchestration boundary contract and the
manual VM Continuation Handoff. Inspect available prior lifecycle fixtures;
absence of an ignored `tmp/` file is not a missing runtime prerequisite.

### Execution steps

1. Review the handoff's guest-OS and paired firewall evidence. Require tested
   native and Docker paths, working positive controls, IPv4/IPv6 applicability,
   rule/hook identity and remaining reboot checks. Record it as operator
   evidence, not a worker-executed test. Do not start another host fixture cycle.
2. Identify the running agent from the reviewed Compose labels and guest
   Docker inspection. Confirm guest networking, no privileged mode or nested
   daemon, exact same-path working/bare mounts, guest socket and read-only
   guest kubeconfig mount. Compare with the handoff's daemon/container identity;
   a matching hostname or marker alone is insufficient. Check current/selected
   cluster, loopback API and Ready node; query Tilt without starting it.
3. Verify all selected guest working clones resolve `origin` to their matching
   guest bare repositories, and have no additional remote, host credential
   helper, forwarded authentication socket or GitHub authority. Inspect only
   relevant configuration, reporting presence/absence without secret values.
4. Inspect the existing lifecycle implementation and finish only actual gaps.
   Put its repeatable test in a tracked location such as
   `tests/agent-vm/test-container-lifecycle.sh`, with fixture scratch data in
   `tmp/`. Adapt an available staged fixture or reconstruct it from the helper
   contract; do not require copying ignored host files. Update documentation
   and instruction references to the tracked test entry point.
5. Exercise helpers from outside the workspace against disposable Compose
   fixtures. Prove daily base+kubeconfig selection, explicit bootstrap-only
   selection, provider-state preservation, no image build or Kind/Tilt change,
   and clear failures for missing/invalid env, kubeconfig, endpoint and service.
   Use fixture-local state and mocks for operations that would stop the agent.
   Guest-OS helper paths are not assumed to exist inside the agent; never run
   the real lifecycle helpers here as a substitute for fixture validation.
6. In workspace `tmp/`, create disposable bare/working Git fixtures. Verify
   local push/fetch preserves commit identity, additions, deletions and
   executable bits. Configure author/committer identity only in the fixtures;
   do not touch the real guest origins or global Git configuration.
7. Use a reviewed digest-pinned test image and uniquely named disposable
   guest containers to verify published-port reachability from the agent and
   bind-path resolution for a file under the mounted workspace. Prove a fresh
   image download using an uncached reviewed image/layer; do not remove images
   used by Kind or workloads to manufacture a cold pull. Record whether layers
   were downloaded or cached. Remove only test-owned containers/networks.
8. Confirm Kind, Tilt and Internet access remain healthy after cleanup. Record
   direct results, operator evidence and deferred human checks separately in
   `docs/host-isolation.md`. Include the container identity and Maven-home
   distinction that Phases 2–4 will rely on.

### Implementation notes

Preserve the existing Mint configuration. Guest source is already local and
writable; no host transfer is needed for helper/script edits. If a sandbox
source needs changing, inspect mounts first and preserve the running image.
Fixture validation does not replace Checkpoint B's live helper acceptance.

### Validation

Run the tracked lifecycle test, direct disposable Git/Docker checks, shell
syntax/ShellCheck for changed scripts, relevant Compose rendering, links and
`git diff --check`. Inspect runtime state before and after fixtures. Do not
render full environment contents into the acceptance record.

### Completion criteria

The guest agent and repository boundary pass direct checks; lifecycle tests
are repeatable from tracked source; host firewall evidence is adequate and
explicitly attributed. Workspace evidence is available to subsequent workers.
No executing-agent or host state was restarted or synchronized.

## Phase 2: Prepare Shared Libraries In The Agent Maven Repository

### Workspace

../service-common

### Goal

Make the shared Java artifacts available to service tests inside this exact
guest agent, without GitHub Packages credentials or another repository's build.

### Scope

Existing shared-library build/local publication and evidence in this
repository's README or nearest active development documentation.

### Non-goals

No library logic change, version/dependency upgrade, remote publication,
consumer edit, guest-OS home mount or shared host cache.

### Required context

Read `AGENTS.md`, `README.md`, Gradle settings/build/catalog files,
`docs/testing-patterns.md`, workspace `docs/host-isolation.md`, and orchestration
`docs/development/service-common-artifact-resolution.md`. Read the two consumer
catalogs only to compare their selected shared-library coordinates.

### Execution steps

1. Confirm Phase 1's same running agent and local Docker selection. Check JDK
   25, Gradle, writable agent build/Maven directories, and no GitHub credential
   dependency. Verify the checked-in producer version matches both consumers;
   a mismatch requires reviewed source alignment, not an opportunistic bump.
2. Run `./gradlew clean build publishToMavenLocal --no-build-cache` inside this
   repository as the normal agent user. This intentionally populates the
   agent's Maven Local; guest-OS Tilt's prior publication is not a substitute.
   Use only the local publication task, never a remote `publish` task.
3. Inspect the resulting BOM/POM/module and JAR artifacts for the coordinates
   consumed by both services, and the shared-library build/test results. Record
   the source revision, actual local repository location in portable form,
   agent identity, command and result. Do not run a consumer build here.
4. Document that container recreation can remove these artifacts; after
   recreation this prerequisite must run again in the service-common context.
   Preserve caches and the current container for the rest of this invocation.

### Implementation notes

This phase owns the prerequisite that the original service phases could only
report as missing. Local Maven publication is authorized build output, not
GitHub publication. Diagnose a build defect but do not change library behavior
under this migration plan.

### Validation

Require the build and local publication to succeed with the required artifacts
present. Inspect test reports rather than equating an existing JAR with a pass.
Check documentation links and `git diff --check`.

### Completion criteria

Both consumers' selected shared coordinates exist in this agent's Maven Local,
the existing library build passes, and durable evidence is available for the
service phases and orchestration acceptance.

## Phase 3: Verify Currency Service Testcontainers

### Workspace

../currency-service

### Goal

Prove the representative PostgreSQL, Redis and RabbitMQ integration tests run
successfully against the guest daemon from the agent container.

### Scope

Existing tests and results in `docs/local-development.md`.

### Non-goals

No service logic changes, dependency upgrades, weakening/skipping tests,
publishing service-common, GitHub credentials or host runtime fallback.

### Required context

Read `AGENTS.md`, `docs/local-development.md`, Gradle/Testcontainers
configuration, workspace runtime evidence and service-common's Phase 2 record.

### Execution steps

1. Verify the same agent/container, JDK, guest socket and agent-local shared
   artifacts. Do not rerun another repository's prerequisite from this phase.
2. Capture scoped Docker lifecycle evidence while running
   `./gradlew test --rerun-tasks --no-build-cache`. Identify the tests that cover
   PostgreSQL, Redis and RabbitMQ from source and JUnit reports. Require actual
   starts, dynamically mapped port connectivity and test-owned cleanup.
3. Inspect current JUnit reports and task outcomes; count passing/failing/skipped
   tests and distinguish justified unrelated skips from missing required Docker
   coverage. Record commands, source inputs, runtime identity and report paths
   in `docs/local-development.md`. Confirm Kind/Tilt remain healthy.

### Implementation notes

Do not infer Testcontainers success from a cached Gradle result or healthy
application infrastructure. Report service-owned failures with reproduction
and ownership; do not introduce orchestration compensations.

### Validation

Require the existing suite to pass, required container-backed cases to execute,
and fresh container lifecycle evidence. Check links and `git diff --check`.

### Completion criteria

The suite passes in the guest agent with real container startup and cleanup,
and Phase 5 can read the durable results without a host transfer.

## Phase 4: Verify Session Gateway Testcontainers

### Workspace

../session-gateway

### Goal

Prove the second representative consumer's Redis-backed tests work from the
same guest agent and Docker daemon.

### Scope

Existing tests and results in `docs/local-development.md`.

### Non-goals

No service logic/dependency changes, weakened tests, personal browser/session
credentials, shared-library publication or host runtime fallback.

### Required context

Read `AGENTS.md`, `docs/local-development.md`, Gradle/Testcontainers settings,
workspace runtime evidence and service-common's Phase 2 record.

### Execution steps

1. Verify the same runtime, JDK, guest socket and local shared-library artifacts.
2. Run `./gradlew test --rerun-tasks --no-build-cache` while capturing scoped
   test-container lifecycle evidence. Prove real Redis startup, dynamic
   connectivity and test-owned cleanup.
3. Inspect fresh JUnit/task results, account for skipped cases, confirm the
   required Redis tests executed, and record command, source/runtime identity,
   counts and report paths in `docs/local-development.md`. Check Kind/Tilt health.

### Implementation notes

This verifies a second configuration, not every service. Missing prerequisites
or service defects remain explicit failures; do not obtain credentials or
execute another repository's build from here.

### Validation

Require passing fresh tests and actual Redis lifecycle evidence, plus links
and `git diff --check` for documentation changes.

### Completion criteria

The suite passes against guest Docker with reproducible evidence available to
the final orchestration phase.

## Phase 5: Verify The Guest Application And Finish Operator Acceptance Instructions

### Workspace

.

### Goal

Verify the full guest stack and leave concrete Checkpoint B/C instructions and
an honest consolidated acceptance record.

### Scope

Orchestration-owned verifiers/configuration, application/security checks,
canonical documentation and acceptance evidence.

### Non-goals

No personal-host administration, certificate generation, cluster recreation,
agent restart, service-source edits, Git operations or production changes.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`, the architecture boundary,
getting-started/local-environment docs, `scripts/README.md`, port/observability
references, manual handoff, acceptance record and Phases 1–4 owner evidence.

### Execution steps

1. Confirm the handoff and prior phase results, including current source/runtime
   identity. Use the operator's guest-OS prerequisite record plus direct agent
   socket/mount/cluster checks; do not run systemd/guest-host-only preflight in
   this container. Query Tilt and pods and wait for the existing stack to be
   healthy without reinitializing it.
2. Install the host-published public root into container trust using
   `ensure-budget-analyzer-local-ca-trust` for exactly
   `https://app.budgetanalyzer.localhost`. Run verified HTTPS checks and
   `./scripts/smoketest/smoketest.sh`, plus focused security and internal-only
   observability checks required by any fixes. Use loopback-only operator
   access; clean up only forwards/fixtures this run started.
3. Resolve orchestration-owned environment/verifier/configuration defects with
   repo-owned repeatable fixes and relevant validation. Do not mask service
   failures or weaken host-only target checks to make container execution pass.
   Identify scripts' execution location before invoking them; record a genuine
   unsupported environment as a defect with its owner.
4. Confirm guest-local builds and Tilt file detection using prior service build
   evidence and read-only Tilt inspection. Reuse Checkpoint A's agent restart
   evidence with its original configuration identity; record whether subsequent
   changes require fresh human acceptance. Do not restart this worker or claim
   Java/frontend Remote SSH save proof from build/test success.
5. Complete exact Checkpoint B procedures in the manual plan: name a harmless,
   reversible Java fixture and a frontend fixture selected by reading their
   current Tilt/build wiring; specify the save, expected update/rebuild, visible
   behavior check and restoration. The human performs those edits. Add live
   helper start/restart/status/shell/stop checks from a fresh guest-OS session
   outside the workspace, proving provider state and exact kubeconfig survive
   while Kind/Tilt remain healthy. These run only after this handler ends.
6. Update owner docs before summaries. Explain guest-OS versus agent commands,
   separate Maven Local prerequisites, bootstrap versus daily startup, canonical
   lifecycle helpers, explicit bidirectional Git transfer, host-only GitHub
   publication, trusted HTTPS forwarding, clean rebuild and certificate renewal.
   Link to workspace/service evidence instead of editing sibling docs here.
7. Update `docs/plans/agent-host-isolation-acceptance.md` with actual worker
   results and the operator evidence used. Distinguish implementation completion
   from pending B/C acceptance. Keep Mint Docker retirement exclusively in C;
   require reviewed work to return to host repositories before retirement.

### Implementation notes

The existing host/browser and post-reboot checks remain necessary. Moving
execution into the VM does not complete them. Do not erase historical failures
or relabel old operator results as tests performed by this worker.

### Validation

Require aggregate and relevant focused checks to pass on the guest stack.
Validate changed shell/configuration surfaces, documentation links and
`git diff --check`. Verify B/C commands and success criteria are concrete and
use the current helper interface. Report results and material limitations.

### Completion criteria

All five continuation phases pass their guest verification; evidence and
remaining manual actions are reviewable in the guest worktrees. Checkpoint B
has exact live-update, lifecycle, browser and reboot steps; Checkpoint C still
owns host Docker retirement. End the handler before either checkpoint. Overall
migration acceptance remains pending until the human records B and C success.
