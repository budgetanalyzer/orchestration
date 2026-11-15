# 018. Disable the `redis-session` `default` User Instead of Restricting It

**Date:** 2026-11-15
**Status:** Accepted
**Deciders:** Architecture Team

## Context

`redis-session` holds sessions, session indexes and OAuth state, with AOF on a
PVC (see [ADR 016](016-separate-session-and-cache-redis.md)). Its ACL limited
`default` to `+ping +auth` with a password, and the liveness and readiness
probes authenticated as `default`.

Redis 7 writes the effects of a Lua script to the AOF as one batch. A batch
with one write is logged as a plain command; a batch with more than one is
wrapped in `MULTI`/`EXEC`. The AOF loader runs as `default`. Redis does not
check ACLs for plain replayed commands, but `EXEC` re-checks them for every
queued command. With a restricted `default`, each command in a replayed
transaction was refused with `NOPERM` and skipped. Upstream tracks this in
[redis/redis#14156](https://github.com/redis/redis/issues/14156), still open on
2026-11-15.

These Session Gateway writes are multi-write and were lost on restart:

- session creation (`create-session.lua`);
- heartbeat and permission refresh (`conditional-update.lua`, when the
  session exists);
- OAuth state creation (`RedisAuthorizationRequestRepository`).

Bulk revocation (`delete-user-sessions.lua`) normally logs one `DEL` and
replays. When an indexed session key has expired but is still in memory,
`DEL` first lazily expires it and logs that deletion too. Redis then wraps
both deletions in `MULTI`/`EXEC`, and replay dropped the revocation.

On 2026-11-12 the local cluster (Redis 7.4) showed the defect. Every `default`
`ACL LOG` entry came from the AOF loader client (id `18446744073709551615`) in
`multi` context: `hset` 990, `pexpireat` 685, `sadd` 33, `select` 1. The
incremental AOF held 578 `MULTI`/`EXEC` blocks. The impact:

- A restart lost every session and pending login created since the last AOF
  rewrite. This failed closed.
- Restored sessions kept the permissions and expiry from the base RDB, not
  their last refresh.
- A revoked session could come back if its revocation was wrapped. This undid
  emergency containment. The window was bounded by the idle TTL after the
  last rewrite.
- The production reference uses the same base, so it had the same defect.

## Decision

1. Set `user default reset off ~* &* +@all` in
   `kubernetes/infrastructure/redis-session/start-redis.sh`. `off` refuses
   every client authentication as `default`. The full permissions exist only
   so the AOF loader can replay.
2. Add `user redis-health reset on >${REDIS_SESSION_HEALTH_PASSWORD} +ping`,
   with no key or channel access. Both probes run
   `redis-cli -e --tls --cacert /tls-ca/ca.crt --user redis-health ping` with
   `REDISCLI_AUTH` from the bootstrap Secret key `health-password`. The probe
   must keep `-e`: without it, `redis-cli` on the pinned image exits 0 even
   when authentication fails.
3. Retire `REDIS_SESSION_DEFAULT_PASSWORD` and its `default-password` Secret
   key. This amends ADR 016's credential list. `redis-session` now uses
   `REDIS_SESSION_HEALTH_PASSWORD` and `REDIS_SESSION_OPS_PASSWORD`.
   `redis-cache` has no AOF and keeps its `default` wiring unchanged.
4. Keep the pinned Redis image. Changing the image is a separate dependency
   decision. Before relying on a new image, rerun the isolated harness
   `scripts/guardrails/verify-redis-session-aof-replay.sh --mode all`.
5. Static guardrails reject a re-enabled `default`, extra `redis-health`
   grants, probes without `--user` or `-e`, and a missing `health-password`.
   `verify-credential-isolation.sh` asserts the live ACL, and
   `verify-redis-session-persistence.sh --allow-restart` is the live restart
   proof. Interfaces are in `scripts/README.md`.
6. Cut over with a one-time local reset under
   [ADR 015](015-reset-local-state-instead-of-migrating.md). No start with the
   fixed configuration may load AOF history written under the restricted
   `default`. Earlier starts skipped writes in that history, so later commands
   acted on a different in-memory state, and a full replay could restore
   revoked sessions. Flush the old instance while it still runs, then start
   the fixed configuration. Session writers keep running: writes after the
   flush were applied in memory and replay correctly. The procedure is
   [Redis Session ACL Cutover](../development/local-environment.md#redis-session-acl-cutover).

## Alternatives Considered

### Alternative 1: Upgrade to a Redis release that skips the `EXEC` re-check
**Pros:**
- Fixes the cause and keeps a restricted `default`.

**Cons:**
- On 2026-11-15 the upstream issue is open, and no fixed release on the pinned
  7.4 line was identified.
- A Redis upgrade is a dependency decision with its own validation. It was not
  proven against this workload.

### Alternative 2: Probes authenticate as `redis-ops`
**Pros:**
- No new user, password or Secret key.

**Cons:**
- Puts the full-admin password in the pod environment for kubelet exec probes.
  Anyone who can read it can run `FLUSHALL`, `ACL`, `CONFIG` and `SHUTDOWN`.
- A `+ping`-only user gives the probes what they need and nothing more.

### Alternative 3: Keep `default` enabled with narrow replay grants
**Pros:**
- Probes stay on `default`.

**Cons:**
- `default` stays reachable by clients. Any grant broad enough for replay lets
  a holder of the `default` password write session data, including forged
  sessions.
- The grants must track every command any script can log, including lazy
  expiry `DEL` and `SELECT`. A missed command silently drops writes again.

## Consequences

**Positive:**
- Restarts preserve sessions, session indexes, refreshed grants and
  expirations, OAuth state and bulk revocations, including a revocation that
  lazily expires an indexed key.
- No client can authenticate as `default`. The probes have least privilege,
  and a wrong probe credential fails the probe.

**Negative:**
- Redis keeps its default `appendfsync everysec`, so a crash or node loss can
  still lose about the last second of writes, including a revocation.
  Durability is bounded by one replica and its PVC.
- The expired-but-present revocation case needs `DEBUG`, so only the isolated
  harness proves it. The live proof covers revocation with all members live
  and with a member already gone.
- The production reference uses the same ACL and probes. Only its offline
  render is checked; it has no runtime validation.
- `default` holds `+@all`. Its safety depends on `off`, which the static
  guardrail and the credential isolation verifier enforce.
- The cutover reset logged every local user out once and dropped pending
  logins.

**Neutral:**
- Replay keeps absolute expirations, so a restart never extends a session or
  OAuth state. Keys whose expiry passed while Redis was down are gone after
  the restart.

## Verification

All results are from 2026-11-15, with the pinned image
`docker.io/library/redis@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499`
(Redis 7.4.11).

**Isolated harness.** `verify-redis-session-aof-replay.sh --mode all` passed
214 checks with no failures. It runs each case in a network-less container.
Each case writes after a base rewrite, then restarts Redis:

| Case | Incremental AOF | Restricted `default` | Disabled `default` |
| --- | --- | --- | --- |
| Session creation | `MULTI`/`EXEC` | Session and index lost | Restored |
| Heartbeat refresh | `MULTI`/`EXEC` | Reverts to base values | Refreshed values restored |
| OAuth state creation | `MULTI`/`EXEC` | Lost | Restored |
| Revocation, all members live | single `DEL` | Holds | Holds |
| Revocation, expired key still present | `MULTI`/`EXEC` | Revoked session returns | Holds |
| Revocation, member key already gone | single `DEL` | Holds | Holds |

- The harness read the Session Gateway scripts directly. Their SHA-256
  prefixes were `create-session.lua` `be706487`, `conditional-update.lua`
  `380dbb54`, `delete-user-sessions.lua` `5eb156c1` and
  `RedisAuthorizationRequestRepository.java` `46cbbc2a`. It read the ACL
  heredoc from `start-redis.sh`, prefix `ea78b97d`. A later edit changed only
  a comment in that file, so its hash changed but the ACL did not.
- Re-enabling `default` in a temporary copy produced 20 failures, and the
  loader denials returned.
- In the disabled mode, `default` logins were refused in every form: none,
  password-only `AUTH`, and `AUTH` or `HELLO` naming `default`. `redis-health`
  got `PONG` and was denied key access, admin commands, `SELECT`, `PUBLISH`
  and `EVAL`.

**Offline render checks.**
- The `verify-static-security-manifests.sh` self-test rejected all seven
  `redis-session` mutants, and the full run passed on the local and production
  infrastructure renders.
- `verify-production-image-overlay.sh` and `check-secrets-only-handling.sh`
  passed.
- The local and production renders had identical `start-redis.sh`, probes and
  `redis-session` environment.

**Cutover reset.**
- With Tilt stopped and session writers running, `flush-redis.sh session`
  flushed the old instance at 11:46:49Z.
- The AOF manifest then held only the sequence 2 base and an empty incremental
  file. The pre-flush sequence 1 history was gone.
- `tilt up` then rolled out the fixed configuration. The output of the
  pre-start check was not captured. When live verification began, the
  rewrite count was still 0, and the verifier's first rewrite produced
  sequence 3. The first fixed start therefore loaded the post-flush
  sequence 2.

**Live local Kind.**
- As `redis-ops`, `ACL GETUSER default` showed `off ~* &* +@all`. `ACL LOG`
  had no AOF-loader entries.
- `verify-credential-isolation.sh` passed 130 checks: `default` logins were
  refused, `redis-health` was limited to `PING`, and both probes passed with
  the health credential and failed with a wrong one.
- `verify-redis-session-persistence.sh --allow-restart` passed 78 checks over
  two `kubectl rollout restart` cycles on the same PVC.
  - Session creation, heartbeat refresh and OAuth state, each logged as
    `MULTI`/`EXEC`, survived. Hashes, index membership and absolute
    expirations matched, and the restored sessions authorized a protected
    ingress request.
  - Bulk revocations, all members live and one member already gone, held
    through the second restart. The revoked cookies stayed denied with `401`.
  - The exit trap removed every synthetic key.
- `verify-runtime-hardening.sh` passed 191 checks, and
  `verify-transport-encryption.sh` passed 22.

## References
- [Security Architecture: High Availability Configuration](../architecture/security-architecture.md#high-availability-configuration)
- [Local Environment: Redis Session ACL Cutover](../development/local-environment.md#redis-session-acl-cutover)
- [Secrets-Only Handling](../development/secrets-only-handling.md)
- [Scripts: Guardrails](../../scripts/README.md#guardrails) and [Smoketest](../../scripts/README.md#smoketest)
- [ADR 015: Reset Local State Instead of Migrating](015-reset-local-state-instead-of-migrating.md)
- [ADR 016: Separate Session and Cache Redis Instances](016-separate-session-and-cache-redis.md), whose session credential list this ADR amends
- [redis/redis#14156](https://github.com/redis/redis/issues/14156)
- Source: the issue "Redis AOF replay drops scripted session writes", from live
  `ACL LOG` inspection on 2026-11-12, and its implementation plan. Both were
  deleted after this ADR was written; see Git history.
