# Plan: OCI Deployment Upgrade Lockstep

Date: 2026-05-05
Status: Draft

Related documents:

- `docs/plans/dependency-upgrade-and-centralized-bom-plan.md`
- `docs/dependency-notifications.md`
- `docs/OWNERSHIP.md`
- `docs-aggregator/README.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `deploy/scripts/lib/phase-4-version-contract.sh`
- `scripts/lib/pinned-tool-versions.sh`
- `kubernetes/production/apps/image-inventory.yaml`
- `kubernetes/production/apps/kustomization.yaml`
- `scripts/guardrails/verify-production-image-overlay.sh`
- `docs/plans/kind-k3s-inotify-log-streaming-plan.md`

## Scope

This plan adds the OCI production half of the dependency upgrade plan. The goal
is that local Tilt/Kind development and OCI/k3s production stay on one reviewed
compatibility baseline, with every local version upgrade either reflected in the
OCI deploy path or explicitly marked local-only.

This plan does not replace the dependency upgrade plan. It is the production
execution companion for that plan.

## Current Branch Alignment

The current dependency-upgrade branch implements centralized backend dependency
management as two `service-common` platform artifacts:

- `org.budgetanalyzer:spring-platform`
- `org.budgetanalyzer:spring-cloud-platform`

Use those names when planning production release images. The earlier
`budgetanalyzer-dependencies` name remains a planning direction from the
dependency plan, not the artifact name in the current sibling branches.

Production surfaces already reflected on this branch:

- Gateway API is pinned to `v1.5.1` in both the local tool contract and the OCI
  phase 4 version contract.
- Istio is pinned to `1.29.2` in local Tilt and the OCI phase 4 version
  contract.
- Kyverno is pinned to chart `3.8.0` locally and in OCI, with production image
  digests refreshed in `deploy/helm-values/kyverno.values.yaml`.
- PostgreSQL and Redis shared infrastructure manifests use refreshed digest
  pins, and the production infrastructure render path inherits them.
- The RabbitMQ `currency-service` resource allow-list now follows the
  `exchange-rate.import.requested` destination introduced by
  `currency-service` commit `6535b33` and removes the former `currency.created`
  destination from the local Tilt definitions. OCI operators must render
  `budget-analyzer-rabbitmq-definitions` from
  `deploy/manifests/phase-5/rabbitmq-definitions.template.json` before
  deploying the matching `currency-service` image.
- The `/api-docs` ConfigMap split is represented in both local Tilt and the
  production app overlay so large OpenAPI documents do not fall back to one
  apply-annotation-heavy ConfigMap.

Production surfaces still pending before this upgrade is actually deployed to
OCI:

- Backend and frontend GHCR release images still need to be rebuilt and
  published for `linux/arm64` after the sibling repo branches are merged.
- The `transaction-service` preview import token encryption secret introduced
  by the `duplicate-file-upload-warning` branch needs a full local and OCI
  secret-sync path before deploying a matching release image. See
  `docs/plans/transaction-preview-import-token-secret-plan.md`.
- `kubernetes/production/apps/image-inventory.yaml`,
  `kubernetes/production/apps/kustomization.yaml`, and
  `scripts/guardrails/verify-production-image-overlay.sh` still reference the
  existing production release image set until those images exist.
- The planned release-image update helper and OCI lockstep verifier are not yet
  implemented in this repo; they remain required script work below.
- The OCI bootstrap path does not yet converge host inotify limits for
  k3s/containerd log-follow behavior. Add that before treating `kubectl logs -f`
  and operator log streaming as reliable on the production host.
- The current sibling backend branches still pin Spring Boot `3.5.7`, Spring
  Cloud `2025.0.0`, and Spring Modulith `1.4.0` through the new platform
  artifacts. If those framework versions are upgraded later, treat that as a
  new release-image batch for OCI.

## Review Findings

The dependency upgrade plan correctly identifies the main local upgrade
workstreams: centralized backend dependency management, Java and Gradle, Kind
and Kubernetes, Gateway API, Calico, Tilt, Istio, Kyverno, PostgreSQL, Redis,
and frontend dependencies.

The plan does not yet spell out the OCI production surfaces that must change in
lockstep. The important production surfaces are:

- `deploy/scripts/lib/phase-4-version-contract.sh` for k3s, Gateway API,
  Istio, External Secrets Operator, cert-manager, Kyverno, kube-prometheus-stack,
  Kiali, and Pod Security label version pins
- `deploy/scripts/*.sh` for the reviewed render/apply order that reconciles the
  live OCI cluster to those pins
- `deploy/helm-values/*.yaml` and `kubernetes/monitoring/*.yaml` for
  production Helm values and digest-pinned chart-managed images
- `kubernetes/production/apps/image-inventory.yaml`,
  `kubernetes/production/apps/kustomization.yaml`, and
  `scripts/guardrails/verify-production-image-overlay.sh` for application
  release image refs
- `kubernetes/production/infrastructure` plus
  `deploy/scripts/17-render-production-infrastructure.sh` and
  `deploy/scripts/18-apply-production-infrastructure.sh` for production
  PostgreSQL, RabbitMQ, and Redis changes

The production image path currently repeats the same six GHCR release refs in
three places. That is too easy to drift during dependency upgrades that produce
new release images.

## Lockstep Rules

- Every dependency upgrade PR or batch must include an "OCI surface" line for
  each changed version.
- Local-only versions are allowed only when they truly have no production
  runtime effect, such as Tilt itself. Mark them `Local-only` in the upgrade
  notes instead of silently omitting OCI.
- OCI version pins must live in checked-in scripts, manifests, or values files.
  Do not rely on one-off live `kubectl` or `helm` mutations.
- Production script pins should be centralized in
  `deploy/scripts/lib/phase-4-version-contract.sh` when the version is consumed
  by more than one deployment script.
- All third-party production images and Docker base images remain digest-pinned
  unless an executable inventory explicitly documents an exception.
- Application dependency upgrades do not reach OCI until all affected service
  and frontend release images are published for `linux/arm64` and the
  production image inventory is updated to those digest-pinned refs.
- The live OCI path must be verified from the same repo-owned scripts that a
  new host would use.

## Version Surface Map

| Upgrade area | Local development surface | OCI production surface | Required lockstep action |
| --- | --- | --- | --- |
| Spring Boot, Spring Cloud, Spring Modulith, backend library BOMs | Backend Gradle files and the new `service-common` `spring-platform` / `spring-cloud-platform` artifacts | Published service release images and production image inventory | Build and publish new `linux/arm64` GHCR images, then update production image refs and the production verifier. |
| Java and Gradle | Backend wrappers, toolchains, local Tilt runtime image, devcontainer | Service production Dockerfiles in sibling repos, published GHCR images | Treat OCI as updated only after the release images were rebuilt from the new Java/Gradle baseline and pinned in production manifests. |
| Frontend React dependencies | `../budget-analyzer-web/package.json` and local Vite/Tilt flow | `budget-analyzer-web` GHCR release image used as the `nginx-gateway` web-assets init container | Publish the frontend release image and update the production image inventory, kustomize patch, and verifier. |
| Istio | `Tiltfile`, local Istio values, Gateway API route smoke tests | `PHASE4_ISTIO_CHART_VERSION`, k3s CNI values, `deploy/scripts/04-install-istio.sh` | Update the production version contract, render/review phase 4 and phase 6 output, then rerun the Istio production script. |
| Gateway API CRDs | `Tiltfile`, `setup.sh`, local prerequisite checks | `PHASE4_GATEWAY_API_CRDS_VERSION` and `deploy/scripts/02-bootstrap-cluster.sh` | Update both local and production CRD pins, apply CRDs through the production bootstrap script, then rerun route checks. |
| Kubernetes platform | Kind binary/node image, kubectl, Calico | `PHASE4_K3S_VERSION`, `PHASE4_POD_SECURITY_VERSION`, OCI host `kubectl` install | Choose compatible Kind and k3s Kubernetes versions together, update the production version contract, and reconcile k3s before mesh upgrades. |
| Calico | `scripts/bootstrap/install-calico.sh` and Kind CNI | Not installed separately in OCI k3s | Mark OCI as `Not applicable`; still validate k3s NetworkPolicy enforcement with the production verifier. |
| Kubernetes node inotify budget | `scripts/bootstrap/install-calico.sh` converges Kind node `fs.inotify.max_user_instances` and `fs.inotify.max_user_watches` | OCI host sysctl settings consumed by k3s/containerd and `kubectl logs -f` | Keep local and OCI minimums aligned at `max_user_instances >= 8192` and `max_user_watches >= 524288`; converge OCI before or during k3s install and verify log-follow behavior after rollout. |
| Tilt | `scripts/lib/pinned-tool-versions.sh`, devcontainer | No runtime production component | Mark OCI as `Local-only`; no deploy script change required. |
| Kyverno | `Tiltfile`, local policies, Kyverno CLI | `PHASE7_KYVERNO_CHART_VERSION`, `deploy/helm-values/kyverno.values.yaml`, `deploy/scripts/14-install-phase-7-kyverno.sh`, `deploy/scripts/15-apply-phase-7-policies.sh` | Update production chart and digest-pinned controller image values together, then rerun production policy install/apply. |
| kube-prometheus-stack | Local monitoring Helm install and values | `PHASE7_PROMETHEUS_STACK_CHART_VERSION`, production monitoring override, `deploy/scripts/22-apply-production-monitoring.sh` | Update chart pin and any digest-pinned rendered image values/post-render expectations, then reapply production monitoring. |
| Kiali | Local Kiali chart and values | `PHASE7_KIALI_CHART_VERSION`, `kubernetes/monitoring/kiali-values.yaml`, `deploy/scripts/20-render-phase-7-observability.sh`, `deploy/scripts/21-apply-phase-7-observability.sh` | Update chart pin and values, render production Kiali against the live cluster, then apply through the reviewed observability path. |
| RabbitMQ application channels | `Tiltfile` boot-time definitions and local RabbitMQ secret | OCI Vault `budget-analyzer-rabbitmq-definitions` synced into `rabbitmq-bootstrap-credentials[definitions.json]` | Keep `deploy/manifests/phase-5/rabbitmq-definitions.template.json` aligned with `currency-service` Spring Cloud Stream destinations, include service queues/DLQs in `write` permission for RabbitMQ declaration checks, update the OCI Vault secret before deploying a matching service image, and clean obsolete broker resources such as the former `currency.created` exchange/queues during the infrastructure reconcile. |
| Transaction preview import token encryption secret | `Tiltfile` local `transaction-service-preview-import-token-credentials[encryption-secret]` and `kubernetes/services/transaction-service/deployment.yaml` env injection | OCI Vault `budget-analyzer-transaction-preview-import-token-encryption-secret` generated by `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh` and synced into `transaction-service-preview-import-token-credentials[encryption-secret]` | Create the dedicated generated application secret before deploying a transaction-service image that requires `PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET`; keep the key out of PostgreSQL credentials and `deploy/instance.env.template`, update the secrets-only inventory, and reapply phase 5 secret sync on OCI. |
| PostgreSQL | `kubernetes/infrastructure/postgresql` | `kubernetes/production/infrastructure` render/apply path | Refresh digests in the shared manifest, render the production overlay, and apply through `18-apply-production-infrastructure.sh`; major versions need a separate data migration plan. |
| Redis | `kubernetes/infrastructure/redis` | `kubernetes/production/infrastructure` render/apply path and Redis StatefulSet storage patch | Refresh digests in the shared manifest, render the production overlay, and apply through the production infrastructure script; major versions need session/cache compatibility validation first. |

## Required Script Work

### 1. Add A Production Release Image Update Helper

Add `deploy/scripts/23-update-production-release-images.sh`.

Inputs:

- `--release-version <version>`
- `--transaction-service <image-ref>`
- `--currency-service <image-ref>`
- `--permission-service <image-ref>`
- `--session-gateway <image-ref>`
- `--budget-analyzer-web <image-ref>`
- `--ext-authz <image-ref>`

Validation performed by the script:

- every image ref starts with `ghcr.io/budgetanalyzer/`
- every image ref contains `:<release-version>@sha256:<64 lowercase hex>`
- no ref contains `:latest`, `:tilt-`, or `imagePullPolicy: Never`
- all six application refs are present exactly once in the generated update
- `kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone`
  succeeds after the edit
- `./scripts/guardrails/verify-production-image-overlay.sh` passes after the
  edit

Files updated by the script:

- `kubernetes/production/apps/image-inventory.yaml`
- `kubernetes/production/apps/kustomization.yaml`
- `scripts/guardrails/verify-production-image-overlay.sh`
- `deploy/instance.env.template`
- `kubernetes/production/README.md`
- `docs/ci-cd.md` if the documented release version changes there
- `scripts/README.md` if the verifier summary names the old release version

Use a structured YAML-aware update where practical. If the script has to update
the shell verifier array, keep the array sorted in the same service order as
`image-inventory.yaml`.

Validation for this new script:

```bash
bash -n deploy/scripts/23-update-production-release-images.sh
shellcheck deploy/scripts/23-update-production-release-images.sh
./deploy/scripts/23-update-production-release-images.sh --help
```

### 2. Add An OCI Lockstep Static Verifier

Add `deploy/scripts/24-verify-oci-upgrade-lockstep.sh`.

The verifier should fail when:

- `PHASE4_ISTIO_CHART_VERSION` differs from the Istio chart version used by
  local Tilt
- `PHASE4_GATEWAY_API_CRDS_VERSION` differs from the local Gateway API CRD pin
- `PHASE7_KYVERNO_CHART_VERSION` differs from the local Kyverno Helm chart pin
- `PHASE7_KIALI_CHART_VERSION` differs from the local Kiali chart pin
- `PHASE7_PROMETHEUS_STACK_CHART_VERSION` differs from the local
  kube-prometheus-stack chart pin
- production `image-inventory.yaml`, production kustomize patches, and
  `EXPECTED_IMAGE_REFS` in `verify-production-image-overlay.sh` disagree
- production `/api-docs` ConfigMap generation disagrees with the rendered
  `nginx-gateway` deployment volume references
- production infrastructure renders an image that is not digest-pinned
- production Helm values render chart-managed workload images without digests

The verifier should warn, not fail, for accepted non-identical local/production
platform choices:

- Kind node image versus k3s version, as long as both Kubernetes versions are in
  the supported Istio range selected by the upgrade batch
- Calico local CNI versus k3s NetworkPolicy implementation, because OCI does
  not install Calico separately
- Tilt, because it is local-only

Validation for this new script:

```bash
bash -n deploy/scripts/24-verify-oci-upgrade-lockstep.sh
shellcheck deploy/scripts/24-verify-oci-upgrade-lockstep.sh
./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
```

### 3. Wire The New Verifier Into Existing OCI Gates

Update `scripts/guardrails/verify-production-image-overlay.sh` or the
production CI guardrail entry point to call the lockstep verifier after the
production render checks. Avoid circular calls: if
`24-verify-oci-upgrade-lockstep.sh` calls the production image verifier, the
production image verifier must not call it back.

Document the new script in:

- `deploy/README.md`
- `kubernetes/production/README.md`
- `scripts/README.md`

### 4. Add OCI Host Inotify Budget Convergence

Update `deploy/scripts/01-install-k3s.sh` or add a small helper sourced by that
script so the OCI host converges these sysctls before k3s starts or restarts:

```text
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
```

Required behavior:

- write a reviewed file such as `/etc/sysctl.d/90-budget-analyzer-inotify.conf`
  through `phase4_run_sudo`
- run `sysctl --system` or targeted `sysctl -w` commands before installing or
  restarting k3s
- print the final values with `sysctl fs.inotify.max_user_instances
  fs.inotify.max_user_watches`
- make reruns idempotent
- do not lower higher operator-provided values
- document that this is a host prerequisite for reliable `kubectl logs -f`,
  Tilt-like log streaming, and other fsnotify consumers on k3s/containerd

Validation for the changed production script:

```bash
bash -n deploy/scripts/01-install-k3s.sh
shellcheck deploy/scripts/01-install-k3s.sh
```

## OCI Upgrade Execution Steps

### Phase 0: Preflight

1. Confirm the local dependency upgrade branch has passed the validation in
   `docs/plans/dependency-upgrade-and-centralized-bom-plan.md`.
2. Confirm every changed service or frontend repo has a release tag and a
   `linux/arm64` GHCR image.
3. Confirm `~/.config/budget-analyzer/instance.env` exists on the OCI host.
4. Export the production kubeconfig on the OCI host:
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ```
5. Capture the live baseline:
   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A
   helm list -A
   kubectl get deploy,statefulset -A
   ```
6. Capture the current OCI host inotify baseline:
   ```bash
   sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
   ```
   Values below `8192` instances or `524288` watches must be reconciled before
   relying on `kubectl logs -f` during the upgrade.

### Phase 1: Update Version Contracts

1. Update `deploy/scripts/lib/phase-4-version-contract.sh` for every production
   platform version changed by the local upgrade batch:
   - `PHASE4_K3S_VERSION`
   - `PHASE4_GATEWAY_API_CRDS_VERSION`
   - `PHASE4_ISTIO_CHART_VERSION`
   - `PHASE4_EXTERNAL_SECRETS_CHART_VERSION`
   - `PHASE4_CERT_MANAGER_CHART_VERSION`
   - `PHASE7_KYVERNO_CHART_VERSION`
   - `PHASE7_PROMETHEUS_STACK_CHART_VERSION`
   - `PHASE7_KIALI_CHART_VERSION`
   - `PHASE4_POD_SECURITY_VERSION`
2. Update production Helm values when chart-managed images or chart value
   schemas changed:
   - `deploy/helm-values/external-secrets.values.yaml`
   - `deploy/helm-values/cert-manager.values.yaml`
   - `deploy/helm-values/kyverno.values.yaml`
   - `kubernetes/monitoring/kiali-values.yaml`
   - `kubernetes/monitoring/prometheus-stack-values.yaml`
   - `kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
3. Validate changed shell scripts:
   ```bash
   bash -n deploy/scripts/lib/phase-4-version-contract.sh
   shellcheck deploy/scripts/lib/phase-4-version-contract.sh
   ```

### Phase 2: Update Application Release Images

1. Collect the six published digest-pinned image refs from the release
   workflows.
2. Run the new helper:
   ```bash
   ./deploy/scripts/23-update-production-release-images.sh \
     --release-version 0.0.x \
     --transaction-service ghcr.io/budgetanalyzer/transaction-service:0.0.x@sha256:<digest> \
     --currency-service ghcr.io/budgetanalyzer/currency-service:0.0.x@sha256:<digest> \
     --permission-service ghcr.io/budgetanalyzer/permission-service:0.0.x@sha256:<digest> \
     --session-gateway ghcr.io/budgetanalyzer/session-gateway:0.0.x@sha256:<digest> \
     --budget-analyzer-web ghcr.io/budgetanalyzer/budget-analyzer-web:0.0.x@sha256:<digest> \
     --ext-authz ghcr.io/budgetanalyzer/ext-authz:0.0.x@sha256:<digest>
   ```
3. Review the exact diff in:
   - `kubernetes/production/apps/image-inventory.yaml`
   - `kubernetes/production/apps/kustomization.yaml`
   - `scripts/guardrails/verify-production-image-overlay.sh`
4. Render and verify locally before touching OCI:
   ```bash
   kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
   ./scripts/guardrails/check-secrets-only-handling.sh
   ./scripts/guardrails/verify-production-image-overlay.sh
   ./deploy/scripts/09-render-phase-5-secrets.sh
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ```

### Phase 3: Render Production Artifacts

1. Render the phase 4 ingress artifacts:
   ```bash
   ./deploy/scripts/03-render-phase-4-istio-manifests.sh
   sed -n '1,220p' tmp/phase-4/ingress-gateway-config.yaml
   sed -n '1,220p' tmp/phase-4/istio-gateway.yaml
   ```
2. Render the phase 6 production route, ingress policy, monitoring override,
   and egress artifacts:
   ```bash
   ./deploy/scripts/13-render-phase-6-production-manifests.sh
   sed -n '1,260p' tmp/phase-6/gateway-routes.yaml
   sed -n '1,220p' tmp/phase-6/istio-ingress-policies.yaml
   sed -n '1,120p' tmp/phase-6/prometheus-stack-values.override.yaml
   sed -n '1,260p' tmp/phase-6/istio-egress.yaml
   ```
3. Render production infrastructure:
   ```bash
   ./deploy/scripts/17-render-production-infrastructure.sh
   sed -n '1,260p' tmp/production-infrastructure/infrastructure.yaml
   ```
4. Render observability if Kiali, Jaeger, or monitoring versions changed:
   ```bash
   ./deploy/scripts/20-render-phase-7-observability.sh
   sed -n '1,220p' tmp/phase-7-observability/jaeger-deployment.yaml
   sed -n '1,260p' tmp/phase-7-observability/kiali.yaml
   ```

### Phase 4: Reconcile OCI Platform

Run these on the OCI host from the updated repo checkout.

1. Reconcile k3s if `PHASE4_K3S_VERSION` changed:
   ```bash
   ./deploy/scripts/01-install-k3s.sh
   kubectl get nodes -o wide
   ```
   This step must also converge the OCI host inotify budget for k3s/containerd
   log-follow behavior. Confirm the values after the script runs:
   ```bash
   sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
   ```
2. Reapply Gateway API CRDs and namespace labels if Gateway API or Pod Security
   version changed:
   ```bash
   ./deploy/scripts/02-bootstrap-cluster.sh
   ```
3. Reconcile Istio if Istio, Gateway API, CNI values, ingress config, or mesh
   policy changed:
   ```bash
   ./deploy/scripts/04-install-istio.sh
   ```
   If the live cluster already has public TLS, use
   `--acknowledge-public-tls-downgrade` only when the phase 11 TLS manifests
   will be reapplied immediately afterward.
4. Reconcile platform controllers if External Secrets Operator or cert-manager
   changed:
   ```bash
   ./deploy/scripts/05-install-platform-controllers.sh
   ```
5. Reapply network policies after Kubernetes, CNI, ingress, cert-manager, or
   policy changes:
   ```bash
   ./deploy/scripts/07-apply-network-policies.sh
   ./deploy/scripts/08-verify-network-policy-enforcement.sh
   ```

### Phase 5: Reconcile OCI Workloads

1. Apply production infrastructure if PostgreSQL, RabbitMQ, Redis, storage, or
   infrastructure manifests changed:
   ```bash
   ./deploy/scripts/18-apply-production-infrastructure.sh
   ```
2. Apply production secrets and IDP config if the upgrade changes non-secret
   Auth0/IDP config or `ExternalSecret` wiring:
   ```bash
   ./deploy/scripts/09-render-phase-5-secrets.sh
   ./deploy/scripts/10-apply-phase-5-secrets.sh
   ```
   If the upgrade includes the transaction-service preview import token work,
   create or confirm the OCI Vault
   `budget-analyzer-transaction-preview-import-token-encryption-secret` first,
   then confirm the synced
   `transaction-service-preview-import-token-credentials` Secret exists in the
   `default` namespace before deploying the matching transaction-service image:
   ```bash
   kubectl get externalsecret -n default transaction-service-preview-import-token-credentials
   kubectl get secret -n default transaction-service-preview-import-token-credentials
   ```
   If the upgrade changes RabbitMQ application destinations, update the OCI
   Vault `budget-analyzer-rabbitmq-definitions` secret from
   `deploy/manifests/phase-5/rabbitmq-definitions.template.json` before this
   step, then confirm the synced `rabbitmq-bootstrap-credentials` secret
   contains the new definitions.
3. If the upgrade removes RabbitMQ application destinations, manually delete
   the obsolete empty queues before deploying the matching service image. For
   the `currency.created` to `exchange-rate.import.requested` cutover:
   ```bash
   kubectl exec -n infrastructure statefulset/rabbitmq -- rabbitmqctl delete_queue -p / currency.created.exchange-rate-import-service
   kubectl exec -n infrastructure statefulset/rabbitmq -- rabbitmqctl delete_queue -p / currency.created.exchange-rate-import-service.dlq
   ```
   Do not delete non-empty queues without an explicit migration or discard
   decision.
4. Apply the production app overlay with server-side apply:
   ```bash
   kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone | kubectl apply --server-side -f -
   kubectl rollout status deployment/transaction-service --timeout=300s
   kubectl rollout status deployment/currency-service --timeout=300s
   kubectl rollout status deployment/permission-service --timeout=300s
   kubectl rollout status deployment/session-gateway --timeout=300s
   kubectl rollout status deployment/ext-authz --timeout=300s
   kubectl rollout status deployment/nginx-gateway --timeout=300s
   ```
5. Reapply Kyverno and policies if Kyverno, policies, or production image refs
   changed:
   ```bash
   ./deploy/scripts/14-install-phase-7-kyverno.sh
   ./deploy/scripts/15-apply-phase-7-policies.sh
   ```
6. Reapply observability if monitoring, Jaeger, or Kiali changed:
   ```bash
   ./deploy/scripts/22-apply-production-monitoring.sh --verify-runtime
   ```
7. If phase 4 Istio reconcile temporarily removed public TLS, render and apply
   the phase 11 public TLS artifacts immediately:
   ```bash
   ./deploy/scripts/16-render-phase-11-public-tls-manifests.sh
   kubectl apply -f tmp/phase-11/cluster-issuer.yaml
   kubectl apply -f tmp/phase-11/public-certificate.yaml
   kubectl apply -f tmp/phase-11/reference-grant.yaml
   kubectl apply -f tmp/phase-11/ingress-gateway-config.yaml
   kubectl apply -f tmp/phase-11/istio-gateway.yaml
   ```

### Phase 6: Production Verification

1. Run static production checks:
   ```bash
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ./scripts/guardrails/verify-production-image-overlay.sh
   ```
2. Verify live cluster state:
   ```bash
   kubectl get nodes -o wide
   kubectl get pods -A
   kubectl get gateway,httproute -A
   kubectl get peerauthentication,authorizationpolicy -A
   kubectl get networkpolicy -A
   ```
3. Verify application images match the checked-in inventory:
   ```bash
   kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u
   kubectl get pods -A -o jsonpath='{.items[*].spec.initContainers[*].image}' | tr ' ' '\n' | sort -u
   ```
4. Run focused production smoke checks from the OCI host:
   ```bash
   ./deploy/scripts/08-verify-network-policy-enforcement.sh
   ./scripts/smoketest/verify-observability-port-forward-access.sh
   ./scripts/smoketest/verify-monitoring-runtime.sh --wait-timeout 180
   ```
5. Verify Kubernetes log follow no longer emits the fsnotify watcher error:
   ```bash
   kubectl logs -f deployment/transaction-service --tail=1 --request-timeout=10s
   ```
   Any remaining `failed to create fsnotify watcher: too many open files` output
   means the OCI host inotify budget is still not converged or another host
   file-descriptor limit needs investigation.
6. From a workstation, verify the public route through the production hostname:
   ```bash
   curl -I https://demo.budgetanalyzer.org/
   curl -I https://demo.budgetanalyzer.org/api-docs
   ```

## Completion Criteria

- Every local dependency upgrade has a matching OCI action or an explicit
  `Local-only` / `Not applicable` note.
- Production platform pins are centralized in
  `deploy/scripts/lib/phase-4-version-contract.sh` where applicable.
- The production image inventory, production kustomize patches, and production
  image verifier all reference the same digest-pinned release images.
- `./deploy/scripts/24-verify-oci-upgrade-lockstep.sh` passes.
- `./scripts/guardrails/verify-production-image-overlay.sh` passes.
- OCI workloads roll out from checked-in scripts/manifests without manual live
  cluster drift.
- OCI host inotify limits are converged by the checked-in production bootstrap
  path and `kubectl logs -f` works without fsnotify watcher errors.
- Observability remains internal-only, with no public Grafana, Prometheus,
  Jaeger, or Kiali routes.
- Any changed shell scripts pass `bash -n` and `shellcheck`.
