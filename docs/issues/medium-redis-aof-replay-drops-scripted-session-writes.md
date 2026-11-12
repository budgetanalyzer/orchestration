# Redis AOF replay drops scripted session writes

- **Severity:** Medium
- **Owner:** orchestration (`kubernetes/infrastructure/redis/`)
- **Status:** Open
- **Source:** live `ACL LOG` inspection, 2026-11-12 (security documentation reorganization follow-up)

## Problem

When Redis starts, it replays the AOF. Commands in `MULTI`/`EXEC` blocks are
denied during that replay, so their writes are lost.

Redis 7 writes the effects of a Lua script to the AOF as one batch. If the
batch has one write, Redis logs it as a plain command. If it has more than
one, Redis wraps them in a `MULTI`/`EXEC` block. The AOF loader runs as the
`default` user. Redis does not check ACLs for plain replayed commands, but
`EXEC` re-checks ACLs for every queued command. `kubernetes/infrastructure/redis/start-redis.sh` limits `default` to
`+ping +auth`, so every command queued in a replayed transaction is refused
with `NOPERM` and skipped. Upstream tracks this behavior in redis/redis#14156.

Observed on the local cluster (Redis 7.4, uptime about 6,000 s):

- Every `default`-user `ACL LOG` entry has context `multi`, `cmd=exec`,
  `fd=-1`, client id `18446744073709551615` (the AOF loader client), and an
  age equal to the Redis uptime.
- Denied counts: `hset` 990, `pexpireat` 685, `sadd` 33, `select` 1.
- `appendonly.aof.<n>.incr.aof` contained 578 `MULTI`/`EXEC` blocks.

These Session Gateway scripts make more than one write, so their writes are
lost:

- session creation (`create-session.lua`): `HSET`s, `PEXPIREAT`, `SADD`,
  `PEXPIREAT`;
- heartbeat and permission refresh (`conditional-update.lua`, when the
  session exists): `SADD`, `HSET`s, `PEXPIREAT`s;
- OAuth state creation (`RedisAuthorizationRequestRepository`): `HSET`,
  `PEXPIREAT`.

Bulk revocation (`delete-user-sessions.lua`) normally logs one `DEL`, which
replays fine. It is affected only when an indexed session key has expired but
Redis has not deleted it yet. `DEL` first runs lazy expiry on each key. That
expired key is deleted and the deletion is logged, which makes a second write.
Redis then wraps both deletions in `MULTI`/`EXEC`, and replay drops the
revocation. A stale index member whose key Redis has already deleted does not
trigger this, because there is no key to expire. Stale members are common,
since only logout removes them (see
`low-bulk-session-revocation-fails-on-large-index.md`). Expired keys that are
not yet deleted are less common. Redis's active expiry deletes them in the
background, but not promptly in every case.

Single-session logout uses top-level `UNLINK` and `SREM`. Currency-service
cache writes are also top-level. Both replay normally. The base RDB written at
the last AOF rewrite also loads normally.

### Reproduction

Reproduced on 2026-11-12 with the pinned `redis:7-alpine@sha256:858f009f…`
image and the unchanged `delete-user-sessions.lua`, in a container with no
network. The ACLs matched the cluster: an application user with full
permissions, and `default` limited to `+ping +auth`. Each case stored a live
session in the base RDB (`BGREWRITEAOF`), ran the bulk revocation, then
restarted Redis:

| Case | AOF representation | After restart |
| --- | --- | --- |
| All indexed sessions live | single `DEL` | Revocation holds |
| One expired key not yet deleted | `MULTI`/`EXEC` with the lazy-expiry deletion | Live session and index return; one `default` `ACL LOG` entry |
| One member whose key is already gone | single `DEL` | Revocation holds |

The second case disabled active expiry (`DEBUG SET-ACTIVE-EXPIRE 0`) to make
it deterministic. That shows the mechanism, not how often it happens in normal
operation.

## Impact

- **Lost sessions.** A Redis restart loses every session and pending login
  created since the last AOF rewrite, so those users must log in again. It
  fails closed. Only sessions present in the base RDB survive.
  `docs/architecture/security-architecture.md` (Redis, high availability and
  session management sections) records this limitation and links here.
- **Revoked sessions can come back.** This needs two conditions. The session
  is in the base RDB. And when a bulk revocation deletes it after the rewrite,
  the user's index holds a session key that has expired but is not yet
  deleted. On restart the deletion is dropped and the session is valid again. Its refresh writes were dropped too,
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
- A bulk revocation still holds after a Redis restart. Each test stores a live
  session in the base RDB (`BGREWRITEAOF`) before the revocation, then
  restarts Redis. Test three index states:
  - all indexed sessions live;
  - an indexed member whose key has expired but is still in memory;
  - an indexed member whose key is already gone.

  The second case needs `DEBUG SET-ACTIVE-EXPIRE 0` to be deterministic.
  `DEBUG` requires `--enable-debug-command`, so run that case in an isolated
  reproduction, not the live cluster.
- Logging in as `default` is refused, and the Redis probes still pass.
- `verify-credential-isolation.sh` asserts both behaviors.
- When the fix lands, `security-architecture.md` is updated to say Redis
  restarts preserve sessions again.
