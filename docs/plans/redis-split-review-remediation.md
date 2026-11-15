# Redis Split Review Remediation

Fix the findings from the 2026-11-15 review of the Redis session/cache split. The split itself
stays: `redis-session` holds sessions, session indexes and OAuth state; `redis-cache` holds only the
currency-service exchange-rate series cache. This plan does not reopen that design.

## Decisions

These are settled. Do not reopen them in a phase.

- **End-date cap:** the latest effective `endDate` for `GET /v1/exchange-rates` is tomorrow, the
  UTC date from the injected `Clock` plus one day. A later `endDate` is treated as tomorrow. An
  omitted `endDate` still means today. Reversed input dates are still rejected before the cap is
  applied. The reason is that transaction-service accepts transaction dates through tomorrow, and
  the web client requests rates through its latest transaction date.
- **Empty ranges are unchanged:** a range with no source rate inside it still returns an empty
  list. This matches the behavior before the split and is not part of this plan.
- **No cross-repo script references:** sibling-repository docs do not cite orchestration script
  paths. Where a sibling doc needs a Redis inspection or reset procedure, it links to the
  orchestration doc section that owns it. One-time cutover instructions that are already complete
  are removed instead of being redirected.
- **Redis memory budgets** have one owner: a `Redis Memory Budgets` section in
  `docs/architecture/security-architecture.md`. Other docs summarize and link to it.
- **Live-config verification** belongs in `scripts/smoketest/verify-credential-isolation.sh`,
  which already authenticates as `redis-ops` on both instances. Do not add Redis credential
  handling to `verify-runtime-hardening.sh`.
- **Unknown `.env` keys:** the Tiltfile warns about `.env` keys that `.env.example` does not
  declare. It names keys only, never values. It does not special-case the removed
  `REDIS_DEFAULT_PASSWORD` or `REDIS_OPS_PASSWORD` names, and it does not map old names to new
  ones.
- **No production migration:** no production environment is configured. There are no migration,
  compatibility or fallback steps.

## Rules

- Follow each workspace's `AGENTS.md`. No git write operations.
- Never run `mkcert`, any `openssl` generation command, `scripts/bootstrap/setup-infra-tls.sh` or
  `scripts/bootstrap/setup-k8s-tls.sh`, and never trigger the Tilt `infra-tls-prerequisites`
  resource.
- Phases 1 to 9 are static work. Do not mutate the cluster in them. Do not start or stop Tilt in
  any phase.
- Before Phase 10, the human starts Tilt (`tilt up`) and waits for all resources to be ready.
  Phases 10 and 11 stop if `tilt get uiresources` fails.
- Before every cluster mutation or exec, apply the `AGENTS.md` preconditions: the context is
  `kind-kind`, the API server is loopback HTTPS with no proxy override, and `kind-control-plane`
  is Ready.
- Never print a password, token or Secret value in output, logs or docs.
- Every changed shell script passes `bash -n` and `shellcheck`.
- Do not edit `docs/archive/`, `archive/` or `docs/decisions/`. Do not edit or link to
  `docs/plans/split-redis-session-and-cache.md`. It is being deleted.

## Phase 1: Orchestration Scripts, Verifiers And Tiltfile

### Workspace

.

### Goal

Tilt removes the stale pre-split Redis NetworkPolicy, warns about unrecognized `.env` keys, and
`flush-redis.sh` fails on a bad reply. The credential-isolation verifier asserts each instance's
exact memory and persistence settings and that foreign application users are absent.

### Scope

- `Tiltfile`: the `network-policies-core` command and a `.env` key check after `dotenv()`.
- `.env.example`: declare every key the Tiltfile reads through `os.getenv`.
- `scripts/ops/flush-redis.sh`.
- `scripts/smoketest/verify-credential-isolation.sh`.
- `scripts/README.md`, only if it describes the coverage of these scripts.

### Non-goals

- Running Tilt, the verifiers or the flush script. Phase 10 does that.
- Changing Redis configuration, ACLs or manifests.
- Tiltfile nits such as resource labels or unused variables.

### Required context

- `AGENTS.md`, sections "Operational guardrails" and "Shell Script Validation".
- `Tiltfile`, around the `dotenv()` call, the Redis credential `os.getenv` calls and
  `network-policies-core`.
