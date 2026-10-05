# Native VM Agents: Human Preparation And Cutover

**Status:** Checkpoint A completed by operator on 2026-10-04; Phases 1–2 are
cleared to run. The native execution plan has not yet been invoked. Earlier
VM/container results remain prior evidence unless explicitly recorded in the
acceptance record.
**Execution plan:** [Native agents in the VM](agent-vm-native-execution-plan.md).
**Evidence:** [Host-isolation acceptance record](agent-host-isolation-acceptance.md).

This is the human checklist for migrating the **existing** development VM to
native agents. It replaces the previous manual plan and does not require that
file, either previous execution plan, or their runner state. The execution plan
owns repository implementation; this document owns installation, authentication,
host policy, manual live-update acceptance and runtime retirement.

The final arrangement is a normal guest user running agents, AI Session Handler,
Tilt and builds directly in Ubuntu. Guest Docker remains for application builds,
Kind, infrastructure and disposable test containers. There is no daily agent
container, agent Compose lifecycle or separate agent Maven home.

## Location And Authority

- **Personal host:** the Mint desktop terminal. Only the human administers
  libvirt/firewalls, manages GitHub credentials, signs browser certificates,
  transfers source, or retires Mint Docker.
- **Guest OS:** a normal console/SSH terminal in the Ubuntu VM, outside any
  container. The human runs system/user provisioning and provider login here.
- **Existing guest container:** used once for execution Phases 1–2. It must be
  on guest Docker with guest-local files. Checkpoint B.3 destroys it with all
  old guest Docker state before rebuilding the application for native phases.
- **Native agent:** normal guest process after Checkpoint B. It can administer
  guest Docker and approved Kind, so all guest assets are in its trust boundary.

Keep the same normal guest development user for Tilt, agents and builds. Do not
use root as the agent account or add blanket passwordless sudo. Docker-group
membership already conveys guest-root-equivalent power; it is not a boundary
between the user and the guest OS. Native command sandboxing is an additional
control, subject to the selected launcher's actual permissions.

Keep all repositories, caches and runtime data guest-local. Never add shared
folders, host Docker/libvirt sockets, host kubeconfig, SSH/GPG forwarding,
credential proxies, GitHub login or production credentials. Provider login
inside the guest is permitted; its state is accessible within the guest.

## Checkpoint Order

| Checkpoint | Human action | Next execution |
| --- | --- | --- |
| A | Preserve source, verify existing guest and host boundary, transfer this plan | Phases 1–2 in the existing guest container, then stop |
| B | Review/run native installers, establish trust/authentication, destroy old guest Docker state and clean-rebuild the application | Phases 3–8 natively in the same guest checkout/state |
| C | Verify browser, live updates, native daily workflow, reboot and absence of legacy agent resources | No active handler |
| D | Return reviewed work, retire Mint Docker, repeat final boundary proof | Native daily work |

Do not reboot, change authentication or install over a running worker. The only
migration-time `setup.sh` invocation is the explicitly destructive guest-local
clean rebuild in B.3 after every old worker exits. Missing prerequisites stop
the relevant checkpoint. A source fix needing a new installation is reviewed,
installed by the human after the worker exits, then retried using the new
plan's normal runner recovery.

## Checkpoint A: Prepare The Existing Guest

### A.1 Preserve Source And Identify The Machines

End any old handler/worker invocation; retain its files as historical evidence.
Privately back up uncommitted/untracked source on both machines. Inspect every
affected checkout with `git status --short` and record selected revisions and
dirty inputs. Do not reset, overwrite or synchronize away guest work.

The accepted prior configuration was VM `budget-analyzer-agent`, Ubuntu 24.04
x86-64, 8 vCPUs, 24 GiB RAM, 200 GiB sparse disk, libvirt network `agent-nat`
on `virbr1`, gateway `192.168.231.1`, guest `192.168.231.10`. These are discovery
baselines, not proof of current state. Resolve actual storage/repository paths
from the existing guest setup; do not create a second workspace.

