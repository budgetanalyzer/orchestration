# Autonomous AI Execution Pattern

## Scope

Orchestration grants agents broad authority over the disposable Budget Analyzer
application environment on the trusted local development machine, which for
agents is the workspace development VM. That authority covers
local builds, tests, Tilt, application containers, the approved Kind cluster,
development Kubernetes Secrets and disposable local API-test credentials. It
does not cover the personal host, GitHub publication, staging or production.

The optional sibling workspace's
[development VM owner document](../../../workspace/docs/host-isolation.md)
owns that agent environment, its boundary check, native tools, trust and
personal-host transport. Read it before changing or diagnosing those concerns;
they are separate from orchestration's application prerequisites.

This document owns only the application-facing authority enforced by
orchestration:

- application bootstrap and daily Tilt behavior;
- the exact local Kubernetes mutation target;
- local API-test origin selection;
- imported ingress-file validation and Kubernetes Secret reconciliation;
- local development credential exposure and staging/production exclusions.

## Application Authority

Within that local application environment, an agent may:

- modify local working clones and run application builds and tests;
- build and run application images and Testcontainers workloads;
- inspect and mutate the approved local `kind-kind` cluster;
- read local Kubernetes Secrets, imported ingress keys, generated
  infrastructure keys and disposable local API-test credentials.

An agent must never receive or use staging or production kubeconfigs, cloud or
deployment credentials, user credentials, session cookies, GitHub publication
credentials, personal-host credentials, or personal-host administration
authority. Never deploy to or administer staging or production from an agent
session.

Local development secrets are inside the trusted local boundary and are not
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
Its Docker endpoint guard first rejects any nonempty `KIND_EXPERIMENTAL_PROVIDER`
other than `docker`, so the transport it checks is the one Kind uses; it then
requires a reachable local Unix-socket daemon. This is a transport check, not
host-isolation proof. `scripts/bootstrap/check-local-runtime.sh` combines that
guard with the exact-target check for daily startup. Setup and the prerequisite
checker call the same guard before any Kind access, and the Secret installer
repeats the exact-target check before mutation.

## Bootstrap And Daily Startup

The explicit first application bootstrap is:

```bash
./setup.sh
```

It is a destructive local rebuild. It requires a reachable local Docker Unix
socket and validates the supplied ingress files before deleting Kind, installs
the pinned platform tools, creates the cluster, installs application
prerequisites, generates local infrastructure TLS and prepares `.env`. It is
not a daily-start command.

Daily application work starts with the read-only local-runtime check:

```bash
./scripts/bootstrap/check-local-runtime.sh
tilt up
```

The exact first-bootstrap sequence, including human browser-machine
certificate preparation, lives in
[Getting Started](../development/getting-started.md#first-bootstrap).

## Local API-Test Gate

Agent-driven live API tests may use automatic local trust verification only
when the resolved configuration declares `environment_type: local` and targets
exactly `https://app.budgetanalyzer.localhost`. A configuration name such as
`local`, a hostname alias, or a loopback address by itself is insufficient.

Do not run local trust helpers for staging, production, arbitrary HTTPS
origins, or public Internet trust failures. Never weaken verification with
HTTP, `--insecure`, `verify=False` or `ignore_https_errors`.

## Ingress TLS Boundary

The browser machine owns browser certificate generation and renewal, and each
client environment owns its trust. Orchestration receives only the approved
wildcard leaf, leaf key and public CA; it validates those files, reports
whether the Kind machine's system bundle alone verifies the leaf, and
reconciles the local Kubernetes TLS Secret. That report is not browser
acceptance and does not gate bootstrap. The optional workspace development VM
owns its OS/NSS and Chromium trust procedure.

`scripts/bootstrap/install-imported-ingress-tls.sh` never generates
certificates or writes client trust. In install mode it applies the Secret only
after the exact local Kubernetes checks pass. Tilt uses that same
non-generating path for the `ingress-tls-secret` resource.

If an imported file is missing, expired or mismatched, stop. Do not generate a
replacement from an agent. Follow the browser-machine renewal and
three-file-transfer flow in
[Local Environment Mechanics](../development/local-environment.md#development-vm-import-and-renewal),
then reconcile the Secret without recreating Kind.

## Autonomous Execution Workflow

1. Define the task and explicit success criteria.
2. Run `scripts/bootstrap/check-local-runtime.sh` before daily local work.
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
