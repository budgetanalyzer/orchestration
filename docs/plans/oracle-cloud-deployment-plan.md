# Oracle Cloud Deployment Plan

**Date:** 2026-04-12
**Status:** Revised plan
**Based on:** [`single-instance-demo-hosting.md`](../research/single-instance-demo-hosting.md), [`oracle-cloud-always-free-provisioning.md`](../research/oracle-cloud-always-free-provisioning.md), [`production-secrets-and-ai-agent-boundaries.md`](../research/production-secrets-and-ai-agent-boundaries.md), [`split-local-and-production-kyverno-image-policy-2026-03-27.md`](./split-local-and-production-kyverno-image-policy-2026-03-27.md), [`service-common-docker-build-strategy.md`](./service-common-docker-build-strategy.md)

Deploy the full Budget Analyzer architecture - k3s, Istio service mesh, application services, infrastructure (PostgreSQL/Redis/RabbitMQ), and the observability bundle (Prometheus/Grafana/Jaeger/Kiali) - to an Oracle Cloud Always Free Ampere A1 instance (4 OCPU / 24 GB RAM / 200 GB disk). Cost: $0/mo.

**Fallback:** If Oracle capacity lottery takes more than one week, switch to Hetzner CAX41 (~$40/mo). Same ARM architecture, same production image set.

---

## Production Gates

These gates are non-negotiable. Do not deploy the public demo until all are true.

1. **No mutable/local production images.** Production manifests must not use `:latest`, `:tilt-<hash>`, `imagePullPolicy: Never`, or unqualified local image names such as `transaction-service:latest`. Production image refs should be immutable digest refs, preferably with the human-readable version tag retained: `registry.example.com/budgetanalyzer/transaction-service:v2026.04.12-<gitsha>@sha256:<digest>`.
2. **`service-common` must be resolvable by isolated image builds.** Local `publishToMavenLocal` remains a dev convenience only. Production Java service Docker builds must resolve `service-common` from a real remote Maven repository (recommended: GitHub Packages) using build secrets or CI credentials. Do not copy host `.m2` into Docker contexts and do not expand service Docker contexts to include sibling repos.
3. **Production builds must use immutable dependency versions.** Local development can keep snapshot workflows. Production image builds should consume an immutable `service-common` release/prerelease version and produce versioned application image tags plus digests.
4. **Kyverno image policy must be split by environment.** Local Tilt may keep the approved local-image exception. Production must use a separate production image policy variant that rejects all approved-local `:latest` and `:tilt-<hash>` refs.
5. **Production overlays must exist before deployment.** The checked-in local manifests are not a production deployment as-is. Production needs explicit overlays or generated manifests for image refs, hostnames, TLS secret names, NGINX production config, frontend static assets, Auth0 non-secret config, ExternalSecret resources, and chart values.
6. **NetworkPolicy enforcement must be proven on k3s.** Do not assume the single-node CNI behaves like the local Kind/Calico environment. Verify NetworkPolicy enforcement before treating the public demo as hardened.

---

## Phase 1: OCI Account & Instance Provisioning

**Owner:** Human (manual - involves credit card, region selection, SSH keys)
**Estimated time:** 1-7 days (capacity lottery)

### Pre-requisites

- Physical credit/debit card (not prepaid/virtual)
- SSH keypair: `ssh-keygen -t ed25519 -f ~/.ssh/oci-budgetanalyzer -C "oci-budgetanalyzer"`
- Decision on home region (permanent, cannot be changed)

### Steps

1. **Choose home region.** Phoenix (US audience) or Frankfurt (EU audience). Not Ashburn. Spend 5 minutes checking recent `r/oraclecloud` capacity reports before committing.
2. **Create OCI account** at https://www.oracle.com/cloud/free/. Real name, real address, real card. Expect a small authorization hold that drops off after several days.
3. **Verify free-tier status.** Hamburger menu -> Governance -> Limits, Quotas and Usage. Confirm `VM.Standard.A1.Flex` shows Always Free availability. Do not upgrade to PAYG.
4. **Prepare networking.**
   - Create VCN with Internet Connectivity, or use the default VCN.
   - Add ingress rules to the default security list:
     - `0.0.0.0/0` TCP port `22` (usually pre-existing; restrict to your IP if practical)
     - `0.0.0.0/0` TCP port `80`
     - `0.0.0.0/0` TCP port `443`
   - Confirm Internet Gateway is attached and public subnet routes `0.0.0.0/0` to it.
