# Phase 5: Runtime Hardening and Pod Security - Implementation Plan

## Context

Phase 5 cannot start with Pod Security `enforce` labels. The current mesh still injects `istio-init` into sidecar workloads, and that init container is incompatible with Pod Security `restricted`.

Observed in the live Kind cluster on March 24, 2026:

- A secure test pod in a temporary namespace labeled `istio-injection=enabled` and `pod-security.kubernetes.io/enforce=restricted` is rejected because injected `istio-init` still requests `NET_ADMIN` / `NET_RAW`, runs as UID `0`, and neither the pod nor `istio-proxy` set `seccompProfile`.
- All repo-managed application Deployments in `default` still omit `automountServiceAccountToken: false` and pod/container `securityContext` hardening.
- The current runtime user split is already uneven:
  - `session-gateway`, `currency-service`, `transaction-service`, and `permission-service` run as UID `1001`
  - `ext-authz` uses a distroless non-root image
  - `budget-analyzer-web`, `nginx-gateway`, `redis`, `postgresql`, and `rabbitmq` still run as UID `0`
- Default-namespace workloads currently mount the Kubernetes API token volume (`kube-api-access-*`) because neither the pod specs nor the ServiceAccounts disable token automount.

This phase therefore starts with an Istio prerequisite, then hardens workloads in risk order.

Relevant upstream guidance:

- Istio CNI removes the need for privileged `istio-init` in sidecar mode: <https://istio.io/latest/docs/setup/additional-setup/cni/>
- Istio with Pod Security Admission requires Istio CNI if meshed namespaces are going to enforce `baseline` or `restricted`: <https://istio.io/latest/docs/setup/additional-setup/pod-security-admission/>
- Newer Istio releases can harden Gateway API auto-provisioned gateway resources declaratively through `spec.infrastructure.parametersRef`: <https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/>
- The repo now targets Istio `1.29.1`, so Session 3 uses Gateway `spec.infrastructure.parametersRef` for ingress hardening and fixed NodePort ownership. The egress gateway also returns to direct Helm install because `istio/gateway` `1.29.1` accepts `service.type=ClusterIP` under the repo's Helm `v3.20.1` toolchain.

Sequence update for March 25, 2026:

- The repo-side work from [istio-1.29-upgrade.md](./istio-1.29-upgrade.md) is implemented: Istio pins are `1.29.1` and Gateway API CRDs are `v1.4.0`.
- Complete the fresh-cluster regression gate from that plan before starting Session 4.
- Revalidate Session 3's ingress and egress gateway hardening approach on the upgraded Istio baseline before resuming the remaining Phase 5 sessions.

## Target State

Phase 5 is complete when all of the following are true:

- `istio-system` enforces Pod Security `privileged` because the `istio-cni` DaemonSet runs there
- `default`, `istio-ingress`, and `istio-egress` enforce Pod Security `restricted`
- `infrastructure` enforces Pod Security `baseline`
- Meshed application pods no longer contain `istio-init`
- Repo-managed workloads disable Kubernetes API token automount unless they have a concrete Kubernetes API dependency
- Compatible workloads set:
  - pod `securityContext.seccompProfile.type: RuntimeDefault`
  - container `allowPrivilegeEscalation: false`
  - container `capabilities.drop: ["ALL"]`
  - `runAsNonRoot: true`
- `readOnlyRootFilesystem: true` is enabled where runtime validation proves it is safe
- `./scripts/dev/verify-phase-5-runtime-hardening.sh` passes

## Compatibility Matrix

