# Scripts Directory

This directory contains automation for the Budget Analyzer orchestration
repository. Scripts are grouped by purpose so setup, validation, operational,
loadtest, and repository-management tasks have stable entry points.

This README is the canonical catalog for the `scripts/` tree and for
cross-cutting verifier entry points. The maintained provider-neutral,
render-only production surface under `../deploy/scripts/` is owned by
[../deploy/README.md](../deploy/README.md).

The removed OCI scripts preserved below `../archive/oci/` are frozen
historical copies, not members of the active `scripts/` or `deploy/scripts/`
catalogs. Do not add
archive paths to maintained image-pinning inventories, deployment acceptance
checks, shell validation sweeps, build discovery, or update automation. General
secret detection still applies. See
[../archive/oci/README.md](../archive/oci/README.md) for the lean archive and
complete-tree history boundary.

## Layout

```
scripts/
├── bootstrap/   # Host and cluster bootstrap helpers
├── guardrails/  # CI-safe static security and manifest checks
├── lib/         # Shared shell helpers and maintained inventories
├── loadtest/    # Synthetic local fixture data helpers
├── ops/         # Day-to-day local cluster operations
├── repo/        # Cross-repository management helpers
└── smoketest/   # Local live-cluster validation gates
```

## Canonical Entry Points

- [Workspace host-isolation audit](../../workspace/docs/host-isolation-audit.md) - Workspace-owned entry point
  for the human-only personal-host isolation audit, private evidence handling,
  collector, protocol fixture and binary verifier. Orchestration does not keep
  fallback copies of those tools.
- `../setup.sh` - Human-run first bootstrap against the local Docker daemon
  using the three supplied ingress TLS files. It installs the pinned platform
  tools, recreates Kind and is not a daily-start command.
- `bootstrap/check-local-runtime.sh` - Read-only daily application preflight
  requiring Kind's Docker provider, a reachable local Docker Unix-socket daemon
  and the exact Ready loopback `kind-kind` Kubernetes target. It has no
  workspace dependency.
- `bootstrap/install-imported-ingress-tls.sh` - Non-generating imported TLS
  validator and strict local-`kind-kind` Secret installer; use
  `--validate-only` for static file checks. Tilt uses its default install mode
  to reconcile the existing files into the Secret. This script never changes
  client trust.
- `bootstrap/check-tilt-prerequisites.sh` - Tooling and environment preflight.
  It checks orchestration repository inputs, exact tool versions, local Docker,
  the Ready loopback `kind-kind` target, supplied ingress TLS and system-bundle
  trust, Tilt and runtime-security diagnostics without invoking workspace.
- `../tests/local-kubernetes-target/test-local-kubernetes-target.sh` - Tracked
  fail-closed fixtures for wrong Kubernetes context/referenced cluster,
  nonloopback, malformed or deceptive API authorities, kubeconfig proxy
  redirection and missing control-plane node, plus the Docker guard's
  `KIND_EXPERIMENTAL_PROVIDER` contract: unset, empty and `docker` pass;
  alternate and malformed values fail before any Docker, Kind or kubectl
  command. All fixtures use command stubs.
- `../tests/local-runtime/test-check-local-runtime.sh` - Offline stub fixtures
  for the daily wrapper: local Docker Unix-socket selection and reachability,
  Kind provider rejection, exact Kind enforcement, read-only success, and
  unknown-option and extra-argument rejection with exit status, diagnostics
  and no Docker, Kind or kubectl invocation. Its final check is structural
  evidence only: a source ordering check that `setup.sh` places the shared
  Docker/Kind-provider guard before its Kind deletion line; it does not execute
  setup or prove every mutation path.
- `../tests/tilt-prerequisites/test-client-trust.sh` - Offline real-OpenSSL
  chain, hostname and bundle-only verification using the public test-only
  certificates in `fixtures/client-trust/`: a matching root/leaf passes, while a wrong
  hostname, an unrelated root bundle and a root available only through
  `SSL_CERT_DIR` fail. A command stub covers OpenSSL stderr propagation. It
  also runs the copied prerequisite checker with failing Docker, Kind and
  kubectl stubs to prove missing and untrusted leaves are reported as trust
  failures, without mkcert.
- `../tests/tilt-prerequisites/test-local-target-gating.sh` - Offline stub
  fixtures running the prerequisite checker with an absent Kind cluster, a
  wrong Kubernetes context and an alternate Kind provider. Tool checks still
  report, while cluster-specific Docker, Kind and kubectl commands do not run
  until the exact target passes.
- `../tests/imported-ingress-tls/test-install-imported-ingress-tls.sh` -
  Offline command fixtures that reproduce the zero-exit `x509 -checkhost`
  mismatch, require hostname-aware chain verification, accept the matching
  hostname and prove wrong-host rejection precedes mutation.