From the **personal host**, inspect:

```bash
virsh --connect qemu:///system dominfo budget-analyzer-agent
virsh --connect qemu:///system net-info agent-nat
virsh --connect qemu:///system dumpxml budget-analyzer-agent
ssh -G budget-agent-vm
```

Review XML privately: require active AppArmor confinement, guest disks outside
personal source trees, no shared filesystem/host-device passthrough, and no
clipboard/file-transfer integration. Retain only redacted results. Require
verified strict SSH host keys, the dedicated host-to-guest identity,
`IdentitiesOnly yes`, `ForwardAgent no`, `ForwardX11 no`, and no unrequested
forwarding. No guest-to-host SSH identity is needed.

Keep the dedicated VS Code Remote SSH profile. Disable automatic/restored port
forwarding and `git.terminalAuthentication` / `git.useIntegratedAskPass`; do not
use **Reopen in Container** for the final native workflow or install remote
extensions that bridge personal GitHub authentication. Recreate terminals after
settings changes. Check only presence/absence of sensitive configuration.

### A.2 Transfer Reviewed Source Explicitly

Use existing host `vm` remotes and matching guest-local bare `origin` repos.
Transfer reviewed orchestration/workspace changes and any aligned handler or
service revisions through the human-owned Git flow below. These plans may be
transferred along with deletion of the three superseded plans; their content
and links do not depend on those files. Preserve the acceptance record.

For each selected repository, from its **personal-host checkout**:

```bash
native_branch=$(git branch --show-current)
test -n "$native_branch"
git status --short
git push vm "HEAD:refs/heads/$native_branch"
```

Proceed only after reviewing/committing intended changes yourself and confirming
`vm` is the dedicated guest SSH destination. In the matching **guest checkout**,
select the reviewed branch name and inspect the worktree before fetching:

```bash
read -r -p 'Reviewed branch name: ' native_branch
git status --short
git fetch origin
git switch "$native_branch"
git merge --ff-only "origin/$native_branch"
```

For a new branch, explicitly create it with
`git switch --track "origin/$native_branch"` instead. Stop on dirty conflicts,
divergence or unexpected origins; never force/reset to make transfer work.
Guest clones must have only their matching local bare origin, including push
URLs. Do not rerun one-time repository setup against existing working clones.

### A.3 Revalidate Host Isolation

The installed host policy must remain active during preparation, native work
and C while Mint Docker exists. Inspect from the **personal host**:

```bash
native_vm_bridge=$(virsh --connect qemu:///system net-info agent-nat | awk '/^Bridge:/ {print $2}')
test -n "$native_vm_bridge"
ip -brief -4 address show
ip -brief -6 address show
sudo ufw status verbose
sudo ufw status numbered
sudo iptables -S DOCKER-USER
sudo ip6tables -S DOCKER-USER
sudo systemctl cat docker.service
sudo sed -n '1,200p' /usr/local/sbin/agent-vm-docker-isolation
sudo sed -n '1,200p' /etc/ufw/after.init
```

The previously installed policy is:

- Persistent UFW native input denial on the dedicated VM bridge in IPv4/IPv6,
  with only needed IPv4 DHCP and gateway DNS TCP/UDP exceptions before the deny.
  Preserve essential IPv6 neighbor discovery and established replies.
- For Mint's `iptables-nft` Docker backend, one new-connection reject in each
  IPv4/IPv6 `DOCKER-USER` chain from the VM bridge to `docker0` and `br-+`.
  Cover any additionally discovered Docker bridge explicitly.
- Root-owned `/usr/local/sbin/agent-vm-docker-isolation`, Docker's
  `/etc/systemd/system/docker.service.d/agent-vm-isolation.conf`
  `ExecStartPost`, and the existing UFW `after.init` start hook reapply these
  rules without duplicates. The UFW file also has unrelated packaged content
  that must be preserved.

