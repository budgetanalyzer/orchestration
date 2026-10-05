# Agent Host Isolation Acceptance Record

**Status:** Native preparation Phases 1–2 and human Checkpoint B are complete.
The preserved runner state selects Phase 3 for the first native execution on
2026-10-05; Checkpoints C–D and overall native acceptance remain pending. Prior
container migration evidence is retained below and is not native proof.
Operator preparation Steps 1–5 and the Initial Handoff were completed and
verified on 2026-10-03. Checkpoint A repository, credential, TLS, bootstrap,
stack-health and agent-restart checks were completed on 2026-10-04; the Java
and frontend live-update checks remain deferred to Checkpoint C.

The active contracts are the [native execution plan](agent-vm-native-execution-plan.md)
and [human checkpoints](agent-vm-native-manual-plan.md). References to original
phase numbers and Checkpoints A–C in the historical sections describe the old
container migration, not the new native A–D checkpoints.

This record contains redacted acceptance evidence for the development VM host
isolation work. Keep repository references to basenames. Do not add private
remote URLs, absolute personal-host paths, credentials, private keys,
certificate private-key contents, browser state, full firewall dumps, MAC
addresses or unrelated host configuration.

## Native Preparation Handoff

**Status:** COMPLETE; operator verified Checkpoint A on 2026-10-04. The first
native-plan invocation has not yet been recorded. Phases 1–2 are cleared to
start in the existing guest container.

| Evidence | Result |
| --- | --- |
| Old workers ended; source preserved; new reviewed plan/tool sources transferred | PASS — operator verified; no old native-plan workers were running |
| Guest-local checkout/bare origins and handler revision; no imported old runner state | PASS — operator verified; workspace and orchestration clean at 8222890 and 99af5c5, respectively; local workspace origin; fresh native-plan state |
| Current VM confinement, no host integration, Remote SSH/credential boundary | PASS — operator verified on the personal host and guest |
| Paired native/Docker host firewall fixtures, positives, IPv4/IPv6 applicability and hooks | PASS — operator verified paired results, applicable address families, positive controls, and persistent policy hooks |
| Guest OS prerequisites, default local Docker, exact Kind target and healthy Tilt | PASS — read-only checks; default Unix Docker endpoint, `/var/lib/docker`, context/cluster `kind-kind`, loopback API, Ready `kind-control-plane`, healthy Tilt and workloads |
| Existing guest container identity/mounts and provider/handler availability | PASS — operator verified nonprivileged guest agent, host networking, same-path guest source/bare mounts, read-only guest kubeconfig, and available provider/handler |
| First invocation capped at two phases in the guest checkout | READY — first invocation must use the command below with `--max-phases 2`; no native-plan invocation recorded yet |

Checkpoint A evidence was reviewed on 2026-10-04. The in-container
`systemd-detect-virt` command is unavailable and was not used as VM proof;
personal-host VM inspection and confinement evidence were verified by the
operator. Java and frontend live-update checks remain deferred to Checkpoint B.

## Native Execution Handoff

**Status:** COMPLETE on 2026-10-05; cleared to resume at Phase 3 from the
native guest OS. This does not complete Checkpoints C–D.

| Evidence | Result |
| --- | --- |
| Installer revision, full tool inventory and tracked fixture results reviewed | PASS — workspace installation base `faa63e9`, reviewed B.2/B.3 revisions `42c0896` and `0195929`; handler `619cdd1`; prior Phase 1/2 fixture evidence retained |
| System/user installation and repeat-run idempotence; no unintended runtime restart | PASS — live system install plus initial and repeated user installs completed; unrelated configuration was preserved and the pre-cutover Docker runtime was not restarted by installation |
| Native user/home, fresh-shell tool resolution, handler import and selected permissions | PASS — `budgetops`, normal home, native `.local/bin` commands, editable guest-local handler import and unrestricted high-reasoning handler mode verified |
| Native provider workspace-read and sandbox-mode proof without credential disclosure | PASS — native Codex 0.160.0 read the guest checkout; selected process used the documented full-guest bypass mode; separate `codex sandbox` bubblewrap proof passed and is not misrepresented as the selected mode |
| curl/Python/Node/Playwright verified app trust and public-root preservation | PASS — all four clients returned verified HTTPS success for the exact local app; established host-published public-root identity remained unchanged |
| Guest origins/credential boundary and current Docker/Kind/Tilt health | PASS — 13 local repository pairs, no prohibited credential bridge variables, local Unix Docker, loopback `kind-kind`, Ready node and healthy Tilt resources |
| All old guest containers/volumes removed; clean guest-local rebuild and application proof | PASS — human-confirmed empty container/volume checks preceded the rebuild; no old container, image or Docker volume was retained; rebuilt ingress, app and full smoke test passed |
| Same new-plan guest state selects Phase 3; paired host evidence still applicable | PASS — accepted plan SHA-256 unchanged, status selects Phase 3, and Checkpoint A host evidence remains applicable pending its required C repetition |

