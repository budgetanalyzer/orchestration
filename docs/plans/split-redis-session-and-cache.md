# Split Session Redis From The Application Cache

Resolve [the shared Redis exhaustion issue](../issues/high-currency-cache-exhausts-shared-redis.md)
and [the unbounded end date issue](../issues/medium-exchange-rate-end-date-unbounded-response.md).
The single `redis` instance becomes two:

- `redis-session`: the existing instance, renamed. It holds only sessions, session indexes and
  OAuth state for `session-gateway` and `ext-authz`. It stays a StatefulSet with the PVC-backed
  `/data`, AOF and `noeviction`.
- `redis-cache`: new. It holds only the currency-service cache and is shared by all
  currency-service replicas. It is disposable: no PVC, no AOF, no RDB snapshots, `allkeys-lru`.

currency-service caches one forward-filled (dense) exchange-rate series per currency and slices
the requested range in Java. Request date ranges never create cache keys.

## Decisions

These are settled. Do not reopen them in a phase.

- **Cache key:** the currency code. Cache name `exchangeRateSeries`. The old `exchangeRates` cache
  name and its range key are removed.
- **Cached value:** the dense, forward-filled series for one currency from its first source rate to
  its last source rate, stored compactly: the constant fields once (base currency, target
  currency, `providerSeriesId`), the series start date, one rate per day (already normalized to
  USD base) and one published-date offset per day (0 means a source rate on that day).
- **Serializer:** a Jackson serializer bound to the cached value type. No default typing and no
  type ids in cached values. Disable pretty printing on the cache mapper copy.
- **TTL:** 1 hour. Imports keep `@CacheEvict(allEntries = true)` after commit.
- **No reseeding:** the cache is filled lazily on a miss. Do not add `@CachePut` warm-up or import
  events for the cache.
- **Stale-write race:** a read that queried the database before an import committed can write a
  stale series after the eviction, and a failed after-commit eviction leaves the previous series in
  place. The TTL bounds both. Document them in one or two sentences; do not add versioned keys.
- **End date:** the effective end date is `min(endDate, today)`. A missing `endDate` means today.
  "Today" is the UTC date from an injected `java.time.Clock`. When both dates are supplied,
  `startDate > endDate` is an error, checked against the original inputs before clamping. A valid
  future range that becomes empty after clamping returns an empty list.
- **Fail open:** cache `get`, `put`, `evict` and `clear` errors are logged and the request is
  served from the database; a successful database operation never fails because of the cache,
  including deferred after-commit writes and evictions. Fail-open handling lives in a `Cache`
  decorator that wraps the Redis cache directly, beneath the transaction-aware decorator, so that
  each cache is `TransactionAwareCacheDecorator(FailOpenCache(RedisCache))`. Do not use a
  `CacheErrorHandler`: Spring's transaction-aware decorator runs deferred `put`, `evict` and
  `clear` in `afterCommit`, outside the annotation-level handler, and exceptions there propagate
  to the caller. Redis is not part of currency-service readiness. Redis connect and command
  timeouts are short.
- **Local ports:** both Kubernetes Services listen on `6379`. Tilt forwards VM-loopback `6379` to
  `redis-session` and VM-loopback `6380` to `redis-cache`. currency-service's local `bootRun`
  workflow uses `localhost:6380`; its `application.yml` port default stays `6379` because the
  Kubernetes deployment sets the port explicitly.
- **Naming:** directories `kubernetes/infrastructure/redis-session/` and
  `kubernetes/infrastructure/redis-cache/`; Services, labels (`app: ...`) and Tilt resources
  `redis-session` and `redis-cache`; hosts `redis-session.infrastructure` and
  `redis-cache.infrastructure`; TLS secrets `infra-tls-redis-session` and `infra-tls-redis-cache`;
  bootstrap Secrets `redis-session-bootstrap-credentials` and `redis-cache-bootstrap-credentials`;
  ACL ConfigMaps `redis-session-acl-bootstrap` and `redis-cache-acl-bootstrap`.
- **Credentials:** the `default` and `redis-ops` users exist on both instances with separate
  passwords: `REDIS_SESSION_DEFAULT_PASSWORD`, `REDIS_SESSION_OPS_PASSWORD`,
  `REDIS_CACHE_DEFAULT_PASSWORD`, `REDIS_CACHE_OPS_PASSWORD`. Application users exist on exactly
  one instance, so `REDIS_SESSION_GATEWAY_PASSWORD`, `REDIS_EXT_AUTHZ_PASSWORD` and
  `REDIS_CURRENCY_SERVICE_PASSWORD` keep their names, as do the client Secrets
  `session-gateway-redis-credentials`, `ext-authz-redis-credentials` and
  `currency-service-redis-credentials`. `REDIS_DEFAULT_PASSWORD` and `REDIS_OPS_PASSWORD` are
  removed everywhere.
- **No stale references:** after this plan, no active file in orchestration, currency-service,
  service-common, session-gateway or ext-authz refers to the old instance name, host, labels,
  Secrets, ConfigMap, TLS secret, PVC, environment variables or the range cache key. Defaults in
  sibling configuration and code change too. `docs/archive/`, `archive/` and `docs/decisions/`
  are excluded and must not be edited.

## Rules

- Follow each workspace's `AGENTS.md`. No git write operations.
- Never run `scripts/bootstrap/setup-infra-tls.sh`, `mkcert`, or any `openssl` generation command,
  and never trigger the Tilt `infra-tls-prerequisites` resource. Editing those scripts is allowed.
- Phases 1 to 8 are static work. Do not mutate the cluster or run `tilt up` in them.
- Tilt must be stopped before Phase 1 and stay stopped through Phase 8. A running Tilt watches the
  Tiltfile, manifests and sibling sources and would deploy partial changes before the new
  certificates and credentials exist. Each of Phases 1 to 8 first runs `tilt get uiresources`; if
  it succeeds, stop and report "Tilt is running; stop it before continuing". Do not stop Tilt from
  the agent.
