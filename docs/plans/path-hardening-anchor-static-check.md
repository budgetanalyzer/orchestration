# Statically Check The Path-Hardening ext_authz Anchor

Close the gap recorded as accepted in the Negative consequences of
[ADR 012](../decisions/012-shared-nginx-routes-and-path-hardening.md#consequences).
`kubernetes/istio/ingress-path-hardening.yaml` patches the gateway with
`INSERT_BEFORE envoy.filters.http.ext_authz`. If nothing generates that
filter, Istio silently skips the patch. `scan_istio_ingress_path_hardening_contract`
in `scripts/guardrails/verify-static-security-manifests.sh` already checks that
the patch names that anchor. Nothing in the static suite checks what generates
the anchor. Istio generates the filter on the gateway only when a `CUSTOM`
AuthorizationPolicy selects the gateway and names a mesh `extensionProviders`
entry of type `envoyExtAuthzHttp` or `envoyExtAuthzGrpc`. Here those are
`ext-authz-at-ingress` in `kubernetes/istio/ext-authz-policy.yaml` and
`ext-authz-http` in `kubernetes/istio/istiod-values.yaml`.
`verify-mesh-authorization.py` skips `CUSTOM` policies.
`scan_istio_ext_authz_denial_contract` checks only the provider's fields, not
whether a policy uses it. So today no static check fails when the ext_authz
policy is deleted, renamed, retargeted or pointed at a non-ext_authz provider.
That loss also silently removes path hardening from the `/auth/*` lane, which
ext_authz never covered.

ADR 012 accepts this gap until the static suite gains a cheap way to assert
the anchor. That cheap way exists: the existing Python scan can also read the
`CUSTOM` policy and the istiod values. PyYAML is already loaded, and the
production render `istio-ingress-policies.yaml` already contains both the
EnvoyFilter and the policy. CI runs the static suite. The live edge verifier
runs only against local Kind, so this moves the anchor regression from
"caught live" to "caught in CI".

Constraints:

- Keep the check structural. It cannot prove Istio's generated filter name or
  order, and it does not model `CUSTOM` policies in the mesh root namespace or
  outside the passed manifest set. The live check in
  `scripts/smoketest/verify-edge-contract.sh` (`ingress_path_hardening_filter_problem`)
  stays the proof of the generated order. Do not change it.
- No runtime manifest behavior changes. Do not edit
  `ext-authz-policy.yaml`, `istiod-values.yaml` or the EnvoyFilter spec.
- Follow the repository shell rules (`bash -n`, `shellcheck`) and the
  explicit PyYAML interpreter rule in `AGENTS.md`. If
  `.cache/phase7-static-tools/pyyaml-venv/bin/python` is missing, create it
  with `docs/ci-cd.md#security-guardrailsyml`. Never fall back to system
  PyYAML.
- `docs/decisions/` is normally read-only. The user explicitly authorized
  this plan to update ADR 012's path-filter anchor bullet in Phase 2, and no
  other ADR content.
- Do not run git write commands.

## Phase 1: Anchor Check In The Static Path-Hardening Scan

### Workspace

.

### Goal

Make `scan_istio_ingress_path_hardening_contract` fail unless the same manifest
set contains exactly one ingress `CUSTOM` AuthorizationPolicy that will make
Istio generate `envoy.filters.http.ext_authz` on the workload the EnvoyFilter
selects. Prove the check with self-test fixtures that fail only for their
intended reason.

### Scope

- `scripts/guardrails/verify-static-security-manifests.sh`: the scan function,
  its header comment, its repo and production-render call sites, the self-test
  loop, a new `EXT_AUTHZ_POLICY_FILE` variable and the `usage()` text bullet
  for ingress path hardening.
- New fail fixtures under `tests/security-guardrails/fixtures/fail/`.

### Non-goals

- Changes to `verify-mesh-authorization.py`, the live edge verifier,
  `scan_istio_ext_authz_denial_contract` or any Kubernetes manifest.
- Modeling root-namespace or cross-namespace `CUSTOM` policies.
- Documentation outside the script (Phase 2).

### Required context

- `scripts/guardrails/verify-static-security-manifests.sh`: read
  `scan_istio_ingress_path_hardening_contract`, `scan_istio_ext_authz_denial_contract`,
  `run_repo_pattern_scans` and `run_self_test`
- `kubernetes/istio/ingress-path-hardening.yaml`
- `kubernetes/istio/ext-authz-policy.yaml`
- `kubernetes/istio/istiod-values.yaml` (`meshConfig.extensionProviders`)
- `kubernetes/production/istio-ingress-policies/kustomization.yaml`
- The existing `tests/security-guardrails/fixtures/fail/ingress-path-hardening-*.yaml`
- `docs/ci-cd.md#security-guardrailsyml`

### Execution steps

1. Add `EXT_AUTHZ_POLICY_FILE="${REPO_DIR}/kubernetes/istio/ext-authz-policy.yaml"`
   next to `INGRESS_PATH_HARDENING_FILE`.
2. Change the scan's signature to
   `scan_istio_ingress_path_hardening_contract SUBJECT ISTIOD_VALUES MANIFEST...`.
   In the embedded Python, take the istiod values path as `sys.argv[2]` and the
   manifests as `sys.argv[3:]`. Load documents from all manifests into one
   set instead of checking each file on its own, and require exactly one
   `ingress-path-hardening` EnvoyFilter across the set. Keep every existing
   EnvoyFilter assertion unchanged.
3. Add the anchor check, with failure messages that name the anchor, for
   example `path-hardening anchor envoy.filters.http.ext_authz is not
   generated: ...`:
   - From `meshConfig.extensionProviders` in the istiod values file, loaded
     with `yaml.safe_load`, collect the providers by name. A file that cannot
     be parsed, or a missing provider list, is a failure.
   - Across the manifest set, require exactly one `AuthorizationPolicy` with
     `spec.action: CUSTOM` in namespace `istio-ingress`. Require it to be
     named `ext-authz-at-ingress` with `apiVersion: security.istio.io/v1`.
   - Its `spec.selector.matchLabels` must equal the EnvoyFilter's
     `spec.workloadSelector.labels`. Compare against the parsed EnvoyFilter,
     not a constant. It must set neither `targetRef` nor `targetRefs`.
   - It must not carry the `istio.io/dry-run` annotation.
   - It must have a non-empty `rules` list. A `CUSTOM` policy with no rules
     matches nothing.
   - `spec.provider.name` must name exactly one extension provider, and that
     provider must have an `envoyExtAuthzHttp` or `envoyExtAuthzGrpc` key.
     Do not duplicate the provider field checks, which
     `scan_istio_ext_authz_denial_contract` owns.
4. Update the call sites:
   - Repo: `scan_istio_ingress_path_hardening_contract "repo" "${ISTIOD_VALUES_FILE}" "${INGRESS_PATH_HARDENING_FILE}" "${EXT_AUTHZ_POLICY_FILE}"`.
   - Production render: `scan_istio_ingress_path_hardening_contract "production render" "${ISTIOD_VALUES_FILE}" "${KUSTOMIZE_RENDER_DIR}/istio-ingress-policies.yaml"`.
     The production mesh guard call already uses the shared istiod values.
5. Update the self-test:
   - Existing `ingress-path-hardening-*.yaml` loop: pass
     `"${ISTIOD_VALUES_FILE}" "${path_fixture}" "${EXT_AUTHZ_POLICY_FILE}"`
     so each existing fixture still fails only for its EnvoyFilter defect.
   - New loop over `ingress-ext-authz-anchor-*.yaml` with
     `"${ISTIOD_VALUES_FILE}" "${INGRESS_PATH_HARDENING_FILE}" "${anchor_fixture}"`,
     using the same "unexpectedly passed" counter pattern. Declare the new
     loop variable in the existing `local` line.
6. Add these fail fixtures. Each is a copy of `ext-authz-policy.yaml` with one
   defect and a leading comment that names the scan and the defect, matching
   the existing fixture style:
   - `ingress-ext-authz-anchor-missing.yaml`: no `CUSTOM` policy, only an
     unrelated `istio-ingress` `DENY` AuthorizationPolicy.
   - `ingress-ext-authz-anchor-allow-action.yaml`: `action: ALLOW`.
   - `ingress-ext-authz-anchor-selector-mismatch.yaml`: a different
     `gateway.networking.k8s.io/gateway-name` value.
   - `ingress-ext-authz-anchor-unknown-provider.yaml`: `provider.name` not in
     the istiod values.
   - `ingress-ext-authz-anchor-non-ext-authz-provider.yaml`:
     `provider.name: jaeger`, an existing `opentelemetry` provider.
   - `ingress-ext-authz-anchor-dry-run.yaml`: `istio.io/dry-run: "true"`.
7. Update the `usage()` bullet for ingress path hardening to say the scan also
   requires the ext_authz anchor policy and provider, locally and in the
   production render. Update the function's header comment to match.

### Implementation notes

- The self-test checks only that a fixture fails, not why it fails. For each
  new fixture and each existing `ingress-path-hardening-*` fixture, read the
  scan's stderr in the self-test output and confirm that the only reported
  failure is the intended one.
- The self-test also passes the whole fixture directory to the image-pinning
  and PSA scans, which are expected to fail. New fixtures need no third-party
  images or namespaces.
- Keep YAML access defensive (`or {}` / `or []`), as the existing scan does.
  A malformed input must produce a failure message, not a traceback.

### Validation

```bash
bash -n scripts/guardrails/verify-static-security-manifests.sh
shellcheck scripts/guardrails/verify-static-security-manifests.sh

INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh

INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh --self-test
```

The normal run must print `repo ingress path hardening contract scan passed`
and `production render ingress path hardening contract scan passed`. The
self-test must report no `unexpectedly passed` line, and per the
implementation notes each anchor fixture must fail with its intended anchor
message.

### Completion criteria

- Both guardrail runs exit 0. `bash -n` and `shellcheck` report nothing.
- Removing `ext-authz-at-ingress`, changing its action, selector or provider,
  or adding dry-run makes the repo scan fail. The six new fixtures prove this.
- The existing path-hardening fixtures still fail only for their original
  defects.
- No Kubernetes manifest, live verifier or mesh guard file changed.

## Phase 2: Documentation And ADR 012 Update

### Workspace

.

### Goal

Document the anchor dependency and its static and live checks in their owner
docs, and change ADR 012's accepted-gap bullet into a statement of the
current checks.

### Scope

- `docs/decisions/012-shared-nginx-routes-and-path-hardening.md`: only the
  Negative-consequence bullet that begins "The path filter is inserted before
  `envoy.filters.http.ext_authz`"
- `docs/architecture/security-architecture.md#ingress-path-hardening`
- `scripts/README.md`: the `verify-static-security-manifests.sh` entry that
  describes the path-hardening scan
- `kubernetes/istio/ingress-path-hardening.yaml`: header comment only

### Non-goals

- Any code or manifest spec change. Phase 1 owns the code.
- Edits to other ADR content, other ADRs, `docs/archive/` or issue files.

### Required context

- Phase 1's diff to `scripts/guardrails/verify-static-security-manifests.sh`
- `docs/OWNERSHIP.md`
- `docs/decisions/012-shared-nginx-routes-and-path-hardening.md`
  (Consequences)
- `docs/architecture/security-architecture.md` (the Ingress Path Hardening
  and Static Contract Guard sections)
- `scripts/README.md`

### Execution steps

1. Rewrite the ADR 012 anchor bullet. Keep these facts:
   - The path filter is inserted before `envoy.filters.http.ext_authz`, which
     Istio generates only from the `CUSTOM` `ext-authz-at-ingress` policy and
     its `ext-authz-http` provider.
   - Without that filter, the patch silently does not apply, on either lane.
   - Source: 2026-11-09 independent implementation review C8.

   Replace the acceptance and the "revisit if" sentence with the current
   state:
   - The static suite now checks, locally and in the production render, that
     the policy and provider exist and select the patched gateway.
   - The live edge verifier checks the generated order.
   - The static check does not prove Istio's generated filter name or order.

   Since this is no longer an accepted gap, decide whether the bullet still
   belongs under Negative or should move to Neutral, and keep the separate
   ADR 019 bullet as it is.
2. In `security-architecture.md#ingress-path-hardening`, add a short
   paragraph. The filter's anchor is the `envoy.filters.http.ext_authz` filter
   that Istio generates only while `ext-authz-at-ingress` selects the gateway
   with the `ext-authz-http` provider. Without that filter, the patch silently
   does not apply on either lane. The static suite checks that the policy and
   provider exist, locally and in the production render, and
   `verify-edge-contract.sh` checks the generated order live. State the static
   limit: it does not prove Istio's filter name or order.
3. In `scripts/README.md`, extend the `verify-static-security-manifests.sh`
   path-hardening sentence with the anchor requirement. Keep the wording
   aligned with the `usage()` text from Phase 1.
4. In the header comment of `ingress-path-hardening.yaml`, add one sentence:
   the anchor exists only while `ext-authz-policy.yaml`'s `CUSTOM` policy
   selects this gateway, and the static suite checks this.

### Implementation notes

- Keep `security-architecture.md` as the owner of the current explanation.
  The README and manifest comment get one sentence each and do not restate
  it. ADR 012 records the decision context and may link to the
  security-architecture section instead of repeating its detail.
- Apply `docs/agents-md-checkstyle.md` only if `AGENTS.md` changes. This
  plan expects no `AGENTS.md` change.

### Validation

```bash
rg -n "Revisit if the static suite" docs/decisions/012-shared-nginx-routes-and-path-hardening.md

INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh

INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh --self-test

git diff --stat
```

The `rg` must return nothing. The static suite reruns because Phase 2 touches
a scanned manifest comment.

### Completion criteria

- ADR 012 no longer describes the anchor as an accepted gap. It names the
  static and live checks and the static limit, and keeps the review source.
- The security architecture doc, `scripts/README.md`, the manifest comment and
  ADR 012 describe the same anchor contract and its static limit.
- Both guardrail runs exit 0.
- `git diff --stat` shows changes only to the Phase 1 files, the Phase 2 scope
  files and the earlier ADR 012 and issue-deletion edits.
