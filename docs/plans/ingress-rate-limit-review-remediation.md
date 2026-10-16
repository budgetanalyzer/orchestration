# Ingress Rate-Limit PR Review Remediation

Fix the three bounded review findings that belong in the current rate-limit
pull request: authority variants must not bypass a policy, the existing
production gateway render inputs must include the policy stats matcher, and
the live verifier must not leak port-forward processes or logs.

Do not add cleanup for `ingress-auth-local-rate-limit` to the OCI release
wrapper. OCI is retired and there is no existing production cluster to migrate.
Provider-neutral production architecture, retirement of OCI-specific paths,
and consolidation of local/production overlays belong to the separate
`docs/plans/provider-neutral-production-parity.md` plan. This PR may make the
small template updates needed to close the diagnostics bug, but must not turn
that fix into a deployment-platform refactor.

All work stays in this repository. Production checks are offline render checks;
do not access or mutate OCI or any production cluster. Live acceptance is
allowed only against the guarded local `kind-kind` target after documented
native prerequisites pass. Do not perform TLS writes, bypass normal certificate
verification, modify ADRs or archived documents, or run Git write operations.
Run `bash -n` and ShellCheck on every changed shell script and fix every finding.

## Phase 1: Close authority-variant limiter bypasses

### Workspace

.

### Goal

Ensure equivalent authority spellings cannot skip any protected auth or API
rate-limit policy.

### Scope

The Envoy matcher wrappers, production authority patches if still required,
offline matcher assertions, focused live authority probes, and canonical
rate-limit documentation.

### Non-goals

Changing Gateway host ownership, route destinations, token-bucket values,
client identity, path families, filter order, or broader production overlay
architecture.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `kubernetes/gateway/app-httproute.yaml`
- `kubernetes/gateway/api-httproute.yaml`
- `kubernetes/gateway/auth-httproute.yaml`
- `kubernetes/istio/ingress-rate-limit.yaml`
- `kubernetes/production/istio-ingress-policies/kustomization.yaml`
- `scripts/guardrails/verify-ingress-rate-limit-config.sh`
- `scripts/smoketest/verify-ingress-rate-limits.sh`
- `scripts/guardrails/verify-production-image-overlay.sh`

### Execution steps

1. Confirm that Gateway API routes own hostname admission and that the
   EnvoyFilter is selected only onto the application ingress gateway workload.
2. Prefer removing the redundant `:authority` predicate from each
   `ExtensionWithMatcher` so protected path families are limited for every
   authority reaching the selected gateway. Keep the segment-safe path regex,
   descriptor identity, marker, stats prefix, cache bound, token bucket, and
   insertion before `ext_authz` unchanged. If pinned Envoy behavior makes this
   impossible, use one case-insensitive matcher that accepts an optional
   default HTTPS port; do not enumerate casing variants.
3. If authority matching is removed, delete the four production hostname JSON
   patches so production renders the exact shared EnvoyFilter. Keep hostname
   ownership in production `HTTPRoute` patches.
4. Strengthen the offline verifier to assert the chosen matcher structure and
   exercise canonical, uppercase, `:443`, and mixed-case-with-`:443`
   authorities for every policy boundary. Equivalent authorities must resolve
   to the same policy and per-client descriptor. Retain path/query/method,
   lookalike-path, insertion-order, token-bucket, and client-isolation checks.
5. Extend the live probe helper to set an explicit HTTP authority while
   preserving canonical TLS SNI and normal certificate verification. After
   exhausting a protected API bucket, prove all authority variants receive the
   same policy-marked `429` while a second client retains its allowance.
6. Update production guardrails that assume the production hostname appears
   inside the EnvoyFilter, and update canonical security documentation to
   describe the final matcher boundary accurately.

### Implementation notes

Path-only matching is the preferred fix because it removes duplicate hostname
canonicalization rules. Gateway routing still decides whether a hostname is
served. An unmatched authority can consume only its caller's per-IP descriptor
before routing rejects it; it cannot consume another client's allowance.

### Validation

- Render `kubernetes/production/istio-ingress-policies` with Kustomize and
  compare the resulting EnvoyFilter structurally with the local source.
- Run `./scripts/guardrails/verify-ingress-rate-limit-config.sh`.
- After guarded local reconciliation, run the authority-variant section of
  `./scripts/smoketest/verify-ingress-rate-limits.sh` with normal TLS
  verification.
- Run `./scripts/guardrails/verify-production-image-overlay.sh`.
- Run `bash -n` and `shellcheck` for every shell script changed in this phase.

### Completion criteria

Uppercase and default-port authority variants cannot skip or obtain a fresh
allowance for any protected family, local and production policy semantics
match, and focused offline/live checks pass.

## Phase 2: Wire policy diagnostics into existing production renders

### Workspace

.

### Goal

Ensure both existing production gateway render stages select the same four
rate-limit metric families as local development.

### Scope

The ingress-bootstrap and public-TLS gateway ConfigMap templates, their render
checks, the focused configuration verifier, and narrowly affected diagnostics
documentation.

### Non-goals

Migrating an OCI cluster, changing release scripts, redesigning production
deployment, introducing shared gateway Kustomize bases, changing Service
exposure, or selecting a future provider. Those belong to the separate parity
plan.