- `smoketest/smoketest.sh` - Aggregate local validation sequence for a live
  Tilt cluster.
- `smoketest/verify-istio-ingress.sh` - Focused live Istio ingress/egress
  verifier. In addition to gateway identity, mTLS, routing, rate limiting,
  header sanitization, and egress controls, it inspects the rendered Envoy
  `ext_authz` filter and proves unauthenticated JSON denials for `/api/*`,
  `/auth/v1/user`, and `/auth/v1/session` through the real local HTTPS ingress.
  It requires normal TLS verification and confirms the `/api/*` denial stops
  before NGINX routing. Parent verifiers that already completed the focused
  rate-limit proof may pass `--skip-ingress-rate-limits` to avoid repeating
  its bounded bursts and refill waits.
- `guardrails/verify-ingress-rate-limit-config.sh` - Offline, non-mutating
  structural guardrail for the four per-client Istio ingress policies. It
  renders the production overlay, requires the exact shared EnvoyFilter, checks
  insertion before `ext_authz`, token buckets, markers, metrics prefixes,
  bounded dynamic descriptors and the absence of a default bucket, requires
  path normalization plus encoded-slash rejection before filter selection,
  exercises path/query/method boundaries and equivalent authority spellings,
  and checks the maintained ingress gateway ConfigMap's narrow stats matcher.
  Its NGINX cutover scan fails closed for missing or unreadable
  inputs and distinguishes a clean negative search from a search error;
  `--self-test-nginx-search` proves the clean, forbidden-directive, and missing
  input cases with disposable fixtures. The verifier defaults to managed-VM
  `python3`, honors only `INGRESS_RATE_LIMIT_PYTHON` as its selected interpreter,
  verifies the exact PyYAML version declared in
  `guardrails/requirements-ingress-rate-limit.txt`, and reports the resolved
  interpreter and module path. This static render and matcher proof complements
  the live exhaustion, refill, and client-isolation proof in
  `smoketest/verify-ingress-rate-limits.sh`; it does not replace that runtime
  gate.
- `smoketest/verify-ingress-rate-limits.sh` - Focused live proof for the final
  ingress-only rate-limit architecture. It uses two controlled clients and a
  real browser login to prove client/policy isolation, forged-header resistance,
  authority-variant resistance, refill, callback completion, filter order,
  policy markers and counters, unauthenticated API protection, `ext_authz`
  short-circuiting, canonicalized double-slash limiting, encoded-slash ingress
  rejection, deterministic per-instance replica semantics, NGINX forwarded
  identity, and cleanup. Its replica proof retains direct child
  port-forward PIDs and logs in the parent shell, removes them through the EXIT
  trap on failure, and explicitly proves their processes, listeners, and logs
  are gone on success. Public requests use normal TLS verification.
- `smoketest/verify-observability-port-forward-access.sh` - Focused
  loopback-only Grafana, Prometheus, Jaeger, and Kiali port-forward verifier.
  It defaults to the canonical `3300`, `9090`, `16686`, and `20001` local
  ports, starts any missing temporary forwards itself, reuses the expected
  existing loopback `kubectl port-forward` listeners on those canonical ports,
  and accepts flag overrides when some other intentional listener already
  owns one of them. It verifies Grafana health,
  Prometheus readiness, Jaeger query API access, Kiali UI shell access, and
  that unauthenticated Grafana and Kiali API access is rejected. Use the same
  loopback-only access model for local Tilt, and do not use
  `--address 0.0.0.0` for observability access.
- `ops/start-observability-port-forwards.sh` - Foreground supervisor for the
  canonical loopback-only Grafana, Prometheus, Jaeger, and Kiali
  `kubectl port-forward` processes. It starts all four forwards by default,
  supports repeated `--component` selection plus per-component port overrides,
  prints the local URLs plus the Grafana password and Kiali token commands,
  and cleans up all child forwards on exit.
- `ops/triage-kiali-findings.sh` - Authenticates to Kiali, snapshots the
  current Kiali API findings plus recent Kiali warnings, compares them to live
  Kubernetes namespace object counts, and classifies the obvious buckets such
  as runtime-absent workloads, missing backend services, tracing dependency
  gaps, and likely low-signal waypoint warnings. The
  `--runtime-shape production` option remains useful when inspecting a runtime
  shaped like the maintained production reference (`nginx-gateway` serves the
  bundle; no standalone `budget-analyzer-web` Deployment).
- `ops/show-pod-version-labels.sh` - Lists pod release/reference metadata for the
  current Kubernetes context and warns when Budget Analyzer runtime pods do not
  match a schema v2 deployment manifest or the checked-in production image
  inventory. Use `--allow-mixed-deployment-id` when intentionally inspecting a
  selective historical rollout where unchanged pods retain an earlier
  runtime id. Use `--strict` when the warning check should fail the command.
