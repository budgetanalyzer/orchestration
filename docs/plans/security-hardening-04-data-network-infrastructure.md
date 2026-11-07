# Security Hardening 04: Data, Network and Infrastructure

**Status:** Draft for iteration. Do not run until D5 is settled.

This is plan 04 of five that together implement every finding from the four 2026-11-01 security
reviews that holds up against the code and that no review disputes, with the decisions in the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document applied.
This plan sets a measured Redis memory budget, excludes private destinations from the egress
gateway, requires TLS on the PostgreSQL server side, separates migration roles from runtime roles,
and moves to a supported RabbitMQ series.
Phase numbers without a plan refer to this plan.

**Order:** 04 of 5

**Depends on:** plans 02.1-02.8, because Phase 1 measures the final session records. Runs after plan 03.

**Repositories:** orchestration.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

## Decisions

| # | Decision | Recommendation | Why it matters | Status |
| --- | --- | --- | --- | --- |
| D5 | Where the migration credential lives | In the service pod, as a separate credential | This stops DDL through the runtime connection, including SQL injection. It does not stop code execution in the pod, which can read both credentials. An out-of-process migrator would, at much higher cost. | Open |

## Plan-wide rules

- No staging or production access, no certificate generation, and no git write operations unless
  the user asks.
- (added per user direction) No production environment or production data exists. Discarding
  local state is acceptable: sessions, Redis keys, OAuth state, database contents and broker
  volumes. Do not write migration, dual-format or backward-compatibility code. Reset instead,
  with `./scripts/ops/flush-redis.sh`, `scripts/ops/reset-databases.sh` or by recreating the
  volume, and document any reset an existing local cluster needs.
- Each phase works in its declared workspace only. Follow that repository's `AGENTS.md`.
- Treat review claims as leads. Re-check them against the code before relying on them.
- Before any cluster mutation, apply the `kind-kind` checks in the orchestration `AGENTS.md`.
- Phases marked **Live** need a running stack. In orchestration phases, run
  `./scripts/bootstrap/check-local-runtime.sh` and `tilt up`. If the stack cannot be started, stop
  and report; do not substitute static evidence.
- Do not edit `docs/decisions/` or `docs/archive/`.
- Do not edit this plan during a run, because the runner stops launching phases when it changes.
- Record measurements and results in `docs/research/security-consensus-hardening-evidence.md`. A
  phase in a sibling repository records them in that repository's `docs/` folder, and plan 05,
  Phase 3 collects the links.

**Orchestration static gate**, for every orchestration phase:

