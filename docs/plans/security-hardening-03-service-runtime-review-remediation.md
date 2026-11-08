# Security Hardening 03: Service Runtime Review Remediation

**Status:** Ready to execute.

This plan fixes the findings from the review of the uncommitted implementation of
[`security-hardening-03-service-runtime.md`](security-hardening-03-service-runtime.md). D6 already
settles the audit-coverage scope. This plan closes missing Session Gateway lifecycle-audit paths,
makes logout audit outcomes match completed HTTP responses, removes redundant source-directory
config overrides from runtime tests, and replaces order-dependent dependency-outage tests with
one sequential runtime-contract test per affected service.

Plan-wide rules:

- Follow each phase workspace's `AGENTS.md` and remain within that repository for all writes and
  validation in the phase.
- Do not run git write operations, generate certificates, access staging or production, or mutate
  the local Kind cluster.
- Preserve the already implemented runtime behavior outside these review findings. In particular,
  do not redesign the shared audit event, session flow, readiness groups, deployment probes, or
  Redis ACLs.
- Do not mock or spy application-owned Spring beans. Use the existing real-component integration
  test patterns.
- Keep audit events free of session tokens, token digests, OAuth codes or state, email addresses,
  display names, request bodies, and response bodies.
- Do not edit this remediation plan while an AI Session Handler run is active. The original plan is
  a separate file and may be updated by Phase 5.
- Record exact validation results in the owning repository's existing security hardening evidence
  file. Do not claim a command passed unless it was run successfully.

## Phase 1: Complete Session Gateway lifecycle auditing

### Workspace

../session-gateway

### Goal

Emit exactly one safe audit event for every completed login success, login failure, logout, and
bulk-revocation attempt, including failures handled outside `SecurityConfig`, and record the HTTP
outcome actually returned to the caller.

### Scope

Session lifecycle audit emission in `SecurityConfig`, `LogoutController`,
`InternalSessionController`, `OAuth2CallbackTransportFailureWebExceptionHandler`,
`OAuth2CallbackUnexpectedFailureWebExceptionHandler`, and `BrowserErrorRedirectHandler`; a small
Session Gateway-local audit helper if it reduces duplication; related integration tests;
`SessionGatewayApplicationIntegrationTest`; and the nearest security, configuration, `AGENTS.md`,
and evidence documentation.

### Non-goals

The shared `AuditEvent` shape, servlet auto-auditing, OAuth2 redirect behavior, session storage,
authentication policy, readiness composition, client-address handling, and audit-log retention or
routing.

### Required context

- `docs/security.md#session-lifecycle-audit-events`.
- `docs/configuration.md#logging` and `docs/configuration.md#health-probes`.
- `src/main/java/org/budgetanalyzer/sessiongateway/config/SecurityConfig.java`.
- The three Session Gateway `WebExceptionHandler` implementations and
  `RedisSessionSecurityContextRepository`.
- The service-common `AuditLogger` and `AuditEvent` contract in `../service-common/service-web`.
- Existing callback diagnostics, logout, revocation, and security configuration integration tests.

### Execution steps

1. Inventory every terminal path that completes a login callback, logout request, or bulk
   revocation. Distinguish paths completed by `SecurityConfig`, a controller, or a
   `WebExceptionHandler` so each path has exactly one audit owner.
2. Keep login-success and normal authentication-failure auditing in `SecurityConfig`, but also
   audit successful redirects completed by both dedicated callback failure handlers. Cover token,
   userinfo, and JWKS transport failures and unexpected callback-completion failures without
   emitting a second event for paths already handled by `SecurityConfig`.
3. Keep successful logout auditing in `LogoutController`. Remove the controller's pre-terminal
   hard-coded `500` failure event. When `BrowserErrorRedirectHandler` completes the exact
   `/logout` failure redirect, emit one logout-failure event using the response's final status
   (`302`) and `anonymous` when no safely resolved internal actor is already available.
