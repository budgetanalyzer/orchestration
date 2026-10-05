# Autonomous AI Execution Pattern

## Overview

Budget Analyzer gives coding agents broad authority inside a disposable local
development boundary. That authority is useful for builds, tests, Docker,
Kubernetes and local API diagnostics, but it is not authority over the personal
workstation, GitHub publication, staging or production.

The supported development-VM target is **native agents**, with Docker reserved
for application builds, Kind, infrastructure and Testcontainers. Workspace-
owned system/user installers and the normal guest home now provide the agent
toolchain, provider state, Maven Local, Gradle caches and browser data. All
eight repository execution phases passed on 2026-10-05; the human Remote SSH,
live-update, reboot and final Mint Docker retirement checkpoints remain.

Read the [native execution plan](../plans/agent-vm-native-execution-plan.md)
and [human checkpoints](../plans/agent-vm-native-manual-plan.md) before
continuing migration acceptance. The old guest agent container has been
retired and is not an alternative daily path. The personal-host Mint
devcontainer remains only until the explicit Checkpoint D retirement; do not
resume native work there or reconstruct the removed guest container.

## Boundary Terminology

- **Personal host**: the Linux Mint workstation. It owns GitHub credentials,
  canonical GitHub remotes, the native VS Code and browser UIs, the mkcert
  signing key, libvirt and the host-enforced VM firewall boundary.
- **Development VM**: the Ubuntu guest. It owns working clones, local bare Git
  repositories, Docker storage, dependency caches, Kind, Tilt, Kubernetes
  state, development credentials and application data.
- **Native agent**: a process of the normal guest development user,
  sharing that user's tool environment and build caches with Tilt. Access to
  the rootful guest Docker daemon confers guest-root-equivalent authority.
  Native command sandboxing can constrain ordinary commands, but unrestricted
  Docker access remains a route to control guest assets.
- **Retired guest agent container**: the preparation bridge used only through
  native Phases 1–2. Its tracked Compose/lifecycle sources and Docker state are
  gone. Historical evidence does not authorize recreating it.

A marker, compose-project name, environment variable or command-line flag can
prevent an accidental launch in the wrong place. It does not prove isolation.
Isolation comes from the VM boundary, guest-local storage and Docker endpoint,
the absence of host mounts and credentials, and host-enforced network policy.

## Native Guest Architecture

```text
Personal host
  GitHub credentials + canonical clones
  native VS Code UI -- Remote SSH ----------> development VM working clones
  browser -- loopback-only SSH forward ------> development VM ingress
  git push/fetch over host-initiated SSH ----> development VM bare repositories
  mkcert signing key (never copied)

Development VM
  <guest-storage>/bare/<repo>.git
  <guest-storage>/worktrees/<repo>
  normal guest home
    provider state + Maven Local + Gradle/browser caches
  native agent + AI Session Handler + Tilt
  /var/lib/docker (one guest-local Docker daemon)
    Kind + application images + Testcontainers
```

There is no shared host workspace. Each guest working clone has only a
guest-local bare `origin`; the personal host has the explicit `vm` remote. The
host pushes reviewed committed objects into the bare repository, and later
fetches agent commits from it. Only the host contacts GitHub or creates a pull
request. Do not add rsync, a shared folder, an authenticated GitHub remote, a
credential proxy, automatic publication or a forwarded SSH/GPG agent.

VS Code Remote SSH keeps the editor UI on the personal host while remote
extensions, terminals, language servers, tasks and files execute in the guest.
Use the dedicated host profile from the manual plan. Keep SSH-agent, X11,
credential and automatic port forwarding disabled, and do not install remote
extensions that expose a personal GitHub session.

## Authority And Remaining Risk

The guest agent may:

- modify guest working clones and push commits to guest-local bare remotes;
- run builds and tests, create Testcontainers workloads, and administer the
  guest Docker daemon;
