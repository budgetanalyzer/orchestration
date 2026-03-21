# Security Hardening v2 Phase 1 Implementation Plan

## Goal

Implement Phase 1 of [Security Hardening Plan v2](./security-hardening-v2.md): remove shared application credentials, introduce least-privilege database/broker/cache identities, and make the development secret bootstrap clearly separable from production secret sourcing.

This plan is intentionally scoped so the work can be completed in one implementation session without hiding cross-repo fallout.

## Preconditions

Do not start Phase 1 work until all of the following are true:

- `./scripts/dev/verify-security-prereqs.sh` passes.
- The Kind cluster was created from `kind-cluster-config.yaml` with `disableDefaultCNI: true` and Calico installed.
- It is acceptable to rebuild local PostgreSQL, RabbitMQ, and Redis state. If local data must be preserved, stop and split migration work out of this session.
- The write scope remains:
  - orchestration repo: code, config, scripts, docs
  - sibling repos: configuration and documentation only
  - no sibling Java/TypeScript code changes

## Session Strategy

Treat each step below as one focused patch plus a short verification pass. Do not batch the whole phase into one blind edit.

Recommended order:

1. Secret contract and bootstrap seam
2. PostgreSQL hardening
3. RabbitMQ hardening
4. Redis ACLs and ext-authz support
5. Cross-repo local config alignment
6. Verification scripts
7. Documentation sweep

## Step 1: Freeze the Secret Contract and Bootstrap Seam

**Why first:** the current manifests mix secret consumption with local secret creation. If this is not cleaned up first, every later step gets reworked twice.

**Primary files**

- `Tiltfile`
- `.env.example`
- `setup.sh`
- `kubernetes/services/*/deployment.yaml`
- `kubernetes/infrastructure/postgresql/statefulset.yaml`
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`
- `kubernetes/infrastructure/redis/deployment.yaml`

**Work**

- Define the Phase 1 secret contract up front.
- Split bootstrap/admin secrets from application-consumption secrets.
- Use one secret per consuming service where practical instead of one large shared secret object.
- Keep secret names and keys stable so production deployers can replace Tilt-generated secrets with any external source later.
- Keep Tilt as the local secret producer only; manifests should reference secret names, not inline cleartext credentials.

**Target secret shape**

- PostgreSQL bootstrap secret:
  - superuser/admin username
  - superuser/admin password
  - per-service passwords needed by init logic
- PostgreSQL service secrets:
  - one secret each for transaction-service, currency-service, permission-service
  - keys: `username`, `password`, `url`
- RabbitMQ bootstrap secret:
  - admin username/password
  - per-service passwords or a generated definitions payload
- RabbitMQ service secrets:
  - one secret each for transaction-service and currency-service
  - keys: `host`, `amqp-port`, `username`, `password`, optionally `virtual-host`
- Redis bootstrap/ops secret:
  - local-only admin or ops username/password for probes and maintenance scripts
- Redis service secrets:
  - one secret each for session-gateway, ext-authz, currency-service
  - keys: `host`, `port`, `username`, `password`

**Exit criteria**

- No application credential is hardcoded in a manifest or ConfigMap.
- Secret consumption and local secret production are visibly separate concerns.
- `.env.example` documents every local Phase 1 credential the developer must supply or accept as a local default.

## Step 2: PostgreSQL Per-Service Users

**Primary files**

- `kubernetes/infrastructure/postgresql/configmap.yaml`
- `kubernetes/infrastructure/postgresql/statefulset.yaml`
- `Tiltfile`
- `kubernetes/services/transaction-service/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`
- `kubernetes/services/permission-service/deployment.yaml`
- `scripts/dev/reset-databases.sh`

**Work**

- Replace the static SQL that grants every database to `budget_analyzer`.
- Convert bootstrap logic to create dedicated users and ownership/grants for:
  - `transaction_service` -> `budget_analyzer`
  - `currency_service` -> `currency`
  - `permission_service` -> `permission`
- Remove hardcoded PostgreSQL bootstrap credentials from the StatefulSet and source them from the bootstrap secret defined in Step 1.
- Change service deployments to consume service-specific PostgreSQL secrets.
- Update `reset-databases.sh` so recreated databases are owned by the correct service user instead of `budget_analyzer`.

**Implementation notes**

- Expect to replace the current single SQL blob with a shell-driven init script or templated SQL so passwords can come from secrets.
- Do not preserve the current shared `postgresql-credentials` secret shape if it keeps all services on one identity.
- Keep the existing database names. Phase 1 is about identity separation, not schema redesign.

**Verification**

- `transaction_service` can connect to `budget_analyzer` and is denied on `currency` and `permission`.
- `currency_service` can connect to `currency` and is denied on the others.
- `permission_service` can connect to `permission` and is denied on the others.
- `scripts/dev/reset-databases.sh` still works after the credential split.

## Step 3: RabbitMQ Per-Service Users and Permissions

**Primary files**

- `kubernetes/infrastructure/rabbitmq/configmap.yaml`
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`
- `Tiltfile`
- `kubernetes/services/transaction-service/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`