- `kubernetes/network-policies/`. Confirm that no checked-in manifest defines
  `allow-redis-ingress-from-approved-default-workloads`.
- `kubernetes/infrastructure/redis-session/start-redis.sh` and
  `kubernetes/infrastructure/redis-cache/start-redis.sh`. These are the sources of the expected
  values.
- `scripts/ops/redis-browse.sh`, which has the empty-password guard to copy.
- `scripts/lib/redis-cli.sh`.

### Execution steps

1. In `network-policies-core`, delete the pre-split policy alongside the existing deletions of
   retired policies:
   `kubectl delete networkpolicy allow-redis-ingress-from-approved-default-workloads -n infrastructure --ignore-not-found`.
2. After `dotenv()` in the Tiltfile:
   - If `.env` exists, collect its keys and the keys `.env.example` declares. A declared key
     appears either as `KEY=` or as a commented `# KEY=`.
   - Call `warn()` once, listing the `.env` keys that `.env.example` does not declare, and say
     that the Tiltfile ignores them.
   - Do not print values. Do not fail the load.
3. Add every key that the Tiltfile reads through `os.getenv` but `.env.example` does not declare.
   Currently this is only `PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET`. Follow the file's existing
   comment and default-value pattern.
4. In `flush-redis.sh`:
   - Fail with a clear error if the `ops-password` read from the bootstrap Secret is empty,
     matching `redis-browse.sh`.
   - Capture the `FLUSHALL` reply instead of discarding it. Strip `\r`. Exit non-zero with an
     error unless the reply is exactly `OK`.
   - Keep the existing AOF-rewrite verification.
5. In `verify-credential-isolation.sh`, replace the two `CONFIG GET maxmemory` existence checks
   in the break-glass section with exact assertions. Use the `redis-ops` helpers already there.
   - `redis-session`: `maxmemory` is `134217728`, `maxmemory-policy` is `noeviction`, and
     `appendonly` is `yes`.
   - `redis-cache`: `maxmemory` is `67108864`, `maxmemory-policy` is `allkeys-lru`, `appendonly`
     is `no`, and `save` is empty.
   - Add a comment naming the `start-redis.sh` file each expected value comes from.
6. In the same verifier, assert that foreign application users do not exist, using `redis-ops`:
   - `ACL GETUSER currency-service` on `redis-session` returns nil.
   - `ACL GETUSER session-gateway` and `ACL GETUSER ext-authz` on `redis-cache` return nil.
   - Keep the existing `WRONGPASS` checks. They prove the passwords differ, and the new checks
     prove the users are absent.
7. Update the verifier descriptions in `scripts/README.md` if they list the Redis coverage.

### Implementation notes

The stale policy still exists in the live cluster with selector `app=redis`. The pre-split
manifest that created it is gone, so no checked-in manifest will recreate it.

`redis-cli` prints a nil reply as an empty line when stdout is not a TTY. Confirm how the
verifier's helpers render nil and an empty `save` value by reading the helper. Do not run a live
command in this phase. If you are unsure of the rendering, make the assertion accept only the
exact forms the helper can produce, and record that Phase 10 must confirm them.

### Validation

- `bash -n` and `shellcheck` pass on `scripts/ops/flush-redis.sh` and
  `scripts/smoketest/verify-credential-isolation.sh`.
- Do not evaluate the Tiltfile, because evaluation runs its `local()` commands. Check the new
  Starlark by reading it: it uses only `read_file`, `os.path.exists`, string methods and
  `warn()`. Phase 10 confirms the warning live.
- `rg -n "allow-redis-ingress-from-approved-default-workloads" Tiltfile` shows the deletion.
- `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python ./scripts/guardrails/verify-static-security-manifests.sh`
  passes. If the interpreter is missing, follow `docs/ci-cd.md#security-guardrailsyml`.

### Completion criteria

- The Tiltfile deletes the stale policy and warns about undeclared `.env` keys.
- `.env.example` declares every key the Tiltfile reads.
- `flush-redis.sh` fails on an empty password or a non-`OK` flush.
- The verifier asserts the exact settings and the absent users.
- Static checks pass.

## Phase 2: Orchestration Documentation

### Workspace

.

### Goal

