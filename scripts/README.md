# Scripts Directory

This directory contains automation for the Budget Analyzer orchestration
repository. Scripts are grouped by purpose so setup, validation, operational,
loadtest, and repository-management tasks have stable entry points.

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

- `../setup.sh` - Standard local platform bootstrap from the repository root.
- `bootstrap/check-tilt-prerequisites.sh` - Tooling and environment preflight.
- `smoketest/smoketest.sh` - Aggregate local validation sequence for a live
  Tilt cluster.
- `smoketest/verify-observability-port-forward-access.sh` - Focused
  loopback-only Grafana, Prometheus, Jaeger, and Kiali port-forward verifier.
  It defaults to the canonical `3300`, `9090`, `16686`, and `20001` local
  ports, starts any missing temporary forwards itself, reuses the expected
  existing loopback `kubectl port-forward` listeners on those canonical ports,
  and accepts flag overrides when some other intentional listener already
  owns one of them. It verifies Grafana health,
  Prometheus readiness, Jaeger query API access, Kiali UI shell access, and
  that unauthenticated Grafana and Kiali API access is rejected. Use the same
  loopback-only access model in local Tilt and production OCI/k3s for the
  observability components installed there, and do not use `--address 0.0.0.0`
  for observability access.
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
  gaps, and likely low-signal waypoint warnings. Use
  `--runtime-shape production` on OCI so the helper expects the production
  frontend topology (`nginx-gateway` serves the bundle; no standalone
  `budget-analyzer-web` Deployment).
- `ops/start-observability-ssh-tunnels.sh` - Workstation-side foreground SSH
  tunnel helper for production OCI/k3s observability access. It takes the OCI
  host as an optional argument or reads `OCI_INSTANCE_IP`, assumes `ubuntu`
  plus `~/.ssh/oci-budgetanalyzer`, opens loopback-only tunnels for the
  canonical Grafana, Prometheus, Jaeger, and Kiali ports, and expects the
  matching `ops/start-observability-port-forwards.sh` process to already be
  running on the OCI host.
- `ops/capture-prometheus-operator-phase-1-baseline.sh` - Renders the current
  Prometheus stack, extracts the operator RBAC objects, builds a representative
  `kubectl auth can-i` matrix for the operator service account, and refreshes
  the checked-in Phase 1 least-privilege baseline note under
  `docs/research/`.
- `ops/post-render-prometheus-stack.sh` - Helm post-renderer for the
  Prometheus stack that replaces the upstream broad Prometheus Operator
  ClusterRole/ClusterRoleBinding with the repo-owned least-privilege split:
  one narrow cluster-read binding plus namespaced monitoring/default roles.
- `smoketest/verify-istio-tracing-config.sh` - Focused live-cluster verifier
  for the Jaeger OpenTelemetry extension provider and mesh-default Istio
  Telemetry resource.
- `smoketest/verify-monitoring-rendered-manifests.sh` - Renders the
  Prometheus stack and Kiali chart, then checks image pinning, service exposure,
  Kiali auth/RBAC posture, Prometheus Operator namespace-scope flags and
  reduced RBAC shape, and server dry-run compliance for rendered workload
  objects.
- `smoketest/verify-prometheus-operator-least-privilege.sh` - Full live
  Phase 4 verifier for the Prometheus Operator least-privilege plan. It reruns
  the rendered-manifest proof, checks the live operator RBAC object set,
  enforces the required positive and negative `kubectl auth can-i` matrix,
  reruns the monitoring runtime proof, and captures Kiali triage artifacts
  under `tmp/`.
- `guardrails/verify-phase-7-static-manifests.sh` - Static manifest and
  security guardrail gate used by CI and local preflight.
- `guardrails/verify-production-image-overlay.sh` - Static verifier for the
  full Oracle production baseline: app overlay, production
  infrastructure overlay, production render output, and the production image
  Kyverno policy. It is non-mutating, but it requires a live
  `kubectl` context so the Kiali production render can use a Helm server-side
  dry run and capture the full namespace-scoped RBAC footprint.
- `repo/generate-unified-api-docs.sh` - Regenerates the checked-in unified
  OpenAPI artifacts used by `/api-docs`.

Choose scripts by runtime boundary:

