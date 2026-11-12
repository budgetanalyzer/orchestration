# Bulk session revocation fails on a large session index

- **Severity:** Low (implementation review: P2; independent review: Low-Medium)
- **Owner:** session-gateway; permission-service for the error message
- **Status:** Open. The algorithm predates hardening (`55719f2` in
  session-gateway).
- **Source:** 2026-11-09 implementation review F3; independent implementation review C3

## Problem

`../session-gateway/src/main/resources/redis/delete-user-sessions.lua:5-14`
loads every member of the user's index and passes them all to one
`DEL` through `unpack`. Redis's embedded Lua has a finite argument stack.

The 2026-11-09 implementation review ran the unchanged script on the
manifest-pinned `redis:7-alpine` (7.4.11). Each case had one existing session
hash; the other index members stood for expired sessions. The container had
no network, mounts, published ports or credentials:

| Index members | Result |
| --- | --- |
| 100 | `2` keys deleted |
| 8,000 | `ERR ... too many results to unpack`; session and index remain |
| 10,000 | Same error |

These counts demonstrate the failure. 8,000 is not the smallest failing size.

Index members are removed only on logout. Expired sessions leave stale
members.

## Why Low

- The index TTL is the 900s sliding session TTL, extended with `EXPIRE GT`
  (`create-session.lua`, `conditional-update.lua`). The index expires 15
  minutes after the user's last activity on any session. Stale members build up only
  if activity never pauses for 15 minutes across about 8,000 logins. Normal use
  resets the index.
- Login initiation is rate limited per client (burst 25, 1/s;
  `kubernetes/istio/ingress-rate-limit.yaml:74-76`).
- permission-service commits the deactivation before revocation, and heartbeat
  rechecks account status. An existing session therefore lives at most one
  sliding TTL (15 minutes) after deactivation.

The concrete defects are:

- an admin deactivation that fails on every retry;
- the `503` message "retry is safe"
  (`../permission-service/src/main/java/org/budgetanalyzer/permission/service/UserService.java:180`),
  which is false in this case.

## Proposed fix

- Delete in bounded batches (about 1,000 keys) inside the same Lua script,
  then delete the index and return the total. This keeps atomicity with
  concurrent session creation.
- Correct the permission-service message, or make it accurate once batching
  lands.
- Skip pruning stale members (`SREM` on create): it makes every login cost grow with the
  index size and isn't needed once the delete is batched.

## Acceptance

- An index with at least 10,000 mostly stale members revokes all live
  sessions and removes the index.
- The existing concurrency and two-session lifetime tests still pass.
