# Tilt/Kind Manual Deep Dive

**Status:** Manual reference
**Audience:** Contributors debugging or reproducing local bootstrap internals

This is not the supported default onboarding path.

Use [docs/development/getting-started.md](development/getting-started.md) for
the supported `./setup.sh` and `tilt up` workflow. Use this guide only when you
need to understand or reproduce the underlying development-VM bootstrap steps one by
one.

## When To Use This Guide

- debugging `./setup.sh`
- reproducing a specific bootstrap step manually
- learning how the Kind, Calico, DNS, and TLS pieces fit together
- validating the VM application environment without the full happy-path wrapper

For the live-update pipeline, mixed local-and-cluster workflows, and
troubleshooting after the stack is already up, use
[docs/development/local-environment.md](development/local-environment.md).

## Development VM Prerequisites

Run the repo preflight first:

```bash
./scripts/bootstrap/check-tilt-prerequisites.sh
```

For VM-local binary installs, prefer the verified installer:

```bash
./scripts/bootstrap/install-verified-tool.sh <kubectl|helm|tilt|kind|kubeconform|kube-linter|kyverno>
```

Current baseline:

- Docker `24.0+`
- Kind `0.31.0` (`./setup.sh` auto-installs this pinned version if missing or
  mismatched)
- `kubectl` `1.35.4` (`./setup.sh` auto-installs this pinned version if missing
  or mismatched)
- Helm `3.20.x`
- Tilt `0.37.3` (`./setup.sh` auto-installs this pinned version if Tilt is
  missing or mismatched)
- OpenSSL `3.x+`

Manual equivalents for repo-managed binaries:

```bash
./scripts/bootstrap/install-verified-tool.sh kubectl
./scripts/bootstrap/install-verified-tool.sh kind
./scripts/bootstrap/install-verified-tool.sh helm
./scripts/bootstrap/install-verified-tool.sh tilt
```

Keep the repos side by side under a common parent directory if you are working
outside the sibling `workspace` repo:

```text
parent-directory/
├── orchestration/
├── service-common/
├── transaction-service/
├── currency-service/
├── session-gateway/
├── permission-service/
└── budget-analyzer-web/
```

## Manual Bootstrap Sequence

### 1. Preflight

```bash
cd orchestration/
./scripts/bootstrap/check-tilt-prerequisites.sh
```

### 2. `service-common` Resolution

The supported local Tilt path is credential-free and publishes `service-common`
for you. Do not treat manual `publishToMavenLocal` as part of normal
onboarding.

Only publish manually when you are intentionally reproducing Gradle resolution
outside the normal Tilt flow or recovering from a local Maven cache problem:

```bash
cd ../service-common
./gradlew clean build publishToMavenLocal
```

See
[docs/development/service-common-artifact-resolution.md](development/service-common-artifact-resolution.md)
for the full local-vs-remote artifact contract.

### 3. Create The Kind Cluster

Use the checked-in Kind config so the cluster matches the repo baseline:

```bash
cd ../orchestration
kind create cluster --config kind-cluster-config.yaml
./scripts/bootstrap/install-calico.sh
```

That baseline does three important things:

- disables Kind's default CNI so `NetworkPolicy` can be enforced with Calico
- pins the Kind node image for reproducibility
- maps HTTPS traffic through the repo's ingress contract
- reconciles the Kind node inotify budget required by Kubernetes log-follow
  streams during bootstrap and on every `tilt up`

Useful checks:

```bash
kind get clusters
kubectl cluster-info --context kind-kind
docker inspect kind-control-plane --format '{{.Config.Image}}'
docker port kind-control-plane
kubectl get daemonset kindnet -n kube-system || true
kubectl get daemonset calico-node -n kube-system
```

Tilt log streaming and `kubectl logs -f` use Kubernetes follow mode, which can
allocate fsnotify watchers on the Kubernetes node. If follow mode fails with
`failed to create fsnotify watcher: too many open files`, plain
`kubectl logs` may still work and the workload may still be healthy. Tilt runs
the durable local fix as the `kind-node-inotify-budget` resource on every
`tilt up`; for a running session, trigger that resource or run:

```bash
./scripts/bootstrap/reconcile-kind-inotify-budget.sh
```

That script raises low Kind node values for both
`fs.inotify.max_user_instances` and `fs.inotify.max_user_watches`. A one-off
live command such as `docker exec kind-control-plane sysctl ...` is diagnostic
recovery only; do not treat it as a persistent setup step.

### 4. Configure Browser Access

The personal host owns the interactive browser, its loopback hostname mapping,
and the reviewed SSH forwarding path into VM port 443. Workspace owns those
host-boundary details; do not expose the VM ingress on a broad interface.

### 5. Transfer And Reconcile Browser TLS Material

The human runs the browser-facing certificate preparation in the personal-host
orchestration checkout, then transfers only the wildcard leaf, leaf key and
public CA into the VM checkout. There is no personal-host Kind cluster:

```bash
# Personal host only
./scripts/bootstrap/setup-k8s-tls.sh

# Development VM only, after the workspace-owned transfer and trust procedure
./scripts/bootstrap/install-imported-ingress-tls.sh
```

Agents must not run host-trust certificate generation; use the documented
human-operated personal-host workflow. Existing migrated files may be reused
when `install-imported-ingress-tls.sh --validate-only` accepts them.

### 6. Generate Internal Transport TLS Material

`./setup.sh` normally handles this for you. When reproducing the steps
manually, generate the internal TLS secrets in the development VM:

```bash
./scripts/bootstrap/setup-infra-tls.sh
```

### 7. Prepare `.env`

```bash
[ -f .env ] || cp .env.example .env
vim .env
```

Review the local infrastructure password defaults, then add the Auth0 domain,
client ID, client secret, and FRED API key.

### 8. Start Tilt

```bash
tilt up
```

### 9. Run Focused Verification

For the supported verifier order, go back to
[docs/development/getting-started.md](development/getting-started.md). For the
full script catalog, use [scripts/README.md](../scripts/README.md).

Common focused checks after manual bring-up:

```bash
./scripts/smoketest/verify-clean-tilt-deployment-admission.sh
./scripts/smoketest/verify-security-prereqs.sh
./scripts/smoketest/verify-security-guardrails.sh
```

## Manual Verification

Basic runtime checks:

```bash
kubectl get pods -n default
kubectl get pods -n infrastructure
kubectl get pods -n monitoring
```

Operator entry points:

- app: `https://app.budgetanalyzer.localhost`
- Tilt UI: `http://localhost:10350`
- unified API docs: `https://app.budgetanalyzer.localhost/api-docs`

Exact `/api-docs` behavior lives in
[docs-aggregator/README.md](../docs-aggregator/README.md). Exact observability
access commands live in
[docs/architecture/observability.md](architecture/observability.md).

## Troubleshooting

Start with [docs/runbooks/README.md](runbooks/README.md) for active runbooks.

### Preflight Fails

Rerun the checked preflight and fix the reported missing tool, DNS, or
certificate prerequisite instead of skipping it:

```bash
./scripts/bootstrap/check-tilt-prerequisites.sh
```

### Kind Cluster Issues

If the cluster shape drifted, rebuild it from the checked-in config:

```bash
kind delete cluster --name kind
kind create cluster --config kind-cluster-config.yaml
./scripts/bootstrap/install-calico.sh
```

### TLS Failures

Repair only the affected TLS material in its owning environment:

```bash
# Personal host: browser-facing files; then repeat transfer and reconciliation
./scripts/bootstrap/setup-k8s-tls.sh

# Development VM: internal application transport
./scripts/bootstrap/setup-infra-tls.sh
```

### `service-common` Resolution Failures

If a local Java build cannot resolve `org.budgetanalyzer` artifacts while you
are deliberately bypassing the normal Tilt publication step, republish
`service-common` locally:

```bash
cd ../service-common
./gradlew clean build publishToMavenLocal
```

## Cleanup

```bash
tilt down
kind delete cluster --name kind
```
