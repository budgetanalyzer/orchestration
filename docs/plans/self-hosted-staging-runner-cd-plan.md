# Plan: Self-Hosted Staging Runner For CD

Date: 2026-06-04
Status: Preliminary

Related documents:

- `docs/ci-cd.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `kubernetes/production/README.md`

## Scope

This plan sketches a no-additional-cloud-cost staging and release-validation
path using a home Linux media/testing box as a GitHub Actions self-hosted
runner.

The immediate target machine is the ASUS PN50 media/testing box documented in
the sysadmin workspace. It is an `amd64` host, while the OCI production target
is `arm64`. That architecture mismatch is a first-class design constraint, not
an implementation detail.

## Problem Statement

The current production release path is review-driven and digest-pinned, but it
does not yet have a credible pre-production environment that can run deployed
black-box API tests before production changes are applied.

Adding a second OCI instance would solve the environment-boundary problem but
adds cost. A home self-hosted runner can provide useful staging coverage with
no public inbound exposure if the release images support the runner's CPU
architecture.

## Goals

1. Add a low-cost staging gate before OCI production deployment.
2. Exercise GitHub Actions job routing through a self-hosted runner.
3. Run the deployed stack from immutable release images rather than local Tilt
   dev images.
4. Verify release image signatures before treating candidate images as eligible
   for staging or production promotion.
5. Run standalone black-box HTTP/API acceptance tests against the staging
   deployment.
6. Preserve the existing manual production approval gate.
7. Avoid exposing the home machine, Kubernetes API, observability tools, or
   staging ingress publicly.

## Non-Goals

- Replace OCI production.
- Turn the home box into a public staging server.
- Store production deploy credentials on the home box in the first iteration.
- Build a full always-on duplicate production environment.
- Hide service-owned defects with orchestration-level compensating changes.

## Recommended Direction

Use the home box as a private staging executor:

```text
GitHub Actions -> self-hosted runner job assignment over outbound HTTPS
home runner -> deploy candidate release images to local staging cluster
home runner -> run standalone API tests against private staging ingress
human -> review results and approve production desired-state change
OCI host -> apply reviewed production manifest
```

GitHub does not need inbound connectivity to the home runner. The runner
maintains outbound HTTPS/WebSocket or long-poll communication with GitHub
Actions, receives jobs over that connection, and streams logs/results back to
GitHub over outbound HTTPS.

## Architecture Constraint: Image Platforms

The current release workflows publish `linux/arm64` images only. That is
correct for OCI Free Tier A1 production, but it means an `amd64` PN50 cannot
run the current GHCR release images.

Before the PN50 can validate release images, service release workflows should
publish multi-arch images:

```text
linux/amd64
linux/arm64
```

The PN50 will then pull the `amd64` variant, and OCI will pull the `arm64`
variant, from the same release tag or manifest-list reference. This validates
the same Dockerfiles, release workflow, image labels, tags, deployment
manifests, routing, and API behavior, while acknowledging that platform-specific
layers are not byte-identical.

The production ARM image still needs a production-side pull/start proof during
OCI deployment verification.

## Supply Chain Constraint: Digest Pinning And Signatures

Digest pinning and image signing solve different parts of the release trust
problem. The existing production desired-state model records immutable image
digests so deployment applies the exact reviewed image bytes. Image signing
should add proof that those same digests were produced by the trusted release
workflow from the expected source repository and ref.

The staging gate should eventually verify both:

- the deployment manifest and image inventory reference digest-pinned images
- each candidate digest has a valid signature from the expected GitHub Actions
  workflow identity

Recommended first implementation:

- use `cosign` keyless signing from each owning repository's
  `publish-release.yml` workflow through GitHub Actions OIDC
- sign the pushed digest, not just the mutable tag
- verify signatures in the staging workflow before deployment
- record signature verification evidence alongside the staging test artifacts
- keep production admission enforcement as a later hardening step after
  workflow-side signing and staging-side verification are stable

Later options:

- enforce signature policy in the cluster with Kyverno `verifyImages` or an
  equivalent admission policy
- add provenance attestations and SBOMs once signature verification is reliable
- require production apply to fail if any managed artifact lacks a trusted
  signature

## Proposed Release Flow

### Phase 1: Release Image Baseline

AI assistant:

- Update release workflow standards to build multi-arch images where supported.
- Add release image signing to each owning repository's release workflow.
- Add a staging verifier that confirms every candidate digest is signed by the
  expected repository/workflow identity before deployment.
- Update orchestration documentation to record multi-arch release-image policy.
- Update orchestration documentation to record the difference between digest
  pinning, signing, provenance, and SBOMs.
- Add or update static checks that prevent accidental return to single-arch
  release images if practical.
- Add or update checks that prevent unsigned candidate images from passing the
  staging gate after signing is adopted.
- Verify that pinned base images and build tooling support both platforms.

Human operator:

- Review the change in each owning repository.
- Confirm GHCR package visibility and permissions are acceptable.
- Confirm the intended trusted signing identities for each release workflow.
- Decide whether multi-arch publishing applies to all runtime artifacts at
  once or rolls out service by service.

### Phase 2: Self-Hosted Runner Provisioning

Human operator on the home box:

- Create a dedicated non-root runner user.
- Install the GitHub Actions runner as that user.
- Register the runner with repository or organization scope using restricted
  labels such as `self-hosted`, `linux`, `x64`, and `pn50-staging`.
- Install it as a systemd service so it survives reboots.
- Keep the machine private; do not add router port forwards for staging.

Suggested user shape:

```bash
sudo adduser --disabled-password --gecos "GitHub Actions Runner" gha-runner
sudo usermod -aG docker gha-runner
sudo install -d -o gha-runner -g gha-runner -m 0750 /opt/actions-runner
```

The exact runner registration command should come from GitHub's runner setup
page because the registration token is short-lived.

AI assistant:

- Prepare documentation and scripts that assume a pre-existing runner label.
- Avoid requiring root on the box from repo automation.
- Keep production OCI credentials out of the staging runner workflow unless a
  later explicit design makes the home box part of the production trust
  boundary.

### Phase 3: Home Box Prerequisites

Human operator on the home box:

- Install Docker or another supported container runtime.
- Install Kind or k3s for the private staging cluster.
- Install `kubectl`.
- Install `helm` if the staging deploy path needs Helm-rendered dependencies.
- Install `git`.
- Install `jq`, `curl`, `bash`, and `ca-certificates`.
- Install `mkcert` only if browser-trusted local TLS is needed on that host.
- Run any certificate generation from the host, not from an AI container.

AI assistant:

- Align prerequisite checks with the existing local-development and deployment
  docs rather than inventing a parallel toolchain.
- Prefer checked-in bootstrap/preflight scripts over manual drift.
- Add a focused staging prerequisite verifier before adding deployment logic.

Open decision:

- Choose Kind or k3s for staging. Kind is closer to current local development;
  k3s is closer to the OCI runtime path.

Current recommendation:

- Start with Kind if the goal is quickest GitHub-runner staging.
- Move to k3s if OCI parity becomes more important than setup simplicity.

### Phase 4: Staging Deployment Shape

AI assistant:

- Define a staging overlay or deployment script that consumes the same
  digest-pinned image inventory used for production candidates.
- Verify release image signatures before applying the candidate image inventory
  to staging.
- Keep staging namespaces and data stores separate from any production state.
- Ensure staging ingress is private to the home box or LAN/VPN.
- Add cleanup/reset commands for staging data and cluster state.
- Add smoke verification that proves the deployed images, pods, routing, auth
  lane, and API docs surface are behaving.

Human operator:

- Decide whether staging should be always-on or ephemeral per release
  qualification run.
- Decide whether LAN-only access is enough or whether private VPN access such
  as Tailscale/WireGuard is useful.

Current recommendation:

- Use ephemeral staging at first:

```text
create or reset staging cluster
deploy candidate desired state
run API acceptance tests
preserve logs/artifacts
destroy or idle the environment
```

## Standalone API Test Repository Prerequisite

A credible staging gate needs black-box HTTP/API tests that live outside the
deployed service repos. The detailed implementation plan lives in
`docs/plans/openapi-black-box-api-test-repository-plan.md`.

Recommended shape:

```text
budget-analyzer-api-tests/
  tests/
    auth/
    routing/
    transactions/
    currency/
    permissions/
    api_docs/
    security/
  environments/
    local.yaml
    staging.yaml
    production.yaml
  schemas/
  README.md
