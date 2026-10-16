#!/usr/bin/env bash

# Shared dependency versions for the provider-neutral production reference.
# These pins support offline rendering, static validation, and image evidence;
# they do not identify a live cluster or prescribe a Kubernetes distribution.

export PRODUCTION_VERSION_CONTRACT_EFFECTIVE_DATE="2026-04-15"
readonly PRODUCTION_VERSION_CONTRACT_EFFECTIVE_DATE

# The Kubernetes API compatibility target is retained from the final OCI/k3s
# baseline without retaining k3s installation or lifecycle ownership.
export PRODUCTION_KUBERNETES_VERSION="1.34.6"
readonly PRODUCTION_KUBERNETES_VERSION

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
export PRODUCTION_GATEWAY_API_CRDS_VERSION="v1.5.1"
readonly PRODUCTION_GATEWAY_API_CRDS_VERSION
export PRODUCTION_GATEWAY_API_STANDARD_INSTALL_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${PRODUCTION_GATEWAY_API_CRDS_VERSION}/standard-install.yaml"
readonly PRODUCTION_GATEWAY_API_STANDARD_INSTALL_URL

# renovate: datasource=helm depName=base registryUrl=https://istio-release.storage.googleapis.com/charts
export PRODUCTION_ISTIO_CHART_VERSION="1.29.2"
readonly PRODUCTION_ISTIO_CHART_VERSION
export PRODUCTION_ISTIO_HELM_REPO_URL="https://istio-release.storage.googleapis.com/charts"
readonly PRODUCTION_ISTIO_HELM_REPO_URL

# renovate: datasource=helm depName=external-secrets registryUrl=https://charts.external-secrets.io
export PRODUCTION_EXTERNAL_SECRETS_CHART_VERSION="2.2.0"
readonly PRODUCTION_EXTERNAL_SECRETS_CHART_VERSION
export PRODUCTION_EXTERNAL_SECRETS_HELM_REPO_URL="https://charts.external-secrets.io"
readonly PRODUCTION_EXTERNAL_SECRETS_HELM_REPO_URL

# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
export PRODUCTION_CERT_MANAGER_CHART_VERSION="v1.20.2"
readonly PRODUCTION_CERT_MANAGER_CHART_VERSION
export PRODUCTION_CERT_MANAGER_HELM_REPO_URL="https://charts.jetstack.io"
readonly PRODUCTION_CERT_MANAGER_HELM_REPO_URL

# renovate: datasource=helm depName=kyverno registryUrl=https://kyverno.github.io/kyverno/
export PRODUCTION_KYVERNO_CHART_VERSION="3.8.0"
readonly PRODUCTION_KYVERNO_CHART_VERSION
export PRODUCTION_KYVERNO_HELM_REPO_URL="https://kyverno.github.io/kyverno/"
readonly PRODUCTION_KYVERNO_HELM_REPO_URL

# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
export PRODUCTION_PROMETHEUS_STACK_CHART_VERSION="83.4.0"
readonly PRODUCTION_PROMETHEUS_STACK_CHART_VERSION
export PRODUCTION_PROMETHEUS_STACK_HELM_REPO_URL="https://prometheus-community.github.io/helm-charts"
readonly PRODUCTION_PROMETHEUS_STACK_HELM_REPO_URL

# renovate: datasource=helm depName=kiali-server registryUrl=https://kiali.org/helm-charts
export PRODUCTION_KIALI_CHART_VERSION="2.24.0"
readonly PRODUCTION_KIALI_CHART_VERSION
export PRODUCTION_KIALI_HELM_REPO_URL="https://kiali.org/helm-charts"
readonly PRODUCTION_KIALI_HELM_REPO_URL

export PRODUCTION_POD_SECURITY_VERSION="v1.32"
readonly PRODUCTION_POD_SECURITY_VERSION

