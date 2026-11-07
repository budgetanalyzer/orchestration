# Security Hardening 02.6: `__Host-` Session Cookie

**Status:** Draft for iteration.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan renames the session cookie to `__Host-BA_SESSION` in every consumer
and removes the configuration that conflicts with it. It also aligns the API tests with the plan 01
edge 503 contract.
Phase numbers without a plan refer to this plan.

**Order:** 02.6 of 02.1-02.8.

**Depends on:** plan 01: its edge 503 contract.

**Repositories:** session-gateway, ext-authz, budget-analyzer-web, budget-analyzer-api-tests,
orchestration.

**Merge unit:** Synchronized. Merge the session-gateway, ext-authz, budget-analyzer-api-tests and
orchestration PRs together:
- The gateway issues the new cookie name.
- ext-authz must read that name, through its default and the deployment's explicit
  `SESSION_COOKIE_NAME`.
- The verifiers and API-test environments must use that name too.

The budget-analyzer-web PR changes only comments and docs, because the cookie is HttpOnly. It may
merge at any time.

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
| D4 | `SESSION_COOKIE_DOMAIN_OVERRIDE` | Remove it | `__Host-` forbids a `Domain` attribute. No checked-in deployment sets the override. | Recommendation confirmed by contested #5 |

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

**Cutover rule:** `kubernetes/production` shares these manifests but pins older images
(session-gateway 0.0.15, ext-authz 0.0.16) that lack the new cookie. The offline checks do not catch
this. Plan 05, Phase 3 records the release and pin updates, which are human-owned. No production
environment exists, so no dual-cookie migration is needed.

## Contested decisions applied

