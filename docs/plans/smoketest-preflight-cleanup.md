# Smoketest Preflight Residue Cleanup

**Status:** Ready to run manually. Not formatted for AI Session Handler.

Add a bounded, fail-closed cleanup step that runs first in `scripts/smoketest/smoketest.sh`. It
removes test resources left by earlier interrupted verifier runs, so leftovers cannot affect the
next run.

## Rules

- Work in this repository only. Follow `AGENTS.md`.
- No git write operations, no certificate operations, no staging or production access.
- Every cluster mutation goes through `assert_local_kind_target` from
  `scripts/lib/local-kubernetes-target.sh`. If the guard fails, mutate nothing and exit non-zero.
- Every changed shell script passes `bash -n` and `shellcheck`.
- Do not edit `docs/decisions/` or `docs/archive/`.
- Delete only resources that a verifier identifies as its own, by verifier-owned label or exact
  name pattern. Never select Tilt-managed or operator-owned resources.

## Start Here: Capture The Current Failure

After a manual cleanup, the user reran the smoketest and got errors along the lines of "unable
to create pod". That output was not captured, and a read-only check of the cluster did not
explain it:

- no ResourceQuota or LimitRange
- no admission denials or FailedCreate/FailedScheduling events
- Kyverno and istiod healthy
- node at 48% CPU and 23% memory requested, with no pressure

The only remaining residue found was namespace `ba-phase5-psa-1792397007`, created 2026-10-19 by
`verify-runtime-hardening.sh`. Its pod `secure-meshed-smoke` has restarted about 1,500 times.

Before implementing, rerun the smoketest and save the full output:

```bash
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/smoketest/smoketest.sh 2>&1 | tee /tmp/smoketest-$(date +%s).log
```

Find the first pod-creation error, the verifier that printed it, and the resource it names. If
the cause is not residue (for example an admission policy, an image pull or a PSA label change),
record it and fix it separately. This cleanup will not fix a non-residue failure, and must not
hide one.

## Background

Evidence from the session that produced this plan:

- After the RabbitMQ 4.4 upgrade, `verify-runtime-security-guardrails.sh` failed because
  `rabbitmqadmin` 2.x accepts only `--name`, not `name=...`. That fix is already applied.
- Killing the verifier tree with a process-group SIGTERM stopped the inner cleanup traps from
  running. A reproduction showed that each inner script gets SIGTERM twice: once directly and
  once forwarded by `timeout --foreground`. The second signal kills bash inside its EXIT trap.
  Ctrl-C and a single SIGTERM to `timeout` both cleaned up correctly.
- The resulting `np2-*` probe pods carry real workload labels (`app=nginx-gateway` and so on).
  They became Ready endpoints of the real Services and received about half of all live traffic.
- `tilt down` does not remove verifier residue, because the resources have no Tilt label or
  owner.
- Fixed-name residue is replaced only when its own verifier runs, late in step 9. Steps 2–8 run
  against a polluted cluster.
- Orphaned `kubectl port-forward` processes (PPID 1) from earlier runs persist indefinitely.

## Residue Inventory

Confirm each entry against the current scripts before coding; the scripts are the source of
truth.

| Verifier | Residue | Selector |
|---|---|---|
| `verify-network-policies.sh` | Pods and Services in `default`, `monitoring`, `istio-ingress`, `istio-egress` | Name prefix `np2-`. These have **no** verifier label today; see Step 2 |
| `verify-transport-encryption.sh` | Pods in `default`; NetworkPolicies in `default`, `infrastructure` | `verify-transport-encryption-temp=true` |
| `verify-runtime-security-guardrails.sh` | Pods in `default`; NetworkPolicies in `default`, `infrastructure`; RabbitMQ vhosts | `verify-runtime-security-guardrails-temp=true`; vhost name `runtime-guardrails-<digits>` |
| `verify-istio-ingress.sh` | Deployment, Service, NetworkPolicy, AuthorizationPolicy, HTTPRoute in `default`; NetworkPolicy in `istio-ingress`; probe pods such as `p3-mtls-probe` | `verify-istio-ingress-temp=true`; check whether its probe pods carry this label |
| `verify-ingress-rate-limits.sh` | Pod, NetworkPolicy, ConfigMap in `default`; ingress Deployment scaled to 2; one Redis session key | `verify-ingress-rate-limits-temp=true`; replica count, see Step 4 |
| `verify-security-prereqs.sh` | Namespaces `ba-netpol-*`, `ba-psa-*`, `ba-kyverno-*`; pod `default/istio-sidecar-smoke` | Namespace prefix plus exact pod name |
| `verify-runtime-hardening.sh` | Namespace `ba-phase5-psa-*` | Namespace prefix |
| `verify-edge-browser-hardening.sh` | `/tmp/edge-browser-prod-nginx.*` inside the `nginx-gateway` pod | Path pattern; harmless and gone on pod restart, so leave out unless trivial |
| `verify-credential-isolation.sh`, `verify-ingress-rate-limits.sh`, `verify-edge-browser-hardening.sh` | Orphaned `kubectl port-forward` processes on the VM | See Step 3 |
| `verify-edge-contract.sh --inject-failures` (not in the smoketest chain) | `ClusterNetworkPolicy edge-contract-block-ingress-to-ext-authz-<pid>`; ext-authz or Redis scaled to 0 | Name prefix; replicas are checked only, see Step 4 |