5. **Provision A1 instance.**
   - Image: **Canonical Ubuntu 22.04 (aarch64)** - verify it says `aarch64`
   - Shape: **VM.Standard.A1.Flex**, 4 OCPU, 24 GB RAM
   - Boot volume: **200 GB** (default is ~47-50 GB; expand it)
   - Networking: public subnet, assign public IPv4
   - SSH key: paste `~/.ssh/oci-budgetanalyzer.pub`
6. **Handle "Out of host capacity."** Expected on first attempt.
   - Try rotating Availability Domains.
   - If that fails, use the `hitrov/oci-arm-host-capacity` retry script from outside this repo.
   - If retries exceed one week, fall back to Hetzner CAX41.
7. **First SSH and verification.**
   ```bash
   ssh -i ~/.ssh/oci-budgetanalyzer ubuntu@<public-ip>
   uname -m      # expect: aarch64
   nproc         # expect: 4
   free -h       # expect: ~24 GB total
   df -h /       # expect: ~200 GB
   ```

### Outputs

- Running A1 instance with public IP
- SSH access confirmed
- Ports 22, 80, and 443 open in OCI networking

---

## Phase 2: Host Hardening & Firewall

**Owner:** Human (SSH session on instance)
**Estimated time:** 15-30 minutes

### Steps

1. **Fix host-level iptables.** Ubuntu on OCI can ship iptables rules that block 80/443 even after the VCN allows them.
   ```bash
   sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
   sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
   sudo apt install -y iptables-persistent
   sudo netfilter-persistent save
   ```
2. **Verify connectivity** from a local machine:
   ```bash
   curl -v http://<public-ip>
   # "connection refused" = good before a listener exists
   # "connection timed out" = iptables or VCN still blocking
   ```
3. **System updates and unattended upgrades.**
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y unattended-upgrades
   sudo dpkg-reconfigure --priority=low unattended-upgrades
   ```
4. **Verify SSH hardening** (should be default on OCI Ubuntu):
   ```bash
   sudo grep -E '^(PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config
   # Expect: PasswordAuthentication no, PermitRootLogin prohibit-password or no
   ```

### Outputs

- Ports 80/443 reachable from the internet
- System patched, auto-updates enabled
- SSH key-only confirmed

---

## Phase 3: Production Image & Build Contract

**Owner:** Service repo maintainers + CI/release workflow
**Estimated time:** 1-2 days if service-common remote publishing is not implemented yet

This phase folds in [`service-common-docker-build-strategy.md`](./service-common-docker-build-strategy.md). It must complete before any production Kubernetes manifests are applied.

### Decisions

1. **Registry:** Use a real registry reachable by the OCI host. Recommended: GHCR under the `budgetanalyzer` organization.
2. **Image version scheme:** Use immutable version tags derived from releases or commits, for example `v2026.04.12-<gitsha>`. Do not publish or deploy production `latest`.
3. **Manifest image format:** Production manifests use digest-pinned refs. Recommended shape:
   ```text
   ghcr.io/budgetanalyzer/transaction-service:v2026.04.12-<gitsha>@sha256:<digest>
   ```
4. **Java dependency source:** Production Docker builds resolve `org.budgetanalyzer:service-common` from a remote Maven repository. Local `mavenLocal()` may remain first for developer workflows, but it is not the production build source.
5. **Production `service-common` version:** Use immutable release/prerelease versions for production. Do not build production images against `0.0.1-SNAPSHOT`; snapshot dependencies are a local-development convenience, not a public demo release contract.

### Steps

1. **Publish `service-common` to a remote Maven repository.**
   - Add a remote publish target in `service-common`.
   - Publish an immutable version.
   - Document credentials outside the workspace.
2. **Update Java service builds to resolve remote `service-common`.**
   - `transaction-service`
   - `currency-service`
   - `permission-service`
   - `session-gateway`
   - Keep `mavenLocal()` for local host builds only.
   - Docker builds must authenticate via build secrets or CI env, never hardcoded tokens.
3. **Build and push production images for all local app repos.**
   - `transaction-service`
   - `currency-service`
   - `permission-service`
   - `session-gateway`
   - `ext-authz`
   - `budget-analyzer-web` production static asset image or an equivalent NGINX-served web bundle image
   - Any repo-owned NGINX/config image if the production overlay chooses to bake config/assets instead of mounting ConfigMaps
4. **Verify ARM64 support.**
   ```bash
   docker buildx imagetools inspect ghcr.io/budgetanalyzer/transaction-service:<version>
   # Expect linux/arm64 in the manifest list, or a single linux/arm64 image.
   ```
5. **Record immutable image refs in a production inventory.**
   - Store non-secret refs in a committed template or generated manifest.
   - Do not store registry tokens in the repo or workspace.

### Outputs

- `service-common` production artifact published remotely
- Java service Docker builds no longer depend on host-only Maven Local state
- All production app images are versioned and digest-pinned
- No production manifest path uses `:latest`, `:tilt-<hash>`, or `imagePullPolicy: Never`

---

## Phase 4: Install k3s, Gateway API, Istio, ESO, and cert-manager

**Owner:** Human executes scripts (Pattern B - idempotent, sources external config)
**Estimated time:** 45-75 minutes

### Steps

1. **Install a pinned k3s version** with Istio-friendly flags.
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=<pinned-supported-version> INSTALL_K3S_EXEC="\
     --disable=traefik \
     --disable=servicelb \
     --disable=metrics-server \
     --write-kubeconfig-mode=644" sh -
   ```
   Use a k3s version compatible with the repo's Istio baseline. Do not leave the install unpinned.
