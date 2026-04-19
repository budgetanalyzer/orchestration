# Plan: Redis Production Parity and Manifest Ownership

Date: 2026-04-19

Status: Draft

Related documents:

- `kubernetes/production/README.md`
- `deploy/README.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/plans/oracle-cloud-deployment-plan.md`
- `scripts/smoketest/verify-phase-5-runtime-hardening.sh`
- `scripts/guardrails/verify-production-image-overlay.sh`

## Problem Statement

Redis currently uses a different local/production shape than PostgreSQL and
RabbitMQ.

PostgreSQL and RabbitMQ use shared local infrastructure manifests with
PVC-backed `StatefulSet` storage. Redis uses:

- local development: `kubernetes/infrastructure/redis/deployment.yaml` with
  `/data` backed by `emptyDir`
- production: a separate checked-in path under
  `kubernetes/production/infrastructure/redis/` with a duplicated Deployment,
  Service, bootstrap script, and PVC

This creates two mismatches:

1. Production parity: local Redis writes AOF to disk, but the disk is ephemeral
   pod storage. Production writes AOF to PVC-backed storage.
2. Manifest ownership: Redis production storage is solved by duplicating the
   whole Redis manifest path, while PostgreSQL and RabbitMQ keep their storage
   contract in the shared infrastructure manifests.

The practical symptom is that local Redis session/cache data disappears when
the Redis pod is recreated, including during ordinary `tilt down` cleanup.
Production Redis data already survives pod recreation through its PVC.

## Goals

1. Make Redis local storage behavior match production by default.
2. Bring Redis manifest ownership closer to PostgreSQL and RabbitMQ without
   changing production runtime behavior.
3. Keep the "fresh Redis state" workflow explicit through an ops command or
   intentionally selected overlay, not an accidental side effect of pod deletion.
4. Preserve the existing Redis ACL, TLS-only transport, runtime hardening, and
   image-pinning contracts.
5. Avoid broad service-code changes. This is orchestration-owned manifest,
   verification, and documentation work.

## Non-Goals

- Changing Redis ACL users or key-prefix ownership.
- Adding Redis HA, clustering, Sentinel, or managed Redis.
- Changing browser session semantics in Session Gateway.
- Changing production backup strategy beyond documenting how this storage shape
  affects future backup/recovery work.
- Writing Java, TypeScript, or Go service logic in sibling repositories.

## Current Behavior

Redis starts with AOF enabled in both local and production:

```text
redis-server --appendonly yes --dir /data
```

The difference is the backing volume:

- local `/data`: `emptyDir`
- production `/data`: `PersistentVolumeClaim/redis-data`

Expected local lifecycle today:

- container restart in the same pod: Redis data can survive
- pod deletion/recreation: Redis data is lost
- `tilt down`: Redis data is lost because the Deployment pod is deleted
- `setup.sh` cluster recreation: Redis data is lost

Expected production lifecycle today:

- pod deletion/recreation: Redis data survives through `redis-data` PVC
- node or volume loss: data depends on the production host storage and future
  backup/recovery work

Production does not need a runtime storage fix. It already has the desired
PVC-backed Redis behavior. Any production work in this plan should be a manifest
ownership cleanup only, with rendered production behavior kept stable.

## Recommended Direction

Make the shared Redis baseline PVC-backed and production-ready, then reduce the
production Redis path to an overlay or kustomization that only owns true
production differences.

The preferred steady state:

```text
kubernetes/infrastructure/redis/
  deployment.yaml       # shared Redis Deployment
  service.yaml          # shared Redis Service
  pvc.yaml              # shared Redis data PVC
  start-redis.sh        # shared ACL/TLS bootstrap script
  kustomization.yaml    # optional shared kustomize entry point

kubernetes/production/infrastructure/redis/
  kustomization.yaml    # references shared base and patches production-only differences
```

If there are no production-only Redis differences after this change, the
production kustomization should still remain as a stable apply target for
operators, but it should not duplicate the Deployment, Service, or bootstrap
script.

## Design Choices

### Redis Workload Kind

