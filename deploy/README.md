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

## Expected Inputs

`~/.config/budget-analyzer/instance.env` is the only required Phase 4 input file outside the repo. It holds non-secret deployment metadata:

- OCI tenancy, compartment, vault, instance, subnet, and region identifiers
- the instance public IP and SSH key path
- the public demo hostname plus any optional observability hostnames for later phases
- the Let's Encrypt contact email

Do not put secret payloads in `instance.env`. Secret values stay in OCI Vault and later `ExternalSecret` resources.

Do not duplicate production image refs in `instance.env`. Production image inventory stays in `kubernetes/production/apps/image-inventory.yaml`.

## Script Map

| Script | Purpose | Reused Later |
| --- | --- | --- |
| `deploy/scripts/01-install-k3s.sh` | Installs the pinned k3s release with the repo's Istio-friendly flags and prints the base cluster snapshot. | Re-run only if the host must be rebuilt or reconciled to the pinned k3s version. |
| `deploy/scripts/02-bootstrap-cluster.sh` | Installs the pinned Gateway API CRDs and creates or labels every namespace Phase 4 depends on. | Re-run after a cluster rebuild or if namespace labels drift. |
| `deploy/scripts/03-render-phase-4-istio-manifests.sh` | Renders the Phase 4 ingress ConfigMap and wildcard HTTP Gateway into `tmp/phase-4/`. | Re-run before Phase 11 adds the TLS listener or whenever the reviewed ingress render output changes. |
| `deploy/scripts/04-install-istio.sh` | Installs `istio-base`, `istio-cni`, `istiod`, the egress gateway, then applies the rendered ingress manifests plus mesh security policies. | Re-run after changing Istio pins, values, or the rendered ingress manifests. |
| `deploy/scripts/05-install-platform-controllers.sh` | Installs External Secrets Operator and cert-manager from the pinned charts and checked-in values. | Re-run when Phase 5 or Phase 11 needs controller value changes. |
| `deploy/scripts/06-configure-host-redirects.sh` | Adds persistent host `iptables` redirects for any ingress NodePorts that currently exist, replacing stale redirects on rerun if a NodePort changes or disappears. | Re-run if the gateway service ports change, especially when Phase 11 adds or removes HTTPS. |
| `deploy/scripts/07-apply-network-policies.sh` | Applies the checked-in NetworkPolicy manifests after namespaces and controllers exist. | Re-run after policy edits or after rebuilding the cluster. |

## Phase Boundary Notes

`deploy/scripts/03-render-phase-4-istio-manifests.sh` intentionally renders an HTTP-only `Gateway` with a single wildcard listener. That keeps the checked-in localhost `HTTPRoute` manifests attachable during Phase 4 while still leaving room for later host-specific route renders and ACME HTTP-01 challenge routes. Public certificate issuance and the final HTTPS listener secret wiring stay in Phase 11.

`deploy/scripts/06-configure-host-redirects.sh` only redirects the ports that the auto-provisioned ingress Service actually exposes. On the initial Phase 4 run that is expected to be port `80` only. Re-run the same script after Phase 11 if the ingress service later exposes `443`; rerunning also removes stale redirects if a previously exposed listener disappears.

The checked-in ingress NetworkPolicy allow list must continue to admit that Phase 4 HTTP listener so ACME HTTP-01 reachability is not cut off when `deploy/scripts/07-apply-network-policies.sh` runs.

## Validation Standard

Every committed `deploy/scripts/*.sh` file must pass:

- `bash -n <script>`
- `shellcheck -x <script>`

The render path must also be provable locally with sample non-secret input so reviewers can inspect generated YAML under `tmp/phase-4/`.
