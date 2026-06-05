# Plan: OpenAPI Black-Box API Test Repository

Date: 2026-06-04
Status: Preliminary

Related documents:

- `docs/plans/self-hosted-staging-runner-cd-plan.md`
- `docs-aggregator/README.md`
- `docs-aggregator/openapi.json`
- `docs/architecture/session-edge-authorization-pattern.md`
- `docs/architecture/resource-routing-pattern.md`
- `nginx/README.md`
- `scripts/repo/generate-unified-api-docs.sh`

## Scope

This plan defines a standalone black-box API test repository for every public
operation in the unified OpenAPI contract served through `/api-docs`.

The target repository is separate from service implementation repositories so
it can test the deployed system through the same public API lane used by the
browser:

```text
test runner -> HTTPS ingress -> ext_authz -> NGINX -> services
```

The first consumer is the self-hosted staging runner plan. The repository can
be built before the runner exists and should be usable against local Tilt,
private staging, and production read-only checks.

## Direct Answer: Can This Be Done First?

Yes. The standalone API test repository is a good first step and does not need
to wait for the self-hosted staging runner.

The minimum first configuration is a target URL, but a credible suite needs
more than that:

- public origin and API base path, such as `https://app.budgetanalyzer.localhost`
  plus `/api`
- auth/session strategy for obtaining or receiving a valid `BA_SESSION` cookie
- TLS trust behavior for local and staging certificates
- environment type, such as `local`, `staging`, or `production`
- destructive-test policy so mutating tests cannot run against production by
  accident
- seed-data strategy and test identity assumptions
- timeout, retry, and artifact settings for CI diagnostics

The recommended first version can accept a pre-created session cookie from an
environment variable. Automated session acquisition can be added after the
test identity and Auth0 strategy are explicit.

## Goals

1. Create a standalone test repository that runs outside service repos.
2. Treat `docs-aggregator/openapi.json` or the deployed
   `/api-docs/openapi.json` as the coverage manifest.
3. Exercise every public operation currently exposed by the unified OpenAPI
   spec.
4. Run through the public gateway path, not direct Kubernetes service DNS.
5. Verify success responses, schema shape, expected validation failures,
   not-found behavior, and authorization boundaries where the contract exposes
   them.
6. Produce CI-friendly JUnit, coverage, request log, and OpenAPI drift
   artifacts.
7. Support local and staging as full mutating environments while keeping
   production checks read-only unless explicitly overridden.

## Non-Goals

- Testing service internals or direct in-cluster service URLs.
- Replacing service-local unit, integration, or controller tests.
- Creating orchestration-level workarounds for service-owned API defects.
- Requiring public inbound access to a home staging runner.
- Exercising archived docs or stale test assets.
- Making production data destructive-test capable by default.

## Proposed Repository Shape

```text
budget-analyzer-api-tests/
  README.md
  pyproject.toml
  pytest.ini
  environments/
    local.yaml
    staging.yaml
    production.yaml
  schemas/
    openapi.json
  tests/
    auth/
    api_docs/
    contract/
    currencies/
    exchange_rates/
    statement_formats/
    transactions/
    users/
    views/
  tools/
    export-openapi-coverage.py
    refresh-openapi.py
    validate-environment.py
  artifacts/
    .gitkeep
```

Preferred initial stack:

- `pytest`
- `httpx`
- `pydantic` or `jsonschema` for response and payload checks
- `pytest-xdist` only after data isolation is reliable
- `respx` only for unit tests of the test harness itself, not for API tests

## Environment Configuration

Environment files should be declarative and non-secret:

```yaml
name: local
origin: https://app.budgetanalyzer.localhost
api_base_path: /api
openapi_path: /api-docs/openapi.json
verify_tls: true
environment_type: local
allow_mutation: true
allow_destructive: true
session_cookie_name: BA_SESSION
auth:
  mode: env_cookie
  cookie_env: BA_SESSION
data:
  namespace_prefix: ba-api-test
  cleanup: best_effort
timeouts:
  request_seconds: 15
  eventually_seconds: 30
```

Secrets stay outside the YAML. The first version should read them from
environment variables:

- `BA_SESSION` for a pre-created browser session
- future `BA_TEST_USERNAME` and `BA_TEST_PASSWORD` only if automated login is
  explicitly approved
- future Auth0 or test-identity inputs only after their owner and visibility
  are documented

Production should default to:

```yaml
environment_type: production
allow_mutation: false
allow_destructive: false
```

## OpenAPI Coverage Model

The suite should treat the current OpenAPI document as executable coverage
input.

Required harness behavior:

