# Development VM Manual Setup Plan

**Status:** Ready for operator preparation; no host changes have been made.

**Audience:** The human operating the personal Linux Mint workstation.

**Companion:** [Agent implementation plan](agent-host-isolation-plan.md).

This is a manual checklist, not an AI Session Handler execution plan. Complete
Steps 1–5 before agent implementation. Two checkpoints remain afterward: run
the reviewed one-time repository setup and bootstrap the guest, then accept the
browser and daily Git workflow. Agents may prepare instructions; they do not
administer your host or push to GitHub.

## Selected setup

| Item | Choice |
| --- | --- |
| Personal host | Linux Mint 22.1 MATE, Intel i7-12700H, 64 GB RAM, reported 1.2 TB disk |
| Virtualization | KVM/QEMU, libvirt and virt-manager |
| Guest | Ubuntu Server 24.04 LTS, x86-64 |
| Initial resources | 8 vCPUs, 24 GiB RAM, 200 GiB sparse guest disk; verify actual free space |
| Source files | Guest-local bare repositories and working clones; no shared host workspace |
| Editor | Native host VS Code UI using Remote SSH; execution and files remain in guest |
| Browser | Dedicated development profile on the personal host |
| Runtime | One guest Docker daemon; packaged agent container retained initially |
| Repository transfer | Explicit host-initiated Git push/fetch over SSH through a `vm` remote |
| GitHub authority | Host only; no guest GitHub write credential or authenticated GitHub browser |
| Browser URL | `https://app.budgetanalyzer.localhost`, through host-loopback forwarding |

The implementation plan owns the boundary and exclusions. This checklist owns
manual preparation and handoffs. It does not introduce shared folders, rsync,
an agent-controlled fork, daily publication automation or routine source
copying outside Git.

## Step 1: Preserve Work And Check The Host

- [ ] Back up important host repositories, including uncommitted and untracked
  work. Keep the old Docker/Kind environment and data until acceptance; record
  how to stop it and release ingress ports without deleting it.
- [ ] Confirm free RAM/disk, hardware virtualization and the current firewall
  manager. Run these read-only commands on **Mint**, not in a container:

```bash
lscpu
free -h
df -h .
sudo ufw status verbose
sudo nft list ruleset
```

- [ ] Confirm each ecosystem repository that should enter the VM is an immediate
  child of one common parent, has a local `main` branch and has no operation in
  progress. Private repositories remain on the host until the reviewed setup
  script transfers committed Git objects to the VM.
- [ ] Decide which current checked-out branch, if different from `main`, should
  be seeded for each repository. The setup script will print the discovered set
  and require confirmation; move unrelated repositories outside the selected
  parent or decline the run.

If required, enable Intel virtualization in firmware. Ordinary Docker/Kind in
the VM needs no nested virtualization.

## Step 2: Install And Create The VM

- [ ] Install distribution packages on Mint using its normal package manager:

```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager
```

- [ ] Verify the libvirt service and access in virt-manager. Follow the packaged
  authorization flow; if the user needs libvirt group membership, add it and
  log out/in. Keep host libvirt access out of the guest.
- [ ] Obtain an official Ubuntu Server 24.04 LTS image and verify its published
  checksum/signature. Create a named VM in virt-manager with the resources above,
  a private NAT network and a guest disk outside all host repository directories.
  Choose a subnet that does not conflict with Docker, Kind or a VPN.
- [ ] Install the guest OS, security updates, Git and OpenSSH server. Use the
  console initially. Keep the guest account separate from personal credentials.
- [ ] Keep normal QEMU/AppArmor confinement active. Do not add shared folders,
  home-directory mounts, shared clipboard, drag-and-drop, device passthrough,
  SSH/GPG agents, credential helpers or browser-profile integration.

