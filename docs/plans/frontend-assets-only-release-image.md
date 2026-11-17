# Frontend Assets-Only Release Image

Remove NGINX from `budget-analyzer-web` so that orchestration owns the only NGINX runtime that
serves the frontend. The frontend release image becomes a static-asset carrier, which is how the
production reference already uses it. After this plan, orchestration's
`kubernetes/services/nginx-gateway/deployment.yaml` is the only NGINX selection in the ecosystem,
and the web repository has no NGINX version to keep in sync.

Why this is safe:

- The production reference never runs the web image's NGINX. `kubernetes/production/apps/kustomization.yaml`
  uses the web release image only as the `web-assets` init container of `nginx-gateway`. That
  container runs `sh -c 'cp -R /usr/share/nginx/html/. /workdir/'`, and the gateway then serves the
  files with `nginx/nginx.production.k8s.conf`.
- The gateway already provides every behavior in web's `nginx.production.conf`: the SPA fallback,
  immutable `/assets/` caching and no-store application routes. The web `/health` endpoint and
  port `3000` server have no orchestration consumer.
- Local Tilt does not use `Dockerfile.production`. The Vite pod uses web's `Dockerfile`, and
  `/_prod-smoke/` uses orchestration's own `nginx/Dockerfile.prod-smoke-assets`, which already
  follows the assets-only pattern.

Starting state, uncommitted: the previous NGINX runtime-line plan pinned the gateway to
`nginxinc/nginx-unprivileged:1.31.7-alpine` and deleted the runtime-support issue. Its web edit,
which bumped the `Dockerfile.production` NGINX stage to 1.31.7, is superseded by Phase 1 here.

Frontend release image contract. Both phases must keep this exact contract:

- Built from `budget-analyzer-web/Dockerfile.production` and published for `linux/arm64`.
- Contains the root-mounted `npm run build` output (`index.html` at the root, plus `assets/`) at
  `/usr/share/nginx/html`. The path name is historical. It is kept so that the unchanged overlay
  command works with both the pinned historical baseline image and future releases.
- Provides POSIX `sh` and `cp` on `PATH`.
- Copies successfully as UID/GID `101` with a read-only root filesystem, all capabilities dropped
  and no privilege escalation. The image's default user is `101:101`.
- Contains no NGINX or other server and exposes no ports.

Plan-wide constraints:

- Keep `@sha256:` digest pins for a multi-arch index that includes `linux/arm64`.
- Do not change frontend application code, `package.json`, `package-lock.json` or the Node build
  stage.
- Do not change the production overlay's init-container command or path, the pinned historical
  release images, or the reference baseline metadata. Updating the baseline is the human-owned
  coordinated release in `kubernetes/production/README.md#release-order`.
- No live cluster changes are needed, and no certificate operations are allowed.
- Run static-suite verifiers with
  `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python`.
- Do not edit or delete files under `docs/plans/`, `docs/archive/`, `docs/decisions/` or
  `archive/oci/`.

## Phase 1: Assets-Only Web Release Image

### Workspace

../budget-analyzer-web

### Goal

Replace the NGINX runtime stage of `Dockerfile.production` with a minimal, digest-pinned Alpine
asset stage that satisfies the contract in the plan preamble. Remove every NGINX-specific file and
reference that describes this repository's image.

### Scope

- `Dockerfile.production` (the runtime stage only)
- Delete `nginx.production.conf`
- `.github/workflows/image-build-check.yml` (remove `nginx.production.conf` from the path filter)
- `docs/development.md` (the Production Container section)
- `docs/dependency-automation.md` (update discovery and the Image Build Check entry)
- Any other active doc in this repository that describes this repository's image as running NGINX

### Non-goals

- No application code, `package.json`, lockfile, Node image, build stage or `publish-release.yml`
  changes.
- No changes to `Dockerfile` or `Dockerfile.dev`.
- Do not change text that describes orchestration's NGINX gateway in the request flow, such as the
  architecture and authentication diagrams or `vite.config.ts` comments.

### Required context

- `AGENTS.md`, including Prerequisites First and the Validation section
- `docs/development.md#production-container`
- `docs/dependency-automation.md` (Update discovery and Image build check)
- `Dockerfile.production`, `nginx.production.conf`, `.github/workflows/image-build-check.yml`,
  `.dockerignore`
