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
UFW persistence and evidence of Docker retirement. Reads use `sudo -n`; failure
or a 30-second command timeout is recorded. Required failures make the exit
nonzero. Optional missing retired Docker files/packages or UFW hook files are
recorded for review; absence is never a filtering pass.

## Review And Return Evidence

The output directory and raw captures are private. Keep raw captures and
`index.json` on the personal host, outside Git and guest-accessible storage.
The index contains capture hashes for host-side comparison, not proof of a
trusted collector or unchanged future policy.

Privately inspect `candidate-report.md` before sharing it. Redaction removes
MACs, UUIDs, public IP literals, common personal path prefixes and rule comments;
VM XML is reduced to relevant structure. It intentionally retains private,
loopback, link-local and multicast addresses, interfaces, rule order, protocol,
ports, counters, chain/set names and process names. **This is best-effort
redaction, not a secret scanner**: custom identifiers, hostnames, unusual paths
and string-match rules may still identify private information. Manually redact
those while preserving consistent labels and rule relationships. Full XML,
systemd unit text and UFW hooks remain private-only; provide a
manually redacted excerpt if the reviewer needs them.

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

## Prove Protocol Behavior After Rule Review

Use the original manual plan's
[paired native listener tests](../plans/agent-vm-native-manual-plan.md#a3-revalidate-host-isolation)
as the TCP baseline.
Do not recreate retired host Docker. Extend proof with selected UDP unicast and
multicast cases based on the actual rule review. The review must specify exact
interfaces, family, destinations, port and expected counter change before the
human starts a fixture; do not send arbitrary LAN/VPN traffic.

For UDP, a timeout or `nc -u` exit is insufficient. A human-operated empty
receiver must first receive a nonce-bearing positive control; the guest sends
a different nonce while packet/rule counters establish the packet reached the
intended host ingress and was denied. The receiver must observe no guest nonce.
For multicast, join the selected group on the VM-facing host interface and
prove that group/interface's positive control. Use harmless payloads and scoped
disposable listeners; do not weaken policy, expose personal files or send
discovery commands to real host services. Missing route, group membership or
positive control means **NOT TESTED**, not PASS. Record narrowly selected packet
metadata/counter deltas rather than capturing unrelated payloads.

Repeat applicable TCP/UDP/family tests after the final host reboot, together
with successful guest DNS/verified Internet HTTPS and host-initiated SSH/Git
and loopback app HTTPS. Stop only the named fixtures. The follow-up plan owns
adding a focused protocol helper if the selected policy requires it; generic
automated probes cannot choose the correct host topology in advance.

## Audit Result

Record collection time, reviewed source revisions, rule-order conclusions,
protocol/family coverage, confinement, persistence, positives/denials and any
limitations in the follow-up section of the
[acceptance record](../plans/agent-host-isolation-acceptance.md#post-migration-security-review).
Keep operator-reported results distinct from independently reviewed artifacts.
The native migration remains completed even while this additional review is
open; the additional review becomes complete only when its own evidence passes.
