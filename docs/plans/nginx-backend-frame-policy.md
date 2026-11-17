# NGINX Backend Frame Policy And Shared Docker Harness Plan

Resolve two issues in one change:
- `docs/issues/low-duplicate-x-frame-options.md` is the defect that justifies
  the work.
- `docs/issues/info-duplicated-nginx-docker-harnesses.md` is the maintenance
  refactor. Its own condition is "the next time either script changes", and the
  frame-policy proof changes `scripts/guardrails/verify-nginx-backend-headers.sh`.

The refactor goes first so the new proof lands on the shared harness:
1. Move the duplicated container lifecycle in
   `scripts/guardrails/verify-nginx-backend-headers.sh` and
   `scripts/guardrails/verify-nginx-shared-routes.sh` into
   `scripts/lib/nginx-docker-harness.sh` without changing behavior.
2. Add `proxy_hide_header X-Frame-Options;` to
   `nginx/includes/backend-headers.conf` so the edge's `SAMEORIGIN` is the
   only value on API responses. Prove it offline in the backend header harness.
3. Prove it on the live local stack through the ingress, then close the
   issues.

Evidence captured while planning (2026-11-17):
- On the running local stack, a request from inside the `nginx-gateway` pod to
  `currency-service` returned `x-frame-options: DENY`, the Spring Security
  default. The same request through NGINX (`127.0.0.1:8080/api/v1/currencies`)
  returned both `x-frame-options: DENY` and `X-Frame-Options: SAMEORIGIN`. That
  confirms the issue.
- The backend header harness passed with 7 passed and 0 failed, and the shared
  routes harness with 26 passed and 0 failed.
- The static NGINX backend header scan in
  `scripts/guardrails/verify-static-security-manifests.sh`
  (`scan_nginx_backend_header_contract`) inspects only `proxy_set_header`
  lines for `Cookie`, `Authorization` and `X-Forwarded-Proto`. A
  `proxy_hide_header` line does not trip it.
- No aggregate smoketest, Tilt resource or GitHub workflow invokes either
  NGINX harness.

Out of scope. Record these as follow-up candidates and do not fix them here:
- API responses also carry a second, identical
  `X-Content-Type-Options: nosniff` from the backends.
- API responses carry the backends' `X-XSS-Protection: 0`.

Do not change Spring defaults in `service-common` for this; the edge owns frame
policy. Follow `AGENTS.md`:
- Shell scripts must pass `bash -n` and `shellcheck`.
- Run the static suite with the pinned PyYAML interpreter.
- Run cluster mutations only after the local Kind target checks pass.
- Run no git write commands.

## Phase 1: Shared NGINX Docker Harness Library

### Workspace

.

### Goal

Create `scripts/lib/nginx-docker-harness.sh` and migrate both NGINX Docker
harnesses to it. Both must keep the same probes, assertions, output lines, exit
codes, `--help` text and container isolation flags. Then delete the
duplication issue.

### Scope

- New file `scripts/lib/nginx-docker-harness.sh`
- `scripts/guardrails/verify-nginx-backend-headers.sh`
- `scripts/guardrails/verify-nginx-shared-routes.sh`
- `scripts/README.md`: add one sentence to each of the two harness bullets
- Delete `docs/issues/info-duplicated-nginx-docker-harnesses.md`

### Non-goals

- Any assertion, fixture or NGINX include change. Frame policy is Phase 2.
- Moving `pass`/`fail`, summary printing, option parsing, fixtures or probes
  into the library. The same two-line `pass`/`fail` helpers appear in about
  ten other verifiers in `scripts/`, so they stay per script.
- Adding container labels, names, options or environment overrides
- Refactoring `scripts/guardrails/verify-redis-session-aof-replay.sh` or other
  Docker harnesses

### Required context

- `docs/issues/info-duplicated-nginx-docker-harnesses.md`
- `scripts/guardrails/verify-nginx-backend-headers.sh`
- `scripts/guardrails/verify-nginx-shared-routes.sh`
- `scripts/lib/local-kubernetes-target.sh` and `scripts/lib/guardrail-python.sh`
  for the library header style and `BASH_SOURCE`-relative repo resolution
- `scripts/README.md`: `## Shared Lib` and the two harness bullets
- `scripts/smoketest/verify-edge-contract.sh` lines 24-27 for the justified
  `# shellcheck disable=SC1091` comment used on `source` lines

