# Heartbeat Permission Refresh Phase 3 Execution Report

**Date:** 2026-10-13

**Environment:** Native development VM, local `kind-kind` cluster

**Plan:** [Refresh Authorization Before Extending Browser Sessions](heartbeat-permission-refresh-plan.md)

## Result

Phase 3 passed. Heartbeat is the authorization refresh boundary, while normal
`/api/*` authorization remains Redis-only. The existing local and production
mesh and network policies already admit the internal Session Gateway to
permission-service lookup, and neither public NGINX configuration exposes the
internal route. No deployment-policy change was required.

The canonical session-edge and security documentation now records the `401`
versus `503` behavior, unchanged activity and idle-lifetime rules, normal
two-minute observation cadence, remaining-TTL fallback, and accepted in-flight
race. Emergency admin containment remains a separate operator procedure.

## Validation Evidence

- `./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime`
  passed, including the exact loopback `kind-kind` target checks.
- `bash -n` and `shellcheck` passed for
  `scripts/repo/generate-unified-api-docs.sh` and
  `scripts/smoketest/verify-session-architecture.sh`.
- `./scripts/smoketest/verify-session-architecture.sh --static-only` passed
  all 39 checks.
- `./scripts/smoketest/verify-session-architecture.sh` passed all 58 static
  and live checks, including live workload readiness, Istio authorization,
  NetworkPolicy presence, Redis ACLs, and session keyspace hygiene.
- The Session-Gateway-only generator mode wrote a 7,011-byte YAML file to a
  disposable orchestration path. The output contained
  `/auth/v1/session`, contained no `/internal/*` path, and did not change the
  unified docs or frontend docs worktrees. Missing, ambiguous, and non-YAML
  output arguments were rejected.

## Focused Local Scenarios

One uniquely named disposable user and Redis session were created after the
local target preflight and removed afterward.

| Scenario | Evidence |
| --- | --- |
| Redis-only API path | A Redis-seeded USER session, without login or heartbeat, received `200` from `/api/v1/transactions`; static source/wiring checks confirm `ext-authz` reads Redis and has no permission-service client. |
| Grant refresh boundary | The same session received `403` from `/api/v1/users`. After its database role changed from USER to ADMIN, the API still returned `403` before heartbeat. Heartbeat returned `200`, atomically changed the Redis role to ADMIN with `users:read`, and the next API request returned `200`. |
| Retained-session deactivation fallback | Direct fixture deactivation represented a failed immediate bulk deletion and left the Redis session present. Heartbeat returned `401`, sent an expired `BA_SESSION` cookie, and removed the session. The next protected API request returned `401`. |
| Cleanup | The exact fixture user, role assignment, session hash, and user-session index were absent after cleanup. |

## Limits

The shared cluster was not disrupted to manufacture permission-service timeout
or Redis failure. Phase 2's isolated integration tests cover lookup timeout,
invalid payload, service failure, Redis mutation failure, and concurrent
session disappearance. The accepted login/heartbeat race remains: an
authorization result obtained just before a concurrent account or grant change
may still be applied, so the remaining TTL is not a strict deadline measured
from the deactivation commit.