| Workload group | Current runtime posture | Baseline target | `readOnlyRootFilesystem` target | Notes |
| --- | --- | --- | --- | --- |
| Spring Boot services (`session-gateway`, `currency-service`, `transaction-service`, `permission-service`) | Already run as UID `1001` | Manifest-only hardening in this repo | Yes | Add `/tmp` `emptyDir` before flipping read-only |
| `ext-authz` | Distroless non-root | Manifest-only hardening in this repo | Yes | Low-risk first candidate |
| `budget-analyzer-web` | Sibling Docker runtime now runs as UID/GID `1001`, and the Deployment now pins `runAsUser`/`runAsGroup` to `1001` | Orchestration manifest hardening is implemented | Deferred until HMR writable-path validation is proven | `readOnlyRootFilesystem` remains intentionally off until the dev workflow is validated on narrow writable mounts |
| `nginx-gateway` | Pinned unprivileged image, explicit `/tmp` runtime mount, read-only root filesystem | Implemented in this repo | Yes | Logs now go to stdout/stderr and temp/pid paths are moved under `/tmp` |
| `istio-ingress` generated gateway | Non-root proxy container, pod seccomp and fixed NodePort now configured declaratively | Gateway `parametersRef` customization | Already effectively yes | Retains SA token mount because the gateway watches TLS secrets; do not use ad-hoc `kubectl patch` as source of truth |
| `istio-egress` gateway | Non-root proxy container, pod seccomp now applied through Helm values | Helm values hardening in this repo | Already yes | Currently keeps the chart-managed token behavior because this repo does not add a separate post-render patch just to remove it |
| `redis` | Runs as UID `999` / GID `1000` with explicit `/tmp` and `/data` writable mounts | Implemented in this repo | Yes | AOF remains intentionally ephemeral on `emptyDir` in local dev unless a PVC-backed path is introduced |
| `postgresql` | Runs as UID/GID `70` with explicit writable mounts for `/tmp` and `/var/run/postgresql` | Implemented in this repo | Yes | TLS-prep init container also runs as UID/GID `70`, uses `readOnlyRootFilesystem: true`, and copies the mounted secret material into `/tls` |
| `rabbitmq` | Runs as UID/GID `999` with `fsGroup: 999` and a PVC-backed data mount | Implemented in this repo | Yes | Config, definitions, and TLS mounts remain read-only while `/var/lib/rabbitmq` stays writable |

## Session Breakdown

Each session below is scoped so it can be finished, validated, and documented in a single working session.

### Session 1: Replace `istio-init` with Istio CNI

**Goal**

Remove the hard blocker that prevents meshed workloads from being admitted under Pod Security `restricted`.

Current implementation status for March 25, 2026:

- Session 1 is implemented in-repo.
- Tilt now installs `istio/cni`, enables `pilot.cni.enabled=true` for `istiod`, labels `istio-system` for PSA `privileged`, and includes an idempotent reinjection step for `default` namespace deployments that still carry `istio-init`.

**Files**

- `Tiltfile`
- `kubernetes/istio/istiod-values.yaml`
- `kubernetes/istio/cni-values.yaml` (new)

**Changes**

- Install the `istio/cni` chart in `istio-system`
- Set `pilot.cni.enabled=true` for the `istiod` install
- Add an explicit `kubernetes/istio/cni-values.yaml` instead of baking CNI knobs into long inline Helm commands
- Set `seccompProfile.type: RuntimeDefault` on the `istio-cni` DaemonSet through chart values
- Label `istio-system` for PSA `enforce=privileged` through the existing Tiltfile namespace-label resource because the namespace is created by Helm, not by a checked-in namespace manifest
- Restart or roll the meshed workloads in `default` so they are reinjected without `istio-init`
- Leave `cniConfFileName` unset unless node inspection proves auto-detection picks the wrong Calico config file

**Verification**

- `kubectl rollout status daemonset/istio-cni-node -n istio-system --timeout=120s`
- Create a temporary namespace with `istio-injection=enabled` and `pod-security.kubernetes.io/enforce=restricted`
- Apply a secure smoke pod and verify it starts
- Confirm new `default` namespace pods do not list `istio-init` in `.spec.initContainers[*].name`
- Re-run [`verify-phase-3-istio-ingress.sh`](/workspace/orchestration/scripts/dev/verify-phase-3-istio-ingress.sh)

**Stop if**

- Traffic redirection breaks
- The CNI repair loop leaves pods unredirected
- Meshed secure smoke pods are still rejected by PSA

