# Development VM Manual Setup Plan

**Status:** Operator preparation Steps 1–5 and the Initial Handoff were
completed and verified by the operator on 2026-10-03. The post-implementation
Checkpoints A–C remain pending and must not be treated as completed by this
preparation status.

**Audience:** The human operating the personal Linux Mint workstation.

**Companion:** [Agent implementation plan](agent-host-isolation-plan.md).

This is a manual checklist, not an AI Session Handler execution plan. Complete
Steps 1–5 before agent implementation. Three checkpoints remain afterward: run
the reviewed one-time repository setup and bootstrap the guest, accept the
browser and daily Git workflow after implementation, then establish the final
guest-only Docker architecture. Agents may prepare instructions; they do not
administer your host or push to GitHub.

This is a clean setup, not a migration. Do not copy, export, import or recreate
host Docker images, containers, volumes, Kind clusters, databases, application
data or build caches in the VM. The guest creates fresh runtime state from the
reviewed configuration. Only committed Git objects and the approved
browser-trusted development TLS files cross from host to guest.

Work on feature branches. The existing Mint-hosted workspace devcontainer is
the implementation runner for Phases 1–6. It is the currently working container
defined by sibling workspace `.devcontainer/devcontainer.json` and
`ai-agent-sandbox/docker-compose.yml`; keep it available through Checkpoint B.
The guest agent container is a separate target runtime, not a replacement for
the implementation runner during those phases. Do not create a saved-image or
runtime fallback. The one retirement step is Checkpoint C, after every
implementation phase and Checkpoint B have finished: close the Mint-hosted
devcontainer, uninstall Mint Docker, remove its runtime state and remove the
temporary Docker-specific firewall integration.

## How To Use This Checklist

Run commands only in the environment named immediately above the code block:

- **Mint host terminal** means a normal terminal opened from the Linux Mint
  desktop, not VS Code's devcontainer terminal.
- **Guest console** means virt-manager's console for the new VM.
- **Guest SSH session** means a terminal reached through the dedicated SSH
  alias created in Step 3.

Container and editor terms are deliberately distinct:

- **Existing Mint devcontainer** means the working agent environment hosted by
  Mint Docker. It runs the AI Session Handler implementation phases.
- **Guest agent container** means the separate guest-Docker configuration that
  implementation Phase 2 adds at
  `../workspace/ai-agent-sandbox/docker-compose.agent-vm.yml`. It is launched
  during Checkpoint A for guest bootstrap, validation and eventual daily use.
- **`Budget Analyzer VM` VS Code profile** means only the host editor settings
  and extension selection used for Remote SSH. It is not a Docker or Dev
  Container configuration.

There is no object called a “Mint profile” or “VM profile” in this plan.

Do not copy a leading `$` or substitute commands from an agent container. A
checkbox is complete only when its stated success evidence is visible. Save a
redacted text record of command versions, resource values, interface names and
pass/fail results; do not record passwords, private keys, tokens, certificate
private-key contents or private remote URLs.

Use these names unless there is a collision. Host route checks in Step 2
confirmed `192.168.231.0/24` for the dedicated VM network, with gateway
`192.168.231.1`, dynamic DHCP range `192.168.231.128` through
`192.168.231.254`, and reserved guest address `192.168.231.10`.

```text
VM name:                 budget-analyzer-agent
libvirt connection:     qemu:///system
libvirt network name:   agent-nat
libvirt subnet:          192.168.231.0/24
libvirt gateway:         192.168.231.1
dynamic DHCP range:      192.168.231.128-192.168.231.254
reserved guest address: 192.168.231.10
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
| Guest editor | Native host VS Code UI using Remote SSH; guest files, terminals and extensions remain in the VM |
| Browser | Dedicated development profile on the personal host |
| Runtime | Keep Mint Docker through implementation and Checkpoint B; final state is one fresh guest Docker daemon |
| Implementation runner | Existing Mint-hosted workspace devcontainer through Phases 1–6 |
| Guest agent runtime | Separate `docker-compose.agent-vm.yml` configuration created in Phase 2 |
| Repository transfer | Explicit host-initiated Git push/fetch over SSH through a `vm` remote |
| GitHub authority | Host only; no guest GitHub write credential or authenticated GitHub browser |
| Browser URL | `https://app.budgetanalyzer.localhost`, through host-loopback forwarding |

The implementation plan owns the boundary and exclusions. This checklist owns
manual preparation and handoffs. It does not introduce shared folders, rsync,
an agent-controlled fork, daily publication automation or routine source
copying outside Git.

## Step 1: Check Host And Source Prerequisites

- [x] Back up important host repositories, including uncommitted and untracked
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
  branch is named in the handoff. This protects source work; it is not a runtime
  migration step.

- [x] Check whether host ports 80 or 443 are currently in use:

**Mint host terminal:**

```bash
sudo ss -ltnp '( sport = :80 or sport = :443 )'
```

  Record the owner, including Docker port mappings, so the human operator can
  stop it at Checkpoint B. Leave it running during initial setup; the preliminary
  forwarding test uses port 8443. No runtime data needs to be copied or retained.

- [x] Confirm free RAM/disk, hardware virtualization and the current firewall
  manager. Run these read-only commands on Mint:

```bash
lscpu
free -h
df -h .
df -h /data/libvirt/agent-vm-images 2>/dev/null || true
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
  - The filesystem that will hold `/data/libvirt/agent-vm-images` can
    accommodate a sparse disk that may grow to 200 GiB. Sparse allocation does
    not reserve that free space.
  - The handoff says whether UFW is active, whether another nftables manager
    owns persistent rules, or whether no persistent host firewall is active.
    Do not enable, disable or flush anything yet; Step 4 owns the reviewed
    adoption path when no manager is active.

- [x] Confirm each ecosystem repository that should enter the VM is an immediate
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
- [x] Decide which current checked-out branch, if different from `main`, should
  be seeded for each repository. The setup script will print the discovered set
  and require confirmation; move unrelated repositories outside the selected
  parent or decline the run.

**Step 1 succeeds when:** source work is backed up; hardware virtualization is
usable; RAM and disk are sufficient; the firewall ownership state and any
port-443 listener are known, including an explicit record when there is no
active persistent firewall owner; and the selected parent, repositories and
seed branches are recorded. If KVM is unavailable, stop and enable Intel
virtualization in firmware. Ordinary Docker/Kind inside this VM needs no nested
virtualization.

## Step 2: Install And Create The VM

### 2.1 Install And Validate KVM/libvirt

- [x] Install the distribution packages on Mint:

**Mint host terminal:**

```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager ovmf \
  gnupg ripgrep shellcheck
```

- [x] Start the packaged libvirt system service and run its host validator:

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

- [x] Open **Menu → Administration → Virtual Machine Manager**. In virt-manager:

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

- [x] In a host browser, open the official
  [Ubuntu 24.04 LTS release directory](https://releases.ubuntu.com/24.04/).
  Download all three files from the same directory:

  1. the current `ubuntu-24.04...-live-server-amd64.iso`;
  2. `SHA256SUMS`; and
  3. `SHA256SUMS.gpg`.

  Do not use a search-result mirror, a daily build, a desktop ISO or a file for
  another CPU architecture.

- [x] Put the three files in one otherwise empty directory, then verify the
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

- [x] Inventory every currently active host, Docker, libvirt and VPN route:

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

- [x] Choose one unused RFC1918 `/24` for the dedicated VM network. For example,
  `192.168.231.0/24` is acceptable only if no route, Docker/Kind network,
  libvirt network or VPN route contains or overlaps it. Record the selected
  network, gateway (normally `.1`) and DHCP range. Recheck after connecting any
  VPN used during development.

- [x] In virt-manager, create the network:

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

- [x] Confirm the installed UI version and that `/data` is the mounted backing
  filesystem rather than an ordinary directory on the root filesystem:

**Mint host terminal:**

```bash
virt-manager --version
findmnt --target /data/libvirt/agent-vm-images \
  --output TARGET,SOURCE,FSTYPE,OPTIONS