2. **Verify k3s.**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   kubectl get storageclass
   ```
3. **Install Gateway API CRDs before Istio ingress.**
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
   ```
4. **Create and label namespaces before admission policies.**
   - `default`: `istio-injection=enabled`, PSA `restricted`, `budgetanalyzer.io/ingress-routes=true`
   - `infrastructure`: `istio-injection=disabled`, PSA `baseline`
   - `monitoring`: `budgetanalyzer.io/ingress-routes=true`, PSA `baseline`
   - `istio-system`: PSA `privileged`
   - `istio-ingress`: use `kubernetes/istio/ingress-namespace.yaml`
   - `istio-egress`: use `kubernetes/istio/egress-namespace.yaml`
   - `external-secrets` and `cert-manager`: label explicitly before installing charts
5. **Install Istio with pinned chart versions.**
   ```bash
   helm repo add istio https://istio-release.storage.googleapis.com/charts
   helm repo update

   helm upgrade --install istio-base istio/base \
     --namespace istio-system \
     --create-namespace \
     --version 1.29.1 \
     --wait

   helm upgrade --install istio-cni istio/cni \
     --namespace istio-system \
     --version 1.29.1 \
     --values kubernetes/istio/cni-values.yaml \
     --wait

   helm upgrade --install istiod istio/istiod \
     --namespace istio-system \
     --version 1.29.1 \
     --values kubernetes/istio/istiod-values.yaml \
     --wait
   ```
6. **Install the egress gateway from the chart.**
   ```bash
   kubectl apply -f kubernetes/istio/egress-namespace.yaml
   helm upgrade --install istio-egress-gateway istio/gateway \
     --namespace istio-egress \
     --version 1.29.1 \
     --values kubernetes/istio/egress-gateway-values.yaml \
     --wait
   ```
7. **Install the ingress gateway through Gateway API auto-provisioning, not Helm values.**
   - Create a production overlay for `kubernetes/istio/istio-gateway.yaml` with the real hostname.
   - Add an HTTP listener on port `80` for ACME HTTP-01, or choose DNS-01 and omit public port 80 routing to the gateway.
   - Extend the ingress gateway infrastructure ConfigMap if NodePort `80 -> 30080` is required.
   - Apply:
     ```bash
     kubectl apply -f kubernetes/istio/ingress-namespace.yaml
     kubectl apply -f <production-ingress-gateway-config.yaml>
     kubectl apply -f <production-istio-gateway.yaml>
     kubectl wait --for=condition=Programmed gateway/istio-ingress-gateway -n istio-ingress --timeout=120s
     kubectl rollout status deployment/istio-ingress-gateway-istio -n istio-ingress --timeout=120s
     ```
8. **Apply mesh security policies.**
   ```bash
   kubectl apply -f kubernetes/istio/peer-authentication.yaml
   kubectl apply -f kubernetes/istio/authorization-policies.yaml
   ```
   Do not apply raw egress placeholder files yet. Render egress config after production Auth0 issuer config exists.
