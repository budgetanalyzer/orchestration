# Security Hardening 01: Review Follow-ups

**Status:** Ready to run manually. Not formatted for AI Session Handler.

Follow-up to [Security Hardening 01](security-hardening-01-edge-mesh-redis-acl.md), from the review
of its uncommitted implementation. Each phase is small and is validated on its own. Run them in
order; Phase 4 validates with the default verifier run from Phase 3.

## Rules

- Work in this repository only. Follow `AGENTS.md`.
- No git write operations, no certificate operations, no staging or production access.
- Before any cluster mutation, apply the `kind-kind` checks in `AGENTS.md`.
- Every changed shell script passes `bash -n` and `shellcheck`.
- Do not edit `docs/decisions/` or `docs/archive/`. Do not rewrite the existing sections of
  `docs/research/security-consensus-hardening-evidence.md`. Add a dated follow-up section where a
  phase changes recorded behaviour, and correct only the tenant hostname in Phase 1.
- Leave `docs/plans/security-hardening-01-edge-mesh-redis-acl.md` unchanged. Its runs are
  recorded in the evidence file.

**Static gate**, at the end of every phase:

```bash
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh --self-test
./scripts/guardrails/verify-production-image-overlay.sh
git diff --check
```

## Phase 1: Repository hygiene

### Goal

Remove the local Auth0 tenant hostname, stop Python bytecode from appearing in the tree, and align
the Tilt CSP render with the existing interpreter convention.

### Context

- `docs/research/security-consensus-hardening-evidence.md:607` names the real local tenant
  origin. The file is untracked, so the hostname is in no unpushed commit. The same hostname is
  already in pushed history (`cc2f181` and `168c541` on `origin/main`, November 2025), so removing
  it is hygiene rather than a retraction.
- `.gitignore` contains `+__pycache__`, a diff marker committed in `59be115`. It ignores nothing.
- `scripts/guardrails/verify-edge-headers.py:14-16` imports `deploy/scripts/render/render-csp.py`
  through `importlib`. That writes `deploy/scripts/render/__pycache__/`.
- `Tiltfile:694` runs `python3` for the CSP render. The existing generator call at `Tiltfile:266`
  uses `python3 -I`.

### Steps

1. In the evidence file, replace the literal local tenant origin (`https://dev-<tenant>.us.auth0.com`) with "the local
   `AUTH0_ISSUER_URI` origin". Keep the production origin `https://auth.budgetanalyzer.org`, which
   is a documented reference input.
2. In `.gitignore`, replace `+__pycache__` with `__pycache__/`, and fix the comment spacing to
   `# Python cache`.
3. In `verify-edge-headers.py`, set `sys.dont_write_bytecode = True` before the `importlib`
   import of the renderer.
4. Delete `deploy/scripts/render/__pycache__/`.
5. Change the Tiltfile render command to `['python3', '-I', 'deploy/scripts/render/render-csp.py', ...]`.
6. In `docs/development/getting-started.md`, extend the existing step that says
   `AUTH0_ISSUER_URI` must be valid before `tilt up`. A missing or invalid issuer now stops the
   Tiltfile from loading at all, with `CSP issuer/render error: ...`, not just the egress resource.

### Validation

```bash
git grep --untracked -nE 'dev-[a-z0-9]{16}\.us\.auth0\.com'   # no output
git check-ignore -v deploy/scripts/render/__pycache__/x.pyc   # matched by __pycache__/
python3 -I deploy/scripts/render/render-csp.py --issuer '' --includes-json; echo "rc=$?"   # rc=1, no stdout
```

Run the static gate, then confirm `deploy/scripts/render/__pycache__/` was not recreated. With Tilt
running, confirm the Tiltfile reloads cleanly with `tilt get uiresources`.

## Phase 2: Static guardrail Python uses the repository venv

### Goal

No part of the static suite falls back to the system `python3` and its PyYAML. The repository venv
at `.cache/phase7-static-tools/pyyaml-venv/bin/python` is the default, and
`INGRESS_RATE_LIMIT_PYTHON` remains an explicit override.

### Context

- `scripts/guardrails/verify-static-security-manifests.sh:91` sets
  `AUTHORIZATION_POLICY_PYTHON="${INGRESS_RATE_LIMIT_PYTHON:-python3}"`. That interpreter runs the
  AuthorizationPolicy scan, the ingress path-hardening scan, and `verify-edge-headers.py`.
- `scripts/guardrails/verify-ingress-rate-limit-config.sh:14` also defaults to `python3`. It does
  enforce the pinned PyYAML version, so with the system interpreter it fails rather than drifting.
