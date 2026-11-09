# Security Hardening 03: Service Runtime

**Status:** Implemented; post-implementation review remediation is complete. The production
release and image-pin updates remain with plan 05, Phase 3, per the cutover rule.

This is plan 03 of five that together implement every finding from the four 2026-11-01 security
reviews that holds up against the code and that no review disputes, with the decisions in the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document applied.
This plan separates liveness from readiness, adds ext-authz server timeouts, uses the trusted
client address, adds audit events, safe logging and endpoint authorization coverage across the
services, aligns the ext-authz Go toolchain, removes unused deletion code, and narrows the
currency-service Redis grant.
Phase numbers without a plan refer to this plan.

**Order:** 03 of 5

**Depends on:** plans 02.1-02.8: its live phases need the completed session-contract cutover.

**Repositories:** ext-authz, service-common, transaction-service, permission-service,
session-gateway, currency-service, orchestration.

**Post-implementation review:** D6 is settled on the scope implemented here: audit
state-changing requests and session lifecycle events, but not reads. The remaining Session
Gateway terminal-path audit fixes and runtime-test simplifications were completed by
[`security-hardening-03-service-runtime-review-remediation.md`](security-hardening-03-service-runtime-review-remediation.md):
Session Gateway now also audits callback transport and unexpected failures and logout
session-read and deletion failures, recording the completed response status; currency-service's
runtime test is one sequential test; and each runtime-configuration test documents why it loads
the shipped base configuration. A failed final logout response write is deliberately not audited.
Validation evidence is in each owning repository's `docs/` folder. The broader audit-claim
corrections remain with
[plan 05, Phase 2](security-hardening-05-closeout-release-handoff.md#phase-2-evidence-record-and-release-handoff).

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
| D6 | Audit event coverage | State-changing requests and the session lifecycle | The docs claim audit logging of data access. Auditing reads adds volume and no review requires it, so plan 05, Phase 3 narrows the claim instead. | Settled |

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
- Before launching this plan, stop the existing Tilt process from its orchestration terminal.
  Keep Tilt stopped through Phase 1 and Phase 2's manifest edits. Phase 1 uses repository tests
  only; Phase 2 starts Tilt after the new health endpoints and probes agree. This is a short local
  cutover, and the combined dependency-outage drill remains in Phase 12.
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

**Cutover rule:** `kubernetes/production` shares these manifests but pins older images
(session-gateway 0.0.15, ext-authz 0.0.16). Phase 2 and plans 02.3, 02.5 and 02.6 therefore
describe behaviour those images lack: the new cookie, hashed keys, the POST sync call and `/livez`.
The mesh policy from plan 02.3, Phase 3 would also block the pinned Session Gateway's login call. The
offline checks catch none of this. Plan 05, Phase 3 records the release and pin updates, which are
human-owned. No production environment exists, so no dual-cookie or session migration is needed.

## Contested decisions applied

- [#6, PDF memory handling](../research/security-review-contested-issues-2026-11-02.md#6-pdf-memory-handling-and-a-parsing-worker):
  the PDF-bounding phase is dropped (see [Dropped phases](#dropped-phases)), and Phase 6's non-goal
  is amended.
- [#10, `deleteUser`](../research/security-review-contested-issues-2026-11-02.md#10-the-unused-deleteuser-method):
  Phase 8 is added to remove the unused method.
- [#2, Redis enumeration](../research/security-review-contested-issues-2026-11-02.md#2-redis-enumeration-after-hashing):
  Phases 11 and 13 are added to clear the cache with `SCAN` and drop `+keys`. Residual key-name
  metadata exposure is accepted.
- [A4, ext-authz Go toolchain](../research/security-review-contested-issues-2026-11-02.md#settled-by-checking-the-code):
  Phase 3 is added as a separate maintenance finding.
- [#5, duplicate session cookies](../research/security-review-contested-issues-2026-11-02.md#5-rejecting-duplicate-session-cookies):
  Phase 9 does not add duplicate rejection.

## Dropped phases

Original Phase 23, Bound PDF parsing in transaction-service, is omitted per contested #6.
Unbounded upload processing is recorded as a known limitation in plan 05, Phase 3.

## Phase 1: Separate ext-authz liveness from readiness and add server timeouts

### Workspace

../ext-authz

### Goal

Keep the authorizer process alive through a Redis outage without serving as ready, and bound its
HTTP servers.

### Scope

`main.go`, `session.go`, tests, and `README.md`.

### Non-goals

Orchestration manifests, which are Phase 2.

### Required context

R1 finding 7; R2 on process exit and server timeouts; R3 N4.

### Execution steps

1. Add `/livez`, which reports process health with no Redis dependency.
2. Add `/readyz`, which pings Redis. Remove `/healthz`.
3. Start the health server before connecting to Redis.
4. Replace the exit after 10 failed connection attempts with continued background retries.
5. While Redis is unavailable, keep returning the existing fail-closed response.
6. Set `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout` and `IdleTimeout` on both HTTP servers.

### Implementation notes

- R3 found the retry loop can back off for about 27.5 seconds, while the startup probe allows about
  10 seconds and the health server only starts after Redis connects. Set a startup probe target for
  Phase 2.
- Keep `WriteTimeout` above the Redis call budget, and `IdleTimeout` long enough that closing an idle
  connection does not surface as an authorization failure.

### Validation

`go test ./...`, including a test that `/livez` stays healthy and `/readyz` fails while Redis is
unavailable.

### Completion criteria

Repository tests prove a Redis outage cannot cause a liveness failure or a process exit,
authorization stays fail-closed, and neither server can hold a connection open indefinitely.
Phase 2 can deploy these health endpoints with the matching probes.

## Phase 2: Wire ext-authz probes and resume the local stack (Live)

### Workspace

.

### Goal

Deploy the new ext-authz health endpoints with matching probes immediately after the service change.

### Scope

`kubernetes/services/ext-authz/deployment.yaml`, `scripts/smoketest/verify-credential-isolation.sh`,
and the docs that reference `/healthz`.

### Non-goals

Spring probe changes and the combined outage drill, which are Phase 12, and service code.

### Required context

Phase 1's repository-local evidence; `docs/runbooks/tilt-debugging.md`;
`docs/architecture/session-edge-authorization-pattern.md`.

### Execution steps

1. With Tilt still stopped, point ext-authz startup and liveness probes at `/livez`, and readiness
   at `/readyz`. Use the startup probe budget established in Phase 1.
2. Update `verify-credential-isolation.sh:624`, `docs/runbooks/tilt-debugging.md:222,492,652`, and
   `docs/architecture/session-edge-authorization-pattern.md:90` for the new endpoints.
3. Run the orchestration static gate and `./scripts/bootstrap/check-local-runtime.sh`, then start
   `tilt up`. Confirm ext-authz is built from the Phase 1 worktree and wait for its rollout.
4. Confirm the deployed probes use the new paths, ext-authz becomes Ready, and an authenticated API
   request succeeds. Record the result in the evidence file.

### Implementation notes

Do not start Tilt or wait for healthy workloads before updating the probes: Phase 1 removed
`/healthz`. Keep this cutover adjacent to Phase 1. Phase 12 proves outage behaviour after the Spring
services have their final readiness configuration.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-credential-isolation.sh`, and the live rollout
and authenticated request checks above.

### Completion criteria

The current ext-authz worktree runs with matching startup, liveness and readiness probes, the
deployment is Ready, and normal authorization works before the remaining runtime phases begin.

## Phase 3: Align the ext-authz Go toolchain

### Workspace

../ext-authz

### Goal

(added per contested A4) Build and test ext-authz on one supported Go toolchain.

### Scope

`go.mod`, `.github/workflows/build.yml`, `Dockerfile`, and docs.

### Non-goals

Service behaviour changes.

### Required context

Contested doc, "Settled by checking the code", row "ext-authz Go toolchain mismatch (A4)"; the
repository's `AGENTS.md` workflow rules.

### Execution steps

1. Align the supported CI and build toolchains. Build CI selects the 1.24 line from `go.mod`, while
   Docker builds with 1.27, and Go's support policy excludes 1.24.
2. Keep workflow action refs full-SHA pinned.

### Implementation notes

This is a maintenance finding, independent of the ingress CSRF design.

### Validation

`go test ./...` and the repository's other documented checks.

### Completion criteria

CI and the Docker build use the same supported Go line.

## Phase 4: Use the trusted client address in service-common

### Workspace

../service-common

### Goal

Stop logging a client address the caller controls.

### Scope

`ContentLoggingUtil`, `ContentLoggingUtilTest`, and the shared docs.

### Non-goals

Changing how NGINX or the ingress derive the address.

### Required context

R1 finding 6; R2 on client IPs; `nginx/nginx.k8s.conf` in orchestration.

### Execution steps

1. Change `getClientIpAddress` to read `X-Real-IP`, falling back to `request.getRemoteAddr()`.
2. Remove the rest of the header list, because a caller can set every entry on it.
3. Replace the test at `ContentLoggingUtilTest.java:93`, which asserts the first `X-Forwarded-For`
   entry, and add a test that a forged `X-Forwarded-For` is ignored.
4. Confirm what `ReactiveHttpLoggingFilter` logs behind the ingress, and record it.
5. Publish to Maven Local so later phases build against the change.

### Implementation notes

- NGINX overwrites `X-Real-IP` with its derived address, so it is trustworthy on the NGINX lane. The
  mesh limits who else can reach these services.
- `ForwardedHeaderTransformer` replaces the reactive remote address with an unresolved one, so
  `getAddress()` should return null and Session Gateway should log no client address. That is a
  missing value, not a forged one. Record the gap, and do not switch to `getHostString()`, which
  would log a caller-controlled value.

### Validation

The repository's documented build and test commands.

### Completion criteria

A forged `X-Forwarded-For` cannot change the logged client address.

## Phase 5: Add structured audit events to service-common

### Workspace

../service-common

### Goal

Give every service one safe way to record who changed what, now that body logging is going away.

### Scope

A new audit event type and logger, servlet auto-configuration, tests, and the shared docs.

### Non-goals

Retention and access control, which need a hosted log store, and reads, per D6.

### Required context

R1 finding 6; R2 item 6; `CorrelationIdFilter`; `SecurityContextUtil`; `HttpLoggingConfig`.

### Execution steps

1. Add an event with timestamp, actor, operation, resource identifier, outcome and correlation ID,
   written to a dedicated `budgetanalyzer.audit` logger at INFO.
2. Auto-configure a servlet component that emits one event for each POST, PUT, PATCH and DELETE that
   maps to a handler. Use the route pattern for the operation, path variables for the resource
   identifier, and the response status for the outcome.
3. Expose the logger so Session Gateway can emit the same shape from reactive code.
4. Add tests that no event contains a body, query string, email or display name.
5. Publish to Maven Local so later phases build against the change.

### Implementation notes

Auto-configuration means the three servlet services need no code change, and a new endpoint cannot
be forgotten. Plan 05, Phase 3 updates the audit claims in the orchestration docs.

### Validation

The repository's documented build and test commands.

### Completion criteria

A state-changing request produces exactly one event, and the event holds no payload or personal
data.

## Phase 6: Safe logging, readiness and authorization coverage in transaction-service

### Workspace

../transaction-service

### Goal

Stop logging bodies by default, make readiness reflect the service's own dependencies, and guarantee
every new endpoint declares an authorization policy.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

PDF bounds (amended per contested #6: deferred as a known limitation), and
service logic.

### Required context

R3 finding 6 table; R2 finding F; R4 "Method authorization (F)"; `HttpLoggingProperties` in
service-common, where both body flags default to `false`.

### Execution steps

1. Remove `include-request-body` and `include-response-body`.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add an opt-in `debug-logging` profile for synthetic-data debugging only.
4. Set `management.endpoint.health.probes.enabled` to `true`, so the probe groups also exist in
   tests and outside Kubernetes.
5. Set `management.endpoint.health.group.readiness.include` to `readinessState` plus the data stores
   the service needs in order to serve requests.
6. Add a test that reads `RequestMappingHandlerMapping`, lists every `org.budgetanalyzer` handler,
   and fails unless the method or its class has `@PreAuthorize`, with an explicit exception list.

### Implementation notes

- This trap is not in any review. Spring's default readiness group holds only `readinessState`, so
  switching the probes without step 5 would stop a database outage from removing the pod.
- Keep `/actuator/health/liveness` free of dependencies. Do not add downstream services to
  readiness. Exclude RabbitMQ unless request serving depends on it.
- `@PreAuthorize` is already enforced (R4 corrects R2's heading), and 31 of 31 handlers have it. The
  rule stops a new endpoint falling back to `authenticated()`. It says nothing about ownership
  checks.

### Validation

The repository's documented build and test commands. Confirm the effective `kubernetes` profile has
no body logging, and that a state-changing request emits one audit event.

### Completion criteria

Default configuration logs no bodies and no TRACE, readiness fails when the database is down, and an
unannotated handler fails the build.

## Phase 7: Safe logging, readiness and authorization coverage in permission-service

### Workspace

../permission-service

### Goal

Apply the Phase 6 changes to permission-service.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

`deleteUser` (amended per contested #10: Phase 8).

### Required context

Phase 6 notes.

### Execution steps

1. Remove both body-logging settings.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add the `debug-logging` profile.
4. Enable the probe groups, and set the readiness group to `readinessState` plus the database.
5. Add the coverage test, listing the two `InternalPermissionController` handlers as exceptions.

### Implementation notes

This service returns user and permission data, so response bodies are the main exposure here.

### Validation

The repository's documented build and test commands.

### Completion criteria

Same as Phase 6.

## Phase 8: Remove the unused `deleteUser` method

### Workspace

../permission-service

### Goal

(added per contested #10) Remove latent deletion code that nothing calls.

### Scope

`UserService`, its tests, and docs.

### Non-goals

A deletion endpoint, and any change to account lifecycle policy or re-signup semantics.

### Required context

Contested issue #10.

### Execution steps

1. Remove `deleteUser` from `UserService`, along with any test that exists only for it.
2. Retain the existing synchronization checks.

### Implementation notes

`UserSyncService` rejects any subject with a `DEACTIVATED` record, regardless of soft deletion.
Preserve that distinction between deletion and deactivation. If deletion is later exposed, specify
revocation, concurrent login handling and re-registration semantics first.

### Validation

The repository's documented build and test commands.

### Completion criteria

`deleteUser` is gone, and deactivated subjects still cannot sign in again.

## Phase 9: Safe logging, readiness and session audit events in session-gateway

### Workspace

../session-gateway

### Goal

Apply the Phase 6 logging and readiness changes, and record session lifecycle events.

### Scope

`application.yml`, `application-kubernetes.yml`, `SecurityConfig`, `LogoutController`,
`InternalSessionController`, and tests.

### Non-goals

Client-address changes, which Phase 4 records as a gap.

### Required context

Phase 6 notes; Phase 5; R3 N4 on the leftover override.

### Execution steps

1. Remove both body-logging settings from `application.yml`.
2. Remove the override and the "isolate POST timeout issue" comment from
   `application-kubernetes.yml`.
3. Change `org.budgetanalyzer` from TRACE to INFO, and add the `debug-logging` profile.
4. Set the readiness group to `readinessState` plus Redis. `probes.enabled` is already set.
5. Emit audit events for login success, login failure, logout and bulk revocation.

### Implementation notes

Do not add permission-service to readiness. It is a downstream dependency, and including it would
take the auth lane down with it. Never log session tokens or their digests in audit events; use the
internal user ID.

### Validation

The repository's documented build and test commands.

### Completion criteria

Logging matches Phase 6, and each session lifecycle event produces one audit event.

## Phase 10: Safe logging, readiness and authorization coverage in currency-service

### Workspace

../currency-service

### Goal

Apply the Phase 6 changes to currency-service.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

Cache eviction and `KEYS`/`SCAN` changes (amended per contested #2: Phase
11).

### Required context

Phase 6 notes.

### Execution steps

1. Remove `include-request-body`. Response bodies are already off, so remove that setting too.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add the `debug-logging` profile.
4. Enable the probe groups, and set the readiness group to `readinessState` plus the stores needed to
   serve requests.
5. Add the coverage test.

### Implementation notes

Decide deliberately whether Redis belongs in readiness. If a cache miss can fall back to the
database, a Redis outage should not make this service unready.

### Validation

The repository's documented build and test commands.

### Completion criteria

Same as Phase 6.

## Phase 11: Clear the currency-service cache with SCAN

### Workspace

../currency-service

### Goal

(added per contested #2) Let cache-wide eviction work without the `KEYS` command.

### Scope

`CacheConfig`, cache eviction tests, and docs.

### Non-goals

Cache-generation keys, TTL-only expiry, and a Redis split.

### Required context

Contested issue #2.

### Execution steps

1. Add a `SCAN` batch strategy (`BatchStrategies.scan(...)`) to the existing cache-writer configurer
   alongside `immediateWrites()`, and choose the batch size there.
2. Keep `@CacheEvict(allEntries = true)` and the existing freshness behaviour.
3. Test after-commit eviction under a Redis user with `+scan` and `+del` but no `+keys`.

### Implementation notes

- Spring Data Redis defaults to `BatchStrategies.keys()`, so today each eviction runs `KEYS` and then
  `DEL`.
- `SCAN` walks the keyspace incrementally instead of blocking Redis for one full `KEYS` pass. This
  matters because ext-authz reads sessions from the same instance on every request.
- Like `KEYS`, it is not a point-in-time delete. A racing stale write remains the accepted race,
  bounded by the one-hour TTL.

### Validation

The repository's documented build and test commands.

### Completion criteria

Eviction clears every matching key under a grant without `+keys`.

## Phase 12: Switch Spring probes and run the combined outage drill (Live)

### Workspace

.

### Goal

Point Spring probes at the final health groups, and prove a dependency outage causes no restarts
across the services and ext-authz.

### Scope

Spring deployment manifests in `kubernetes/services/`, the dependency-outage evidence, and the
nearest probe documentation.

### Non-goals

Alerting and service code.

### Required context

Phases 1-11; `docs/runbooks/tilt-debugging.md`.

### Execution steps

1. Point Spring startup and liveness probes at `.../actuator/health/liveness`, and readiness at
   `.../actuator/health/readiness`, keeping each service's context path.
2. Update the nearest probe documentation and confirm the running services use the current
   worktrees, including the service-common changes. Retain the ext-authz probes from Phase 2.
3. Interrupt Redis on local Kind, then repeat for PostgreSQL. Record readiness, restart counts and
   client errors, then confirm recovery.

### Implementation notes

Apply the `kind-kind` checks before the drill. Redis data is on a PVC and survives a pod replacement.
Report a failing drill as a finding rather than loosening probes to make it pass.

### Validation

Orchestration static gate, and `scripts/smoketest/verify-credential-isolation.sh`. Compare
`restartCount` before and after each interruption.

### Completion criteria

During each outage affected pods become unready with no restarts, authorization stays fail-closed,
and service recovers without intervention.

## Phase 13: Narrow the currency-service Redis grant to `+scan` (Live)

### Workspace

.

### Goal

(added per contested #2) Remove `KEYS` from the currency-service Redis ACL.

### Scope

`kubernetes/infrastructure/redis/start-redis.sh`, `scripts/smoketest/verify-credential-isolation.sh`,
and the nearest docs.

### Non-goals

Hiding key names from `SCAN`, and a Redis split.

### Required context

Contested issue #2; Phase 11; plan 01, Phase 6.

### Execution steps

1. Remove `+keys` from the currency-service ACL, retaining `+scan` and `+del`.
2. Restart Redis with `kubectl rollout restart statefulset/redis -n infrastructure`, and confirm with
   `ACL GETUSER` that the new ACL is live.
3. Extend `verify-credential-isolation.sh` to assert currency-service `KEYS` denial.
4. Trigger a currency import that evicts the cache, and confirm `ACL LOG` shows no denial.

### Implementation notes

- Redis ACL key patterns do not filter `SCAN` results. After hashing, this credential can still list
  session-digest, user-index and OAuth-state key names. That is accepted residual metadata exposure;
  record it in the evidence file.
- Apply the `kind-kind` checks.

### Validation

Orchestration static gate and `./scripts/smoketest/verify-credential-isolation.sh` against the
restarted Redis.

### Completion criteria

currency-service is denied `KEYS`, and cache eviction still works.
