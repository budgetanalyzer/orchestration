# Security Hardening 02.8: Exact-Origin Ingress Rule

**Status:** Draft for iteration.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan denies unsafe browser requests from any origin other than the
application's own, on both ingress lanes. Callers outside the browser are updated to send the
configured Origin first.
Phase numbers without a plan refer to this plan.

**Order:** 02.8 of 02.1-02.8. Run last.

**Depends on:** plan 02.7: POST heartbeat and form-POST logout. Plan 01, Phase 5: the final CSP.

**Repositories:** budget-analyzer-api-tests, orchestration.

**Merge unit:** Ordered. Each PR is safe on its own if merged in this order:
1. budget-analyzer-api-tests. An Origin header is harmless without the rule.
2. orchestration. It adds the policy and updates every orchestration caller in the same PR.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

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
- Tilt builds sibling worktrees, so the local stack may be inconsistent until every phase before
  the Live phase is complete. Those phases must not rely on a running stack.
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

- [#1, primary CSRF control](../research/security-review-contested-issues-2026-11-02.md#1-primary-csrf-control):
  an exact-Origin ingress `DENY`, completing the POST heartbeat and form-POST logout from plan 02.7.
  OAuth callback binding stays a separate control (plan 02.1).

## Phase 1: Send Origin from the API tests

### Workspace

../budget-analyzer-api-tests

### Goal

(added per contested #1) Keep the API tests working under the exact-Origin ingress rule.

### Scope

`src/api_tests/client.py` and unit tests.

### Non-goals

New API coverage, and staging or production runs.

### Required context

The repository's `AGENTS.md`; contested issue #1.

### Execution steps

1. Have the client send the configured browser Origin on requests other than GET, HEAD and OPTIONS.
2. Update the affected unit tests.

### Implementation notes

The Origin header is CSRF provenance, not authentication for arbitrary HTTP clients.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes, and unsafe requests carry the configured Origin.

## Phase 2: Require exact Origin on unsafe requests at the ingress (Live)

### Workspace

.

### Goal

(added per contested #1) Deny unsafe browser requests from any origin other than the application's
own, on both ingress lanes.

### Scope

A new ingress AuthorizationPolicy under `kubernetes/istio/`, `verify-edge-contract.sh`, a static
guardrail, orchestration scripts that send unsafe requests through the ingress,
`docs/architecture/security-architecture.md` (CSRF row and the CSP section's note on hostile-form
checks), and `docs/architecture/session-edge-authorization-pattern.md`.

### Non-goals

Fetch Metadata, CSRF tokens, and checks in ext-authz or Session Gateway.

### Required context

Contested issue #1; plan 01, Phase 5; plans 02.1 and 02.7; Phase 1.

### Execution steps

1. Add one native ingress `DENY` AuthorizationPolicy covering both lanes and scoped to the HTTP
   application listener. It denies methods other than GET, HEAD and OPTIONS unless Origin equals the
   configured serialized browser origin (scheme, host and effective port).
2. Reject absent, empty, `null`, foreign or multi-valued Origin. Do not accept suffix matches or
   derive the trusted value from caller-controlled forwarding headers. Fetch Metadata must not
   provide an exception.
3. Prove rejection of missing, empty, `null` and foreign Origin in the generated configuration and in
   live local requests, plus success for the configured origin on both lanes. Add these as an
   "Origin" section in `verify-edge-contract.sh`.
4. Verify login, logout, hostile same-site and cross-site submissions, and absence of mutation on
   rejected requests with the final CSP. Check `form-action` redirect enforcement in supported
   browsers.
5. Add a static guardrail for the policy, and update the CSRF row and the edge contract docs.
   (amended per contested A2) In those docs, state the configured `Strict` session-cookie default
   and its same-site limit: it does not stop same-site requests, and top-level cookie deletion
   remains possible. Record the observed browser effects from step 4 in the evidence file.

### Implementation notes

- A permissive `ALLOW` rule is not a substitute, because other ALLOW policies are additive.
- This design depends on the existing mesh restrictions preventing browser access around the
  ingress. Internal workload calls use their own caller and path policy.
- The current OAuth GET callback relies on the plan 02.1 browser binding. A future POST callback
  needs an explicit contract change.
- Orchestration verifiers and load-test scripts that send unsafe requests through the ingress must
  supply the configured Origin, as the API-test client does.
- Apply the `kind-kind` checks.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-edge-contract.sh`,
`./scripts/smoketest/verify-session-architecture.sh`, and a browser login and logout.

### Completion criteria

Every unsafe request without the exact Origin is denied on both lanes with no mutation, the
configured origin succeeds, and login and logout work under the final CSP.
