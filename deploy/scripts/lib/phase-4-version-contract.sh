#!/usr/bin/env bash

# Shared version contract for the Oracle Cloud production install path.
# Source this file from deploy/scripts/*.sh instead of duplicating version pins.

export PHASE4_VERSION_CONTRACT_EFFECTIVE_DATE="2026-04-15"
readonly PHASE4_VERSION_CONTRACT_EFFECTIVE_DATE

# Selection rule:
# - prefer the upstream stable or explicitly supported release line
# - then take the latest patch in that line
# - do not automatically follow a project's latest channel or a newly
#   published minor release

export PHASE4_K3S_VERSION="v1.34.6+k3s1"
readonly PHASE4_K3S_VERSION
export PHASE4_K3S_INSTALL_URL="https://get.k3s.io"
readonly PHASE4_K3S_INSTALL_URL
export PHASE4_GATEWAY_API_CRDS_VERSION="v1.4.0"
readonly PHASE4_GATEWAY_API_CRDS_VERSION
export PHASE4_GATEWAY_API_STANDARD_INSTALL_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${PHASE4_GATEWAY_API_CRDS_VERSION}/standard-install.yaml"
readonly PHASE4_GATEWAY_API_STANDARD_INSTALL_URL
export PHASE4_ISTIO_CHART_VERSION="1.29.2"
readonly PHASE4_ISTIO_CHART_VERSION
export PHASE4_ISTIO_HELM_REPO_URL="https://istio-release.storage.googleapis.com/charts"
readonly PHASE4_ISTIO_HELM_REPO_URL
export PHASE4_EXTERNAL_SECRETS_CHART_VERSION="2.2.0"
readonly PHASE4_EXTERNAL_SECRETS_CHART_VERSION
export PHASE4_EXTERNAL_SECRETS_HELM_REPO_URL="https://charts.external-secrets.io"
readonly PHASE4_EXTERNAL_SECRETS_HELM_REPO_URL
export PHASE4_CERT_MANAGER_CHART_VERSION="v1.20.2"
readonly PHASE4_CERT_MANAGER_CHART_VERSION
export PHASE4_CERT_MANAGER_HELM_REPO_URL="https://charts.jetstack.io"
readonly PHASE4_CERT_MANAGER_HELM_REPO_URL
export PHASE7_KYVERNO_CHART_VERSION="3.7.1"
readonly PHASE7_KYVERNO_CHART_VERSION
export PHASE7_KYVERNO_HELM_REPO_URL="https://kyverno.github.io/kyverno/"
readonly PHASE7_KYVERNO_HELM_REPO_URL
export PHASE4_POD_SECURITY_VERSION="v1.32"
readonly PHASE4_POD_SECURITY_VERSION

# Intentional exceptions:
# - Gateway API stays on v1.4.0 until the repo validates a newer CRD bundle
#   against the current Istio and Gateway baseline.
# - External Secrets stays on 2.2.0 until the project explicitly documents a
#   newer supported stable minor.
