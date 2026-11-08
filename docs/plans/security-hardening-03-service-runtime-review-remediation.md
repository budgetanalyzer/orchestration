# Security Hardening 03: Service Runtime Review Remediation

**Status:** Ready to execute.

This plan fixes the findings from the review of the uncommitted implementation of
[`security-hardening-03-service-runtime.md`](security-hardening-03-service-runtime.md). D6 already
settles the audit-coverage scope. This plan closes missing Session Gateway lifecycle-audit paths,
makes logout audit outcomes match completed HTTP responses, documents the required
source-directory config overrides in runtime tests, and replaces currency-service's chained, order-dependent
dependency-outage tests with one sequential runtime-contract test.

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
- Keep `spring.config.additional-location=file:./src/main/resources/` in each runtime
  configuration test. The review finding that called it redundant was wrong: every affected
  service has a `src/test/resources/application.yml` that shadows the main `application.yml` on
  the test classpath, so only profile files such as `application-kubernetes.yml` load from main
  resources. Without the override, those tests stop covering the shipped base configuration
  (verified in Session Gateway: the readiness group and base logging assertions fail). Add a
  one-line comment at the override explaining this shadowing. Do not rename test resources or
  introduce a test profile to remove it.

## Phase 1: Complete Session Gateway lifecycle auditing

### Workspace

../session-gateway

### Goal

Emit exactly one safe audit event for every completed login success, login failure, logout, and
bulk-revocation attempt, including failures handled outside `SecurityConfig`, and record the HTTP
outcome actually returned to the caller.

### Scope

Session lifecycle audit emission in `SecurityConfig`, `LogoutController`,
`InternalSessionController`, `OAuth2CallbackTransportFailureWebExceptionHandler`, and
`OAuth2CallbackUnexpectedFailureWebExceptionHandler`; logout failure handling in
`LogoutController`; a small Session Gateway-local audit helper if it reduces duplication; related
integration tests;
`SessionGatewayApplicationIntegrationTest`; and the nearest security, configuration, `AGENTS.md`,
and evidence documentation.

### Non-goals

The shared `AuditEvent` shape, servlet auto-auditing, OAuth2 redirect behavior,
`BrowserErrorRedirectHandler` behavior, service-common's reactive exception handlers, session
storage,
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
3. Make `LogoutController` the single logout audit owner. Rename its audit operations to
   `LOGOUT_SUCCESS` and `LOGOUT_FAILURE` to match `OAUTH2_LOGIN_*`. Keep successful logout
   auditing as `LOGOUT_SUCCESS`. Remove the controller's pre-terminal hard-coded `500` failure
   event.
4. Nothing on `/logout` loads the security context before the controller; the first Redis session
   read is `LogoutController.resolveActor` (`exchange.getPrincipal()`). Today any failure from
   that read (including a malformed Redis session) or from session deletion escapes to
   service-common's catch-all handler as a JSON `500` with no audit event, contradicting the
   Browser Error Strategy in `docs/security.md` for the top-level form navigation the frontend
   uses. Change `LogoutController` so any session-read or session-deletion failure completes as a
   `302` redirect to `/oops`. On that path, do not clear the session cookie and do not redirect to
   the IdP. After the redirect completes, emit exactly one `LOGOUT_FAILURE` event with the
   response's final status (`302`) and the resolved internal user ID, or `anonymous` when the
   session read failed. Leave `BrowserErrorRedirectHandler` and service-common unchanged.
   Status: implemented and tested in the current uncommitted tree; keep it.
5. Narrow logout failure recovery so the `/oops` redirect and `LOGOUT_FAILURE` event cover only the
   session read and session deletion. Session deletion is the commit point: today the
   `onErrorResume` in `invalidateSession` also catches failures after deletion, which would report
   `LOGOUT_FAILURE` for an already deleted session and send `/oops` with a cookie-clearing header,
   contradicting the documented "without clearing the cookie" contract. The only post-deletion
   failures are `URI.create` on a malformed `idp.logout.url-template` and the response write
   itself. Build and validate the IdP logout `URI` once in the `LogoutController` constructor so a
   malformed template fails application startup, then apply the failure recovery to the deletion
   step only. A failed final response write is not redirected or audited, because the response
   is already committed. Add a direct unit test that constructing `LogoutController` with a
   malformed template throws, and keep the existing logout integration tests green.
6. Preserve bulk-revocation success and failure coverage. If lifecycle audit field construction is
   now repeated across several classes, introduce one small, direct Session Gateway-local helper
   around `AuditLogger` for operation names, correlation-ID extraction, and emission. Do not add a
   configurable audit framework or a global catch-all web filter.
7. Extend integration coverage to prove exactly one safe event for:
   - normal login success and ordinary OAuth2 authentication failure;
   - callback token/JWKS transport failure handled by the dedicated transport handler;
   - unexpected callback failure handled by the dedicated unexpected-failure handler;
   - successful authenticated logout (`LOGOUT_SUCCESS`);
   - a logout session-read failure, using real components and a malformed synthetic Redis session
     (for example, one missing `expires_at`) or an equivalent deterministic repository-owned
     fixture, proving `302` to `/oops`, no cookie clearing, no IdP redirect, and one
     `LOGOUT_FAILURE` event with actor `anonymous`;
   - a logout Redis-deletion failure, updating
     `logoutDoesNotClearCookieOrRedirectWhenRedisDeletionFails` from expecting `5xx` with no
     `Location` to expecting `302` to `/oops`, no cookie clearing, and one `LOGOUT_FAILURE` event
     with the resolved internal actor;
   - bulk-revocation success and its existing failure behavior where practical.