### Session 2: Harden Non-Root Application Workloads

**Goal**

Land the low-risk hardening on workloads that are already built to run non-root.

Current implementation status for March 25, 2026:

- Session 2 is implemented in-repo for `session-gateway`, `currency-service`, `transaction-service`, `permission-service`, and `ext-authz`.
- The Spring Boot services now mount an explicit `/tmp` `emptyDir`, seed Tilt's `/tmp/.restart-proc` marker through a hardened init container, pin UID/GID `1001` in the manifest, and run with `readOnlyRootFilesystem: true`.
- `ext-authz` now disables service-account token automount and runs with pod seccomp, a read-only root filesystem, and explicit UID/GID `65532`.

**Files**

- `kubernetes/services/session-gateway/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`
- `kubernetes/services/transaction-service/deployment.yaml`
- `kubernetes/services/permission-service/deployment.yaml`
- `kubernetes/services/ext-authz/deployment.yaml`
- `kubernetes/services/session-gateway/serviceaccount.yaml`
- `kubernetes/services/currency-service/serviceaccount.yaml`
- `kubernetes/services/transaction-service/serviceaccount.yaml`
- `kubernetes/services/permission-service/serviceaccount.yaml`
- `kubernetes/services/ext-authz/serviceaccount.yaml`

**Changes**