```bash
bash -n <changed-script> && shellcheck <changed-script>
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

## Contested decisions applied

- [#9, per-caller egress identity](../research/security-review-contested-issues-2026-11-02.md#9-per-caller-egress-identity):
  the egress identity deferral is kept. Phase 2's private-range exclusions are independent of it.
- [#2, Redis enumeration](../research/security-review-contested-issues-2026-11-02.md#2-redis-enumeration-after-hashing):
  a Redis split stays optional (Phase 1 non-goal).
- [Settled by checking the code](../research/security-review-contested-issues-2026-11-02.md#settled-by-checking-the-code):
  the 70–75% `maxmemory` figure is discarded, so Phase 1 keeps its measurement requirement. The
  PostgreSQL rejection test stands (Phase 3). RabbitMQ 3.13 is out of community support, so verify
  the target series' support at implementation time (Phase 5).

## Phase 1: Set an explicit Redis memory budget (Live)

### Workspace

.

### Goal

Replace unbounded Redis memory with a measured budget that keeps auth data out of eviction.

### Scope

`kubernetes/infrastructure/redis/start-redis.sh`, the pod limit only if measurement requires it, and
`docs/architecture/security-architecture.md:639`.

### Non-goals

Splitting Redis.

### Required context

R1 finding 8; R2's capacity estimate; R4's qualifications on `maxmemory` and `noeviction`.

### Execution steps

1. Measure session, index and maximum-size OAuth-state record sizes, base RSS, and AOF rewrite
   overhead on the pinned Redis image. This phase follows the cutover so it measures the final
   records: hashed keys, the `returnUrl` cap and the binding field.
2. Set `--maxmemory` from that data, leaving headroom below the 256Mi limit. Do not adopt R2's
   70-75% unless the measurements support it.
3. Set `--maxmemory-policy noeviction`.
4. In a disposable environment, fill Redis and record login, heartbeat and API behaviour under
   rejected writes, and recovery afterwards.
5. Replace the `allkeys-lru` claim. Put the measurements and the limits of the budget in the
   evidence file.

### Implementation notes

- `noeviction` turns a crash into failed writes, so anonymous OAuth-state growth can still block
  logins. The plan 02.2, Phase 1 lifetime lowers the ceiling per address to about 625 live records, but this
  remains a known gap.
- `maxmemory` is not an RSS limit (R4).
- The shared cache is capped along with auth data. If its growth threatens the budget, report it
  rather than changing the policy.
- Restart Redis to apply the change, as in plan 01, Phase 6.

### Validation

Orchestration static gate, and `CONFIG GET maxmemory*` as `redis-ops` after a restart. Run
`verify-credential-isolation.sh`.

### Completion criteria

The budget is backed by recorded measurements, and failure behaviour under exhaustion is documented.

## Phase 2: Exclude private destinations from the egress gateway (Live)

### Workspace

.

### Goal

Stop the egress gateway's NetworkPolicy allowing any destination on port 443, as a layer beneath the
Envoy host rules.

### Scope

`kubernetes/network-policies/istio-egress-allow.yaml`, `scripts/smoketest/verify-network-policies.sh`,
and the nearest docs.

### Non-goals

Per-caller egress identity and any `ISTIO_MUTUAL` change (amended per contested #9: deferred as
coordinated design work).

### Required context

R1 "Treat egress controls as layered containment"; `kubernetes/istio/egress-routing.yaml`.

### Execution steps

1. In `allow-istio-egress-external-egress`, replace the port-only rule with an `ipBlock` of
   `0.0.0.0/0` that excepts `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16` and
   `100.64.0.0/10`. Keep port 443.
2. Cover IPv6 the same way if the cluster has it.
3. Add a static check for the exclusions.
4. Prove from the gateway pod that the Kubernetes API service is unreachable on 443.
5. Confirm a real login reaches Auth0 and a currency import reaches FRED.

### Implementation notes

R1 qualifies this with "where the hosting environment supports them". Calico enforces `except`
locally. Record that a hosted CNI must too. This limits where the gateway can connect; it does not
tell the gateway which service is calling.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-network-policies.sh`, and
`./scripts/smoketest/verify-istio-ingress.sh`.

### Completion criteria

The gateway cannot reach private ranges on 443, and both external integrations still work.

## Phase 3: Require TLS on the PostgreSQL server side (Live)

### Workspace

.

### Goal

Make PostgreSQL refuse plaintext connections, instead of relying on clients to request TLS.

### Scope

`kubernetes/infrastructure/postgresql/`, `scripts/smoketest/verify-transport-encryption.sh`, and the
nearest docs.

### Non-goals

Client configuration, which already uses `sslmode=verify-full`, and certificate generation.

### Required context

R2 finding H; R3 "Postgres `hostssl`"; `docs/architecture/security-architecture.md`.

### Execution steps

1. Add a ConfigMap holding a `pg_hba.conf` with a `local` scram rule and `hostssl` scram rules for
   IPv4 and IPv6, and no `host` rules.
2. Mount it read-only, and pass `-c hba_file=<path>` in the container args.
3. Confirm the probes and `scripts/ops/reset-databases.sh` still work.
4. Add a negative check to `verify-transport-encryption.sh`: `sslmode=disable` must fail with no
   `pg_hba.conf` entry, and `verify-full` must still connect.

### Implementation notes

- Use `hba_file` because `PGDATA/pg_hba.conf` is written only on an empty volume, so changing it
  would not reach an existing cluster.
- Keep this file out of the `postgresql-init` ConfigMap. That one is mounted whole into
  `/docker-entrypoint-initdb.d`.
