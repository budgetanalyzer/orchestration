# OAuth binding smoketest imports private api-tests modules

- **Severity:** Low (maintenance)
- **Owner:** orchestration, with budget-analyzer-api-tests
- **Status:** Open
- **Source:** 2026-11-09 independent implementation review O6

## Problem

`scripts/smoketest/verify-oauth-browser-binding.py:14-19` inserts
`../budget-analyzer-api-tests/src` into `sys.path` and imports
`api_tests.auth`, `api_tests.browser_login`, `api_tests.config` and
`api_tests.session_gateway_assertions`.

A refactor in api-tests can break an orchestration smoketest without either
repo's own checks noticing.

## Options

1. Move the test into api-tests, which owns the browser client. Orchestration
   would then no longer gate the browser-binding contract itself.
2. Make the orchestration script self-contained.
3. Have api-tests expose a small supported entry point that orchestration
   calls, instead of importing internals.

## Open question

Which repo should own the browser-binding assertion? That decides between
options 1 and 2/3.

## Acceptance

Orchestration no longer imports private `api_tests` modules, and the
browser-binding contract is still exercised by a gate that someone runs.