1. Load the target OpenAPI document from the deployed environment.
2. Optionally compare it with the checked-in `schemas/openapi.json` snapshot.
3. Build an operation inventory from `paths`.
4. Require every `operationId` to map to at least one test marker.
5. Fail CI when a new operation appears without an explicit test or waiver.
6. Emit a coverage artifact listing operation id, method, path, expected test
   files, and execution status.

Coverage marker convention:

```python
@pytest.mark.openapi("create")
def test_create_currency_series(...):
    ...
```

Waivers should be explicit, reviewed, and time bounded:

```yaml
waivers:
  importLatestExchangeRates:
    reason: "Calls external provider; needs deterministic provider fixture."
    expires: "2026-07-15"
```

## Current Public Operation Inventory

This inventory reflects `docs-aggregator/openapi.json` on 2026-06-04. It is a
planning snapshot only. The implemented suite should regenerate coverage from
OpenAPI at runtime.

### Transactions

| Operation | Method | Path | Primary assertions |
| --- | --- | --- | --- |
| `getTransactions` | `GET` | `/v1/transactions` | Returns a paged transaction response for the authenticated user. |
| `searchTransactions` | `GET` | `/v1/transactions/search` | Supports documented filters, pagination, and sorting. |
| `countTransactions` | `GET` | `/v1/transactions/count` | Returns count consistent with seeded transactions. |
| `countTransactionsAcrossUsers` | `GET` | `/v1/transactions/search/count` | Enforces role/permission behavior and returns aggregate count only when allowed. |
| `getTransaction` | `GET` | `/v1/transactions/{id}` | Returns seeded transaction by id and `404` for an unknown id. |
| `updateTransaction` | `PATCH` | `/v1/transactions/{id}` | Applies partial updates and rejects invalid fields. |
| `deleteTransaction` | `DELETE` | `/v1/transactions/{id}` | Deletes an owned transaction and returns `404` after deletion. |
| `previewTransactions` | `POST` | `/v1/transactions/preview` | Accepts representative upload input and reports preview rows or validation errors. |
| `batchImportTransactions` | `POST` | `/v1/transactions/batch` | Imports a deterministic batch and reports accepted/rejected rows. |
| `bulkDeleteTransactions` | `POST` | `/v1/transactions/bulk-delete` | Deletes a controlled seeded set and rejects malformed ids. |

### Statement Formats

| Operation | Method | Path | Primary assertions |
| --- | --- | --- | --- |
| `listFormats` | `GET` | `/v1/statement-formats` | Lists visible formats and honors `includeHidden`. |
| `createFormat` | `POST` | `/v1/statement-formats` | Creates a format and rejects invalid mapping payloads. |
| `getFormat` | `GET` | `/v1/statement-formats/{id}` | Returns a seeded format and `404` for an unknown id. |
| `updateFormat` | `PUT` | `/v1/statement-formats/{id}` | Replaces editable fields and validates required structure. |
| `hideFormat` | `POST` | `/v1/statement-formats/{id}/hide` | Hides a format from default listing. |
| `unhideFormat` | `POST` | `/v1/statement-formats/{id}/unhide` | Restores a hidden format to default listing. |
| `analyzeCsvSample` | `POST` | `/v1/statement-formats/csv-wizard/analyze` | Accepts a fixture CSV and returns detected columns/warnings. |
| `previewCsvMapping` | `POST` | `/v1/statement-formats/csv-wizard/preview` | Applies CSV mapping and returns deterministic preview rows. |
| `saveCsvWizardFormat` | `POST` | `/v1/statement-formats/csv-wizard/save` | Saves a CSV wizard format from fixture input. |
| `analyzePdfSample` | `POST` | `/v1/statement-formats/pdf-wizard/analyze` | Accepts a fixture PDF and returns table candidates. |
| `previewPdfMapping` | `POST` | `/v1/statement-formats/pdf-wizard/preview` | Applies PDF mapping and returns deterministic preview rows. |
| `savePdfWizardFormat` | `POST` | `/v1/statement-formats/pdf-wizard/save` | Saves a PDF wizard format from fixture input. |

### Saved Views