- `ops/capture-prometheus-operator-baseline.sh` - Renders the upstream
  Prometheus stack without the repo post-renderer, extracts the operator RBAC
  objects, builds a representative `kubectl auth can-i` matrix for the
  operator service account, and refreshes the checked-in RBAC baseline note
  under `docs/research/`.
- `ops/post-render-prometheus-stack.sh` - Helm post-renderer for the
  Prometheus stack that replaces the upstream broad Prometheus Operator
  ClusterRole/ClusterRoleBinding with the repo-owned least-privilege split:
  one narrow cluster-read binding plus namespaced monitoring/default roles.
- `smoketest/verify-istio-tracing-config.sh` - Focused live-cluster verifier
  for the Jaeger OpenTelemetry extension provider and mesh-default Istio
  Telemetry resource.
- `smoketest/verify-monitoring-rendered-manifests.sh` - Renders the
  Prometheus stack and Kiali chart, then checks image pinning, service exposure,
  Kiali auth/RBAC posture, the exact approved Prometheus Operator
  namespace-scope args and effective RBAC model, and server dry-run compliance
  for rendered workload objects.
- `smoketest/verify-prometheus-operator-least-privilege.sh` - Full live
  verifier for the Prometheus Operator least-privilege posture. It reruns the
  rendered-manifest proof, checks the live operator RBAC object set, enforces
  the required positive and negative `kubectl auth can-i` matrix, reruns the
  monitoring runtime proof, and captures Kiali triage artifacts under `tmp/`.
- `guardrails/verify-static-security-manifests.sh` - Static manifest and
  security guardrail gate used by CI and local preflight. Its ingress
  rate-limit proof requires the exact PyYAML wheel declared in
  `guardrails/requirements-ingress-rate-limit.txt`; create the disposable
  `.cache/phase7-static-tools/pyyaml-venv` environment with the hash-verified
  install documented in `docs/ci-cd.md#security-guardrailsyml`, then set
  `INGRESS_RATE_LIMIT_PYTHON` to that environment's interpreter.
- `guardrails/verify-production-image-overlay.sh` - Non-mutating,
  provider-neutral verifier for the production reference: app and
  infrastructure overlays, route/authorization/ingress/egress/observability
  renders, immutable image provenance, and the production Kyverno image
  policy. Focused comparisons allow only the declared route hostname,
  standalone-frontend authorization omission, local gateway publication, and
  Redis storage-size differences. It uses client-side rendering only and does
  not inspect or contact a Kubernetes cluster.
- `repo/prepare-lockstep-release.sh` - Release-manager preflight for the
  lockstep source release. It validates the sibling repository set, prints the
  commit SHAs for the coordinated source state, verifies the
  `service-common` version contract, checks remote tag availability, and can
  prompt before delegating to `repo/tag-lockstep-release.sh`.
- `repo/prepare-service-release.sh` - Release-manager preflight for one
  runtime artifact. It validates only the selected artifact's source
  repository, prints the source commit, expected image tag, workflow page, and
  Java `serviceCommon` version when applicable, and can prompt before
  delegating to `repo/tag-release.sh --repo <repo>`.
- `repo/tag-release.sh` - Normal single-repository release tag helper. It
  requires `--repo`, validates only that repository, and accepts any repo in
  `LOCKSTEP_RELEASE_REPOS`.
- `repo/tag-lockstep-release.sh` - Explicit helper for rare coordinated
  all-repo tags across the `LOCKSTEP_RELEASE_REPOS` set. Use
  `--repo-set runtime-images --current-state --plan-only` to preview which
  runtime image repos need the requested tag based on the current local HEADs,
  then rerun without `--plan-only` to tag only the missing repos and skip tags
  already pointing at current HEAD.
- `repo/generate-unified-api-docs.sh` - Regenerates the checked-in unified
  OpenAPI artifacts used by `/api-docs`; its opt-in
  `--session-gateway-only OUTPUT_YAML` mode writes one filtered Session Gateway
  YAML snapshot without changing unified or frontend outputs.
- `repo/compare-test-coverage.py` - Compares committed coverage on every
  non-main core sibling repository with its local `origin/main` ref without
  switching branches or changing a working tree.
Choose scripts by runtime boundary:

- `bootstrap/` changes or checks the host and cluster prerequisites.
- `guardrails/` stays non-mutating; the production-reference verifier uses
  client-side `kubectl kustomize` rendering and does not contact a cluster.