- `bootstrap/` changes or checks the host and cluster prerequisites.
- `guardrails/` stays non-mutating; most scripts are CI-safe, while
  `verify-production-image-overlay.sh` also expects a live `kubectl` context.
- `smoketest/` assumes a live `kubectl` context and a running local stack.
- `ops/` is for interactive local maintenance.
- `loadtest/` manages synthetic local fixtures.
- `repo/` coordinates cross-repo maintenance tasks.

## Bootstrap

- `bootstrap/install-verified-tool.sh` installs repo-pinned `kubectl`, Helm,
  Tilt, `mkcert`, `kubeconform`, `kube-linter`, and `kyverno` releases after
  verifying checked-in SHA-256 values.
- `bootstrap/check-tilt-prerequisites.sh` validates local tools, certificates,
  DNS, Docker/Kind prerequisites, and optional runtime security state.
- `bootstrap/install-calico.sh` installs pinned Calico CNI for Kind clusters
  created with `disableDefaultCNI`.
- `bootstrap/setup-k8s-tls.sh` and `bootstrap/setup-infra-tls.sh` are host-only
  certificate bootstrap scripts. Do not run them from an AI container because
  the browser must trust the host mkcert CA.

## Guardrails

- `guardrails/check-phase-7-image-pinning.sh` verifies the image-pinning
  contract using `lib/phase-7-image-pinning-targets.txt` and
  `lib/phase-7-allowed-latest.txt`.
- `guardrails/check-secrets-only-handling.sh` verifies the local Tilt-generated
  secret payload inventory in `lib/secrets-only-expected-keys.txt`.
- `guardrails/verify-phase-7-static-manifests.sh` runs kubeconform,
  kube-linter, Kyverno fixtures, generated local Tilt-tag admission replay, a
  rendered production Kyverno Helm check that rejects mutable controller/hook
  image refs, image pinning, secrets-only checks, namespace PSA checks, and
  active setup guidance scans. It also rejects Jaeger/Kiali public-entry drift
  in checked-in manifests and keeps the Kiali auth contract plus the Jaeger
  internal-only storage/service contract pinned in static review. Its
  kubeconform pass validates checked-in Kubernetes resource manifests and skips
  Kustomize patch fragments under `patches/` directories.
- `guardrails/verify-production-image-overlay.sh` renders
  `kubernetes/production/apps`, `kubernetes/production/infrastructure`, and the
  reviewed production route/ingress/monitoring/egress output, verifies
  the `0.0.12` digest-pinned GHCR image inventory, rejects local `:latest` /
  `:tilt-` image paths, localhost hosts, placeholder Auth0 hosts, and
  `imagePullPolicy: Never`, rejects rendered observability Ingress/HTTPRoute/
  Gateway exposure for Grafana, Prometheus, Jaeger, and Kiali, uses a live
  Helm server-side dry run for the production Kiali render so namespace-scoped
  RBAC is fully reviewed, verifies the Redis StatefulSet uses a `5Gi`
  `redis-data` claim template, and applies the production image Kyverno policy
  to the rendered app overlay.

Use the live-cluster production verifier when a cluster is available:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

CI should keep calling the fully static guardrail directly:

```bash
./scripts/guardrails/verify-phase-7-static-manifests.sh
./scripts/guardrails/verify-phase-7-static-manifests.sh --self-test
```

## Smoketest

`smoketest/smoketest.sh` is a thin dispatcher for live local validation. It runs:

1. `guardrails/verify-phase-7-static-manifests.sh`
2. `smoketest/verify-security-prereqs.sh`
3. `smoketest/verify-clean-tilt-deployment-admission.sh`
4. `smoketest/verify-monitoring-rendered-manifests.sh`
5. `smoketest/verify-istio-tracing-config.sh`
6. `smoketest/verify-monitoring-runtime.sh`
7. `smoketest/verify-observability-port-forward-access.sh`
8. `smoketest/verify-session-architecture-phase-5.sh`
9. `smoketest/verify-phase-7-security-guardrails.sh`

Use targeted verifiers when debugging one capability, and the umbrella when
proving the current cluster:

```bash
./scripts/smoketest/smoketest.sh
./scripts/smoketest/verify-istio-tracing-config.sh
./scripts/smoketest/verify-observability-port-forward-access.sh
./scripts/smoketest/verify-phase-6-edge-browser-hardening.sh
./scripts/smoketest/verify-phase-7-security-guardrails.sh
```

