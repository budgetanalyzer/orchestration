# Phase 4 Review Fix Plan

## Context

This plan captures the fixes required after a review of the Phase 4 transport-encryption work against:

- `docs/plans/security-hardening-v2.md`
- `docs/plans/security-hardening-v2-phase-4-implementation.md`
- `docs/plans/security-hardening-v2-phase-4-mitigation-plan.md`
- the current Phase 4 manifests, scripts, and docs in this repository

Scope is intentionally limited to work that should be done by the end of Phase 4. It does **not** include the mitigation plan's production follow-on work for certificate lifecycle automation or TLS protocol-floor policy.

## Review Summary

The infrastructure TLS rollout is mostly present:

- Redis, PostgreSQL, and RabbitMQ are serving TLS.
- Redis and PostgreSQL clients are wired for CA-based validation.
- The cluster is healthy enough for the transport-TLS verifier to run meaningful checks.

But Phase 4 is **not complete as intended** because the completion gate and nearby docs do not match the implementation plans:

1. `scripts/dev/verify-phase-4-transport-encryption.sh` has a broken RabbitMQ listener check and still does not prove RabbitMQ client-side TLS validation.
2. The Phase 4 verifier's Phase 2 regression step calls a stale verifier that still assumes Envoy Gateway, so it fails before assertions run in the current Istio-ingress topology.
3. `currency-service` RabbitMQ SSL settings are still implicit; the mitigation plan required explicit server-certificate and hostname verification semantics.
4. Developer/operator docs still contain stale pre-Phase-4 guidance.

## Workstream 1: Repair the Phase 4 Completion Gate

### Goal

Make `./scripts/dev/verify-phase-4-transport-encryption.sh` a working completion gate that proves the transport-TLS guarantees it claims to prove.

### Required updates

- Replace the broken `rabbitmqctl listeners` check with a supported broker inspection command.
  - Prefer `rabbitmq-diagnostics listeners` or a stable `rabbitmqctl status` parser.
- Add a disposable RabbitMQ probe in `default` with:
  - sidecar injection disabled
  - mounted `infra-ca`
  - least-privilege network-policy access to `rabbitmq.infrastructure:5671`
- Add RabbitMQ positive client-path verification:
  - trusted CA
  - expected hostname
  - connection succeeds
- Add RabbitMQ negative verification:
  - wrong CA fails, and/or
  - hostname mismatch fails
- Keep the listener inspection as secondary proof only.
- Update `scripts/README.md` so it describes the verifier accurately.

### Acceptance criteria

- `./scripts/dev/verify-phase-4-transport-encryption.sh` passes in a healthy cluster.
- Breaking RabbitMQ CA trust or hostname validation makes the verifier fail.
- Redis and PostgreSQL checks remain unchanged or stronger.

## Workstream 2: Restore Valid Phase 2 Regression Coverage

### Goal

Make the Phase 4 regression step validate the current network-policy posture instead of invoking an obsolete topology-specific verifier.

### Required updates

- Update `scripts/dev/verify-phase-2-network-policies.sh` for the post-Phase-3 Istio ingress topology.
  - Remove the `envoy-gateway-system` probe assumptions.
  - Assert the ingress-facing paths that still belong to Phase 2 network-policy scope in the current topology.
  - Keep the infrastructure allow/deny assertions that Phase 4 depends on, especially `currency-service -> rabbitmq:5671`.
- If preserving a historical Envoy-era verifier is useful, split it into an archived or clearly legacy script and keep the active verifier aligned with the current platform.
- Ensure the Phase 4 verifier calls only the current, supported regression script.

### Acceptance criteria

- `./scripts/dev/verify-phase-2-network-policies.sh` runs successfully in the current Istio-ingress environment.
- The Phase 4 verifier's regression section passes on a healthy cluster and fails when a relevant Phase 2/4 policy edge is broken.

## Workstream 3: Make RabbitMQ Client Verification Explicit

### Goal

Implement the mitigation-plan requirement that `currency-service` states its RabbitMQ TLS verification behavior explicitly instead of relying on framework defaults.

### Required updates

- Update [`../currency-service/src/main/resources/application.yml`](/workspace/currency-service/src/main/resources/application.yml) to set the Spring RabbitMQ SSL properties that make:
  - server-certificate validation explicit
  - hostname verification explicit
- Update [`../currency-service/README.md`](/workspace/currency-service/README.md) if direct `bootRun` requires additional env vars or notes about hostname verification and SAN expectations.
- Add a small verification note to the Phase 4 docs describing the exact RabbitMQ client contract.

### Acceptance criteria

- `currency-service` still starts against the TLS-only broker.
- The config itself makes certificate validation and hostname verification explicit.
- The Phase 4 verifier covers the broker-side trust/hostname path.

## Workstream 4: Finish the Documentation Consistency Pass

### Goal

Remove stale plaintext and pre-cutover guidance from the current developer/operator docs.

### Required updates

- Update [`docs/runbooks/tilt-debugging.md`](/workspace/orchestration/docs/runbooks/tilt-debugging.md):
  - RabbitMQ data-plane port `5671`, not `5672`
  - TLS-aware PostgreSQL examples using `sslmode=verify-full`
- Update [`docs/development/local-environment.md`](/workspace/orchestration/docs/development/local-environment.md):
  - `ext-authz` local Redis contract should use `REDIS_ADDR=localhost:6379`
  - keep `REDIS_USERNAME`, `REDIS_EXT_AUTHZ_PASSWORD`, `REDIS_TLS=true`, and `REDIS_CA_CERT`
- Re-scan `README.md`, `docs/`, and `scripts/README.md` for stale:
  - `5672` data-plane references
  - plaintext PostgreSQL examples
  - outdated `ext-authz` env names
- Operator contract decision for infrastructure TLS bootstrap:
  - `setup.sh` remains responsible for calling `setup-infra-tls.sh`
  - `./scripts/dev/setup-infra-tls.sh` stays available as the standalone host-side regeneration path

### Acceptance criteria

- A targeted grep for stale Phase 4 instructions only returns intentional historical references in plan files.
- The current docs describe the same operator workflow and the same runtime env contracts the code actually uses.

## Verification Checklist

After the fixes land:

```bash
./scripts/dev/check-tilt-prerequisites.sh
./scripts/dev/verify-phase-1-credentials.sh
./scripts/dev/verify-phase-2-network-policies.sh
./scripts/dev/verify-phase-4-transport-encryption.sh
rg -n '\\b5672\\b|psql -h localhost|REDIS_HOST=localhost|REDIS_PORT=6379' \
  README.md docs scripts ../session-gateway/README.md ../currency-service/README.md \
  -g '!docs/archive/**' -g '!docs/decisions/**'
```

Expected result:

- all three verification scripts pass in a healthy cluster
- the grep only hits intentional plan-history references, not active operator guidance