Redis memory budgets have one owner and the `redis-cache` derivation lives there. Redis local
access has a stable anchor that sibling repos can link to. Prose that means `redis-session` says
so. The issue documents describe the tomorrow cap and no longer link to the deleted plan.

### Scope

- `docs/OWNERSHIP.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/system-overview.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `docs/architecture/session-security-benefits.md`
- `docs/issues/high-currency-cache-exhausts-shared-redis.md`
- `docs/issues/medium-exchange-rate-end-date-unbounded-response.md`
- `docs/issues/low-user-sync-request-schema-leaks-into-public-api-docs.md`

### Non-goals

- New measurements, and changes to the `W` figure. Phase 10 recomputes it.
- Changing Redis configuration.
- Editing `docs/archive/` or `docs/decisions/`.

### Required context

- `docs/OWNERSHIP.md`, including its rules section.
- `docs/agents-md-checkstyle.md`. This phase edits no `AGENTS.md`, but read it if one needs a
  change.
- The `redis-cache` sizing bullet in the "Caching Strategy" section of `system-overview.md`.
- The `redis-session` memory budget bullet and the "Redis memory budget derivation" paragraph in
  the "Session Management" section of `security-architecture.md`.
- The "Redis local access:" and "RabbitMQ local access:" labels under
  `### Backend Services (Spring Boot)` in `local-environment.md`.

### Execution steps

1. In `security-architecture.md`, add a `### Redis Memory Budgets` section:
   - Move the existing `redis-session` derivation paragraph into it unchanged.
   - Move the `redis-cache` sizing text from `system-overview.md` into it unchanged.
   - In "Session Management", replace the derivation with a one-sentence pointer to the new
     section. The memory-budget bullet keeps its values.
2. In `system-overview.md`, reduce the `redis-cache` sizing bullet to one sentence with the
   `maxmemory` value and a link to the new section.
3. Add an `OWNERSHIP.md` row: "Redis instance memory budgets and their derivations", owned by
   `security-architecture.md#redis-memory-budgets`. Non-owner docs state the values and link to
   the owner.
4. In `local-environment.md`, convert "Redis local access:" to `#### Redis Local Access` and
   "RabbitMQ local access:" to `#### RabbitMQ Local Access`. Keep the content. Fix any in-repo
   links that relied on the old text.
5. Wherever these lines mean the session instance, change bare "Redis" to `redis-session`.
   Reread each line first; leave a line unchanged if it means Redis generally.
   - `docs/runbooks/tilt-debugging.md`: lines near 477 and 558.
   - `docs/architecture/session-edge-authorization-pattern.md`: lines near 67 and 90.
   - `docs/architecture/session-security-benefits.md`: lines near 41, 78 and 88.
6. Rewrite the Resolution in `medium-exchange-rate-end-date-unbounded-response.md` to the
   tomorrow cap:
   - The effective end date is `min(endDate, tomorrow)`, with tomorrow taken as UTC.
   - An omitted `endDate` means today.
   - Reversed inputs are rejected before the cap.
   - Ranges without a source rate return an empty list.
   - The cap is tomorrow because transaction-service accepts transaction dates through tomorrow.
   Update the Options paragraph if it now contradicts the Resolution. Keep the statement that a
   maximum response is bounded by the history length.
7. Remove the links to `split-redis-session-and-cache.md`:
   - In the Status lines of the high and medium issue documents, keep the dates and outcomes and
     drop the link.
   - In the low issue document's Source line, describe the source as the 2026-11-14 Redis split
     API-doc regeneration without naming the plan file.

### Implementation notes

`OWNERSHIP.md` says that if no existing owner fits a recurring topic, choose one and update the
map in the same change. That rule is why step 3 belongs in this phase.

Anchors are GitHub-style lowercase slugs: `#redis-local-access` and `#redis-memory-budgets`.
Phases 7 and 8 link to `#redis-local-access`.

### Validation

- `rg -n "split-redis-session-and-cache" docs --glob '!docs/plans/**'` returns nothing.
- `rg -n "196,696" docs` matches only the new section in `security-architecture.md`.
- Every changed relative link resolves to an existing file, and each anchor matches a heading.
  Check this with `rg` against the target headings.

### Completion criteria

