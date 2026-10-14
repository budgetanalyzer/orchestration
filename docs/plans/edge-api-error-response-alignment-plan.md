# Align Edge Authentication Error Responses

Make every versioned machine endpoint return the shared `ApiErrorResponse` wire
contract for authentication and dependency failures, regardless of which edge or
application layer rejects the request. Preserve browser-oriented redirects on
`/login`, `/oauth2/*`, `/login/oauth2/*`, and `/logout`.

The unified `/api` specification and the separate Session Gateway specification
remain distinct contracts. Public `/api/*` authentication denials are normally
produced by `ext-authz`; `/auth/v1/*` responses are produced by Session Gateway;
backend services retain their existing defense-in-depth JSON security responses.
The shared wire shape requires `type` and `message`; edge producers may omit the
optional `code` and `fieldErrors` fields.

## Agreed behavior and boundaries

| Request outcome | Producer | Public response |
| --- | --- | --- |
| Missing, blank, unknown, or expired API session | `ext-authz` | `401 application/json` with `UNAUTHORIZED` / `Authentication required` |
| `ext-authz` session-store or unexpected lookup failure | `ext-authz` | Fail closed with `503 application/json` and `SERVICE_UNAVAILABLE`; do not misclassify infrastructure failure as invalid credentials |
| Missing, invalid, expired, or invalidated `/auth/v1/*` session | Session Gateway | `401 application/json` with `UNAUTHORIZED` / `Authentication required`; preserve required cookie clearing |
| Session Gateway authorization refresh or Redis failure | Session Gateway | Existing temporary-failure status with schema-valid `ApiErrorResponse` JSON |
| Missing or malformed trusted claims after edge admission | Backend service | Existing service-common JSON `401` defense-in-depth response |
| Insufficient authenticated grants | Backend service | Existing JSON `403` response |

Use generic messages for security failures and never reveal whether a cookie was
unknown, expired, malformed, or tied to a particular account. Do not make OAuth
navigation endpoints return JSON, change session storage, weaken fail-closed
behavior, introduce a shared cross-language runtime package, or deploy to staging
or production.

`service-common/docs/error-handling.md` records the accepted coupling decision:
changes to `ApiErrorResponse` must be coordinated with edge producers so callers
receive one stable public shape without learning which internal layer rejected a
request. The Go service should implement the minimal wire representation locally;
it must not depend on Java implementation artifacts.

## Execution prerequisites

- Execute each phase in its declared repository and read that repository's
  `AGENTS.md` before changing files. A phase may inspect sibling contracts but may
  not write outside its workspace.
- Preserve all existing worktree changes. In particular,
  `../budget-analyzer-api-tests` contains the uncommitted Phase 1 and Phase 2
  handoff from `openapi-authentication-authorization-response-plan.md`; do not
  discard, reset, regenerate over, or reinterpret that work.
- Live validation is local Tilt/Kind only. Before any cluster mutation, satisfy
  `docs/architecture/autonomous-ai-execution.md`: prove context and referenced
  cluster are exactly `kind-kind`, the Kubernetes API authority is exact loopback
  HTTPS with no proxy override, the local Kind cluster exists, and
  `kind-control-plane` is Ready. Never generate certificates, bypass TLS
  verification, use human credentials, or access staging/production.
- Use repository-owned build, live-update, and verification workflows. Do not
  leave durable manual cluster drift. Do not commit, push, manipulate branches,
  publish releases, or update production image digests.

## Phase 1: Emit Structured Denials From ext-authz

### Workspace

../ext-authz

### Goal

Make the external authorization service emit the shared minimal JSON error wire
contract while preserving fail-closed session validation.

### Scope

HTTP authorization denial responses, failure classification, focused Go tests,
and service-local documentation.

### Non-goals

Changing Redis session fields, cookie names, identity headers, authorization
policy, ports, successful allow responses, permission checks, or deployment
manifests.

### Required context

- `AGENTS.md`, `README.md`, `http_server.go`, `http_server_test.go`, and the Redis
  session lookup implementation and tests.
- `../service-common/docs/error-handling.md` and the required fields and enum
  values in the public `ApiErrorResponse` schema.
- `../orchestration/docs/architecture/session-edge-authorization-pattern.md`
  and `../orchestration/kubernetes/istio/istiod-values.yaml`.

### Execution steps

1. Introduce a small service-local JSON response representation or equivalent
   encoder containing only `type` and `message`. Keep the literals aligned with
   the public contract; do not copy optional Java-only behavior or expose lookup
   details.
2. Route missing/blank cookies and known missing or expired sessions through one
   `401` writer that sets `Content-Type: application/json` and emits
   `UNAUTHORIZED` / `Authentication required`.
