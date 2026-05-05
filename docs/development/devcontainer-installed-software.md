# Devcontainer Installed Software

This document tracks the current devcontainer tooling baseline provided by the
sibling `workspace/ai-agent-sandbox/Dockerfile` used for Budget Analyzer
development.

## Command-Line Tools

| Tool | Version | Installation Method |
|---|---|---|
| Kind | `v0.31.0` | Downloaded binary from GitHub releases |
| kubectl | `v1.35` apt repo | Installed from the Kubernetes apt repository |
| Helm | `v3.20.1` | Downloaded from `get.helm.sh` and verified with a checked-in SHA-256 |
| Tilt | `0.37.3` | Downloaded from GitHub releases and verified with a checked-in SHA-256 |
| Node.js | `20.x` | Installed from the signed NodeSource apt repository |

## Kubernetes Components (via Helm)

| Component | Chart Version | Namespace |
|---|---|---|
| cert-manager | `v1.13.2` | `cert-manager` |
| Istio Base | `1.29.2` | `istio-system` |
| Istio CNI | `1.29.2` | `istio-system` |
| istiod | `1.29.2` | `istio-system` |
| Istio Gateway (egress) | `1.29.2` | `istio-egress` |

`istio/gateway` `1.29.2` is installed directly from Helm in this repo's steady
state. The egress gateway uses
[`kubernetes/istio/egress-gateway-values.yaml`](../../kubernetes/istio/egress-gateway-values.yaml)
to keep `service.type=ClusterIP` and pod `seccompProfile.type: RuntimeDefault`.
The ingress gateway remains auto-provisioned from Gateway API and is hardened
through
[`kubernetes/istio/ingress-gateway-config.yaml`](../../kubernetes/istio/ingress-gateway-config.yaml).
