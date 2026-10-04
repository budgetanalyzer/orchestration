# Agent Host Isolation Acceptance Record

**Status:** Operator preparation Steps 1–5 and the Initial Handoff were
completed and verified by the operator on 2026-10-03. Checkpoint A repository,
credential, TLS, bootstrap, stack-health and agent-restart checks were completed
on 2026-10-04; its Java and frontend live-update checks are explicitly deferred
to Checkpoint B. Checkpoints A–C therefore remain pending final acceptance.

This record contains redacted acceptance evidence for the development VM host
isolation work. Keep repository references to basenames. Do not add private
remote URLs, absolute personal-host paths, credentials, private keys,
certificate private-key contents, browser state, full firewall dumps, MAC
addresses or unrelated host configuration.

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
- Guest reboot persistence: `PENDING until Checkpoint B`
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
- Final 443 loopback binding: `PENDING until Checkpoint B`
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

- Java Remote SSH live-update smoke edit: `NOT TESTED - deferred to Checkpoint B`.
- Frontend Remote SSH live-update smoke edit:
  `NOT TESTED - deferred to Checkpoint B`.
- Guest agent-container lifecycle helpers:
  `IMPLEMENTED in the original partial Phase 3 - fixture results recorded in
  workspace docs/host-isolation.md; tracked verifier and direct guest proof
  pending continuation Phase 1; live helper acceptance pending Checkpoint B`.
- Host/VM restart persistence, host loopback port 443, trusted browser behavior
  and the final daily workflow remain `PENDING Checkpoint B`.

The [VM continuation plan](agent-host-isolation-vm-continuation-plan.md) replaces
the stopped Mint-hosted execution after its manual handoff. Neither Checkpoint
A nor Checkpoint B may be marked fully accepted until both named live-update
smoke edits pass. Original phase numbers below describe historical results.

## VM Continuation Handoff

**Status:** `PENDING operator H.1–H.4`; creating the continuation plan does not
complete its prerequisites. Follow the
[manual handoff](agent-host-isolation-manual-plan.md#continuation-handoff-start-the-vm-execution-plan)
and replace pending entries only with actual results. Earlier bare firewall
PASS summaries need the detailed paired evidence specified in H.2.

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