4. Ensure a Redis failure or malformed Redis session encountered while the security context is
   loading before controller invocation still reaches the logout-failure audit owner.
5. Preserve bulk-revocation success and failure coverage. If lifecycle audit field construction is
   now repeated across several classes, introduce one small, direct Session Gateway-local helper
   around `AuditLogger` for operation names, correlation-ID extraction, and emission. Do not add a
   configurable audit framework or a global catch-all web filter.
6. Extend integration coverage to prove exactly one safe event for:
   - normal login success and ordinary OAuth2 authentication failure;
   - callback token/JWKS transport failure handled by the dedicated transport handler;
   - unexpected callback failure handled by the dedicated unexpected-failure handler;
   - successful authenticated logout;
   - a pre-controller logout failure, using real components and a malformed synthetic Redis
     session or an equivalent deterministic repository-owned fixture;
   - bulk-revocation success and its existing failure behavior where practical.
7. For each event assertion, verify operation, actor or deliberate `anonymous`, final HTTP outcome,
   correlation ID, and absence of session token and digest. Reuse existing logger-capture support
   rather than creating a second test logging mechanism.
8. Remove
   `spring.config.additional-location=file:./src/main/resources/` from
   `SessionGatewayApplicationIntegrationTest`; Spring Boot already loads main and profile resources
   from the test runtime classpath. Keep the `kubernetes` profile assertion.
9. Correct `docs/security.md`, `AGENTS.md`, and
   `docs/research/security-consensus-hardening-evidence.md` so their exact-one and outcome claims
   match the now-tested terminal paths. Record the focused and full validation results.

### Implementation notes

- Audit after a redirect or response completes successfully, so `response.getStatusCode()` is the
  returned status rather than a guessed error code.
- A completed browser failure redirect is still a failed lifecycle operation even though its HTTP
  outcome is `302`; the operation name carries the success/failure meaning.
- Do not resolve a failure actor by making another Redis or downstream call. Use an already
  available internal user ID, otherwise `anonymous`.
- Keep auditing synchronous and small as it is today; do not introduce a reactive persistence
  pipeline or make request success depend on an external audit destination.

### Validation

Run focused tests for the changed terminal paths first, including:

```bash
./gradlew test \
  --tests 'org.budgetanalyzer.sessiongateway.config.SecurityConfigIntegrationTest' \
  --tests 'org.budgetanalyzer.sessiongateway.config.OAuth2CallbackDiagnosticsIntegrationTest' \
  --tests 'org.budgetanalyzer.sessiongateway.api.LogoutControllerIntegrationTest' \
  --tests 'org.budgetanalyzer.sessiongateway.api.InternalSessionControllerIntegrationTest' \
  --tests 'org.budgetanalyzer.sessiongateway.SessionGatewayApplicationIntegrationTest'
```

Then run the repository-required gates in sequence:

```bash
./gradlew clean spotlessApply
./gradlew clean build
git diff --check
```

### Completion criteria

Every tested terminal lifecycle path emits exactly one event, transport and pre-controller
failures are no longer missed, logout failure records the final redirect status rather than a
hard-coded `500`, no sensitive value enters an event, the runtime configuration test has no
source-directory override, and the Session Gateway documentation and evidence make only proven
claims.

## Phase 2: Simplify transaction-service runtime configuration testing

### Workspace

../transaction-service

### Goal

Retain the safe-logging and database readiness/liveness proof without a redundant source-resource
override or order-dependent test methods.

### Scope

`TransactionServiceApplicationIntegrationTest` and its repository-local evidence entry if the
validation description changes.

### Non-goals

Production configuration, readiness membership, logging defaults, controller security coverage,
audit behavior, and application code.

### Required context

- `docs/configuration.md#logging` and `docs/configuration.md#health-probes`.
- `TransactionServiceApplicationIntegrationTest`.
- The transaction-service testing rules in `../service-common/docs/testing-patterns.md`.

