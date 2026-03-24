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
- Gateway API auto-provisioned gateway resources can be hardened declaratively through `spec.infrastructure.parametersRef`: <https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/>

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
| `budget-analyzer-web` | Root image in sibling repo | Requires sibling Dockerfile change first | Validate after non-root cutover | Do not pretend this is orchestration-only |
| `nginx-gateway` | Root image and root-owned paths | Orchestration-only, but needs image/runtime path changes | Yes | Move logs off `/var/log/nginx`; mount writable temp dirs |
| `istio-ingress` generated gateway | Non-root proxy container, but no pod seccomp or token hardening yet | Declarative overlay through Gateway `parametersRef` | Already effectively yes | Do not use ad-hoc `kubectl patch` as source of truth |
| `istio-egress` gateway | Non-root proxy container, but no pod seccomp or token hardening yet | Manifest hardening in this repo | Already yes | Repo already vendors this manifest |
| `redis` | Root, writes ACL file to `/tmp`, AOF to default data path | Needs writable `/tmp` and `/data` plus explicit UID validation | Optional after validation | Current Deployment has no explicit Redis data volume |
| `postgresql` | Root | Needs volume ownership strategy and explicit non-root validation | Optional after validation | Init container may remain UID `0` if strictly necessary |
| `rabbitmq` | Root | Needs volume ownership strategy and explicit non-root validation | Optional after validation | StatefulSet session should stand alone |

## Session Breakdown

Each session below is scoped so it can be finished, validated, and documented in a single working session.

### Session 1: Replace `istio-init` with Istio CNI

**Goal**

Remove the hard blocker that prevents meshed workloads from being admitted under Pod Security `restricted`.

**Files**

- `Tiltfile`
- `kubernetes/istio/istiod-values.yaml`
- `kubernetes/istio/cni-values.yaml` (new)

**Changes**

- Install the `istio/cni` chart in `istio-system`
- Set `pilot.cni.enabled=true` for the `istiod` install
- Add an explicit `kubernetes/istio/cni-values.yaml` instead of baking CNI knobs into long inline Helm commands
- Set `seccompProfile.type: RuntimeDefault` on the `istio-cni` DaemonSet through chart values
- Label `istio-system` for PSA `enforce=privileged`
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
- Set explicit UID/GID `1001` on the Spring Boot containers so the runtime does not rely on image metadata alone
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

Make both gateway namespaces compatible with Pod Security `restricted` and remove Kubernetes API token mounts from the gateway pods.

**Files**

- `kubernetes/istio/istio-gateway.yaml`
- `kubernetes/istio/ingress-gateway-options-configmap.yaml` (new)
- `kubernetes/istio/egress-gateway.yaml`
- `Tiltfile`

**Changes**

- Add `spec.infrastructure.parametersRef` to the Gateway API `Gateway` in `istio-ingress`
- Create a same-namespace ConfigMap that overlays the generated ingress `Deployment` and `ServiceAccount`
- Use the ingress overlay to set:
  - pod `automountServiceAccountToken: false`
  - pod `securityContext.seccompProfile.type: RuntimeDefault`
  - any missing service-account defaults needed to keep generated resources hardened after controller reconciliation
- Update the vendored egress gateway manifest to set:
  - pod `automountServiceAccountToken: false`
  - pod `securityContext.seccompProfile.type: RuntimeDefault`
  - ServiceAccount `automountServiceAccountToken: false`

**Verification**

- Ingress and egress gateway rollouts complete
- Gateway pods do not mount `kube-api-access-*`
- Ingress and egress gateway pods show pod-level `seccompProfile.type: RuntimeDefault`
- [`verify-phase-3-istio-ingress.sh`](/workspace/orchestration/scripts/dev/verify-phase-3-istio-ingress.sh) passes

### Session 4: Harden `nginx-gateway`

**Goal**

Remove the root runtime from NGINX and make the gateway read-only except for explicitly mounted runtime paths.

**Files**

- `kubernetes/services/nginx-gateway/deployment.yaml`
- `kubernetes/services/nginx-gateway/serviceaccount.yaml`
- `nginx/nginx.k8s.conf`

**Changes**

- Replace the current root-based runtime with a pinned unprivileged NGINX image, or prove an equivalent explicit UID/GID strategy against the current image
- Move access and error logs to stdout/stderr instead of `/var/log/nginx/*`
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

