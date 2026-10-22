# Getting Started

Orchestration owns a self-contained local application path. It does not require
the sibling `workspace` repository or any workspace verifier. The optional
workspace development VM is documented separately below.

Full local Tilt expects the Budget Analyzer repositories, including
`../ext-authz`, to be cloned side by side under one parent directory. Install
the repository build prerequisites reported by
`./scripts/bootstrap/check-tilt-prerequisites.sh`, and edit `.env` before
`tilt up`; Auth0 values and `FRED_API_KEY` are required for local startup.

Read the [application authority contract](../architecture/autonomous-ai-execution.md)
before changing the local-target or credential controls.

## First Bootstrap

Use this path for first setup or an explicitly reviewed clean rebuild:

1. Install Docker on the machine that will run Kind. Configure the Docker CLI
   to use a reachable local Unix-socket daemon; remote TCP and SSH contexts are
   rejected. Kind must use its Docker provider: leave
   `KIND_EXPERIMENTAL_PROVIDER` unset or set it to `docker`.
2. On the machine whose browser will open the application, install `mkcert` and
   OpenSSL, open its orchestration checkout, and have a human prepare or renew
   the browser certificate and the three published files:

   ```bash
   ./scripts/bootstrap/renew-host-ingress-tls.sh
   ```

   This command establishes trust for that machine's browser and never contacts
   Kubernetes. If Kind runs on another machine, place exactly these three files
   in that machine's orchestration checkout under `nginx/certs/k8s/`:

   ```text
   _wildcard.budgetanalyzer.localhost.pem
   _wildcard.budgetanalyzer.localhost-key.pem
   _mkcert-rootCA.pem
   ```

   Never transfer the mkcert CA private key. The
   [ingress TLS contract](local-environment.md#host-published-local-ingress-ca)
   owns validation, renewal and handoff details.
3. On the Kind machine, run the human-operated bootstrap:

   ```bash
   ./setup.sh
   ```

   Setup validates the supplied TLS files, installs orchestration's exact
   pinned kubectl, Helm, Tilt and Kind versions through the verified installer,
   recreates the local Kind cluster, and reconciles the ingress Secret. It is a
   destructive local rebuild, not a daily-start command.
4. Install the frontend's local npm dependencies, complete `.env`, and start
   the platform:

   ```bash
   cd ../budget-analyzer-web
   npm install
   cd ../orchestration
   tilt up
   ```

Run `./scripts/bootstrap/check-tilt-prerequisites.sh` for the broader tooling,
repository, certificate, cluster and runtime-security report before or after
bootstrap. Its live security checks can create and clean named disposable
resources in the approved local cluster.

Valid TLS files are not the same as client trust.
`check-tilt-prerequisites.sh` reports whether the Kind machine's system trust
bundle, with no other trust source, verifies the supplied current ingress leaf
for `app.budgetanalyzer.localhost`. That Kind-machine diagnostic does not gate
`./setup.sh`. It does not prove browser-machine trust, which certificate a
running ingress serves, or whether Chromium's NSS database trusts it.
Browser-machine trust from step 2 remains required before using the
application in a browser. Follow the environment-specific trust documentation
and complete its exact-URL browser acceptance check. The
[ingress TLS contract](local-environment.md#host-published-local-ingress-ca)
distinguishes these checks. For the workspace development VM, use the
[local TLS owner document](../../../workspace/docs/local-budget-analyzer-tls.md)
and [exact ingress trust procedure](../../../workspace/docs/native-user-tools.md#establish-exact-ingress-trust).

The `ingress-tls-secret` Tilt resource revalidates the supplied files and
reconciles the local Kind Secret on startup. It never runs mkcert or changes a
client trust store. Missing, expired or replaced files must return to the
human-operated renewal, three-file handoff and environment-specific trust flow;
`tilt up` does not repair them.

## Daily Startup

With the bootstrap complete, daily startup is read-only preflight followed by
Tilt:

```bash
./scripts/bootstrap/check-local-runtime.sh
tilt up
```

The local-runtime check requires Kind's Docker provider, a reachable local
Docker Unix socket and the exact Ready loopback `kind-kind` Kubernetes target. It does not install tools,
change trust or recreate the cluster. Do not run `setup.sh` for daily startup.

## Running In The Workspace Development VM

Workspace owns VM provisioning,
repository transport, the three-file transfer, guest OS/NSS and Chromium trust,
the personal-host tunnel, and agent launch. Follow its
[development-VM guide](../../../workspace/docs/host-isolation.md),
[TLS handoff guide](../../../workspace/docs/local-budget-analyzer-tls.md), and
[agent-tooling guide](../../../workspace/docs/native-user-tools.md), then use
the same orchestration `./setup.sh` and daily-start commands above. Workspace
commands are environment preparation, not orchestration prerequisites.

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

Orchestration starts the application and Tilt on the Kind machine and owns
their publication on that machine's loopback (VM loopback in the workspace
development VM):

- Application: `https://app.budgetanalyzer.localhost`
- Tilt UI: `http://localhost:10350`
- Unified API docs surface: `https://app.budgetanalyzer.localhost/api-docs`

In the workspace development VM, these VM-loopback entry points are not
automatically available on the personal host. After `tilt up` is healthy, use workspace's
[default combined host tunnel](../../../workspace/docs/host-isolation.md#default-application-and-tilt-host-tunnel)
to carry application HTTPS and the Tilt UI from VM loopback to personal-host
loopback in one foreground process.

Observability is optional and is not part of that default host tunnel. When it
is needed, first run the orchestration
[foreground guest publication helper](../architecture/observability.md#access)
in a separate VM shell. While it remains running, start workspace's
[optional observability host tunnel](../../../workspace/docs/host-isolation.md#optional-observability-host-tunnel)
in a separate personal-host shell. Stopping either foreground process removes
its corresponding layer of access.

Exact `/api-docs` behavior lives in
[docs-aggregator/README.md](../../docs-aggregator/README.md). Exact
observability resources, ports, URLs, health checks, authentication and guest
publication lifecycle live in
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