### Recorded Native Handoff Evidence

- The live installation report identifies native user `budgetops`, the normal
  guest home, workspace base `faa63e9`, handler `619cdd1`, and the reviewed npm
  lock. Its four B.1 dirty workspace paths were incorporated by the reviewed
  B.2/B.3 revisions; workspace is clean at `0195929`. Installed user tools
  include Claude 2.1.289, Codex 0.160.0, Gemini 0.62.0, Playwright 1.63.0,
  mitmproxy 12.2.3 and the editable AI Session Handler 0.2.0. The existing
  Phase 1 and Phase 2 records retain their 36-case and 76-case fixture results
  and the later focused-harness limitation.
- Guest-native identity checks returned user `budgetops`, container detection
  `none` and VM detection `kvm`. The native verifier passed for all 13 local
  repository pairs, provider/browser/helper versions, browser/package/home
  paths and fresh-shell resolution. A fresh login shell resolved every selected
  provider, Playwright and handler command from the native user's `.local/bin`;
  the handler imported from the guest-local `ai-session-handler` checkout.
- The selected provider proof used native Codex 0.160.0 with configured model
  `gpt-5.6-sol`, high reasoning and the explicit
  `dangerously-bypass-approvals-and-sandbox` / `never` /
  `danger-full-access` behavior. It read and updated this guest checkout. That
  mode has full guest access and is not an OS sandbox. Independently,
  `codex sandbox -- sh ...` passed through the loaded scoped bubblewrap policy,
  proving the sandbox mechanism remains available without claiming that the
  selected provider/handler mode uses it.
- The human trust installer and read-only trust check verified the same
  host-published ingress root. Verified requests to the exact local HTTPS app
  passed with curl, Python, Node and headless Playwright/Chromium, each returning
  HTTP 200 without an insecure option. No ingress or proxy CA was generated,
  copied or activated; optional inspection remains unused.
- The native preflight passed on Ubuntu 24.04 with default Docker context,
  `unix:///var/run/docker.sock`, guest daemon `budget-analyzer-agent` and
  `/var/lib/docker`. The credential-boundary check found no forwarded SSH/GPG
  agent, GitHub token or askpass bridge. Kubernetes selected context and cluster
  `kind-kind`, a loopback HTTPS API and Ready `kind-control-plane`.
- Before the cutover, the human reviewed the exact disposable guest Docker
  inventory and confirmed both post-removal empty-state checks. Every old guest
  container and every old named or anonymous volume was deleted, followed by
  the reviewed image/cache/network prune. **No old agent container, agent image,
  provider volume or other pre-reset Docker volume was retained.** The current
  Docker state contains only the rebuilt `kind-control-plane`; its sole
  anonymous `/var` volume was newly created by the clean bootstrap.
- `./setup.sh --guest-local`, frontend dependency installation, the guest-local
  Tilt preflight and `tilt up` rebuilt the environment from retained guest
  files. All required Tilt resources report `ok`; the ingress TLS resource
  logged validation of the imported files and Secret installation without
  certificate generation. Established trust and direct app curl passed. After
  the GNU awk portability repair in the edge verifier, its focused run reported
  84/84 blocking checks and the nested runtime-hardening cascade reported
  176/176; the operator then confirmed the complete smoke-test umbrella passed.
- The accepted execution-plan SHA-256 remains
  `feadfeb5d8c1d2d915352e6db438053bb95945d446230e880bf32e658668b75b`;
  no plan-change acceptance was used. The same guest-local runner state reports
  `next phase: phase-3 Prove Native Workspace Execution` with execution workspace
  `workspace`.
- Checkpoint A's paired native/Docker host denials, listener positives,
  DNS/verified-download and host-initiated SSH/Git evidence remain the human
  host-boundary authority; no B change altered that policy. Checkpoint C must
  still prove trusted host browser behavior, Java/frontend Remote SSH saves and
  restoration, native session lifecycle, restart persistence, repeated boundary
  tests, absence of legacy resources and measured guest use. Checkpoint D must
  still return reviewed source, retire Mint Docker and repeat the final boundary
  proof.

