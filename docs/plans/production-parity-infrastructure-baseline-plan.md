# Plan: Production-Parity Infrastructure Baseline

Date: 2026-04-19

Status: Draft

Related documents:

- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/plans/oracle-cloud-deployment-plan.md`
- `kubernetes/production/README.md`
- `deploy/README.md`
- `README.md`
- `AGENTS.md`
- `kubernetes/istio/cni-common-values.yaml`
- `kubernetes/istio/cni-kind-values.yaml`
- `kubernetes/istio/cni-k3s-values.yaml`
- `scripts/smoketest/verify-phase-5-runtime-hardening.sh`
- `scripts/guardrails/verify-production-image-overlay.sh`

## Problem Statement

The current local and production infrastructure shapes diverge in two places
that should be treated as baseline design issues, not one-off production fixes.

First, Redis is not shaped like the other stateful infrastructure services.
PostgreSQL and RabbitMQ use shared PVC-backed `StatefulSet` manifests. Redis
uses a local `Deployment` with `/data` backed by `emptyDir`, while production
uses a separate duplicated `Deployment`, `Service`, bootstrap script, and
standalone PVC under `kubernetes/production/infrastructure/redis/`.

Second, Istio CNI values are split between a Kind file and a production k3s
file without the normal common-baseline plus explicit-overlay structure. The
current comments intentionally deferred the cleaner structure to avoid touching
the already-verified OCI path.

That conservative posture is no longer the target. The forward pattern should
be:

1. Local development is the production-faithful baseline.
2. Production deployment overlays only true production values.
3. OCI scripts are idempotent and own the production transition commands.
4. Local validation starts from an empty Kubernetes and Docker runtime.

## Confirmed Decisions

1. This is a plan-only task. Implementation happens later.
2. Redis will become a shared single-replica `StatefulSet`, aligned with
   PostgreSQL and RabbitMQ.
3. Redis will use `volumeClaimTemplates` with the template name `redis-data`.
   The actual StatefulSet-created PVC name will be `redis-data-redis-0`.
4. Local Redis migration is not required. Local validation may assume a clean
   Kubernetes cluster and empty Docker runtime.
5. Production Redis migration will be a destructive reset. Existing production
   Redis session/cache data may be discarded.
6. The old production Redis `Deployment` and standalone PVC must be explicitly
   removed during OCI migration before the new `StatefulSet` becomes the
   production baseline.
7. Production infrastructure should move toward one broad apply/render target,
   `kubernetes/production/infrastructure`, instead of a Redis-only production
   path.
8. The Istio CNI files will use:
   - `kubernetes/istio/cni-common-values.yaml`
   - `kubernetes/istio/cni-kind-values.yaml`
   - `kubernetes/istio/cni-k3s-values.yaml`
9. The existing `kubernetes/istio/cni-values.yaml` production file will be
   renamed to `kubernetes/istio/cni-k3s-values.yaml`.
10. Verifier script changes are allowed only where the current verifier encodes
    the old Redis shape. Those required changes are called out explicitly in
    this plan.

## Goals

1. Make local Redis production-faithful by default.
2. Replace Redis `Deployment` plus ad hoc PVC handling with a shared
   `StatefulSet` and `volumeClaimTemplates`.
3. Remove duplicated production Redis manifests and make production reuse the
   shared infrastructure baseline.
4. Establish a broader production infrastructure target that can render and
   apply PostgreSQL, RabbitMQ, and Redis together.
5. Implement the full Istio CNI common-values plus Kind/k3s overlay pattern.
6. Provide idempotent OCI scripts for rendering, applying, and destructively
   migrating Redis to the new StatefulSet shape.
7. Preserve existing Redis TLS, ACL, image-pinning, and runtime-hardening
   contracts unless a change is explicitly required by the StatefulSet move.
8. Keep documentation synchronized with the new baseline.

## Non-Goals

- Adding Redis HA, Sentinel, clustering, or managed Redis.
- Preserving production Redis session/cache data.
- Changing PostgreSQL or RabbitMQ data ownership.
- Changing application service code in sibling repositories.
- Changing Auth0, browser session semantics, or ext_authz session validation.
- Changing OCI certificate generation or secret material handling.

## Prerequisites

1. **[Human]** Confirm production can tolerate Redis data loss during the
   destructive reset. This invalidates active sessions and clears Redis-backed
   cache data.
2. **[Human]** Confirm production PostgreSQL and RabbitMQ data are not part of
   this migration and must not be deleted.
3. **[Human]** Confirm the OCI cluster still has the Phase 5 secret and
   internal TLS baseline:
   - `redis-bootstrap-credentials`
   - `infra-ca`
   - `infra-tls-redis`
4. **[AI-Assistant]** Before implementation, re-check current manifests and
   verifier expectations. If Redis has gained durable business data or any
   new service depends on Redis persistence beyond sessions/cache, stop and
   replace the destructive reset with a data-preserving migration plan.

## Target Repository Shape

```text
kubernetes/istio/
  cni-common-values.yaml
  cni-kind-values.yaml
  cni-k3s-values.yaml

