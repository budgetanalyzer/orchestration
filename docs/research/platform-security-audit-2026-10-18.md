# Platform Security Audit — 2026-10-18

**Status:** Accepted bounded upgrade decision  
**Audit date:** 2026-10-18  
**Target platform:** `linux/arm64`  
**Runtime boundary:** local Tilt/Kind plus the offline provider-neutral
production reference; no hosted environment was inspected

This record narrows the platform work authorized by the 2026-10-18 lifecycle
and image-security audit. It is the decision input for
[`audit-driven-platform-security-remediation.md`](../plans/audit-driven-platform-security-remediation.md),
which supersedes the broad freshness-led platform scope in
`manual-ecosystem-dependency-modernization.md`.

The safe upgrade set is exactly:

- Istio chart/application `1.29.9` to `1.30.6`;
- Kiali chart/application `2.24.0` to `2.26.0`, the first release line whose
  published compatibility table covers Istio `1.30`; and
- Kyverno chart `3.8.2` / application `1.18.2` to chart `3.9.1` /
  application `1.19.1`.

This record does not authorize any other platform or monitoring upgrade. A
newer release is not an automatic substitute for one of these reviewed target
lines.

## Verdicts

| Family | Reconfirmed baseline | Verdict in this plan | Evidence and boundary |
| --- | --- | --- | --- |
| Kubernetes / Kind node | Kubernetes `1.35.8`; `kindest/node:v1.35.8` | **Keep** | The checked-in local and offline compatibility target remains `1.35.8`. Scanner package volume alone is not an instruction to change Kubernetes. |
| Helm | `3.22.1` | **Keep** | This is the pinned rendering tool used for the audit. |
| Gateway API | CRDs `1.5.1` | **Keep** | The existing CRDs remain the reviewed Istio input; the Istio move does not require a Gateway API change. |
| Istio | charts/app `1.29.9` | **Upgrade to `1.30.6`** | Istio `1.29` reached end of life on 2026-10-15. The supported-release table covers Kubernetes `1.35` on Istio `1.30`, and identifies `1.30.6+` as the patched `1.30` level with no known CVEs. The `1.30.6` release fixes the cited Istio and Envoy security issues. |
| Kiali | chart/app `2.24.0` | **Upgrade to `2.26.0` with Istio** | Kiali's compatibility table says Istio `1.30` requires Kiali `2.26` or higher. `2.26.0` is the bounded first compatible line, not a freshness-led selection. |
| Kyverno | chart `3.8.2`, app `1.18.2` | **Upgrade to chart `3.9.1`, app `1.19.1`** | Chart metadata confirms the target pairing and Kubernetes `>=1.25`. The `1.19.1` release includes Go dependency CVE fixes and policy/API-call hardening fixes. |
| kube-prometheus-stack | chart `83.4.3` | **Keep** | The chart, dependencies, CRDs, values, post-renderer, and RBAC remain unchanged. A lower finding count in a different component image does not authorize a parent-chart migration. |
| kube-state-metrics | `2.18.0` | **Defer, then change only in the ordered follow-up** | The exact current image has two critical findings with fixed-version evidence. This plan still leaves it unchanged. Run [`kube-state-metrics-security-remediation.md`](../plans/kube-state-metrics-security-remediation.md) only after this plan; that plan keeps chart `83.4.3` and changes only this image to `2.20.0`. |
| Prometheus Operator | `0.90.1` | **Keep** | The `0.94.1` comparison has fewer raw findings, but no Operator, CRD, RBAC, or chart migration is authorized here. |
| Prometheus config reloader | `0.90.1` | **Keep** | It remains paired with Operator `0.90.1`; the `0.94.1` scan is comparison evidence only. |
| Prometheus | `3.11.3` | **Keep** | The `3.15.0-distroless` comparison has fewer raw findings, but changing image flavor/version and proving compatibility is outside this plan. |
| Grafana | `12.4.13` | **Keep** | It remains part of the unchanged chart-`83.4.3` monitoring baseline. |
| cert-manager | chart/app `1.20.4` | **Keep** | No support or security evidence in this bounded audit justified changing the selected line. |
| external-secrets | chart/app `2.2.0` | **Keep** | No support or security evidence in this bounded audit justified changing the selected line. |

The monitoring decision is intentionally asymmetric: kube-state-metrics has a
separate ordered remediation, while the Operator, config reloader, Prometheus,
Grafana, parent chart, CRDs, RBAC, and all other monitoring behavior have no
migration authorization from this audit.

## Checked-In And Rendered Baseline