If these controls are missing, the firewall backend changed or a rule cannot
be explained, stop for a separately reviewed host policy repair. Do not enable
a new firewall, flush tables or install guest-authored host scripts blindly.
This migration assumes the existing VM boundary, not a new host rollout.

Collect paired tests, not just a PASS assertion. In separate **host terminals**,
serve empty disposable directories on unused native fixture ports:

```bash
native_fixture_dir=$(mktemp -d)
python3 -m http.server 18080 --bind 0.0.0.0 --directory "$native_fixture_dir"
```

Where IPv6 is available:

```bash
native_ipv6_fixture_dir=$(mktemp -d)
python3 -m http.server 18081 --bind :: --directory "$native_ipv6_fixture_dir"
```

From another **host terminal**, require positive controls and inspect bindings:

```bash
curl --noproxy '*' --fail --max-time 3 http://127.0.0.1:18080/
curl --noproxy '*' --fail --max-time 3 'http://[::1]:18081/'
sudo ss -ltnp '( sport = :18080 or sport = :18081 )'
```

From the **guest**, use `nc -4 -vz -w 3 ADDRESS 18080` against every relevant
inventoried nonloopback host IPv4 destination, and `nc -6 -vz -w 3 ADDRESS
18081` against reachable host IPv6 destinations, with guest interface scope
for link-local addresses. Select actual addresses from discovery, not a copied
inventory. Require rejection/timeout, record routing applicability, and never
count `Network is unreachable` as a filtering pass.

Also create one named disposable host Docker HTTP fixture using a reviewed
digest-pinned image, no host mounts, and unused port 18082 bound to the VM
bridge address. Record its exact command/image/mapping/container address.
Require a successful host request to the published address, then denied guest
requests to that address and to the container IP/port directly. Cover each
applicable IPv4/IPv6 Docker path and inspect rule counters or equivalent
evidence. Kernel DNAT need not appear as a process in `ss`. Remove only the
named fixture. Do not invent a route or temporarily disable filtering to test.

These HTTP servers are empty network diagnostics, not a bypass for the HTTPS
application. Stop them and remove only their empty temporary directories.
From the **guest**, require working DNS and verified outbound HTTPS:

```bash
getent hosts archive.ubuntu.com
curl --fail --location --max-time 15 https://archive.ubuntu.com/ >/dev/null
```

From the **host**, require SSH and the reviewed Git transfer to work:

```bash
ssh budget-agent-vm 'printf "host-to-guest SSH works\n"'
```

Record collection time, commands, listener positives, paired denials,
interface/family coverage, policy/hook identity and limitations. Tests cover
host destinations; isolation from other LAN/VPN peers and Internet allowlisting
are not claimed. Changed network/policy inputs invalidate the affected proof.

### A.4 Verify Existing Guest And Launch Two Preparation Phases

From the **guest OS orchestration checkout**:

```bash
./scripts/bootstrap/check-agent-vm-prerequisites.sh
./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local
docker context show
docker info --format '{{.Name}} {{.DockerRootDir}}'
kind get clusters
kubectl config current-context
kubectl config view --minify -o jsonpath='{.clusters[0].name}{"\n"}{.clusters[0].cluster.server}{"\n"}'
kubectl get node kind-control-plane
tilt get uiresources
kubectl get pods -A
```

Require the default local Unix Docker socket, no endpoint overrides, healthy
existing Tilt and the exact loopback `kind-kind` contract. Inspect the current
guest agent by its reviewed Compose labels and container ID: guest networking,
same-path working/bare mounts, guest socket, exact guest kubeconfig, no nested
daemon or privileged mode. Record sanitized identity/mount evidence, not full
environment or secrets. Prove provider/handler commands already work in it.

Use the existing workspace `scripts/agent-vm-container-shell.sh` from the guest
OS to enter that inspected container. If it is stopped, the existing `start`
helper may start it without image rebuild. Do not use `--bootstrap-only` after
Kind exists. If its exact configuration is unavailable, stop rather than
reconstructing it with new privileges.