3. Route unexpected lookup, Redis, parsing, or infrastructure failures through a
   fail-closed `503` writer with `SERVICE_UNAVAILABLE` and a generic message.
   Preserve useful internal logs without returning internal causes to callers.
4. Retain the current `200` allow response and identity-header behavior exactly.
   Ensure denial bodies cannot accidentally be attached to successful responses.
5. Add table-driven tests for no cookie, blank cookie, unknown session, expired
   session, unexpected store failure, encoding/content type, generic messages,
   and successful identity injection. Assert complete decoded JSON values and
   absence of sensitive/session-specific text.
6. Update `README.md` to describe the denial response contract and link to the
   orchestration-owned shared session-edge contract. Note that the Go wire type
   must track `ApiErrorResponse` without depending on service-common binaries.

### Implementation notes

Use `encoding/json` and `net/http` conventions. A serialization failure must not
turn a denial into an allow. Keep all authentication failures indistinguishable
to the caller; only operational failures receive `503`.

### Validation

Run:

```bash
gofmt -w *.go
go test ./...
go vet ./...
docker build -t ext-authz:local .
git diff --check
```

Inspect the diff for accidental session-schema, header, logging, or configuration
changes.

### Completion criteria

Every known authentication denial is schema-compatible JSON `401`, unexpected
store failures are generic JSON `503` denials, valid sessions still produce the
same allow headers, and all Go tests and image build checks pass.

## Phase 2: Align Session Gateway Machine Endpoints

### Workspace

../session-gateway

### Goal

Make both `/auth/v1/user` and `/auth/v1/session` expose the shared JSON error
contract and document their actual behavior accurately.

### Scope

The machine-endpoint security entry point, controller OpenAPI annotations,
focused integration tests, and Session Gateway API/security documentation.

### Non-goals

Changing OAuth redirects, login or logout navigation, session persistence,
heartbeat refresh semantics, cookie attributes, browser routes, or internal
bulk-revocation behavior.

### Required context

- `AGENTS.md`, `README.md`, `docs/security.md`, and
  `docs/session-configuration.md`.
- `SecurityConfig`, `UserController`, `SessionController`, their integration
  tests, and the service-common reactive exception handling already on the
  classpath.
- `../service-common/docs/error-handling.md` and the current
  `ApiErrorResponse`/`ApiErrorType` APIs.
- The generated Session Gateway contract at
  `../budget-analyzer-web/docs/api/session-gateway-api.yaml`, read-only in this
  phase.

### Execution steps

1. Replace the empty `/auth/v1/user` authentication entry-point response with a
   response serialized from the shared `ApiErrorResponse` model using the
   service's configured `ObjectMapper`. Set JSON content type and the generic
   `UNAUTHORIZED` message. Do not hand-maintain a second Java DTO or expose the
   Spring Security exception message.
2. Preserve the browser redirect entry point for every non-machine authentication
   route. Confirm `/login`, OAuth initiation/callback, and failure redirects are
   unchanged.
3. Keep `/auth/v1/session` runtime handling on the existing shared reactive error
   path; it already emits JSON. Preserve cookie clearing for expired, missing,
   deactivated, or concurrently invalidated sessions.
4. Correct both controllers' OpenAPI annotations so runtime `401` responses use
   `application/json` with `ApiErrorResponse`. Correct the heartbeat `503`
   response documentation to the same schema because runtime already uses it.
   Do not add browser redirect endpoints to this machine-response policy.
5. Strengthen integration tests for absent, blank, missing, expired, and
   invalidated sessions. Assert status, JSON content type, exact `type` and generic
   `message`, required cookie clearing, and no sensitive reason text. Retain a
   regression proving browser failures still redirect.
6. Update the nearest API/security documentation to define the boundary between
   versioned JSON endpoints and browser navigation responses.

### Implementation notes

The security filter chain handles an unauthenticated `/auth/v1/user` request
before the controller, while `/auth/v1/session` is permitted through to controller
logic. Tests must cover both paths because controller advice alone cannot prove
the security entry-point response.

### Validation

Run focused controller and security integration tests while iterating. Then run,
in the repository-required sequence:

```bash
./gradlew clean spotlessApply
./gradlew clean build
git diff --check
```

Treat Checkstyle warnings as failures and inspect the generated OpenAPI test
coverage for both machine endpoints.

### Completion criteria

Both `/auth/v1/*` endpoints return schema-compatible JSON for every tested `401`,
heartbeat temporary failures are documented as JSON, browser-oriented routes
retain redirects, and the complete Session Gateway build passes.

