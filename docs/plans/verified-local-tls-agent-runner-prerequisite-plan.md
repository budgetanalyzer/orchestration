# Verified Local TLS For Agent-Container API Test Runs Plan

Make the host-managed local Tilt/Kind HTTPS ingress verifiable from the shared
agent container without weakening TLS behavior. The host will publish only its
public mkcert root CA certificate, the workspace devcontainer will install that
CA into the trust stores used by command-line and browser clients, and the
standalone API test repository will remove configurable TLS bypass behavior and
fail live runs early through a typed prerequisite check.

Status: Proposed blocking prerequisite

This work must complete before resuming Phase 5 of
[`provider-neutral-session-and-api-coverage-completion-plan.md`](../../../budget-analyzer-api-tests/docs/plans/provider-neutral-session-and-api-coverage-completion-plan.md).
It is deliberately outside that plan because certificate publication and agent
container trust are owned by orchestration and workspace, not by the black-box
test harness.

## Repository Ownership And Execution Order

| Phase | Owning repository | Ownership boundary |
| --- | --- | --- |
| 1 | `orchestration` | Host certificate setup and publication of the public mkcert root CA |
| 2 | `workspace` | Agent-container system, Python, curl, and Chromium trust configuration |
| 3 | `budget-analyzer-api-tests` | Mandatory TLS verification and live-test prerequisite diagnostics |
| 4 | `budget-analyzer-api-tests` | Cross-repository acceptance and provider-neutral plan handoff |

Each phase must be implemented from its owning repository after reading that
repository's nearest `AGENTS.md`. Completion of one phase does not authorize an
agent working in that repository to implement a later phase owned elsewhere.
This is a coordination plan, not a single cross-repository AI Session Handler
run: the handler infers its writable workspace from the plan location. Each
owner should execute only its assigned phase from its own repository, using an
owner-local execution plan when automation is desired.

## Resolved Design Decisions

1. Local Tilt/Kind is a production-parity deployment path. Live tests must use
   HTTPS and verify the ingress certificate.
2. The agent container consumes the same host-generated mkcert trust anchor as
   the host workstation. It must not generate or rotate browser-facing
   certificates.
3. The only new material copied from the host mkcert CA directory by this plan
   is `rootCA.pem`, the public CA certificate. `rootCA-key.pem` remains on the
   host and must never be copied, mounted, logged, or committed. Existing local
   development key and Secret visibility is governed by decision 8 rather than
   presented as a confidentiality boundary.
4. Orchestration publishes the public root CA at a deterministic ignored path
   under its existing local certificate directory. The workspace is already
   mounted into the agent container, so no host-home bind mount is required.
5. The workspace container installs the public CA into the operating-system
   trust bundle and the Chromium/NSS trust database. Python HTTPS clients use
   the resulting system bundle.
6. The API test repository has no `verify_tls` environment setting, insecure
   pytest option, environment-variable bypass, or target-specific exception.
7. Offline collection, harness unit tests, and snapshot coverage remain
   independent of a live target. Automatic live prerequisite checks run only
   when selected tests or tools will access a deployed environment.
8. The agent container is inside the trusted local-development boundary. It
   already has access to the shared workspace, local Kind kubeconfig and
   Kubernetes Secrets, generated development TLS private keys, and any local
   API-test credentials deliberately supplied to a run. This plan does not
   claim those local materials are confidential from the agent.
9. That trust boundary is local-only. No staging or production kubeconfig,
   cloud or deployment credential, user credential, or session cookie may be
   supplied to the agent container, and an agent session must never deploy or
   administer staging or production.
10. `rootCA.pem` is public trust material, not a credential. It can contain
    locally identifying subject metadata and a stable fingerprint, so it stays
    ignored by Git and out of uploaded artifacts and logs. The corresponding
    `rootCA-key.pem` remains prohibited.
11. Agent-run acceptance for this plan must fail closed unless the API-test
    configuration declares `environment_type: local` and targets exactly
    `https://app.budgetanalyzer.localhost`. Any plan-authorized cluster mutation
    must additionally verify the local Kind identity using checks appropriate
    to its execution side: host commands verify `kind-kind` plus the host Kind
    cluster named `kind`; in-container commands verify the context, referenced
    cluster, loopback API endpoint, and `kind-control-plane` node through
    `kubectl`.

## Phase 1: Orchestration Publishes The Host mkcert Root

### Goal

Extend the supported host TLS setup so the shared workspace contains a current,
public copy of the mkcert root CA that signed the local ingress certificate.

### Scope

- Update `scripts/bootstrap/setup-k8s-tls.sh`, which must continue to run only
  on the host workstation.
