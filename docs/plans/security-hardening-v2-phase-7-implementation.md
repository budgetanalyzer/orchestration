# Security Hardening v2 Phase 7 Implementation Plan

## Goal

Break Phase 7 into bounded sessions so image pinning, installer hardening,
admission policy work, and runtime verification can land incrementally without
mixing too many failure modes into one change set.

This plan is orchestration-led, but it is not orchestration-only. Phase 7
touches:

- this repository
- sibling Dockerfiles and configuration where image/base-image pinning belongs
- the shared `workspace` devcontainer/tooling image

It still does **not** require sibling service business-logic changes.

## Current State Snapshot (March 26, 2026)

Phase 6 is the latest completed hardening phase. Phase 7 is still open.

Historical snapshot note: the installer findings below describe the repo state
before Session 4 landed. Current-state tracking for the hardened workspace
tooling path appears in the Session 4 status section and the remediation docs.

Current repo reality:

- Third-party images are only partially pinned. Many refs are still tag-only,
  not immutable digests. Examples include:
  - `postgres:16-alpine` in `kubernetes/infrastructure/postgresql/statefulset.yaml`
  - `redis:7-alpine` in `kubernetes/infrastructure/redis/deployment.yaml`
  - `rabbitmq:3.13-management` in `kubernetes/infrastructure/rabbitmq/statefulset.yaml`
  - `eclipse-temurin:24-jre-alpine` and `alpine:3.22.2` in `Tiltfile`
  - `golang:1.24-alpine` and `gcr.io/distroless/static:nonroot` in `ext-authz/Dockerfile`
  - sibling Dockerfiles in `../transaction-service`, `../currency-service`,
    `../permission-service`, `../session-gateway`, and
    `../budget-analyzer-web`
- Installer guidance is still weak in several places:
  - `setup.sh` auto-installs Helm via `get-helm-3 | bash`
  - `scripts/dev/check-tilt-prerequisites.sh` recommends Helm/Tilt install
    commands that pipe remote scripts to `bash`
  - `docs/tilt-kind-setup-guide.md` still uses pipe-to-shell and floating
    `stable.txt` / `latest` download patterns
  - `tests/shared/Dockerfile.test-env` still installs Helm and Tilt by piping
    remote scripts to `bash`
  - `../workspace/ai-agent-sandbox/Dockerfile` still uses
    `setup_lts.x | bash`, `get-helm-3 | bash`, and Tilt's install script
- Kyverno is no longer just a smoke scaffold. The repo now ships the enforce
  policy suite under `kubernetes/kyverno/policies/`, retains the scoped smoke
  policy as `00-smoke-disallow-privileged.yaml`, and carries checked-in
  positive/negative Kyverno CLI fixtures under `kubernetes/kyverno/tests/`.
- Static manifest validation is not implemented yet. There is no checked-in
  `kubeconform` config, `kube-linter` config, Kyverno CLI test suite, or
  orchestration workflow that runs them.
- Runtime verifiers cover Phases 0 through 6, but there is no Phase 7
  completion gate that proves the new supply-chain and admission guardrails.
- The existing DinD suites are not safe to reuse blindly for Phase 7 work:
  `tests/security-preflight` and `tests/setup-flow` still reference Envoy
  Gateway and older Gateway API / Istio versions. If they are used for Phase 7,
  they must be realigned first.

## Implementation Rules

- Keep allowing repo-owned local build outputs tagged `:latest`, but only for
  the known Tilt-built images and only with `imagePullPolicy: Never`.
- Treat third-party refs as Phase 7 targets. Pin them as `name:tag@sha256:...`
  so humans can still read the version while Kubernetes and Docker get
  immutability.
- Do not try to make Kyverno prove full network reachability. Kyverno should
  enforce intent and baseline invariants; static and runtime verifiers should
  prove actual `NetworkPolicy` coverage and enforcement.
- Use narrow exceptions for chart-managed or intentionally special resources
  such as the Istio ingress gateway token-retention case. Do not solve Phase 7
  with broad namespace-wide exclusions that gut the policies.
