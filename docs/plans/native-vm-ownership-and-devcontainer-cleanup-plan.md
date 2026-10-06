# Native VM Ownership And Devcontainer Cleanup Plan

Tighten the native-agent migration by making the sibling `workspace` repository the single owner
of development-VM identity, native user/tooling, guest Docker, repository transport, personal-host
isolation audit tooling, and host-boundary guidance. Keep orchestration responsible for Budget
Analyzer application bootstrap, the exact local Kind target, Tilt, ingress TLS validation, and
Kubernetes Secret reconciliation. Remove duplicate checks and stale devcontainer instructions
instead of preserving compatibility layers for the retired agent-container workflow.

The work must preserve the current native VM happy path, fail closed before destructive Kind
bootstrap, and retain the human-only host-policy and TLS boundaries. No phase may access or change
the personal host, run a live host collector, apply host firewall policy, generate certificates,
administer staging or production, or perform Git write operations. Existing unrelated changes in
either worktree belong to the user and must be preserved.

`candidate-report.md`, raw audit captures, generated redacted reports, machine-specific host
configuration, and host-policy source are private operator evidence, not repository content. The
user has removed the tracked candidate report. Before publishing this branch, the human Git owner
must ensure that report content is excluded from the published branch history or final squashed
change; agents must not rewrite history. Add prevention for future accidental reports, but never
copy the deleted report into `workspace`.

The target ownership split is:

| Workspace owns | Orchestration owns |
| --- | --- |
| Native QEMU/KVM identity, Ubuntu/user/home checks, native tool manifest, credential/forwarding boundary, guest-local repositories and Docker | Application bootstrap and daily startup entry points, local `kind-kind` authority checks, Tilt, Kubernetes mutation guards |
| Personal-host isolation audit documentation, reusable collector/protocol fixtures, offline tests, and a configurable go/no-go verifier | Imported ingress file validation, host-owned ingress renewal, guest Kubernetes TLS Secret reconciliation, infrastructure TLS and application runtime checks |
| Exact OS/NSS trust installation and read-only trust verification | A concise pointer to workspace trust ownership plus orchestration-owned certificate and Secret behavior |

## Phase 1: Establish The Workspace-Owned Native Runtime Contract

### Workspace

../workspace

### Goal

Make the existing workspace verifier and documentation the explicit canonical interface consumed
by orchestration for development-VM, normal-user, repository, credential, native-tool, trust, and
guest-Docker readiness.

### Scope

Update workspace ownership guidance, `AGENTS.md`, `README.md`, `docs/host-isolation.md`,
`docs/native-user-tools.md`, `docs/local-budget-analyzer-tls.md`, the native verifier interface,
and its focused tests where needed. Define one stable read-only invocation for application
bootstrap and daily runtime checks. Preserve the existing tool manifest as the sole version and
capability inventory.

### Non-goals

Do not edit orchestration in this phase. Do not add Kubernetes application checks to workspace,
install tools, modify live trust, authenticate providers, recreate Docker/Kind state, or introduce
a second native preflight implementation. Do not restore any devcontainer or agent-container
runtime.

### Required context

Read `AGENTS.md`, `README.md`, `docs/host-isolation.md`, `docs/native-user-tools.md`,
`docs/local-budget-analyzer-tls.md`, `docs/native-tool-inventory.md`, `native/toolchain.json`,
`scripts/check-agent-vm-tools.sh`, `scripts/native/user_tools.py`, their focused tests, and
`../orchestration/docs/agents-md-checkstyle.md`. Inspect `git status` first and preserve the
user's existing workspace changes.

### Execution steps

1. State in workspace's owner documentation that workspace owns native VM identity, user/home,
   repository topology, forwarded-authority rejection, guest Docker selection, native tool
   versions, and trust readiness; orchestration owns the application and local Kubernetes layer.
2. Treat `scripts/check-agent-vm-tools.sh` and its implementation as the single native runtime
   verifier. Document a stable non-mutating invocation that sibling orchestration can call with
   the reviewed worktree and bare-repository parents.
3. Confirm the canonical verifier enforces the complete accepted contract, including Ubuntu 24.04
   QEMU/KVM execution, normal user/home ownership, absent credential/proxy/endpoint bridges,
   guest-local bare/worktree topology, default Unix Docker socket and `/var/lib/docker`, the
   manifest's Node 24/JDK 25/tool versions, and established read-only ingress trust.
4. Refactor shared verifier code only if necessary to expose that stable invocation. Do not create
   a weaker orchestration-specific Node 20 or partial credential mode; first bootstrap is allowed
   only after workspace preparation and trust have completed.