8. For each event assertion, verify operation, actor or deliberate `anonymous`, final HTTP outcome,
   correlation ID, and absence of session token and digest. Reuse existing logger-capture support
   rather than creating a second test logging mechanism.
9. Keep `spring.config.additional-location=file:./src/main/resources/` in
   `SessionGatewayApplicationIntegrationTest` and add the shadowing comment described in the
   plan-wide rules. Keep the readiness, base logging, and `kubernetes` profile assertions. If the
   evidence file lists the override as an open item, record it as resolved by this decision.
10. Correct `docs/security.md`, `AGENTS.md`, and
    `docs/research/security-consensus-hardening-evidence.md` so their exact-one and outcome claims,
    logout operation names, and `/logout` failure redirect behavior match the now-tested terminal
    paths, including that a malformed IdP logout template fails startup. Record the focused and
    full validation results.

Most of this phase is already implemented in the uncommitted Session Gateway tree from earlier
attempts. Verify the existing work against these steps rather than rewriting it; the remaining
changes are step 5, the step 9 comment and evidence update, and the step 10 documentation for
step 5.

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

Also run the new `LogoutController` construction unit test from step 5.

Then run the repository-required gates in sequence:

```bash
./gradlew clean spotlessApply
./gradlew clean build
git diff --check
```

### Completion criteria

Every tested terminal lifecycle path emits exactly one event, callback transport failures and
logout session-read failures are no longer missed, logout session-read and deletion failures
redirect to `/oops` with `302` and emit one `LOGOUT_FAILURE` event recording that final status
rather than a hard-coded `500`, no post-deletion failure is reported as `LOGOUT_FAILURE` or
redirected to `/oops`, a malformed IdP logout template fails startup, logout events use
`LOGOUT_SUCCESS`/`LOGOUT_FAILURE`, no sensitive
value enters an event, the runtime configuration test keeps its source-directory override with a
comment explaining the test-resource shadowing, and the Session Gateway documentation and
evidence make only proven claims.

## Phase 2: Document the transaction-service runtime configuration override

### Workspace

../transaction-service

### Goal

Explain why `TransactionServiceApplicationIntegrationTest` needs its source-resource override,
without changing what the test covers.

### Scope

The `@SpringBootTest` declaration in `TransactionServiceApplicationIntegrationTest`.

### Non-goals

Test structure, including `@TestMethodOrder`, `@Order`, and `contextLoads`, production
configuration, readiness membership, logging defaults, evidence files, and application code. The
ordered methods are kept deliberately: `@Order` only guarantees that the single destructive
container-stop test runs last, which is correct and deterministic.

### Required context

- `TransactionServiceApplicationIntegrationTest`.
- `src/test/resources/application.yml`.

### Execution steps

1. Confirm `src/test/resources/application.yml` exists and shadows the main `application.yml`.
   If it does not, stop and report rather than adding the comment.
2. Add the one-line shadowing comment described in the plan-wide rules directly above the
   `@SpringBootTest` override. Make no other change.

### Implementation notes

This is a comment-only change. Do not update evidence files for it.

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

The override carries the shadowing comment, the diff contains no other change, and the required
build and formatting gates pass.

## Phase 3: Document the permission-service runtime configuration override

### Workspace

../permission-service

### Goal

Explain why `PermissionServiceApplicationIntegrationTest` needs its source-resource override,
without changing what the test covers.

### Scope

The `@SpringBootTest` declaration in `PermissionServiceApplicationIntegrationTest`.

### Non-goals

Test structure, including `@TestMethodOrder` and `@Order`, production configuration, readiness
membership, logging defaults, authorization exceptions, `deleteUser` removal, evidence files, and
application code. The ordered methods are kept for the same reason as in Phase 2.

### Required context

- `PermissionServiceApplicationIntegrationTest`.
- `src/test/resources/application.yml`.

### Execution steps

1. Confirm `src/test/resources/application.yml` exists and shadows the main `application.yml`.
   If it does not, stop and report rather than adding the comment.
2. Add the one-line shadowing comment described in the plan-wide rules directly above the
   `@SpringBootTest` override. Make no other change.

### Implementation notes

This is a comment-only change. Do not update evidence files for it.

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

The override carries the shadowing comment, the diff contains no other change, and the
repository-required gates pass.

## Phase 4: Simplify currency-service runtime configuration testing

### Workspace

../currency-service

### Goal

Retain the logging, readiness-membership, and dependency-outage proof without order-dependent
test methods, keeping the documented source-resource override.

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

1. Keep `spring.config.additional-location=file:./src/main/resources/` and add the shadowing
   comment described in the plan-wide rules.
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

One deterministic test proves the complete runtime contract from the shipped configuration, the
override carries the shadowing comment, no method-order machinery remains, the evidence matches the test structure, and the repository gates
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

1. Read the owning evidence entries from Session Gateway and currency-service. Confirm they record
   the focused and required full validations actually completed. Transaction-service and
   permission-service have no evidence entry for this remediation because Phases 2-3 are
   comment-only; confirm their AI Session Handler outcomes instead.
2. Confirm the Session Gateway evidence no longer generalizes from one ordinary failure test: it
   must name the callback transport/unexpected failure paths and the logout session-read and
   session-deletion failure paths (`302` to `/oops`, `LOGOUT_FAILURE`) now covered.
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
