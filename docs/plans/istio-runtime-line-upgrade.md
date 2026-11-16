# Istio Runtime Line Upgrade

Move the Istio charts (`base`, `cni`, `istiod`, `gateway`) from 1.30 to a supported line. This
resolves the Istio half of
[`docs/issues/medium-nginx-and-istio-runtime-support-windows.md`](../issues/medium-nginx-and-istio-runtime-support-windows.md).
The NGINX half has its own plan, [`nginx-runtime-line-upgrade.md`](nginx-runtime-line-upgrade.md),
and does not depend on this one.

Upstream status on 2026-11-16 from
<https://istio.io/latest/docs/releases/supported-releases/>:

- 1.30 is expected to reach end of life around 2026-12-16. Upstream lists 1.30.8 as the minimum
  1.30 patch with no known CVEs, so the current `1.30.6` pin already carries known CVEs.
- 1.31 (released 2026-08-27, EOL ~2027-03) supports Kubernetes 1.32–1.37. Its minimum patch with
  no known CVEs is 1.31.4.
- 1.32 (released 2026-11-09, EOL ~2027-06) supports Kubernetes 1.33–1.37. It uses Envoy
  release/v1.40 and Gateway API v1.6.1.

The preferred target is the latest 1.32 patch, because it has the longest support window and the
local Kind node runs Kubernetes 1.35. If Phase 1 finds a blocker for 1.32, fall back to the latest
1.31 patch at or above 1.31.4. Re-check upstream at execution time; these figures are a snapshot.

Plan-wide constraints:

- Keep every Istio chart declaration on one version. The Tiltfile and
  `scripts/lib/production-version-contract.sh` change together. Treat Gateway API CRDs and Istio as
  one compatibility decision.
- Keep `linux/arm64` support, the `REGISTRY_ONLY` egress posture, ingress-layer `ext_authz`,
  per-client ingress rate limiting, path hardening, the exact-origin policy, STRICT mTLS and the
  observability-internal rules.
- Cluster mutation is allowed only after the `kind-kind` target checks in `AGENTS.md` and
  `docs/architecture/autonomous-ai-execution.md` pass. Do not generate certificates, do not run
  `setup.sh`, and do not recreate the cluster.
- Do not relax policies, disable guardrails or leave untracked live drift as a fix. Any temporary
  live step must be labelled as a diagnostic, and the cluster must end reconciled to the checked-in
  state.
- The `pod-security.kubernetes.io/*-version=v1.32` labels and `PRODUCTION_POD_SECURITY_VERSION` are
  Kubernetes Pod Security versions, not Istio versions. Do not change them as part of this plan.
- Run static-suite verifiers with
  `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python`. If that
  interpreter is missing, create it as described in `docs/ci-cd.md#security-guardrailsyml`.
- Validate any changed shell script with `bash -n` and `shellcheck`.

## Phase 1: Compatibility Review And Target Selection

### Workspace

.

### Goal

Select the exact target Istio version and Gateway API CRD version, with written evidence that the
repository's Istio-dependent contracts survive the move, before any pin changes.

### Scope

Read upstream release and upgrade notes for every minor between the current line and the target.
Compare them against the repository's Istio surfaces. Record the findings in
`docs/plans/istio-runtime-line-upgrade-evidence.md`.

### Non-goals

No pin, manifest or Tiltfile changes. No cluster mutation.

### Required context

- `AGENTS.md`
- `docs/architecture/security-architecture.md`, especially the gateway hardening bullet and
  `#ingress-per-client-rate-limiting`
- `docs/architecture/session-edge-authorization-pattern.md#authorizer-failures`
- `docs/development/local-environment.md`
- `docs/architecture/observability.md`
- `Tiltfile` Istio, Gateway API and egress sections
- `scripts/lib/production-version-contract.sh`, `scripts/lib/pinned-tool-versions.sh`
- `kubernetes/istio/`, especially `istiod-values.yaml`, `cni-*-values.yaml`,
  `egress-gateway-values.yaml`, `ingress-gateway-config.yaml`, `ingress-rate-limit.yaml`,
  `ingress-path-hardening.yaml`, `ingress-exact-origin.yaml` and `ext-authz-policy.yaml`
- `kubernetes/monitoring/kiali-values.yaml`

### Execution steps

1. Confirm the current pins with `rg -n '1\.30\.6' --glob '!docs/archive/**' --glob '!archive/**'`.
   Confirm the Gateway API pins in both version libraries.
2. From upstream, record the latest patch of 1.32 and of 1.31, their support windows, their
   supported Kubernetes ranges and their minimum CVE-free patches.