5. Add or tighten offline tests for every contract orchestration will delegate, especially remote
   Docker rejection, forwarded authority, Node/tool version drift, missing native environment
   inputs, and failed read-only trust verification.
6. Remove any remaining active workspace devcontainer instructions or assumptions discovered by
   the focused search in Phase 4's implementation notes. Preserve ordinary application-container,
   Kind, and Testcontainers terminology.
7. Keep human installation and agent-readable checks distinct: the callable verifier must never
   invoke sudo, install packages, mutate trust, authenticate, or repair repositories.

### Implementation notes

Prefer strengthening and documenting the existing complete verifier over adding another mode.
If a new option is unavoidable, name it by the capability it proves, make it at least as strict as
the existing native preflight for overlapping concerns, and test both interfaces against the same
implementation. Workspace may read orchestration's current wrapper to understand the consumer,
but this phase writes only workspace.

### Validation

Run the workspace-required native manifest, install-input, user-environment, preparation,
provisioning, user-tools, and local-CA offline tests listed in `docs/native-tool-inventory.md` and
`docs/native-user-tools.md`. Run `bash -n` and ShellCheck on every changed shell script,
`PYTHONDONTWRITEBYTECODE=1` Python syntax/tests with cache output confined to workspace `tmp/`, and
`git diff --check`. Search active workspace sources for `devcontainer`, `Reopen in Container`,
retired agent-container launch commands, `/home/vscode`, and fixed `/workspace` defaults; explain
or remove every match.

### Completion criteria

Workspace exposes one documented read-only native-runtime contract suitable for both initial
application bootstrap and daily startup, tests prove the delegated checks, no live state changed,
and no active workspace guidance offers the retired container path.

## Phase 2: Move Host Isolation Audit Ownership To Workspace

### Workspace

../workspace

### Goal

Make workspace the canonical home for reusable personal-host isolation review while separating
portable audit logic from private machine-specific values and evidence.

### Scope

Add the host-isolation audit runbook, read-only evidence collector, bounded protocol fixture,
configurable go/no-go verifier, tracked configuration template, focused offline tests, privacy
ignore rules, and concise workspace indexes. Adapt the current orchestration implementations rather
than independently rewriting their behavior.

### Non-goals

Do not delete orchestration copies in this phase, access the personal host, collect new evidence,
apply or install nftables/UFW/systemd/libvirt policy, ship real MAC/IP/bridge values, or treat an
offline fixture as proof of live isolation. Do not copy `candidate-report.md` or any raw report.

### Required context

Read the workspace documents from Phase 1 and the current orchestration
`docs/runbooks/host-isolation-audit.md`, `scripts/ops/collect-host-isolation-evidence.py`,
`scripts/ops/host-isolation-protocol-fixture.py`, `scripts/ops/verify-agent-host-isolation.sh`,
`tests/host-isolation-audit/`, `scripts/README.md`, and `docs/OWNERSHIP.md`. Recheck both worktree
statuses and treat orchestration as read-only source material.

### Execution steps

1. Move the reusable audit procedure into workspace documentation and align it with
   `docs/host-isolation.md`; keep the normal-agent prohibition on host access and human-only
   collection, repair, reboot, and live protocol testing explicit.
2. Port the collector and protocol fixture with their offline tests. Preserve fail-closed host
   identity checks, private output location, best-effort-redaction warnings, no-active-probe
   collector behavior, and positive-control requirements for protocol conclusions.
3. Replace hardcoded verifier topology with a reviewed configuration input generated from a
   tracked example template. Include placeholders for domain, network, bridge, guest MAC/IPv4,
   gateway, policy service/file/loader/unit, and any required unit set; commit no real deployment
   values.
4. Require the live verifier to receive the private configuration explicitly, validate every
   required field and value shape, reject unknown or duplicate keys, and fail closed on a missing,
   symlinked, unexpectedly owned, or group/world-writable configuration. Keep output limited to
   the existing binary `SUCCESS`/`ERROR` contract.
5. Add fixture configurations that prove valid substitution and rejection of missing,
   malformed, unsafe, or drifted values without reading real `/etc`, libvirt, firewall, Docker, or
   process state. Keep policy source private and outside the repository.
6. Add ignore coverage for `candidate-report.md`, `budget-host-audit-*`, raw captures, indexes,
   and documented guest-side temporary audit locations. The collector must continue refusing
   repository output paths.