The active declarations were read from
`scripts/lib/production-version-contract.sh`,
`scripts/lib/pinned-tool-versions.sh`, `kind-cluster-config.yaml`, `Tiltfile`,
`kubernetes/monitoring/prometheus-stack-values.yaml`, and the provider-neutral
Helm values. Archived material and generated runner state were excluded.

The chart metadata reconfirmed these pairings:

| Chart | Chart version | Application version | Relevant Kubernetes constraint |
| --- | ---: | ---: | --- |
| `kyverno/kyverno` | `3.8.2` | `1.18.2` | `>=1.25.0-0` |
| `kyverno/kyverno` candidate | `3.9.1` | `1.19.1` | `>=1.25.0-0` |
| `kiali/kiali-server` | `2.24.0` | `2.24.0` | chart does not declare one |
| `kiali/kiali-server` candidate | `2.26.0` | `2.26.0` | chart does not declare one |
| `prometheus-community/kube-prometheus-stack` | `83.4.3` | `0.90.1` | `>=1.25.0-0` |
| `jetstack/cert-manager` | `1.20.4` | `1.20.4` | `>=1.22.0-0` |
| `external-secrets/external-secrets` | `2.2.0` | `2.2.0` | `>=1.19.0-0` |

The current monitoring chart was rendered, without applying it, with Helm
`3.22.1`, `--kube-version 1.35.8`, the repository values and
`scripts/ops/post-render-prometheus-stack.sh`. A second render added the
production-reference monitoring override. The chart generates a fresh Grafana
admin password and dependent pod-template checksum on each client-side render,
so a whole-file hash is not a reproducible baseline. Stable component and image
fields were compared instead. Both renders retained exactly:

| Component | Rendered source reference |
| --- | --- |
| Grafana | `docker.io/grafana/grafana:12.4.13@sha256:41bbc1b5e04416f81891806076db2a2ff60a5d4da5f78d36a88b033a8c199185` |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.18.0@sha256:1545919b72e3ae035454fc054131e8d0f14b42ef6fc5b2ad5c751cafa6b2130e` |
| Prometheus Operator | `quay.io/prometheus-operator/prometheus-operator:v0.90.1@sha256:52a6a92d915ea2fa94314748d99db7a94922e3fe63274f6182fc033b9126b573` |
| Prometheus config reloader | `quay.io/prometheus-operator/prometheus-config-reloader:v0.90.1@sha256:693faa0b87243cddca2cffb13586e4e2778b0cdf319cb2e601ba7af3fd19ef7d` |
| Prometheus | `quay.io/prometheus/prometheus:v3.11.3@sha256:c0b857aead0d5793aa566adb8f49a9983d6f6031652098759d521a330cfa050f` |

The reloader is carried by the Operator's
`--prometheus-config-reloader=...` argument and is not a standalone Deployment
image in this client-side render. The render confirms version selection only;
it is not runtime evidence.

## Upstream Support And Release Evidence

All links in this section were retrieved on **2026-10-18**.

| Topic | Source | Audit use |
| --- | --- | --- |
| Kubernetes `1.35.8` | [Kubernetes release](https://github.com/kubernetes/kubernetes/releases/tag/v1.35.8), [version-skew policy](https://kubernetes.io/releases/version-skew-policy/) | Reconfirmed the selected Kubernetes line; no freshness substitution was made. |
| Helm `3.22.1` | [Helm release](https://github.com/helm/helm/releases/tag/v3.22.1) | Reconfirmed the exact render tool. |
| Gateway API `1.5.1` | [Gateway API release](https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.5.1) | Reconfirmed the retained CRD release. |
| Istio lifecycle and Kubernetes support | [Supported releases](https://istio.io/latest/docs/releases/supported-releases/) | Recorded that `1.29` is EOL, `1.30` is supported, and Kubernetes `1.35` is supported on `1.30`. |
| Istio `1.30.6` fixes | [Release notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.6/), [GitHub release](https://github.com/istio/istio/releases/tag/1.30.6), [security bulletin](https://istio.io/latest/news/security/istio-security-2026-007/) | Selected the security-patched `1.30` target. |
| Kiali compatibility | [Compatibility table](https://kiali.io/docs/installation/installation-guide/prerequisites/#version-compatibility), [Kiali `2.26.0`](https://github.com/kiali/kiali/releases/tag/v2.26.0) | Established `2.26+` as the published requirement for Istio `1.30`. |
| Kyverno `1.19.1` | [Kyverno release](https://github.com/kyverno/kyverno/releases/tag/v1.19.1), [chart repository](https://kyverno.github.io/kyverno/) | Confirmed security fixes and chart `3.9.1` / app `1.19.1`. |
| kube-prometheus-stack `83.4.3` | [Chart release](https://github.com/prometheus-community/helm-charts/releases/tag/kube-prometheus-stack-83.4.3), [chart source](https://github.com/prometheus-community/helm-charts/tree/kube-prometheus-stack-83.4.3/charts/kube-prometheus-stack) | Confirmed app `0.90.1` and the bundled chart baseline. |
| Monitoring comparison releases | [kube-state-metrics `2.20.0`](https://github.com/kubernetes/kube-state-metrics/releases/tag/v2.20.0), [Prometheus Operator `0.94.1`](https://github.com/prometheus-operator/prometheus-operator/releases/tag/v0.94.1), [Prometheus `3.15.0`](https://github.com/prometheus/prometheus/releases/tag/v3.15.0) | Supplied fixed-version comparison inputs; only kube-state-metrics is routed to a follow-up. |
| Retained controllers | [cert-manager `1.20.4`](https://github.com/cert-manager/cert-manager/releases/tag/v1.20.4), [external-secrets `2.2.0`](https://github.com/external-secrets/external-secrets/releases/tag/v2.2.0), [Grafana `12.4.13`](https://github.com/grafana/grafana/releases/tag/v12.4.13) | Reconfirmed the retained exact versions. |
| Scanner | [Trivy `0.76.0`](https://github.com/aquasecurity/trivy/releases/tag/v0.76.0), [severity selection](https://trivy.dev/docs/v0.76/guide/scanner/vulnerability/#severity-selection) | Fixed the scanner version and interpretation boundary. |

The GitHub release timestamps also reconfirmed Kubernetes `1.35.8` (2026-08-20),
Helm `3.22.1` (2026-10-15), Gateway API `1.5.1` (2026-03-14), Istio
`1.30.6` (2026-10-15), Kiali `2.26.0` (2026-05-11), and Kyverno
`1.19.1` (2026-09-10).

### Istio and Kiali implementation review

The phase-2 implementation rendered Istio base, CNI, istiod, and gateway chart
`1.30.6` with Helm `3.22.1` against Kubernetes `1.35.8`. The repository values
continued to render the required Istio CNI, `REGISTRY_ONLY` outbound policy,
HTTP `ext_authz`, OpenTelemetry tracing provider, hardened ingress gateway, and
ClusterIP egress gateway contracts without a values migration. Gateway API
remained independently pinned at `v1.5.1`.

Kiali chart/application `2.26.0` was retained as the bounded first release in
the published compatibility table for Istio `1.30`. Its reviewed multi-platform
source digest is
`sha256:59cce98a9811ce53ff3da771225d1df00f0ca4ae0819311291ae7316349a13e9`;
the chart render keeps the tag and digest together, and the digest resolves to
the audited Linux ARM64 child recorded below. The `2.26.0` chart still emits
`deployment.image_digest` in invalid digest-before-tag order, so the existing
post-render normalization remains required.

The Jaeger workaround also remains intentional. Kiali `2.26.0` source still
removes the configured gRPC port before attempting its HTTP version fetch when
`use_grpc` is enabled. The checked-in values therefore keep gRPC trace queries
on `16685`, the HTTP health URL on `16686`, and
`disable_version_check: true`; this avoids a default-port probe that does not
match the repository's Jaeger Service contract.

### Kyverno implementation review

The phase-3 implementation rendered Kyverno chart `3.9.1` / application
`1.19.1` with Helm `3.22.1` against Kubernetes `1.35.8`. Local Tilt and the
offline production reference now consume the same values contract, so all
controller, init, CRD-migration, cleanup-hook, and Helm-test images resolve to
the seven reviewed immutable source-manifest digests recorded below. The chart
still lacks first-class digest fields; the values therefore retain the chart's
supported `repository@sha256` plus digest-as-tag encoding.

The old and new renders both contain 22 enabled CRDs, four single-replica
controller Deployments, three hook Jobs, and the same five Helm test Pods. The
upgrade keeps controller token behavior, resource requests and limits,
restricted container security contexts, runtime-default seccomp profiles, and
the `kyverno` namespace recovery exclusion. Repository policies remain
fail-closed with `validationFailureAction: Enforce`; no policy or exception was
relaxed for the chart upgrade. The chart's expanded migration resource list
for the existing `policies.kyverno.io` CRDs is retained as the compatible
`1.19.1` behavior.

## Exact Image And Scanner Evidence

### Method and interpretation

The audit used Docker client `29.1.3` registry manifest inspection to resolve
each source tag or checked-in multi-platform digest to its `linux/arm64` child.
Trivy was installed from the checksum-verified `0.76.0` Linux 64-bit release
archive and invoked with `--image-src remote --platform linux/arm64 --scanners
vuln`. The metadata for this reproduction was:

- Trivy: `0.76.0`;
- vulnerability database schema: `2`;
- database `UpdatedAt`: `2026-10-18 18:32:29.177029985 +0000 UTC`;
- database `DownloadedAt`: `2026-10-18 19:36:57.583293208 +0000 UTC`;
- scan window: 2026-10-18 19:37–19:45 UTC; and
- counts below: the number of Trivy vulnerability entries at `CRITICAL` and
  `HIGH`, across all reported OS and application-package result sets.

The counts are raw scanner observations. They do not establish that a package
or vulnerable function is reachable in this deployment. Conversely, a zero or
lower count does not prove that an image is risk-free. The source tag, source
manifest-list digest, selected platform child, database timestamp, package
inventory, runtime configuration, and upstream support status are distinct
facts. Full generated JSON remains disposable under `tmp/` and is not copied
into this record.

### Bounded upgrade candidates

These are the exact candidate artifacts inspected. Later implementation must
render immutable references derived from the reviewed source manifests and
must re-resolve if an upstream tag no longer matches this record.

| Candidate image | Source manifest digest | `linux/arm64` child scanned | Critical | High |
| --- | --- | --- | ---: | ---: |
| `registry.istio.io/release/pilot:1.30.6` | `sha256:3f9394ff46ad9504f5c6be60f1c8505c7d5a1420c95839f22a9ccc360b049e05` | `sha256:684a64a72b36083c8fefc1c075e9ec1739d0ae006f86f29f80cdc596ee8d5069` | 0 | 7 |
| `registry.istio.io/release/install-cni:1.30.6` | `sha256:42ba6555b79af757054b35e7480d17ce3325db72404372f25278786a075157fe` | `sha256:555fb2976675615448c7a6318d0cb5da66eda561196b3b706cf9667906bd0364` | 0 | 14 |
| `registry.istio.io/release/proxyv2:1.30.6` | `sha256:7c3f8161753a0c0f5033a37f84387d68248f828bfa5123368dd5949c443ca6c3` | `sha256:cd64b7879f1896bd2a2f64aae7cf4e5f76c5723134b0be801d32417b5d2d33da` | 0 | 7 |
| `quay.io/kiali/kiali:v2.26.0` | `sha256:59cce98a9811ce53ff3da771225d1df00f0ca4ae0819311291ae7316349a13e9` | `sha256:bc36f8247ea897d7b6f1618c2918b9eb85812660c4c28bed304b9510343290a9` | 0 | 57 |
| `reg.kyverno.io/kyverno/kyverno-cli:v1.19.1` | `sha256:ced7b2be0b04250cabfe695f15307f69eb715fe23234816388af4f3812915b2a` | `sha256:fd101671c097f84530ef3c29e7012b9fafbe37c89f6692775a600be4235d8bc9` | 0 | 4 |
| `reg.kyverno.io/kyverno/kyvernopre:v1.19.1` | `sha256:c25c47461f06f2845a48c319ae86fbbc1730a7b9ed5b701889c9dc1f9ee94b09` | `sha256:9ba91bfb01e5723a7f7e1ce355965f152ec9bc1f15e9fc998cbfb6221ba7fb9a` | 0 | 4 |
| `reg.kyverno.io/kyverno/kyverno:v1.19.1` | `sha256:b31d8511ae5fd6010e2a01ea72ebae08eb82fa51d91af14a1d9fe989949b4edb` | `sha256:befb22f62c32e1ba416d3d3a0d0db8731db339a39e30f2dfa8af47338ecd75d3` | 0 | 4 |
| `reg.kyverno.io/kyverno/background-controller:v1.19.1` | `sha256:8f1e9143373a27578cafc2d28d2c66ba0926c63b4c77e63de8d2fdd4a122859f` | `sha256:6e428b6d56ecc031d47083bf4df2accf268a051dedddeca60b91a1c58a6ffe35` | 0 | 4 |
| `reg.kyverno.io/kyverno/cleanup-controller:v1.19.1` | `sha256:67a48e62a8d8f8120c86914ff822b90017c54054c7b64ef8a1555645e9d9761e` | `sha256:4a725bdd920ce4f1415d573b53c0275ae1010f8ec194b7af28b4e549cfd6b336` | 0 | 4 |
| `reg.kyverno.io/kyverno/reports-controller:v1.19.1` | `sha256:c0eee97b9b44a0dd35805d56b358fa52548480f79d4944602b9609538eccd64c` | `sha256:939493f65bc02be82ed4134cd8d532f45d2c1030be3c55791c9c8f87c4e7933c` | 0 | 4 |
| `ghcr.io/kyverno/readiness-checker:v1.19.1` | `sha256:31bb42ce7f5b2e27c1cf633aeff4f0cad1f5bb63761e2cb09f0e25cdd26572bf` | `sha256:3f30c6fb3f03b9ad855a00c82b9b3ca94f901a96cfccdabecfdac2cb58f429f8` | 0 | 4 |

The current-to-candidate raw comparison was:

| Image | Current critical/high | Candidate critical/high | Decision basis |
| --- | ---: | ---: | --- |
| Istio pilot | `0 / 8` | `0 / 7` | Lifecycle and fixed security release, not the one-count reduction |
| Istio install-cni | `0 / 16` | `0 / 14` | Lifecycle and fixed security release |
| Istio proxyv2 | `0 / 8` | `0 / 7` | Lifecycle and fixed security release |
| Kiali | `0 / 61` | `0 / 57` | Published Istio `1.30` compatibility |
| Kyverno CLI | `0 / 28` | `0 / 4` | Upstream `1.19.1` security fixes plus scanner reduction |
| Kyverno pre-init | `0 / 25` | `0 / 4` | Same application release |
| Kyverno admission | `0 / 25` | `0 / 4` | Same application release |
| Kyverno background | `0 / 25` | `0 / 4` | Same application release |
| Kyverno cleanup | `0 / 25` | `0 / 4` | Same application release |
| Kyverno reports | `0 / 25` | `0 / 4` | Same application release |
| Kyverno readiness checker | `0 / 15` | `0 / 4` | Same chart release |

Current Istio `1.29.9` source-manifest digests were
`pilot@sha256:14bd7079a51b8589b1674476df1503f132d6b5c74c4af7d8a99401b62dd6e504`,
`install-cni@sha256:0e74dcca6e0582c4d25fbd50c3e0cde4ba51999e718daa2015d995bdbae7e412`,
and
`proxyv2@sha256:8dbf38609a1fea880ec347d1bec05a02f65bac3766fa9da11b2ae63c6430e256`.
Their scanned ARM64 children were respectively
`sha256:51b9915972c0864c186f7bfd24ba7f3df50ddd315abeb3691724e69f612ed1d8`,
`sha256:8a5d228230399411c8c8455324ce9994d9e059bf8776a965b8318660f5ba4b73`,
and
`sha256:e8199ddf1c9c8b23eb592d5d5d2f7cd177ee56e9735d898c02efee5ac1937447`.
The current Kiali source pin is
`quay.io/kiali/kiali:v2.24.0@sha256:744439cbdbbc23c7a5d70544911abf8fe0b32c88c082e9a41ae6b50748bf736e`;
its scanned ARM64 child was
`sha256:0c96c1b8156e051622a5667637f14c44e17c318afa5cba527b5835c390c6ecfb`.
The current Kyverno source-manifest pins and resolved children were:

| Current Kyverno image | Checked-in source digest | `linux/arm64` child scanned | Critical | High |
| --- | --- | --- | ---: | ---: |
| `reg.kyverno.io/kyverno/kyverno-cli` | `sha256:7224ed05508c24419c3df98114c28ba682ad0a940dcdb7b9fdba0a4b6bf943cf` | `sha256:b0f31e545d95b9b912158e8d0a422a8b8f6c101ab797c601f18887083bd476f9` | 0 | 28 |
| `reg.kyverno.io/kyverno/kyvernopre` | `sha256:cd8cb4a31d25b3992734fb8f24a90ef691c90ce49338c89bea96792160eacb98` | `sha256:862425a908ab26ff624ab5cc90cc4cff1ef1eb4f7078427774b22f69d8f8ca76` | 0 | 25 |
| `reg.kyverno.io/kyverno/kyverno` | `sha256:0a540e2ddf74d0d2d3d45f9ef248d7dbc96576accdbcc6a2dd7eaff9fea56504` | `sha256:80bc12c561d163abbfafc5aa13bf8985346cd68ceace44455ac50baeebdab9f2` | 0 | 25 |
| `reg.kyverno.io/kyverno/background-controller` | `sha256:d62566ce41bd0d4a32bf2cf44b9ebfc02c36374f821f83070890287f62f68671` | `sha256:1afb4319d148335042ac61dff55a116e2f99cd204253ec473417b09b2b048794` | 0 | 25 |
| `reg.kyverno.io/kyverno/cleanup-controller` | `sha256:b0395d29ae332276e6910eb40418be9bc127c068d659f90aa1bcddd6be99ccb4` | `sha256:9c80fbe7fef669f3656668aaf49a9ace6a33b1959594efbe7b80dc84077a5095` | 0 | 25 |
| `reg.kyverno.io/kyverno/reports-controller` | `sha256:f09cf305170014e191b94e1c54f5be73163d8824eefad49349675c4efe43159a` | `sha256:ba8a8f240fb0d3af1d36fb84e96f99d2f10abe7281255be7ee9ac8cd5a0f7767` | 0 | 25 |
| `ghcr.io/kyverno/readiness-checker` | `sha256:4fb1870b1a4adfed0fa7a32b7c3bcaf736fb889c7e1947ee8b20710bc2f5a5ce` | `sha256:5c74ed254d0ec59ea333ecdc810a59607c8acf2bc9b0b259427a1cbca1ad070d` | 0 | 15 |

### Monitoring comparisons and explicit deferral

| Image | Source manifest digest | `linux/arm64` child scanned | Critical | High | Authorization |
| --- | --- | --- | ---: | ---: | --- |
| kube-state-metrics `2.18.0` | `sha256:1545919b72e3ae035454fc054131e8d0f14b42ef6fc5b2ad5c751cafa6b2130e` | `sha256:9b14108e8db4069a2292a88fcba2ece7c3af5d2203ec7420498e8281cace5dfe` | 2 | 47 | Keep during this plan; ordered follow-up only |
| kube-state-metrics `2.20.0` | `sha256:42cfe3723a5f058171c627537fb57a3ea0f26e4380fa18555a95cb1a1b4cfc5b` | `sha256:92b46557c71ecac53825772e4827dbcd9fca876b1950060f8fb2f2ef0d7a27af` | 0 | 9 | Candidate only for the standalone kube-state-metrics plan |
| Prometheus Operator `0.90.1` | `sha256:52a6a92d915ea2fa94314748d99db7a94922e3fe63274f6182fc033b9126b573` | `sha256:14e7f4860dc407b771d85a7a38ca5c5c630a26f3b7d7acb4050b9e41a537b27a` | 0 | 31 | Keep |
| Prometheus Operator `0.94.1` | `sha256:7c88d4e7bae63bd8d0f8da986054337c23b4472fa8d3c6817f5bc4b8407a2d6a` | `sha256:635abf8c7159739b6f4cecd596b4dc7ff7bc92626e2793c31ccb34a1aa17b7f6` | 0 | 4 | Comparison only; no migration authorized |
| config reloader `0.90.1` | `sha256:693faa0b87243cddca2cffb13586e4e2778b0cdf319cb2e601ba7af3fd19ef7d` | `sha256:bee408c9865f8210e0ee9e018622f28af67784179e371727b968bdfa513f0ad9` | 0 | 41 | Keep |
| config reloader `0.94.1` | `sha256:06b52bd4dbe3ed6dd5905aadaf8b9987d9da4c31d37bb86deaadae68cee2d26b` | `sha256:7ae9a15097fc5481d91e3ac3a13453a5d797b5bea23655c25c696578ab71e508` | 0 | 4 | Comparison only; no migration authorized |
| Prometheus `3.11.3` | `sha256:c0b857aead0d5793aa566adb8f49a9983d6f6031652098759d521a330cfa050f` | `sha256:8737f27a6102141f06bd38e10e8908a8fa39a649cd187a2fee7c4b8429a366d6` | 0 | 86 | Keep |
| Prometheus `3.15.0-distroless` | `sha256:b2a413d5a03ea6a76782a508d1c7947440bba3b973931a25676e278431891b01` | `sha256:2d4ccd1dcd60d6b22e031ca791ef19d1f298a74153dbfd9cffb705a8ccfd92bc` | 0 | 8 | Comparison only; no migration authorized |
| Grafana `12.4.13` | `sha256:41bbc1b5e04416f81891806076db2a2ff60a5d4da5f78d36a88b033a8c199185` | `sha256:04ddb75abcf1584ac60149bf75a40b4d0a8dbe40bbdcf0b5c10a1ad6c0562634` | 0 | 5 | Keep |

The two kube-state-metrics critical entries had explicit fixed-version evidence:

| Vulnerability | Package | Installed | Trivy fixed version |
| --- | --- | --- | --- |
| `CVE-2026-33186` | `google.golang.org/grpc` | `v1.75.1` | `1.79.3` |
| `CVE-2025-68121` | Go standard library | `v1.25.5` | `1.24.13`, `1.25.7`, or `1.26.0-rc.3` |

The absence of these two critical entries from the `2.20.0` report is evidence
for prioritizing the narrow follow-up. It is not proof that those code paths
are reachable in `2.18.0`, and it is not a claim that `2.20.0` has no remaining
risk.

### Retained-family exact artifacts

| Family/image | Checked-in or rendered source | Resolved `linux/arm64` child | Critical | High |
| --- | --- | --- | ---: | ---: |
| Kubernetes node | `kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0` | `sha256:b38a25576c835bfedc9d06368f87ec40863459a4d5dcbdbab2fd5f58ecf97466` | 6 | 230 |
| cert-manager controller | `quay.io/jetstack/cert-manager-controller:v1.20.4` (`sha256:d4d576c7e6ed3cfe5730f5458fa096b7d8713368d2ccb7ff01b2951861483838` at audit time) | `sha256:5563efc514de80ac1ed524341831d758b40804bfd03a3be5cedacdd63e4c5ede` | 0 | 4 |
| cert-manager webhook | `quay.io/jetstack/cert-manager-webhook:v1.20.4` (`sha256:303a962e77acbed075716379ed8045de65a72fdd5514f9367f449a1f9a907aa7`) | `sha256:918afb8f769c001ee59224a340b5728fef8b785ed70387c9d00886fae6beddc2` | 0 | 4 |
| cert-manager cainjector | `quay.io/jetstack/cert-manager-cainjector:v1.20.4` (`sha256:30c8617ebb3b4a9054da555ee9c6389a7faa464fffe3c7679f80892a9cfbf213`) | `sha256:1b92e60be7a7654f79bf5caa475b4ed0693e36233665dd890dbeb8e4c192ff57` | 0 | 4 |
| cert-manager startup API check | `quay.io/jetstack/cert-manager-startupapicheck:v1.20.4` (`sha256:83e70f57255e133e2fff5129e8372ac493ca66e39446c536798b4742d95f9f49`) | `sha256:bd0a954fd4e4babb74a9047fe85de4ba0a3a7509cc2c360420e520e6bac32774` | 0 | 4 |
| cert-manager ACME solver | `quay.io/jetstack/cert-manager-acmesolver@sha256:bbec214d3935cbbeb3ab88c57ee36e2b2511a0017e48ffc14a999e48fa30d3a2` | `sha256:7e6743092eb4bac0ca9ed958e4535097a16bdcaebb6447b051b4ea50ee9195b7` | 0 | 4 |
| external-secrets controller/webhook/cert-controller | rendered `ghcr.io/external-secrets/external-secrets:v2.2.0`; source manifest `sha256:876e627dbee5b0edd12da49b035469d12418cd6c3c4be5e383ae6a82e8bd4565` | `sha256:c264979838ea3dca630ade3604000436a1f2d02585823c2e977dd07d20092e18` | 0 | 49 |

The node image illustrates the interpretation boundary: a large image can
produce many package findings while the product/version decision remains a
separate support and deployment judgment. The cert-manager controller images
and external-secrets chart rendered mutable tags even though the audit resolved
one exact registry manifest for scanning. This record does not convert that
point-in-time resolution into a durable deployment pin, and this phase does not
authorize changing those retained families.

Helm and Gateway API are release artifacts rather than runtime container
families in this repository, so they have release/checksum and rendered-CRD
evidence instead of container scan rows.

## Reproduction Summary

The following commands describe the evidence path without preserving generated
manifests, registry responses, image layers, caches, or full scanner JSON in
Git:

```bash
# Reconfirm active versions; exclude historical and runner-owned state.
rg -n --hidden \
  -g '!archive/oci/**' -g '!docs/archive/**' -g '!.ai-session-handler/**' \
  -g '!tmp/**' \
  '1\.35\.8|3\.22\.1|1\.5\.1|1\.29\.9|3\.8\.2|83\.4\.3|2\.24\.0|1\.20\.4|2\.2\.0|12\.4\.13|2\.18\.0|0\.90\.1|3\.11\.3' .