- [#5, duplicate session cookies](../research/security-review-contested-issues-2026-11-02.md#5-rejecting-duplicate-session-cookies):
  `__Host-` is the main protection. Duplicate rejection is optional after the cutover and not in
  these plans. D4 is confirmed.

## Phase 1: Move Session Gateway to the `__Host-` session cookie

### Workspace

../session-gateway

### Goal

Make `__Host-BA_SESSION` the default name, and remove the configuration that conflicts with it.

### Scope

`application.yml`, `SessionProperties`, `SessionCookieHelper`, tests, and docs.

### Non-goals

Duplicate-cookie rejection (amended per contested #5: optional after the cutover and not in these
plans).

### Required context

R2 CSRF section; R3 and R4 on `__Host-`; `docs/session-configuration.md`.

### Execution steps

1. Change the `SESSION_COOKIE_NAME` default.
2. Apply D4 by removing the Domain override, or fail at startup if it is combined with `__Host-`.
3. Fail at startup if the name starts with `__Host-` and `secure` is false.
4. Update tests and docs.

### Implementation notes

Confirm the actual `Set-Cookie` output, because browsers silently reject a malformed `__Host-`
cookie.

### Validation

The repository's documented build and test commands.

### Completion criteria

The cookie is issued with `Secure`, `Path=/` and no `Domain`, including when clearing it.

## Phase 2: Match the cookie default in ext-authz

### Workspace

../ext-authz

### Goal

Make ext-authz default to the same session cookie name as Session Gateway.

### Scope

`config.go`, tests, and `README.md`.

### Non-goals

Hashed keys (plan 02.5), the lifetime cap (plan 02.4), and health endpoints and server timeouts,
which are plan 03, Phase 1.

### Required context

`config.go`; Phase 1.

### Execution steps

1. Change the `SESSION_COOKIE_NAME` default to `__Host-BA_SESSION`.
2. Update tests and `README.md`.

### Implementation notes

The orchestration deployment also sets the name explicitly. Phase 5 updates it.

### Validation

`go test ./...` and the repository's other documented checks.

### Completion criteria

The cookie default matches Session Gateway.

## Phase 3: Update frontend references to the session cookie name

### Workspace

../budget-analyzer-web

### Goal

Keep the frontend's references to the session cookie accurate.

### Scope

`src/api/client.ts` and `docs/authentication.md`.

### Non-goals

Other session UX changes, and moving heartbeat and logout to POST (plan 02.7).

### Required context

`docs/authentication.md`; Phase 1.

### Execution steps

1. Update the `BA_SESSION` references in `src/api/client.ts` and `docs/authentication.md`.

### Implementation notes

The cookie is HttpOnly, so no code reads its name.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

No frontend reference names the old cookie.

## Phase 4: Update API tests for the cookie and edge contract

### Workspace

../budget-analyzer-api-tests

### Goal

Keep the API tests aligned with the cookie name and the edge error contract.

### Scope

`environments/*.yaml`, unit tests that reference `BA_SESSION`, and `AGENTS.md`.

### Non-goals

New API coverage beyond these changes, the OAuth binding cookie (plan 02.1), POST heartbeat and
logout (plan 02.7), and the Origin header (plan 02.8).

### Required context

The repository's `AGENTS.md`; plan 01, Phase 4; Phase 1.

### Execution steps

1. Update `session_cookie_name` in the environment files and the affected tests.
2. Find any test that expects a JSON body on an edge 503, and align it with plan 01, Phase 4.

### Implementation notes

- Do not run anything against staging or production. Those files are only updated for consistency.
- Step 2 does not depend on the cookie rename. It ships in this PR because plan 02 grouped it with
  the other API-test contract updates.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes with the new cookie name and the edge 503 contract.

## Phase 5: Wire the cookie name into orchestration

### Workspace

.

### Goal

Update every orchestration consumer of the session cookie name, ready for the live cutover.

### Scope

`kubernetes/services/ext-authz/deployment.yaml`, `kubernetes/services/session-gateway/`,
`Tiltfile`, the scripts and verifiers that reference `BA_SESSION`, and the owner docs.

### Non-goals

Hashed keys (plan 02.5), and `kubernetes/production` image pins.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 1-4.

### Execution steps

1. Set `SESSION_COOKIE_NAME=__Host-BA_SESSION` on ext-authz. Update any session-gateway manifest or
   Tiltfile entry that sets the name or the Domain override.
2. Find every remaining reference with
   `rg -n 'BA_SESSION' scripts kubernetes nginx Tiltfile docs SECURITY.md --glob '!docs/archive/**' --glob '!docs/decisions/**'`.
   Update the active scripts, including `verify-session-architecture.sh`,
   `verify-istio-ingress.sh`, `verify-credential-isolation.sh`, `verify-ingress-rate-limits.sh` and
   `verify-edge-contract.sh`. Leave plans and research records alone.
3. Add a static check that both repositories default to the same cookie name.
4. Update the cookie descriptions in `docs/architecture/session-edge-authorization-pattern.md`,
   `docs/architecture/security-architecture.md`, `SECURITY.md`, `docs/runbooks/tilt-debugging.md`,
   `docs/development/local-environment.md` and `docs/architecture/deployment-architecture-gcp.md`.

### Implementation notes

Scripts that build the `Cookie` header from a seeded token need the new name. Scripts that use a
cookie jar from a real login get it from the gateway, provided they talk to the ingress over HTTPS,
because a client must not store a `__Host-` cookie from a plain-HTTP response.

### Validation

Orchestration static gate and `./scripts/smoketest/verify-session-architecture.sh --static-only`.

### Completion criteria

No active orchestration consumer still assumes the old cookie name, and the static checks pass.

## Phase 6: Cut over to the `__Host-` cookie and prove it live (Live)

### Workspace

.

### Goal

Prove on the running stack that the new cookie works end to end with the required attributes.

### Scope

The evidence file, and any fixes the cutover exposes in orchestration.

### Non-goals

Fixing service code. If a sibling repository is wrong, stop and report it.

### Required context

Phases 1-5.

### Execution steps

1. Confirm the running images came from the current sibling worktrees.
2. Run login, an API call, a heartbeat and logout. Confirm the `Set-Cookie` attributes in a browser.
3. Run the verifiers below.

### Implementation notes

- Old `BA_SESSION` cookies in local browsers become inert. No compatibility path is needed.
- Use disposable local credentials, and never record cookie or token values.

### Validation

Orchestration static gate, `verify-session-architecture.sh`, `verify-istio-ingress.sh`,
`verify-ingress-rate-limits.sh`, `verify-credential-isolation.sh` and `verify-edge-contract.sh`.

### Completion criteria

Session Gateway, ext-authz, the verifiers and the API tests use one cookie name, the browser stores
it with `Secure`, `Path=/` and no `Domain`, and the verifiers pass.
