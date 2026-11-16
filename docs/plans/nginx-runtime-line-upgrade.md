# NGINX Runtime Line Upgrade

Move the NGINX gateway image and the frontend production base image off the unsupported NGINX 1.29
mainline. This resolves the NGINX half of
[`docs/issues/medium-nginx-and-istio-runtime-support-windows.md`](../issues/medium-nginx-and-istio-runtime-support-windows.md).
The Istio half has its own plan, [`istio-runtime-line-upgrade.md`](istio-runtime-line-upgrade.md),
and does not depend on this one.

NGINX uses odd minor numbers for mainline releases and even numbers for stable releases. 1.29
mainline stopped receiving fixes when 1.30.0 stable shipped (2026-04-14 in
`scripts/lib/runtime-support-windows.txt`). On 2026-11-16, <https://nginx.org/en/download.html>
lists mainline 1.31.8 and stable 1.30.6.

The target is the latest `nginxinc/nginx-unprivileged:1.31.x-alpine` image. The reasons are:

- upstream recommends mainline;
- the repository already tracked mainline; and
- mainline receives every fix, while stable receives only critical ones.

Both 1.30 and 1.31 are expected to lose support when 1.32.0 stable ships, which historically
happens in April. Whichever line is chosen therefore enters the report's 90-day `DUE` window around
January 2027. Re-check upstream at execution time.

Current selections:

- `kubernetes/services/nginx-gateway/deployment.yaml`. It is used by local Tilt and by the
  production reference through `kubernetes/production/apps/kustomization.yaml`, and
  `scripts/guardrails/verify-nginx-shared-routes.sh` and `verify-nginx-backend-headers.sh` read
  this image for their disposable containers.
- `../budget-analyzer-web/Dockerfile.production`, the runtime stage of the frontend release image.

Plan-wide constraints:

- Keep the `nginxinc/nginx-unprivileged` Alpine variant, UID/GID 101, the read-only root
  filesystem, the `/tmp` scratch layout, and an `@sha256:` digest pin for a multi-arch index that
  includes `linux/arm64`. Both repositories select the same tag and digest.
- Leave the deliberately unpinned `nginx:1.29.4-alpine` refs in
  `kubernetes/kyverno/tests/fail/workloads.yaml` and
  `tests/security-guardrails/fixtures/fail/unpinned-third-party-image.yaml` unchanged. They are
  negative fixtures for unpinned images, not runtime selections.
- Changing a sibling Dockerfile base image is allowed configuration work. Do not change frontend
  application code.
- Run static-suite verifiers with
  `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python`.
- Cluster mutation is allowed only after the `kind-kind` target checks in `AGENTS.md`. Do not run
  `setup.sh` or any certificate operation.

## Phase 1: Gateway Image Pin And Offline Validation

### Workspace

.

### Goal

Pin `nginx-gateway` to the latest 1.31 `nginx-unprivileged` Alpine image by digest, and prove that
both checked-in NGINX configurations and the shared includes are valid and behave the same on it.

### Scope

`kubernetes/services/nginx-gateway/deployment.yaml`, plus NGINX configuration edits only if 1.30 or
1.31 deprecated or changed a directive that the repository uses.

### Non-goals

No frontend repository changes. No live cluster changes. Documentation prose and the
support-window inventory are Phase 4 work.

### Required context

- `AGENTS.md` Image Pinning and Supply Chain Guardrails
- `nginx/README.md`
- `nginx/nginx.k8s.conf`, `nginx/nginx.production.k8s.conf`, `nginx/includes/`
- `scripts/README.md` entries for `verify-nginx-shared-routes.sh`,
  `verify-nginx-backend-headers.sh`, `verify-production-image-overlay.sh` and
  `check-image-pinning.sh`
- Upstream `https://nginx.org/en/CHANGES-1.30` and `https://nginx.org/en/CHANGES` (1.31 entries)

### Execution steps

1. Find the latest `1.31.x-alpine` tag of `nginxinc/nginx-unprivileged`. Resolve its index digest
   with `docker buildx imagetools inspect`, and confirm that the index contains `linux/arm64` and
   `linux/amd64`.
2. Review the 1.30 and 1.31 change logs for directive removals, default changes or behavior changes
   that affect the directives in the two gateway configs and the includes. Record the outcome in
   the phase summary.
3. Update the deployment image to `nginxinc/nginx-unprivileged:<tag>@sha256:<digest>`.
4. Apply any configuration edits that step 2 requires, in both configs or in the shared includes.
5. Run the validations below. Fix failures without relaxing a check.

### Implementation notes

The two NGINX guardrails extract the image from the deployment, so they exercise the new binary. If
the image fails to pull or the configuration fails `nginx -t` on 1.31, record the cause before
considering the latest 1.30 stable patch as a fallback.

### Validation

```bash
./scripts/guardrails/verify-nginx-shared-routes.sh
./scripts/guardrails/verify-nginx-backend-headers.sh
./scripts/guardrails/check-image-pinning.sh
./scripts/guardrails/verify-production-image-overlay.sh
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
```

### Completion criteria

The deployment selects a digest-pinned 1.31 multi-arch image, and every offline validation above
passes on it.

## Phase 2: Live Local Gateway Verification

### Workspace

.

### Goal

Roll the new gateway image in local Tilt/Kind and prove that routing, the production-smoke frontend
path, browser hardening and the edge contract are unchanged.

### Scope