- Every changed shell script passes `bash -n` and `shellcheck`.
- No compatibility shims, fallbacks to old names, or legacy aliases. The one-time cutover below is
  a human procedure recorded only in this plan.

## Before Phase 1 (human)

Stop Tilt (Ctrl-C in its terminal, or `tilt down`) and keep it stopped until step 5 of the Human
Cutover. Workloads already in the cluster may keep running.

## Human Cutover (between Phase 8 and Phase 9)

Phase 9 stops if these have not been done. The user runs them from a human-operated shell against
the local Kind cluster, after Phases 1 to 8 are complete:

1. Confirm Tilt is still stopped: `tilt get uiresources` must fail.
2. Rename `REDIS_DEFAULT_PASSWORD` and `REDIS_OPS_PASSWORD` in `.env` to the `REDIS_SESSION_*`
   names and add `REDIS_CACHE_DEFAULT_PASSWORD` and `REDIS_CACHE_OPS_PASSWORD`, following
   `.env.example`.
3. Remove the old instance and its data (this logs everyone out once):

   ```bash
   kubectl config current-context   # must print kind-kind
   kubectl delete -n infrastructure statefulset/redis service/redis \
     configmap/redis-acl-bootstrap secret/redis-bootstrap-credentials \
     secret/infra-tls-redis pvc/redis-data-redis-0 --ignore-not-found
   rm -f nginx/certs/infra/redis.pem nginx/certs/infra/redis.key
   ```

4. Issue the two new leaf certificates from the existing infrastructure CA:
   `./scripts/bootstrap/setup-infra-tls.sh`
5. `./scripts/bootstrap/check-infra-tls-secrets.sh`, then `tilt up`.

## Phase 1: Per-Currency Series Cache And End-Date Semantics

### Workspace

../currency-service

### Goal

`ExchangeRateService.getExchangeRates` is no longer `@Cacheable`. It reads a per-currency dense
series from a separate cached bean and slices the requested range, with the new end-date
semantics. The cached value is compact and uses a type-bound serializer.

### Scope

- A compact `ExchangeRateSeries` record in `service.dto`, as described in the plan decisions.
  Use types that Jackson round-trips without type ids.
- A separate concrete `ExchangeRateSeriesService` in `service`, annotated `@Service`, with
  `@Cacheable(cacheNames = CacheConfig.EXCHANGE_RATE_SERIES_CACHE, key = "#currencyCode")` and
  `@Transactional(readOnly = true)`. It loads every rate for the currency in date order and builds
  the dense series from the first to the last source rate, applying the existing USD-base
  normalization from `ExchangeRateData.from`. When the currency has no rates it throws the
  existing `NO_EXCHANGE_RATE_DATA_AVAILABLE` `BusinessException`; exceptions are not cached.
  Do not add an interface or use the external-integration `*Provider` naming pattern.
- Keep the controller's original-input date-order validation: when both dates are supplied and
  `startDate > endDate`, return `400 INVALID_REQUEST` before invoking the service. Preserve the
  existing service precondition and its `IllegalArgumentException` for direct callers, including
  `queryWithStartAfterEndThrowsException`. Do not repeat this validation in the cached series
  service. Clamping must not turn an invalid input range into a successful empty response.
- `ExchangeRateService.getExchangeRates`, uncached, after that original-input precondition:
  1. reject a disabled currency with `CURRENCY_NOT_ENABLED` (uncached lookup);
  2. fetch the cached series;
  3. compute `today` from an injected UTC `Clock`; effective end is today when `endDate` is null,
     otherwise `min(endDate, today)`; effective start is the series start when `startDate` is null;
  4. reject a `startDate` before the series start with `START_DATE_OUT_OF_RANGE`;
  5. return an empty list when the effective start is after the effective end, or when no source
     rate (published-date offset 0) falls in the range;
  6. otherwise return one `ExchangeRateData` per day, indexing by `date - seriesStart` and
     forward-filling the last element, with its published date, for days after the series end.
- `CacheConfig`: replace `EXCHANGE_RATES_CACHE` with `EXCHANGE_RATE_SERIES_CACHE =
  "exchangeRateSeries"`; replace the default-typing `GenericJacksonJsonRedisSerializer` with a
  serializer bound to the series type, built from a copy of the application `JsonMapper`. Disable
  `SerializationFeature.INDENT_OUTPUT` on that copy; the application mapper enables pretty
  printing, which needlessly enlarges cache values. Keep the application mapper unchanged, the
  1-hour TTL, the `currency-service:` prefix, `immediateWrites()`, `SCAN` batch clears and
  `transactionAware()` (Phase 2 changes how transaction awareness is applied).
- `ExchangeRateImportService`: point the three `@CacheEvict` annotations at the new cache name and
  update the javadoc that justifies global eviction with range-key `SCAN` patterns.
- A `Clock` bean (UTC) if the service does not already have one.
- The controller's OpenAPI description for `endDate`: defaults to today; dates after today are
  treated as today (UTC). Document that reversed input dates remain an error before clamping.

### Non-goals

- Cache error handling, Redis timeouts and readiness (Phase 2).
- Orchestration changes.
- Reseeding the cache on import, versioned keys, or per-currency eviction.

### Required context

- `../orchestration/docs/issues/high-currency-cache-exhausts-shared-redis.md`, sections
  "Chosen approach" and "Semantics to preserve"
- `../orchestration/docs/issues/medium-exchange-rate-end-date-unbounded-response.md`
- `src/main/java/org/budgetanalyzer/currency/service/ExchangeRateService.java`
- `src/main/java/org/budgetanalyzer/currency/config/CacheConfig.java`
- `src/main/java/org/budgetanalyzer/currency/service/ExchangeRateImportService.java`
- `src/main/java/org/budgetanalyzer/currency/api/ExchangeRateController.java`
- `ExchangeRateServiceIntegrationTest`, `ExchangeRateImportCacheIntegrationTest`,
  `ExchangeRateCacheEvictionAclIntegrationTest`, `ExchangeRateImportServiceIntegrationTest`,
  `ExchangeRateControllerIntegrationTest`
