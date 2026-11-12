# cert-manager controller images are not digest-pinned

- **Severity:** Low
- **Owner:** orchestration
- **Status:** Open
- **Source:** security documentation reorganization, platform security audit sweep (2026-11-12)

## Problem

The production reference renders four cert-manager images by mutable tag only.
Rendering `deploy/helm-values/cert-manager.values.yaml` against the chart
selected in `scripts/lib/production-version-contract.sh` produces:

- `quay.io/jetstack/cert-manager-controller:<version>`
- `quay.io/jetstack/cert-manager-webhook:<version>`
- `quay.io/jetstack/cert-manager-cainjector:<version>`
- `quay.io/jetstack/cert-manager-startupapicheck:<version>`

Only the HTTP-01 solver (`acmesolver.image.digest`) is pinned. The values
comment says it is pinned because solver pods run in application namespaces,
where the digest policy applies.

The other controller charts pin their images even though their namespaces are
also excluded from the digest policy. `deploy/helm-values/kyverno.values.yaml`
and `deploy/helm-values/external-secrets.values.yaml` both carry digests. The
cert-manager chart supports the same pinning: `image.digest`,
`webhook.image.digest`, `cainjector.image.digest` and
`startupapicheck.image.digest`.

No control catches the gap:

- `kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml`
  excludes the `cert-manager` namespace.
- `kubernetes/kyverno/README.md` explains the namespace exclusions only as
  "chart-managed or cluster-managed rather than orchestration-managed". That
  reason applies equally to Kyverno and External Secrets, which are pinned.
- `scripts/lib/image-pinning-targets.txt` does not list
  `deploy/helm-values/cert-manager.values.yaml`.
- The exact-image evidence workflow scans one resolved digest per run but
  labels these refs mutable (`docs/dependency-automation.md#exact-image-security-evidence`).

## Impact

The production reference is offline-only, so nothing runs these images today.
A future hosted deployment would pull whatever the tag points to at install
time. That breaks the repository rule that every third-party image ref is a
digest-pinning target unless an inventory exception documents why not.

## Proposed fix

- Add `linux/arm64`-capable digests for the four images to
  `deploy/helm-values/cert-manager.values.yaml`, following the
  external-secrets pattern.
- Bring the values file under the static pinning guardrail, either by listing
  it in `scripts/lib/image-pinning-targets.txt` or through an equivalent
  rendered-image check.
- Keep the Kyverno namespace exclusion, which exists for chart-managed pods.
  Pinning in values is the control for those pods, which is also how Kyverno
  and External Secrets are handled.

## Acceptance

- The offline cert-manager render contains only `@sha256:` image refs.
- A static guardrail fails if a cert-manager image loses its digest.
- The exact-image evidence workflow no longer labels the cert-manager
  controller refs mutable.
