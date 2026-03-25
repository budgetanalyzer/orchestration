# Phase 5 Verification and Suggested Improvements

## Context

Post-implementation audit of Security Hardening v2 Phase 5 (Runtime Hardening and Pod Security). The implementation plan (`docs/plans/security-hardening-v2-phase-5-implementation.md`) defines 10 sessions covering Istio CNI, workload hardening, gateway hardening, infrastructure hardening, namespace PSA enforcement, and an original 166-check verification gate. That baseline passed `166/166` on March 25, 2026. The current working tree applies the three follow-up improvements below, expands the gate by 9 assertions, and the expanded verifier passed `175/175` on March 25, 2026.

This review verified every manifest, the Tiltfile wiring, the verification script, and the documentation against the plan's target state and session-level requirements.

## Verification Result

**Phase 5 is correctly implemented.** All 10 sessions match the implementation plan. No correctness errors found.

**Status update:** the three follow-up improvements below are now implemented in-repo, and the expanded Phase 5 gate reran successfully at `175/175` on March 25, 2026.

Verified against the plan's target state:
- `istio-system` enforces PSA `privileged` — Tiltfile labels + verifier check
- `default`, `istio-ingress`, `istio-egress` enforce PSA `restricted` — namespace manifests + Tiltfile labels
- `infrastructure` enforces PSA `baseline` — namespace manifest + Tiltfile labels
- Meshed pods no longer contain `istio-init` — CNI installed, reinjection resource exists
- Workloads disable K8s API token automount (with documented gateway exceptions)
- All compatible workloads set seccomp, drop ALL caps, allowPrivilegeEscalation=false, runAsNonRoot=true
- `readOnlyRootFilesystem: true` enabled everywhere validated; `budget-analyzer-web` intentionally deferred
- Verifier passes with regression reruns for Phases 1–4

## Suggested Improvements (Implemented in Current Working Tree)

### 1. PostgreSQL init container: add `readOnlyRootFilesystem: true`

**File**: `kubernetes/infrastructure/postgresql/statefulset.yaml`

The `fix-tls-perms` init container copies TLS material from a read-only secret mount (`/tls-source`) to a writable emptyDir (`/tls`). It never writes to the root filesystem. But it is the only init container in the repo that omits `readOnlyRootFilesystem: true`.

Compare with the `init-tmp` busybox containers on Spring Boot services — those all set `readOnlyRootFilesystem: true` despite also only writing to mounted volumes.

**Change**: Add `readOnlyRootFilesystem: true` to the `fix-tls-perms` init container security context.

```yaml
# Current (lines 38-46):
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            runAsGroup: 70
            runAsNonRoot: true
            runAsUser: 70
            seccompProfile:
              type: RuntimeDefault

# Add readOnlyRootFilesystem: true (after capabilities block)
```

**Risk**: Low. The container's only writes are to `/tls` (emptyDir mount) and `/tls-source` (read-only mount prevents writes). The root filesystem is never touched, but the bootstrap path still needs a restarted pod to prove it on the live cluster.

### 2. `budget-analyzer-web`: pin explicit `runAsUser`/`runAsGroup` in manifest

**File**: `kubernetes/services/budget-analyzer-web/deployment.yaml`

Every other workload in the repo pins explicit UID/GID in the Kubernetes manifest:
- Spring Boot services: `1001`/`1001`
- ext-authz: `65532`/`65532`
- nginx-gateway: `101`/`101`
- redis: `999`/`1000`
- postgresql: `70`/`70`
- rabbitmq: `999`/`999`

`budget-analyzer-web` sets `runAsNonRoot: true` but relies entirely on the Docker image's USER directive for the actual UID/GID. The Session 2 plan explicitly added UID/GID pinning for Spring Boot services with the rationale "so the runtime does not rely on image metadata alone." That same reasoning applies here now that the sibling Docker image is confirmed running as UID/GID 1001.

**Change**: Add `runAsUser: 1001` and `runAsGroup: 1001` to the container security context.

```yaml
# Current (lines 36-40):
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
          runAsNonRoot: true

# Add:
          runAsUser: 1001
          runAsGroup: 1001
```

**Risk**: Low. The image already runs as UID 1001. This just prevents manifest/image drift.

### 3. Verifier: add `budget-analyzer-web` runtime specifics section

**File**: `scripts/dev/verify-phase-5-runtime-hardening.sh`

Every infrastructure and gateway workload has a dedicated `verify_*_runtime()` function that checks UID/GID and mount contracts. `budget-analyzer-web` only gets the generic `verify_workload` checks. If improvement #2 is applied, the verifier should also assert the pinned UID/GID.

**Change**: Add a `verify_budget_analyzer_web_runtime()` function that checks `assert_container_user_group` for `1001`/`1001`. Also extend `verify_postgresql_runtime()` so recommendation #1 is enforced by asserting the `fix-tls-perms` init-container baseline (`runAsNonRoot`, `allowPrivilegeEscalation=false`, `capabilities.drop=["ALL"]`, `readOnlyRootFilesystem=true`, `seccompProfile.type=RuntimeDefault`, and UID/GID `70`).

**Risk**: None. Additive verifier check.

## Files to Modify

| File | Change |
|------|--------|
| `kubernetes/infrastructure/postgresql/statefulset.yaml` | Add `readOnlyRootFilesystem: true` to `fix-tls-perms` init container |
| `kubernetes/services/budget-analyzer-web/deployment.yaml` | Add `runAsUser: 1001`, `runAsGroup: 1001` to container security context |
| `scripts/dev/verify-phase-5-runtime-hardening.sh` | Add `verify_budget_analyzer_web_runtime()` and PostgreSQL init-container assertions |

## Verification

1. `kubectl apply --dry-run=server` the modified manifests against the live cluster
2. Ensure the current cluster can start the refreshed `budget-analyzer-web` pod template by rebuilding/loading the local frontend image through the normal dev workflow if it is not already present
3. Run `./scripts/dev/verify-phase-5-runtime-hardening.sh --regression-timeout 8m` — expect all checks to pass (count increases from the historical `166` baseline to `175`)