## Native Execution Results

| Phase | Owner evidence | Result |
| --- | --- | --- |
| 1: system installer/tool inventory | workspace `docs/host-isolation.md` | COMPLETE — preparation evidence and live B.1 install recorded |
| 2: user environment/helpers | workspace `docs/host-isolation.md` | COMPLETE — preparation evidence and live B.1/B.2 verification recorded |
| 3: native runtime and workspace checks | workspace `docs/host-isolation.md` | READY — native handoff complete; phase not yet invoked |
| 4: orchestration native preflight/docs | This record | PENDING |
| 5: native shared-library build/publication | service-common active development docs | PENDING |
| 6: native currency Testcontainers | currency-service `docs/local-development.md` | PENDING |
| 7: native gateway Testcontainers | session-gateway `docs/local-development.md` | PENDING |
| 8: application/security proof and final procedures | This record | PENDING |

## Native Human Acceptance

- Checkpoint C trusted browser, Java/frontend save/restoration, native session
  lifecycle and host/guest reboot persistence: PENDING.
- Checkpoint C absence of legacy guest agent resources, native independence,
  rebuilt application persistence and measured guest resource use: PENDING.
- Checkpoint D reviewed source returned, Mint Docker/runtime/hooks retired,
  permanent host policy retained and final reboot proof: PENDING.
- Optional proxy activation: NOT EXECUTED; installed capability/offline checks
  still required in workspace evidence.
- Overall native migration acceptance: PENDING human C/D; no result inferred
  from planning, installer fixtures or historical container passes.

## Initial Operator Handoff

### VM

- Name / guest release:
  `budget-analyzer-agent / Ubuntu Server 24.04.5 LTS (x86-64)`
- vCPU / RAM / virtual disk / free guest space:
  `8 vCPU / 24 GiB / 200 GiB sparse / 172 GiB free`
- QEMU / libvirt / virt-manager versions:
  `QEMU 8.2.2 / libvirt 10.0.0 / virt-manager 4.1.0`
- Disk outside repository trees: `PASS`
- AppArmor dynamic confinement: `PASS - enforcing dynamic libvirt label`
- Prohibited VM devices absent: `PASS - operator verified`

### Network Boundary

- Libvirt network / bridge / selected CIDR:
  `agent-nat / virbr1 / 192.168.231.0/24`
- NAT active + autostart: `PASS`
- Guest IPv4: `192.168.231.10`
- UFW active + native bridge-rule order: `PASS`
- Docker backend / bridge matches:
  `PASS - iptables-nft compatibility backend; docker0 and br-+ covered`
- Docker helper / Docker-start hook / UFW-reload hook:
  `PASS - helper and both persistence hooks recorded; reboot proof pending`
- DHCP/DNS exceptions:
  `PASS - IPv4 DHCP and gateway DNS TCP/UDP precede the virbr1 deny`
- Guest-to-host IPv4 fixture result:
  `PASS - all inventoried non-loopback host IPv4 attempts timed out`
- Guest-to-host IPv6 fixture result: `PASS - operator verified`
- Guest-to-host Docker fixture result / firewall backend:
  `PASS - operator verified / iptables-nft compatibility backend`
- Guest Internet positive control: `PASS - operator verified`
- Host-to-guest SSH positive control: `PASS - operator verified`
- Guest reboot persistence: `PENDING until Checkpoint C`
- Host reboot persistence: `PENDING`
- Mint Docker retirement: `PENDING until Checkpoint C`
- LAN/VPN peer isolation: `OUT OF SCOPE`

### Guest Access

- Storage root: `/srv/budget-analyzer`
- SSH alias / host-key fingerprint verified: `PASS - operator verified`
- SSH/X11/automatic port forwarding disabled: `PASS - operator verified`
- VS Code profile and remote credential checks: `PASS - operator verified`

### Repositories

- Selected host parent description:
  `Common parent containing sibling Budget Analyzer repositories`
- Selected repository basenames: `ai-session-handler`,
  `basic-repository-template`, `budget-analyzer-api-tests`,
  `budget-analyzer-web`, `checkstyle-config`, `currency-service`, `ext-authz`,
  `orchestration`, `permission-service`, `service-common`, `session-gateway`,
  `transaction-service`, `workspace`
- Non-main seed branches:
  `orchestration: vm-workspace`; `workspace: vm-workspace`

### Browser/TLS

- Current host port-443 listener:
  `Mint Docker-published listener`