- One owner holds both Redis budget derivations, and `OWNERSHIP.md` names it.
- `#redis-local-access` exists.
- The listed prose names `redis-session`.
- The end-date issue describes the tomorrow cap.
- No active doc links to the deleted plan.

## Phase 3: Currency Service Tomorrow End-Date Cap

### Workspace

../currency-service

### Goal

`GET /v1/exchange-rates` caps the effective end date at tomorrow (UTC) and forward-fills through
it. Code, tests, OpenAPI text and docs agree.

### Scope

- `ExchangeRateService` end-date logic.
- The `endDate` OpenAPI description in `ExchangeRateController`.
- `TestConstants` javadoc.
- `ExchangeRateServiceIntegrationTest` and `ExchangeRateControllerIntegrationTest`.
- `docs/api/README.md` and `docs/advanced-patterns-usage.md`.

### Non-goals

- Changing the empty-range rule, or the omitted-`endDate` default of today.
- Cache, serializer or `FailOpenCache` changes.
- Changes to transaction-service.

### Required context

- `AGENTS.md`, including the validation commands.
- The end-date logic in `ExchangeRateService.getExchangeRates`.
- `rg -n -i "treated as today|min\(endDate|clamp" src docs` lists every statement of the old cap.
- `ExchangeRateSeries.containsSourceRateBetween` and `exchangeRateOn`.

### Execution steps

1. Compute the effective end date:
   - `today = LocalDate.now(clock)`.
   - `latestEndDate = today.plusDays(1)`.
   - `effectiveEndDate` is `today` when `endDate` is null, `latestEndDate` when `endDate` is
     after it, and `endDate` otherwise.
   - Keep the reversed-range validation on the original inputs, before the cap.
   - Add a one-line comment giving the reason: transaction-service accepts transaction dates
     through tomorrow.
2. Update the controller's `endDate` description:
   - It defaults to today (UTC).
   - Dates after tomorrow (UTC) are treated as tomorrow.
   - A start date after the end date is still rejected before the cap.
3. Update the tests:
   - Far-future `endDate` returns a dense series ending at `FIXED_TODAY + 1`. Rename the tests
     that say "ToToday".
   - `endDate` equal to tomorrow returns tomorrow, forward-filled from the last source rate.
   - Omitted `endDate` still ends at `FIXED_TODAY`.
   - A valid range that starts after tomorrow returns an empty list. Move the existing
     future-range test start date to `FIXED_TODAY + 2` so it still tests the post-cap empty case.
   - Review the cases near `ExchangeRateServiceIntegrationTest` lines 603 and 784, and update any
     whose intent depended on today being the cap.
4. Update the `TestConstants` javadoc, `docs/api/README.md` (the `endDate` row, the effective-date
   bullets, the validation table and the caching note) and `docs/advanced-patterns-usage.md`.

### Implementation notes

The fixed test clock is at the start of `FIXED_TODAY` in UTC. Phase 5 changes that clock. Write
assertions against `FIXED_TODAY`, not against the wall clock, so they hold after Phase 5.

### Validation

- `./gradlew clean spotlessApply`, then `./gradlew clean build`.
- `rg -n -i "treated as today|min\(endDate, today\)" src docs` returns nothing.

### Completion criteria

- The cap is tomorrow and the omitted default is today.
- The tests cover the far-future, tomorrow, omitted and post-cap-empty cases.
- The OpenAPI text and docs match.
- The build passes.

## Phase 4: Currency Service Fail-Open Cache Hardening

### Workspace

../currency-service

### Goal

`FailOpenCache` treats only cache-infrastructure failures as misses, and an outage does not log a
stack trace per request at `WARN`.

### Scope

- `src/main/java/org/budgetanalyzer/currency/config/FailOpenCache.java`.
- `FailOpenCacheTest`, plus any cache integration test that asserts fail-open behavior.
- `docs/configuration.md`, only if it describes the logging or the caught exceptions.

### Non-goals

- Changing decorator order, TTL, timeouts or readiness.
- Changing how value-loader exceptions propagate.

### Required context

- `FailOpenCache`: every `catch` block, the async `retrieve` paths, `RecordingValueLoader` and
  `logFailure`.
