# Oracle Cloud Deployment Path

This directory is the committed, operator-facing install surface for the Oracle
Cloud deployment plan. Phase 4 and Phase 5 now both have first-class,
reviewable artifacts here so a human can inspect the exact cluster mutations
before touching the OCI instance or Vault.

`deploy/` contains only repeatable Pattern B artifacts:

- reviewed scripts under `deploy/scripts/`
- checked-in Helm values under `deploy/helm-values/`
- checked-in non-secret render templates under `deploy/manifests/phase-4/`
- checked-in non-secret Phase 5 templates and manifests under `deploy/manifests/phase-5/`
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
5. Review the Phase 4 render templates:
   - `deploy/manifests/phase-4/ingress-gateway-config.yaml.template`
   - `deploy/manifests/phase-4/istio-gateway.yaml.template`
6. Review the Phase 5 artifacts:
   - `deploy/manifests/phase-5/cluster-secret-store.yaml.template`
   - `deploy/manifests/phase-5/external-secrets.yaml`
   - `deploy/manifests/phase-5/session-gateway-idp-config.yaml.template`
   - `deploy/scripts/09-render-phase-5-secrets.sh`
   - `deploy/scripts/10-apply-phase-5-secrets.sh`
   - `deploy/scripts/11-generate-phase-5-infra-tls.sh`
7. Run the human-owned Phase 4 scripts in this exact order:
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
- the public demo hostname plus any optional observability hostnames for later phases
- the production non-secret Auth0/IDP settings used later to render `session-gateway-idp-config` and the Auth0 Istio egress config
- the Let's Encrypt contact email

Do not put secret payloads in `instance.env`. Secret values stay in OCI Vault and later `ExternalSecret` resources.

Only the non-secret IDP values belong here. `AUTH0_CLIENT_SECRET` still belongs in OCI Vault.

Do not duplicate production image refs in `instance.env`. Production image inventory stays in `kubernetes/production/apps/image-inventory.yaml`.

## Host Tooling Prerequisites

The deployment scripts assume the host already has `kubectl`, `helm`, OpenSSL,
and the standard shell tools used by the scripts.

- `./deploy/scripts/04-install-istio.sh` and `./deploy/scripts/05-install-platform-controllers.sh` require `helm`.
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
| `deploy/scripts/05-install-platform-controllers.sh` | Installs External Secrets Operator and cert-manager from the pinned charts and checked-in values. | Re-run when Phase 5 or Phase 11 needs controller value changes. |
| `deploy/scripts/06-configure-host-redirects.sh` | Runs the Step 15 host-redirect experiment by adding persistent host `iptables` redirects for any ingress NodePorts that currently exist, replacing stale redirects on rerun if a NodePort changes or disappears. Step 16 later removes these rules before the OCI NLB path becomes the steady-state design. | Re-run only while reproducing or comparing the rejected host-redirect path; do not treat it as the steady-state public ingress design. |
| `deploy/scripts/07-apply-network-policies.sh` | Applies the checked-in NetworkPolicy manifests after namespaces and controllers exist. | Re-run after policy edits or after rebuilding the cluster. |
| `deploy/scripts/08-verify-network-policy-enforcement.sh` | Creates disposable probe/listener pods and proves the checked-in allow/deny contract against the live k3s NetworkPolicy implementation. | Re-run after policy edits, CNI changes, or any cluster rebuild before claiming Phase 4 complete. |
| `deploy/scripts/09-render-phase-5-secrets.sh` | Renders the OCI `ClusterSecretStore`, the exact `ExternalSecret` inventory, and the production `session-gateway-idp-config` into `tmp/phase-5/`. | Re-run after any `instance.env` update that changes Vault identifiers or non-secret Auth0/IDP values. |
| `deploy/scripts/10-apply-phase-5-secrets.sh` | Refreshes the Phase 5 render output, then applies the `ClusterSecretStore`, production IDP `ConfigMap`, and the full `ExternalSecret` set. | Re-run after IAM propagation, Vault secret inventory changes, or any `instance.env` change that affects the rendered resources. |
| `deploy/scripts/11-generate-phase-5-infra-tls.sh` | Generates the private `infra-ca` plus the PostgreSQL, Redis, and RabbitMQ server keypairs outside the repo, then applies the expected TLS Secret objects. | Re-run to restore the internal TLS secrets, or pass `--rotate` when intentionally replacing the CA and service certificates. |

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
   grep -E '^(OCI_REGION|OCI_COMPARTMENT_OCID|OCI_VAULT_OCID|AUTH0_CLIENT_ID|AUTH0_ISSUER_URI|IDP_AUDIENCE|IDP_LOGOUT_RETURN_TO)=' \
     ~/.config/budget-analyzer/instance.env
   ls deploy/manifests/phase-5 deploy/scripts/09-render-phase-5-secrets.sh \
     deploy/scripts/10-apply-phase-5-secrets.sh deploy/scripts/11-generate-phase-5-infra-tls.sh
   ```
2. Render the reviewed Phase 5 secret-sync artifacts before touching the live cluster.
   ```bash
   ./deploy/scripts/09-render-phase-5-secrets.sh
   sed -n '1,220p' tmp/phase-5/cluster-secret-store.yaml
   sed -n '1,260p' tmp/phase-5/external-secrets.yaml
   sed -n '1,220p' tmp/phase-5/session-gateway-idp-config.yaml
   ```
3. After the OCI vault, dynamic group, policy, and secret inventory exist and IAM propagation has had time to settle, apply the reviewed secret-sync path on the OCI instance.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ./deploy/scripts/10-apply-phase-5-secrets.sh
   kubectl get clustersecretstore budget-analyzer-oci-vault
   kubectl get externalsecret -A
   kubectl get configmap -n default session-gateway-idp-config -o yaml
   ```
4. Generate and apply the internal TLS secrets from the OCI host or another trusted machine outside AI sessions.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   ./deploy/scripts/11-generate-phase-5-infra-tls.sh
   ```
5. Stop if any `ExternalSecret` reports sync errors, if `session-gateway-idp-config` still shows placeholder/localhost values, or if any of `infra-ca`, `infra-tls-postgresql`, `infra-tls-redis`, or `infra-tls-rabbitmq` are missing.

## Validation Standard

Every committed `deploy/scripts/*.sh` file must pass:

- `bash -n <script>`
- `shellcheck -x <script>`

The render paths must also be provable locally with sample non-secret input so
reviewers can inspect generated YAML under `tmp/phase-4/` and `tmp/phase-5/`.
