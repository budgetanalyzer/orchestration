# Oracle Cloud Deployment Plan

**Date:** 2026-04-12
**Status:** Revised plan
**Based on:** [`single-instance-demo-hosting.md`](../research/single-instance-demo-hosting.md), [`oracle-cloud-always-free-provisioning.md`](../research/oracle-cloud-always-free-provisioning.md), [`production-secrets-and-ai-agent-boundaries.md`](../research/production-secrets-and-ai-agent-boundaries.md), [`split-local-and-production-kyverno-image-policy-2026-03-27.md`](./split-local-and-production-kyverno-image-policy-2026-03-27.md), [`service-common-docker-build-strategy.md`](./service-common-docker-build-strategy.md)

Deploy the full Budget Analyzer architecture - k3s, Istio service mesh, application services, infrastructure (PostgreSQL/Redis/RabbitMQ), and the observability bundle (Prometheus/Grafana/Jaeger/Kiali) - to an Oracle Cloud Always Free Ampere A1 instance (4 OCPU / 24 GB RAM / 200 GB disk). Cost: $0/mo.

**Fallback:** If Oracle capacity lottery takes more than one week, switch to Hetzner CAX41 (~$40/mo). Same ARM architecture, same production image set.

---

## Production Gates

These gates are non-negotiable. Do not deploy the public demo until all are true.

1. **No mutable/local production images.** Production manifests must not use `:latest`, `:tilt-<hash>`, `imagePullPolicy: Never`, or unqualified local image names such as `transaction-service:latest`. Production image refs should be immutable digest refs, preferably with the human-readable numeric SemVer tag retained: `ghcr.io/budgetanalyzer/transaction-service:0.0.8@sha256:<digest>`.
2. **`service-common` must be resolvable by isolated image builds.** Local `publishToMavenLocal` remains a dev convenience only. Production Java service Docker builds must resolve `service-common` from a real remote Maven repository (recommended: GitHub Packages) using build secrets or CI credentials. Do not copy host `.m2` into Docker contexts and do not expand service Docker contexts to include sibling repos.
3. **Production builds must use immutable dependency versions.** Local development can keep snapshot workflows. Production image builds should consume an immutable `service-common` release/prerelease version and produce versioned application image tags plus digests.
4. **Kyverno image policy must be split by environment.** Local Tilt may keep the approved local-image exception. Production must use a separate production image policy variant that rejects all approved-local `:latest` and `:tilt-<hash>` refs.
5. **Production overlays must exist before deployment.** The checked-in local manifests are not a production deployment as-is. Production needs explicit overlays or generated manifests for image refs, hostnames, TLS secret names, NGINX production config, frontend static assets, Auth0 non-secret config, ExternalSecret resources, and chart values.
6. **NetworkPolicy enforcement must be proven on k3s.** Do not assume the single-node CNI behaves like the local Kind/Calico environment. Verify NetworkPolicy enforcement before treating the public demo as hardened.
7. **The local getting-started flow must stay credential-free.** A contributor following `docs/development/getting-started.md` with the side-by-side workspace and `tilt up` must not need `GITHUB_ACTOR`, `GITHUB_TOKEN`, or a personal access token just to build and start the app locally. Remote package auth is allowed only for release or isolated-build paths.

---

## Phase 1: OCI Account & Instance Provisioning

