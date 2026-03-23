# Phase 3 Follow-Up Fix Plan After Commit 55843a6 Review

## Context

This plan captures the issues found while reviewing commit `55843a6` on March 23, 2026 and rerunning the Phase 3 verification flow against the live Kind cluster.

What passed during review:

- `bash -n scripts/dev/verify-phase-3-istio-ingress.sh`
- `kubectl apply --dry-run=server` for the Phase 3 ingress, egress, rate-limit, authz, and `NetworkPolicy` manifests
- live selector and principal checks for the Istio ingress and egress gateways
- 73 of 74 checks in `./scripts/dev/verify-phase-3-istio-ingress.sh`

What did not pass:

- `./scripts/dev/verify-phase-3-istio-ingress.sh` failed `GET /login returns 302`
- `./scripts/dev/verify-security-prereqs.sh` failed because it still expects the removed PERMISSIVE `PeerAuthentication` resources

Non-Phase-3 note:

- `./scripts/dev/check-tilt-prerequisites.sh` failed in this container because `mkcert` is not installed here. That is not evidence that Phase 3 is wrong, but it does mean the full documented verification sequence was not green in this environment.

## Findings

### 1. `/login` is still architecturally inconsistent, and Phase 3 now exposes that inconsistency

Evidence from this review:

- `scripts/dev/verify-phase-3-istio-ingress.sh` expects `GET /login` to return `302`, but it returned `000` because the request hung until curl timed out.
- `curl -sk --max-time 15 --max-redirs 0 https://app.budgetanalyzer.localhost/oauth2/authorization/idp` returned `302` immediately, which shows the real OAuth2 initiation path still works.
- `kubectl logs deployment/session-gateway` showed `GET /login` matching `frontend-route` and attempting to proxy to `http://nginx-gateway:8080`.
- `timeout 12s kubectl exec deploy/session-gateway -c session-gateway -- sh -c "wget -S -O - http://nginx-gateway:8080/login 2>&1"` hung until timeout.
- `kubernetes/istio/authorization-policies.yaml` allows `nginx-gateway` traffic only from `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`.
- `kubernetes/network-policies/default-allow.yaml` no longer allows `session-gateway` egress to `nginx-gateway:8080`.
- `../budget-analyzer-web/src/features/auth/hooks/useAuth.ts` already initiates login via `/oauth2/authorization/idp`, while `../budget-analyzer-web/src/App.tsx` and `../budget-analyzer-web/src/features/admin/components/ProtectedRoute.tsx` still use `/login` as a frontend page route.

Implication:

- The current Phase 3 state keeps `/login` in the ingress auth-path bucket, but the frontend still treats `/login` as an app page.
- Relaxing `nginx-gateway` policy to allow `session-gateway` would weaken the Phase 3 ingress-only boundary and preserve the confused contract.

Recommended direction:

- Keep the stricter ingress-facing `AuthorizationPolicy` and `NetworkPolicy`.
- Stop treating bare `/login` as a Session Gateway route.
- Let the frontend own `/login`, and let Session Gateway own only the real auth endpoints:
  - `/oauth2/**`
  - `/auth/**`
  - `/logout`
  - `/user`
  - `/login/oauth2/**` for the OAuth2 callback path

### 2. The verification workflow is internally inconsistent after Phase 3

Evidence from this review:

- `scripts/dev/verify-security-prereqs.sh` still requires:
  - `default-strict`
  - `nginx-gateway-permissive`
  - `ext-authz-permissive`
  - `session-gateway-permissive`
- Phase 3 intentionally removed those three PERMISSIVE resources.
- `README.md`, `AGENTS.md`, `docs/development/local-environment.md`, and `docs/runbooks/tilt-debugging.md` still instruct users to run `./scripts/dev/verify-security-prereqs.sh` as part of the normal verification flow after `tilt up`.
- `scripts/dev/verify-phase-3-istio-ingress.sh` still encodes the wrong `/login` behavior as a hard requirement.

Implication:

- The repo cannot currently satisfy its own documented verification flow on a correct Phase 3 cluster.
- Goal 5 from the remediation plan, "the verifier becomes the honest completion gate," is not fully achieved yet.

## Fix Plan

### Session 1. Reconcile `/login` ownership without weakening Phase 3 security boundaries

Files to change:

- `kubernetes/gateway/auth-httproute.yaml`
- `kubernetes/istio/ingress-rate-limit.yaml`
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- docs in this repo that currently describe `/login` as a direct Session Gateway entrypoint