Use [Ubuntu's libvirt guide](https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/)
and [virt-manager](https://virt-manager.org/) for platform-specific installation
details. Do not disable confinement to fix a permission issue.

## Step 3: Prepare Guest Storage And Host-Initiated Git Access

- [ ] Choose a guest-local root with separate locations for bare repositories,
  working clones, Docker data and build caches. Record the root for Phase 2; do
  not hardcode a personal path in checked-in configuration.
- [ ] Verify the guest disk has enough space for full Git history, working trees,
  dependencies, images, Kind nodes, persistent volumes and test containers.
- [ ] Create a dedicated host-to-guest SSH key if desired. Its private key stays
  on the host; only its public key enters the guest. Create a dedicated SSH host
  alias for repository setup and daily Git transfer with agent, X11 and automatic
  forwarding disabled and normal host-key checking preserved.
- [ ] Confirm the host can initiate SSH to the guest with that alias. Do not
  configure a reverse connection, mount the host SSH directory or log the guest
  into GitHub.
- [ ] Prepare a separate VS Code Remote SSH profile. Keep GitHub authentication,
  Settings Sync secrets and GitHub-writing extensions out of the remote extension
  host. Disable automatic port forwarding. The UI may run on Mint; workspace
  files, terminals, tasks, language servers and workspace extensions run in the
  guest.

Do not create the ecosystem bare/working repository pairs manually. Phase 2
provides the reviewed one-time script that discovers and prepares all selected
repositories consistently. Until Checkpoint A, record only the guest root and
SSH alias it will use.

## Step 4: Block Guest-Initiated Access To Host Services

- [ ] Establish persistent rules with the existing host firewall manager.
  Identify the VM-facing interface/network; match that traffic rather than only
  a guest source IP. Integrate with libvirt's rules without flushing Docker,
  libvirt or the rest of the host firewall.

| Traffic | Required behavior |
| --- | --- |
| New host-to-guest connections | Permit operator SSH, Git transfer and application access |
| Replies to host-initiated connections | Permit established reply traffic |
| New guest-to-personal-host connections | Deny across all host addresses, IPv4 and IPv6 |
| Guest DNS/DHCP to host, if used | Permit only the required service/address/interface |
| Guest Internet traffic | Preserve ordinary outbound access and replies |

- [ ] Preserve required VM-link network control, including IPv6 neighbor
  discovery when IPv6 is enabled, without opening host application listeners.
- [ ] Account for host bridge, LAN/VPN and other local addresses, including IPv6
  link-local addresses. These are host destinations; this plan does not add a
  separate policy restricting other LAN/VPN devices. Do not assume NAT provides
  host-access protection.
- [ ] Use a temporary dummy TCP listener on an otherwise unused host port with
  no personal data. Confirm it is healthy from the host, then prove guest
  connections are denied against relevant host IPv4/IPv6 addresses. Confirm
  guest DNS/downloads and host-to-guest SSH still work.
- [ ] Reboot the guest and confirm persistent policy. Repeat the boundary check
  after a host reboot when practical before final acceptance.

Exact firewall commands depend on active UFW/nftables/libvirt configuration.
If assistance is needed, provide only a sanitized description. Do not paste a
generic ruleset, disable the firewall or claim success without positive and
negative checks.

## Step 5: Prepare Browser Forwarding And TLS Transfer

- [ ] Choose a persistent host-loopback forward for port 443 to guest loopback
  port 443 through SSH or an equivalent host-managed connection. Binding host
  port 443 needs an appropriate host service/privilege arrangement. Bind only
  loopback and fail visibly if the port is occupied.
- [ ] Verify forwarding with a temporary guest fixture before app startup. Do
  not replace the application with HTTP or bypass HTTPS verification. Stop the
  old ingress only when necessary to test the real port; retain its data.
- [ ] Keep `app.budgetanalyzer.localhost` resolving to host loopback. `/etc/hosts`
  does not itself forward traffic. Kubernetes, Docker and observability get no
  host or LAN exposure.
- [ ] Locate the existing development leaf certificate/key and published public
  root using `docs/development/local-environment.md`. Confirm they are current.
  Keep the host mkcert signing key outside the guest.
- [ ] Plan a human-operated `scp` or equivalent transfer of only the approved
  leaf certificate/key and public root into their documented guest locations
  during Checkpoint A. Git transport will not carry ignored certificate files.
  If renewal is needed, use the host-owned TLS workflow first.
- [ ] Create a dedicated host browser profile containing only development app
  identities. Do not expose its profile, debugging endpoint or GitHub session to
  the guest.

## Initial Handoff

- [ ] Record the VM name, guest release, resources and installed QEMU/libvirt
  versions.
- [ ] Record the guest storage root and free space, host-to-guest SSH alias,
  host-key verification, forwarding exclusions and Remote SSH profile behavior.
- [ ] Record the selected host repository parent and repository names, but omit
  private remote URLs, credentials, personal paths and unrelated repositories.
- [ ] Record VM network/interface, guest address, DNS/DHCP exceptions,
  IPv4/IPv6 host-denial results and persistence. Record LAN/VPN peer reachability
  as outside this plan's guarantee, not as an untested denial claim.
- [ ] Record browser-forwarding instructions, current TLS validity and port
  conflicts. Preserve trusted VM, firewall, SSH and forwarding settings in
  host-owned storage outside the guest.

Provide a redacted handoff for
`docs/plans/agent-host-isolation-acceptance.md` during Phase 1. Do not include
credentials, private keys, browser state or unrelated host configuration.

**Handoff:** Run implementation Phases 1–2 only. They prepare guest
configuration, `scripts/setup-agent-vm-repositories.sh`, and exact bootstrap
commands. Do not reopen the existing workspace devcontainer in the guest
unchanged; it would bring back DinD and the old mount assumptions.

## Checkpoint A: Set Up Repositories And Bootstrap The Guest

This happens **after implementation Phase 2**, not during initial VM creation.

- [ ] Review the Phase 1 bootstrap changes, Phase 2 workspace configuration and
  every line of `scripts/setup-agent-vm-repositories.sh`. Run the script from a
  human-operated host terminal with the selected parent, SSH alias and guest
  root. Confirm its printed repository set before proceeding.
- [ ] For every selected repository, confirm the host has a `vm` remote pointing
  to the intended guest bare repository; the guest has a bare repository and a
  working clone; and the working clone's only `origin` is guest-local. Confirm
  initial `main` and any distinct current branch arrived without force, hooks,
  host Git configuration or credentials.
- [ ] Perform one disposable round trip without GitHub: create/push a temporary
  host branch to `vm`, fetch/switch it in the guest working clone, add a harmless
  commit, push to the guest-local `origin`, fetch it from `vm` on the host and
  fast-forward with `--ff-only`. Delete only that fixture after recording proof.
- [ ] Confirm the guest has no GitHub write key/token, forwarded `SSH_AUTH_SOCK`,
  host credential helper, authenticated GitHub CLI/browser session or GitHub
  remote in its working clones. Do not test this by entering host credentials.
- [ ] Transfer only the reviewed development leaf certificate/key and public CA
  from host to guest. Run documented validation; never transfer the mkcert
  signing key or bypass verification.
- [ ] Install guest prerequisites from a human-operated guest terminal. Verify
  Java/Node/npm and all working clones, including `ext-authz`; install frontend
  dependencies through normal owner workflows.
- [ ] Run the prepared orchestration guest bootstrap outside the agent container,
  selecting certificate reuse. This recreates the **guest** Kind cluster.
  Generate required infrastructure TLS as the human operator in the guest and
  configure development-only `.env` credentials.
- [ ] Start Tilt in the guest and launch the reviewed agent container against
  the guest daemon. Supply only dedicated agent/development credentials. Confirm
  container, Docker, Kind and guest HTTPS availability; rebuild/restart the agent
  once and confirm Kind networking survives.
- [ ] Open the guest workspace with the dedicated VS Code Remote SSH profile.
  Make and restore disposable Java/frontend verification edits while Tilt runs;
  capture live-update results without modifying the host clones.
- [ ] Complete dummy-listener checks across a VM restart with positive controls,
  then restart guest Tilt/agent. Supply all results to Phases 3 and 6.

**Handoff:** Run implementation Phases 3–6 from the guest environment. Use
Remote SSH for guest-local source; do not mount or edit the host clones from the
agent container.

## Checkpoint B: Accept Browser And Daily Git Workflow

This happens **after implementation Phase 6** has passed guest validation.

- [ ] Stop old runtime components as needed to release host ports. Disable
  automatic restart of the old privileged DinD container. Preserve the old
  cluster and volumes until the migration is accepted.
- [ ] Start the reviewed HTTPS forward and open
  `https://app.budgetanalyzer.localhost` in the dedicated host browser profile.
  Confirm trusted TLS, development login/logout, application requests and
  frontend WebSocket updates.
- [ ] Exercise the documented daily Git flow on a disposable branch: host
  `main` update and feature-branch push to `vm`; guest fetch/switch, commit and
  local-origin push; host fetch and `--ff-only` merge. Do not push the fixture to
  GitHub. Confirm commit history and additions/deletions survive.
- [ ] Save Java and frontend changes through Remote SSH; confirm guest live
  update and restore the fixture without resetting unrelated work.
- [ ] Confirm host-service denial survives VM/host restart, forwarding remains
  loopback-only and no personal credential forwarding appeared.
- [ ] Record acceptance, measured resource use, known limitations and daily
  start/stop/Git commands. Send results for the acceptance record; until then
  cutover remains pending even if guest tests pass.

Daily use starts the VM, guest Tilt/agent, Remote SSH editor and HTTPS forward.
For a task, the host updates `main`, creates a feature branch and explicitly
pushes it to `vm`; the guest agent commits and pushes only to its guest-local
bare `origin`; the host fetches and fast-forwards, then separately reviews,
pushes to GitHub and creates the PR. Do not rerun the one-time repository setup,
`setup.sh`, certificate generation or any source synchronization for ordinary
daily work.