df -h /data/libvirt/agent-vm-images
```

  The packaged Linux Mint 22.1/Ubuntu 24.04 version is virt-manager 4.1.x. The
  `findmnt` target must be `/data`, and `df` must show enough free space for the
  qcow2 file to grow to 200 GiB. Stop if `/data` is not mounted. The detailed
  labels below describe the 4.1.x UI; record the installed version if a newer
  package changes a label.

- [x] If a previous installation attempt created a VM named
  `budget-analyzer-agent`, remove that failed definition before retrying. In the
  main virt-manager window, right-click the stopped VM and select **Delete**.
  Leave **Delete associated storage files** unselected. In the storage-pool
  steps below, separately remove only an unwanted volume named
  `budget-analyzer-agent.qcow2`; do not remove the pool directory or installer
  ISO. If the VM name is absent, continue without doing anything.

- [x] Create or verify the dedicated system storage pool before creating the
  VM. These labels match virt-manager 4.1.x, the Ubuntu 24.04 package used by
  Linux Mint 22.1:

  1. In the main virt-manager window, single-click the **QEMU/KVM** connection
     that represents `qemu:///system`; do not select **QEMU/KVM User Session**.
  2. Open **Edit → Connection Details**, then select the **Storage** tab.
  3. If `agent-vm-images` is already listed, select it and verify its
     **Location** is `/data/libvirt/agent-vm-images`. Do not create a second
     pool. Stop if the existing pool has another location. Otherwise, select
     the **+** button whose tooltip is **Add Pool**.
  4. In **Add a New Storage Pool**, enter `agent-vm-images` for **Name**, choose
     `dir: Filesystem Directory` for **Type**, and select **Forward**.
  5. Enter `/data/libvirt/agent-vm-images` in **Target Path**, then select
     **Finish**. This target is the pool directory, not a virtual disk.
  6. Select `agent-vm-images` in the pool list. If its **State** is inactive,
     select the triangular **Start Pool** button. Enable **Autostart**. Do not
     select **Browse Local** when defining this pool.

**Mint host terminal:**

```bash
virsh --connect qemu:///system pool-info agent-vm-images
virsh --connect qemu:///system pool-path agent-vm-images
```

  Success means the pool is active, autostarts and its canonical path is exactly
  `/data/libvirt/agent-vm-images`, outside all repository trees.

- [x] Copy the already verified public installer ISO into that pool so normal
  libvirt/AppArmor access applies. Replace `<iso-filename>` with the exact file
  that passed Step 2.2:

**Mint host terminal:**

```bash
sudo install -o root -g root -m 0644 \
  "$HOME/Downloads/ubuntu-24.04-server-verify/<iso-filename>" \
  /data/libvirt/agent-vm-images/
virsh --connect qemu:///system pool-refresh agent-vm-images
virsh --connect qemu:///system vol-list agent-vm-images
```

  The volume list must show the ISO. Do not loosen home-directory permissions or
  disable AppArmor to make a system VM read an ISO from `Downloads`.

- [x] Create the virtual-disk volume before opening the New VM wizard. This
  makes the pool directory and the disk file impossible to confuse:

  1. Return to **Edit → Connection Details → Storage** and select the
     `agent-vm-images` pool.
  2. In the **Volumes** pane, remove an unwanted volume only if its exact name is
     `budget-analyzer-agent.qcow2`: select that row, select the button whose
     tooltip is **Delete Volume**, and confirm the displayed path ends in that
     exact filename. Keep the verified `.iso` volume.
  3. Select the **+** button immediately above the **Volumes** list. Its tooltip
     identifies it as the control for creating a new volume; it is not the
     **Add Pool** button on the left.
  4. In **Add a Storage Volume**, enter `budget-analyzer-agent.qcow2` for
     **Name**, select `qcow2` for **Format**, and set **Capacity** to `200 GiB`.
  5. Leave **Allocate entire volume now** unselected so the file is sparse.
     Leave **Backing store** empty, then select **Finish**.
  6. Confirm the **Volumes** list contains two distinct files: the verified
     Ubuntu `.iso` and `budget-analyzer-agent.qcow2`. A row representing
     `/data/libvirt/agent-vm-images` itself is not a disk volume.

**Mint host terminal:**

```bash
virsh --connect qemu:///system vol-info \
  --pool agent-vm-images budget-analyzer-agent.qcow2
virsh --connect qemu:///system vol-path \
  --pool agent-vm-images budget-analyzer-agent.qcow2
sudo qemu-img info \
  /data/libvirt/agent-vm-images/budget-analyzer-agent.qcow2
```

  Success requires a 200 GiB capacity, an allocation much smaller than the
  capacity, the exact path
  `/data/libvirt/agent-vm-images/budget-analyzer-agent.qcow2`, and `file format:
  qcow2`. Stop if `qemu-img` reports `raw`, if the path is the pool directory,
  or if the full 200 GiB was allocated.

- [x] Create the VM and explicitly select the two previously created file
  volumes:

  1. Close **Connection Details**, select **File → New Virtual Machine**, choose
     **Local install media (ISO image or CDROM)**, and select **Forward**.
  2. At **Choose ISO or CDROM install media**, select **Browse...**. In **Choose
     Storage Volume**, select `agent-vm-images` in the left pool list, select the
     verified Ubuntu `.iso` file in the right **Volumes** list, and select
     **Choose Volume**. Do not select **Browse Local** and do not select only the
     pool name.
  3. Back in the wizard, verify the media field ends in the exact `.iso`
     filename. Verify the detected operating system is Ubuntu 24.04 LTS;
     manually select that release if detection is blank. Select **Forward**.
  4. Set **Memory** to `24576 MiB`, set **CPUs** to `8`, and select **Forward**.
  5. On the storage page, select **Select or create custom storage**, then
     select **Manage...**. In **Choose Storage Volume**, select
     `agent-vm-images` on the left, select
     `budget-analyzer-agent.qcow2` in the right **Volumes** list, and select
     **Choose Volume**.
  6. Verify the custom-storage field contains the full path
     `/data/libvirt/agent-vm-images/budget-analyzer-agent.qcow2`, not the
     directory `/data/libvirt/agent-vm-images`. Do not select **Create a disk
     image for the virtual machine**, because the checked qcow2 volume already
     exists. Select **Forward**.
  7. Enter `budget-analyzer-agent` for **Name**, select **Customize configuration
     before install**, choose **Virtual network 'agent-nat': NAT** for the
     network selection, and select **Finish**. Do not select a host bridge,
     macvtap or direct attachment.

- [x] In **Customize configuration**, check every relevant device before
  starting the VM:

  1. In **Overview**, keep **KVM** virtualization, the normal QEMU emulator,
     `x86_64` architecture and UEFI firmware. Do not enable nested
     virtualization.
  2. Select the 200 GiB disk entry. Its source path must end in
     `budget-analyzer-agent.qcow2`, its storage format must be `qcow2`, and its
     disk bus must be `VirtIO`. A source path ending at `agent-vm-images` is an
     error; remove that device and return to the preceding storage-selection
     steps.
  3. Select the CD-ROM entry and confirm its source path ends in the verified
     Ubuntu `.iso` filename.
  4. Select **NIC** and set **Network source** to **Virtual network
     'agent-nat': NAT** and **Device model** to `virtio`.
  5. Select **Display**, set **Type** to **VNC server**, **Listen type** to
     **Address**, and **Address** to **Localhost only**. Leave automatic port
     selection enabled.
  6. Remove each **USB Redirector** device and any channel whose name is
     `spice-space.webdav`. Do not add Filesystem, Host device, USB host device,
     PCI host device, TPM passthrough or smartcard hardware.
  7. Recheck the disk and CD-ROM source paths, then select **Begin
     Installation**.