- Certificate validity/SAN/chain/key-match checks: `PASS - operator verified`
- 8443 SSH forwarding fixture: `PASS - operator verified`
- Final 443 loopback binding: `PENDING until Checkpoint C`
- Dedicated browser profile created: `PASS - operator verified`

## Evidence Notes

- Guest evidence recorded Ubuntu 24.04.5 LTS on x86-64 under KVM, Linux kernel
  6.8.0-146-generic, Git 2.43.0 and an active SSH service. The root and project
  paths share a 193 GiB filesystem with 172 GiB available.
- Host evidence recorded eight vCPUs, 24 GiB RAM, an external VM storage-pool
  disk, QEMU 8.2.2 and libvirt 10.0.0. Machine identifiers, VM UUID, MAC address
  and the absolute personal-host disk path were intentionally omitted.
- Step 4.1 recorded the dedicated `agent-nat` bridge as `virbr1` with gateway
  `192.168.231.1`.
- Step 4.2 recorded active UFW rules with DHCP and DNS exceptions before the
  IPv4 bridge deny and only the corresponding bridge deny for IPv6.
- Step 4.2 recorded exactly one IPv4 and one IPv6 `DOCKER-USER` reject for each
  of `docker0` and `br-+`. The Docker service and UFW reload hooks invoke the
  reviewed isolation helper.
- Step 4.3 recorded timeouts from the guest to every inventoried non-loopback
  host IPv4 address. The operator verified the IPv6, Docker-path and required-
  traffic positive controls while following the manual plan.
- The persistent-rule listing was captured for the later Checkpoint B reboot
  comparison; it is not reboot-persistence proof.

## Checkpoint A Operator Handoff

### Repository And Credential Boundary

- One-time repository setup and host/guest topology checks:
  `PASS - operator verified`; every selected host checkout has the reviewed
  `vm` remote, and guest working clones use guest-local bare origins.
- Two-commit Git round trip:
  `PASS - checkstyle-config`; host-to-guest commit `63903c2`, guest-to-host
  commit `6ce57cf`; the host fast-forwarded the guest result, then removed the
  fixture branch and file and restored a clean worktree.
- Guest GitHub authority checks:
  `PASS - operator verified`; no forwarded SSH agent, GitHub token/askpass
  variable, global credential helper, authenticated GitHub CLI state or GitHub
  remote was present in the checked guest paths.
- Dedicated Remote SSH credential-injection checks:
  `PASS - operator verified`.

### TLS And Guest Runtime

- Approved TLS transfer and validation:
  `PASS - operator verified`; only the reviewed wildcard leaf, leaf key and
  public root were transferred, the guest validation and trusted temporary
  forwarding test passed, and no mkcert root signing key entered the guest.
- Guest prerequisites and local Docker selection:
  `PASS - operator verified`; the guest used its default Unix Docker endpoint
  and `/var/lib/docker` data root.
- Guest agent before Kind bootstrap:
  `PASS - operator verified`; the reviewed base container started and the
  selected provider read the guest-local workspace without GitHub authority.
- Fresh guest bootstrap:
  `PASS - operator verified`; cluster `kind`, context and referenced cluster
  `kind-kind`, loopback Kubernetes API selection and Ready
  `kind-control-plane` were confirmed.
- Agent kubeconfig recreation:
  `PASS - operator verified`; the exact guest kubeconfig was mounted read-only
  and the agent selected `kind-kind`.
- Tilt/application health:
  `PASS - operator verified`; required Tilt resources and Kubernetes pods were
  healthy. The guest listener was `docker-proxy` on `0.0.0.0:443`, matching the
  reviewed Kind `30443` to guest port `443` mapping; this is not the later Mint
  loopback-only forwarding check.
- Agent-container restart:
  `PASS - operator verified`; the agent returned to running state, guest and
  in-agent `kubectl` reported `kind-control-plane` Ready, and Kind/Tilt remained
  healthy.

### Deferred Acceptance

- Java Remote SSH live-update smoke edit: `NOT TESTED - deferred to Checkpoint C`.
- Frontend Remote SSH live-update smoke edit:
  `NOT TESTED - deferred to Checkpoint C`.
- Guest agent-container lifecycle helpers:
  `IMPLEMENTED in the original partial Phase 3 - fixture results recorded in
  workspace docs/host-isolation.md; tracked verifier and direct guest proof
  pending continuation Phase 1; live helper acceptance pending Checkpoint B`.
