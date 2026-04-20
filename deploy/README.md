# Oracle Cloud Deployment Path

This directory is the committed, operator-facing install surface for the Oracle
Cloud deployment path. k3s/Istio bootstrap, secret synchronization,
production rendering, infrastructure render/apply/migration, public TLS, and
production Kyverno install/apply operations all have first-class, reviewable
artifacts here so a human can inspect the exact cluster mutations before
touching the OCI instance or Vault.

`deploy/` contains only repeatable Pattern B artifacts:

- reviewed scripts under `deploy/scripts/`
- checked-in Helm values under `deploy/helm-values/`
- checked-in non-secret render templates under `deploy/manifests/phase-4/`
- checked-in non-secret secret-sync templates and manifests under `deploy/manifests/phase-5/`
- the production render entry point under `deploy/scripts/`
- the production infrastructure render/apply and guarded Redis migration entry points under `deploy/scripts/`
- the production Kyverno install/apply entry points under `deploy/scripts/`
- the non-secret instance config template at `deploy/instance.env.template`

Runtime render output still belongs under `tmp/`, not under `deploy/`.

## Review And Run Order

1. Copy `deploy/instance.env.template` to `~/.config/budget-analyzer/instance.env` and fill in only the deployment-specific non-secret values.
2. Review the deployment scripts and checked-in values before running them on the OCI host.
3. Review the shared contract files:
   - `deploy/scripts/lib/phase-4-version-contract.sh`
   - `deploy/scripts/lib/common.sh`
4. Review the pinned Helm values:
   - `deploy/helm-values/external-secrets.values.yaml`
   - `deploy/helm-values/cert-manager.values.yaml`
   - `deploy/helm-values/kyverno.values.yaml`
5. Review the k3s/Istio bootstrap render templates:
   - `deploy/manifests/phase-4/ingress-gateway-config.yaml.template`
   - `deploy/manifests/phase-4/istio-gateway.yaml.template`
   - `kubernetes/istio/cni-common-values.yaml`
   - `kubernetes/istio/cni-k3s-values.yaml`
   - `kubernetes/istio/istiod-values.yaml`
   - `kubernetes/istio/egress-gateway-values.yaml`
6. Review the secret synchronization artifacts:
   - `deploy/manifests/phase-5/cluster-secret-store.yaml.template`
   - `deploy/manifests/phase-5/external-secrets.yaml`
   - `deploy/manifests/phase-5/session-gateway-idp-config.yaml.template`
   - `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh`
   - `deploy/scripts/09-render-phase-5-secrets.sh`
   - `deploy/scripts/10-apply-phase-5-secrets.sh`
   - `deploy/scripts/11-generate-phase-5-infra-tls.sh`
