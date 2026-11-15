# Close Additive ALLOW Gaps in the Static Mesh Guard

Address [the open mesh guard issue](../issues/medium-static-mesh-guard-misses-additive-allow.md)
by checking all relevant additive ALLOW rules, including Session Gateway and
policies selected by labels other than `app`. Keep this a structural contract
checker, not an Istio policy simulator. The unmodified policy set must pass;
both mutations recorded in the issue must fail for their intended reasons.

The current baseline includes a legitimate selectorless
`envoy-metrics-prometheus-policy`, allowing only the Prometheus identity on
port `15090`. Preserve that allowance through an exact, content-validated
exception. Rejecting every selectorless ALLOW as proposed in the issue would
break the existing observability contract. A policy name alone must never
exempt its contents from validation.

All work stays in orchestration. Preserve runtime authorization behavior and
use offline tests and production-reference renders. No cluster mutation,
certificate operation, sibling service change, Git write, or publication is
part of this plan. Follow the workspace pre-agent procedure in `AGENTS.md`.
Use the repository-local hash-verified PyYAML environment documented in
[CI/CD](../ci-cd.md#security-guardrailsyml); create it through that documented
setup if missing, and stop on unmet prerequisites rather than falling back to
system PyYAML. Production checks prove only the offline reference.

## Phase 1: Enforce the local additive ALLOW contract

### Workspace

.

### Goal

Replace the narrow embedded checker with a directly testable structural guard
that detects additive grants across the complete local policy input set and
discovers backend workloads without the hardcoded `BACKEND_APPS` tuple.

### Scope

The AuthorizationPolicy scanner in
`scripts/guardrails/verify-static-security-manifests.sh`, a focused Python
helper under `scripts/guardrails/`, focused tests under
`tests/security-guardrails/`, and the nearest security and verifier docs.

### Non-goals

Changing deployed access rules, deriving every public resource path from NGINX,
simulating Istio request evaluation, validating arbitrary third-party mesh
configuration, or refactoring unrelated static checks.

### Required context

- `docs/issues/medium-static-mesh-guard-misses-additive-allow.md`
- `docs/OWNERSHIP.md`
- `docs/architecture/security-architecture.md#mesh-publicinternal-boundary`
- `docs/architecture/session-edge-authorization-pattern.md`
- `scripts/guardrails/verify-static-security-manifests.sh`, especially
  `scan_istio_authorization_policy_contract`, `run_repo_pattern_scans`, and
  `run_self_test`
- `scripts/lib/guardrail-python.sh` and
  `docs/ci-cd.md#security-guardrailsyml`
- `kubernetes/istio/authorization-policies.yaml`,
  `kubernetes/istio/ext-authz-policy.yaml`, and
  `kubernetes/istio/ingress-exact-origin.yaml`
- `kubernetes/services/`, `Tiltfile`, and the namespace/injection settings
  under `kubernetes/istio/` and `kubernetes/monitoring/`
- Existing `tests/security-guardrails/fixtures/fail/authorization-policy-*.yaml`
  and the static gate entry in `scripts/README.md`

### Execution steps

1. Extract the `AUTHZ_PY` logic into
   `scripts/guardrails/verify-mesh-authorization.py`. Keep the shell function as
   its adapter, using `GUARDRAIL_PYTHON` and isolated Python execution. Give
   the helper explicit policy-set and workload inputs, deterministic exit
   status, and diagnostics naming the file, namespace/policy, rule, and
   offending `from` or `to` entry. Catch malformed input as a validation
   failure. Retain the empty default-deny and backend path checks.
2. Discover application workload pod labels and service accounts from
   `kubernetes/services/`. Classify all discovered workloads: treat new
   workloads as NGINX backends by default, with explicit, reasoned special
   roles for `nginx-gateway`, `session-gateway`, `ext-authz`, and
   `budget-analyzer-web`. Validate exclusions against discovered workloads;
   a new backend must require a checkable NGINX path rule without editing a
   backend-name tuple. Use actual pod labels for selector matching, including
   `app.kubernetes.io/framework`, namespace boundaries, and conjunctions of
   multiple selector labels.
3. Collect complete AuthorizationPolicy documents from active Kubernetes
   source manifests, including newly added files. Exclude Kustomize patch
   fragments from standalone policy evaluation and handle rendered overlays
   separately in Phase 2. Exclude archives and fixtures. Evaluate the local
   files together as one set; do not require a default-deny policy per file.
   Reject duplicate policy identities. Document the inspected mesh namespace
   scope from the checked-in topology: application `default`,
   `istio-ingress`, `istio-egress`, meshed monitoring workloads, and the
   mesh root namespace (`istio-system` unless configured otherwise). A new
   namespace must not silently evade the declared scope.
4. Handle omitted `action` as ALLOW. Preserve exactly one empty
   `default/default-deny-all`; its name must not exempt a nonempty grant.
   Reject other selectorless or effectively empty-selector ALLOW policies
   in the inspected mesh namespaces, except the exact Envoy metrics contract:
   the existing namespace/name, Prometheus principal, sole port `15090`, and
   no extra granting branches. Inspect root-namespace policies as potentially
   cross-namespace. Reject unsupported ALLOW attachment forms such as
   `targetRefs` with an actionable diagnostic instead of silently skipping
   them. Leave DENY, CUSTOM, and AUDIT to their existing checks.
5. Inspect every ALLOW policy that selects a protected workload, including
   additional policies and selectors without `app`. Each rule must have a
   nonempty `from`, and every alternative must provide nonempty, explicit
   `source.principals`. Reject wildcard or unapproved principals, empty
   alternatives, and rules using only other source fields. Validate each
   principal against the selected workload's caller contract, so adding a
   second source entry cannot bypass the check. Do not flatten alternatives
   and conclude that one valid principal makes the whole rule safe.
6. Check every `to` alternative for the applicable caller/workload pair:
   - NGINX to discovered backends requires nonempty paths and retains the
     existing rejection of service/version-wide wildcards and `{**}`.
   - Ingress to Session Gateway requires paths confined to the currently
     documented auth surface. A `/*` path or one extra unrestricted operation
     must fail; the auth prefixes must not be passed through the backend-only
     minimum-segment heuristic.
   - Session Gateway to permission-service preserves the exact POST sync
     and GET authorization path/method pairs. permission-service to Session
     Gateway preserves the DELETE revocation path and port `8081`.
   - Prometheus rules preserve the checked-in principal and narrow metrics
     path/method/port combinations, including the framework-label selector.
   - Preserve the intentional caller-only rules for ingress to NGINX and
     ext-authz, and NGINX to the local frontend. These are specific
     caller/workload contracts, not general exemptions from path checks.
   Mixed principals must satisfy every applicable contract; unsupported
   combinations fail closed rather than selecting the first matching case.
7. Add a focused runner
   `tests/security-guardrails/test-mesh-authorization.py` that invokes the
   same helper as the shell adapter against temporary copies of complete
   valid inputs. Prove the baseline passes before applying each mutation,
   assert the mutation changed its input, and require both nonzero status
   and the intended diagnostic. Update existing minimal fixtures as needed
   so unrelated missing-workload failures cannot mask their purpose. Wire
   these regression cases into `--self-test` without introducing a new
   Python dependency.
8. Update the canonical security architecture section first, then
   `scripts/README.md` and the shell help/comments to describe the implemented
   local scope, inventory discovery, exact metrics exception, and structural
   limits. Do not claim exact equivalence with NGINX routes or live mesh
   evaluation. Keep instructions for adding a service aligned with the new
   classification rule; update `AGENTS.md` only if its workflow changes,
   applying `docs/agents-md-checkstyle.md` if it does.

### Implementation notes

Use a small explicit caller contract and ordinary YAML/label inspection.
Avoid a generic policy language or a service-name/path inventory copied from
multiple sources. Existing ALLOW policies are additive even when a default
deny-all policy exists. Every granting branch matters: `from` alternatives,
principals within a source, `to` alternatives, and extra policies.

The checker may accept a narrower grant while requiring the baseline caller
lanes to remain represented. It must not claim that its backend wildcard
heuristic establishes exact public-route membership. Preserve that distinction
in diagnostics and docs.

### Validation

Run the focused runner with the pinned interpreter:

```bash
.cache/phase7-static-tools/pyyaml-venv/bin/python -I \
  tests/security-guardrails/test-mesh-authorization.py
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh --self-test
bash -n scripts/guardrails/verify-static-security-manifests.sh
shellcheck scripts/guardrails/verify-static-security-manifests.sh
```

Also run `bash -n` and ShellCheck on any other changed shell script. The
focused matrix must include:

| Input or mutation | Expected result |
| --- | --- |
| Unmodified complete local policies and workloads | Pass |
| Add namespace-wide `ALLOW` with `rules: [{}]`, in the existing file and a new file | Fail: broad additive grant |
| Omit `action` or use an empty selector on that grant | Fail: implicit/broad ALLOW |
| Add a broad root-namespace ALLOW | Fail: root scope |
| Remove Session Gateway ingress `to`, remove paths, or add `/*` | Fail: auth path restriction |
| Add an empty `from` alternative beside an approved source | Fail: unrestricted source alternative |
| Add a wildcard or unexpected principal, including alongside a valid principal | Fail: caller contract |
| Add a broad policy using the Spring framework label instead of `app` | Fail: selected workload contract |
| Add an unrestricted `to` beside a valid operation | Fail: unrestricted operation alternative |
| Remove internal permission-service paths or broaden internal methods/revocation port | Fail: internal caller contract |
| Keep the legitimate selectorless Envoy metrics grant | Pass |
| Keep its name but change its principal/port or add a granting rule | Fail: metrics exception mismatch |
| Add a synthetic backend without a NGINX path rule, then supply a valid rule | Fail, then pass |
| Existing missing/nonempty default-deny and backend wildcard fixtures | Fail for their original reasons |
| Existing ingress CUSTOM/DENY policies | Remain valid under their own checks |

### Completion criteria

The shell adapter and focused runner use the same checker; the unchanged
local set passes, both issue reproductions fail for their intended reasons,
and the additional source/selector/operation cases pass their assertions.
New policy files and new backend workloads cannot silently bypass the local
check. Focused tests, self-tests, and shell validation pass, and documentation
accurately describes the local behavior delivered in this phase.

## Phase 2: Validate the offline production reference and full gate

### Workspace

.

### Goal

Apply the same contract to the production-reference policy/workload renders,
prove integration through the full static gate, and close the issue only
after its acceptance criteria are verified.

### Scope

Production render inputs to the static scanner, production regression cases,
the full static validation path, and final documentation/issue status.

### Non-goals

Hosted deployment, image publication or release changes, live cluster tests,
and changes to the frontend's intentional production topology difference.

### Required context

- Phase 1 helper, shell integration, tests, and updated documentation
- `docs/OWNERSHIP.md` and `docs/ci-cd.md#security-guardrailsyml`
- `deploy/README.md`, `archive/oci/README.md`, and
  `kubernetes/production/README.md`
- `kubernetes/production/istio/kustomization.yaml` and its frontend deletion
  patch, `kubernetes/production/apps/kustomization.yaml`, and
  `kubernetes/production/istio-ingress-policies/kustomization.yaml`
- `deploy/scripts/render/production-routes.sh`
- `scripts/guardrails/verify-static-security-manifests.sh`
- `docs/issues/medium-static-mesh-guard-misses-additive-allow.md`

### Execution steps

1. Extend the existing offline render path to feed the production workload
   authorization and relevant ingress policy sets, plus rendered app pod
   labels/service accounts, to the same helper. Reuse the gate's verified
   Kustomize tool and temporary-output lifecycle. Keep local and production
   sets separate; do not combine shared source policies with their rendered
   copies or treat deletion patches as standalone policies.
2. Model the existing production absence of `budget-analyzer-web` as the
   documented topology difference. Require all remaining application caller
   contracts and the default-deny/metrics contracts without weakening local
   frontend coverage. Fail if other required policies or workloads disappear.
3. Extend the focused tests to assert the unchanged production render passes,
   then mutate temporary rendered copies with the two issue reproductions,
   an added broad policy, and a broadened metrics exception. Require the
   intended failures. Check that a production-only overlay addition is
   inspected, not hidden by a successful source-file check.
4. Update `docs/architecture/security-architecture.md`, then
   `scripts/README.md` and `docs/ci-cd.md`, to state the exact local and
   rendered-production coverage and remaining structural limitations. Update
   `kubernetes/production/README.md` only where its validation description
   changes. Retain the offline-reference qualification throughout.
5. Run the validation below. Resolve failures caused by this change and
   distinguish prerequisite or unrelated failures; do not mark acceptance
   complete without a passing relevant gate. After successful validation,
   update the issue status and link the implemented checker/tests, noting
   the exact metrics exception that replaces the proposed blanket ban.

### Implementation notes

Rendering and static analysis must require no kubeconfig, Kubernetes API,
cloud configuration, or deployment credentials. Existing verified-tool or
pinned-chart downloads may still require network access. Do not modify
archived files or decision records. Keep shell diagnostics useful when a
render or Python input fails, and clean temporary artifacts on failure.

### Validation

Run the focused runner against both environments, then the self-test and full
static suite with the explicitly selected interpreter:

```bash
.cache/phase7-static-tools/pyyaml-venv/bin/python -I \
  tests/security-guardrails/test-mesh-authorization.py
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh --self-test
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
bash -n scripts/guardrails/verify-static-security-manifests.sh
shellcheck scripts/guardrails/verify-static-security-manifests.sh
git diff --check
```

Validate any other changed shell scripts as well. Check documentation links
and ensure the reported acceptance distinguishes fixture/static success from
live runtime evidence. Neither the live security wrapper nor the aggregate
smoketest is necessary for this offline checker change.

### Completion criteria

Unmodified local policies and the production reference pass the same guard.
Both original reproductions and the expanded additive-grant regression cases
fail with specific diagnostics in the applicable environments. The full
static suite, self-tests, and shell checks pass. The canonical docs match the
implemented scope and the issue is closed with verifiable implementation and
test pointers.
