# Devcontainer Installed Software

This document tracks all software that has been manually installed within the devcontainer environment by the AI agent to support the Tilt + Kind development setup. This helps in understanding the environment's dependencies and makes it easier to add them to the devcontainer configuration later.

## Command-Line Tools

| Tool | Version | Installation Method |
|---|---|---|
| Kind | `v0.30.0` | Downloaded binary from GitHub releases |
| kubectl | latest stable | Downloaded binary from Kubernetes release artifacts|
| Helm | `v3.20.1` | Installed with `get-helm-3` pinned via `DESIRED_VERSION=v3.20.1` |
| iputils-ping| latest from apt| `apt-get install iputils-ping` |

## Kubernetes Components (via Helm)

| Component | Chart Version | Namespace |
|---|---|---|
| cert-manager | `v1.13.2` | `cert-manager` |
| Istio Base | `1.29.1` | `istio-system` |
| Istio CNI | `1.29.1` | `istio-system` |
| istiod | `1.29.1` | `istio-system` |
| Istio Gateway (egress) | `1.29.1` | `istio-egress` |

`istio/gateway` `1.29.1` is installed directly from Helm in this repo's steady
state. The egress gateway uses
[`kubernetes/istio/egress-gateway-values.yaml`](../../kubernetes/istio/egress-gateway-values.yaml)
to keep `service.type=ClusterIP` and pod `seccompProfile.type: RuntimeDefault`.
The ingress gateway remains auto-provisioned from Gateway API and is hardened
through
[`kubernetes/istio/ingress-gateway-config.yaml`](../../kubernetes/istio/ingress-gateway-config.yaml).