7. Review the production render inputs:
   - `kubernetes/production/README.md`
   - `kubernetes/production/gateway-routes/kustomization.yaml`
   - `kubernetes/production/istio-ingress-policies/kustomization.yaml`
   - `kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
   - `kubernetes/production/infrastructure/kustomization.yaml`
   - `kubernetes/production/infrastructure/patches/redis-storage.yaml`
   - `deploy/scripts/13-render-phase-6-production-manifests.sh`
8. Review the production infrastructure operation scripts:
   - `deploy/scripts/17-render-production-infrastructure.sh`
   - `deploy/scripts/18-apply-production-infrastructure.sh`
   - `deploy/scripts/19-migrate-production-redis-statefulset.sh`
9. Review the production observability rollout inputs:
   - `kubernetes/monitoring/jaeger/configmap.yaml`
   - `kubernetes/monitoring/jaeger/pvc.yaml`
   - `kubernetes/monitoring/jaeger/deployment.yaml`
   - `kubernetes/monitoring/jaeger/services.yaml`
   - `kubernetes/monitoring/kiali-values.yaml`
   - `scripts/ops/post-render-kiali-server.sh`
   - `deploy/scripts/20-render-phase-7-observability.sh`
   - `deploy/scripts/21-apply-phase-7-observability.sh`
10. Review the production admission inputs:
   - `kubernetes/kyverno/README.md`
   - `kubernetes/kyverno/policies/00-smoke-disallow-privileged.yaml`
   - `kubernetes/kyverno/policies/10-require-namespace-pod-security-labels.yaml`
   - `kubernetes/kyverno/policies/20-require-workload-automount-disabled.yaml`
   - `kubernetes/kyverno/policies/30-require-workload-security-context.yaml`
   - `kubernetes/kyverno/policies/40-disallow-obvious-default-credentials.yaml`
   - `kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml`
   - `deploy/scripts/14-install-phase-7-kyverno.sh`
   - `deploy/scripts/15-apply-phase-7-policies.sh`
11. Note the current observability boundary before reviewing or running any
   later observability artifacts:
   - The existing production Prometheus/Grafana path is unchanged.
   - Phase 7.8 now adds a reviewed OCI rollout path for Jaeger and Kiali
     through `deploy/scripts/20-render-phase-7-observability.sh` and
     `deploy/scripts/21-apply-phase-7-observability.sh`.
   - Production Grafana is internal-only and accessed with
     `kubectl port-forward`; the production route render does not publish a
     Grafana `HTTPRoute`.
   - Phase 7 uses the same internal-only access model for Jaeger and Kiali:
     both stay in `monitoring`, stay `ClusterIP`-only, and use loopback-bound
     `kubectl port-forward` instead of public routes.
   - Do not add Grafana, Kiali, or Jaeger public hostname inputs.
12. Run the human-owned cluster bootstrap scripts in this exact order:
   - `./deploy/scripts/01-install-k3s.sh`
   - `./deploy/scripts/02-bootstrap-cluster.sh`
   - `./deploy/scripts/03-render-phase-4-istio-manifests.sh`
   - `./deploy/scripts/04-install-istio.sh`
   - `./deploy/scripts/05-install-platform-controllers.sh`
   - `./deploy/scripts/06-configure-host-redirects.sh`
   - `./deploy/scripts/07-apply-network-policies.sh`
   - `./deploy/scripts/08-verify-network-policy-enforcement.sh`

## Expected Inputs

`~/.config/budget-analyzer/instance.env` is the only required deployment input
file outside the repo. It holds non-secret deployment metadata:

- OCI tenancy, compartment, vault, instance, subnet, and region identifiers
- the instance public IP and SSH key path
- the public demo hostname
- the production non-secret Auth0/IDP settings used later to render `session-gateway-idp-config` and the Auth0 Istio egress config
- the Let's Encrypt contact email

Do not put secret payloads in `instance.env`. Secret values stay in OCI Vault and later `ExternalSecret` resources.

Only the non-secret IDP values belong here. `AUTH0_CLIENT_SECRET` still belongs in OCI Vault.

Do not duplicate production image refs in `instance.env`. Production image inventory stays in `kubernetes/production/apps/image-inventory.yaml`.

## Host Tooling Prerequisites

The deployment scripts assume the host already has `kubectl`, `helm`, OpenSSL,
and the standard shell tools used by the scripts.

- `./deploy/scripts/04-install-istio.sh` and `./deploy/scripts/05-install-platform-controllers.sh` require `helm`.
- `./deploy/scripts/14-install-phase-7-kyverno.sh` requires `helm`.
- `./deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh` requires the OCI CLI plus `openssl`.
- `./deploy/scripts/11-generate-phase-5-infra-tls.sh` requires `openssl`.
- On a fresh OCI Ubuntu host, install the repo-pinned Helm build with `./scripts/bootstrap/install-verified-tool.sh helm`.
- Verify the install before rerunning the cluster bootstrap scripts: `helm version`

## Script Map

| Script | Purpose | Reused Later |
| --- | --- | --- |
| `deploy/scripts/01-install-k3s.sh` | Installs the pinned k3s release with the repo's Istio-friendly flags and prints the base cluster snapshot. | Re-run only if the host must be rebuilt or reconciled to the pinned k3s version. |
| `deploy/scripts/02-bootstrap-cluster.sh` | Installs the pinned Gateway API CRDs and creates or labels every namespace the deployment path depends on. | Re-run after a cluster rebuild or if namespace labels drift. |
| `deploy/scripts/03-render-phase-4-istio-manifests.sh` | Renders the ingress ConfigMap and host-agnostic HTTP Gateway into `tmp/phase-4/`. | Re-run before public TLS adds the TLS listener or whenever the reviewed ingress render output changes. |
| `deploy/scripts/04-install-istio.sh` | Refreshes the rendered ingress output, installs `istio-base`, installs `istio-cni` with the common values plus k3s overlay, installs `istiod`, installs the egress gateway, then applies the rendered ingress manifests plus mesh security policies. | Re-run after changing Istio pins, values, or the rendered ingress manifests. |
| `deploy/scripts/05-install-platform-controllers.sh` | Installs External Secrets Operator and cert-manager from the pinned charts and checked-in values. The script logs Helm repo-update vs install stages separately, waits up to `10m` per release, dumps `helm status`, workloads, and recent namespace events if either install fails, and accepts `PHASE4_PLATFORM_CONTROLLERS=cert-manager`, `external-secrets`, or `all` (default). | Re-run when secret synchronization or public TLS needs controller value changes. For the public TLS cert-manager solver refresh path, use `PHASE4_PLATFORM_CONTROLLERS=cert-manager`. |
| `deploy/scripts/06-configure-host-redirects.sh` | Runs the Step 15 host-redirect experiment by adding persistent host `iptables` redirects for any ingress NodePorts that currently exist, replacing stale redirects on rerun if a NodePort changes or disappears. Step 16 later removes these rules before the OCI NLB path becomes the steady-state design. | Re-run only while reproducing or comparing the rejected host-redirect path; do not treat it as the steady-state public ingress design. |
| `deploy/scripts/07-apply-network-policies.sh` | Applies the checked-in NetworkPolicy manifests after namespaces and controllers exist. | Re-run after policy edits or after rebuilding the cluster. |
| `deploy/scripts/08-verify-network-policy-enforcement.sh` | Creates disposable probe/listener pods and proves the checked-in allow/deny contract against the live k3s NetworkPolicy implementation. | Re-run after policy edits, CNI changes, or any cluster rebuild before treating NetworkPolicy enforcement as verified. |
| `deploy/scripts/09-render-phase-5-secrets.sh` | Renders the OCI `ClusterSecretStore`, the exact `ExternalSecret` inventory, and the production `session-gateway-idp-config` into `tmp/phase-5/`. | Re-run after any `instance.env` update that changes Vault identifiers or non-secret Auth0/IDP values. |
| `deploy/scripts/10-apply-phase-5-secrets.sh` | Refreshes the secret-sync render output, then applies the `ClusterSecretStore`, production IDP `ConfigMap`, and the full `ExternalSecret` set. | Re-run after IAM propagation, Vault secret inventory changes, or any `instance.env` change that affects the rendered resources. |
| `deploy/scripts/11-generate-phase-5-infra-tls.sh` | Generates the private `infra-ca` plus the PostgreSQL, Redis, and RabbitMQ server keypairs outside the repo, refuses container/AI-workspace execution, and applies the expected TLS Secret objects. | Re-run to restore the internal TLS secrets, or pass `--rotate` when intentionally replacing the CA and service certificates. |
| `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh` | Creates the OCI Vault secrets for Auth0, FRED, PostgreSQL, RabbitMQ, and Redis, while leaving `budget-analyzer-rabbitmq-definitions` as the one manual follow-up. The generated infrastructure passwords are written to an operator-only file outside the repo so the RabbitMQ definitions JSON can be assembled once. | Re-run to create any missing plain-text vault secrets. Existing OCI secrets are left unchanged, and the generated password receipt file is reused on subsequent runs. |
| `deploy/scripts/13-render-phase-6-production-manifests.sh` | Renders the reviewed app-only production gateway routes, ingress policies, production Grafana port-forward override, and Auth0-derived Istio egress manifests into `tmp/phase-6/` for operator review before live apply. | Re-run after changing the reviewed production overlay files or the non-secret production `AUTH0_ISSUER_URI`. |
| `deploy/scripts/14-install-phase-7-kyverno.sh` | Creates or relabels the `kyverno` namespace, then installs the pinned Kyverno chart with the checked-in production values. | Re-run after changing the Kyverno chart pin or `deploy/helm-values/kyverno.values.yaml`, or after rebuilding the cluster. |
| `deploy/scripts/15-apply-phase-7-policies.sh` | Runs the repo-owned production image verifier, then applies the shared admission policies plus the production-only image-digest variant. | Re-run after changing any `kubernetes/kyverno/policies/*.yaml`, the production `50-...` variant, or the checked-in production image baseline. |
| `deploy/scripts/16-render-phase-11-public-tls-manifests.sh` | Renders the reviewed app-only public TLS artifacts into `tmp/phase-11/`, including the Let's Encrypt `ClusterIssuer`, the app `Certificate`, the `ReferenceGrant`, and the `80/443` ingress Gateway manifests. | Re-run before the app TLS cutover or whenever the reviewed public hostname/TLS contract changes. |
| `deploy/scripts/17-render-production-infrastructure.sh` | Renders `kubernetes/production/infrastructure` with Kustomize load restrictions disabled into `tmp/production-infrastructure/infrastructure.yaml` for review. | Re-run before applying infrastructure, after changing the shared infrastructure baseline, or after changing the production Redis storage patch. |
| `deploy/scripts/18-apply-production-infrastructure.sh` | Refreshes the production infrastructure render, applies it to the current cluster, and waits for PostgreSQL, RabbitMQ, and Redis StatefulSets when present. | Re-run on a new or already migrated cluster, or after infrastructure manifest changes. |
| `deploy/scripts/19-migrate-production-redis-statefulset.sh` | Requires `--confirm-destroy-redis`, removes the old Redis Deployment and standalone `redis-data` PVC when present, applies the broad infrastructure target, verifies Redis TLS `PING`, and can optionally restart Redis clients with `--restart-redis-clients`. | Run once for an existing OCI Redis Deployment-to-StatefulSet migration; safe to rerun after migration because absent old Redis resources are ignored. |
| `deploy/scripts/20-render-phase-7-observability.sh` | Copies the reviewed Jaeger manifests and renders the pinned Kiali Helm output into `tmp/phase-7-observability/` for operator review using a Helm server-side dry run, so the reviewed Kiali RBAC matches the live namespace-scoped install footprint. | Re-run before live Jaeger/Kiali install, after changing shared Jaeger manifests, or after changing the Kiali values/post-renderer contract. |
| `deploy/scripts/21-apply-phase-7-observability.sh` | Reruns the production static verifier, refreshes the reviewed observability render, applies the shared Jaeger manifests, installs Kiali from the pinned chart and values, waits for both Deployments, and fails if any stale observability `HTTPRoute` still exists. | Re-run on a new or existing OCI cluster after changing the Jaeger manifests, the Kiali values/post-renderer, or the production observability contract. |

External Secrets Operator values intentionally leave service account token
automount enabled for the controller, webhook, and cert-controller pods. Those
controllers need in-cluster Kubernetes API credentials for watches, leader
election, admission webhook serving, and certificate reconciliation.

## Istio Setup Checkpoint

If you are resuming at the Istio setup checkpoint, use this section instead of
re-reading shell history:

1. Confirm Chunk 2 is already complete and `~/.config/budget-analyzer/instance.env` still exists.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   kubectl get namespace \
     default infrastructure monitoring istio-system istio-ingress istio-egress external-secrets cert-manager
   ```
2. Render the reviewed ingress manifests into `tmp/phase-4/`.
   ```bash
   ./deploy/scripts/03-render-phase-4-istio-manifests.sh
   sed -n '1,220p' tmp/phase-4/ingress-gateway-config.yaml
   sed -n '1,220p' tmp/phase-4/istio-gateway.yaml
   ```
3. Run the mesh install script. It covers the remaining human-owned Chunk 3 work in order.
   ```bash
   ./deploy/scripts/04-install-istio.sh
   ```
4. Verify the control plane, egress gateway, and ingress gateway before moving to Chunk 4.
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

If you are resuming at the NetworkPolicy checkpoint, the OCI-host checkpoint
recorded on 2026-04-16 has all steps complete. The only deferred follow-up is
rerunning `./deploy/scripts/08-verify-network-policy-enforcement.sh` after the
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
2. Step 13 and Step 14 are already complete on the current OCI host. If you are rebuilding or reconciling the host, rerun the shared controller-install script once and verify both controllers before continuing.
   ```bash
   ./deploy/scripts/05-install-platform-controllers.sh
   kubectl get pods -n external-secrets
   kubectl get pods -n cert-manager
   ```
3. Step 15 is historical only. Do not rerun `./deploy/scripts/06-configure-host-redirects.sh` on the forward path unless you are explicitly reproducing the rejected host-redirect design from the 2026-04-16 OCI debugging thread.
4. Step 16 and Step 17 are already complete on the current OCI host. If you are rebuilding or reconciling the environment, make sure any stale host redirects, debug-only `INPUT` rules, and direct-instance public `80/443` exposure are gone before creating the NLB.
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
5. Step 18 is already checked in: the reviewed ingress gateway config now sets `externalTrafficPolicy: Local`, and the rationale remains documented in [ADR 008](../docs/decisions/008-oci-public-ingress-via-nlb.md).
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
   ./deploy/scripts/07-apply-network-policies.sh
   kubectl get networkpolicy -A
   ```
9. Step 21b: run the runtime NetworkPolicy verifier.
   ```bash
   ./deploy/scripts/08-verify-network-policy-enforcement.sh
   ```
10. Before production Auth0 config exists, the verifier's two positive checks to `istio-egress-gateway:443` may fail because the bootstrap path intentionally does not apply placeholder egress routing. If those are the only failures, record the output and continue to secret synchronization. Do not accept any other failure at this step.
11. After the real egress config is rendered and applied from the production `AUTH0_ISSUER_URI`, rerun `./deploy/scripts/08-verify-network-policy-enforcement.sh` and require those two `istio-egress-gateway:443` checks to pass.

## Deployment Boundary Notes

`deploy/scripts/03-render-phase-4-istio-manifests.sh` intentionally renders an HTTP-only `Gateway` with a single host-agnostic listener and omits `spec.listeners[].hostname`. That keeps the checked-in localhost `HTTPRoute` manifests attachable during bootstrap while still leaving room for later host-specific route renders and ACME HTTP-01 challenge routes. Public certificate issuance and the final HTTPS listener secret wiring stay in the public TLS cutover.

`deploy/scripts/06-configure-host-redirects.sh` is kept in the repo because Step 15 is still recorded as the original host-redirect experiment. The 2026-04-16 OCI debugging thread proved that `nat/PREROUTING REDIRECT` to the ingress NodePort did not become a real NodePort service flow on this host, and it did not satisfy the requirement to preserve the original client IP at the ingress gateway. Do not rerun that experiment during the normal forward path. If the host still carries any Step 15 mutations, Step 16 host cleanup and Step 17 OCI-networking rollback are mandatory before the steady-state OCI Network Load Balancer plus `externalTrafficPolicy: Local` path begins.

The bootstrap ingress path stays HTTP-only even after the NLB pivot. The public
NLB needs only the listener and backend path for port `80 -> 30080` until the
public TLS cutover. The instance itself should no longer accept direct public
`80/443` traffic once the NLB path exists. The public TLS cutover adds the
HTTPS listener, the `30443` backend path, and the matching certificate/TLS
wiring.

On OCI, the public listener path also needs the frontend NSG to egress to the backend NSG on TCP `30080`. The 2026-04-16 operator run needed that explicit rule before the backend health check on `30080` would turn healthy.

The checked-in ingress NetworkPolicy allow list must continue to admit the
HTTP listener so ACME HTTP-01 reachability is not cut off when
`deploy/scripts/07-apply-network-policies.sh` runs. The repo now includes a
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

If you are moving directly from the completed OCI cluster bootstrap into secret
synchronization, use this checkpoint instead of reconstructing the next
commands from shell history:

1. Confirm the non-secret operator config is populated and the reviewed secret-sync artifacts are present.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   grep -E '^(OCI_REGION|OCI_COMPARTMENT_OCID|AUTH0_CLIENT_ID|AUTH0_ISSUER_URI|IDP_AUDIENCE|IDP_LOGOUT_RETURN_TO)=' \
     ~/.config/budget-analyzer/instance.env
   ls deploy/manifests/phase-5 deploy/scripts/09-render-phase-5-secrets.sh \
     deploy/scripts/10-apply-phase-5-secrets.sh deploy/scripts/11-generate-phase-5-infra-tls.sh
   ```
   `OCI_COMPARTMENT_OCID` is the compartment that contains the deployment
   vault, key, and secrets. If you are using the tenancy root compartment for those
   resources, `OCI_COMPARTMENT_OCID` should equal `OCI_TENANCY_OCID`.
2. Review the checked-in secret-sync artifacts first. Do not run the render step yet if the OCI vault/key work is still pending.
   ```bash
   sed -n '1,220p' deploy/manifests/phase-5/cluster-secret-store.yaml.template
   sed -n '1,260p' deploy/manifests/phase-5/external-secrets.yaml
   sed -n '1,220p' deploy/manifests/phase-5/session-gateway-idp-config.yaml.template
   sed -n '1,260p' deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh
   sed -n '1,220p' deploy/scripts/09-render-phase-5-secrets.sh
   sed -n '1,220p' deploy/scripts/10-apply-phase-5-secrets.sh
   sed -n '1,260p' deploy/scripts/11-generate-phase-5-infra-tls.sh
   ```
3. After the OCI vault/key exists and `~/.config/budget-analyzer/instance.env` includes `OCI_VAULT_OCID`, populate the plain-text vault secrets and then render the reviewed secret-sync artifacts.
   ```bash
   ./deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh
   ./deploy/scripts/09-render-phase-5-secrets.sh
   sed -n '1,220p' tmp/phase-5/cluster-secret-store.yaml
   sed -n '1,260p' tmp/phase-5/external-secrets.yaml
   sed -n '1,220p' tmp/phase-5/session-gateway-idp-config.yaml
   ```
   The script intentionally stops short of `budget-analyzer-rabbitmq-definitions`. Build that JSON with the generated RabbitMQ passwords from `~/.local/share/budget-analyzer/vault-secrets/phase-5-generated-secrets.env`, then create the final OCI secret manually.
4. After the OCI vault, dynamic group, policy, and secret inventory exist and IAM propagation has had time to settle, apply the reviewed secret-sync path on the OCI instance.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ./deploy/scripts/10-apply-phase-5-secrets.sh
   kubectl get clustersecretstore budget-analyzer-oci-vault
   kubectl get externalsecret -A
   kubectl get configmap -n default session-gateway-idp-config -o yaml
   ```
5. Generate and apply the internal TLS secrets from the OCI host or another trusted machine outside AI sessions.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ./deploy/scripts/11-generate-phase-5-infra-tls.sh
   ```
   The script writes the CA and service keypairs under `~/.local/share/budget-analyzer/infra-tls` by default, keeps them outside the repo, and refuses to run from the containerized AI workspace.
6. Stop if any `ExternalSecret` reports sync errors, if `session-gateway-idp-config` still shows placeholder/localhost values, or if any of `infra-ca`, `infra-tls-postgresql`, `infra-tls-redis`, or `infra-tls-rabbitmq` are missing.

## Production Render Review

The repo-owned production render path must be reviewed before any production
gateway or egress objects are applied:

```bash
./deploy/scripts/13-render-phase-6-production-manifests.sh
sed -n '1,260p' tmp/phase-6/gateway-routes.yaml
sed -n '1,220p' tmp/phase-6/istio-ingress-policies.yaml
sed -n '1,120p' tmp/phase-6/prometheus-stack-values.override.yaml
sed -n '1,260p' tmp/phase-6/istio-egress.yaml
rg -n 'budgetanalyzer\\.localhost|auth0-issuer\\.placeholder\\.invalid' \
  kubernetes/production tmp/phase-6
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
./deploy/scripts/17-render-production-infrastructure.sh
sed -n '1,260p' tmp/production-infrastructure/infrastructure.yaml
```

On a new or already migrated cluster, apply that rendered target with:

```bash
./deploy/scripts/18-apply-production-infrastructure.sh
```

Both production infrastructure scripts are safe to rerun. The render script
overwrites the review artifact under `tmp/production-infrastructure/`, and the
apply script refreshes that render before applying it and waiting for the
StatefulSets that are present.

The old production-only Redis Deployment/PVC overlay is superseded. Migrating
an existing OCI Redis Deployment to the StatefulSet shape is destructive for
Redis session/cache data; use the guarded migration script rather than applying
ad hoc deletes:

```bash
./deploy/scripts/19-migrate-production-redis-statefulset.sh --confirm-destroy-redis
```

Add `--restart-redis-clients` when you want the script to roll out
`session-gateway`, `ext-authz`, and `currency-service` after Redis passes the
TLS `PING` check.
The migration script ignores already-absent old Redis resources, so a rerun
after the first migration should converge on the same broad infrastructure
target without deleting PostgreSQL or RabbitMQ data.

For monitoring, keep the Helm release name `prometheus-stack` when
kube-prometheus-stack is installed. The checked-in production override at
`kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
assumes that release name so Grafana stays reachable through the existing
`prometheus-stack-grafana` Service used by the loopback port-forward contract.

For Jaeger and Kiali, use the repo-owned Phase 7.8 render/apply path instead of
one-off `kubectl` or `helm` commands:

```bash
./deploy/scripts/20-render-phase-7-observability.sh
sed -n '1,220p' tmp/phase-7-observability/jaeger-deployment.yaml
sed -n '1,260p' tmp/phase-7-observability/kiali.yaml

./deploy/scripts/21-apply-phase-7-observability.sh
```

The render step keeps the exact OCI Jaeger manifests and rendered Kiali output
reviewable under `tmp/phase-7-observability/`. It now uses a Helm server-side
dry run against the live cluster so `kiali.yaml` includes the full
namespace-scoped `Role`/`RoleBinding` footprint that production will install.
The apply step refreshes that artifact, applies the shared Jaeger manifests
unchanged, installs the same `kiali/kiali-server` `2.24.0` chart version with
the same pinned values and post-renderer used locally, waits for
`Deployment/jaeger` plus `Deployment/kiali`, and aborts if any stale
observability `HTTPRoute` still exists.

## Public TLS Cutover

The repo-owned render path for the public TLS cutover is:

```bash
./deploy/scripts/16-render-phase-11-public-tls-manifests.sh
sed -n '1,220p' tmp/phase-11/cluster-issuer.yaml
sed -n '1,220p' tmp/phase-11/public-certificate.yaml
sed -n '1,220p' tmp/phase-11/reference-grant.yaml
sed -n '1,220p' tmp/phase-11/ingress-gateway-config.yaml
sed -n '1,260p' tmp/phase-11/istio-gateway.yaml
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
- `deploy/manifests/phase-11/cluster-issuer.yaml.template` labels the temporary
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
PHASE4_PLATFORM_CONTROLLERS=cert-manager ./deploy/scripts/05-install-platform-controllers.sh
./deploy/scripts/07-apply-network-policies.sh
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
- Production Grafana has no public `HTTPRoute` in the phase-6 route render.
  Access it through the shared loopback-bound operator contract:
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-grafana 3300:80`.
- Production Prometheus stays internal-only and uses the same pattern:
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090`.
- Phase 7.8 now adds the reviewed OCI rollout path for Jaeger and Kiali:
  `./deploy/scripts/20-render-phase-7-observability.sh` for review and
  `./deploy/scripts/21-apply-phase-7-observability.sh` for the live install.
- Jaeger follows the same internal-only model through
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/jaeger-query 16686:16686`.
- Kiali follows the same model through
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/kiali 20001:20001`.
- Keep observability port-forwards bound to `127.0.0.1`; do not use `--address 0.0.0.0`.
- When updating a live instance from an older render, explicitly delete any
  stale observability routes because `kubectl apply` does not prune removed
  kustomize resources:
  `kubectl delete httproute -n monitoring grafana-route prometheus-route kiali-route jaeger-route --ignore-not-found`.
- Keep Prometheus, Jaeger, and Kiali internal-only on the same reviewed
  loopback port-forward model.
- Do not introduce `grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, or
  `jaeger.budgetanalyzer.org` as public production hostnames.
- Public TLS cutover is the next open deployment area.

## Production Admission Policy

The repo-owned production install/apply path is checked in. Review the
checked-in Kyverno values and policy inventory first. The production values now
pin every rendered Kyverno controller and hook image by digest rather than
inheriting chart-default tags:

Re-run the production policy install/apply steps when you change the Kyverno
values, the policies, or rebuild the OCI cluster.

```bash
sed -n '1,240p' deploy/helm-values/kyverno.values.yaml
sed -n '1,220p' deploy/scripts/14-install-phase-7-kyverno.sh
sed -n '1,220p' deploy/scripts/15-apply-phase-7-policies.sh
sed -n '1,220p' kubernetes/kyverno/README.md
find kubernetes/kyverno/policies -maxdepth 2 -type f | sort
```

Then install the controller with the pinned chart and checked-in values:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
./deploy/scripts/14-install-phase-7-kyverno.sh
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
./deploy/scripts/15-apply-phase-7-policies.sh
kubectl get clusterpolicy
```

Stop if the production verifier fails, if any Kyverno controller deployment is
unavailable, or if `phase7-require-third-party-image-digests` in the live
cluster does not come from the production variant.

## Validation Standard

Every committed `deploy/scripts/*.sh` file must pass:

- `bash -n <script>`
- `shellcheck -x <script>`

The render paths must also be provable locally with sample non-secret input so
reviewers can inspect generated YAML under `tmp/phase-4/`, `tmp/phase-5/`, and
`tmp/phase-6/`.