### Execution steps

1. Capture baselines before editing. Run both harnesses and save each one's
   combined output to a `mktemp -d` directory outside the repository. They must
   exit `0`, with 7 passed and 0 failed for backend headers and 26 passed and 0
   failed for shared routes. If either fails, stop and report it.
2. Create `scripts/lib/nginx-docker-harness.sh` with this contract:
   - Shebang `#!/bin/bash`. Add a header comment that says what the file is for
     and "Source this file; do not execute it directly." Do not call `set` or
     install a trap when the file is sourced.
   - Derive `NGINX_HARNESS_REPO_DIR` from `BASH_SOURCE`. Use it only for
     repo-relative error paths.
   - Initialize the globals `NGINX_HARNESS_CONTAINER_ID=""` and
     `NGINX_HARNESS_WORK_DIR=""`.
   - `nginx_harness_require_docker`: print
     `ERROR: required command not found: docker` to stderr and exit 1 when
     Docker is missing.
   - `nginx_harness_image <deployment-file>`: use the current `sed`
     extraction and `@sha256:[0-9a-f]{64}$` check. Print the image ref. On
     failure, print the current error with the repo-relative path and exit 1.
   - `nginx_harness_make_work_dir`: run `mktemp -d` and `chmod 755`, then set
     `NGINX_HARNESS_WORK_DIR`. The caller must not run it in a command
     substitution.
   - `nginx_harness_start <image> <ready-url> [extra docker run args...]`:
     run `docker run --detach --network none --read-only --tmpfs /tmp
     --entrypoint nginx`, then the extra args, then
     `<image> -g 'daemon off;'`. Store the ID in `NGINX_HARNESS_CONTAINER_ID`
     before polling. Poll `<ready-url>` with
     `docker exec <id> curl --silent --fail --max-time 2 -o /dev/null`
     20 times, 0.5 s apart. On timeout, print
     `ERROR: disposable NGINX did not start`, then the `docker logs`, and exit
     1. The caller must not run it in a command substitution.
   - `nginx_harness_stop`: when an ID is set, run `docker rm -f` on it (ignore
     errors) and clear the ID.
   - `nginx_harness_cleanup`: `set +e`, call `nginx_harness_stop`, and remove
     `NGINX_HARNESS_WORK_DIR` if it is set. Callers install
     `trap nginx_harness_cleanup EXIT`.
3. Migrate `verify-nginx-backend-headers.sh`:
   - Source the library and delete the local `cleanup`, `nginx_image` and
     `start_container`, and the `WORK_DIR`/`CONTAINER_ID` globals.
   - In `main`:
     - Call `nginx_harness_require_docker`.
     - Get the image with `image=$(nginx_harness_image "${DEPLOYMENT_FILE}")`.
     - Call `nginx_harness_make_work_dir`.
     - Start with `nginx_harness_start "${image}"
       http://127.0.0.1:9000/ready` plus the three current `-v` mounts, in
       order.
   - Use the `NGINX_HARNESS_*` globals in `write_fixture` and `probe`.
4. Migrate `verify-nginx-shared-routes.sh`:
   - Source the library and delete the local `stop_container`, `cleanup`,
     `nginx_image` and `start_container`, and the `WORK_DIR`/`CONTAINER_ID`
     globals. This script uses no work directory.
   - In `verify_config`, start with `nginx_harness_start "${image}"
     http://127.0.0.1:8080/health` plus the current
     `--add-host "${RESOLVER_HOST}:127.0.0.1"`, config mount and includes
     mount, in order. End the function with `nginx_harness_stop`.
   - Use `NGINX_HARNESS_CONTAINER_ID` in `probe` and the `nginx -t` calls.
5. In `scripts/README.md`, add one sentence to each harness bullet. It should
   say the harness uses `lib/nginx-docker-harness.sh` for image selection and
   the disposable container lifecycle.
6. Delete `docs/issues/info-duplicated-nginx-docker-harnesses.md`. Then
   `rg -n "info-duplicated-nginx-docker-harnesses" --glob '!docs/plans/**'`
   must return nothing.

### Implementation notes

- Under `set -e`, `image=$(nginx_harness_image ...)` stops the caller on
  failure, as the current `nginx_image` does.