- The `-h 127.0.0.1` probes use the default `sslmode=prefer`, so they keep working over TLS.
- `statefulset.yaml:71` only sets the auth method (R3 corrects R2's citation). The actual `host` rule
  comes from the image's default.

### Validation

Orchestration static gate and `./scripts/smoketest/verify-transport-encryption.sh`. Confirm all three
services start and serve requests.

### Completion criteria

A plaintext connection is refused by the server, and every service still connects.

## Phase 4: Separate migration roles from runtime roles (Live)

### Workspace

.

### Goal

Stop each service's runtime database role from owning its database or changing its schema.

### Scope

`kubernetes/infrastructure/postgresql/configmap.yaml`, the three service deployments, `Tiltfile`,
`scripts/lib/secrets-only-expected-keys.txt`, `scripts/ops/`, a runtime check, and the nearest docs.

### Non-goals

An out-of-process migrator, per D5, and service code.

### Required context

R2 finding H; `scripts/ops/reset-databases.sh`; `kubernetes/production/README.md`.

### Execution steps

1. For each database, add a `<service>_migrator` role that owns the database and schema. Reduce the
   runtime role to `SELECT`, `INSERT`, `UPDATE` and `DELETE` on tables and `USAGE, SELECT` on
   sequences, with `ALTER DEFAULT PRIVILEGES` so new tables stay reachable.
2. Update `01-init-databases.sh` and `scripts/ops/reset-databases.sh`.
3. (amended per user direction) Reset existing volumes with the
   updated `scripts/ops/reset-databases.sh`, or by recreating the PostgreSQL volume, and document that
   one-time reset for existing local clusters. Do not add an ownership-migration script.
4. Add the migrator credentials to the Tiltfile, the bootstrap secret and
   `secrets-only-expected-keys.txt`.
5. Set `SPRING_FLYWAY_USER` and `SPRING_FLYWAY_PASSWORD` on the three deployments.
6. Add a runtime check that each runtime role is refused `CREATE TABLE`, `ALTER TABLE` and
   `DROP TABLE`, and that normal reads and writes work.
7. Update the production secrets contract in `kubernetes/production/README.md`.

### Implementation notes

- (amended per user direction) Init scripts run
  only on an empty data directory, so an existing volume must be reset (step 3).
- All three services set `ddl-auto: validate`, and their schemas come from Flyway, so the runtime
  role needs no DDL. Confirm that the Spring Modulith tables in currency-service came from Flyway.
- Spring Boot binds the two environment variables, so no service change should be needed. Confirm
  that Flyway connects as the migrator.
- Record D5's limit in the evidence file.

### Validation

Orchestration static gate, the new runtime check, and a clean `scripts/ops/reset-databases.sh` run
after which all three services migrate and serve requests.

### Completion criteria

No runtime role owns a database or can change a schema, and migrations still run at startup.

## Phase 5: Move to a supported RabbitMQ series and report support dates (Live)

### Workspace

.

### Goal

Get off a series with no community support, and make support dates visible before they pass.

### Scope

`kubernetes/infrastructure/rabbitmq/`, the image inventories, a support-date report,
`docs/dependency-automation.md`, and the nearest docs.

### Non-goals

Gating releases on support dates, because vulnerability gating is deferred by agreement.

### Required context

R2 finding B; R3 and R4 on support status; `docs/dependency-automation.md`, which must be read before
changing this area; the upstream upgrade guide for the selected series.

### Execution steps

1. Record the version inside the pinned digest. R3 and R4 could not confirm it is 3.13.7.
2. (amended per user direction) Select the newest
   community-supported series that has a `linux/arm64` image. No upgrade path from 3.13 is needed,
   because the broker starts on a fresh volume.
3. (amended per user direction) Recreate the RabbitMQ volume
   instead of upgrading it in place, and document that one-time reset for existing local clusters. Do
   not enable feature flags on 3.13 or take intermediate upgrade steps.
4. Confirm no definition uses classic mirrored queues.
5. Update the digest pin and any configuration the new series requires.
6. Add `scripts/lib/runtime-support-windows.txt`, listing each runtime line from the quarterly review
   with its support end date and source, and a report script that prints anything past or within 90
   days of its end date.
7. Name the report in the quarterly review in `docs/dependency-automation.md`.

### Implementation notes

R3 is right that commercial support continues, and R3 and R4 are right that nothing shows a quarterly
review ran. The conclusion holds anyway: no commercial contract exists, so this series is unsupported
here. The report needs no network and turns a calendar task into a check, but a person still keeps
the dates current.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-transport-encryption.sh`, and a currency import
that publishes and consumes an event.

### Completion criteria

The broker runs a supported series over TLS only, messaging works, and the report flags a past date.
