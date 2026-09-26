# Development VM Manual Setup Plan

**Status:** Ready for operator preparation; no host changes have been made.

**Audience:** The human operating the personal Linux Mint workstation.

**Companion:** [Agent implementation plan](agent-host-isolation-plan.md).

This is a manual checklist, not an AI Session Handler execution plan. Complete
Steps 1–5 before agent implementation. Two checkpoints remain afterward: run
the reviewed one-time repository setup and bootstrap the guest, then accept the
browser and daily Git workflow. Agents may prepare instructions; they do not
administer your host or push to GitHub.

## How To Use This Checklist

Run commands only in the environment named immediately above the code block:

- **Mint host terminal** means a normal terminal opened from the Linux Mint
  desktop, not VS Code's devcontainer terminal.
- **Guest console** means virt-manager's console for the new VM.
- **Guest SSH session** means a terminal reached through the dedicated SSH
  alias created in Step 3.

Do not copy a leading `$` or substitute commands from an agent container. A
checkbox is complete only when its stated success evidence is visible. Save a
redacted text record of command versions, resource values, interface names and
pass/fail results; do not record passwords, private keys, tokens, certificate
private-key contents or private remote URLs.

Use these names unless there is a collision. The subnet is deliberately not
preselected; Step 2 requires checking active host routes first.

```text
VM name:                 budget-analyzer-agent
libvirt connection:     qemu:///system
libvirt network name:   agent-nat
libvirt storage pool:   agent-vm-images
guest hostname:         budget-analyzer-agent
SSH alias:              budget-agent-vm
forwarding SSH alias:   budget-agent-vm-forward
```

Stop at the relevant step instead of improvising if a command reports an
unexpected hypervisor, an overlapping subnet, an unverified installer image, a
disk under a repository path, disabled confinement or an active port conflict.

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
  work. A remote branch is not a backup of uncommitted files. For every
  repository that will enter the VM, run the following from its host checkout
  and review the output:

**Mint host terminal:**

```bash
git status --short
git branch --show-current
git rev-parse --show-toplevel
```

  Save or back up anything reported by `git status --short`. Success means the
  backup can be located without using the future VM and the intended seed
  branch is named in the handoff.

- [ ] Inventory the old local runtime without deleting it. Record the commands
  that stop it and release ports 80/443, but do not run destructive Docker,
  Kind or volume-removal commands.

**Mint host terminal:**

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
kind get clusters
sudo ss -ltnp '( sport = :80 or sport = :443 )'
```

  Success means the handoff identifies what currently owns ports 80 and 443,
  how to stop that component without deleting its data, and whether the old
  Kind cluster is still present.

- [ ] Confirm free RAM/disk, hardware virtualization and the current firewall
  manager. Run these read-only commands on Mint:

```bash
lscpu
free -h
df -h .
df -h /var/lib/libvirt/images 2>/dev/null || true
test -c /dev/kvm && ls -l /dev/kvm
lsmod | grep -E '^kvm'
sudo ufw status verbose
sudo nft list ruleset
```

  Confirm all of the following before continuing:

  - `lscpu` reports virtualization support (`VT-x`) and does not report that
    virtualization is disabled.
  - `/dev/kvm` exists and a `kvm_intel` or equivalent KVM module is loaded.
  - At least 24 GiB plus several GiB for Mint remains available while the VM is
    running. Do not allocate the VM if doing so would force the host into swap
    during normal use.
  - The filesystem that will hold `/var/lib/libvirt/images` can accommodate a
    sparse disk that may grow to 200 GiB. Sparse allocation does not reserve
    that free space.
  - The handoff says whether UFW is active and whether another nftables manager
    owns persistent rules. Do not enable, disable or flush either one yet.

- [ ] Confirm each ecosystem repository that should enter the VM is an immediate
  child of one common parent, has a local `main` branch and has no operation in
  progress. For each selected repository, run:

**Mint host terminal, from each selected repository:**

```bash
git show-ref --verify --quiet refs/heads/main
git status --porcelain=v1
test ! -e "$(git rev-parse --git-path MERGE_HEAD)"
test ! -d "$(git rev-parse --git-path rebase-merge)"
test ! -d "$(git rev-parse --git-path rebase-apply)"
```

  `git show-ref` must exit zero, `git status --porcelain=v1` must be empty by
  the time Checkpoint A runs, and no merge/rebase operation may be active.
  Private repositories remain on the host until the reviewed setup script
  transfers committed Git objects to the VM.
- [ ] Decide which current checked-out branch, if different from `main`, should
  be seeded for each repository. The setup script will print the discovered set
  and require confirmation; move unrelated repositories outside the selected
  parent or decline the run.

**Step 1 succeeds when:** work is backed up; the old runtime remains recoverable;
hardware virtualization is usable; RAM and disk are sufficient; the active
firewall owner is known; and the selected parent, repositories and seed branches
are recorded. If KVM is unavailable, stop and enable Intel virtualization in
firmware. Ordinary Docker/Kind inside this VM needs no nested virtualization.

## Step 2: Install And Create The VM

### 2.1 Install And Validate KVM/libvirt

- [ ] Install the distribution packages on Mint:

**Mint host terminal:**

```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager ovmf \
  gnupg ripgrep shellcheck
```

- [ ] Start the packaged libvirt system service and run its host validator:

**Mint host terminal:**

```bash
sudo systemctl enable --now libvirtd
systemctl is-active libvirtd
systemctl is-enabled libvirtd
sudo virt-host-validate qemu
virsh --connect qemu:///system list --all
```

  Success means both `systemctl` commands print `active`/`enabled`, the QEMU
  hardware-virtualization, `/dev/kvm` existence/access and QEMU security-model
  checks in `virt-host-validate` pass, and `virsh` prints a domain table instead
  of a permission or connection error. IOMMU or secure-guest warnings are not
  blockers because this VM uses neither device passthrough nor confidential-VM
  features; do not dismiss a KVM, QEMU or confinement failure as optional.

- [ ] Open **Menu → Administration → Virtual Machine Manager**. In virt-manager:

  1. Select **File → Add Connection** if no connection is shown.
  2. Choose **QEMU/KVM** as the hypervisor.
  3. Select **System** rather than **User session** (the resulting URI is
     `qemu:///system`).
  4. Leave remote connection disabled and select **Connect**.
  5. Verify the connection row says **QEMU/KVM** and is connected.

  If PolicyKit prompts for the current Mint user's password, use that packaged
  authorization flow. If `virsh` or virt-manager instead reports that the user
  is not authorized, run the following once, then log out of the entire Mint
  desktop session and log back in; opening a new terminal alone is insufficient:

**Mint host terminal, only after an authorization failure:**

```bash
sudo usermod -aG libvirt "$USER"
```

**Mint host terminal, after desktop logout/login:**

```bash
id -nG | tr ' ' '\n' | rg '^libvirt$'
virsh --connect qemu:///system list --all
```

  Do not add a libvirt socket, group, client or connection inside the guest.

### 2.2 Download And Verify Ubuntu Server