### Required context

- `AGENTS.md`, `docs/architecture/security-architecture.md`
- `kubernetes/istio/ingress-gateway-config.yaml`
- `deploy/manifests/ingress-bootstrap/ingress-gateway-config.yaml.template`
- `deploy/manifests/public-tls/ingress-gateway-config.yaml.template`
- `deploy/scripts/bootstrap/03-render-ingress-bootstrap-manifests.sh`
- `deploy/scripts/render/public-tls.sh`
- `scripts/guardrails/verify-ingress-rate-limit-config.sh`
- `scripts/guardrails/verify-static-security-manifests.sh`

### Execution steps

1. Add the local ConfigMap's exact `proxy.istio.io/config` annotation and
   narrow `proxyStatsMatcher.inclusionRegexps` value to both production
   templates. Preserve their existing Service ports,
   `externalTrafficPolicy`, service account, security context, and unrelated
   render behavior.
2. Extend the focused configuration verifier to render or parse all three
   ConfigMaps and inspect the embedded deployment YAML. Assert each has exactly
   one equivalent stats inclusion regex and that it matches all four expected
   `ingress_*` local-rate-limit prefixes without enabling all optional Envoy
   statistics.
3. Exercise both production render entry points with temporary non-secret
   fixture values and temporary output directories. Validate the rendered
   ConfigMaps rather than only checking template strings.
4. Add the rendered templates to the appropriate static manifest gate if they
   are not already covered. Update only diagnostics documentation that claims
   where the four counters are available; leave provider architecture and OCI
   retirement documentation to the separate plan.

### Implementation notes

This intentionally duplicates a small annotation as a bounded bug fix. The
follow-up parity plan replaces that synchronization burden with a common base.
Do not begin that refactor in this PR.

### Validation

- Run both production render scripts with temporary fixture configuration and
  output directories; do not apply their output.
- Parse the local, ingress-bootstrap, and public-TLS ConfigMaps as YAML and
  prove the stats matcher structures are equivalent.
- Run `./scripts/guardrails/verify-ingress-rate-limit-config.sh` and the
  applicable static manifest guardrail.
- Run `bash -n` and `shellcheck` for every changed shell script.

### Completion criteria

Local development and both existing production renders expose the four narrow
policy metric families, structural render checks prevent regression, and no
deployment-platform refactor or OCI migration work is included.

## Phase 3: Make verifier port-forward cleanup reliable

### Workspace

.

### Goal

Preserve port-forward process state in the parent shell and prove successful
and failure-path cleanup cannot leak listeners or temporary logs.

### Scope

The focused live rate-limit verifier, cleanup assertions, verifier
documentation, and final integrated regression checks.

### Non-goals

Running against production, changing policy capacities, adding sustained load
tests, or weakening TLS and local-cluster guards.

### Required context

- `AGENTS.md`, `docs/architecture/autonomous-ai-execution.md`
- `docs/development/getting-started.md`
- `scripts/README.md`
- `scripts/lib/local-kubernetes-target.sh`
- `scripts/smoketest/verify-ingress-rate-limits.sh`
- final artifacts and validation results from Phases 1-2

### Execution steps

1. Change `start_pod_port_forward` to run in the parent shell and assign its
   selected port through an explicit output-variable argument or equivalent
   parent-shell state. Do not capture the function with command substitution.
   Register each PID and log immediately after spawning so startup timeout and
   later-test failures remain trap-cleanable.
2. Preserve direct child PIDs and stop them with precise `kill` plus `wait`;
   do not introduce broad process-name cleanup. Keep repeated cleanup harmless.
3. Before normal replica-test teardown, copy the registered PIDs and log paths,
   call `stop_port_forwards`, and assert every process is gone and every log has
   been removed. Retain the EXIT trap as the failure-path safety net.
4. Add a focused shell fixture if practical with the current script structure;
   otherwise make the live verifier's explicit post-cleanup assertions the
   regression proof. Do not weaken or bypass the local Kind guard to unit-test
   cleanup.
5. Run the full verifier against the reconciled local stack. Independently
   inspect listeners/processes and captured log paths after exit, then update
   `scripts/README.md` and the local verification record only after success.

### Implementation notes

Avoid `eval`. `printf -v` with a validated caller-provided variable name or a
simple global result variable is sufficient. A port-forward must be registered
before polling its log so the EXIT trap can clean up every partial startup.

### Validation

- Run `./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime`;
  stop if prerequisites fail.
- Before every local mutation, use the exact guarded `kind-kind` target check.
- Run `./scripts/smoketest/verify-ingress-rate-limits.sh` with normal TLS
  verification. Confirm replicas are restored and no registered PID, listener,
  or temporary log remains.
- Rerun `./scripts/guardrails/verify-ingress-rate-limit-config.sh`, production
  render checks from Phase 2, and affected static guardrails.
- Run `bash -n` and `shellcheck` on every changed shell script, then run
  `git diff --check`.

### Completion criteria

The live verifier retains all port-forward PIDs/logs in parent-shell state,
cleans them on success and failure, restores local replicas/resources, and all
three in-PR fixes pass focused offline and local validation.