- Keep certificate generation host-only. Phase 7 may harden guidance around
  certificate tooling, but it must not move `mkcert` or OpenSSL key generation
  into agent-run automation.

## Session Breakdown

### Session 1: Freeze The Contract

**Objective**

Create the decision baseline before mass edits start.

**Status (March 27, 2026)**

Session 1 is implemented. The source-of-truth inventory lives in
[`security-hardening-v2-phase-7-session-1-contract.md`](./security-hardening-v2-phase-7-session-1-contract.md).

Frozen outcomes:

- the only allowed local `:latest` exceptions are the seven known Tilt-built
  images, each backed by a checked-in manifest with `imagePullPolicy: Never`
- orchestration-owned third-party pinning targets now have an explicit
  inventory across manifests, inline Tilt Dockerfiles, `ext-authz`, runtime
  verifier scripts, Kind configs, and retained DinD assets
- the sibling scan found coordinated pinning targets in
  `transaction-service`, `currency-service`, `permission-service`,
  `session-gateway`, `budget-analyzer-web`, and `workspace/ai-agent-sandbox`,
  while `service-common` and `checkstyle-config` currently have no relevant
  `image:` or `FROM` refs
- `tests/setup-flow` and `tests/security-preflight` are frozen as stale,
  non-gating Phase 7 assets until they are realigned to the current Istio-only
  baseline
- explicit exclusions are recorded for documentation-only snippets and grep
  false positives so later sessions do not argue about scope

**Work**

- Inventory every third-party `image:` and `FROM` reference in:
  - this repo
  - sibling service Dockerfiles
  - sibling repos that may carry coordinated build assets, to confirm whether
    they are in scope or have no relevant refs
  - `../workspace/ai-agent-sandbox/Dockerfile`
- Classify every image ref as one of:
  - allowed local Tilt image
  - third-party runtime image
  - third-party build/base image
  - test-only image
- Record explicit out-of-scope exclusions discovered during the inventory, such
  as documentation example `FROM` lines and non-deployment template Dockerfiles.
- Record sibling scan results for repos that currently have no relevant
  `image:` or `FROM` refs requiring action, such as `../service-common` and
  `../checkstyle-config`.
- Freeze the pinning rule:
  - local Tilt images may stay `:latest`
  - every third-party image/base image must carry `@sha256:`
- Freeze the installer rule:
  - no new pipe-to-shell guidance
  - no floating `stable.txt` / `latest` install instructions where a pinned,
    integrity-checked release artifact is available
- Freeze the DinD contract:
  - `tests/setup-flow` and `tests/security-preflight` are stale, non-gating
    assets for Phase 7 until they are explicitly realigned to the current
    Istio-only baseline
  - if those files remain checked in, their third-party image refs still follow
    the same digest-pinning rule as the rest of the repo

**Likely files touched**

- `docs/plans/security-hardening-v2-phase-7-implementation.md`
- `docs/dependency-notifications.md`
- optional new helper doc or checklist if the inventory should live outside the
  plan

**Verification**

- A simple discovery pass can explain every third-party image reference.
- The inventory distinguishes active pinning targets from explicit
  documentation/template exclusions.
- The exemption list for local `:latest` images is explicit and reviewable.

**Done when**

- Sessions 2 through 8 can execute without arguing about what counts as a pin,
  what counts as a valid exception, or which repos are in scope.

### Session 2: Pin Orchestration-Owned Third-Party Images

**Objective**

Make the orchestration repo itself immutable from a third-party image
perspective.

**Status (March 27, 2026)**

Session 2 is implemented in-repo.

Implemented outcomes:

- all orchestration-owned third-party `image:` refs in active manifests and the
  retained DinD assets now use `name:tag@sha256:...`
- the inline Tilt Dockerfiles, `ext-authz/Dockerfile`, the retained
  `tests/shared/Dockerfile.test-env`, and both Kind configs are digest-pinned
