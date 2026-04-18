# Oracle Cloud Deployment Path

This directory is the committed, operator-facing install surface for the Oracle
Cloud deployment plan. Phase 4, Phase 5, the Phase 6 production render path,
and the Phase 7 production Kyverno install/apply path now all have first-class,
reviewable artifacts here so a human can inspect the exact cluster mutations
before touching the OCI instance or Vault.

`deploy/` contains only repeatable Pattern B artifacts:

- reviewed scripts under `deploy/scripts/`
- checked-in Helm values under `deploy/helm-values/`
- checked-in non-secret render templates under `deploy/manifests/phase-4/`
- checked-in non-secret Phase 5 templates and manifests under `deploy/manifests/phase-5/`
- the Phase 6 production render entry point under `deploy/scripts/`
- the Phase 7 production Kyverno install/apply entry points under `deploy/scripts/`
- the non-secret instance config template at `deploy/instance.env.template`

Runtime render output still belongs under `tmp/`, not under `deploy/`.

## Review And Run Order

1. Review `docs/plans/oracle-cloud-deployment-plan.md#phase-4-install-k3s-gateway-api-istio-eso-and-cert-manager`.
2. Copy `deploy/instance.env.template` to `~/.config/budget-analyzer/instance.env` and fill in only the deployment-specific non-secret values.
3. Review the shared contract files:
   - `deploy/scripts/lib/phase-4-version-contract.sh`
   - `deploy/scripts/lib/common.sh`
4. Review the pinned Helm values:
   - `deploy/helm-values/external-secrets.values.yaml`
   - `deploy/helm-values/cert-manager.values.yaml`
   - `deploy/helm-values/kyverno.values.yaml`
5. Review the Phase 4 render templates:
   - `deploy/manifests/phase-4/ingress-gateway-config.yaml.template`
   - `deploy/manifests/phase-4/istio-gateway.yaml.template`
6. Review the Phase 5 artifacts:
   - `deploy/manifests/phase-5/cluster-secret-store.yaml.template`
   - `deploy/manifests/phase-5/external-secrets.yaml`
   - `deploy/manifests/phase-5/session-gateway-idp-config.yaml.template`
   - `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh`
   - `deploy/scripts/09-render-phase-5-secrets.sh`
   - `deploy/scripts/10-apply-phase-5-secrets.sh`
   - `deploy/scripts/11-generate-phase-5-infra-tls.sh`