- Set `automountServiceAccountToken: false` on the pod templates
- Set `automountServiceAccountToken: false` on the checked-in ServiceAccounts
- Add pod-level `securityContext.seccompProfile.type: RuntimeDefault`
- Add container security context:
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: ["ALL"]`
  - `runAsNonRoot: true`
- For the Spring Boot services, set explicit `runAsUser: 1001` and `runAsGroup: 1001` so the runtime does not rely on image metadata alone
- Add `/tmp` `emptyDir` mounts for the Spring Boot services, then validate and enable `readOnlyRootFilesystem: true`
- Enable `readOnlyRootFilesystem: true` on `ext-authz`

**Verification**

- Each workload restarts cleanly and stays Ready
- No checked workload pod contains `kube-api-access-*`
- `kubectl get pod ... -o jsonpath='{.spec.automountServiceAccountToken}'` returns `false`
- `kubectl get pod ... -o jsonpath='{.spec.securityContext.seccompProfile.type}'` returns `RuntimeDefault`
- [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh) still passes

### Session 3: Harden Ingress and Egress Gateways

**Goal**

Make both gateway namespaces compatible with Pod Security `restricted` without introducing controller or chart drift. Ingress still needs Kubernetes API token access for TLS secret watching, while egress currently keeps the chart-managed token behavior.

Current implementation status for March 25, 2026:

- Session 3 is implemented in-repo.
- The auto-provisioned Istio ingress gateway now uses Gateway `spec.infrastructure.parametersRef` to set pod `seccompProfile.type: RuntimeDefault`, keep service-account token automount explicit, and pin the HTTPS NodePort to `30443`.
- The Istio egress gateway now installs directly from the `istio/gateway` chart with values that keep `service.type=ClusterIP`, preserve the chart-managed low-port binding sysctl, and set pod `seccompProfile.type: RuntimeDefault`.
- The Phase 5 runtime verifier now treats ingress token retention and the current egress chart-managed token behavior as explicit exceptions instead of hardening failures.

**Files**

- `kubernetes/istio/istio-gateway.yaml`
- `kubernetes/istio/ingress-gateway-config.yaml`
- `kubernetes/istio/egress-gateway-values.yaml`
- `Tiltfile`

**Changes**

- Keep the Gateway API `Gateway` as the controller source of truth and use `spec.infrastructure.parametersRef` so the generated ingress `Deployment`, `Service`, and `ServiceAccount` are customized declaratively
- Use the ingress Gateway config to set:
  - pod `securityContext.seccompProfile.type: RuntimeDefault`
  - `automountServiceAccountToken: true` on the generated ServiceAccount because the gateway still needs Kubernetes API access for TLS secret watching
  - `nodePort: 30443` on the HTTPS Service port so Tilt no longer has to patch the generated Service after reconciliation
- Update the checked-in egress gateway Helm values to set:
  - `service.type: ClusterIP`
  - `securityContext.sysctls[net.ipv4.ip_unprivileged_port_start=0]` so the non-root gateway keeps the chart's low-port binding behavior
  - pod `securityContext.seccompProfile.type: RuntimeDefault`

**Exception**

The ingress gateway keeps Kubernetes API token access because it watches listener TLS secrets. The egress gateway currently retains the chart's default Kubernetes API token behavior because this repo does not add a separate post-render patch just to remove it. Phase 5 hardens both gateway pod security contexts, but it does not disable either token mount unless an explicit replacement path is introduced and validated.

**Verification**

- Ingress and egress gateway rollouts complete
- Ingress and egress gateway pods show pod-level `seccompProfile.type: RuntimeDefault`
- [`verify-phase-3-istio-ingress.sh`](/workspace/orchestration/scripts/dev/verify-phase-3-istio-ingress.sh) passes

### Session 4: Harden `nginx-gateway`

**Goal**

Remove the root runtime from NGINX and make the gateway read-only except for explicitly mounted runtime paths.

Current implementation status for March 25, 2026:

- Session 4 is implemented in-repo.
- The `nginx-gateway` Deployment and ServiceAccount now disable service-account token automount, set pod `seccompProfile.type: RuntimeDefault`, and apply the planned non-root container baseline.
- The gateway now uses `nginxinc/nginx-unprivileged:1.29.4-alpine`, enables `readOnlyRootFilesystem: true`, and mounts an explicit writable `emptyDir` at `/tmp`.
- `nginx/nginx.k8s.conf` now logs to stdout/stderr, moves the PID file under `/tmp`, and directs temp-file paths to `/tmp` so the read-only root filesystem remains compatible.

**Files**

- `kubernetes/services/nginx-gateway/deployment.yaml`
- `kubernetes/services/nginx-gateway/serviceaccount.yaml`
- `nginx/nginx.k8s.conf`

**Changes**

- Switch to a pinned unprivileged NGINX image. `nginxinc/nginx-unprivileged:<pinned>-alpine` is the preferred path unless an equivalent pinned unprivileged image is already proven in-repo.
- Change `nginx/nginx.k8s.conf` to write logs to stdout/stderr explicitly:
  - `access_log /dev/stdout main;`
  - `error_log /dev/stderr warn;`
- Mount writable `emptyDir` volumes for the paths NGINX still needs at runtime (`/var/cache/nginx`, `/var/run`, and `/tmp` if required by the chosen image)
- Add:
  - pod `automountServiceAccountToken: false`
  - pod `securityContext.seccompProfile.type: RuntimeDefault`
  - container `allowPrivilegeEscalation: false`
  - container `capabilities.drop: ["ALL"]`
  - container `runAsNonRoot: true`
  - container `readOnlyRootFilesystem: true`

**Verification**

- `kubectl exec deployment/nginx-gateway -n default -c nginx -- nginx -t`
- `curl -k https://app.budgetanalyzer.localhost/health`
- `curl -k https://app.budgetanalyzer.localhost/api/docs`
- SPA routes still render through NGINX

### Session 5: Harden `budget-analyzer-web`

**Goal**

Remove the root runtime from the frontend container without breaking the current Vite/HMR workflow.

Current implementation status for March 25, 2026:

- Session 5 is implemented across the orchestration and `budget-analyzer-web` repos.
- The frontend Docker development runtimes now create a dedicated UID/GID `1001` user and run Vite as that numeric non-root user.
- The `budget-analyzer-web` Deployment and ServiceAccount now disable service-account token automount, set pod `seccompProfile.type: RuntimeDefault`, pin `runAsUser`/`runAsGroup` to `1001`, and apply the planned non-root container baseline.
- The Phase 5 verifier now includes a dedicated frontend runtime section that asserts the pinned `1001`/`1001` container identity.
- `readOnlyRootFilesystem: true` remains intentionally deferred until the HMR workflow is proven against explicit writable mounts.