| Operation | Method | Path | Primary assertions |
| --- | --- | --- | --- |
| `listViews` | `GET` | `/v1/views` | Lists views for the authenticated user. |
| `createView` | `POST` | `/v1/views` | Creates a view with criteria and rejects invalid criteria. |
| `getView` | `GET` | `/v1/views/{id}` | Returns a seeded view and `404` for unknown id. |
| `updateView` | `PUT` | `/v1/views/{id}` | Updates name and criteria. |
| `deleteView` | `DELETE` | `/v1/views/{id}` | Deletes a view and verifies subsequent `404`. |
| `getViewTransactions` | `GET` | `/v1/views/{id}/transactions` | Returns transactions matching view criteria plus pin/exclude state. |
| `pinTransaction` | `POST` | `/v1/views/{id}/pin/{txnId}` | Pins one seeded transaction. |
| `unpinTransaction` | `DELETE` | `/v1/views/{id}/pin/{txnId}` | Removes one pinned transaction. |
| `bulkPinTransactions` | `POST` | `/v1/views/{id}/pin` | Pins multiple seeded transactions. |
| `excludeTransaction` | `POST` | `/v1/views/{id}/exclude/{txnId}` | Excludes one seeded transaction. |
| `unexcludeTransaction` | `DELETE` | `/v1/views/{id}/exclude/{txnId}` | Removes one excluded transaction. |
| `bulkExcludeTransactions` | `POST` | `/v1/views/{id}/exclude` | Excludes multiple seeded transactions. |

### Currency And Exchange Rates

| Operation | Method | Path | Primary assertions |
| --- | --- | --- | --- |
| `getAll` | `GET` | `/v1/currencies` | Lists currencies and honors `enabledOnly`. |
| `create` | `POST` | `/v1/currencies` | Creates a test currency series and rejects duplicates/invalid ISO codes. |
| `getById` | `GET` | `/v1/currencies/{id}` | Returns created currency series and `404` for unknown id. |
| `update` | `PUT` | `/v1/currencies/{id}` | Updates editable currency-series fields. |
| `getExchangeRates` | `GET` | `/v1/exchange-rates` | Filters by date range and target currency. |
| `importLatestExchangeRates` | `POST` | `/v1/exchange-rates/import` | Runs only in mutation-enabled environments and asserts deterministic result shape. |

### User Administration

| Operation | Method | Path | Primary assertions |
| --- | --- | --- | --- |
| `getUsers` | `GET` | `/v1/users` | Enforces permission requirements and supports documented filters. |
| `getUser` | `GET` | `/v1/users/{id}` | Returns accessible user details and denies/404s inaccessible ids as specified. |
| `deactivateUser` | `POST` | `/v1/users/{id}/deactivate` | Runs only against disposable test identities and verifies permission checks. |

## Cross-Cutting Test Categories

Every operation should have at least one happy-path or expected-result test.
Mutating operations also need cleanup or isolated data. The suite should add
the following cross-cutting tests:

- unauthenticated `/api/*` request returns `401` from the edge
- authenticated request reaches the expected service and does not fall through
  to the SPA
- unknown `/api/v1/...` route fails closed
- malformed JSON returns the documented `400` shape where applicable
- invalid multipart upload returns documented validation status
- response content type is JSON for API responses
- response payloads conform to referenced OpenAPI schemas for `2xx` responses
- destructive tests are blocked when `allow_destructive` is false
- operation coverage fails when the OpenAPI spec gains an untested operation

## Data And Identity Strategy

The suite needs repeatable data without service-internal setup hooks.

Recommended first approach:

1. Use a dedicated test user for local and staging.
2. Create test data through public APIs whenever possible.
3. Prefix names/descriptions with a unique run id such as
   `ba-api-test-<timestamp>-<short-sha>`.
4. Register cleanup callbacks after every successful create.
5. Prefer cleanup through public delete/hide/deactivate APIs.
6. Keep production checks read-only and skip create/update/delete/import tests
   unless explicitly enabled.

Open identity decisions:

- whether the test repository is allowed to automate Auth0 browser login
- whether CI receives a short-lived pre-created `BA_SESSION` cookie
- whether staging can include a controlled test-only identity bootstrap process
- how to represent admin versus non-admin users for permission tests

Until those decisions are made, the first implementation should support
`auth.mode: env_cookie` and fail clearly when the cookie is missing.

## Implementation Phases

### Phase 1: Repository Bootstrap

Work:

- create the standalone repository with the proposed Python test stack
- add local, staging, and production environment config templates
- add a typed config loader
- add an `httpx` client wrapper that composes `origin`, `api_base_path`, and
  operation paths
- support `BA_SESSION` cookie injection
- add JUnit XML and request-log artifact output

Completion criteria:

- `pytest --env local --collect-only` works
- missing target URL or missing auth fails with a useful error
- one authenticated `/api-docs/openapi.json` or public docs download check runs
  without service-specific assumptions

### Phase 2: OpenAPI Coverage Harness

Work:

- vendor or fetch `openapi.json`
- parse every method/path/operationId
- add `@pytest.mark.openapi("<operationId>")`
- add a coverage verifier that fails on missing tests
- write coverage output to `artifacts/openapi-coverage.json`
- add optional snapshot drift detection against `schemas/openapi.json`