- `../service-common/docs/code-quality-standards.md`,
  `../service-common/docs/spring-boot-conventions.md` (service naming and records),
  `../service-common/docs/testing-patterns.md` (unit and integration testing)

### Execution steps

1. Read the current service, cache config, import service and the listed tests. List every test
   that asserts a null-`endDate`-means-last-rate or unbounded-`endDate` behavior.
2. Add the series record, the concrete series service and the `Clock` bean.
3. Rewrite `getExchangeRates` as specified and delete the code it replaces (the range
   specification and the lookback query, if no longer used).
4. Update `CacheConfig` and the import service eviction annotations.
5. Update the tests: preserve every existing case except the deliberate null-end and clamp
   changes, which are changed explicitly. Add tests for: far-future `endDate` clamped to today;
   null `endDate` forward-filling to today; repeated requests for different ranges of one currency
   creating exactly one cache key; a currency disabled after its series was cached being rejected;
   the cached value round-tripping through the configured serializer. Use a fixed `Clock` in
   tests. Cover reversed original dates (including both dates in the future) returning `400`,
   and valid future ranges becoming empty after clamping. Preserve the direct service
   reversed-date exception test.
6. Update the eviction tests' key patterns to `currency-service:exchangeRateSeries::*`. Replace
   arbitrary string and integer cache values with a reusable valid `ExchangeRateSeries` fixture,
   including the import service tests and their rollback case. Assert the entry is present and
   readable before the import, then absent after commit or unchanged after rollback. Preserve
   the ACL test's multi-batch SCAN coverage and unrelated-key assertion.

### Implementation notes

- Call the cached method on the separate bean so the Spring proxy applies.
- The cached series ends at the last source rate. Forward-filling to today happens per request, so
  the cached value does not change at midnight.
- A request with correctly ordered original dates entirely in the future ends with an effective
  end before its start and returns an empty list, which keeps
  `queryForFutureDateRangeReturnsEmptyList` passing. An originally reversed range remains an
  error even when both dates are in the future.

### Validation

```bash
./gradlew clean spotlessApply
./gradlew clean build
rg -n "EXCHANGE_RATES_CACHE|exchangeRates::|DefaultTyping|startDate \+ ':'" src
```

The `rg` command returns no matches.

### Completion criteria

`./gradlew clean build` passes. The only `@Cacheable` for exchange rates is keyed by currency
code. No default typing remains in the cache serializer. Changed tests document the end-date
behavior change.

## Phase 2: Fail-Open Cache And currency-service Documentation

### Workspace

../currency-service

### Goal

A failing or unreachable cache makes requests slower, not failed, and does not affect readiness.
currency-service documentation describes the new cache and end-date behavior.

### Scope

- A fail-open `Cache` decorator, for example `FailOpenCache`, that wraps the Redis cache and
  delegates every `Cache` method. Read and write failures are logged at `WARN` with the cache name
  and key (no key for `clear`) and not rethrown: a failed read is a miss, a failed write or
  eviction is a no-op. Loader exceptions from `get(key, Callable)` still propagate.
- `CacheConfig`: remove `transactionAware()` from the `RedisCacheManager` builder and apply the
  decoration explicitly, so that each cache the manager returns is
  `TransactionAwareCacheDecorator(FailOpenCache(redisCache))` (for example by overriding
  `decorateCache` in a `RedisCacheManager` subclass). Deferred after-commit operations then run
  through the fail-open layer. Do not add a `CacheErrorHandler` or `CachingConfigurer`.
- Register the custom Redis cache manager only when `spring.cache.type=redis`, leaving Boot's
  no-op manager active for `spring.cache.type=none`, as used by most tests. Pass the typed
  `RedisCacheConfiguration` and the writer configured with `immediateWrites()` and SCAN batches
  directly to the custom manager. A manually created manager does not receive Boot's
  `RedisCacheManagerBuilderCustomizer` automatically; remove the superseded customizer instead
  of leaving unused configuration. Update documentation of supported cache properties to match
  the explicit configuration.
- `application.yml`: remove `redis` from the readiness group; set
  `spring.data.redis.timeout` and `spring.data.redis.connect-timeout` to short values (about 1 s;
  state the chosen values and why in `docs/configuration.md`).
- Update the cache-related javadoc in `CacheConfig` and `ExchangeRateService`, including one or two
  sentences on the stale-write race bounded by the TTL.
- Update the currency-service docs that describe caching, Redis or the exchange-rate endpoint:
  discover them with `rg -n -i "cache|redis|endDate|end date" README.md AGENTS.md docs`. Describe
  Redis as the dedicated `redis-cache` instance, not a shared or session instance.
- Local development: `docs/local-development.md` exports and `README.md` point `bootRun` at the
  `redis-cache` VM-loopback forward on `localhost:6380`, and `docs/configuration.md` states the
  local cache endpoint as `localhost:6380`. The `application.yml` port default stays `6379`.

### Non-goals

- Circuit breakers or local fallback caches.
- Orchestration manifests.

### Required context

- `src/main/java/org/budgetanalyzer/currency/config/CacheConfig.java`
- `src/main/java/org/budgetanalyzer/currency/service/ExchangeRateImportService.java`
- `src/main/resources/application.yml`
- `src/test/resources/application.yml`, `AbstractIntegrationTest`,
  `RuntimeConfigurationIntegrationTest`, `ExchangeRateImportServiceIntegrationTest`
- `../service-common/docs/testing-patterns.md` (real application beans, framework fakes,
  integration tests and Testcontainers)
- `docs/local-development.md`, `docs/configuration.md`,
  `docs/advanced-patterns-usage.md`, `docs/api/README.md`,
  `docs/domain-model.md`, `README.md`, `AGENTS.md`

### Execution steps

1. Add the fail-open decorator and the explicit, conditional cache manager configuration. Verify
   `spring.cache.type=none` still selects a no-op manager and Redis-enabled tests exercise the
   decorated manager.