- The frontend release image contract in this plan's preamble

### Execution steps

1. Prerequisite: run `docker buildx version`. If buildx is unavailable, stop and report it as a
   missing development-VM prerequisite owned by `../workspace`. Do not download, install or run a
   substitute buildx binary, and do not change binfmt registration.
2. Find the latest Alpine stable patch release on Docker Hub (`alpine:<major>.<minor>.<patch>`).
   Resolve its index digest with `docker buildx imagetools inspect` and confirm that the index
   includes `linux/arm64` and `linux/amd64`.
3. Replace the runtime stage of `Dockerfile.production`. Use
   `FROM alpine:<tag>@sha256:<digest>`, copy `/app/dist` from the build stage to
   `/usr/share/nginx/html`, and set `USER 101:101`. Do not add `EXPOSE`, a server command or a
   healthcheck. Keep the `# syntax=` line and the build stage unchanged.
4. Delete `nginx.production.conf`, and remove it from the Image Build Check path filter.
5. Rewrite the Production Container section of `docs/development.md`:
   - The release image is an assets-only carrier for the built bundle.
   - Orchestration's `nginx-gateway` copies the bundle into the gateway and serves it.
   - The gateway owns the SPA fallback, caching and security headers. Link to the orchestration
     NGINX README with the `https://github.com/budgetanalyzer/orchestration/blob/main/...` style
     that this repository already uses for cross-repository links.
   - State the asset path and the `sh`/`cp` and UID `101` requirements once, as the contract this
     repository must preserve.
6. Update `docs/dependency-automation.md`. Renovate discovers Node and Alpine images, not NGINX.
   The `Dockerfile.production` Image Build Check entry proves the arm64 Alpine base manifest, the
   asset copy and the coverage-gated build, not an NGINX configuration.
7. Run `rg -n -i 'nginx' --glob '!node_modules/**' --glob '!dist/**' --glob '!coverage/**'
   --glob '!tmp/**' --glob '!package-lock.json' .`. Confirm that every remaining hit describes
   orchestration's gateway or the historical asset path, not an NGINX in this repository's image.

### Implementation notes

- `/usr/share/nginx/html` stays because the production overlay copies from that path. Changing it
  is a coordinated orchestration release decision, not part of this plan.
- Files that `COPY` creates are root-owned and world-readable, which UID `101` can copy. Do not
  add `chown` or a `RUN` step unless the contract proof shows a permission failure.
- The runtime stage has no `RUN` step, so an arm64 build needs no emulation. The `sh`/`cp`
  contract proof runs on the native platform's variant of the same Dockerfile and base index.
  BusyBox `sh` and `cp` behave the same on both architectures. CI's Image Build Check proves the
  arm64 build again.

### Validation

```bash
docker buildx build --platform linux/arm64 -f Dockerfile.production .
docker buildx build --platform linux/amd64 -f Dockerfile.production \
  --load -t budget-analyzer-web:assets-contract .

docker image inspect budget-analyzer-web:assets-contract \
  --format '{{.Config.User}} {{json .Config.ExposedPorts}} {{.Os}}/{{.Architecture}}'
# expect: 101:101 null linux/amd64

out=$(mktemp -d) && chmod 0777 "$out"
docker run --rm --read-only --user 101:101 --cap-drop ALL \
  --security-opt no-new-privileges -v "$out:/workdir" \
  budget-analyzer-web:assets-contract sh -c 'cp -R /usr/share/nginx/html/. /workdir/'
test -f "$out/index.html" && ls "$out/assets"

docker run --rm budget-analyzer-web:assets-contract sh -c '! command -v nginx'
```

Also confirm that every `/assets/` file referenced by `$out/index.html` exists in `$out/assets`.
Then remove the temporary image and directory, and run `git diff --check`. Format the changed
Markdown and YAML files with the repository's Prettier configuration. Because the change touches
a workflow, also run the workflow-change gates in `AGENTS.md` Validation. Report any gate that
cannot run.

### Completion criteria

- `Dockerfile.production` builds for `linux/arm64` from a digest-pinned Alpine base.
- The image meets every point of the preamble contract, proven by the commands above.
- `nginx.production.conf` is deleted, and no active document describes an NGINX in this
  repository's image.
- Application code and npm manifests are unchanged.

## Phase 2: Orchestration Sole NGINX Ownership