7. Update workspace `README.md`, `AGENTS.md`, and the nearest script/test indexes with concise
   links; keep the detailed procedure in one owner document.

### Implementation notes

Use either a strict key/value configuration file or an equivalently reviewable rendered template,
but do not silently discover and accept topology. The tracked template is documentation and test
input, not live policy. Human review must compare private concrete values with the actual VM before
running the verifier. Keep addresses and host storage choices operator-owned as already stated by
workspace.

### Validation

Run the ported collector, protocol, configuration-parser, and verifier offline tests; run no live
collector or verifier. Run Python syntax/tests with `PYTHONDONTWRITEBYTECODE=1`, `bash -n`,
ShellCheck, workspace documentation link checks available in the repository, `git diff --check`,
and a secret/privacy scan of added fixtures. Prove tracked files contain placeholders rather than
the previously embedded MAC, private addresses, bridge, or personal-host listener/process output.

### Completion criteria

Workspace owns a tested reusable audit suite and runbook, the live go/no-go verifier is driven by
an explicit private configuration derived from a safe template, generated evidence is ignored,
and no machine-specific report or topology was added.

## Phase 3: Delegate Orchestration Native Checks And Remove Duplicates

### Workspace

.

### Goal

Reduce orchestration to a thin application preflight that consumes workspace's canonical native
verifier and adds only orchestration-owned local Kind and application checks.

### Scope

Update `scripts/bootstrap/check-agent-vm-prerequisites.sh`,
`scripts/bootstrap/check-tilt-prerequisites.sh`, `setup.sh`, the shared target libraries, native
preflight fixtures, imported-TLS integration where needed, `scripts/README.md`, and direct links to
the relocated audit suite. Remove the orchestration host-audit implementations and tests only after
the workspace copies and tests from Phase 2 exist.

### Non-goals

Do not edit workspace in this phase, change the standard local bootstrap's application behavior,
weaken Kubernetes target checks, generate TLS, install guest trust, recreate a live cluster during
validation, or keep fallback copies of workspace-owned VM/Docker/credential logic.

### Required context

Read `AGENTS.md`, `scripts/README.md`, `setup.sh`, all three current target libraries,
`scripts/bootstrap/check-agent-vm-prerequisites.sh`,
`scripts/bootstrap/check-tilt-prerequisites.sh`, `scripts/bootstrap/install-imported-ingress-tls.sh`,
the native/imported-TLS fixtures, and the completed workspace contracts from Phases 1 and 2.
Inspect the current user deletion of `candidate-report.md` and preserve it.

### Execution steps

1. Keep `scripts/lib/local-kubernetes-target.sh` in orchestration as the single implementation of
   exact `kind-kind` context, referenced cluster, loopback HTTPS authority, absent proxy override,
   local Kind name, and Ready control-plane checks.
2. Change `check-agent-vm-prerequisites.sh` into a thin aggregator: resolve the sibling workspace
   without a hardcoded absolute path, require the managed native environment inputs, invoke the
   complete workspace verifier, and add the local Kind target only for daily/runtime mode.
3. Make `setup.sh --guest-local` invoke the complete workspace-backed bootstrap preflight and
   imported-TLS validation before the first `kind delete cluster` or other mutation. A missing
   workspace checkout, stale tools, wrong Node/JDK, forwarded authority, remote Docker, or missing
   trust must stop before destructive work.
4. Make `check-tilt-prerequisites.sh --guest-local` delegate native boundary/Docker/tool checks to
   workspace and retain only orchestration repository, image/tool compatibility, Kind, Tilt, and
   runtime-security diagnostics. Keep standard non-VM behavior separate and explicit.
5. Remove `scripts/lib/native-guest-boundary.sh` and `scripts/lib/local-docker-target.sh` after all
   consumers delegate to workspace. Split or rename `tests/native-guest-preflight/` so
   orchestration retains only local-Kubernetes and wrapper-integration fixtures; do not duplicate
   workspace's VM/Docker/credential cases.
6. Remove the orchestration copies of the host-isolation runbook, collector, protocol fixture,
   go/no-go verifier, and host-audit tests. Update all direct references to the workspace-owned
   paths in the same checkpoint.
7. Add orchestration ignore protection for candidate reports and host-audit output even though the
   producer now lives in workspace.
8. Preserve orchestration-owned imported ingress validation, host-only ingress renewal,
   Kubernetes Secret reconciliation, Tilt resource/guardrail, and their tests unchanged except for
   required owner links.

### Implementation notes

