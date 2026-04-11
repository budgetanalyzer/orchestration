# Single-Instance Demo Hosting — Cost Research

**Date:** 2026-04-06
**Status:** Research / draft recommendation
**Author:** Architecture working notes
**Audience:** Project owner deciding where to host a 24/7 public demo URL for a resume/cover-letter link
**Supersedes (partially):** Cost section of [`deployment-architecture-gcp.md`](../architecture/deployment-architecture-gcp.md) for the demo-only deployment scenario

> Goal: Host the **full Budget Analyzer architecture** — Kubernetes, Istio service mesh, mTLS, ext_authz, network policies, Kyverno admission baseline, the application stack, AND the observability surface (Kiali, Prometheus, Grafana, Jaeger) that makes the architecture *visible* to a recruiter clicking the link — on **one** cheap VM, 24/7. The Budget Analyzer application itself is unremarkable; the production architecture is the actual showcase. Stripping out k8s and Istio to fit on a $10/mo box defeats the entire purpose of the project. The full managed-GCP deployment (~$420/mo) is overkill for demo traffic, but the architecture itself is non-negotiable.

---

## TL;DR

| Recommendation | Why | Monthly Cost |
|---|---|---|
| **Free: Oracle Cloud Always Free Ampere A1 (4 OCPU, 24 GB RAM, 200 GB block)** | 24 GB is comfortable for the full stack + observability bundle; running Prometheus continuously also incidentally solves the idle-reclamation problem | **$0** (with caveats — see [§5](#5-oracle-cloud-always-free-the-deal-and-the-asterisks)) |
| **Primary paid: Hetzner CAX41 (16 vCPU ARM, 32 GB RAM, 320 GB NVMe)** in EU | Comfortable headroom for k3s + Istio + observability + JVMs, same ARM as Oracle so images are portable, includes 20 TB egress | **€31.49 (~$33.70)** + €6.30 backups = **~$40/mo** |
| **Floor: Hetzner CAX31 (8 vCPU ARM, 16 GB RAM, 160 GB NVMe)** | Tight but workable if Prometheus retention is dropped to 24h; the cheapest ARM box that holds the full stack | **€15.99 (~$17.10)** + €3.20 backups = **~$20/mo** |

**Is hosting the full architecture on one box a bad idea?** No — for a portfolio demo at this traffic profile, single-node k3s with Istio is the correct call. You give up HA and multi-node failure modes (which don't matter at 1-2 RPS) but you keep every interesting architectural element: the mesh, mTLS, AuthorizationPolicies, ext_authz, the network policies, the Kyverno admission baseline, and the manifests themselves. See [§7](#7-is-this-a-bad-idea-honest-assessment) for what you are and aren't giving up.

**Recommended path:** Try Oracle first because $0 beats $40. Have a Hetzner CAX41 ready as the immediate fallback if Oracle's capacity lottery, account flagging, or idle-reclamation policy bites. Both options use ARM, so your container images need to be `linux/arm64` — which Eclipse Temurin and the existing Jib build already support.

---

## 1. Workload sizing — what you actually need to host

The goal is to run k3s + Istio + the application stack + the observability bundle that makes the mesh visible. The application sizing comes from the Kubernetes manifests in this repo (the closest thing to ground truth); the platform and observability sizing comes from standard sizing for a small Istio mesh.

### Application services

| Component | Request RAM | Limit RAM | Request CPU | Limit CPU | Source |
|---|---|---|---|---|---|
| transaction-service | 256 Mi | 512 Mi | 100 m | 500 m | `kubernetes/services/transaction-service/deployment.yaml:74-78` |
| currency-service | 256 Mi | 512 Mi | 100 m | 500 m | `kubernetes/services/currency-service/deployment.yaml:116-120` |
| session-gateway | 256 Mi | 512 Mi | 100 m | 500 m | `kubernetes/services/session-gateway/deployment.yaml:96-100` |
| permission-service | 256 Mi | 512 Mi | 100 m | 500 m | `kubernetes/services/permission-service/deployment.yaml:77-81` |
| budget-analyzer-web | 256 Mi | 1024 Mi | 200 m | 1000 m | `kubernetes/services/budget-analyzer-web/deployment.yaml:45-49` |
| nginx-gateway | 64 Mi | 128 Mi | 50 m | 200 m | `kubernetes/services/nginx-gateway/deployment.yaml:101-105` |
| ext-authz | 32 Mi | 64 Mi | 50 m | 200 m | `kubernetes/services/ext-authz/deployment.yaml:68-72` |
| **App subtotal** | **~1.4 GiB** | **~3.25 GiB** | **0.7 vCPU** | **3.4 vCPU** | |

### Infrastructure services

| Component | Request RAM | Limit RAM | Request CPU | Limit CPU | Source |
|---|---|---|---|---|---|
| postgresql | 256 Mi | 512 Mi | 100 m | 500 m | `kubernetes/infrastructure/postgresql/statefulset.yaml:100-104` |
| rabbitmq | 256 Mi | 512 Mi | 100 m | 500 m | `kubernetes/infrastructure/rabbitmq/statefulset.yaml:35-39` |
| redis | 128 Mi | 256 Mi | 100 m | 300 m | `kubernetes/infrastructure/redis/deployment.yaml:87-91` |
| **Infra subtotal** | **640 Mi** | **1.25 GiB** | **0.3 vCPU** | **1.3 vCPU** | |

### Platform overhead (k3s + Istio)

| Component | Realistic working set | Notes |
|---|---|---|
| k3s control plane (apiserver + controller-manager + scheduler) + containerd + kubelet | ~0.8 GiB | Single-node lightweight distro; full kubeadm would add ~0.7 GiB. Run with `--disable=traefik --disable=servicelb` so Istio's ingress gateway is the only ingress path. |
| istiod | ~0.7 GiB | Realistic for ~10 sidecars; the 256 Mi request in `istiod-values.yaml` is the floor, not the steady-state |
| istio-cni | ~0.05 GiB | |
| istio-ingressgateway | ~0.3 GiB | NodePort 30443 per `ingress-gateway-config.yaml` |
| Istio sidecars (~10 pods × ~60 MiB) | ~0.6 GiB | One per app pod; dominant data-plane cost |
| Kyverno (admission baseline) | ~0.3 GiB | Phase 7 ClusterPolicies — kept for production parity |
| **Platform subtotal** | **~2.75 GiB** | |

### Observability bundle (the architectural showcase)

| Component | Realistic working set | Notes |
|---|---|---|
| Prometheus (1-week retention, ~20 targets, 15s scrape) | ~1.5 GiB | Dominant observability cost; drop retention to 24h to save ~1 GiB |
| Grafana | ~0.3 GiB | Istio's bundled mesh dashboards |
| Jaeger all-in-one (Badger backend) | ~0.7 GiB | All-in-one with on-disk Badger storage; in-memory is smaller but loses traces on restart |
| Kiali | ~0.4 GiB | Service mesh graph and traffic-flow visualization |
| **Observability subtotal** | **~2.9 GiB** | |

### Totals

| Layer | RAM (realistic) |
|---|---|
| Application services | ~3.0 GiB |
| Platform (k3s + Istio + Kyverno) | ~2.75 GiB |
| Observability bundle | ~2.9 GiB |
| OS + page cache + headroom | ~1.0 GiB |
| **Total** | **~9.65 GiB** |

- **All requests floor:** ~6 GiB / ~2 vCPU
- **Realistic working set:** **~9.7 GiB / peaks under 2 vCPU at demo traffic**
- **Disk:** ~30 GB minimum (OS + Istio/observability container images + Prometheus TSDB at 1-week retention + Postgres data); 80 GB tight, 160 GB comfortable, 320 GB wasteful but cheap

The dominant single chunk is still the JVMs (5 Spring Boot services × ~400 MiB resident ≈ 2 GiB), with Prometheus now the second-largest single component. The 9.7 GiB total means **16 GB is the floor and 32 GB is the comfortable target.** A 4 GB or 8 GB box, which would have worked for a stripped-down compose stack, cannot hold the full architecture with the observability surface — and the previous draft of this doc was wrong to suggest otherwise.

> **Note on k3s vs full kubeadm:** k3s ships everything as a single binary, uses SQLite (or embedded etcd) instead of standalone etcd, and disables the cloud-controller-manager. The distinction matters because the ~0.7 GiB savings is the difference between "fits on CAX31 with no margin" and "fits on CAX31 with no margin and OOMs on the first GC pause." Single-node kubeadm is also possible and produces a more "production-faithful" cluster, but the headroom cost is real.

---

## 2. The candidates

This list is intentionally narrow: providers that are (a) cheap enough to be irrelevant on a personal credit card, (b) have a track record of not vanishing, and (c) can host a long-running 24/7 VM rather than scale-to-zero workloads. Scale-to-zero (Cloud Run, Fly Machines) is great for cost but produces cold-start latency that looks bad in a demo.

### 2.1 Free / freemium

| Provider | Plan | vCPU | RAM | Disk | Egress | Cost | Catch |
|---|---|---|---|---|---|---|---|
| **Oracle Cloud** | Always Free Ampere A1 | 4 OCPU | 24 GB | 200 GB block | 10 TB/mo | **$0** | Capacity lottery, idle reclamation, account flagging — see [§5](#5-oracle-cloud-always-free-the-deal-and-the-asterisks) |
| Google Cloud | e2-micro Always Free | 0.25-1 vCPU (burst) | 1 GB | 30 GB std PD | 1 GB/mo | $0 | **Way too small** for this stack. RAM alone disqualifies it. |
| AWS | EC2 t2.micro / t3.micro | 1 vCPU | 1 GB | 30 GB EBS | 100 GB/mo | $0 (12 months only) | Same RAM problem. Not "always free." |
| Fly.io | (no free tier in 2026) | n/a | n/a | n/a | n/a | n/a | Removed free allowance in 2024. New signups get a 2-VM-hour trial. |

Only Oracle is in the running for a free option. With 24 GB RAM, it's the only "always free" tier with enough headroom to host the full architecture (k3s + Istio + observability + the application stack ≈ 9.7 GiB working set per [§1](#1-workload-sizing--what-you-actually-need-to-host)). The other free tiers cannot even hold the application services, let alone the platform and observability layers.

### 2.2 Budget VPS providers (paid, EU/global)

All prices are the listed monthly rate after the April 2026 Hetzner adjustment. EUR→USD conversions use 1 EUR ≈ 1.07 USD. **Plans with less than 16 GB RAM are excluded** — they cannot hold the full architecture per [§1](#1-workload-sizing--what-you-actually-need-to-host).

| Provider | Plan | Arch | vCPU | RAM | Disk | Traffic | Monthly EUR | Monthly USD | Locations |
|---|---|---|---|---|---|---|---|---|---|
| **Hetzner** | **CAX31** | ARM64 (shared) | 8 | 16 GB | 160 GB NVMe | 20 TB | **€15.99** | **~$17.10** | EU only |
| **Hetzner** | **CAX41** | ARM64 (shared) | 16 | 32 GB | 320 GB NVMe | 20 TB | **€31.49** | **~$33.70** | EU only |
| Hetzner | CPX42 | x86 (AMD shared) | 8 | 16 GB | 320 GB NVMe | 20 TB | €25.49 | ~$27.30 | EU + US + SG |
| Hetzner | CPX52 | x86 (AMD shared) | 12 | 24 GB | 480 GB NVMe | 20 TB | €36.49 | ~$39.05 | EU + US + SG |
| Hetzner | CCX23 | x86 (AMD dedicated) | 4 | 16 GB | 160 GB NVMe | 20 TB | €31.49 | ~$33.70 | EU + US + SG |
| Hetzner | CCX33 | x86 (AMD dedicated) | 8 | 32 GB | 240 GB NVMe | 20 TB | €62.49 | ~$66.85 | EU + US + SG |
| Hetzner | AX41-NVMe (dedicated iron) | Ryzen 5 3600 (6c/12t) | 6 | 64 GB | 2× 512 GB NVMe | 20 TB | varies — verify in console | ~$42-52 + setup | DE + FI |
| DigitalOcean | Basic 16 GB / 4 vCPU | x86 (shared) | 4 | 16 GB | 320 GB | 6 TB | n/a | ~$96 | All DO regions |
| AWS Lightsail | General Purpose (16 GB tier) | x86 | 4 | 16 GB | 320 GB | 6 TB | n/a | ~$80 | All AWS regions |

Plans deliberately omitted:
- **Contabo VPS 10/20** — 8 GB and 12 GB respectively, both under the 16 GB floor. VPS 30 is in the right range on paper but Contabo's historical reliability stories make it risky for a thing your future job depends on.
- **OVH, Netcup small ARM, Linode Nanode** — same RAM problem as the Contabo small tiers.
- **Hetzner CAX21, CX33, CPX32** — the previous draft of this doc recommended CAX21 at €7.99 for the stripped-down compose stack. None of these fit the full architecture.

### 2.3 Quick read of the table

- **CAX41 is the sweet spot.** 16 vCPU and 32 GB RAM on shared ARM, 320 GB NVMe, 20 TB egress, ~$34/mo before backups. That is 3-4x more headroom than the workload needs in every dimension, which is what you want for "I am not going to think about this box again until the cert renews."
- **CAX31 is the floor.** 16 GB RAM is exactly the realistic working set with ~6 GiB of breathing room above peak. It works if you drop Prometheus retention to 24h and accept that one runaway JVM will OOM the box. For a portfolio demo this is acceptable but not comfortable; the $20/mo savings vs CAX41 is real but not transformative.
- **CCX (dedicated CPU) is overkill.** Shared CPU on Hetzner is fine at demo traffic — the demo never sustains the kind of load that would benefit from dedicated cores. CCX33 at €62 is twice CAX41's price for the same 32 GB and arguably worse (8 dedicated vs 16 shared vCPU). Reach for CCX only if you have a specific benchmark-stability requirement, which a portfolio demo does not.
- **AX41 dedicated iron is interesting but not worth it.** On paper, ~€39-49/mo for a real Ryzen 5 3600 with 64 GB RAM is impressive. In practice you take on a one-time setup fee, longer provisioning, slower disaster recovery (no hypervisor snapshots — you're back to `pg_dump` and rsync), and you're managing physical hardware. Same money as CAX41 with worse ops.
- **DigitalOcean and AWS Lightsail are 2-3x more expensive** than Hetzner for equivalent RAM. Convenience tax. Worth it for production, not for a portfolio link.
- **Hetzner CAX is EU-only.** If demo latency from US recruiters matters, use CPX42 in a US data center (Ashburn or Hillsboro), accept ~120 ms transatlantic latency on the EU plans (fine for an HTTP demo), or pay the AWS/DO premium for a region closer to the audience.

---

## 3. Sizing the cost over time

Annual cost of running the demo for the year you're applying for jobs:

| Option | Monthly | + Backups | Annual all-in |
|---|---|---|---|
| Oracle Always Free A1 | $0 | $0 (DIY pg_dump to B2/R2) | **$0** |
| Hetzner CAX31 (16 GB ARM, floor) | €15.99 (~$17.10) | €3.20 (~$3.42) | **~$246/yr** |
| Hetzner CPX42 (16 GB AMD x86, US-region) | €25.49 (~$27.30) | €5.10 (~$5.46) | **~$393/yr** |
| **Hetzner CAX41 (32 GB ARM, comfortable)** | €31.49 (~$33.70) | €6.30 (~$6.74) | **~$485/yr** |
| Hetzner CCX33 (32 GB AMD dedicated) | €62.49 (~$66.85) | €12.50 (~$13.38) | **~$963/yr** |
| Hetzner AX41-NVMe (64 GB dedicated iron) | ~$42-52 + setup | DIY snapshots | **~$500-625/yr + setup** |
| DigitalOcean Basic 16 GB | $96 | +20% = $19.20 | **~$1,382/yr** |
| AWS Lightsail (16 GB tier) | $80 | + snapshot fees | **~$1,000-1,100/yr** |
| Original GCP managed plan | $420 | included | **~$5,040/yr** |

**The Hetzner CAX41 path saves ~$4,555/year** versus the original GCP managed design *while preserving every architectural element* (Kubernetes, Istio, mTLS, the ext_authz pattern, network policies, Kyverno baseline, the manifests themselves) that the project is meant to showcase. The Oracle path saves the full ~$5,040/year for $0/mo if you can tolerate the operational fragility documented in [§5](#5-oracle-cloud-always-free-the-deal-and-the-asterisks).

---

## 4. The Hetzner backups footnote

Hetzner Cloud's automated backup add-on is a flat **20% of the instance price** and gives you 7 rolling daily snapshots, regardless of disk size. For a CAX41 that's about €6.30/month; for a CAX31 it's about €3.20. Worth it because:

- Restore-from-backup is one click in their console
- It de-risks the "I broke my own demo the night before an interview" failure mode
- Cheaper than spending an hour setting up `pg_dump` to S3

For Oracle (and any provider without an integrated backup add-on) you're on your own: cron a daily `pg_dump` to a free object-storage bucket (Cloudflare R2 has a free tier; Backblaze B2 is ~$0.005/GB), and use an Oracle Block Volume backup policy for the boot/data volumes.

---

## 5. Oracle Cloud Always Free — the deal and the asterisks

**The deal:** 4 OCPU + 24 GB RAM + 200 GB block storage on Ampere A1 (ARM), free forever, in any single region. This is the most generous free tier on the planet by a wide margin and would host this entire stack with room to spare.

**The asterisks:**

1. **Capacity lottery.** "Always Free" Ampere A1 capacity is famously hard to get in popular regions. You may hit `Out of host capacity` errors for days or weeks. Common workarounds: pick a less popular home region (Frankfurt, Phoenix, Zurich tend to have more capacity than Ashburn), or run a polling script that retries provisioning. There are open-source bash/PHP retry helpers people have used for years.

2. **Credit card required at signup.** Oracle does an authorization hold that drops off in 3-5 days. They explicitly do not accept prepaid/virtual cards.

3. **Idle-reclamation policy.** If your VM's 95th-percentile CPU is below 20% over a 7-day window, Oracle flags it as idle and may stop it. For the previous draft of this doc (a stripped-down compose stack with no observability) this was a real concern; **for the full-architecture plan it likely is not.** Prometheus scraping ~20 targets every 15 seconds, plus the JVMs idling, plus the istiod control loop, plus background telemetry from ~10 sidecars, generates enough continuous CPU activity that the box is unlikely to drop below the 20% threshold. The observability bundle accidentally pays for itself by keeping you out of reclamation.

   If you do hit the threshold (e.g., very tuned-down Prometheus retention combined with idle JVMs), the older mitigations still apply:
   - An external uptime monitor (UptimeRobot, free) hitting `/health` every 5 minutes — explicitly fine, also keeps the JVMs warm
   - A real cron that does meaningful work (e.g., dial up the currency-import scheduler the stack already has)
   - A synthetic-load script (`stress-ng --cpu 1 --cpu-load 25 --timeout 0`) — gray area, not against TOS but exactly what the policy is designed to prevent

4. **Account-inactivity policy.** Accounts left untouched for 30 days are eligible for suspension. Logging into the console once a month is enough.

5. **Pay-as-you-go upgrade trap.** If you ever upgrade to PAYG to "unlock more shapes," your Always Free resources are still free, but it is now genuinely possible to run up a bill. Stay on the free-tier account.

6. **No SLA, no support.** When (not if) something breaks, you have a forum and no recourse. For a demo this is fine; for anything else it isn't.

**Honest verdict on Oracle:** It is genuinely free, the resources are real, and the catch list above is the entire reason it is still free in 2026. If you can tolerate the operational fragility and a one-time provisioning struggle, run on Oracle. If anything in §5 makes you want to close the tab, pay Hetzner ~$40/month for a CAX41 and never think about it again.

**Ready to try it?** The concrete step-by-step walkthrough — home region selection, account signup, networking prep, the `Out of host capacity` retry script, the iptables gotcha, and basic hardening — is in [`oracle-cloud-always-free-provisioning.md`](./oracle-cloud-always-free-provisioning.md). Read that after you've decided based on the asterisks above.

---

## 6. Single-node k3s topology

This section will eventually want a dedicated plan doc under `docs/plans/`, but the sketch needs to be in this research note so the cost analysis is grounded in a concrete deployment.

**Goal:** keep the Kubernetes manifests, Istio mesh, ext_authz pattern, network policies, and Kyverno admission baseline that are the actual project showcase, while running on one cheap VM. The application code, the manifests under `kubernetes/`, and the Istio configuration (`kubernetes/istio/*`) are unchanged from the multi-node design — only the cluster topology and a few k3s-specific feature flags differ.

### What stays the same (the showcase)

- All `kubernetes/services/*` deployments — `transaction-service`, `currency-service`, `session-gateway`, `permission-service`, `budget-analyzer-web`, `nginx-gateway`, `ext-authz`
- All `kubernetes/infrastructure/*` workloads — Postgres StatefulSet, RabbitMQ StatefulSet, Redis Deployment
- All `kubernetes/istio/*` — `peer-authentication.yaml` (mesh-wide STRICT mTLS), `authorization-policies.yaml`, `ext-authz-policy.yaml`, the istiod extension provider for `ext-authz-http`, the istio ingress gateway, the egress gateway, the egress `REGISTRY_ONLY` outbound traffic policy and `ServiceEntry`s
- `kubernetes/network-policies/*` — the default-deny baseline plus the per-namespace allow rules for `istio-ingress`, `istio-egress`, and infrastructure
- `kubernetes/kyverno/*` — the Phase 7 ClusterPolicies and the static gate (`scripts/guardrails/verify-phase-7-static-manifests.sh`). The existing exception list already covers `local-path-storage`, which is the k3s default storage class, so the baseline runs unchanged.
- `kubernetes/gateway/*` — the Gateway API HTTPRoutes that fan traffic from the Istio ingress gateway into `nginx-gateway` (and onward to the services)
- The ext_authz session-edge pattern, complete with `cookie` request-header passthrough and `x-user-id`/`x-roles`/`x-permissions` upstream injection
- mTLS between sidecars (Istio handles this — it does not care that all sidecars happen to live on one node)

### What changes (the topology, not the architecture)

- **k3s replaces full kubeadm.** Lightweight distro, single-node, ~0.7 GiB lighter on the control plane. Install with `--disable=traefik --disable=servicelb --disable=metrics-server` so Istio's ingress gateway is the only ingress path and the bundled extras don't fight Istio for ports. Keep `--write-kubeconfig-mode=644` for convenience. Use the embedded SQLite datastore — embedded etcd is unnecessary at single-node.
- **No HA anywhere.** One Postgres pod, one Redis pod, one RabbitMQ pod, one of every service. Box dies → restore from snapshot (Hetzner) or `pg_dump` (Oracle). This is documented and accepted in [§7](#7-is-this-a-bad-idea-honest-assessment).
- **External TLS terminates at the Istio ingress gateway** with `cert-manager` + Let's Encrypt (HTTP-01 challenge through the ingress gateway listener on port 80). The cert-manager controller is small (~100 MiB) and is the standard pattern; the alternative is to run Caddy on the host as a reverse proxy and lose the Istio-native termination.
- **Persistent volumes use the k3s `local-path` provisioner** (the default). No CSI driver, no networked storage. Daily snapshot of the underlying VM disk via Hetzner backups, plus a daily `pg_dump` to a free Backblaze B2 / Cloudflare R2 bucket as a belt-and-braces backup.
- **NodePort is the cluster ingress path.** The Istio ingress gateway is already configured as `type: NodePort` on `nodePort: 30443` per `kubernetes/istio/ingress-gateway-config.yaml`. Front it with host-level `iptables -t nat` redirects from 443 → 30443 (and 80 → the cert-manager challenge port), or run a tiny userspace proxy. No external load balancer is needed because there is no second node to balance to.
- **Auth0 callback URL** points to whatever public hostname the box has — one config edit in the Auth0 tenant.
- **DNS:** point a subdomain you own at the box's IPv4. Hetzner gives you a free reverse-DNS entry; both Hetzner and Oracle give you a stable public IP.

### What's added (the observability bundle)

This is what makes the architecture *visible* to a recruiter visiting the demo. Without this, the link goes to a budget analyzer SPA that does not visibly differ from any other CRUD app, and the entire architectural showcase lives only in the GitHub repo — defeating the point of hosting a demo at all.

| Component | Purpose | Helm chart | Realistic RAM |
|---|---|---|---|
| Prometheus (kube-prometheus-stack, scaled down) | Metrics scraping for the mesh and the apps | `prometheus-community/kube-prometheus-stack` with alertmanager disabled, 24h-7d retention | ~1.5 GiB |
| Grafana | Service dashboards (Istio's bundled mesh dashboards plus per-service JVM dashboards) | `grafana/grafana` (or the bundled one inside kube-prometheus-stack) | ~0.3 GiB |
| Jaeger (all-in-one, Badger backend) | Distributed traces from the Istio sidecars | `jaegertracing/jaeger` all-in-one chart | ~0.7 GiB |
| Kiali | Service mesh graph and traffic-flow visualization | `kiali/kiali-server` | ~0.4 GiB |

All four are standard Istio observability addons and are documented as such. Istio's tracing extension provider must be configured in `istiod-values.yaml` to point at the Jaeger collector (this is a small addition to the existing `meshConfig.extensionProviders` list, which currently only contains `ext-authz-http`).

### Public exposure of the observability surface

The demo landing page needs to expose Kiali, Grafana, and Jaeger publicly so visitors can actually see the mesh in action. Three options, in order of effort:

1. **Read-only credentials behind nginx-gateway basic auth** — single shared `demo:demo` account, easiest, low attack surface for read-only dashboards. Add the auth in front of the relevant Gateway API HTTPRoutes. Recommended for the first iteration.
2. **AuthorizationPolicy that allows GET-only on `/kiali`, `/grafana`, `/jaeger`** and denies everything else, leveraging the existing Istio AuthorizationPolicy infrastructure that the rest of the mesh already uses. More work but more aligned with the architecture's existing patterns, and arguably part of the showcase.
3. **Static screenshots embedded in the landing page** if you want zero attack surface. Loses the "live" element of the demo, which is half the point of running it at all. Not recommended unless options 1 and 2 prove operationally painful.

For all three options, **lock down Grafana's anonymous-access mode to viewer-only** (`auth.anonymous.enabled=true`, `auth.anonymous.org_role=Viewer`) and **disable Prometheus's `/api/v1/admin/*` endpoints**. Kiali defaults to view-only when its auth strategy is set to `anonymous`; Jaeger's UI is read-only by design.

### What this is NOT

- **It is not the full GCP-managed variant.** Cloud SQL, Memorystore, Secret Manager, Cloud Armor, the GKE-managed control plane — none of those are in the demo. The [`deployment-architecture-gcp.md`](../architecture/deployment-architecture-gcp.md) design is the production target; the demo proves you can build the k8s/Istio half of it. Be clear about this on the demo landing page so a knowledgeable visitor doesn't mistake the demo for the production design.
- **It is not HA.** [§7](#7-is-this-a-bad-idea-honest-assessment) covers what you're giving up. Briefly: single host, single Postgres, single Redis, single RabbitMQ, brief unavailability during deploys.
- **It is not multi-node.** Pod anti-affinity, zone-aware routing, multi-AZ failure tolerance — none of these can be exercised on one box. The manifests are written to allow them; the demo just doesn't run them.

Production parity goes from "matches the multi-node GKE design" to "matches every architectural element of the multi-node design except the multi-node bit and the GCP-managed datastores." For a demo whose entire point is showing the architecture, this is the right tradeoff.

---

## 7. Is this a bad idea? Honest assessment

**Short answer: No, this is the correct call for the actual goal, but be clear-eyed about what you're giving up — which is much less than the previous draft of this doc claimed.**

### What you're giving up vs the GCP managed-services design

| Capability | GCP managed plan | Single-node k3s demo |
|---|---|---|
| Database HA & failover | ✅ Cloud SQL Standard | ❌ One Postgres pod; if the box dies you restore from snapshot/pg_dump |
| Session persistence on outage | ✅ Memorystore HA | ❌ Redis dies → users get logged out |
| Zero-downtime deploys | ✅ Rolling restarts across nodes | ⚠️ Rolling deploys work via the k8s deployment strategy, but a single-node cluster reschedules onto the same node — brief unavailability per service during a restart, no parallel-version safety |
| Multi-node failure isolation | ✅ Pod anti-affinity, zone redundancy | ❌ Single host = single failure domain |
| Audit logging for secrets | ✅ Secret Manager | ❌ k8s Secrets (better than `.env` on disk, but no audit trail) |
| DDoS protection | ✅ Cloud Armor | ⚠️ Provider-level only; no app-aware rules |
| Scaling under load | ✅ HPA + cluster autoscaler | ❌ Vertical-only, and only by changing instance type |
| Managed datastores | ✅ Cloud SQL, Memorystore | ❌ Self-hosted Postgres/Redis/RabbitMQ in-cluster |
| **Service mesh (Istio + STRICT mTLS + AuthorizationPolicies + ext_authz)** | ✅ Same | ✅ **Same — preserved** |
| **Network policies (default-deny baseline)** | ✅ Same | ✅ **Same — preserved** |
| **Kyverno admission baseline (Phase 7)** | ✅ Same | ✅ **Same — preserved** |
| **The k8s manifests themselves** | ✅ Same | ✅ **Same — preserved** |
| **Observability surface (Kiali + Prometheus + Grafana + Jaeger)** | ⚠️ Cloud Monitoring or self-hosted, often hidden internally | ✅ **Self-hosted, exposed publicly as part of the demo** |

### Why none of that matters here

- **Demo traffic is 1-2 RPS peak.** You will never approach the limits of any 16+ GB box.
- **The audience is recruiters and hiring managers**, not paying customers. A few minutes of downtime during a deploy is fine. Losing a session during an outage is fine — the visitor reloads and re-logs.
- **There is no real data to lose.** A daily `pg_dump` to a free B2/R2 bucket plus Hetzner snapshots is a complete DR plan for this scenario.
- **The point of the demo is to show the architecture you designed.** This was the failure mode of the previous draft of this doc, which proposed stripping out k8s and Istio to fit on a $10/mo box and thereby demolishing the actual showcase. The k3s topology in [§6](#6-single-node-k3s-topology) preserves every architectural element worth seeing, and the observability bundle makes those elements *visible* to a visitor instead of hidden behind an unremarkable SPA.
- **The cost asymmetry is still enormous.** $0 (Oracle) or $40/mo (Hetzner CAX41) vs $420/mo is a 10-100x multiplier for HA and managed-datastore parity that demo traffic does not need.

### The one thing I'd push back on

> "If I can run the full stack in Tilt on my laptop, I should be able to do the same on a cheap cloud VM."

Mostly yes, but with one caveat:

**Your laptop probably has 32-64 GB of RAM, and when Tilt is running you usually rely on `kubectl port-forward` for the bits of observability you actually want to see, instead of running the full Istio addon bundle continuously.** A 16 GB box is the floor for the *full architecture plus the observability bundle* (~9.7 GiB working set per [§1](#1-workload-sizing--what-you-actually-need-to-host)), and 32 GB is the comfortable target. Don't try to fit this on a 4 GB or 8 GB box — the previous draft of this doc was wrong to suggest you could.

Also: **measure the actual working set against your full Tilt environment plus the observability addons before committing to a cloud tier.** `kubectl apply` the prometheus, grafana, jaeger, and kiali charts to your local Tilt cluster, exercise the demo flow for an hour, and `kubectl top pods` to confirm. If the total resident memory exceeds 12 GiB, skip CAX31 and go straight to CAX41 (or stay on Oracle A1 with its 24 GB headroom). This is a 30-minute experiment that prevents a "demo down on Sunday" message.

### One more honest concern: the resume signal

The point of putting the URL on a resume is "click here, see the thing work *and* see the architecture I designed actually doing its job." Three failure modes that look bad:

1. **Cold-start latency** — first hit after idleness takes 30+ seconds because the JVMs need to warm up. Mitigation: an uptime monitor (UptimeRobot, free) hits `/health` every 5 minutes, which keeps the JVMs hot. Combined with Prometheus scraping continuously, this also doubles as Oracle idle-reclamation insurance.
2. **TLS cert expiration** — Let's Encrypt is 90 days. Use cert-manager with the Istio ingress gateway (the standard pattern, well-documented) or fall back to Caddy on the host if the in-cluster path is too much yak shaving. Don't be the person whose resume link shows a browser warning.
3. **Public observability dashboards getting defaced or exfiltrated.** Kiali and Jaeger are read-only by default, but Grafana's anonymous-access mode and Prometheus's HTTP API need explicit lockdown. See the "Public exposure of the observability surface" subsection in [§6](#6-single-node-k3s-topology) for the recommended approach (basic auth at the nginx-gateway layer, or AuthorizationPolicy that allows GET-only).

---

## 8. Final recommendation

1. **First choice — Oracle Cloud Always Free Ampere A1.** It is $0 and the resources are generous enough to host the full architecture with comfortable margin (24 GB RAM ≈ 14 GB headroom over the realistic working set). Plan to spend an evening fighting `Out of host capacity`. Run UptimeRobot on `/health` to keep the JVMs warm; Prometheus scraping continuously plus Istio's control loop should keep you out of idle reclamation as a side effect. Document the recovery procedure for the first time the box does get reclaimed anyway.
2. **Fallback — Hetzner CAX41 (ARM, 32 GB, EU) at €31.49/mo + €6.30 backups (~$40/mo all-in).** The cleanest answer that just works. Use this the second Oracle becomes annoying. Same ARM architecture as Oracle so your container images don't change between providers.
3. **Floor — Hetzner CAX31 (ARM, 16 GB, EU) at €15.99/mo + €3.20 backups (~$20/mo)** if $40/mo is genuinely tight and you're willing to drop Prometheus retention to 24h. The full architecture fits but with no breathing room; one runaway JVM and you OOM.
4. **If US-region latency matters more than the ARM price advantage — Hetzner CPX42** (€25.49, AMD x86, 16 GB, US/EU/SG) instead of CAX41. You give up some headroom and pay slightly more for the same RAM, but you get a US data center.
5. **Avoid for this scenario:** AWS, GCP, Azure, DigitalOcean, Linode — 3-5x more expensive without giving you anything you'll use at demo traffic. CCX dedicated tier is wasted money. Contabo's larger plans are technically cheap enough but the reliability stories make them risky for a thing your future job depends on. Dedicated AX-line iron is the same money as CAX41 with worse ops.

### Concrete next steps

1. **Validate the 9.7 GiB working-set estimate locally.** Bring up the existing Tilt environment, then `kubectl apply` the Istio addon bundle (`prometheus-community/kube-prometheus-stack`, `grafana/grafana`, `jaegertracing/jaeger`, `kiali/kiali-server`). Exercise the demo flow for an hour and check `kubectl top pods` to confirm the totals match this doc within ±20%. Iterate the sizing tables in [§1](#1-workload-sizing--what-you-actually-need-to-host) if reality disagrees.
2. **Create the Oracle Cloud free account and provision the A1 instance** — see [`oracle-cloud-always-free-provisioning.md`](./oracle-cloud-always-free-provisioning.md) for the concrete walkthrough: home region selection (Phoenix vs Frankfurt), networking setup, capacity-retry script, first-SSH verification, and the iptables gotcha.
3. **If Oracle provisioning fails after a day of retries**, sign up for Hetzner Cloud and provision a CAX41 in Helsinki or Falkenstein.
4. **Install k3s** with `--disable=traefik --disable=servicelb --disable=metrics-server`; install Istio with the existing `istiod-values.yaml` and `cni-values.yaml`; apply the existing manifests under `kubernetes/`; install the four observability addons; configure the istiod tracing extension provider to point at the Jaeger collector.
5. **Front Kiali, Grafana, and Jaeger with read-only authentication.** Basic auth at nginx-gateway is the minimum bar; an Istio AuthorizationPolicy that allows GET-only is the more architecturally consistent option.
6. **Set up cert-manager + Let's Encrypt** for the public TLS cert at the Istio ingress gateway, plus a daily `pg_dump` to a Backblaze B2 / Cloudflare R2 free bucket.
7. **Build the demo landing page** that links to (a) the app, (b) the Kiali service mesh graph, (c) the Grafana dashboards (with a curated default dashboard showing the mesh in action), and (d) a sample Jaeger trace from a recent request. This landing page is the actual showcase surface — without it, the demo is just an SPA.
8. **Write a runbook** for: cert renewal verification, postgres backup/restore, k3s upgrade, Istio upgrade, and the recovery procedure for "the box died, restore from snapshot."
9. **Promote the runbook to a `docs/plans/` doc** once the deployment has been done end-to-end at least once. The plan should reference this research note as the rationale.
10. **Put the URL on the resume only after the runbook has been used at least once successfully** — including a deliberate "blow away the box and restore from backup" drill. If you cannot recover the demo in under an hour, the runbook isn't done.

---

## References

### Oracle Cloud Always Free
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
- [Always Free Resources documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Free Tier FAQ](https://www.oracle.com/cloud/free/faq/)
- [Resolving Out of Host Capacity errors](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/troubleshooting-out-of-host-capacity.htm)
- [oci-arm-host-capacity retry script (community)](https://github.com/hitrov/oci-arm-host-capacity)

### Hetzner Cloud
- [Hetzner Cloud product page](https://www.hetzner.com/cloud/)
- [Hetzner pricing calculator (community, shows current plans)](https://costgoat.com/pricing/hetzner)
- [Hetzner April 2026 price adjustment notice](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
- [Backup vs snapshot pricing analysis](https://hetsnap.com/blog/hetzner-cloud-backup-vs-snapshot-pricing-comparison)

### Other budget VPS providers
- [Contabo VPS pricing](https://contabo.com/en-us/vps/)
- [Contabo global pricing page](https://contabo.com/en-us/pricing/)
- [Netcup VPS plans](https://www.netcup.com/en/server/vps)
- [OVHcloud VPS](https://www.ovhcloud.com/en/vps/)
- [DigitalOcean Droplet pricing](https://www.digitalocean.com/pricing/droplets)
- [DigitalOcean Droplet pricing reference docs](https://docs.digitalocean.com/products/droplets/details/pricing/)

### Hyperscaler comparisons
- [AWS Lightsail pricing](https://aws.amazon.com/lightsail/pricing/)
- [GCP Free Tier (e2-micro)](https://cloud.google.com/free)
- [Fly.io pricing (no free tier in 2026)](https://fly.io/docs/about/pricing/)

### Observability stack and platform
- [k3s documentation](https://docs.k3s.io/) — single-node k8s distribution used by the topology in [§6](#6-single-node-k3s-topology)
- [Istio observability best practices](https://istio.io/latest/docs/ops/best-practices/observability/)
- [Istio addons (Prometheus, Grafana, Jaeger, Kiali)](https://istio.io/latest/docs/ops/integrations/)
- [Kiali documentation](https://kiali.io/docs/) — service mesh graph and traffic flow visualization
- [kube-prometheus-stack Helm chart](https://github.com/prometheus-operator/kube-prometheus) — Prometheus + Alertmanager + Grafana bundle (disable Alertmanager for the demo)
- [Grafana Helm chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
- [Jaeger all-in-one chart](https://www.jaegertracing.io/docs/latest/operator/) — single-binary Jaeger with Badger backend, suitable for single-node demos
- [cert-manager documentation](https://cert-manager.io/docs/) — Let's Encrypt automation for the Istio ingress gateway

### Internal cross-references
- [`oracle-cloud-always-free-provisioning.md`](./oracle-cloud-always-free-provisioning.md) — the concrete operational walkthrough for the Oracle path recommended in [§8](#8-final-recommendation)
- [`docs/architecture/deployment-architecture-gcp.md`](../architecture/deployment-architecture-gcp.md) — the original $420/mo design this document is the demo-only counterpart to
- `kubernetes/services/*/deployment.yaml` and `kubernetes/infrastructure/**/*.yaml` — source of the application/infrastructure sizing in [§1](#1-workload-sizing--what-you-actually-need-to-host)
- `kubernetes/istio/*` — the mesh configuration preserved by the [§6](#6-single-node-k3s-topology) topology
- `kubernetes/network-policies/*` — the default-deny baseline preserved by the [§6](#6-single-node-k3s-topology) topology
- `kubernetes/kyverno/*` — the Phase 7 admission baseline preserved by the [§6](#6-single-node-k3s-topology) topology (already supports `local-path-storage`, the k3s default)
- `kubernetes/gateway/*` — Gateway API HTTPRoutes that route through the Istio ingress gateway

---

## Open questions for follow-up

1. Is the Auth0 free-tier user/MAU limit going to be a problem if recruiters click the link? (Probably not — Auth0 free is 7,500 MAU.)
2. Does the FRED API rate limit allow continuous polling from a public IP? (Currency-service is the only outbound dependency; need to confirm.)
3. Does the demo need Auth0 at all, or can we ship a "demo user" path that bypasses login? (Lower friction for the resume click, but loses the session-edge auth story which is part of the architecture showcase. Probably keep Auth0 and accept the friction.)
4. **ARM image availability** for `service-common` and the Spring Boot services — Eclipse Temurin publishes ARM64, so Jib should produce multi-arch images, but verify before committing to an ARM host. Same applies to `nginx-gateway`, `ext-authz`, and the Postgres/Redis/RabbitMQ images.
5. **cert-manager + Istio ingress gateway integration** — HTTP-01 challenge through the Istio ingress gateway is the standard pattern but requires a small `Gateway`/`HTTPRoute` config addition for the `.well-known/acme-challenge` path. Verify the recipe end-to-end before committing. DNS-01 via a Hetzner DNS API or Cloudflare token is the fallback if HTTP-01 proves fragile.
6. **Public Kiali/Grafana/Jaeger exposure** — basic auth at nginx-gateway is the minimum, but is there a cleaner pattern using the existing Istio AuthorizationPolicy infrastructure that the rest of the mesh already uses? See [§6](#6-single-node-k3s-topology) "Public exposure of the observability surface" for the three options; pick one and prototype it.
7. **Prometheus retention vs disk pressure** — 1 week was assumed in [§1](#1-workload-sizing--what-you-actually-need-to-host). If disk pressure shows up on a 160 GB box (CAX31), drop to 24-48h. The trade-off is "I can show a recruiter a 7-day mesh trend" vs "the box stays healthy unattended." Probably 48h is the right default.
8. **Kyverno on k3s** — the Phase 7 ClusterPolicies in `kubernetes/kyverno/policies/` are designed for the multi-node Tilt environment. The exception list already covers `local-path-storage`, but verify that the image-digest rule and the `:tilt-<hash>` exception don't accidentally block production pulls of Istio addon images. May need a small allow-path for the observability bundle's chart-managed images.