```

Preferred initial technology:

- `pytest` plus `httpx` for HTTP tests
- schema assertions where response shape is part of the contract
- environment files for local, staging, and production targets

AI assistant:

- Scaffold the test repo when requested.
- Add initial smoke and routing tests.
- Wire tests into the self-hosted runner workflow.

Human operator:

- Decide repository ownership and visibility.
- Provide test credentials or test identity setup strategy.
- Review any API behavior changes before approving deployment.

## Manual Gate

The manual gate stays between candidate validation and production apply.

The minimum evidence for approval should include:

- GHCR release workflows completed for changed artifacts.
- Orchestration desired-state PR records expected digest-pinned images.
- Candidate image digests have trusted release-workflow signatures.
- Self-hosted staging workflow passed.
- Standalone API tests passed against staging.
- Any public HTTP behavior changes include matching API test updates or an
  explicit waiver.
- OCI production deployment checklist has been prepared.

Production apply should remain a separate, reviewed action until the project
intentionally adopts in-cluster GitOps or another production deployment
executor.

## Security Guardrails

- Do not expose the home runner publicly.
- Do not run the runner as root.
- Do not attach broad runner labels that unrelated workflows can target.
- Do not store production secrets on the home runner during the first
  iteration.
- Do not allow pull requests from untrusted forks to run arbitrary code on the
  self-hosted runner.
- Prefer GitHub environments and required reviewers for any workflow that can
  affect deployment state.
- Treat digest pinning as necessary but insufficient once signing is adopted:
  staging should reject unsigned or incorrectly signed candidate images.
- Treat runner compromise as local-machine compromise; keep the trust boundary
  narrow.

## Open Questions

1. Should the runner be repository-scoped or organization-scoped?
2. Should staging use Kind first or k3s first?
3. Should staging be ephemeral per run or a persistent local cluster?
4. Should the standalone API test repo be public, private, or initially local?
5. How should test identities and seed data be provisioned without coupling the
   API tests to service internals?
6. Should image signatures be enforced only in the staging workflow at first,
   or also by production cluster admission after the signing baseline is stable?
7. Should production deployment remain host-run/manual, or eventually move to
   Flux/Argo CD after the staging gate is reliable?

## Initial Success Criteria

- A self-hosted runner appears online in GitHub with a dedicated staging label.
- A GitHub Actions workflow can run a harmless command on the PN50 over outbound
  runner connectivity only.
- Release workflows publish multi-arch images for at least one service.
- Release workflows sign candidate image digests for at least one service.
- The staging workflow verifies the trusted signature for at least one
  candidate image before deployment.
- The staging cluster can deploy a candidate image by immutable reference.
- A standalone API smoke test can run from the staging runner and report results
  back to GitHub Actions.
- No public inbound network exposure is required.