# Render the unchanged monitoring baseline, client-side only.
helm template prometheus-stack kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --namespace monitoring --version 83.4.3 \
  --values kubernetes/monitoring/prometheus-stack-values.yaml \
  --kube-version 1.35.8 \
  --post-renderer scripts/ops/post-render-prometheus-stack.sh

# Reproduce all checked-in exact-image inputs without contacting Kubernetes.
./scripts/security/render-image-scan-inputs.sh \
  --output-dir tmp/platform-security-audit-2026-10-18/current-scan-inputs \
  --local-platform linux/amd64

# Resolve a source tag to its platform-specific child.
docker manifest inspect --verbose IMAGE:TAG

# After checksum-verifying the Trivy 0.76.0 release and downloading its DB:
TRIVY_CACHE_DIR=tmp/platform-security-audit-2026-10-18/trivy-cache \
  tmp/platform-security-audit-2026-10-18/tools/trivy image \
  --image-src remote --platform linux/arm64 --scanners vuln \
  --format json --output tmp/platform-security-audit-2026-10-18/report.json \
  REPOSITORY@PLATFORM_CHILD_DIGEST
```

Registry manifests are mutable when addressed only by tag. A future
reproduction should report changed digests or database results honestly rather
than forcing these counts to match.

## Integrated Local And Offline Validation — 2026-10-19

The bounded upgrade set was reconciled through the supported daily Tilt path
on the authorized local target. The native-runtime preflight proved the exact
`kind-kind` context and referenced cluster, loopback HTTPS API authority with no
proxy override, local `kind` cluster, and Ready `kind-control-plane` before the
live checks ran. The cluster was not recreated, PVC-backed data was not reset,
and no TLS material was generated or rotated.

The final source, offline render, Helm release, and live workload evidence was:

| Family | Final evidence |
| --- | --- |
| Kubernetes / Kind | `kind-control-plane` Ready on Kubernetes `1.35.8`; the checked-in `kindest/node:v1.35.8` digest remained unchanged |
| Helm | repository-pinned client `3.22.1` used by the final static and chart renders |
| Gateway API | live CRD bundle label `v1.5.1` |
| Istio | deployed Helm releases `istio-base`, `istio-cni`, `istiod`, and `istio-egress-gateway` at chart/app `1.30.6`; live CNI, pilot, ingress proxy, and egress proxy workloads Ready |
| Kiali | deployed chart/app `2.26.0`; live image `quay.io/kiali/kiali:v2.26.0@sha256:59cce98a9811ce53ff3da771225d1df00f0ca4ae0819311291ae7316349a13e9` Ready |
| Kyverno | deployed chart `3.9.1` / app `1.19.1`; all four controllers Ready and the migration Job complete on the reviewed immutable image set |
| Monitoring | deployed kube-prometheus-stack chart `83.4.3`; Operator and config reloader `0.90.1`, Prometheus `3.11.3`, kube-state-metrics `2.18.0`, and Grafana `12.4.13` retained and Ready |
| Retained controllers | final exact-image render retained cert-manager `1.20.4` and external-secrets `2.2.0` |

All Tilt UI resources reported Ready. All expected workload pods were Ready,
the completed Kyverno migration Job was the only expected non-running pod, and
Grafana, Prometheus, Jaeger, and Kiali Services remained `ClusterIP`-only.

Final validation passed:

- the pinned-PyYAML static security verifier and its intentional-failure
  self-test, the provider-neutral production-reference verifier, and a fresh
  exact-image input render for `linux/arm64`;
- Bash syntax and ShellCheck for every shell file changed by this plan;
- focused ingress/egress, tracing, monitoring render/runtime, loopback-only
  observability access, complete static/runtime security, and Prometheus
  Operator least-privilege verifiers; and
- `./scripts/smoketest/smoketest.sh` as the final integrated local proof,
  including 55 shared-session checks, 96 ingress/egress checks, both 69-check
  NetworkPolicy matrices, and the 176-check runtime-hardening regression
  cascade.

The first least-privilege invocation followed the intentionally high-volume
security denial probes closely enough that Kiali's rolling health window still
classified several apps, including `monitoring/prometheus`, as failures. Direct
Prometheus targets, metrics, and Kiali's Prometheus/Jaeger integrations were
healthy. Without changing a threshold or control, the bounded monitoring
runtime poll passed after the probe traffic aged out, and the complete
least-privilege verifier then passed all 31 checks. This is sequencing evidence,
not an accepted health exception.

Concise logs and generated render inputs are retained only under ignored
`tmp/audit-driven-platform-security-remediation/` paths. The production
reference was rendered and verified offline; this evidence does not claim a
hosted production deployment or runtime parity.

The scanner interpretation boundary remains unchanged after runtime
acceptance. Raw package findings and count reductions do not demonstrate
reachability, and a zero or lower count does not establish that an image is
risk-free. Exact source manifests, selected `linux/arm64` children, scanner and
database metadata, runtime configuration, and upstream support status remain
separate evidence.

## Ordered Handoff

The Istio/Kiali and Kyverno upgrades and their plan-level validation are
complete. The only ordered monitoring remediation is
[`docs/plans/kube-state-metrics-security-remediation.md`](../plans/kube-state-metrics-security-remediation.md).
That follow-up keeps kube-prometheus-stack `83.4.3`, Prometheus Operator and
config reloader `0.90.1`, Prometheus `3.11.3`, Grafana `12.4.13`, the current
CRDs/RBAC, and all other monitoring behavior unchanged; it may change only the
kube-state-metrics image after compatibility, render-diff, ARM64, and scanner
proof.

No Operator, Prometheus, Grafana, parent-chart, CRD, RBAC, values,
post-renderer, or other monitoring migration is implied by this record.
