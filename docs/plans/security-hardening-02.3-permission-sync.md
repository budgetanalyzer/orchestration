# Security Hardening 02.3: Login Permission Sync

**Status:** Draft for iteration.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan replaces the user-sync GET that writes at login with an explicit POST,
gives the login permission call a deadline, and narrows the mesh policy to the new call.
Phase numbers without a plan refer to this plan.

**Order:** 02.3 of 02.1-02.8.

**Depends on:** plan 01: its `permission-service-policy` rule for the current login path.

**Repositories:** permission-service, session-gateway, orchestration.

**Merge unit:** Synchronized. Merge all three PRs together:
- permission-service removes the GET that today's gateway calls at login.
- The gateway's POST needs both the new endpoint and the new mesh rule.
- The new mesh rule blocks the old GET.

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

**Cutover rule:** `kubernetes/production` shares these manifests but pins an older Session Gateway
image (0.0.15). This plan's mesh policy blocks that image's login call, and the offline checks do
not catch it. Plan 05, Phase 3 records the release and pin updates, which are human-owned.

## Contested decisions applied

- [#10, `deleteUser`](../research/security-review-contested-issues-2026-11-02.md#10-the-unused-deleteuser-method):
  the method is removed in plan 03, Phase 8, not here.

## Phase 1: Replace the user-sync GET in permission-service

### Workspace

../permission-service

### Goal

Make the write that happens at login an explicit POST, with personal fields out of the URL.

### Scope

`InternalPermissionController`, `PermissionServiceSecurityConfig`, tests, and docs.

### Non-goals

`deleteUser` (amended per contested #10: removed in plan 03, Phase 8), and
the read-only authorization lookup.

### Required context

R2 finding E; R3 N1 on why a GET that writes matters; R4 "Login permissions (E)".

### Execution steps

1. Add `POST /internal/v1/users/sync` with a JSON body of `idpSub`, `email` and `displayName`,
   returning the existing response.
2. Remove `GET /internal/v1/users/{idpSub}/permissions`.
3. Update `PermissionServiceSecurityConfig` to permit the POST and the authorization GET only.
4. Keep the existing behaviour for deactivated users.
5. Update tests and the controller's OpenAPI annotations.

### Implementation notes

Taking `idpSub` from the body gives the mesh one exact path to allow in Phase 3, and keeps all
three fields out of access logs and traces. The GET is removed rather than kept, because no
production environment needs a transition.

### Validation

The repository's documented build and test commands.

### Completion criteria

User sync happens only through the POST, and no personal field appears in its URL.

## Phase 2: Move the login permission call to POST with a deadline

### Workspace

../session-gateway

### Goal

Stop a slow permission-service from hanging logins, and use the new sync call.

### Scope

`PermissionServiceClient`, `PermissionServiceProperties`, `application.yml`, tests, and docs.

### Non-goals

Transport-pool tuning and the heartbeat lookup, which already has a timeout.

### Required context

R2 finding E; R4 "Login permissions (E)"; Phase 1.

### Execution steps

1. Change `fetchPermissions` to `POST /internal/v1/users/sync` with a JSON body.
2. Add `permission-service.login-timeout` from `PERMISSION_SERVICE_LOGIN_TIMEOUT`, defaulting to 5 s,
   and apply it with `.timeout()`.
3. Map timeouts and transport failures to `PermissionServiceException`, as `fetchAuthorization` does.
4. Add a test with a delayed stub: the callback redirects to `/oops` and creates no session.

### Implementation notes

R4 is right that a bare `WebClient` builder does not prove there is no connect timeout. An
operation deadline bounds the whole call either way. The existing `onErrorResume` in
`handleAuthenticationSuccess` already handles the failure.

### Validation

The repository's documented build and test commands.

### Completion criteria

A hung permission-service fails a login within the deadline, with no session created.

## Phase 3: Wire the sync call into the mesh and prove login live (Live)

### Workspace

.

### Goal

Allow only the new sync call through the mesh, update every orchestration consumer of the old path,
and prove login works on the running stack.

### Scope

`kubernetes/istio/authorization-policies.yaml`, every orchestration script or manifest that
references the old login path, the owner docs that describe it, and the evidence file.

### Non-goals

`kubernetes/production` image pins, and fixing service code. If a sibling repository is wrong, stop
and report it.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; plan 01, Phase 1 step 7; Phases 1 and 2.

### Execution steps

1. Change `permission-service-policy` so Session Gateway gets `POST` on
   `/permission-service/internal/v1/users/sync` and `GET` on the authorization path only.
2. (added in the split) Find every remaining reference with
   `rg -n 'internal/v1/users' scripts kubernetes nginx Tiltfile docs --glob '!docs/archive/**' --glob '!docs/decisions/**'`
   and update the active verifiers, guardrails and owner docs. Leave plans and research records
   alone.
3. Confirm the running images came from the current sibling worktrees.
4. Log in as a new and an existing user and confirm each gets a session with the expected
   permissions.
5. Update `docs/architecture/security-architecture.md` and
   `docs/architecture/session-edge-authorization-pattern.md` where they describe the login
   permission call, and record the results.

### Implementation notes

The search in step 2 currently finds the path in `verify-istio-ingress.sh`,
`verify-security-prereqs.sh`, `verify-edge-contract.sh`, `verify-session-architecture.sh`,
`verify-production-image-overlay.sh` and `verify-nginx-shared-routes.sh`. Those names come from a
reference count only. Decide each change from the script itself.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-session-architecture.sh`,
`./scripts/smoketest/verify-istio-ingress.sh`, `./scripts/smoketest/verify-edge-contract.sh` and
a browser login.

### Completion criteria

The mesh allows only the POST sync and the authorization GET, no active orchestration consumer
references the old path, and login works live.
