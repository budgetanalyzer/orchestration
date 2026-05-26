# Oracle Cloud Deployment Path

This directory is the committed, operator-facing install surface for the Oracle
Cloud deployment path. k3s/Istio bootstrap, secret synchronization,
production rendering, infrastructure render/apply, public TLS, and
production Kyverno install/apply operations all have first-class, reviewable
artifacts here so a human can inspect the exact cluster mutations before
touching the OCI instance or Vault.

`deploy/` contains only repeatable Pattern B artifacts:

- reviewed scripts under `deploy/scripts/`
- checked-in Helm values under `deploy/helm-values/`
- checked-in non-secret render templates under `deploy/manifests/ingress-bootstrap/`
- checked-in non-secret secret-sync templates and manifests under `deploy/manifests/secret-sync/`
- production render entry points under `deploy/scripts/render/`
- production reconciliation and apply entry points under `deploy/scripts/reconcile/`
- production release preparation and OCI apply entry points under `deploy/scripts/release/`
- the non-secret instance config template at `deploy/instance.env.template`

Runtime render output still belongs under `tmp/`, not under `deploy/`.

## Deployment Operating Model

The normal OCI production operation is a local desired-state preparation step,
human review, and an OCI-host apply step. The canonical terminology lives in
[docs/ci-cd.md](../docs/ci-cd.md).

```bash
# Local workstation
./deploy/scripts/release/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --plan-only
./deploy/scripts/release/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --push-tags

# After GitHub Actions publishes the expected GHCR tags
./deploy/scripts/release/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --resolve-images

# OCI host, after the orchestration diff is reviewed, committed, pushed, and pulled
./deploy/scripts/release/deploy-current-oci-manifest.sh
```

The local preparation command previews tag work against the checked-in
production image inventory. By default, it tags and resolves only artifacts
whose current source repository or source commit differs from the inventory,
while unchanged artifacts keep their existing digest-pinned images. Use
`--lockstep` when a coordinated release should force every managed artifact to
the requested source tag and Docker label. After the owning GitHub Actions
workflows publish the expected GHCR image tags, `--resolve-images` reads those
tags once, resolves immutable digests, updates the checked-in production
desired state, and stops for review. Missing GHCR image tags are a prerequisite
failure, not a retry loop. The local flow does not build Docker images, deploy
to OCI, or require OCI kubeconfig access. The OCI host command applies the
checked-in production manifest and fails if live pods do not match it.

`--resolve-images` uses the Docker Registry API with GHCR bearer tokens. Public
packages can resolve anonymously; private packages require `GHCR_USERNAME` and
`GHCR_TOKEN` with `read:packages` scope. GitHub SSH keys are not used by GHCR
image reads.

Every durable deployment state must remain repo-owned, repeatable, and
digest-pinned. `service-common` is released only when the shared Java libraries
change; do not bump it to force an unrelated OCI deployment.

The `ext-authz` image is sourced from the sibling `budgetanalyzer/ext-authz`
repository. During a release, its source tag can intentionally point at an
earlier commit than the later orchestration commit that records the reviewed
desired state.

## Script Layout

`deploy/scripts/` is grouped by lifecycle and mutation boundary:

- `bootstrap/` is the ordered OCI host and cluster bootstrap lane. These scripts
  keep numeric prefixes because they are intentionally run in sequence from
  k3s install through baseline NetworkPolicy apply.
- `secrets/` owns OCI Vault bootstrap, RabbitMQ definitions sync, External
  Secrets render/apply, and internal infrastructure TLS secret generation.
- `render/` produces reviewable non-secret artifacts under `tmp/` without
  applying them directly.
- `reconcile/` mutates the live cluster after the reviewed inputs are ready:
  infrastructure, monitoring, observability, and admission policy operations.
- `release/` owns local desired-state preparation and OCI application release
  helpers. The normal entry points are
  `release/prepare-oci-manifest-from-current-stack.sh` and
  `release/deploy-current-oci-manifest.sh`; the explicit baseline update and
  manifest replay helpers remain lower-level repair paths.
- `verify/` contains non-mutating or temporary-probe verifiers.
- `lib/` contains sourced implementation shared by the deployment scripts.

## Review And Run Order

1. Copy `deploy/instance.env.template` to `~/.config/budget-analyzer/instance.env` and fill in only the deployment-specific non-secret values.
2. Review the deployment scripts and checked-in values before running them on the OCI host.
3. Review the shared contract files:
   - `deploy/scripts/lib/version-contract.sh`
   - `deploy/scripts/lib/common.sh`
4. Review the pinned Helm values:
   - `deploy/helm-values/external-secrets.values.yaml`
   - `deploy/helm-values/cert-manager.values.yaml`
   - `deploy/helm-values/kyverno.values.yaml`
5. Review the k3s/Istio bootstrap render templates:
   - `deploy/manifests/ingress-bootstrap/ingress-gateway-config.yaml.template`
   - `deploy/manifests/ingress-bootstrap/istio-gateway.yaml.template`
   - `kubernetes/istio/cni-common-values.yaml`
   - `kubernetes/istio/cni-k3s-values.yaml`
   - `kubernetes/istio/istiod-values.yaml`
   - `kubernetes/istio/egress-gateway-values.yaml`
   - `kubernetes/istio/peer-authentication.yaml`
   - `kubernetes/production/istio/authorization-policies.yaml`
6. Review the secret synchronization artifacts:
   - `deploy/manifests/secret-sync/cluster-secret-store.yaml.template`
   - `deploy/manifests/secret-sync/external-secrets.yaml`
   - `deploy/manifests/secret-sync/session-gateway-idp-config.yaml.template`
   - `deploy/scripts/secrets/bootstrap-vault-secrets.sh`
   - `deploy/scripts/secrets/update-rabbitmq-definitions-secret.sh`
   - `deploy/scripts/secrets/render-secret-sync.sh`
   - `deploy/scripts/secrets/apply-secret-sync.sh`
   - `deploy/scripts/secrets/generate-infra-tls.sh`