`smoketest/verify-monitoring-runtime.sh` is the runtime observability proof for
the current cluster. It keeps the existing Spring Boot dashboard-input checks
and now also verifies the service-DNS-backed `istiod`, Grafana, Prometheus
Operator, and kube-state-metrics scrapes plus the Kiali
`monitoring/prometheus` health regression and the live Jaeger integration
contract (`16685` gRPC queries, `16686` HTTP health check, no repeated Jaeger
version-check failures in the current Kiali pod logs).
`smoketest/verify-prometheus-operator-least-privilege.sh` is the focused
Phase 4 least-privilege proof for the Prometheus Operator. It keeps a checked
permission matrix under `tmp/prometheus-operator-least-privilege/`, requires
the representative denials in `default`, `infrastructure`, and `istio-system`,
and persists `triage-kiali-findings.sh --output-dir` artifacts under
`tmp/kiali-triage/`.

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
  bring-up is the blocker and Kiali is just reporting missing runtime. Local
  Tilt defaults to the seven-workload topology; OCI production should use
  `--runtime-shape production` so the helper expects the six-workload topology
  where `nginx-gateway` serves the frontend bundle.
  It references [docs/runbooks/kiali-expected-warnings.md](../docs/runbooks/kiali-expected-warnings.md)
  for the warnings this repo intentionally ignores. Use `--output-dir <dir>`
  when you want the raw JSON and log artifacts for later review.
- `ops/start-observability-ssh-tunnels.sh` is the workstation-side companion
  for production OCI/k3s. First start the Kubernetes port-forwards on the OCI
  host, then from the workstation run
  `./scripts/ops/start-observability-ssh-tunnels.sh <oci-host>` or set
  `OCI_INSTANCE_IP` and run `./scripts/ops/start-observability-ssh-tunnels.sh`.
  The helper keeps one SSH session open with local loopback tunnels for
  `3300`, `9090`, `16686`, and `20001`, and fails fast if the remote loopback
  endpoints are not reachable.
- `ops/capture-prometheus-operator-phase-1-baseline.sh` is the repo-owned
  Phase 1 evidence capture for the Prometheus Operator least-privilege plan.
  It refreshes the chart render, records the rendered operator RBAC plus a
  representative `kubectl auth can-i` matrix for
  `system:serviceaccount:monitoring:prometheus-stack-kube-prom-operator`, and
  rewrites
  `docs/research/prometheus-operator-least-privilege-phase-1-baseline.md`.
  Run `smoketest/verify-monitoring-runtime.sh` separately after Tilt is up when
  you want the live runtime proof.
- `ops/post-render-prometheus-stack.sh` is the repo-owned Phase 3 reduction
  layer for `kube-prometheus-stack`. Local Tilt and production Helm installs
  both run through it so the Prometheus Operator loses cluster-wide `secrets`,
  `configmaps`, service mutation, and pod-delete authority outside
  `monitoring` while retaining the documented cluster-read exceptions for
  `namespaces`, `nodes`, `ingresses`, and `storageclasses`.
- `deploy/scripts/08-verify-network-policy-enforcement.sh` can run before
  production Auth0 config exists, but in that pre-Auth0 state the two positive
  `istio-egress-gateway:443` checks are deferred until the real egress routing
  is rendered and applied later in the production plan.
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

- `repo/validate-repos.sh` validates the sibling repository layout and branch
  state.
- `repo/checkout-main.sh` and `repo/checkout-tag.sh` help switch sibling repos.
- `repo/tag-release.sh` creates release tags across configured repositories.
- `repo/update-service-common-version.sh` bumps the checked-in
  `service-common` version literal in `../service-common/build.gradle.kts` and
  the matching `serviceCommon` catalog entry in each Java consumer repo.
- `repo/generate-unified-api-docs.sh` fetches live in-cluster OpenAPI specs,
  writes `docs-aggregator/openapi.json` and `docs-aggregator/openapi.yaml`, and
  copies the browser-facing API docs into `../budget-analyzer-web/docs/api/`
  when that sibling repo is present.
- `repo/github/add-repo-topics.sh` manages GitHub repository topics.

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