- Before reading, deleting, or creating Kubernetes resources, fail closed
  unless `kubectl config current-context` is exactly `kind-kind` and `kind get
  clusters` contains the expected `kind` cluster. A reachable Kubernetes API
  alone is not sufficient proof of the local target.
- After resolving `mkcert -CAROOT` and confirming `rootCA.pem` exists, publish
  it to a deterministic path such as:

  ```text
  nginx/certs/k8s/_mkcert-rootCA.pem
  ```

- Copy atomically with public-certificate permissions and make repeated setup
  runs idempotent.
- Validate that the source is a parseable CA certificate and that its subject
  matches the issuer of the generated wildcard ingress certificate.
- Never copy `rootCA-key.pem`; reject any implementation that handles the CA
  private key.
- Extend the host prerequisite/status output to name the published public CA
  path and give a clear remediation when it is absent or stale.
- Keep the published PEM ignored by Git and document that it is public local
  trust material generated by host setup. Do not print its subject or issuer in
  routine status output because mkcert commonly embeds local user or device
  metadata.
- Update the closest orchestration setup documentation and script catalog.

### Non-goals

- Do not run mkcert or certificate-generation scripts from the agent
  container.
- Do not change the Kubernetes TLS Secret format or put the mkcert root into
  the cluster Secret.
- Do not publish the CA private key or any application/session secret.
- Do not weaken browser, curl, Python, ingress, or Kubernetes TLS settings.
- Do not add manual live-cluster drift as a durable solution.

### Required context

- `AGENTS.md`, especially the host-only certificate constraints
- `scripts/bootstrap/setup-k8s-tls.sh`
- `scripts/bootstrap/check-tilt-prerequisites.sh`
- `scripts/README.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `.gitignore`
- the sibling workspace trust-consumer contract described by Phase 2

### Implementation notes

- Prefer `install` to a temporary file followed by an atomic rename so a
  container never reads a partially written PEM.
- Compare certificate fingerprints or file content before replacing the
  published copy so unchanged setup runs remain quiet and stable.
- Validate CA basic constraints where the available OpenSSL version supports a
  portable check.
- Keep the existing `assert_host_execution` guard before all mkcert and
  certificate publication work.
- The published filename must not resemble or include a private-key filename.

### Validation

Agent-safe static validation:

```bash
bash -n scripts/bootstrap/setup-k8s-tls.sh
shellcheck scripts/bootstrap/setup-k8s-tls.sh
bash -n scripts/bootstrap/check-tilt-prerequisites.sh
shellcheck scripts/bootstrap/check-tilt-prerequisites.sh
git check-ignore nginx/certs/k8s/_mkcert-rootCA.pem
```

Required host acceptance, performed outside the agent container:

```bash
./scripts/bootstrap/setup-k8s-tls.sh
test -r nginx/certs/k8s/_mkcert-rootCA.pem
openssl x509 -in nginx/certs/k8s/_mkcert-rootCA.pem -noout
cmp "$(mkcert -CAROOT)/rootCA.pem" nginx/certs/k8s/_mkcert-rootCA.pem
openssl verify \
  -CAfile nginx/certs/k8s/_mkcert-rootCA.pem \
  nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem
