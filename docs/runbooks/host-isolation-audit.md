# Personal-Host Isolation Audit

This runbook owns evidence collection and review of the boundary between the
personal Mint workstation and the root-capable development VM. The completed
[migration acceptance](../plans/agent-host-isolation-acceptance.md#native-human-acceptance)
is operator-attested. The subsequent review of firewall rule ordering and
protocol coverage is a separate audit; neither a successful collector exit nor
passed guest application tests constitute that audit's acceptance.

## Collect On The Personal Host

Use a normal **personal-host terminal** and a reviewed personal-host checkout.
Transfer source through the existing human-owned Git workflow; review the script
before running it. Do not give this guest a host SSH identity, mount, credential
or remote administration path. The agent must not execute the live collector.

```bash
sudo -v
python3 scripts/ops/collect-host-isolation-evidence.py --confirm-personal-host
```

Defaults are libvirt domain `budget-analyzer-agent` and network `agent-nat`.
If discovery shows different names, pass `--domain NAME --network NAME`.
The collector requires Mint on the physical host, the normal user, existing
sudo authorization and installed inspection tools. It does not install tools,
change rules, reload services, start Docker, connect to the guest, start
listeners, generate certificates or probe other machines. It writes only a new
private `budget-host-audit-*` directory under the host home. An optional
`--output-parent /absolute/private/directory` must select an existing canonical
user-owned directory outside the checkout, with no group/world write access.

It captures the live IPv4/IPv6 rules, nftables and available legacy tables,
backend versions, UFW before/user/after configuration, addresses/routes,
listeners, live/persistent VM and network definitions, AppArmor/process labels,
UFW persistence and evidence of Docker retirement. The package section reports
only installed Docker engine/CLI, containerd and runc families and distinguishes
an empty result from a failed query. Reads use `sudo -n`; failure or a 30-second
command timeout is recorded. Required failures make the exit nonzero. Optional
missing retired Docker policy files or UFW hook files are recorded for review;
absence is never a filtering pass.

## Review And Return Evidence

The output directory and raw captures are private. Keep raw captures and
`index.json` on the personal host, outside Git and guest-accessible storage.
The index contains capture hashes for host-side comparison, not proof of a
trusted collector or unchanged future policy.

Privately inspect `candidate-report.md` before sharing it. Redaction removes
MACs, UUIDs, public IP literals, common personal path prefixes and full rule
comments. It consistently aliases the selected domain, network, bridge and tap
while preserving their relationships and CIDR masks; VM XML is reduced to
relevant structure. It intentionally retains private, loopback, link-local and
multicast addresses, rule order, protocol, ports, counters, chain/set names and
process names. **This is best-effort redaction, not a secret scanner**: other
interfaces, hostnames, unusual paths and string-match rules may still identify
private information. Manually redact those with consistent labels. Full XML,
systemd unit text and UFW hooks remain private-only; provide a manually redacted
excerpt if the reviewer needs them.

Return only the reviewed candidate report through an explicit human transfer
or paste its relevant sections. For a guest-local file, keep it under ignored
`tmp/host-isolation-audit/`; do not commit raw or full redacted rule dumps into
the acceptance record. If the report is large, provide it in numbered sections
without dropping rule order. Do not upload the private directory or index.

## Review The Effective Boundary

The reviewer must account for these paths before an isolation conclusion:

1. Match the guest's live and persistent network attachment to the dedicated
   host bridge. Compare live and persistent definitions; require active
   AppArmor confinement, no host filesystem/device passthrough, clipboard,
   file transfer, unexpected channels or custom QEMU integrations. Inspect
   the private full XML when the structural summary flags an integration or
   cannot establish disk/confinement details. Configuration alone is not
   proof of live enforcement. Keep hypervisor, host kernel, SSH, browser and
   editor security updates current; this audit cannot rule out unknown flaws.
2. Follow actual packet traversal through nftables base chains and every
   applicable iptables backend, including raw/mangle/NAT/filter, INPUT and
   FORWARD. Determine effective interface matching, jumps, priorities and
   terminal verdicts. Check IPv4 and IPv6 independently. `ufw status` does not
   expose the full earlier rule path.
3. Account for UFW before-rules and libvirt-inserted rules before the bridge
   deny. Look specifically for mDNS UDP 5353, SSDP UDP 1900, other multicast,
   broadcast, ICMP and established/related exceptions. Require narrow needed
   DHCP, gateway DNS and IPv6 neighbor-discovery allowances. Do not block
   essential IPv6 traffic by guessing. Check exceptions cannot admit unrelated
   host services, including services added later.
4. Inspect all host addresses, routes, listeners and alternate interfaces.
   Explain any DNAT, forwarding or alternate path back to host services. With
   Mint Docker retired, establish absence of its engine/socket, listeners,
   bridge rules and hooks; do not restart it to reproduce obsolete fixtures.
   LAN/VPN peer isolation and Internet allowlisting remain outside the stated
   contract; do not silently expand the firewall scope.
5. Review persistent UFW inputs and service activation, then compare live rules
   after a human-owned reboot. Host firewall files remain host-owned and outside
   guest-writable source. A policy defect requires a concrete, separately
   reviewed human-applied repair; this collector never repairs policy.
6. Retain the dedicated SSH/editor/browser boundaries from the migration:
   strict host keys, no agent/X11/credential forwarding, no automatic editor
   port forwarding, reviewed extensions, loopback HTTPS forwarding and the
   dedicated browser profile. Those intentional host clients process
   guest-controlled data; firewall isolation does not eliminate that residual
   attack surface. Host review precedes publication or execution of guest code.

## Confirmed Finding Baseline

The privately reviewed post-migration report establishes two policy defects:
IPv4 and IPv6 mDNS/SSDP accepts occur before the intended UFW user-input bridge
deny, and libvirt accepts bridge-originated TCP/UDP ports 53 and 67 before the
narrower UFW rules. Those paths are reachable in policy. The report does **not**
establish that a guest datagram was delivered to Avahi, DNS, DHCP or any other
listener. Preserve that distinction in every result.

The same report positively supports live AppArmor confinement, no reported host
filesystem/device passthrough and loopback-only app/VNC listeners. Those are
separate controls, not a firewall pass. It also contradicts final Mint Docker
retirement because inactive units coexist with retained bridge/rules and policy
files. Keep both firewall findings and retirement open until the repair,
reconciliation and repeated post-reboot evidence below pass.

## Human-Owned Firewall Repair Contract

Perform this work only from the personal host after all affected workers stop
and the reviewed repository changes have returned through the human Git flow.
An agent must not apply, reload or test host policy. Do not install a repository
file as host policy: create the final source in a root-owned host directory,
review every concrete value there and keep it inaccessible to the guest.

Before host repair, complete the workspace-owned
[Phase 5 native source refresh](../../../workspace/docs/native-user-tools.md#phase-5-native-source-refresh)
and the orchestration
[Phase 3/4 trust handoff](../development/local-environment.md#phase-34-human-trust-handoff)
from fresh guest shells. Both are human installation steps after workers stop;
offline phase results are not live installation evidence. Stop if the repeated
native user install, sole-managed-CA check or verified curl/Python/Node/browser
matrix fails.

The durable enforcement point must be one dedicated nftables `inet` input base
chain at priority `-190`. That is after conntrack is available and before the
normal mangle/DNAT/filter priorities used by the observed libvirt and UFW input
paths. A verdict from an earlier base chain does not exempt the packet from this
later hook. Read back every active hook and prove that the selected chain sees
VM bridge/tap input before the observed `LIBVIRT_INP` DNS/DHCP accepts and UFW
multicast/before-rule accepts. If any installed nft, iptables-nft or legacy
backend can accept a VM-originated host-input path without subsequently
traversing this hook, stop; the proposed repair is incomplete.

An ordinary UFW user rule or a change only to UFW before-rules is not an
acceptable repair. Do not flush UFW, libvirt, nftables or either iptables
backend. Keep LAN/VPN peer and Internet policy outside this repair.

### Discover Concrete Inputs

Use private shell variables and record only reviewed aliases in returned
evidence. Select one domain after comparing `virsh list --all` with its live and
persistent XML; do not infer names from this runbook.

```bash
read -r -p 'Reviewed development VM domain: ' vm_domain
vm_network=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" |
  awk '$2 == "network" {print $3}')
vm_tap=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" |
  awk '$2 == "network" {print $1}')
vm_mac=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" |
  awk '$2 == "network" {print $5}')
test "$(printf '%s\n' "$vm_network" | sed '/^$/d' | wc -l)" -eq 1
test "$(printf '%s\n' "$vm_tap" | sed '/^$/d' | wc -l)" -eq 1
test "$(printf '%s\n' "$vm_mac" | sed '/^$/d' | wc -l)" -eq 1
vm_bridge=$(sudo virsh --connect qemu:///system net-info "$vm_network" |
  awk '$1 == "Bridge:" {print $2}')
test -n "$vm_bridge"
ip -details link show dev "$vm_bridge"
ip -details link show dev "$vm_tap"
ip -4 -o address show dev "$vm_bridge"
ip -6 -o address show dev "$vm_bridge"
sudo virsh --connect qemu:///system net-dhcp-leases "$vm_network" --mac "$vm_mac"
sudo virsh --connect qemu:///system dumpxml "$vm_domain"
sudo virsh --connect qemu:///system net-dumpxml "$vm_network"
```

Stop if the domain has zero/multiple network interfaces, another domain shares
the supposedly dedicated network, live and persistent attachments differ, the
tap/bridge cannot be mapped, or DHCP/DNS/IPv6 behavior is not understood. From
the guest, record its current IPv4/IPv6 addresses, default routes, DNS server and
link-layer address. Reconcile those with the host output before authoring rules.

Inspect all active input hooks and all installed backends before choosing the
allowlist:

```bash
sudo nft -a list ruleset
sudo iptables-save -c
sudo ip6tables-save -c
command -v iptables-legacy-save >/dev/null && sudo iptables-legacy-save -c
command -v ip6tables-legacy-save >/dev/null && sudo ip6tables-legacy-save -c
sudo ufw show raw
sudo sed -n '1,240p' /etc/ufw/before.rules
sudo sed -n '1,260p' /etc/ufw/before6.rules
```

### Author And Validate The Minimum Policy

The concrete root-owned nft source must use the stable discovered dedicated
bridge and the selected VM MAC as an anti-spoof constraint. Keep the current tap
for scoped capture/attribution; do not bake an ephemeral tap name or a broad tap
wildcard into persistent policy. If scoped counters show that host-input packets
arrive on the tap instead of the bridge, stop and design a separately reviewed
fail-closed dynamic binding rather than broadening this contract. The chain must
contain, in this order:

1. Drop bridge input whose source MAC is not the selected VM MAC.
2. Allow only `ct state established,related`; this permits replies to
   host-initiated SSH and other reviewed host-to-guest flows, not new guest
   connections.
3. Allow guest-source TCP and UDP DNS only to the discovered gateway address on
   destination port 53. Create separate IPv4/IPv6 rules only where that family
   is actually configured and tested.
4. Allow IPv4 DHCP only from the selected MAC, UDP client port 68 to server port
   67, with source `0.0.0.0` or the assigned guest address and only the observed
   gateway/broadcast destinations. If DHCPv6 is in use, allow only the observed
   client-port-546/server-port-547 flow to its reviewed link-local/multicast
   destination.
5. Allow only observed, required ICMPv6 control types. Derive these from the
   working network and scoped capture; name each numeric type and purpose in the
   source. Do not copy a generic all-ICMPv6 exception or guess that IPv6 is
   inapplicable because no global route exists.
6. Count and drop mDNS UDP 5353 and SSDP UDP 1900 explicitly in each applicable
   family, then count and drop every other VM-originated host-input packet.

Use the non-identifying table and chain names below. Replace every uppercase
network token with one reviewed concrete value and omit only family-specific
blocks proven inapplicable. This is a contract, not an installable policy file.

```nft
table inet budget_agent_host_input {
  chain early_vm_host_input {
    type filter hook input priority -190; policy accept;

    iifname "VM_BRIDGE" ether saddr != VM_MAC counter drop
    iifname "VM_BRIDGE" ct state established,related counter accept

    iifname "VM_BRIDGE" ether saddr VM_MAC ip saddr GUEST_V4 \
      ip daddr GATEWAY_V4 meta l4proto { tcp, udp } th dport 53 counter accept
    iifname "VM_BRIDGE" ether saddr VM_MAC \
      ip saddr { 0.0.0.0, GUEST_V4 } ip daddr { GATEWAY_V4, DHCP_BROADCAST_V4 } \
      udp sport 68 udp dport 67 counter accept

    iifname "VM_BRIDGE" ether saddr VM_MAC ip6 saddr GUEST_V6 \
      ip6 daddr GATEWAY_V6 meta l4proto { tcp, udp } th dport 53 counter accept
    iifname "VM_BRIDGE" ether saddr VM_MAC ip6 saddr GUEST_V6 \
      ip6 daddr DHCPV6_DESTINATION udp sport 546 udp dport 547 counter accept
    iifname "VM_BRIDGE" ether saddr VM_MAC ip6 saddr GUEST_V6 \
      icmpv6 type { REVIEWED_NUMERIC_TYPES } counter accept

    iifname "VM_BRIDGE" udp dport { 1900, 5353 } counter drop
    iifname "VM_BRIDGE" counter drop
  }
}
```

Create the final policy at
`/etc/nftables.d/budget-agent-host-input.nft` and a root-owned loader under
`/usr/local/sbin/`. The loader must build one atomic nft batch: when the custom
table exists, prepend deletion of only that table, append the complete table
definition, run `nft --check -f` on the batch, and only then run `nft -f` on the
same bytes. A validation or apply failure must leave the previous live table in
place. It must never flush a ruleset or delete another table.

The reviewed loader implementation is:

```sh
#!/bin/sh
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
policy=/etc/nftables.d/budget-agent-host-input.nft
table_family=inet
table_name=budget_agent_host_input
mode=${1:-apply}

test "$(id -u)" -eq 0
test -f "$policy"
test ! -L "$policy"
test "$(stat -c '%U:%G' "$policy")" = root:root
case "$(stat -c '%a' "$policy")" in
  600|640) ;;
  *) printf 'ERROR: unsafe policy mode\n' >&2; exit 1 ;;
esac
case "$mode" in
  apply|--check-only) ;;
  *) printf 'usage: %s [--check-only]\n' "$0" >&2; exit 2 ;;
esac

work_dir=$(mktemp -d /run/budget-agent-host-input.XXXXXX)
batch=$work_dir/batch.nft
cleanup() {
  rm -f -- "$batch"
  rmdir -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if nft list table "$table_family" "$table_name" >/dev/null 2>&1; then
  printf 'delete table %s %s\n' "$table_family" "$table_name" >"$batch"
else
  : >"$batch"
fi
cat "$policy" >>"$batch"
nft --check -f "$batch"
sha256sum "$batch"
test "$mode" = --check-only && exit 0
nft -f "$batch"
```

The check and apply operate on the same generated bytes in one invocation. The
nft batch is atomic; a failed check or apply does not partially replace the
live table. The temporary path is fixed under `/run`, created by `mktemp` and
removed without a recursive delete.

Create a oneshot systemd unit with `RemainAfterExit=yes` whose `ExecStart` and
`ExecReload` call that loader. Order it before UFW and every installed libvirt
service/socket capable of creating the network or starting the domain. Add
`Requires=` and `After=` drop-ins from those discovered libvirt units/sockets to
the enforcement unit. This makes a boot-time load failure prevent the VM path
from starting rather than expose it. Discover the applicable unit set; do not
assume monolithic versus modular libvirt:

```bash
systemctl list-unit-files 'libvirt*' 'virtqemu*' 'virtnetwork*'
systemctl list-dependencies --reverse --all libvirtd.service 2>/dev/null || true
systemctl list-dependencies --reverse --all virtqemud.service 2>/dev/null || true
systemctl list-dependencies --reverse --all virtnetworkd.service 2>/dev/null || true
```

Use this exact unit body at
`/etc/systemd/system/budget-agent-host-input.service`:

```systemd
[Unit]
Description=Early development-VM host-input policy
After=local-fs.target
Before=ufw.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/load-budget-agent-host-input
ExecReload=/usr/local/sbin/load-budget-agent-host-input
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

For every discovered libvirt service **and socket** that can start the selected
network or domain, add a root-owned systemd drop-in containing exactly:

```systemd
[Unit]
Requires=budget-agent-host-input.service
After=budget-agent-host-input.service
```

Do not add a guessed unit. The discovered set is part of the private handoff;
omitting an applicable activation socket is a fail-open defect.

Before initial application, require all policy, loader, unit and drop-in files
to be regular, non-symlinked `root:root` files with no group/world write bit.
Validate the loader with `sh -n` and ShellCheck, run the loader's nft check-only
path, then review the complete generated batch. Back up the replaced host files
under a root-only host directory and record their hashes. Do not copy backups,
policy source or full rules into the guest.

Shut down the selected VM before the first apply. Do not restart its network,
domain or activation sockets until the policy service is active, the complete
table read-back matches review and every applicable libvirt drop-in reports the
required dependency. A failed initial load therefore leaves no running guest
path on the old defective boundary.

Run these review gates against the concrete host paths before enabling or
starting anything:

```bash
sudo stat -c '%U:%G %a %N' \
  /etc/nftables.d/budget-agent-host-input.nft \
  /usr/local/sbin/load-budget-agent-host-input \
  /etc/systemd/system/budget-agent-host-input.service
sudo test ! -L /etc/nftables.d/budget-agent-host-input.nft
sudo test ! -L /usr/local/sbin/load-budget-agent-host-input
sudo test ! -L /etc/systemd/system/budget-agent-host-input.service
sudo sh -n /usr/local/sbin/load-budget-agent-host-input
sudo shellcheck /usr/local/sbin/load-budget-agent-host-input
sudo systemd-analyze verify /etc/systemd/system/budget-agent-host-input.service
sudo /usr/local/sbin/load-budget-agent-host-input --check-only
```

Expected output is `root:root` with no group/world write bit, no symlink, and
zero exits from every validator. The loader's check-only mode must print the
complete intended batch location/hash without applying it. After private review,
the human may apply and inspect it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now budget-agent-host-input.service
sudo systemctl is-enabled budget-agent-host-input.service
sudo systemctl is-active budget-agent-host-input.service
sudo nft -a list table inet budget_agent_host_input
systemctl show budget-agent-host-input.service -p Before -p ActiveState -p UnitFileState
```

Expected service states are `enabled` and `active`; the nft read-back must show
one input hook at priority `-190`, only the reviewed allow rules, explicit
mDNS/SSDP counters and the final drop. Verify each discovered libvirt unit and
socket reports the custom service in `Requires` and `After`. Do not proceed on
a warning, inactive dependency or output that differs from the reviewed batch.

After human application, read back the actual hook, priority, handles and
counters with `sudo nft -a list table inet budget_agent_host_input`, then inspect every
backend command above again. Confirm UFW and libvirt rules remain present and
the custom table precedes their permissive input paths. A load error, missing
dependency, changed interface/address, unexpected earlier terminal path,
unexplained counter, lost positive flow or broader-than-listed allow rule is a
stop condition.

### Persistence And Rollback Boundary

With workers stopped, prove the custom table and dependency remain effective
after each event: `sudo ufw reload`; a controlled stop/start of only the selected
libvirt network while its domain is shut down; and the final personal-host
reboot. Re-read the hook order and rerun the full matrix after the reboot. Never
reload by flushing the ruleset.

Rollback is permitted only to the reviewed prior files, not to an open rule.
If an allowed flow fails, shut down the VM first, preserve private diagnostics,
restore the exact root-owned backup and its hashes, validate it, then use the
normal host service lifecycle. Do not keep the VM running while deleting or
bypassing the early policy, and do not weaken LAN/VPN policy as compensation.

## Reconcile Final Mint Docker Retirement

Do not invoke the Docker CLI: an apparently harmless command can activate the
socket. First prove both activation paths inactive and inventory packages,
consumers and data without starting Docker:

```bash
systemctl is-active docker.service docker.socket containerd.service || true
systemctl is-enabled docker.service docker.socket containerd.service || true
test ! -S /var/run/docker.sock
dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' 2>/dev/null |
  awk -F '\t' 'substr($2, 2, 1) == "i" && $1 ~ /^(docker|containerd|runc|moby)/'
apt-cache rdepends --installed containerd containerd.io runc 2>/dev/null
systemctl list-dependencies --reverse --all containerd.service 2>/dev/null || true
sudo readlink -f /var/lib/docker /var/lib/containerd
sudo findmnt --target /var/lib/docker || true
sudo findmnt --target /var/lib/containerd || true
sudo du -shx /var/lib/docker /var/lib/containerd 2>/dev/null || true
```

Name every non-Docker consumer before retaining containerd or runc. A package
dependency alone is not a runtime consumer. Retention evidence must identify the
owning package/service and prove it does not start Docker, create `docker0`, add
Docker chains or repopulate the retired data root.

Build and privately review four exact lists: installed Docker engine/CLI and
exclusive runtime packages; Docker-owned source/key/config files; the canonical
Docker data root plus exclusively Docker-owned containerd data; and the three
transitional policy locations from manual-plan D.3. Simulate package purge and
review autoremove before applying it. Quarantine each validated data root by an
exact canonical path in a root-only host location before eventual deletion; do
not use a wildcard, unfiltered prune or recursive command against a variable
that has not been printed and confirmed.

Put only exact discovered package names in the array, print it, and review the
simulation. An empty array means no package action; any proposed unrelated
removal is a stop condition.

```bash
retired_docker_packages=(EXACT_PACKAGE_NAMES_REPLACE_THIS_TOKEN)
printf 'retire package: %s\n' "${retired_docker_packages[@]}"
sudo apt-get --simulate purge -- "${retired_docker_packages[@]}"
```

After explicit human confirmation, rerun the same `apt-get purge` command
without `--simulate`. Do not accept an autoremove proposal until every package
has been classified. Keep retained containerd/runc out of the array.

Remove only the retired Docker-isolation invocation from UFW's existing hook and
preserve all unrelated content. Validate that retained hook with `sh -n` and
ShellCheck. Remove only the reviewed Docker service drop-in and isolation helper
after the new VM input policy has passed pre-reboot checks. Run daemon-reload;
do not reload/start Docker and do not remove UFW or libvirt. If any file differs
from the reviewed backup, a retained hook cannot be explained, or the Docker
root resolves unexpectedly, stop before removal.

Use a root-only quarantine so the policy-file and data moves remain recoverable
until post-reboot acceptance. Replace the uppercase data path only with the
printed canonical path reviewed above:

```bash
sudo install -d -o root -g root -m 0700 /root/budget-agent-retirement-review
sudo cp --archive /etc/ufw/after.init \
  /root/budget-agent-retirement-review/ufw-after.init.before
sudoedit /etc/ufw/after.init
sudo sh -n /etc/ufw/after.init
sudo shellcheck /etc/ufw/after.init
sudo mv -- /etc/systemd/system/docker.service.d/agent-vm-isolation.conf \
  /root/budget-agent-retirement-review/
sudo mv -- /usr/local/sbin/agent-vm-docker-isolation \
  /root/budget-agent-retirement-review/
sudo mv -- EXACT_CANONICAL_DOCKER_DATA_ROOT \
  /root/budget-agent-retirement-review/docker-data
sudo systemctl daemon-reload
```

Move containerd data only when its exclusive Docker ownership was established.
Move each reviewed Docker package source, key and daemon configuration into the
same quarantine with its relative identity recorded; do not use a wildcard. A
missing expected source, cross-filesystem surprise, destination collision or
attempt to move `/`, `/var`, `/var/lib` or guest data is a stop condition.

After reboot, final retirement evidence must show all of the following:

- `docker.service` and `docker.socket` are not found, inactive and disabled;
  `/var/run/docker.sock` and the `docker` CLI are absent.
- No installed Docker engine/CLI package remains. Retained containerd/runc has
  the named non-Docker consumer evidence above.
- `docker0`, every Docker nft/legacy chain and Docker-created listener is
  absent in both address families/backends.
- The reviewed Docker data root, exclusive retired containerd data, isolation
  helper, Docker service drop-in and UFW hook invocation are absent.
- The early VM host-input table, UFW/libvirt policy and required guest flows
  remain healthy.

If any post-reboot check fails, keep the quarantine and follow the rollback
boundary; do not start Docker. Only after the complete post-reboot matrix and
guest/host positives pass, privately list and confirm the fixed quarantine path,
then remove that one reviewed tree and prove it absent:

```bash
sudo find /root/budget-agent-retirement-review -xdev -print
read -r -p 'Type DELETE-REVIEWED-DOCKER-QUARANTINE: ' retirement_confirmation
test "$retirement_confirmation" = DELETE-REVIEWED-DOCKER-QUARANTINE
sudo rm -rf -- /root/budget-agent-retirement-review
sudo test ! -e /root/budget-agent-retirement-review
```

This is the irreversible boundary. Stop if the listing contains anything not
on the retirement inventory; do not broaden or parameterize the removal target.

Host Docker-path fixtures are now **inapplicable**. Record absence evidence;
never revive Docker to obtain a historical test result.

Collect the final absence result without invoking Docker:

```bash
! command -v docker
test ! -S /var/run/docker.sock
! ip link show docker0 >/dev/null 2>&1
systemctl show docker.service docker.socket \
  -p Id -p LoadState -p ActiveState -p UnitFileState
dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' 2>/dev/null |
  awk -F '\t' 'substr($2, 2, 1) == "i" && $1 ~ /^(docker|containerd|runc|moby)/'
sudo nft list ruleset | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
sudo iptables-save | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
sudo ip6tables-save | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
command -v iptables-legacy-save >/dev/null && \
  sudo iptables-legacy-save | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
command -v ip6tables-legacy-save >/dev/null && \
  sudo ip6tables-legacy-save | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
sudo test ! -e /usr/local/sbin/agent-vm-docker-isolation
sudo test ! -e /etc/systemd/system/docker.service.d/agent-vm-isolation.conf
sudo rg -n 'agent-vm-docker-isolation' /etc/ufw/after.init && exit 1 || true
```

The `systemctl show` output must be inactive with no enabled activation path;
engine/CLI package and every chain search must be empty. Any retained
containerd/runc line must map to the previously named non-Docker consumer.
Check the separately recorded canonical data/quarantine paths explicitly; they
are intentionally not represented by a generic deletion command here.

## Prove Protocol Behavior After Rule Review

Use the original manual plan's
[paired native listener tests](../plans/agent-vm-native-manual-plan.md#a3-revalidate-host-isolation)
as the TCP baseline, but bind each server to the selected VM-facing host address
rather than a wildcard. Do not recreate retired host Docker.

For each family, use an unused high port and an empty host directory. Start the
listener on the selected VM-facing address, prove it locally, then issue the
guest attempt while recording the early catch-all counter before and after:

```bash
tcp_fixture_dir=$(mktemp -d)
python3 -m http.server UNUSED_PORT --bind HOST_VM_ADDRESS \
  --directory "$tcp_fixture_dir"
curl --noproxy '*' --fail --max-time 3 \
  http://HOST_VM_ADDRESS:UNUSED_PORT/
sudo nft -a list table inet budget_agent_host_input
```

Use bracketed syntax for an IPv6 curl URL. From the guest, run
`nc -4 -vz -w 3 HOST_V4 UNUSED_PORT` or the corresponding `nc -6` command with
an interface scope for link-local IPv6. A reject/timeout plus the expected
counter delta is a denial; an unreachable route is not. Stop the server and
remove only its empty temporary directory afterward.

For UDP, use `scripts/ops/host-isolation-protocol-fixture.py` only after filling
in the reviewed family, interface, source/destination addresses and unused port.
It sends only a fixed non-protocol prefix plus a random nonce. The listener
rejects wildcard addresses, occupied ports and ambiguous multicast membership;
it exits `1` if the expected guest payload arrives, `3` when the positive
control is missing and `0` only for receiver non-delivery after a positive
control. Exit `0` is still not a firewall pass without an independently observed
early-policy counter delta or exact-interface scoped capture for that guest
attempt.

Generate two non-secret nonces on the host:

```bash
control_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
probe_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
test "$control_nonce" != "$probe_nonce"
```

For each unicast UDP family, start the listener in one host terminal with the
selected host and guest source addresses:

```bash
python3 scripts/ops/host-isolation-protocol-fixture.py listen \
  --family FAMILY --bind-address HOST_VM_ADDRESS --port UNUSED_PORT \
  --control-nonce "$control_nonce" --probe-nonce "$probe_nonce" \
  --control-source-address HOST_VM_ADDRESS \
  --probe-source-address GUEST_ADDRESS --timeout 20
```

Send the control from another host terminal:

```bash
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family FAMILY --source-address HOST_VM_ADDRESS \
  --destination-address HOST_VM_ADDRESS --port UNUSED_PORT \
  --nonce "$control_nonce"
```

Then send the guest attempt from its checked-out copy:

```bash
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family FAMILY --source-address GUEST_ADDRESS \
  --destination-address HOST_VM_ADDRESS --port UNUSED_PORT \
  --nonce "$probe_nonce"
```

For a disposable multicast port that has no owner, add the same reviewed
`--interface INTERFACE --multicast-group GROUP` pair to the listener and use
the group as each sender's destination, with its own selected interface. This
proves group/interface membership before evaluating receiver non-delivery.

Never bind the helper to occupied mDNS/SSDP ports, stop their owner or send a
valid discovery message. For those ports, use the helper's deliberately invalid
nonce payload only as the guest attempt, while a host operator runs an exact
bridge/tap/source/group/UDP-port capture and records the dedicated early-drop
counter before and after. The capture proves ingress; the terminal early-drop
counter proves disposition. A broad host-wide multicast counter is inadequate.
Do not retain unrelated packet payloads.

The scoped capture shape is:

```bash
sudo tcpdump -ni "$vm_bridge" -c 1 \
  "ether src $vm_mac and src host GUEST_ADDRESS and dst host GROUP_ADDRESS and udp dst port PORT"
sudo nft -a list table inet budget_agent_host_input
```

Fill one exact group/port/family per capture and start it before the guest send.
Do not use an unfiltered interface capture or `-A` payload dump.

Any local send reporting `NOT_TESTED`, missing listener control, missing group
membership, absent expected ingress/counter attribution, wrong source address,
or `Network is unreachable` is **NOT TESTED**, never a denial. Stop only the
named listener/capture, preserve its output privately and do not alter routing,
firewall or services to make a test pass.

### Required Post-Repair Matrix

Record each attempt's family, exact aliased source/destination/interface/port,
fixture positive, sender result, before/after early-rule counter or scoped
capture, receiver result and applicability. Run every applicable row before and
again after the final host reboot:

| Path | Required result and attribution |
| --- | --- |
| Guest to host unicast TCP, IPv4 and IPv6 | Selected-address empty HTTP listener has a host positive; guest is denied; early catch-all counter or exact scoped ingress attributes the attempt. |
| Guest to host unicast UDP, IPv4 and IPv6 | Bounded helper receives the host control, does not receive the guest nonce, and the early catch-all counter/capture attributes it. |
| Guest to host disposable multicast UDP, IPv4 and IPv6 | Applicable selected group/interface has a positive control; guest nonce is not delivered; early explicit multicast/catch-all counter and scoped ingress identify it. |
| mDNS and SSDP, IPv4 and IPv6 | No listener replacement or discovery message; exact guest source/group/port capture plus the dedicated early mDNS/SSDP drop counter proves the harmless nonce attempt was dropped before service delivery. |
| Gateway DNS | Guest TCP and UDP queries target only the discovered gateway, return expected answers and increment only the narrow DNS allow counters. Queries to every other host address are denied and attributed. |
| DHCP/DHCPv6 | Normal post-reboot guest lease acquisition succeeds with the expected address/router/DNS; only the narrow client/server-port and destination counters increment. Do not force a lease reset merely for evidence. |
| Required IPv6 control | Each allowlisted numeric type has a named purpose and positive working-flow/counter result; an unapproved guest-to-host IPv6 attempt reaches the final drop. Link-local-only applicability is recorded. |

After each matrix run, also require guest DNS plus verified Internet HTTPS,
host-initiated SSH and reviewed Git transfer, and host loopback-only verified app
HTTPS. From the guest run read-only native prerequisite, Docker target, exact
Kind target and Tilt health checks. Do not run setup, recreate Kind or mutate the
cluster merely for this proof. Host Docker-path checks are replaced by the
retirement absence evidence above.

The final report must pair the pre-reboot and post-reboot rows. Changed domain,
network, interfaces, addresses, policy bytes, backend or listener ownership
invalidates affected rows and requires review before retesting.

## Audit Result

Record collection time, reviewed source revisions, rule-order conclusions,
protocol/family coverage, confinement, persistence, positives/denials and any
limitations in the follow-up section of the
[acceptance record](../plans/agent-host-isolation-acceptance.md#post-migration-security-review).
Keep operator-reported results distinct from independently reviewed artifacts.
The native migration remains completed even while this additional review is
open; the additional review becomes complete only when its own evidence passes.
