# Edge verifier deletes a load-test fixture it says it protects

- **Severity:** Medium
- **Owner:** orchestration
- **Status:** Open (plans 01 and 05)
- **Source:** 2026-11-09 implementation review F2; independent implementation review C4
- **Related:** [cleanup residue verifier detection](low-cleanup-residue-verifier-detection-regex.md)

## Problem

In `scripts/smoketest/verify-edge-contract.sh`, five sections refuse to run if
`.loadtest/session-pool.txt` exists, because teardown would remove it
(`:439-441`, `:664-666`, `:970-972`, `:1147-1149`, `:1449-1451`). Each calls
`fail` and then a bare `return`, so `main` continues.

The last section, `verify_response_headers` (`:1588-1590`), calls
`seed_fixture` (`:361-365`), which has no ownership check. The sequence is:

1. The verifier warns five times and skips those sections.
2. The seeder overwrites the pool file
   (`scripts/loadtest/seed-loadtest-users.sh:188`).
3. `scripts/loadtest/teardown-loadtest.sh` removes all `usr_loadtest_%`
   users, roles, transactions and indexed sessions by pattern, including the
   pre-existing fixture. The EXIT trap (`:269-276`) does the same if the
   section fails partway.
4. The verifier exits with failure, but only after the destructive cleanup.

This conclusion comes from reading the control flow; it was not reproduced. The data is local and synthetic,
but the guard contradicts itself.

## Proposed fix

- Put one mandatory ownership check in `seed_fixture` (or in `main` before any
  section) and exit immediately if a pool already exists.
- Delete the five per-section copies.
- If concurrent verifier and load-test runs are supported, use one shared lock
  around fixture acquisition and cleanup. A file-existence check alone is racy.

## Acceptance

- With a pre-existing pool, a stubbed seeder and teardown are never called,
  the pool is unchanged, and the verifier fails before sending requests.
- A seed failure after partial creation has explicit cleanup ownership.

## Open question

Are concurrent verifier and load-test runs a supported workflow? That decides
whether a lock is needed or a preflight is enough.