2. Change readiness and timeouts. Update `RuntimeConfigurationIntegrationTest` so Redis is absent
   from readiness and stopping Redis leaves readiness `UP`; preserve PostgreSQL failure and
   liveness coverage. Reuse its dedicated containers and production-configuration loading
   pattern: the ordinary test `application.yml` shadows the shipped configuration. Never stop
   the shared reusable Redis container to simulate an outage.
3. Add unit tests for the decorator: each `Cache` method swallows a Redis failure and returns the
   miss or no-op result. Use a small concrete failing implementation of the framework `Cache`
   interface, and verify loader exceptions still propagate.
4. Add integration tests with the cache Redis unreachable or failing (stopped or blocked
   container, or the cache pointed at an unreachable port):
   - `GET /v1/exchange-rates` returns the database result with `200` and the readiness group
     stays `UP`;
   - a cache miss whose deferred `put` fails after commit still returns the database result;
   - an import whose deferred after-commit `clear` fails completes successfully and its rows are
     committed.
   For the deferred-operation cases, invoke the real proxied service inside an explicit enclosing
   `TransactionTemplate` transaction (read-only for the query). This ensures the cache interceptor
   runs inside the transaction regardless of advisor ordering. Prove the operation is deferred:
   before the enclosing transaction commits, assert no `put`/`clear` failure warning has occurred;
   after it commits, assert the operation-specific warning and the successful result. Verify
   imported rows from a separate transaction after commit. Retain the HTTP outage case above to
   prove the endpoint returns `200`.
   Use real Redis failure conditions, such as an unreachable dedicated container or restricted
   ACLs, and capture the cache name, operation and applicable key in WARN logs. Do not replace or
   spy application-owned beans. A successful response or a generic cache warning alone does not
   prove an after-commit failure was handled.
5. Update javadoc and documentation.

### Implementation notes

A cache outage still costs up to the command timeout per request; that is the accepted "slower"
mode. Keep the `redis` health contributor available outside the readiness group. Fail-open must
not depend on the relative order of the transaction and cache interceptors.

### Validation

```bash
./gradlew clean spotlessApply
./gradlew clean build
rg -n -i "shared redis|session" docs README.md AGENTS.md | rg -i redis
rg -n "CacheErrorHandler|CachingConfigurer|\.transactionAware\(\)" src/main
```

Review the first `rg` output; no remaining text may describe the cache as sharing Redis with
sessions. The second returns nothing.

### Completion criteria

Build passes, cache-disabled tests retain the no-op manager, and the fail-open tests prove reads,
deferred writes and after-commit import eviction succeed despite cache failures. Readiness excludes
Redis while retaining PostgreSQL failure coverage, local development targets `localhost:6380`, and
the docs match the code.

## Phase 3: service-common Caching Pattern Documentation

### Workspace

../service-common

### Goal

The shared caching pattern stops recommending cache keys built from request parameters such as
date ranges and reflects the pattern currency-service now uses.

### Scope

- `docs/advanced-patterns.md`, section "Redis Distributed Caching", and the caching lines in
  `AGENTS.md`.
- `docs/common-patterns.md`, section "Implement Caching Where Appropriate": replace its
  date-range `@Cacheable` example with a short relative link to the canonical Redis caching
  section in `advanced-patterns.md`. Spring's default key includes all method arguments, so
  omitting an explicit `key` still produces the unbounded range-key pattern.
- Replace the range-key example and the "include all query parameters" key-design rule with: key by
  a bounded domain identifier, cache the expensive derived data set, slice per request in Java.
- Replace the default-typing serializer example with a type-bound serializer.
- Add fail-open caching as a `Cache` decorator beneath the transaction-aware decorator, with the
  reason (a `CacheErrorHandler` does not cover deferred after-commit writes and evictions), short
  Redis timeouts, and keeping Redis out of readiness.
- State that caches belong on a dedicated Redis with an eviction policy, never on the
  `noeviction` session instance.
- Remove the "TTL also bounds memory for keys built from arbitrary parameters" guidance; keep the
  stale-race TTL guidance.

### Non-goals

Code changes in service-common.

### Required context

- `docs/advanced-patterns.md` ("Redis Distributed Caching")
- `docs/common-patterns.md` ("Implement Caching Where Appropriate")
- `AGENTS.md` caching references
- `../orchestration/docs/agents-md-checkstyle.md` before editing `AGENTS.md`
- `docs/code-quality-standards.md`, `docs/spring-boot-conventions.md`, and
  `docs/testing-patterns.md`
- `../currency-service/src/main/java/org/budgetanalyzer/currency/config/CacheConfig.java` as
  updated by Phases 1 and 2
- The completed currency-service series service, fail-open decorator, and tests from Phases 1
  and 2: bounded keys, typed serialization, commit/rollback eviction, deferred-operation failures,
  HTTP outage behavior, and readiness

### Execution steps

1. Confirm Phases 1 and 2 are complete. Read the shared caching guidance and the updated
   currency-service implementation and tests. Stop and report missing prerequisites rather than
   documenting the planned behavior as implemented.
2. Rewrite the canonical caching section and replace the `common-patterns.md` example with its
   pointer. Read and apply the AGENTS.md checkstyle before updating the `AGENTS.md` summary lines.
3. Compare the replacement guidance with the completed implementation and executable test cases.
   Verify the decorator ordering, synchronous writes, SCAN clears, serializer, supported cache
   properties, timeouts, readiness, and TTL limitations. Confirm the tests use concrete framework
   fakes and real application beans with dedicated Redis failure conditions, without mocking or
   spying application-owned beans. Report discrepancies rather than copying them into guidance.

### Implementation notes

Keep the section pattern-level. Link to currency-service for the concrete implementation instead of
copying it in full.

### Validation

```bash
rg -n "startDate|endDate|DefaultTyping|NON_FINAL|arbitrary parameters|exchangeRates" \
  docs/advanced-patterns.md docs/common-patterns.md AGENTS.md
rg -n -i 'cache|redis' docs/advanced-patterns.md docs/common-patterns.md AGENTS.md
```

