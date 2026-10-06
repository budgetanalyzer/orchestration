# Getting Started

**Tested with:** VS Code, Claude Code (extension or terminal), Codex, and Gemini.

The sibling `workspace` repository owns developer tooling. The accepted daily
agent workflow uses native tools in the VM through Remote SSH. The following
personal-host devcontainer onboarding is a separate local-host workflow; do
not use it as the development-VM agent environment:

```bash
git clone https://github.com/budgetanalyzer/workspace.git
```

Open the workspace in VS Code and choose **Reopen in Container**. After the
devcontainer starts, open the `orchestration` repository in its own VS Code
window so the repo-local `AGENTS.md` instructions load for that session.

The isolated development-VM target uses native agents and VS Code Remote SSH.
The personal-host container instructions above do not apply to that target;
use the native daily path below. Working clones, the normal guest home, Docker,
Kind and runtime state stay guest-local. The old guest agent container is
retired and must not be reconstructed. Read the boundary contract in
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
  workspace-devcontainer trust installation, sets up local DNS, and prepares
  `.env`.
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

## Development VM Native Workflow

The workspace-owned installer establishes the normal guest user's native tool
environment before application bootstrap. Follow the exact human installation,
provider authentication and trust procedure in the
[native user-tools guide](../../../workspace/docs/native-user-tools.md). Do not
install tools ad hoc from orchestration or create a second agent-specific home.

### Development VM First Bootstrap

Use this path only for first bootstrap or an explicitly reviewed clean rebuild,
after guest provisioning, repository setup, native trust/provider verification
and approved TLS transfer. End affected workers before a clean rebuild. Do not
run this path simply to restart agents. Run bootstrap from a human-operated
guest OS shell:

```bash
./scripts/bootstrap/check-agent-vm-prerequisites.sh
./scripts/bootstrap/install-imported-ingress-tls.sh --validate-only
. "$HOME/.config/budget-analyzer-native/env.sh"
../workspace/scripts/install-agent-vm-local-ca-trust.sh \
  --worktree-parent "$BUDGET_ANALYZER_WORKTREE_PARENT" \
  --bare-parent "$BUDGET_ANALYZER_BARE_PARENT"
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
or Kubernetes. The reviewed workspace command is the only guest OS/NSS trust
writer and fails closed when its native identity, repository or trust
prerequisites are not satisfied. `./setup.sh --guest-local` repeats the Docker
check, recreates a fresh guest `kind` cluster, and applies the ingress TLS
Secret only after the strict loopback `kind-kind` checks pass; it does not
change guest trust.

`./setup.sh` in either mode recreates Kind. It is a first-bootstrap or explicit
clean-rebuild command, never a daily VM-start command. Use the daily native
startup below for ordinary guest work.

The `ingress-tls-secret` Tilt resource validates the already transferred files
and reconciles the local Kind Secret on startup. It does not run mkcert or alter
guest trust. Missing, expired, or replaced files return to the host renewal,
three-file transfer, workspace trust and orchestration Secret-reconciliation
workflow; they are not repaired by `tilt up`.

Do not import personal-host Docker state or run the standard host certificate
generator in the guest. Imported TLS ownership and renewal remain in the
local-environment guide.

### Daily Native Startup

Open a fresh guest shell as the normal development user. The managed shell
environment should already be loaded; the native runtime preflight verifies
that user/home, every local working/bare repository pair, pinned user tools,
the credential boundary, guest Docker and the exact loopback Kind target still
agree:

```bash
./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime
tilt up
```

Run `./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local` when
diagnosing tool, repository, cluster or runtime-security drift. It also fails
closed on the exact guest-local Docker and Kubernetes targets before its
runtime security proof creates and cleans named disposable probe resources.
The native runtime preflight is read-only; neither command installs packages,
changes trust or recreates the cluster. Do not run `setup.sh` during daily
startup.

Launch agents and AI Session Handler from that same fresh guest shell, never
through Docker Compose or a separate agent home. Plain provider commands keep
their upstream defaults; use the reviewed wrapper when a plan calls for it:

```bash
codex
# Or, from a repository that owns PLAN_NAME:
ai-run PLAN_NAME
```

Exit the agent independently when its work is complete. Tilt, guest Docker,
Kind and the application remain running, and the next fresh login shell reuses
the normal user's provider state, Maven Local and Gradle caches. Run
`check-budget-analyzer-local-ca-trust` when diagnosing native HTTPS trust; it is
read-only. After provisioning or a reboot, verify fresh-shell PATH resolution,
agent exit/reentry, live saves and runtime persistence before relying on the
environment.

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
