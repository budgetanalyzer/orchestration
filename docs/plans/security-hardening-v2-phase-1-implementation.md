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
  - superuser username (`postgres_admin` — renamed from `budget_analyzer` to eliminate identity collision)
  - superuser password
  - per-service passwords needed by init logic
- PostgreSQL service secrets:
  - one secret each for transaction-service, currency-service, permission-service
  - keys: `username`, `password`, `url`
- RabbitMQ bootstrap/admin secret:
  - admin username/password (with `administrator` tag for Management UI access)
  - per-service passwords or a generated definitions payload
- RabbitMQ service secrets:
  - one secret for currency-service (the only service with active RabbitMQ usage)
  - keys: `host`, `amqp-port`, `username`, `password`, optionally `virtual-host`
- Redis bootstrap/ops secret:
  - local-only admin or ops username/password for developer maintenance scripts and break-glass operations
- Redis service secrets:
  - one secret each for session-gateway, ext-authz, currency-service
  - keys: `host`, `port`, `username`, `password`

**Exit criteria**

- No application credential is hardcoded in a manifest or ConfigMap.
- Secret consumption and local secret production are visibly separate concerns.
- `.env.example` documents every local Phase 1 credential the developer must supply or accept as a local default.
- Sibling `application.yml` defaults are fail-closed: missing env vars must cause a connection failure, not a silent fallback to the old superuser identity. *(Implemented in Step 5, not Step 1. Listed here because it is part of the overall secret-contract guarantee, but the actual config changes depend on the identities created in Steps 2–4.)*

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

- Rename the bootstrap superuser from `budget_analyzer` to `postgres_admin`.
- Replace the static SQL init script with a shell init script (`.sh` in `/docker-entrypoint-initdb.d/`) that reads per-service passwords from environment variables sourced from Kubernetes Secrets. This is the standard pattern for the postgres Docker image and is the hardest technical piece of Step 2.
- Convert bootstrap logic to create dedicated users and ownership/grants for:
  - `transaction_service` -> `budget_analyzer`
  - `currency_service` -> `currency`
  - `permission_service` -> `permission`
- Add explicit `REVOKE CONNECT ON DATABASE ... FROM PUBLIC` for all three databases, then `GRANT CONNECT` only to the owning service user. Without this, PostgreSQL's default behavior allows any authenticated user to connect to any database — the verification step ("transaction_service is denied on currency") would silently pass the wrong way (the user can connect, it just won't own objects).
- Add `REVOKE CREATE ON SCHEMA public FROM PUBLIC` in each database, then grant `CREATE` only to the owning service user.
- Set `password_encryption = scram-sha-256` in PostgreSQL config and use `scram-sha-256` in `pg_hba.conf` for stronger credential storage.
- Remove hardcoded PostgreSQL bootstrap credentials from the StatefulSet and source them from the bootstrap secret defined in Step 1.
- Change service deployments to consume service-specific PostgreSQL secrets.
- Update the PostgreSQL readiness probe to use the admin user (`postgres_admin`) from the bootstrap secret.
- Update `reset-databases.sh` so recreated databases are owned by the correct service user instead of `budget_analyzer`.

**Implementation notes**

- Do not preserve the current shared `postgresql-credentials` secret shape if it keeps all services on one identity.
- Keep the existing database names. Phase 1 is about identity separation, not schema redesign.

**Verification**

- `transaction_service` can connect to `budget_analyzer` and is denied connection (not just denied object access) on `currency` and `permission`.
- `currency_service` can connect to `currency` and is denied connection on the others.
- `permission_service` can connect to `permission` and is denied connection on the others.
- `psql -U postgres_admin` can still connect to all databases (break-glass path).
- `scripts/dev/reset-databases.sh` still works after the credential split.

## Step 3: RabbitMQ Per-Service Users and Permissions

**Primary files**