- [x] While the installer is running, verify the disk location from another
  host terminal:

**Mint host terminal:**

```bash
virsh --connect qemu:///system domblklist budget-analyzer-agent --details
virsh --connect qemu:///system dumpxml budget-analyzer-agent | \
  sed -n '/<disk /,/<\/disk>/p'
virsh --connect qemu:///system dumpxml budget-analyzer-agent | \
  rg -n "<graphics|<listen|<filesystem|<hostdev|<redirdev|spice-space.webdav"
```

  `domblklist` must show a `file`/`disk` row whose source is exactly
  `/data/libvirt/agent-vm-images/budget-analyzer-agent.qcow2` and a
  `file`/`cdrom` row whose source is the verified ISO. The disk XML must show
  `<disk type='file' device='disk'>`, a qcow2 driver and a `<source file=...>`;
  it must not show `<disk type='dir'>`. The final search must show VNC listening
  on `127.0.0.1` and no `<filesystem>`, `<hostdev>`, `<redirdev>` or SPICE
  WebDAV device. Shut down and correct the hardware before OS setup if any
  check fails.

### 2.5 Install And Update The Guest

- [x] Complete the Ubuntu installer from virt-manager's console:

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

- [x] Log in through the virt-manager console first and install updates and the
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

- [x] Reserve the selected stable guest address so the SSH aliases do not
  silently point at a different DHCP client later. `192.168.231.10` is inside
  the selected `192.168.231.0/24` subnet, avoids the `192.168.231.1` gateway,
  and is outside the dynamic DHCP range `192.168.231.128` through
  `192.168.231.254`. Run:

**Mint host terminal:**

```bash
GUEST_MAC="$(virsh --connect qemu:///system domiflist budget-analyzer-agent | awk '$3 == "agent-nat" {print $5}')"
RESERVED_GUEST_IP='192.168.231.10'
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

- [x] With the VM running, perform these read-only host checks:

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

- [x] Confirm from the guest that host authority did not enter it:

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

- [x] Use `/srv/budget-analyzer` as the guest-local project root unless the VM
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

- [x] Find and record the guest's DHCP address and SSH host-key fingerprint.

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

- [x] Create a key used only for this VM. Accept the proposed filename below;
  use a passphrase stored by the human, but do not add the key to a forwarded
  agent.

**Mint host terminal:**

```bash
ssh-keygen -t ed25519 -a 100 \
  -f "$HOME/.ssh/budget-analyzer-agent-vm" \
  -C 'budget-analyzer-agent host-to-guest'
```

- [x] Copy only the public key. Replace `<guest-user>` and `<guest-ip>` with the
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

- [x] Open `~/.ssh/config` on Mint in a host editor and add the following two
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

- [x] On Mint, install the Microsoft **Remote - SSH** extension in the local VS
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

- [x] Resolve the dedicated libvirt bridge and gateway; do not assume a bridge
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

These input rules cover native host services. Docker-published ports can take
a DNAT/FORWARD path instead; complete the Docker check below as well.

#### Recorded Host State

The Step 1 and Step 4 discovery performed on the Mint host on 2026-10-03 found
the following state. This is setup-specific evidence, not a portable inventory
to reuse on a different host:

| Item | Observed state |
| --- | --- |
| UFW | Installed but inactive; no added user rules |
| Other persistent manager | `nftables` inactive/disabled; `firewalld` absent |
| UFW defaults | IPv6 enabled; deny incoming; allow outgoing; deny routed |
| Active compatibility backend | `iptables` and `ip6tables` both resolve to `xtables-nft-multi` |
| Dedicated VM network | `agent-nat`; `virbr1`; gateway `192.168.231.1` |
| Docker default bridge | `docker0`; network ID prefix `a87d6b19b4e1`; `172.17.0.0/16` |
| Docker Kind bridge | `br-77a017d8bb5e`; network ID prefix `77a017d8bb5e`; `172.18.0.0/16` and `fc00:f853:ccd:e793::/64` |
| Docker filtering | IPv4 and IPv6 `DOCKER-USER` chains exist; host ports 80 and 443 are Docker-published |
| Native listeners relevant to the boundary | libvirt DNS/DHCP on `virbr0`/`virbr1`; Avahi on wildcard UDP; remaining non-Docker TCP listeners are loopback-only |

The `nft` tables visible during discovery are created through the active
`iptables-nft` compatibility backend by Docker/libvirt; they are not evidence
of a persistent host firewall manager. Both `iptables` commands also warned
that legacy tables exist. Inspect those tables read-only before adoption, but
do not flush them or install this policy through the legacy alternatives:

**Mint host terminal:**

```bash
sudo iptables-legacy -S
sudo ip6tables-legacy -S
```

- [x] Review the recorded listener and legacy-table inventory. Deliberately
  adopt UFW as the workstation's ongoing host-input firewall, not as a
  temporary way to pass this checklist. Enabling it applies the default-deny
  input policy across the host. Loopback-only editor, printing, VNC and SSH
  forwarding listeners remain local; unsolicited native LAN access and some
  discovery behavior may change. Do not add a host SSH allow merely for the
  host-initiated connection to the guest.

#### Adopt UFW For Native Host Input

- [x] Re-resolve and validate the bridge in the same terminal, add the rules
  while UFW is inactive, review the stored rules, and then enable UFW. These
  rules permit only DHCP and DNS requests to libvirt's host-side service and
  deny other guest-to-host input. UFW's established/related handling preserves
  replies to host-initiated SSH and Git connections.

**Mint host terminal:**

```bash
VM_BRIDGE="$(
  virsh --connect qemu:///system net-info agent-nat |
    awk '/^Bridge:/ {print $2}'
)"
test "$VM_BRIDGE" = 'virbr1'
BRIDGE_IPV4='192.168.231.1'
ip -4 address show dev "$VM_BRIDGE" | rg -F "$BRIDGE_IPV4/24"

sudo ufw prepend deny in on "$VM_BRIDGE" comment 'deny agent VM to host'
sudo ufw insert 1 allow in on "$VM_BRIDGE" proto tcp \
  from any to "$BRIDGE_IPV4" port 53 comment 'agent VM DNS TCP'
sudo ufw insert 1 allow in on "$VM_BRIDGE" proto udp \
  from any to "$BRIDGE_IPV4" port 53 comment 'agent VM DNS UDP'
sudo ufw insert 1 allow in on "$VM_BRIDGE" proto udp \
  from 0.0.0.0/0 port 68 to 0.0.0.0/0 port 67 comment 'agent VM DHCP'

