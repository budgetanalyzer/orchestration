# Getting Started

**Tested with:** VS Code, Claude Code (extension or terminal), and an
Anthropic account.

The supported containerized developer workspace lives in the sibling
`workspace` repository:

```bash
git clone https://github.com/budgetanalyzer/workspace.git
```

Open the workspace in VS Code and choose **Reopen in Container**. After the
devcontainer starts, open the `orchestration` repository in its own VS Code
window so the repo-local `AGENTS.md` instructions load for that session.

## Supported Local Happy Path

Run the platform bootstrap from your host terminal, not from inside the
devcontainer:

```bash
cd path/to/workspace/orchestration
./scripts/bootstrap/check-tilt-prerequisites.sh
./setup.sh
vim .env
./scripts/guardrails/verify-phase-7-static-manifests.sh
tilt up
./scripts/smoketest/verify-clean-tilt-deployment-admission.sh
./scripts/smoketest/verify-security-prereqs.sh
./scripts/smoketest/verify-phase-7-security-guardrails.sh
./scripts/smoketest/smoketest.sh
```

This is the supported local startup path for the repository:

- `./setup.sh` recreates the local `kind` cluster, installs the supported
  Helm/Calico/Istio prerequisites, configures browser and internal TLS, sets up
  local DNS, and prepares `.env`.
- `tilt up` is the supported entry point for the full local stack.
- [`scripts/README.md`](../../scripts/README.md) owns the full verifier catalog
  and targeted capability checks.
- [`local-environment.md`](local-environment.md) explains how the local
  environment works once that stack is up, including Tilt live update, mixed
  local-and-cluster workflows, and troubleshooting.

Open `https://app.budgetanalyzer.localhost` after the app workloads are green
in Tilt.

## `service-common` Contract

This happy path should not require `GITHUB_ACTOR`, `GITHUB_TOKEN`, or a
personal access token just to start the app locally. Tilt publishes
`service-common` to Maven Local before downstream Java builds run.

The canonical explanation of the local-vs-remote artifact contract lives in
[service-common-artifact-resolution.md](service-common-artifact-resolution.md).

## External Services

The app needs two external accounts in addition to the local infrastructure
password defaults already present in `.env`.

### Auth0

1. Create an account at [auth0.com](https://auth0.com).
2. Create an application of type **Regular Web Application**.
3. Copy the Auth0 domain, client ID, and client secret into `.env`.
4. Use [auth0-setup.md](../setup/auth0-setup.md) for the full setup guide.

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