3. Read the 1.31 and 1.32 upgrade notes and change notes. For each change, record whether it
   affects the repository, and cite the affected file. At minimum, check:
   - EnvoyFilter filter-name matching. The 1.32 notes rename the gateway RBAC `ALLOW` filter to
     `istio.authorization.allow` when `ENABLE_GATEWAY_API_HTTPROUTE_AUTH=true`. Check whether that
     flag is set, and whether the `ext_authz` filter name that `ingress-rate-limit.yaml` and
     `ingress-path-hardening.yaml` anchor on stays the same.
   - Envoy local-rate-limit API fields relied on in `security-architecture.md` (in-filter actions,
     wildcard dynamic descriptors, `max_dynamic_descriptors`,
     `always_consume_default_token_bucket`, draft-03 headers, `ExtensionWithMatcher`).
   - `envoyExtAuthzHttp` fields in `istiod-values.yaml`, including `statusOnError` and `timeout`.
   - Gateway `spec.infrastructure.parametersRef` customization of the auto-provisioned ingress
     gateway, and its NodePort, seccomp and token-mount behavior.
   - `istio/gateway` chart values for the egress gateway, including `service.type=ClusterIP` and
     the low-port sysctl.
   - `istio/cni` chart values and Kind + Calico paths.
   - Kubernetes API client timeouts and unhealthy-endpoint publishing defaults.
   - The Gateway API CRD version that the target requires or bundles, and whether v1.5.1 stays
     supported.
   - Kiali chart `PRODUCTION_KIALI_CHART_VERSION` compatibility with the target Istio version, from
     Kiali's version-compatibility table.
   - Published `linux/arm64` artifacts for `pilot`, `proxyv2` and `install-cni`.
4. Decide how to move the running local cluster. Upstream documents in-place Helm upgrades from the
   previous minor. If the target skips a minor, the recommended live path is a transient,
   diagnostic-labelled in-place step through the latest 1.31 patch, followed by Tilt reconciling to
   the checked-in target. Record the chosen path.
5. Write the evidence file. It must contain the selected Istio version, the selected Gateway API
   version, the live upgrade path, a per-surface impact table, and the required follow-up edits for
   Phase 2.

### Implementation notes

If a 1.32 blocker cannot be resolved within this plan's constraints, select the latest 1.31 patch
at or above 1.31.4 and record why. If both lines have a blocker that needs a policy relaxation or a
sibling service change, stop and report it instead of continuing.

### Validation

The evidence file exists. Every surface listed in step 3 has an explicit outcome (no impact,
config edit needed, or blocker) with a source link. `git status` shows only the evidence file.

### Completion criteria

A fresh worker can read the evidence file and apply exact versions and edits without repeating the
upstream research.

## Phase 2: Pin Change And Offline Validation

### Workspace

.

### Goal

Move every checked-in Istio and coupled Gateway API pin to the Phase 1 selection, apply any
required configuration edits, and pass the offline guardrails.

### Scope

`Tiltfile` chart versions and version comments, `scripts/lib/production-version-contract.sh`, the
Gateway API version in both `production-version-contract.sh` and `pinned-tool-versions.sh` when
Phase 1 selected a change, and any `kubernetes/istio/` or values-file edits listed in the evidence
file.

### Non-goals

No cluster mutation. No changes to Pod Security version labels. Documentation prose updates belong
to Phase 4, except where a guardrail reads the text.

### Required context

- `docs/plans/istio-runtime-line-upgrade-evidence.md`
- `AGENTS.md` sections on Prerequisites First and Image Pinning
- `scripts/README.md` entries for `verify-static-security-manifests.sh`,
  `verify-production-image-overlay.sh`, `verify-ingress-rate-limit-config.sh` and
  `render-image-scan-inputs.sh`
- `docs/ci-cd.md#security-guardrailsyml`

### Execution steps

1. Replace every `1.30.6` Istio chart version in `Tiltfile` (`istio-base`, `istio-cni`, `istiod`,
   egress `gateway`) and `PRODUCTION_ISTIO_CHART_VERSION` with the selected version. Keep the
   `# renovate:` annotations intact.
2. Update the Tiltfile comments that name the Istio version.
3. If Phase 1 selected a new Gateway API version, update `PHASE7_GATEWAY_API_VERSION` and
   `PRODUCTION_GATEWAY_API_CRDS_VERSION` together.
4. Apply the configuration edits from the evidence file.
5. Bump `PRODUCTION_VERSION_CONTRACT_EFFECTIVE_DATE` to the date of the change.
6. Run the offline validations below and fix the failures without relaxing a check.

### Implementation notes

Use `rg` to confirm that no checked-in non-archive, non-plan file still selects the old Istio
version. Leave historical references in `docs/archive/` and `archive/oci/` unchanged.

### Validation

```bash
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-ingress-rate-limit-config.sh
./scripts/guardrails/verify-production-image-overlay.sh
./scripts/guardrails/check-image-pinning.sh
./scripts/security/render-image-scan-inputs.sh   # confirm it renders with the new chart version
```

Run `bash -n` and `shellcheck` on every changed shell script.

### Completion criteria

All checked-in active Istio selections name one version, the Gateway API pins agree, and every
offline validation above passes.

## Phase 3: Live Local Upgrade And Edge Verification

### Workspace

.

### Goal