**Files**

- `../budget-analyzer-web/Dockerfile` or `../budget-analyzer-web/Dockerfile.dev` (prerequisite, outside this repo)
- `kubernetes/services/budget-analyzer-web/deployment.yaml`
- `kubernetes/services/budget-analyzer-web/serviceaccount.yaml`
- `Tiltfile` only if the Dockerfile path or build flow changes

**Changes**

- In the sibling repo, create or switch to a non-root runtime user and validate that Vite still runs with live update
- In this repo, add:
  - pod `automountServiceAccountToken: false`
  - pod `securityContext.seccompProfile.type: RuntimeDefault`
  - container `allowPrivilegeEscalation: false`
  - container `capabilities.drop: ["ALL"]`
  - container `runAsNonRoot: true`
- Mount a writable `/tmp` volume if the frontend tooling needs it
- Only enable `readOnlyRootFilesystem: true` if HMR, the Vite cache path, and live sync all work against explicit writable mounts

**Verification**

- Frontend pod runs as UID/GID `1001`
- No `kube-api-access-*` mount remains
- Login page loads
- HMR still reconnects after an edited file sync

**Stop if**

- The sibling Dockerfile still runs as root
- Vite requires broad write access to the image filesystem and no narrow writable-path strategy is proven

### Session 6: Harden Redis

**Goal**

Make Redis compatible with Phase 5 baseline hardening without changing the Phase 1 ACL or Phase 4 TLS behavior.

Current implementation status for March 25, 2026:

- Session 6 is implemented in-repo.
- The Redis Deployment now disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, and runs the container as UID `999` / GID `1000` with the planned non-root baseline.
- Redis now mounts writable `emptyDir` volumes at `/tmp` and `/data`, so `users.acl` bootstrap and AOF output remain compatible with `readOnlyRootFilesystem: true`.
- The local-dev AOF path remains intentionally ephemeral on `emptyDir`; production persistence would require replacing that mount with a PVC-backed volume.

**Files**

- `kubernetes/infrastructure/redis/deployment.yaml`
- `kubernetes/infrastructure/redis/start-redis.sh`

**Changes**

- Set pod `automountServiceAccountToken: false`
- Set pod `securityContext.seccompProfile.type: RuntimeDefault`
- Add container `allowPrivilegeEscalation: false` and `capabilities.drop: ["ALL"]`
- Add explicit writable mounts for:
  - `/tmp` for `users.acl`
  - `/data` for AOF output
- Document explicitly that AOF on an `emptyDir` remains ephemeral in local dev; production persistence would require a PVC
- Validate the Redis image with an explicit non-root UID/GID before turning on `runAsNonRoot: true`
- Enable `readOnlyRootFilesystem: true` only after `/tmp` and `/data` are mounted and startup/probes pass

**Verification**

- Redis restarts and stays Ready
- `./scripts/dev/verify-phase-5-runtime-hardening.sh` asserts the Redis pod runs as UID `999` / GID `1000` and still exposes the explicit writable `emptyDir` mounts at `/tmp` and `/data`
- [`verify-phase-1-credentials.sh`](/workspace/orchestration/scripts/dev/verify-phase-1-credentials.sh) passes
- [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh) still passes

### Session 7: Harden PostgreSQL

**Goal**

Remove the default root runtime from PostgreSQL without breaking bootstrap, TLS material preparation, or PVC initialization.

Current implementation status for March 25, 2026:

- Session 7 is implemented in-repo.
- The PostgreSQL StatefulSet now disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, and pins pod/container ownership to UID/GID `70` through `runAsUser`, `runAsGroup`, and `fsGroup`.
- The TLS-prep init container now runs as the `postgres` user with `readOnlyRootFilesystem: true`, copies the mounted secret material into `/tls`, and tightens the copied keypair permissions without any `chown`.
- The main PostgreSQL container now runs with `readOnlyRootFilesystem: true` and explicit writable mounts for the PVC, `/tmp`, and `/var/run/postgresql`, while first-time bootstrap from an empty PVC remains compatible.
- The Phase 5 verifier now asserts the `fix-tls-perms` init-container baseline alongside the main PostgreSQL runtime contract.

