# Phase 4 Deployment Path

This directory is the committed, operator-facing install surface for Oracle Cloud Phase 4. The goal is straightforward: a human should be able to review the exact host and cluster mutations in-repo before touching the OCI instance.

`deploy/` contains only repeatable Pattern B artifacts:

- reviewed scripts under `deploy/scripts/`
- checked-in Helm values under `deploy/helm-values/`
- checked-in non-secret render templates under `deploy/manifests/phase-4/`
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
5. Review the non-secret render templates:
   - `deploy/manifests/phase-4/ingress-gateway-config.yaml.template`
   - `deploy/manifests/phase-4/istio-gateway.yaml.template`
6. Run the human-owned scripts in this exact order:
   - `./deploy/scripts/01-install-k3s.sh`
   - `./deploy/scripts/02-bootstrap-cluster.sh`
   - `./deploy/scripts/03-render-phase-4-istio-manifests.sh`
   - `./deploy/scripts/04-install-istio.sh`
   - `./deploy/scripts/05-install-platform-controllers.sh`
   - `./deploy/scripts/06-configure-host-redirects.sh`
   - `./deploy/scripts/07-apply-network-policies.sh`
   - `./deploy/scripts/08-verify-network-policy-enforcement.sh`

## Expected Inputs

`~/.config/budget-analyzer/instance.env` is the only required Phase 4 input file outside the repo. It holds non-secret deployment metadata:

- OCI tenancy, compartment, vault, instance, subnet, and region identifiers
- the instance public IP and SSH key path
- the public demo hostname plus any optional observability hostnames for later phases
- the Let's Encrypt contact email

Do not put secret payloads in `instance.env`. Secret values stay in OCI Vault and later `ExternalSecret` resources.

Do not duplicate production image refs in `instance.env`. Production image inventory stays in `kubernetes/production/apps/image-inventory.yaml`.

## Host Tooling Prerequisites

Phase 4 assumes the host already has `kubectl`, `helm`, and the standard shell tools used by the scripts.

- `./deploy/scripts/04-install-istio.sh` and `./deploy/scripts/05-install-platform-controllers.sh` require `helm`.
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
| `deploy/scripts/06-configure-host-redirects.sh` | Adds persistent host `iptables` redirects for any ingress NodePorts that currently exist, replacing stale redirects on rerun if a NodePort changes or disappears. | Re-run if the gateway service ports change, especially when Phase 11 adds or removes HTTPS. |
| `deploy/scripts/07-apply-network-policies.sh` | Applies the checked-in NetworkPolicy manifests after namespaces and controllers exist. | Re-run after policy edits or after rebuilding the cluster. |
| `deploy/scripts/08-verify-network-policy-enforcement.sh` | Creates disposable probe/listener pods and proves the checked-in allow/deny contract against the live k3s NetworkPolicy implementation. | Re-run after policy edits, CNI changes, or any cluster rebuild before claiming Phase 4 complete. |

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

If you are resuming at Phase 4 Chunk 4, the repo is already complete through Step 12. The next open step is Step 13.

1. Reconfirm the Chunk 3 ingress state before starting Step 13.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   kubectl get gateway -n istio-ingress
   kubectl get svc -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway
   ```
2. Step 13 and Step 14: run the shared controller-install script once, then verify both controllers.
   ```bash
   ./deploy/scripts/05-install-platform-controllers.sh
   helm list -n external-secrets
   helm list -n cert-manager
   kubectl get pods -n external-secrets
   kubectl get pods -n cert-manager
   ```
3. Step 15: add the host redirects only after the ingress NodePorts are present.
   ```bash
   ./deploy/scripts/06-configure-host-redirects.sh
   sudo iptables -t nat -S PREROUTING
   ```
4. Step 16a: apply the checked-in NetworkPolicy manifests.
   ```bash
   ./deploy/scripts/07-apply-network-policies.sh
   kubectl get networkpolicy -A
   ```
5. Step 16b: run the runtime NetworkPolicy verifier.
   ```bash
   ./deploy/scripts/08-verify-network-policy-enforcement.sh
   ```
6. Stop if any step above fails. Do not move to Phase 5 until Step 16b passes.

## Phase Boundary Notes

`deploy/scripts/03-render-phase-4-istio-manifests.sh` intentionally renders an HTTP-only `Gateway` with a single host-agnostic listener and omits `spec.listeners[].hostname`. That keeps the checked-in localhost `HTTPRoute` manifests attachable during Phase 4 while still leaving room for later host-specific route renders and ACME HTTP-01 challenge routes. Public certificate issuance and the final HTTPS listener secret wiring stay in Phase 11.

`deploy/scripts/06-configure-host-redirects.sh` only redirects the ports that the auto-provisioned ingress Service actually exposes. On the initial Phase 4 run that is expected to be port `80` only. The script programs `nat/PREROUTING`, which is the chain used for incoming host traffic. Re-run the same script after Phase 11 if the ingress service later exposes `443`; rerunning also removes stale redirects if a previously exposed listener disappears.

The checked-in ingress NetworkPolicy allow list must continue to admit that Phase 4 HTTP listener so ACME HTTP-01 reachability is not cut off when `deploy/scripts/07-apply-network-policies.sh` runs.

## Validation Standard

Every committed `deploy/scripts/*.sh` file must pass:

- `bash -n <script>`
- `shellcheck -x <script>`

The render path must also be provable locally with sample non-secret input so reviewers can inspect generated YAML under `tmp/phase-4/`.