## Implementation

### Step 1: New script `scripts/smoketest/cleanup-smoketest-residue.sh`

- Standalone and idempotent. Exits 0 on a clean cluster.
- Source `scripts/lib/local-kubernetes-target.sh` and call `assert_local_kind_target` before any
  mutation.
- Hold the residue inventory in one place inside the script, as data (namespace, kind, selector
  or prefix), not as scattered commands.
- Print each category it removes and a count. Print nothing alarming on a no-op.
- Support `--dry-run`: list what would be removed and change nothing.

**Timeouts.** Every call must be bounded; no step may hang the smoketest.

- Add `--request-timeout=20s` to every `kubectl` call.
- Pods: `kubectl delete ... --grace-period=0 --force --wait=true --timeout=60s`. The probes are
  `sleep` containers, so a forced delete is safe. Waiting matters because the Services keep
  routing to Ready probes until those probes are gone.
- Services, NetworkPolicies, ConfigMaps, Deployments, AuthorizationPolicies, HTTPRoutes and
  ClusterNetworkPolicies: `--wait=true --timeout=60s`.
- Namespaces: `--wait=true --timeout=180s`. If a namespace is still `Terminating` after that,
  fail and report its remaining finalizers and contents. Do not remove finalizers automatically.
- RabbitMQ vhosts: run `kubectl exec ... rabbitmqadmin` with `--timeout 20` and
  `delete vhost --name <n> --idempotently`. List vhosts first and delete only exact
  `runtime-guardrails-<digits>` matches. Never touch `/`.
- Port-forwards: SIGTERM, wait up to 5 seconds, then SIGKILL the survivors.
- Wrap the whole script in an overall budget of 5 minutes, using `timeout` in `smoketest.sh`.
  Fail with a clear message if the budget runs out.

**Post-cleanup assertion.** Fail if it does not hold.

- Re-query every inventory selector and require zero matches.
- For every Service in `default`, `monitoring`, `istio-ingress` and `istio-egress`, require that
  each EndpointSlice target pod has an `ownerReferences` entry. This catches label-impersonating
  pods even when they are not in the inventory, which was the high-impact failure in this
  session.
- Require the ext-authz Deployment and Redis StatefulSet to have at least 1 ready replica.

### Step 2: Label the `np2-*` probes

In `verify-network-policies.sh`, add a verifier-owned label such as
`verify-network-policies-temp: "true"` to every Pod and Service it creates, in `create_probe`,
`create_injected_probe`, `create_listener` and `create_service`. The cleanup script selects by
that label.

Also keep the `np2-` name-prefix selector in the cleanup script, restricted to pods that have no
`ownerReferences`, so residue from runs before this change is still caught.

If the Step 1 inventory finds other verifiers whose pods carry no verifier label (for example
`verify-istio-ingress.sh` probe pods, or the `verify-security-prereqs.sh` pod in `default`),
label them the same way.

### Step 3: Port-forward cleanup, narrowly scoped

Kill a process only if it meets all of the following:

- owned by the current user
- PPID 1 (orphaned)
- its command line is `kubectl port-forward` with a random local port (`:<remote>`), matching
  one of the verifier signatures:
  - `infrastructure service/rabbitmq :15672`
  - `default deployment/ext-authz :8090` or `:9002`
  - `default deployment/nginx-gateway :8080`
  - `istio-ingress pod/<ingress-pod> :443`