**Files**

- `kubernetes/infrastructure/postgresql/statefulset.yaml`

**Changes**

- Set pod `automountServiceAccountToken: false`
- Set pod `securityContext.seccompProfile.type: RuntimeDefault`
- Harden both the init container and main container with:
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: ["ALL"]`
  - `seccompProfile.type: RuntimeDefault`
- Change the TLS-prep init container to run as UID/GID `70`, replace `chown` with `cp` plus `chmod 600`, and set `runAsNonRoot: true`
- Move the main PostgreSQL process to an explicit non-root UID/GID once volume ownership and socket/tmp paths are validated
- Enable `readOnlyRootFilesystem: true` only after all writable runtime paths are explicitly mounted

**Verification**

- Bootstrap still succeeds from an empty PVC
- PostgreSQL stays Ready
- `./scripts/dev/verify-phase-5-runtime-hardening.sh` asserts the PostgreSQL pod runs as UID/GID `70`, the `fix-tls-perms` init container keeps the hardened baseline including `readOnlyRootFilesystem: true`, and the pod still exposes the explicit writable mounts at `/tmp` and `/var/run/postgresql`
- [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh) passes

### Session 8: Harden RabbitMQ

**Goal**

Apply the same baseline hardening pattern to RabbitMQ as an isolated final infrastructure session.

Current implementation status for March 25, 2026:

- Session 8 is implemented in-repo.
- The RabbitMQ StatefulSet now disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, and pins pod/container ownership to UID/GID `999` through `fsGroup`, `runAsUser`, and `runAsGroup`.
- The broker now runs with `readOnlyRootFilesystem: true` while keeping `/var/lib/rabbitmq` as the explicit PVC-backed writable path.
- The mounted config, boot-time definitions, and TLS material remain read-only.

**Files**

- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`

**Changes**

- Set pod `automountServiceAccountToken: false`
- Set pod `securityContext.seccompProfile.type: RuntimeDefault`
- Add container `allowPrivilegeEscalation: false` and `capabilities.drop: ["ALL"]`
- Validate an explicit non-root UID/GID strategy against the mounted config, definitions, certs, and data volume
- Enable `readOnlyRootFilesystem: true` only after writable runtime paths are isolated to mounted volumes

**Verification**

- RabbitMQ stays Ready
- AMQPS and management remain reachable
- `./scripts/dev/verify-phase-5-runtime-hardening.sh` asserts the RabbitMQ pod runs with `fsGroup`/UID/GID `999`, keeps `/var/lib/rabbitmq` mounted from a PVC, and keeps the config, definitions, and TLS mounts read-only
- [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh) passes

### Session 9: Roll Out Final Namespace PSA Labels

**Goal**

Flip namespace `enforce` labels only after the workloads are actually compatible.

Current implementation status for March 25, 2026:

- Session 9 is implemented in-repo.
- `kubernetes/infrastructure/namespace.yaml`, `kubernetes/istio/ingress-namespace.yaml`, and `kubernetes/istio/egress-namespace.yaml` now declare the final `enforce` labels alongside `warn` and `audit`.
- Tilt's `istio-injection` resource now reapplies the final Pod Security labels for `default`, `infrastructure`, and `istio-system`, so reconciliations restore the intended cluster state without ad-hoc manual labeling.

**Files**

- `kubernetes/infrastructure/namespace.yaml`
- `kubernetes/istio/ingress-namespace.yaml`
- `kubernetes/istio/egress-namespace.yaml`
- `Tiltfile` for `default`, `infrastructure`, and `istio-system`

**Changes**

- `default`: `warn=audit=enforce=restricted`
- `istio-ingress`: `warn=audit=enforce=restricted`
- `istio-egress`: `warn=audit=enforce=restricted`
- `infrastructure`: `warn=audit=enforce=baseline`
- `istio-system`: `enforce=privileged` via the existing Tiltfile namespace-label resource because the namespace is created by Helm
- Restart the affected workloads after the label flip so admission is re-proven under the final policy

