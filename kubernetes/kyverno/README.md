# Kyverno Policies

This directory holds the Phase 7 admission-policy baseline.

- `policies/*.yaml` contains the ClusterPolicies Tilt applies to the local cluster.
- `policies/production/` contains production-only policy variants. The Phase 3
  image overlay verifier applies `production/50-require-third-party-image-digests.yaml`
  against the rendered production app overlay to prove the production image path
  has no local Tilt image exceptions.
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
./scripts/guardrails/verify-phase-7-static-manifests.sh
```

That script stays under `scripts/guardrails/` because it is CI-safe. The
live-cluster runtime proof stays separate under
`./scripts/smoketest/verify-phase-7-security-guardrails.sh`.

That static gate also generates a small Kyverno replay from
`scripts/lib/phase-7-allowed-latest.txt` so representative approved local
Tilt `:tilt-<hash>` deploy refs are rechecked even if the checked-in fixtures
stop matching the live apply path.

## Production Path

The OCI production path does not reuse the full local `policies/*.yaml`
directory verbatim. It keeps the shared `00` through `40` policies, but swaps
the local image-admission rule for the production-only variant under
`policies/production/`.

Use the checked-in operator surface for that path:

- `deploy/helm-values/kyverno.values.yaml` pins the production controller
  replica counts, runtime-hardening values, and immutable digests for every
  rendered Kyverno controller and hook image.
- `deploy/scripts/14-install-phase-7-kyverno.sh` installs the pinned chart
  version into the `kyverno` namespace with those reviewed values.
- `deploy/scripts/15-apply-phase-7-policies.sh` runs
  `./scripts/guardrails/verify-production-image-overlay.sh` first, then applies:
  - `policies/00-smoke-disallow-privileged.yaml`
  - `policies/10-require-namespace-pod-security-labels.yaml`
  - `policies/20-require-workload-automount-disabled.yaml`
  - `policies/30-require-workload-security-context.yaml`
  - `policies/40-disallow-obvious-default-credentials.yaml`
  - `policies/production/50-require-third-party-image-digests.yaml`
  It then checks the live `phase7-require-third-party-image-digests` resource
  for the production-only rule name and fails if the local Tilt/latest
  exception rules are still present.

The production apply path intentionally does not apply
`policies/50-require-third-party-image-digests.yaml`. The shared local `50`
rule accepts the approved local `:latest` and `:tilt-<hash>` exceptions needed
for Tilt, which must never be active on the OCI cluster.

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