- Host/VM restart persistence, host loopback port 443, trusted browser behavior
  and the final daily workflow remain `PENDING Checkpoint C`.

The former container continuation was superseded by the
[native execution plan](agent-vm-native-execution-plan.md). The old incomplete
results remain historical; native acceptance still requires both named
live-update proofs. Original phase numbers below describe historical results.

## VM Continuation Handoff

**Status:** SUPERSEDED, not executed. These pending entries preserve the former
container-continuation handoff; do not execute or complete it. Use the native
handoffs above and [human checklist](agent-vm-native-manual-plan.md). Earlier
bare firewall PASS summaries still require detailed paired evidence for native
acceptance.

| Prerequisite | Evidence / status |
| --- | --- |
| Original handler/workers ended; original state retained on Mint | PENDING |
| Reviewed orchestration/workspace changes and lifecycle helpers transferred | PENDING; record selected branches, revisions and any relevant worktree changes |
| Guest handler/service-common/consumer revisions and shared coordinates aligned | PENDING |
| Guest-OS prerequisite checkers, Docker/Kind/Tilt/pod health | PENDING; commands, collection time, exits and sanitized results |
| Native INPUT fixtures and positive controls | PENDING; H.2 commands, bindings/address coverage and paired results |
| Docker forwarding fixtures and positive controls | PENDING; H.2 digest/bindings/routes and paired results |
| IPv4/IPv6 coverage and policy/hook inspection | PENDING; distinguish tested paths, absent routes and unexplained gaps |
| Allowed DNS/HTTPS/host-initiated SSH/Git | PENDING; command/results or unchanged detailed A.2 evidence |
| Final agent identity, mounts, socket, namespace and kubeconfig | PENDING; compare guest-OS inspection with in-agent checks |
| Provider workspace-read proof and handler/wrapper availability | PENDING; versions/results, never credentials |
| Container HTTPS trust, tools and writable build directories | PENDING |
| New plan has fresh state and guest-local command paths | PENDING |

The worker inspects host-owned evidence and directly executes guest-owned
checks. Host fixtures may be removed after paired evidence is recorded; no
worker SSH key or mid-run host source transfer is required. Network/policy
changes invalidate the affected host evidence. Guest-OS bootstrap checkers are
not run inside the agent. Its Maven artifacts are prepared by continuation
Phase 2, not inferred from the healthy guest-OS Tilt stack.

## VM Continuation Results

| Phase | Owner record | Result |
| --- | --- | --- |
| 1: guest/runtime/helper fixtures | workspace `docs/host-isolation.md` | PENDING |
| 2: agent-local shared-library build/publication | service-common active development documentation | PENDING |
| 3: currency Testcontainers | currency-service `docs/local-development.md` | PENDING |
| 4: session Testcontainers | session-gateway `docs/local-development.md` | PENDING |
| 5: application/security checks and operator procedures | This record and the manual plan | PENDING |

Continuation completion is distinct from overall acceptance. Java/frontend
Remote SSH saves, live lifecycle-helper operations, trusted host browser,
restart persistence and final Mint Docker retirement remain B/C requirements.

## Phase 1 Static Preparation

- Guest-local boundary contract and host-only GitHub publication model:
  `IMPLEMENTED - pending runtime proof at Checkpoint A`
- Explicit local-Docker preflight and `./setup.sh --guest-local` path:
  `IMPLEMENTED - statically validated; not launched in Phase 1`
- Imported ingress TLS validation, guest trust/Secret installation and
  host-only renewal path:
  `IMPLEMENTED - non-generating validation passed; guest install pending`
- Kind, Calico, Gateway API, infrastructure TLS, persistence and Tilt behavior:
  `UNCHANGED - guest runtime proof pending`
- Atomic frontend production-smoke image target:
  `UNCHANGED - guest live-update proof pending`
- Guest agent compose configuration and one-time repository setup script:
  `PENDING implementation Phase 2`
- Checkpoint A repository, GitHub-authority, TLS, bootstrap, agent restart and
  live-update acceptance: `PENDING`

Static validation passed for all changed shell files with `bash -n` and
ShellCheck; the existing approved TLS files passed the non-generating
validation path; local Docker socket selection passed while a synthetic remote
`DOCKER_HOST` was rejected; changed-document local links and `git diff --check`
passed; and the aggregate static security manifest guardrail passed. No guest
bootstrap or live-runtime acceptance is claimed.

Phase 1 made no live cluster mutation, VM change, certificate generation,
repository transfer, firewall change or GitHub write.