sudo ufw show added
sudo ufw --force enable
sudo ufw status verbose
sudo ufw status numbered
```

  `prepend` is required when the initial UFW user ruleset is empty; `insert 1`
  has no valid target position in that state. The explicit IPv4 wildcard on the
  DHCP rule prevents UFW from generating an irrelevant UDP 68-to-67 IPv6 rule.
  Confirm the three narrow IPv4 allows appear before the IPv4 bridge-wide deny,
  the only IPv6 user rule is the equivalent bridge-wide deny, UFW reports
  active and IPv6 support remains enabled. UFW's packaged IPv6 pre-rules must
  retain essential neighbor discovery; do not add an IPv6 application allow
  for the guest. If activation changes an unrelated host service that the
  operator requires, stop and review a narrowly scoped allow; do not disable
  the boundary or add a broad allow on `virbr1`.

#### Persist Docker Forward-Path Isolation

Docker-published ports are translated before UFW's input rules, so the native
UFW policy is not sufficient. Docker on this host uses the supported
`iptables-nft` compatibility backend. Install rules in its `DOCKER-USER` chains
rather than editing raw nftables state or Docker-owned chains. The rules below
reject only new traffic arriving from `virbr1` and leaving through the default
Docker bridge or a Docker-generated `br-...` bridge. Established replies and
guest Internet traffic through a non-Docker host interface remain eligible for
the later rules. This follows Docker's documented
[`DOCKER-USER` filtering model](https://docs.docker.com/engine/network/firewall-iptables/)
and uses UFW's documented
[`after.init` customization hook](https://manpages.ubuntu.com/manpages/noble/man8/ufw-framework.8.html)
for reload ordering.

This is a transitional defense, not the final architecture. Keep it installed
for the entire period in which the host-resident implementation agents require
Mint Docker, including all phases of the companion implementation plan and
Checkpoint B. Remove it only in Checkpoint C after Mint Docker has been stopped
and uninstalled. The permanent UFW rules protecting native Mint input on
`virbr1` remain after that cleanup.

- [x] Use a host editor to create
  `/usr/local/sbin/agent-vm-docker-isolation` with the exact reviewed content
  below. The `br-+` spelling is the `iptables` interface-prefix match and covers
  the current Kind bridge plus future Docker-generated bridge names.

```sh
#!/bin/sh
set -eu

VM_BRIDGE='virbr1'

add_new_reject() {
    firewall=$1
    docker_output=$2

    if ! "$firewall" --wait -C DOCKER-USER \
        -i "$VM_BRIDGE" -o "$docker_output" \
        -m conntrack --ctstate NEW \
        -m comment --comment 'deny agent VM to Docker' \
        -j REJECT 2>/dev/null; then
        "$firewall" --wait -I DOCKER-USER 1 \
            -i "$VM_BRIDGE" -o "$docker_output" \
            -m conntrack --ctstate NEW \
            -m comment --comment 'deny agent VM to Docker' \
            -j REJECT
    fi
}

/usr/sbin/iptables --wait -n -L DOCKER-USER >/dev/null
/usr/sbin/ip6tables --wait -n -L DOCKER-USER >/dev/null
add_new_reject /usr/sbin/iptables docker0
add_new_reject /usr/sbin/iptables 'br-+'
add_new_reject /usr/sbin/ip6tables docker0
add_new_reject /usr/sbin/ip6tables 'br-+'
```

**Mint host terminal:**

```bash
sudo chown root:root /usr/local/sbin/agent-vm-docker-isolation
sudo chmod 0755 /usr/local/sbin/agent-vm-docker-isolation
sudo sh -n /usr/local/sbin/agent-vm-docker-isolation
sudo shellcheck /usr/local/sbin/agent-vm-docker-isolation
```

- [x] Make the helper run after every Docker start. Create the systemd drop-in
  directory first:

**Mint host terminal:**

```bash
sudo install -d -o root -g root -m 0755 \
  /etc/systemd/system/docker.service.d
```

  Then use a host editor to create
  `/etc/systemd/system/docker.service.d/agent-vm-isolation.conf` with:

```systemd
[Service]
ExecStartPost=/usr/local/sbin/agent-vm-docker-isolation
```

**Mint host terminal:**

```bash
sudo chown root:root \
  /etc/systemd/system/docker.service.d/agent-vm-isolation.conf
sudo chmod 0644 \
  /etc/systemd/system/docker.service.d/agent-vm-isolation.conf
sudo systemctl daemon-reload
sudo systemd-analyze verify docker.service
sudo systemctl cat docker.service
```

- [x] Make UFW reloads reapply the same Docker rules. First inspect whether a
  local customization already exists:

**Mint host terminal:**

```bash
sudo test ! -e /etc/ufw/after.init || sudo sed -n '1,240p' /etc/ufw/after.init
```

  If the file exists, stop and merge the behavior below without deleting its
  existing policy. Otherwise use a host editor to create `/etc/ufw/after.init`
  with:

```sh
#!/bin/sh
set -eu

case "${1:-}" in
    start)
        if systemctl --quiet is-active docker.service; then
            /usr/local/sbin/agent-vm-docker-isolation
        fi
        ;;
    stop|status|flush-all)
        ;;
esac

