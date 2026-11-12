# Unused HMSET grant on the Session Gateway Redis ACL

- **Severity:** Low
- **Owner:** orchestration
- **Status:** Open
- **Source:** 2026-11-09 independent implementation review C8

## Problem

The Session Gateway ACL grants `+hmset`
(`kubernetes/infrastructure/redis/start-redis.sh:9`). No Session Gateway code
issues it:

- session and OAuth-state writes are `HSET` inside Lua (`create-session.lua`,
  `conditional-update.lua`, `RedisAuthorizationRequestRepository.java:81`);
- reads use `opsForHash().get` / `.entries` (`HGET` / `HGETALL`);
- no `opsForHash().putAll`, which would issue `HMSET`.

`scripts/smoketest/verify-credential-isolation.sh:551` asserts that `HMSET`
on `oauth2:state:*` succeeds, which locks the unused grant in.

## Proposed fix

- Remove `+hmset` from the Session Gateway ACL.
- Change the credential-isolation assertion to expect `HMSET` to be denied.

## Acceptance

- Login, callback, heartbeat, logout and bulk revocation pass with the grant
  removed.
- The credential-isolation verifier asserts `NOPERM` for `HMSET`.