- `smoketest/` assumes a live `kubectl` context and a running local stack.
- `ops/` is for interactive local maintenance.
- `loadtest/` manages synthetic local fixtures.
- `repo/` coordinates cross-repo maintenance tasks.
- `security/` prepares repeatable scanner inputs without applying resources or
  contacting a Kubernetes API.

## Bootstrap

- `bootstrap/install-verified-tool.sh` installs repo-pinned `kubectl`, Helm,
  Tilt, `mkcert`, Kind, `kubeconform`, `kube-linter`, `kyverno`, and `yq`
  releases from checked-in upstream URLs after verifying each downloaded
  artifact against its checked-in SHA-256 value. Installing a pin converges a
  recognized existing destination binary to that pin, upgrading or
  downgrading it, and prints `Replacing <tool> <old> with pinned <new> at
  <destination>` first. Symlinked, non-regular or unidentifiable destinations
  are rejected before download. The default `/usr/local/bin` destination is
  written with sudo; it, every ancestor and any existing destination must be
  root-owned, non-symlinked and non-writable by group/other, rechecked before
  the final write. A custom `--install-dir` is written without sudo: missing
  directories are created with `mkdir -p` under the caller's umask (for
  example mode 775 cache directories under umask `0002`), symlinked ancestors
  are allowed, and normal filesystem permissions govern the write. The
  installer does not inspect other copies of the tool on `PATH`; `setup.sh`
  runs `hash -r` and then reports the installed destination, resolved
  executable, expected version and detected version when `PATH` selects a
  different version. Every tool follows one download and checksum path;
  explicit per-tool metadata in `lib/pinned-tool-versions.sh` selects either a
  raw binary copy or stdout extraction of one named archive member, and a tool
  without that metadata fails rather than defaulting to a raw copy. An archive
  must contain exactly one regular-file entry for that member, so duplicate
  entries cannot be concatenated into the installed binary; other archive
  entries are never extracted and are not inspected. Version probing for both
  scripts also lives in `lib/pinned-tool-versions.sh`; destination checks live
  in `lib/verified-tool-destination.sh`.
- `bootstrap/verify-platform-tool-releases.sh` downloads the pinned `kubectl`,
  Helm, Tilt, and Kind inputs for Linux amd64 and arm64, verifies all eight
  checked-in checksums, and applies the installer's Helm/Tilt archive-member
  check without installing or executing downloaded binaries. It is the
  release-input gate for the four pins and runs in the separate
  `verify-platform-tool-releases.yml` workflow only for changes to
  `lib/pinned-tool-versions.sh`, `bootstrap/install-verified-tool.sh`, this
  script or that workflow, plus manual dispatch.
- `bootstrap/check-tilt-prerequisites.sh` validates local tools, pinned binary
  versions (including exact Helm, not a supported range), the host-published
  public ingress CA, DNS, Docker/Kind
  prerequisites, inotify budgets, pinned Gateway API and Calico state, and
  optional runtime security state. It reports drift and install commands
  without performing interactive cluster changes. Tool, repository and file
  checks run before a cluster exists; an absent cluster is a warning, and
  cluster-specific checks run only after the Docker/Kind-provider guard and
  exact `kind-kind` target pass.
- `bootstrap/check-local-runtime.sh` requires Kind's Docker provider
  (`KIND_EXPERIMENTAL_PROVIDER` unset or `docker`) and a Docker CLI that selects
  a reachable local Unix-socket daemon, then enforces the exact Ready loopback
  `kind-kind` target. It is the read-only daily-start preflight and accepts no
  mode flags.
- `../tests/platform-tools/test-platform-tool-safeguards.sh` provides offline
  fixtures with stubbed downloads and executables: exact Helm probing
  (including failed probes), custom installs under the current umask and
  `0002`, nested missing and symlinked-ancestor directories, replacement of
  newer and older recognized versions, destination symlink, non-regular and
  unidentifiable rejection, checksum mismatch, successful archive-member
  extraction, duplicated and missing archive members, refusal to stage a tool
  without artifact metadata, privileged ownership/mode/symlink rejection on
  disposable paths, and setup's final `PATH` check. It needs no host platform
  binary, sudo or privileged write. Two checks are not behavioral: a metadata
  check that every tool declares an artifact kind and complete checksums, and
  a wiring check that greps that setup and the prerequisite checker call the
  shared probe. The offline `test-setup.yml` workflow runs these fixtures
  without downloading releases.
- `bootstrap/install-imported-ingress-tls.sh` validates the three approved
  host-created ingress files without invoking mkcert, including one
  hostname-aware chain verification for `app.budgetanalyzer.localhost`.
  Install mode applies the TLS Secret only after exact context,
  referenced-cluster, strict loopback HTTPS authority, absent kubeconfig proxy
  override, Kind-cluster and control-plane-node checks pass. Orchestration does
  not install client trust. The `ingress-tls-secret` Tilt resource reconciles
  only the existing files and Secret; it never generates certificates or
  changes browser-machine or Kind-machine trust.
