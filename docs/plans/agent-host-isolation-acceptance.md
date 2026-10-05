# Agent Host Isolation Acceptance Record

**Status:** Operator-attested migration COMPLETE; independent security review
OPEN with confirmed firewall and retirement discrepancies. On 2026-10-05 the
operator confirmed that all eight execution phases and human Checkpoints A–D
were complete and that the full execution
and manual plans had finished and all checks passed, and requested this record
be updated. C/D completion is attributed to that confirmation, not a new agent
inspection of the personal host. The separate post-migration security review
below remains open. The subsequently supplied host report does not satisfy
the claimed final Docker-retirement state; see the dated review below.
Prior timestamped evidence is preserved as collected.
Operator preparation Steps 1–5 and the Initial Handoff were completed and
verified on 2026-10-03. Checkpoint A repository, credential, TLS, bootstrap,
stack-health and agent-restart checks were completed on 2026-10-04; the Java
and frontend live-update checks were deferred then and subsequently completed
in Checkpoint C according to the operator's final confirmation.

The completed migration used the [native execution plan](agent-vm-native-execution-plan.md)
and [human checkpoints](agent-vm-native-manual-plan.md). References to original
phase numbers and Checkpoints A–C in the historical sections describe the old
container migration, not the new native A–D checkpoints.

This record contains redacted acceptance evidence for the development VM host
isolation work. Keep repository references to basenames. Do not add private
remote URLs, absolute personal-host paths, credentials, private keys,
certificate private-key contents, browser state, full firewall dumps, MAC
addresses or unrelated host configuration.

## Native Preparation Handoff

**Status:** COMPLETE; operator verified Checkpoint A on 2026-10-04. This section
preserves the pre-invocation handoff state. The capped first invocation and
preparation Phases 1–2 subsequently completed before the native handoff above.

| Evidence | Result |
| --- | --- |
| Old workers ended; source preserved; new reviewed plan/tool sources transferred | PASS — operator verified; no old native-plan workers were running |
| Guest-local checkout/bare origins and handler revision; no imported old runner state | PASS — operator verified; workspace and orchestration clean at 8222890 and 99af5c5, respectively; local workspace origin; fresh native-plan state |
| Current VM confinement, no host integration, Remote SSH/credential boundary | PASS — operator verified on the personal host and guest |
| Paired native/Docker host firewall fixtures, positives, IPv4/IPv6 applicability and hooks | PASS — operator verified paired results, applicable address families, positive controls, and persistent policy hooks |
| Guest OS prerequisites, default local Docker, exact Kind target and healthy Tilt | PASS — read-only checks; default Unix Docker endpoint, `/var/lib/docker`, context/cluster `kind-kind`, loopback API, Ready `kind-control-plane`, healthy Tilt and workloads |
| Existing guest container identity/mounts and provider/handler availability | PASS — operator verified nonprivileged guest agent, host networking, same-path guest source/bare mounts, read-only guest kubeconfig, and available provider/handler |
| First invocation capped at two phases in the guest checkout | PASS — the initial run used the two-phase cap, committed Phases 1–2 and left the same runner state selecting Phase 3 |

Checkpoint A evidence was reviewed on 2026-10-04. The in-container
`systemd-detect-virt` command is unavailable and was not used as VM proof;
personal-host VM inspection and confinement evidence were verified by the
operator. Java and frontend live-update checks were deferred at this collection
point and remain Checkpoint C work after the completed native handoff.

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

- The live installation report identifies native user `budgetops`, home
  `/home/budgetops`, workspace base `faa63e9`, handler `619cdd1`, and the reviewed npm
  lock. Its four B.1 dirty workspace paths were incorporated by the reviewed
  B.2/B.3 revisions; the workspace source baseline was clean at `0195929`
  before these handoff evidence edits. Installed user tools
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
  no plan-change acceptance was used. The resumed orchestration handoff revision
  is `c1a3a2b`, containing the GNU awk verifier repair and this B.3 evidence.
  The same guest-local runner state reports
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

## Native Phase 4 Orchestration Evidence