**Work**

- Remove `guest/guest`.
- Bootstrap RabbitMQ users through a definitions file or equivalent secret-driven startup path rather than hardcoded config values.
- Create one user for `transaction-service` and one for `currency-service`.
- Scope permissions by vhost and regex permissions where possible.
- Update service deployment manifests to consume service-specific RabbitMQ secrets.

**Important constraint**

- Do not invent a multi-vhost topology unless the current event flows allow it.
- The source tree currently shows real RabbitMQ usage in `currency-service`, but not active bindings in `transaction-service`.
- If the shared vhost must remain for current messaging patterns, keep it and enforce least privilege with distinct users plus scoped `configure`/`write`/`read` regexes.

**Verification**

- `guest` access is gone.
- Each service can authenticate with its own credentials.
- Unauthorized exchanges/queues cannot be configured or consumed by the wrong user.
- RabbitMQ still starts cleanly with persisted storage after the definitions-based bootstrap.

## Step 4: Redis ACL Users and ext-authz Username Support

**Primary files**

- new Redis ACL material under `kubernetes/infrastructure/redis/`
- `kubernetes/infrastructure/redis/deployment.yaml`
- `Tiltfile`
- `kubernetes/services/session-gateway/deployment.yaml`
- `kubernetes/services/ext-authz/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`
- `ext-authz/config.go`
- `ext-authz/session.go`
- `scripts/dev/seed-ext-authz-session.sh`
- `scripts/dev/flush-redis.sh`

**Work**

- Replace `requirepass` with ACL-based auth.
- Create the required Redis users:
  - `session-gateway`
  - `ext-authz`
  - `currency-service`
- Add one local-only `redis-ops` or equivalent admin user for probes and developer maintenance scripts. Do not reuse an application identity for admin operations.
- Wire session-gateway and currency-service deployments to pass `SPRING_DATA_REDIS_USERNAME` and `SPRING_DATA_REDIS_PASSWORD`.
- Add `REDIS_USERNAME` support to ext-authz and use it in the Go Redis client options.
- Update Redis liveness/readiness probes and helper scripts so they authenticate with the ops/admin user.

**Required ACL scope**

- `session-gateway`: read/write only for Spring Session keys and ext-authz session keys
- `ext-authz`: read-only on ext-authz session keys and only the commands it needs
- `currency-service`: only its cache key namespace and only the cache commands it needs

**Implementation notes**

- Phase 1 should disable the open-ended shared password model, not layer ACLs on top of it.
- Expect docs and scripts that use `redis-cli` without auth or with `-a <password>` only to break until updated.

**Verification**

- Session Gateway can create/update session data.
- ext-authz can read session hashes but cannot write them.
- currency-service can use its cache namespace but cannot read or mutate session keys.
- Redis probes and maintenance scripts still work with the ops/admin user.

## Step 5: Align Sibling Local Configuration Defaults

Phase 1 is not finished if local `bootRun` paths still assume shared credentials that no longer exist.