- Phase 0 through Phase 6 verifier image constants now use digest-pinned probe
  images so the runtime proofs themselves stop drifting
- the retained `tests/setup-flow` Kind node image intentionally remains on
  `kindest/node:v1.32.2` while the main local cluster config remains on
  `kindest/node:v1.30.8`; that divergence is now documented as a retained-suite
  artifact, not an active parity target
- `scripts/dev/check-phase-7-image-pinning.sh` provides the static scan that
  fails on missing digests or unexpected `:latest` refs outside the seven
  allowed local Tilt images

**Work**

- Pin third-party runtime images in checked-in manifests:
  - PostgreSQL
  - Redis
  - RabbitMQ
  - `nginxinc/nginx-unprivileged`
  - `busybox` init containers in service deployments
  - retained test DinD images such as `docker:27-dind`
- Pin third-party base images in orchestration-owned Dockerfiles and inline
  Dockerfile content:
  - `Tiltfile` Spring Boot JRE bases
  - `Tiltfile` production-smoke `alpine`
  - `ext-authz/Dockerfile` builder/runtime bases
  - `tests/shared/Dockerfile.test-env`
- Pin probe images embedded in verifier scripts so runtime tests stop drifting:
  - `busybox`
  - `curlimages/curl`
  - `postgres`
  - any other inline probe image constants used by Phase 2 through Phase 6
- Pin the Kind node images used by orchestration-owned cluster configs to
  digests, not just tags. If the main Kind config and the retained DinD test
  config intentionally stay on different Kubernetes versions, document why.
- Add one checked-in static scan that fails if a third-party orchestration-owned
  image ref is missing `@sha256:` or if an unexpected `:latest` appears.

**Likely files touched**