9. **Install External Secrets Operator with pinned/hardened chart values.**
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm upgrade --install external-secrets external-secrets/external-secrets \
     -n external-secrets \
     --version <pinned-version> \
     --values <production-external-secrets-values.yaml> \
     --wait
   ```
10. **Install cert-manager with Gateway API support enabled and pinned/hardened chart values.**
    ```bash
    helm repo add jetstack https://charts.jetstack.io
    helm upgrade --install cert-manager jetstack/cert-manager \
      -n cert-manager \
      --create-namespace \
      --version <pinned-version> \
      --set installCRDs=true \
      --set config.enableGatewayAPI=true \
      --values <production-cert-manager-values.yaml> \
      --wait
    ```
11. **Set up host port redirects after NodePorts exist.**
    ```bash
    sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 30443
    # Only if the production ingress gateway service exposes nodePort 30080:
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 30080
    sudo netfilter-persistent save
    ```
12. **Apply network policies after namespaces exist.**
    ```bash
    kubectl apply -f kubernetes/network-policies/
    ```
    Validate enforcement on k3s. If the selected k3s CNI does not enforce the repo's NetworkPolicy contract correctly, install a supported CNI such as Calico before continuing.

### Outputs

- k3s running, single node Ready
- Gateway API CRDs installed
- Istio mesh installed with STRICT mTLS policy ready for meshed app namespaces
- Ingress gateway auto-provisioned from Gateway API, not installed from the ConfigMap as Helm values
- ESO and cert-manager installed before production secrets/TLS work
- NetworkPolicy manifests applied after target namespaces exist, with enforcement validation pending runtime smoke tests

---

## Phase 5: OCI Vault, External Secrets, and Internal TLS

**Owner:** Human for OCI/IAM/secret values; AI may write templates only
**Estimated time:** 1-2 hours

### Principle

AI agents work with secret names and vault paths, never secret values. Templates and manifests are committed; populated values never enter the repo or workspace.

### Steps

1. **Create instance config directory** on the project owner's local machine.
   ```bash
   mkdir -p ~/.config/budget-analyzer
   cp deploy/instance.env.template ~/.config/budget-analyzer/instance.env
   # Fill in OCIDs, public IP, domain, release version, and image inventory refs.
   ```
2. **Create OCI Vault resources.**
   - Use an Always Free-compatible OCI Vault setup.
   - Do not choose paid Virtual Private Vault features.
   - Keep vault OCIDs outside the workspace.
3. **Create IAM dynamic group** matching the compute instance.
   ```text
   instance.id = '<instance-ocid>'
   ```
4. **Create IAM policy** allowing the instance to read vault secrets.
   ```text
   Allow dynamic-group budgetanalyzer-instance to read secret-family in compartment <compartment-name>
   ```
5. **Populate vault secrets** via OCI Console or OCI CLI outside AI sessions.
   - `budget-analyzer/auth0-client-secret`
   - `budget-analyzer/fred-api-key`
   - `budget-analyzer/postgres-admin-password`
   - `budget-analyzer/postgres-transaction-svc`
   - `budget-analyzer/postgres-currency-svc`
   - `budget-analyzer/postgres-permission-svc`
   - `budget-analyzer/rabbitmq-admin-password`
   - `budget-analyzer/rabbitmq-definitions`
   - `budget-analyzer/rabbitmq-currency-svc`
   - `budget-analyzer/redis-default-password`
   - `budget-analyzer/redis-ops-password`
   - `budget-analyzer/redis-session-gateway`
   - `budget-analyzer/redis-ext-authz`
   - `budget-analyzer/redis-currency-svc`
6. **Create a `ClusterSecretStore` or per-namespace `SecretStore`s.**
   - A namespaced `SecretStore` in `infrastructure` is not enough for `ExternalSecret` resources in `default`.
   - Recommended first iteration: one `ClusterSecretStore` with explicit namespace policy review.
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ClusterSecretStore
   metadata:
     name: oci-vault
   spec:
     provider:
       oracle:
         vault: <vault-ocid>
         region: <home-region>
         auth:
           instancePrincipal: true
   ```
7. **Create `ExternalSecret` manifests** for native Kubernetes Secrets in the correct target namespaces.
   - `auth0-credentials` in `default`
   - `fred-api-credentials` in `default`
   - service PostgreSQL/RabbitMQ/Redis credentials in `default`
   - bootstrap PostgreSQL/RabbitMQ/Redis credentials in `infrastructure`
8. **Create production non-secret ConfigMaps.**
   - `session-gateway-idp-config` must contain production `AUTH0_CLIENT_ID`, `AUTH0_ISSUER_URI`, `IDP_AUDIENCE`, and `IDP_LOGOUT_RETURN_TO`.
   - These are not secret values, but do not leave placeholder localhost values in production.
