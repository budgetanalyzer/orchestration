# 008. OCI Public Ingress Uses a Network Load Balancer Instead of Host Redirects

**Date:** 2026-04-16
**Status:** Accepted
**Deciders:** Architecture Team

## Context

The original Phase 4 OCI deployment plan exposed the Istio ingress gateway by
adding host `iptables` `nat/PREROUTING` redirects from public port `80` to the
Gateway API-managed ingress `NodePort` on `30080`. That choice was attractive
because it looked minimal:

- no extra OCI resource
- no additional daemon on the host
- no host TLS termination
- easy to express in a small idempotent script

The live debugging work on 2026-04-16 proved that this design does not behave
correctly on the current OCI host:

1. Direct non-loopback NodePort access works. `curl http://10.0.0.8:30080/`
   returns `HTTP/1.1 404 Not Found` from `istio-envoy`, and `tcpdump` shows the
   packet entering the pod datapath normally.
2. The public packet reaches the instance and matches the host `PREROUTING`
   redirect rule, so OCI routing and the public security list are not the
   blocker.
3. The redirected packet then falls into the host-local `INPUT` path instead of
   becoming the same working NodePort service flow.
4. Adding a temporary `INPUT dpt:30080 ACCEPT` rule changes the public failure
   from `ICMP admin prohibited` to `Connection refused`, which proves the kernel
   is trying host-local delivery to port `30080` rather than kube-proxy service
   handling.

At the same time, preserving the original client IP at the ingress gateway is a
hard requirement. This is not a "just get it working" environment; it is meant
to demonstrate a production-shaped ingress design that can scale from one node
to multiple nodes with minimal architectural change.

## Decision

Public ingress on OCI will use a public layer-4 Network Load Balancer in front
of the Istio ingress gateway NodePorts.

Specifically:

1. The host `iptables` redirect path from Step 15 remains documented only as a
   historical experiment and must be cleaned up before the steady-state public
   ingress path is introduced.
2. The ingress gateway remains the real edge component for routing, TLS, and
   policy; the OCI public entry point is a TCP load balancer, not an L7 reverse
   proxy.
3. The checked-in ingress Service configuration must use
   `externalTrafficPolicy: Local` so the ingress gateway preserves the original
   client source IP.
4. Phase 4 stays HTTP-only. The OCI NLB needs only the `80 -> 30080` listener
   and backend path during Phase 4. Phase 11 adds the HTTPS listener and the
   `30443` backend path.
5. The OCI security boundary must allow only the backend path the NLB actually
   needs. NodePorts must not be opened broadly to `0.0.0.0/0`.

## Alternatives Considered

### Alternative 1: Host `iptables` `REDIRECT` to the ingress NodePort
**Pros:**
- Minimal moving parts on paper.
- No extra OCI resource.
- Easy to script and persist.

**Cons:**
- Proven incorrect on the current OCI host: the redirected packet became
  host-local traffic instead of a working NodePort service flow.
- Couples public ingress to host firewall behavior rather than the cloud/K8s
  ingress shape.
- Does not provide a convincing future multi-node story.

### Alternative 2: Tiny host TCP proxy or binder on ports `80` and `443`
**Pros:**
- Operationally simple.
- More predictable than the broken `REDIRECT` path.

**Cons:**
- A naive proxy hides the original client IP from the ingress gateway.
- Preserving client IP would require extra PROXY protocol or transparent-proxy
  complexity that does not improve the architecture.
- Still makes the host itself part of the ingress design.

### Alternative 3: `hostNetwork` or `hostPort` on the ingress gateway
**Pros:**
- Can preserve client IP.
- Removes the extra public load-balancer layer.

**Cons:**
- More node-centric than cloud-native.
- Couples ingress scheduling to specific host ports.
- Less representative of the standard "external load balancer -> ingress
  gateway -> services" production pattern.

### Alternative 4: OCI HTTP(S) Load Balancer in front of the cluster
**Pros:**
- Common managed-cloud ingress pattern.
- Rich L7 features at the cloud edge.

**Cons:**
- Moves more edge behavior out of Istio and into the cloud load balancer.
- Client identity is carried by forwarded headers rather than preserved as the
  packet source address.
- Less aligned with the requirement to keep Istio as the real edge.

## Consequences

**Positive:**
- The public ingress story now matches the common production cloud pattern:
  external L4 load balancer -> ingress gateway -> services.
- The architecture scales from one ingress node to multiple ingress nodes with
  minimal design change.
- Client IP preservation becomes an explicit, verifiable requirement instead of
  an accidental byproduct of host firewall tricks.
- The OCI VM stops carrying a special-purpose public ingress hack that would be
  hard to defend in a portfolio review.

**Negative:**
- OCI now has an additional public infrastructure resource to provision and
  document.
- The repo must maintain the ingress service settings and OCI security rules
  needed for the NLB backend path.
- Phase 4 operator steps become slightly longer because they now include both
  host cleanup and NLB creation.

**Neutral:**
- Step 15 is not deleted from the plan; it remains as a recorded experiment for
  historical continuity and debugging context.
- Phase 11 still owns the HTTPS listener and TLS secret wiring. This decision
  changes the public exposure mechanism, not the phase boundary.

## References
- [Oracle Cloud Deployment Plan](../plans/oracle-cloud-deployment-plan.md)
- [Oracle Cloud Deployment Debugging Plan](../plans/oracle-cloud-deployment-debugging-plan.md)
- [Kubernetes: Source IP for Services](https://kubernetes.io/docs/tutorials/services/source-ip/)
- [Istio: Ingress Access Control - Network Load Balancer](https://preliminary.istio.io/latest/docs/tasks/security/authorization/authz-ingress/)
- [OCI: Configuring Load Balancers and Network Load Balancers](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengconfiguringloadbalancersnetworkloadbalancers-subtopic.htm)
