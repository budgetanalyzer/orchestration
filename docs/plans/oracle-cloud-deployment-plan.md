# Oracle Cloud Deployment Plan

**Date:** 2026-04-12
**Status:** Revised plan
**Based on:** [`single-instance-demo-hosting.md`](../research/single-instance-demo-hosting.md), [`oracle-cloud-always-free-provisioning.md`](../research/oracle-cloud-always-free-provisioning.md), [`production-secrets-and-ai-agent-boundaries.md`](../research/production-secrets-and-ai-agent-boundaries.md), [`split-local-and-production-kyverno-image-policy-2026-03-27.md`](./split-local-and-production-kyverno-image-policy-2026-03-27.md), [`service-common-docker-build-strategy.md`](./service-common-docker-build-strategy.md)

Deploy the full Budget Analyzer architecture - k3s, Istio service mesh, application services, infrastructure (PostgreSQL/Redis/RabbitMQ), and the observability bundle (Prometheus/Grafana/Jaeger/Kiali) - to an Oracle Cloud Always Free Ampere A1 instance (4 OCPU / 24 GB RAM / 200 GB disk). Cost: $0/mo.

**Fallback:** If Oracle capacity lottery takes more than one week, switch to Hetzner CAX41 (~$40/mo). Same ARM architecture, same production image set.

---

## Production Gates

These gates are non-negotiable. Do not deploy the public demo until all are true.

1. **No mutable/local production images.** Production manifests must not use `:latest`, `:tilt-<hash>`, `imagePullPolicy: Never`, or unqualified local image names such as `transaction-service:latest`. Production image refs should be immutable digest refs, preferably with the human-readable numeric SemVer tag retained: `ghcr.io/budgetanalyzer/transaction-service:0.0.12@sha256:<digest>`.
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
- Initial OCI networking opened ports 22, 80, and 443 for the original host-direct ingress path; Chunk 4 Step 17 later removes the direct public instance rules for 80/443 when the design pivots to an OCI NLB

---

## Phase 2: Host Hardening & Firewall

**Owner:** Human (SSH session on instance)
**Status:** Complete as of 2026-04-13. Verified external 80/443 reachability reached the host and returned `connection refused` before a listener existed; effective SSH config reports `passwordauthentication no` and root password login disabled via `permitrootlogin without-password`. Chunk 4 Step 16 later removes the direct host `INPUT` accepts for 80/443 when the public ingress path moves behind the OCI NLB.
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
**Status:** Strategy clarified on 2026-04-13; detailed human work breakdown added 2026-04-13; updated on 2026-04-14 to treat GitHub Packages as CI-only infrastructure for `service-common`; corrected on 2026-04-14 after verifying that GitHub Packages Maven/Gradle packages remain repository-scoped and do not expose per-package **Manage Actions access** for cross-repo workflow grants; implementation checkpoint reached through Chunk 2 Step 14 from the previous draft.
**Estimated time:** Remaining work is roughly 0.5-1 day after the Chunk 2 Step 14 checkpoint, assuming the initial `service-common` workflow publish is already proven.

This phase must complete before any production Kubernetes manifests are applied.

### Registry Decision

Use GitHub registries under the `budgetanalyzer` organization, but keep the two package types separate:

| Artifact | Registry | Example |
|---|---|---|
| Container images | GitHub Container Registry (GHCR) | `ghcr.io/budgetanalyzer/transaction-service:0.0.12@sha256:<digest>` |
| Java library artifacts | GitHub Packages Maven registry | `https://maven.pkg.github.com/budgetanalyzer/service-common` |

GHCR does not solve `service-common` resolution by itself. The Java service Docker builds need `org.budgetanalyzer:service-web` and `org.budgetanalyzer:service-core` from a Maven repository before they can produce images to push to GHCR.

For this repo, GitHub Packages Maven is a CI/release mechanism, not a public library distribution channel. As of 2026-04-14, GitHub still documents Maven and Gradle packages as repository-scoped packages, so the cross-repo consuming workflow path cannot rely on per-package **Manage Actions access** grants. For the current plan, the supported remote-consumption path is a dedicated GitHub Packages credential stored in GitHub Actions secrets for the consuming repos. Do not design the contributor workflow around local token-based package pulls.

### GitHub Setup References

Use the official GitHub docs as the setup source for registry behavior:

1. [Working with the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) - GHCR authentication, pushing, pulling by digest, labels, and package behavior.
2. [Publishing Docker images](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images) - GitHub Actions workflow pattern for logging in to `ghcr.io`, building, pushing, and generating image digests/attestations.
3. [About permissions for GitHub Packages](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages) - registry-specific permission models, including repository-scoped Maven/Gradle behavior.
4. [Configuring a package's access control and visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility) - package visibility, repository inheritance, and when granular package permissions are available.
5. [Working with the Gradle registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-gradle-registry) - Gradle publishing and dependency resolution through GitHub Packages, including the current token constraints for private packages in other repositories.
6. [Use `GITHUB_TOKEN` for authentication in workflows](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token) - workflow token permissions and least-privilege configuration.

### Development Contract

Local development stays fast and local-first:

1. Developers can continue to change `service-common` and run:
   ```bash
   cd ../service-common
   ./gradlew clean build publishToMavenLocal
   ```
2. Java service Gradle builds keep `mavenLocal()` first, so `./gradlew build`, `./gradlew bootJar`, and the Tilt live-update path can consume the locally published checked-in snapshot version, for example `0.0.13-SNAPSHOT`.
3. Tilt remains the supported local image path. It publishes `service-common` locally, builds service JARs on the host, and creates thin runtime images without requiring a remote Maven package or GHCR push.
4. Raw service-repo `docker build` is not the primary dev loop. It becomes a release-candidate verification path after the remote Maven package contract exists.
5. The side-by-side workspace plus `tilt up` path remains the source of truth for contributor onboarding. Do not make GitHub Packages credentials a prerequisite for the getting-started flow.

This means `publishToMavenLocal` remains the correct dev answer, but it is intentionally not the production image answer.

### Release Contract

Production releases use immutable artifacts and keep version naming explicit:

1. Pick one numeric SemVer release version for build and artifact metadata, for example `0.0.12`.
2. Use a `v`-prefixed Git tag as the human release ref, for example `v0.0.12`.
3. Before tagging, bump the checked-in version literals to the numeric release version. The source of truth is the literal `version = "..."` in `service-common/build.gradle.kts` plus the `serviceCommon = "..."` entry in each consumer's `gradle/libs.versions.toml`.
4. From the `v0.0.12`-forward contract, CI workflows treat the checked-out ref as source selection only, keep the checked-in files as the source of truth for `service-common`, and allow the published image tag to be selected separately.
5. Publish `service-common` to GitHub Packages Maven with the checked-in numeric Maven version, for example `0.0.12`. Maven artifact versions must not include the leading `v`. The steady-state publish path is the `service-common` GitHub Actions workflow using `GITHUB_TOKEN`, not a manually managed maintainer PAT.
6. Build each Java service image with that exact numeric `service-common` version. Because GitHub Packages Maven/Gradle packages are repository-scoped, the current supported remote-resolution path for cross-repo consuming workflows is a dedicated GitHub Packages credential stored in Actions secrets, not the workflow repo's default `GITHUB_TOKEN`.
7. Push application images to GHCR with an intentionally selected human-readable image tag. Standard `v*` releases still strip the leading `v`; manual dispatch may either use that default or override it explicitly.
8. Resolve and record the pushed image digest.
9. Deploy only digest-pinned image refs, preferably retaining the readable tag:
   ```text
   ghcr.io/budgetanalyzer/transaction-service:0.0.12@sha256:<digest>
   ```

Use numeric SemVer (`0.0.12`, `0.0.13`, `0.1.0`) for build inputs, Maven artifacts, Docker image tags, and manifest inventory refs. Use matching `v`-prefixed Git tags (`v0.0.12`, `v0.0.13`, `v0.1.0`) only for intentional Git release refs. Date-plus-SHA Git tags such as `v2026.04.13-<shortsha>` are useful for CI snapshots or nightly builds, but they are noisier than necessary for this public demo's release tags. The digest is what makes the deployed image immutable.

### Phase 3 Execution Order (Detailed)

This is the exact execution order for Phase 3. Follow the steps in order. Each step names the owner so there is no hidden handoff.

#### Phase 3 Constants

- Release version for build files, Gradle properties, Maven artifacts, and Docker tags: `0.0.12`
- Git release tag: `v0.0.12`
- Version source of truth: the literal `version = "..."` in `service-common/build.gradle.kts` and the `serviceCommon` entry in each consumer's `gradle/libs.versions.toml`. Bumped in lockstep by `orchestration/scripts/repo/update-service-common-version.sh`. No `-P` override, no CI tag-derivation.
- `service-common` Maven version: `0.0.12` (no `-SNAPSHOT`, no `v` prefix)
- Supported remote package consumer: GitHub Actions workflows in the consuming repos using a dedicated GitHub Packages username/token secret pair until artifact distribution changes
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
- the first successful workflow publish proof for Maven version `0.0.12`

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

15. **[Human]** If a one-time bootstrap classic PAT was created during the completed validation work, revoke it now. If the cross-repo consuming workflow path still requires GitHub Packages credentials after that cleanup, replace the bootstrap token with a dedicated, least-privilege GitHub Packages read credential stored only in GitHub Actions secrets; do not keep using an ad-hoc maintainer token.
16. **[AI Assistant]** While `service-common` and the Java consumer repos are still on the release version `0.0.12`, update the `service-common` docs so they say:
   - local workspace development uses `publishToMavenLocal`
   - normal remote publishing is tag-driven via GitHub Actions
   - GitHub Packages consumption is a CI/release concern, not a contributor prerequisite
   - the remote-resolution path needs a GitHub Packages username plus token, and cross-repo consuming workflows cannot rely on package-access grants because Maven/Gradle packages are repository-scoped
   - completed bootstrap PAT instructions, if any exist in docs, are removed or replaced with the dedicated secret-based workflow credential model
17. **[AI Assistant]** While those same repos are still on `0.0.12`, update the sibling Java consumer docs (`transaction-service`, `currency-service`, `permission-service`, and `session-gateway`) so their setup/build docs state:
   - local development stays local-first with `mavenLocal()` and orchestration/Tilt
   - the supported contributor onboarding path is the orchestration getting-started flow
   - GitHub Packages remote resolution is for GitHub Actions/release or intentional isolated builds, not for routine local setup
   - repo-local docs should link back to orchestration's `docs/development/getting-started.md` and `docs/development/service-common-artifact-resolution.md` instead of duplicating token setup
18. **[Human]** Review, commit, and push the `0.0.12` documentation/config state in `service-common`, `transaction-service`, `currency-service`, `permission-service`, and `session-gateway` before moving any repo to `0.0.13-SNAPSHOT`. Do not create an ordering gap where the pushed release-version repos still imply the old package-grant model or leave the required GitHub Packages workflow credential shape undocumented.
19. **[Human]** After the release-version doc/config state is pushed, and only when all consumer repos are ready to move in lockstep, return to the orchestration repo root and bump the source back to the next snapshot for ongoing development across `service-common` plus every consumer repo together. Do not move only a subset of repos to the next snapshot if that would leave the side-by-side workspace unable to follow the getting-started flow. Then commit each touched repo:
    ```bash
    cd ../orchestration
    ./scripts/repo/update-service-common-version.sh 0.0.13-SNAPSHOT
    ```
20. **[Human]** After the lockstep snapshot bump lands across the touched repos, verify the local contributor path from a clean shell without `GITHUB_ACTOR` or `GITHUB_TOKEN`. The expected proof is the orchestration getting-started flow, not a release build:
    ```bash
    cd ../orchestration
    tilt up
    ```
    This confirms the side-by-side workspace and Tilt path still resolve `service-common` locally without a PAT.

#### Chunk 3: Lock the Repository-Scoped Package Model

GitHub Packages Maven is no longer treated as a public-consumption channel for
`service-common`. This chunk locks the steady-state model to private/CI-only
workflow access after the release-version docs are already in sync, while
explicitly acknowledging that Maven/Gradle packages are repository-scoped.

1. **[Human]** Open the `org.budgetanalyzer.service-core` and `org.budgetanalyzer.service-web` package settings and confirm the package visibility matches the CI-only intent. Do not make the Maven packages public just for convenience; public visibility does not remove the Maven/Gradle auth requirement anyway.
   - Visit `https://github.com/budgetanalyzer/service-common/packages`.
   - If the repo landing page does not show the packages immediately, open the repo root first at `https://github.com/budgetanalyzer/service-common` and click **Packages** in the right sidebar.
   - Click `org.budgetanalyzer.service-core`.
   - On the package page, click **Package settings** on the right side.
   - Confirm the page is the package options/settings page for that package.
   - Check whether the package exposes any visibility control beyond the current minimal options page. For repository-scoped Maven packages, GitHub may show only a limited options page.
   - Repeat the same clicks for `org.budgetanalyzer.service-web`.
2. **[Human]** On those same package pages, confirm the UI reflects repository-scoped package behavior: there is no per-package **Manage Actions access** control to grant cross-repo workflow reads. Treat that absence as an expected platform constraint, not as a misconfiguration in this repo.
   - On each package page's settings/options screen, look for a section or sidebar entry named **Manage Actions access**.
   - Expected result for this repo as of 2026-04-14: that control does not exist for these Maven packages.
   - If the only destructive control you see is something like **Delete Package**, treat that as confirmation that this package is following the repository-scoped model rather than the granular-permissions model.
   - Do not spend more time trying to find a hidden org-level package grant UI for these Maven packages; the absence of that control is the point this step is recording.
3. **[Human]** Create or confirm a dedicated GitHub Packages read credential for cross-repo consuming workflows, store it as Actions secrets available to `transaction-service`, `currency-service`, `permission-service`, and `session-gateway`, and record the secret names in private maintainer runbooks only. Do not reuse a broad maintainer personal token if a narrower dedicated credential can be issued.
   - Recommended secret names in workflows:
     - `SERVICE_COMMON_PACKAGES_USERNAME`
     - `SERVICE_COMMON_PACKAGES_READ_TOKEN`
   - Recommended first choice: organization-level Actions secrets limited to the four consuming repos.
   - Visit `https://github.com/organizations/budgetanalyzer/settings/secrets/actions`.
   - In the left sidebar under **Security**, click **Secrets and variables**, then **Actions** if you are not already on the Actions secrets page.
   - Stay on the **Secrets** tab.
   - Click **New organization secret**.
   - Create `SERVICE_COMMON_PACKAGES_USERNAME`.
   - In **Repository access**, choose **Selected repositories**.
   - Select exactly these repos:
     - `transaction-service`
     - `currency-service`
     - `permission-service`
     - `session-gateway`
   - Click **Add secret**.
   - Click **New organization secret** again.
   - Create `SERVICE_COMMON_PACKAGES_READ_TOKEN`.
   - Again choose **Selected repositories**.
   - Select the same four consuming repos.
   - Click **Add secret**.
   - After both secrets are created, confirm they appear in the org Actions secrets list with restricted repository access rather than broad org-wide exposure.
   - If organization secrets are not available on the current GitHub plan or org policy, fall back to repo-level secrets in each consumer repo:
     - `https://github.com/budgetanalyzer/transaction-service/settings/secrets/actions`
     - `https://github.com/budgetanalyzer/currency-service/settings/secrets/actions`
     - `https://github.com/budgetanalyzer/permission-service/settings/secrets/actions`
     - `https://github.com/budgetanalyzer/session-gateway/settings/secrets/actions`
   - In each repo:
     - click **New repository secret**
     - add `SERVICE_COMMON_PACKAGES_USERNAME`
     - click **New repository secret** again
     - add `SERVICE_COMMON_PACKAGES_READ_TOKEN`
   - Do not record the token value in this repo. Only the secret names belong in docs.
4. **[Human]** Verify secret visibility before spending time on release wiring.
   - If you used organization secrets, return to `https://github.com/organizations/budgetanalyzer/settings/secrets/actions`.
   - Click `SERVICE_COMMON_PACKAGES_USERNAME`.
   - Confirm the repository access policy shows only the four intended consuming repos.
   - Repeat for `SERVICE_COMMON_PACKAGES_READ_TOKEN`.
   - If you used repo-level secrets, open each repo secrets URL listed above and confirm both secret names appear.
5. **[Human]** Run one package-consuming GitHub Actions workflow in a Java service repo and confirm it resolves `service-common` with the dedicated secret-based GitHub Packages credential. This is the steady-state proof that replaces the removed package-grant assumption.
   - This proof is only valid after at least one consumer workflow is actually wired to use the new secrets. If no such workflow exists yet, do not fake this step; complete Chunk 4 Step 1 and Step 2 first, then come back and record this proof.
   - Recommended first repo for the proof: `transaction-service`.
   - Visit `https://github.com/budgetanalyzer/transaction-service/actions`.
   - Click the workflow that builds or releases the Java image using remote `service-common` resolution.
   - Click **Run workflow** and select the intended branch or tag.
   - Open the job logs and confirm the build resolves `org.budgetanalyzer:service-core` / `service-web` from GitHub Packages without cloning `service-common` and without relying on host Maven Local state.
   - If the job fails with a package-auth error, stop and fix the secret names, secret scope, or credential value before proceeding to the image-publish steps in Chunk 4.

#### Chunk 4: Build, Push & Verify Production Images

1. **[AI Assistant]** Update the Java service repos so GitHub Actions release builds can resolve `service-common:0.0.12` without sibling source trees or host-only Maven Local state. Because Maven/Gradle packages are repository-scoped, do not assume the consuming repo's default `GITHUB_TOKEN` can read `service-common`; wire the release build around the dedicated GitHub Packages credential from Chunk 3 instead. If Dockerfile or workflow changes are needed, pass credentials through BuildKit secrets or CI environment without leaking tokens into images, layers, logs, or checked-in files. Do not let this release-build wiring become a getting-started prerequisite for the side-by-side workspace or `tilt up`. The version itself is already pinned in `gradle/libs.versions.toml` by the Chunk 2 bump script — no `-P` override needed at release time.
2. **[AI Assistant]** Add or update the Java service release workflows so each workflow builds at least `linux/arm64`, pushes a GHCR image tagged `0.0.12`, and prints the digest-pinned image reference. Do not publish `latest`.
3. **[AI Assistant]** Add or update the release workflows for `budget-analyzer-web` and `ext-authz` so they also build at least `linux/arm64`, push `0.0.12`, and print digests.
4. **[Human]** Review and merge the release-workflow and Dockerfile changes in each affected repo.
5. **[Human]** Create and push the release tag `v0.0.12` in each service repo: `transaction-service`, `currency-service`, `permission-service`, `session-gateway`, `budget-analyzer-web`, and the repo that owns `ext-authz`.


6. **[Human]** Watch each Actions run and record the digest it prints. Each final reference should look like:
   ```
   ghcr.io/budgetanalyzer/<service-name>:0.0.12@sha256:<digest>
   ```
7. **[Human]** Go to `https://github.com/orgs/budgetanalyzer/packages`. For each published container image package, open **Package settings**, then under **Danger Zone** use **Change visibility** -> **Public** and type the package name to confirm.
8. **[Human]** Repeat step 7 for all app images: `transaction-service`, `currency-service`, `permission-service`, `session-gateway`, `budget-analyzer-web`, and `ext-authz` (or whatever exact package name the workflow pushed for the Go service).
9. **[Human]** From any machine that has not authenticated to GHCR, verify that the public ARM64 production image can be pulled without `docker login ghcr.io`. The OCI target is ARM64, and release workflows in this phase only have to publish `linux/arm64`; an AMD64 workstation must request that platform explicitly or Docker will fail with `no matching manifest for linux/amd64`.
   ```bash
   docker pull --platform linux/arm64 ghcr.io/budgetanalyzer/transaction-service:0.0.12
   ```
   To prove anonymous access even on a machine that may already have GHCR credentials, use a temporary Docker config:
   ```bash
   tmpdir="$(mktemp -d)"
   DOCKER_CONFIG="${tmpdir}" docker pull --platform linux/arm64 ghcr.io/budgetanalyzer/transaction-service:0.0.12
   rm -rf "${tmpdir}"
   ```
10. **[AI Assistant] Complete as of 2026-04-15.** Update the production image inventory and overlay files with the digest-pinned GHCR refs collected in step 6. Production paths must not contain `:latest`, `:tilt-<hash>`, unqualified app image names, or `imagePullPolicy: Never`.
    - Inventory: `kubernetes/production/apps/image-inventory.yaml`
    - Overlay: `kubernetes/production/apps/kustomization.yaml`
    - Production frontend bundle source: `ghcr.io/budgetanalyzer/budget-analyzer-web:0.0.12@sha256:3299d088121fcfca8dc69f0d9de92944b311cc408ccbcb08e1bb5243523eb03e` copied into the production NGINX document root by the `nginx-gateway` init container.
11. **[AI Assistant] Complete as of 2026-04-15.** Run the production Kyverno/static manifest checks once the overlay exists and confirm the local Tilt image exceptions are not present in production policy.
    - Verifier: `./scripts/guardrails/verify-production-image-overlay.sh`
    - Production image policy: `kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml`
    - Regression gate also run: `./scripts/guardrails/verify-phase-7-static-manifests.sh`
12. **[Human]** Review the generated production image inventory and verification results, then hand off to Phase 4.

#### Credential Safety Rules

- Never place package tokens in the repo, `.env`, shell history snippets committed to docs, or the shared workspace.
- If a bootstrap classic PAT was created during the already-complete Chunk 2 validation work, revoke it. Ongoing workflow publishing may still use `GITHUB_TOKEN` in `service-common`, but cross-repo Maven consumption must use the dedicated secret-based credential until artifact distribution changes.
- Review the generated production image inventory before it is consumed by the OCI overlay.
- Keep service-repo top-level docs concise: local development should point to the orchestration getting-started and artifact-resolution docs, while GitHub Packages CI/release details stay in orchestration release/build documentation instead of dominating each service repo's main README or AGENTS file.

### Phase 3 Outputs

- `service-common` production artifact published to GitHub Packages Maven
- Java service release workflows can resolve `service-common` with the dedicated secret-based GitHub Packages credential, without host-only Maven Local state
- Sibling Java consumer docs point local contributors back to orchestration's local-first setup docs
- GHCR contains ARM64-compatible images for every app component
- Production image inventory records digest-pinned refs
- No production manifest path uses `:latest`, `:tilt-<hash>`, unqualified local image names, or `imagePullPolicy: Never`

---

## Phase 4: Install k3s, Gateway API, Istio, ESO, and cert-manager

**Owner:** Human executes scripts (Pattern B - idempotent, sources external config)
**Estimated time:** 45-75 minutes
**Status:** Chunks 1, 2, and 3 are complete as of 2026-04-16. The next open work starts at Chunk 4 Step 13, and all preceding Phase 4 work is complete through the mesh-install checkpoint. Step 15 is retained only as the documented 2026-04-16 host-redirect experiment; do not rerun it on the forward path. After any remaining Step 13-14 controller work, the first ingress-transition step is Step 16 host cleanup, followed by Step 17 OCI networking rollback, Step 18-20 OCI Network Load Balancer adoption, and the Step 21 NetworkPolicy verification gate.

Pattern B here does not mean "AI executes Phase 4." It means the AI assistant may prepare or refine the repeatable scripts and non-secret manifests, while the human runs anything that changes the OCI host or live cluster.

### Steps

1. **Install a pinned k3s version** with Istio-friendly flags.
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=<pinned-stable-version> INSTALL_K3S_EXEC="\
     --disable=traefik \
     --disable=servicelb \
     --disable=metrics-server \
     --write-kubeconfig-mode=644" sh -
   ```
   Use the current **K3s stable-channel** release that is compatible with the repo's Istio baseline, not the K3s `latest` channel. Do not leave the install unpinned.
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
     --version 1.29.2 \
     --wait

   helm upgrade --install istio-cni istio/cni \
     --namespace istio-system \
     --version 1.29.2 \
     --values kubernetes/istio/cni-values.yaml \
     --wait

   helm upgrade --install istiod istio/istiod \
     --namespace istio-system \
     --version 1.29.2 \
     --values kubernetes/istio/istiod-values.yaml \
     --wait
   ```
6. **Install the egress gateway from the chart.**
   ```bash
   kubectl apply -f kubernetes/istio/egress-namespace.yaml
   helm upgrade --install istio-egress-gateway istio/gateway \
     --namespace istio-egress \
     --version 1.29.2 \
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
     --version 2.2.0 \
     --values deploy/helm-values/external-secrets.values.yaml \
     --wait
   ```
10. **Install cert-manager with Gateway API support enabled and pinned/hardened chart values.**
    ```bash
    helm repo add jetstack https://charts.jetstack.io
    helm upgrade --install cert-manager jetstack/cert-manager \
      -n cert-manager \
      --create-namespace \
      --version v1.20.2 \
      --set crds.enabled=true \
      --set config.enableGatewayAPI=true \
      --values deploy/helm-values/cert-manager.values.yaml \
      --wait
    ```
11. **Keep the rejected host redirect experiment as historical context only, then clean up its host mutations before adopting the OCI Network Load Balancer ingress path.**
    ```bash
    # Historical experiment reference only; do not rerun on the forward path
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

### Phase 4 Execution Order (Detailed)

This is the exact execution order for Phase 4. Follow the steps in order. Each step names the owner so there is no hidden handoff.

#### Phase 4 Script Boundary

- Reusable Phase 4 deployment scripts belong under `deploy/scripts/`.
- Temporary draft helpers, scratch scripts, or debug probes may live under `tmp/` while they are being iterated.
- Do not treat `tmp/` as the long-term deployment path. If the command becomes part of the repeatable install flow, promote it into a committed `deploy/scripts/` artifact before calling Phase 4 complete.
- Not every short one-time command needs its own script, but anything long, stateful, or likely to be re-run should stop living as copy-paste shell history and move into a reviewed Pattern B script.

#### Chunk 1: Prepare the Install Path

**Status:** Complete as of 2026-04-16.

1. **[AI Assistant]** Convert the raw Phase 4 command sequence into a reviewed, repeatable, repo-owned install path before the human touches the OCI host.
2. **[Human]** Review the generated artifacts, confirm the pins, and only then run them on the OCI instance.

**Chunk 1 implementation plan**

1. **Create the deployment scaffold in-repo.**
   - Add `deploy/README.md`, `deploy/instance.env.template`, `deploy/scripts/`, `deploy/helm-values/`, and `deploy/manifests/phase-4/`.
   - Keep runtime render output in `tmp/`, not under `deploy/`.
   - Treat `deploy/` as the committed operator-facing surface for Pattern B scripts only.
   - Complete as of 2026-04-16 with the scaffold and operator handoff doc under `deploy/`.
2. **Define the Phase 4 version contract in one place.**
   - Current target pins for this plan revision, as of **April 15, 2026**, using the **latest stable/supported** choice for production rather than the newest available release:
     - k3s `v1.34.6+k3s1`
     - Gateway API CRDs `v1.4.0`
     - Istio charts `1.29.2`
     - External Secrets Operator chart `2.2.0`
     - cert-manager chart `v1.20.2`
   - Keep those pins in a shared shell include so every Phase 4 script reads the same contract.
   - Selection rule:
     - prefer the upstream **stable** or explicitly **supported** release line
     - then take the latest patch in that line
     - do **not** automatically follow a project's `latest` channel or a freshly published minor release
   - Gateway API intentionally stays on `v1.4.0` until the repo validates a newer CRD bundle against the current Istio/Gateway baseline.
   - External Secrets intentionally stays on `2.2.0` for now because the project's published stability/support page still identifies `2.2` as the current supported minor; do not jump to `2.3.0` until the support docs catch up or the project explicitly marks `2.3` supported.
   - Complete as of 2026-04-16 in `deploy/scripts/lib/phase-4-version-contract.sh`.
3. **Add a shared deploy helper library.**
   - Resolve the repo root without hardcoding `/workspace`.
   - Load `~/.config/budget-analyzer/instance.env`.
   - Fall back to `/etc/rancher/k3s/k3s.yaml` for `KUBECONFIG` after k3s install.
   - Centralize common logging, required-command checks, and `sudo`/root wrappers for host mutations.
   - Complete as of 2026-04-16 in `deploy/scripts/lib/common.sh`.
4. **Add the human-run Phase 4 scripts in execution order.**
   - `deploy/scripts/01-install-k3s.sh`
   - `deploy/scripts/02-bootstrap-cluster.sh`
   - `deploy/scripts/03-render-phase-4-istio-manifests.sh`
   - `deploy/scripts/04-install-istio.sh`
   - `deploy/scripts/05-install-platform-controllers.sh`
   - `deploy/scripts/06-configure-host-redirects.sh`
   - `deploy/scripts/07-apply-network-policies.sh`
   - Each script must be idempotent, non-secret, and safe to review before execution.
   - Complete as of 2026-04-16 with the seven reviewed scripts under `deploy/scripts/`.
5. **Make the raw Kubernetes host mutations explicit instead of embedded shell history.**
   - `01-install-k3s.sh`: install pinned k3s with `--disable=traefik --disable=servicelb --disable=metrics-server --write-kubeconfig-mode=644`.
   - `02-bootstrap-cluster.sh`: install Gateway API CRDs and label `default`, `infrastructure`, `monitoring`, `istio-system`, `istio-ingress`, `istio-egress`, `external-secrets`, and `cert-manager`.
   - `04-install-istio.sh`: install `istio-base`, `istio-cni`, `istiod`, and the chart-managed egress gateway, then apply the mesh security policy manifests.
   - `05-install-platform-controllers.sh`: install External Secrets Operator and cert-manager from pinned charts using checked-in values.
   - `06-configure-host-redirects.sh`: capture the rejected host-redirect experiment as a reviewed, idempotent script; Step 16 later removes any host mutations from that experiment before the OCI NLB path begins.
   - `07-apply-network-policies.sh`: apply `kubernetes/network-policies/` without adding production-only workaround policies.
   - Complete as of 2026-04-16; those mutations now live in reviewed scripts instead of copy-paste command history.
6. **Check in the missing non-secret manifests and values needed by Phase 4.**
   - Add hardened values files for External Secrets Operator and cert-manager under `deploy/helm-values/`.
   - Add a production-phase ingress gateway infrastructure template and `Gateway` template under `deploy/manifests/phase-4/`.
   - Render those templates from `instance.env`; do not leave raw copy-paste placeholders in the human install path.
   - Complete as of 2026-04-16 in `deploy/helm-values/` plus `deploy/manifests/phase-4/`, rendered by `deploy/scripts/03-render-phase-4-istio-manifests.sh`.
7. **Keep TLS scope explicit for Phase 4.**
   - Phase 4 prepares the ingress install path and port `80` ACME reachability.
   - Public certificate issuance and the final HTTPS listener secret wiring remain in Phase 11.
   - Do not invent an AI-generated certificate, self-signed fallback, or certificate private-key workaround.
   - Complete as of 2026-04-16: `03-render-phase-4-istio-manifests.sh` renders an HTTP-only host-agnostic `Gateway`, and `06-configure-host-redirects.sh` remains available only to reproduce the rejected host-redirect experiment against whatever ports the current ingress Service exposes.
8. **Document the operator handoff in the repo.**
   - `deploy/README.md` must show the exact review/run order, expected inputs, and which later phase reuses each script.
   - This plan document must point to the new deploy artifacts instead of leaving Chunk 1 as a vague “generate scripts” placeholder.
   - Complete as of 2026-04-16 in `deploy/README.md` plus the concrete artifact references in this section.
9. **Validate the install-path artifacts before calling Chunk 1 complete.**
   - Run `bash -n` and `shellcheck` on every new or modified `deploy/scripts/*.sh`.
   - If a render helper exists, run it locally with sample non-secret inputs and confirm it produces reviewable YAML under `tmp/`.
   - Do not call Chunk 1 complete with unvalidated shell scripts or placeholder-only manifest templates.
   - Complete as of 2026-04-16 with `bash -n`, `shellcheck`, and a local sample render pass over the new Phase 4 scripts and templates.
10. **Chunk 1 exit criteria.**
   - A reviewer can clone the repo, inspect `deploy/README.md`, copy `deploy/instance.env.template`, and see the exact Phase 4 execution order without consulting shell history.
   - All Phase 4 version pins are explicit and centralized.
   - No secret values, OCI private keys, or certificate private keys enter the repo or AI workspace.
   - Complete as of 2026-04-16 through the checked-in deploy path under `deploy/`, the shared version contract in `deploy/scripts/lib/phase-4-version-contract.sh`, and the non-secret render-only operator inputs in `deploy/instance.env.template`.

#### Chunk 2: Bootstrap the Base Cluster

**Status:** Complete as of 2026-04-16. Chunk 4 Step 13 is the next open work item.

3. **[Human]** Install the pinned k3s version with the documented Istio-friendly flags.
4. **[Human]** Verify the k3s node, system pods, and storage class.
5. **[Human]** Install the Gateway API CRDs.
6. **[Human]** Create and label the namespaces before admission policies or Helm installs.

**Chunk 2 implementation plan**

1. **Run this chunk on the OCI instance, not in the AI container.**
   - Use a sudo-capable shell on the Oracle Cloud VM.
   - Run from the checked-out `orchestration` repo root on that host.
   ```bash
   cd /path/to/orchestration
   pwd
   ```
2. **Confirm the required non-secret instance config exists before mutating the host.**
   - `deploy/scripts/01-install-k3s.sh` and `deploy/scripts/02-bootstrap-cluster.sh` both load `~/.config/budget-analyzer/instance.env`.
   - If it does not exist yet, create it from the checked-in template now.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env || {
     mkdir -p ~/.config/budget-analyzer
     cp deploy/instance.env.template ~/.config/budget-analyzer/instance.env
     echo "Populate ~/.config/budget-analyzer/instance.env before continuing."
     exit 1
   }
   ```
3. **Review the exact pinned contract and human-run scripts one last time.**
   - This is the last review gate before the VM and cluster change.
   - Verify that the pinned versions and flags still match the intended Phase 4 contract.
   ```bash
   sed -n '1,200p' deploy/scripts/lib/phase-4-version-contract.sh
   sed -n '1,220p' deploy/scripts/01-install-k3s.sh
   sed -n '1,260p' deploy/scripts/02-bootstrap-cluster.sh
   ```
4. **Install or reconcile k3s with the repo-owned script.**
   - This installs the pinned k3s release with `--disable=traefik --disable=servicelb --disable=metrics-server --write-kubeconfig-mode=644`.
   - The script also prints the immediate cluster snapshot after install.
   ```bash
   ./deploy/scripts/01-install-k3s.sh
   ```
5. **Verify the base k3s state before continuing.**
   - Stop here if the node is not `Ready`, if core pods are crash-looping, or if no default storage class exists.
   ```bash
   sudo systemctl status k3s --no-pager
   sudo k3s --version | head -n 1
   kubectl get nodes -o wide
   kubectl get pods -A
   kubectl get storageclass
   ```
   Expect:
   - one node in `Ready`
   - core `kube-system` workloads up
   - a default storage class such as `local-path`
6. **Bootstrap the cluster with Gateway API CRDs and namespace labels.**
   - This is the canonical path for Human Steps 5-6.
   - The script installs Gateway API `v1.4.0`, applies the checked-in namespace manifests, and labels the namespaces used by later Phase 4 installs.
   ```bash
   ./deploy/scripts/02-bootstrap-cluster.sh
   ```
7. **Verify the Gateway API CRDs and namespace labeling result.**
   - Stop here if the Gateway CRDs are not `Established` or if any namespace is missing the expected labels.
   ```bash
   kubectl get crd gateways.gateway.networking.k8s.io
   kubectl get crd httproutes.gateway.networking.k8s.io
   kubectl get namespace \
     default infrastructure monitoring istio-system istio-ingress istio-egress external-secrets cert-manager \
     --show-labels
   ```
   Expect:
   - `gateways.gateway.networking.k8s.io` present and established
   - `default` labeled with `istio-injection=enabled`, `budgetanalyzer.io/ingress-routes=true`, and PSA `restricted`
   - `istio-system` labeled with PSA `privileged`
   - `infrastructure`, `monitoring`, `istio-ingress`, `istio-egress`, `external-secrets`, and `cert-manager` present before Helm installs begin
8. **Record the completion point and advance the plan.**
   - If Steps 4-7 succeeded, Chunk 2 is complete.
   - At that point, mark Phase 4 complete through Chunk 2 and leave Chunk 3 Step 7 as the next open work item.
   - Marked complete as of 2026-04-16.
   ```bash
   kubectl cluster-info
   kubectl get namespace \
     default infrastructure monitoring istio-system istio-ingress istio-egress external-secrets cert-manager
   ```

**Chunk 2 exit criteria**

- The OCI host is running the pinned k3s version from `deploy/scripts/lib/phase-4-version-contract.sh`.
- `kubectl get nodes` shows the single node `Ready`.
- The cluster has a usable default storage class.
- Gateway API CRDs from `v1.4.0` are installed and established.
- `default`, `infrastructure`, `monitoring`, `istio-system`, `istio-ingress`, `istio-egress`, `external-secrets`, and `cert-manager` all exist with the expected labels for the next Phase 4 installs.
- Once those checks pass, mark all preceding work complete through Phase 4 Chunk 2.

#### Chunk 3: Install the Mesh

**Status:** Complete as of 2026-04-16. Verified on the OCI host with `gateway/istio-ingress-gateway` `Programmed=True`, the auto-provisioned `istio-ingress-gateway-istio` `NodePort` Service exposing `80:30080`, `PeerAuthentication/default-strict` in `default`, and the checked-in `AuthorizationPolicy` set present in `default`.

7. **[Human]** Install `istio-base`, `istio-cni`, and `istiod` with the pinned chart version and checked-in values.
8. **[Human]** Install the chart-managed egress gateway in `istio-egress`.
9. **[AI Assistant]** If the production ingress overlay or ingress-gateway infrastructure config is still placeholder-only, prepare the non-secret manifest updates in-repo for human review.
10. **[Human]** Apply the ingress namespace, ingress infrastructure config, and production `Gateway` resources, then wait for `Programmed` and rollout success.
11. **[Human]** Apply `kubernetes/istio/peer-authentication.yaml` and `kubernetes/istio/authorization-policies.yaml`. Do not apply placeholder egress routing until the production Auth0 issuer config exists.

**Chunk 3 implementation plan**

1. **Run this chunk on the OCI instance from the checked-out repo root.**
   - Chunk 2 must already be complete on this host and cluster.
   - The current checked-in render templates under `deploy/manifests/phase-4/` are the reviewed ingress inputs for this chunk; no extra AI-generated placeholder cleanup is pending before the human run.
   ```bash
   cd /path/to/orchestration
   pwd
   ```
2. **Confirm the required non-secret operator input still exists.**
   - `deploy/scripts/03-render-phase-4-istio-manifests.sh` and `deploy/scripts/04-install-istio.sh` both load `~/.config/budget-analyzer/instance.env`.
   - Export the k3s kubeconfig into your shell before running manual `helm` verification commands; unlike the repo scripts, your interactive shell will not auto-populate `KUBECONFIG`.
   - Stop here if the file is missing or stale.
   ```bash
   test -f ~/.config/budget-analyzer/instance.env
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   sed -n '1,220p' ~/.config/budget-analyzer/instance.env
   ```
3. **Review the exact Chunk 3 contract and inputs before mutating the live cluster.**
   - This is the human review gate for the pinned Istio version, Helm values, and rendered-ingress source templates.
   ```bash
   sed -n '1,200p' deploy/scripts/lib/phase-4-version-contract.sh
   sed -n '1,260p' deploy/scripts/03-render-phase-4-istio-manifests.sh
   sed -n '1,320p' deploy/scripts/04-install-istio.sh
   sed -n '1,220p' deploy/manifests/phase-4/ingress-gateway-config.yaml.template
   sed -n '1,220p' deploy/manifests/phase-4/istio-gateway.yaml.template
   sed -n '1,220p' kubernetes/istio/cni-values.yaml
   sed -n '1,260p' kubernetes/istio/istiod-values.yaml
   sed -n '1,220p' kubernetes/istio/egress-gateway-values.yaml
   ```
4. **Render the reviewed Phase 4 ingress manifests into `tmp/phase-4/`.**
   - This is the concrete operator step that closes Human Step 10's "ingress infrastructure config and production `Gateway` resources" preparation path.
   - Stop here if the render fails or leaves unresolved placeholders.
   ```bash
   ./deploy/scripts/03-render-phase-4-istio-manifests.sh
   ls -la tmp/phase-4
   ```
5. **Review the rendered ingress manifests before applying them.**
   - In Phase 4 the `Gateway` is intentionally HTTP-only and host-agnostic, with the listener hostname omitted so the checked-in localhost `HTTPRoute` manifests can still attach.
   - The ingress infrastructure ConfigMap should expose NodePort `30080` for service port `80`.
   ```bash
   sed -n '1,220p' tmp/phase-4/ingress-gateway-config.yaml
   sed -n '1,220p' tmp/phase-4/istio-gateway.yaml
   grep -n "nodePort" tmp/phase-4/ingress-gateway-config.yaml
   grep -n "protocol: HTTP" tmp/phase-4/istio-gateway.yaml
   ```
6. **Install the mesh and apply the rendered ingress resources with the repo-owned script.**
   - This single script covers Human Steps 7, 8, 10, and 11 in the correct order:
     - installs `istio-base`, `istio-cni`, and `istiod`
     - installs the chart-managed egress gateway
     - applies the rendered ingress namespace, ConfigMap, and `Gateway`
     - waits for the `Gateway` to become `Programmed`
     - applies `kubernetes/istio/peer-authentication.yaml` and `kubernetes/istio/authorization-policies.yaml`
   ```bash
   ./deploy/scripts/04-install-istio.sh
   ```
7. **Verify the Istio control plane and egress gateway state before moving on.**
   - Stop here if any Helm release is missing, if `istiod` is not `Available`, or if the egress gateway deployment is not rolled out.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   helm list -n istio-system
   helm list -n istio-egress
   kubectl get pods -n istio-system
   kubectl get pods -n istio-egress
   kubectl rollout status daemonset/istio-cni-node -n istio-system --timeout=180s
   kubectl rollout status deployment/istiod -n istio-system --timeout=180s
   kubectl rollout status deployment/istio-egress-gateway -n istio-egress --timeout=180s
   ```
   Expect:
   - `istio-base`, `istio-cni`, and `istiod` releases present in `istio-system`
   - `istio-egress-gateway` release present in `istio-egress`
   - `istio-cni-node`, `istiod`, and `istio-egress-gateway` healthy after rollout
8. **Verify the ingress gateway was auto-provisioned from Gateway API and is serving the Phase 4 HTTP listener.**
   - Stop here if the `Gateway` is not `Programmed`, if the ingress deployment did not roll out, or if the Service does not expose port `80`.
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   kubectl get gateway -n istio-ingress
   kubectl describe gateway istio-ingress-gateway -n istio-ingress
   kubectl get deploy -n istio-ingress
   kubectl get svc -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway
   kubectl get pods -n istio-ingress
   ```
   Expect:
   - `gateway/istio-ingress-gateway` shows `Programmed=True`
   - `deployment/istio-ingress-gateway-istio` is `Available`
   - the auto-provisioned Service exposes port `80` with nodePort `30080`
   - no Phase 4 expectation for `443` yet; HTTPS listener wiring remains Phase 11 work
9. **Verify the mesh security policies landed in the cluster.**
   - This is the completion proof for Human Step 11.
   - Do not apply placeholder egress routing in this chunk; only the checked-in peer authentication and authorization policies belong here.
   ```bash
   kubectl get peerauthentication -n default
   kubectl get authorizationpolicy -n default
   kubectl get peerauthentication default-strict -n default -o yaml
   ```
   Expect:
   - `PeerAuthentication/default-strict` exists in `default` with `mtls.mode: STRICT`
   - the default namespace shows the checked-in AuthorizationPolicies for ingress-facing services, backend services, and Prometheus scraping
10. **Record the completion point and advance to Chunk 4 only after the mesh checks pass.**
    - If Steps 4-9 succeeded, Chunk 3 is complete and the next human work is Chunk 4 Steps 13-14 plus Steps 16-21. Step 15 is historical only.
    - Do not move on to the Step 16 cleanup, the OCI NLB ingress path, or network policies until the ingress Service and mesh policies are verified.
    ```bash
    kubectl get gateway -n istio-ingress
    kubectl get svc -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway
    kubectl get peerauthentication,authorizationpolicy -n default
    ```
    Verified on 2026-04-16:
    - `gateway/istio-ingress-gateway` in `istio-ingress` showed `Programmed=True` with address `istio-ingress-gateway-istio.istio-ingress.svc.cluster.local`
    - the auto-provisioned Service exposed `15021:32143/TCP` and `80:30080/TCP`
    - `PeerAuthentication/default-strict` showed `MODE STRICT`
    - the default namespace contained the checked-in `AuthorizationPolicy` set for `budget-analyzer-web`, `currency-service`, `envoy-metrics-prometheus`, `ext-authz`, `nginx-gateway`, `permission-service`, `session-gateway`, `spring-boot-metrics-prometheus`, and `transaction-service`

**Chunk 3 exit criteria**

- `deploy/scripts/03-render-phase-4-istio-manifests.sh` ran successfully and produced reviewed YAML under `tmp/phase-4/`.
- `deploy/scripts/04-install-istio.sh` completed without Helm or rollout failures.
- `istio-base`, `istio-cni`, and `istiod` are installed at the pinned version from `deploy/scripts/lib/phase-4-version-contract.sh`.
- `istio-egress-gateway` is installed and rolled out in `istio-egress`.
- `gateway/istio-ingress-gateway` in `istio-ingress` is `Programmed`, and its auto-provisioned Service exposes the Phase 4 HTTP listener on port `80` via nodePort `30080`.
- `PeerAuthentication/default-strict` and the checked-in `AuthorizationPolicy` set are present in `default`.
- Complete as of 2026-04-16 from OCI-host verification output.
- Continue with Chunk 4.

#### Chunk 4: Install Supporting Controllers and Host Wiring

**Current checkpoint:** Complete through Step 12 as of 2026-04-16. The next open step is Step 13. Start there on the OCI host. After Step 14, the forward path resumes at Step 16 cleanup; Step 15 is retained only as historical context from the rejected host-redirect design.

12. **[AI Assistant]** If hardened production Helm values for External Secrets Operator or cert-manager are missing, prepare them in-repo for human review before install.
    - **Status:** Complete as of 2026-04-16.
    - Completed artifacts:
      - `deploy/helm-values/external-secrets.values.yaml`
      - `deploy/helm-values/cert-manager.values.yaml`
      - `deploy/scripts/08-verify-network-policy-enforcement.sh`
13. **[Human]** Install External Secrets Operator with pinned values.
    - **Status:** Open. This is the first step you should run.
    - Run:
      ```bash
      cd /path/to/orchestration
      test -f ~/.config/budget-analyzer/instance.env
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
      ./deploy/scripts/05-install-platform-controllers.sh
      ```
    - Verify:
      ```bash
      helm list -n external-secrets
      kubectl get pods -n external-secrets
      kubectl get crd \
        clustersecretstores.external-secrets.io \
        secretstores.external-secrets.io \
        externalsecrets.external-secrets.io
      ```
    - Stop if the `external-secrets` release is missing, if its pods are not ready, or if the ESO CRDs are absent.
14. **[Human]** Install cert-manager with Gateway API support enabled and pinned values.
    - **Status:** Open.
    - Run:
      - No second install command is needed. Step 14 is completed by the same `./deploy/scripts/05-install-platform-controllers.sh` run from Step 13.
    - Verify:
      ```bash
      helm list -n cert-manager
      helm get values cert-manager -n cert-manager
      kubectl get pods -n cert-manager
      kubectl get crd \
        certificates.cert-manager.io \
        certificaterequests.cert-manager.io \
        clusterissuers.cert-manager.io \
        issuers.cert-manager.io
      ```
    - Stop if the `cert-manager` release is missing, if the cert-manager pods are not ready, or if `config.enableGatewayAPI=true` is not present in the Helm values output.
15. **[Human]** Add the host `iptables` redirects after the ingress NodePorts exist.
    - **Status:** Complete as part of the 2026-04-16 OCI debugging thread. Keep this step only as historical context; do not rerun `./deploy/scripts/06-configure-host-redirects.sh` on the forward path unless you are explicitly reproducing the rejected design.
    - Commands used during the recorded experiment:
      ```bash
      kubectl get svc -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway -o wide
      ./deploy/scripts/06-configure-host-redirects.sh
      ```
    - Verification captured during the experiment:
      ```bash
      sudo iptables -t nat -S PREROUTING
      curl -I --max-time 5 http://127.0.0.1:30080/ || true
      ```
    - Recorded outcome: host port `80` was redirected to the current ingress nodePort in `PREROUTING`, but the redirected public flow still did not become a working NodePort service path on this OCI host. The redirect had to be inserted before kube-proxy's `KUBE-SERVICES` jump in `nat/PREROUTING`, and even with that fix the forward path still moved to Step 16 cleanup plus the OCI NLB design. If you ever reproduce this failure on purpose, use `curl -I http://<public-ip>/` from your workstation rather than treating `curl` from the SSH session as an end-to-end proof.
16. **[Human]** Remove the Step 15 host-redirect experiment and the older host-direct firewall rules before introducing the replacement public-ingress path.
    - **Status:** Open.
    - Run:
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
      ```
    - Verify:
      ```bash
      sudo iptables -L INPUT --line-numbers -n | sed -n '1,20p'
      sudo iptables -t nat -S PREROUTING
      ```
    - Stop if the temporary `INPUT dpt:30080 ACCEPT` rule remains, if any Step 15 `PREROUTING REDIRECT` rule remains for `80` or `443`, if the older direct-instance `INPUT` accepts for `80` or `443` remain in place, or if the host baseline is ambiguous. Do not continue with both exposure mechanisms configured at the same time.
17. **[Human]** Roll back the earlier direct-to-instance OCI ingress exposure and replace it with an NLB-oriented frontend/backend network model before creating the public load balancer.
    - **Status:** Open.
    - In OCI, remove the earlier `0.0.0.0/0` TCP `80` and `443` ingress rules that were added for direct host ingress to the instance.
    - Do not continue with a shared-subnet security-list design that still exposes the instance itself on public `80` or `443`. Introduce NSGs or an equivalent OCI control boundary so the public listener belongs to the future NLB and the instance backend path is separate.
    - Recommended target shape:
      - frontend NSG on the public NLB allowing `0.0.0.0/0` to listener `80` during Phase 4
      - backend NSG on the instance VNIC allowing only the NLB path to backend `30080`
      - no direct public ingress rule to the instance on `80` or `443`
    - Keep Phase 4 HTTP-only. Reserve the equivalent `443 -> 30443` backend pattern for Phase 11.
    - Verify in OCI:
      - the instance is no longer directly reachable from the internet on `80` or `443`
      - the planned backend path to `30080` is not open to `0.0.0.0/0`
    - Stop if the instance still depends on public `0.0.0.0/0` rules for `80` or `443`, or if the backend `30080` rule is broader than the future NLB path requires.
18. **[AI Assistant]** Update the checked-in ingress gateway service config and operator docs for OCI Network Load Balancer exposure with preserved client IP.
    - **Status:** Open.
    - Set `externalTrafficPolicy: Local` on the auto-provisioned ingress Service via the checked-in Gateway infrastructure ConfigMap.
    - Keep Phase 4 HTTP-only; Phase 11 is still responsible for adding the HTTPS listener, the `30443` backend path, and the matching NLB listener.
    - Record the rationale in [`docs/decisions/008-oci-public-ingress-via-nlb.md`](../decisions/008-oci-public-ingress-via-nlb.md).
    - Stop if the checked-in config still treats host `iptables` redirects as the steady-state public ingress design or if the service would hide the original client IP from the ingress gateway.
19. **[Human]** Expose the Phase 4 ingress listener through a public OCI Network Load Balancer instead of host `iptables`.
    - **Status:** Open.
    - In OCI, create a public layer-4 Network Load Balancer in the application VCN.
    - For Phase 4, configure one TCP listener on port `80` and point it at a backend set that targets the instance on ingress NodePort `30080`.
    - Configure the backend set in source-IP-preserving mode, register compute-instance backends rather than a machine-specific host workaround, and attach the frontend/backend NSGs from Step 17.
    - Add a TCP health check against `30080`.
    - Verify:
      ```bash
      curl -I --max-time 5 http://<nlb-public-ip>/ || true
      curl -I --max-time 5 -H 'Host: app.budgetanalyzer.localhost' http://<nlb-public-ip>/ || true
      ```
    - Stop if the public ingress path still depends on host `REDIRECT` rules, if the OCI resource is configured as an HTTP proxy instead of a TCP load balancer, or if the backend registration model would block future multi-node ingress scale-out.
20. **[Human]** Prove the NLB-only backend path and preserved client IP before moving on.
    - **Status:** Open.
    - Confirm the OCI security boundary now matches the target state from Step 17: the instance accepts backend traffic from the NLB path to `30080` during Phase 4 and does not expose ingress NodePorts or host ports to `0.0.0.0/0`.
    - When Phase 11 adds HTTPS, repeat the same pattern for `30443`.
    - Verify on the instance:
      ```bash
      sudo tcpdump -ni any 'tcp port 30080'
      ```
      Then from the workstation:
      ```bash
      curl -v -H 'Host: app.budgetanalyzer.localhost' http://<nlb-public-ip>/
      ```
    - Stop if the backend sees only an OCI load balancer address instead of the workstation client IP, if the instance is still directly reachable on public `80` or `443`, or if the security rule is broader than the NLB path requires.
21. **[Human]** Apply the network policies and verify the selected k3s CNI actually enforces the repo's NetworkPolicy contract before moving to Phase 5.
    - **Status:** Open.
    - Run:
      ```bash
      ./deploy/scripts/07-apply-network-policies.sh
      ./deploy/scripts/08-verify-network-policy-enforcement.sh
      ```
    - Verify:
      ```bash
      kubectl get networkpolicy -A
      ```
    - Stop if the verifier reports any unexpected allow or deny result. `kubectl get networkpolicy` only proves the API objects exist; the verifier is the actual enforcement proof.

**Operator notes**

- Run Chunk 4 on the OCI instance from the checked-out repo root.
- Chunk 3 must already be complete before you start Chunk 4.
- Step 13 and Step 14 share the same install script: `deploy/scripts/05-install-platform-controllers.sh`.
- Step 15 is retained only as the recorded host-redirect experiment from 2026-04-16. Do not rerun it on the forward path. If the OCI host still carries any Step 15 redirects or debug-only rules, Step 16 cleanup is the first ingress-transition action before Step 17.
- Step 21 requires two commands:
  - `deploy/scripts/07-apply-network-policies.sh` creates the policy objects.
  - `deploy/scripts/08-verify-network-policy-enforcement.sh` proves the live CNI enforces them.
- If any deny check unexpectedly succeeds during Step 21, stop. Fix the k3s network-policy implementation before moving to Phase 5.
- Once Step 21 passes, Chunk 4 is complete and Phase 5 is the next open phase.

**Chunk 4 exit criteria**

- `external-secrets` is installed in namespace `external-secrets` at the pinned chart version from `deploy/scripts/lib/phase-4-version-contract.sh`, and its controller/webhook/cert-controller pods are ready.
- `cert-manager` is installed in namespace `cert-manager` at the pinned chart version, and the live Helm values still show `config.enableGatewayAPI=true`.
- The Step 15 host redirect experiment has been fully removed from the OCI host; no stale `PREROUTING REDIRECT` rules, no debug `INPUT dpt:30080 ACCEPT` rules, and no leftover direct-instance `INPUT` accepts for public `80` or `443` remain.
- The earlier direct-to-instance OCI public `80`/`443` exposure has been removed; the NLB frontend and the instance backend path now use separate OCI controls.
- The checked-in ingress service configuration is compatible with OCI NLB exposure and preserves client IP at the ingress gateway via `externalTrafficPolicy: Local`.
- The reviewed Phase 4 HTTP listener is reachable through a public OCI Network Load Balancer, and packet capture on the instance proves the ingress path preserves the workstation client IP.
- The checked-in NetworkPolicy manifests are present in `default`, `infrastructure`, `istio-ingress`, and `istio-egress`.
- A runtime probe-based verification proves the selected k3s network-policy implementation actually enforces the repo's allow/deny contract. Without that proof, do not claim Chunk 4 complete and do not move to Phase 5.

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
   # Fill in the instance-specific, non-secret OCI, routing, and contact values.
   # Production image refs stay in kubernetes/production/apps/image-inventory.yaml.
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