9. **Create internal infrastructure TLS secrets.**
   Current workloads require:
   - `infra-ca` in `default`
   - `infra-ca` in `infrastructure`
   - `infra-tls-postgresql` in `infrastructure`
   - `infra-tls-redis` in `infrastructure`
   - `infra-tls-rabbitmq` in `infrastructure`

   Pick one explicit production mechanism before deploying infrastructure:
   - human-run host/instance script that generates and applies these secrets, or
   - cert-manager private CA resources, or
   - OCI Vault-backed material synced through ESO.

   Do not have AI agents generate or handle certificate private keys.

### Outputs

- OCI Vault populated with all application secret values
- ESO syncs vault secrets into native Kubernetes Secrets
- Production Auth0 non-secret config exists
- Internal TLS secrets exist before infrastructure pods start

---

## Phase 6: Production Manifests and Overlays

**Owner:** AI agent may write manifests/scripts; human reviews
**Estimated time:** 1-2 days

This phase turns the local repo manifests into a production deployment artifact. It should produce committed, reviewable YAML or scripts with no secret values.

### Required production overlay changes

1. **Images**
   - Replace every local app image with a versioned digest ref from Phase 3.
   - Remove every `imagePullPolicy: Never` from production manifests.
   - Remove `budget-analyzer-web-prod-smoke:latest` from the production NGINX path.
   - Keep third-party images digest-pinned.
2. **Frontend**
   - Do not deploy the Vite dev server as the production frontend.
   - Serve a production static bundle through NGINX or a production web image.
   - Use `nginx/nginx.production.k8s.conf`, not `nginx/nginx.k8s.conf`, for the public app route.
3. **NGINX ConfigMaps**
   - Create production equivalents for `nginx-gateway-config`, `nginx-gateway-includes`, and `nginx-gateway-docs`.
   - Make `/api/*`, `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`, `/login`, `/`, and `/api-docs` match the current route contract.
4. **Gateway API resources**
   - Replace `app.budgetanalyzer.localhost` and `grafana.budgetanalyzer.localhost` with production hostnames.
   - Keep direct auth-path routing to Session Gateway.
   - Keep API/frontend routing through NGINX.
5. **Istio egress config**
   - Render `kubernetes/istio/egress-service-entries.yaml` and `kubernetes/istio/egress-routing.yaml` from the production `AUTH0_ISSUER_URI`.
   - Do not apply the checked-in placeholder host.
6. **Monitoring**
   - Keep the kube-prometheus-stack release name aligned with `kubernetes/monitoring/grafana-httproute.yaml`; the current checked-in route expects `prometheus-stack-grafana`.
   - Add committed, pinned, hardened values for Jaeger and Kiali before exposing them.
7. **Storage**
   - PostgreSQL and RabbitMQ already use PVCs.
   - Redis currently uses `emptyDir`; either document intentional ephemeral session loss for the demo or create a production PVC-backed Redis variant.
8. **Verification scripts**
   - Add a production render/static verifier that fails on:
     - `:latest`
     - `:tilt-`
     - `imagePullPolicy: Never`
     - `budgetanalyzer.localhost`
     - `auth0-issuer.placeholder.invalid`
     - `nginx.k8s.conf` on the production route

### Outputs

- Production manifests or deploy scripts exist as first-class artifacts
- No production path relies on Tilt-only ConfigMap creation
- No production path relies on local dev image names or frontend dev server behavior

---

## Phase 7: Production Kyverno Admission Policy

**Owner:** AI agent may write manifests/tests; human reviews
**Estimated time:** 4-8 hours

This phase folds in [`split-local-and-production-kyverno-image-policy-2026-03-27.md`](./split-local-and-production-kyverno-image-policy-2026-03-27.md).

### Required policy layout

```text
kubernetes/kyverno/policies/shared/
  00-smoke-disallow-privileged.yaml
  10-require-namespace-pod-security-labels.yaml
  20-require-workload-automount-disabled.yaml
  30-require-workload-security-context.yaml
  40-disallow-obvious-default-credentials.yaml

kubernetes/kyverno/policies/local/
  50-require-third-party-image-digests.yaml

kubernetes/kyverno/policies/production/
  50-require-third-party-image-digests.yaml
```

### Production policy behavior