- `kubernetes/infrastructure/rabbitmq/configmap.yaml`
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`
- `Tiltfile`
- `kubernetes/services/currency-service/deployment.yaml`
- `kubernetes/services/transaction-service/deployment.yaml` (remove dead RabbitMQ wiring only)

**Work**

- Remove `guest/guest`.
- Bootstrap RabbitMQ users through a definitions file or equivalent secret-driven startup path rather than hardcoded config values.
- Create one user for `currency-service` (the only service with active RabbitMQ usage).
- Create one admin/ops user (`rabbitmq-admin`) with `administrator` tag for Management UI access.
- Do **not** create a RabbitMQ user for transaction-service — it has zero RabbitMQ code. Remove the dead wiring: RabbitMQ env vars from `transaction-service/deployment.yaml` and the Tilt dependency on RabbitMQ.
- Scope permissions by vhost and regex permissions where possible.
- Update currency-service deployment manifest to consume its RabbitMQ secret.

**Important constraint**

- Do not invent a multi-vhost topology unless the current event flows require it. Currency-service is the only RabbitMQ consumer — it publishes to `currency.created` and consumes from the same exchange (internal feedback loop).
- If the shared vhost must remain, enforce least privilege with a distinct user plus scoped `configure`/`write`/`read` regexes.

**Developer workflow note**

RabbitMQ's definitions file is imported only at first startup. If definitions change (adding/removing users, changing permissions), the RabbitMQ PVC must be deleted and recreated. Document this:
```bash
kubectl delete pvc rabbitmq-data-rabbitmq-0 -n infrastructure
# then restart RabbitMQ via tilt
```

**Verification**

- `guest` access is gone.
- `currency-service` can authenticate with its own credentials and access its exchanges/queues.
- `rabbitmq-admin` can access the Management UI.
- The admin user can verify permission scoping via `rabbitmqctl list_permissions` or the management API.
- Unauthorized exchanges/queues cannot be configured or consumed by the wrong user (verify with `rabbitmqctl` or the management API — unlike PostgreSQL/Redis, RabbitMQ permission denial requires explicit tooling to test).
- RabbitMQ still starts cleanly with persisted storage after the definitions-based bootstrap.
- transaction-service starts without RabbitMQ wiring and functions normally.

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
- Create the required Redis users with concrete ACL rules. The `ext-authz` rules are confirmed from source; `session-gateway` intentionally uses broad command access with key isolation; `currency-service` starts with a cache-focused allow-list that must be validated with runtime tests because Spring Cache/Lettuce hides some concrete Redis commands behind framework abstractions.

```
# session-gateway: Spring Session uses a wide range of internal commands (hash ops,
# set ops, key ops, pub/sub for session events). Restricting to specific commands
# risks breakage on Spring Session upgrades. Use +@all with key-pattern isolation.
user session-gateway on >PASSWORD ~spring:session:* ~extauthz:session:* +@all

# ext-authz: read-only on ext-authz sessions + health check
user ext-authz on >PASSWORD ~extauthz:session:* +hgetall +ping +auth +hello +info

# currency-service: initial cache-focused allow-list on its namespace only.
# This must be validated in runtime tests and expanded only if Spring Cache/Lettuce
# requires an additional command that is not obvious from application code.
user currency-service on >PASSWORD ~currency-service:* +get +set +del +keys +scan +ping +auth +hello +ttl +pttl +expire +exists +type +object

# redis-ops: admin for maintenance scripts and break-glass operations
user redis-ops on >PASSWORD ~* +@all

