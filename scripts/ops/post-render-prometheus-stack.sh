#!/usr/bin/env bash
# Helm post-renderer for the prometheus-community/kube-prometheus-stack chart.
#
# The upstream chart does not expose a repo-suitable Prometheus Operator RBAC
# shape. This renderer removes the broad operator ClusterRole/ClusterRoleBinding
# pair and replaces them with:
# - one narrow ClusterRole for unavoidable cluster-scoped reads
# - a monitoring namespace Role/RoleBinding for operator-owned writes
# - a default namespace Role/RoleBinding for read-only monitoring CR access

set -euo pipefail

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

rendered_file="${tmp_dir}/all.yaml"
overlay_file="${tmp_dir}/operator-rbac.yaml"

cat > "${rendered_file}"

cat > "${overlay_file}" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-stack-kube-prom-operator-cluster-read
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/instance: prometheus-stack
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/component: prometheus-operator
    app.kubernetes.io/name: kube-prometheus-stack-prometheus-operator
rules:
  - apiGroups:
      - ""
    resources:
      - namespaces
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - list
      - watch
  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - storage.k8s.io
    resources:
      - storageclasses
    verbs:
      - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-stack-kube-prom-operator-cluster-read
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/instance: prometheus-stack
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/component: prometheus-operator
    app.kubernetes.io/name: kube-prometheus-stack-prometheus-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-stack-kube-prom-operator-cluster-read
subjects:
  - kind: ServiceAccount
    name: prometheus-stack-kube-prom-operator
    namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: prometheus-stack-kube-prom-operator-monitoring
  namespace: monitoring
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/instance: prometheus-stack
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/component: prometheus-operator
    app.kubernetes.io/name: kube-prometheus-stack-prometheus-operator
rules:
  - apiGroups:
      - monitoring.coreos.com
    resources:
      - prometheuses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - monitoring.coreos.com
    resources:
      - prometheuses/finalizers
      - prometheuses/status
    verbs:
      - update
      - patch
  - apiGroups:
      - monitoring.coreos.com
    resources:
      - alertmanagers
      - alertmanagerconfigs
      - podmonitors
      - probes
      - prometheusagents
      - prometheusrules
      - scrapeconfigs
      - servicemonitors
      - thanosrulers
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - apps
    resources:
      - statefulsets
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - ""
    resources:
      - configmaps
      - secrets
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - list
      - delete
  - apiGroups:
      - ""
    resources:
      - endpoints
      - services
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - ""
    resources:
      - services/finalizers
    verbs:
      - update
  - apiGroups:
      - discovery.k8s.io
    resources:
      - endpointslices
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
  - apiGroups:
      - ""
      - events.k8s.io
    resources:
      - events
    verbs:
      - create
      - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: prometheus-stack-kube-prom-operator-monitoring
  namespace: monitoring
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/instance: prometheus-stack
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/component: prometheus-operator
    app.kubernetes.io/name: kube-prometheus-stack-prometheus-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: prometheus-stack-kube-prom-operator-monitoring
subjects:
  - kind: ServiceAccount
    name: prometheus-stack-kube-prom-operator
    namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: prometheus-stack-kube-prom-operator-default-read
  namespace: default
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/instance: prometheus-stack
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/component: prometheus-operator
    app.kubernetes.io/name: kube-prometheus-stack-prometheus-operator
rules:
  - apiGroups:
      - monitoring.coreos.com
    resources:
      - podmonitors
      - probes
      - prometheusrules
      - scrapeconfigs
      - servicemonitors
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
      - events.k8s.io
    resources:
      - events
    verbs:
      - create
      - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: prometheus-stack-kube-prom-operator-default-read
  namespace: default
  labels:
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/instance: prometheus-stack
    app.kubernetes.io/part-of: kube-prometheus-stack
    app.kubernetes.io/component: prometheus-operator
    app.kubernetes.io/name: kube-prometheus-stack-prometheus-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: prometheus-stack-kube-prom-operator-default-read
subjects:
  - kind: ServiceAccount
    name: prometheus-stack-kube-prom-operator
    namespace: monitoring
EOF

cat > "${tmp_dir}/kustomization.yaml" <<'EOF'
resources:
  - all.yaml
  - operator-rbac.yaml
patches:
  - target:
      group: rbac.authorization.k8s.io
      version: v1
      kind: ClusterRole
      name: prometheus-stack-kube-prom-operator
    patch: |-
      $patch: delete
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      metadata:
        name: prometheus-stack-kube-prom-operator
  - target:
      group: rbac.authorization.k8s.io
      version: v1
      kind: ClusterRoleBinding
      name: prometheus-stack-kube-prom-operator
    patch: |-
      $patch: delete
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      metadata:
        name: prometheus-stack-kube-prom-operator
EOF

kubectl kustomize "${tmp_dir}"