- `scripts/guardrails/verify-production-image-overlay.sh:947` already defaults to the venv.

### Steps

1. In both `verify-static-security-manifests.sh` and `verify-ingress-rate-limit-config.sh`, default
   the interpreter to `${REPO_DIR}/.cache/phase7-static-tools/pyyaml-venv/bin/python`. Keep
   `INGRESS_RATE_LIMIT_PYTHON` as the override.
2. In `verify-static-security-manifests.sh`, rename `AUTHORIZATION_POLICY_PYTHON` to a neutral
   name such as `GUARDRAIL_PYTHON`, because it now serves three checks.
3. Before the first Python use, which runs in both the normal and the `--self-test` paths, fail
   with a clear error if the interpreter is not executable. Use the same setup pointer that
   `verify-ingress-rate-limit-config.sh:180-187` prints, and link to
   `docs/ci-cd.md#security-guardrailsyml`. Do not fall back to `python3`.
4. In `verify-production-image-overlay.sh`, add the same executable check before
   `verify-edge-headers.py` runs.
5. Update every doc that describes a `python3` fallback for these variables. Find them with
   `rg -n 'INGRESS_RATE_LIMIT_PYTHON|python3' docs/ci-cd.md scripts/README.md deploy/README.md`.
   `AGENTS.md` stays correct, because explicit selection still works. Edit it only if it states a
   fallback.
6. Leave `.github/workflows/security-guardrails.yml` unchanged. It sets the variable explicitly.

### Validation

```bash
env -u INGRESS_RATE_LIMIT_PYTHON ./scripts/guardrails/verify-static-security-manifests.sh   # passes using the venv
INGRESS_RATE_LIMIT_PYTHON=/nonexistent/python ./scripts/guardrails/verify-static-security-manifests.sh   # fails with the setup pointer
INGRESS_RATE_LIMIT_PYTHON=/nonexistent/python ./scripts/guardrails/verify-static-security-manifests.sh --self-test   # same failure
env -u INGRESS_RATE_LIMIT_PYTHON ./scripts/guardrails/verify-ingress-rate-limit-config.sh   # passes using the venv
```

Then run the static gate.

## Phase 3: `verify-edge-contract.sh` makes no Kubernetes changes by default (Live)

### Goal

A run with no flags changes no Kubernetes object. Failure injection, the only part that does,
runs only with `--inject-failures`.

### Boundary

The default run may:

- send HTTPS requests through the ingress, including `DELETE` probes and login start
- write and remove the synthetic user and session with `seed-loadtest-users.sh` and
  `teardown-loadtest.sh`. These change data inside the Postgres and Redis pods through
  `kubectl exec`; they create no Kubernetes objects.
- use `kubectl get`, `kubectl logs` and `kubectl exec`

The default run must not create, update, delete or scale any Kubernetes object. Today that covers
everything in the Authorization Failure section's injection: scaling ext-authz, applying and
deleting the temporary `ClusterNetworkPolicy`, scaling Redis, and deleting an ext-authz pod to
reset its CrashLoopBackOff.

### Flag

`--inject-failures` runs the ext-authz scaled-to-zero, hang and Redis-stopped cases and their
recovery, exactly as now.

Without the flag, the Authorization Failure section still runs its read-only checks: the ingress
config dump (timeout, `status_on_error`, no fail-open) and the JSON 401 for a missing and an
unknown session. Every other section runs in full. Print one `[SKIP]` line per skipped injection
case that names the flag, and report the skip count in the summary, so a default run does not
look like full coverage.

### Steps

1. Parse `--inject-failures`. Update `usage` to say what the default run changes and what the
   flag adds.
2. Add a `require_inject_failures` guard that fails the run if the flag is absent. Call it first in
   `apply_block_policy`, `scale_ext_authz`, the Redis scale-down, the pod delete in
   `wait_for_ext_authz_ready`, and `restore_authorization_failure_state`. The guard is the backstop
   for sections that later plans add.
3. In `verify_authorization_failure`, run the config-dump and 401 checks unconditionally. Run the
   injection cases, and the `BLOCK_POLICY_CRD` precheck, only with the flag.
4. In `cleanup`, keep the existing restore logic. It already runs only after an injection.
5. Extend the header comment. A new section must not change Kubernetes objects except behind
   `--inject-failures` and `require_inject_failures`.