No first-command match remains in the caching sections. Review all caching references from the
second command, including annotations with implicit keys, for consistency with the canonical
pattern. Verify the new relative link resolves and the `AGENTS.md` changes satisfy the checkstyle.
Record the implementation and test files reviewed and which cases support the documented behavior;
an empty search alone is not proof of correctness. This documentation-only phase reviews the
Phase 1 and 2 test evidence without adding tests or rerunning sibling builds.

### Completion criteria

The caching section describes the bounded-key, dedicated-instance, fail-open pattern and matches
the completed currency-service implementation and tests. `common-patterns.md` points to that
canonical guidance without retaining a range-key example, and the `AGENTS.md` summary complies
with its checkstyle.

## Phase 4: Rename The Session Instance To redis-session

### Workspace

.

### Goal

The existing Redis instance is `redis-session` everywhere in orchestration: manifests, Tilt,
Secrets, TLS, network policies, ops scripts, verifiers and guardrails. currency-service still
connects to it at the end of this phase; Phase 5 moves it.

### Scope

- Move `kubernetes/infrastructure/redis/` to `kubernetes/infrastructure/redis-session/`. Rename
  the StatefulSet, `serviceName`, Service, labels, container and volume names, ConfigMap, Secret
  and TLS secret references as in the plan decisions. The PVC template stays `redis-data`, so the
  new claim is `redis-data-redis-session-0`.
- `kubernetes/infrastructure/kustomization.yaml` and
  `kubernetes/production/infrastructure/kustomization.yaml` (patch target `redis-session`; rename
  the patch file if its name refers to the instance).
- `Tiltfile`: resource name, objects, `redis_host`, Secret names, `REDIS_SESSION_*` variables, and
  `resource_deps` of `session-gateway`, `ext-authz` and `currency-service`. The port forward stays
  `6379` and is renamed `redis-session`.
- `kubernetes/services/*/deployment.yaml` hosts: `redis-session.infrastructure`.
- Network policies: selectors and policy names.
- `scripts/bootstrap/setup-infra-tls.sh` (`SERVICES`, secret creation, output listing),
  `check-infra-tls-secrets.sh`, `check-tilt-prerequisites.sh`.
- `scripts/lib/redis-cli.sh` takes the target instance (`redis-session` or `redis-cache`) as an
  explicit argument with no default; `scripts/ops/flush-redis.sh` and
  `scripts/ops/redis-browse.sh` require an explicit `session` or `cache` argument. Update every
  caller.
- Every other active script, verifier, guardrail, inventory and fixture that names the instance:
  `scripts/smoketest/*`, `scripts/loadtest/*`, `scripts/lib/*` (including
  `image-pinning-targets.txt`, `runtime-support-windows.txt`, `secrets-only-expected-keys.txt`),
  `scripts/guardrails/*`, `kubernetes/kyverno/tests/`, `renovate-presets/`, `setup.sh`,
  `.env.example`.

### Non-goals

- Adding `redis-cache` (Phase 5).
- Prose documentation outside files that must change for scripts to stay correct (Phase 8 owns the
  documentation sweep).
- Running anything against the cluster.

### Required context

- `AGENTS.md` (Shell Script Validation, SSL/TLS Certificate Constraints, Image Pinning)
- `scripts/README.md`
- `kubernetes/infrastructure/redis/*`, `kubernetes/network-policies/*.yaml`, `Tiltfile`
- `docs/development/secrets-only-handling.md` for the secrets inventory contract

### Execution steps

1. Inventory references:

   ```bash
   rg -n -P --glob '!docs/**' --glob '!archive/**' \
     -e "redis\.infrastructure" -e "app[:=] ?redis(?![-\w])" -e "(?<![-\w])redis-0" \
     -e "infra-tls-redis(?![-\w])" -e "redis-acl-bootstrap" -e "redis-bootstrap-credentials" \
     -e "(statefulset|svc|service|pod|deployment)/redis(?![-\w])" -e "'redis'" \
     -e "REDIS_(DEFAULT|OPS)_PASSWORD" -e "infrastructure/redis/" -e "redis-data-redis-0"
   ```

2. Apply the renames and the credential split for the session instance.
3. Parameterize the Redis ops helper and scripts; update callers.
4. Rerun the inventory until it returns nothing outside `docs/`.

### Implementation notes

`kubernetes/production/docs-aggregator/` contains generated artifacts; do not hand-edit them.

### Validation

```bash
kubectl kustomize kubernetes/infrastructure >/dev/null
kubectl kustomize kubernetes/production/infrastructure >/dev/null
./scripts/guardrails/check-image-pinning.sh
./scripts/guardrails/check-secrets-only-handling.sh
./scripts/guardrails/check-tilt-resource-roots.sh
./scripts/guardrails/verify-production-image-overlay.sh
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
```

Plus `bash -n` and `shellcheck` on every changed script, and the Step 1 inventory returning nothing
outside `docs/`.

### Completion criteria

All static checks pass. Outside `docs/`, nothing refers to the old instance name.

## Phase 5: Add redis-cache And Move currency-service To It

### Workspace

.

### Goal

A dedicated, disposable `redis-cache` instance exists with its own ACL, TLS, network policy,
Tilt resource, production-reference entry and verifier coverage. currency-service uses it, and has
no access to `redis-session`.

### Scope

- `kubernetes/infrastructure/redis-cache/`: a `Deployment` (one replica) and `Service`, using the
  same pinned `redis:7-alpine` digest, the same pod and container security context as
  `redis-session`, TLS from `infra-tls-redis-cache` and `infra-ca`, and a start script with:
  `--maxmemory 64mb --maxmemory-policy allkeys-lru --appendonly no --save ""`, `--dir` on an
  `emptyDir`, and ACL users `currency-service` (the rule set currency-service has today on the
  session instance), `redis-ops` and `default` (as on the session instance). Requests and limits
  sized for the 64 MB budget.
- Remove the `currency-service` user from the `redis-session` ACL and its key from
  `redis-session-bootstrap-credentials`.
