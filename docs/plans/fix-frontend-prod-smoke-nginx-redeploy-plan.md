# Fix Frontend Production-Smoke NGINX Redeploy Plan

Replace the fragile `local_resource` to staging-directory to `docker_build` handoff for the local
`/_prod-smoke/` frontend bundle with one atomic Tilt image build. A successful production-smoke
build must publish a new `budget-analyzer-web-prod-smoke` image through Tilt's image target, update
the `nginx-gateway` Deployment image reference, and replace the NGINX pod so its init container
copies the current bundle into the pod-local `emptyDir` volume.

This plan changes only the orchestration repository. It does not change frontend service code,
production release images, production NGINX routing, or the normal Vite/HMR development path.

## Phase 1: Make The Production-Smoke Image Build Atomic

### Workspace

.

### Goal

Make the frontend production-smoke compilation and static-asset image construction one Tilt image
target so Tilt cannot consider the frontend build complete without also producing the image that
is mapped into `nginx-gateway`.

### Scope

Update `Tiltfile`, add a small digest-pinned Dockerfile for the local production-smoke asset image,
and align the executable Tilt-root and image-pinning inventories. Update the affected prerequisite
script message while preserving its existing checks.

### Non-goals

Do not change sibling `budget-analyzer-web` files, Kubernetes workload manifests, NGINX route
behavior, the production deployment overlay, frontend release-image construction, or the regular
`budget-analyzer-web` Vite image. Do not add a rollout-restart command, timestamp or random stamp,
mutable image-tag workaround, live-cluster patch, or second Tilt process.

### Required context

Read `AGENTS.md`, `docs/development/getting-started.md`,
`docs/development/local-environment.md`, `nginx/README.md`,
`kubernetes/services/nginx-gateway/deployment.yaml`, `scripts/README.md`,
`scripts/lib/image-pinning-targets.txt`, `scripts/lib/tilt-intentional-root-resources.txt`, and the
frontend production-smoke section of `Tiltfile`. Run
`./scripts/bootstrap/check-tilt-prerequisites.sh` before implementation. If the sibling frontend
checkout, supported Node/npm versions, or its local `node_modules` prerequisite is missing, stop
and report the missing prerequisite instead of changing the build design to conceal it.

### Execution steps

1. Add a narrowly scoped Dockerfile under `nginx/` for the
   `budget-analyzer-web-prod-smoke` asset image. Preserve the current digest-pinned Alpine base,
   `/prod-smoke` working directory, and static bundle copy contract used by the NGINX init
   container.
2. Replace `budget-analyzer-web-prod-smoke-build` plus its separate `docker_build` with one
   `custom_build` image target. Its command must run the existing npm/node_modules preflight,
   execute `npm run build:prod-smoke` in the sibling frontend repository, and build the asset image
   from the completed `dist/` directory tagged with Tilt's quoted `$EXPECTED_REF`.
3. Give the custom image target direct `deps` on every existing frontend production-smoke input
   and on the new asset Dockerfile. Keep optional Vite environment files watched, use dynamically
   resolved repository paths, and do not hardcode an absolute workspace path.
4. Remove the obsolete production-smoke local resource from the `nginx-gateway` `resource_deps`.
   Retain `istio-injection` and rely on the image map, not initialization ordering, to update the
   Deployment after successful image builds.
5. Remove the deleted local resource from `scripts/lib/tilt-intentional-root-resources.txt`, add
   the new Dockerfile to `scripts/lib/image-pinning-targets.txt`, and update only the stale resource
   name/description in `scripts/bootstrap/check-tilt-prerequisites.sh`.

### Implementation notes

Tilt `resource_deps` establishes startup readiness and selection, not recurring build dependency
propagation. The custom build must therefore own both compilation and image creation in one
command. Use `$EXPECTED_REF` rather than a fixed `:latest` tag so Tilt can verify, content-address,
and inject the result normally. Keep the image associated with the existing
`budget-analyzer-web-prod-smoke:latest` manifest reference; the checked-in Kubernetes manifest and
Kyverno local-image policy should not need changes.

The init-container and `emptyDir` design intentionally requires an NGINX pod replacement. Do not
attempt to solve this with `nginx -s reload`, because reloading cannot rerun the init container or
repopulate the volume.

### Validation

Run:

```bash
bash -n scripts/bootstrap/check-tilt-prerequisites.sh
shellcheck scripts/bootstrap/check-tilt-prerequisites.sh
./scripts/guardrails/check-image-pinning.sh
./scripts/guardrails/check-tilt-resource-roots.sh
tilt alpha tiltfile-result --context kind-kind | jq '
  .Manifests[]
  | select(.Name == "nginx-gateway" or .Name == "budget-analyzer-web-prod-smoke-build")
  | {Name, ResourceDependencies, ImageTargets, DeployTarget}'
git diff --check
```

Inspect the parsed result rather than accepting command success alone. It must contain no
`budget-analyzer-web-prod-smoke-build` manifest; `nginx-gateway` must own an image target selected
by `budget-analyzer-web-prod-smoke`; the image target must be a custom build with the frontend
inputs and new Dockerfile as dependencies; and the deploy target must retain the
`budget-analyzer-web-prod-smoke` image map. Confirm all `FROM` references in the new Dockerfile are
digest-pinned.

### Completion criteria

The old local resource and staging-directory file-watch handoff are gone, the production-smoke
compilation and image build are one successful-or-failed Tilt operation, the NGINX Deployment still
maps the asset image, the prerequisite script passes Bash and ShellCheck validation, and the Tilt
and supply-chain guardrails pass. No sibling repository or live Kubernetes object has been
modified.