Complete **Native Preparation Handoff** in the acceptance record. Then, inside
the **guest container's orchestration checkout**, with no competing workers:

```bash
ai-session-handler status --plan "$PWD/docs/plans/agent-vm-native-execution-plan.md"
ai-session-handler run \
  --plan "$PWD/docs/plans/agent-vm-native-execution-plan.md" \
  --max-phases 2 --quiet \
  --agent-cmd "ai-session-handler-codex-high"
```

The first launch must have fresh state for this plan. End the handler after
Phases 1–2; confirm status selects Phase 3. Do not use `--max-phases 999` yet.
No host state is copied into the guest; this plan's state already lives in the
same guest checkout that native execution will use.

## Checkpoint B: Install And Launch Native Agents

### B.1 Review The Installer And Run It As The Guest User

The following are **implementation deliverables of Phases 1–2**, not commands
claimed to exist before that work. Review source and fixture results first.
Require a complete tool inventory, explicit version/checksum policy, no
automatic credential import, no CA generation, no blanket sudoers rule and no
Docker/Kind/Tilt restart on an already provisioned guest. Privately preserve
any existing guest user configuration before installation.

In the **guest OS workspace checkout**, after all authoring workers exit:

```bash
native_worktree_parent=$(cd .. && pwd -P)
read -r -p 'Existing guest bare-repository parent: ' native_bare_parent
test -d "$native_bare_parent"
./scripts/provision-agent-vm-guest.sh --docker-user "$USER"
```

The normal user invokes the script; it uses explicit sudo only for reviewed
system operations. Do not run the user installer as root. If guest Docker
would need an upgrade/restart or an OS reboot, stop for a scheduled maintenance
window after all workers exit; do not interrupt it implicitly in provisioning.
Reconnect after Docker-group or login-environment changes, then rederive the
paths in the fresh **guest workspace checkout**:

```bash
native_worktree_parent=$(cd .. && pwd -P)
read -r -p 'Existing guest bare-repository parent: ' native_bare_parent
./scripts/install-agent-vm-user-tools.sh \
  --worktree-parent "$native_worktree_parent" --bare-parent "$native_bare_parent"
./scripts/check-agent-vm-tools.sh \
  --worktree-parent "$native_worktree_parent" --bare-parent "$native_bare_parent"
```

Run installation a second time to verify idempotence and preservation of user
configuration. Confirm no duplicate shell fragments/hooks or unexpected tool
upgrade. Phase 2 must supply any exact reviewed trust/environment setup needed
before the verifier passes. Record failures honestly and fix source through
the owning repository; do not compensate manually and call it repeatable.

### B.2 Establish Native Trust And Provider State

Existing TLS inputs are the three approved ignored files under orchestration
`nginx/certs/k8s/`: `_wildcard.budgetanalyzer.localhost.pem`,
`_wildcard.budgetanalyzer.localhost-key.pem`, and `_mkcert-rootCA.pem`.
The mkcert **root signing key never enters the guest**. Validate the existing
inputs with `scripts/bootstrap/install-imported-ingress-tls.sh --validate-only`.
Use Phase 2's native trust flow to install the public root in the guest system
and this user's Chromium NSS database, preserving public roots. Prove curl,
Python, Node and Playwright verified access to the exact local HTTPS app.

Native `tilt up` uses the non-generating `ingress-tls-secret` resource to
validate those same files and reconcile the local Kind Secret. Require that
resource and `istio-ingress-config` to become healthy before the HTTPS proof.
If Tilt reports `mkcert-tls-secret` or invokes `setup-k8s-tls.sh`, stop because
the guest checkout predates the native-TLS wiring; do not install mkcert or
select guest behavior through an environment variable, hostname or marker.