- `kubernetes/infrastructure/postgresql/statefulset.yaml`
- `kubernetes/infrastructure/redis/deployment.yaml`
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`
- `kubernetes/services/nginx-gateway/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`
- `kubernetes/services/permission-service/deployment.yaml`
- `kubernetes/services/transaction-service/deployment.yaml`
- `kubernetes/services/session-gateway/deployment.yaml`
- `Tiltfile`
- `ext-authz/Dockerfile`
- `kind-cluster-config.yaml`
- `tests/setup-flow/kind-cluster-test-config.yaml`
- `tests/shared/Dockerfile.test-env`
- `tests/setup-flow/docker-compose.test.yml`
- `tests/security-preflight/docker-compose.test.yml`
- `scripts/dev/verify-security-prereqs.sh`
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- `scripts/dev/verify-phase-2-network-policies.sh`
- `scripts/dev/verify-phase-4-transport-encryption.sh`
- `scripts/dev/verify-phase-5-runtime-hardening.sh`
- `scripts/dev/verify-phase-6-edge-browser-hardening.sh`
- `scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh`
- `scripts/dev/check-phase-7-image-pinning.sh`

**Verification**

- `rg` scans over orchestration-owned `image:` and `FROM` refs show digests on
  every third-party reference.
- Changed Dockerfiles still build.
- Existing verifiers still parse and use the now-pinned probe image constants.

**Done when**

- The orchestration repo no longer depends on mutable third-party image tags.

### Session 3: Cross-Repo Base-Image Pinning

**Objective**

Close the cross-repo gaps that Phase 7 explicitly calls out but this repo does
not own by itself.

**Status (March 27, 2026)**

Session 3 is implemented.

Implemented outcomes:

- sibling service Dockerfile base images are now digest-pinned in
  `../transaction-service`, `../currency-service`, `../permission-service`,
  `../session-gateway`, and `../budget-analyzer-web`
- the Java service Dockerfiles now share the same digest-pinned Temurin 24
  builder/runtime bases already used by the orchestration `Tiltfile`
- both `budget-analyzer-web` Dockerfiles now pin the `node:20-alpine` base
  image to an immutable digest
- `../workspace/ai-agent-sandbox/Dockerfile` now pins its Ubuntu 24.04 base
  image to an immutable digest as well, so the Session 3 cross-repo image
  inventory is fully closed

**Work**

- Pin sibling service Dockerfile base images to digests:
  - `../transaction-service/Dockerfile`
  - `../currency-service/Dockerfile`
  - `../permission-service/Dockerfile`
  - `../session-gateway/Dockerfile`
  - `../budget-analyzer-web/Dockerfile`
  - `../budget-analyzer-web/Dockerfile.dev`
- Pin `../workspace/ai-agent-sandbox/Dockerfile` base images and any
  third-party tooling images it depends on.
- Update the nearest docs in those repos if their build/setup stories change.
- Keep the scope to Dockerfiles and setup/config docs only. Do not pull service
  business logic into Phase 7.

**Verification**

- A cross-repo `rg -n '^FROM '` pass shows `@sha256:` on every third-party base
  image in the Session 3 target set.
- The owning repo's normal build path still works after the pin.

**Done when**

- Phase 7 image pinning is true across the orchestrated workspace, not just in
  this repo.

### Session 4: Replace Weak Installer Guidance

**Objective**

Remove the remaining "trust this mutable internet endpoint and pipe it into a
shell" instructions from the checked-in developer experience.

**Status (March 27, 2026)**

Session 4 is implemented across the orchestration-owned setup surfaces and the
coordinated workspace devcontainer.

Implemented outcomes:

- `scripts/dev/install-verified-tool.sh` now centralizes pinned,
  checksum-verified installs for `kubectl`, Helm, Tilt, and `mkcert`
- `setup.sh`, `scripts/dev/check-tilt-prerequisites.sh`,
  `docs/tilt-kind-setup-guide.md`, `docs/development/getting-started.md`, and
  `docs/development/local-environment.md` now point contributors at the
  verified install path instead of mutable pipe-to-shell flows
- `tests/shared/Dockerfile.test-env` now installs `kubectl`, Helm, Tilt, and
  `mkcert` from pinned artifacts instead of `stable.txt`, `latest`, or install
  scripts
- `../workspace/ai-agent-sandbox/Dockerfile` now uses a keyring-based
  NodeSource apt repo, Helm `v3.20.1` from a checksum-verified release
  tarball, and Tilt `0.37.0` from a checksum-verified release tarball
- Workstream 3 later removed the temporary
  `tmp/ai-agent-sandbox.Dockerfile.phase7-session4` handoff after the sibling
  workspace Dockerfile absorbed the same content

**Work**

- Replace Helm and Tilt install guidance with pinned release downloads plus
  checksum verification.
- Replace floating `kubectl stable.txt` guidance with an explicit tested
  version or version-family contract tied to the repo's Kind/Kubernetes
  baseline.
- Replace `mkcert latest` guidance with explicit versioned download guidance
  where package-manager install is not used.
- Replace NodeSource `setup_lts.x | bash` in the `workspace` devcontainer with
  a keyring-based apt repo or another integrity-checked install path.
- Consider adding a shared helper script for verified downloads so the repo
  does not duplicate checksum logic across `setup.sh`, test images, and docs.
- Update all affected docs in the same session.

**Likely files touched**

- `setup.sh`
- `scripts/dev/check-tilt-prerequisites.sh`
- `scripts/dev/setup-k8s-tls.sh`
- `README.md`
- `docs/tilt-kind-setup-guide.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `tests/shared/Dockerfile.test-env`
- `../workspace/ai-agent-sandbox/Dockerfile`

**Verification**

- A grep for `| bash`, `stable.txt`, and `latest?for=linux/amd64` no longer
  finds unapproved installer guidance in the active setup docs/scripts.
- Changed shell scripts still pass `bash -n`.
- The shared test image and workspace image still build.

**Done when**

- The repo stops telling contributors to install critical tooling through
  mutable pipe-to-shell flows.

### Session 5: Kyverno Policy Framework And Exceptions

**Objective**