**Verification**

- A secure injected smoke pod can be created in a fresh `restricted` namespace
- An intentionally insecure pod is rejected in the same namespace
- All production workloads in the labeled namespaces still roll out cleanly

### Session 10: Run the Final Phase Gate and Clean Up Docs

**Goal**

Treat Phase 5 as complete only when the new verifier and the earlier phase regressions all pass together.

Current implementation status for March 25, 2026:

- Session 10 is complete in-repo.
- Historical baseline: `./scripts/dev/verify-phase-5-runtime-hardening.sh --regression-timeout 8m` passed end-to-end against the live Kind cluster on March 25, 2026 with `166/166` checks passing.
- The current working tree expands that gate with 9 additional assertions: frontend UID/GID pinning plus the PostgreSQL `fix-tls-perms` init-container baseline.
- Verified again on March 25, 2026: the expanded gate passed end-to-end at `175/175`.
- The Phase 5 verifier now bounds each Phase 1 through Phase 4 regression rerun with a per-script timeout, and the nested Phase 2 rerun inside Phase 4 uses a slightly longer warmup budget to avoid transient probe-startup flakes while preserving the same policy assertions.

**Files**

- `scripts/dev/verify-phase-5-runtime-hardening.sh`
- nearest affected docs in `docs/`, `README.md`, and `scripts/README.md` as required by whatever changed during implementation

**Changes**

- Finish any missing verifier checks discovered during the implementation sessions
- Extend the regression step so Phase 5 re-runs:
  - [`verify-phase-1-credentials.sh`](/workspace/orchestration/scripts/dev/verify-phase-1-credentials.sh)
  - [`verify-phase-2-network-policies.sh`](/workspace/orchestration/scripts/dev/verify-phase-2-network-policies.sh)
  - [`verify-phase-3-istio-ingress.sh`](/workspace/orchestration/scripts/dev/verify-phase-3-istio-ingress.sh)
  - [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh)
- Keep those regression reruns bounded with a per-script timeout so the final gate fails cleanly instead of hanging indefinitely
- Run the new Phase 5 verifier
- Fix any drift exposed by the verifier before calling the phase complete
- Update operational documentation in the same sessions as the implementation changes

**Verification**

- `./scripts/dev/verify-phase-5-runtime-hardening.sh`

## Verification Gate

The Phase 5 completion gate is the Phase 5 verifier added in this planning session:

```bash
./scripts/dev/verify-phase-5-runtime-hardening.sh
```

Verified on March 25, 2026 with:

```bash
./scripts/dev/verify-phase-5-runtime-hardening.sh --regression-timeout 8m
```

Observed historical result before the follow-up verifier expansion: `166/166` checks passed.

Verified again on March 25, 2026 with the expanded gate:

```bash
./scripts/dev/verify-phase-5-runtime-hardening.sh --regression-timeout 8m
```

Observed expanded result: `175/175` checks passed.

That verifier is expected to prove:

- namespace PSA labels are at their final enforce levels
- `istio-cni` is installed and meshed secure pods no longer get `istio-init`
- repo-managed workload pods whose prerequisites are satisfied disable Kubernetes API token automount unless they have a concrete Kubernetes API dependency
- workload pods whose prerequisites are satisfied carry the expected hardening fields
- restricted PSA both admits a secure meshed pod and rejects an insecure one
- Phase 1 credential isolation, Phase 2 network policies, Phase 3 ingress behavior, and Phase 4 transport encryption still pass as regressions

The current verifier now includes dedicated `budget-analyzer-web` UID/GID checks because Session 5's sibling-repo image prerequisite is satisfied in the checked-in frontend Dockerfiles, and it now also asserts the PostgreSQL `fix-tls-perms` init-container baseline from Session 7.

Do not declare Phase 5 complete until that verifier passes end-to-end.
