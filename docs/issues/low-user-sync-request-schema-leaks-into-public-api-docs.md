# Internal `UserSyncRequest` schema leaks into the public API docs

- **Severity:** Low
- **Owner:** permission-service (rename); orchestration (regenerated API docs)
- **Status:** Open
- **Source:** 2026-11-14 Redis split API-doc regeneration

## Problem

permission-service `c7aecf9` ("use POST for user sync", #52) added a request body
record, `UserSyncRequest`, for `POST /internal/v1/users/sync`. The endpoint path
is internal, but the schema name does not use the `Internal` prefix that the
other internal DTOs use (`InternalPermissionsResponse`,
`InternalAuthorizationResponse`).

`scripts/repo/generate-unified-api-docs.sh` removes `/internal` paths and
`Internal*` component schemas. It keeps `UserSyncRequest` as an unreferenced
component, so the public unified contract exposes the shape of an internal
Session Gateway-to-permission-service contract. It appears in:

- `docs-aggregator/openapi.json` and `docs-aggregator/openapi.yaml`, served at
  `/api-docs`;
- `../budget-analyzer-web/docs/api/budget-analyzer-api.yaml`;
- `../budget-analyzer-api-tests/schemas/openapi.json` after its next refresh.

permission-service does not document the `Internal` prefix convention, and
`PermissionOpenApiIntegrationTest.java` asserts the current
`#/components/schemas/UserSyncRequest` reference.

## Proposed fix

- In permission-service, rename `UserSyncRequest` to `InternalUserSyncRequest`,
  update `PermissionOpenApiIntegrationTest`, and document the `Internal` prefix
  rule for internal-endpoint DTOs.
- Rerun `./scripts/repo/generate-unified-api-docs.sh` and refresh the api-tests
  `schemas/openapi.json` snapshot.

## Acceptance

- No `UserSyncRequest` or `InternalUserSyncRequest` schema appears in the
  regenerated `docs-aggregator/` outputs, the web `docs/api/` snapshot or the
  api-tests snapshot.
- Session Gateway login-time user sync still succeeds against the renamed
  permission-service contract.
