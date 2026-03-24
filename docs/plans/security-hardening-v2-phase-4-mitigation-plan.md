# Phase 4: In-cluster Transport Encryption - Mitigation Plan

## Context

This plan captures the follow-on work from a review of:

- `docs/plans/security-hardening-v2.md`
- `docs/plans/security-hardening-v2-phase-4-implementation.md`
- the uncommitted Phase 4 transport-encryption changes in this repository

The review found three concrete gaps:

1. The Phase 4 completion gate proves Redis and PostgreSQL client-side TLS validation, but RabbitMQ is only verified by listener inspection. That is weaker than the implementation-plan requirement that all infrastructure clients verify the server certificate with hostname validation.
2. Operator documentation still contains stale pre-Phase-4 plaintext troubleshooting paths.
3. The direct local-run documentation for `ext-authz` documents the wrong Redis environment contract.

This mitigation plan is split into:

- an immediate correctness track for the current Phase 4 rollout
- a production-grade follow-on track for certificate lifecycle and TLS policy hardening

The security-hardening-v2 plan header still applies: **"No backward compatibility required. Rip and replace."**

---

## Goals

- Make the Phase 4 completion gate prove RabbitMQ client-side certificate validation, including hostname validation.
- Make RabbitMQ hostname verification explicit in client configuration rather than relying on framework defaults.
- Remove stale plaintext operational guidance from the current developer and runbook docs.
- Correct the `ext-authz` local Redis configuration contract in documentation.
- Capture the next production-grade hardening steps for certificate lifecycle automation and TLS protocol policy.

## Non-goals

- No sibling service code changes. Sibling repo work is limited to configuration and documentation.
- No new product features.
- No attempt to solve data ownership, multi-tenancy, or cross-service user scoping.
- No migration of the RabbitMQ management UI from HTTP to HTTPS in local development; that path remains internal-only.

---

## Workstream A: Immediate Phase 4 Correctness

### Session 1: RabbitMQ Client-Path Proof

**Goal**: Upgrade the Phase 4 verifier so RabbitMQ transport security is proven by a real client TLS handshake, not only by broker listener state.

### Required updates

- Update `scripts/dev/verify-phase-4-transport-encryption.sh`
- Add a disposable RabbitMQ probe pod in `default` that:
  - has sidecar injection disabled
  - mounts `infra-ca`
  - has network-policy access only to `rabbitmq.infrastructure:5671`
  - includes a TLS client tool such as `openssl`
- Add a positive AMQPS test:
  - connect to `rabbitmq.infrastructure:5671`
  - trust `infra-ca`
  - require hostname validation for `rabbitmq.infrastructure`
  - fail the script unless certificate verification succeeds
- Add at least one negative AMQPS test:
  - wrong CA bundle fails, and/or
  - hostname mismatch fails
- Keep the existing `rabbitmqctl listeners` checks as secondary proof that the broker exposes `5671/ssl` and does not expose plaintext `5672`

### Why this is required

The current implementation-plan context says Phase 4 "configures all clients to verify the server certificate with hostname validation." Listener presence does not prove that `currency-service`-class clients would reject an untrusted or mismatched broker certificate.

### Files

- **Modify**: `scripts/dev/verify-phase-4-transport-encryption.sh`
- **Modify**: `scripts/README.md`

### Verification

```bash
./scripts/dev/verify-phase-4-transport-encryption.sh
```

Success means the verifier now fails when RabbitMQ trust or hostname validation is broken, instead of passing on listener state alone.

---

### Session 2: Explicit RabbitMQ Hostname Verification

**Goal**: Make the RabbitMQ client verification semantics explicit in `currency-service` configuration instead of relying on Spring Boot defaults.

### Required updates

- Update `/workspace/currency-service/src/main/resources/application.yml`
- Under `spring.rabbitmq.ssl`, set the equivalent of:
  - server-certificate validation enabled
  - hostname verification enabled
- Preserve the existing SSL bundle wiring through `infra-ca`
- Update `/workspace/currency-service/README.md` if the direct `bootRun` instructions need to mention that hostname verification is mandatory and the CA path must match the broker certificate SANs

### Why this is required

Defaults are easier to weaken accidentally during framework upgrades or config drift. The Phase 4 transport-TLS contract should be explicit in configuration.

### Files

- **Modify (sibling config-only)**: `/workspace/currency-service/src/main/resources/application.yml`
- **Modify (sibling docs-only, if needed)**: `/workspace/currency-service/README.md`

### Verification

- `currency-service` starts successfully with the TLS-only RabbitMQ listener on `5671`
- Spring Cloud Stream bindings come up
- the Phase 4 verifier passes the new RabbitMQ client-path checks

---

### Session 3: Documentation Consistency Fixes

**Goal**: Remove stale plaintext operational guidance and correct the `ext-authz` local Redis contract.

### Required updates

#### `docs/runbooks/tilt-debugging.md`

- Change the RabbitMQ infrastructure port reference from `5672`/AMQP to `5671`/AMQPS
- Update any PostgreSQL "connect directly" examples to use TLS-aware `psql` commands with `sslmode=verify-full` and the `infra-ca` PEM
- Re-scan the rest of the runbook for stale plaintext Redis/PostgreSQL/RabbitMQ instructions introduced by the Phase 4 cutover