Move from a smoke policy to a real, maintainable Phase 7 admission layer.

**Status (March 27, 2026)**

Session 5 is implemented in-repo.

Implemented outcomes:

- `kubernetes/kyverno/` now has a real layout with `policies/`,
  `tests/pass/`, `tests/fail/`, and a local README
- Tilt now applies the policy directory instead of a single scaffold file
- the enforce-mode Phase 7 suite now covers:
  - namespace Pod Security labels
  - `automountServiceAccountToken: false` for repo-owned workloads
  - the repo-owned workload `securityContext` baseline
  - obvious default-credential literals in workload env vars
  - third-party image digests with only the seven documented local `:latest`
    exceptions
- the retained smoke policy now lives inside the policy directory as a scoped
  bootstrap signal instead of being the whole Kyverno story
- the exception boundary is explicit and narrow: `istio-system`,
  `istio-ingress`, `istio-egress`, `kyverno`, and the core cluster namespaces
  are excluded from the repo-owned workload baseline so chart-managed/system
  pods do not get forced through rules this repo does not own, and fully
  mutated sidecar-injected Pods are skipped by the direct Pod digest rule while
  controller-spec autogen rules still enforce the repo-owned images
- repo-owned verifier/setup scripts that create temporary namespaces or probe
  pods now create policy-compliant resources up front, so the suite can stay in
  enforce mode without breaking the local proofs

**Work**

- Create a real policy layout under `kubernetes/kyverno/`, for example:
  - `kubernetes/kyverno/policies/`
  - `kubernetes/kyverno/tests/pass/`
  - `kubernetes/kyverno/tests/fail/`
- Update Tilt so it applies the policy directory, not just the smoke policy.
- Add the concrete Phase 7 policy set:
  - required workload `securityContext` baseline
  - required `automountServiceAccountToken: false`
  - rejection of obvious default credentials in manifests
  - required third-party image digests
  - required namespace Pod Security labels
- Roll the policy suite in deliberately:
  - prove the new rules against checked-in pass/fail fixtures and the current
    repo-managed manifests
  - finish the session with the intended Phase 7 baseline in enforce mode
- Handle `NetworkPolicy` coverage honestly:
  - do not try to make Kyverno prove selector correctness or live
    reachability
  - use the static and runtime verifiers as the actual coverage/enforcement
    proof
- Encode tight exceptions for known special cases:
  - ingress gateway token retention
  - egress gateway chart-managed behavior
  - Kyverno's own workloads
  - other chart-managed Istio resources that cannot satisfy the repo baseline
- Keep the existing smoke policy until the real policy suite is proven, then
  decide whether to retain it as a cheap bootstrap signal or retire it.

**Likely files touched**

- `kubernetes/kyverno/README.md`
- new `kubernetes/kyverno/policies/*.yaml`
- new `kubernetes/kyverno/tests/**`
- `Tiltfile`
- verifier/setup scripts that create namespaces or temporary probe pods

**Verification**

- `kyverno test` passes the positive and negative fixture set.
- The policy suite rejects intentionally insecure sample manifests.
- The policy suite admits the current repo-managed manifests, plus the
  documented exception cases.
- The session does not stop in a long-lived audit-only state; the intended
  repo-owned baseline ends in enforce mode.

**Done when**

- Kyverno enforces Phase 7 baseline rules instead of only proving that Kyverno
  itself is alive.

### Session 6: Static Manifest Validation And PR CI

**Objective**

Catch security regressions before anyone applies manifests to a cluster.

**Status (March 27, 2026)**

Session 6 is implemented in-repo.

Implemented outcomes:

- `scripts/dev/verify-phase-7-static-manifests.sh` is now the local static gate
  for Phase 7
- the gate bootstraps pinned `kubeconform`, `kube-linter`, and `kyverno`
  binaries into a repo-local cache via `scripts/dev/install-verified-tool.sh`
- `.kube-linter.yaml` captures the repo-specific lint baseline and keeps the
  exceptions explicit instead of burying them in workflow flags