Execution: 2026-10-05, AI Session Handler run
`20261005T115915Z-phase-4-7a906cf9-081c-4a42-a614-933ce235f822`, native
`budgetops` process in the KVM guest with home `/home/budgetops`. The
orchestration input revision was
`75ea1c5b4a6482cc91645eef5e2ebb3019b0ddde` and the worktree was initially
clean. The accepted execution plan was not modified.

Phase 4 aligned orchestration with the workspace-owned native tool/user/home
contract. The bootstrap preflight no longer requires Compose merely for the
retired guest agent container. Its new `--native-runtime` mode invokes the
workspace verifier and then checks the exact local Kubernetes target. Shared
helpers now fail closed on native-versus-container execution, forwarded host
authority, remote Docker/Testcontainers selection, context and referenced
cluster `kind-kind`, loopback HTTPS API, local Kind cluster `kind`, and a Ready
`kind-control-plane`. The imported-TLS installer and guest Tilt preflight use
the same Kubernetes target helper.

Canonical boundary, startup and local-environment docs now make one normal
guest user/home the supported native path, keep first bootstrap/clean rebuild
explicitly destructive and human-owned, and define daily startup as the
read-only native runtime preflight followed by `tilt up`. The deeper Tilt
preflight is documented accurately: its target gate is fail-closed and its
runtime-security proof creates and cleans named disposable probe resources.
Personal-host GitHub/mkcert/publication authority, exact local API target,
internal-only observability, native sandbox qualification and production
exclusions remain unchanged. A read-only sibling-doc search found no active
service-owner changes; workspace references to the removed guest Compose path
remain only in explicitly historical sections.

Validation results:

| Proof | Result |
| --- | --- |
| Native runtime preflight | PASS — workspace verifier checked `budgetops`, `/home/budgetops`, 13 working/bare repository pairs, pinned user tools, browser/trust paths and editable handler import; orchestration then verified local Docker and exact Ready Kind target |
| Target/boundary fixtures | PASS — 11 checks covering native and container execution, forwarded GitHub authority, remote Docker, Testcontainers override, non-Unix endpoint, valid target, wrong context, wrong referenced cluster, nonloopback API and missing node |
| Guest Tilt prerequisite/security proof | PASS — pinned tools, six service checkouts, Docker/Kind/Calico/Gateway API/TLS state and all four runtime-security proofs |
| Imported TLS validation | PASS — existing host-created files validated without trust or Kubernetes mutation |
| Static security guardrails | PASS — full manifest gate and intentional-failure self-test |
| Shell and documentation checks | PASS — Bash syntax and ShellCheck for all seven affected shell files; local links for eight changed docs; AGENTS checkstyle review; portable-path review; `git diff --check` |
| Preserved runtime | PASS — default Unix Docker at `/var/lib/docker`, cluster/context `kind`/`kind-kind`, loopback API, Ready node, 45/45 healthy Tilt resources, 34/34 healthy pods and verified HTTPS 200 from the exact app origin |

Reports are under `tmp/native-phase-4/validation/`. No package installation,
certificate generation/trust change, cluster recreation, service code change,
sibling write, production access or real-repository Git write occurred.

Read-only Maven inspection found `service-common` group
`org.budgetanalyzer`, version `0.0.17-SNAPSHOT`, with all four Java consumers
selecting the same `serviceCommon` version. Phase 4 did not infer publication
from the healthy stack or existing Maven Local contents. Native publication,
library tests and consumer-owned Testcontainers proofs remain assigned to
Phases 5–7. Human Checkpoint C still owns Remote SSH live edits, browser/session
acceptance and reboot/boundary repetition; Checkpoint D still owns Mint
retirement.

## Native Phase 8 Orchestration Evidence

Execution: 2026-10-05, AI Session Handler run
`20261005T145138Z-phase-8-4a362fcd-457e-4a0d-b604-eb5407b33b74`, native
`budgetops` process in the KVM guest with home `/home/budgetops`. The
orchestration input revision was
`75ea1c5b4a6482cc91645eef5e2ebb3019b0ddde`; the worktree contained the expected
cumulative Phase 4 implementation and documentation changes. The accepted
execution plan was not modified.