**Owner:** Human (manual - involves credit card, region selection, SSH keys)
**Status:** Complete as of 2026-04-13. Verified A1/aarch64 instance with 4 OCPU, 23 GiB RAM, and a 194G root filesystem, which is the expected Linux view of the 200 GB OCI boot volume.
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
   df -h /       # expect: roughly 190-200G; 194G is normal for the 200 GB boot volume
   ```

### Outputs

- Running A1 instance with public IP
- SSH access confirmed
- Ports 22, 80, and 443 open in OCI networking

---

## Phase 2: Host Hardening & Firewall

**Owner:** Human (SSH session on instance)
**Status:** Complete as of 2026-04-13. Verified external 80/443 reachability reaches the host and returns `connection refused` before a listener exists; effective SSH config reports `passwordauthentication no` and root password login disabled via `permitrootlogin without-password`.
**Estimated time:** 15-30 minutes

### Steps

1. **Fix host-level iptables.** Ubuntu on OCI can ship iptables rules that block 80/443 even after the VCN allows them.
   ```bash
   while sudo iptables -C INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT 2>/dev/null; do
     sudo iptables -D INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT
   done
   while sudo iptables -C INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT 2>/dev/null; do
     sudo iptables -D INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT
   done
   reject_line="$(sudo iptables -L INPUT --line-numbers -n | awk '$2 == "REJECT" {print $1; exit}')"
   sudo iptables -I INPUT "${reject_line:-1}" -m state --state NEW -p tcp --dport 80 -j ACCEPT
   sudo iptables -I INPUT "${reject_line:-1}" -m state --state NEW -p tcp --dport 443 -j ACCEPT
   sudo iptables -L INPUT --line-numbers -n | sed -n '1,20p'
   sudo apt install -y iptables-persistent
   sudo netfilter-persistent save
   ```
2. **Verify connectivity** from a local machine:
   ```bash
   curl -v http://<public-ip>
   # "connection refused" = good before a listener exists
   # "No route to host" = host iptables is probably still rejecting before the 80/443 allow rules
   # "connection timed out" = OCI VCN security list/NSG/routing is probably still blocking
   ```
   Run this from your workstation, not from the SSH session on the instance. If `No route to host` persists, verify the port 80 and 443 `ACCEPT` rules appear before any broad `REJECT` rule in the `iptables -L INPUT --line-numbers -n` output. Rules after the broad `REJECT` are dead code and will not open the ports.
3. **System updates and unattended upgrades.**
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y unattended-upgrades
   sudo dpkg-reconfigure --priority=low unattended-upgrades
   ```
4. **Verify SSH hardening** (should be default on OCI Ubuntu):
   ```bash
   ssh -V
   apt-cache policy openssh-server
   sudo sshd -T | grep -E '^(passwordauthentication|permitrootlogin) '
   # Expect: passwordauthentication no
   # Expect: permitrootlogin prohibit-password, without-password, or no
   ```
   No output from grepping only `/etc/ssh/sshd_config` is not enough to prove the setting either way; Ubuntu cloud images can use included files under `/etc/ssh/sshd_config.d/` and compiled defaults. `sshd -T` prints the effective server configuration. `without-password` is the older spelling for `prohibit-password` and is acceptable here because it still disables root password login.

### Outputs

- Ports 80/443 reachable from the internet
- System patched, auto-updates enabled
- SSH key-only confirmed

---

## Phase 3: Production Image & Build Contract

**Source of truth:** This section is the source of truth for Oracle Cloud Phase 3 execution. [`service-common-docker-build-strategy.md`](./service-common-docker-build-strategy.md) is supporting background for why Maven Local is insufficient for isolated Docker builds; it is not a separate deployment plan.
**Owner:** Human for org/package settings and release approval; AI Assistant for repo configuration, workflow templates, documentation, and non-secret manifest inventory; CI/release workflow for publishing.
**Status:** Strategy clarified on 2026-04-13; detailed human work breakdown added 2026-04-13; updated on 2026-04-14 to treat GitHub Packages as CI-only infrastructure for `service-common`; implementation checkpoint reached through Chunk 2 Step 14 from the previous draft.
**Estimated time:** Remaining work is roughly 0.5-1 day after the Chunk 2 Step 14 checkpoint, assuming the initial `service-common` workflow publish is already proven.

This phase must complete before any production Kubernetes manifests are applied.

### Registry Decision

Use GitHub registries under the `budgetanalyzer` organization, but keep the two package types separate:

| Artifact | Registry | Example |
|---|---|---|
| Container images | GitHub Container Registry (GHCR) | `ghcr.io/budgetanalyzer/transaction-service:0.0.8@sha256:<digest>` |
| Java library artifacts | GitHub Packages Maven registry | `https://maven.pkg.github.com/budgetanalyzer/service-common` |

GHCR does not solve `service-common` resolution by itself. The Java service Docker builds need `org.budgetanalyzer:service-web` and `org.budgetanalyzer:service-core` from a Maven repository before they can produce images to push to GHCR.

