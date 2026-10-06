# Native VM Security Review: Human Phase 7 Completion

**Status:** Ready for human execution. Repository remediation Phases 1–6 are
complete; Phase 7 remains blocked on the live guest and personal-host work in
this checklist.
**Repository plan:**
[Native VM Security Review Remediation](agent-vm-security-review-remediation-plan.md).
**Canonical host contract:**
[Personal-Host Isolation Audit](../runbooks/host-isolation-audit.md).
**Evidence record:**
[Host-Isolation Acceptance](agent-host-isolation-acceptance.md#post-migration-security-review).

This is the literal human checklist for satisfying the external prerequisites
that stopped remediation Phase 7. It is a one-time execution aid, not a second
source of truth for firewall design. If this checklist and the host audit
runbook differ, stop and resolve the difference in the runbook before touching
the personal host.

The current `candidate-report.md`, collected on 2026-10-06, is a pre-repair
baseline. It still contains early UFW mDNS/SSDP accepts, no
`budget_agent_host_input` table, installed Mint Docker packages and the retired
Docker helper/drop-in. Running the collector again without completing the
repair and proof steps below will leave Phase 7 blocked.

## Authority And Terminal Labels

- **Guest terminal** means a normal-user shell in the Ubuntu development VM.
- **Personal-host terminal** means a normal-user shell on the Mint workstation.
- **Personal-host root operation** means an explicitly shown `sudo` command
  typed by the human on Mint after reviewing its resolved targets.
- **Host terminal A/B** and **guest terminal A/B** mean separate terminals used
  for paired listeners, senders, captures and counters.
- An agent may review explicitly supplied redacted evidence. An agent must not
  log into the personal host, apply host policy, write OS/NSS trust, reboot a
  machine, generate certificates or perform the Docker retirement.

Do not run any command containing an uppercase replacement token. Do not
replace a failed check with a broader rule, wildcard, insecure TLS option,
firewall flush or Docker restart. Stop at the first unexpected result.

## Completion Order

1. Preserve state and stop affected workers.
2. Prove committed workspace installation inputs.
3. Refresh the installed native user tools twice.
4. Converge guest trust and run the verified HTTPS matrix.
5. Reconcile the existing Kind ingress Secret through the exact local target.
6. Discover personal-host network and policy inputs.
7. Author, validate and apply the early nftables boundary with the VM stopped.
8. Prove UFW/libvirt lifecycle persistence before reboot.
9. Reconcile final Mint Docker retirement into quarantine.
10. Run the complete pre-reboot protocol and positive-flow matrix.
11. Reboot the personal host and repeat the complete matrix.
12. Collect and transfer only reviewed post-repair evidence.
13. Resume the existing Phase 7 runner state.
14. Delete the Docker quarantine only after Phase 7 accepts the evidence.

## Step 1: Preserve State And Stop Affected Workers

From the **guest orchestration checkout**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
git status --short
sha256sum candidate-report.md
git status --short -- .ai-session-handler docs/plans candidate-report.md
```

The expected current report SHA-256 is
`6ad0b74beccc5e3249d8c5e50d789928dd103f1a6f709a20e894fe97d0a664df`.
If it differs, review the new report privately before continuing. Do not reset
or overwrite source to make the status clean.

Stop AI Session Handler and every affected Codex, Claude or Gemini worker.
From a new **guest terminal**, inspect remaining processes:

```bash
pgrep -af 'ai-session-handler|codex|claude|gemini' || true
```

Proceed only after every process that could use the old workspace helpers or
trust state has exited. Keep this manual plan open from a static copy or a
separate human terminal; do not leave an agent worker running during Steps 3–5.

## Step 2: Prove Committed Workspace Inputs

From a **guest terminal**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
worktree_parent=$(dirname "$orchestration_root")
workspace_root="$worktree_parent/workspace"
test -e "$workspace_root/.git"
git -C "$workspace_root" rev-parse --is-inside-work-tree
cd "$workspace_root"
git status --short
git rev-parse --short HEAD
git ls-tree -r --name-only HEAD -- \
  native/npm/package.json native/npm/package-lock.json
sha256sum native/npm/package-lock.json
PYTHONPYCACHEPREFIX=tmp/pycache \
  python3 tests/native/check_install_inputs.py --publication committed
```

Require all of the following before continuing:

- `native/npm/package-lock.json` appears in `git ls-tree`.
- Its SHA-256 is
  `f42dff943f668e927407f16ef214f43ea2e88f319c9d0deae13e5b27f6df8b91`.
- The committed checker reports a `git archive HEAD` source-only proof.
- No unexpected workspace change appears in `git status --short`.

## Step 3: Refresh Installed Native User Tools Twice

Remain in the **guest workspace checkout**. Resolve the existing worktree and
bare-repository parents, then run the installer exactly twice:

```bash
workspace_root=$(git rev-parse --show-toplevel)
native_worktree_parent=$(dirname "$workspace_root")
read -r -p 'Existing guest bare-repository parent: ' native_bare_parent
test -d "$native_bare_parent"
./scripts/install-agent-vm-user-tools.sh \
  --worktree-parent "$native_worktree_parent" \
  --bare-parent "$native_bare_parent"
. "$HOME/.config/budget-analyzer-native/env.sh"
./scripts/install-agent-vm-user-tools.sh \
  --worktree-parent "$native_worktree_parent" \
  --bare-parent "$native_bare_parent"
```

Both invocations must exit zero. Do not run the system provisioner, remove
provider state, delete caches or substitute a package update.

## Step 4: Converge Guest Trust And Prove Verified HTTPS

Still in the **guest workspace checkout**, validate the transferred public TLS
inputs without changing Kubernetes:

```bash
"$native_worktree_parent/orchestration/scripts/bootstrap/install-imported-ingress-tls.sh" \
  --validate-only
openssl x509 \
  -in "$native_worktree_parent/orchestration/nginx/certs/k8s/_mkcert-rootCA.pem" \
  -noout -sha256 -fingerprint
```

Privately compare the fingerprint with the approved host transfer. If the
files are missing, stale or for another hostname, stop and use the documented
host-only renewal and three-file transfer. Do not run `mkcert`, generate a CA
in the guest or bypass verification.

Run the human trust installer and read-only verifiers:

```bash
cd "$workspace_root"
./scripts/install-agent-vm-local-ca-trust.sh \
  --worktree-parent "$native_worktree_parent" \
  --bare-parent "$native_bare_parent"
ensure-budget-analyzer-local-ca-trust
check-budget-analyzer-local-ca-trust
./scripts/check-agent-vm-tools.sh \
  --worktree-parent "$native_worktree_parent" \
  --bare-parent "$native_bare_parent"
```

Inspect the sole managed CA state:

```bash
canonical_ca=/usr/local/share/ca-certificates/budget-analyzer-local-mkcert.crt
legacy_ca=/usr/local/share/ca-certificates/budget-analyzer-local-ingress-ca.crt
test -f "$canonical_ca"
test ! -L "$canonical_ca"
test ! -e "$legacy_ca"
test ! -L "$legacy_ca"
stat -c '%U:%G %a %F' "$canonical_ca"
check-budget-analyzer-local-ca-trust
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt \
  "$native_worktree_parent/orchestration/nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem"
certutil -L -d "sql:$HOME/.pki/nssdb" \
  -n 'Budget Analyzer local mkcert CA' -a \
  | openssl x509 -noout -sha256 -fingerprint
```

Require `root:root 644 regular file` for the canonical CA, no legacy CA path,
and the approved fingerprint in the NSS output.

Open a fresh **guest terminal**, load the installed environment, and run every
verified client:

```bash
. "$HOME/.config/budget-analyzer-native/env.sh"
curl --fail --show-error \
  https://app.budgetanalyzer.localhost/ >/dev/null
python3 - <<'PY'
import urllib.request
with urllib.request.urlopen(
        'https://app.budgetanalyzer.localhost/', timeout=20) as response:
    print('Python verified HTTPS:', response.status)
PY
node - <<'JS'
fetch('https://app.budgetanalyzer.localhost/', {redirect: 'manual'})
  .then(r => {
    if (r.status >= 500) throw Error('ingress unavailable');
    console.log('Node verified HTTPS:', r.status);
  })
  .catch(e => {console.error(e.message); process.exitCode = 1});
JS
node - <<'JS'
const {chromium} = require('playwright');
(async () => {
  const browser = await chromium.launch({headless: true});
  try {
    const page = await browser.newPage();
    let ingressResponse;
    page.on('response', r => {
      if (r.url() === 'https://app.budgetanalyzer.localhost/') {
        ingressResponse = r;
      }
    });
    await page.route('**/*', route => {
      const url = new URL(route.request().url());
      return url.origin === 'https://app.budgetanalyzer.localhost'
        ? route.continue() : route.abort();
    });
    try {
      await page.goto('https://app.budgetanalyzer.localhost/', {
        waitUntil: 'domcontentloaded', timeout: 20000
      });
    } catch (error) {
      if (!ingressResponse) throw error;
    }
    if (!ingressResponse || ingressResponse.status() >= 500) {
      throw Error('ingress response missing/unavailable');
    }
    console.log('Chromium verified HTTPS:', ingressResponse.status());
  } finally {
    await browser.close();
  }
})().catch(e => {console.error(e.message); process.exitCode = 1});
JS
```

Record all four exits and statuses. An authentication redirect is acceptable;
a certificate bypass, cached browser screenshot or HTTP request is not.

## Step 5: Reconcile The Existing Kind Ingress Secret

From the **guest orchestration checkout**:

```bash
cd "$native_worktree_parent/orchestration"
./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime
./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local
kubectl config current-context
kubectl config view --minify \
  -o jsonpath='{.clusters[0].name}{"\n"}{.clusters[0].cluster.server}{"\n"}'
kubectl get node kind-control-plane
./scripts/bootstrap/install-imported-ingress-tls.sh
```

Require context and cluster `kind-kind`, an exact loopback HTTPS API authority,
no kubeconfig proxy override and a Ready `kind-control-plane` before the final
command. The command reconciles the existing Secret; it does not authorize
cluster recreation or certificate generation.

## Step 6: Discover Personal-Host Inputs

Continue only after Steps 1–5 pass. Use a **personal-host terminal** in its
reviewed orchestration checkout:

```bash
host_orchestration_root=$(git rev-parse --show-toplevel)
cd "$host_orchestration_root"
git status --short
sudo -v
vm_domain=budget-analyzer-agent
vm_network=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" \
  | awk '$2 == "network" {print $3}')
vm_tap=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" \
  | awk '$2 == "network" {print $1}')
vm_mac=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" \
  | awk '$2 == "network" {print $5}')
test "$(printf '%s\n' "$vm_network" | sed '/^$/d' | wc -l)" -eq 1
test "$(printf '%s\n' "$vm_tap" | sed '/^$/d' | wc -l)" -eq 1
test "$(printf '%s\n' "$vm_mac" | sed '/^$/d' | wc -l)" -eq 1
test "$vm_network" = agent-nat
test "$vm_mac" = 52:54:00:d9:c2:70
vm_bridge=$(sudo virsh --connect qemu:///system net-info "$vm_network" \
  | awk '$1 == "Bridge:" {print $2}')
test "$vm_bridge" = virbr1
printf 'domain=%s\nnetwork=%s\nbridge=%s\ntap=%s\nmac=%s\n' \
  "$vm_domain" "$vm_network" "$vm_bridge" "$vm_tap" "$vm_mac"
ip -details link show dev "$vm_bridge"
ip -details link show dev "$vm_tap"
ip -4 -o address show dev "$vm_bridge"
ip -6 -o address show dev "$vm_bridge"
sudo virsh --connect qemu:///system net-dhcp-leases "$vm_network" \
  --mac "$vm_mac"
sudo virsh --connect qemu:///system dumpxml "$vm_domain"
sudo virsh --connect qemu:///system net-dumpxml "$vm_network"
```

From a **guest terminal**, record the guest side without changing networking:

```bash
ip -4 -o address show
ip -6 -o address show
ip -4 route show
ip -6 route show
ip link show
resolvectl status
```

Privately map one selected guest IPv4 address, any applicable guest IPv6
address and scope, the IPv4 gateway, any IPv6 gateway/control destinations,
DHCP destinations and required ICMPv6 types. Reconcile these values with the
host lease and network XML. Stop if the domain has zero or multiple network
interfaces, another domain shares the network, live and persistent attachments
differ, or any needed family/protocol remains unexplained.

Inspect every firewall path and persistence input on the **personal host**:

```bash
sudo nft -a list ruleset
sudo iptables-save -c
sudo ip6tables-save -c
command -v iptables-legacy-save >/dev/null && \
  sudo iptables-legacy-save -c
command -v ip6tables-legacy-save >/dev/null && \
  sudo ip6tables-legacy-save -c
sudo ufw show raw
sudo sed -n '1,240p' /etc/ufw/before.rules
sudo sed -n '1,260p' /etc/ufw/before6.rules
systemctl list-unit-files 'libvirt*' 'virtqemu*' 'virtnetwork*'
systemctl list-dependencies --reverse --all libvirtd.service 2>/dev/null || true
systemctl list-dependencies --reverse --all virtqemud.service 2>/dev/null || true
systemctl list-dependencies --reverse --all virtnetworkd.service 2>/dev/null || true
```

The reviewed monolithic libvirt unit set is:

```text
libvirt-guests.service
libvirtd.service
libvirtd-admin.socket
libvirtd-ro.socket
libvirtd-tcp.socket
libvirtd-tls.socket
libvirtd.socket
```

The TCP/TLS sockets are disabled but remain in the dependency set so that a
later enable cannot bypass the host-input service. Stop and revise the plan if
the discovered unit files differ from this list.

## Step 7: Author And Validate The Early Host Boundary

First require that no prior partial installation occupies the managed paths.
From the **personal host**:

```bash
for managed_path in \
  /etc/nftables.d/budget-agent-host-input.nft \
  /usr/local/sbin/load-budget-agent-host-input \
  /etc/systemd/system/budget-agent-host-input.service; do
  if sudo test -e "$managed_path" || sudo test -L "$managed_path"; then
    printf 'ERROR: existing managed path requires private review: %s\n' \
      "$managed_path" >&2
    exit 1
  fi
done
```

An existing path means a prior application was attempted. Stop and reconcile
it against the runbook and private backups; do not overwrite it with this
first-install sequence.

Create the root-owned policy directory:

```bash
sudo install -d -o root -g root -m 0755 /etc/nftables.d
sudoedit /etc/nftables.d/budget-agent-host-input.nft
```

Enter the following policy exactly. It contains the reviewed domain network
values: bridge `virbr1`, VM MAC `52:54:00:d9:c2:70`, guest
`192.168.231.10`, gateway `192.168.231.1` and limited DHCP broadcast
`255.255.255.255`. The selected guest has only link-local IPv6 on `enp1s0`,
the libvirt network has no IPv6 gateway, and the guest has no IPv6 default
route, so this policy intentionally adds no IPv6 allow rule.

```nft
table inet budget_agent_host_input {
  chain early_vm_host_input {
    type filter hook input priority -190; policy accept;

    iifname "virbr1" ether saddr != 52:54:00:d9:c2:70 counter drop
    iifname "virbr1" ct state established,related counter accept

    iifname "virbr1" ether saddr 52:54:00:d9:c2:70 \
      ip saddr 192.168.231.10 ip daddr 192.168.231.1 \
      meta l4proto { tcp, udp } th dport 53 counter accept
    iifname "virbr1" ether saddr 52:54:00:d9:c2:70 \
      ip saddr { 0.0.0.0, 192.168.231.10 } \
      ip daddr { 192.168.231.1, 255.255.255.255 } \
      udp sport 68 udp dport 67 counter accept

    iifname "virbr1" udp dport { 1900, 5353 } counter drop
    iifname "virbr1" counter drop
  }
}
```

Set ownership and mode:

```bash
sudo chown root:root /etc/nftables.d/budget-agent-host-input.nft
sudo chmod 0600 /etc/nftables.d/budget-agent-host-input.nft
```

Create the loader:

```bash
sudoedit /usr/local/sbin/load-budget-agent-host-input
```

Enter exactly:

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

Set its ownership and executable mode:

```bash
sudo chown root:root /usr/local/sbin/load-budget-agent-host-input
sudo chmod 0750 /usr/local/sbin/load-budget-agent-host-input
```

Create the systemd service:

```bash
sudoedit /etc/systemd/system/budget-agent-host-input.service
```

Enter exactly:

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

Set its ownership and mode:

```bash
sudo chown root:root /etc/systemd/system/budget-agent-host-input.service
sudo chmod 0644 /etc/systemd/system/budget-agent-host-input.service
```

For each concrete libvirt service and socket, open its drop-in editor:

```bash
reviewed_libvirt_units=(
  libvirt-guests.service
  libvirtd.service
  libvirtd-admin.socket
  libvirtd-ro.socket
  libvirtd-tcp.socket
  libvirtd-tls.socket
  libvirtd.socket
)
for reviewed_libvirt_unit in "${reviewed_libvirt_units[@]}"; do
  systemctl list-unit-files "$reviewed_libvirt_unit" --no-legend \
    | rg -F "$reviewed_libvirt_unit" || exit 1
  sudo systemctl edit "$reviewed_libvirt_unit"
done
```

Enter exactly this drop-in body and save it in each editor:

```systemd
[Unit]
Requires=budget-agent-host-input.service
After=budget-agent-host-input.service
```

Do not add a guessed unit and do not omit an activation socket. Validate all
three primary files before applying anything:

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
sudo systemd-analyze verify \
  /etc/systemd/system/budget-agent-host-input.service
sudo /usr/local/sbin/load-budget-agent-host-input --check-only
```

Any warning, unresolved family, unsafe mode, symlink, syntax error or nftables
check failure is a stop condition.

## Step 8: Apply With The VM Stopped And Prove Lifecycle Persistence

From the **personal host**, request a clean VM shutdown:

```bash
sudo virsh --connect qemu:///system shutdown "$vm_domain"
sudo virsh --connect qemu:///system domstate "$vm_domain"
```

Repeat only the `domstate` command until it reports `shut off`. Do not destroy
the domain to shorten the wait. With the VM shut off, back up the new and any
replaced host files into a fixed root-only review directory:

```bash
sudo install -d -o root -g root -m 0700 \
  /root/budget-agent-host-input-review
sudo cp --archive \
  /etc/nftables.d/budget-agent-host-input.nft \
  /usr/local/sbin/load-budget-agent-host-input \
  /etc/systemd/system/budget-agent-host-input.service \
  /root/budget-agent-host-input-review/
sudo sha256sum \
  /root/budget-agent-host-input-review/budget-agent-host-input.nft \
  /root/budget-agent-host-input-review/load-budget-agent-host-input \
  /root/budget-agent-host-input-review/budget-agent-host-input.service
```

Load and inspect the policy:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now budget-agent-host-input.service
sudo systemctl is-enabled budget-agent-host-input.service
sudo systemctl is-active budget-agent-host-input.service
sudo nft -a list table inet budget_agent_host_input
systemctl show budget-agent-host-input.service \
  -p Before -p ActiveState -p UnitFileState
```

Verify every concrete libvirt service and socket:

```bash
reviewed_libvirt_units=(
  libvirt-guests.service
  libvirtd.service
  libvirtd-admin.socket
  libvirtd-ro.socket
  libvirtd-tcp.socket
  libvirtd-tls.socket
  libvirtd.socket
)
for reviewed_libvirt_unit in "${reviewed_libvirt_units[@]}"; do
  systemctl show "$reviewed_libvirt_unit" -p Requires -p After
done
```

Require the custom service in both `Requires` and `After`. Require exactly one
input hook at priority `-190`, only the reviewed allows, explicit mDNS/SSDP
drops and the final bridge drop.

Prove a UFW reload does not remove the custom table:

```bash
sudo ufw reload
sudo systemctl is-active budget-agent-host-input.service
sudo nft -a list table inet budget_agent_host_input
sudo nft -a list ruleset
sudo iptables-save -c
sudo ip6tables-save -c
command -v iptables-legacy-save >/dev/null && \
  sudo iptables-legacy-save -c
command -v ip6tables-legacy-save >/dev/null && \
  sudo ip6tables-legacy-save -c
```

With the domain still shut off, prove the selected network lifecycle:

```bash
sudo virsh --connect qemu:///system net-destroy "$vm_network"
sudo virsh --connect qemu:///system net-start "$vm_network"
sudo systemctl is-active budget-agent-host-input.service
sudo nft -a list table inet budget_agent_host_input
sudo virsh --connect qemu:///system start "$vm_domain"
sudo virsh --connect qemu:///system domstate "$vm_domain"
```

If the policy service, dependency or table disappears, keep the VM stopped and
follow the runbook rollback boundary. Do not delete the table while the VM is
running.

## Step 9: Reconcile Mint Docker Retirement Into Quarantine

Do not invoke `docker`. From the **personal host**, inspect activation paths,
packages, consumers and canonical data roots:

```bash
systemctl is-active docker.service docker.socket containerd.service || true
systemctl is-enabled docker.service docker.socket containerd.service || true
test ! -S /var/run/docker.sock
dpkg-query -W \
  -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' 2>/dev/null \
  | awk -F '\t' \
      'substr($2, 2, 1) == "i" && $1 ~ /^(docker|containerd|runc|moby)/'
apt-cache rdepends --installed containerd containerd.io runc 2>/dev/null
systemctl list-dependencies --reverse --all \
  containerd.service 2>/dev/null || true
sudo readlink -f /var/lib/docker /var/lib/containerd
sudo findmnt --target /var/lib/docker || true
sudo findmnt --target /var/lib/containerd || true
sudo du -shx /var/lib/docker /var/lib/containerd 2>/dev/null || true
```

The baseline report identifies these Docker-owned packages:

```bash
retired_docker_packages=(
  docker-buildx-plugin
  docker-ce
  docker-ce-cli
  docker-ce-rootless-extras
  docker-compose-plugin
)
printf 'retire package: %s\n' "${retired_docker_packages[@]}"
sudo apt-get --simulate purge -- "${retired_docker_packages[@]}"
```

The report also lists `containerd.io`. If and only if the preceding consumer
commands prove that no non-Docker package/service uses it, append it and rerun
the simulation:

```bash
retired_docker_packages+=(containerd.io)
printf 'retire package: %s\n' "${retired_docker_packages[@]}"
sudo apt-get --simulate purge -- "${retired_docker_packages[@]}"
```

If another Docker/Moby engine or CLI package appears, stop and add its exact
name only after classifying it. If the simulation proposes an unrelated
removal, stop. After reviewing the exact simulation, run:

```bash
sudo apt-get purge -- "${retired_docker_packages[@]}"
```

Do not accept an autoremove proposal until every proposed package is
classified.

Create the root-only quarantine and preserve the UFW hook before editing it:

```bash
sudo install -d -o root -g root -m 0700 \
  /root/budget-agent-retirement-review
sudo cp --archive /etc/ufw/after.init \
  /root/budget-agent-retirement-review/ufw-after.init.before
sudoedit /etc/ufw/after.init
```

Remove only the invocation of `/usr/local/sbin/agent-vm-docker-isolation` from
the editor; preserve every unrelated line. Then validate:

```bash
sudo sh -n /etc/ufw/after.init
sudo shellcheck /etc/ufw/after.init
sudo rg -n 'agent-vm-docker-isolation' /etc/ufw/after.init && exit 1 || true
```

Quarantine the retired helper and drop-in only after the early nftables policy
has passed Step 8:

```bash
sudo mv -- /etc/systemd/system/docker.service.d/agent-vm-isolation.conf \
  /root/budget-agent-retirement-review/
sudo mv -- /usr/local/sbin/agent-vm-docker-isolation \
  /root/budget-agent-retirement-review/
```

Resolve and validate the Docker data root before moving it:

```bash
docker_data_root=$(sudo readlink -f /var/lib/docker)
printf 'Docker data root selected for quarantine: %s\n' "$docker_data_root"
test "$docker_data_root" = /var/lib/docker
sudo test -d "$docker_data_root"
sudo test ! -L /var/lib/docker
sudo mv -- "$docker_data_root" \
  /root/budget-agent-retirement-review/docker-data
```

Do not move `/var/lib/containerd` unless Step 9 proved it is exclusively
Docker-owned. If that proof exists, run exactly:

```bash
containerd_data_root=$(sudo readlink -f /var/lib/containerd)
printf 'containerd data root selected for quarantine: %s\n' \
  "$containerd_data_root"
test "$containerd_data_root" = /var/lib/containerd
sudo test -d "$containerd_data_root"
sudo test ! -L /var/lib/containerd
sudo mv -- "$containerd_data_root" \
  /root/budget-agent-retirement-review/containerd-data
```

Inspect Docker-owned apt/config paths and quarantine only individually reviewed
files:

```bash
sudo find /etc/apt/sources.list.d /etc/apt/keyrings /usr/share/keyrings \
  -maxdepth 1 -type f -iname '*docker*' -print
sudo find /etc/docker -xdev -print 2>/dev/null || true
```

For each printed path, privately verify ownership and contents, then enter its
exact absolute path at the prompt:

```bash
read -r -p 'Exact reviewed Docker-owned file or directory to quarantine: ' \
  retired_docker_path
test -n "$retired_docker_path"
sudo test -e "$retired_docker_path"
sudo stat -c '%U:%G %a %F %N' "$retired_docker_path"
sudo mv -- "$retired_docker_path" \
  /root/budget-agent-retirement-review/
```

Repeat only for reviewed Docker-owned paths. Stop on a destination-name
collision, symlink, unexpected canonical path or unrelated content. Finish the
pre-reboot reconciliation:

```bash
sudo systemctl daemon-reload
sudo systemctl is-active docker.service docker.socket || true
sudo systemctl is-enabled docker.service docker.socket || true
test ! -S /var/run/docker.sock
sudo nft -a list table inet budget_agent_host_input
```

Keep `/root/budget-agent-retirement-review` intact through Phase 7 acceptance.

## Step 10: Run The Pre-Reboot Protocol Matrix

Create a private label for this run on the **personal host**:

```bash
matrix_stage=pre-reboot
matrix_time=$(date -u +%Y%m%dT%H%M%SZ)
matrix_dir="$HOME/budget-host-phase7-$matrix_stage-$matrix_time"
install -d -m 0700 "$matrix_dir"
printf 'matrix evidence directory: %s\n' "$matrix_dir"
```

Resolve the repository, domain, network and selected addresses again so this
matrix does not depend on shell state left by Step 6. Type address literals
without CIDR suffixes:

```bash
host_orchestration_root=$(git rev-parse --show-toplevel)
cd "$host_orchestration_root"
read -r -p 'Reviewed development VM domain: ' vm_domain
vm_network=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" \
  | awk '$2 == "network" {print $3}')
vm_tap=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" \
  | awk '$2 == "network" {print $1}')
vm_mac=$(sudo virsh --connect qemu:///system domiflist "$vm_domain" \
  | awk '$2 == "network" {print $5}')
vm_bridge=$(sudo virsh --connect qemu:///system net-info "$vm_network" \
  | awk '$1 == "Bridge:" {print $2}')
test "$(printf '%s\n' "$vm_network" | sed '/^$/d' | wc -l)" -eq 1
test "$(printf '%s\n' "$vm_tap" | sed '/^$/d' | wc -l)" -eq 1
test "$(printf '%s\n' "$vm_mac" | sed '/^$/d' | wc -l)" -eq 1
test -n "$vm_bridge"
read -r -p 'Selected host VM-facing IPv4 address: ' host_v4
read -r -p 'Selected guest IPv4 address: ' guest_v4
read -r -p 'Selected guest interface: ' guest_interface
read -r -p 'Selected host non-VM IPv4 address for denied DNS proof: ' host_other_v4
printf 'host_v4=%s guest_v4=%s guest_interface=%s host_other_v4=%s\n' \
  "$host_v4" "$guest_v4" "$guest_interface" "$host_other_v4"
matrix_inputs="$matrix_dir/host-inputs.sh"
umask 077
{
  printf 'host_orchestration_root=%q\n' "$host_orchestration_root"
  printf 'vm_domain=%q\n' "$vm_domain"
  printf 'vm_network=%q\n' "$vm_network"
  printf 'vm_tap=%q\n' "$vm_tap"
  printf 'vm_mac=%q\n' "$vm_mac"
  printf 'vm_bridge=%q\n' "$vm_bridge"
  printf 'host_v4=%q\n' "$host_v4"
  printf 'guest_v4=%q\n' "$guest_v4"
  printf 'guest_interface=%q\n' "$guest_interface"
  printf 'host_other_v4=%q\n' "$host_other_v4"
} >"$matrix_inputs"
chmod 0600 "$matrix_inputs"
```

At the start of every new **host terminal A/B** used in Steps 10.1–10.7, run:

```bash
read -r -p 'Exact matrix evidence directory: ' matrix_dir
test -f "$matrix_dir/host-inputs.sh"
. "$matrix_dir/host-inputs.sh"
cd "$host_orchestration_root"
```

Do not copy this file into the guest or repository. It remains private on the
personal host and contains the unredacted topology values.

### Step 10.1: IPv4 Unicast TCP

In **host terminal A**:

```bash
tcp_port=48180
if sudo ss -H -ltn "sport = :$tcp_port" | rg -q .; then
  printf 'ERROR: selected TCP port is occupied\n' >&2
  exit 1
fi
tcp_fixture_dir=$(mktemp -d)
python3 -m http.server "$tcp_port" --bind "$host_v4" \
  --directory "$tcp_fixture_dir"
```

In **host terminal B**:

```bash
tcp_port=48180
curl --noproxy '*' --fail --max-time 3 \
  "http://$host_v4:$tcp_port/"
sudo nft -a list table inet budget_agent_host_input
```

In a **guest terminal**:

```bash
read -r -p 'Selected host VM-facing IPv4 address: ' host_v4
tcp_port=48180
nc -4 -vz -w 3 "$host_v4" "$tcp_port"
```

Immediately after that attempt, in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

The guest attempt must fail and increment the attributable early final-drop
counter or appear in an exact scoped capture. Stop host terminal A with
`Ctrl-C`, then run in that terminal:

```bash
rmdir -- "$tcp_fixture_dir"
```

### Step 10.2: IPv4 Unicast UDP

In **host terminal A**:

```bash
cd "$host_orchestration_root"
udp_port=48181
control_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
probe_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
test "$control_nonce" != "$probe_nonce"
printf 'control_nonce=%s\nprobe_nonce=%s\n' \
  "$control_nonce" "$probe_nonce"
python3 scripts/ops/host-isolation-protocol-fixture.py listen \
  --family ipv4 --bind-address "$host_v4" --port "$udp_port" \
  --control-nonce "$control_nonce" --probe-nonce "$probe_nonce" \
  --control-source-address "$host_v4" \
  --probe-source-address "$guest_v4" --timeout 30
```

After `LISTENER_READY`, in **host terminal B**:

```bash
cd "$host_orchestration_root"
udp_port=48181
read -r -p 'Control nonce from host terminal A: ' control_nonce
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv4 --source-address "$host_v4" \
  --destination-address "$host_v4" --port "$udp_port" \
  --nonce "$control_nonce"
sudo nft -a list table inet budget_agent_host_input
```

In a **guest terminal**, use the printed `$probe_nonce` value from host
terminal A:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
read -r -p 'Selected guest IPv4 address: ' guest_v4
read -r -p 'Selected host VM-facing IPv4 address: ' host_v4
read -r -p 'Probe nonce from host terminal A: ' probe_nonce
udp_port=48181
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv4 --source-address "$guest_v4" \
  --destination-address "$host_v4" --port "$udp_port" \
  --nonce "$probe_nonce"
```

Immediately after that attempt, in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

Host terminal A must report `CONTROL_RECEIVED` and
`RECEIVER_NON_DELIVERY_WITH_CONTROL`, exit zero, and the dedicated early final
drop must increment for the guest attempt. Exit `3`, no counter attribution or
`NOT_TESTED` is not a pass.

### Step 10.3: IPv4 Disposable Multicast UDP

Use group `239.255.0.42` and port `48182`. In **host terminal A**:

```bash
cd "$host_orchestration_root"
multicast_group=239.255.0.42
multicast_port=48182
control_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
probe_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
test "$control_nonce" != "$probe_nonce"
printf 'control_nonce=%s\nprobe_nonce=%s\n' \
  "$control_nonce" "$probe_nonce"
python3 scripts/ops/host-isolation-protocol-fixture.py listen \
  --family ipv4 --bind-address "$host_v4" --port "$multicast_port" \
  --interface "$vm_bridge" --multicast-group "$multicast_group" \
  --control-nonce "$control_nonce" --probe-nonce "$probe_nonce" \
  --control-source-address "$host_v4" \
  --probe-source-address "$guest_v4" --timeout 30
```

After `LISTENER_READY`, in **host terminal B**:

```bash
cd "$host_orchestration_root"
multicast_group=239.255.0.42
multicast_port=48182
read -r -p 'Control nonce from host terminal A: ' control_nonce
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv4 --source-address "$host_v4" \
  --destination-address "$multicast_group" \
  --interface "$vm_bridge" --port "$multicast_port" \
  --nonce "$control_nonce"
sudo nft -a list table inet budget_agent_host_input
```

In a **guest terminal**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
read -r -p 'Selected guest IPv4 address: ' guest_v4
read -r -p 'Selected guest interface: ' guest_interface
read -r -p 'Probe nonce from host terminal A: ' probe_nonce
multicast_group=239.255.0.42
multicast_port=48182
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv4 --source-address "$guest_v4" \
  --destination-address "$multicast_group" \
  --interface "$guest_interface" --port "$multicast_port" \
  --nonce "$probe_nonce"
```

Immediately after that attempt, in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

Require the host positive control, guest receiver non-delivery and exact early
counter or scoped-ingress attribution.

### Step 10.4: IPv4 mDNS And SSDP

Do not bind to ports 5353 or 1900 and do not stop Avahi. For mDNS, start this
in **host terminal A**:

```bash
sudo tcpdump -ni "$vm_bridge" -c 1 \
  "ether src $vm_mac and src host $guest_v4 and dst host 224.0.0.251 and udp dst port 5353"
```

In **host terminal B**, record the custom table counters:

```bash
sudo nft -a list table inet budget_agent_host_input
```

In a **guest terminal**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
read -r -p 'Selected guest IPv4 address: ' guest_v4
read -r -p 'Selected guest interface: ' guest_interface
mdns_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv4 --source-address "$guest_v4" \
  --destination-address 224.0.0.251 --interface "$guest_interface" \
  --port 5353 --nonce "$mdns_nonce"
```

Immediately after that attempt, in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

Require one exact capture and an increment in the early mDNS/SSDP drop. Repeat
for SSDP. In **host terminal A**:

```bash
sudo tcpdump -ni "$vm_bridge" -c 1 \
  "ether src $vm_mac and src host $guest_v4 and dst host 239.255.255.250 and udp dst port 1900"
```

In the **guest terminal**:

```bash
ssdp_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv4 --source-address "$guest_v4" \
  --destination-address 239.255.255.250 --interface "$guest_interface" \
  --port 1900 --nonce "$ssdp_nonce"
```

Then in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

### Step 10.5: Gateway DNS And Other-Host DNS Denial

From the **guest**:

```bash
command -v dig
read -r -p 'Reviewed IPv4 gateway/DNS address: ' gateway_v4
read -r -p 'Reviewed other host IPv4 address: ' host_other_v4
dig +time=3 +tries=1 @"$gateway_v4" example.com A
dig +tcp +time=3 +tries=1 @"$gateway_v4" example.com A
dig +time=2 +tries=1 @"$host_other_v4" example.com A
dig +tcp +time=2 +tries=1 @"$host_other_v4" example.com A
```

The gateway UDP/TCP queries must succeed and increment only the narrow DNS
allow. The other-host queries must fail and increment the early final drop. A
timeout without the counter attribution is not a pass. On the **personal
host**, read the counters before and after each pair:

```bash
sudo nft -a list table inet budget_agent_host_input
```

### Step 10.6: DHCP And IPv6 Control Evidence

Do not force a lease renewal. From the **guest**, record the working lease and
resolver state:

```bash
read -r -p 'Selected guest interface: ' guest_interface
ip -4 -o address show dev "$guest_interface"
ip -4 route show default
resolvectl status "$guest_interface"
ip -6 -o address show dev "$guest_interface"
ip -6 route show
ip -6 neigh show dev "$guest_interface"
```

From the **personal host**, record the matching lease and policy counters:

```bash
sudo virsh --connect qemu:///system net-dhcp-leases "$vm_network" \
  --mac "$vm_mac"
sudo nft -a list table inet budget_agent_host_input
```

### Step 10.7: Exact IPv6 Rows

First determine IPv6 applicability from the actual host and guest state. In a
**host terminal** initialized with `host-inputs.sh`:

```bash
ip -6 -o address show dev "$vm_bridge"
ip -6 -o address show dev "$vm_tap"
ip -6 route show
sudo ss -H -lunp | rg ':(5353|1900)\b'
read -r -p 'Selected host VM-facing IPv6 address with scope when needed: ' \
  host_v6_scoped
read -r -p 'Host interface owning that IPv6 address: ' host_v6_interface
read -r -p 'Selected guest IPv6 address with scope when needed: ' \
  guest_v6_scoped
read -r -p 'Guest IPv6 interface: ' guest_v6_interface
host_v6_literal=${host_v6_scoped%%%*}
guest_v6_literal=${guest_v6_scoped%%%*}
test -n "$host_v6_literal"
test -n "$guest_v6_literal"
ip -6 address show dev "$host_v6_interface" | rg -F "$host_v6_literal"
ipv6_inputs="$matrix_dir/ipv6-inputs.sh"
{
  printf 'host_v6_scoped=%q\n' "$host_v6_scoped"
  printf 'host_v6_literal=%q\n' "$host_v6_literal"
  printf 'host_v6_interface=%q\n' "$host_v6_interface"
  printf 'guest_v6_scoped=%q\n' "$guest_v6_scoped"
  printf 'guest_v6_literal=%q\n' "$guest_v6_literal"
  printf 'guest_v6_interface=%q\n' "$guest_v6_interface"
} >"$ipv6_inputs"
chmod 0600 "$ipv6_inputs"
```

If no host/guest IPv6 pair exists, do not enter empty values. Record the exact
address, route and listener output above plus the guest commands below as the
applicability evidence:

```bash
ip -6 -o address show
ip -6 route show
ip -6 neigh show
```

An absent global route alone does not make link-local multicast inapplicable.
If a link-local pair exists, run every IPv6 row below.

At the start of each new **host terminal A/B** for the IPv6 rows, run:

```bash
read -r -p 'Exact matrix evidence directory: ' matrix_dir
test -f "$matrix_dir/host-inputs.sh"
test -f "$matrix_dir/ipv6-inputs.sh"
. "$matrix_dir/host-inputs.sh"
. "$matrix_dir/ipv6-inputs.sh"
cd "$host_orchestration_root"
```

For IPv6 unicast TCP, in **host terminal A**:

```bash
tcp6_port=48183
if sudo ss -H -ltn "sport = :$tcp6_port" | rg -q .; then
  printf 'ERROR: selected IPv6 TCP port is occupied\n' >&2
  exit 1
fi
tcp6_fixture_dir=$(mktemp -d)
python3 -m http.server "$tcp6_port" --bind "$host_v6_scoped" \
  --directory "$tcp6_fixture_dir"
```

In **host terminal B**:

```bash
tcp6_port=48183
host_v6_url=${host_v6_scoped/\%/%25}
curl --noproxy '*' --fail --max-time 3 \
  "http://[$host_v6_url]:$tcp6_port/"
sudo nft -a list table inet budget_agent_host_input
```

In a **guest terminal**:

```bash
read -r -p 'Selected host IPv6 literal without scope: ' host_v6_literal
read -r -p 'Guest IPv6 interface: ' guest_v6_interface
tcp6_port=48183
nc -6 -vz -w 3 \
  "${host_v6_literal}%${guest_v6_interface}" "$tcp6_port"
```

Immediately after that attempt, in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

The host request must pass. The guest attempt must fail with an attributable
early final-drop increment. If it reaches the listener, or if only the tap sees
it while the bridge rule does not, stop, shut down the VM and design the
runbook-required fail-closed dynamic tap binding before proceeding. Stop host
terminal A with `Ctrl-C`, then run:

```bash
rmdir -- "$tcp6_fixture_dir"
```

For IPv6 unicast UDP, in **host terminal A**:

```bash
udp6_port=48184
control_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
probe_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
test "$control_nonce" != "$probe_nonce"
printf 'control_nonce=%s\nprobe_nonce=%s\n' \
  "$control_nonce" "$probe_nonce"
python3 scripts/ops/host-isolation-protocol-fixture.py listen \
  --family ipv6 --bind-address "$host_v6_scoped" --port "$udp6_port" \
  --interface "$host_v6_interface" \
  --control-nonce "$control_nonce" --probe-nonce "$probe_nonce" \
  --control-source-address "$host_v6_scoped" \
  --probe-source-address "$guest_v6_scoped" --timeout 30
```

After `LISTENER_READY`, in **host terminal B**:

```bash
udp6_port=48184
read -r -p 'Control nonce from host terminal A: ' control_nonce
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv6 --source-address "$host_v6_scoped" \
  --destination-address "$host_v6_scoped" \
  --interface "$host_v6_interface" --port "$udp6_port" \
  --nonce "$control_nonce"
sudo nft -a list table inet budget_agent_host_input
```

In a **guest terminal**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
read -r -p 'Selected guest IPv6 address with scope when needed: ' \
  guest_v6_scoped
read -r -p 'Selected host IPv6 literal without scope: ' host_v6_literal
read -r -p 'Guest IPv6 interface: ' guest_v6_interface
read -r -p 'Probe nonce from host terminal A: ' probe_nonce
udp6_port=48184
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv6 --source-address "$guest_v6_scoped" \
  --destination-address "${host_v6_literal}%${guest_v6_interface}" \
  --interface "$guest_v6_interface" --port "$udp6_port" \
  --nonce "$probe_nonce"
```

Immediately after that attempt, in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

Require `CONTROL_RECEIVED`, receiver non-delivery and an attributable early
drop. `NOT_TESTED`, exit `3` or a route error is not a denial.

For disposable IPv6 multicast, use group `ff02::114` and port `48185`. In
**host terminal A**:

```bash
multicast6_group=ff02::114
multicast6_port=48185
control_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
probe_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
test "$control_nonce" != "$probe_nonce"
printf 'control_nonce=%s\nprobe_nonce=%s\n' \
  "$control_nonce" "$probe_nonce"
python3 scripts/ops/host-isolation-protocol-fixture.py listen \
  --family ipv6 --bind-address "$host_v6_scoped" \
  --port "$multicast6_port" --interface "$host_v6_interface" \
  --multicast-group "$multicast6_group" \
  --control-nonce "$control_nonce" --probe-nonce "$probe_nonce" \
  --control-source-address "$host_v6_scoped" \
  --probe-source-address "$guest_v6_scoped" --timeout 30
```

In **host terminal B**:

```bash
multicast6_group=ff02::114
multicast6_port=48185
read -r -p 'Control nonce from host terminal A: ' control_nonce
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv6 --source-address "$host_v6_scoped" \
  --destination-address "$multicast6_group" \
  --interface "$host_v6_interface" --port "$multicast6_port" \
  --nonce "$control_nonce"
sudo nft -a list table inet budget_agent_host_input
```

In a **guest terminal**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
read -r -p 'Selected guest IPv6 address with scope when needed: ' \
  guest_v6_scoped
read -r -p 'Guest IPv6 interface: ' guest_v6_interface
read -r -p 'Probe nonce from host terminal A: ' probe_nonce
multicast6_group=ff02::114
multicast6_port=48185
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv6 --source-address "$guest_v6_scoped" \
  --destination-address "$multicast6_group" \
  --interface "$guest_v6_interface" --port "$multicast6_port" \
  --nonce "$probe_nonce"
```

Immediately after that attempt, in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

Require the positive control, receiver non-delivery and exact early-drop or
scoped-ingress attribution.

For IPv6 mDNS, in **host terminal A**:

```bash
sudo tcpdump -ni "$vm_bridge" -c 1 \
  "ether src $vm_mac and ip6 src $guest_v6_literal and ip6 dst ff02::fb and udp dst port 5353"
```

In a **guest terminal**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
read -r -p 'Selected guest IPv6 address with scope when needed: ' \
  guest_v6_scoped
read -r -p 'Guest IPv6 interface: ' guest_v6_interface
mdns6_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv6 --source-address "$guest_v6_scoped" \
  --destination-address ff02::fb --interface "$guest_v6_interface" \
  --port 5353 --nonce "$mdns6_nonce"
```

In **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

Require the exact bridge capture and early mDNS/SSDP drop increment. Repeat for
IPv6 SSDP. In **host terminal A**:

```bash
sudo tcpdump -ni "$vm_bridge" -c 1 \
  "ether src $vm_mac and ip6 src $guest_v6_literal and ip6 dst ff02::f and udp dst port 1900"
```

In the **guest terminal**:

```bash
ssdp6_nonce=$(python3 scripts/ops/host-isolation-protocol-fixture.py nonce)
python3 scripts/ops/host-isolation-protocol-fixture.py send \
  --family ipv6 --source-address "$guest_v6_scoped" \
  --destination-address ff02::f --interface "$guest_v6_interface" \
  --port 1900 --nonce "$ssdp6_nonce"
```

Then in **host terminal B**:

```bash
sudo nft -a list table inet budget_agent_host_input
```

If the guest sender reports success but the bridge capture and early counter
do not see the packet, run this diagnostic capture once on the exact current
tap while sending a new nonce:

```bash
sudo tcpdump -ni "$vm_tap" -c 1 \
  "ether src $vm_mac and ip6 src $guest_v6_literal and udp dst port 5353"
```

A tap-only result is a failed repair, not an inapplicable row. Shut down the VM
and return to the separately reviewed dynamic-binding design required by the
canonical runbook.

Record required IPv6 control behavior from the **guest**:

```bash
ip -6 -o address show dev "$guest_v6_interface"
ip -6 route show
ip -6 neigh show dev "$guest_v6_interface"
ping -6 -c 3 "${host_v6_literal}%${guest_v6_interface}"
```

On the **personal host**, read the counters before and after the working flow:

```bash
sudo nft -a list table inet budget_agent_host_input
```

Each allowed ICMPv6 numeric type must map to a named observed purpose. Do not
broaden the set merely to make `ping` pass; echo request/reply is optional
unless it was explicitly reviewed as required.

### Step 10.8: Required Positive Flows And Guest Runtime

From the **guest orchestration checkout**:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
cd "$orchestration_root"
getent hosts archive.ubuntu.com
curl --fail --location --max-time 15 \
  https://archive.ubuntu.com/ >/dev/null
curl --fail --show-error \
  https://app.budgetanalyzer.localhost/ >/dev/null
./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime
./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local
docker context show
docker info --format '{{.Name}} {{.DockerRootDir}}'
kind get clusters
kubectl config current-context
kubectl config view --minify \
  -o jsonpath='{.clusters[0].name}{"\n"}{.clusters[0].cluster.server}{"\n"}'
kubectl get node kind-control-plane
tilt get uiresources
kubectl get pods -A
```

From the **personal host**:

```bash
ssh budget-agent-vm 'printf "host-to-guest SSH works\n"'
curl --fail --show-error \
  https://app.budgetanalyzer.localhost/ >/dev/null
read -r -p 'Personal-host checkout with the reviewed vm remote: ' \
  vm_remote_checkout
git -C "$vm_remote_checkout" remote get-url vm
git -C "$vm_remote_checkout" ls-remote vm HEAD
```

Run `git ls-remote vm HEAD` from a personal-host checkout whose reviewed `vm`
remote is the guest-local bare repository. Do not add a GitHub remote or push.

## Step 11: Reboot And Repeat The Complete Matrix

Keep the Docker quarantine. From the **personal host**:

```bash
sudo reboot
```

After the host returns, open a new **personal-host terminal** and rediscover the
domain/network/bridge/tap/MAC by rerunning every command in Step 6. Require the
same reviewed topology or stop for review. Then run:

```bash
systemctl is-enabled budget-agent-host-input.service
systemctl is-active budget-agent-host-input.service
sudo nft -a list table inet budget_agent_host_input
sudo nft -a list ruleset
sudo iptables-save -c
sudo ip6tables-save -c
command -v iptables-legacy-save >/dev/null && \
  sudo iptables-legacy-save -c
command -v ip6tables-legacy-save >/dev/null && \
  sudo ip6tables-legacy-save -c
```

Create the post-reboot matrix directory with these exact commands:

```bash
matrix_stage=post-reboot
matrix_time=$(date -u +%Y%m%dT%H%M%SZ)
matrix_dir="$HOME/budget-host-phase7-$matrix_stage-$matrix_time"
install -d -m 0700 "$matrix_dir"
printf 'matrix evidence directory: %s\n' "$matrix_dir"
```

Then execute Step 10 starting with the topology/address discovery block that
creates `host-inputs.sh`; do not rerun its `matrix_stage=pre-reboot` or matrix
directory block. Execute every Step 10.1–10.8 command again. The commands
generate new nonce values and check/refuse occupied fixture ports. Do not reuse
the pre-reboot result as post-reboot evidence.

Collect final Docker-retirement absence evidence without invoking Docker:

```bash
! command -v docker
test ! -S /var/run/docker.sock
! ip link show docker0 >/dev/null 2>&1
systemctl show docker.service docker.socket \
  -p Id -p LoadState -p ActiveState -p UnitFileState
dpkg-query -W \
  -f='${binary:Package}\t${db:Status-Abbrev}\t${Version}\n' 2>/dev/null \
  | awk -F '\t' \
      'substr($2, 2, 1) == "i" && $1 ~ /^(docker|containerd|runc|moby)/'
sudo nft list ruleset \
  | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
sudo iptables-save \
  | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
sudo ip6tables-save \
  | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
command -v iptables-legacy-save >/dev/null && \
  sudo iptables-legacy-save \
    | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
command -v ip6tables-legacy-save >/dev/null && \
  sudo ip6tables-legacy-save \
    | rg '(^|[^[:alnum:]_])(docker|DOCKER)([^[:alnum:]_]|$)' || true
sudo test ! -e /usr/local/sbin/agent-vm-docker-isolation
sudo test ! -e \
  /etc/systemd/system/docker.service.d/agent-vm-isolation.conf
sudo rg -n 'agent-vm-docker-isolation' /etc/ufw/after.init \
  && exit 1 || true
sudo test ! -e /var/lib/docker
sudo find /root/budget-agent-retirement-review -xdev -print
```

Engine/CLI package and chain searches must be empty. Any retained
containerd/runc line must match the previously documented non-Docker consumer.

## Step 12: Collect And Transfer Reviewed Evidence

After the post-reboot matrix passes, use the **personal-host orchestration
checkout**:

```bash
cd "$host_orchestration_root"
sudo -v
python3 scripts/ops/collect-host-isolation-evidence.py \
  --confirm-personal-host
```

The command prints the private output directory. Inspect its raw captures,
`index.json` and `candidate-report.md` on the personal host. Manually redact
unusual hostnames, interfaces, paths or comments while preserving rule order,
protocols, counters and aliases. Do not transfer raw captures or `index.json`.

On the **guest**, create the ignored evidence destination and print its exact
path:

```bash
orchestration_root=$(git rev-parse --show-toplevel)
guest_evidence_dir="$orchestration_root/tmp/host-isolation-audit"
install -d -m 0700 "$guest_evidence_dir"
printf '%s\n' "$guest_evidence_dir"
git check-ignore -v "$guest_evidence_dir"
```

From the **personal host**, transfer only the manually reviewed report. Use the
exact collector directory and the exact guest directory printed above:

```bash
read -r -p 'Private collector output directory: ' audit_output_dir
test -f "$audit_output_dir/candidate-report.md"
read -r -p 'Exact guest evidence directory printed above: ' guest_evidence_dir
scp -- "$audit_output_dir/candidate-report.md" \
  "budget-agent-vm:$guest_evidence_dir/post-repair-candidate-report.md"
```

Transfer or paste a separate narrow summary containing:

- committed source checker exit and lock hash;
- both native installer exits;
- trust one-source checks and curl/Python/Node/Chromium statuses;
- pre- and post-reboot TCP/UDP/multicast rows with positive controls,
  captures/counter deltas and receiver results;
- gateway DNS, DHCP and required IPv6 positive evidence;
- UFW reload, libvirt restart and reboot policy read-backs;
- post-reboot Docker package/socket/CLI/data/helper/drop-in/chain absence;
- AppArmor, VM device, dedicated-network and loopback-listener evidence;
- exact collection times, source revisions and every untested limitation.

Do not overwrite or update the tracked root `candidate-report.md`. Do not stage
or commit anything under `tmp/host-isolation-audit/`.

## Step 13: Resume Existing Phase 7 State

From the **guest orchestration checkout**, confirm the evidence is present and
the accepted remediation plan hash is unchanged:

```bash
cd "$orchestration_root"
test -f tmp/host-isolation-audit/post-repair-candidate-report.md
sha256sum docs/plans/agent-vm-security-review-remediation-plan.md
git status --short
```

The accepted remediation plan SHA-256 must remain
`43804fd8541ea5f789286bfadc68c1cd57d098f87ab407b9dfaa99f8563eb755`.
Do not delete or edit `.ai-session-handler` state. Resume with:

```bash
repo_root=$(git rev-parse --show-toplevel)
workspace_parent=$(dirname "$repo_root")
ai-session-handler run \
  --plan "$repo_root/docs/plans/agent-vm-security-review-remediation-plan.md" \
  --max-phases 999 \
  --quiet \
  --agent-cmd "$workspace_parent/ai-session-handler/.venv/bin/ai-session-handler-codex-high"
```

The runner must retry Phase 7, review the supplied evidence, run only the
authorized read-only guest checks and update the acceptance record. A repeated
block means the evidence remains incomplete; do not delete runner state or
manually mark the phase complete.

## Step 14: Delete Quarantine Only After Acceptance

Run this step only after Phase 7 has accepted all post-reboot firewall,
protocol, confinement, positive-flow and Docker-retirement evidence. From the
**personal host**:

```bash
sudo find /root/budget-agent-retirement-review -xdev -print
read -r -p 'Type DELETE-REVIEWED-DOCKER-QUARANTINE: ' \
  retirement_confirmation
test "$retirement_confirmation" = DELETE-REVIEWED-DOCKER-QUARANTINE
sudo rm -rf -- /root/budget-agent-retirement-review
sudo test ! -e /root/budget-agent-retirement-review
```

Stop if the listing contains anything outside the reviewed Docker retirement
inventory. This deletion is irreversible; never broaden or parameterize its
fixed target.

## Final Acceptance Conditions

The manual work is complete only when all of the following are true:

- Workspace committed-source proof passes from `git archive HEAD`.
- Both native user-tool installer runs pass from current reviewed source.
- Exactly one managed guest CA remains and all four HTTPS clients verify it.
- The early nftables table is enabled, active and effective before UFW/libvirt
  permissive paths after UFW reload, libvirt network restart and host reboot.
- Applicable IPv4/IPv6 TCP, UDP, multicast, mDNS and SSDP attempts have paired
  positives plus exact ingress/drop attribution before and after reboot.
- Gateway DNS, DHCP, required IPv6 controls, guest Internet HTTPS, host SSH,
  reviewed Git access, app HTTPS and guest Docker/Kind/Tilt remain healthy.
- Mint Docker daemon/socket/CLI/engine packages, `docker0`, Docker chains,
  retired data, helper, drop-in and UFW hook invocation are absent after reboot.
- The running VM remains AppArmor-confined on its dedicated network with no
  host filesystem/device passthrough and loopback-only app/VNC listeners.
- Phase 7 updates the independent post-migration review without changing the
  meaning of the completed historical migration acceptance.