## Phase 3: Pin the Edge Contract in Orchestration

### Workspace

.

### Goal

Make deny-response forwarding explicit, document the shared edge contract, and
prove the response shape through the real local ingress.

### Scope

Istio extension-provider response-header policy, canonical architecture docs,
the targeted ingress verifier and its catalog entry, and local Tilt/Kind runtime
validation.

### Non-goals

Editing sibling service code, publishing images, updating production image
digests, deploying outside local Kind, weakening TLS, or changing API routing.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`,
  `docs/architecture/session-edge-authorization-pattern.md`,
  `docs/architecture/security-architecture.md`, and
  `docs/architecture/autonomous-ai-execution.md`.
- `kubernetes/istio/istiod-values.yaml`,
  `kubernetes/istio/ext-authz-policy.yaml`, `Tiltfile`, and the rendered ingress
  Envoy `ext_authz` filter configuration.
- `scripts/smoketest/verify-istio-ingress.sh`, `scripts/README.md`, and relevant
  static security guardrails.
- Phase 1 and Phase 2 outcomes and their focused test evidence.

### Execution steps

1. Add an explicit, narrow `headersToDownstreamOnDeny` policy for
   `content-type` to the Istio HTTP extension provider. Preserve the existing
   allow-header list, cookie check input, and `failOpen: false`. Inspect rendered
   Envoy configuration to confirm the intended deny-header allowlist and body
   forwarding rather than relying only on source YAML.
2. Update the canonical session-edge documentation with the versioned-machine
   endpoint rule, producer split, exact generic `401` contract, `503` operational
   distinction, and accepted cross-language coupling. Keep OAuth/browser redirect
   behavior explicitly outside the JSON rule.
3. Strengthen the existing ingress verifier so an unauthenticated public API
   request must receive exactly `401`, JSON content type, and the required
   `UNAUTHORIZED`/`Authentication required` fields. Add equivalent checks for
   unauthenticated `/auth/v1/user` and `/auth/v1/session`. Use verified local HTTPS
   and redact response diagnostics; do not use `--insecure` or create accounts.
4. Extend static guardrails or focused configuration checks to prevent removal of
   the deny `content-type` forwarding policy. Update `scripts/README.md` and the
   nearest architecture cross-links for the enhanced verifier.
5. Before applying any local runtime change, run the exact local-cluster safety
   checks required by the autonomous-execution document. Let Tilt rebuild/live
   update the sibling services and reconcile repo-owned Istio configuration;
   never patch the live cluster as the durable fix.
6. Run the focused public-ingress verifier, inspect `ext-authz`, Session Gateway,
   and ingress logs for the tested requests, and confirm NGINX/backend logs show
   that unauthenticated `/api/*` requests were denied before routing.

### Implementation notes

The response body is produced by the authorization service; orchestration owns
which denial headers Envoy may expose. Keep that list minimal. Existing production
installation paths consume the same checked-in Istio values, but production
release publication and deployment remain human-owned follow-up after reviewed
service releases.

### Validation

Run `bash -n` and `shellcheck` on every modified shell script and fix every
warning. Run the focused static security checks, the enhanced ingress verifier,
and `git diff --check`. Validate the live Envoy filter and all three public JSON
denial responses through `https://app.budgetanalyzer.localhost` with normal TLS
verification.

### Completion criteria

Repo-owned Istio configuration narrowly forwards the JSON media type on denial,
canonical docs define one machine-error contract, static checks protect the
wiring, and the real local ingress proves JSON denials for `/api/*` and both
`/auth/v1/*` endpoints without downstream API routing.

## Phase 4: Refresh the Published Session Gateway Specification

### Workspace

../budget-analyzer-web

### Goal

Refresh the frontend-owned generated Session Gateway API snapshot from the
corrected deployed local contract and verify that only the intended response
documentation changed.

### Scope

`docs/api/session-gateway-api.yaml` and any nearest API-integration wording that
incorrectly claims empty machine-endpoint errors.

### Non-goals

Frontend runtime behavior, generated unified backend API changes, application
error-message UX, dependencies, or source code.

### Required context

- `AGENTS.md`, `docs/README.md`, `docs/api-integration.md`, and
  `docs/api/session-gateway-api.yaml`.
- Phase 2's live Session Gateway OpenAPI output and Phase 3's successful local
  ingress verification.
- `../orchestration/docs-aggregator/README.md` and the documented
  `--session-gateway-only` generator contract.

### Execution steps

1. Confirm the local deployment exposes the reviewed Session Gateway contract:
   both machine endpoints document schema-backed JSON `401` responses, and the
   heartbeat documents its JSON `503` response.
2. From this workspace, run the orchestration generator's explicit
   `--session-gateway-only` mode with
   `docs/api/session-gateway-api.yaml` as the sole output. Do not run default mode
   or modify orchestration/unified outputs from this phase.
3. Inspect the generated diff. Accept only the intended response content/schema
   changes and generator-normalization changes that are understood and reviewed;
   stop on unrelated API drift.
4. Update `docs/api-integration.md` only if it currently describes an empty error
   response or otherwise conflicts with the versioned-machine endpoint rule.

### Implementation notes

The snapshot is generated evidence, not a hand-edited substitute for correcting
Session Gateway annotations. Do not refresh it until the Phase 2 implementation
is deployed locally.

### Validation

Run the repository's documentation/link checks that apply to API docs, validate
the YAML parses, confirm both response schemas resolve to `ApiErrorResponse`, and
run `git diff --check`. No frontend build is required if no application source or
tooling file changes.

### Completion criteria

The checked-in Session Gateway specification matches the deployed machine-error
contract, contains no unrelated drift, and any nearby frontend documentation is
consistent.

## Phase 5: Complete Black-Box Authentication Coverage

### Workspace

../budget-analyzer-api-tests

### Goal

Prove the aligned contracts through public ingress and complete the previously
blocked exhaustive authentication phase without weakening its assertions.

### Scope

The existing uncommitted OpenAPI-driven authentication matrix, focused
unauthenticated Session Gateway checks, marker policy as needed, local execution,
and redacted run evidence.

### Non-goals

Service or deployment changes, authenticated `403` execution, request-body
generation, admin identities, production mutations, or accepting a contract from
a sibling file instead of the deployed public endpoint.

### Required context

- `AGENTS.md`, `README.md`, `docs/openapi-coverage.md`, and
  `docs/plans/openapi-authentication-authorization-response-plan.md`.
- The current uncommitted Phase 1/Phase 2 files and the stopped run under
  `.ai-session-handler/plans/`; preserve them as the implementation handoff.
- `tests/api/auth/`, `src/api_tests/assertions.py`, marker policy tests,
  environment files, and the checked-in unified OpenAPI snapshot.
- Phase 3 ingress evidence and the deployed Session Gateway public contract.

### Execution steps

1. Inspect and retain the existing exhaustive 40-operation matrix and strict
   OpenAPI schema assertions. Do not turn JSON checks into status-only checks or
   regenerate away reviewed snapshot changes.
2. Add focused unauthenticated tests for `/auth/v1/user` and
   `/auth/v1/session`. Use the unauthenticated public gateway client, issue no
   login or provisioning request, and assert `401`, JSON, `UNAUTHORIZED`, and the
   generic message. Keep these separate from the unified `/api` OpenAPI inventory
   because Session Gateway publishes a separate specification.
3. Apply per-case read-only and production-safe markers to these GET requests,
   and update marker-policy unit tests or documented counts if collection changes.
   Ensure production selection cannot instantiate a session fixture.
4. Run focused offline unit, collection, formatting, lint, and strict typing
   checks. Then run the matrix-only local selection and the full
   `./run-tests tests/api/auth` selector through verified public HTTPS.
5. Inspect the isolated request log: require exactly one unauthenticated request
   per selected case, no cookie or authorization header, no login/signup traffic,
   JSON `401` responses, and no sensitive values. Keep the normal shared pacing.
6. Rerun the original plan's listed Phase 2 validation and record the successful
   evidence needed to retry or close its previously blocked handler state. Do not
   edit handler state files manually.

### Implementation notes

The Session Gateway checks validate the shared wire behavior directly but do not
merge its separately published OpenAPI into the backend operation inventory. A
uniform failure across all backend operations is still one edge regression, but
the exhaustive matrix remains valuable proof that every documented route is
covered and rejected before parsing.

### Validation

At minimum run:

```bash
.venv/bin/python -m pytest tests/unit/openapi tests/unit/pytest_plugin --env local
.venv/bin/python -m pytest tests/api/auth --env local --collect-only
.venv/bin/python -m pytest tests/api/auth --env production --collect-only
.venv/bin/python -m ruff format --check .
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src tests
./run-tests tests/api/auth -m authentication
./run-tests tests/api/auth
git diff --check
```

Inspect each generated run artifact rather than relying only on pytest totals.

### Completion criteria

All 40 unified API operations and both Session Gateway machine endpoints return
the agreed JSON `401` through public ingress, no authentication fixture is used by
the unauthenticated cases, all offline and live gates pass, and the original
blocked Phase 2 has durable success evidence without weakened assertions.
