# Plan: Kind And k3s Inotify Log Streaming

Date: 2026-05-11
Status: Draft

Related documents:

- `scripts/bootstrap/install-calico.sh`
- `scripts/bootstrap/check-tilt-prerequisites.sh`
- `docs/development/local-environment.md`
- `docs/tilt-kind-setup-guide.md`
- `deploy/scripts/01-install-k3s.sh`
- `docs/plans/oci-deployment-upgrade-lockstep-plan.md`

## Scope

This plan fixes Kubernetes log-follow failures like:

```text
failed to create fsnotify watcher: too many open files
```

The observed failure occurs when following logs with Tilt or `kubectl logs -f`.
Plain `kubectl logs` still works, and the affected workload can remain healthy.
The failure belongs to the Kubernetes node log-follow path and Linux inotify
limits, not to `transaction-service` application behavior.

## Decision

Raise the local Kind node inotify instance budget through
`scripts/bootstrap/install-calico.sh`, because that script already owns the
post-Kind node convergence step and already contains
`ensure_kind_node_inotify_budget`.

Use this local baseline:

```text
fs.inotify.max_user_instances >= 8192
fs.inotify.max_user_watches >= 524288
```

Keep the local change node-scoped and repeatable. Do not add service manifest
workarounds, pod security relaxations, or application environment overrides.

## Local Required Changes

### 1. Expand `install-calico.sh` Inotify Convergence

Update `scripts/bootstrap/install-calico.sh`:

- replace the current `MIN_INOTIFY_INSTANCES=1024` default with `8192`
- add a `MIN_INOTIFY_WATCHES=524288` default
- have `ensure_kind_node_inotify_budget` check and raise both:
  - `/proc/sys/fs/inotify/max_user_instances`
  - `/proc/sys/fs/inotify/max_user_watches`
- keep the existing `MIN_INOTIFY_INSTANCES` environment override
- add a matching `MIN_INOTIFY_WATCHES` override for local diagnostics
- keep the change idempotent, only writing values when the current node value is
  lower than the required minimum
- include node names and final values in the script output when a value changes

### 2. Add Preflight Visibility

Update `scripts/bootstrap/check-tilt-prerequisites.sh` so read-only preflight
reports the current inotify budget:

- check local host/container visible values:
  - `fs.inotify.max_user_instances`
  - `fs.inotify.max_user_watches`
- if a reachable Kind node exists, check those same values inside each Kind node
- warn when either value is below the local baseline
- tell the user to run `./scripts/bootstrap/install-calico.sh` when a Kind node
  needs reconciliation

Do not make preflight mutate the host or Kind node. Mutation stays in
`install-calico.sh` and `setup.sh`.

### 3. Update Local Documentation

Document the behavior in:

- `docs/development/local-environment.md`
- `docs/tilt-kind-setup-guide.md`
- `scripts/README.md`

The docs should say:

- `kubectl logs -f` and Tilt log streaming use Kubernetes follow mode, which can
  allocate fsnotify watchers on the Kubernetes node
- the repo converges Kind node inotify limits during Calico setup
- a one-off live `docker exec kind-control-plane sysctl ...` is diagnostic
  recovery only, not the durable fix

## Validation

Run after implementation:

```bash
bash -n scripts/bootstrap/install-calico.sh
shellcheck scripts/bootstrap/install-calico.sh
bash -n scripts/bootstrap/check-tilt-prerequisites.sh
shellcheck scripts/bootstrap/check-tilt-prerequisites.sh
./scripts/bootstrap/install-calico.sh
./scripts/bootstrap/check-tilt-prerequisites.sh
kubectl logs -f transaction-service-fd7c7d865-r8st7 --tail=1 --request-timeout=10s
```

Use the current transaction-service pod name from `kubectl get pods` rather than
hardcoding the example pod name.

## OCI Alignment

OCI production uses k3s with containerd, so it needs a matching host-level
inotify budget. The OCI steps live in
`docs/plans/oci-deployment-upgrade-lockstep-plan.md` because they affect the
production bootstrap path rather than local Kind.

The OCI fix should be implemented in the production deploy scripts, not in
application manifests.