Phase 8 reviewed the completed workspace and service-owner evidence before
application acceptance. Phase 5 built and published the existing
`org.budgetanalyzer:0.0.17-SNAPSHOT` library artifacts to the native user's
Maven Local after 183 service-core and 545 service-web tests passed. Phase 6
passed all 252 currency-service tests against fresh PostgreSQL, Redis and
RabbitMQ Testcontainers. Phase 7 passed all 127 session-gateway tests against a
fresh Redis Testcontainer and its 90% line/65% branch coverage gates. Both
consumer runs proved Ryuk cleanup back to only `kind-control-plane`; their
documented shutdown connection warnings remain harmless limitations.

Fresh Phase 8 results:

| Proof | Result |
| --- | --- |
| Native identity and target | PASS — `budgetops`, `/home/budgetops`, container detection `none`, VM detection `kvm`, native tool/repository verifier, default Unix Docker at `/var/lib/docker`, loopback `kind-kind` and Ready node |
| Existing runtime | PASS — only `kind-control-plane` ran in Docker; all 45 Tilt resources and 34 pods were healthy before and after validation; no legacy agent/provider image or volume name was present |
| Exact HTTPS trust | PASS — the read-only native trust helper and verified curl returned HTTP 200 for `https://app.budgetanalyzer.localhost/`; no bypass, trust write or certificate operation occurred |
| Aggregate application/security proof | PASS — `./scripts/smoketest/smoketest.sh` completed, including 16/16 monitoring checks, loopback-only Grafana/Prometheus/Jaeger/Kiali access, 38/38 shared-session checks, 84/84 edge checks, 176/176 runtime-hardening checks and 69/69 NetworkPolicy checks |
| Disposable-resource cleanup | PASS — observability forwards and security/network probes reported cleanup; the runtime returned to the rebuilt Kind/application baseline |
| Human procedure review | PASS — Checkpoint C now specifies exact fresh-shell agent exit/reentry, browser, Java JAR-sync/JVM-restart and frontend HMR save/restoration proofs; Checkpoint D has scoped Mint discovery, host-policy ownership, source return and post-retirement native build/Testcontainers proofs |
| Changed-source validation | PASS — Bash syntax and ShellCheck passed for all seven cumulative shell files; the native boundary suite passed 11/11; static guardrail intentional-failure self-test, changed-document links, portable-path review and `git diff --check` passed |
| Immutable plan and final baseline | PASS — execution-plan SHA-256 remained `feadfeb5d8c1d2d915352e6db438053bb95945d446230e880bf32e658668b75b`; app, API docs and production-smoke routes returned 200, and both documented fixture sources remained at baseline |

The Java fixture changes only the `getAll` OpenAPI summary in
currency-service `CurrencySeriesController.java`; direct runtime inspection
confirmed the baseline summary and health endpoint before documenting it. The
frontend fixture changes only the login-page sentence in `LoginPage.tsx`; the
live Vite module and browser route exposed the baseline text before the
procedure was recorded. Both require Remote SSH save events, unchanged
pod/container identities, exact hash restoration, clean source diffs and
unchanged personal-host files. The worker did not perform or claim those human
save proofs.

No package installation, provider authentication, proxy activation,
certificate/trust write, VM or Docker restart, Kind recreation, human browser
login, source fixture edit, sibling service-source edit, runtime retirement,
host administration, production access or Git write occurred. Checkpoint C
still owns Remote SSH saves, native process reentry, browser/session behavior,
reboot persistence and repeated host-boundary evidence. Checkpoint D still owns
reviewed source return and Mint Docker retirement.

## Native Execution Results

