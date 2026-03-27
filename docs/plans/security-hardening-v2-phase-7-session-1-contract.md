# Security Hardening v2 Phase 7 Session 1 Contract

This document freezes the Phase 7 supply-chain scope for the orchestration repo.

## Scope

Phase 7 guardrails cover orchestration-owned third-party image references in:

- active Kubernetes manifests
- orchestration-owned Dockerfiles and Tilt inline Dockerfiles
- retained DinD assets that still ship in this repo
- verifier probe image constants that are part of the Phase 0 through Phase 7 runtime proofs

The checked-in executable inventory for that scope lives in:

- `scripts/dev/lib/phase-7-image-pinning-targets.txt`
- `scripts/dev/lib/phase-7-allowed-latest.txt`

`scripts/dev/check-phase-7-image-pinning.sh` must read those inventories instead
of carrying its own parallel file list.

## Allowed `:latest` Exceptions

Only these seven local Tilt-built images may remain on `:latest`:

- `transaction-service:latest`
- `currency-service:latest`
- `permission-service:latest`
- `session-gateway:latest`
- `ext-authz:latest`
- `budget-analyzer-web:latest`
- `budget-analyzer-web-prod-smoke:latest`

Every other orchestration-owned third-party `image:` or `FROM` reference must
be pinned with `@sha256:`.

## Explicit Exclusions

- `docs/archive/**` and `docs/decisions/**` are historical only and not part of
  the guardrail scope.
- Documentation snippets may show unpinned images as examples; they are not the
  executable inventory.
- `tests/setup-flow/**` and `tests/security-preflight/**` remain stale,
  non-gating runtime suites, but their checked-in image references are still
  frozen and stay inside the static image-pinning scan while those assets remain
  in this repo.

## Change Rule

If a Phase 7 guarded surface is added, removed, or renamed:

1. Update `scripts/dev/lib/phase-7-image-pinning-targets.txt` or
   `scripts/dev/lib/phase-7-allowed-latest.txt` first.
2. Update this contract doc in the same change.
3. Rerun `./scripts/dev/check-phase-7-image-pinning.sh`.