- `CacheConfig`: the decorator chain and the serializer.
- Spring Data Redis exception translation for Lettuce, especially connection failures and command
  timeouts.
- `../service-common/docs/advanced-patterns.md`, the "Fail-Open Caching" section. Read it only;
  do not edit it.

### Execution steps

1. Find the exception types that reach `FailOpenCache` for:
   - an unreachable Redis;
   - a command timeout;
   - an undeserializable cached value.
   Use the existing tests or an ad hoc Testcontainers check. Expect
   `org.springframework.dao.DataAccessException` subclasses and
   `org.springframework.data.redis.serializer.SerializationException`.
2. Narrow every sync `catch (RuntimeException ...)` to the confirmed types.
3. In the async `retrieve` paths, unwrap `CompletionException` and `ExecutionException`. Treat
   only the confirmed types as cache failures, and propagate anything else.
4. Preserve the `RecordingValueLoader` distinction. A value-loader failure, including a database
   `DataAccessException` thrown by the loader, must still propagate and must not be treated as a
   cache failure.
5. Change `logFailure`:
   - At `WARN`, log the operation, cache name, key, and the exception class and message, with no
     stack trace.
   - At `DEBUG`, log the same message with the throwable.
6. Add tests:
   - An unexpected `RuntimeException`, such as `IllegalStateException` from the delegate,
     propagates from each sync and async operation.
   - The confirmed types still fail open.
   - A loader-thrown `DataAccessException` propagates from `get(key, loader)` and `retrieve(key,
     loader)`.

### Implementation notes

If step 1 finds a cache-infrastructure failure type outside these two families, such as a
connection-pool exception, include it and name it in a short comment. Do not fall back to
catching `RuntimeException`.

### Validation

`./gradlew clean spotlessApply`, then `./gradlew clean build`.

### Completion criteria

- Only the confirmed cache-failure types fail open, sync and async.
- Other exceptions and loader failures propagate.
- `WARN` lines carry no stack trace.
- The build passes.

## Phase 5: Currency Service Test Clock And Cleanup

### Workspace

../currency-service

### Goal

The test clock fixes "today" without freezing time for Spring Modulith. Cache-absence assertions
prove absence in Redis. Unused repository capabilities and stale javadoc are gone.

### Scope

- `src/test/java/org/budgetanalyzer/currency/config/FixedClockTestConfig.java`
- `ExchangeRateImportServiceIntegrationTest` and `ExchangeRateImportCacheIntegrationTest`
- `ExchangeRateRepository` and `ExchangeRateRepositoryIntegrationTest`
- The cache javadoc in `ExchangeRateImportService`

### Non-goals

- Production behavior changes beyond removing `JpaSpecificationExecutor`.
- Changing `TestConstants.FIXED_CLOCK` for pure unit tests that construct services directly.

### Required context

- `FixedClockTestConfig`, and `TestConstants.FIXED_TODAY` and `FIXED_CLOCK`.
- Spring Modulith's event publication configuration. It takes the application `Clock` bean when
  one exists, so a `@Primary` fixed clock freezes publication and completion timestamps.
- `rg -n "isNull\(\)" src/test` around the `cache.get(...)` assertions. In
  `ExchangeRateImportServiceIntegrationTest` they are near lines 720, 760, 800 and 839, and in
  `ExchangeRateImportCacheIntegrationTest` near line 98.
- `rg -n "Specification" src`.
- The "Performance Impact" paragraphs in `ExchangeRateImportService`.

### Execution steps

1. Make `FixedClockTestConfig` provide a running clock anchored at the start of `FIXED_TODAY`.
   Use `Clock.offset(Clock.systemUTC(), offset)`, with the offset computed once when the bean is
   created. "Today" then stays `FIXED_TODAY` for any test run under 24 hours, while Modulith
   timestamps advance. Update the class javadoc.
2. Run the suite. Fix any test that compared a timestamp against `FIXED_CLOCK.instant()` and
   relied on frozen time; compare against a captured before/after window instead.
3. Replace each `cache.get(key)).isNull()` absence assertion with a direct Redis key check, such
   as `StringRedisTemplate.hasKey` on the full key `currency-service:exchangeRateSeries::<code>`.
   Where the test does not already prove the key existed, assert presence before the eviction, so
   a fail-open miss cannot pass the check vacuously.
