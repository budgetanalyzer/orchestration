# Kiali Expected Warnings

Operational reference for Kiali warnings that this repo currently treats as
expected noise rather than actionable failures.

Use this document with `./scripts/ops/triage-kiali-findings.sh`. If a warning
listed here appears and the stated assumptions still hold, treat it as expected.
If those assumptions no longer hold, re-evaluate it as a real issue.

## Expected Warnings We Ignore

### `ext-authz` service detail shows no Istio config

Observed UI pattern:

- `No Istio Config found for ext-authz`

Why we ignore it:

- The repo wires `ext-authz` into Istio through the mesh-wide
  `extensionProviders` entry in `kubernetes/istio/istiod-values.yaml`, not
  through a service-local `VirtualService`, `DestinationRule`, or similar
  traffic object.
- The ingress attachment happens through the `CUSTOM`
  `AuthorizationPolicy` in `kubernetes/istio/ext-authz-policy.yaml`, while the
  workload service itself is still a plain Kubernetes `Service`.
- Kiali's service detail Istio Config view does not treat that mesh-global
  extension-provider wiring as service-attached Istio config, so the empty
  state is expected for `ext-authz`.

When to revisit:

- The repo moves `ext-authz` to service-local Istio traffic configuration and
  Kiali should then show attached config on the service detail page.
- Upstream Kiali gains first-class visibility for
  `meshConfig.extensionProviders` on service detail pages.
- The message appears for other services that are expected to have ordinary
  attached Istio config.

### `KIA1317` in non-ambient namespaces

Message:

- `This workload has Authorization Policies but no Waypoint`

Why we ignore it:

- This repo runs a sidecar-based Istio mesh, not an ambient mesh.
- Kiali reports this warning even when the namespace is not ambient.
- The repo intentionally uses `AuthorizationPolicy` without waypoint resources
  in `default` and `istio-ingress`.

When to revisit:

- The namespace is actually ambient.
- The repo adopts waypoint-based policy enforcement.
- Kiali changes the meaning of `KIA1317` for sidecar meshes.

### Missing additional CA bundle file at Kiali startup

Observed log pattern:

- `Unable to read CA bundle [/kiali-cabundle/additional-ca-bundle.pem]`

Why we ignore it:

- The repo does not rely on a custom extra CA bundle for Kiali.
- Kiali starts, authenticates, and serves its APIs without that file.
- Adding a dummy mount just to suppress the warning would be configuration
  noise, not a real fix.

When to revisit:

- Kiali starts depending on a custom CA bundle for Prometheus, Jaeger, or the
  Kubernetes API.
- TLS failures show that this missing file is no longer harmless.

### Missing `mutatingwebhookconfigurations` read permissions

Observed log pattern:

- `Unable to list webhooks for cluster [Kubernetes]. Give Kiali permission to read 'mutatingwebhookconfigurations'.`

Why we ignore it:

- The repo intentionally keeps Kiali namespace-scoped.
- [`kubernetes/monitoring/kiali-values.yaml`](../../kubernetes/monitoring/kiali-values.yaml)
  sets `cluster_wide_access: false`.
- Widening Kiali to cluster-scoped webhook reads would weaken the current
  least-privilege posture for little value.

When to revisit:

- A workflow explicitly requires webhook inspection from Kiali.
- The repo approves broader RBAC for Kiali.

## Warnings We Do Not Ignore

Examples that still require investigation:

- unhealthy external integrations in Kiali's `Istio Status`
- `monitoring/prometheus` health failures
- missing `jaeger-query` service when tracing is enabled
- missing workload version information for the tracked app workloads in
  `default`. The shared Deployment manifests are expected to stamp
  `version: v1` on workload metadata and pod templates for Kiali grouping.
- `KIA0004` for `AuthorizationPolicy/default/budget-analyzer-web-policy` on
  OCI production. That policy is stale drift there because production serves
  the frontend from `nginx-gateway` instead of a standalone
  `budget-analyzer-web` workload.
- validation findings caused by absent pods, services, or service accounts
  after cluster bring-up should have completed