- `nginx_harness_start` assigns the container ID before polling and runs in the
  caller's shell, so the `EXIT` trap removes a container whose readiness check
  failed.
- In the shared routes harness, `nginx_harness_stop` clears the ID before the
  next config starts a new container.

### Validation

- Run `bash -n` and `shellcheck` (plain, then `-x` from the repo root) on the
  library and both harnesses. All must be clean.
- `rg -n '^(cleanup|nginx_image|start_container|stop_container)\(\)' scripts/guardrails/verify-nginx-*.sh`
  returns nothing.
- Check that no container is left behind. Record
  `docker ps -aq --filter "ancestor=<image>" | wc -l` before and after every
  run below. The count must not change. Get the image from the `sed`
  extraction on `kubernetes/services/nginx-gateway/deployment.yaml`. The
  `ancestor` filter matches digest-pinned refs.
- Both harnesses exit `0`, with 7 passed and 0 failed and 26 passed and 0
  failed. Their `[PASS]`/`[FAIL]`/`[INFO]`, section, banner and summary lines
  `diff` clean against the step 1 baselines.
- `--help` exits `0` with unchanged text for both scripts, and an unknown
  option exits `1`.
- Negative check for the image guard: make a temp copy of the deployment file
  with a tag-only image. Then
  `bash -c 'source scripts/lib/nginx-docker-harness.sh; nginx_harness_image "$1"' _ <tmpfile>`
  must exit `1` with the "is not digest-pinned" error.
- Negative check for readiness and cleanup: in a temp driver script outside the
  repo, source the library, run `trap nginx_harness_cleanup EXIT`, and call
  `nginx_harness_start "<image>" http://127.0.0.1:9999/ready` with no extra
  mounts. It must exit non-zero, print "disposable NGINX did not start", and
  leave the container count unchanged.

### Completion criteria

- Both harnesses use the library for image selection, the Docker check,
  container start and readiness, stop, and cleanup. Neither defines those
  helpers locally.
- Both pass, and their output matches the baselines. The negative checks passed
  and no containers were left behind.
- `scripts/README.md` names the library in both harness bullets, and the
  duplication issue file is deleted.
- `nginx/includes/`, the NGINX configs and `docs/issues/low-duplicate-x-frame-options.md`
  are unchanged.

## Phase 2: Hide Backend X-Frame-Options And Prove It Offline

### Workspace

.

### Goal

Make NGINX drop the backends' `X-Frame-Options` on every API route, so the
edge's server-level `SAMEORIGIN` is the only value. First show that the
extended backend header harness fails without the fix, then show it passes with
the fix.

### Scope

- `scripts/guardrails/verify-nginx-backend-headers.sh`: extend the fixture,
  probe and assertions
- `nginx/includes/backend-headers.conf`: add `proxy_hide_header X-Frame-Options;`
- `nginx/README.md`: the `backend-headers.conf` bullet
- `docs/architecture/security-architecture.md`: the browser header paragraph
  that covers the CSP profiles and `X-XSS-Protection`
- `scripts/README.md`: the backend header harness bullet

### Non-goals

- Reloading NGINX, restarting pods or any other cluster mutation (Phase 3)
- Live verifier changes (Phase 3)
- Hiding `X-Content-Type-Options` or `X-XSS-Protection`, or changing any
  `security-headers-*.conf` include
- Adding a static guardrail rule for `proxy_hide_header`. The offline harness
  and live verifier are the proofs.
- Changing Spring Security defaults in sibling repos

### Required context

- `docs/issues/low-duplicate-x-frame-options.md`
- `nginx/includes/backend-headers.conf` and
  `nginx/includes/security-headers-strict-csp.conf`
- `nginx/includes/api-routes.conf`. Its locations declare no `add_header`, so
  they inherit server-level security headers.
- `scripts/guardrails/verify-nginx-backend-headers.sh` (migrated in Phase 1)
- `scripts/lib/nginx-docker-harness.sh`
- `nginx/README.md` `## Include Files` area, `backend-headers.conf` bullet
- `docs/architecture/security-architecture.md`, the CSP profile paragraph near
  "No profile sends the deprecated `X-XSS-Protection` header"

### Execution steps