exit 0
```

**Mint host terminal:**

```bash
sudo chown root:root /etc/ufw/after.init
sudo chmod 0755 /etc/ufw/after.init
sudo sh -n /etc/ufw/after.init
sudo shellcheck /etc/ufw/after.init
```

- [x] Apply the Docker rules without restarting the currently running Docker
  workloads, reload UFW to exercise its persistence hook, and inspect both
  address families. Do not use `iptables-save`/`netfilter-persistent` to save
  Docker- or libvirt-generated rules.

**Mint host terminal:**

```bash
sudo /usr/local/sbin/agent-vm-docker-isolation
sudo ufw reload
sudo iptables -S DOCKER-USER
sudo ip6tables -S DOCKER-USER
```

  Each chain must contain one new-connection reject for `virbr1` to `docker0`
  and one for `virbr1` to `br-+`, with no duplicate copies. Re-run the helper
  and confirm the listing is unchanged to prove idempotence. If Docker later
  uses an explicitly named bridge that does not match `docker0` or `br-+`, add
  that exact output interface to the reviewed helper before using the network.

  Recorded result: the packaged `/etc/ufw/after.init` placeholder was retained
  and its `start)` branch was extended with the reviewed helper call. After a
  UFW reload, both the IPv4 and IPv6 `DOCKER-USER` chains contained exactly one
  new-connection reject for `virbr1` to `docker0` and one for `virbr1` to
  `br-+`. Re-running the helper did not add duplicates. The expected warnings
  about separately present legacy tables remained informational; the installed
  policy uses the active `iptables-nft` compatibility backend.

| Traffic | Required behavior |
| --- | --- |
| New host-to-guest connections | Permit operator SSH, Git transfer and application access |
| Replies to host-initiated connections | Permit established reply traffic |
| New guest-to-personal-host connections | Deny across all host addresses, IPv4 and IPv6 |
| New guest-to-host-Docker connections | Deny published-port and direct container routes |
| Guest DNS/DHCP to host, if used | Permit only the required service/address/interface |
| Guest Internet traffic | Preserve ordinary outbound access and replies |

### 4.3 Run Positive And Negative Boundary Tests

- [x] Inventory every address assigned to the host, including the libvirt
  bridge, LAN/Wi-Fi, VPN, Docker bridges and IPv6 link-local addresses:

**Mint host terminal:**

```bash
ip -brief -4 address show
ip -brief -6 address show
```

  Build a test list from these results. This checks host destinations only; it
  does not claim to isolate the guest from other LAN or VPN devices.

  Recorded inventory: IPv4 addresses were `192.168.50.178` on `wlp0s20f3`,
  `192.168.231.1` on `virbr1`, `192.168.122.1` on down `virbr0`, `172.17.0.1`
  on down `docker0`, and `172.18.0.1` on `br-77a017d8bb5e`. `virbr1` had no
  IPv6 address. The Docker bridge had `fc00:f853:ccd:e793::1/64`; host
  link-local addresses were also recorded for Wi-Fi, the Docker bridge, its
  veth and `vnet0`.

- [x] Start a temporary empty fixture on an unused host port. Keep this terminal
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

- [x] From the guest, attempt the fixture against every relevant host IPv4
  address recorded above. Replace `<host-ipv4>` each time; do not test only the
  libvirt gateway.

**Guest console or guest SSH session:**

```bash
nc -4 -vz -w 3 <host-ipv4> 18080
```

  Every guest attempt must fail by rejection or timeout. A connection success
  is a failed boundary and must be fixed before continuing.

  Recorded result: from guest interface `enp1s0` at `192.168.231.10`, attempts
  to all five inventoried non-loopback IPv4 addresses timed out.

- [x] When the host has an IPv6 address reachable on the VM link, run the
  equivalent scoped test against the proven IPv6 fixture and require failure:

```bash
nc -6 -vz -w 3 '<host-ipv6>%<guest-interface>' 18081
```

  Recorded partial result: the guest reported `Network is unreachable` for
  `fc00:f853:ccd:e793::1`, so do not add a route merely to manufacture that
  test. The current scoped candidate is the host-side `vnet0` link-local
  address `fe80::fc54:ff:fed9:c270`; test it from guest interface `enp1s0`
  while the proven IPv6 fixture is running.

- [x] Test the Docker path with a disposable HTTP container using a reviewed
  digest-pinned image, no host mounts and unused published port 18082. Bind it
  to the host's libvirt bridge address. Confirm a host request to that published
  address succeeds, then require guest requests to both the published address
  and container IP/port to fail. Inspect Docker's port mapping even if `ss`
  shows no listener: kernel DNAT need not create a listening process. Cover
  IPv6 too if host Docker provides IPv6 routes or published bindings. Remove
  only this fixture afterward. Record the image, commands and results.

- [x] Prove required traffic still works after the deny:

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

- [x] Keep the persistent-rule listing for Checkpoint B, which performs the
  host-reboot check once after the complete runtime is installed:

**Mint host terminal:**

```bash
sudo ufw status numbered
sudo iptables -S DOCKER-USER
sudo ip6tables -S DOCKER-USER
sudo systemctl cat docker.service
virsh --connect qemu:///system net-info agent-nat
```

  Success means the ordered UFW rules and four Docker bridge rejects remain
  present, the Docker service includes the reviewed `ExecStartPost`, and
  `agent-nat` is active.

  Recorded result: UFW was active with the IPv4 DHCP and two DNS allows ordered
  before the IPv4 `virbr1` deny, followed by only the equivalent IPv6 `virbr1`
  deny. Each `DOCKER-USER` chain contained exactly one reject from `virbr1` to
  `br-+` and one to `docker0`, with no duplicates. `systemctl cat` showed
  `/etc/systemd/system/docker.service.d/agent-vm-isolation.conf` and its
  `ExecStartPost=/usr/local/sbin/agent-vm-docker-isolation`. The `agent-nat`
  network was active, persistent and configured to autostart on `virbr1`. The
  legacy-table notices remained the previously reviewed informational warnings.

The commands above are specific to the recorded Mint/UFW, libvirt and
Docker-`iptables-nft` configuration. Re-run discovery and review this section
before applying it on a different host or after changing Docker's firewall
backend. Do not substitute raw nftables or legacy-iptables rules, disable the
firewall or claim success without the positive and negative checks.

**Step 4 succeeds when:** a host-owned persistent rule set blocks new IPv4 and
IPv6 guest connections to every host address on the dedicated bridge, permits
only required DHCP/DNS exceptions, blocks Docker forwarding paths, and preserves
Internet and host-initiated SSH. Reboot persistence remains pending until
Checkpoint B.

## Step 5: Prepare Browser Forwarding And TLS Transfer

### 5.1 Verify Name Resolution And Port Availability

- [x] Check the browser name and current listener before changing anything:

**Mint host terminal:**

```bash
getent ahostsv4 app.budgetanalyzer.localhost
sudo ss -ltnp '( sport = :443 )'
```

  Name resolution must include `127.0.0.1`. Record any port-443 listener from
  Step 1. `/etc/hosts` only controls name resolution; it does not forward
  traffic. The human operator must stop that listener before the final
  forwarding test.

### 5.2 Verify The Existing Host-Owned TLS Material

- [x] From the host orchestration checkout, inspect the three files owned by the
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
openssl x509 -in "$CERT" -noout -checkhost app.budgetanalyzer.localhost
openssl x509 -in "$CA" -noout -text | rg 'CA:TRUE'
openssl verify -CAfile "$CA" "$CERT"
openssl x509 -in "$CERT" -pubkey -noout | sha256sum
openssl pkey -in "$KEY" -pubout | sha256sum
```

  Success means all files are readable, the leaf remains valid for at least 30
  days, its SAN covers the local hostname, the public root is a CA, verification
  prints `<certificate path>: OK`, and the final two public-key hashes are
  identical. Never print or copy the key contents into the handoff. If renewal
  is needed, use the following certificate-only commands on Mint, then repeat
  the checks above. `setup.sh` recreates Kind and is unnecessary for renewal.

**Mint host terminal, from this repository, only when certificate renewal is needed:**

```bash
mkcert -install
mkdir -p nginx/certs/k8s
mkcert -cert-file nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem \
  -key-file nginx/certs/k8s/_wildcard.budgetanalyzer.localhost-key.pem \
  '*.budgetanalyzer.localhost' budgetanalyzer.localhost
install -m 0644 "$(mkcert -CAROOT)/rootCA.pem" nginx/certs/k8s/_mkcert-rootCA.pem
chmod 600 nginx/certs/k8s/_wildcard.budgetanalyzer.localhost-key.pem
```

  These commands generate host-owned browser certificates only; they do not
  rebuild Kind or update its TLS Secret. Never run them in an agent container
  or the guest. If mkcert or host trust is broken, repair it on Mint first.

- [x] Record the exact three source paths for Checkpoint A. Only those leaf,
  leaf-key and public-root files may be copied to the guest. The host mkcert CA
  signing key (normally named `rootCA-key.pem`) must never enter the guest.

### 5.3 Prepare And Test The Explicit SSH Forward

- [x] First test on unprivileged host port 8443 so any port-443 listener can
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

- [x] Install a narrow host mechanism that permits the current Mint user, only
  when explicitly invoking `authbind`, to bind port 443 on IPv4 loopback
  without running SSH as root. `authbind` cannot restrict this authorization
  by transport protocol or executable; the later `ssh -L` command supplies the
  TCP listener and repeats the explicit loopback address:

**Mint host terminal:**

```bash
sudo apt install authbind
test ! -e /etc/authbind/byport/443
sudo install -o "$USER" -g "$(id -gn)" -m 0500 \
  /dev/null '/etc/authbind/byaddr/127.0.0.1,443'
ls -l '/etc/authbind/byaddr/127.0.0.1,443'
```

  The file must be owned by the current Mint user and executable only by that
  user. The broad `/etc/authbind/byport/443` marker must not exist. If the
  `test` command fails, stop and determine who owns that authorization; if it
  was created while following an earlier version of this plan, remove that
  exact marker before continuing. Do not grant a blanket capability to `ssh`,
  lower the system-wide unprivileged-port threshold or run a root-owned SSH
  client with personal key access.

- [x] Reserve the following command for Checkpoint B, after freeing host port
  443. Do not stop the existing listener to test it during initial setup:

**Mint host terminal:**

```bash
authbind ssh -N -T -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:443:127.0.0.1:443 budget-agent-vm-forward
```

  At Checkpoint B, keep it in a dedicated terminal. In another host
  terminal, `sudo ss -ltnp '( sport = :443 )'` must show only
  `127.0.0.1:443`, never `0.0.0.0`, a LAN address or `[::]:443`. A supervised
  user service may replace the foreground command only after its exact unit is
  reviewed and proves the same binding and `ExitOnForwardFailure` behavior. Do
  not add `--deep`; only the directly invoked SSH client needs the scoped bind
  authorization.

  During Checkpoint A, repeat the test with a temporary TLS fixture using the
  copied approved leaf/key and verify it with the copied public CA. Do not use
  HTTP, `curl --insecure`, browser certificate exceptions or an unverified
  guest-generated certificate.