#### `docs/development/local-environment.md`

- Replace the `ext-authz` direct-run guidance that mentions `REDIS_HOST` and `REDIS_PORT`
- Document the actual contract used by the binary:
  - `REDIS_ADDR=localhost:6379`
  - `REDIS_USERNAME=ext-authz`
  - `REDIS_EXT_AUTHZ_PASSWORD=...`
  - `REDIS_TLS=true`
  - `REDIS_CA_CERT=<path to infra-ca PEM>`

#### Additional doc consistency pass

- Re-check the current developer/operator docs touched by Phase 4 for:
  - stale `5672` data-plane references
  - stale plaintext PostgreSQL examples
  - stale plaintext Redis examples

### Files

- **Modify**: `docs/runbooks/tilt-debugging.md`
- **Modify**: `docs/development/local-environment.md`
- **Modify (if needed)**: `README.md`, `scripts/README.md`, or other nearby Phase 4 docs that still contradict the transport-TLS cutover

### Verification

```bash
rg -n '\\b5672\\b|psql -h localhost|REDIS_HOST=localhost|REDIS_PORT=6379' \
  README.md docs scripts -g '!docs/archive/**' -g '!docs/decisions/**'
```

The remaining matches should be either intentionally historical, explicitly marked non-current, or unrelated to the in-cluster RabbitMQ/Redis/PostgreSQL transport path.

---

## Workstream B: Production-Grade Follow-on Hardening

These sessions are not required to close the immediate review findings, but they should be planned next if this transport-TLS pattern is being carried toward production guidance.

### Session 4: Certificate Lifecycle Automation

**Goal**: Replace manual certificate bootstrap with an automated production-grade certificate lifecycle.

### Required design work

- Add a production-oriented certificate-management design using cert-manager or equivalent internal PKI automation
- Define:
  - issuer model
  - certificate subjects/SANs
  - renewal window
  - secret rotation behavior
  - workload rollout or reload strategy after rotation
- Keep local Kind bootstrap separate from the production trust model
- Document the boundary clearly so `setup-infra-tls.sh` remains a local-development-only tool

### Deliverables

- new or updated architecture documentation under `docs/architecture/`
- follow-on manifest/configuration plan for production deployments

---

### Session 5: TLS Protocol and Cipher Policy

**Goal**: Make the TLS protocol floor explicit across Redis, PostgreSQL, and RabbitMQ instead of inheriting image defaults.

### Required design work

- Redis:
  - pin minimum TLS version to `TLSv1.2` or higher
- PostgreSQL:
  - set explicit SSL minimum protocol version where supported
- RabbitMQ:
  - restrict listener versions to `TLSv1.2+`
- Decide whether cipher-suite pinning is desirable or whether protocol floors are sufficient for the reference architecture
- Extend the Phase 4 verifier with protocol-floor checks if practical

### Deliverables

- manifest/configuration follow-on plan
- updated transport-security documentation
- verifier extensions if the repo chooses to enforce protocol-floor proof at runtime

---

## File Change Summary

### Immediate track

- `scripts/dev/verify-phase-4-transport-encryption.sh`
- `scripts/README.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/development/local-environment.md`
- `/workspace/currency-service/src/main/resources/application.yml`
- `/workspace/currency-service/README.md` (if needed)

### Production-grade follow-on track

- likely `docs/architecture/*`
- potentially `kubernetes/infrastructure/*`
- potentially `kubernetes/services/currency-service/deployment.yaml`
- possibly future production overlays or deployment documentation

---

## Success Criteria

### Immediate track success

- Phase 4 verification includes a RabbitMQ positive client-path proof with trusted CA and hostname validation
- Phase 4 verification includes a RabbitMQ negative client-path proof
- `currency-service` explicitly enables RabbitMQ server-certificate validation and hostname verification
- Current developer/operator docs no longer instruct users to use RabbitMQ `5672` for the data plane
- Current developer/operator docs no longer present plaintext PostgreSQL guidance for the transport-TLS path
- Current developer/operator docs correctly describe `ext-authz` local Redis configuration using `REDIS_ADDR`

### Production-grade follow-on success

- There is a documented path away from manual host-generated infrastructure certs for production
- TLS minimum-version policy is explicit for Redis, PostgreSQL, and RabbitMQ
- Certificate rotation and trust distribution are documented as part of the platform design rather than as manual operator steps

---

## Execution Order

Execute the immediate track in order:

1. Session 1: RabbitMQ client-path proof
2. Session 2: explicit RabbitMQ hostname verification
3. Session 3: documentation consistency fixes

The production-grade follow-on track can be planned after the immediate track lands:

4. Session 4: certificate lifecycle automation
5. Session 5: TLS protocol and cipher policy

---

## Final Verification

After the immediate track is implemented:

```bash
./scripts/dev/check-tilt-prerequisites.sh
tilt up
./scripts/dev/verify-phase-4-transport-encryption.sh
./scripts/dev/verify-phase-1-credentials.sh
./scripts/dev/verify-phase-2-network-policies.sh
```

Review the current docs once more after the verifier passes to ensure the Phase 4 operator story is consistent end to end.
