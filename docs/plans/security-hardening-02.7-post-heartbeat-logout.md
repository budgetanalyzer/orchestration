# Security Hardening 02.7: POST Heartbeat And Logout

**Status:** Draft for iteration.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan stops heartbeat and logout changing state through GET. Session Gateway
accepts only a POST heartbeat and a form-POST logout. The frontend, API tests and orchestration
verifiers switch their callers to match.
Phase numbers without a plan refer to this plan.

**Order:** 02.7 of 02.1-02.8. Run after plans 02.4 and 02.6, whose heartbeat cap and cookie
clearing this plan's tests build on.

**Depends on:** plan 01, Phase 5: its CSP `form-action` already allows the form logout and its IdP
redirect.

**Repositories:** session-gateway, budget-analyzer-web, budget-analyzer-api-tests, orchestration.

**Merge unit:** Synchronized. Merge all four PRs together. The gateway rejects the GET calls that
today's frontend, API tests and orchestration verifiers make.

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
- Tilt builds sibling worktrees, so the local stack is inconsistent until every phase before the
  Live phase is complete. Those phases must not rely on a running stack.
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
  POST heartbeat and form-POST logout, in Phases 1-3. Plan 02.8 adds the exact-Origin ingress
  rule. OAuth callback binding stays a separate control (plan 02.1).

## Phase 1: Move heartbeat and logout to POST in Session Gateway

### Workspace

../session-gateway

### Goal

(added per contested #1) Stop heartbeat and logout changing state through GET.

### Scope

`SessionController`, `LogoutController`, the security configuration, tests, and docs.

### Non-goals

A CSRF token system or Fetch Metadata check in Session Gateway, and the OAuth callback, which keeps
the plan 02.1 browser binding.

### Required context

Contested issue #1; plans 02.4 and 02.6.

### Execution steps

1. Move the heartbeat to POST.
2. Accept logout as a same-origin top-level form POST to `/logout`, then a server-constructed 303
   redirect to the configured IdP logout URL.
3. Reject the old mutating GET and HEAD handlers.
4. Add tests for POST success, GET and HEAD rejection, and the 303 target.

### Implementation notes

- Changing only GET to POST does not stop a hostile form submission. Plan 02.8 adds the exact-Origin
  ingress check for both lanes, so Session Gateway needs no separate CSRF implementation.
- The form POST keeps navigation in the browser without adding a JSON URL response contract.

### Validation

The repository's documented build and test commands. Phase 4 proves the live behaviour.

### Completion criteria

Heartbeat and logout respond only to POST, and logout ends with a 303 to the IdP logout URL.

## Phase 2: Move frontend heartbeat and logout callers to POST

### Workspace

../budget-analyzer-web

### Goal

(added per contested #1) Match the POST heartbeat and form-POST logout contract from Phase 1.

### Scope

`src/features/auth/hooks/useAuth.ts`, `src/components/InactivityWarningModal.tsx`,
`src/hooks/useSessionHeartbeat.ts`, a shared logout submission helper, tests, and
`docs/authentication.md`.

### Non-goals

Other session UX changes.

### Required context

Contested issue #1; Phase 1.

### Execution steps

1. Add one helper that submits a same-origin top-level form POST to `/logout`, and share it across
   all four navigation call sites.
2. Move heartbeat calls to POST.
3. Add tests, and update `docs/authentication.md`.

### Implementation notes

Keep the existing `strict-origin-when-cross-origin` referrer policy. A form POST's Origin can become
`null` under `no-referrer`, and the plan 02.8 ingress rule rejects `null`.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

No caller uses GET for heartbeat or logout, and every logout uses the shared form POST helper.

## Phase 3: Use POST heartbeat and logout in the API tests

### Workspace

../budget-analyzer-api-tests

### Goal

(added per contested #1) Keep the API tests working under the POST heartbeat and logout contract.

### Scope

Any heartbeat or logout helpers, and unit tests.

### Non-goals

The Origin header (plan 02.8), new API coverage, and staging or production runs.

### Required context

The repository's `AGENTS.md`; contested issue #1; Phase 1.

### Execution steps

1. Use POST for heartbeat and logout.
2. Update the affected unit tests.

### Implementation notes

Do not run anything against staging or production.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes, and no helper uses GET for heartbeat or logout.

## Phase 4: Move orchestration callers to POST and prove the contract live (Live)

### Workspace

.

### Goal

(added in the split) Update every orchestration caller of heartbeat and logout, and prove the POST
contract on the running stack.

### Scope

Orchestration scripts, verifiers and guardrails that call or describe `/auth/v1/session` or
`/logout`, ingress or NGINX configuration that matches those paths by method, `scripts/README.md`,
`docs/architecture/session-edge-authorization-pattern.md`,
`docs/architecture/security-architecture.md`, and the evidence file.

### Non-goals

The exact-Origin ingress rule (plan 02.8), and fixing service code. If a sibling repository is
wrong, stop and report it.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 1-3.

### Execution steps

1. Find every caller with
   `rg -n 'auth/v1/session|/logout' scripts kubernetes nginx Tiltfile`. Move the callers that make
   these requests to POST, and update the guardrails that assert their method.
2. Check whether any ingress rate-limit or route configuration matches those paths by method, and
   update it if so.
3. Confirm the running images came from the current sibling worktrees.
4. In a browser, log in, wait for a heartbeat, and log out. Confirm logout ends in a 303 to the IdP
   logout URL under the current CSP.
5. Confirm GET and HEAD to both endpoints are rejected without changing the session.
6. Update the endpoint descriptions in the docs in scope, and record the results.

### Implementation notes

The plan 02 split added this phase. The original plan changed the endpoint methods without
updating the orchestration callers. The search in step 1 currently finds references in
`verify-ingress-browser-callback.py`, `verify-session-architecture.sh`, `verify-edge-contract.sh`,
`verify-edge-browser-hardening.sh`, `verify-ingress-rate-limits.sh`, `verify-istio-ingress.sh`, and
the static-security, production-overlay and ingress rate-limit guardrails. Those names come from a
reference search only. Decide each change from the script itself.

### Validation

Orchestration static gate, `verify-session-architecture.sh`, `verify-istio-ingress.sh`,
`verify-ingress-rate-limits.sh`, `verify-edge-contract.sh`, `verify-edge-browser-hardening.sh`,
`verify-ingress-browser-callback.py`, and a browser login, heartbeat and logout.

### Completion criteria

No orchestration caller uses GET for heartbeat or logout, the verifiers pass, and browser logout
ends with a 303 to the IdP.