### 5.4 Create The Dedicated Browser Profile

- [x] Create a clean host browser profile:

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
unprivileged 8443 forwarding fixture succeeds; port-443 forwarding is prepared
for Checkpoint B; and a clean browser profile exists. Real trusted HTTPS remains
pending until Checkpoint A transfers the approved files and Checkpoint B runs
the application acceptance test.

## Initial Handoff

- [x] Capture the version and VM evidence without including the full domain XML
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

- [x] Fill in this redacted handoff template. Use repository basenames, not
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
  UFW active + native bridge-rule order: PASS | FAIL
  Docker backend / bridge matches:
  Docker helper / Docker-start hook / UFW-reload hook:
  DHCP/DNS exceptions:
  guest-to-host IPv4 fixture result:
  guest-to-host IPv6 fixture result:
  guest-to-host Docker fixture result / firewall backend:
  guest Internet positive control:
  host-to-guest SSH positive control:
  guest reboot persistence: PENDING until Checkpoint B
  host reboot persistence: PASS | FAIL | PENDING
  Mint Docker retirement: PENDING until Checkpoint C
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
  current host port-443 listener (if any):
  certificate validity/SAN/chain/key-match checks: PASS | FAIL
  8443 SSH forwarding fixture: PASS | FAIL
  final 443 loopback binding: PASS | FAIL | PENDING
  dedicated browser profile created: PASS | FAIL
```

- [x] Store trusted VM, firewall, SSH and forwarding configuration in
  human-owned host storage outside the guest. The handoff may name settings but
  must omit passwords, tokens, private keys, certificate private-key contents,
  browser state, private remote URLs, personal paths and unrelated host
  configuration.

Provide a redacted handoff for
`docs/plans/agent-host-isolation-acceptance.md` during Phase 1. Do not include
credentials, private keys, browser state or unrelated host configuration.

**Handoff:** From the existing Mint-hosted workspace devcontainer, run
implementation Phases 1–2 only. Keep that devcontainer running and usable; it
remains the implementation runner through Phase 6. These phases add the
separate guest configuration
`ai-agent-sandbox/docker-compose.agent-vm.yml`,
`scripts/setup-agent-vm-repositories.sh`, and exact bootstrap commands. Do not
copy or launch the existing Mint devcontainer configuration in the guest: its
DinD feature and host-workspace mount assumptions belong to the transitional
Mint environment, not the guest target.

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
  guest remote may contain `github.com`. Run `git branch --show-current` in
  each guest working clone and require the selected seed branch; orchestration
  and workspace must use the feature branches containing Phases 1–2.

### A.2 Prove A Full Git Round Trip Without GitHub

- [ ] Choose one non-sensitive repository and require a clean host and guest
  worktree. Save each side's starting branch in its terminal and keep those
  terminals open through cleanup. Start from the selected seed branch; this
  fixture needs no GitHub operation. Before running it, stop if either worktree
  is dirty, either HEAD is detached, the fixture branch exists, or the fixture
  filename is already present. Use the same fixture branch name on both sides:

**Mint host terminal, in the selected host checkout:**

```bash
git status --short
HOST_START_BRANCH="$(git branch --show-current)"
FIXTURE_BRANCH=host-isolation-roundtrip
git switch -c "$FIXTURE_BRANCH"
printf 'host fixture\n' > host-isolation-roundtrip.txt
git add host-isolation-roundtrip.txt
git commit -m 'test: verify host to guest Git transfer'
git push --set-upstream vm "$FIXTURE_BRANCH"
```

**Guest SSH session, in the matching guest working clone:**

```bash
FIXTURE_BRANCH=host-isolation-roundtrip
GUEST_START_BRANCH="$(git branch --show-current)"
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
git diff "$HOST_START_BRANCH"...HEAD -- host-isolation-roundtrip.txt
```

  Success means the log shows both fixture commits, the diff shows both lines,
  and no force, merge commit, rsync or GitHub operation occurred in the guest.
  Record the commit IDs, then clean up only this disposable fixture:

**Guest SSH session, in the matching guest working clone:**

```bash
git switch "$GUEST_START_BRANCH"
git branch -D host-isolation-roundtrip
```

**Mint host terminal, in the selected host checkout:**

```bash
git switch "$HOST_START_BRANCH"
git branch -D host-isolation-roundtrip
git push vm --delete host-isolation-roundtrip
```

  Do not run the cleanup if the branch contains anything except the two known
  fixture commits. Switching back removes the tracked fixture file. Confirm
  both starting branches are restored before continuing bootstrap.

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
./scripts/bootstrap/install-imported-ingress-tls.sh --validate-only
find /srv/budget-analyzer -name rootCA-key.pem -print
```

  Validation must report that the files are valid for
  `app.budgetanalyzer.localhost`, and the final search must print nothing. The
  validator proves the public root is a current CA, the leaf is current and
  covers the hostname, the chain verifies, and the leaf/key pair matches. If
  the implementation changes the documented guest certificate destination,
  use that reviewed destination consistently instead of creating a second
  copy.

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

### A.5 Start The Guest Agent, Then Bootstrap The Application

- [ ] From a human-operated guest SSH session, install the guest-host
  prerequisites outside the agent container. These commands use Ubuntu's
  Docker package plus the same signed NodeSource and Azul package repositories
  as the reviewed workspace image:

**Guest SSH session:**

```bash
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl docker.io docker-compose-v2 git gnupg openssl shellcheck
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

install -d -m 0755 /tmp/budget-analyzer-prerequisites
curl -fsSLo /tmp/budget-analyzer-prerequisites/nodesource.key \
  https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
gpg --dearmor \
  < /tmp/budget-analyzer-prerequisites/nodesource.key \
  > /tmp/budget-analyzer-prerequisites/nodesource.gpg
sudo install -m 0644 /tmp/budget-analyzer-prerequisites/nodesource.gpg \
  /etc/apt/keyrings/nodesource.gpg
echo 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main' |
  sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null

curl -fsSLo /tmp/budget-analyzer-prerequisites/azul.key \
  https://repos.azul.com/azul-repo.key
gpg --dearmor \
  < /tmp/budget-analyzer-prerequisites/azul.key \
  > /tmp/budget-analyzer-prerequisites/azul.gpg
sudo install -m 0644 /tmp/budget-analyzer-prerequisites/azul.gpg \
  /etc/apt/keyrings/azul.gpg
echo 'deb [signed-by=/etc/apt/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main' |
  sudo tee /etc/apt/sources.list.d/zulu.list >/dev/null

sudo apt-get update
sudo apt-get install -y nodejs zulu25-jdk
rm -r /tmp/budget-analyzer-prerequisites
```

  End the SSH session and reconnect so the new `docker` group membership takes
  effect. Do not use `newgrp` to leave an ambiguous nested shell around the
  remaining checkpoint. Then run the Phase 1 read-only preflight from the guest
  orchestration clone:

```bash
cd /srv/budget-analyzer/worktrees/orchestration
./scripts/bootstrap/check-agent-vm-prerequisites.sh
docker info
git --version
java -version
node --version
npm --version
for repo in \
  orchestration budget-analyzer-web ext-authz session-gateway service-common \
  workspace currency-service permission-service transaction-service; do
  test -d "/srv/budget-analyzer/worktrees/$repo/.git"
done
```

  The preflight must confirm Ubuntu 24.04 and reject remote Docker environment
  variables, a non-default context, a non-Unix endpoint, an inactive local
  service, a daemon-name mismatch or a Docker data root other than
  `/var/lib/docker`. It also rejects a forwarded SSH agent, GitHub token/askpass
  variables and a global Git credential helper. Require all version commands to
  succeed. The final loop must verify every basename from the Initial Handoff,
  including `orchestration`, `workspace` and `ext-authz`. Stop on a missing
  prerequisite; do not compensate in orchestration for a service-owned
  failure.