Live `kind-kind` cluster through Tilt. Repo-owned fixes only for defects that the live proof finds.

### Non-goals

No cluster recreation and no certificate operations. No frontend repository changes.

### Required context

- `docs/architecture/autonomous-ai-execution.md`
- `docs/development/local-environment.md#frontend-reactvite`
- `docs/runbooks/tilt-debugging.md`
- `nginx/README.md#adding-a-new-resource-route` (SPA fallthrough checks)
- `scripts/README.md` entries for the verifiers below

### Execution steps

1. Prerequisite: the human has `tilt up` running and the stack is healthy. If it is not, stop and
   report this rather than starting it yourself.
2. Run `./scripts/bootstrap/check-local-runtime.sh` and apply the `kind-kind` target checks.
3. Wait for Tilt to roll `nginx-gateway`. Confirm that the running pod uses the new digest, then run
   `kubectl exec deployment/nginx-gateway -- nginx -t` and `nginx -v`.
4. Run the live verifiers below. Fix repo-owned defects, re-run Phase 1's offline validations, then
   re-run the live verifiers.

### Implementation notes

Check `kubectl logs deployment/nginx-gateway` for new warnings, not just errors.

### Validation

```bash
./scripts/smoketest/verify-edge-contract.sh
./scripts/smoketest/verify-edge-browser-hardening.sh
./scripts/smoketest/verify-istio-ingress.sh --skip-ingress-rate-limits
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/smoketest/verify-security-guardrails.sh
```

### Completion criteria

`nginx-gateway` runs the new digest with no new warnings, and every live verifier above passes.

## Phase 3: Frontend Production Base Image

### Workspace

../budget-analyzer-web

### Goal

Move the `Dockerfile.production` runtime stage to the same `nginx-unprivileged` tag and digest that
Phase 1 selected, and prove that the arm64 release image still builds and serves.

### Scope

The runtime-stage `FROM` in `Dockerfile.production`, any NGINX directive change in
`nginx.production.conf` required by the Phase 1 change-log review, and any active doc in this
repository that names the NGINX version.

### Non-goals

No application code, `package.json`, Node image or workflow changes.

### Required context

- `AGENTS.md` in `../budget-analyzer-web`
- `docs/development.md` (production image section)
- `docs/dependency-automation.md` (Image Build Check entry for `Dockerfile.production`)
- `Dockerfile.production`, `nginx.production.conf`
- The orchestration `kubernetes/services/nginx-gateway/deployment.yaml` image line, for the exact
  tag and digest (read only)

### Execution steps

1. Copy the exact tag and digest from the orchestration deployment into the runtime `FROM` line.
2. Apply any `nginx.production.conf` edit that the 1.30/1.31 change-log review requires.
3. Build the image for `linux/arm64` with `docker buildx build --platform linux/arm64 -f
   Dockerfile.production .`. Use emulation if the host is not arm64.
4. Run the built image and confirm that `nginx -t` passes, that `/` serves the SPA on port 3000 as
   UID 101, and that an unknown path falls back to the SPA shell as `nginx.production.conf`
   defines.
5. Update any active doc in this repository that names the old NGINX version.

### Implementation notes

The build stage runs on the build platform; only the NGINX runtime stage is arm64. Follow this
repository's AGENTS.md for its own validation commands.

### Validation

A successful `linux/arm64` build, the runtime checks in step 4, and
`rg -n '1\.29\.8' .` returning no active hits.

### Completion criteria

`Dockerfile.production` selects the same digest-pinned image as the orchestration gateway, and the
arm64 image builds and serves.

## Phase 4: Documentation, Support Window And Closeout

### Workspace

.

### Goal

Bring orchestration documentation, the runtime support inventory and the issue in line with the new
NGINX line.

### Scope

`docs/architecture/security-architecture.md` (the `nginx-gateway` runtime hardening bullet), any
other active orchestration doc that names the old NGINX version, the NGINX row in
`scripts/lib/runtime-support-windows.txt`, and the issue file.

### Non-goals

No edits to `docs/archive/`, `docs/decisions/` or `archive/oci/`. No Istio changes. No changes to
the negative fixtures named in the preamble.

### Required context

- `docs/OWNERSHIP.md`
- `docs/dependency-automation.md#operator-routine`
- `docs/issues/medium-nginx-and-istio-runtime-support-windows.md`

### Execution steps

1. Replace the old image reference in `security-architecture.md` and in any other active doc that
   `rg -n '1\.29\.8'` finds.
2. Update the NGINX row in `scripts/lib/runtime-support-windows.txt`: line `1.31`, both
   `selected_in` locations with the new tag, the source URL, and a `support_end` derived from the
   expected 1.32.0 stable release. Explain the derivation in the note column, as the existing row
   does.
3. Update the issue. If Istio is still flagged by `./scripts/repo/report-runtime-support-windows.sh`,
   remove the NGINX content and leave the issue Open. If neither line is flagged, delete the issue
   file, which is the repository convention for resolved issues.

### Implementation notes

Do not introduce new version inventories in docs. Update only the places that already carry the
version.

### Validation

```bash
./scripts/repo/report-runtime-support-windows.sh   # NGINX must not be flagged
rg -n '1\.29\.8' --glob '!docs/archive/**' --glob '!archive/**'   # expect no active hits
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
```

### Completion criteria

The report does not flag NGINX, no active file selects 1.29, and the issue reflects the remaining
scope or is deleted.