Preferred first step: keep Redis as a single-replica `Deployment` and add a
named PVC.

Reasoning:

- It is the smallest behavior-preserving change.
- Production already uses a Deployment with a PVC.
- Redis remains a single-node cache/session store, not a stateful replicated
  database topology.

Possible later step: convert Redis to a `StatefulSet`.

That would align more closely with PostgreSQL and RabbitMQ, but it is a larger
change and not required to fix the immediate parity mismatch. If chosen later,
the plan should account for stable pod identity, volume claim template naming,
and migration from any existing `redis-data` PVC.

### Local Fresh-State Workflow

Do not rely on pod deletion for a clean Redis.

Use one explicit reset path:

- existing command: `./scripts/ops/flush-redis.sh`
- optional future command: `./scripts/ops/reset-local-redis.sh` that flushes
  Redis and, if needed, deletes the PVC after confirming intent

The default local experience should be:

- `tilt up`: reuses Redis data when the PVC still exists
- `tilt down`: stops Redis resources but should not be treated as a cache reset
- explicit flush/reset command: clears sessions and cache

There is no dev migration requirement. Existing local data is disposable. If a
developer wants a clean baseline after this change, they can recreate the local
cluster or delete local Docker/Kubernetes resources and rebuild everything.

### Tilt PVC Lifecycle

This needs one concrete verification during implementation.

Tilt's `down` command deletes resources specified in the Tiltfile. If the new
Redis PVC is included directly in `k8s_yaml(...)`, verify whether `tilt down`
deletes it in this repo's Tilt version and cluster setup.

If `tilt down` deletes the Redis PVC by default, choose one of these patterns:

1. Add `tilt.dev/down-policy: keep` to the local Redis PVC.
2. Manage the Redis PVC outside Tilt with a documented bootstrap/apply step.
3. Use a local kustomize/Tilt split where persistent storage has a separate
   lifecycle from the Redis Deployment and Service.

The preferred option is `tilt.dev/down-policy: keep` if it behaves cleanly and
does not complicate production rendering.

## Implementation Plan

### Phase 1: Establish Shared Redis Storage

1. Add `kubernetes/infrastructure/redis/pvc.yaml`.
2. Change `kubernetes/infrastructure/redis/deployment.yaml` so
   `redis-data` uses `persistentVolumeClaim.claimName: redis-data`.
3. Decide and apply the local PVC lifecycle rule after verifying Tilt behavior.
4. Update `Tiltfile` to include the Redis PVC or the selected kustomize entry
   point.
5. Keep `redis-tmp` as `emptyDir`; only Redis data should move to PVC-backed
   storage.

### Phase 2: Reduce Production Duplication

1. Replace the duplicated production Redis Deployment, Service, and bootstrap
   script with a production kustomization that references the shared Redis
   resources, only if this ownership cleanup is worth the extra review.
2. Keep `kubernetes/production/infrastructure/redis/kustomization.yaml` as the
   production apply target.
3. Keep production-specific patches only where a real production difference
   exists.
4. Ensure the production render still includes:
   - `ConfigMap/redis-acl-bootstrap`
   - `Deployment/redis`
   - `Service/redis`
   - `PersistentVolumeClaim/redis-data`
   - `redis-data` mounted at `/data`
   - Redis AOF enabled through the shared bootstrap script

### Phase 3: Verification Updates

1. Update `scripts/smoketest/verify-phase-5-runtime-hardening.sh` so Redis
   expects `redis-data` to be PVC-backed in local development.
2. Keep the `redis-tmp` assertion as `emptyDir`.
3. Update `scripts/guardrails/verify-production-image-overlay.sh` if production
   rendering paths or expected Redis snippets change.
4. Run static and live checks appropriate to the change:
   - `bash -n` and `shellcheck` for any modified shell scripts
   - `kubectl kustomize kubernetes/production/infrastructure/redis`
   - `./scripts/guardrails/verify-production-image-overlay.sh`
   - `./scripts/smoketest/verify-phase-5-runtime-hardening.sh` after `tilt up`
   - `./scripts/smoketest/verify-phase-7-security-guardrails.sh` if image or
     security guardrail surfaces are touched

