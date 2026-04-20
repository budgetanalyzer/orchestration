# Plan: Observability Local Access Alignment

**Status:** Proposed
**Date:** 2026-04-20
**Related:**
- `docs/plans/internal-observability-access-plan.md`
- `docs/plans/internal-observability-phase-7-jaeger-kiali-plan.md`

## Decision

Keep observability access explicit and loopback-bound.

`tilt up` should install and reconcile the observability components, but it
should not own persistent localhost tunnels for Grafana, Prometheus, Jaeger, or
Kiali. Persistent operator access should live in the normal `scripts/ops/`
surface, while the focused smoke verifier should work in both day-to-day modes:
it should start temporary port-forwards itself when none exist, and it should
reuse an already-running expected local forward instead of failing on the port
check.

This keeps the local workflow aligned with the documented production model:
internal-only observability reached through explicit `kubectl port-forward`
usage, not a special Tilt-only access path.

## Problems To Fix

1. `Tiltfile` currently reserves `127.0.0.1:16686` for Jaeger during normal
   `tilt up`, which collides with the default Jaeger port used by
   `scripts/smoketest/verify-observability-port-forward-access.sh`.
2. `Tiltfile` advertises `http://localhost:20001/kiali`, but the Kiali Tilt
   resource only installs the chart and does not create a tunnel, so that link
   is dead in a plain `tilt up` session.
3. `kubernetes/network-policies/monitoring-allow.yaml` does not currently allow
   Kiali to reach `istiod` on `15014` for the control-plane version endpoint,
   which leaves Kiali partially disconnected from Istio and reports an unknown
   version.
4. The repo's local observability access story is internally inconsistent:
   docs teach explicit loopback `kubectl port-forward`, Tilt partially
   auto-forwards Jaeger, and there is no repo-owned persistent tunnel helper.
   If a new helper script is added without adjusting the smoke verifier to
   reuse existing forwards and start missing ones, the same port-collision bug
   simply moves from Tilt to the new script.

## Scope

- `Tiltfile`
- `kubernetes/network-policies/monitoring-allow.yaml`
- `scripts/ops/`
- `scripts/smoketest/verify-observability-port-forward-access.sh`
- the nearest affected docs and script index entries

## Non-Goals

- No public observability routes, DNS, or ingress changes
- No Tilt-managed background `kubectl port-forward` `local_resource`
- No change to Kiali auth mode, RBAC posture, or `ClusterIP` exposure
- No weakening of the loopback-only `127.0.0.1` access requirement

## Implementation Plan

### 1. Align Tilt With Explicit Operator Access

- Remove the Jaeger `port_forward(16686, 16686)` from `Tiltfile`.
- Remove localhost links that only make sense when Tilt owns the tunnel.
  After Jaeger's auto-forward is removed, both the Jaeger and Kiali localhost
  Tilt links should be removed or replaced with non-misleading guidance.
- Keep the Jaeger and Kiali Tilt resources focused on deployment and rollout,
  not workstation tunnel management.

### 2. Add A Repo-Owned Operator Tunnel Helper

- Add `scripts/ops/start-observability-port-forwards.sh`.
- Default it to the canonical local ports already used in docs and smoke:
  `3300`, `9090`, `16686`, and `20001`.
- Run the forwards as a foreground supervisor that:
  - binds only to `127.0.0.1`
  - starts all four forwards by default
  - supports port overrides and targeted component selection
  - traps `EXIT`/`INT`/`TERM` and cleans up child `kubectl port-forward`
    processes
  - prints the local URLs plus the existing Kiali token and Grafana password
    retrieval commands
- Keep the first version simple. Do not add detached daemon mode, PID files, or
  Tilt integration unless later work proves it necessary.

### 3. Make The Smoke Verifier Coexist With Persistent Operator Tunnels

- Update `scripts/smoketest/verify-observability-port-forward-access.sh` so the
  canonical operator workflow remains usable after the new ops helper lands.