### Execution steps

1. Remove `spring.config.additional-location=file:./src/main/resources/`; use Spring Boot's normal
   runtime classpath configuration loading.
2. Replace `@TestMethodOrder`, `@Order`, and the separate stateful methods with one sequential
   runtime-contract test that:
   - asserts the effective `kubernetes` profile has `INFO` application logging and both body flags
     disabled;
   - proves readiness is initially up;
   - stops the test-owned PostgreSQL container;
   - proves readiness becomes unavailable while liveness remains up.
3. Remove a standalone `contextLoads` test if the runtime-contract test already proves successful
   context startup.
4. Keep the test-owned container, short connection timeout, datasource properties, and preview
   token fixture needed for deterministic startup.
5. Update the evidence wording only if it currently names the old three-method structure, and
   record the validation actually run.

### Implementation notes

One sequential test is intentional because stopping the container is destructive for that test
application context. It makes the lifecycle explicit without relying on JUnit method ordering.

### Validation

Run:

```bash
./gradlew test --tests \
  'org.budgetanalyzer.transaction.TransactionServiceApplicationIntegrationTest'
./gradlew clean spotlessApply
./gradlew clean build
git diff --check
```

### Completion criteria

The same runtime guarantees remain covered from classpath-loaded configuration, the class has no
explicit method ordering or redundant context test, and the required build and formatting gates
pass.

## Phase 3: Simplify permission-service runtime configuration testing

### Workspace

../permission-service

### Goal

Retain the safe-logging and database readiness/liveness proof without a redundant source-resource
override or order-dependent test methods.

### Scope

`PermissionServiceApplicationIntegrationTest` and its repository-local evidence entry if the
validation description changes.

### Non-goals

Production configuration, readiness membership, logging defaults, authorization exceptions,
`deleteUser` removal, audit behavior, and application code.

### Required context

- The runtime configuration section in `README.md`.
- `PermissionServiceApplicationIntegrationTest`.
- The permission-service and service-common testing rules.

### Execution steps

1. Remove `spring.config.additional-location=file:./src/main/resources/`; rely on normal classpath
   configuration loading.
2. Replace `@TestMethodOrder`, `@Order`, and the two stateful methods with one sequential
   runtime-contract test that asserts safe effective logging, proves readiness is initially up,
   stops the test-owned PostgreSQL container, and proves readiness goes down while liveness stays
   up.
3. Preserve the `kubernetes` profile and the datasource connection timeout needed for a bounded
   outage assertion.
4. Update the evidence wording only where it describes the former method count or structure, and
   record exact validation results.

### Implementation notes

Do not create separate application contexts merely to retain independent test methods. The test
owns and deliberately stops its container, so one explicit sequence is the simplest representation
of the runtime contract.

### Validation

Run:

```bash
./gradlew test --tests \
  'org.budgetanalyzer.permission.PermissionServiceApplicationIntegrationTest'
./gradlew clean spotlessApply
./gradlew clean build
git diff --check
```

### Completion criteria

The runtime guarantees are still proven using classpath configuration, no JUnit method ordering is
needed, and the repository-required gates pass.

## Phase 4: Simplify currency-service runtime configuration testing

### Workspace

../currency-service

### Goal

Retain the logging, readiness-membership, and dependency-outage proof without a redundant
source-resource override or order-dependent test methods.

### Scope

`RuntimeConfigurationIntegrationTest` and the corresponding repository-local evidence wording.

### Non-goals

Production configuration, cache behavior, SCAN eviction, Redis ACL tests, authorization coverage,
audit behavior, and application code.

### Required context

- `docs/configuration.md#logging` and `docs/configuration.md#health-probes`.
- `RuntimeConfigurationIntegrationTest`.
- The currency-service and service-common Testcontainers guidance.

### Execution steps