- Allows digest-pinned third-party images.
- Allows Istio sidecar/system image cases intentionally covered by the policy.
- Rejects all approved local `:latest` refs.
- Rejects all approved local `:tilt-<hash>` refs.
- Rejects unapproved mutable refs.
- Uses the same policy name as the local variant, but production applies exactly one variant: `shared + production`.

### Steps

1. **Restructure Kyverno policy directories.**
2. **Update Tilt to apply `shared + local` only.**
3. **Add production Kyverno tests.**
   - local `:latest` fails
   - local `:tilt-<hash>` fails
   - digest-pinned third-party passes
   - unapproved mutable refs fail
4. **Install Kyverno with pinned chart version and hardened values.**
   ```bash
   helm repo add kyverno https://kyverno.github.io/kyverno/
   helm upgrade --install kyverno kyverno/kyverno \
     -n kyverno \
     --create-namespace \
     --version 3.7.1 \
     --values <production-kyverno-values.yaml> \
     --wait
   ```
5. **Apply production policies only.**
   ```bash
   kubectl apply -f kubernetes/kyverno/policies/shared/
   kubectl apply -f kubernetes/kyverno/policies/production/
   ```
6. **Run production policy verification before deploying repo-managed workloads.**

### Outputs

- Local and production image-admission contracts are separate
- Production admission cannot accept `transaction-service:latest` or Tilt deploy tags
- Static guardrails prevent local exceptions from leaking into production policy

---

## Phase 8: Deploy Infrastructure Services

**Owner:** Human executes script (Pattern B)
**Estimated time:** 15-30 minutes

### Steps

1. **Verify namespace labels and required secrets.**
   ```bash
   kubectl get namespace infrastructure --show-labels
   kubectl get secrets -n infrastructure
   kubectl get secret -n default infra-ca
   kubectl get secret -n infrastructure infra-ca infra-tls-postgresql infra-tls-redis infra-tls-rabbitmq
   ```
2. **Deploy PostgreSQL.**
   ```bash
   kubectl apply -f kubernetes/infrastructure/postgresql/
   ```
3. **Deploy RabbitMQ.**
   ```bash
   kubectl apply -f kubernetes/infrastructure/rabbitmq/
   ```
4. **Deploy Redis.**
   ```bash
   kubectl apply -f <production-redis-manifest-or-current-ephemeral-redis.yaml>
   ```
5. **Verify infrastructure pods.**
   ```bash
   kubectl get pods -n infrastructure
   ```
   Current repo design disables Istio sidecar injection for `infrastructure`; expect one app container per pod, not `2/2`. Infrastructure transport encryption is provided by PostgreSQL/Redis/RabbitMQ TLS plus mesh-protected app namespaces.

### Outputs

- PostgreSQL, RabbitMQ, and Redis running in `infrastructure`
- PVC-backed data for PostgreSQL/RabbitMQ
- Redis persistence decision documented and implemented
- Infrastructure TLS active

---

## Phase 9: Deploy Application Services

**Owner:** Human executes script (Pattern B)
**Estimated time:** 30-60 minutes

### Pre-requisites

- Phase 3 production image inventory completed
- Phase 6 production overlays completed
- Phase 7 production Kyverno policy active
- ESO-created service secrets ready in `default`
- Production Auth0 callback/logout URLs configured in Auth0

### Steps

1. **Verify service secrets and production non-secret IDP config.**
   ```bash
   kubectl get secrets -n default
   kubectl get configmap -n default session-gateway-idp-config -o yaml
   ```
2. **Render and apply Istio egress config from production Auth0 issuer.**
   ```bash
   ./scripts/ops/render-istio-egress-config.sh --apply --auth0-issuer-uri "<production-auth0-issuer-uri>"
   ```
3. **Apply app production overlays.**
   ```bash
   kubectl apply -f <production-services-overlay-or-rendered-output>
   ```
4. **Apply production HTTPRoutes.**
   ```bash
   kubectl apply -f <production-gateway-routes-overlay-or-rendered-output>
   ```
5. **Apply ext_authz policy and ingress rate-limit policy after ext-authz is ready.**
   ```bash
   kubectl apply -f kubernetes/istio/ext-authz-policy.yaml
   kubectl apply -f kubernetes/istio/ingress-rate-limit.yaml
   ```
6. **Verify app pods and image refs.**
   ```bash
   kubectl get pods -n default
   kubectl get pods -n default -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u
   ```
   Every repo-owned app pod in `default` should have an Istio sidecar. No listed image may contain `:latest`, `:tilt-`, or a local-only repo ref.
