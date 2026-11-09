# Security Hardening 05: Closeout and Release Handoff

This is the last of the plans that implement the 2026-11-01 security review findings, with the
decisions in the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
document applied. It completes the edge contract verifier and finishes with the evidence record and
an explicit human-owned release handoff.

**Depends on:** plans 01, 02.1–02.8, 03 (including its review remediation) and 04.

**Repositories:** orchestration.

**Human-run verification, 2026-11-09.** The user ran both suites against the local stack after plans
01–04 and before Phase 1. Agents must not rerun them:

- Local API tests, `../budget-analyzer-api-tests/run-tests`: run `20261109T014950Z-ac3c3b7b`,
  436 tests, 0 failures, 0 errors, 0 skipped. Artifacts are git-ignored under
  `../budget-analyzer-api-tests/artifacts/runs/20261109T014950Z-ac3c3b7b/`.
- Aggregate smoketest, `./scripts/smoketest/smoketest.sh`: passed, as reported by the user. No
  saved report.

| Label | Review |
| --- | --- |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

## Final scope

`01 P1` means plan 01, Phase 1. A bare `02.4` means every phase of plan 02.4. Phase numbers without
a plan refer to this plan. Evidence headings in
`docs/research/security-consensus-hardening-evidence.md` use the same plan and phase numbers.
Item 25 is deferred and item 29 is an accepted risk; both are excluded from implementation
acceptance.

| # | Fix | Where |
| --- | --- | --- |
| 1 | Narrow mesh policies to the callers' real paths | 01 P1, 02.3 P3 |
| 2 | Add an explicit mesh deny baseline | 01 P1 |
| 3 | Prove the public/internal boundary across encoded path forms | 01 P1, Phase 1 |
| 4 | Strip `Cookie` and `Authorization` before backends | 01 P2 |
| 5 | Send backends the real `X-Forwarded-Proto` | 01 P2 |
| 6 | Set ext_authz `statusOnError` and a timeout; correct the contract; test real denials | 01 P4 |
| 7 | Send HSTS from the ingress | 01 P5 |
| 8 | Stop trusting caller forwarded headers; fix the OAuth redirect URI | 01 P5, 02.2 |
| 9 | Add CSP `form-action`; drop `X-XSS-Protection` | 01 P5, 02.8 P2 |
| 10 | Replace Session Gateway `+@all` and its literal verifier | 01 P6 |
| 11 | Reconcile the documentation with the code | 01 P7, 02.1–02.8 |
| 12 | Bind OAuth callbacks to the initiating browser | 02.1 |
| 13 | Validate and cap `returnUrl` at login start; shorten the OAuth-state lifetime | 02.2 |
| 14 | Reject backslashes and control characters in redirect targets | 02.2 |
| 15 | Enforce an absolute session lifetime | 02.4 |
| 16 | Hash session tokens in session keys and index members | 02.5 |
| 17 | Adopt the `__Host-` session cookie | 02.6 |
| 18 | Add a login permission-call deadline; move user sync off GET | 02.3 |
| 19 | Separate liveness from readiness | 03 P1, P2, P6, P7, P9, P10, P12 |
| 20 | Add ext-authz HTTP server timeouts | 03 P1 |
| 21 | Use the trusted client address | 03 P4 |
| 22 | Add structured audit events | 03 P5, P9; 03 remediation P1 |
| 23 | Turn body logging and TRACE off by default in all four services | 03 P6, P7, P9, P10 |
| 24 | Add an endpoint authorization coverage rule | 03 P6, P7, P10 |
| 25 | Bound PDF parsing | Deferred per contested #6 |
| 26 | Set a measured Redis memory budget; no `allkeys-lru` on auth data | 04 P1 |
| 27 | Exclude private destinations from the egress gateway | 04 P2 |
| 28 | Require TLS on the PostgreSQL server side | 04 P3 |
| 29 | Separate migration roles from runtime roles | Accepted risk per plan 04, D5 |
| 30 | Move to a supported RabbitMQ series; report runtime support dates | 04 P4 |
| 31 | Test the edge contract across layers, including forged headers with no permissions | 01 P1–P5, 02.8 P2, Phase 1 |
| 32 | Share NGINX API routes between local and production-reference configurations | 01 P3 |
| 33 | Reject decoded semicolons on the NGINX lane | 01 P3 |
| 34 | Move heartbeat and logout to POST across services and clients | 02.7 |
| 35 | Require exact Origin on unsafe requests on both ingress lanes | 02.8 |
| 36 | Align the ext-authz Go toolchain | 03 P3 |
| 37 | Remove the unused `deleteUser` method | 03 P8 |
| 38 | Use SCAN for currency cache eviction and remove its `KEYS` grant | 03 P11, P13 |

**Deferred by agreement**, not gaps: recovery objectives and restore tests, secret rotation and
storage encryption, exporters and alert delivery, vulnerability gating, Redis high availability,
step-up reauthentication, and an account generation check for immediate containment.

## Plan-wide rules

- No staging or production access, no certificate generation, and no git write operations unless
  the user asks.
- No production environment or production data exists. Discarding local state is acceptable. Do not
  write migration, dual-format or backward-compatibility code. Reset instead, with
  `./scripts/ops/flush-redis.sh`, `./scripts/ops/reset-databases.sh` or by recreating the volume.