- `kustomization.yaml` entries and `redis-cache-acl-bootstrap` generator; the production overlay
  includes it through the base, with no storage patch.
- `Tiltfile`: `redis-cache` resource with the VM-loopback port forward
  `port_forward(6380, 6379, name='redis-cache')`, `redis-cache-bootstrap-credentials`,
  `REDIS_CACHE_*` variables, currency-service `resource_deps` on `redis-cache` instead of
  `redis-session`.
- `kubernetes/services/currency-service/deployment.yaml`: host `redis-cache.infrastructure`.
- Network policies: currency-service egress only to `redis-cache`; `redis-cache` ingress only from
  currency-service; `redis-session` ingress no longer allows currency-service.
- `setup-infra-tls.sh`, `check-infra-tls-secrets.sh`, `check-tilt-prerequisites.sh`: add
  `redis-cache`.
- Inventories and guardrails: `image-pinning-targets.txt`, `runtime-support-windows.txt`,
  `secrets-only-expected-keys.txt`, `check-tilt-resource-roots.sh`.
- Verifiers: extend `verify-credential-isolation.sh`, `verify-network-policies.sh`,
  `verify-transport-encryption.sh`, `verify-runtime-security-guardrails.sh`,
  `verify-runtime-hardening.sh` and `cleanup-smoketest-residue.sh` where they enumerate Redis
  instances or users, so they prove: currency-service cannot authenticate to or reach
  `redis-session`; `session-gateway` and `ext-authz` cannot reach `redis-cache`; `redis-cache`
  requires TLS.
- `.env.example`: `REDIS_CACHE_DEFAULT_PASSWORD`, `REDIS_CACHE_OPS_PASSWORD`, and
  `REDIS_CURRENCY_SERVICE_PASSWORD` described as a `redis-cache` user.

### Non-goals

- Prose documentation sweep (Phase 8).
- Cluster mutation.

### Required context

- `AGENTS.md` (Production-Reference Parity, Image Pinning, Observability rules for port forwards)
- `kubernetes/infrastructure/redis-session/` from Phase 4
- `docs/architecture/port-reference.md`
- `docs/development/secrets-only-handling.md`
- `scripts/README.md` for each verifier's contract

### Execution steps

1. Create the `redis-cache` manifests and start script.
2. Split the ACLs and credentials.
3. Wire Tilt, network policies, TLS scripts and inventories.
4. Extend the verifiers.
5. Run the validation.

### Implementation notes

- The lack of persistence is deliberate: this is a cache. Say so in a comment in the manifest so
  the "no `emptyDir` in place of StatefulSets" guardrail in `AGENTS.md` is not misapplied.
- 64 MB is provisional; Phase 9 measures the real worst case and adjusts it.

### Validation

Same commands as Phase 4, plus `bash -n` and `shellcheck` on every changed script, and:

```bash
rg -n "currency-service" kubernetes/infrastructure/redis-session/
rg -n "redis-session" kubernetes/services/currency-service/
```

Both return nothing.

### Completion criteria

All static checks pass. The two instances are separate in ACL, credentials, network policy and
TLS, and the verifiers cover the separation.

## Phase 6: session-gateway Defaults And Documentation

### Workspace

../session-gateway

### Goal

No session-gateway configuration default or document refers to the old Redis instance.

### Scope

- `src/main/resources/application-kubernetes.yml`: default host `redis-session.infrastructure`
  (or the fully qualified form already used by orchestration).
- `docs/local-development.md`, `docs/configuration.md`, `AGENTS.md`: pod `redis-session-0`, label
  `app=redis-session`, the `redis-session` port forward, the instance name.
- Any other reference found by the inventory below.

### Non-goals

Session logic changes. Testcontainers `@ServiceConnection(name = "redis")` refers to the image and
stays.

### Required context

- `AGENTS.md`
- `../orchestration/docs/plans/split-redis-session-and-cache.md` decisions

### Execution steps

1. `rg -n -P 'redis\.infrastructure|(?<![-\w])redis-0|app=redis(?![-\w])|SPRING_DATA_REDIS_HOST:redis\}|pod/redis(?![-\w])' .`
2. Update each match.

### Implementation notes

None.

### Validation

```bash
./gradlew clean spotlessApply
./gradlew clean build
```

Rerun the Step 1 inventory; it returns nothing.

### Completion criteria

Build passes and the inventory is empty.

## Phase 7: ext-authz Default And Documentation

### Workspace

../ext-authz

### Goal

ext-authz's `REDIS_ADDR` default and documentation name `redis-session`.

### Scope

- `config.go`: default `redis-session.infrastructure:6379`.
- Tests asserting the default.
- `README.md` and `AGENTS.md` references.

### Non-goals

Any other ext-authz behavior.

### Required context

- `AGENTS.md`, `config.go`, `config_test.go`, `README.md`

### Execution steps

1. `rg -n -P "redis\.infrastructure|(?<![-\w])redis-0|app=redis(?![-\w])" .`
2. Update the default, tests and docs.

### Implementation notes

`session.go` derives the TLS server name from `REDIS_ADDR`; the new certificate's SANs include
`redis-session.infrastructure`, so no TLS code change is needed.

### Validation

```bash
go test ./...
```

Rerun the Step 1 inventory; it returns nothing.

### Completion criteria

Tests pass and the inventory is empty.

## Phase 8: Orchestration Documentation Sweep And Static Gate

### Workspace

.

### Goal

All active orchestration documentation describes two Redis instances with separate roles, the two
issues record their resolution, and a cross-repo inventory finds no stale reference.

### Scope

- `AGENTS.md` (topology line, Redis PVC guardrail, `flush-redis.sh` usage, stateful patterns
  rule), applying `docs/agents-md-checkstyle.md`.
- `README.md`, `SECURITY.md`, `deploy/README.md`, `kubernetes/production/README.md`,
  `scripts/README.md`, `nginx/README.md`, `nginx/includes/backend-headers.conf` comments,
  `kubernetes/istio/ingress-exact-origin.yaml` comments, `docs/OWNERSHIP.md`, `docs/ci-cd.md`.
