# Security Hardening 05: Closeout and Release Handoff

**Status:** Draft for iteration.

This is plan 05 of five that together implement every finding from the four 2026-11-01 security
reviews that holds up against the code and that no review disputes, with the decisions in the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document applied.
This plan completes the edge contract verifier, runs the disposable local API tests, and finishes
with full verification and an explicit human-owned release handoff.
Phase numbers without a plan refer to this plan.

**Order:** 05 of 5

**Depends on:** plans 01–04.

**Repositories:** orchestration, budget-analyzer-api-tests.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

## Inclusion rule

An original consensus item is in scope when all three of these hold:

1. At least one review proposes it.
2. No review disputes the fix direction. Silence is not a dispute.
3. It was checked against the code on 2026-11-02.

A disagreement over severity does not exclude an item. A dispute over part of a remedy excludes only
that part.

The accepted decisions in the contested issues document extend or supersede that original set.
The table below covers the final scope, including those additions; item 25 remains explicitly
deferred, and item 29 is an accepted risk (plan 04, D5). Both are excluded from implementation
acceptance.

`01.1` means plan 01, Phase 1.

| # | Fix | Review or accepted decision | Phases |
| --- | --- | --- | --- |
| 1 | Narrow mesh policies to the callers' real paths | All four | 01.1, 02.14 |
| 2 | Add an explicit mesh deny baseline | R2, R4 | 01.1 |
| 3 | Prove the public/internal boundary across encoded path forms | R3, R4 | 01.1, 05.3 |
| 4 | Strip `Cookie` and `Authorization` before backends | All four | 01.2 |
| 5 | Send backends the real `X-Forwarded-Proto` | R2, R4 | 01.2 |
| 6 | Set ext_authz `statusOnError` and a timeout; correct the contract; test real denials | R2, R3, R4 | 01.4 |
| 7 | Send HSTS from the ingress | R2, R3, R4 | 01.5 |
| 8 | Stop trusting caller forwarded headers; fix the OAuth redirect URI | R2, R4 | 01.5, 02.2, 02.14 |
| 9 | Add CSP `form-action`; drop `X-XSS-Protection` | R2, R4; contested #1 | 01.5, 02.16 |
| 10 | Replace Session Gateway `+@all` and its literal verifier | All four | 01.6 |
| 11 | Reconcile the documentation with the code | All four; R2, R3, R4 on additions | 01.7, 02.14 |
| 12 | Bind OAuth callbacks to the initiating browser | All four | 02.1, 02.15 |
| 13 | Validate and cap `returnUrl` at login start; shorten the OAuth-state lifetime | R2, R3 | 02.2 |
| 14 | Reject backslashes and control characters in redirect targets | R2 | 02.2, 02.10 |
| 15 | Enforce an absolute session lifetime | All four | 02.3, 02.9, 02.10, 02.14, 02.15 |
| 16 | Hash session tokens in session keys and index members | R2, R3, R4 | 02.4, 02.9, 02.14, 02.15 |
| 17 | Adopt the `__Host-` session cookie | R1 ("consider"), R2, R3, R4 | 02.5, 02.9, 02.10, 02.12, 02.14, 02.15 |
| 18 | Add a login permission-call deadline; move user sync off GET | R2, R3, R4 | 02.7, 02.8, 02.14 |
| 19 | Separate liveness from readiness | All four | 03.1, 03.2, 03.6, 03.7, 03.9, 03.10, 03.12 |
| 20 | Add ext-authz HTTP server timeouts | R2 | 03.1 |
| 21 | Use the trusted client address | R1, R2, R4 | 03.4 |
| 22 | Add structured audit events | R1, R2 | 03.5, 03.9 |
| 23 | Turn body logging and TRACE off by default in all four services | All four | 03.6, 03.7, 03.9, 03.10 |
| 24 | Add an endpoint authorization coverage rule | R2, R3, R4 | 03.6, 03.7, 03.10 |
| 25 | Bound PDF parsing, limited to the agreed controls | R2, R3, R4 | Deferred per contested #6; limitation recorded in 05.3 |
| 26 | Set a measured Redis memory budget; no `allkeys-lru` on auth data | All four | 04.1 |
| 27 | Exclude private destinations from the egress gateway | R1, R3 | 04.2 |
| 28 | Require TLS on the PostgreSQL server side | R2, R3, R4 | 04.3 |
| 29 | Separate migration roles from runtime roles | R2, R4 | Not implemented; accepted risk per plan 04, D5; recorded in 05.3 |
| 30 | Move to a supported RabbitMQ series; report runtime support dates | R2, R3, R4; R2 | 04.4 |
| 31 | Test the edge contract across layers, including forged headers with no permissions | R2, R3, R4; contested #1 | 01.1, 01.2, 01.3, 01.4, 01.5, 02.16, 05.1, 05.3 |
| 32 | Share NGINX API routes between local and production-reference configurations | Contested #12 | 01.3 |
| 33 | Reject decoded semicolons on the NGINX lane | Contested #3 | 01.3 |
| 34 | Move heartbeat and logout to POST across services and clients | Contested #1 | 02.6, 02.11, 02.13, 02.14, 02.15 |
| 35 | Require exact Origin on unsafe requests on both ingress lanes | Contested #1 | 02.13, 02.16 |
| 36 | Align the ext-authz Go toolchain | Contested A4 | 03.3 |
| 37 | Remove the unused `deleteUser` method | Contested #10 | 03.8 |
| 38 | Use SCAN for currency cache eviction and remove its `KEYS` grant | Contested #2 | 03.11, 03.13 |