6. Update the docs:
   - `scripts/README.md`: the verifier entry and the flag
   - `docs/architecture/session-edge-authorization-pattern.md:294`: the failure cases need
     `--inject-failures`. Check that `docs/architecture/security-architecture.md:278`, `:322` and
     `:606` and `nginx/README.md:195` describe only default-run checks.
   - The `verify-edge-contract.sh` validation steps in plans 02.3 Phase 3, 02.4 Phase 3, 02.5
     Phase 4, 02.6 Phase 6, 02.7 Phase 4 and 02.8 Phase 2 (`docs/plans/security-hardening-02.*.md`,
     split from the original plan 02, Phases 14-16; only 02.5 Phase 4 uses failure injection),
     and `docs/plans/security-hardening-05-closeout-release-handoff.md:161` and `:193`: add the
     flag only where a validation step relies on failure injection. Plan 05's aggregate smoketest
     wiring uses the default run.
   - The evidence file: a dated follow-up note that the earlier runs match today's
     `--inject-failures`. Do not rewrite the recorded commands.

### Validation

1. Run `bash -n` and `shellcheck` on the verifier.
2. Capture a Kubernetes snapshot before and after a default run, and require the two to be
   identical:
   - `kubectl get deploy,sts -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,R:.spec.replicas`
   - `kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,UID:.metadata.uid,RESTARTS:.status.containerStatuses[*].restartCount`
   - `kubectl get clusternetworkpolicy`, which must show none
3. Confirm the fixture was removed: no `.loadtest/session-pool.txt`, and no `usr_loadtest_%` row
   in the `permission` database.
4. For a negative control, temporarily call `scale_ext_authz` from the default path in a scratch
   copy. `require_inject_failures` must fail the run before `kubectl scale` runs.
5. Run with `--inject-failures`. It passes, the step 2 snapshot shows replicas and policies
   restored, and the pass count equals the earlier full run's 185 plus any checks this phase adds.
   Pod UIDs may change in this mode, because ext-authz and Redis pods are recreated.
6. Run the static gate.

## Phase 4: Deny semicolons at any encoding depth (Live)

### Goal

The ingress path-hardening regex covers `;` at any percent-encoding depth, not just up to double
encoding.

### Context

`kubernetes/istio/ingress-path-hardening.yaml` matches `^[^?]*(;|%3[bB]|%253[bB]).*$`, so
`%25253b` and deeper forms pass the ingress. No exploit is shown, because the mesh path rules still
apply. The change has no compatibility cost, and RE2 supports it.

### Steps

1. Change the regex to `^[^?]*(;|%(25)*3[bB]).*$` and update the manifest comment.
2. In the path-hardening scan in `verify-static-security-manifests.sh`, add deny vectors
   `%25253b`, `%25253B` and `%2525253b`. Add allow vectors such as `/api/v1/transactions%2533` and
   `/api/v1/transactions%25` so the pattern does not over-match.
3. Add a self-test fixture `ingress-path-hardening-double-encoded-only.yaml` that uses the old
   regex. The scan must reject it for missing triple-encoded denial. Confirm the existing fixtures
   still fail for their intended reasons.
4. Add `%25253b` and `%25253B` to `SEMICOLON_FORMS` in `verify-edge-contract.sh`. These probes are
   part of the default run.
5. Check `scripts/guardrails/verify-nginx-shared-routes.sh` for comments or probes that list the
   covered forms, and update them.
6. Update the regex and the list of forms in `docs/architecture/security-architecture.md`
   (Ingress Path Hardening), `nginx/README.md` (troubleshooting `;`) and `scripts/README.md`.
7. Let Tilt reapply `istio-ingress-routes`. Then confirm that the live ingress config dump carries
   the new regex.
8. Add a dated follow-up section to the evidence file with the config-dump result and the
   semicolon section's probe count and `rbac.denied` delta.

### Validation

Run the static gate, including `--self-test`. Then run `./scripts/smoketest/verify-edge-contract.sh`
with no flags. Every semicolon form, including the triple-encoded ones, must be
an ingress RBAC 403, and the counter must rise by the probe count. Query strings containing `;`
must still work.

## Not changed

These were reviewed and left as they are:

- Literal `..;` and `.;` segments are resolved by ingress normalization, not denied. The Phase 1
  frontend-shell exception is also unchanged. Both are documented in the evidence file.
- Raw `kubectl kustomize kubernetes/production/apps` output keeps the CSP placeholder. It is
  documented as an intermediate, and `production-routes.sh` resolves it.

## Completion criteria

- No tenant hostname remains in the tree, and `__pycache__/` is ignored and absent.
- No static-suite Python check uses the system interpreter.
- A no-flag `verify-edge-contract.sh` run leaves the Kubernetes snapshot unchanged, and every
  Kubernetes change sits behind `--inject-failures`, enforced by `require_inject_failures`.
- The ingress denies `;` at any encoding depth, and the guardrail, verifier and docs agree.
- The static gate and the live runs listed above pass.