kubernetes/infrastructure/
  kustomization.yaml
  namespace.yaml
  postgresql/
    configmap.yaml
    service.yaml
    statefulset.yaml
  rabbitmq/
    configmap.yaml
    service.yaml
    statefulset.yaml
  redis/
    service.yaml
    start-redis.sh
    statefulset.yaml

kubernetes/production/infrastructure/
  kustomization.yaml
  patches/
    redis-storage.yaml
```

The old production Redis-only directory is removed:

```text
kubernetes/production/infrastructure/redis/
  deployment.yaml
  service.yaml
  pvc.yaml
  start-redis.sh
  kustomization.yaml
```

## Important Kustomize Constraint

The production infrastructure overlay needs to reuse the shared local baseline
under `kubernetes/infrastructure`. A direct `kubectl apply -k
kubernetes/production/infrastructure` may not be sufficient if Kustomize load
restrictions reject references outside the overlay directory.

The implementation should therefore make the repo-owned OCI scripts the
canonical production path:

```bash
kubectl kustomize kubernetes/production/infrastructure \
  --load-restrictor=LoadRestrictionsNone
```

then apply the rendered output with `kubectl apply -f -`.

This keeps the shared-baseline model without reintroducing duplicated
production Redis manifests.

## Phase 1: Istio CNI Values Baseline

**Status:** Implemented on 2026-04-19. Local Tilt now installs Istio CNI from
the common values plus the Kind overlay, and the OCI install script uses the
same common values plus the k3s overlay.

1. **[AI-Assistant]** Add `kubernetes/istio/cni-common-values.yaml` with the
   shared Istio CNI values:
   - `seccompProfile.type: RuntimeDefault`
2. **[AI-Assistant]** Rewrite `kubernetes/istio/cni-kind-values.yaml` as the
   explicit Kind/Calico overlay:
   - do not set `global.platform`
   - document that Kind uses the chart's standard CNI paths
3. **[AI-Assistant]** Rename `kubernetes/istio/cni-values.yaml` to
   `kubernetes/istio/cni-k3s-values.yaml`.
4. **[AI-Assistant]** Keep the k3s overlay production-specific:
   - `global.platform: k3s`
   - no duplicated common seccomp values
5. **[AI-Assistant]** Update local Tilt Istio CNI installation to pass values
   in this order:
   - `kubernetes/istio/cni-common-values.yaml`
   - `kubernetes/istio/cni-kind-values.yaml`
6. **[AI-Assistant]** Update OCI Istio installation scripts to pass values in
   this order:
   - `kubernetes/istio/cni-common-values.yaml`
   - `kubernetes/istio/cni-k3s-values.yaml`
7. **[AI-Assistant]** Update script dependencies and documentation references
   from `cni-values.yaml` to `cni-k3s-values.yaml`.
8. **[AI-Assistant]** Validate the script edits:
   - `bash -n deploy/scripts/04-install-istio.sh`
   - `shellcheck deploy/scripts/04-install-istio.sh`

## Phase 2: Shared Redis StatefulSet Baseline

**Status:** Implemented on 2026-04-19. Local Redis now uses the shared
infrastructure kustomization and a single-replica `StatefulSet` with the
`redis-data` claim template. The local runtime verifiers that directly encoded
the old Redis `Deployment` or `emptyDir` shape were updated with this phase.
The production overlay, production migration scripts, and production render
guardrail updates remain later phases in this plan.

1. **[AI-Assistant]** Replace
   `kubernetes/infrastructure/redis/deployment.yaml` with
   `kubernetes/infrastructure/redis/statefulset.yaml`.
2. **[AI-Assistant]** Define `StatefulSet/redis` with:
   - `metadata.name: redis`
   - `namespace: infrastructure`
   - `serviceName: redis`
   - `replicas: 1`
   - selector and pod labels `app: redis`
   - the current Redis image digest
   - the current TLS-only startup command
   - the current ACL environment variables
   - the current Redis liveness and readiness probes
3. **[AI-Assistant]** Move Redis data storage to a StatefulSet claim template:
   - `volumeClaimTemplates[0].metadata.name: redis-data`
   - local baseline request: `1Gi`
   - actual local PVC name after creation: `redis-data-redis-0`
4. **[AI-Assistant]** Keep `redis-tmp` as `emptyDir`.
5. **[AI-Assistant]** Add pod filesystem ownership needed for PVC-backed
   Redis writes:
   - preserve `runAsUser: 999`
   - preserve `runAsGroup: 1000`
   - add `fsGroup: 1000`
   - add `fsGroupChangePolicy: OnRootMismatch`
6. **[AI-Assistant]** Preserve the existing security baseline:
   - `automountServiceAccountToken: false`
   - `allowPrivilegeEscalation: false`
   - dropped capabilities
   - `readOnlyRootFilesystem: true`
   - `runAsNonRoot: true`
   - `seccompProfile.type: RuntimeDefault`
7. **[AI-Assistant]** Add or update
   `kubernetes/infrastructure/kustomization.yaml` so the shared baseline
   includes namespace, PostgreSQL, RabbitMQ, and Redis. Keep the Redis
   `ConfigMap/redis-acl-bootstrap` generator here instead of adding a nested
   Redis kustomization:
   - include `redis/statefulset.yaml`
   - include `redis/service.yaml`
   - generate `ConfigMap/redis-acl-bootstrap` from `redis/start-redis.sh`
   - set `generatorOptions.disableNameSuffixHash: true`
8. **[AI-Assistant]** Update `Tiltfile` to load Redis from the shared
   infrastructure kustomization instead of creating the Redis ConfigMap
   separately and loading a Deployment.
9. **[AI-Assistant]** Update resource references from Redis Deployment to
   Redis StatefulSet where the repo keeps static inventories:
   - `scripts/lib/phase-7-image-pinning-targets.txt`
   - dependency notification docs
   - local environment docs

## Phase 3: Production Infrastructure Overlay

1. **[AI-Assistant]** Add
   `kubernetes/production/infrastructure/kustomization.yaml`.
2. **[AI-Assistant]** Make the production target reuse the shared
   infrastructure baseline instead of duplicating Redis manifests.
3. **[AI-Assistant]** Add a production Redis storage patch under
   `kubernetes/production/infrastructure/patches/redis-storage.yaml`:
   - target `StatefulSet/redis`
   - replace Redis `volumeClaimTemplates` storage request with `5Gi`
4. **[AI-Assistant]** Delete the old Redis-only production path:
   - `kubernetes/production/infrastructure/redis/deployment.yaml`
   - `kubernetes/production/infrastructure/redis/service.yaml`
   - `kubernetes/production/infrastructure/redis/pvc.yaml`
   - `kubernetes/production/infrastructure/redis/start-redis.sh`
   - `kubernetes/production/infrastructure/redis/kustomization.yaml`
5. **[AI-Assistant]** Update production documentation so the canonical
   infrastructure render/apply target is `kubernetes/production/infrastructure`
   through repo-owned scripts, not the old Redis-only overlay.
6. **[AI-Assistant]** Confirm the rendered production infrastructure output
   contains:
   - `Namespace/infrastructure`
   - `StatefulSet/postgresql`
   - `StatefulSet/rabbitmq`
   - `StatefulSet/redis`
   - `Service/postgresql`
   - `Service/rabbitmq`
   - `Service/redis`
   - `ConfigMap/postgresql-init`
   - `ConfigMap/rabbitmq-config`
   - `ConfigMap/redis-acl-bootstrap`
   - Redis `volumeClaimTemplates.metadata.name: redis-data`
   - Redis storage request `5Gi`

## Phase 4: Idempotent OCI Scripts

1. **[AI-Assistant]** Add
   `deploy/scripts/17-render-production-infrastructure.sh`.
2. **[AI-Assistant]** The render script must:
   - load the repo-local deploy common library
   - require `kubectl`
   - render `kubernetes/production/infrastructure` with
     `--load-restrictor=LoadRestrictionsNone`
   - write output under a deterministic temp/review location, such as
     `tmp/production-infrastructure/infrastructure.yaml`
   - be safe to rerun
3. **[AI-Assistant]** Add
   `deploy/scripts/18-apply-production-infrastructure.sh`.
4. **[AI-Assistant]** The apply script must:
   - call the render script
   - apply the rendered infrastructure manifest
   - wait for PostgreSQL, RabbitMQ, and Redis StatefulSets when present
   - be safe to rerun against an already-converged cluster
5. **[AI-Assistant]** Add
   `deploy/scripts/19-migrate-production-redis-statefulset.sh`.
6. **[AI-Assistant]** The Redis migration script must require an explicit
   destructive flag, for example:
   ```bash
   ./deploy/scripts/19-migrate-production-redis-statefulset.sh --confirm-destroy-redis
   ```
7. **[AI-Assistant]** The Redis migration script must be idempotent:
   - if old `Deployment/redis` exists, scale it to zero and delete it
   - if old standalone `PersistentVolumeClaim/redis-data` exists, delete it
   - if either resource is already absent, continue
   - apply the new broad production infrastructure target
   - wait for `StatefulSet/redis`
   - verify `redis-0` answers `PING` over TLS
   - optionally restart Redis clients to force clean connections:
     `session-gateway`, `ext-authz`, and `currency-service`
8. **[AI-Assistant]** The script must not delete PostgreSQL or RabbitMQ
   resources.
9. **[AI-Assistant]** The script must not generate certificates or write
   secret values.
10. **[AI-Assistant]** Validate all new or modified shell scripts:
    - `bash -n deploy/scripts/17-render-production-infrastructure.sh`
    - `bash -n deploy/scripts/18-apply-production-infrastructure.sh`
    - `bash -n deploy/scripts/19-migrate-production-redis-statefulset.sh`
    - `shellcheck deploy/scripts/17-render-production-infrastructure.sh`
    - `shellcheck deploy/scripts/18-apply-production-infrastructure.sh`
    - `shellcheck deploy/scripts/19-migrate-production-redis-statefulset.sh`

## Phase 5: Required Verifier Updates

Verifier changes are not optional here because the existing checks encode the
old Redis `Deployment` plus standalone PVC shape.

1. **[AI-Assistant]** Update
   `scripts/smoketest/verify-phase-5-runtime-hardening.sh`.
2. **[AI-Assistant]** Required Phase 5 verifier changes:
   - stop asserting `redis-data` is an `emptyDir`
   - keep asserting `redis-tmp` is an `emptyDir`
   - assert Redis `/data` is backed by a PVC
   - accept the StatefulSet-created claim name `redis-data-redis-0`
   - keep existing Redis TLS, ACL, non-root, and read-only-root checks
3. **[AI-Assistant]** Update
   `scripts/guardrails/verify-production-image-overlay.sh`.
4. **[AI-Assistant]** Required production guardrail changes:
   - render `kubernetes/production/infrastructure` instead of
     `kubernetes/production/infrastructure/redis`
   - assert production Redis is `StatefulSet/redis`
   - assert Redis uses `volumeClaimTemplates.metadata.name: redis-data`
   - assert production Redis requests `storage: 5Gi`
   - remove the old assertion for `claimName: redis-data`
   - continue checking for forbidden mutable images, localhost hosts, and
     production route regressions
5. **[AI-Assistant]** Validate any modified verifier scripts:
   - `bash -n scripts/smoketest/verify-phase-5-runtime-hardening.sh`
   - `shellcheck scripts/smoketest/verify-phase-5-runtime-hardening.sh`
   - `bash -n scripts/guardrails/verify-production-image-overlay.sh`
   - `shellcheck scripts/guardrails/verify-production-image-overlay.sh`
6. **[AI-Assistant]** Do not change other verifier scripts unless
   implementation proves another old Redis Deployment assumption. If that
   happens, stop and document the additional verifier change explicitly.

## Phase 6: Documentation Updates

1. **[AI-Assistant]** Update `docs/development/local-environment.md`:
   - local Istio CNI now uses common values plus the Kind overlay
   - Redis is a `StatefulSet`, not a `Deployment`
   - Redis `/data` is PVC-backed locally by default
   - local clean-state development assumes cluster/runtime destruction or the
     explicit Redis flush command, not accidental pod deletion
2. **[AI-Assistant]** Update `docs/runbooks/tilt-debugging.md`:
   - Redis pod name is `redis-0`
   - Redis data is PVC-backed
   - `tilt down` is not the Redis reset contract
3. **[AI-Assistant]** Update `kubernetes/production/README.md`:
   - production infrastructure applies through the broad infrastructure script
   - Redis is no longer a duplicated production-only overlay
   - Redis production reset is destructive for sessions/cache
4. **[AI-Assistant]** Update `deploy/README.md`:
   - replace `kubectl apply -k kubernetes/production/infrastructure/redis`
     with the new production infrastructure scripts
   - document the destructive Redis StatefulSet migration command
   - document expected rerun behavior
5. **[AI-Assistant]** Update `README.md` and `AGENTS.md` references:
   - CNI common plus Kind/k3s overlays
   - Redis StatefulSet baseline where relevant
6. **[AI-Assistant]** Update `docs/plans/oracle-cloud-deployment-plan.md`:
   - mark the old Redis production-only overlay as superseded
   - point future OCI rebuilds to the broad production infrastructure target
   - record that existing production Redis migration is destructive

## Phase 7: Local Validation From Empty Runtime

1. **[Human]** Destroy local Kubernetes and Docker runtime state as desired.
   The plan does not require preserving local Redis data.
2. **[Human]** Run local setup from the host if certificates need to be
   generated. AI agents must not run SSL certificate generation commands.
3. **[Human or AI-Assistant]** Start the local stack:
   ```bash
   tilt up
   ```
4. **[AI-Assistant]** Verify the local infrastructure shape:
   ```bash
   kubectl get statefulset -n infrastructure
   kubectl get pod -n infrastructure redis-0
   kubectl get pvc -n infrastructure redis-data-redis-0
   kubectl describe pod -n infrastructure redis-0
   ```
5. **[AI-Assistant]** Verify Redis over TLS from the Redis pod:
   ```bash
   kubectl exec -n infrastructure redis-0 -- \
     redis-cli --tls --cacert /tls-ca/ca.crt ping
   ```
6. **[AI-Assistant]** Run the local smoke pass:
   ```bash
   ./scripts/smoketest/smoketest.sh
   ```
7. **[AI-Assistant]** If the smoke pass requires any verifier changes beyond
   Phase 5, stop and call them out before changing more scripts.

## Phase 8: OCI Validation

1. **[Human]** Pull or otherwise place the reviewed implementation on the OCI
   host.
2. **[Human]** Review the rendered production infrastructure:
   ```bash
   ./deploy/scripts/17-render-production-infrastructure.sh
   sed -n '1,260p' tmp/production-infrastructure/infrastructure.yaml
   ```
3. **[Human]** Reinstall or upgrade Istio CNI with the new common plus k3s
   values path:
   ```bash
   ./deploy/scripts/04-install-istio.sh
   ```
4. **[Human]** Verify CNI convergence:
   ```bash
   kubectl rollout status daemonset/istio-cni-node -n istio-system --timeout=180s
   kubectl get daemonset istio-cni-node -n istio-system
   ```
5. **[Human]** Run the destructive Redis StatefulSet migration:
   ```bash
   ./deploy/scripts/19-migrate-production-redis-statefulset.sh --confirm-destroy-redis
   ```
6. **[Human]** Verify production infrastructure shape:
   ```bash
   kubectl get statefulset -n infrastructure
   kubectl get pod -n infrastructure redis-0
   kubectl get pvc -n infrastructure redis-data-redis-0
   kubectl get deployment -n infrastructure redis
   kubectl get pvc -n infrastructure redis-data
   ```
   Expected result:
   - `StatefulSet/redis` exists
   - `Pod/redis-0` is ready
   - `PersistentVolumeClaim/redis-data-redis-0` exists
   - old `Deployment/redis` is absent
   - old standalone `PersistentVolumeClaim/redis-data` is absent
7. **[Human]** Run production render guardrails:
   ```bash
   ./scripts/guardrails/verify-production-image-overlay.sh
   ```
8. **[Human]** Run the relevant live production smoke checks already used for
   OCI validation. Do not edit smoke scripts on the OCI host.

## Success Criteria

1. Local Kind CNI installs from common values plus Kind overlay.
2. OCI k3s CNI installs from common values plus k3s overlay.
3. Redis is a shared `StatefulSet` in the local baseline.
4. Redis local and production data paths are both PVC-backed.
5. Production Redis no longer has duplicated production-only Deployment,
   Service, PVC, or bootstrap-script manifests.
6. Production infrastructure renders from one broad infrastructure target.
7. OCI Redis migration is idempotent and destructively removes the old
   Deployment/PVC before applying the new StatefulSet.
8. The required verifier changes are limited to old Redis-shape assumptions.
9. A clean local `tilt up` followed by `./scripts/smoketest/smoketest.sh`
   passes.
10. OCI CNI, infrastructure, and production guardrail checks pass after one
    planned migration run.

## Rollback Notes

Redis rollback is destructive in both directions because the chosen production
migration deletes the old standalone Redis PVC. If rollback is needed after the
new StatefulSet is applied:

1. **[Human]** Accept that Redis session/cache data may be lost again.
2. **[Human]** Delete `StatefulSet/redis` and
   `PersistentVolumeClaim/redis-data-redis-0`.
3. **[Human]** Reapply the last known good production Redis manifests from the
   previous git revision.
4. **[Human]** Restart Redis clients if they do not reconnect cleanly.

PostgreSQL and RabbitMQ rollback must not delete their PVCs.

## Open Items For Implementation Review

1. Confirm whether direct `kubectl apply -k kubernetes/production/infrastructure`
   is possible after implementation. If not, keep the repo-owned render/apply
   scripts as the only documented production path.
2. Confirm whether Redis client deployments need an explicit restart after the
   destructive Redis replacement or whether reconnect behavior is sufficient.
   The migration script should prefer deterministic client restarts unless
   testing proves they are unnecessary.
3. Confirm the Redis PVC group ownership on both Kind and k3s. If `fsGroup:
   1000` is not sufficient on either runtime, stop and fix the ownership
   contract in the Redis StatefulSet rather than weakening container security.