- `docs/architecture/*` (system overview, security architecture, port reference with the
  `redis-session` VM-loopback forward on `6379` and the `redis-cache` forward on `6380`, session
  edge authorization pattern, session security benefits, observability, deployment
  architecture), `docs/development/*`, `docs/runbooks/*`.
- Open issue and plan documents in `docs/issues/` and `docs/plans/` that name the instance, its
  paths or its scripts.
- `docs/issues/high-currency-cache-exhausts-shared-redis.md`: replace "Chosen approach" with the
  implemented design (dedicated `redis-cache`, per-currency series, fail-open), keep the problem
  analysis, and mark it resolved pending Phase 9 verification. Correct the statement that ShedLock
  needs Redis; it uses PostgreSQL.
- `docs/issues/medium-exchange-rate-end-date-unbounded-response.md`: record the clamp decision and
  the null-means-today rule; mark it resolved pending Phase 9.

### Non-goals

`docs/archive/`, `archive/`, `docs/decisions/`. Generated `docs-aggregator` artifacts (Phase 9).

### Required context

- `docs/OWNERSHIP.md`, `docs/agents-md-checkstyle.md`
- The plan decisions above

### Execution steps

1. Inventory documentation references:

   ```bash
   rg -n -i --glob '!docs/archive/**' --glob '!archive/**' --glob '!docs/decisions/**' \
     --glob '!docs/plans/split-redis-session-and-cache.md' --glob '!kubernetes/production/docs-aggregator/**' \
     '\bredis\b' .
   ```

   Review each hit: instance-specific text names `redis-session` or `redis-cache`; generic
   technology mentions may stay.
2. Update the owner documents first, then summaries and links, per `docs/OWNERSHIP.md`.
3. Update the two issue documents.
4. Run the cross-repo stale-reference inventory (read-only on siblings):

   ```bash
   for repo in . ../currency-service ../service-common ../session-gateway ../ext-authz; do
     rg -n -P --glob '!**/build/**' --glob '!docs/archive/**' --glob '!archive/**' \
       --glob '!docs/decisions/**' --glob '!docs/plans/split-redis-session-and-cache.md' \
       --glob '!kubernetes/production/docs-aggregator/**' \
       -e "redis\.infrastructure" -e "app[:=] ?redis(?![-\w])" -e "(?<![-\w])redis-0" \
       -e "infra-tls-redis(?![-\w])" -e "redis-acl-bootstrap" -e "redis-bootstrap-credentials" \
       -e "(statefulset|svc|service|pod)/redis(?![-\w])" -e "REDIS_(DEFAULT|OPS)_PASSWORD" \
       -e "infrastructure/redis/" -e "exchangeRates::" "$repo"
   done
   ```

   It must return nothing. If a sibling match remains, record it as a blocker; do not edit sibling
   repositories from this phase.

### Implementation notes

Keep `AGENTS.md` pattern-based; link to the port reference and architecture docs instead of
listing ports or Secrets.

### Validation

Phase 4 static commands, plus the Step 4 inventory returning nothing.

### Completion criteria

Documentation matches the two-instance design, the issue documents record the resolution, and the
cross-repo inventory is empty.

## Phase 9: Live Cutover Verification And Cache Sizing

### Workspace

.

### Goal

The running local stack proves the separation and the fail-open behavior, the cache's worst-case
size is measured and recorded, and generated API documentation is refreshed.

### Scope

- Verify the human cutover was completed; stop otherwise.
- Run the focused and aggregate verifiers.
- Measure cache entry sizes and set `redis-cache` `maxmemory` from the measurement.
- Refresh the unified API docs for the `endDate` description change by running the generator in
  its normal mode.

### Non-goals

- Certificate generation, `.env` edits, deleting old cluster resources (all human cutover steps).
- Changing the API-doc generator.

### Required context

- `AGENTS.md` (agent cluster mutation preconditions, PyYAML interpreter)
- `docs/architecture/autonomous-ai-execution.md`
- `scripts/README.md`, `docs-aggregator/README.md`
- The Human Cutover section of this plan

### Execution steps

1. Precondition check. Stop and report "human cutover incomplete" if any fails:
   - current context and cluster are `kind-kind` and satisfy the `AGENTS.md` mutation checks;
   - `secret/infra-tls-redis-session` and `secret/infra-tls-redis-cache` exist in
     `infrastructure`; `statefulset/redis`, `secret/infra-tls-redis` and
     `pvc/redis-data-redis-0` do not;
   - `tilt get uiresources` shows `redis-session`, `redis-cache`, `currency-service`,
     `session-gateway` and `ext-authz` healthy.
2. Run `./scripts/bootstrap/check-tilt-prerequisites.sh`, then the focused verifiers changed in
   Phases 4 and 5, then:

   ```bash
   INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
     ./scripts/smoketest/smoketest.sh
   ```

3. Fail-open check: scale `deployment/redis-cache` in `infrastructure` to 0, confirm
   exchange-rate reads return `200` and currency-service pods stay Ready, and confirm login and
   heartbeat still work. Restoring the cache is guaranteed cleanup: whether the checks pass or
   fail, scale it back to 1 and wait for `kubectl rollout status` to succeed before recording a
   result or continuing. Because `redis-cache` has no persistence, it restarts empty.
4. Exercise the cache: confirm with `redis-ops` that `redis-cache` holds no
   `currency-service:exchangeRateSeries::*` keys, then request the full range and two different
   sub-ranges for several enabled currencies through the supported API path. Confirm that exactly
   one `currency-service:exchangeRateSeries::*` key exists per currency requested, with no other
   keys under that prefix, and that `redis-session` holds no `currency-service:*` key.