- `bootstrap/setup-k8s-tls.sh` and
  `bootstrap/renew-host-ingress-tls.sh` are human-operated browser-machine
  preparation paths. They create or retain that machine's mkcert CA, establish
  its browser trust, create and validate a leaf/key, publish only the public root,
  and never contact or recreate Kubernetes.
- `bootstrap/check-infra-tls-secrets.sh` is the focused read-only post-check
  used by `setup.sh` and Tilt. Tilt reruns the local
  `bootstrap/setup-infra-tls.sh` before PostgreSQL, Redis, and RabbitMQ start
  so namespace recreation cannot leave the infrastructure TLS secrets missing.
- `bootstrap/reconcile-kind-inotify-budget.sh` raises low Kind node inotify
  values used by Kubernetes log-follow streams. Tilt runs it as
  `kind-node-inotify-budget` on every `tilt up` before workload resources
  start.
- `bootstrap/install-calico.sh` installs or reconciles pinned Calico CNI for
  Kind clusters created with `disableDefaultCNI`. It also uses the inotify
  reconciliation helper. A live `docker exec kind-control-plane sysctl ...`
  recovery command is diagnostic only; use the helper or Tilt resource for the
  durable local fix.
- `bootstrap/setup-infra-tls.sh` is the local internal infrastructure
  certificate producer used by setup and its Tilt resource. It is separate
  from browser trust; agents must not invoke certificate writers directly.
  Browser-facing certificate preparation remains a browser-machine human
  action; it publishes the three ignored transfer files under `nginx/certs/k8s/` and
  never requires a host Kind cluster. No CA private key is published.

Use `../setup.sh` on the local Kind machine after it has the three approved
ingress TLS files and a reachable local Docker Unix socket. Use
`bootstrap/install-verified-tool.sh` for a single pinned binary, and use
`bootstrap/check-tilt-prerequisites.sh` as a diagnostic before or after setup;
its live security proof creates and cleans named disposable probe resources.
For normal daily startup, run `bootstrap/check-local-runtime.sh` and then
`tilt up`; never rerun `setup.sh` as a daily start command. Browser-machine
client trust is environment-owned and required for browser use, but
Kind-machine system-bundle trust does not gate `setup.sh`; see the
getting-started guide.

## Guardrails

- `guardrails/check-image-pinning.sh` verifies the image-pinning
  contract using `lib/image-pinning-targets.txt` and
  `lib/allowed-latest-image-refs.txt`.
- `guardrails/check-secrets-only-handling.sh` verifies the local Tilt-generated
  secret payload inventory in `lib/secrets-only-expected-keys.txt`.
- `guardrails/check-tilt-resource-roots.sh` evaluates the Tiltfile and verifies
  that resources without `resource_deps` match
  `lib/tilt-intentional-root-resources.txt`. It requires the standard
  side-by-side checkout under a common parent because Tiltfile evaluation references
  sibling service repositories. It also requires the ingress TLS resource to
  use the non-generating installer and rejects any Tilt command that invokes
  the host-only certificate generator. The startup graph must reconcile
  Kyverno immediately after the Kind preflight and hold every Kubernetes
  platform branch behind the `kyverno-ready` admission-readiness gate;
  non-Kubernetes `service-common` publication may run in parallel.
- `guardrails/verify-static-security-manifests.sh` runs kubeconform,
  kube-linter, Kyverno fixtures, generated local Tilt-tag admission replay, a
  rendered production Kyverno Helm check that rejects mutable controller/hook
  image refs, image pinning, secrets-only checks, namespace PSA checks, and
  active setup guidance scans. It also rejects Jaeger/Kiali public-entry drift
  in checked-in manifests and keeps the Kiali auth contract plus the Jaeger
  internal-only storage/service contract pinned in static review. Its
  kubeconform pass validates checked-in Kubernetes resource manifests, skips
  Kustomize patch fragments under `patches/` directories and the schema-v2
  production desired-state manifest as a standalone Kubernetes resource, and
  validates the rendered production app and infrastructure overlays that
  consume the Kubernetes inputs.
- `guardrails/verify-production-image-overlay.sh` renders
  `kubernetes/production/apps`, `kubernetes/production/infrastructure`, and the
  reviewed production route/authorization/ingress/monitoring/egress output,
  compares shared routes, gateway pod settings, authorization policies, and
  stateful infrastructure with their narrow declared differences, verifies
  the digest-pinned GHCR image inventory, rejects local `:latest` /
  `:tilt-` image paths, localhost hosts, placeholder Auth0 hosts, and
  `imagePullPolicy: Never`, rejects rendered observability Ingress/HTTPRoute/
  Gateway exposure for Grafana, Prometheus, Jaeger, and Kiali, asserts that the
  offline Kiali render contains namespace-scoped RBAC for every approved
  discovery namespace, verifies the Redis StatefulSet uses a `5Gi`
  `redis-data` claim template, and applies the production image Kyverno policy
  to the rendered app overlay.