4. Remove `JpaSpecificationExecutor` from `ExchangeRateRepository`. Delete the Specification tests
   and the javadoc bullet in `ExchangeRateRepositoryIntegrationTest`.
5. Rewrite the three "Performance Impact" paragraphs in `ExchangeRateImportService`:
   - Describe the current cache: after the all-entries eviction, the first request per currency
     reloads that currency's full series from PostgreSQL.
   - Remove the unmeasured latency figures.

### Implementation notes

If step 2 shows a test that truly needs frozen time, give that test its own fixed clock. Do not
restore the global `@Primary` fixed clock.

### Validation

- `./gradlew clean spotlessApply`, then `./gradlew clean build`.
- `rg -n "JpaSpecificationExecutor|Specification<" src` returns nothing.
- `rg -n "50-200ms|1-3ms" src` returns nothing.

### Completion criteria

- Modulith sees advancing time while "today" stays fixed.
- Absence assertions query Redis directly.
- The repository has no Specification support.
- The javadoc is current.
- The build passes.

## Phase 6: Service Common Caching Pattern Wording

### Workspace

../service-common

### Goal

The Redis caching pattern doc restores three facts lost in the rewrite.

### Scope

`docs/advanced-patterns.md`, in the Redis caching Configuration, Fail-Open Caching and TTL
sections.

### Non-goals

Code changes or other doc sections.

### Required context

- `docs/advanced-patterns.md`, in the Redis caching pattern section.
- `../currency-service/src/main/java/org/budgetanalyzer/currency/config/CacheConfig.java`, read
  only, for the serializer class name.

### Execution steps

1. In the serializer bullet, name the class: `JacksonJsonRedisSerializer` bound to the value
   type.
2. In the decorator bullet, add why `FailOpenCache` sits beneath `TransactionAwareCacheDecorator`.
   The decorator runs deferred `put`, `evict` and `clear` in `afterCommit`. Failures there reach
   the caller after the database has committed, so the fail-open layer must wrap the Redis cache
   directly to cover them.
3. In the TTL bullet, restore the race mechanism. A read that queried the database before a write
   committed can repopulate the cache with a stale result after the write's after-commit
   eviction.

### Implementation notes

Keep each addition to one sentence and match the section's style.

### Validation

`rg -n "JacksonJsonRedisSerializer|afterCommit|after-commit" docs/advanced-patterns.md` shows all
three.

### Completion criteria

The three facts are stated, and nothing else changed.

## Phase 7: Session Gateway Documentation

### Workspace

../session-gateway

### Goal

The troubleshooting commands no longer read a Secret key that does not exist. Session Gateway
docs carry no orchestration script paths, and no doc tells developers to port-forward a local
port that Tilt already uses.

### Scope

- `AGENTS.md`, in the Troubleshooting section.
- `docs/security.md`, near line 67.
- `docs/session-configuration.md`, near line 51.
- `docs/local-development.md`, near line 31.

### Non-goals

Code or configuration changes.

### Required context

- `AGENTS.md`, including any authoring rules it cites.
- `../orchestration/docs/development/local-environment.md#redis-local-access`. Phase 2 creates
  this anchor.
- `../orchestration/docs/architecture/session-edge-authorization-pattern.md#shared-session-contract`.

### Execution steps