## Phase 2: Document And Prove Incremental NGINX Replacement

### Workspace

.

### Goal

Update the canonical local-development documentation and prove that changing an input of the new
asset image target causes Tilt to publish a changed image reference and Kubernetes to replace the
NGINX pod with the current production-smoke bundle.

### Scope

Update the canonical local-environment owner document first, then its NGINX and agent-context
summaries. Run the full static checks relevant to the changed files and a focused live Tilt/Kind
rollout proof against the trusted local-development cluster.

### Non-goals

Do not edit sibling frontend source, generate or rotate TLS certificates, bypass certificate
verification, restart unrelated workloads, weaken admission or network policy, expose
observability, or perform git write operations. Do not start Tilt inside the agent container when
the supported host-managed Tilt control plane is unavailable.

### Required context

Read `docs/OWNERSHIP.md`, `docs/development/local-environment.md`, `nginx/README.md`, `AGENTS.md`,
`docs/agents-md-checkstyle.md`, `docs/decisions/003-pattern-based-claude-md.md`, and
`docs/architecture/autonomous-ai-execution.md`. Re-run
`./scripts/bootstrap/check-tilt-prerequisites.sh` and confirm the Phase 1 diff is present and its
focused checks pass.

Live validation requires the existing host-managed Tilt server to be running and reachable by the
execution environment. Before any cluster-affecting validation, prove that the current context and
referenced cluster are `kind-kind`, the Kubernetes API endpoint is loopback-only, and the
`kind-control-plane` node exists. If any boundary check fails, or the host Tilt API cannot be
reached, stop and report the exact prerequisite instead of starting another Tilt instance or
declaring runtime validation complete.

### Execution steps

1. Update `docs/development/local-environment.md` first because it owns local live-update
   mechanics. Replace the two-resource staging description with the atomic custom image build,
   retain the host Node/npm/node_modules prerequisite, and explain that a successful changed image
   causes an NGINX pod replacement because assets are copied by an init container.
2. Update `nginx/README.md` to summarize the new build path and correct the `/_prod-smoke/`
   troubleshooting checklist. Remove commands and resource names that refer to the deleted local
   resource or orchestration-owned staging directory.
3. Update `AGENTS.md` in the active local-development workflow section with one stable guardrail:
   preserve the production-smoke build as an atomic Tilt image target mapped to NGINX. Keep exact
   mechanics in the canonical local-environment document and follow the active checkstyle.
4. With the host Tilt server reachable, inspect Tilt's UIResource, ImageMap, and FileWatch objects
   to confirm that the NGINX resource owns the production-smoke image and that the new asset
   Dockerfile plus sibling frontend inputs are watched directly.
5. Record the current NGINX pod UID, ReplicaSet, init-container image reference, and
   `/_prod-smoke/index.html` hash. Make a temporary, harmless OCI `LABEL` change to the new
   orchestration-owned asset Dockerfile, wait for Tilt to rebuild and for
   `kubectl rollout status deployment/nginx-gateway` to succeed, then prove that the image
   reference, ReplicaSet, and pod UID changed and that the pod's served bundle matches the locally
   built frontend `dist/` bundle.
6. Restore the temporary Dockerfile label with `apply_patch`, wait for Tilt to return the resource
   to `UpToDate`, and verify the final working tree contains only the intended implementation and
   documentation changes. Do not use git checkout/reset or leave a validation-only label behind.

### Implementation notes

The temporary Dockerfile label is only a controlled trigger for the orchestration-owned image
input; it must be removed before completion. It avoids writing sibling service code while still
proving the complete image-map-to-Deployment rollout path. Direct FileWatch inspection supplies
the complementary proof that normal frontend production-smoke inputs feed the same custom build.

Use Kubernetes pod and image state as evidence. A green custom build without a changed NGINX
ReplicaSet is not sufficient. Likewise, a changed pod without matching local and in-pod bundle
hashes is not sufficient.

### Validation

Run the repository checks and focused runtime proof:

```bash
bash -n scripts/bootstrap/check-tilt-prerequisites.sh
shellcheck scripts/bootstrap/check-tilt-prerequisites.sh
./scripts/guardrails/check-image-pinning.sh
./scripts/guardrails/check-tilt-resource-roots.sh
./scripts/guardrails/verify-static-security-manifests.sh
tilt alpha tiltfile-result --context kind-kind >/dev/null
kubectl rollout status deployment/nginx-gateway --timeout=180s
sha256sum ../budget-analyzer-web/dist/index.html
kubectl exec deployment/nginx-gateway -c nginx -- \
  sha256sum /usr/share/nginx/html/_prod-smoke/index.html
git diff --check
git status --short
```

Also inspect `tilt get uiresources`, the relevant FileWatch/ImageMap objects, Deployment revision,
ReplicaSet, pod UID, and init-container image before and after the controlled trigger. Run
`./scripts/smoketest/verify-edge-browser-hardening.sh` only after satisfying its documented local
TLS trust and API-test prerequisites; never substitute `--insecure`, HTTP, or another TLS bypass.

### Completion criteria

Canonical and summary documentation accurately describe the atomic build, all static and shell
checks pass, Tilt directly watches the frontend production-smoke inputs, a controlled changed image
causes a new NGINX ReplicaSet and pod, and the served bundle hash matches the completed frontend
build. The temporary validation change is removed, no sibling repository was modified, and no
manual live-cluster drift remains.
