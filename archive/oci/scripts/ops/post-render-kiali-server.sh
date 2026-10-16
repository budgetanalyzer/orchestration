#!/usr/bin/env bash
# Helm post-renderer for the kiali/kiali-server chart.
#
# The chart owns the Kiali RBAC/service/config resources, while this renderer
# applies repo-required pod hardening that the chart does not currently expose
# as values.

set -euo pipefail

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

rendered_file="${tmp_dir}/all.yaml"

# kiali-server 2.24.0 renders deployment.image_digest as
# image@sha256:<digest>:<tag>. Normalize that to the valid OCI form
# image:<tag>@sha256:<digest> before applying the manifest.
sed -E \
    's#(image:[[:space:]]*"?)(quay\.io/kiali/kiali)@sha256:([a-f0-9]{64}):([^"[:space:]]+)("?)#\1\2:\4@sha256:\3\5#' \
    > "${rendered_file}"

cat > "${tmp_dir}/kustomization.yaml" <<'EOF'
resources:
  - all.yaml
patches:
  - target:
      group: apps
      version: v1
      kind: Deployment
      name: kiali
    patch: |-
      - op: add
        path: /spec/template/spec/automountServiceAccountToken
        value: false
      - op: add
        path: /spec/template/spec/securityContext
        value:
          seccompProfile:
            type: RuntimeDefault
      - op: add
        path: /spec/template/spec/volumes/-
        value:
          name: kiali-api-token
          projected:
            defaultMode: 420
            sources:
              - serviceAccountToken:
                  expirationSeconds: 3600
                  path: token
              - configMap:
                  name: kube-root-ca.crt
                  items:
                    - key: ca.crt
                      path: ca.crt
              - downwardAPI:
                  items:
                    - path: namespace
                      fieldRef:
                        apiVersion: v1
                        fieldPath: metadata.namespace
      - op: add
        path: /spec/template/spec/containers/0/volumeMounts/-
        value:
          name: kiali-api-token
          mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          readOnly: true
EOF

kubectl kustomize "${tmp_dir}"