# default: restricted to PING and AUTH only (do not disable)
user default on >PASSWORD ~* +ping +auth
```

- Wire session-gateway and currency-service deployments to pass `SPRING_DATA_REDIS_USERNAME` and `SPRING_DATA_REDIS_PASSWORD`. Spring Boot 3.x auto-configures `spring.data.redis.username` natively — no Java code changes needed.
- Add `REDIS_USERNAME` support to ext-authz and use it in the Go Redis client `Options.Username`. This is the only code change required for Redis username support.
- Keep Redis liveness/readiness probes on the restricted `default` user path for Phase 1, and update helper scripts to authenticate with the `redis-ops` user.

**Probe authentication mechanism**

Disabling the `default` user entirely breaks probes: `REDISCLI_AUTH` only provides a password, but Redis ACL requires `AUTH <username> <password>`. Kubernetes exec probes do not support env var expansion in command arrays.

Recommended approach for Phase 1: keep `default` user enabled but restricted to `+ping +auth` only. This allows existing probe commands (`redis-cli ping`) to continue working while preventing the default user from accessing any data. Use `redis-ops` for explicit maintenance actions and scripts, not the health probes.

**Key design decision for session-gateway**

Spring Session uses a wide range of Redis commands internally. The value of ACLs for session-gateway is in **key-pattern isolation** (`~spring:session:* ~extauthz:session:*`), not command restriction. Using `+@all` with key patterns is the right tradeoff — it prevents session-gateway from touching currency cache keys while avoiding breakage from Spring Session internal changes.

**Implementation notes**

- Phase 1 should disable the open-ended shared password model, not layer ACLs on top of it.
- Expect docs and scripts that use `redis-cli` without auth or with `-a <password>` only to break until updated.
- Treat the `currency-service` ACL command list as an initial least-privilege baseline, not a source-proven final set. Runtime verification is required before calling it complete.

**Verification**

- Session Gateway can create/update session data.
- ext-authz can read session hashes but cannot write them.
- currency-service can use its cache namespace but cannot read or mutate session keys.
- Redis probes still work via the restricted `default` user, and maintenance scripts authenticate with `redis-ops`.
- Break-glass: `redis-ops` user can run `FLUSHALL` and other admin commands.

## Step 5: Align Sibling Local Configuration Defaults

Phase 1 is not finished if local `bootRun` paths still assume shared credentials that no longer exist.

**Expected sibling config touch points**

- `../transaction-service/src/main/resources/application.yml`
- `../currency-service/src/main/resources/application.yml`
- `../permission-service/src/main/resources/application.yml`
- `../session-gateway/src/main/resources/application.yml`

**Work**

- Replace shared local defaults with fail-closed placeholders. The pattern is `${ENV_VAR:}` (empty default) for passwords — a developer who doesn't set env vars should get a connection failure, not a silent fallback to the old superuser identity.
- For usernames, default to the per-service identity: `${SPRING_DATASOURCE_USERNAME:transaction_service}`.
- Add Redis username support to sibling config where the service may run directly against the hardened Redis instance (`spring.data.redis.username` placeholder).
- Add RabbitMQ username/password placeholders to currency-service config.
- Keep these changes configuration-only. If any service would require Java code changes to honor the new credentials, stop and hand that repo back to the user explicitly.

**What to change**

- `transaction-service`: PostgreSQL username default -> `transaction_service`, password default -> empty (fail-closed)
- `currency-service`: PostgreSQL defaults (per-service, fail-closed), RabbitMQ username/password placeholders, Redis username placeholder
- `permission-service`: PostgreSQL username default -> `permission_service`, password default -> empty (fail-closed)
- `session-gateway`: Redis username placeholder for direct local runs

**What NOT to change**

- transaction-service RabbitMQ config — there is none (no RabbitMQ code exists in this service)

**Verification**

- Each service can still run locally when pointed at the Tilt-managed infrastructure with the documented env vars.
- Running `./gradlew bootRun` without env vars fails with a connection error, not a successful superuser connection.
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

  **Positive tests (authorized access works):**
  - Each PostgreSQL service user can connect to its own database
  - currency-service RabbitMQ user can access its exchanges/queues
  - Each Redis ACL user can perform its authorized operations
  - ext-authz can start and query Redis with username/password auth

  **Negative tests (unauthorized access is denied):**
  - PostgreSQL: `transaction_service` is denied `CONNECT` to `currency` and `permission` databases (use `psql -U transaction_service -d currency` and verify connection refused, not just object access denied)
  - RabbitMQ: currency-service user cannot configure/write unauthorized exchanges (use `rabbitmqctl` or the management API to verify — unlike PostgreSQL/Redis, RabbitMQ permission denial requires explicit tooling)
  - Redis: each ACL user is denied outside their key pattern and command scope (use `redis-cli --user <user> --pass <pass>`)

  **Break-glass tests (admin/ops users still work):**
  - `postgres_admin` can connect to all databases
  - `redis-ops` can run `FLUSHALL` and admin commands
  - `rabbitmq-admin` can access the Management UI and run `rabbitmqctl list_permissions`

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
- PostgreSQL superuser rename from `budget_analyzer` to `postgres_admin`
- Service-specific PostgreSQL users instead of `budget_analyzer` everywhere
- Removal of `guest/guest` and the new RabbitMQ admin user
- Redis ACL auth examples using username plus password
- Updated troubleshooting commands for `psql`, `rabbitmqctl`, and `redis-cli`
- Any direct local run instructions that now require explicit env vars
- RabbitMQ PVC deletion workflow when definitions change
- Removal of transaction-service RabbitMQ references (dead wiring cleanup)

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