- [ ] In a host browser, open the official
  [Ubuntu 24.04 LTS release directory](https://releases.ubuntu.com/24.04/).
  Download all three files from the same directory:

  1. the current `ubuntu-24.04...-live-server-amd64.iso`;
  2. `SHA256SUMS`; and
  3. `SHA256SUMS.gpg`.

  Do not use a search-result mirror, a daily build, a desktop ISO or a file for
  another CPU architecture.

- [ ] Put the three files in one otherwise empty directory, then verify the
  signature and ISO checksum. The Ubuntu CD Image signing key fingerprint is
  `8439 38DF 228D 22F7 B374 2BC0 D94A A3F0 EFE2 1092`; independently compare it
  with Ubuntu's current
  [image-verification instructions](https://ubuntu.com/tutorials/how-to-verify-ubuntu)
  before trusting it.

**Mint host terminal:**

```bash
mkdir -p "$HOME/Downloads/ubuntu-24.04-server-verify"
cd "$HOME/Downloads/ubuntu-24.04-server-verify"
ls -1
gpg --keyserver hkps://keyserver.ubuntu.com \
  --recv-keys D94AA3F0EFE21092
gpg --keyid-format long --fingerprint D94AA3F0EFE21092
gpg --keyid-format long --verify SHA256SUMS.gpg SHA256SUMS
sha256sum --ignore-missing -c SHA256SUMS
sha256sum ubuntu-24.04*-live-server-amd64.iso
```

  Success requires all of the following:

  - `ls` shows one server AMD64 ISO plus the two checksum files.
  - The displayed fingerprint exactly matches the fingerprint above and the
    current official Ubuntu instructions.
  - GPG reports a **Good signature** made by the Ubuntu CD Image signing key.
    A warning that the key is not personally certified is expected; a bad or
    missing signature is not.
  - `sha256sum` prints the exact downloaded ISO filename followed by `OK`.

  Stop and delete the download if any check fails. Record the ISO filename and
  the computed hash, not the signature key's trust database.

### 2.3 Select And Create A Non-Overlapping NAT Network

- [ ] Inventory every currently active host, Docker, libvirt and VPN route:

**Mint host terminal:**

```bash
ip -4 route show table all
ip -6 route show table all
nmcli connection show --active
docker network ls
docker network inspect $(docker network ls -q) \
  --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}'
virsh --connect qemu:///system net-list --all
```

  If Docker has no networks, its inspect command may print its usage text; that
  does not invalidate the other checks.

- [ ] Choose one unused RFC1918 `/24` for the dedicated VM network. For example,
  `192.168.231.0/24` is acceptable only if no route, Docker/Kind network,
  libvirt network or VPN route contains or overlaps it. Record the selected
  network, gateway (normally `.1`) and DHCP range. Recheck after connecting any
  VPN used during development.

- [ ] In virt-manager, create the network:

  1. Select the `qemu:///system` connection.
  2. Open **Edit → Connection Details → Virtual Networks**.
  3. Select **+** to add a network and name it `agent-nat`.
  4. Choose **NAT** forwarding, not routed, open or isolated mode.
  5. Enter the selected IPv4 `/24`, enable DHCP and choose a DHCP range inside
     that subnet that excludes the `.1` gateway.
  6. Do not define an IPv6 subnet. Step 4 still blocks IPv6 link-local access.
  7. Finish, start the network and enable **Autostart on boot**.

  Labels vary slightly by virt-manager version. Stop if the wizard does not
  clearly show NAT, IPv4 subnet, DHCP and autostart rather than guessing.

**Mint host terminal:**

```bash
virsh --connect qemu:///system net-info agent-nat
virsh --connect qemu:///system net-dumpxml agent-nat
```

  Success means `net-info` reports `Active: yes`, `Autostart: yes` and a named
  bridge; the XML shows the selected IPv4 subnet and `<forward mode='nat'/>`.

### 2.4 Create The VM In virt-manager

- [ ] Create a dedicated system storage pool before creating the VM:

  1. Select the `qemu:///system` connection.
  2. Open **Edit → Connection Details → Storage**.
  3. Select **+**, name the pool `agent-vm-images`, choose a **dir: Filesystem
     Directory** pool and set its target to
     `/var/lib/libvirt/images/agent-vm-images`.
  4. Finish, start the pool and enable **Autostart on boot**.

**Mint host terminal:**

```bash
virsh --connect qemu:///system pool-info agent-vm-images
virsh --connect qemu:///system pool-path agent-vm-images
```

  Success means the pool is active, autostarts and its canonical path is exactly
  `/var/lib/libvirt/images/agent-vm-images`, outside all repository trees.

- [ ] Copy the already verified public installer ISO into that pool so normal
  libvirt/AppArmor access applies. Replace `<iso-filename>` with the exact file
  that passed Step 2.2:

**Mint host terminal:**

```bash
sudo install -o root -g root -m 0644 \
  "$HOME/Downloads/ubuntu-24.04-server-verify/<iso-filename>" \
  /var/lib/libvirt/images/agent-vm-images/
virsh --connect qemu:///system pool-refresh agent-vm-images
virsh --connect qemu:///system vol-list agent-vm-images
```

  The volume list must show the ISO. Do not loosen home-directory permissions or
  disable AppArmor to make a system VM read an ISO from `Downloads`.

- [ ] In virt-manager, select **File → New Virtual Machine** and perform these
  actions in order:

  1. Select **Local install media (ISO image or CDROM)**.
  2. Select **Browse**, open the `agent-vm-images` storage pool, choose the
     verified server ISO and verify the detected operating system is Ubuntu
     24.04 LTS. Manually select it if detection is blank; do not choose a
     different release.
  3. Set memory to `24576 MiB` and CPUs to `8`.
  4. Create a `200 GiB` disk in the `agent-vm-images` storage pool. Use
     `qcow2`/sparse allocation. Do not browse to a home directory, repository
     parent, mounted host workspace or removable disk.
  5. Name the VM `budget-analyzer-agent` and select **Customize configuration
     before install**.
  6. In **NIC**, choose **Virtual network 'agent-nat': NAT** and the virtio
     device model. Do not use a host bridge, macvtap or direct attachment.
  7. Keep the normal QEMU emulator, UEFI firmware and virtio disk defaults. Do
     not enable nested virtualization.
  8. Use a local-only VNC display for the installation console. Remove USB
     redirection devices and any SPICE WebDAV channel. Do not add Filesystem,
     Host device, USB host device, PCI host device, TPM passthrough or smartcard
     hardware.
  9. Select **Begin Installation**.

- [ ] While the installer is running, verify the disk location from another
  host terminal:

**Mint host terminal:**

```bash
virsh --connect qemu:///system domblklist budget-analyzer-agent --details
virsh --connect qemu:///system dumpxml budget-analyzer-agent | \
  rg -n "<source file=|<filesystem|<hostdev|<redirdev|spice-space.webdav"
```

  The disk source must be below
  `/var/lib/libvirt/images/agent-vm-images` and outside every repository
  directory. The search must show the disk source and no `<filesystem>`,
  `<hostdev>`, `<redirdev>` or SPICE WebDAV device. Shut down and correct the
  hardware before OS setup if it does not.

### 2.5 Install And Update The Guest

- [ ] Complete the Ubuntu installer from virt-manager's console:

  1. Choose the required language and keyboard layout.
  2. Choose the standard **Ubuntu Server** installation, not a minimized or
     third-party image.
  3. Confirm the virtio NIC receives DHCP on the selected `agent-nat` subnet.
  4. Leave the proxy blank unless the workstation genuinely requires one; keep
     the default official Ubuntu archive mirror.
  5. Use the entire 200 GiB virtual disk with LVM. Confirm that only the virtual
     disk is listed. On the storage summary, edit the root logical volume to use
     the remaining free volume-group space rather than accepting an automatic
     cap near 100 GiB. Do not attach or select a host disk.
  6. Set hostname `budget-analyzer-agent`. Create a guest-only operator account
     with a unique password not reused by Mint, GitHub or any personal service.
     Do not use a personal email address as the account identity.
  7. Enable **Install OpenSSH server**. Do not import an SSH identity from
     GitHub or Launchpad.
  8. Select no featured server snaps. Finish installation, reboot and allow
     virt-manager to disconnect the ISO when prompted.

- [ ] Log in through the virt-manager console first and install updates and the
  minimal Step 2 tools:

**Guest console:**

```bash
sudo apt update
sudo apt full-upgrade
sudo apt install git openssh-server ca-certificates curl netcat-openbsd ripgrep
sudo systemctl enable --now ssh
test -f /var/run/reboot-required && sudo reboot || true
```

  After any reboot, log in at the console again and run:

**Guest console:**

```bash
hostnamectl
cat /etc/os-release
git --version
systemctl is-active ssh
ip -4 address show
ip route
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
df -h /
```

  Success means the hostname is `budget-analyzer-agent`, the release is Ubuntu
  24.04 LTS, SSH is active, the guest has an address on `agent-nat`, its default
  route uses that network, and the root filesystem reflects the virtual disk.

- [ ] Reserve a stable guest address so the SSH aliases do not silently point at
  a different DHCP client later. Choose an unused address in the selected subnet
  but outside the dynamic DHCP range, replace `<reserved-guest-ip>`, and run:

**Mint host terminal:**

```bash
GUEST_MAC="$(virsh --connect qemu:///system domiflist budget-analyzer-agent | awk '$3 == "agent-nat" {print $5}')"
RESERVED_GUEST_IP='<reserved-guest-ip>'
printf 'MAC=%s reserved IP=%s\n' "$GUEST_MAC" "$RESERVED_GUEST_IP"
virsh --connect qemu:///system net-update agent-nat add-last ip-dhcp-host \
  "<host mac='$GUEST_MAC' name='budget-analyzer-agent' ip='$RESERVED_GUEST_IP'/>" \
  --live --config
virsh --connect qemu:///system net-dumpxml agent-nat
```

  Reboot the guest from its console, then require `hostname -I` and
  `virsh --connect qemu:///system net-dhcp-leases agent-nat` to show the reserved
  address. Stop if the MAC was empty, the address was already in use or the guest
  receives another address.

### 2.6 Prove Confinement And The Absence Of Host Integration

- [ ] With the VM running, perform these read-only host checks:

**Mint host terminal:**

```bash
sudo aa-status
virsh --connect qemu:///system dumpxml budget-analyzer-agent | \
  rg -n "<seclabel|<graphics|<filesystem|<hostdev|<redirdev|spice-space.webdav"
sudo qemu-img info --force-share "$(virsh --connect qemu:///system domblklist budget-analyzer-agent --details | awk '$2 == "disk" {print $4; exit}')"
```

  Success means AppArmor is enabled; the live domain has a dynamic AppArmor
  security label; the display is local-only; no filesystem, host-device, USB
  redirection or SPICE WebDAV entry appears; and the disk format is `qcow2` with
  a 200 GiB virtual size. Do not switch QEMU to an unconfined profile to fix an
  access problem.

- [ ] Confirm from the guest that host authority did not enter it:

**Guest console:**

```bash
test ! -S /var/run/libvirt/libvirt-sock
test ! -S /run/libvirt/libvirt-sock
test -z "${SSH_AUTH_SOCK:-}"
command -v virsh >/dev/null && echo 'unexpected virsh client installed' || true
```

  Both socket tests and the empty-agent test must exit zero, and the final
  command should print nothing. Do not install `spice-vdagent`, a QEMU guest
  agent, credential helpers or host-integration tools. Do not enable shared
  folders, home mounts, shared clipboard, drag-and-drop, device passthrough,
  SSH/GPG agents or browser-profile integration later.

**Step 2 succeeds when:** `qemu:///system` works without an authorization
error; the Ubuntu signature and checksum passed; `agent-nat` is active,
autostarting, NAT-backed and non-overlapping; the VM has exactly the requested
CPU/RAM/disk; Ubuntu and SSH are updated and active; the disk is outside all
repositories; and AppArmor plus the no-integration checks pass. Record the VM,
network, bridge, guest IPv4 address, ISO filename/hash, disk path/format and
QEMU/libvirt versions in the handoff.

Use [Ubuntu's libvirt guide](https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/)
and [virt-manager](https://virt-manager.org/) for platform-specific installation
details. Do not disable confinement to fix a permission issue.

## Step 3: Prepare Guest Storage And Host-Initiated Git Access

### 3.1 Reserve Guest-Local Storage

- [ ] Use `/srv/budget-analyzer` as the guest-local project root unless the VM
  has a separately reviewed guest disk. Create only the parent locations now;
  do not create per-repository bare repositories or working clones before the
  Phase 2 setup script exists.

**Guest console:**

```bash
sudo install -d -o "$USER" -g "$(id -gn)" -m 0750 \
  /srv/budget-analyzer \
  /srv/budget-analyzer/bare \
  /srv/budget-analyzer/worktrees \
  /srv/budget-analyzer/cache
df -h /srv/budget-analyzer /var/lib/docker 2>/dev/null || df -h /srv/budget-analyzer
findmnt --target /srv/budget-analyzer
```

  Record `/srv/budget-analyzer` for implementation Phase 2. Docker's normal
  guest-local data root is `/var/lib/docker`; do not relocate it into a host
  mount. Success means all listed project directories are guest-owned and the
  backing guest filesystem has room for repositories, dependencies, images,
  Kind nodes, persistent volumes and test containers. Treat less than 100 GiB
  free at this point as a stop-and-resize condition, not something sparse
  allocation will solve.

### 3.2 Establish A Dedicated Host-To-Guest SSH Identity

- [ ] Find and record the guest's DHCP address and SSH host-key fingerprint.

**Guest console:**

```bash
hostname -I
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

**Mint host terminal:**

```bash
virsh --connect qemu:///system net-dhcp-leases agent-nat
```

  The address shown by libvirt must match the guest's address and belong to the
  selected subnet. Keep the console-displayed ED25519 fingerprint visible for
  the first SSH connection.

- [ ] Create a key used only for this VM. Accept the proposed filename below;
  use a passphrase stored by the human, but do not add the key to a forwarded
  agent.

**Mint host terminal:**

```bash
ssh-keygen -t ed25519 -a 100 \
  -f "$HOME/.ssh/budget-analyzer-agent-vm" \
  -C 'budget-analyzer-agent host-to-guest'
```

- [ ] Copy only the public key. Replace `<guest-user>` and `<guest-ip>` with the
  guest-only account and DHCP address. At the first-connect prompt, compare the
  displayed ED25519 fingerprint character-for-character with the one read from
  the guest console before answering `yes`.

**Mint host terminal:**

```bash
ssh-copy-id -i "$HOME/.ssh/budget-analyzer-agent-vm.pub" \
  '<guest-user>@<guest-ip>'
```

  After key login works, leave password authentication unchanged until the
  operator has a separately tested recovery route through the console. Do not
  copy a host private key, `known_hosts`, SSH agent socket or `.ssh` directory
  into the guest.

- [ ] Open `~/.ssh/config` on Mint in a host editor and add the following two
  aliases, replacing the two placeholders. The second alias exists only for an
  explicit loopback forward; neither alias permits agent or X11 forwarding.

```sshconfig
Host budget-agent-vm budget-agent-vm-forward
    HostName <guest-ip>
    User <guest-user>
    IdentityFile ~/.ssh/budget-analyzer-agent-vm
    IdentitiesOnly yes
    ForwardAgent no
    ForwardX11 no
    ForwardX11Trusted no
    PermitLocalCommand no
    StrictHostKeyChecking yes
    UserKnownHostsFile ~/.ssh/known_hosts

Host budget-agent-vm
    ExitOnForwardFailure yes

Host budget-agent-vm-forward
    ExitOnForwardFailure yes
```

**Mint host terminal:**

```bash
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/config" "$HOME/.ssh/budget-analyzer-agent-vm"
chmod 644 "$HOME/.ssh/budget-analyzer-agent-vm.pub"
ssh -G budget-agent-vm | rg '^(hostname|user|identityfile|forwardagent|forwardx11) '
ssh budget-agent-vm 'hostname; test -z "${SSH_AUTH_SOCK:-}"'
```

  Success means the resolved host/user/key are the dedicated VM values, both
  forwarding settings are `no`, SSH prints `budget-analyzer-agent`, and the
  remote empty-agent test exits zero. Do not configure a reverse SSH tunnel or
  log the guest into GitHub.

### 3.3 Create A Dedicated VS Code Remote Profile

- [ ] On Mint, install the Microsoft **Remote - SSH** extension in the local VS
  Code UI if it is not already installed. Then:

  1. Select **Manage (gear) → Profiles → Create Profile**.
  2. Create an empty profile named `Budget Analyzer VM`; do not copy Settings
     Sync state or extensions from a personal/GitHub profile.
  3. In that profile, install only **Remote - SSH** locally.
  4. Open Settings, search for `Remote: Auto Forward Ports` and clear it.
  5. Search for `Remote: Restore Forwarded Ports` and clear it.
  6. Run **Remote-SSH: Connect to Host... → budget-agent-vm**.
  7. When connected, open `/srv/budget-analyzer` only to confirm access; do not
     create repositories manually.
  8. In the Extensions view's **SSH: budget-agent-vm** section, do not install
     GitHub Pull Requests, GitHub authentication/publishing, Settings Sync,
     credential-vault or personal-account extensions.
  9. Search the Extensions view for `@builtin GitHub Authentication` and disable
     it for this profile if VS Code offers a profile-scoped disable action. Do
     not disable it globally in a way that changes the normal host profile.

**VS Code remote terminal:**

```bash
hostname
pwd
env | rg '^(SSH_AUTH_SOCK|GITHUB_TOKEN|GH_TOKEN)=' || true
git config --show-origin --get-all credential.helper || true
```

  Success means the terminal hostname is the VM, the opened folder is under
  `/srv/budget-analyzer`, and the credential/agent checks print nothing. VS
  Code's UI remains on Mint, but remote extensions, terminals, tasks, language
  servers and workspace files are in the guest.

Do not create the ecosystem bare/working repository pairs manually. Phase 2
provides the reviewed one-time script that discovers and prepares all selected
repositories consistently. Until Checkpoint A, record only the guest root and
SSH alias it will use.

**Step 3 succeeds when:** the guest storage root and free-space result are
recorded; the host reaches the guest with the dedicated key and verified host
key; no SSH agent is forwarded; and the dedicated VS Code profile opens only
guest-local files with automatic port forwarding and personal extensions
disabled.

## Step 4: Block Guest-Initiated Access To Host Services

### 4.1 Identify The Enforcement Interface

- [ ] Resolve the dedicated libvirt bridge and gateway; do not assume a bridge
  name such as `virbr0`.

**Mint host terminal:**

```bash
VM_BRIDGE="$(virsh --connect qemu:///system net-info agent-nat | awk '/^Bridge:/ {print $2}')"
printf 'VM bridge: %s\n' "$VM_BRIDGE"
ip -4 address show dev "$VM_BRIDGE"
ip -6 address show dev "$VM_BRIDGE"
```

  Success means `VM_BRIDGE` is non-empty and the IPv4 address matches the
  selected `agent-nat` gateway. Rules must match this interface so they remain
  valid when DHCP changes the guest address.

### 4.2 Install The Host-Input Policy

- [ ] Re-run `sudo ufw status verbose`. If it says `Status: active`, use the UFW
  sequence below. Replace `<bridge-ipv4>` with the bridge's IPv4 address but
  keep `$VM_BRIDGE` in the same terminal. These rules permit only DHCP and DNS
  requests to libvirt's host-side service, then deny other new guest-to-host
  traffic. UFW's existing established/related handling preserves replies to
  host-initiated SSH and Git connections.

**Mint host terminal, only when UFW is already active:**

```bash
sudo ufw insert 1 deny in on "$VM_BRIDGE" comment 'deny agent VM to host'
sudo ufw insert 1 allow in on "$VM_BRIDGE" proto tcp \
  from any to <bridge-ipv4> port 53 comment 'agent VM DNS TCP'
sudo ufw insert 1 allow in on "$VM_BRIDGE" proto udp \
  from any to <bridge-ipv4> port 53 comment 'agent VM DNS UDP'
sudo ufw insert 1 allow in on "$VM_BRIDGE" proto udp \
  from any port 68 to any port 67 comment 'agent VM DHCP'
sudo ufw status numbered
```

  Confirm the three narrow allows appear before the bridge-wide deny, UFW's
  IPv6 support remains enabled, and no earlier broad allow on the same bridge
  defeats the deny. UFW's packaged IPv6 pre-rules must retain essential neighbor
  discovery; do not add an IPv6 application allow for the guest.

  If UFW is inactive, **do not enable it just for this plan and do not run raw
  `nft flush` or replacement rulesets**. Stop this step and prepare equivalent
  persistent input-chain rules in the firewall manager identified in Step 1:
  established/related first, DHCP/DNS on the exact libvirt bridge second, and a
  final IPv4/IPv6 reject for other input from that bridge. Review the resulting
  manager-specific commands before applying them. An unowned ad-hoc nftables
  rule is not a durable completion.

| Traffic | Required behavior |
| --- | --- |
| New host-to-guest connections | Permit operator SSH, Git transfer and application access |
| Replies to host-initiated connections | Permit established reply traffic |
| New guest-to-personal-host connections | Deny across all host addresses, IPv4 and IPv6 |
| Guest DNS/DHCP to host, if used | Permit only the required service/address/interface |
| Guest Internet traffic | Preserve ordinary outbound access and replies |

### 4.3 Run Positive And Negative Boundary Tests

- [ ] Inventory every address assigned to the host, including the libvirt
  bridge, LAN/Wi-Fi, VPN, Docker bridges and IPv6 link-local addresses:

**Mint host terminal:**

```bash
ip -brief -4 address show
ip -brief -6 address show
```

  Build a test list from these results. This checks host destinations only; it
  does not claim to isolate the guest from other LAN or VPN devices.

- [ ] Start a temporary empty fixture on an unused host port. Keep this terminal
  open and stop it with `Ctrl+C` after the tests.

**Mint host terminal 1:**

```bash
FIXTURE_DIR="$(mktemp -d)"
python3 -m http.server 18080 --bind 0.0.0.0 --directory "$FIXTURE_DIR"
```

**Mint host terminal 1, second tab when the host has IPv6:**

```bash
IPV6_FIXTURE_DIR="$(mktemp -d)"
python3 -m http.server 18081 --bind :: --directory "$IPV6_FIXTURE_DIR"
```

**Mint host terminal 2:**

```bash
curl --fail --max-time 3 http://127.0.0.1:18080/
curl --noproxy '*' --fail --max-time 3 'http://[::1]:18081/'
sudo ss -ltnp '( sport = :18080 )'
sudo ss -ltnp '( sport = :18081 )'
```

  The host curl must succeed and `ss` must show the Python fixture. The empty
  directory prevents accidental exposure of personal files.

- [ ] From the guest, attempt the fixture against every relevant host IPv4
  address recorded above. Replace `<host-ipv4>` each time; do not test only the
  libvirt gateway.

**Guest console or guest SSH session:**

```bash
nc -4 -vz -w 3 <host-ipv4> 18080
```

  Every guest attempt must fail by rejection or timeout. A connection success
  is a failed boundary and must be fixed before continuing. When the host has an
  IPv6 address reachable on the VM link, run the equivalent scoped test against
  the proven IPv6 fixture and require failure:

```bash
nc -6 -vz -w 3 '<host-ipv6>%<guest-interface>' 18081
```

- [ ] Prove required traffic still works after the deny:

**Guest SSH session:**

```bash
getent hosts archive.ubuntu.com
curl --fail --location --max-time 15 https://archive.ubuntu.com/ >/dev/null
```

**Mint host terminal:**

```bash
ssh budget-agent-vm 'printf "host-to-guest SSH works\n"'
```

  DNS, the HTTPS download and host-to-guest SSH must all succeed. This positive
  control distinguishes isolation from a broken VM network.

  Stop both fixture servers with `Ctrl+C`, then remove the two empty temporary
  directories shown in their shell variables with `rmdir`.

- [ ] Reboot the VM from its console, wait for SSH, and repeat the fixture denial,
  guest Internet check and host-to-guest SSH check. Before final acceptance,
  reboot Mint once and repeat them again. After each reboot, also run:

**Mint host terminal:**

```bash
sudo ufw status numbered
virsh --connect qemu:///system net-info agent-nat
```

  Success means the ordered rules remain present and `agent-nat` is active. If
  another firewall manager is in use, substitute its persistent-rule listing.

Exact firewall commands depend on active UFW/nftables/libvirt configuration.
If assistance is needed, provide only a sanitized description. Do not paste a
generic ruleset, disable the firewall or claim success without positive and
negative checks.

**Step 4 succeeds when:** a host-owned persistent rule set blocks new IPv4 and
IPv6 guest connections to every host address on the dedicated bridge, permits
only required DHCP/DNS exceptions, preserves Internet and host-initiated SSH,
and passes the same tests after a guest reboot. Host-reboot persistence may
remain explicitly pending until Checkpoint B, but it may not be recorded as
passed before it is tested.

## Step 5: Prepare Browser Forwarding And TLS Transfer

### 5.1 Verify Name Resolution And Port Availability

- [ ] Check the browser name and current listener before changing anything:

**Mint host terminal:**

```bash
getent ahostsv4 app.budgetanalyzer.localhost
sudo ss -ltnp '( sport = :443 )'
```

  Name resolution must include `127.0.0.1`. Record the existing port-443 owner
  from Step 1. `/etc/hosts` only controls name resolution; it does not forward
  traffic. Stop the old ingress only for an actual forwarding test, using its
  recorded non-destructive stop command.

### 5.2 Verify The Existing Host-Owned TLS Material

- [ ] From the host orchestration checkout, inspect the three files owned by the
  existing local TLS workflow. These are read-only checks; do not run `mkcert`,
  OpenSSL key-generation commands or either certificate-generation script from
  an agent/container.

**Mint host terminal, from this repository:**

```bash
CERT=nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem
KEY=nginx/certs/k8s/_wildcard.budgetanalyzer.localhost-key.pem
CA=nginx/certs/k8s/_mkcert-rootCA.pem
test -r "$CERT" && test -r "$KEY" && test -r "$CA"
openssl x509 -in "$CERT" -noout -checkend 2592000
openssl x509 -in "$CERT" -noout -ext subjectAltName | \
  rg 'DNS:.*budgetanalyzer\.localhost'
openssl x509 -in "$CA" -noout -text | rg 'CA:TRUE'
openssl verify -CAfile "$CA" "$CERT"
openssl x509 -in "$CERT" -pubkey -noout | sha256sum
openssl pkey -in "$KEY" -pubout | sha256sum
```

  Success means all files are readable, the leaf remains valid for at least 30
  days, its SAN covers the local hostname, the public root is a CA, verification
  prints `<certificate path>: OK`, and the final two public-key hashes are
  identical. Never print or copy the key contents into the handoff. If a check
  fails, stop and run the existing host-owned `./setup.sh` workflow on Mint
  before resuming; never create or rotate browser certificates in the agent
  container.

- [ ] Record the exact three source paths for Checkpoint A. Only those leaf,
  leaf-key and public-root files may be copied to the guest. The host mkcert CA
  signing key (normally named `rootCA-key.pem`) must never enter the guest.

### 5.3 Prepare And Test The Explicit SSH Forward

- [ ] First test on unprivileged host port 8443 so the old port-443 listener can
  remain running. In the guest, start an empty one-connection TCP fixture and
  leave the terminal open:

**Guest console:**

```bash
sudo nc -l 127.0.0.1 443
```

**Mint host terminal 1:**

```bash
ssh -N -T -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8443:127.0.0.1:443 budget-agent-vm-forward
```

**Mint host terminal 2:**

```bash
printf 'forward-test\n' | nc -N 127.0.0.1 8443
```

  The guest fixture must display `forward-test`; stop the SSH process with
  `Ctrl+C`. This proves direction and loopback binding but is not the HTTPS
  acceptance test.

- [ ] Install a narrow host mechanism that permits the current Mint user to
  bind only TCP port 443 without running SSH as root:

**Mint host terminal:**

```bash
sudo apt install authbind
sudo install -o "$USER" -g "$(id -gn)" -m 0500 \
  /dev/null /etc/authbind/byport/443
ls -l /etc/authbind/byport/443
```

  The file must be owned by the current Mint user and executable only by that
  user. Do not grant a blanket capability to `ssh`, lower the system-wide
  unprivileged-port threshold or run a root-owned SSH client with personal key
  access.

- [ ] After the old ingress is deliberately stopped and `ss` shows port 443 is
  free, the reviewed foreground forward command is:

**Mint host terminal:**

```bash
authbind --deep ssh -N -T -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:443:127.0.0.1:443 budget-agent-vm-forward
```

  Keep it in a dedicated terminal for the initial acceptance. In another host
  terminal, `sudo ss -ltnp '( sport = :443 )'` must show only
  `127.0.0.1:443`, never `0.0.0.0`, a LAN address or `[::]:443`. A supervised
  user service may replace the foreground command only after its exact unit is
  reviewed and proves the same binding and `ExitOnForwardFailure` behavior.

  During Checkpoint A, repeat the test with a temporary TLS fixture using the
  copied approved leaf/key and verify it with the copied public CA. Do not use
  HTTP, `curl --insecure`, browser certificate exceptions or an unverified
  guest-generated certificate.

### 5.4 Create The Dedicated Browser Profile

- [ ] Create a clean host browser profile:

  - Firefox: enter `about:profiles`, select **Create a New Profile**, name it
    `Budget Analyzer Development`, then **Launch profile in new browser**.
  - Chromium/Chrome: select the profile icon → **Add** → **Continue without an
    account**, and name it `Budget Analyzer Development`.

  Do not enable browser Sync, sign into GitHub, install remote-debugging tools
  or reuse personal cookies in this profile. It may contain only disposable
  local application identities. The browser and profile stay on Mint and are
  never mounted, copied or exposed through a debugging endpoint to the guest.

**Step 5 succeeds when:** the hostname resolves to host loopback; the current
port owner is known; the approved leaf/key/public CA pass all checks; the
unprivileged 8443 forwarding fixture succeeds; the reviewed port-443 command
can bind only `127.0.0.1` when the old ingress is stopped; and a clean browser
profile exists. Real trusted HTTPS remains pending until Checkpoint A transfers
the approved files and Checkpoint B runs the application acceptance test.

## Initial Handoff

- [ ] Capture the version and VM evidence without including the full domain XML
  (which can contain local paths and MAC addresses):

**Mint host terminal:**

```bash
virsh --connect qemu:///system version
qemu-system-x86_64 --version | head -1
virsh --connect qemu:///system dominfo budget-analyzer-agent
virsh --connect qemu:///system domiflist budget-analyzer-agent
virsh --connect qemu:///system domblklist budget-analyzer-agent --details
virsh --connect qemu:///system net-info agent-nat
```

**Guest console or guest SSH session:**

```bash
hostnamectl
df -h / /srv/budget-analyzer
git --version
systemctl is-active ssh
```

- [ ] Fill in this redacted handoff template. Use repository basenames, not
  private URLs or absolute personal-host paths:

```text
VM
  name / guest release:
  vCPU / RAM / virtual disk / free guest space:
  QEMU / libvirt / virt-manager versions:
  disk outside repository trees: PASS | FAIL
  AppArmor dynamic confinement: PASS | FAIL
  prohibited VM devices absent: PASS | FAIL

Network boundary
  libvirt network / bridge / selected CIDR:
  NAT active + autostart: PASS | FAIL
  guest IPv4:
  firewall manager and persistent rule location:
  DHCP/DNS exceptions:
  guest-to-host IPv4 fixture result:
  guest-to-host IPv6 fixture result:
  guest Internet positive control:
  host-to-guest SSH positive control:
  guest reboot persistence:
  host reboot persistence: PASS | FAIL | PENDING
  LAN/VPN peer isolation: OUT OF SCOPE

Guest access
  storage root:
  SSH alias / host-key fingerprint verified: PASS | FAIL
  SSH/X11/automatic port forwarding disabled: PASS | FAIL
  VS Code profile and remote credential checks: PASS | FAIL

Repositories
  selected host parent description:
  selected repository basenames:
  non-main seed branches:

Browser/TLS
  current host port-443 owner:
  certificate validity/SAN/chain/key-match checks: PASS | FAIL
  8443 SSH forwarding fixture: PASS | FAIL
  final 443 loopback binding: PASS | FAIL | PENDING
  dedicated browser profile created: PASS | FAIL
```

- [ ] Store trusted VM, firewall, SSH and forwarding configuration in
  human-owned host storage outside the guest. The handoff may name settings but
  must omit passwords, tokens, private keys, certificate private-key contents,
  browser state, private remote URLs, personal paths and unrelated host
  configuration.

Provide a redacted handoff for
`docs/plans/agent-host-isolation-acceptance.md` during Phase 1. Do not include
credentials, private keys, browser state or unrelated host configuration.

**Handoff:** Run implementation Phases 1–2 only. They prepare guest
configuration, `scripts/setup-agent-vm-repositories.sh`, and exact bootstrap
commands. Do not reopen the existing workspace devcontainer in the guest
unchanged; it would bring back DinD and the old mount assumptions.

## Checkpoint A: Set Up Repositories And Bootstrap The Guest

This happens **after implementation Phase 2**, not during initial VM creation.

### A.1 Review And Run The One-Time Repository Setup

- [ ] On Mint, review the Phase 1 orchestration diff and Phase 2 workspace diff,
  including every line of the new setup script. Confirm that the implementation
  documentation contains one exact invocation matching the script's `--help`;
  do not infer missing flags.

**Mint host terminal, from the common repository parent:**

```bash
git -C orchestration diff --check
git -C workspace diff --check
bash -n workspace/scripts/setup-agent-vm-repositories.sh
shellcheck workspace/scripts/setup-agent-vm-repositories.sh
workspace/scripts/setup-agent-vm-repositories.sh --help
```

  Stop if either repository has unexpected changes, shell validation fails, or
  the documented invocation does not agree with `--help`.

- [ ] Because the setup script transfers committed Git objects and rejects dirty
  repositories, use the normal human-owned Git workflow to commit the accepted
  Phase 1 orchestration changes and Phase 2 workspace changes on their intended
  seed branches. Do not ask an agent to commit or push them. Then require every
  selected host repository to pass:

**Mint host terminal, from each selected host repository:**

```bash
git status --short
test ! -e "$(git rev-parse --git-path MERGE_HEAD)"
test ! -d "$(git rev-parse --git-path rebase-merge)"
test ! -d "$(git rev-parse --git-path rebase-apply)"
```

  `git status --short` must print nothing and all tests must exit zero. The
  reviewed implementation commits do not need to be pushed to GitHub before VM
  setup, but they must be present on the selected local branches so the guest
  receives them.

- [ ] Run the exact documented setup command from this same human-operated Mint
  terminal, supplying the reviewed common parent, `budget-agent-vm` alias and
  `/srv/budget-analyzer` root. The script must print its resolved host parent,
  guest destination and repository basenames before it changes anything. Read
  that list and answer its confirmation only when every entry is intended.

  Success means the script exits zero without force-pushing, replacing a
  non-empty destination, copying uncommitted files or contacting GitHub from the
  guest. Save the redacted summary, not private remote URLs.

- [ ] For every selected repository basename `<repo>`, verify both sides:

**Mint host terminal, from the common repository parent:**

```bash
git -C <repo> remote get-url vm
git -C <repo> ls-remote --heads vm main
```

**Guest SSH session:**

```bash
git -C /srv/budget-analyzer/bare/<repo>.git rev-parse --is-bare-repository
git -C /srv/budget-analyzer/worktrees/<repo> remote -v
git -C /srv/budget-analyzer/worktrees/<repo> branch --all
```

  The bare check must print `true`; the guest working clone must have only one
  remote named `origin`, and that URL must be the guest-local bare repository.
  `main` and the explicitly selected non-main branch, if any, must exist. No
  guest remote may contain `github.com`.

### A.2 Prove A Full Git Round Trip Without GitHub

- [ ] Choose one non-sensitive repository and require a clean host and guest
  worktree. Use the same fixture branch name in all three terminals:

**Mint host terminal, in the selected host checkout:**

```bash
git status --short
git switch main
git pull --ff-only
FIXTURE_BRANCH=host-isolation-roundtrip
git switch -c "$FIXTURE_BRANCH"
printf 'host fixture\n' > host-isolation-roundtrip.txt
git add host-isolation-roundtrip.txt
git commit -m 'test: verify host to guest Git transfer'
git push --set-upstream vm "$FIXTURE_BRANCH"
```

  `git pull --ff-only` is the only GitHub-facing command in this fixture and is
  run by the human on Mint. Stop if the host worktree was not clean or the
  fixture branch already exists.

**Guest SSH session, in the matching guest working clone:**

```bash
FIXTURE_BRANCH=host-isolation-roundtrip
git fetch origin
git switch --track "origin/$FIXTURE_BRANCH"
printf 'guest fixture\n' >> host-isolation-roundtrip.txt
git add host-isolation-roundtrip.txt
git commit -m 'test: verify guest to host Git transfer'
git push origin "$FIXTURE_BRANCH"
```

**Mint host terminal, back in the selected host checkout:**

```bash
FIXTURE_BRANCH=host-isolation-roundtrip
git fetch vm "refs/heads/$FIXTURE_BRANCH:refs/remotes/vm/$FIXTURE_BRANCH"
git merge --ff-only "vm/$FIXTURE_BRANCH"
git log --oneline --decorate -2
git diff main...HEAD -- host-isolation-roundtrip.txt
```

  Success means the log shows both fixture commits, the diff shows both lines,
  and no force, merge commit, rsync or GitHub operation occurred in the guest.
  Record the commit IDs, then clean up only this disposable fixture:

**Guest SSH session, in the matching guest working clone:**

```bash
git switch main
git branch -D host-isolation-roundtrip
```

**Mint host terminal, in the selected host checkout:**

```bash
git switch main
git branch -D host-isolation-roundtrip
git push vm --delete host-isolation-roundtrip
rm host-isolation-roundtrip.txt 2>/dev/null || true
```

  Do not run the cleanup if the branch contains anything except the two known
  fixture commits.

### A.3 Prove The Guest Has No GitHub Authority

- [ ] Run the following without entering any credential:

**Guest SSH session:**

```bash
test -z "${SSH_AUTH_SOCK:-}"
env | rg '^(GITHUB_TOKEN|GH_TOKEN|GIT_ASKPASS|SSH_ASKPASS)=' || true
git config --global --get-all credential.helper || true
gh auth status 2>&1 || true
find /srv/budget-analyzer/worktrees -mindepth 2 -maxdepth 2 -name .git \
  -exec sh -c 'git -C "$(dirname "$1")" remote -v' sh {} \;
```

  Success means no forwarded agent or token variable is present, no host
  credential helper is configured, GitHub CLI is absent or reports no
  authenticated host, and every printed guest remote is guest-local. Do not
  prove isolation by attempting a GitHub write or entering a host credential.

### A.4 Transfer And Validate Only Approved TLS Files

- [ ] From the host orchestration checkout, repeat Step 5's TLS checks, then copy
  the three approved files to a temporary guest location:

**Mint host terminal, from this repository:**

```bash
ssh budget-agent-vm 'install -d -m 0700 /tmp/budget-analyzer-tls-import'
scp \
  nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem \
  nginx/certs/k8s/_wildcard.budgetanalyzer.localhost-key.pem \
  nginx/certs/k8s/_mkcert-rootCA.pem \
  budget-agent-vm:/tmp/budget-analyzer-tls-import/
```

**Guest SSH session:**

```bash
CERT_DIR=/srv/budget-analyzer/worktrees/orchestration/nginx/certs/k8s
install -d -m 0750 "$CERT_DIR"
install -m 0644 /tmp/budget-analyzer-tls-import/_wildcard.budgetanalyzer.localhost.pem "$CERT_DIR/"
install -m 0600 /tmp/budget-analyzer-tls-import/_wildcard.budgetanalyzer.localhost-key.pem "$CERT_DIR/"
install -m 0644 /tmp/budget-analyzer-tls-import/_mkcert-rootCA.pem "$CERT_DIR/"
rm /tmp/budget-analyzer-tls-import/_wildcard.budgetanalyzer.localhost.pem \
  /tmp/budget-analyzer-tls-import/_wildcard.budgetanalyzer.localhost-key.pem \
  /tmp/budget-analyzer-tls-import/_mkcert-rootCA.pem
rmdir /tmp/budget-analyzer-tls-import
CERT="$CERT_DIR/_wildcard.budgetanalyzer.localhost.pem"
KEY="$CERT_DIR/_wildcard.budgetanalyzer.localhost-key.pem"
CA="$CERT_DIR/_mkcert-rootCA.pem"
openssl verify -CAfile "$CA" "$CERT"
openssl x509 -in "$CERT" -pubkey -noout | sha256sum
openssl pkey -in "$KEY" -pubout | sha256sum
find /srv/budget-analyzer -name rootCA-key.pem -print
```

  Verification must print `OK`, the two public-key hashes must match, and the
  final search must print nothing. If the implementation changes the documented
  guest certificate destination, use that reviewed destination consistently
  instead of creating a second copy.

- [ ] Before application bootstrap, prove trusted forwarding with a temporary
  TLS endpoint:

**Guest SSH session, leave running:**

```bash
CERT_DIR=/srv/budget-analyzer/worktrees/orchestration/nginx/certs/k8s
CERT="$CERT_DIR/_wildcard.budgetanalyzer.localhost.pem"
KEY="$CERT_DIR/_wildcard.budgetanalyzer.localhost-key.pem"
sudo openssl s_server -accept 127.0.0.1:443 \
  -cert "$CERT" -key "$KEY" -www
```

**Mint host terminal 1, leave running:**

```bash
ssh -N -T -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8443:127.0.0.1:443 budget-agent-vm-forward
```

**Mint host terminal 2, from this repository:**

```bash
curl --fail --show-error \
  --cacert nginx/certs/k8s/_mkcert-rootCA.pem \
  --resolve app.budgetanalyzer.localhost:8443:127.0.0.1 \
  https://app.budgetanalyzer.localhost:8443/ >/dev/null
```

  Curl must exit zero without `--insecure`. Stop both temporary processes with
  `Ctrl+C` before the real guest ingress starts.

### A.5 Provision And Bootstrap The Guest Runtime

- [ ] From a human-operated guest SSH session, follow the exact prerequisite
  command sequence produced by implementation Phases 1–2. It must install the
  guest Docker daemon and the Java/Node/npm/Tilt prerequisites outside the
  agent container. Run its read-only verification and require these commands to
  succeed:

**Guest SSH session:**

```bash
docker info
git --version
java -version
node --version
npm --version
```

  Also verify all expected working-clone basenames exist, including
  `orchestration`, `workspace` and `ext-authz`. Stop on a missing prerequisite;
  do not compensate in orchestration for a service-owned failure.

- [ ] From the guest orchestration working clone—not from the agent container—run
  the newly documented guest bootstrap command and explicitly select reuse of
  the copied ingress certificate. Read its destruction prompt: this recreates
  the **guest** Kind cluster and is not a daily start command. Generate required
  infrastructure TLS as the human operator in the guest and configure only
  disposable development `.env` credentials.

**Guest SSH session, after bootstrap:**

```bash
kind get clusters
kubectl config current-context
kubectl config view --minify -o jsonpath='{.clusters[0].name}{"\n"}{.clusters[0].cluster.server}{"\n"}'
kubectl get node kind-control-plane
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

  Success requires cluster `kind`, context and referenced cluster `kind-kind`,
  a loopback Kubernetes API URL, and a Ready `kind-control-plane` node.

- [ ] Start Tilt using the implementation's documented guest command and wait
  for its required resources. Launch the reviewed agent container against only
  the guest Docker socket and guest-local paths. Then run:

**Guest SSH session:**

```bash
tilt get uiresources
kubectl get pods -A
sudo ss -ltnp '( sport = :443 )'
```

  Require healthy Tilt resources/pods and a guest-local ingress listener. The
  agent container must have no privileged mode, nested Docker daemon, personal
  host mount, SSH agent, GitHub credential or host kubeconfig.

### A.6 Verify Live Development And Restart Behavior

- [ ] Open `/srv/budget-analyzer/worktrees` with the dedicated VS Code Remote
  SSH profile. Follow the implementation's named Java and frontend smoke-edit
  procedure. For each fixture, save one harmless edit, observe the expected
  Tilt live-update/rebuild event, verify the guest application behavior, and
  restore only that fixture edit. Confirm the corresponding Mint host checkout
  remains unchanged with `git status --short`.

- [ ] Restart the reviewed agent container once. Require `kind get clusters`,
  `kubectl get node kind-control-plane` and `tilt get uiresources` to remain
  healthy; restarting the agent must not restart a nested Docker daemon or
  destroy Kind networking.

- [ ] Shut down and restart the VM. Repeat Step 4's IPv4/IPv6 dummy-listener
  denials plus DNS/download and host-to-guest SSH positive controls. Start guest
  Tilt and the agent again using only the documented daily commands. Supply the
  redacted repository, TLS, runtime, live-update and restart results to
  implementation Phases 3 and 6.

**Checkpoint A succeeds when:** repository setup and a two-commit round trip
pass without guest GitHub authority; only approved TLS files enter the guest;
verified HTTPS forwarding works; the guest Kind/Tilt/agent stack is healthy;
Java and frontend live updates work from Remote SSH; and the boundary plus
runtime survive a VM restart. Every pending or failed item remains explicit.

**Handoff:** Run implementation Phases 3–6 from the guest environment. Use
Remote SSH for guest-local source; do not mount or edit the host clones from the
agent container.

## Checkpoint B: Accept Browser And Daily Git Workflow

This happens **after implementation Phase 6** has passed guest validation.

### B.1 Cut Over Host Port 443 And Verify The Browser

- [ ] Use Step 1's non-destructive stop command for the old runtime and disable
  automatic restart of only its old privileged DinD agent container. Do not
  remove the old Kind cluster, images, volumes or repositories. Require this to
  print no listener before starting the forward:

**Mint host terminal:**

```bash
sudo ss -ltnp '( sport = :443 )'
```

- [ ] Start the foreground forward and leave it running:

**Mint host terminal 1:**

```bash
authbind --deep ssh -N -T -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:443:127.0.0.1:443 budget-agent-vm-forward
```

**Mint host terminal 2:**

```bash
sudo ss -ltnp '( sport = :443 )'
curl --fail --show-error https://app.budgetanalyzer.localhost/ >/dev/null
openssl s_client -connect 127.0.0.1:443 \
  -servername app.budgetanalyzer.localhost -verify_return_error </dev/null
```

  `ss` must show only `127.0.0.1:443`; curl must succeed using normal host trust;
  and OpenSSL must end with `Verify return code: 0 (ok)`. Do not add `--insecure`
  or a browser exception.

- [ ] Launch the dedicated `Budget Analyzer Development` browser profile and
  open `https://app.budgetanalyzer.localhost`. Confirm the address bar shows a
  trusted connection. Log in with a disposable local development identity,
  load at least one API-backed page, log out and log in again. In browser
  Developer Tools → Network, require successful API requests and the expected
  frontend WebSocket connection/update. No request may be redirected to HTTP or
  a public/host observability endpoint.

### B.2 Exercise The Daily Git Workflow

- [ ] Repeat the A.2 round trip on a new disposable branch named
  `host-isolation-daily-flow`, but model actual daily use:

  1. On Mint, update `main` with `git pull --ff-only`, create the branch and
     explicitly `git push --set-upstream vm host-isolation-daily-flow`.
  2. In the guest working clone, `git fetch origin`, switch to the tracking
     branch, make one harmless commit with both an added and deleted line, and
     `git push origin host-isolation-daily-flow`.
  3. On Mint, run
     `git fetch vm refs/heads/host-isolation-daily-flow:refs/remotes/vm/host-isolation-daily-flow`,
     then fast-forward only with
     `git merge --ff-only vm/host-isolation-daily-flow`.
  4. Compare `git log --oneline`, `git diff --stat main...HEAD` and the file
     contents on both sides.
  5. Delete only the verified fixture branch and file using A.2's cleanup
     sequence. Never push this fixture to GitHub.

  Success means commit IDs, additions and deletions match on both sides, and the
  guest still has no GitHub remote or credential.

### B.3 Recheck Live Update, Isolation And Persistence

- [ ] Save and restore the documented disposable Java and frontend edits through
  the Remote SSH window while Tilt runs. Require the expected live-update or
  rebuild result and a clean host checkout afterward; do not use reset/clean
  commands that could remove unrelated work.

- [ ] Reboot Mint, start the VM, guest Tilt/agent and the foreground HTTPS
  forward using only the documented daily commands. Repeat:

  - Step 4's host fixture positive control and guest-to-host IPv4/IPv6 denials;
  - the guest DNS/download and host-to-guest SSH positive controls;
  - `ss` proof that forwarding is loopback-only;
  - the guest environment/credential-helper checks from A.3; and
  - the trusted curl and browser login/logout/API/WebSocket checks from B.1.

  Every check must pass after the host reboot. A rule or forward that existed
  only in transient state is not accepted.

### B.4 Record Acceptance And The Daily Commands

- [ ] Capture current resource use without recording workload secrets:

**Mint host terminal:**

```bash
free -h
virsh --connect qemu:///system dominfo budget-analyzer-agent
```

**Guest SSH session:**

```bash
free -h
df -h / /var/lib/docker /srv/budget-analyzer 2>/dev/null
docker system df
kubectl top nodes 2>/dev/null || true
kubectl top pods -A 2>/dev/null || true
```

- [ ] Update `docs/plans/agent-host-isolation-acceptance.md` through the normal
  reviewed host Git workflow with pass/fail evidence, measured resource use,
  known limitations and the final daily start/stop/Git commands. Do not include
  credentials, private paths or full firewall dumps. Acceptance remains pending
  while any required result is failed, untested or recorded only from before a
  restart.

**Checkpoint B succeeds when:** host port 443 is loopback-only; normal TLS trust
and browser behavior pass; the explicit daily Git flow preserves history and
content without guest GitHub authority; Remote SSH live update works; and the
firewall, forwarding and credential boundary survive a host reboot.

Daily use starts the VM, guest Tilt/agent, Remote SSH editor and HTTPS forward.
For a task, the host updates `main`, creates a feature branch and explicitly
pushes it to `vm`; the guest agent commits and pushes only to its guest-local
bare `origin`; the host fetches and fast-forwards, then separately reviews,
pushes to GitHub and creates the PR. Do not rerun the one-time repository setup,
`setup.sh`, certificate generation or any source synchronization for ordinary
daily work.