- the gate runs `kubeconform`, `kube-linter`, Kyverno CLI tests, the existing
  image-pinning scan, a namespace PSA-label scan, and an active-doc/script
  pipe-to-shell scan
- `.github/workflows/security-guardrails.yml` runs the same gate on pull
  requests and `main`
- `tests/security-guardrails/fixtures/fail/` now provides intentional failing
  fixtures, and `--self-test` proves the workflow blocks those regressions

**Work**

- Add a local static-validation entrypoint, for example:
  - `scripts/dev/verify-phase-7-static-manifests.sh`
  - or a `--static-only` mode on the final Phase 7 gate
- Run `kubeconform` for schema validation against all checked-in manifests.
- Add `kube-linter` with a repo-specific config and documented exceptions.
- Run Kyverno CLI tests as part of the same local static gate.
- Add a lightweight pattern scan for:
  - unpinned third-party images
  - unexpected `:latest`
  - missing namespace PSA labels
  - lingering pipe-to-shell guidance
- Add a dedicated GitHub Actions workflow for static security guardrails.
- Keep the new workflow additive alongside the existing `test-setup.yml`
  script/setup checks instead of folding Phase 7 guardrails into that older
  workflow.
- Keep this workflow independent of the stale DinD suites unless those suites
  are first realigned to the current Istio-only baseline.

**Likely files touched**

- `.github/workflows/security-guardrails.yml`
- new tool config files such as `.kube-linter.yaml`
- new static-verifier scripts under `scripts/dev/`
- `scripts/README.md`
- `docs/ci-cd.md`

**Verification**

- The static workflow runs on PRs and `main`.
- An intentional failing fixture proves the workflow really blocks bad changes.
- The local static command matches the workflow behavior closely enough that
  contributors can reproduce failures without guessing.

**Done when**

- Manifest and installer regressions fail fast in CI instead of surfacing only
  during `tilt up`.

### Session 7: Runtime Guardrail Proof

**Objective**

Prove the policies work in a live cluster, not just on paper.

**Status (March 27, 2026)**

Session 7 is implemented in-repo.

Implemented outcomes:

- `scripts/dev/verify-phase-7-runtime-guardrails.sh` now provides the live
  Phase 7 runtime proof
- the verifier creates pinned, policy-compliant Redis and PostgreSQL probe pods
  plus self-cleaning temporary `NetworkPolicy` rules, so the new checks can run
  on an existing cluster without leaving stray resources behind
- the new Phase 7 assertions now cover:
  - Redis ACL denials for forbidden commands and forbidden key patterns
  - PostgreSQL cross-database denials for non-owner service users
  - RabbitMQ denials for unauthorized vhost, queue, and exchange access
- the reused-regression story is explicit instead of implicit:
  `verify-phase-7-runtime-guardrails.sh` reruns
  `verify-phase-6-edge-browser-hardening.sh` as the Phase 6 umbrella, which in
  turn preserves the intended Phase 2 through Phase 6 runtime coverage while
  keeping the Session 7 summary separated between new Phase 7 assertions and
  reused regressions

**Work**

- Add a new runtime verifier, for example
  `scripts/dev/verify-phase-7-runtime-guardrails.sh`.
- Reuse existing verifiers where they already prove part of the story:
  - Phase 2 for deny/allow `NetworkPolicy` enforcement
  - Phase 3 for spoofed identity header rejection
  - Phase 4 for TLS-only transport and plaintext-failure paths
  - Phase 6 for auth-endpoint throttling and API rate-limit identity
- Add the Phase 7 gaps that are not already covered:
  - unauthorized pod denied to `nginx-gateway:8080`
  - unauthorized pod denied to Redis, PostgreSQL, and RabbitMQ
  - Redis ACL negative tests for forbidden commands and forbidden key patterns
  - PostgreSQL negative tests for cross-database access
  - RabbitMQ negative tests for unauthorized vhost / queue / exchange access
  - approved external hosts reachable through the egress path
  - non-approved external hosts blocked
