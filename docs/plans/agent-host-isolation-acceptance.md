# Agent Host Isolation Acceptance Record

**Status:** Operator preparation Steps 1–5 and the Initial Handoff were
completed and verified by the operator on 2026-10-03. The post-implementation
Checkpoints A–C remain pending.

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
- Selected repository basenames: `orchestration`, `budget-analyzer-web`,
  `ext-authz`, `session-gateway`, `service-common`, `workspace`,
  `currency-service`, `permission-service`, `transaction-service`
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
