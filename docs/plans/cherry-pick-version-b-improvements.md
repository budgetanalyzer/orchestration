# Cherry-pick version-b improvements into phase0-version-a

## Decision summary

Keep `phase0-version-a` as the base, then cherry-pick the small, high-value details from `phase0-version-b` identified in the Codex + Claude branch reviews.

## Cherry-picked improvements (implemented)

### 1. Kind networking and node pin updates

- Added `networking.podSubnet: "192.168.0.0/16"` to avoid Calico pod CIDR mismatch issues.
- Updated Kind node image pin from `kindest/node:v1.30.8` to `kindest/node:v1.32.2`.

**Files**
- `kind-cluster-config.yaml`
- `tests/setup-flow/kind-cluster-test-config.yaml`

### 2. CoreDNS readiness wait after Calico setup

- Added an explicit CoreDNS rollout wait in the shared Calico installer so setup does not proceed until DNS is healthy.
- Updated setup-flow test to assert CoreDNS readiness after Calico install.

**Files**
- `scripts/dev/install-calico.sh`
- `setup.sh` (status message updated to match new readiness scope)
- `tests/setup-flow/test-setup-flow.sh`

### 3. PSA `-version` labels

- Added explicit `warn-version` and `audit-version` labels (`v1.32`) alongside existing PSA labels.
- Applied consistently for `default`, `infrastructure`, and `envoy-gateway-system` namespace labeling in Tilt.

**Files**
- `kubernetes/infrastructure/namespace.yaml`
- `Tiltfile` (`istio-injection` local_resource)

### 4. Kyverno bootstrap hardening details

- Switched Kyverno repo add to `--force-update` to avoid stale repo metadata issues.
- Added single-replica tuning for Kyverno controllers to reduce local Kind resource pressure.
- Kept version-a's stronger Kyverno structure (namespace `kyverno`, chart `3.7.1`, readiness gate, smoke policy).

**Files**
- `Tiltfile` (`kyverno` local_resource)

## Explicitly not cherry-picked

- Version-b inline Calico install flow in `setup.sh` and `tests/setup-flow/test-setup-flow.sh` (kept version-a's shared `scripts/dev/install-calico.sh`).
- Version-b reduced verifier scope (`verify-network-policy.sh`) (kept version-a's comprehensive `verify-security-prereqs.sh`).
- Version-b Kyverno downgrade (`3.3.7`) and namespace switch (`kyverno-system`) (kept version-a defaults).
- Version-b omission of `envoy-gateway-system` PSA labels (kept version-a broader namespace coverage).

## Validation checklist

1. Recreate cluster and validate Kind config:
   - `kind delete cluster --name kind`
   - `kind create cluster --config kind-cluster-config.yaml`
2. Run bootstrap:
   - `./setup.sh`
3. Confirm security baseline runtime behavior:
   - `./scripts/dev/check-tilt-prerequisites.sh`
4. Run setup-flow integration test:
   - `tests/setup-flow/run-test.sh`