5. Measure:
   - Record the baseline `used_memory` and `evicted_keys` from `INFO`.
   - Request every enabled currency. Confirm with `EXISTS` that every currency's key is present
     and that `evicted_keys` has not increased. If either check fails, measure one currency at a
     time instead, reading its `MEMORY USAGE` immediately after its request.
   - Record `MEMORY USAGE` for every key, their sum, the largest entry, and the final
     `used_memory`.
   - Count the seeded currencies `N` from the `currency_series` table, not from a hard-coded
     number. Compute the worst case as `W = baseline used_memory + N × largest entry` and record
     the formula with its inputs.
   - If `W` exceeds half of `maxmemory`, raise `maxmemory` to at least `2 × W` and raise the
     container memory request and limit in `kubernetes/infrastructure/redis-cache/` in the same
     proportion to `maxmemory` as the Phase 5 values. After Tilt applies the change, wait for
     `kubectl rollout status`, confirm `CONFIG GET maxmemory` shows the new value, rerun
     `verify-runtime-hardening.sh` and the focused Redis verifiers from Phases 4 and 5, and repeat
     Step 4.
   - Record the measurements, the formula and the chosen value in the port reference or system
     overview (whichever owns Redis sizing per `docs/OWNERSHIP.md`) and in the high-severity issue
     document.
6. Run `./scripts/repo/generate-unified-api-docs.sh` with no arguments. Exception to the
   single-workspace rule: this script normally also writes
   `../budget-analyzer-web/docs/api/budget-analyzer-api.yaml` and `session-gateway-api.yaml`, and
   that write is accepted for this step only. Make no other changes in `../budget-analyzer-web`.
   Confirm that the diffs in `docs-aggregator/` and `../budget-analyzer-web/docs/api/` are limited
   to the currency-service exchange-rate contract changes from Phase 1 (the Session Gateway spec
   should be unchanged). Report any other drift as a blocker.
7. Mark both issue documents resolved with the verification evidence.

### Implementation notes

Steps 3 to 6 mutate or exec into the local cluster; apply the `AGENTS.md` mutation preconditions
before each. If a verifier fails because of a sibling-service defect, stop and describe it; do not
compensate in orchestration. Recording a failed Step 3 check does not skip its cleanup.

### Validation

The smoketest passes; Steps 3 to 6 produce the expected evidence; `redis-cache` is running with
one Ready replica at the end of the phase.

### Completion criteria

Live separation and fail-open behavior are proven, `maxmemory` is set from a recorded measurement
with its formula, the generated API docs are current in `docs-aggregator/` and
`../budget-analyzer-web/docs/api/`, and both issues are marked resolved.

## Phase 10: Web Client End-Date Documentation

### Workspace

../budget-analyzer-web

### Goal

The web client's description of `GET /v1/exchange-rates` matches the new end-date contract.

### Scope

- The `getExchangeRates` doc comment in `src/api/currencyApi.ts`: a rate is returned for every
  date in the range; an omitted `startDate` means the first available rate; an omitted `endDate`
  means today (UTC); an `endDate` after today is treated as today.
- Any other comment or doc in the repository that states the old omitted-`endDate` behavior.

### Non-goals

- Runtime changes. `useCurrencies` passes the transactions' latest date as `endDate`, and that
  behavior stays.
- Changing mocked API responses in tests unless one asserts the old omitted-`endDate` behavior.
- Editing `docs/api/*.yaml`; Phase 9's generator run owns those files.

### Required context

- `AGENTS.md`
- `src/api/currencyApi.ts`, `src/hooks/useCurrencies.ts`
- The end-date decision in this plan's Decisions section

### Execution steps

1. `rg -n -i "endDate|end date|all available rates" src docs README.md AGENTS.md` and list
   statements about server-side end-date behavior.
2. Update those statements.

### Implementation notes

This is a comment-only change unless Step 1 finds a test that encodes the old behavior.

### Validation

```bash
npm run lint:fix
npm run build
```

### Completion criteria

Lint and build pass, and no web document or comment describes an omitted `endDate` as "all
available rates" or the last available rate.

## Phase 11: API Contract Snapshot And End-Date Tests

### Workspace

../budget-analyzer-api-tests

### Goal

The checked-in public contract snapshot reflects the intentional `endDate` description change, and
the public API tests cover the new end-date behavior against the live local stack.

### Scope

- Refresh `schemas/openapi.json` with the documented intentional refresh command, and confirm the
  diff is limited to the currency-service exchange-rate contract changes from Phase 1. Any other
  drift is a blocker to report, not to accept.
- New tests in `tests/api/exchange_rates/`, marked `readonly` and `production_safe` and carrying
  the `getExchangeRates` OpenAPI marker:
  - a far-future `endDate` (for example `9999-12-31`) returns `200`, and the last item's `date` is
    today in UTC;
  - an omitted `endDate` returns items whose last `date` is today in UTC;
  - in both, dates are consecutive with no gaps, and the response length is bounded by the days
    from the first returned date to today.
- Update the README or AGENTS coverage summaries if the coverage counts they state change.

### Non-goals

- Changing the existing January 2025 range test.
- Session Gateway snapshot or inventory changes.
- Redis fault-injection cases in `schemas/session-gateway-inbound-inventory.yaml`.

### Required context

- `AGENTS.md`, `README.md` ("Contract Snapshots And Coverage", "Quality Gates")
- `tests/api/exchange_rates/test_exchange_rates.py`
- The end-date decision in this plan's Decisions section

### Execution steps

1. Confirm the live local stack runs the Phase 1 currency-service (Phase 9 complete). Stop if it
   does not.
2. Refresh the snapshot and review the diff as scoped above.
3. Add the tests, reusing `_first_enabled_target_currency` and the existing assertion helpers.
4. Run the quality gates.

### Implementation notes

To avoid a failure at the UTC midnight boundary, compute the UTC date before and after each request
and accept either value as "today".

### Validation

```bash
.venv/bin/python -m pytest tests/unit --env local
.venv/bin/python tools/check-openapi-coverage.py --env local
.venv/bin/python -m ruff format --check .
.venv/bin/python -m ruff check .
.venv/bin/python -m mypy src tests
./run-tests
```

### Completion criteria

The quality gates and `./run-tests` pass, the snapshot diff contains only the intended contract
change, and the new tests prove the cap-at-today and omitted-means-today behavior.