## Security evidence

- `security/render-image-scan-inputs.sh` renders the production app and
  infrastructure Kustomize overlays plus the selected Istio, External Secrets,
  cert-manager, Kyverno, kube-prometheus-stack, and Kiali charts. It uses the
  checked-in values and observability post-renderers, copies the standalone
  Jaeger and Kind inputs, and extracts the Tilt Temurin and frontend smoke base
  refs. The helper is offline with respect to Kubernetes: Helm repository and
  container-registry network access are still required. The main-push,
  weekly, and manual exact-image evidence workflow owns YAML extraction,
  immutable platform resolution, Trivy scanning, summaries, and short-lived
  artifacts. The workflow uploads its declared evidence paths as one seven-day
  artifact; the shared evidence policy lives in
  `../docs/dependency-automation.md`.

Run the offline production-reference verifier when changing maintained
production overlays, render inputs, image metadata, or policies:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

CI should keep calling the fully static guardrail directly:

```bash
./scripts/guardrails/verify-static-security-manifests.sh
./scripts/guardrails/verify-static-security-manifests.sh --self-test
```

## Smoketest

`smoketest/smoketest.sh` is a thin dispatcher for live local validation. It runs:

1. `guardrails/verify-static-security-manifests.sh`
2. `smoketest/verify-security-prereqs.sh`
3. `smoketest/verify-clean-tilt-deployment-admission.sh`
4. `smoketest/verify-monitoring-rendered-manifests.sh`
5. `smoketest/verify-istio-tracing-config.sh`
6. `smoketest/verify-monitoring-runtime.sh`
7. `smoketest/verify-observability-port-forward-access.sh`
8. `smoketest/verify-session-architecture.sh`
9. `smoketest/verify-security-guardrails.sh`

Use targeted verifiers when debugging one capability, and the umbrella when
proving the current cluster:

```bash
./scripts/smoketest/smoketest.sh
./scripts/smoketest/verify-istio-tracing-config.sh
./scripts/smoketest/verify-observability-port-forward-access.sh
./scripts/smoketest/verify-edge-browser-hardening.sh
./scripts/smoketest/verify-security-guardrails.sh
```

`smoketest/verify-monitoring-runtime.sh` is the runtime observability proof for
the current cluster. It keeps the existing Spring Boot dashboard-input checks
and now also verifies the service-DNS-backed `istiod`, Grafana, Prometheus
Operator, and kube-state-metrics scrapes. It verifies kube-state-metrics from
the exact pod image and CRI-reported container image ID (which may identify
either the pinned multi-platform index or the selected platform child), then
checks the binary-reported version and architecture through
`kube_state_metrics_build_info` on a temporary VM-loopback port-forward to the
otherwise unexposed telemetry port. It also keeps the Kiali
`monitoring/prometheus` health regression and the live Jaeger integration
contract (`16685` gRPC queries, `16686` HTTP health check, no repeated Jaeger
version-check failures in the current Kiali pod logs).
`smoketest/verify-prometheus-operator-least-privilege.sh` is the focused
least-privilege proof for the Prometheus Operator. It keeps a checked
permission matrix under `tmp/prometheus-operator-least-privilege/`, requires
the representative denials in `default`, `infrastructure`, and `istio-system`,
and persists `triage-kiali-findings.sh --output-dir` artifacts under
`tmp/kiali-triage/`. Its render-time dependency,
`smoketest/verify-monitoring-rendered-manifests.sh`, fails fast on
namespace-scope drift and RBAC broadening.

All live verifiers execute against the current `kubectl` context. If a verifier
reports missing pods, secrets, or policies while Tilt appears healthy, confirm
the active context and Tilt resource state from the same host shell first.

## Ops

- `ops/render-istio-egress-config.sh` renders or applies the Auth0/FRED Istio
  egress manifests from `.env`.
- `ops/start-observability-port-forwards.sh` is the repo-owned convenience
  entry point for persistent local Grafana, Prometheus, Jaeger, and Kiali
  access. It keeps the forwards bound to `127.0.0.1` and tears them down on
  `Ctrl+C`. The focused smoke verifier remains the clean-shell proof path and
  coexists with that helper by reusing the expected canonical listeners
  when they are already running. Use explicit `--grafana-port`,
  `--prometheus-port`, `--jaeger-port`, and `--kiali-port` overrides only
  when some other intentional listener already owns one of those ports. If the
  helper reports a conflicting `code` listener on a canonical observability
  port, that is host-side VS Code port forwarding, not a repo-owned Tilt
  forward.