- [ ] Build and start the reviewed guest agent container now, before Kind or
  Tilt, using Phase 2's separate
  `ai-agent-sandbox/docker-compose.agent-vm.yml` instructions. Use only the
  guest Docker socket and guest working/bare repository mounts. The initial
  launch omits the kubeconfig mount because Kind does not exist yet.
  Authenticate the chosen agent provider directly in the guest container,
  without GitHub credentials or host credential forwarding. Ask the guest
  agent to read a guest repository file and require a successful response. This
  proves the target runtime and makes an agent available for guest bootstrap
  diagnosis; it does not move the Phase 1–6 implementation workflow out of the
  existing Mint devcontainer. Keep that Mint devcontainer available through
  Phase 6 and Checkpoint B.

- [ ] From the guest orchestration working clone—not from the agent container—
  validate the imported files once more, then run the explicit guest bootstrap:

```bash
cd /srv/budget-analyzer/worktrees/orchestration
./scripts/bootstrap/install-imported-ingress-tls.sh --validate-only
./setup.sh --guest-local
cd ../budget-analyzer-web
npm install
cd ../orchestration
```

  `./setup.sh --guest-local` repeats local-Docker selection, creates a fresh
  **guest** Kind cluster, installs the copied public root into the guest OS
  trust store, applies the ingress TLS Secret only after exact `kind-kind`,
  loopback API and `kind-control-plane` checks, and generates required
  infrastructure TLS as the human operator in the guest. Configure only
  disposable development `.env` credentials. This command deletes and
  recreates Kind; it is never a daily VM-start command.

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

- [ ] Recreate the agent container with the exact newly generated guest Kind
  kubeconfig mounted, using Phase 2's instructions; authenticate again if
  necessary. Start Tilt from the human-operated guest shell and wait for its
  required resources, using the agent to diagnose failures:

```bash
cd /srv/budget-analyzer/worktrees/orchestration
./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local
tilt up
```

  Keep `tilt up` running, then use another guest shell to run:

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

  Supply the redacted repository, TLS, runtime, live-update and agent-restart
  results to implementation Phases 3 and 6. The full restart/persistence check
  runs once at Checkpoint B.

**Checkpoint A succeeds when:** repository setup and a two-commit round trip
pass without guest GitHub authority; only approved TLS files enter the guest;
verified HTTPS forwarding works; the guest agent responds before application
bootstrap; the guest Kind/Tilt/agent stack is healthy; and Java/frontend live
updates and agent restart work. Host/VM reboot persistence remains pending
until Checkpoint B.

**Handoff:** Continue implementation Phases 3–6 without retiring Mint Docker;
the implementation agents remain hosted by the existing Mint Docker
environment until the complete plan run ends. Guest-runtime proof must still
execute in the VM using the reviewed guest access path. Do not mount host clones
or the host Docker socket into the guest.

## Checkpoint B: Accept Browser And Daily Git Workflow

This happens **after implementation Phase 6** has passed guest validation.

### B.1 Start Host Port 443 Forwarding And Verify The Browser

- [ ] Stop the owner of host port 443 recorded in Step 1. For the existing Kind
  stack, stop host Tilt and the identified Kind node container publishing 443;
  `tilt down` alone does not release the node's Docker port mapping. Keep the
  host Docker daemon and the transitional Step 4 rules running because the
  implementation agents still depend on them. Do not uninstall or disable
  Docker here. Confirm Docker no longer publishes that port and the following
  prints no listener before starting the forward:

**Mint host terminal:**

```bash
sudo ss -ltnp '( sport = :443 )'
```

- [ ] Start the foreground forward and leave it running:

**Mint host terminal 1:**

```bash
authbind ssh -N -T -o ExitOnForwardFailure=yes \
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

### B.2 Confirm Git And Live-Update Results

- [ ] Use A.2's Git round-trip results, A.6's live-update results and Phase 3's
  in-container Git check. Review Phase 6's daily Git commands. Repeat a check
  only if the relevant implementation changed or its earlier result failed.

### B.3 Verify Restart Persistence

- [ ] Shut down the VM, reboot Mint, then start the VM, guest Tilt/agent and the
  foreground HTTPS forward using only the documented daily commands. Repeat:

  - Step 4's native and Docker fixture positive controls and guest denials;
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
firewall, forwarding and credential boundary survive a host reboot. Mint Docker
and its Step 4 protection remain transitional until Checkpoint C.

## Checkpoint C: Establish The Guest-Only Docker Final Architecture

This is the final step. Run it only after all phases of
`agent-host-isolation-plan.md` and Checkpoint B have succeeded, their evidence
has been returned to the host repositories, and every implementation-agent
session that depends on Mint Docker has ended. Do not perform any part of this
checkpoint from an agent container that the commands would stop.

The goal is one Docker daemon in the development architecture: the daemon
inside `budget-analyzer-agent`. Libvirt, UFW, host Git, Remote SSH and the
loopback HTTPS forward remain on Mint. No host Docker image, container, volume,
Kind cluster, database, cache or application state is copied to the guest.

### C.1 Prove The Implementation Is Safe To Cut Over

- [ ] From a normal Mint terminal, confirm all implementation work has been
  saved in the intended host repositories and backed up through the human-owned
  Git workflow. Close host VS Code devcontainers and all implementation-agent
  sessions. Inventory the remaining host containers without stopping them yet:

**Mint host terminal:**

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker volume ls
docker network ls
```

  Stop if any remaining container owns work that has not been returned to a
  host repository or otherwise backed up. Runtime state is deliberately not a
  migration input, but source work must not be stranded inside a container.

- [ ] Prove the guest is independently usable before touching Mint Docker:

**Mint host terminal:**

```bash
ssh budget-agent-vm \
  'docker info >/dev/null && kind get clusters && kubectl get node kind-control-plane'
curl --fail --show-error https://app.budgetanalyzer.localhost/ >/dev/null
```

  Require guest Docker, Kind, the control-plane node and the forwarded
  application request to succeed. Failure is a stop condition, not permission
  to retain a hidden host-runtime dependency.

### C.2 Inventory The Mint Installation And Its Cleanup Targets

- [ ] Record how Docker was installed before selecting an uninstall command.
  Do not assume Docker CE, distribution `docker.io` or a standalone binary:

**Mint host terminal:**

```bash
systemctl is-active docker.service docker.socket containerd.service
systemctl is-enabled docker.service docker.socket containerd.service
docker info --format 'DockerRootDir={{.DockerRootDir}}'
dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\t${Version}\n' 2>/dev/null | \
  rg '^ii\s+(docker|containerd|runc)'
getent group docker || true
sudo du -sh /var/lib/docker /var/lib/containerd 2>/dev/null || true
sudo readlink -f /var/lib/docker /var/lib/containerd 2>/dev/null || true
sudo findmnt --target /var/lib/docker 2>/dev/null || true
sudo findmnt --target /var/lib/containerd 2>/dev/null || true
sudo ls -ld /etc/docker 2>/dev/null || true
sudo ls -l /etc/apt/sources.list.d/docker.sources \
  /etc/apt/sources.list.d/docker.list \
  /etc/apt/keyrings/docker.asc \
  /etc/apt/keyrings/docker.gpg 2>/dev/null || true
```

  Require Docker's reported data root and resolved path to be
  `/var/lib/docker`; stop and amend the reviewed cleanup if either differs.
  Record the installed Docker package family and whether `containerd`/`runc`
  has any non-Docker consumer. Stop for review rather than removing a shared
  runtime. Do not print Docker client configuration because it may contain
  registry credentials; inspect it privately and remove Docker-only credentials
  during cleanup.