Never kill a port-forward with a fixed local port or `--address 127.0.0.1`. Those belong to
operator guest publication (`scripts/ops/start-observability-port-forwards.sh`, see
`docs/architecture/observability.md#access`) or to a live verifier.

### Step 4: Mutated replica counts, checked and not guessed

- Ingress Deployment `istio-ingress/istio-ingress-gateway-istio`: find the repo source of truth
  for its intended replica count, from the Gateway infrastructure parameters or the manifests.
  If the live value differs and no `ingress-rate-limit-probe-*` pod exists, restore it, then wait
  on `kubectl rollout status --timeout=120s`. Do not hardcode `1` without citing where the value
  comes from.
- ext-authz and Redis at 0 replicas: report and fail. Do not scale them back up. The cause is
  most likely an interrupted `verify-edge-contract.sh --inject-failures` run, and the user should
  decide. The script may print the exact recovery command.
- Redis session keys left by `verify-ingress-rate-limits.sh`: out of scope. The key name is
  random per run and cannot be identified afterwards. Note this limitation in the script header.

### Step 5: Wire into `smoketest.sh`

Add as the first `run_step`, before the static guardrails:

```bash
run_step "Preflight residue cleanup" \
    timeout --kill-after=10s 5m "${SCRIPT_DIR}/cleanup-smoketest-residue.sh"
```

A cleanup failure stops the smoketest; `smoketest.sh` already runs under `set -e`. Update the
numbered list in the `usage()` text.

### Step 6: Documentation

- `scripts/README.md`: add the script to the smoketest catalog, update the `smoketest.sh` step
  list near line 545, and document standalone use and `--dry-run`.
- `docs/development/getting-started.md`, near line 127: if it lists smoketest steps, add the
  preflight step. If a run is interrupted, tell the user to run
  `./scripts/smoketest/cleanup-smoketest-residue.sh` and not `tilt down`.
- `docs/runbooks/tilt-debugging.md`: add a short entry: "a Service routes to unexpected pods /
  half of requests fail after an interrupted smoketest", pointing to the cleanup script.

## Out Of Scope (Record As Follow-ups)

These are real weaknesses, but separate from this change:

1. **Double-signal cleanup loss.** A group SIGTERM through `timeout --foreground` kills inner
   EXIT traps. A possible fix is for each verifier to ignore further TERM/INT at the start of its
   cleanup function (`trap '' TERM INT`).
2. **10-second cleanup budget on timeout.** `run_regression_verifier` and similar wrappers use
   `--kill-after=10s`. `verify-network-policies.sh` deletes about 35 resources sequentially, so a
   timed-out run can be killed mid-cleanup. Batch the deletes (one `kubectl delete` per
   namespace by label) and/or raise `--kill-after`.
3. **Nested timeouts orphan grandchildren.** When an outer `timeout` fires, it signals only its
   direct child. Inner verifiers and their port-forwards keep running with PPID 1, which is the
   likely source of the orphaned port-forwards found in this session.

## Validation

1. `bash -n` and `shellcheck` on every changed script.
2. Static gate:

   ```bash
   INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
     ./scripts/guardrails/verify-static-security-manifests.sh
   git diff --check
   ```

3. No-op on a clean cluster: `cleanup-smoketest-residue.sh --dry-run` lists nothing, and a real
   run exits 0 in a few seconds.
4. Reproduce residue, then clean it. Run `./scripts/smoketest/verify-network-policies.sh` in the
   background, wait until the `np2-*` pods are Ready, then send SIGTERM to its whole process
   group.
   - Confirm that the `np2-*` pods appear in the real Service EndpointSlices.
   - Run `--dry-run` and confirm it lists them.
   - Run the cleanup and confirm zero residue, and that every EndpointSlice target in `default`
     has an owner.
5. Guard check: with `KUBECONFIG` pointing at a copy whose context is renamed away from
   `kind-kind`, the script must refuse to mutate and exit non-zero.
6. Port-forward scoping: start an operator-style forward
   (`kubectl port-forward --address 127.0.0.1 -n monitoring svc/<grafana> 3300:80`) and an
   orphaned verifier-style forward. Confirm that only the verifier-style one is killed.
7. Full run:

   ```bash
   INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
     ./scripts/smoketest/smoketest.sh
   ```

   Record the result. If the "unable to create pod" failure from the start of this plan remains,
   this plan did not address it; report it separately.
