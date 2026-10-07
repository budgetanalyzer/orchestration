# Autonomous AI Execution Pattern

## Scope

Orchestration grants agents broad authority over the disposable Budget Analyzer
application environment inside the native development VM. That authority covers
local builds, tests, Tilt, application containers, the approved Kind cluster,
development Kubernetes Secrets and disposable local API-test credentials. It
does not cover the personal host, GitHub publication, staging or production.

The native development VM is the only supported agent environment. Former
guest-specific and personal-host agent runtimes are retired and must not be
reconstructed. The sibling workspace's
[development VM owner document](../../../workspace/docs/host-isolation.md)
owns VM identity, native users and tools, repositories, Git transport, Remote
SSH, guest Docker, exact OS/NSS trust, personal-host isolation and its audit.
Read that document before changing or diagnosing any of those concerns; do not
duplicate its procedures here.

This document owns only the application-facing authority enforced by
orchestration:

- application bootstrap and daily Tilt behavior;
- the exact local Kubernetes mutation target;
- local API-test origin selection;
- imported ingress-file validation and Kubernetes Secret reconciliation;
- local development credential exposure and staging/production exclusions.

## Application Authority

Within the verified native VM boundary, an agent may:

- modify guest working clones and run application builds and tests;
- build and run application images and Testcontainers workloads;
- inspect and mutate the approved local `kind-kind` cluster;
- read local Kubernetes Secrets, imported ingress keys, generated
  infrastructure keys and disposable local API-test credentials.

An agent must never receive or use staging or production kubeconfigs, cloud or
deployment credentials, user credentials, session cookies, GitHub publication
credentials, personal-host credentials, or personal-host administration
authority. Never deploy to or administer staging or production from an agent
session.

Local development secrets are inside the trusted guest boundary and are not
hidden from the agent. Use disposable test identities and local-only
credentials. Human review, branch protection and pull-request controls remain
required before publication.

## Exact Local Kubernetes Target

Before an agent-authorized Kubernetes mutation, require all of the following:

1. `kubectl config current-context` is exactly `kind-kind`.
2. The referenced kubeconfig cluster is exactly `kind-kind`.
3. Its API server is an exact HTTPS authority on `127.0.0.1`, `localhost` or
   `[::1]`, with a valid port and no userinfo, path, query or fragment.
4. The selected kubeconfig cluster has no `proxy-url` override.
5. `kind get clusters` contains the `kind` cluster.
6. `kubectl get node kind-control-plane` reports the node Ready.

These checks reject accidental remote authority. A VM marker, cluster name or
process name alone is insufficient. Configuration-only checks use `kubectl
config view`; they must not invoke credential plugins or contact an API server
merely to inspect the selected authority.

`scripts/lib/local-kubernetes-target.sh` owns the reusable implementation.
`scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime` adds that
check after workspace's complete native-runtime verifier. Bootstrap and
Secret-install paths repeat the applicable guard before mutation.

## Bootstrap And Daily Startup

The explicit first application bootstrap is:

```bash
./setup.sh
```

It is a destructive local rebuild. It verifies workspace-owned native
prerequisites and the imported ingress files before deleting Kind, then creates
the cluster, installs application prerequisites, generates guest-owned
infrastructure TLS and prepares `.env`. It is not a VM-start or daily-start
command.

Daily work starts from a fresh normal-user guest shell:

```bash
./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime
tilt up
```

Agents and AI Session Handler are ordinary guest-user processes and remain
independent of Tilt, Kind and the application lifecycle. Do not recreate a
retired runtime or a separate agent home. The exact first-bootstrap sequence,
including its human trust prerequisite, lives in
[Getting Started](../development/getting-started.md#development-vm-first-bootstrap).

## Local API-Test Gate

Agent-driven live API tests may use automatic local trust verification only
when the resolved configuration declares `environment_type: local` and targets
exactly `https://app.budgetanalyzer.localhost`. A configuration name such as
`local`, a hostname alias, or a loopback address by itself is insufficient.

Do not run local trust helpers for staging, production, arbitrary HTTPS
origins, or public Internet trust failures. Never weaken verification with
HTTP, `--insecure`, `verify=False` or `ignore_https_errors`.

## Ingress TLS Boundary

The personal host owns browser certificate generation and renewal. Workspace
owns human-operated guest OS/NSS trust installation and read-only trust
verification. Orchestration receives only the approved wildcard leaf, leaf key
and public CA; it validates those files and reconciles the local Kubernetes TLS
Secret.

`scripts/bootstrap/install-imported-ingress-tls.sh` never generates
certificates or writes guest trust. In install mode it applies the Secret only
after the exact local Kubernetes checks pass. Tilt uses that same
non-generating path for the `ingress-tls-secret` resource.

If an imported file is missing, expired or mismatched, stop. Do not generate a
replacement in the guest. Follow the host-only renewal and approved
three-file-transfer flow in
[Local Environment Mechanics](../development/local-environment.md#development-vm-import-and-renewal),
then reconcile the Secret without recreating Kind.

## Autonomous Execution Workflow

1. Define the task and explicit success criteria.
2. Run the workspace-owned native prerequisite through orchestration's wrapper.
3. Require the exact local Kubernetes target before any cluster mutation.
4. Confirm live API tests select the exact local origin when applicable.
5. Execute only within the local application authority described above.
6. Verify the result with repo-owned checks and human review before publication.

Permission-bypass flags do not establish the operating boundary. If a required
prerequisite is absent, stop instead of weakening a control or hiding a
service-owned defect with an orchestration workaround.

## Orchestration References

- Supported application bootstrap and daily startup:
  [Getting Started](../development/getting-started.md)
- Ingress publication, imported-file validation, renewal and Secret behavior:
  [Local Environment Mechanics](../development/local-environment.md)
- Script interfaces and focused verifiers:
  [scripts/README.md](../../scripts/README.md)