1. Extend the harness fixture:
   - In `echo.js`, set the response header `X-Frame-Options: DENY` before
     returning, to stand in for the Spring Security default.
   - In the `127.0.0.1:8080` server only, add
     `add_header X-Frame-Options "SAMEORIGIN" always;` at server level. Add a
     comment saying it stands in for the server-level
     `security-headers-*-csp.conf` include.
2. Extend `probe`, or add a sibling helper, so the caller can read the response
   headers as well as the echo body. Existing request-header parsing
   (`has_name`, `value_of`) and the printed header-name list must stay
   unchanged. Count response header lines case-insensitively and strip `\r`.
3. Add two assertions:
   - Control location: the response carries two `X-Frame-Options` values, one
     `DENY` and one `SAMEORIGIN`. This proves the stand-in can see the
     conflict.
   - Include location: the response carries exactly one `X-Frame-Options`, and
     its value is `SAMEORIGIN`.
4. Red check: run the harness before changing the include. It must exit `1`,
   with exactly the include-location frame assertion failing (8 passed, 1
   failed). Save this output outside the repository as evidence.
5. Add `proxy_hide_header X-Frame-Options;` to `backend-headers.conf` with a
   short comment. The comment should say that backends send their framework
   default, which conflicts with the edge policy, and that the edge owns frame
   policy through the security-header includes and CSP `frame-ancestors`.
6. Green check: the harness must exit `0` with 9 passed and 0 failed.
7. Update docs:
   - `nginx/README.md` `backend-headers.conf` bullet: say the include also
     hides the backends' `X-Frame-Options` and that the harness proves it.
   - `docs/architecture/security-architecture.md` browser header paragraph:
     add one sentence saying the edge owns frame policy and NGINX hides backend
     `X-Frame-Options` so API responses carry only `SAMEORIGIN`.
   - `scripts/README.md` backend header harness bullet: add the frame-policy
     assertion.

### Implementation notes

- If Tilt is running, it watches `nginx/includes` and updates the
  `nginx-gateway-includes` ConfigMap when the include changes. The running
  NGINX keeps its loaded config until it is reloaded, so the live stack does
  not change behavior in this phase unless the pod restarts. Do not reload it
  here.
- `proxy_hide_header` affects only the response from the upstream. Server-level
  `add_header ... always` headers are still added afterwards.

### Validation

- `bash -n` and `shellcheck` (plain and `-x`) on the harness and library are
  clean.
- Red run: 8 passed and 1 failed (step 4). Green run: 9 passed and 0 failed
  (step 6). The 7 original `[PASS]` lines are unchanged from the Phase 1
  output.
- `./scripts/guardrails/verify-nginx-shared-routes.sh` still exits `0` with 26
  passed and 0 failed. It runs `nginx -t` on both configs with the changed
  include.
- Leftover-container check as in Phase 1.
- Static suite with the pinned interpreter:
  `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python ./scripts/guardrails/verify-static-security-manifests.sh`
  passes. If the interpreter is missing, create it as documented in
  `docs/ci-cd.md#security-guardrailsyml`. Do not use the system PyYAML.

### Completion criteria

- `backend-headers.conf` contains exactly one
  `proxy_hide_header X-Frame-Options;`, and no other directive changed.
- The harness shows the conflict at the control location and exactly one
  `SAMEORIGIN` through the include. The red and green runs are recorded.
- Docs describe the hiding, the static suite and shared routes harness pass, and
  no cluster mutation was made.

## Phase 3: Live Proof Through The Ingress And Issue Closeout

### Workspace

.

### Goal

Load the changed include into the running local NGINX. Add a live assertion
that a real backend API response through the ingress carries exactly one
`X-Frame-Options: SAMEORIGIN`. Run the live edge verifier, then delete the
X-Frame-Options issue.

### Scope

- `scripts/smoketest/verify-edge-contract.sh`: the Response Headers section
  and its `usage` line
- An NGINX reload in the local Kind cluster after the target checks pass
- Delete `docs/issues/low-duplicate-x-frame-options.md`

### Non-goals

- Checking `X-Frame-Options` on Session Gateway lanes (`/auth/*`,
  `/oauth2/*`). They do not pass through NGINX.
- `--inject-failures`, pod restarts, `kubectl apply` of ConfigMaps or any
  manual live drift
- Fixing `low-edge-verifier-global-counter-flakiness.md`

### Required context