```

The implementation may compare subject and issuer internally, but acceptance
output must not print those fields. Use parse success, fingerprint equality,
and `openssl verify` as the recorded evidence.

Review the resulting repository state and confirm that no mkcert
`rootCA-key.pem` copy is present or tracked.

### Completion criteria

- Host TLS setup publishes an exact, readable copy of `rootCA.pem` at the
  documented ignored path.
- The published CA verifies the wildcard ingress certificate.
- Re-running host setup without certificate changes is idempotent.
- The host-only execution guard remains effective.
- The script refuses Kubernetes mutation unless the active target is the
  expected local `kind-kind` context backed by the `kind` cluster.
- No mkcert CA private key or new secret crosses into the workspace.
- Orchestration documentation names the publication contract consumed by the
  workspace repository.

## Phase 2: Workspace Trusts The Published Host CA

### Goal

Make a rebuilt/restarted agent container trust the published host mkcert CA
through the normal certificate-verification paths used by curl, Python/httpx,
and Playwright Chromium.

### Scope

- Add the required CA/NSS tooling to `ai-agent-sandbox/Dockerfile`, including
  `libnss3-tools` when `certutil` is not already available.
- Add a small idempotent trust bootstrap owned by `workspace` and installed in
  the container image.
- At container startup, look for the deterministic orchestration artifact from
  Phase 1 and validate that it is a parseable CA certificate before trusting
  it.
- Install the CA under a stable name in the container operating-system trust
  store and run the platform trust-store update only when required.
- Import or refresh the CA in the NSS database actually used by the bundled
  Playwright Chromium. Discover and document the applicable database rather
  than assuming browser verification from system trust alone.
- Configure Python HTTPS libraries to use the combined system CA bundle, for
  example through the stable container environment:

  ```text
  SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  ```

- Preserve the existing public roots and mitmproxy CA while adding the host
  mkcert CA.
- Emit a concise startup warning when the published CA is absent or invalid,
  without preventing unrelated offline agent work.
- Add an idempotent read-only trust verifier that reports:
  - publication file missing or invalid
  - system trust missing or stale
  - Python bundle not configured
  - Chromium/NSS trust missing or stale
- Update `README.md` or the closest workspace setup/trust documentation.

### Non-goals

- Do not generate a new mkcert CA or ingress certificate in the container.
- Do not mount or copy `rootCA-key.pem`.
- Do not add browser flags that ignore certificate errors.
- Do not replace verified HTTPS with HTTP.
- Do not add Budget Analyzer target behavior to generic AI launch wrappers.
- Do not require the local Budget Analyzer stack merely to start the
  devcontainer.

### Required context

- `AGENTS.md`
- `.devcontainer/devcontainer.json`
- `ai-agent-sandbox/docker-compose.yml`
- `ai-agent-sandbox/Dockerfile`
- `ai-agent-sandbox/entrypoint.sh`
- existing mitmproxy CA installation and environment behavior
- `README.md`
- Phase 1's deterministic publication contract

### Implementation notes

- The shared repositories are already mounted under the workspace, so prefer
  the deterministic published file over an OS-specific host-home bind mount.
- Keep `SSL_CERT_FILE` pointed at a combined bundle, not at the mkcert root
  alone, so public HTTPS endpoints remain trusted.
- Container startup may update container-local trust databases; it must not
  modify the host CA file.
- Use a fixed NSS certificate nickname and replace a stale fingerprint
  idempotently after host CA rotation.
- The verifier must never print certificate private-key paths, session values,
  or unrelated environment secrets.

### Validation

Static validation from a writable checkout of the workspace repository:

```bash
docker compose -f ai-agent-sandbox/docker-compose.yml config
shellcheck ai-agent-sandbox/entrypoint.sh
shellcheck ai-agent-sandbox/scripts/check-budget-analyzer-local-ca-trust.sh
```

After Phase 1, rebuild or reopen the devcontainer and run:

```bash
check-budget-analyzer-local-ca-trust
openssl verify \
  -CAfile /etc/ssl/certs/ca-certificates.crt \
  ../orchestration/nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem
curl --fail-with-body https://app.budgetanalyzer.localhost/
python -c 'import httpx; print(httpx.get("https://app.budgetanalyzer.localhost/api/v1/currencies").status_code)'
```

Run an uncredentialed Playwright smoke navigation to
`https://app.budgetanalyzer.localhost/` without `ignore_https_errors`, then run
the trust bootstrap and verifier a second time to prove idempotency.

### Completion criteria

- A fresh agent container discovers and trusts the host-published public CA.
- Curl and Python/httpx reach the local ingress with normal verification.
- Playwright Chromium loads the local HTTPS origin without ignoring
  certificate errors.
- Public Internet certificates continue to validate.
- Repeated startup/trust checks make no unnecessary changes and report the
  same trusted fingerprint.
- Missing publication produces a clear prerequisite warning rather than an
  insecure fallback.
- No private CA material enters the container or repository.

## Phase 3: API Tests Enforce TLS And Preflight Live Runs

### Goal

Remove target-configurable TLS verification and add one early, actionable
prerequisite result before selected tests or tools attempt live API traffic.

### Scope

- Remove `verify_tls` from:
  - all environment YAML files
  - typed environment configuration and normalized non-secret settings
  - `GatewayClient` construction
  - browser-login construction
  - tests, documentation, workflow inputs, and artifact schemas
- Require supported environment origins to use `https`.
- Let httpx use normal verified TLS and the runner's configured trust store.
- Ensure Playwright never enables `ignore_https_errors`.
- Add typed preflight logic and a thin CLI at:

  ```text
  tools/check-live-prerequisites.py
  ```

- Support explicit prerequisite scopes without changing TLS behavior:
  - `public`: verified origin, ingress, ext_authz edge, and public API docs
  - `authenticated`: public checks plus all prerequisites required by the
    configured primary session-acquisition path
  - `authorization`: authenticated checks plus a usable secondary session path