- Keep the verifier as the default self-sufficient proof for day-to-day use:
  when an expected local observability forward is not already present, it
  should start its own temporary loopback-bound port-forward and clean it up on
  exit.
- When one of the expected local ports is already occupied by the expected
  observability forward, the verifier should skip creating a duplicate forward
  and validate through the existing listener instead of failing immediately on
  the bind check.
- Keep the explicit `--grafana-port`, `--prometheus-port`, `--jaeger-port`, and
  `--kiali-port` overrides as the fallback for workstations that already use the
  canonical ports for something else.
- Preserve the current loopback-only requirement and the authentication checks
  for Grafana and Kiali.

### 4. Restore Kiali's Istiod Version Reachability

- Add a narrow Kiali egress allow rule in
  `kubernetes/network-policies/monitoring-allow.yaml` for:
  - source pods labeled `app.kubernetes.io/name: kiali`
  - destination namespace `istio-system`
  - destination pods labeled `app: istiod`
  - TCP port `15014`
- Keep the rule scoped to the version/monitoring endpoint only; do not broaden
  Kiali egress more than required.

### 5. Update Documentation In The Same Change

Update the nearest docs so the workflow is described once and described
correctly:

- `README.md`
- `scripts/README.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/architecture/observability.md`
- `AGENTS.md` only if the operator entry-point text needs to mention the new
  helper explicitly

Required doc outcomes:

- Tilt is documented as deploying observability, not opening observability
  localhost tunnels.
- The new ops helper is documented as the convenience path for persistent local
  access.
- Raw `kubectl port-forward --address 127.0.0.1 ...` commands remain documented
  as the underlying supported access model.
- The smoke verifier behavior is documented for both a clean shell and a shell
  where the operator helper is already running.
- The default expectation is still that the smoke verifier can be run by itself
  without requiring the operator helper first.

## Validation Plan

### Static And Script Validation

Run after implementation:

```bash
bash -n scripts/ops/start-observability-port-forwards.sh
bash -n scripts/smoketest/verify-observability-port-forward-access.sh
shellcheck scripts/ops/start-observability-port-forwards.sh
shellcheck scripts/smoketest/verify-observability-port-forward-access.sh
tilt alpha tiltfile-result --file Tiltfile
kubectl apply --dry-run=server -f kubernetes/network-policies/monitoring-allow.yaml
```

### Runtime Validation

Use the live local cluster to prove the workflow:

```bash
./scripts/ops/start-observability-port-forwards.sh
./scripts/smoketest/verify-observability-port-forward-access.sh
kubectl rollout status deployment/kiali -n monitoring --timeout=120s
kubectl logs -n monitoring deployment/kiali --since=5m
```

Manual and semi-manual checks to complete:

- `tilt up` no longer reserves `16686` for Jaeger by default.
- Tilt no longer shows dead localhost links for Jaeger or Kiali.
- The new ops helper exposes Grafana, Prometheus, Jaeger, and Kiali on the
  canonical loopback ports and cleans them up on `Ctrl+C`.
- The observability smoke verifier passes both from a clean shell and while the
  ops helper is already holding the canonical ports.
- Kiali no longer emits repeated `Unable to get version info for controlplane`
  errors after rollout, and the UI reports a concrete Istio version.

## Acceptance Criteria

- Standard `tilt up` no longer collides with the observability smoke on Jaeger.
- There is no misleading Kiali localhost link in Tilt.
- Kiali regains access to Istiod's version endpoint under the monitoring
  namespace deny-all posture.
- Operators have a repo-owned persistent observability tunnel helper in
  `scripts/ops/`.
- The smoke verifier and the persistent operator helper can coexist without
  reintroducing the same local port conflict under a different wrapper.
- The smoke verifier remains self-sufficient for normal use: if a required
  forward is missing it creates one, and if the expected forward already exists
  it reuses it.
- Docs, scripts, and Tilt all describe the same observability access model.