### C.3 Stop And Disable Mint Docker

- [ ] Stop the reviewed host containers, then disable both activation paths.
  Use the exact container names from C.1; do not use a blanket container-removal
  command while an unidentified workload remains.

**Mint host terminal, after the reviewed containers are stopped:**

```bash
sudo systemctl disable --now docker.service docker.socket
! systemctl is-active --quiet docker.service
! systemctl is-active --quiet docker.socket
test ! -S /var/run/docker.sock
! docker info >/dev/null 2>&1
sudo ss -ltnp '( sport = :80 or sport = :443 )'
curl --fail --show-error https://app.budgetanalyzer.localhost/ >/dev/null
ssh budget-agent-vm 'docker info >/dev/null'
```

  Port 80 must have no old Docker listener. Port 443 may show only the existing
  `127.0.0.1:443` SSH forward. The host Docker query must fail while the guest
  Docker query and application request continue to succeed. Do not disable
  `containerd.service` until C.2 proves it belongs only to the retired Docker
  installation.

### C.4 Uninstall Mint Docker And Remove Retired Runtime State

- [ ] Purge only the package family proven by C.2. For an official Docker CE
  installation whose `containerd.io` has no other consumer, use the package set
  from Docker's
  [official uninstall guidance](https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine):

**Mint host terminal, Docker CE installations only:**

```bash
sudo apt purge \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
  docker-compose-plugin docker-ce-rootless-extras
```

  For a distribution `docker.io` installation, use the installed package list
  from C.2 instead; do not run the Docker CE command as a substitute. Review any
  `apt` autoremove proposal before accepting it, and do not remove a shared
  `containerd` or `runc` package.

- [ ] Package removal does not delete Docker runtime data. After confirming one
  final time that no host runtime data is an approved retention item, remove
  the exact retired Docker data root. Remove the containerd data root only when
  C.2 proved it was exclusive to this Docker installation. These deletions are
  irreversible:

**Mint host terminal:**

```bash
test "$(sudo readlink -f /var/lib/docker)" = '/var/lib/docker'
if sudo test -d /var/lib/docker; then
  sudo du -sh /var/lib/docker
fi
sudo rm -rf -- /var/lib/docker
```

**Mint host terminal, only for an exclusive retired containerd installation:**

```bash
test "$(sudo readlink -f /var/lib/containerd)" = '/var/lib/containerd'
if sudo test -d /var/lib/containerd; then
  sudo du -sh /var/lib/containerd
fi
sudo rm -rf -- /var/lib/containerd
```

- [ ] If C.2 identified Docker-owned APT source/key files, inspect each exact
  path and remove only those files. Remove the Mint user's Docker registry
  credentials and client configuration only after private review confirms they
  are not used for another Docker endpoint. Inspect and remove `/etc/docker`
  only when it contains configuration solely for the retired daemon. If the
  `docker` group remains, remove the Mint user from it and delete the group only
  after confirming it has no remaining purpose; the final reboot clears cached
  supplementary groups.

### C.5 Remove The Transitional Docker Firewall Integration

- [ ] Remove the UFW reload hook before deleting the helper it invokes. Inspect
  `/etc/ufw/after.init`. If Step 4 created the whole file and it
  still contains only the reviewed Docker helper hook, remove that exact file.
  If Step 4 merged the hook into a pre-existing file, edit out only the Docker
  helper behavior and preserve the pre-existing policy. Do not remove the UFW
  `virbr1` DNS/DHCP/deny rules: they remain the permanent native host boundary.
  Validate any retained script before reloading UFW:

**Mint host terminal:**

```bash
sudo sed -n '1,240p' /etc/ufw/after.init
```

**Mint host terminal, when preserving a pre-existing edited file:**

```bash
sudo sh -n /etc/ufw/after.init
sudo shellcheck /etc/ufw/after.init
sudo ufw reload
sudo ufw status numbered
```

**Mint host terminal, only when Step 4 created the entire dedicated file:**

```bash
sudo rm -- /etc/ufw/after.init
sudo ufw reload
sudo ufw status numbered
```

- [ ] After UFW reload succeeds without the Docker hook, remove the helper and
  Docker service drop-in installed by Step 4:

**Mint host terminal:**

```bash
sudo ls -l /usr/local/sbin/agent-vm-docker-isolation \
  /etc/systemd/system/docker.service.d/agent-vm-isolation.conf
sudo rm -- /usr/local/sbin/agent-vm-docker-isolation
sudo rm -- /etc/systemd/system/docker.service.d/agent-vm-isolation.conf
sudo rmdir --ignore-fail-on-non-empty \
  /etc/systemd/system/docker.service.d
sudo systemctl daemon-reload
```

  Do not manually flush or delete Docker chains. Stopping/uninstalling Docker
  and the final reboot own their removal; UFW and libvirt continue to own their
  separate rules.

### C.6 Reboot And Accept The Guest-Only Final State

- [ ] Reboot Mint, start the VM, guest Tilt/agent and loopback HTTPS forward
  using only the documented daily commands, then run:

**Mint host terminal:**

```bash
! systemctl is-active --quiet docker.service
! systemctl is-active --quiet docker.socket
test ! -S /var/run/docker.sock
! command -v docker >/dev/null 2>&1
! dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null | \
  rg -q '^ii\s+(docker-ce|docker.io|docker-buildx|docker-compose)'
! sudo iptables -S | rg -q '(^-N DOCKER| -j DOCKER)'
! sudo ip6tables -S | rg -q '(^-N DOCKER| -j DOCKER)'
sudo ufw status numbered
sudo ss -ltnp '( sport = :80 or sport = :443 )'
curl --fail --show-error https://app.budgetanalyzer.localhost/ >/dev/null
ssh budget-agent-vm \
  'docker info >/dev/null && kind get clusters && kubectl get node kind-control-plane'
```

  Require no host Docker command, package, socket, service, chain or port-80
  listener; require only the loopback SSH forward on host port 443. The
  permanent UFW bridge rules, guest Docker/Kind node and trusted application
  request must still pass. When C.2 proved `containerd.io` was Docker-exclusive,
  also require that package and `/var/lib/containerd` to be absent. When a
  non-Docker consumer required a containerd package, record the narrowly scoped
  exception rather than misreporting it as Docker Engine.

- [ ] Update `docs/plans/agent-host-isolation-acceptance.md` through the normal
  host Git workflow with the package family removed, the explicit data and
  transitional-file cleanup results, final reboot evidence and the guest-only
  runtime result. Do not record registry credentials or a full firewall dump.

**Checkpoint C succeeds when:** all implementation agents have finished; Mint
has no Docker daemon, socket, CLI, installed engine packages, Docker firewall
chains or retained runtime state; the transitional Step 4 helper/hooks are
gone; the permanent UFW/libvirt boundary remains; and guest Docker, Kind,
trusted HTTPS and the daily Git/editor workflow pass after the final reboot.

Daily use starts the VM, guest Tilt/agent, Remote SSH editor and HTTPS forward.
For a task, the host updates `main`, creates a feature branch and explicitly
pushes it to `vm`; the guest agent commits and pushes only to its guest-local
bare `origin`; the host fetches and fast-forwards, then separately reviews,
pushes to GitHub and creates the PR. Do not rerun the one-time repository setup,
`setup.sh`, certificate generation or any source synchronization for ordinary
daily work.
