# Shared Test Environment

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