Work:

1. Remove bare `/login` from the Session Gateway `HTTPRoute` matches.
2. Add a callback-specific match for `/login/oauth2` so the Auth0 callback still reaches Session Gateway.
3. Update ingress auth-path throttling so it covers the actual auth-sensitive paths, not the frontend login page. The minimum set should be:
   - `/oauth2/**`
   - `/auth/**`
   - `/logout`
   - `/user`
   - `/login/oauth2/**`
4. Update the Phase 3 verifier so it proves the real contract:
   - `GET /login` returns the frontend login page successfully
   - `GET /oauth2/authorization/idp` returns `302` to Auth0
   - callback routing remains attached to Session Gateway

Explicit non-goal for this session:

- Do not "fix" `/login` by reopening `session-gateway -> nginx-gateway` access. That would backslide on the ingress-only protection added in Phase 3.

### Session 2. Repair the verification scripts so the documented flow can pass again

Files to change:

- `scripts/dev/verify-security-prereqs.sh`
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- `README.md`
- `AGENTS.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- architecture docs that currently describe `/login` or the completion gate incorrectly

Work:

1. Remove the three PERMISSIVE `PeerAuthentication` expectations from `scripts/dev/verify-security-prereqs.sh`.
2. Keep that verifier focused on the Phase 0 baseline it is supposed to prove:
   - `NetworkPolicy` enforcement
   - Pod Security Admission enforcement
   - Istio readiness
   - sidecar injection
   - the baseline backend `AuthorizationPolicy` resources
3. Make the docs clear that:
   - `./scripts/dev/verify-security-prereqs.sh` proves the platform baseline
   - `./scripts/dev/verify-phase-3-istio-ingress.sh` is the Phase 3 completion gate
4. Update the docs to describe the real auth entrypoints:
   - frontend login page at `/login`
   - OAuth2 initiation at `/oauth2/authorization/idp`
   - OAuth2 callback under `/login/oauth2/code/*`

### Session 3. Re-run the real closure checks

After Sessions 1 and 2:

1. `bash -n scripts/dev/verify-phase-3-istio-ingress.sh`
2. `bash -n scripts/dev/verify-security-prereqs.sh`
3. `kubectl apply --dry-run=server` for the touched ingress, rate-limit, and verification manifests
4. `./scripts/dev/verify-security-prereqs.sh`
5. `./scripts/dev/verify-phase-3-istio-ingress.sh`
6. Browser validation:
   - open `https://app.budgetanalyzer.localhost/login`
   - confirm it loads without timeout
   - confirm it initiates OAuth2 via `/oauth2/authorization/idp`
   - confirm protected-route navigation still reaches login successfully
   - confirm logout still works

Destructive validation still outstanding after that:

- a fresh-cluster `tilt up` should still be rerun, but that was not done during this review because it would tear down the current live cluster

## Success Criteria

This follow-up is complete only when all of the following are true:

- `GET /login` no longer hangs
- the frontend login page and the Session Gateway OAuth2 initiation path are no longer in conflict
- Phase 3 keeps the stricter `nginx-gateway` ingress-only protections
- `./scripts/dev/verify-security-prereqs.sh` passes on a Phase 3-correct cluster
- `./scripts/dev/verify-phase-3-istio-ingress.sh` passes without special-casing or warning-only fallbacks
- the docs describe the actual auth entrypoints and actual completion gate

## Session 3 Execution Record

Date executed: March 23, 2026

Terminal-verifiable closure checks completed successfully in the live Kind cluster:

1. `bash -n scripts/dev/verify-phase-3-istio-ingress.sh` passed
2. `bash -n scripts/dev/verify-security-prereqs.sh` passed
3. `kubectl apply --dry-run=server -f kubernetes/gateway/auth-httproute.yaml -f kubernetes/istio/ingress-rate-limit.yaml` passed
4. `./scripts/dev/verify-security-prereqs.sh` passed
5. `./scripts/dev/verify-phase-3-istio-ingress.sh` passed with `79 passed (out of 79)`

Manual browser-only validation is still required on the host machine because this container cannot open a real browser session:

- open `https://app.budgetanalyzer.localhost/login`
- confirm the frontend login page loads interactively
- confirm it initiates OAuth2 via `/oauth2/authorization/idp`
- confirm protected-route navigation still returns to login correctly
- confirm logout still works end-to-end
