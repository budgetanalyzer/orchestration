# Getting Started

The application workflow is editor-independent. It is tested from native guest
shells, including VS Code Remote SSH terminals, with Claude Code, Codex, and
Gemini. Other clients must preserve the workspace-owned host-isolation and
credential boundary.

The native development VM is the only supported agent environment. The sibling
`workspace` repository owns VM provisioning, repositories, the normal guest
user and home, native tools, guest Docker, Remote SSH, trust installation and
the host-isolation audit. Complete its human-operated
[development VM setup](../../../workspace/docs/host-isolation.md) and
[native user/tool preparation](../../../workspace/docs/native-user-tools.md)
before application bootstrap. Former guest-specific and personal-host agent
runtimes are retired and must not be reconstructed.

Orchestration owns the application bootstrap, exact local Kind target, Tilt,
imported ingress-file validation and Kubernetes Secret reconciliation. Read the
[application authority contract](../architecture/autonomous-ai-execution.md)
before changing those controls.

Full local Tilt expects the Budget Analyzer repositories to be cloned
side-by-side by the workspace-owned repository workflow. That includes
`../ext-authz`, which owns the Go external authorization service source that
Tilt builds into the local `ext-authz` image.

## Native VM Application Workflow

Do not install native tools ad hoc from orchestration or create a second
agent-specific home. Edit `.env` before `tilt up`; Auth0 values and
`FRED_API_KEY` are required for local startup.

### Development VM First Bootstrap

Use this path only for first bootstrap or an explicitly reviewed clean rebuild,
after guest provisioning, repository setup, native trust/provider verification
and approved TLS transfer. End affected workers before a clean rebuild. Do not
run this path simply to restart agents. Run bootstrap from a human-operated
guest OS shell:

```bash
./scripts/bootstrap/install-imported-ingress-tls.sh --validate-only
. "$HOME/.config/budget-analyzer-native/env.sh"
../workspace/scripts/install-agent-vm-local-ca-trust.sh \
  --worktree-parent "$BUDGET_ANALYZER_WORKTREE_PARENT" \
  --bare-parent "$BUDGET_ANALYZER_BARE_PARENT"
./scripts/bootstrap/check-agent-vm-prerequisites.sh
./setup.sh --guest-local
cd ../budget-analyzer-web
npm install
cd ../orchestration
./scripts/bootstrap/check-tilt-prerequisites.sh --guest-local
tilt up
```

The orchestration guest preflight invokes workspace's complete read-only native
runtime verifier, including VM/user identity, repository topology, forwarded
authority, guest Docker, manifest-owned tools and established trust. The
imported-TLS validation checks the public CA, validity period, hostname, chain
and leaf/key match without changing trust or Kubernetes. The reviewed workspace
command is the only guest OS/NSS trust writer. `./setup.sh --guest-local`
repeats the full workspace verifier before any Kind deletion, recreates a fresh
guest `kind` cluster, and applies the ingress TLS Secret only after the strict
loopback `kind-kind` checks pass; it does not change guest trust.

`./setup.sh --guest-local` recreates Kind. It is a first-bootstrap or explicit
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
closed through workspace's complete native verifier and orchestration's exact
Kubernetes target before its runtime security proof creates and cleans named
disposable probe resources.
The native runtime preflight is read-only; neither command installs packages,
changes trust or recreates the cluster. Do not run `setup.sh` during daily
startup.

Launch agents and AI Session Handler from that same fresh guest shell. Do not
recreate a retired runtime or use a separate agent home. Plain provider
commands keep their upstream defaults; use the reviewed wrapper when a plan
calls for it:

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