- Keep all temporary probe pods, policies, and port-forwards self-cleaning and
  time-bounded.
- Use pinned probe images so the runtime proof is itself supply-chain-stable.

**Likely files touched**

- new `scripts/dev/verify-phase-7-runtime-guardrails.sh`
- optional new `scripts/dev/lib/*.sh` helpers
- `scripts/README.md`

**Verification**

- The new runtime verifier can be rerun on an existing Tilt cluster and leaves
  no stray resources behind.
- The verifier summary clearly separates new Phase 7 assertions from reused
  Phase 2 through Phase 6 regressions.

**Done when**

- Phase 7 has a real live-enforcement proof instead of only manifests and
  admission tests.

### Session 8: Final Gate, Docs, And Recorded Evidence

**Objective**

Make Phase 7 discoverable and maintainable after the implementation work lands.

**Status (March 27, 2026)**

Session 8 is implemented in-repo.

Implemented outcomes:

- `scripts/dev/verify-phase-7-security-guardrails.sh` is now the single local
  Phase 7 completion gate
- the final gate runs `scripts/dev/verify-phase-7-static-manifests.sh` first
  and `scripts/dev/verify-phase-7-runtime-guardrails.sh` second
- the wrapper exposes only narrow runtime-timeout passthrough flags instead of
  becoming a generic argument forwarder
- the README and supporting docs now point contributors to one local Phase 7
  completion command while still documenting the static gate as the CI/local
  Session 6 reproducer
- the final local Phase 7 gate passed on March 27, 2026 via
  `./scripts/dev/verify-phase-7-security-guardrails.sh`

**Work**

- Add a final Phase 7 completion command, for example
  `scripts/dev/verify-phase-7-security-guardrails.sh`, that runs:
  - static checks
  - Kyverno tests
  - the Phase 7 runtime verifier
  - the required earlier-phase regressions
- Update the nearest docs in the same session:
  - `README.md`
  - `scripts/README.md`
  - `docs/architecture/security-architecture.md`
  - `docs/development/getting-started.md`
  - `docs/development/local-environment.md`
  - `docs/ci-cd.md`
  - `docs/dependency-notifications.md`
  - `docs/plans/security-hardening-v2.md`
- Record the exact command and exact pass date once the final gate succeeds.
- Record the DinD disposition explicitly. Unless the suites were realigned
  earlier, document that `tests/setup-flow` and `tests/security-preflight` are
  stale, non-gating assets and not part of the Phase 7 completion gate.

**Verification**

- A new contributor can find one Phase 7 command in the README/docs and one
  workflow in `.github/workflows/`.
- The master security-hardening plan points to the final Phase 7 gate and the
  pass date when complete.

**Done when**

- Phase 7 is not just implemented; it is documented, repeatable, and easy to
  audit later.

## Recommended Order

Use this order unless a concrete repo-specific blocker forces a split:

1. Session 1 first. Do not start patching until the pinning and exception rules
   are frozen.
2. Sessions 2 and 3 next. They can run in parallel because they own different
   write scopes.
3. Session 4 after Session 1. It can overlap with Sessions 2 and 3.
4. Session 5 after Sessions 2 and 4, because the image and installer contracts
   should be stable before admission policies try to enforce them.
5. Session 6 after Session 5.
6. Session 7 after Sessions 2, 5, and 6, and only once the current Phase 6
   completion gate is green.
7. Session 8 last.

## Definition Of Done For This Breakdown

Treat the Phase 7 implementation effort as complete only when all of the
following are true:

- third-party images and base images are digest-pinned across the orchestrated
  workspace
- weak installer guidance is removed from the checked-in setup experience
- Kyverno enforces the intended Phase 7 admission baseline with documented
  exceptions
- static validation runs both locally and in CI
- runtime verification proves the live cluster enforces the new guardrails
- the docs point to one clear Phase 7 completion command and the master plan is
  updated with the result