7. Review the production render inputs:
   - `kubernetes/production/README.md`
   - `kubernetes/production/gateway-routes/kustomization.yaml`
   - `kubernetes/production/istio-ingress-policies/kustomization.yaml`
   - `kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
   - `kubernetes/production/infrastructure/kustomization.yaml`
   - `kubernetes/production/infrastructure/patches/redis-storage.yaml`
   - `deploy/scripts/render/production-routes.sh`
8. Review the production infrastructure operation scripts:
   - `deploy/scripts/render/production-infrastructure.sh`
   - `deploy/scripts/reconcile/production-infrastructure.sh`
9. Review the production observability rollout inputs:
   - `kubernetes/monitoring/jaeger/configmap.yaml`
   - `kubernetes/monitoring/jaeger/pvc.yaml`
   - `kubernetes/monitoring/jaeger/deployment.yaml`
   - `kubernetes/monitoring/jaeger/services.yaml`
   - `kubernetes/monitoring/kiali-values.yaml`
   - `scripts/ops/post-render-kiali-server.sh`
   - `deploy/scripts/render/observability.sh`
   - `deploy/scripts/reconcile/observability.sh`
   - `deploy/scripts/reconcile/production-monitoring.sh`
10. Review the production admission inputs:
   - `kubernetes/kyverno/README.md`
   - `kubernetes/kyverno/policies/00-smoke-disallow-privileged.yaml`
   - `kubernetes/kyverno/policies/10-require-namespace-pod-security-labels.yaml`
   - `kubernetes/kyverno/policies/20-require-workload-automount-disabled.yaml`
   - `kubernetes/kyverno/policies/30-require-workload-security-context.yaml`
   - `kubernetes/kyverno/policies/40-disallow-obvious-default-credentials.yaml`
   - `kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml`
   - `deploy/scripts/reconcile/install-kyverno.sh`
   - `deploy/scripts/reconcile/apply-admission-policies.sh`
11. Review the production desired-state preparation and OCI apply helpers:
   - `deploy/scripts/release/prepare-oci-manifest-from-current-stack.sh`
   - `deploy/scripts/release/deploy-current-oci-manifest.sh`
   - `deploy/scripts/release/update-production-release-images.sh`
   - `deploy/scripts/verify/oci-upgrade-lockstep.sh`
   - `deploy/scripts/release/deploy-oci-release.sh`
   - `docs/runbooks/oci-release-deployment-checklist.md`
   - `kubernetes/production/apps/deployment-manifest.yaml`
   - `kubernetes/production/apps/image-inventory.yaml`
   - `kubernetes/production/apps/kustomization.yaml`
   Run `deploy/scripts/release/prepare-oci-manifest-from-current-stack.sh --source-tag
   vX.Y.Z --plan-only` first to preview changed-artifact tag actions and
   expected GHCR image tags, then use `--push-tags` and wait for GitHub
   Actions before `--resolve-images` updates the checked-in desired state.
12. Note the current observability boundary before reviewing or running any
   later observability artifacts:
   - The production Prometheus/Grafana path is owned by
     `deploy/scripts/reconcile/production-monitoring.sh`.
   - The reviewed OCI rollout path for Jaeger and Kiali uses
     `deploy/scripts/render/observability.sh` and
     `deploy/scripts/reconcile/observability.sh`.
   - Production Grafana is internal-only and accessed with
     `kubectl port-forward`; the production route render does not publish a
     Grafana `HTTPRoute`.
   - Jaeger and Kiali use the same internal-only access model: both stay in
     `monitoring`, stay `ClusterIP`-only, and use loopback-bound
     `kubectl port-forward` instead of public routes.
   - Do not add Grafana, Kiali, or Jaeger public hostname inputs.
13. Run the human-owned cluster bootstrap scripts in this exact order:
   - `./deploy/scripts/bootstrap/01-install-k3s.sh`
   - `./deploy/scripts/bootstrap/02-bootstrap-cluster.sh`
   - `./deploy/scripts/bootstrap/03-render-ingress-bootstrap-manifests.sh`
   - `./deploy/scripts/bootstrap/04-install-istio.sh`
   - `./deploy/scripts/bootstrap/05-install-platform-controllers.sh`
   - `./deploy/scripts/bootstrap/06-apply-network-policies.sh`
   - `./deploy/scripts/verify/network-policy-enforcement.sh`

## Expected Inputs

`~/.config/budget-analyzer/instance.env` is the only required deployment input
file outside the repo. It holds non-secret deployment metadata:

- OCI tenancy, compartment, vault, instance, subnet, and region identifiers
- the instance public IP and SSH key path
- the public demo hostname
- the production non-secret Auth0/IDP settings used later to render `session-gateway-idp-config` and the Auth0 Istio egress config
- the Let's Encrypt contact email

Do not put secret payloads in `instance.env`. Secret values stay in OCI
Vault and later `ExternalSecret` resources. Generated application secrets,
including the transaction-service preview import token encryption secret, are
created by the Vault bootstrap script rather than added to
`deploy/instance.env.template`.

Only the non-secret IDP values belong here. `AUTH0_CLIENT_SECRET` still belongs in OCI Vault.

Do not duplicate production image refs in `instance.env`. Production image inventory stays in `kubernetes/production/apps/image-inventory.yaml`.

## Host Tooling Prerequisites

The deployment scripts assume the host already has `kubectl`, `helm`, OpenSSL,
and the standard shell tools used by the scripts.

- `./deploy/scripts/bootstrap/01-install-k3s.sh` writes
  `/etc/sysctl.d/90-budget-analyzer-inotify.conf` and applies the repo baseline
  for `fs.inotify.max_user_instances` and `fs.inotify.max_user_watches` before
  k3s starts or restarts. Rerun it after rebuilding a host or when
  `kubectl logs -f` reports fsnotify watcher exhaustion.
- `./deploy/scripts/bootstrap/04-install-istio.sh` and `./deploy/scripts/bootstrap/05-install-platform-controllers.sh` require `helm`.
- `./deploy/scripts/reconcile/install-kyverno.sh` requires `helm`.
- `./deploy/scripts/secrets/bootstrap-vault-secrets.sh` requires the OCI CLI plus `openssl`.
- `./deploy/scripts/secrets/update-rabbitmq-definitions-secret.sh` requires the OCI CLI.
- `./deploy/scripts/secrets/generate-infra-tls.sh` requires `openssl`.
- On a fresh OCI Ubuntu host, install the repo-pinned Helm build with `./scripts/bootstrap/install-verified-tool.sh helm`.
- Verify the install before rerunning the cluster bootstrap scripts: `helm version`

## Script Map

| Script | Purpose | Reused Later |
| --- | --- | --- |
| `deploy/scripts/bootstrap/01-install-k3s.sh` | Installs the pinned k3s release with the repo's Istio-friendly flags, converges the host inotify budget for reliable k3s/containerd log-follow streaming, and prints the base cluster snapshot. | Re-run if the host must be rebuilt, reconciled to the pinned k3s version, or repaired after `kubectl logs -f` reports fsnotify watcher exhaustion. |
| `deploy/scripts/bootstrap/02-bootstrap-cluster.sh` | Installs the pinned Gateway API CRDs and creates or labels every namespace the deployment path depends on. | Re-run after a cluster rebuild or if namespace labels drift. |
| `deploy/scripts/bootstrap/03-render-ingress-bootstrap-manifests.sh` | Renders the ingress ConfigMap and host-agnostic HTTP Gateway into `tmp/ingress-bootstrap/`. | Re-run before public TLS adds the TLS listener or whenever the reviewed ingress render output changes. |
| `deploy/scripts/bootstrap/04-install-istio.sh` | Refreshes the rendered ingress output, installs `istio-base`, installs `istio-cni` with the common values plus k3s overlay, installs `istiod`, installs the egress gateway, then applies the rendered ingress manifests plus the shared `PeerAuthentication` baseline and the OCI-specific `AuthorizationPolicy` baseline. The OCI authz baseline intentionally omits `budget-analyzer-web-policy` because production serves the frontend from `nginx-gateway`. The script now refuses to continue when the live cluster already exposes the public TLS path unless you pass `--acknowledge-public-tls-downgrade`, because the ingress bootstrap reconcile is intentionally HTTP-only. | Re-run after changing Istio pins, values, the rendered ingress manifests, or the OCI authz baseline. If the host already completed the public TLS cutover, pass `--acknowledge-public-tls-downgrade` only when you intend to reapply the public TLS ingress manifests immediately after the Istio reconcile. |
| `deploy/scripts/bootstrap/05-install-platform-controllers.sh` | Installs External Secrets Operator and cert-manager from the pinned charts and checked-in values. The script logs Helm repo-update vs install stages separately, waits up to `10m` per release, dumps `helm status`, workloads, and recent namespace events if either install fails, and accepts `PHASE4_PLATFORM_CONTROLLERS=cert-manager`, `external-secrets`, or `all` (default). | Re-run when secret synchronization or public TLS needs controller value changes. For the public TLS cert-manager solver refresh path, use `PHASE4_PLATFORM_CONTROLLERS=cert-manager`. |
| `deploy/scripts/bootstrap/06-apply-network-policies.sh` | Applies the checked-in NetworkPolicy manifests after namespaces and controllers exist. | Re-run after policy edits or after rebuilding the cluster. |
| `deploy/scripts/verify/network-policy-enforcement.sh` | Creates disposable probe/listener pods and proves the checked-in allow/deny contract against the live k3s NetworkPolicy implementation. | Re-run after policy edits, CNI changes, or any cluster rebuild before treating NetworkPolicy enforcement as verified. |
| `deploy/scripts/secrets/render-secret-sync.sh` | Renders the OCI `ClusterSecretStore`, the exact `ExternalSecret` inventory, and the production `session-gateway-idp-config` into `tmp/secret-sync/`, including the transaction-service preview import token credentials sync target. | Re-run after any `instance.env` update that changes Vault identifiers or non-secret Auth0/IDP values, or after checked-in `ExternalSecret` inventory changes. |
| `deploy/scripts/secrets/apply-secret-sync.sh` | Refreshes the secret-sync render output, then applies the `ClusterSecretStore`, production IDP `ConfigMap`, and the full `ExternalSecret` set. | Re-run after IAM propagation, Vault secret inventory changes, checked-in `ExternalSecret` inventory changes, or any `instance.env` change that affects the rendered resources. |
| `deploy/scripts/secrets/generate-infra-tls.sh` | Generates the private `infra-ca` plus the PostgreSQL, Redis, and RabbitMQ server keypairs outside the repo, refuses container/AI-workspace execution, and applies the expected TLS Secret objects. | Re-run to restore the internal TLS secrets, or pass `--rotate` when intentionally replacing the CA and service certificates. |
| `deploy/scripts/secrets/bootstrap-vault-secrets.sh` | Creates the OCI Vault secrets for Auth0, FRED, PostgreSQL, RabbitMQ, Redis, and generated application secrets such as `budget-analyzer-transaction-preview-import-token-encryption-secret`. The generated secret material is written to an operator-only file outside the repo so the RabbitMQ definitions secret can be rendered afterward; existing OCI Vault values are hydrated back into that file on rerun. | Re-run to create any missing plain-text vault secrets. Existing OCI secrets are left unchanged, and the generated secret receipt file is reconciled from Vault before RabbitMQ definitions are rendered. |
| `deploy/scripts/secrets/update-rabbitmq-definitions-secret.sh` | Renders the checked-in RabbitMQ definitions template with the generated RabbitMQ passwords, validates the `exchange-rate.import.requested` contract, and creates or updates the OCI Vault `budget-analyzer-rabbitmq-definitions` secret. | Run after `deploy/scripts/secrets/bootstrap-vault-secrets.sh` and before applying secret sync when RabbitMQ destinations or permissions change. |
| `deploy/scripts/render/production-routes.sh` | Renders the reviewed production application gateway routes, ingress policies, production Grafana port-forward override, and Auth0-derived Istio egress manifests into `tmp/production-routes/` for operator review before live apply. | Re-run after changing the reviewed production overlay files or the non-secret production `AUTH0_ISSUER_URI`. |
| `deploy/scripts/reconcile/install-kyverno.sh` | Creates or relabels the `kyverno` namespace, then installs the pinned Kyverno chart with the checked-in production values. | Re-run after changing the Kyverno chart pin or `deploy/helm-values/kyverno.values.yaml`, or after rebuilding the cluster. |
| `deploy/scripts/reconcile/apply-admission-policies.sh` | Runs the repo-owned production image verifier, then applies the shared admission policies plus the production-only image-digest variant. | Re-run after changing any `kubernetes/kyverno/policies/*.yaml`, the production `50-...` variant, or the checked-in production image baseline. |
| `deploy/scripts/render/public-tls.sh` | Renders the reviewed public TLS artifacts into `tmp/public-tls/`, including the Let's Encrypt `ClusterIssuer`, the app `Certificate`, the `ReferenceGrant`, and the `80/443` ingress Gateway manifests. | Re-run before the app TLS cutover or whenever the reviewed public hostname/TLS contract changes. |
| `deploy/scripts/render/production-infrastructure.sh` | Renders `kubernetes/production/infrastructure` with Kustomize load restrictions disabled into `tmp/production-infrastructure/infrastructure.yaml` for review. | Re-run before applying infrastructure, after changing the shared infrastructure baseline, or after changing the production Redis storage patch. |
| `deploy/scripts/reconcile/production-infrastructure.sh` | Refreshes the production infrastructure render, applies it to the current cluster, and waits for PostgreSQL, RabbitMQ, and Redis StatefulSets when present. | Re-run on a new or already migrated cluster, or after infrastructure manifest changes. |
| `deploy/scripts/render/observability.sh` | Copies the reviewed Jaeger manifests and renders the pinned Kiali Helm output into `tmp/observability/` for operator review using a Helm server-side dry run, so the reviewed Kiali RBAC matches the live namespace-scoped install footprint. | Re-run before live Jaeger/Kiali install, after changing shared Jaeger manifests, or after changing the Kiali values/post-renderer contract. |
| `deploy/scripts/reconcile/observability.sh` | Reruns the production static verifier, refreshes the reviewed observability render, applies the shared Jaeger manifests, installs Kiali from the pinned chart and values, waits for both Deployments, and fails if any stale observability `HTTPRoute` still exists. | Re-run on a new or existing OCI cluster after changing the Jaeger manifests, the Kiali values/post-renderer, or the production observability contract. |
| `deploy/scripts/reconcile/production-monitoring.sh` | Idempotently reapplies the production monitoring stack: the Prometheus/Grafana Helm baseline, Grafana dashboard ConfigMap, Spring Boot ServiceMonitor, and by default the existing Jaeger/Kiali apply path. | Re-run on OCI after monitoring values, dashboards, ServiceMonitors, Jaeger/Kiali manifests, or observability access contracts change. Use `--skip-jaeger-kiali` for a Prometheus/Grafana-only refresh and `--verify-runtime` to run the dashboard input verifier. |
| `deploy/scripts/release/prepare-oci-manifest-from-current-stack.sh` | Normal local OCI desired-state preparation entry point. It requires clean source workspaces, compares current artifact source state with the production image inventory, previews changed-artifact tag actions with `--plan-only`, creates and pushes missing `vX.Y.Z` source tags for changed artifacts with `--push-tags`, and reads already-published GHCR tags with `--resolve-images` to resolve digests, write a complete desired-state manifest, update the production image inventory, release metadata, runtime metadata patch, and app overlay, then stop for review. Use `--lockstep` only when every managed artifact must move to the requested tag. | Run from the local workstation before an OCI deployment. Missing GHCR image tags are a prerequisite failure in `--resolve-images`; wait for GitHub Actions manually instead of leaving the script in a polling loop. |
| `deploy/scripts/release/deploy-current-oci-manifest.sh` | Normal OCI-host apply entry point. It applies the checked-in production manifest, validates manifest/inventory agreement, runs the static gate, applies the managed production app set with selective workload rollout, waits only for changed deployments, and verifies live runtime metadata against the checked-in manifest while allowing unchanged pods to retain an earlier deployment id. | Run on the OCI host after the reviewed orchestration desired-state diff has been pulled. |
| `deploy/scripts/release/update-production-release-images.sh` | Lower-level renderer used by the preparation command. It updates the checked-in production deployment baseline from a complete schema v2 desired-state manifest, regenerates `/api-docs/release-metadata.json` and the runtime metadata patch, copies the reviewed manifest into `kubernetes/production/apps/deployment-manifest.yaml`, then runs the static agreement gate. | Use directly only when repairing the checked-in baseline from an already complete desired-state manifest. Java artifacts must carry `service_common_version`. |
| `deploy/scripts/verify/oci-upgrade-lockstep.sh` | Runs non-mutating static checks that local Tilt chart pins match OCI version contracts; production deployment manifest, image inventory, app kustomization, runtime metadata patch, and release metadata agree; production `/api-docs` render wiring remains intact; and production infrastructure and Helm values keep digest-pin inputs. | Run before tagging or deploying an OCI release, and after any platform, app image, monitoring, production render, or config-only deployment change. |
| `deploy/scripts/release/deploy-oci-release.sh` | Lower-level OCI desired-state applier. It requires a schema v2 `--deployment-manifest`, validates it against the checked-in production baseline, runs the static gate, captures pre/post cluster snapshots, applies the managed production app set with selective workload rollout, waits only for changed deployments, and verifies live pods against the manifest while allowing unchanged pods to retain an earlier deployment id. | Use directly only when replaying an explicit reviewed desired-state manifest. |

External Secrets Operator values intentionally leave service account token
automount enabled for the controller, webhook, and cert-controller pods. Those
controllers need in-cluster Kubernetes API credentials for watches, leader
election, admission webhook serving, and certificate reconciliation.

## Istio Setup Checkpoint

If you are resuming at the Istio setup checkpoint, use this section instead of
re-reading shell history:

1. Confirm the prerequisite namespaces exist and `~/.config/budget-analyzer/instance.env` is present.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   kubectl get namespace \
     default infrastructure monitoring istio-system istio-ingress istio-egress external-secrets cert-manager
   ```
2. Render the reviewed ingress manifests into `tmp/ingress-bootstrap/`.
   ```bash
   ./deploy/scripts/bootstrap/03-render-ingress-bootstrap-manifests.sh
   sed -n '1,220p' tmp/ingress-bootstrap/ingress-gateway-config.yaml
   sed -n '1,220p' tmp/ingress-bootstrap/istio-gateway.yaml
   ```
3. Run the mesh install script. It covers the remaining human-owned Chunk 3 work in order.
   ```bash
   ./deploy/scripts/bootstrap/04-install-istio.sh
   ```
4. Verify the control plane, egress gateway, and ingress gateway before continuing.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   helm list -n istio-system
   helm list -n istio-egress
   kubectl get gateway -n istio-ingress
   kubectl get svc -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway
   kubectl get peerauthentication,authorizationpolicy -n default
   ```
5. Stop if the ingress `Gateway` is not `Programmed`, if the auto-provisioned Service does not expose port `80`/nodePort `30080`, or if `PeerAuthentication/default-strict` is missing from `default`.

## Network Policy Checkpoint

If you are resuming at the NetworkPolicy checkpoint, verify the ingress,
controller, and host-networking prerequisites before applying policy changes.
Rerun `./deploy/scripts/verify/network-policy-enforcement.sh` after the
real Auth0-derived egress config is applied.

1. Reconfirm the Chunk 3 ingress state and the shared controller-install result before starting Step 19.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   kubectl get gateway -n istio-ingress
   kubectl get svc -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway
   helm list -n external-secrets
   helm list -n cert-manager
   ```
2. If you are rebuilding or reconciling the host, rerun the shared controller-install script once and verify both controllers before continuing.
   ```bash
   ./deploy/scripts/bootstrap/05-install-platform-controllers.sh
   kubectl get pods -n external-secrets
   kubectl get pods -n cert-manager
   ```
3. The host-redirect experiment from the 2026-04-16 OCI debugging thread is historical only and is no longer retained as an executable path.
4. If you are rebuilding or reconciling the environment, make sure any stale host redirects, debug-only `INPUT` rules, and direct-instance public `80/443` exposure are gone before creating the NLB.
   ```bash
   while sudo iptables -C INPUT -p tcp --dport 30080 -j ACCEPT 2>/dev/null; do
     sudo iptables -D INPUT -p tcp --dport 30080 -j ACCEPT
   done
   while sudo iptables -C INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT 2>/dev/null; do
     sudo iptables -D INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT
   done
   while sudo iptables -C INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT 2>/dev/null; do
     sudo iptables -D INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT
   done
   while read -r rule; do
     [[ -n "${rule}" ]] || continue
     sudo iptables -t nat ${rule}
   done < <(
     sudo iptables -t nat -S PREROUTING | awk '
       $1 == "-A" && $2 == "PREROUTING" &&
       ($0 ~ /--dport 80 / || $0 ~ /--dport 443 /) &&
       $0 ~ /-j REDIRECT/ {
         sub(/^-A /, "-D ")
         print
       }
     '
   )
   sudo netfilter-persistent save
   sudo iptables -t nat -S PREROUTING
   ```
5. The reviewed ingress gateway config sets `externalTrafficPolicy: Local`, and the rationale remains documented in [ADR 008](../docs/decisions/008-oci-public-ingress-via-nlb.md).
6. Step 19: create the public OCI Network Load Balancer for the current ingress NodePort.
   - For the HTTP listener bootstrap, create one TCP listener on `80`, point it at the instance backend on `30080`, and configure the backend set in source-IP-preserving mode.
   - OCI operator note: the frontend NSG also needs a stateful egress rule to the backend NSG on TCP `30080`; otherwise the NLB backend health check stays critical and the listener never forwards traffic.
   - Add a TCP health check against `30080`.
7. Step 20: prove only the NLB path can reach the ingress NodePort and that the backend still sees the real workstation client IP.
   ```bash
   sudo tcpdump -ni any 'tcp port 30080'
   ```
8. Step 21a: apply the checked-in NetworkPolicy manifests.
   ```bash
   ./deploy/scripts/bootstrap/06-apply-network-policies.sh
   kubectl get networkpolicy -A
   ```
9. Step 21b: run the runtime NetworkPolicy verifier.
   ```bash
   ./deploy/scripts/verify/network-policy-enforcement.sh
   ```
10. Before production Auth0 config exists, the verifier's two positive checks to `istio-egress-gateway:443` may fail because the bootstrap path intentionally does not apply placeholder egress routing. If those are the only failures, record the output and continue to secret synchronization. Do not accept any other failure at this step.
11. After the real egress config is rendered and applied from the production `AUTH0_ISSUER_URI`, rerun `./deploy/scripts/verify/network-policy-enforcement.sh` and require those two `istio-egress-gateway:443` checks to pass.

## Deployment Boundary Notes

`deploy/scripts/bootstrap/03-render-ingress-bootstrap-manifests.sh` intentionally renders an HTTP-only `Gateway` with a single host-agnostic listener and omits `spec.listeners[].hostname`. That keeps the checked-in localhost `HTTPRoute` manifests attachable during bootstrap while still leaving room for later host-specific route renders and ACME HTTP-01 challenge routes. Public certificate issuance and the final HTTPS listener secret wiring stay in the public TLS cutover.

The rejected host-redirect experiment from the 2026-04-16 OCI debugging thread is retained only as operational context. That run proved that `nat/PREROUTING REDIRECT` to the ingress NodePort did not become a real NodePort service flow on this host, and it did not satisfy the requirement to preserve the original client IP at the ingress gateway. Do not recreate that experiment during the normal forward path. If the host still carries any mutations from that experiment, host cleanup and OCI-networking rollback are mandatory before the steady-state OCI Network Load Balancer plus `externalTrafficPolicy: Local` path begins.

The bootstrap ingress path stays HTTP-only even after the NLB pivot. The public
NLB needs only the listener and backend path for port `80 -> 30080` until the
public TLS cutover. The instance itself should no longer accept direct public
`80/443` traffic once the NLB path exists. The public TLS cutover adds the
HTTPS listener, the `30443` backend path, and the matching certificate/TLS
wiring.

Because `deploy/scripts/bootstrap/04-install-istio.sh` reapplies that HTTP-only
ingress bootstrap baseline, it now blocks by default when the live cluster already
exposes the public TLS `443 -> 30443` listener. Use
`--acknowledge-public-tls-downgrade` only for an intentional Istio reconcile on
an already-cut-over host, then immediately rerender and reapply the public TLS
manifests.

On OCI, the public listener path also needs the frontend NSG to egress to the backend NSG on TCP `30080`. The 2026-04-16 operator run needed that explicit rule before the backend health check on `30080` would turn healthy.

The checked-in ingress NetworkPolicy allow list must continue to admit the
HTTP listener so ACME HTTP-01 reachability is not cut off when
`deploy/scripts/bootstrap/06-apply-network-policies.sh` runs. The repo now includes a
narrow solver-only path for that purpose: the `istio-ingress` gateway may
egress to labeled cert-manager HTTP-01 solver Pods in `default` on TCP `8089`,
those solver Pods admit ingress only from the gateway, and they may egress to
`istiod` on TCP `15012` so the injected sidecar can join the mesh.

The runtime NetworkPolicy verifier intentionally runs before production Auth0
config exists. Because the deployment path explicitly defers placeholder Istio
egress routing, a pre-Auth0 OCI host can legitimately miss the verifier's two
positive `istio-egress-gateway:443` checks while still proving the rest of the
CNI contract. Treat those two checks as deferred only, and rerun the verifier
after the rendered egress config from the real `AUTH0_ISSUER_URI` is applied.

## Secret Synchronization Checkpoint

If you are moving directly from the OCI cluster bootstrap into secret
synchronization, use this checkpoint instead of reconstructing commands from
shell history:

1. Confirm the non-secret operator config is populated and the reviewed secret-sync artifacts are present.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   grep -E '^(OCI_REGION|OCI_COMPARTMENT_OCID|AUTH0_CLIENT_ID|AUTH0_ISSUER_URI|IDP_AUDIENCE|IDP_LOGOUT_RETURN_TO)=' \
     ~/.config/budget-analyzer/instance.env
   ls deploy/manifests/secret-sync deploy/scripts/secrets/render-secret-sync.sh \
     deploy/scripts/secrets/apply-secret-sync.sh deploy/scripts/secrets/generate-infra-tls.sh
   ```
   `OCI_COMPARTMENT_OCID` is the compartment that contains the deployment
   vault, key, and secrets. If you are using the tenancy root compartment for those
   resources, `OCI_COMPARTMENT_OCID` should equal `OCI_TENANCY_OCID`.
2. Review the checked-in secret-sync artifacts first. Do not run the render step yet if the OCI vault/key work is still pending.
   ```bash
   sed -n '1,220p' deploy/manifests/secret-sync/cluster-secret-store.yaml.template
   sed -n '1,260p' deploy/manifests/secret-sync/external-secrets.yaml
   sed -n '1,220p' deploy/manifests/secret-sync/session-gateway-idp-config.yaml.template
   sed -n '1,260p' deploy/scripts/secrets/bootstrap-vault-secrets.sh
   sed -n '1,260p' deploy/scripts/secrets/update-rabbitmq-definitions-secret.sh
   sed -n '1,220p' deploy/scripts/secrets/render-secret-sync.sh
   sed -n '1,220p' deploy/scripts/secrets/apply-secret-sync.sh
   sed -n '1,260p' deploy/scripts/secrets/generate-infra-tls.sh
   ```
3. After the OCI vault/key exists and `~/.config/budget-analyzer/instance.env` includes `OCI_VAULT_OCID`, populate the plain-text vault secrets and then render the reviewed secret-sync artifacts.
   ```bash
   set -euo pipefail
   ./deploy/scripts/secrets/bootstrap-vault-secrets.sh
   ./deploy/scripts/secrets/update-rabbitmq-definitions-secret.sh
   ./deploy/scripts/secrets/render-secret-sync.sh
   sed -n '1,220p' tmp/secret-sync/cluster-secret-store.yaml
   sed -n '1,260p' tmp/secret-sync/external-secrets.yaml
   sed -n '1,220p' tmp/secret-sync/session-gateway-idp-config.yaml
   ```
   The script generates `budget-analyzer-transaction-preview-import-token-encryption-secret`
   for the transaction-service preview import token flow. That is an OCI Vault
   application secret, not a `deploy/instance.env.template` value.

   The RabbitMQ definitions script renders
   `deploy/manifests/secret-sync/rabbitmq-definitions.template.json` with the
   generated or Vault-hydrated RabbitMQ passwords from
   `~/.local/share/budget-analyzer/vault-secrets/secret-sync-generated-secrets.env`
   and writes the rendered secret payload outside the repo. The template is the
   checked-in allow-list for the `currency-service` AMQP resources. It
   currently grants `exchange-rate.import.requested`,
   `exchange-rate.import.requested.exchange-rate-import-service`, its DLQ,
   server-named reply queues, `amq.default`, and `DLX`. The service queue and
   DLQ must be present in `write` as well as `configure` and `read`, because
   RabbitMQ checks `write` permission during queue declaration. `DLX` must also
   be present in `read`, because RabbitMQ checks `read` on the source exchange
   during DLQ binding.
4. After the OCI vault, dynamic group, policy, and secret inventory exist and IAM propagation has had time to settle, apply the reviewed secret-sync path on the OCI instance.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ./deploy/scripts/secrets/apply-secret-sync.sh
   kubectl get clustersecretstore budget-analyzer-oci-vault
   kubectl get externalsecret -A
   kubectl get externalsecret -n default transaction-service-preview-import-token-credentials
   kubectl get secret -n default transaction-service-preview-import-token-credentials
   kubectl get configmap -n default session-gateway-idp-config -o yaml
   ```
5. Generate and apply the internal TLS secrets from the OCI host or another trusted machine outside AI sessions.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ./deploy/scripts/secrets/generate-infra-tls.sh
   ```
   The script writes the CA and service keypairs under `~/.local/share/budget-analyzer/infra-tls` by default, keeps them outside the repo, and refuses to run from the containerized AI workspace.
6. Stop if any `ExternalSecret` reports sync errors, if
   `transaction-service-preview-import-token-credentials` is missing before a
   transaction-service image that requires
   `PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET` is deployed, if
   `session-gateway-idp-config` still shows placeholder/localhost values, or if
   any of `infra-ca`, `infra-tls-postgresql`, `infra-tls-redis`, or
   `infra-tls-rabbitmq` are missing.

## Production Render Review

The repo-owned production render path must be reviewed before any production
gateway or egress objects are applied:

```bash
./deploy/scripts/render/production-routes.sh
sed -n '1,260p' tmp/production-routes/gateway-routes.yaml
sed -n '1,220p' tmp/production-routes/istio-ingress-policies.yaml
sed -n '1,120p' tmp/production-routes/prometheus-stack-values.override.yaml
sed -n '1,260p' tmp/production-routes/istio-egress.yaml
rg -n 'budgetanalyzer\\.localhost|auth0-issuer\\.placeholder\\.invalid' \
  kubernetes/production tmp/production-routes
```

The production apps overlay no longer applies the checked-in fallback
`session-gateway-idp-config`. Keep the production non-secret IDP ConfigMap
owned by the secret-sync render/apply path, then apply the rendered route and
egress output separately during the live deployment.

Before any live production policy or route/egress apply step, run the
repo-owned production verifier against the checked-in baseline:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

That command renders the production app overlay, the broad production
infrastructure overlay, and the reviewed
route/ingress/monitoring/egress output using the locked production hostnames. It
fails on localhost hosts, placeholder Auth0 values, mutable image refs,
`imagePullPolicy: Never`, the old standalone Redis PVC shape, or a production
route that falls back to `nginx/nginx.k8s.conf`.

The production infrastructure target is now
`kubernetes/production/infrastructure/`. It reuses the shared infrastructure
baseline for PostgreSQL, RabbitMQ, and Redis, and patches the Redis
StatefulSet's `redis-data` claim template to request `5Gi`. Render it for
review with:

```bash
./deploy/scripts/render/production-infrastructure.sh
sed -n '1,260p' tmp/production-infrastructure/infrastructure.yaml
```

On a new or already migrated cluster, apply that rendered target with:

```bash
./deploy/scripts/reconcile/production-infrastructure.sh
```

Both production infrastructure scripts are safe to rerun. The render script
overwrites the review artifact under `tmp/production-infrastructure/`, and the
apply script refreshes that render before applying it and waiting for the
StatefulSets that are present.

The old production-only Redis Deployment/PVC overlay is superseded, and the
one-time migration to the shared Redis StatefulSet baseline has been completed.
Do not reintroduce the old standalone Redis Deployment or PVC. New or already
migrated OCI clusters should use the normal production infrastructure render
and apply scripts above; the apply script waits for Redis when the StatefulSet
is present. If an unexpected host still has the pre-StatefulSet Redis shape,
treat that as incident recovery: confirm the desired data-retention posture,
delete only the obsolete Redis Deployment and standalone `redis-data` PVC, apply
`./deploy/scripts/reconcile/production-infrastructure.sh`, verify Redis with a
TLS `PING` from `redis-0`, and roll Redis clients only if reconnect behavior
needs a forced reset.

For monitoring, keep the Helm release name `prometheus-stack` when
kube-prometheus-stack is installed. The checked-in production override at
`kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
assumes that release name so Grafana stays reachable through the existing
`prometheus-stack-grafana` Service used by the loopback port-forward contract.
Use `scripts/ops/post-render-prometheus-stack.sh` for every production Helm
install or upgrade so the Prometheus Operator keeps the repo-owned
least-privilege RBAC split instead of the chart's default broad cluster role.

For Jaeger and Kiali, use the repo-owned observability render/apply path
instead of one-off `kubectl` or `helm` commands:

```bash
./deploy/scripts/render/observability.sh
sed -n '1,220p' tmp/observability/jaeger-deployment.yaml
sed -n '1,260p' tmp/observability/kiali.yaml

./deploy/scripts/reconcile/observability.sh
```

The render step keeps the exact OCI Jaeger manifests and rendered Kiali output
reviewable under `tmp/observability/`. It uses a Helm server-side dry
run against the live cluster so `kiali.yaml` includes the full
namespace-scoped `Role`/`RoleBinding` footprint that production will install.
The apply step refreshes that artifact, applies the shared Jaeger manifests
unchanged, installs the same `kiali/kiali-server` `2.24.0` chart version with
the same pinned values and post-renderer used locally, waits for
`Deployment/jaeger` plus `Deployment/kiali`, and aborts if any stale
observability `HTTPRoute` still exists.

## Public TLS Cutover

The repo-owned render path for the public TLS cutover is:

```bash
./deploy/scripts/render/public-tls.sh
sed -n '1,220p' tmp/public-tls/cluster-issuer.yaml
sed -n '1,220p' tmp/public-tls/public-certificate.yaml
sed -n '1,220p' tmp/public-tls/reference-grant.yaml
sed -n '1,220p' tmp/public-tls/ingress-gateway-config.yaml
sed -n '1,260p' tmp/public-tls/istio-gateway.yaml
```

The current forward-path public TLS contract remains locked to:

- `demo.budgetanalyzer.org`

Grafana, Kiali, and Jaeger do not belong on the public TLS surface.
Keep observability off the new public DNS/TLS path while the internal-only
redesign remains pending.

Do not move the live app to the apex domain during public TLS cutover unless
the production hostname contract is reviewed and changed first. For the current
repo state, the apex `budgetanalyzer.org` is best handled as an optional
forwarding target to `demo.budgetanalyzer.org`, not as the direct app origin.

The ACME HTTP-01 path now depends on the reviewed cert-manager and
Kyverno compatibility contract in-repo:

- `deploy/helm-values/cert-manager.values.yaml` pins the chart-managed
  `acmesolver` image by digest so the temporary solver Pod can pass the
  production image policy even though it runs in `default`.
- `deploy/manifests/public-tls/cluster-issuer.yaml.template` labels the temporary
  solver Pod and applies the strongest pod-level security context the
  cert-manager Gateway solver API exposes.
- `kubernetes/kyverno/policies/30-require-workload-security-context.yaml`
  keeps the normal container-level checks for repo-managed workloads but makes a
  narrow exception for only those labeled solver Pods because cert-manager does
  not let this repo declare `allowPrivilegeEscalation=false` or
  `capabilities.drop=["ALL"]` on them.
- `kubernetes/network-policies/default-allow.yaml` and
  `kubernetes/network-policies/istio-ingress-allow.yaml` now include the
  matching narrow NetworkPolicy allowances for the temporary solver Pod path:
  gateway -> solver on TCP `8089`, solver -> `istiod` on TCP `15012`, and no
  broader default-namespace exception.

If your OCI cluster predates that contract change, re-run only the cert-manager
portion before retrying public certificate issuance so the live cert-manager
release picks up the digest-pinned solver image:

```bash
PHASE4_PLATFORM_CONTROLLERS=cert-manager ./deploy/scripts/bootstrap/05-install-platform-controllers.sh
./deploy/scripts/bootstrap/06-apply-network-policies.sh
```

If that rerun appears to stall, read the last emitted phase line first:

- `updating Helm repo external-secrets` or `updating Helm repo jetstack` means the host is still fetching chart metadata.
- `installing External Secrets Operator ... (timeout 10m)` or `installing cert-manager ... (timeout 10m)` means Helm is waiting for the selected release resources to become ready.
- On failure, the script now prints `helm status`, controller workloads, and recent namespace events for `external-secrets` and `cert-manager` automatically.

For the OCI `443 -> 30443` public TLS cutover, treat the NLB security rules as
required setup, not optional troubleshooting:

- the frontend NSG on the public NLB needs a stateful ingress rule allowing
  `0.0.0.0/0` to TCP `443`
- that same frontend NSG needs a stateful egress rule to the instance-attached
  backend NSG on TCP `30443`
- the backend NSG on the instance VNIC needs a stateful ingress rule allowing
  the frontend NSG to TCP `30443`
- the `30443` backend set health check must stay `TCP` on port `30443`

Without that frontend-egress plus backend-ingress pair, the HTTPS backend set
can sit in `Critical` even when the Kubernetes `Gateway`, TLS secret, and
certificate are all healthy.

## Observability Boundary

- `kube-prometheus-stack` with Helm release
  `prometheus-stack` remains the production metrics baseline.
- Reapply the full internal monitoring stack with
  `./deploy/scripts/reconcile/production-monitoring.sh`; pass
  `--verify-runtime` when you want the script to also prove the Spring
  Boot/Grafana dashboard inputs after the rollout. That path also keeps the
  Prometheus Operator on the repo-owned RBAC post-renderer.
- Production Grafana has no public `HTTPRoute` in the production-route render.
  Production Prometheus also stays internal-only. Use the shared loopback-bound
  operator contract documented in
  [../docs/architecture/observability.md](../docs/architecture/observability.md)
  instead of maintaining a second command inventory here.
- The reviewed OCI rollout path for Jaeger and Kiali uses
  `./deploy/scripts/render/observability.sh` for review and
  `./deploy/scripts/reconcile/observability.sh` for the live install.
- Jaeger and Kiali follow that same internal-only loopback model; use the
  canonical commands and helper scripts from
  [../docs/architecture/observability.md](../docs/architecture/observability.md).
- For workstation access, start those Kubernetes port-forwards on the OCI host
  first, then run
  `./scripts/ops/start-observability-ssh-tunnels.sh <oci-host>` locally. The
  helper also accepts `OCI_INSTANCE_IP` when the argument is omitted, assumes
  `ubuntu` and `~/.ssh/oci-budgetanalyzer`, and opens only loopback-bound SSH
  tunnels for `3300`, `9090`, `16686`, and `20001`.
- Keep observability port-forwards bound to `127.0.0.1`; do not use `--address 0.0.0.0`.
- When updating a live instance from an older render, explicitly delete any
  stale observability routes because `kubectl apply` does not prune removed
  kustomize resources:
  `kubectl delete httproute -n monitoring grafana-route prometheus-route kiali-route jaeger-route --ignore-not-found`.
- Keep Prometheus, Jaeger, and Kiali internal-only on the same reviewed
  loopback port-forward model.
- Do not introduce `grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, or
  `jaeger.budgetanalyzer.org` as public production hostnames.

## Production Admission Policy

The repo-owned production install/apply path is checked in. Review the
checked-in Kyverno values and policy inventory first. The production values now
pin every rendered Kyverno controller and hook image by digest rather than
inheriting chart-default tags:

Re-run the production policy install/apply steps when you change the Kyverno
values, the policies, or rebuild the OCI cluster.

```bash
sed -n '1,240p' deploy/helm-values/kyverno.values.yaml
sed -n '1,220p' deploy/scripts/reconcile/install-kyverno.sh
sed -n '1,220p' deploy/scripts/reconcile/apply-admission-policies.sh
sed -n '1,220p' kubernetes/kyverno/README.md
find kubernetes/kyverno/policies -maxdepth 2 -type f | sort
```

Then install the controller with the pinned chart and checked-in values:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
./deploy/scripts/reconcile/install-kyverno.sh
kubectl get namespace kyverno --show-labels
kubectl get deployments,pods -n kyverno
```

Expected install output:
- the upstream chart warns when `admissionController.replicas=1`; that is intentional for the current single-node OCI target and does not require a repo change
- the upstream chart warns that PolicyExceptions are disabled; that is also intentional unless you plan to manage explicit `PolicyException` resources
- Kubernetes unknown-field warnings are not expected; treat them as a values/render issue that should be fixed before treating the install output as clean

Before applying the production policy set, rerun the repo-owned production
verifier against the checked-in image/render baseline. The policy apply script
does this automatically and then applies exactly the shared `00` through `40`
policies plus `kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml`, then verifies the live
`phase7-require-third-party-image-digests` resource no longer contains the
local Tilt/latest exception rules:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
./deploy/scripts/reconcile/apply-admission-policies.sh
kubectl get clusterpolicy
```

Stop if the production verifier fails, if any Kyverno controller deployment is
unavailable, or if `phase7-require-third-party-image-digests` in the live
cluster does not come from the production variant.

## Validation Standard

Every committed shell script under `deploy/scripts/` must pass:

- `bash -n <script>`
- `shellcheck -x <script>`

The render paths must also be provable locally with sample non-secret input so
reviewers can inspect generated YAML under `tmp/ingress-bootstrap/`, `tmp/secret-sync/`, and
`tmp/production-routes/`.
