# Kyverno Policies

This directory holds the Phase 7 admission-policy baseline.

- `policies/` contains the ClusterPolicies Tilt applies to the local cluster.
- `tests/pass/` contains fixtures that must be admitted or intentionally skipped
  by documented system exceptions.
- `tests/fail/` contains fixtures that must be rejected.

Run the local policy fixtures with:

```bash
kyverno test kubernetes/kyverno/tests
```

The Phase 7 static gate wraps those fixtures together with schema validation,
`kube-linter`, and repo-specific guardrail scans:

```bash
./scripts/dev/verify-phase-7-static-manifests.sh
```

That static gate also generates a small Kyverno replay from
`scripts/dev/lib/phase-7-allowed-latest.txt` so representative approved local
Tilt `:tilt-<hash>` deploy refs are rechecked even if the checked-in fixtures
stop matching the live apply path.

Current exception boundaries are intentionally narrow:

- `istio-ingress` keeps service-account token automount enabled for the ingress
  gateway's mesh identity bootstrap.
- `istio-system`, `istio-ingress`, `istio-egress`, `kyverno`, `kube-system`,
  `kube-public`, `kube-node-lease`, and `local-path-storage` are excluded from
  the repo-owned workload baseline because those pods are chart-managed or
  cluster-managed rather than orchestration-managed.
- The third-party image-digest rule skips fully mutated sidecar-injected Pod
  objects by checking for `sidecar.istio.io/status`, because the autogen
  controller rules already enforce the repo-owned images at the Deployment /
  StatefulSet level while Istio adds chart-managed containers during mutation.
  The direct Pod rule still covers non-meshed temporary probes, and the rule
  also retains a narrow allow-path for injected Istio data-plane container
  names when the injector surfaces the current non-digest proxy image form.
- The local-image exception applies only to the seven approved Tilt-built repos
  and only for `:latest` checked into manifests or immutable
  `:tilt-<16 hex>` deploy tags for those same repos. The policy also accepts
  the equivalent `docker.io/library/...` local form, keeps
  `imagePullPolicy: Never` for checked-in `:latest` refs, and accepts the
  current Tilt-managed `IfNotPresent` rewrite for live `:tilt-<hash>` deploys.
- Namespace Pod Security labels remain required for all non-excluded
  namespaces, including temporary verifier namespaces.