7. Review the Phase 6 production render inputs:
   - `kubernetes/production/README.md`
   - `kubernetes/production/gateway-routes/kustomization.yaml`
   - `kubernetes/production/istio-ingress-policies/kustomization.yaml`
   - `kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
   - `kubernetes/production/infrastructure/redis/kustomization.yaml`
   - `deploy/scripts/13-render-phase-6-production-manifests.sh`
8. Review the Phase 7 production admission inputs:
   - `kubernetes/kyverno/README.md`
   - `kubernetes/kyverno/policies/00-smoke-disallow-privileged.yaml`
   - `kubernetes/kyverno/policies/10-require-namespace-pod-security-labels.yaml`
   - `kubernetes/kyverno/policies/20-require-workload-automount-disabled.yaml`
   - `kubernetes/kyverno/policies/30-require-workload-security-context.yaml`
   - `kubernetes/kyverno/policies/40-disallow-obvious-default-credentials.yaml`
   - `kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml`
   - `deploy/scripts/14-install-phase-7-kyverno.sh`
   - `deploy/scripts/15-apply-phase-7-policies.sh`
9. Note the current Phase 10 boundary before reviewing or running any later
   observability artifacts:
   - Phase 10 is complete for the current forward deployment path as of
     2026-04-18.
   - Phase 10 Step 1 completed on 2026-04-18. The remaining originally planned
     Phase 10 work is deferred pending an internal-only observability access
     redesign.
   - Leave `KIALI_DOMAIN` and `JAEGER_DOMAIN` blank, and do not resume any
     Jaeger, Kiali, tracing, or observability-route rollout work on this
     branch.
10. Run the human-owned Phase 4 scripts in this exact order:
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
- the public demo hostname plus the current Grafana hostname; keep
  `KIALI_DOMAIN` and `JAEGER_DOMAIN` blank until the deferred internal-only
  observability redesign explicitly reopens that work
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
- Verify the install before rerunning the Phase 4 scripts: `helm version`

## Script Map

| Script | Purpose | Reused Later |
| --- | --- | --- |
| `deploy/scripts/01-install-k3s.sh` | Installs the pinned k3s release with the repo's Istio-friendly flags and prints the base cluster snapshot. | Re-run only if the host must be rebuilt or reconciled to the pinned k3s version. |
| `deploy/scripts/02-bootstrap-cluster.sh` | Installs the pinned Gateway API CRDs and creates or labels every namespace Phase 4 depends on. | Re-run after a cluster rebuild or if namespace labels drift. |
| `deploy/scripts/03-render-phase-4-istio-manifests.sh` | Renders the Phase 4 ingress ConfigMap and host-agnostic HTTP Gateway into `tmp/phase-4/`. | Re-run before Phase 11 adds the TLS listener or whenever the reviewed ingress render output changes. |
| `deploy/scripts/04-install-istio.sh` | Refreshes the rendered ingress output, installs `istio-base`, `istio-cni`, `istiod`, the egress gateway, then applies the rendered ingress manifests plus mesh security policies. | Re-run after changing Istio pins, values, or the rendered ingress manifests. |
| `deploy/scripts/05-install-platform-controllers.sh` | Installs External Secrets Operator and cert-manager from the pinned charts and checked-in values. The script now logs Helm repo-update vs install phases separately, waits up to `10m` per release, dumps `helm status`, workloads, and recent namespace events if either install fails, and accepts `PHASE4_PLATFORM_CONTROLLERS=cert-manager`, `external-secrets`, or `all` (default). | Re-run when Phase 5 or Phase 11 needs controller value changes. For the Phase 11 cert-manager solver refresh path, use `PHASE4_PLATFORM_CONTROLLERS=cert-manager`. |
| `deploy/scripts/06-configure-host-redirects.sh` | Runs the Step 15 host-redirect experiment by adding persistent host `iptables` redirects for any ingress NodePorts that currently exist, replacing stale redirects on rerun if a NodePort changes or disappears. Step 16 later removes these rules before the OCI NLB path becomes the steady-state design. | Re-run only while reproducing or comparing the rejected host-redirect path; do not treat it as the steady-state public ingress design. |
| `deploy/scripts/07-apply-network-policies.sh` | Applies the checked-in NetworkPolicy manifests after namespaces and controllers exist. | Re-run after policy edits or after rebuilding the cluster. |
| `deploy/scripts/08-verify-network-policy-enforcement.sh` | Creates disposable probe/listener pods and proves the checked-in allow/deny contract against the live k3s NetworkPolicy implementation. | Re-run after policy edits, CNI changes, or any cluster rebuild before claiming Phase 4 complete. |
| `deploy/scripts/09-render-phase-5-secrets.sh` | Renders the OCI `ClusterSecretStore`, the exact `ExternalSecret` inventory, and the production `session-gateway-idp-config` into `tmp/phase-5/`. | Re-run after any `instance.env` update that changes Vault identifiers or non-secret Auth0/IDP values. |
| `deploy/scripts/10-apply-phase-5-secrets.sh` | Refreshes the Phase 5 render output, then applies the `ClusterSecretStore`, production IDP `ConfigMap`, and the full `ExternalSecret` set. | Re-run after IAM propagation, Vault secret inventory changes, or any `instance.env` change that affects the rendered resources. |
| `deploy/scripts/11-generate-phase-5-infra-tls.sh` | Generates the private `infra-ca` plus the PostgreSQL, Redis, and RabbitMQ server keypairs outside the repo, refuses container/AI-workspace execution, and applies the expected TLS Secret objects. | Re-run to restore the internal TLS secrets, or pass `--rotate` when intentionally replacing the CA and service certificates. |
| `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh` | Creates the Phase 5 OCI Vault secrets for Auth0, FRED, PostgreSQL, RabbitMQ, and Redis, while leaving `budget-analyzer-rabbitmq-definitions` as the one manual follow-up. The generated infrastructure passwords are written to an operator-only file outside the repo so the RabbitMQ definitions JSON can be assembled once. | Re-run to create any missing plain-text vault secrets. Existing OCI secrets are left unchanged, and the generated password receipt file is reused on subsequent runs. |
| `deploy/scripts/13-render-phase-6-production-manifests.sh` | Renders the reviewed Phase 6 production gateway routes, ingress policies, monitoring hostname override, and Auth0-derived Istio egress manifests into `tmp/phase-6/` for operator review before Phase 9 applies them. | Re-run after changing the reviewed Phase 6 production overlay files or the non-secret production `AUTH0_ISSUER_URI`. |
| `deploy/scripts/14-install-phase-7-kyverno.sh` | Creates or relabels the `kyverno` namespace, then installs the pinned Kyverno chart with the checked-in production values. | Re-run after changing the Kyverno chart pin or `deploy/helm-values/kyverno.values.yaml`, or after rebuilding the cluster. |
| `deploy/scripts/15-apply-phase-7-policies.sh` | Runs the repo-owned production image verifier, then applies the shared Phase 7 policies plus the production-only image-digest variant. | Re-run after changing any `kubernetes/kyverno/policies/*.yaml`, the production `50-...` variant, or the checked-in production image baseline. |
| `deploy/scripts/16-render-phase-11-public-tls-manifests.sh` | Renders the reviewed Phase 11 app-only public TLS artifacts into `tmp/phase-11/`, including the Let's Encrypt `ClusterIssuer`, the app `Certificate`, the `ReferenceGrant`, and the `80/443` ingress Gateway manifests. | Re-run before the Phase 11 app TLS cutover or whenever the reviewed Phase 11 hostname/TLS contract changes. |

## Chunk 3 Checkpoint

If you are resuming at Phase 4 Chunk 3, use this checkpoint instead of re-reading shell history:

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

## Chunk 4 Checkpoint

If you are resuming at Phase 4 Chunk 4, the OCI-host checkpoint recorded on 2026-04-16 has all steps complete. The only deferred follow-up is rerunning `./deploy/scripts/08-verify-network-policy-enforcement.sh` after Phase 9 Step 2 applies the real Auth0-derived egress config.

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
5. Step 18 is already checked in: the reviewed Phase 4 ingress gateway config now sets `externalTrafficPolicy: Local`, and the rationale remains documented in [ADR 008](../docs/decisions/008-oci-public-ingress-via-nlb.md).
6. Step 19: create the public OCI Network Load Balancer for the current ingress NodePort.
   - For Phase 4, create one TCP listener on `80`, point it at the instance backend on `30080`, and configure the backend set in source-IP-preserving mode.
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
10. Before production Auth0 config exists, the verifier's two positive checks to `istio-egress-gateway:443` may fail because Phase 4 intentionally does not apply placeholder egress routing. If those are the only failures, record the output and continue to Phase 5. Do not accept any other failure at this step.
11. After Phase 9 Step 2 renders and applies the real egress config from the production `AUTH0_ISSUER_URI`, rerun `./deploy/scripts/08-verify-network-policy-enforcement.sh` and require those two `istio-egress-gateway:443` checks to pass.

## Phase Boundary Notes

`deploy/scripts/03-render-phase-4-istio-manifests.sh` intentionally renders an HTTP-only `Gateway` with a single host-agnostic listener and omits `spec.listeners[].hostname`. That keeps the checked-in localhost `HTTPRoute` manifests attachable during Phase 4 while still leaving room for later host-specific route renders and ACME HTTP-01 challenge routes. Public certificate issuance and the final HTTPS listener secret wiring stay in Phase 11.

`deploy/scripts/06-configure-host-redirects.sh` is kept in the repo because Step 15 is still recorded as the original host-redirect experiment. The 2026-04-16 OCI debugging thread proved that `nat/PREROUTING REDIRECT` to the ingress NodePort did not become a real NodePort service flow on this host, and it did not satisfy the requirement to preserve the original client IP at the ingress gateway. Do not rerun that experiment during the normal forward path. If the host still carries any Step 15 mutations, Step 16 host cleanup and Step 17 OCI-networking rollback are mandatory before the steady-state OCI Network Load Balancer plus `externalTrafficPolicy: Local` path begins.

Phase 4 stays HTTP-only even after the NLB pivot. For this phase the public NLB needs only the listener and backend path for port `80 -> 30080`. The instance itself should no longer accept direct public `80/443` traffic once the NLB path exists. Phase 11 is still where the repo adds the HTTPS listener, the `30443` backend path, and the matching certificate/TLS wiring.

On OCI, the public listener path also needs the frontend NSG to egress to the backend NSG on TCP `30080`. The 2026-04-16 operator run needed that explicit rule before the backend health check on `30080` would turn healthy.

The checked-in ingress NetworkPolicy allow list must continue to admit that Phase 4 HTTP listener so ACME HTTP-01 reachability is not cut off when `deploy/scripts/07-apply-network-policies.sh` runs.

The Phase 4 runtime NetworkPolicy verifier intentionally runs before production Auth0 config exists. Because Step 8 of the main plan explicitly defers applying placeholder Istio egress routing, a pre-Auth0 OCI host can legitimately miss the verifier's two positive `istio-egress-gateway:443` checks while still proving the rest of the CNI contract. Treat those two checks as deferred only, and rerun the verifier after Phase 9 Step 2 applies the rendered egress config from the real `AUTH0_ISSUER_URI`.

## Phase 5 Checkpoint

If you are moving directly from the completed Phase 4 OCI host into Phase 5,
use this checkpoint instead of reconstructing the next commands from the plan:

1. Confirm the non-secret operator config is populated and the reviewed Phase 5 artifacts are present.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   grep -E '^(OCI_REGION|OCI_COMPARTMENT_OCID|AUTH0_CLIENT_ID|AUTH0_ISSUER_URI|IDP_AUDIENCE|IDP_LOGOUT_RETURN_TO)=' \
     ~/.config/budget-analyzer/instance.env
   ls deploy/manifests/phase-5 deploy/scripts/09-render-phase-5-secrets.sh \
     deploy/scripts/10-apply-phase-5-secrets.sh deploy/scripts/11-generate-phase-5-infra-tls.sh
   ```
   `OCI_COMPARTMENT_OCID` is the compartment that contains the Phase 5 vault,
   key, and secrets. If you are using the tenancy root compartment for those
   resources, `OCI_COMPARTMENT_OCID` should equal `OCI_TENANCY_OCID`.
2. Review the checked-in Phase 5 artifacts first. Do not run the render step yet if the OCI vault/key work is still pending.
   ```bash
   sed -n '1,220p' deploy/manifests/phase-5/cluster-secret-store.yaml.template
   sed -n '1,260p' deploy/manifests/phase-5/external-secrets.yaml
   sed -n '1,220p' deploy/manifests/phase-5/session-gateway-idp-config.yaml.template
   sed -n '1,260p' deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh
   sed -n '1,220p' deploy/scripts/09-render-phase-5-secrets.sh
   sed -n '1,220p' deploy/scripts/10-apply-phase-5-secrets.sh
   sed -n '1,260p' deploy/scripts/11-generate-phase-5-infra-tls.sh
   ```
3. After the OCI vault/key exists and `~/.config/budget-analyzer/instance.env` includes `OCI_VAULT_OCID`, populate the plain-text vault secrets and then render the reviewed Phase 5 secret-sync artifacts.
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

## Phase 6 Checkpoint

Phase 6 Step 7 now has a repo-owned production render path. Before Phase 9
applies any production gateway or egress objects, render and review the
committed output first:

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
owned by the Phase 5 render/apply path, then apply the Phase 6 rendered route
and egress output separately during Phase 9.

Before any live Phase 7 or Phase 9 step, run the repo-owned Phase 6 production
verifier against the checked-in baseline:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

That command renders the production app overlay, production Redis overlay, and
the reviewed Phase 6 route/ingress/monitoring/egress output using the locked
Phase 6 hostnames. It fails on localhost hosts, placeholder Auth0 values,
mutable image refs, `imagePullPolicy: Never`, or a production route that falls
back to `nginx/nginx.k8s.conf`.

Phase 6 also adds the checked-in production Redis path at
`kubernetes/production/infrastructure/redis/`. That overlay generates the
`redis-acl-bootstrap` ConfigMap from the committed production-local
`start-redis.sh`, replaces the shared local-dev `emptyDir` with
`PersistentVolumeClaim/redis-data`, and is the reviewed artifact Phase 8 should
apply with `kubectl apply -k
kubernetes/production/infrastructure/redis`.

Status as of 2026-04-17: Phase 8 is complete per operator handoff. Keep this
Redis overlay as the reviewed production path for future infrastructure
rebuilds.

For monitoring, keep the Helm release name `prometheus-stack` when Phase 10
installs kube-prometheus-stack. The checked-in production override at
`kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
assumes that release name so Grafana stays reachable through the existing
`prometheus-stack-grafana` Service referenced by the checked-in `HTTPRoute`.

## Phase 11 Checkpoint

Phase 11 now has a repo-owned render path for the public TLS cutover:

```bash
./deploy/scripts/16-render-phase-11-public-tls-manifests.sh
sed -n '1,220p' tmp/phase-11/cluster-issuer.yaml
sed -n '1,220p' tmp/phase-11/public-certificate.yaml
sed -n '1,220p' tmp/phase-11/reference-grant.yaml
sed -n '1,220p' tmp/phase-11/ingress-gateway-config.yaml
sed -n '1,260p' tmp/phase-11/istio-gateway.yaml
```

The current forward-path Phase 11 public TLS contract remains locked to:

- `demo.budgetanalyzer.org`

Grafana, Kiali, and Jaeger do not belong on the Phase 11 public TLS surface.
Keep observability off the new public DNS/TLS path while the internal-only
redesign remains pending.

Do not move the live app to the apex domain during Phase 11 unless the Phase 6
and Phase 11 production hostname contract is reviewed and changed first. For
the current repo state, the apex `budgetanalyzer.org` is best handled as an
optional forwarding target to `demo.budgetanalyzer.org`, not as the direct app
origin.

Phase 11's ACME HTTP-01 path now depends on the reviewed cert-manager and
Kyverno compatibility contract in-repo:

- `deploy/helm-values/cert-manager.values.yaml` pins the chart-managed
  `acmesolver` image by digest so the temporary solver Pod can pass the Phase 7
  production image policy even though it runs in `default`.
- `deploy/manifests/phase-11/cluster-issuer.yaml.template` labels the temporary
  solver Pod and applies the strongest pod-level security context the
  cert-manager Gateway solver API exposes.
- `kubernetes/kyverno/policies/30-require-workload-security-context.yaml`
  keeps the normal container-level checks for repo-managed workloads but makes a
  narrow exception for only those labeled solver Pods because cert-manager does
  not let this repo declare `allowPrivilegeEscalation=false` or
  `capabilities.drop=["ALL"]` on them.

If your OCI cluster predates that contract change, re-run only the cert-manager
portion before retrying Phase 11 certificate issuance so the live cert-manager
release picks up the digest-pinned solver image:

```bash
PHASE4_PLATFORM_CONTROLLERS=cert-manager ./deploy/scripts/05-install-platform-controllers.sh
```

If that rerun appears to stall, read the last emitted phase line first:

- `updating Helm repo external-secrets` or `updating Helm repo jetstack` means the host is still fetching chart metadata.
- `installing External Secrets Operator ... (timeout 10m)` or `installing cert-manager ... (timeout 10m)` means Helm is waiting for the selected release resources to become ready.
- On failure, the script now prints `helm status`, controller workloads, and recent namespace events for `external-secrets` and `cert-manager` automatically.

## Phase 10 Checkpoint

Status as of 2026-04-18:

- Phase 10 is complete for the current forward deployment path.
- Phase 10 Step 1 is complete. `kube-prometheus-stack` with Helm release
  `prometheus-stack` and the current Grafana hostname are the live production
  observability baseline.
- The remaining originally planned Phase 10 work is deferred pending an
  internal-only observability access redesign.
- Keep Prometheus internal-only. Leave `KIALI_DOMAIN` and `JAEGER_DOMAIN`
  blank, and do not resume any Jaeger, Kiali, tracing, or
  observability-route rollout work unless the deployment plan is explicitly
  reopened with a reviewed access model for Grafana, Jaeger, and Kiali.
- Phase 11 is the next open phase.

## Phase 7 Checkpoint

Phase 7 now has a repo-owned production install/apply path. Review the
checked-in Kyverno values and policy inventory first. The production values now
pin every rendered Kyverno controller and hook image by digest rather than
inheriting chart-default tags:

Status: complete per operator handoff as of 2026-04-17. Re-run the Phase 7
install/apply steps when you change the Kyverno values, the Phase 7 policies,
or rebuild the OCI cluster.

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
verifier against the checked-in image/render baseline. The Phase 7 apply script
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