Upgrade the running local Kind cluster to the selected Istio version, roll every meshed workload
and gateway onto the new proxy, and prove that the edge, authorization, rate-limit, egress and
tracing contracts still hold.

### Scope

Live `kind-kind` cluster only, through Tilt and the Phase 1 upgrade path.

### Non-goals

No cluster recreation, no `setup.sh`, and no certificate operations. No checked-in changes except
fixes for defects the live proof finds. Those fixes must be repo-owned and must be re-run through
the Phase 2 offline validations.

### Required context

- `docs/plans/istio-runtime-line-upgrade-evidence.md`
- `docs/architecture/autonomous-ai-execution.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/development/getting-started.md`
- `scripts/README.md` entries for the verifiers below

### Execution steps

1. Prerequisite: the human has `tilt up` running and the stack is healthy. If it is not, stop and
   report this rather than starting it yourself.
2. Run `./scripts/bootstrap/check-local-runtime.sh`. Apply the `kind-kind` context, loopback API,
   no-proxy and Ready-node checks from `AGENTS.md`.
3. Record the pre-upgrade `helm list -n istio-system` and `helm list -n istio-egress`, plus the
   proxy versions from the pod images.
4. If the evidence file requires a transient intermediate minor, run the labelled diagnostic
   `helm upgrade` steps for `base`, `cni` and `istiod`, then the egress `gateway`, at that patch,
   with the same values files Tilt uses. Verify that istiod and the gateways are Ready.
5. Trigger the Tilt resources (`gateway-api-crds` if changed, `istio-base`, `istio-cni`, `istiod`,
   `istio-egress-gateway`) with `tilt trigger`, so that the cluster reconciles to the checked-in
   target.
6. Restart meshed workloads in `default` and any other injected namespace. Confirm that the
   auto-provisioned ingress gateway and the egress gateway run the target proxy version, and that
   no pod still runs the old proxy.
7. Run the live verifiers below. Fix repo-owned defects and re-run.

### Implementation notes

Use `tilt get uiresources`, `kubectl get pods -A` and `kubectl logs` for diagnosis. Do not leave
any Helm release, CRD or workload on a version that differs from the checked-in pins.

### Validation

```bash
./scripts/smoketest/verify-istio-ingress.sh
./scripts/smoketest/verify-ingress-rate-limits.sh
./scripts/smoketest/verify-edge-contract.sh
./scripts/smoketest/verify-edge-browser-hardening.sh
./scripts/smoketest/verify-session-architecture.sh
./scripts/smoketest/verify-istio-tracing-config.sh
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/smoketest/verify-security-guardrails.sh
```

Also confirm in the Kiali UI or API that Kiali reports the new Istio version without
compatibility warnings. Use the documented observability port-forward with a VM-loopback listener
only.

### Completion criteria

Every Helm release and proxy in the cluster runs the selected version, and every live verifier
above passes against it.

## Phase 4: Documentation, Support Window And Closeout

### Workspace

.

### Goal

Bring active documentation, the runtime support inventory and the issue in line with the new
baseline, and pass the aggregate smoketest.

### Scope

Active docs that name the Istio version or describe behavior that Phase 1 found changed,
`scripts/lib/runtime-support-windows.txt`, the issue file, and removal of the evidence file after
its durable facts are moved into owner docs.

### Non-goals

No edits to `docs/archive/`, `docs/decisions/` or `archive/oci/`. No NGINX changes.

### Required context

- `docs/OWNERSHIP.md`
- `docs/plans/istio-runtime-line-upgrade-evidence.md`
- `docs/dependency-automation.md#operator-routine`
- `docs/issues/medium-nginx-and-istio-runtime-support-windows.md`

### Execution steps

1. Update `docs/development/local-environment.md` and `docs/architecture/security-architecture.md`
   (the gateway hardening bullet and the Envoy local-rate-limit paragraph), plus any other active
   doc that `rg` shows naming the old Istio version.
2. Move any durable behavior change recorded in the evidence file into its owner doc, following
   `docs/OWNERSHIP.md`.
3. Update the Istio row in `scripts/lib/runtime-support-windows.txt` with the new line, its support
   end and the source URL. When upstream gives only a month, record the first day of that month and
   explain the derivation in the note column.
4. Update the issue. If the NGINX line is still flagged by
   `./scripts/repo/report-runtime-support-windows.sh`, remove the Istio content and leave the issue
   Open. If neither line is flagged, delete the issue file, which is the repository convention for
   resolved issues.
5. Delete `docs/plans/istio-runtime-line-upgrade-evidence.md`.

### Implementation notes

Keep documentation version mentions to the places that already carry them. Do not add new version
inventories.

### Validation

```bash
./scripts/repo/report-runtime-support-windows.sh   # Istio must not be flagged
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/smoketest/smoketest.sh
rg -n '1\.30\.6' --glob '!docs/archive/**' --glob '!archive/**'   # expect no active hits
```

### Completion criteria

The report does not flag Istio, the aggregate smoketest passes, active docs name the new version,
the issue reflects the remaining scope or is deleted, and the evidence file is gone.
