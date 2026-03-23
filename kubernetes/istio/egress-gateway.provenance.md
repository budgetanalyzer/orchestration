# Istio Egress Gateway Manifest Provenance

`kubernetes/istio/egress-gateway.yaml` is a checked-in render of the upstream
`istio/gateway` chart at version `1.24.3`.

Render command:

```bash
helm template istio-egress-gateway istio/gateway \
  --version 1.24.3 \
  --namespace istio-egress \
  --set service.type=ClusterIP \
  --skip-schema-validation
```

Why this is checked in instead of installed directly from Helm:

- Helm `v3.20.1` reproduces a chart-schema failure for the required
  `service.type=ClusterIP` override:
  `additional properties 'service', '_internal_defaults_do_not_set' not allowed`
- The remediation plan rejects `--skip-schema-validation` as a steady-state
  Tilt dependency
- Vendoring the rendered manifest keeps the egress gateway topology and labels
  aligned with the upstream chart while removing the runtime schema bypass
