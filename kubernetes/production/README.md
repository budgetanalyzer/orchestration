# Production Manifests

This directory contains production-only artifacts for the Oracle Cloud deployment plan.

## App Image Overlay

`apps/` is the Phase 3 production image overlay. It renders the repo-owned application workloads with the `0.0.12` GHCR release images pinned by digest.

Render it with:

```bash
kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
```

Verify it with:

```bash
./scripts/guardrails/verify-production-image-overlay.sh
```

That verifier renders the overlay, rejects local image refs and `imagePullPolicy:
Never`, and applies the production Kyverno image policy at
`../kyverno/policies/production/50-require-third-party-image-digests.yaml`.

The overlay is intentionally limited to image cutover and production NGINX static-asset wiring. Hostname, production secret, ExternalSecret, storage, observability, and the full shared/local/production Kyverno directory split remain in the later Oracle deployment phases.