Do not source implementation internals from workspace. Invoke a documented executable interface so
each repository retains a clear boundary. Keep wrapper arguments compatible only where they still
describe an active native workflow; remove retired-container flags and messages rather than
translating them. Tests must use disposable command stubs and paths, never the live workspace
installer, trust store, Docker daemon, or cluster.

### Validation

Run `bash -n` and ShellCheck on every changed shell script. Run the refactored local-Kubernetes,
wrapper, imported-ingress-TLS, setup safety, and Tilt-resource guardrail fixtures without mutating
the live cluster. Use `rg` to prove removed orchestration files have no active references and that
`local-docker-target.sh` and `native-guest-boundary.sh` have no consumers. Run `git diff --check`.

### Completion criteria

Every guest bootstrap and daily path consumes workspace's full native verifier, destructive setup
fails before mutation on an invalid workspace prerequisite, orchestration retains only its local
Kubernetes/application checks, and all duplicate host-audit and native-boundary implementations
are gone.

## Phase 4: Remove Devcontainer Guidance And Simplify Active Documentation

### Workspace

.

### Goal

Make the native development VM the only active agent workflow described by orchestration and
remove stale devcontainer/container-agent instructions and duplicated workspace-owned detail.

### Scope

Update `docs/OWNERSHIP.md` first, then `AGENTS.md`, `README.md`, `CONTRIBUTING.md`,
`docs/development/getting-started.md`, `docs/development/local-environment.md`,
`docs/architecture/autonomous-ai-execution.md`, bootstrap diagnostics, script indexes, and other
active references found by repository-wide search. Delete the obsolete
`docs/development/devcontainer-installed-software.md` if no active supported consumer remains.

### Non-goals

Do not edit `docs/archive/` or rewrite ADR history merely to modernize historical examples. Do not
remove references to application containers, Kind node containers, Testcontainers, Docker image
builds, or the explicit warning that agents must not reconstruct a retired runtime. Do not copy
workspace's detailed host/VM/trust procedures back into orchestration.

### Required context

Read `docs/OWNERSHIP.md`, `docs/agents-md-checkstyle.md`, `AGENTS.md`, `README.md`,
`CONTRIBUTING.md`, both development guides, the autonomous-execution architecture document, the
completed workspace owner documents, and all matches from the focused searches below. Use the
documentation ownership rules before editing summaries.

### Execution steps

1. Update `docs/OWNERSHIP.md` first: workspace owns host/VM isolation, repository transport,
   native tools/user/home, guest Docker, exact OS/NSS trust, and host audit; orchestration owns
   application startup, local Kind authority, imported TLS validation/renewal, and Secret/Tilt
   integration.
2. Remove the personal-host devcontainer onboarding block from the beginning of
   `docs/development/getting-started.md`. Start directly with workspace provisioning as a human
   prerequisite and the native VM first-bootstrap/daily paths.
3. Remove `Reopen in Container`, devcontainer auto-configuration, lazy container-local trust,
   container-agent launch, old `/home/vscode`, Compose lifecycle, and retired sandbox guidance
   from all active docs and diagnostics. Replace relevant host-versus-container errors with precise
   host-OS or guest-OS ownership language.
4. Delete the dedicated devcontainer software inventory and remove every inbound link. Update
   `CONTRIBUTING.md`, `README.md`, and setup guidance to point to workspace native provisioning and
   orchestration application startup.
5. Reduce `docs/architecture/autonomous-ai-execution.md` to orchestration-owned authority: local
   application credentials, exact Kubernetes mutation target, API-test local-origin gate,
   bootstrap/Tilt behavior, and production exclusions. Link once to workspace for VM, Git, Remote
   SSH, host isolation, Docker, and native-agent details.
6. Reduce `docs/development/local-environment.md` to orchestration-owned ingress publication,
   imported-file validation, host-only renewal, Secret reconciliation, and application mechanics.
   Replace exact workspace installer/convergence commands and system trust paths with a link to the
   workspace owner, except for the one stable prerequisite invocation needed by the end-to-end
   Getting Started sequence.
7. Keep `AGENTS.md` guardrails concise: native VM only, no host/staging/production authority,
   workspace owner link, exact local Kubernetes guard, TLS write prohibition, and no absolute path
   assumptions. Remove claims that a separate local-host devcontainer remains supported.
8. Run focused searches over active files for `devcontainer`, `dev container`, `Reopen in
   Container`, `containerized agent`, `agent container`, `sandboxed container`,
   `workspace-devcontainer`, `/home/vscode`, Docker Compose agent launch commands, and absolute
   `/workspace` runtime paths. Remove each stale match or document why a generic container or
   portability guard is still valid.