If inputs expired or changed, the human renews only on the personal host with
`scripts/bootstrap/renew-host-ingress-tls.sh`, explicitly recopies only the
three approved files over host-initiated SSH, and follows
[the guest import/renewal workflow](../development/local-environment.md#development-vm-import-and-renewal).
Do not rerun host `setup.sh`, generate an ingress CA in the guest, or bypass
TLS verification. A change requiring cluster Secret installation first needs
the exact guest Docker and Kubernetes target checks.

Authenticate the selected provider natively as the guest development user,
using its current supported interactive/device flow. Do not copy provider
volumes, personal browser cookies, host API keys or an entire home directory.
Install all supported CLI capabilities but authenticate only those you use.
Keep provider configuration private and test a benign workspace-read request.
Do not authenticate GitHub. Proxy tools remain installed but inactive unless
you explicitly perform the separately documented optional inspection setup;
that setup must not run automatically during provisioning or a worker test.

Verify a fresh login shell and a Remote SSH terminal resolve the same native
tools, home, Maven Local and trust. Require these commands to work:

```bash
command -v codex claude gemini ai-session-handler ai-session-handler-codex-high ai-run
ai-session-handler --version
ai-session-handler-codex-high --help
check-budget-analyzer-local-ca-trust
curl --fail --show-error https://app.budgetanalyzer.localhost/ >/dev/null
```

Privately check effective Git credentials/remotes/includes, push URLs and
environment. `SSH_AUTH_SOCK`, `GITHUB_TOKEN`, `GH_TOKEN`, `GIT_ASKPASS` and
`SSH_ASKPASS` must be absent, as must forwarded GPG sockets and host credential
bridges. Require native sandbox proof for the mode actually selected; do not
disable AppArmor globally to make bubblewrap start.

### B.3 Destroy Guest Docker State, Clean-Rebuild, And Resume

This is the selected destructive cutover. It deletes every container and every
named or anonymous volume from the development VM's local Docker daemon, then
prunes unused images, build cache and custom networks. The old agent container,
its image and provider volumes are intentionally not retained. All application
database/PVC state is also discarded. Native provider state in the normal
guest user's home, working and bare repositories, orchestration `.env`, the
three imported TLS files and `.ai-session-handler/` runner state are ordinary
guest files and are not Docker prune targets.

Do not run this section from the old agent container. Finish and exit every old
handler/worker, preserve any required work in the guest repositories, and open
a fresh guest OS shell. Do not proceed if any identity, durable-input or Docker
target check fails.

First prove the durable inputs and Phase 1–2 runner state exist outside Docker:

```bash
cd "$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration"

id -un
systemd-detect-virt --container || true
systemd-detect-virt --vm

./scripts/bootstrap/check-agent-vm-prerequisites.sh
./scripts/bootstrap/install-imported-ingress-tls.sh --validate-only
test -s .env

ai-session-handler status \
  --plan "$PWD/docs/plans/agent-vm-native-execution-plan.md"
```

Require the expected normal guest user, container detection `none`, QEMU/KVM
VM detection, passing guest-local/TLS checks, an existing `.env` and status
selecting Phase 3. A missing input or runner state is a stop condition.

From another guest shell, stop Tilt-managed resources:

```bash
cd "$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration"
tilt down
```

Press `Ctrl+C` in the terminal that was running `tilt up`. Then verify Tilt is
stopped and review the exact Docker resources that will be destroyed:

```bash
if pgrep -a -x tilt; then
  printf 'ERROR: stop every Tilt process before deleting Docker state.\n' >&2
  exit 1
fi

./scripts/bootstrap/check-agent-vm-prerequisites.sh
docker context show
docker context inspect default --format '{{.Endpoints.docker.Host}}'
docker info --format 'daemon={{.Name}} root={{.DockerRootDir}}'

docker container ls --all \
  --format 'container={{.ID}} name={{.Names}} image={{.Image}} status={{.Status}}'
docker volume ls
docker image ls
docker system df
```

Require context `default`, endpoint `unix:///var/run/docker.sock`, daemon name
equal to the guest's short hostname and root `/var/lib/docker`. This inventory
is final human review, not retained cleanup evidence. If anything belongs
outside this disposable development-VM environment, stop instead of deleting
it.

After review, delete all guest Docker containers and volumes, then prune all
unused image, build-cache and custom-network state:

```bash
read -r -p \
  'Type DELETE-ALL-GUEST-DOCKER-DATA to continue: ' \
  docker_reset_confirmation
test "$docker_reset_confirmation" = DELETE-ALL-GUEST-DOCKER-DATA
unset docker_reset_confirmation

docker container ls --all --quiet \
  | xargs --no-run-if-empty docker container rm --force --volumes

docker volume prune --all --force
docker system prune --all --force --volumes

test -z "$(docker container ls --all --quiet)"
test -z "$(docker volume ls --quiet)"
docker system df
```

Both empty-state checks must pass. Default Docker networks remain. Do not
delete `/var/lib/docker`, stop the daemon, remove repositories or delete native
home-directory state.

Rebuild the complete guest-local Kind environment through the supported clean
bootstrap:

```bash
cd "$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration"

./scripts/bootstrap/check-agent-vm-prerequisites.sh
./scripts/bootstrap/install-imported-ingress-tls.sh --validate-only
./setup.sh --guest-local

cd "$BUDGET_ANALYZER_WORKTREE_PARENT/budget-analyzer-web"
npm install

cd "$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration"
./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local
tilt up
```

Leave `tilt up` running. In a second fresh guest shell, repeat the resource
status command until required resources are healthy, then prove the rebuilt
ingress and application:

```bash
cd "$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration"

tilt get uiresources \
  -o custom-columns='NAME:.metadata.name,UPDATE:.status.updateStatus,RUNTIME:.status.runtimeStatus'
tilt logs ingress-tls-secret --tail 100

check-budget-analyzer-local-ca-trust
curl --fail --show-error \
  https://app.budgetanalyzer.localhost/ >/dev/null

./scripts/smoketest/smoketest.sh
```

Do not continue while a required resource is pending or reports an error. The
TLS log must show validation and Secret installation from the imported files,
never guest certificate generation.

Record **Native Execution Handoff** in the acceptance record and workspace
handoff evidence: actual installer revisions, fixture/live results, user/home
and command resolution, native provider proof, actual sandbox mode, trust,
identity/target checks, empty Docker-state proof, clean-bootstrap result,
rebuilt Tilt/application proof, host boundary evidence and remaining C/D work.
State explicitly that no old container or Docker volume was retained. Do not
claim this evidence before the commands pass. Leave the accepted execution-plan
bytes unchanged; this human cutover does not use `--accept-plan-change`.

Only after the evidence exists, resume from the native guest OS orchestration
checkout:

```bash
cd "$BUDGET_ANALYZER_WORKTREE_PARENT/orchestration"

ai-session-handler status \
  --plan "$PWD/docs/plans/agent-vm-native-execution-plan.md"

ai-session-handler run \
  --plan "$PWD/docs/plans/agent-vm-native-execution-plan.md" \
  --max-phases 999 --quiet \
  --agent-cmd "ai-session-handler-codex-high"
```

Status must still select Phase 3. Missing state is a path/transfer problem, not
permission to manufacture completed phases or import old state. For a genuinely
stopped attempt, inspect its artifacts, end any surviving worker and use
`--retry-stopped`. Keep the native shell connected until completion.

## Checkpoint C: Accept Native Daily Operation

Run only after all eight phases pass and every handler/worker has ended.

1. Review native tool, representative service and application evidence. All
   required tool capabilities must be installed and checked; optional proxy
   activation can remain unused with that limitation recorded. Test a new
   agent session, exit it, then start another. Provider state and Maven/Gradle
   caches persist; Docker, Kind and Tilt keep running. No agent container starts.
2. On the **personal host**, stop only the identified old app/Kind publisher
   occupying port 443. Keep Mint Docker and its firewall hooks until D. Confirm
   the port is free and start the existing restricted forward:

   ```bash
   authbind ssh -N -T -o ExitOnForwardFailure=yes \
     -L 127.0.0.1:443:127.0.0.1:443 budget-agent-vm-forward
   ```

   Require the pre-existing host authbind permission and dedicated SSH alias;
   do not launch a root SSH session as a workaround. In a second host terminal:

   ```bash
   sudo ss -ltnp '( sport = :443 )'
   curl --fail --show-error https://app.budgetanalyzer.localhost/ >/dev/null
   openssl s_client -connect 127.0.0.1:443 \
     -servername app.budgetanalyzer.localhost -verify_return_error </dev/null
   ```

   Require only `127.0.0.1:443`, normal trusted curl and certificate verification
   success. Keep observability ClusterIP-only and any operator forwards on
   loopback; no public monitoring hostname.
3. In the dedicated host development browser profile, test trusted HTTPS,
   disposable development login/logout/login, an API-backed page and expected
   frontend WebSocket behavior. Do not expose personal cookies to the guest.
4. Perform the two exact reversible Java/frontend save fixtures supplied by
   execution Phase 8 in this document. Require Remote SSH saves to trigger the
   expected guest Tilt update and visible behavior, restore only fixture edits,
   and verify restoration and unchanged personal-host source. These procedures
   are a required Phase 8 deliverable; C cannot pass without them.
5. Shut down the guest cleanly, reboot the personal host, restart the VM, guest
   Tilt, native agent and loopback forward using the daily flow below. Repeat
   A.3's paired native/Docker boundary tests and positive controls, trust,
   credential checks, native tool preflight and browser acceptance. Record
   actual post-reboot evidence; pre-reboot passes do not establish persistence.
6. Confirm B.3 left no legacy guest agent container, image or provider volume
   and that the rebuilt Kind/application state remains healthy. Do not repeat
   the blanket prune during acceptance or delete newly rebuilt PVC/application
   data. Prove native provider sessions and the app remain independent of all
   retired agent-container state.

Record C results and measured guest memory/disk use, not full process/env dumps.
Any failure leaves acceptance pending. Returning to a container is not a native
pass; repair the native path before continuing to D.

## Checkpoint D: Return Work And Retire Mint Docker

### D.1 Return Reviewed Work Before Destruction

Review/commit guest work yourself, publish each selected branch to its local
bare origin, then fetch it on the personal host. From the **guest checkout**:

```bash
native_branch=$(git branch --show-current)
test -n "$native_branch"
git push origin "$native_branch"
```

From the matching **personal-host checkout**:

```bash
read -r -p 'Reviewed guest branch name: ' native_branch
git fetch vm "refs/heads/$native_branch:refs/remotes/vm/$native_branch"
git log --oneline "HEAD..vm/$native_branch"
git diff "HEAD...vm/$native_branch"
git merge --ff-only "vm/$native_branch"
```

Stop and review divergence; do not force. Only the host may subsequently push
to GitHub or create a PR. Preserve untracked work separately before retiring
containers. Close all Mint devcontainers/agents; never retire their daemon
from an agent session that depends on it.

### D.2 Discover And Retire Only Mint's Installation

In a **normal personal-host terminal**, inventory exact remaining containers,
images/volumes, Docker packages, data-root realpaths/mounts and Docker's service
configuration. Useful read-only checks:

```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker volume ls
docker info --format '{{.DockerRootDir}}'
systemctl is-active docker.service docker.socket containerd.service
dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\t${Version}\n' 2>/dev/null | rg '^ii\s+(docker|containerd|runc)'
sudo readlink -f /var/lib/docker /var/lib/containerd
sudo findmnt --target /var/lib/docker
```

Prove the guest app and Docker work independently through SSH/verified HTTPS.
Stop only identified Mint workloads, then disable both Docker activation paths:

```bash
sudo systemctl disable --now docker.service docker.socket
! systemctl is-active --quiet docker.service
! systemctl is-active --quiet docker.socket
test ! -S /var/run/docker.sock
ssh budget-agent-vm 'docker info >/dev/null && kubectl get node kind-control-plane'
curl --fail --show-error https://app.budgetanalyzer.localhost/ >/dev/null
```

Purge only the discovered Docker package family. Do not assume Docker CE when
the host uses distribution `docker.io`. Remove containerd/runc only after
proving no other consumer needs them, and review any autoremove proposal.
Privately inspect Docker client/registry credentials; never print them.

After source backup and final human confirmation, delete only the inspected
retired Mint Docker data root; delete containerd data only if exclusively
retired. If the reported/canonical Docker root differs from `/var/lib/docker`,
stop and review exact targets before deletion. Do not copy any Mint runtime
image, database, volume or cache to the guest. Remove only Docker-owned package
sources/keys, daemon configuration and obsolete group membership discovered
during review. This checklist deliberately does not supply a blanket `rm -rf`
or package wildcard against an uninspected installation.

### D.3 Remove Transitional Hooks And Prove The Final State

Remove only the Docker-isolation call from the host's existing
`/etc/ufw/after.init`; preserve other content. Validate the retained script with
`sh -n` and ShellCheck, reload UFW, and confirm the permanent bridge DHCP/DNS/
input-deny policy remains. Only then remove the reviewed Docker service drop-in
and `/usr/local/sbin/agent-vm-docker-isolation`, and run systemd daemon-reload.
Do not remove UFW/libvirt or flush firewall tables. Final reboot clears retired
Docker-created state; inspect both address families afterward.

Reboot the personal host and start the guest/daily flow again. Require no Mint
Docker daemon/socket/CLI/engine packages, retired runtime data, Docker hooks or
Docker firewall chains. Record any retained non-Docker containerd consumer
explicitly. Repeat native host fixture denials with positives, DNS/download,
host-initiated SSH/Git, trusted loopback HTTPS, native agent and guest
Docker/Kind/Tilt health. Docker-path fixtures are now inapplicable because Mint
Docker is absent; record absence rather than inventing a filtering pass.

Complete the native acceptance section with C/D results, revisions, commands,
limitations and the human's final acceptance. Do not relabel historical
container results as native evidence.

## Daily Workflow After Acceptance

1. Start the VM from the personal host and connect using the dedicated Remote
   SSH profile. Use guest working clones; no shared folder or container reopen.
2. In the guest orchestration checkout, run the native tool/runtime preflight
   and start `tilt up` only if that Tilt instance is not already running. Tilt
   reconciles the existing imported ingress files into the Kind Secret; it
   never generates browser-facing certificates or changes guest trust.
3. Start the host loopback HTTPS forward and dedicated development browser.
4. In a normal guest terminal, run the selected agent command, or use
   `ai-run PLAN_NAME` from the owning repository. Plain commands keep their
   documented defaults; explicit wrappers retain their reviewed behavior.
5. End agent processes independently of Tilt. Stop Tilt and shut down the VM
   deliberately when finished; do not use bootstrap, image rebuilds or Docker
   cleanup as a daily lifecycle command.
6. Transfer source with reviewed Git operations as in A.2/D.1. Host publication
   remains a separate human action. Rerun installers only for explicit tool
   refresh/repair, outside active worker sessions.

## Recovery And Reprovisioning

For a native tool defect, fix the workspace-owned source, end workers, review
and rerun the appropriate installer, then run the verifier and retry the
stopped phase. Preserve this new plan's state; do not hand-edit it or use an old
plan as a recovery runner.

For an explicit clean guest rebuild, the human creates/reviews a replacement
Ubuntu VM under the same boundary requirements, seeds guest-local bare/working
repos with the workspace repository-setup script, runs the native installers,
transfers approved TLS inputs, and follows
[guest first bootstrap](../development/getting-started.md#development-vm-first-bootstrap).
That path recreates Kind and requires fresh runtime/boundary acceptance. It
never launches an agent container or imports old Docker/cache state. If host
libvirt/firewall prerequisites must be rebuilt too, prepare a separate reviewed
host setup before enabling autonomous agents; this existing-VM migration is
not authorization to improvise host policy.