### Workspace

.

### Goal

Make the orchestration inventory and documentation reflect that `nginx-gateway` is the only NGINX
selection, and document the frontend release image contract in its owner document.

### Scope

- The NGINX row in `scripts/lib/runtime-support-windows.txt`
- The owner document for the production frontend-delivery and asset-image contract (see step 2)
- Summaries that describe the web release image as NGINX-based, including the
  `budget-analyzer-web` bullet in `docs/ci-cd.md`

### Non-goals

- No changes to `kubernetes/production/apps/` manifests, the `web-assets` init-container command or
  path, pinned release images or reference baseline metadata.
- No gateway image change. The 1.31.7 pin is already in place.
- No NGINX configuration, Tiltfile, live cluster or web repository changes.

### Required context

- `docs/OWNERSHIP.md`
- `nginx/README.md#checked-in-production-route-variant`
- `kubernetes/production/README.md` (the near-identical table, Application And Image Baseline and
  Release Order)
- `kubernetes/production/apps/kustomization.yaml` (the `nginx-gateway` patch, read only)
- `docs/ci-cd.md` (the source-release bullets for `budget-analyzer-web`)
- `docs/dependency-automation.md#operator-routine`
- The frontend release image contract in this plan's preamble

### Execution steps

1. Prerequisite: read `../budget-analyzer-web/Dockerfile.production` and confirm that the
   runtime stage is the Phase 1 Alpine asset stage and that `nginx.production.conf` is gone. If
   not, stop and report it. Do not edit the web repository.
2. Use `docs/OWNERSHIP.md` to choose the owner for the production frontend-delivery contract. If
   nothing more specific owns it, use `nginx/README.md#checked-in-production-route-variant`, which
   already states the `/usr/share/nginx/html` expectation. In that owner, replace the expectation
   with the preamble contract:
   - the overlay copies the release image's `/usr/share/nginx/html` in an init container with
     `cp -R` as UID `101`;
   - the release image is assets-only; and
   - `nginx-gateway` is the only NGINX that serves the frontend.
3. Update the summaries that conflict with the owner, and link to it instead of repeating it. The
   `budget-analyzer-web` bullet in `docs/ci-cd.md` should say that `Dockerfile.production` builds
   the assets-only release image. Change the Workloads and Frontend delivery rows of the
   near-identical table in `kubernetes/production/README.md` only if their wording conflicts.
4. Change the NGINX row's `selected_in` to
   `orchestration: kubernetes/services/nginx-gateway/deployment.yaml`. Remove the web repository
   and the patch tag. Keep the line, `support_end`, source and derivation note.
5. Search the active tree for statements that the frontend release image runs or configures NGINX:
   `rg -n 'nginx\.production\.conf|Dockerfile\.production' --glob '!docs/archive/**'
   --glob '!archive/**' --glob '!docs/plans/**' --glob '!.ai-session-handler/**' .` plus a review
   of every hit that mentions both `budget-analyzer-web` and NGINX. Fix active hits. Leave
   historical documents unchanged; for example, `docs/architecture/deployment-architecture-gcp.md`
   is marked historical.

### Implementation notes

The pinned historical web image (`0.0.15`) still contains NGINX 1.29. Nothing executes it, and it
is reference-only until the coordinated release in `kubernetes/production/README.md#release-order`
replaces it. The unchanged copy command works with both the old and the new image. Do not add a
version inventory or describe that image's internals in documentation.

### Validation

```bash
./scripts/repo/report-runtime-support-windows.sh
rg -n 'budget-analyzer-web' scripts/lib/runtime-support-windows.txt   # Node.js row only
rg -n 'nginx\.production\.conf' --glob '!docs/archive/**' --glob '!archive/**' \
  --glob '!docs/plans/**' --glob '!.ai-session-handler/**' .         # expect no hits
./scripts/guardrails/verify-production-image-overlay.sh
./scripts/guardrails/check-image-pinning.sh
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
git diff --check
```

Also verify that every link and anchor changed in this phase resolves.

### Completion criteria

- The runtime-support inventory lists NGINX only for the orchestration gateway, and the report
  flags nothing.
- One orchestration owner document states the frontend release image contract, and the summaries
  link to it without contradicting it.
- No active orchestration document says the web release image runs NGINX.
- The production overlay and the static suite pass unchanged.