- `ops/triage-kiali-findings.sh` is the first-pass Kiali investigation helper.
  It reuses an existing loopback Kiali listener when one is already up, starts
  a temporary loopback-only Kiali port-forward when needed, authenticates with
  a short-lived `kubectl create token kiali` token, and prints a human-readable
  triage summary. It also compares the current Kiali findings against the
  expected app deployments in `default`, so it can say explicitly when cluster
  startup is the blocker and Kiali is just reporting missing runtime. Local
  Tilt defaults to the seven-workload topology. Use
  `--runtime-shape production` only when inspecting the six-workload reference
  topology where `nginx-gateway` serves the frontend bundle.
  It references [docs/runbooks/kiali-expected-warnings.md](../docs/runbooks/kiali-expected-warnings.md)
  for the warnings this repo intentionally ignores. Use `--output-dir <dir>`
  when you want the raw JSON and log artifacts for later review.
- `ops/show-pod-version-labels.sh` prints all pods by default and marks
  Budget Analyzer runtime pods with `WARN` when runtime id, artifact
  version, source ref, source commit, service-common version, or image
  annotation differs from the expected schema v2 manifest/inventory metadata.
  Use `--deployment-manifest <path>` for an explicit reviewed manifest,
  `--tracked-only` to hide third-party and infrastructure pods, and `--strict`
  to return non-zero on warnings. Use `--allow-mixed-deployment-id` only when a
  deliberately selective historical rollout should accept already-current
  pods from an earlier runtime id.
- `ops/capture-prometheus-operator-baseline.sh` is the repo-owned upstream
  comparison capture for the Prometheus Operator. It refreshes the chart
  render without the repo post-renderer, records the rendered operator RBAC
  plus a representative `kubectl auth can-i` matrix for
  `system:serviceaccount:monitoring:prometheus-stack-kube-prom-operator`, and
  rewrites `docs/research/prometheus-operator-rbac-baseline.md`. Run
  `smoketest/verify-monitoring-runtime.sh` separately after Tilt is up when
  you want the live runtime proof.
- `ops/post-render-prometheus-stack.sh` is the repo-owned RBAC reduction layer
  for `kube-prometheus-stack`. Local Tilt and production Helm installs both run
  through it so the Prometheus Operator loses cluster-wide `secrets`,
  `configmaps`, service mutation, and pod-delete authority outside
  `monitoring` while retaining the documented cluster-read exceptions for
  `namespaces`, `nodes`, `ingresses`, and `storageclasses`.
- `ops/grafana-ui-playwright-debug.sh` creates an ignored temporary Playwright
  runner under `tmp/grafana-ui-debug/`, expects an already-running Grafana
  port-forward at `http://127.0.0.1:3300` by default, logs into that
  port-forwarded Grafana URL, opens the provisioned dashboards, and captures
  browser-side debugging artifacts without committing Node dependency files.
- `ops/seed-ext-authz-session.sh` seeds a test ext-authz session in Redis using
  the TLS-only in-cluster listener.
- `ops/flush-redis.sh` and `ops/redis-browse.sh` inspect or clear local Redis.
- `ops/reset-databases.sh` resets local PostgreSQL databases.

## Loadtest Fixtures

Track 1 loadtest support is synthetic fixture data only. It creates local users,
sessions, and transactions for workflows like user deactivation and session
revocation without driving traffic.

```bash
./scripts/loadtest/seed-loadtest-users.sh --count 500 --admin-count 20 --session-ttl 86400
./scripts/loadtest/seed-loadtest-transactions.sh --per-user 200 --shape heavy-tail

# Later, when finished with the fixture set
./scripts/loadtest/teardown-loadtest.sh
```

`seed-loadtest-users.sh` writes `.loadtest/session-pool.txt`, which is
gitignored and reserved for future traffic-replay tooling. The shared
`lib/loadtest-common.sh` helper resolves that pool path from the orchestration
repo root, so callers can run the loadtest scripts from any current working
directory without writing outside the repository.

## Repo Management

- `repo/compare-test-coverage.py` discovers core sibling repositories that are
  currently on a branch other than `main` or `master`, requires their working
  trees to be clean, and builds temporary exports of `origin/main` and `HEAD`.
  It runs the repository-native JaCoCo, Vitest, or Go coverage command and
  prints line/statement and branch coverage comparisons. The script uses the
  existing local `origin/main` refs and never fetches or changes Git state.
  Run it without arguments:

  ```bash
  ./scripts/repo/compare-test-coverage.py
  ```