7. **Smoke test through ingress.**
   ```bash
   curl -kisS https://<public-ip>/health
   curl -kisS https://<production-app-domain>/health
   ```

### Outputs

- All application services running with production images
- ext_authz session-edge pattern active
- Traffic routing through Istio ingress -> Session Gateway or NGINX -> services
- No local/Tilt image refs admitted

---

## Phase 10: Deploy Observability Bundle

**Owner:** Human executes script (Pattern B)
**Estimated time:** 45-90 minutes

The observability surface is part of the demo. It should be live but read-only.

### Steps

1. **Install kube-prometheus-stack with the checked-in release name and values.**
   ```bash
   kubectl apply -f kubernetes/monitoring/namespace.yaml
   kubectl apply -f kubernetes/monitoring/grafana-dashboards-configmap.yaml

   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
     -n monitoring \
     --version 83.4.0 \
     --values kubernetes/monitoring/prometheus-stack-values.yaml \
     --wait --timeout 5m

   kubectl apply -f kubernetes/monitoring/servicemonitor-spring-boot.yaml
   ```
2. **Install Jaeger with committed production values.**
   - Keep query UI enabled if Kiali or visitors need the UI.
   - Pin every chart image by digest.
   - Use Badger or another explicit storage backend.
3. **Install Kiali with committed production values.**
   - Configure Prometheus, Grafana, and Jaeger URLs to match actual release names.
   - Set view-only/public behavior deliberately.
   - Pin every chart image by digest.
4. **Configure Istio tracing extension provider.**
   - Add the Jaeger collector to `meshConfig.extensionProviders`.
   - Keep the existing `ext-authz-http` provider.
   - `helm upgrade` istiod with the updated production values.
5. **Expose only read-only UIs.**
   - Grafana: anonymous Viewer or shared read-only credentials.
   - Kiali: anonymous/read-only mode or route-level protection.
   - Jaeger: read-only UI.
   - Prometheus: keep internal; do not expose the Prometheus admin/API surface publicly.
6. **Apply production observability HTTPRoutes.**
   ```bash
   kubectl apply -f <production-observability-routes>
   ```

### Outputs

- Prometheus scraping app, Kubernetes, and Istio targets
- Grafana dashboards available read-only
- Jaeger collecting traces
- Kiali showing the live service mesh graph
- Public observability routes do not expose mutating/admin capabilities

---

## Phase 11: Public TLS, DNS, and Uptime Monitoring

**Owner:** Human (DNS requires registrar access)
**Estimated time:** 30-60 minutes

### Steps

1. **Point DNS** at the instance public IPv4.
   - Example: `demo.yourdomain.com`
   - Optional separate hosts: `grafana.demo.yourdomain.com`, `kiali.demo.yourdomain.com`, `jaeger.demo.yourdomain.com`
2. **Create Let's Encrypt ClusterIssuer.**
   - cert-manager must have Gateway API support enabled.
   - HTTP-01 requires an existing Gateway listener on port `80`.
   - Use the actual Gateway name: `istio-ingress-gateway`.
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: <your-email>
       privateKeySecretRef:
         name: letsencrypt-prod
       solvers:
         - http01:
             gatewayHTTPRoute:
               parentRefs:
                 - name: istio-ingress-gateway
                   namespace: istio-ingress
                   kind: Gateway
   ```
3. **Create Certificate resource(s).**
   - Prefer storing the public TLS secret in `istio-ingress` so the Gateway can reference it without a cross-namespace `ReferenceGrant`.
   - If the secret remains in `default`, create a production `ReferenceGrant` matching the production secret name.
4. **Update the production Gateway** to reference the cert-manager-managed TLS secret.
5. **Verify certificate readiness and renewal path.**
   ```bash
   kubectl get certificate -A
   kubectl describe certificate -n istio-ingress <certificate-name>
   curl -Iv https://<production-app-domain>/health
   ```
6. **Set up UptimeRobot or equivalent.**
   - HTTP check on `https://<production-app-domain>/health` every 5 minutes.
   - Purpose: catch outages and keep JVMs warm.
   - Do not rely on uptime checks to satisfy OCI idle policy; verify OCI 7-day CPU/memory/network metrics directly.

### Outputs

- Valid HTTPS with auto-renewing Let's Encrypt certs
- DNS points at the instance
- External uptime checks alert on failures

---

## Phase 12: Backup, Runbook, and Go-Live