**Expected sibling config touch points**

- `../transaction-service/src/main/resources/application.yml`
- `../currency-service/src/main/resources/application.yml`
- `../permission-service/src/main/resources/application.yml`
- `../session-gateway/src/main/resources/application.yml`

**Work**

- Replace shared local defaults where they would now fail against the hardened local infrastructure.
- Prefer environment-backed placeholders over hardcoded shared credentials.
- Add Redis username support to sibling config where the service may run directly against the hardened Redis instance.
- Keep these changes configuration-only. If any service would require Java code changes to honor the new credentials, stop and hand that repo back to the user explicitly.

**What to change**

- `transaction-service`: PostgreSQL username/password defaults
- `currency-service`: PostgreSQL username/password defaults, RabbitMQ username/password defaults, Redis username/password support
- `permission-service`: PostgreSQL username/password defaults
- `session-gateway`: Redis username/password support for direct local runs

**Verification**

- Each service can still run locally when pointed at the Tilt-managed infrastructure with the documented env vars.
- No sibling repo needs a code change just to consume the new credentials.

## Step 6: Add Focused Phase 1 Verification Scripts

**Primary files**

- `scripts/dev/reset-databases.sh`
- `scripts/dev/seed-ext-authz-session.sh`
- `scripts/dev/flush-redis.sh`
- new `scripts/dev/verify-phase-1-credentials.sh` or equivalent

**Work**

- Keep helper scripts usable after the credential split.
- Add one focused verifier script for Phase 1 runtime checks:
  - PostgreSQL user cannot access another service database
  - RabbitMQ user cannot access unauthorized resources
  - Redis ACL users are denied outside their command/key scope
  - ext-authz can start and query Redis with username/password auth

**Scope guardrail**

- Do not turn this session into a full DinD expansion of `tests/security-preflight`.
- A local verifier script is required in this phase.
- Extending containerized security suites is a good follow-up, but it is not the critical path for the first Phase 1 landing.

**Verification**

- The verifier passes on a clean `tilt up`.
- Failures are obvious and map directly to one Phase 1 control area.

## Step 7: Documentation Sweep Across Repos

Documentation updates are part of the implementation, not follow-up work.

**Orchestration docs that should be updated in the same session**

- `docs/plans/security-hardening-v2.md`
- `docs/development/database-setup.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/architecture/bff-api-gateway-pattern.md`
- `README.md` if setup or `.env` expectations materially change

**Sibling docs to review and update if configs change**

- `../session-gateway/README.md`
- `../currency-service/README.md`
- `../transaction-service/README.md`
- `../permission-service/README.md`

**What the docs must cover**

- New local `.env` variables and secret names
- Service-specific PostgreSQL users instead of `budget_analyzer` everywhere
- Removal of `guest/guest`
- Redis ACL auth examples using username plus password
- Updated troubleshooting commands for `psql`, `rabbitmqctl`, and `redis-cli`
- Any direct local run instructions that now require explicit env vars

**Guardrails**

- Do not touch `docs/archive/` or `docs/decisions/`.
- Do not leave stale examples that still show `guest/guest`, one shared Redis password, or one shared PostgreSQL user.

## Definition of Done for the Session

Phase 1 is complete for this session when all of the following are true:

1. Application-facing PostgreSQL credentials are per-service and enforced.
2. RabbitMQ no longer uses `guest/guest`, and each service uses its own credentials.
3. Redis uses ACL users instead of one shared password.
4. ext-authz supports Redis username/password auth.
5. Local secret generation is Tilt-only and clearly separated from manifest consumption.
6. Helper scripts still work after the hardening changes.
7. Local configuration defaults in sibling repos no longer assume shared credentials where that would break Phase 1.
8. The relevant documentation in orchestration and touched sibling repos is updated in the same work.

## Explicit Non-Goals

Do not expand this session into:

- external secret manager integration
- TLS for PostgreSQL, RabbitMQ, or Redis
- NetworkPolicy work from Phase 2
- Istio ingress/egress migration from Phase 3
- sibling service business-logic changes
