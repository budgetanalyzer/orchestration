# Getting Started

**Tested with:** VS Code, Claude Code (extension or terminal), Codex, and Gemini.

The supported transitional containerized developer workspace lives in the
sibling `workspace` repository:

```bash
git clone https://github.com/budgetanalyzer/workspace.git
```

Open the workspace in VS Code and choose **Reopen in Container**. After the
devcontainer starts, open the `orchestration` repository in its own VS Code
window so the repo-local `AGENTS.md` instructions load for that session.

The selected isolated target uses native agents and VS Code Remote SSH in a
development VM. Native provisioning is planned in the
[execution plan](../plans/agent-vm-native-execution-plan.md), with a separate
[human installation/cutover checklist](../plans/agent-vm-native-manual-plan.md).
The current guest agent container is a temporary preparation runner. Working
clones, Docker, Kind and runtime state stay guest-local. Read
the boundary contract in
[`../architecture/autonomous-ai-execution.md`](../architecture/autonomous-ai-execution.md)
before changing either configuration.

Full local Tilt expects the Budget Analyzer repositories to be cloned
side-by-side. That includes `../ext-authz`, which owns the Go external
authorization service source that Tilt builds into the local `ext-authz` image.

## Supported Local Happy Path

Run the platform bootstrap from your host terminal, not from inside the
devcontainer:

```bash
cd path/to/workspace/orchestration
./setup.sh
vim .env
tilt up
```

This is the supported local startup path for the repository:

- `./setup.sh` converges repo-managed pinned prerequisites such as `kubectl`,
  Kind, Tilt, `mkcert`, Calico, and Gateway API CRDs, installs a supported
  Helm 3 binary when needed, recreates the local `kind` cluster, configures
  browser and internal TLS, publishes the public local ingress CA for lazy
  agent-container trust installation, sets up local DNS, and prepares `.env`.
- Edit `.env` before `tilt up`. Auth0 values and `FRED_API_KEY` are required
  for local startup.
- `tilt up` is the supported entry point for the full local stack.
- [`local-environment.md`](local-environment.md) explains how the local
  environment works once that stack is up, including Tilt live update, mixed
  local-and-cluster workflows, and troubleshooting.
- [`scripts/README.md`](../../scripts/README.md) owns the full verifier catalog
  and targeted capability checks.

Open `https://app.budgetanalyzer.localhost` after the app workloads are green
in Tilt.

Agents that need verified HTTPS access to that exact origin may run
`ensure-budget-analyzer-local-ca-trust` inside a rebuilt workspace container.
If it reports that the host publication is missing, run `./setup.sh` from the
host; do not generate or rotate certificates in the container. The publication
contract and diagnostics live in
[`local-environment.md`](local-environment.md#host-published-local-ingress-ca).

## Development VM First Bootstrap

Use this path only for first bootstrap or an explicitly reviewed clean rebuild,
after guest provisioning, repository setup and approved TLS transfer. The
[native migration](../plans/agent-vm-native-manual-plan.md) invokes this path
once during its explicitly destructive B.3 cutover, after native trust/provider
proof and all old workers have ended. Outside first bootstrap or that reviewed
cutover, do not run it simply to restart agents. Run bootstrap from a
human-operated guest OS shell:

```bash
./scripts/bootstrap/check-agent-vm-prerequisites.sh
./scripts/bootstrap/install-imported-ingress-tls.sh --validate-only
./setup.sh --guest-local
cd ../budget-analyzer-web
npm install
cd ../orchestration
./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local
tilt up
```

The guest preflight rejects a remote Docker environment or context and requires
the guest's default `/var/run/docker.sock`, normal `/var/lib/docker` data root,
JDK 25, Node.js 20+ and npm 10+. The imported-TLS validation checks the public
CA, validity period, hostname, chain and leaf/key match without changing trust
or Kubernetes. `./setup.sh --guest-local` repeats the Docker check, recreates a
fresh guest `kind` cluster, installs the public root in the guest trust store,
and applies the ingress TLS Secret only after the strict loopback `kind-kind`
checks pass.

`./setup.sh` in either mode recreates Kind. It is a first-bootstrap or explicit
clean-rebuild command, never a daily VM-start command. Daily guest startup is:

```bash
tilt up
```

The `ingress-tls-secret` Tilt resource validates the already transferred files
and reconciles the local Kind Secret on startup. It does not run mkcert or alter
guest trust. Missing, expired, or replaced files return to the host renewal and
guest import workflow; they are not repaired by `tilt up`.

Follow the [native manual plan](../plans/agent-vm-native-manual-plan.md) for the
agent installation gate and daily startup. Until that gate passes, the existing
guest container is used only for preparation. Do not import Mint Docker state
or run the standard host certificate generator in the guest. Imported TLS
ownership and renewal remain in the local-environment guide.

## Validation

After Tilt is healthy, run the aggregate local proof:

```bash
./scripts/smoketest/smoketest.sh
```

Use targeted verifiers only when you are debugging one capability:

```bash
./scripts/smoketest/verify-clean-tilt-deployment-admission.sh
./scripts/smoketest/verify-security-prereqs.sh
./scripts/smoketest/verify-security-guardrails.sh
```

For the full verifier catalog, use
[`scripts/README.md`](../../scripts/README.md).

## `service-common` Contract

This happy path should not require `GITHUB_ACTOR`, `GITHUB_TOKEN`, or a
personal access token just to start the app locally. Tilt publishes
`service-common` to Maven Local before downstream Java builds run.

The canonical explanation of the local-vs-remote artifact contract lives in
[service-common-artifact-resolution.md](service-common-artifact-resolution.md).

## External Services

The app requires both Auth0 and FRED credentials for local startup.

### Auth0

1. Create an account at [auth0.com](https://auth0.com).
2. Create an application of type **Regular Web Application**.
3. Copy the Auth0 domain, client ID, and client secret into `.env`.
4. `AUTH0_ISSUER_URI` must be valid before `tilt up`; the local Auth0 egress
   render derives its hostname from that value.
5. Use [auth0-setup.md](../setup/auth0-setup.md) for the full setup guide.

### FRED API

1. Create a free API key at
   [fred.stlouisfed.org](https://fred.stlouisfed.org/docs/api/api_key.html).
2. Copy the key into `.env`.
3. Use [fred-api-setup.md](../setup/fred-api-setup.md) for the full setup
   guide.

## Operator Entry Points

- Application: `https://app.budgetanalyzer.localhost`
- Tilt UI: `http://localhost:10350`
- Unified API docs surface: `https://app.budgetanalyzer.localhost/api-docs`
- Observability helper:
  `./scripts/ops/start-observability-port-forwards.sh`

Exact `/api-docs` behavior lives in
[docs-aggregator/README.md](../../docs-aggregator/README.md). Exact
observability access commands and operator posture live in
[../architecture/observability.md](../architecture/observability.md).

## Deeper References

- Local environment mechanics:
  [local-environment.md](local-environment.md)
- Manual bootstrap and setup internals:
  [../tilt-kind-setup-guide.md](../tilt-kind-setup-guide.md)
- Script catalog and verifier entry points:
  [../../scripts/README.md](../../scripts/README.md)

## Stopping

```bash
tilt down
```