**Deferred by agreement.** All four reviews leave these until hosted use is planned: recovery
objectives and restore tests, secret rotation and storage encryption, exporters and alert delivery,
vulnerability gating, and Redis high availability. R1 and R4 tie two more to requirements that do not exist yet: step-up reauthentication,
and an account generation check for immediate containment.

## Decisions

| # | Decision | Recommendation | Why it matters | Status |
| --- | --- | --- | --- | --- |
| D6 | Audit event coverage | State-changing requests and the session lifecycle | The docs claim audit logging of data access. Auditing reads adds volume and no review requires it, so Phase 3 narrows the claim instead. | Settled and implemented by [plan 03](security-hardening-03-service-runtime.md) |

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
  phase in a sibling repository records them in that repository's `docs/` folder, and Phase 3
  collects the links.

**Orchestration static gate**, for every orchestration phase:

```bash
bash -n <changed-script> && shellcheck <changed-script>
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

**Cutover rule:** `kubernetes/production` shares these manifests but pins older images
(session-gateway 0.0.15, ext-authz 0.0.16). Plans 02.3, 02.5 and 02.6 and plan 03, Phase 2
therefore describe behaviour those images lack: the new cookie, hashed keys, the POST sync call and
`/livez`. The mesh policy from plan 02.3, Phase 3 would also block the pinned Session Gateway's login
call. The offline checks catch none of this. Phase 3 records the release and pin updates, which are
human-owned. No production environment exists, so no dual-cookie or session migration is needed.

## Contested decisions applied

- [#7, signed identity context](../research/security-review-contested-issues-2026-11-02.md#7-signed-identity-context):
  signing stays deferred. Phase 1 proves ingress header replacement with empty permissions, and
  Phase 3 records intermediary forgery and replay as residual risks.
- [#2, Redis enumeration](../research/security-review-contested-issues-2026-11-02.md#2-redis-enumeration-after-hashing)
  and [#5, duplicate session cookies](../research/security-review-contested-issues-2026-11-02.md#5-rejecting-duplicate-session-cookies):
  Phase 1's non-goal is amended. `KEYS` denial is asserted in plan 03, Phase 13, and duplicate
  rejection is not in these plans.
- [#6, PDF memory handling](../research/security-review-contested-issues-2026-11-02.md#6-pdf-memory-handling-and-a-parsing-worker):
  Phase 3 drops the PDF evidence, records the known limitation, and excludes scope item 25.
- [Severity disputes](../research/security-review-contested-issues-2026-11-02.md#severity-disputes):
  unchanged. These plans assign no comparable severity scores.

## Phase 1: Complete the edge contract verifier (Live)

### Workspace

.

### Goal

Finish the single cross-layer verifier, so the seams between components stay tested.

### Scope

`verify-edge-contract.sh`, `scripts/smoketest/verify-security-guardrails.sh`, and `scripts/README.md`.

### Non-goals

(amended per contested #2 and #5) Two-cookie request tests, because
duplicate rejection is optional and not in these plans, and `KEYS` denial, which plan 03, Phase 13
asserts in `verify-credential-isolation.sh`.

### Required context

R2 "Define the edge contract once"; R3 N3; R4 "Define and test one edge contract"; plan 01, Phases 1-5;
plan 02.8, Phase 2.

### Execution steps

1. Add a "Forged Identity" section. Seed a session with empty roles and permissions, send forged
   `X-User-Id`, `X-Roles` and `X-Permissions: users:read` headers to `/api/v1/users`, and assert 403.
2. Add a positive control: a seeded session that really holds `users:read` gets past the gate.
3. Confirm the verifier covers the boundary, failure statuses, response headers, exact Origin on
   both lanes, and forged identity. The `503` failure statuses need a direct
   `verify-edge-contract.sh --inject-failures` run.
4. Wire the default run, which changes no Kubernetes object, into `verify-security-guardrails.sh`
   and update `scripts/README.md`.

### Implementation notes

- This goes through the real chain, unlike `p3-header-echo`, which bypasses NGINX. It relies on a
  real permission check instead of an echo backend. R3 tested the forged-header case at Envoy and
  found a coverage gap, not an exposure.
- Cookie stripping keeps its plan 01, Phase 2 stand-in test, because NGINX has no route to an echo backend.
  Say so in the verifier's header comment.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-edge-contract.sh` through the aggregate