**Prerequisite**

The sibling repo `../budget-analyzer-web` must stop building a root image first. This repo cannot finish that prerequisite because it is a sibling code change.

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

- Frontend pod runs as non-root
- No `kube-api-access-*` mount remains
- Login page loads
- HMR still reconnects after an edited file sync

**Stop if**

- The sibling Dockerfile still runs as root
- Vite requires broad write access to the image filesystem and no narrow writable-path strategy is proven

### Session 6: Harden Redis

**Goal**

Make Redis compatible with Phase 5 baseline hardening without changing the Phase 1 ACL or Phase 4 TLS behavior.

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
- Validate the Redis image with an explicit non-root UID/GID before turning on `runAsNonRoot: true`
- Enable `readOnlyRootFilesystem: true` only after `/tmp` and `/data` are mounted and startup/probes pass

**Verification**

- Redis restarts and stays Ready
- [`verify-phase-1-credentials.sh`](/workspace/orchestration/scripts/dev/verify-phase-1-credentials.sh) passes
- [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh) still passes

### Session 7: Harden PostgreSQL

**Goal**

Remove the default root runtime from PostgreSQL without breaking bootstrap, TLS material preparation, or PVC initialization.

**Files**

- `kubernetes/infrastructure/postgresql/statefulset.yaml`

**Changes**

- Set pod `automountServiceAccountToken: false`
- Set pod `securityContext.seccompProfile.type: RuntimeDefault`
- Harden both the init container and main container with:
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: ["ALL"]`
  - `seccompProfile.type: RuntimeDefault`
- Move the main PostgreSQL process to an explicit non-root UID/GID once volume ownership and socket/tmp paths are validated
- Keep the init container at UID `0` only if that remains necessary for file ownership fixes; do not give it extra capabilities
- Enable `readOnlyRootFilesystem: true` only after all writable runtime paths are explicitly mounted

**Verification**

- Bootstrap still succeeds from an empty PVC
- PostgreSQL stays Ready
- [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh) passes

### Session 8: Harden RabbitMQ

**Goal**

Apply the same baseline hardening pattern to RabbitMQ as an isolated final infrastructure session.

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
- [`verify-phase-4-transport-encryption.sh`](/workspace/orchestration/scripts/dev/verify-phase-4-transport-encryption.sh) passes

### Session 9: Roll Out Final Namespace PSA Labels

**Goal**

Flip namespace `enforce` labels only after the workloads are actually compatible.

**Files**

- `kubernetes/infrastructure/namespace.yaml`
- `kubernetes/istio/ingress-namespace.yaml`
- `kubernetes/istio/egress-namespace.yaml`
- `Tiltfile` for `default` and `istio-system`

**Changes**

- `default`: `warn=audit=enforce=restricted`
- `istio-ingress`: `warn=audit=enforce=restricted`
- `istio-egress`: `warn=audit=enforce=restricted`
- `infrastructure`: `warn=audit=enforce=baseline`
- `istio-system`: `enforce=privileged`
- Restart the affected workloads after the label flip so admission is re-proven under the final policy

**Verification**

- A secure injected smoke pod can be created in a fresh `restricted` namespace
- An intentionally insecure pod is rejected in the same namespace
- All production workloads in the labeled namespaces still roll out cleanly

### Session 10: Run the Final Phase Gate and Clean Up Docs

**Goal**

Treat Phase 5 as complete only when the new verifier and the earlier phase regressions all pass together.

**Files**

- `scripts/dev/verify-phase-5-runtime-hardening.sh`
- nearest affected docs in `docs/`, `README.md`, and `scripts/README.md` as required by whatever changed during implementation

**Changes**

- Finish any missing verifier checks discovered during the implementation sessions
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

That verifier is expected to prove:

- namespace PSA labels are at their final enforce levels
- `istio-cni` is installed and meshed secure pods no longer get `istio-init`
- repo-managed workload pods disable Kubernetes API token automount
- workload pods carry the expected hardening fields
- restricted PSA both admits a secure meshed pod and rejects an insecure one
- Phase 3 ingress behavior and Phase 4 transport encryption still pass as regressions

Do not declare Phase 5 complete until that verifier passes end-to-end.