### Phase 4: Documentation Updates

Update the nearest affected docs in the same change:

1. `kubernetes/production/README.md`: describe production Redis as using the
   shared PVC-backed Redis base plus a production apply target.
2. `deploy/README.md`: remove language that says production replaces the shared
   local-dev `emptyDir`; describe the current production apply target.
3. `docs/development/local-environment.md`: document that local Redis is
   PVC-backed by default and that `./scripts/ops/flush-redis.sh` clears sessions
   and cache.
4. `docs/runbooks/tilt-debugging.md`: clarify that `tilt down` is not the
   canonical Redis reset path after this change.
5. `docs/plans/oracle-cloud-deployment-plan.md`: remove or update the TODO that
   says local Redis still uses `emptyDir`.

## Rollout Notes

For local development, do not plan a data migration. Existing Redis data is
cache/session state and is disposable. The clean rollout is to rebuild the local
environment from scratch when needed.

For production, no storage migration is required by the parity fix because
production Redis is already PVC-backed. If the production manifest ownership
cleanup is implemented, keep the same PVC name, namespace, and mount path so
the rendered production behavior stays stable.

Before applying any production ownership cleanup, render the old and new
production Redis manifests and verify that the persistent volume claim identity
and Redis pod spec remain equivalent except for intentional metadata or
kustomize ownership changes:

```bash
kubectl kustomize kubernetes/production/infrastructure/redis
```

## Risks

- Old local sessions and cache entries can survive longer than developers
  expect. Mitigation: document and rely on the explicit Redis flush command.
- `tilt down` may delete a Tilt-managed PVC unless the lifecycle is handled
  explicitly. Mitigation: verify Tilt behavior before finalizing the manifest
  change.
- Reducing production duplication can accidentally change rendered production
  output even though no production runtime change is needed. Mitigation: compare
  rendered manifests and keep the production verifier strict. If the render
  cannot be kept stable, defer the production ownership cleanup.
- If Redis credentials or ACL bootstrap behavior drift, production and local
  session validation can fail. Mitigation: keep the bootstrap script shared and
  preserve existing ACL verification.

## Success Criteria

The work is complete when:

1. Local Redis `/data` is PVC-backed by default.
2. Production Redis still renders and applies through
   `kubernetes/production/infrastructure/redis`.
3. Production Redis runtime behavior is unchanged. If the ownership cleanup is
   implemented, production Redis no longer duplicates the shared Deployment,
   Service, and bootstrap script unless a specific production-only difference
   justifies it.
4. PostgreSQL, RabbitMQ, and Redis all have persistent local infrastructure data
   by default.
5. `tilt down` behavior is documented and no longer treated as the Redis reset
   contract.
6. The Redis reset path is explicit and documented.
7. Static guardrails and relevant live smoke tests pass.

## Open Decisions

1. Should Redis stay a Deployment with a named PVC, or should this cleanup also
   convert it to a StatefulSet?
2. Should local `tilt down` preserve Redis PVC data by default through
   `tilt.dev/down-policy: keep`?
3. Is a separate destructive reset command needed, or is the existing
   `./scripts/ops/flush-redis.sh` enough?
4. Should local Redis PVC size match production `5Gi`, or should local use a
   smaller request while production patches the size?
5. Should the production duplication cleanup be done now, or should this pass
   only fix local parity and leave the already-correct production apply path
   unchanged?

## Recommendation

Start with the conservative path:

1. Shared Redis Deployment plus shared `PersistentVolumeClaim/redis-data`.
2. Preserve Redis data across ordinary local pod restarts and `tilt down` if
   Tilt supports a clean PVC keep policy.
3. Keep `./scripts/ops/flush-redis.sh` as the canonical fresh-state command.
4. Treat production as behaviorally complete. Only collapse production Redis
   duplication into a shared-base kustomization if the rendered output remains
   stable and the ownership cleanup is worth reviewing.

This fixes the parity and ownership mismatch without turning the Redis cleanup
into a broader infrastructure redesign.