| Phase | Owner evidence | Result |
| --- | --- | --- |
| 1: system installer/tool inventory | [workspace host-isolation evidence](../../../workspace/docs/host-isolation.md) | COMPLETE — preparation evidence and live B.1 install recorded |
| 2: user environment/helpers | [workspace host-isolation evidence](../../../workspace/docs/host-isolation.md) | COMPLETE — preparation evidence and live B.1/B.2 verification recorded |
| 3: native runtime and workspace checks | [workspace host-isolation evidence](../../../workspace/docs/host-isolation.md) | COMPLETE — native tool, provider, sandbox distinction, Git/Docker/trust and preserved-runtime evidence recorded |
| 4: orchestration native preflight/docs | This record | COMPLETE — native preflight, shared target checks, tracked fixtures, owner docs and preserved guest health recorded |
| 5: native shared-library build/publication | [service-common README](../../../service-common/README.md#native-vm-maven-local-verification) | COMPLETE — native build, 728 tests, quality gates and four Maven Local publications passed |
| 6: native currency Testcontainers | [currency-service local development](../../../currency-service/docs/local-development.md#native-vm-testcontainers-verification) | COMPLETE — 252 tests passed with PostgreSQL, Redis and RabbitMQ lifecycle/cleanup evidence |
| 7: native gateway Testcontainers | [session-gateway local development](../../../session-gateway/docs/local-development.md#native-vm-testcontainers-verification) | COMPLETE — 127 tests and coverage gates passed with Redis lifecycle/cleanup evidence |
| 8: application/security proof and final procedures | This record | COMPLETE — native target/trust, aggregate smoke/security/observability proof and concrete C/D procedures passed review |

## Native Human Acceptance

- Checkpoint C trusted browser, Java/frontend save/restoration, native session
  lifecycle and host/guest reboot persistence: COMPLETE — operator-confirmed.
- Checkpoint C absence of legacy guest agent resources, native independence,
  rebuilt application persistence and measured guest resource use: COMPLETE —
  operator-confirmed; no new measurements are invented in this update.
- Checkpoint D reviewed source returned, Mint Docker/runtime/hooks retired,
  permanent host policy retained and final reboot proof: COMPLETE —
  operator-confirmed.
- Installed native tool parity and required capability checks: COMPLETE; this
  establishes tooling, not human C/D acceptance.
- Representative native shared-library and Testcontainers execution: COMPLETE;
  these runs do not establish Remote SSH save or reboot persistence.
- Repository execution workers: COMPLETE through Phase 8; no worker completion
  is relabeled as human browser, host-policy or retirement proof.
- Optional proxy activation: NOT EXECUTED; installed capability and offline
  checks are recorded in workspace evidence, and live activation is not required.
- Overall native migration acceptance: COMPLETE — operator confirmed the full
  execution/manual plans and all checks passed on 2026-10-05.

This completion update records the operator's attestation. Exact C/D command
transcripts, individual run timestamps, host configuration and measurements
were not supplied in this conversation and are not fabricated here. Earlier
sections that said C/D were pending preserve their historical collection state.
The original execution-plan bytes and runner state remain unchanged.

## Post-Migration Security Review

**Status:** OPEN; distinct from completed migration acceptance.
Review baseline: orchestration `3b67af2`, workspace `fed714c`, both compared
against local `main`. The operator requested a new remediation plan after review.

| Finding / improvement | Evidence and next action | Status |
| --- | --- | --- |
| Required native npm lock missing from committed source | Local lock exists but is ignored; `git ls-tree HEAD native/npm/` lists only package.json. Include the reviewed lock and prove source-only input closure. | OPEN |
| TLS hostname rejection ineffective | Real `openssl x509 -checkhost unrelated.invalid` reported mismatch with exit 0. Use hostname-aware chain verification and negative coverage. | OPEN |
| Kubernetes loopback authority check too broad | Mocked target guard accepted `https://127.0.0.1:6443@outside.invalid:443`; URL authority is remote. Require strict actual authority validation. | OPEN |
| Full host firewall order/protocol coverage | Supplied host report confirms early UFW multicast acceptance and broader libvirt DNS/DHCP acceptance before the bridge deny. See dated review below; repair and paired protocol/reboot evidence remain required. | CONFIRMED POLICY DEFECTS |
| Duplicate managed guest CA roots | Both orchestration/workspace destinations exist with the same certificate. Consolidate ownership and safely converge the exact legacy duplicate. | OPEN |
| Transitional source/workflow/helper duplication | Mint retirement is operator-confirmed; remove obsolete active guidance and duplicate implementations with their consumers accounted for. | OPEN |
| Final host Docker retirement discrepancy | Supplied report shows inactive/disabled Docker units but retained bridge, rules in both backends and helper/drop-in files. Complete and independently verify the intended D.3 state without restarting Docker. | OPEN |

Review checks passed: 12 workspace native unit tests, 11 orchestration preflight
fixtures, manifest/environment checks, changed-shell Bash/ShellCheck, diff
checks and read-only live native preflight. These results do not negate the
reproduced defects or constitute the new host audit.

Implementation is owned by the
[security review remediation plan](agent-vm-security-review-remediation-plan.md).
The [host audit runbook](../runbooks/host-isolation-audit.md) and read-only
collector are available for human host execution. Collector fixture success
does not mean the live host has been inspected. Record additional audit results
here with explicit attribution after privately reviewed evidence arrives.

### Host Report Review — 2026-10-05

Source: operator-supplied `candidate-report.md`, collected at
`2026-10-05T16:58:47.449548+00:00`; SHA-256
`0ab72f8421b930d166f48ae8ef42c412dd92033951c0e4d23699b2f737af6c34`.
This is an agent review of supplied evidence, not direct agent access to the
personal host. No active packet probes or host changes occurred in this review.

Findings:

- **P1 — VM input denial is too late for multicast.** Both live rules and
  persistent UFW before-rules accept mDNS/SSDP before the user-input chain that
  contains the bridge deny. IPv4 allows UDP to the mDNS and SSDP multicast
  groups on ports 5353/1900 without an ingress-interface restriction; IPv6 has
  corresponding earlier accepts. Avahi listens on IPv4/IPv6 wildcard port 5353.
  This proves the firewall policy allows these paths, not that a particular
  guest packet reached Avahi or exploited it. Multicast membership/interface
  delivery and post-repair denial require paired fixtures.
- **P2 — Libvirt bypasses the intended DNS/DHCP scope.** INPUT reaches
  `LIBVIRT_INP` before UFW. That chain accepts guest-bridge TCP/UDP destination
  ports 53 and 67 on any host destination, before UFW's gateway-only DNS and
  UDP client-port-constrained DHCP rules. No matching early restrictive chain
  appears in the supplied nft/legacy input paths. This is broader firewall
  permission, not proof that every corresponding application listener responds.
- **P2 — Final retirement is not established.** Docker service/socket are
  loaded, inactive and disabled, but `docker0`, nft and legacy Docker rules,
  `agent-vm-docker-isolation` and `agent-vm-isolation.conf` remain. D.3 requires
  those remnants absent after the final reboot. The package query returned a
  nonzero exit with its partial output withheld; package absence cannot be
  inferred. UFW's hook contents also remain private-only. Preserve the earlier
  attestation as history; reconcile this contradictory snapshot before claiming
  independently verified retirement. Containerd needs consumer discovery,
  not automatic removal.

Positive evidence: the running VM uses the selected NAT network, its live
AppArmor label is enforcing in both libvirt info and process labels, UFW is
active/enabled with root-owned non-writable policy files, and app HTTPS/VNC
listeners bind to loopback. The captured device summaries show no filesystem
or host-device passthrough. A QEMU guest-agent channel exists but is reported
disconnected; it is not a demonstrated host escape. Empty persistent security
labels alone do not contradict live dynamic AppArmor enforcement.

The repair must constrain VM-originated host input independently of earlier
generic UFW/libvirt accepts, preserving only reviewed DNS/DHCP, required IPv6
control traffic and legitimate host-initiated replies. Merely adding another
`ufw deny` user rule or changing only UFW's before-chain cannot close both
ordering defects. Review host IPv6 tap/bridge ingress applicability as well;
an absent routed IPv6 network is not proof of absent link-local access. Keep
host policy changes human-owned, persistent and narrow; do not flush tables,
revive host Docker or change unrelated LAN/VPN policy.

Remaining proof: concrete reviewed host repair, applicable paired TCP/UDP/
multicast IPv4/IPv6 positives and denials with counters/ingress evidence,
post-reboot persistence, continued DNS/HTTPS/SSH/Git/app functionality, and
retirement inventory. Existing multicast counters are host-wide and do not
attribute traffic to this VM. No independent host-isolation PASS is recorded.

Collector follow-up: the supplied report reveals incomplete redaction of
iptables comments and shortened bridge MAC identifiers, and over-redaction of
a subnet mask. Its partial package output handling also limits retirement
review. Fix these narrowly with representative offline fixtures before another
collection. The report is currently Git-tracked; privately review publication
scope before sending it to an external remote. No report or Git history was
removed or rewritten by the agent.

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
- Mint Docker retirement: `PENDING until Checkpoint D`
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