- inspect and mutate the approved guest-local `kind-kind` cluster;
- read development Kubernetes Secrets, imported ingress keys, generated
  infrastructure keys and disposable local API-test credentials.

The guest agent must not receive or use:

- GitHub write credentials, host credential helpers, personal SSH/GPG agents,
  authenticated browser state or personal home-directory mounts;
- the host Docker or libvirt socket, host kubeconfig, host workspace, staging
  or production kubeconfigs, cloud/deployment credentials, user credentials or
  session cookies;
- authority to deploy or administer staging or production.

The VM boundary protects the personal workstation; it does not protect guest
assets from the agent. Host review, branch protection and normal pull-request
controls remain necessary before publishing agent-authored commits or workflow
changes. Normal Internet access is permitted, so secrets placed in the guest
must be considered accessible to the agent. LAN/VPN destination isolation and
Internet allowlisting are outside this contract.

## Docker And Kubernetes Target Selection

Native agents use the guest's default `/var/run/docker.sock` directly. Do not
set `DOCKER_HOST`, `DOCKER_CONTEXT` or `TESTCONTAINERS_HOST_OVERRIDE`, select a
TCP/SSH endpoint, run a nested daemon, or forward another machine's socket.
Docker-group authority is guest-root-equivalent even when the selected agent
command uses a native command sandbox.

Before guest bootstrap, `scripts/bootstrap/check-agent-vm-prerequisites.sh`
fails closed unless execution is native, Docker uses the default local Unix
socket, no remote-Docker environment is selected, the service is active on the
current machine, the daemon name matches the guest and its data root is
`/var/lib/docker`. `./setup.sh --guest-local` repeats that non-runtime check
before recreating Kind. The `--native-runtime` mode additionally delegates the
full tool/user/home/repository proof to the workspace-owned native verifier and
requires the exact live Kind target.

Before an agent-authorized Kubernetes mutation, require all of the following:

1. `kubectl config current-context` is exactly `kind-kind`.
2. The referenced kubeconfig cluster is exactly `kind-kind`.
3. Its API server is HTTPS on `127.0.0.1`, `localhost` or IPv6 loopback.
4. `kubectl get node kind-control-plane` reports the node Ready.

`kind get clusters` must additionally contain the expected `kind` cluster.
This is useful native daemon evidence, but a cluster name, VM marker or process
name alone is not personal-host isolation proof.

For local API-test acceptance, require the selected configuration to declare
`environment_type: local` and target exactly
`https://app.budgetanalyzer.localhost`. A configuration name such as `local`
is insufficient.

## Clean Bootstrap And Daily Startup

The VM starts from committed Git objects and explicitly transferred TLS files.
Do not copy, export, import or reconstruct host Docker images, containers,
volumes, Kind clusters, databases, application data or build caches.

The explicit first-bootstrap command is:

```bash
./setup.sh --guest-local
```

It is a destructive local bootstrap: like the standard setup path, it deletes
and recreates the `kind` cluster, installs Calico and Gateway API prerequisites,
installs the imported ingress certificate, generates guest-owned
infrastructure TLS and prepares `.env`. It is not a VM-start or daily-start
command. Daily work starts the VM, verifies the native runtime, starts Tilt and
uses the host loopback HTTPS forward without rerunning `setup.sh`.