For this repo, GitHub Packages Maven is a CI/release mechanism, not a public library distribution channel. The supported remote-consumption path is GitHub Actions with `GITHUB_TOKEN` plus package access granted to the consuming repos. Do not design the contributor workflow around local PAT-based package pulls.

### GitHub Setup References

Use the official GitHub docs as the setup source for registry behavior:

1. [Working with the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) - GHCR authentication, pushing, pulling by digest, labels, and package behavior.
2. [Publishing Docker images](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images) - GitHub Actions workflow pattern for logging in to `ghcr.io`, building, pushing, and generating image digests/attestations.
3. [Configuring a package's access control and visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility) - package visibility, repository inheritance, and workflow access.
4. [Working with the Gradle registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-gradle-registry) - Gradle publishing and dependency resolution through GitHub Packages.
5. [Use `GITHUB_TOKEN` for authentication in workflows](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token) - workflow token permissions and least-privilege configuration.

### Development Contract

Local development stays fast and local-first:

1. Developers can continue to change `service-common` and run:
   ```bash
   cd ../service-common
   ./gradlew clean build publishToMavenLocal
   ```
2. Java service Gradle builds keep `mavenLocal()` first, so `./gradlew build`, `./gradlew bootJar`, and the Tilt live-update path can consume the locally published checked-in snapshot version, for example `0.0.9-SNAPSHOT`.
3. Tilt remains the supported local image path. It publishes `service-common` locally, builds service JARs on the host, and creates thin runtime images without requiring a remote Maven package or GHCR push.
4. Raw service-repo `docker build` is not the primary dev loop. It becomes a release-candidate verification path after the remote Maven package contract exists.
5. The side-by-side workspace plus `tilt up` path remains the source of truth for contributor onboarding. Do not make GitHub Packages credentials a prerequisite for the getting-started flow.

This means `publishToMavenLocal` remains the correct dev answer, but it is intentionally not the production image answer.

### Release Contract

Production releases use immutable artifacts and keep version naming explicit:

1. Pick one numeric SemVer release version for build and artifact metadata, for example `0.0.8`.
2. Use a `v`-prefixed Git tag as the human release ref, for example `v0.0.8`.
3. Before tagging, bump the checked-in version literals to the numeric release version. The source of truth is the literal `version = "..."` in `service-common/build.gradle.kts` plus the `serviceCommon = "..."` entry in each consumer's `gradle/libs.versions.toml`.
4. CI workflows may validate that the pushed tag matches the checked-in numeric version after stripping the leading `v`, but they must not derive or override the publish version from the tag at release time.
5. Publish `service-common` to GitHub Packages Maven with the checked-in numeric Maven version, for example `0.0.8`. Maven artifact versions must not include the leading `v`. The steady-state publish path is the `service-common` GitHub Actions workflow using `GITHUB_TOKEN`, not a manually managed maintainer PAT.
6. Build each Java service image with that exact numeric `service-common` version. The supported remote-resolution path is GitHub Actions with `GITHUB_TOKEN` and package-access grants for the consuming repos.
7. Push application images to GHCR with the numeric version as the human-readable image tag.
8. Resolve and record the pushed image digest.
9. Deploy only digest-pinned image refs, preferably retaining the readable tag:
   ```text
   ghcr.io/budgetanalyzer/transaction-service:0.0.8@sha256:<digest>
   ```

Use numeric SemVer (`0.0.8`, `0.0.9`, `0.1.0`) for build inputs, Maven artifacts, Docker image tags, and manifest inventory refs. Use matching `v`-prefixed Git tags (`v0.0.8`, `v0.0.9`, `v0.1.0`) only for intentional Git release refs. Date-plus-SHA Git tags such as `v2026.04.13-<shortsha>` are useful for CI snapshots or nightly builds, but they are noisier than necessary for this public demo's release tags. The digest is what makes the deployed image immutable.

### Phase 3 Execution Order (Detailed)

This is the exact execution order for Phase 3. Follow the steps in order. Each step names the owner so there is no hidden handoff.

#### Phase 3 Constants

- Release version for build files, Gradle properties, Maven artifacts, and Docker tags: `0.0.8`
- Git release tag: `v0.0.8`
- Version source of truth: the literal `version = "..."` in `service-common/build.gradle.kts` and the `serviceCommon` entry in each consumer's `gradle/libs.versions.toml`. Bumped in lockstep by `orchestration/scripts/repo/update-service-common-version.sh`. No `-P` override, no CI tag-derivation.
- `service-common` Maven version: `0.0.8` (no `-SNAPSHOT`, no `v` prefix)
- Supported remote package consumer: GitHub Actions workflows in the consuming repos using `GITHUB_TOKEN` plus package-access grants
- Production image names:
  - `ghcr.io/budgetanalyzer/transaction-service`
  - `ghcr.io/budgetanalyzer/currency-service`
  - `ghcr.io/budgetanalyzer/permission-service`
  - `ghcr.io/budgetanalyzer/session-gateway`
  - `ghcr.io/budgetanalyzer/budget-analyzer-web`
  - `ghcr.io/budgetanalyzer/ext-authz`

#### Phase 3 Checkpoint

As of 2026-04-14, implementation is complete through Chunk 2 Step 14 from the
previous draft of this plan. That checkpoint covers:

- the cross-repo version bump script
- `service-common` GitHub Packages publishing configuration
- Java consumer remote-fallback repository wiring
- the tag-triggered `service-common` publish workflow
- the first successful workflow publish proof for Maven version `0.0.8`

Remaining work starts after that checkpoint. The remaining steps below align the
steady-state model to GitHub Packages for CI only, not for contributor-facing
public consumption.

#### Chunk 1: GitHub Org & Repo Package Permissions

1. **[Human]** Go to `https://github.com/organizations/budgetanalyzer/settings/actions`, open **General**, and confirm the org-level **Policies** setting allows the release workflows to use the GitHub-authored and Docker actions they need. A policy that only allows local organization actions will block `actions/checkout` and the Docker publishing actions.
2. **[Human]** On that same org Actions settings page, keep **Workflow permissions** set to **Read repository contents and packages permissions**. The workflow YAML will request narrower write scopes such as `packages: write` when needed.
3. **[Human]** Go to `https://github.com/organizations/budgetanalyzer/settings/packages`. Under **Package Creation**, ensure **Private** packages are allowed. **Public** is optional and not required for this plan. Do not rely on **Internal** for Maven/Gradle; GitHub still documents Maven and Gradle as public/private only.
4. **[Human]** On that same packages page, under **Default Package Settings**, keep **Inherit access from source repository** enabled for new org-scoped packages.
5. **[Human]** Go to `https://github.com/budgetanalyzer/service-common/settings/actions`, open **General**, and confirm Actions is enabled for the repo. Keep the restricted **Workflow permissions** default there too.
6. **[Human]** Repeat step 5 for every repo that will publish images: `transaction-service`, `currency-service`, `permission-service`, `session-gateway`, `budget-analyzer-web`, and `orchestration` (for `ext-authz`, if its workflow lives here).
7. **[Human]** Open the Actions tab in any one of those repos and confirm you do not see an "Actions are disabled for this repository" banner.

#### Chunk 2: Publish `service-common` to GitHub Packages Maven

`service-common` produces `org.budgetanalyzer:service-core` and `org.budgetanalyzer:service-web`.

The version is a plain literal in `service-common/build.gradle.kts` and in each consumer's `gradle/libs.versions.toml`. A helper script bumps it across all repos in lockstep — no `-P` override, no CI tag-derivation. Standard Maven flow: bump to release version, commit, tag, publish, then bump back to the next `-SNAPSHOT` for ongoing development.

Original Steps 1-14 from the 2026-04-13 draft are already implemented and
verified. Do not reintroduce those completed bootstrap steps into contributor
documentation. The remaining work starts here.

15. **[Human]** If a one-time bootstrap classic PAT was created during the completed validation work, revoke it now. Ongoing publishing and workflow-based package consumption should use `GITHUB_TOKEN`, not a stored maintainer PAT.
16. **[AI Assistant]** While `service-common` and the Java consumer repos are still on the release version `0.0.8`, update the `service-common` docs so they say:
   - local workspace development uses `publishToMavenLocal`
   - normal remote publishing is tag-driven via GitHub Actions
   - GitHub Packages consumption is a CI/release concern, not a contributor prerequisite
   - the remote-resolution path needs both `GITHUB_TOKEN` and `GITHUB_ACTOR`
   - completed bootstrap PAT instructions, if any exist in docs, are removed
17. **[AI Assistant]** While those same repos are still on `0.0.8`, update the sibling Java consumer docs (`transaction-service`, `currency-service`, `permission-service`, and `session-gateway`) so their setup/build docs state:
   - local development stays local-first with `mavenLocal()` and orchestration/Tilt
   - the supported contributor onboarding path is the orchestration getting-started flow
   - GitHub Packages remote resolution is for GitHub Actions/release or intentional isolated builds, not for routine local setup
   - repo-local docs should link back to orchestration's `docs/development/getting-started.md` and `docs/development/service-common-artifact-resolution.md` instead of duplicating token setup
18. **[Human]** Review, commit, and push the `0.0.8` documentation/config state in `service-common`, `transaction-service`, `currency-service`, `permission-service`, and `session-gateway` before moving any repo to `0.0.9-SNAPSHOT`. Do not create an ordering gap where the pushed release-version repos still imply the old PAT-era setup or leave the `GITHUB_ACTOR` requirement undocumented.
19. **[Human]** After the release-version doc/config state is pushed, and only when all consumer repos are ready to move in lockstep, return to the orchestration repo root and bump the source back to the next snapshot for ongoing development across `service-common` plus every consumer repo together. Do not move only a subset of repos to the next snapshot if that would leave the side-by-side workspace unable to follow the getting-started flow. Then commit each touched repo:
    ```bash
    cd ../orchestration
    ./scripts/repo/update-service-common-version.sh 0.0.9-SNAPSHOT
    ```
20. **[Human]** After the lockstep snapshot bump lands across the touched repos, verify the local contributor path from a clean shell without `GITHUB_ACTOR` or `GITHUB_TOKEN`. The expected proof is the orchestration getting-started flow, not a release build:
    ```bash
    cd ../orchestration
    tilt up
    ```
    This confirms the side-by-side workspace and Tilt path still resolve `service-common` locally without a PAT.

#### Chunk 3: Lock the CI-Only Package Model

GitHub Packages Maven is no longer treated as a public-consumption channel for
`service-common`. This chunk locks the steady-state model to private/CI-only
workflow access after the release-version docs are already in sync.

1. **[Human]** Open the `org.budgetanalyzer.service-core` and `org.budgetanalyzer.service-web` package settings and confirm the package visibility matches the CI-only intent. Do not make the Maven packages public just for convenience; public visibility does not remove the Maven/Gradle auth requirement anyway.
2. **[Human]** In each `service-common` package's **Manage Actions access** settings, grant read access to the consuming workflow repos: `transaction-service`, `currency-service`, `permission-service`, and `session-gateway`. Add any future Java consumer repo here as part of its setup.
3. **[Human]** Run one package-consuming GitHub Actions workflow in a Java service repo and confirm it resolves `service-common` using `GITHUB_TOKEN` plus `GITHUB_ACTOR` with the configured package-access grant. This is the steady-state proof that replaces any assumption of PAT-based consumer setup.

#### Chunk 4: Build, Push & Verify Production Images

1. **[AI Assistant]** Update the Java service repos so GitHub Actions release builds can resolve `service-common:0.0.8` without sibling source trees or host-only Maven Local state. Prefer workflow-driven resolution with `GITHUB_TOKEN` plus package-access grants over PAT-based manual setup. If Dockerfile or workflow changes are needed, pass credentials through BuildKit secrets or CI environment without leaking tokens into images, layers, logs, or checked-in files. Do not let this release-build wiring become a getting-started prerequisite for the side-by-side workspace or `tilt up`. The version itself is already pinned in `gradle/libs.versions.toml` by the Chunk 2 bump script — no `-P` override needed at release time.
2. **[AI Assistant]** Add or update the Java service release workflows so each workflow builds at least `linux/arm64`, pushes a GHCR image tagged `0.0.8`, and prints the digest-pinned image reference. Do not publish `latest`.
3. **[AI Assistant]** Add or update the release workflows for `budget-analyzer-web` and `ext-authz` so they also build at least `linux/arm64`, push `0.0.8`, and print digests.
4. **[Human]** Review and merge the release-workflow and Dockerfile changes in each affected repo.
5. **[Human]** Create and push the release tag `v0.0.8` in each service repo: `transaction-service`, `currency-service`, `permission-service`, `session-gateway`, `budget-analyzer-web`, and the repo that owns `ext-authz`.
6. **[Human]** Watch each Actions run and record the digest it prints. Each final reference should look like:
   ```
   ghcr.io/budgetanalyzer/<service-name>:0.0.8@sha256:<digest>
   ```
7. **[Human]** Go to `https://github.com/orgs/budgetanalyzer/packages`. For each published container image package, open **Package settings**, then under **Danger Zone** use **Change visibility** -> **Public** and type the package name to confirm.
8. **[Human]** Repeat step 7 for all app images: `transaction-service`, `currency-service`, `permission-service`, `session-gateway`, `budget-analyzer-web`, and `ext-authz` (or whatever exact package name the workflow pushed for the Go service).
9. **[Human]** From any machine that has not authenticated to GHCR, verify that a public image can be pulled without `docker login ghcr.io`.
   ```bash
   docker pull ghcr.io/budgetanalyzer/transaction-service:0.0.8
   ```
10. **[AI Assistant]** Update the production image inventory and overlay files with the digest-pinned GHCR refs collected in step 6. Production paths must not contain `:latest`, `:tilt-<hash>`, unqualified app image names, or `imagePullPolicy: Never`.
11. **[AI Assistant]** Run the production Kyverno/static manifest checks once the overlay exists and confirm the local Tilt image exceptions are not present in production policy.
12. **[Human]** Review the generated production image inventory and verification results, then hand off to Phase 4.

#### Credential Safety Rules

- Never place package tokens in the repo, `.env`, shell history snippets committed to docs, or the shared workspace.
- If a bootstrap classic PAT was created during the already-complete Chunk 2 validation work, revoke it. Ongoing workflow publishing and consumption should rely on `GITHUB_TOKEN` plus package-access grants.
- Review the generated production image inventory before it is consumed by the OCI overlay.
- Keep service-repo top-level docs concise: local development should point to the orchestration getting-started and artifact-resolution docs, while GitHub Packages CI/release details stay in orchestration release/build documentation instead of dominating each service repo's main README or AGENTS file.

### Phase 3 Outputs

- `service-common` production artifact published to GitHub Packages Maven
- Java service release workflows can resolve `service-common` with `GITHUB_TOKEN` and package-access grants, without host-only Maven Local state
- Sibling Java consumer docs point local contributors back to orchestration's local-first setup docs
- GHCR contains ARM64-compatible images for every app component
- Production image inventory records digest-pinned refs
- No production manifest path uses `:latest`, `:tilt-<hash>`, unqualified local image names, or `imagePullPolicy: Never`

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

1. **Production image pipeline:** finish the CI-only `service-common` package-consumption model, sync the sibling Java service docs, and verify GitHub Actions release builds for all Java services.
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

---

## Optional Hardening

### Disable Root SSH Login Completely

The Phase 2 baseline accepts `permitrootlogin without-password` because it disables root password login and preserves the default OCI Ubuntu key-based access model through the `ubuntu` user. For stricter hardening, disable root SSH login entirely only after key-based `ubuntu` login is proven working.

Keep the current SSH session open while making this change:

```bash
sudo tee /etc/ssh/sshd_config.d/99-budgetanalyzer-hardening.conf >/dev/null <<'EOF'
PermitRootLogin no
EOF
sudo sshd -t
sudo systemctl reload ssh
```

Before closing the original session, open a second terminal from your workstation and verify a fresh login still works:

```bash
ssh -i ~/.ssh/oci-budgetanalyzer ubuntu@<public-ip>
```

If the second login fails, keep the original session open and revert immediately:

```bash
sudo rm /etc/ssh/sshd_config.d/99-budgetanalyzer-hardening.conf
sudo sshd -t
sudo systemctl reload ssh
```
