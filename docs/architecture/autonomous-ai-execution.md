# Autonomous AI Execution Pattern

## Overview

Budget Analyzer gives coding agents broad authority inside a disposable local
development boundary. That authority is useful for builds, tests, Docker,
Kubernetes and local API diagnostics, but it is not authority over the personal
workstation, GitHub publication, staging or production.

Two development arrangements exist during the host-isolation migration:

- The **transitional Mint workspace devcontainer** is the existing
  implementation runner. It mounts the host's sibling-repository workspace and
  kubeconfig and uses the Mint Docker environment. Keep it available through
  implementation Phases 1–6 and Checkpoint B.
- The **guest agent container** is the target runtime defined separately by the
  sibling workspace repository's `ai-agent-sandbox/docker-compose.agent-vm.yml`.
  It runs on the development VM's Docker daemon against guest-local files and
  guest-local Kind. It is not a Mint profile, a VM definition, or a replacement
  compose file for the existing devcontainer.

The transition ends only after the human completes the explicit Docker
retirement checkpoint in
[`../plans/agent-host-isolation-manual-plan.md`](../plans/agent-host-isolation-manual-plan.md).

## Boundary Terminology

- **Personal host**: the Linux Mint workstation. It owns GitHub credentials,
  canonical GitHub remotes, the native VS Code and browser UIs, the mkcert
  signing key, libvirt and the host-enforced VM firewall boundary.
- **Development VM**: the Ubuntu guest. It owns working clones, local bare Git
  repositories, Docker storage, dependency caches, Kind, Tilt, Kubernetes
  state, development credentials and application data.
- **Agent container**: a container created by the development VM's Docker
  daemon. It can administer that daemon and therefore must be assumed able to
  read, alter or destroy all guest repositories, local credentials, Kind state
  and other guest runtime data.

A marker, compose-project name, environment variable or command-line flag can
prevent an accidental launch in the wrong place. It does not prove isolation.
Isolation comes from the VM boundary, guest-local storage and Docker endpoint,
the absence of host mounts and credentials, and host-enforced network policy.

## Target Guest-Local Architecture

```text
Personal host
  GitHub credentials + canonical clones
  native VS Code UI -- Remote SSH ----------> development VM working clones
  browser -- loopback-only SSH forward ------> development VM ingress
  git push/fetch over host-initiated SSH ----> development VM bare repositories
  mkcert signing key (never copied)

Development VM
  /srv/budget-analyzer/bare/<repo>.git
  /srv/budget-analyzer/worktrees/<repo>
  /var/lib/docker (one guest-local Docker daemon)
    Kind + Testcontainers + guest agent container
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

The guest uses Docker-outside-of-Docker: the agent container mounts the
**guest's** `/var/run/docker.sock`. It does not run a nested daemon and does not
need privileged mode. Guest host networking is allowed so local Kind, Tilt and
application endpoints retain their normal loopback behavior.

Before guest bootstrap, `scripts/bootstrap/check-agent-vm-prerequisites.sh`
fails closed unless Docker uses the default local Unix socket, no remote-Docker
environment is selected, the service is active on the current machine, and the
daemon reports its normal guest-local data root. `./setup.sh --guest-local`
repeats that check before recreating Kind. Do not use `DOCKER_HOST`, an SSH/TCP
Docker context, a nested daemon, or a host socket forwarded into the VM.

Before an agent-authorized Kubernetes mutation, require all of the following:

1. `kubectl config current-context` is exactly `kind-kind`.
2. The referenced kubeconfig cluster is exactly `kind-kind`.
3. Its API server is HTTPS on `127.0.0.1`, `localhost` or IPv6 loopback.
4. `kubectl get node kind-control-plane` succeeds.

On the VM host, `kind get clusters` must additionally contain the expected
`kind` cluster before bootstrap-owned secret installation. It is only an
additional host-side check; an agent container can reach the same guest daemon
but a container marker or cluster name alone is not boundary proof.

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
command. Daily work starts the VM, the reviewed guest agent container, Tilt and
the host loopback HTTPS forward without rerunning `setup.sh`.

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
mkcert `rootCA-key.pem` must never enter the workspace, guest or agent
container.

`scripts/bootstrap/install-imported-ingress-tls.sh` does not generate
certificates. It validates that the three files exist, the public root is a
valid CA, the leaf and CA are currently valid, the leaf covers
`app.budgetanalyzer.localhost`, the chain verifies, and the leaf matches the
private key. In install mode it also enforces the local `kind-kind` target,
optionally installs the public root into the guest OS trust store, and applies
the ingress TLS Secret.

The human copies the three files over the dedicated host-to-guest SSH path and
runs the installer in the guest. The agent-container's
`ensure-budget-analyzer-local-ca-trust` command remains the lazy container-local
trust path. Infrastructure certificates are separate, disposable guest
material generated by the human-owned guest bootstrap; they are not copied
from the personal host.

If the leaf is missing, expired, mismatched or otherwise invalid, stop. Do not
use HTTP, `--insecure`, `verify=False`, `ignore_https_errors`, a guest-generated
browser CA or an agent-generated replacement. Renew on the personal host with
`scripts/bootstrap/renew-host-ingress-tls.sh`, recopy the three approved files,
and rerun the guest installer. Renewal does not run `setup.sh` and does not
require or recreate a host Kind cluster.

## Transitional Mint Runner

The sibling workspace `.devcontainer/devcontainer.json` and
`ai-agent-sandbox/docker-compose.yml` remain the implementation runner until
Checkpoint B. They currently mount the shared sibling-repository parent and
host kubeconfig and use host networking; their Docker-in-Docker devcontainer
feature belongs to that transitional environment. Do not copy this
configuration to the VM, reinterpret it as the guest target or claim that it
isolates mounted host files from the agent.

The separate guest compose configuration is owned by the sibling workspace
repository. It must mount only guest-local working/bare repositories, the
guest Docker socket and, after Kind exists, the guest kubeconfig. It must not
mount a personal host path, host credential socket, host kubeconfig, libvirt
socket or nested Docker data directory.

The retained `tests/setup-flow` and `tests/security-preflight` DinD suites are
stale, non-gating reference assets. They are not the guest runtime and are not
completion proof for this migration.

## Autonomous Execution Workflow

Use autonomy only after the boundary and success criteria are reviewed:

1. Define the task and explicit success criteria.
2. Confirm the selected workspace, Docker endpoint, kubeconfig and credential
   boundary.
3. Let the agent execute within that boundary.
4. Verify the result with repo-owned checks and human review before publication.

Permission bypass flags do not create safety. The VM, mounts, credentials,
network policy and target checks create the operating boundary. If a required
prerequisite is absent, stop instead of weakening a control or hiding a
service-owned defect with orchestration.

## Operator References

- Guest VM preparation, firewall rules and checkpoints:
  [`../plans/agent-host-isolation-manual-plan.md`](../plans/agent-host-isolation-manual-plan.md)
- Redacted migration evidence:
  [`../plans/agent-host-isolation-acceptance.md`](../plans/agent-host-isolation-acceptance.md)
- Supported setup and guest bootstrap commands:
  [`../development/getting-started.md`](../development/getting-started.md)
- Local mechanics, TLS ownership and live update:
  [`../development/local-environment.md`](../development/local-environment.md)
- Script catalog and verifier entry points:
  [`../../scripts/README.md`](../../scripts/README.md)
- Workspace-owned guest agent configuration and trust helper:
  the sibling `../workspace` repository documentation
