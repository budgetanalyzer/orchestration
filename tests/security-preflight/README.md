# Security Preflight Testing

> Phase 7 status: this retained DinD suite is stale against the current
> Istio-only baseline and is non-gating for Phase 7 until it is explicitly
> realigned. Keep it in the inventory, and keep its third-party image refs
> aligned with the same digest-pinning rule as the rest of the repo.

Containerized runtime test harness for Security Hardening v2 Phase 0.

## Purpose

This suite validates runtime platform security prerequisites after minimal control-plane bootstrapping.

It depends on the reorganized script tree: bootstrap helpers live under
`scripts/bootstrap/`, while the runtime verifier it exercises lives under
`scripts/smoketest/`.

It provisions only what the verifier needs:

1. Kind cluster with `disableDefaultCNI`
2. Calico CNI
3. Gateway API CRDs + Envoy Gateway namespace
4. Istio base + `istiod`
5. Namespace baseline labels (Istio + Pod Security warn/audit)
6. Kyverno + smoke policy
7. `scripts/smoketest/verify-security-prereqs.sh`

## Usage

From the orchestration root:

```bash
./tests/security-preflight/run-test.sh
```

## What It Proves

- `NetworkPolicy` enforcement blocks traffic after deny and restores traffic after allow
- Pod Security Admission rejects non-compliant pods in an `enforce=restricted` namespace
- Istio is ready, expected policy resources exist, and sidecar injection occurs
- Kyverno admission is active and smoke policy rejects privileged pods in labeled namespaces

## Files

| File | Purpose |
|------|---------|
| `docker-compose.test.yml` | DinD + test runner orchestration |
| `run-test.sh` | Host-side entry point |
| `test-security-preflight.sh` | In-container bootstrap + verifier run |

Shared test environment:
- `tests/shared/Dockerfile.test-env` (single source of truth used by setup-flow and security-preflight suites)

## Runtime

Expect approximately 10-20 minutes depending on network speed (Helm pulls dominate runtime).

## Shared Test-Env Contract

This suite validates the shared test image contract before DinD startup. The image must include:

- `docker`
- `kubectl`
- `kind`
- `helm`
- `tilt`
- `mkcert`
- `git`
- `certutil`