- Add an explicit `--require-local-target` safety option to the preflight CLI
  and pytest plugin for this plan's agent-run acceptance. When selected,
  validate the resolved configuration rather than trusting the `--env local`
  label alone: require `environment_type == "local"` and the exact origin
  `https://app.budgetanalyzer.localhost`. Refuse staging, production, aliases,
  and origin overrides before reading any credential or opening the network.
  This option constrains the target; it must not change TLS behavior.
- Distinguish and report at least:
  - invalid environment configuration or non-HTTPS origin
  - DNS resolution failure
  - connection refusal/timeout suggesting Tilt or the target cluster is down
  - certificate issuer, hostname, expiry, or trust-chain failure
  - ingress/backend readiness failure
  - unexpected unauthenticated gateway behavior
  - missing configured credential/session environment-variable names
- Report all missing variables for the selected acquisition path in one result,
  without reading them into artifacts or printing their values.
- Integrate preflight with pytest after collection but before network-capable
  fixture setup:
  - infer the highest required scope from selected live tests and fixtures
  - do not preflight `--collect-only`
  - do not preflight offline harness/unit tests or snapshot-only tools
  - run once per pytest session, not once per test
- Make live OpenAPI/refresh tools call the public preflight path before fetching
  the deployed document.
- Return documented stable exit codes from the standalone preflight CLI.
- Add deterministic unit tests using `httpx.MockTransport`, `monkeypatch`, and
  pytester; unit tests must not call the live target.
- Update `README.md`, `AGENTS.md`, environment validation documentation, and
  any generated artifact contract affected by removal of `verify_tls`.

### Non-goals

- Do not add `--insecure`, `--no-verify`, agent-container detection, or any
  equivalent TLS bypass.
- Do not make offline collection depend on Tilt, DNS, TLS, credentials, or
  network access.
- Do not start Tilt or mutate Kubernetes from preflight.
- Do not acquire sessions for public-only tools.
- Do not log cookies, passwords, authorization headers, or browser storage.
- Do not convert expected test assertion failures into prerequisite failures.

### Required context

- repository `AGENTS.md`
- `environments/*.yaml`
- `src/api_tests/config.py`
- `src/api_tests/client.py`
- `src/api_tests/browser_login.py`
- `src/api_tests/auth.py`
- `src/api_tests/pytest_plugin.py`
- `src/api_tests/tools/`
- `tools/`
- harness/tool/config tests
- completed Phases 1 and 2 of this plan
- the blocked provider-neutral completion plan

### Implementation notes

- Keep network exception parsing at the httpx boundary and translate expected
  failures into concise typed results.
- Use public gateway requests only. Preflight must not query Kubernetes,
  service DNS, databases, Redis, RabbitMQ, or service health endpoints.
- A useful public readiness proof is:
  - verified HTTPS succeeds
  - unauthenticated `GET /api/v1/currencies` returns the exact expected edge
    status and non-HTML response
  - `GET /api-docs/openapi.json` returns the expected public JSON document
- If browser credentials are configured and the current acquisition
  implementation eagerly requires both users, report all four missing
  username/password variables rather than stopping at the first one.
- Keep prerequisite diagnostics separate from redacted request artifacts.

### Validation

```bash
.venv/bin/python -m ruff format --check .
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src tests
.venv/bin/python -m pytest --env local tests/tools tests/contract tests/auth -q
.venv/bin/python -m pytest --env local --collect-only
.venv/bin/python tools/check-openapi-coverage.py --env local --fail-missing --fail-placeholder
.venv/bin/python tools/check-live-prerequisites.py --help
```

With host Tilt healthy and Phase 2 trust installed:

```bash
.venv/bin/python tools/check-live-prerequisites.py --env local --scope public --require-local-target
.venv/bin/python -m pytest --env local --require-local-target \
  tests/auth/test_edge_auth.py \
  tests/contract/test_unknown_routes.py
```

Stop Tilt or use mocked tests to verify that unavailable-target, TLS, gateway,
and authentication failures each produce one clear prerequisite result without
a traceback or secret value.

### Completion criteria

- `verify_tls` and every insecure TLS execution path are absent from active
  configuration, code, docs, and workflows.
- Supported live origins require HTTPS.
- `--require-local-target` fails before credentials or network access unless
  the resolved target is the exact local Budget Analyzer origin.
- Verified local requests succeed from the trusted agent container.
- A selected live pytest run performs one automatic preflight before client or
  session fixtures.
- Collection and offline tests perform no live preflight.
- The CLI distinguishes target-down, TLS, gateway-readiness, and
  authentication-prerequisite failures.