Completion criteria:

- all 43 current operations are mapped to tests or explicit waivers
- adding a fake operation to the snapshot makes the coverage verifier fail
- the coverage report is uploaded as a CI artifact

### Phase 3: Read-Only Smoke And Contract Tests

Work:

- implement docs route checks for `/api-docs/openapi.json`
- implement unauthenticated `/api/*` edge rejection checks
- implement read-only list/get tests for currencies, exchange rates,
  transactions, statement formats, saved views, and users
- add schema validation for stable `2xx` responses
- add unknown-id `404` checks where ids can be safely generated

Completion criteria:

- read-only suite can run against local, staging, and production
- production mode skips mutating tests by default
- failures include method, URL, status, response headers, and clipped body

### Phase 4: Public-API Data Builders

Work:

- add builders for currency series, statement formats, transactions, and saved
  views using only public APIs
- add fixture CSV and PDF files for preview and wizard endpoints
- add best-effort cleanup through public APIs
- isolate test runs by unique prefix and created-id registry

Completion criteria:

- local and staging can create and clean their own data
- rerunning after a failed test does not require manual database cleanup
- cleanup failures are reported but do not hide the original test failure

### Phase 5: Mutating Endpoint Coverage

Work:

- implement create/update/delete tests for transactions
- implement batch import, preview, and bulk delete tests
- implement create/update/hide/unhide and CSV/PDF wizard tests for statement
  formats
- implement saved-view create/update/delete, transactions, pin, unpin, exclude,
  and unexclude tests
- implement currency create/update tests
- guard exchange-rate import behind mutation and external-dependency controls

Completion criteria:

- every non-user operation has a happy path or a documented waiver
- validation-error cases cover all request-body schemas
- destructive operations run only when the environment explicitly allows them

### Phase 6: Permission And User Administration Coverage

Work:

- define admin and non-admin test identities
- verify user list/detail permission behavior
- verify `deactivateUser` only against disposable test identities
- add negative tests for cross-user transaction and saved-view access if the
  public contract promises isolation

Completion criteria:

- permission tests prove expected `403` behavior where OpenAPI documents it
- no test can deactivate or mutate a non-disposable identity
- user-admin tests are skipped with a clear reason when identity prerequisites
  are absent

### Phase 7: CI And Self-Hosted Runner Integration

Work:

- add GitHub Actions workflow for lint, type checks, unit tests, and API tests
- add a workflow input for environment selection
- run read-only tests on hosted runners when the target is public and safe
- run full staging tests on the `pn50-staging` self-hosted label after staging
  deployment succeeds
- upload JUnit XML, OpenAPI coverage, and request logs

Completion criteria:

- a failed operation blocks the staging gate
- production deployment approval can cite the staging API test workflow result
- test artifacts are available from the GitHub Actions run

## Staging Runner Integration Point

The self-hosted staging workflow should call this repository after deployment:

```bash
pytest --env staging --junitxml artifacts/junit.xml
python tools/export-openapi-coverage.py --fail-missing
```

The staging workflow should provide:

- target origin
- trusted CA or TLS verification mode
- session cookie or approved automated-login inputs
- `allow_mutation=true`
- `allow_destructive=true` only for ephemeral staging
- deployment metadata such as image manifest or release id

## Maintenance Rules

- Regenerate the OpenAPI snapshot when the unified API contract changes.
- Treat every new public operation as incomplete until it has a test or waiver.
- Keep detailed endpoint behavior in OpenAPI and service-local docs, not in
  this plan.
- Keep environment secrets out of checked-in YAML.
- Do not add direct database, Redis, RabbitMQ, or Kubernetes setup paths to the
  black-box API tests.
- Do not broaden production test permissions just to exercise mutating
  endpoints.

## Open Questions

1. Should the test repository be public, private, or initially local?
2. Who owns the test Auth0 tenant/application and disposable identities?
3. Should the first CI version require a manually supplied `BA_SESSION`, or is
   automated browser login acceptable?
4. Should exchange-rate import be mocked by staging configuration, tested
   against the real provider, or limited to response-shape checks?
5. Which user-admin scenarios are safe enough for automated staging mutation?
6. Should the OpenAPI snapshot be copied from orchestration during release
   preparation or fetched live from the deployed `/api-docs/openapi.json` only?

## Initial Success Criteria

- Standalone repo can run one authenticated request against local Tilt by URL.
- Coverage harness discovers all 43 current unified OpenAPI operations.
- Every operation has a mapped test or explicit waiver.
- Read-only tests are safe against production by default.
- Full mutating tests pass against an isolated local or staging environment.
- Staging runner workflow can consume the suite as a deployment gate.
