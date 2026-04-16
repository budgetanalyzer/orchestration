# Oracle Cloud Deployment Debugging Plan

**Date:** 2026-04-16
**Status:** Findings captured; forward path moved into the main deployment plan
**Scope:** Phase 4 Chunk 4 Step 15 host ingress wiring on the OCI instance
**Related plan:** [`oracle-cloud-deployment-plan.md`](./oracle-cloud-deployment-plan.md#15-human-add-the-host-iptables-redirects-after-the-ingress-nodeports-exist)

This document records the Phase 4 OCI ingress-debugging thread so the work is restartable from a known baseline. It now captures the final findings from the Step 15 investigation, the cleanup required to remove the failed host-redirect path, and the design conclusion that pushed the forward plan toward an OCI Network Load Balancer.

## Problem Statement

Phase 4 Chunk 4 Step 15 is intended to expose the HTTP ingress listener through a host-level `iptables` redirect:

- public host port `80`
- redirected to the auto-provisioned Istio ingress `NodePort`
- currently `30080`

The Step 15 failure sequence eventually proved to be:

- from the workstation, public `curl http://152.70.145.68/` first failed with `No route to host`
- after targeted host debugging, the same public path failed with `Connection refused`
- on the OCI instance, `tcpdump` showed the public SYN arriving on the host every time

That means OCI routing and the public IP were never the primary blocker. The packet was reaching the instance, and the failure was in the host-local handling of the redirect-to-NodePort design itself.

## Confirmed Facts

These are backed by command output captured during the current debugging session.

1. The auto-provisioned ingress Service exists and currently exposes only HTTP for Phase 4.
   - `kubectl get svc -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway -o wide`
   - Observed service ports included `80:30080/TCP`.

2. The ingress listener is alive on the instance when addressed directly via both loopback and the instance private IP NodePort.
   - `curl -I --max-time 5 http://127.0.0.1:30080/`
   - `curl -I --max-time 5 http://10.0.0.8:30080/`
   - Result: `HTTP/1.1 404 Not Found` from `istio-envoy`
   - Interpretation: Envoy is listening, and the non-loopback NodePort path itself is valid. `404` is acceptable here because the request did not include a matching production Host/path.

3. The host NAT redirect is present in `nat/PREROUTING`, and external traffic does hit it.
   - `sudo iptables -t nat -S PREROUTING`
   - `sudo iptables -t nat -L PREROUTING -n -v --line-numbers`
   - Observed rule shape: `-A PREROUTING -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 30080`
   - Observed behavior: the packet counter on that rule incremented during a failed workstation `curl` to public port `80`.

4. OCI ingress traffic is reaching the instance, but the redirected public packet does not enter the same working NodePort path as direct `10.0.0.8:30080`.
   - `sudo tcpdump -ni any 'tcp port 80 or tcp port 30080 or icmp'`
   - Observed:
     - inbound SYN to `10.0.0.8.80`
     - immediate outbound `ICMP host 10.0.0.8 unreachable - admin prohibited`
     - no corresponding `30080`, `cni0`, or pod traffic for that failed public request

5. The direct private-IP NodePort request does enter the pod datapath cleanly.
   - During `curl -I --max-time 5 http://10.0.0.8:30080/`, `tcpdump` showed the flow rewritten through `cni0` to the ingress pod IP and returning `HTTP/1.1 404 Not Found`.
   - Interpretation: the raw NodePort service path is healthy; the failure is specific to the host redirect path.

6. The redirected public packet is handled as host-local traffic after NAT.
   - `sudo iptables -L INPUT --line-numbers -n | sed -n '1,40p'`
   - `sudo iptables -L KUBE-ROUTER-INPUT -n -v --line-numbers`
   - Observed behavior during a failed workstation `curl`:
     - the `INPUT` rule for `tcp dpt:80 ACCEPT` did not increment, because the packet was no longer port `80` by then
     - the `KUBE-ROUTER-INPUT` NodePort allow rule for local NodePorts did increment
     - the final broad `INPUT` `REJECT ... icmp-host-prohibited` also incremented
   - Interpretation: the `REDIRECT` rewrote the packet to local port `30080`, but that still did not turn it into the working NodePort service flow.

7. A temporary `INPUT dpt:30080 ACCEPT` rule changed the failure from `ICMP admin prohibited` to `Connection refused`.
   - Manual rule:
     ```bash
     sudo iptables -I INPUT 1 -p tcp --dport 30080 -j ACCEPT
     ```
   - Result from the workstation:
     - `curl -v http://152.70.145.68/` failed with `Connection refused`
   - Interpretation: after the redirect, the kernel was attempting host-local delivery to port `30080`, not kube-proxy NodePort handling. If it had become a real NodePort flow, the request would have reached Envoy instead of a local closed port.

8. Preserving the original client IP at the ingress gateway is a hard requirement for the final design.
   - That requirement rules out a naive host TCP proxy as the fallback, because it would replace the real client IP unless the design adds extra proxy-protocol or transparent-proxy complexity.

## Repo Changes Already Made

These are repository changes already applied in this repo during the debugging thread.

1. Cert-manager deprecation cleanup unrelated to the current network issue:
   - [`deploy/helm-values/cert-manager.values.yaml`](../../deploy/helm-values/cert-manager.values.yaml)
   - [`docs/plans/oracle-cloud-deployment-plan.md`](./oracle-cloud-deployment-plan.md)
   - Changed `installCRDs` usage to `crds.enabled`.

2. Step 15 verification docs were corrected so they no longer treat `curl http://127.0.0.1/` from the SSH session as the authoritative end-to-end test for a `PREROUTING` redirect.
   - [`docs/plans/oracle-cloud-deployment-plan.md`](./oracle-cloud-deployment-plan.md)
   - [`deploy/README.md`](../../deploy/README.md)

3. The host redirect helper was changed to insert the `PREROUTING` redirect ahead of kube-proxy's `KUBE-SERVICES` jump instead of appending it later.
   - [`deploy/scripts/lib/common.sh`](../../deploy/scripts/lib/common.sh)
   - Rationale: if the redirect occurs after kube-proxy's service jump, the rewritten NodePort may be evaluated too late for the service path to match.

These repo changes are intended to stay idempotent. They do not include one-off host-only debug rules.

## Temporary Host-Side Debug Mutations

These are not part of the desired steady-state configuration and must be removed before the OCI NLB path is introduced.

1. Temporary `INPUT` allow rule for port `30080`
   - Added manually:
     ```bash
     sudo iptables -I INPUT 1 -p tcp --dport 30080 -j ACCEPT
     ```
   - Result: changed the public failure from `ICMP admin prohibited` to `Connection refused`.
   - Interpretation: proved the packet was being treated as host-local `30080` traffic after NAT.

2. Step 15 `PREROUTING REDIRECT` rules for public `80` (and eventually `443`)
   - Added via `./deploy/scripts/06-configure-host-redirects.sh`
   - Result: external traffic matched the rule counters, but the redirect still did not become a working NodePort service flow.

### Revert Commands

Use the same cleanup sequence captured in the main plan's Step 16:

```bash
while sudo iptables -C INPUT -p tcp --dport 30080 -j ACCEPT 2>/dev/null; do
  sudo iptables -D INPUT -p tcp --dport 30080 -j ACCEPT
done
while read -r rule; do
  [[ -n "${rule}" ]] || continue
  sudo iptables -t nat ${rule}
done < <(
  sudo iptables -t nat -S PREROUTING | awk '
    $1 == "-A" && $2 == "PREROUTING" &&
    ($0 ~ /--dport 80 / || $0 ~ /--dport 443 /) &&
    $0 ~ /-j REDIRECT/ {
      sub(/^-A /, "-D ")
      print
    }
  '
)
sudo netfilter-persistent save
```

Then verify the host is back at the baseline:

```bash
sudo iptables -L INPUT --line-numbers -n | sed -n '1,20p'
sudo iptables -t nat -S PREROUTING
```

## Dead Theories

These explanations no longer fit the observed evidence.

1. **OCI security list or public subnet routing is the primary current blocker.**
   - Rejected because the SYN is observed arriving on `enp0s6`.

2. **The Step 15 failure is only a bad local verification command.**
   - Rejected because the workstation-to-public-IP test also fails.

3. **The only issue is a missing `INPUT dpt:80 ACCEPT`.**
   - Rejected because the host already accepts `80`, and the packet still fails after arrival.

4. **A temporary `INPUT dpt:30080 ACCEPT` fixes the path.**
   - Rejected by direct test; it only changed the error to `Connection refused`.

5. **A tiny host TCP proxy is the obvious fallback.**
   - Rejected for the forward plan because preserving the original client IP at the ingress gateway is a requirement.

## Resolved Conclusions

1. **The Step 15 `REDIRECT 80 -> 30080` design is not sufficient for this OCI host.**
   - The redirect matches external traffic.
   - Direct NodePort traffic works.
   - The redirected public packet still becomes host-local traffic and never enters the same service datapath.

2. **The problem is not OCI routing or the public security list.**
   - The public SYN reaches the instance consistently.
   - The failure happens only after the packet arrives on the host.

3. **The fallback cannot be a naive host proxy because client IP preservation is required.**
   - The forward plan needs a public ingress shape that keeps the original source IP visible to the ingress gateway.

4. **The replacement public ingress design should be an OCI public Network Load Balancer in front of the ingress NodePort, not more host firewall trickery.**
   - That is the cloud-native pattern that scales from one ingress node to multiple ingress nodes with minimal architectural change.
   - The checked-in ingress Service must also move to `externalTrafficPolicy: Local`.

## Next Actions

The debugging thread itself is done. The forward work now lives in the main plan:

1. Run the Step 16 cleanup in [`oracle-cloud-deployment-plan.md`](./oracle-cloud-deployment-plan.md#16-human-remove-the-step-15-host-redirect-experiment-and-the-older-host-direct-firewall-rules-before-introducing-the-replacement-public-ingress-path).
2. Run the Step 17 OCI-networking rollback so the instance is no longer directly exposed on public `80` or `443`.
3. Step 18 is now complete in-repo: the checked-in ingress gateway config sets `externalTrafficPolicy: Local`, and the companion operator docs were updated.
4. Replace the host redirect exposure path with a public OCI Network Load Balancer as described in Steps 19-20.
5. Keep Step 15 only as the recorded experiment; do not revive it as the steady-state ingress design.

## Guardrails For Continued Debugging

1. Keep the OCI host close to the checked-in plan baseline.
2. Revert any temporary debug-only `iptables` rules once the test is complete.
3. Do not leave the Step 15 `PREROUTING REDIRECT` rules in place once the plan moves to the OCI NLB path.
4. Preserve the original client IP at the ingress gateway; do not accept a host-side workaround that hides it.
5. Do not claim the replacement ingress path complete until a workstation can reach the public endpoint and packet capture on the instance proves the original client IP survives.