1. In `AGENTS.md` Quick Commands, remove the two Secret reads and the two `kubectl exec ...
   redis-cli` commands. Add one line saying that `redis-session` inspection uses the `redis-ops`
   procedure in [orchestration's Redis local access](../orchestration/docs/development/local-environment.md#redis-local-access).
   Keep the health, log and OAuth commands.
2. Under "Session Not Persisting", point "Inspect Redis session keys..." to the same link.
3. Under "Session Not Created After Login", keep only the facts Session Gateway owns:
   - The key is `session:` followed by the lowercase hex SHA-256 of the cookie value.
   - The digest command is `printf '%s' "$SESSION_TOKEN" | sha256sum | cut -d' ' -f1`.
   Then say to `HGETALL` that key through the linked procedure.
4. In `docs/security.md`, delete the clause about an optional local reset through the
   orchestration flush script. Keep "No cluster reset is required for this additive hash field."
5. In `docs/session-configuration.md`, delete the sentence telling readers to run the flush
   script on an existing cluster. Keep the statements that raw-token keys are unreachable, that
   there is no migration path, and that both services deploy hashed keys together.
6. In `docs/local-development.md`:
   - Remove the `kubectl port-forward ... redis-session-0 6379:6379` line. Tilt already forwards
     VM-loopback `6379` to `redis-session`.
   - State that in the comment, and keep the permission-service forward.

### Implementation notes

The steps 4 and 5 cutover already happened, and no production environment exists, so the reset
instruction has no remaining reader. Removing it is the fix.

### Validation

- `rg -n "flush-redis|ops-username|scripts/ops/" AGENTS.md docs` returns nothing.
- `rg -n "port-forward.*6379" docs AGENTS.md` returns nothing.
- Each new link resolves to an existing file, and the anchor matches a heading in it.

### Completion criteria

- No nonexistent Secret key is read.
- No orchestration script path appears.
- No colliding port-forward is shown.

## Phase 8: ext-authz README

### Workspace

../ext-authz

### Goal

The README carries no orchestration script path.

### Scope

`README.md`, the paragraph on hashed session keys near line 18.

### Non-goals

Any other change.

### Required context

`README.md`, the session key paragraph.

### Execution steps

1. Delete the clause "after switching to hashed keys, flush existing sessions with
   `../orchestration/scripts/ops/flush-redis.sh`".
2. End the sentence at "There is no fallback to raw-token keys."

### Implementation notes

The same reasoning as Phase 7 steps 4 and 5 applies: the cutover is complete.

### Validation

`rg -n "flush-redis|scripts/ops/" README.md docs` returns nothing.

### Completion criteria

The README states that there is no fallback, without a script reference.

## Phase 9: Web Client End-Date Comments

### Workspace

../budget-analyzer-web

### Goal

The exchange-rate API comments match the tomorrow cap and no longer promise a rate for every
date.

### Scope

- The `getExchangeRates` doc comment in `src/api/currencyApi.ts`.
- The comment in `src/hooks/useCurrencies.ts` near lines 49 and 50.

### Non-goals

- Runtime changes.
- Editing `docs/api/*.yaml`. Phase 10's generator run owns those files.

### Required context

- `AGENTS.md`, including the validation rules for comment-only changes.
- `src/api/currencyApi.ts` and `src/hooks/useCurrencies.ts`.

### Execution steps

1. Rewrite the `getExchangeRates` comment:
   - The response is dense, one rate per date, from the first source rate in range through the
     effective end date.
   - A range with no source rate returns an empty list.
   - An omitted `startDate` means the first available rate.
   - An omitted `endDate` means today (UTC).
   - An `endDate` after tomorrow (UTC) is treated as tomorrow.
2. Make the `useCurrencies.ts` comment state the same end-date rule.

### Implementation notes

A transaction dated tomorrow now receives a rate unless its whole requested range has no source
rate.

### Validation

- `npm run lint:fix`.
- `rg -n "treated as today|guarantees a rate" src` returns nothing.

### Completion criteria

Both comments state the current contract, and lint passes.

## Phase 10: Live Verification, API Docs And Cache Budget

### Workspace

.

### Goal

Prove the changes against the running local stack, regenerate the API docs, and recompute the
`redis-cache` worst case from the largest possible series.

### Scope

- Live checks and focused verifiers.
- `docs-aggregator/` and `../budget-analyzer-web/docs/api/` through the generator.
- The `Redis Memory Budgets` section in `docs/architecture/security-architecture.md`, and the
  high-severity issue doc.

### Non-goals

- Changing `maxmemory`. If the recomputed `W` exceeds half of it, stop and report.
- Flushing `redis-session`.

### Required context

- `AGENTS.md`, sections "Prerequisites First" and "Operating Context" for the mutation
  preconditions.
- `scripts/README.md` for the verifier catalog.
- The `Redis Memory Budgets` section written in Phase 2.

### Execution steps

1. Run `tilt get uiresources`. If it fails, stop with "Start Tilt before Phase 10". Then run
   `./scripts/bootstrap/check-local-runtime.sh`.
2. Confirm the stale policy is gone:
   `kubectl get networkpolicy allow-redis-ingress-from-approved-default-workloads -n infrastructure`
   must return NotFound. If it still exists, run `tilt trigger network-policies-core`, wait, and
   recheck.
3. If `.env` contains a key that `.env.example` does not declare, confirm that the `(Tiltfile)`
   log in `tilt logs` shows the warning and that it names keys only.
4. Run `./scripts/smoketest/verify-credential-isolation.sh`. If the nil or empty-`save` rendering
   differs from what Phase 1 assumed, fix the assertion, rerun `bash -n` and `shellcheck`, and
   rerun the verifier.
5. Run `printf 'y' | ./scripts/ops/flush-redis.sh cache`. It must print success, and
   `redis-cache` `DBSIZE` must be `0` afterwards. Do not run the `session` mode.
6. Through the supported API path, request rates for an enabled currency:
   - `endDate=9999-12-31` ends at tomorrow (UTC).
   - An omitted `endDate` ends at today.
   - Tomorrow's rate equals the last source rate, forward-filled.
7. Recompute the `redis-cache` worst case:
   - With read-only SQL against the currency-service database, find the longest series by days
     between its first source rate and today, over all `currency_series` rows, enabled or not.
   - Estimate its entry size from the measured bytes per day of the THB entry
     (`196,696 / 16,745`).
   - Recompute `W = baseline used_memory + N × largest entry`.
   - Update the `Redis Memory Budgets` section and the high-severity issue with the inputs,
     marking the largest entry as an estimate from measured bytes per day.
8. Run `./scripts/repo/generate-unified-api-docs.sh` with no arguments.
   - This step is the one exception to the single-workspace rule: the generator writes
     `../budget-analyzer-web/docs/api/`.
   - The resulting diffs in `docs-aggregator/` and `../budget-analyzer-web/docs/api/` must be
     limited to the `endDate` description from Phase 3. Report any other drift as a blocker.
9. Run the static security suite through the live wrapper:
   `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python ./scripts/smoketest/verify-security-guardrails.sh`.

### Implementation notes

Apply the `AGENTS.md` mutation preconditions before steps 2, 5 and 8.

If a verifier fails because of a defect in a sibling service, stop and describe the defect. Do
not compensate for it in orchestration.

### Validation

- Steps 2 to 9 produce the expected evidence.
- `verify-credential-isolation.sh` passes.
- The generated-doc diff is limited to the `endDate` text.

### Completion criteria

- The stale policy is gone.
- The new assertions and the flush check pass live.
- The tomorrow cap is observed.
- `W` is recomputed from the largest possible series.
- The API docs are current.

## Phase 11: API Tests End-Date Contract

### Workspace

../budget-analyzer-api-tests

### Goal

The exchange-rate API tests and the OpenAPI snapshot match the tomorrow cap.

### Scope

- `tests/api/exchange_rates/test_exchange_rates.py`.
- `schemas/openapi.json`, refreshed through the repository tool.

### Non-goals

- Other test modules, or any test of the empty-range rule.

### Required context

- `AGENTS.md` and `README.md` for the runner, Ruff, strict mypy and snapshot refresh.
- The far-future and omitted-`endDate` tests in `test_exchange_rates.py`, and
  `_assert_dense_rates_end_today`.

### Execution steps

1. Run `tilt get uiresources`. If it fails, stop with "Start Tilt before Phase 11".
2. Rename `test_get_exchange_rates_caps_future_end_date_at_today` to
   `..._at_tomorrow`. Its acceptable last dates become tomorrow (UTC) captured before and after
   the request.
3. Generalize `_assert_dense_rates_end_today` to take the acceptable end dates. The
   omitted-`endDate` test keeps today.
4. Refresh the snapshot: `.venv/bin/python tools/refresh-openapi.py --env local`. Confirm the
   diff is limited to the `endDate` description.

### Implementation notes

The far-future test starts 30 days back, so its range contains source rates despite the
provider's publication lag.

### Validation

- `.venv/bin/python -m ruff format --check .`
- `.venv/bin/python -m ruff check .`
- strict mypy, as documented in `AGENTS.md`.
- The exchange-rate test module, run through the documented runner against the local stack.

### Completion criteria

- Both end-date tests pass live.
- The snapshot matches the deployed contract.
- Lint and type checks pass.