- `docs/issues/low-duplicate-x-frame-options.md`
- `docs/architecture/autonomous-ai-execution.md`: the local target checks that
  must pass before an agent cluster mutation
- `nginx/README.md` `## Commands`: an include change needs
  `nginx -s reload`; Tilt only refreshes the ConfigMap
- `scripts/smoketest/verify-edge-contract.sh`: `verify_response_headers`,
  `edge_request`, `record`, and the `usage` text for Response Headers
- `docs/issues/low-edge-verifier-global-counter-flakiness.md`, for
  interpreting unrelated counter-section failures

### Execution steps

1. Check prerequisites:
   - `./scripts/bootstrap/check-local-runtime.sh` passes.
   - `kubectl config current-context` is `kind-kind`.
   - `tilt get uiresources` shows Tilt is running.
   - `.loadtest/session-pool.txt` does not exist.

   If any prerequisite fails, stop and report it. Do not work around it.
2. Confirm the live ConfigMap carries the change:
   `kubectl get configmap nginx-gateway-includes -o jsonpath='{.data.backend-headers\.conf}'`
   must contain `proxy_hide_header X-Frame-Options;`. If it does not, run
   `tilt trigger nginx-gateway` once and recheck. If it is still missing, stop.
3. Before reloading, record the live red state from inside the pod:
   `kubectl exec deployment/nginx-gateway -c nginx -- sh -c 'curl -s -o /dev/null -D - --max-time 5 -H "X-User-Id: usr_probe" -H "X-Permissions: currencies:read" http://127.0.0.1:8080/api/v1/currencies'`.
   Note how many `X-Frame-Options` values it returns. If the pod already
   restarted onto the new include, record that instead.
4. Poll for up to 120 s until
   `/etc/nginx/includes/backend-headers.conf` in the pod contains the new
   directive. Then run `kubectl exec deployment/nginx-gateway -c nginx --
   nginx -t`, and if it passes, `... -- nginx -s reload`. Repeat the step 3
   probe: it must return exactly one `X-Frame-Options: SAMEORIGIN`.
5. In `verify_response_headers`, for the `/api/v1/currencies` iteration only,
   read every `X-Frame-Options` line from `${WORK_DIR}/headers`
   (case-insensitive, `\r` stripped).
   - Pass when there is exactly one value and it is `SAMEORIGIN`.
   - Otherwise fail with the values seen.
   - `record` the result in the section's existing style.

   Add the frame-policy check to the Response Headers `usage` line.
6. Delete `docs/issues/low-duplicate-x-frame-options.md`. Then
   `rg -n "low-duplicate-x-frame-options" --glob '!docs/plans/**'` must return
   nothing.

### Implementation notes

- `nginx-gateway` runs one replica, so `kubectl exec deployment/...` reaches
  the only pod. If the replica count has changed, reload every pod.
- The section already sends `/api/v1/currencies` with the seeded session
  cookie. That is a real `currency-service` response through ingress,
  `ext_authz` and NGINX, so no new request is needed.

### Validation

- `bash -n` and `shellcheck` (plain and `-x`) on
  `scripts/smoketest/verify-edge-contract.sh` are clean.
- The step 3 and step 4 in-pod probes show the before and after header counts.
- `./scripts/smoketest/verify-edge-contract.sh` (no flags) exits `0`, and the
  new Response Headers assertion passes. Unrelated global-counter sections can
  fail from concurrent browser traffic. If one does, rerun once with no
  browser tabs open, and report both runs faithfully.
- Both offline harnesses still pass, with 9 passed and 0 failed and 26 passed
  and 0 failed.
- The static suite passes with the pinned interpreter.
- `git status --short` shows only:
  - the library
  - the two harnesses
  - `verify-edge-contract.sh`
  - `backend-headers.conf`
  - `scripts/README.md`, `nginx/README.md` and
    `docs/architecture/security-architecture.md`
  - the two deleted issue files
  - this plan

### Completion criteria

- The running local NGINX serves the new include. API responses through the
  ingress carry exactly one `X-Frame-Options: SAMEORIGIN`.
- `verify-edge-contract.sh` asserts it and passes on the live stack.
- Both issue files are deleted, and nothing outside `docs/plans/` references
  either one.
- No manual drift remains. The only cluster action was the documented
  `nginx -s reload` after the target checks.
