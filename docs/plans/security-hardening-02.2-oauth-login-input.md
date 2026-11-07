# Security Hardening 02.2: Bounded OAuth Login Input

**Status:** Draft for iteration.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan validates and caps `returnUrl`, shortens the OAuth state lifetime,
lets deployments fix the IdP redirect URI, and stops the login page trusting `returnUrl`.
Phase numbers without a plan refer to this plan.

**Order:** 02.2 of 02.1-02.8. Run after plan 02.1, which edits the same repository class.

**Depends on:** plan 01.

**Repositories:** session-gateway, budget-analyzer-web, orchestration.

**Merge unit:** Independent. Each PR is safe on its own, in any order:
- The gateway's `redirect-uri` default keeps `{baseUrl}`, so it needs no new configuration.
- Today's gateway ignores `IDP_REDIRECT_URI`.
- The frontend check is local.

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

## Phase 1: Bound OAuth login input

### Workspace

../session-gateway

### Goal

Validate and cap what an anonymous login can store, shorten how long it stays, and stop building the
callback URL from request headers.

### Scope

`OAuth2ClientConfig`, `RedisAuthorizationRequestRepository`, `RedirectUrlValidator`,
`application.yml`, tests, and `docs/session-configuration.md`.

### Non-goals

Rate limits, and Redis memory settings, which are plan 04, Phase 1.

### Required context

R2 "Validate and cap `returnUrl`" and finding H; R3 on `noeviction`;
`../budget-analyzer-web/src/features/auth/utils/loginRedirect.ts`.

### Execution steps

1. In `addReturnUrlAdditionalParameter`, keep `returnUrl` only if it passes `RedirectUrlValidator`
   and is at most 2048 characters. Otherwise drop it and continue the login.
2. Remove the fallback in `saveAuthorizationRequest` that re-reads `returnUrl` from the request.
3. Tighten `RedirectUrlValidator`: reject backslashes, control characters and whitespace, and require
   a value that parses as a `java.net.URI` with no scheme or authority. Add tests for `/\evil.com`,
   an embedded tab, and a value with spaces.
4. Change the `SESSION_OAUTH2_STATE_TTL_SECONDS` default to 600.
5. Set `redirect-uri` to `${IDP_REDIRECT_URI:{baseUrl}/login/oauth2/code/{registrationId}}`, so a
   deployment can fix the URI and local non-Kubernetes runs keep working.
6. Update the docs.

### Implementation notes

- Without step 2, step 1 does nothing. When the additional parameter is absent, lines 98-109 read
  the raw query parameter and store it unchecked.
- Dropping a bad value is deliberate. The user still signs in and lands on the default page.
- The validator's parse check also closes a failure-path bug: an unparsable value that passes today
  makes `URI.create` throw in the redirect.
- R2 proposes 5-10 minutes for the OAuth state. Hosted logins with MFA can be slow, so this uses the
  upper end.
- A login-start cap does not stop anonymous growth. It only bounds each record. Plan 04, Phase 1 records the
  remaining gap.

### Validation

The repository's documented build and test commands.

### Completion criteria

An oversized or unsafe `returnUrl` is never stored, the validator matches the frontend's rejections,
and the redirect URI can be fixed by configuration.

## Phase 2: Stop trusting `returnUrl` on the login page

### Workspace

../budget-analyzer-web

### Goal

Navigate to `returnUrl` on the login page only after the same safety check `login()` uses.

### Scope

`LoginPage`, its tests, and the `returnUrl` description in `docs/authentication.md`.

### Non-goals

The session lifetime cap (plan 02.4), cookie-name references (plan 02.6), and POST heartbeat and
logout (plan 02.7).

### Required context

`docs/authentication.md`; `src/features/auth/utils/loginRedirect.ts`; Phase 1.

### Execution steps

1. In `LoginPage.tsx:30`, pass `returnUrl` to `navigate` only if `isSafeReturnUrl` accepts it, and add
   a test.
2. Update the docs.

### Implementation notes

R2 notes that `LoginPage` is not exploitable today, because the browser refuses cross-origin
history changes. This makes it safe by construction, since `login()` already validates the same
value.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

An unsafe `returnUrl` falls back to the default path, and the test passes.

## Phase 3: Configure the IdP redirect URI and verify login input live (Live)

### Workspace

.

### Goal

Let orchestration set the IdP redirect URI explicitly, and prove logins still work with the bounded
input.

### Scope

`kubernetes/services/session-gateway/idp-configmap.yaml`, the Tiltfile's
`session-gateway-idp-config`, the environment-specific list in `kubernetes/production/README.md`,
the owner docs that describe the redirect URI, and the evidence file.

### Non-goals

Fixing service code. If a sibling repository is wrong, stop and report it.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 1 and 2.

### Execution steps

1. Add `IDP_REDIRECT_URI` to `idp-configmap.yaml`, the Tiltfile's `session-gateway-idp-config` and
   the environment-specific list in `kubernetes/production/README.md`.
2. (added in the split) Confirm the running images came from the current sibling worktrees.
3. (added in the split) Log in from a deep link and confirm it returns to that page. Log in with a
   `returnUrl` of `/\evil.com` and confirm it lands on the default page.
4. Update the docs and record the results.

### Implementation notes

The configured value must equal the callback URL registered with the IdP, which is what
`{baseUrl}` produces today.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-session-architecture.sh` and
`verify-ingress-browser-callback.py`.

### Completion criteria

The redirect URI comes from configuration, logins succeed, and an unsafe `returnUrl` falls back to
the default page live.