- `repo/validate-repos.sh` validates the sibling repository layout and branch
  state without changing branches or pulling.
- The tag helpers below push tags to each sibling repository's `origin`. Run
  them where `origin` is GitHub; in the optional development VM, `origin` is a
  guest-local bare repository, so tag pushes there do not trigger publish
  workflows. See
  [docs/ci-cd.md#where-to-run-tag-helpers](../docs/ci-cd.md#where-to-run-tag-helpers).
- `repo/prepare-lockstep-release.sh` is the release-manager source preflight
  for lockstep releases. Run it with `--release-version X.Y.Z` after
  `service-common` and Java consumers are pinned to the released
  `serviceCommon` version. It checks that configured sibling repos are on clean
  up-to-date `main`, verifies the requested remote tag is absent everywhere
  except the documented `service-common` skip case, prints the commit SHA map,
  and prints the GitHub Actions workflow pages to monitor. Pass `--tag` only
  when you want it to prompt before calling `repo/tag-lockstep-release.sh`.
  Pass `--tag-current-state` when the current local HEADs are the intended
  deployable state and the tagger should decide which repos still need the
  requested tag.
- `repo/tag-release.sh` creates a normal single-repository release tag. It
  requires `--repo`, validates only that repository, and accepts any repo in
  `LOCKSTEP_RELEASE_REPOS`. A tag produces a release artifact only in repos
  with a tag-triggered publish workflow; tagging repos such as
  `checkstyle-config` or `budget-analyzer-api-tests` only marks the source
  version. `RUNTIME_IMAGE_REPOS` and the production image inventory, not tag
  presence, define the runtime artifact set.
- `repo/tag-lockstep-release.sh` creates coordinated lockstep tags across the
  explicit `LOCKSTEP_RELEASE_REPOS` set by default. `--repo-set runtime-images`
  narrows the operation to the runtime image source repos. In the default
  strict mode, any existing non-`service-common` tag is a hard failure. With
  `--current-state`, the helper compares the requested
  tag to each selected repo's current local HEAD, creates and pushes only
  absent tags, pushes local-only tags that already point at current HEAD, skips
  tags already present at current HEAD, and fails if an existing tag points
  somewhere else. Use `--current-state --plan-only` for a non-mutating preview.
- `repo/release-service-common-snapshot.sh` coordinates the tag-driven
  `service-common` snapshot-to-release flow. Run `prepare` while
  `service-common` and all Java consumers are pinned to the same
  `MAJOR.MINOR.PATCH-SNAPSHOT`; it reads that version from
  `../service-common/build.gradle.kts`, verifies the Java consumers match
  exactly, strips `-SNAPSHOT` in
  `../service-common/build.gradle.kts` and runs the required Gradle validation.
  After that release-prep change is merged to `service-common` main, run
  `tag --push` to fast-forward main, assert local `main` matches `origin/main`,
  and push the derived `vMAJOR.MINOR.PATCH` from `service-common` only. The
  explicit `--push` flag is required for the release-triggering network write.
  This phase intentionally does not call `repo/tag-release.sh`, because the
  Java consumer repos also publish on tag pushes and still point at the
  snapshot dependency until `post` has run and those changes have been merged.
  Once `publish-release.yml` has completed for the service-common tag, run
  `post` to pin Java consumers to the released version. `post` leaves
  `service-common` on the released version; bump it back to the next snapshot
  manually when ready.
- `repo/update-service-common-version.sh` bumps the checked-in
  `service-common` version literal in `../service-common/build.gradle.kts` and
  the matching `serviceCommon` catalog entry in each Java consumer repo
  (`transaction-service`, `currency-service`, `permission-service`, and
  `session-gateway`). Use `--dry-run` before edits and `--validate-only` after
  edits or before release tagging.
- `repo/generate-unified-api-docs.sh` fetches live in-cluster OpenAPI specs,
  writes `docs-aggregator/openapi.json` and `docs-aggregator/openapi.yaml`, and
  copies the browser-facing API docs into `../budget-analyzer-web/docs/api/`
  when that sibling repo is present. Pass
  `--session-gateway-only OUTPUT_YAML` to fetch only Session Gateway, apply the
  same `/internal/*` path filter, and write exactly that YAML path without
  writing unified or sibling-repository files.

The repo-management scripts source `repo/repo-config.sh`, which derives the
orchestration root from `scripts/repo/` and then resolves sibling repos from
the common parent directory.

## Shared Lib

Shared shell helpers and inventories live in `lib/`. Scripts should source them
with a path relative to their own directory, for example:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../lib/pinned-tool-versions.sh"
```

## Adding Scripts

When adding a script, place it in the purpose-specific directory, include a
usage comment or `--help`, make it executable, and update this README in the
same change.