**Owner:** Human + AI agent for non-secret scripts/docs
**Estimated time:** 2-4 hours

### Steps

1. **Set up daily PostgreSQL logical backup.**
   ```bash
   # Cron: daily pg_dump -> Cloudflare R2, Backblaze B2, or OCI Object Storage
   0 3 * * * /usr/local/bin/backup-postgres.sh
   ```
2. **Set up OCI Block Volume backup policy.**
   - Always Free includes a limited number of volume backups.
   - Cap retention so backup creation does not fail after the free allocation is exhausted.
3. **Document Redis recovery behavior.**
   - If Redis remains ephemeral, document that outages log users out.
   - If Redis gets a PVC, include it in restore testing.
4. **Build the demo landing page** that links to:
   - Budget Analyzer app
   - Kiali service mesh graph
   - Grafana dashboards
   - Sample Jaeger trace from a recent request
5. **Write runbook** covering:
   - cert renewal verification
   - PostgreSQL backup/restore
   - k3s upgrade
   - Istio upgrade
   - image release and rollback
   - Kyverno local/production policy distinction
   - box died: restore from snapshot
   - instance reclaimed: restart and recover
6. **Disaster recovery drill.**
   - Stop/restart the instance and verify the stack returns.
   - Restore PostgreSQL into a clean environment.
   - If recovery takes more than one hour, the runbook is not done.
7. **Monthly maintenance reminders.**
   - Log into OCI console once per month.
   - Check OCI Metrics for CPU/memory/network utilization.
   - Check cert-manager certificate status.
   - Do not touch "Upgrade to PAYG."
8. **Go live** only after DR drill succeeds.

### Outputs

- Automated database backups
- Bounded volume backup policy
- Tested disaster recovery procedure
- Demo landing page live
- URL ready for resume

---

## Resource Budget Summary

| Layer | RAM (realistic) |
|---|---:|
| Application services (7 pods) | ~3.0 GiB |
| Infrastructure (PostgreSQL + RabbitMQ + Redis) | ~1.25 GiB |
| Platform (k3s + Istio + Kyverno + ESO + cert-manager) | ~3.0 GiB |
| Observability (Prometheus + Grafana + Jaeger + Kiali) | ~2.9 GiB |
| OS + page cache + headroom | ~1.0 GiB |
| **Total** | **~10.15 GiB** |
| **Available (Oracle A1)** | **24 GiB** |
| **Headroom** | **~13.8 GiB** |

---

## What AI Agents Can and Cannot Do

| Task | Agent role |
|---|---|
| Write production manifests, overlays, render scripts, ExternalSecret YAMLs, and documentation | Pattern C - agent writes, human reviews |
| Write deployment scripts that source `~/.config/budget-analyzer/instance.env` | Pattern B - agent writes script, human executes |
| Create OCI Vault, populate secrets, configure IAM, configure DNS | Pattern A - agent writes templates with placeholders, human fills values and executes |
| Build/push production images | Human/CI release workflow; agents may write CI/templates but must not handle registry secrets |
| Generate or handle production certificate private keys | Never in AI sessions |
| Read/modify production secret values | Never - secrets live outside the workspace |

---

## Remaining Prototype Gates

1. **Production image pipeline:** implement remote `service-common` publishing and verify isolated Docker builds for all Java services.
2. **Production Kyverno split:** create `shared`, `local`, and `production` policy paths and tests.
3. **cert-manager + Istio Gateway HTTP-01:** prove the port 80 listener and solver route end-to-end, or choose DNS-01.
4. **Jaeger/Kiali production chart values:** pin images, harden security contexts, and align service names with Kiali config.
5. **Redis persistence:** decide ephemeral sessions versus PVC-backed Redis.
6. **FRED API limits:** confirm demo polling does not exceed limits from one public IP.
7. **Auth0 friction:** keep Auth0 for the architecture showcase unless a separate demo-user path is deliberately designed and documented.

---

## Escape Hatch

If Oracle does not work out (capacity lottery >1 week, account flagging, reclamation headaches):

**Hetzner CAX41** - EUR 31.49/mo + EUR 6.30 backups (~$40/mo)

- 16 vCPU ARM, 32 GB RAM, 320 GB NVMe, 20 TB egress
- Same ARM architecture, same production image set
- One-click backups, no capacity lottery
- EU-only (120-160 ms to US is fine for this HTTP demo)

Do not spend more than a week trying to save $40/mo.