wrapper, and one direct `./scripts/smoketest/verify-edge-contract.sh --inject-failures` run.

### Completion criteria

The aggregate gate fails if any section of the edge contract regresses.

## Phase 2: Run the disposable local API tests (Live)

### Workspace

../budget-analyzer-api-tests

### Goal

Prove the application works end to end after every change.

### Scope

The local API test run, using disposable local credentials.

### Non-goals

Staging, production, and new coverage.

### Required context

The repository's `AGENTS.md`.

### Execution steps

1. Confirm the stack left by earlier phases is running. If it is not, stop and report.
2. Run the local suite through `./run-tests`.
3. Record the result in this repository's `docs/` folder, with no credentials. If the suite fails,
   report each failure with its owner and leave this phase incomplete.

### Implementation notes

A failure in a service is a finding for that repository. Do not weaken a test to pass it. Have the
failure fixed in its owning workspace, then rerun this phase. Reporting a failure does not satisfy
acceptance or permit successful closeout.

### Validation

`./run-tests` against the local environment.

### Completion criteria

The local suite passes and its passing result is recorded. Unresolved test failures block phase
completion and progression to Phase 3.

## Phase 3: Full verification and release handoff (Live)

### Workspace

.

### Goal

Prove the combined change and record the human-owned release steps.

### Scope

Full verification suites, the evidence file, and remaining docs.

### Non-goals

Releasing images, changing production pins, or starting work the contested decisions defer
(amended per user direction).

### Required context

`scripts/README.md`; the final scope table; the evidence file; the passing sibling evidence from
Phase 2 (amended per contested #6: the PDF phase was dropped).

### Execution steps

1. Confirm Phase 2 has passing local API-test evidence, then run the aggregate smoketest. Any
   unresolved failure blocks successful closeout; record its owner and rerun the affected gate after
   the fix.
2. Confirm the plan 01, Phase 1 probes still fail after every later change.
3. Update the audit claims in `docs/architecture/security-architecture.md` to describe the events
   from plan 03, Phases 5 and 9 and its review remediation, and D6's scope: state-changing requests
   and the session lifecycle, not reads. The claims are the "Audit logging of data access" bullet
   under "4. Backend Microservices", the "Audit logging of sensitive data access" bullet under
   "Layer 3: Backend Services", and the "Audit Logging (Required for Financial Data)" list and its
   `data_access` read example under "Logging Strategy". Search for `audit` to catch any others.
4. Confirm no doc in the scope table still contradicts the code.
5. Record the human-owned handoff: release service-common, then session-gateway, ext-authz, the three
   services and the frontend, and update `kubernetes/production/apps/deployment-manifest.yaml` and
   `image-inventory.yaml`. Release them together, because the plan 02.3, Phase 3 policy blocks the pinned
   Session Gateway's login call. (amended per user direction)
   Also record that the production reference supports only a deployment that starts from empty state;
   no upgrade path from the pinned images or existing data is provided.
6. Note the production secrets and configuration added by plans 02.2, 02.4 and 02.6.
7. Link passing evidence for every scope item other than items 25 and 29, including additions
   32-38, and note every accepted remaining gap: Session Gateway client address, audit retention
   and access, anonymous OAuth-state growth, and runtime database roles that own their schemas with
   no separate migration role (plan 04, D5). (amended per contested #2,
   #6 and #7) Also record unbounded upload processing as a known availability
   limitation of the single-replica transaction-service, without presenting any current setting as
   a capacity bound; key-name visibility to the currency-service credential as residual metadata
   exposure; and that a compromised allowed intermediary can forge or replay identity claims.

### Implementation notes

Passing offline checks prove the production reference renders. They do not prove the pinned images
support the new probes or cookie contract, so do not claim parity.

### Validation

```bash
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/smoketest/smoketest.sh
```

### Completion criteria

Every scope item in the final table other than items 25 and 29 has recorded passing evidence, the
local API suite and aggregate smoketest pass, and the release handoff is explicit. Item 25 stays
deferred per contested #6, and item 29 stays an accepted risk per plan 04, D5. Accepted limitations are documented separately; unresolved verification failures
block successful closeout.
