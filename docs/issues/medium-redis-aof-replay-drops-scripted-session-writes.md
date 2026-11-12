# Redis AOF replay drops scripted session writes

- **Severity:** Medium
- **Owner:** orchestration (`kubernetes/infrastructure/redis/`)
- **Status:** Open
- **Source:** live `ACL LOG` inspection, 2026-11-12 (security documentation reorganization follow-up)

## Problem

When Redis starts, it replays the AOF. Commands in `MULTI`/`EXEC` blocks are
denied during that replay, so their writes are lost.

Redis 7 writes the effects of a Lua script to the AOF as a `MULTI`/`EXEC`
block. The AOF loader runs as the `default` user. Redis does not check ACLs
for plain replayed commands, but `EXEC` re-checks ACLs for every queued
command. `kubernetes/infrastructure/redis/start-redis.sh` limits `default` to
`+ping +auth`, so every command queued in a replayed transaction is refused
with `NOPERM` and skipped. Upstream tracks this behavior in redis/redis#14156.

Observed on the local cluster (Redis 7.4, uptime about 6,000 s):

- Every `default`-user `ACL LOG` entry has context `multi`, `cmd=exec`,
  `fd=-1`, client id `18446744073709551615` (the AOF loader client), and an
  age equal to the Redis uptime.
- Denied counts: `hset` 990, `pexpireat` 685, `sadd` 33, `select` 1.
- `appendonly.aof.<n>.incr.aof` contained 578 `MULTI`/`EXEC` blocks.

These Session Gateway writes are scripted, so they are lost:

- session creation (`create-session.lua`);
- heartbeat and permission refresh (`conditional-update.lua`);
- bulk revocation (`delete-user-sessions.lua`);
- OAuth state creation (`RedisAuthorizationRequestRepository`).

Single-session logout uses top-level `UNLINK` and `SREM`. Currency-service
cache writes are also top-level. Both replay normally. The base RDB written at
the last AOF rewrite also loads normally.

## Impact

- **Lost sessions.** A Redis restart loses every session and pending login
  created since the last AOF rewrite, so those users must log in again. It
  fails closed. But `docs/architecture/security-architecture.md` (Redis, high
  availability section) says "a pod restart keeps sessions", and that is only
  true for sessions present in the base RDB.
- **Revoked sessions can come back.** Suppose a session is in the base RDB and
  a bulk revocation deletes it after the rewrite. On restart the deletion is
  dropped and the session is valid again. Its refresh writes were dropped too,
  so it keeps the expiry recorded in the base RDB, which is at most the idle
  TTL (`SESSION_TTL_SECONDS`, 900 s by default) after the rewrite. The window is
  narrow, but this undoes a security control (emergency containment).
- **Stale data.** Restored sessions carry permissions and expiry from the
  base RDB, not from their last refresh.
- **Production reference.** It reuses the same Redis base through
  `kubernetes/production/infrastructure/kustomization.yaml`, so it inherits
  the defect.

## Proposed fix

Choose one option and record it:

- **Allow replay as `default` and block logins.** Change the `default` user to
  `off` with full permissions (`reset off ~* &* +@all`), which keeps replay
  working while refusing logins as `default`. Move the liveness and readiness
  probes off `default` first. They currently authenticate through
  `REDISCLI_AUTH` with `default-password`. Give them a dedicated `+ping` user,
  or use `redis-ops`.
- **Upstream fix.** If a supported Redis release skips the `EXEC` ACL re-check
  for the AOF client, upgrade to it instead.

Either way, reset local Redis state before relying on the fix, in line with
ADR 015. Use `./scripts/ops/flush-redis.sh`, which runs `FLUSHALL` and
`BGREWRITEAOF`. Without the reset, the first fixed start would replay
transactions that earlier starts dropped.

## Acceptance

- After `kubectl rollout restart statefulset/redis -n infrastructure`,
  `ACL LOG` has no `default`-user entries from the AOF loader client.
- A session created after the last AOF rewrite still works after a Redis
  restart.
- A bulk revocation made after the last AOF rewrite still holds after a
  Redis restart.
- Logging in as `default` is refused, and the Redis probes still pass.
- `verify-credential-isolation.sh` asserts both behaviors.
- The "pod restart keeps sessions" sentence in `security-architecture.md` is
  accurate.
