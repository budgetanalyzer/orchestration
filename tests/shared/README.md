# Shared Test Environment

> Phase 7 status: this shared DinD image contract is retained only because
> `tests/setup-flow` and `tests/security-preflight` are still checked in. Those
> suites are stale, non-gating Phase 7 assets until they are explicitly
> realigned, but `Dockerfile.test-env` still follows the same digest-pinning
> rule as the rest of the repo.

This directory contains the shared DinD test runner image used by multiple test suites.

## Purpose

Avoid cross-suite coupling by keeping test image definition in one neutral location:

- `tests/setup-flow/docker-compose.test.yml`
- `tests/security-preflight/docker-compose.test.yml`

Both suites must reference:

- `build.context: ../shared`
- `build.dockerfile: Dockerfile.test-env`

## Contract

`Dockerfile.test-env` must provide these tools for test scripts:

- `docker`
- `kubectl`
- `kind`
- `helm`
- `tilt`
- `mkcert`
- `git`
- `certutil`

The suite `run-test.sh` scripts validate this contract before running tests.