- Unit tests cover each error category without a real target.
- No prerequisite output or artifact exposes secrets.

## Phase 4: Cross-Repository Acceptance And Plan Handoff

### Goal

Prove the complete host-to-container trust path against a healthy Tilt stack,
then explicitly unblock the provider-neutral API coverage plan.

### Scope

- Confirm Phase 1 host publication and Phase 2 container trust checks pass for
  the same CA fingerprint.
- Start or confirm the local Tilt stack from the host; do not start Tilt from
  the agent container.
- From the agent container, verify the shared Kind cluster and public HTTPS
  ingress are reachable without a TLS bypass.
- Run the API test preflight for public, authenticated, and authorization
  scopes as available, supplying only disposable local test credentials through
  environment variables. Environment variables prevent persistence in config;
  they do not make values confidential from the agent.
- Run the blocked Phase 5 public edge tests and authenticated behavioral suites.
- Record any real endpoint assertion failures as API/product issues rather than
  trust-store prerequisites.
- Update active operator documentation so the supported topology is explicit:

  ```text
  host Tilt/Kind + host mkcert CA
      -> published public root CA
      -> trusted agent container
      -> verified HTTPS public gateway tests
  ```

- Mark this prerequisite plan complete only after the public live acceptance
  path passes. Then resume Phase 5 of the provider-neutral completion plan
  without rerunning its completed Phases 1 through 4.

### Non-goals

- Do not make agent-container Tilt startup part of the supported workflow.
- Do not bypass TLS for diagnostics or acceptance.
- Do not broaden mutation, destructive, staging, or production permissions.
- Do not mark provider-neutral Phase 5 complete if its behavioral assertions
  have not passed.
- Do not treat missing credentials as a harness defect.

### Required context

- completion evidence from Phases 1 through 3
- healthy host-managed Tilt resources
- pre-provisioned browser users or supplied opaque sessions
- `budget-analyzer-api-tests/.ai-session-handler/` state for the blocked plan
- provider-neutral Phase 5 validation and completion criteria

### Implementation notes

- Keep host-only and container-only commands clearly separated in the handoff.
- Before any acceptance command, prove the API-test configuration resolves to
  `environment_type: local` with the exact origin
  `https://app.budgetanalyzer.localhost`. Before host-side cluster inspection
  or mutation, also prove the active context is `kind-kind` and the expected
  host Kind cluster is named `kind`. If an in-container cluster check is added,
  use the context, referenced cluster, loopback API endpoint, and
  `kind-control-plane` node checks instead of `kind get clusters`. Stop on any
  mismatch.
- Compare public CA fingerprints rather than relying only on filenames.
- The existing AI Session Handler state is runner-owned. Do not edit it
  manually; resume or re-accept the revised provider-neutral plan through the
  handler's supported workflow.
- Because the provider-neutral Markdown plan changed while Phase 5 was
  stopped, its next handler invocation must use both `--accept-plan-change` and
  `--retry-stopped` after this prerequisite phase completes.
- If authenticated credentials are intentionally unavailable, public trust and
  edge acceptance may be proven, but this phase remains incomplete until the
  provider-neutral Phase 5 live behavioral suite can run.

### Validation

On the host:

```bash
test "$(kubectl config current-context)" = "kind-kind"
kind get clusters | grep -Fx "kind"
tilt get uiresources
kubectl get pods -A
```

In the agent container:

```bash
check-budget-analyzer-local-ca-trust
.venv/bin/python tools/check-live-prerequisites.py --env local --scope public --require-local-target
.venv/bin/python -m pytest --env local --require-local-target \
  tests/auth/test_edge_auth.py \
  tests/contract/test_unknown_routes.py
.venv/bin/python tools/check-live-prerequisites.py --env local --scope authenticated --require-local-target
.venv/bin/python -m pytest --env local --require-local-target \
  tests/transactions tests/statement_formats tests/views
```

When secondary prerequisites are available:

```bash
.venv/bin/python tools/check-live-prerequisites.py --env local --scope authorization --require-local-target
```

### Completion criteria

- Host and container report the same trusted public CA fingerprint.
- Curl, Python/httpx, and Playwright validate the local ingress without bypass
  options.
- Public preflight and gateway edge tests pass against host-managed Tilt.
- Authenticated Phase 5 behavioral tests run after one clear prerequisite
  result and reach actual endpoint assertions.
- Documentation assigns host certificate publication, container trust, and
  test preflight to the correct repositories.
- The provider-neutral completion plan is explicitly unblocked at Phase 5.