Agents and AI Session Handler are ordinary processes of the same guest user
that runs Tilt. Start them from a fresh guest login shell after the native
runtime preflight. Exiting an agent or handler must not stop Tilt, Docker, Kind
or the application; a later fresh shell reuses the normal user's provider
state, Maven Local and Gradle caches. No agent container, separate home or
Compose lifecycle belongs in this daily path. Exact daily commands live in
[Getting Started](../development/getting-started.md#daily-native-startup), and
the remaining human process/reboot proof lives in the
[native manual plan](../plans/agent-vm-native-manual-plan.md#checkpoint-c-accept-native-daily-operation).

The standard `./setup.sh` path remains the supported transitional/local-host
bootstrap. Do not silently select guest behavior from hostname, a marker file
or environment. The `--guest-local` option is an explicit accidental-mislaunch
guard, and the local-Docker checks provide the endpoint evidence.

## Browser TLS Contract

The personal host owns browser trust and the mkcert signing key. The guest may
receive only these ignored files:

```text
nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem
nginx/certs/k8s/_wildcard.budgetanalyzer.localhost-key.pem
nginx/certs/k8s/_mkcert-rootCA.pem
```

The public root can contain workstation-identifying subject metadata and a
stable fingerprint. Keep it out of Git, logs and uploaded artifacts. The
mkcert `rootCA-key.pem` must never enter the workspace or guest.

`scripts/bootstrap/install-imported-ingress-tls.sh` does not generate
certificates. It validates that the three files exist, the public root is a
valid CA, the leaf and CA are currently valid, the leaf covers
`app.budgetanalyzer.localhost`, the chain verifies, and the leaf matches the
private key. In install mode it also enforces the local `kind-kind` target,
optionally installs the public root into the guest OS trust store, and applies
the ingress TLS Secret.

The human copies the three files over the dedicated host-to-guest SSH path and
runs the trust installer in the guest. Native `ensure-budget-analyzer-local-ca-trust`
and `check-budget-analyzer-local-ca-trust` are read-only verification commands;
they never modify trust. Infrastructure certificates are separate, disposable
guest material generated by the human-owned guest bootstrap; they are not
copied from the personal host.

If the leaf is missing, expired, mismatched or otherwise invalid, stop. Do not
use HTTP, `--insecure`, `verify=False`, `ignore_https_errors`, a guest-generated
browser CA or an agent-generated replacement. Renew on the personal host with
`scripts/bootstrap/renew-host-ingress-tls.sh`, recopy the three approved files,
and rerun the guest installer. Renewal does not run `setup.sh` and does not
require or recreate a host Kind cluster.

## Historical Runners And Remaining Cutover

The native manual plan owns source transfer, human firewall evidence, browser
and reboot acceptance, and final Mint Docker retirement. Native agents, Tilt
and service builds now share one guest user/home, so there is no duplicate
agent-container Maven Local or provider volume to populate. Do not add GitHub
package credentials, mount a personal-host cache, or recreate the removed
guest Compose path to bridge a failure.

The sibling workspace's Mint devcontainer files remain for its supported
transitional purpose until Checkpoint D. They do not define the development-VM
runtime and must not be copied into the guest. The retained orchestration
`tests/setup-flow` and `tests/security-preflight` DinD suites are stale,
non-gating reference assets and are not native completion proof.

## Autonomous Execution Workflow

Use autonomy only after the boundary and success criteria are reviewed:

1. Define the task and explicit success criteria.
2. Confirm the native guest user/home, selected workspace, Docker endpoint,
   kubeconfig and credential boundary with the repo-owned preflight.
3. Let the agent execute within that boundary.
4. Verify the result with repo-owned checks and human review before publication.

Permission bypass flags do not create safety. The VM, mounts, credentials,
network policy and target checks create the operating boundary. If a required
prerequisite is absent, stop instead of weakening a control or hiding a
service-owned defect with orchestration.

## Operator References

- Guest VM preparation, firewall rules and checkpoints:
  [native manual plan](../plans/agent-vm-native-manual-plan.md)
- Redacted migration evidence:
  [`../plans/agent-host-isolation-acceptance.md`](../plans/agent-host-isolation-acceptance.md)
- Supported setup and guest bootstrap commands:
  [`../development/getting-started.md`](../development/getting-started.md)
- Local mechanics, TLS ownership and live update:
  [`../development/local-environment.md`](../development/local-environment.md)
- Script catalog and verifier entry points:
  [`../../scripts/README.md`](../../scripts/README.md)
- Workspace-owned native tool manifest, provisioning, user environment and
  trust verifier: the sibling `../workspace` repository documentation