9. Update links to the workspace-owned host-audit runbook and scripts and ensure no active link
   points at deleted orchestration paths.

### Implementation notes

The acceptance target is zero active `devcontainer` or `Reopen in Container` guidance outside
historical archives/ADRs. Generic words such as container, Docker, image, Kind, and Testcontainers
remain valid when they refer to application workloads. The `AGENTS.md` rule prohibiting hardcoded
`/workspace` paths may remain because it is a portability guard, not launch guidance; operational
examples must use relative or dynamically resolved paths.

### Validation

Run the focused searches from step 8 with `docs/archive/` and immutable decision context reported
separately. Verify every remaining active match manually. Check all changed relative links and all
links to sibling workspace files, run the repository's `AGENTS.md` checkstyle procedure, and run
`git diff --check`. Confirm `getting-started.md`, `README.md`, and `CONTRIBUTING.md` describe one
coherent native VM workflow and no longer tell users to reopen anything in a container.

### Completion criteria

Active orchestration documentation presents only the native VM agent path, detailed VM/host/trust
material has one workspace owner, the obsolete devcontainer inventory and links are gone, and the
remaining container references are application-runtime terms or explicit safety prohibitions.

## Phase 5: Prove The Simplified Cross-Repo Contract

### Workspace

.

### Goal

Complete orchestration-side integration validation and eliminate stale files, links, privacy
hazards, and compatibility remnants left by the ownership move.

### Scope

Inspect the complete orchestration diff and active source tree, make only final orchestration
cleanup required by validation, and run all safe offline/static checks relevant to native
preflight delegation, local Kubernetes targeting, TLS reconciliation, Tilt wiring, documentation,
and evidence privacy.

### Non-goals

Do not edit workspace in this phase, run live host audit tools, mutate the personal host or live
Kind cluster, run certificate generators, install trust, rewrite Git history, or claim live
host-isolation acceptance from offline tests.

### Required context

Read the completed outputs and validation evidence from Phases 1 through 4, current `AGENTS.md`,
`docs/OWNERSHIP.md`, `scripts/README.md`, `setup.sh`, `Tiltfile`, the remaining target/preflight
libraries and tests, and both repositories' current status. Re-read the host-isolation and
autonomous-execution owner documents before interpreting any safety failure.

### Execution steps

1. Inventory the final branch delta and verify every changed or deleted orchestration file has a
   clear owner and an active consumer; remove no unrelated user work.
2. Prove no candidate report, raw host capture, concrete host-audit configuration, real MAC/IP
   fixture, or generated index is tracked or newly unignored. Confirm the deleted report is not
   reintroduced; leave history handling to the human Git owner.
3. Prove all guest bootstrap and daily entry points use the workspace executable contract and all
   cluster mutations retain the orchestration exact-target guard.
4. Prove Tilt invokes only the non-generating imported-TLS installer and no active path invokes
   guest trust installation, browser certificate generation, or host-audit collection.
5. Run the complete changed-shell `bash -n` and ShellCheck set, Python syntax/offline tests,
   native wrapper/local-Kubernetes fixtures, imported-TLS fixtures, setup safety checks, Tilt
   resource guardrail, and relevant static security guardrails. Use only fixtures for destructive
   or host-owned behavior.
6. Repeat the active devcontainer/retired-runtime search and stale-path search across orchestration.
   Verify sibling links resolve to the final workspace owner paths and no deleted orchestration
   audit path remains.
7. Run `git diff --check`, inspect final status, and produce a handoff that distinguishes offline
   proof, any unavailable live check, the private human history gate, and any remaining manual
   host verification.

### Implementation notes

Do not weaken a check to make the suite green. A failure caused by a missing workspace prerequisite
must remain a clear prerequisite failure. If a cross-repo interface changed after its workspace
phase, stop and return to a new workspace-scoped phase rather than reimplementing it in
orchestration.

### Validation

At minimum, require all commands listed in step 5, the focused active-reference searches, sibling
link inspection, `git diff --check`, and a clean accounting of worktree status. Do not run live
`kubectl`, `kind delete`, `setup.sh`, `tilt up`, host collectors, firewall verifiers, trust
installers, or TLS generators as part of this offline final gate.

### Completion criteria

The two repositories have one unambiguous ownership split, orchestration contains no duplicate VM
or host-audit implementation, active devcontainer guidance is absent, all safe static/offline tests
pass, private evidence prevention is in place, and the handoff clearly identifies the human-only
history and live-host gates.