1. Remove `spring.config.additional-location=file:./src/main/resources/`; rely on Spring Boot's
   runtime classpath.
2. Replace `@TestMethodOrder`, `@Order`, and the four stateful methods with one sequential
   runtime-contract test that:
   - verifies safe logging defaults and both body flags;
   - verifies initial readiness contains `readinessState`, `db`, and `redis` but not `rabbit`;
   - verifies liveness contains neither database nor Redis;
   - stops Redis and proves readiness reports Redis down while liveness remains up;
   - then stops PostgreSQL and proves readiness also reports the database down while liveness
     remains up.
3. Keep the test-owned PostgreSQL, Redis, and RabbitMQ containers, `@DirtiesContext`, FRED test
   key, disabled startup import, and health-component visibility required by the assertions.
4. Update the evidence section so it describes one sequential runtime-contract test instead of
   four ordered methods, and record exact validation results.

### Implementation notes

Redis may remain stopped while the database assertion runs; the test should assert the named
database component rather than require it to be the only failing contributor. Do not restart a
stopped Testcontainer and risk changing its mapped connection details.

### Validation

Run:

```bash
./gradlew test --tests \
  'org.budgetanalyzer.currency.RuntimeConfigurationIntegrationTest'
./gradlew clean spotlessApply
./gradlew clean build
git diff --check
```

### Completion criteria

One deterministic test proves the complete runtime contract from classpath configuration, no
method-order machinery remains, the evidence matches the test structure, and the repository gates
pass.

## Phase 5: Close the original plan remediation

### Workspace

.

### Goal

Verify that every review finding has durable repository evidence and mark the original plan's
post-implementation remediation complete without overstating validation.

### Scope

`docs/plans/security-hardening-03-service-runtime.md` and, only if needed to correct a statement
made by this implementation, `docs/research/security-consensus-hardening-evidence.md`.

### Non-goals

Any service implementation change, rerunning service builds from orchestration, plan 05's release
and production-pin work, broader audit-architecture claims, and live cluster validation.

### Required context

- The completed outcomes and evidence from Phases 1-4 in their owning repositories.
- The settled D6 and post-implementation review note already recorded in the original plan.
- The original plan's cutover rule and plan 05 handoff.

### Execution steps

1. Read the owning evidence entries from Session Gateway, transaction-service,
   permission-service, and currency-service. Confirm they record the focused and required full
   validations actually completed.
2. Confirm the Session Gateway evidence no longer generalizes from one ordinary failure test: it
   must name the callback transport/unexpected and pre-controller logout failure paths now covered.
3. Update the original plan status to say implementation and post-implementation review
   remediation are complete, while retaining its existing plan 05 release/pin handoff.
4. Extend the original plan's review note with a concise completion statement and link to this
   remediation plan. Do not copy detailed per-repository test evidence into the plan.
5. Search active orchestration documentation for statements introduced by plan 03 that conflict
   with the corrected lifecycle-audit behavior. Correct only direct contradictions; leave plan
   05's broader audit-claim work in plan 05.

### Implementation notes

Do not modify this remediation plan during an active runner invocation. AI Session Handler state
and the repository evidence files are the execution record; the source plan remains stable.

### Validation

Run:

```bash
rg -n 'Status:|D6|review remediation|plan 05|audit' \
  docs/plans/security-hardening-03-service-runtime.md \
  docs/research/security-consensus-hardening-evidence.md
git diff --check -- docs/plans/security-hardening-03-service-runtime.md \
  docs/research/security-consensus-hardening-evidence.md
```

Verify the links to this plan and plan 05 resolve. Do not run builds, static manifest gates, or live
checks for this documentation-only closeout.

### Completion criteria

The original plan records D6 as settled and the review remediation as complete, every service
finding has exact owning-repository evidence, no plan 03 documentation overstates lifecycle audit
coverage, and the deferred production-release work remains clearly assigned to plan 05.