- Do not run `./run-tests`, `./scripts/smoketest/smoketest.sh` or
  `./scripts/smoketest/verify-security-guardrails.sh`. The user owns those runs.
- Before any cluster mutation, apply the `kind-kind` checks in the orchestration `AGENTS.md`.
- Phases marked **Live** need a running stack. Run `./scripts/bootstrap/check-local-runtime.sh` and
  `tilt up`. If the stack cannot be started, stop and report; do not substitute static evidence.
- Do not edit `docs/decisions/` or `docs/archive/`.
- Do not edit this plan during a run, because the runner stops launching phases when it changes.
- Record results in `docs/research/security-consensus-hardening-evidence.md`.

**Orchestration static gate**, for every orchestration phase:

```bash
bash -n <changed-script> && shellcheck <changed-script>
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

**Cutover rule:** `kubernetes/production` shares these manifests but pins older images
(session-gateway 0.0.15, ext-authz 0.0.16). Those images lack the new cookie, hashed keys, the POST
sync call and `/livez` (plans 02.3, 02.5, 02.6 and 03 P2), and the plan 02.3 P3 mesh policy blocks
the pinned Session Gateway's login call. The offline checks catch none of this. Phase 2 records the
human-owned release and pin updates.

## Phase 1: Complete the edge contract verifier (Live)

### Workspace

.

### Goal

Finish the single cross-layer verifier, so the seams between components stay tested.

### Scope

`scripts/smoketest/verify-edge-contract.sh`, `scripts/smoketest/verify-security-guardrails.sh`, and
`scripts/README.md`.

### Non-goals

Two-cookie request tests (duplicate rejection is not in these plans, per contested #5) and `KEYS`
denial, which plan 03 P13 asserts in `verify-credential-isolation.sh`.

### Required context

R2 "Define the edge contract once"; R3 N3; R4 "Define and test one edge contract"; plan 01,
Phases 1-5; plan 02.8, Phase 2.

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
  real permission check instead of an echo backend.
- Cookie stripping keeps its plan 01 P2 stand-in test, because NGINX has no route to an echo
  backend. Say so in the verifier's header comment.

### Validation

The orchestration static gate, then run the verifier directly; do not run the wrapper:

```bash
./scripts/smoketest/verify-edge-contract.sh
./scripts/smoketest/verify-edge-contract.sh --inject-failures
```

Record both results, including the boundary section's results, in the evidence file.

### Completion criteria

Both direct verifier runs pass with the Forged Identity section and its positive control included,
and `verify-security-guardrails.sh` invokes the default run.

## Phase 2: Evidence record and release handoff

### Workspace

.

### Goal

Record the verification evidence and the human-owned release steps.

### Scope

The evidence file and remaining docs.

### Non-goals

Running test suites, releasing images, changing production pins, or starting deferred work.

### Required context

`scripts/README.md`; the final scope table; the human-run verification in the preamble; the evidence
file, including Phase 1's results; the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document, #2, #6
and #7.

### Execution steps

1. Record the human-run API test and smoketest results from the preamble in the evidence file. Note
   that both ran before Phase 1, so Phase 1's direct verifier runs are the evidence for the Forged
   Identity section.
2. Confirm from Phase 1's recorded boundary results that the plan 01 P1 probes are still denied.
3. Update the audit claims in `docs/architecture/security-architecture.md` to describe the events
   from plan 03 P5, P9 and its [review remediation](security-hardening-03-service-runtime-review-remediation.md),
   scoped to state-changing requests and the session lifecycle, not reads. The claims are the "Audit
   logging of data access" bullet under "4. Backend Microservices", the "Audit logging of sensitive
   data access" bullet under "Layer 3: Backend Services", and the "Audit Logging (Required for
   Financial Data)" list and its `data_access` read example under "Logging Strategy". Search for
   `audit` to catch any others.
4. Confirm no doc in the scope table still contradicts the code.
5. Record the human-owned handoff: release service-common, then session-gateway, ext-authz, the three
   services and the frontend together, and update
   `kubernetes/production/apps/deployment-manifest.yaml` and
   `kubernetes/production/apps/image-inventory.yaml` (see the cutover rule). Record that the
   production reference supports only a deployment that starts from empty state; no upgrade path
   from the pinned images or existing data is provided.
6. Note the production secrets and configuration added by plans 02.2, 02.4 and 02.6.
7. Link passing evidence for every scope item other than 25 and 29, and record every accepted
   remaining gap:
   - Session Gateway client address
   - audit retention and access
   - anonymous OAuth-state growth
   - runtime database roles that own their schemas, with no separate migration role (plan 04, D5)
   - unbounded upload processing as a known availability limitation of the single-replica
     transaction-service, without presenting any current setting as a capacity bound (contested #6)
   - key-name visibility to the currency-service credential as residual metadata exposure
     (contested #2)
   - a compromised allowed intermediary can forge or replay identity claims (contested #7)

### Implementation notes

Passing offline checks prove the production reference renders. They do not prove the pinned images
support the new probes or cookie contract, so do not claim parity.

### Validation

Every link added to the evidence file and docs resolves. No suite is rerun.

### Completion criteria

Every scope item other than 25 and 29 has linked passing evidence, the human-run API test and
smoketest results are recorded, accepted gaps are documented, and the release handoff is explicit.
