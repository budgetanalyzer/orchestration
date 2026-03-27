# Security Hardening v2 Production Review - March 27, 2026

## Outcome

The `security-hardening-v2` branch is close, but it is not production-complete.
The static verifier completed successfully, and the live runtime verifier
advanced through the new Phase 7 assertions plus multiple nested regressions on
the reviewed cluster without exposing additional failures. Even so, three
follow-up changes are still required before this hardening work matches its own
contract and is safe to treat as a production-quality `v1.0` baseline.

## Review Scope

- Diff reviewed: `main...security-hardening-final`
- Focus: security intent, production-readiness, verifier quality, and absence of
  branch-local shortcuts
- Commands run during review:
  - `./scripts/dev/check-phase-7-image-pinning.sh`
  - `./scripts/dev/verify-phase-7-static-manifests.sh`
  - `./scripts/dev/verify-phase-7-static-manifests.sh --self-test`
  - `./scripts/dev/verify-phase-7-runtime-guardrails.sh`

The reviewed cluster uses the same Auth0 tenant currently hardcoded in the new
Istio egress manifests. That masks one of the issues below and explains why the
runtime checks remain green on this machine.

## Required Changes

### 1. Remove the hardcoded Auth0 tenant from Istio egress policy

Why this is required:

- The hardening plan says the allowed Auth0 egress host must be derived from
  `AUTH0_ISSUER_URI`.
- The implementation hardcodes `dev-gcz1r8453xzz0317.us.auth0.com` in
  `kubernetes/istio/egress-service-entries.yaml` and
  `kubernetes/istio/egress-routing.yaml`.
- `.env.example` and the Auth0 setup docs still tell users to supply their own
  tenant hostname.

Risk:

- Any deployment that uses a different Auth0 tenant will have a valid
  `session-gateway` config but an invalid Istio egress allowlist.
- Phase 3 verification currently only proves reachability to whatever host is
  already in the `ServiceEntry`; it does not prove that the host matches
  `AUTH0_ISSUER_URI`.

Required implementation:

- Generate the Auth0 hostname for the egress `ServiceEntry`, egress `Gateway`,
  and `VirtualService` from one source of truth.
- Keep the FRED hostname static; only the Auth0 host needs to be dynamic.
- Extend `scripts/dev/verify-phase-3-istio-ingress.sh` to fail if the egress
  Auth0 host does not match the configured `AUTH0_ISSUER_URI` hostname.
- Document the rendering path clearly so production secret sourcing and local
  Tilt secret sourcing stay aligned.

### 2. Expand CI trigger coverage for the static security guardrails workflow

Why this is required:

- `check-phase-7-image-pinning.sh` explicitly treats files like `Tiltfile`,
  `ext-authz/Dockerfile`, `kind-cluster-config.yaml`, and the retained DinD
  assets as guarded Phase 7 surfaces.
- `.github/workflows/security-guardrails.yml` does not trigger when several of
  those files change.

Risk:

- A PR can weaken pinned images or installer/security posture in a guarded file
  without running the Phase 7 CI workflow at all.
- That is an avoidable audit-gap in the exact branch that is supposed to freeze
  supply-chain and admission-policy discipline.

Required implementation:

- Expand the workflow `paths:` filters to include every Phase 7 guarded surface,
  at minimum:
  - `Tiltfile`
  - `kind-cluster-config.yaml`
  - `ext-authz/**`
  - `tests/setup-flow/**`
  - `tests/security-preflight/**`
- If keeping the path filter becomes too brittle, remove it and run the static
  guardrail workflow on all PRs and pushes to `main`.

### 3. Bring the image-pinning scan back into sync with Phase 7 runtime assets

Why this is required:

- `scripts/dev/verify-phase-7-runtime-guardrails.sh` introduces new pinned probe
  images for Redis, PostgreSQL, and RabbitMQ.
- `scripts/dev/check-phase-7-image-pinning.sh` does not scan that file.

Risk:

- A future edit can silently unpin those Phase 7 runtime probe images while the
  static image-pinning check still reports success.
- That is a guardrail drift problem, not an immediate exploit, but it directly
  undermines the Phase 7 contract.

Required implementation:

- Add `scripts/dev/verify-phase-7-runtime-guardrails.sh` to the Phase 7 image
  pinning target set.
- Re-check the target inventory against the Session 1 contract so the scan and
  the documented scope cannot drift independently.
- Prefer one maintained inventory source over parallel hand-kept lists.

## Recommended Order

1. Fix the Auth0 egress host derivation and verifier mismatch first.
2. Expand the CI workflow triggers so the corrected branch is actually guarded.
3. Update the image-pinning scan target list and rerun the static gate.

## Done When

- The Auth0 egress allowlist follows the configured `AUTH0_ISSUER_URI`
  hostname instead of a checked-in tenant.
- The Phase 3 verifier proves config-to-egress alignment, not just egress
  reachability to a manifest value.
- The `security-guardrails` workflow runs for every guarded Phase 7 surface.
- The image-pinning scan covers the Phase 7 runtime verifier's probe images.
- `./scripts/dev/verify-phase-7-security-guardrails.sh` still passes after the
  fixes.
