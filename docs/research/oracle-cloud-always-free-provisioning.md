# Oracle Cloud Always Free — A1 Provisioning Walkthrough

**Date:** 2026-04-06
**Status:** Operational walkthrough
**Audience:** Project owner provisioning the Budget Analyzer demo on Oracle Cloud Always Free
**Companion to:** [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md)

Concrete step-by-step for getting a 4 OCPU / 24 GB / 200 GB ARM Ampere A1 instance on Oracle Cloud Always Free, focused on the decisions and gotchas that trip up first-time users. Read this *after* [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md) has convinced you Oracle is the right host for this workload — the research note explains *why* Oracle; this doc explains *how*.

---

## TL;DR

- Pick **Phoenix** (US audience) or **Frankfurt** (EU audience) as your home region. Not Ashburn.
- Home region is **permanent** on Free Tier accounts. Pick carefully.
- Expect the capacity lottery to take 1-7 days. Use a retry script rather than refreshing the console.
- Do not upgrade to PAYG, do not use prepaid cards, do not try to change regions later.
- If you spend more than a week fighting Oracle friction, fall back to Hetzner CAX41 per [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md) §8. Do not spend more than a week trying to save $40/mo.

---

## 1. Before you start

- **Physical credit or debit card.** Oracle places an authorization hold of ~$1 that drops off in 3-5 days. They explicitly reject prepaid/virtual cards and silently flag accounts that try.
- **SSH keypair.** Generate one locally before provisioning so you can paste the public key during instance creation:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/oci-budgetanalyzer -C "oci-budgetanalyzer"
  ```
  You'll paste the contents of `~/.ssh/oci-budgetanalyzer.pub` when OCI asks for it.
- **Decision on home region** — see [§2](#2-home-region-selection) below. Make the decision *before* starting signup because the signup flow commits you.
- **Expect this to take multiple sessions.** Signup plus first provisioning attempt is one sitting; capacity retries often span several days.

---

## 2. Home region selection

Home region is **permanent on Free Tier accounts** and it **dramatically affects A1 capacity availability**. This is the single most consequential decision in the entire signup flow.

### Short answer

| Your audience | Pick this |
|---|---|
| North American recruiters | **Phoenix (PHX)** |
| European recruiters | **Frankfurt (FRA)** |
| Mixed / unsure | **Phoenix** — 140-160 ms to EU is still fine for HTTP |

Phoenix and Frankfurt have the longest track records of relatively better A1 Ampere capacity for Always Free users. Not "available immediately" — nothing is — but "you'll probably win the capacity lottery within a few days of retrying" rather than "you'll fight it for weeks."

### Regions to avoid

- **Ashburn (IAD, US East)** — the most in-demand region in OCI. A1 capacity there is famously terrible and has been for years. Do not pick Ashburn even if the signup UI pre-selects it based on your IP.
- **London (LHR), Tokyo (NRT), São Paulo (GRU), Seoul (ICN), Mumbai (BOM)** — consistently tight on A1 per community reports.
- **Any region you've pre-committed to for a reason other than A1 capacity.** A "nice to be close" region with no capacity is useless.

### Why this is a one-shot decision

1. **Home region cannot be changed on a Free Tier account.** Oracle support will not do it for you regardless of what forum posts you find. If you pick wrong, your only recourse is closing the account and starting over with a new credit card — which Oracle is good at detecting and often flags as fraud.
2. **"Subscribe to additional regions" does not help.** The OCI console has a "Manage regions" button that lets you add more regions to your tenancy after signup. This is a trap for Free Tier users: **Always Free resources stay tied to your original home region**. Subscribing to Phoenix from a Frankfurt home account only gives you paid access to Phoenix.
3. **Capacity is per-Availability-Domain within a region.** Regions with multiple ADs give you multiple independent capacity pools to try, but three empty ADs in Ashburn still equals no A1.

### 5-minute reality check before committing

Capacity drifts over time — Frankfurt has not always been the best, and Phoenix has had bad months too. Before you click "confirm region," spend 5 minutes searching for recent capacity reports:

- The `r/oraclecloud` subreddit — search `A1 capacity <region>` filtered to the past month
- The Oracle Cloud Community forum — same search

You're looking for recent posts saying things like "finally got an A1 in Phoenix after 2 days" (good) vs "still fighting Ashburn after 3 weeks" (avoid). This 5-minute check is much cheaper than a new-account-with-a-different-card situation later.

---

## 3. Create the account

1. Go to https://www.oracle.com/cloud/free/ and click "Start for free."
2. Enter your email, country, and verify.
3. Enter your name and address. Use a real address; Oracle does light address verification.
4. **Payment method.** Real credit or debit card. You'll see a small authorization hold on your statement within a day — expected, drops off in 3-5 days. If the hold becomes a real charge, open a ticket immediately.
5. **Choose your home region.** Double-check this matches your decision from [§2](#2-home-region-selection) before confirming. You cannot change it later.
6. Complete SMS verification.
7. Wait for account activation. Usually 5-15 minutes but can occasionally take hours. You'll get an email when it's ready.

### If the account gets flagged during signup

This happens occasionally — usually due to a card/address mismatch or a region heuristic. Open a support ticket through the form on the signup error page. Resolution typically takes 24-48 hours. **Do not retry with a different card on the same browser** — that can make things worse.

---

## 4. First login and orientation

1. Log in at https://cloud.oracle.com/. Oracle's login flow is awkward — you may need to enter your tenancy name (chosen during signup) before your username.
2. You'll land on the OCI console. The primary navigation is the hamburger menu at the top-left.
3. **Verify your free-tier status.** Hamburger menu → Governance → Limits, Quotas and Usage. Confirm you see "Always Free" availability for `VM.Standard.A1.Flex` in your home region. If the limit shows 0, you're on PAYG, not Always Free.
4. **Do not upgrade to PAYG** even if the console suggests it. "Upgrade to Pay As You Go" is a one-way door — your Always Free resources remain free but you lose the "Always Free" account safety rail. Stay on the Free Tier account.

---

## 5. Prepare networking

Open ingress ports *before* provisioning the VM. Forgetting this is the #1 reason people say "my instance is up but I can't reach it."

1. Hamburger menu → Networking → Virtual Cloud Networks.
2. You should see a default VCN (often named `vcn-<timestamp>`). If not, click "Start VCN Wizard" → "Create VCN with Internet Connectivity" and accept the defaults.
3. Click into the VCN, then "Security Lists" → the default security list.
4. Add these ingress rules:
   - Source `0.0.0.0/0`, TCP, destination port `22` — usually already present
   - Source `0.0.0.0/0`, TCP, destination port `80`
   - Source `0.0.0.0/0`, TCP, destination port `443`
5. Confirm the VCN has an "Internet Gateway" attached and the public subnet's route table routes `0.0.0.0/0` to it.

---

## 6. Provision the A1 instance

1. Hamburger menu → Compute → Instances → "Create instance."
2. **Name:** something like `budgetanalyzer-demo`.
3. **Placement:** default compartment (root) is fine. Note which Availability Domain you end up in (AD-1/AD-2/AD-3) because A1 capacity is per-AD.
4. **Image:** Click "Change image" → Ubuntu → **Canonical Ubuntu 22.04 (aarch64)**. Verify it says `aarch64`, not `x86_64`. Picking the x86 image by accident is a classic first-try mistake because the default is often x86.
5. **Shape:** Click "Change shape" → "Ampere" tab → **VM.Standard.A1.Flex**.
6. **OCPUs and memory:** Set OCPUs to **4** and memory to **24 GB**. This is the maximum of the Always Free A1 allowance — take all of it.
7. **Networking:** Default VCN and public subnet. Ensure "Assign a public IPv4 address" is checked.
8. **SSH keys:** Paste the contents of `~/.ssh/oci-budgetanalyzer.pub` into the "Paste public keys" box.
9. **Boot volume:** Expand "Specify a custom boot volume size" and set it to **200 GB** (default is 47 GB; Always Free includes 200 GB total block storage — use it). Leave VPU at Balanced.
10. Click "Create."

---

## 7. Handle "Out of host capacity"

You will probably see this error on your first attempt. This is normal. Do not panic, do not change home regions, do not delete and recreate the account on the same card.

Options in order of effort:

1. **Retry manually, rotating availability domains.** On the create-instance page, change the "Availability Domain" dropdown (AD-1 → AD-2 → AD-3) and try again. Capacity is per-AD and frees up sporadically.
2. **Wait a few hours and retry.** Capacity often frees up in bursts when other users' trial instances get reclaimed.
3. **Set up the community retry script.** This is the accepted workaround at this point. The most-used one is [hitrov/oci-arm-host-capacity](https://github.com/hitrov/oci-arm-host-capacity).

### Setting up the retry script

1. In the OCI console: click your avatar (top-right) → "My profile" → "API Keys" → "Add API Key" → "Generate API Key Pair." Download the private key file. Copy the displayed config snippet (you'll need `tenancy`, `user`, `fingerprint`, `region`).
2. Gather the OCIDs you'll need. The OCI Cloud Shell (the `>_` icon in the top bar) has the `oci` CLI pre-authenticated:
   ```bash
   # Availability Domains in your home region
   oci iam availability-domain list

   # Tenancy / root compartment OCID
   oci iam compartment list --all --compartment-id-in-subtree true

   # Public subnet OCID
   oci network subnet list --compartment-id <tenancy-ocid>

   # Image OCID for Ubuntu 22.04 aarch64
   oci compute image list --compartment-id <tenancy-ocid> \
     --operating-system "Canonical Ubuntu" \
     --operating-system-version "22.04" \
     --shape "VM.Standard.A1.Flex"
   ```
3. Clone the script somewhere it can run continuously — your laptop overnight is fine, or a $4/mo tiny VPS if you want it running 24/7:
   ```bash
   git clone https://github.com/hitrov/oci-arm-host-capacity.git
   cd oci-arm-host-capacity
   ```
4. Populate the `.env` file with the OCIDs, the A1 shape parameters (4 OCPU, 24 GB, 200 GB boot volume), the availability domains you want to try, and your SSH public key. Follow the repo's README for the exact variable names — they change occasionally.
5. Run the script in a loop. When capacity becomes available, it provisions the instance and stops.

### What NOT to do

- **Do not try to switch home regions.** Oracle does not support this on Free Tier. Your only recourse would be a new account with a fresh credit card, which Oracle is good at detecting.
- **Do not delete and recreate a working VCN repeatedly.** You'll burn your network configuration for no reason.
- **Do not confuse `LimitExceeded` with `OutOfCapacity`.** `LimitExceeded` means you already have an A1 instance (or you're on PAYG without an uplifted limit). Delete any existing A1 first.

---

## 8. First SSH and shape verification

Once the instance is running and has a public IP:

```bash
ssh -i ~/.ssh/oci-budgetanalyzer ubuntu@<public-ip>
```

(Use `opc@` instead of `ubuntu@` if you picked Oracle Linux.)

Verify you got what you asked for:

```bash
uname -m      # expect: aarch64
nproc         # expect: 4
free -h       # total should show ~24 GB
df -h /       # should show ~200 GB available
```

If any of those don't match, you provisioned the wrong shape — delete and retry with the correct settings.

---

## 9. Host-level firewall gotcha

Ubuntu on OCI ships with `iptables` rules that mirror the VCN security list — meaning even after you open ports 80 and 443 in the VCN, the host-level `iptables` may still block them. This is the #2 "my instance is up but I can't reach it" trap.

To fix:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
```

Test from your laptop:

```bash
curl -v http://<public-ip>
```

Expect the connection to succeed and then close (nothing is listening on 80 yet). If you get "connection refused" that's the iptables path working but nothing listening — fine. If you get "connection timed out" either iptables or the VCN security list is still blocking — go fix it before moving on.

---

## 10. Basic hardening before installing anything

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

SSH should already be key-only by default on OCI Ubuntu images. Confirm:

```bash
sudo grep -E '^(PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config
```

Expect `PasswordAuthentication no` and `PermitRootLogin prohibit-password` (or `no`).

---

## 11. Recurring maintenance

Set calendar reminders for these:

- **Log into the OCI console once a month.** Free Tier accounts inactive for 30 days are eligible for suspension. One login per month is enough to keep it alive.
- **Do not touch "Upgrade to PAYG"** even if Oracle emails promotional offers.
- **Monitor the idle-reclamation policy** — see [§12](#12-idle-reclamation-policy-details) below.

---

## 12. Idle reclamation policy details

Oracle reclaims idle Always Free compute instances to free up capacity. Understanding this policy is critical to keeping your instance.

### What triggers reclamation

Your instance is considered **idle** if ALL THREE of the following are below 20% (measured as the 95th percentile over a rolling 7-day window):

| Metric | Threshold | Applies to |
|--------|-----------|------------|
| CPU utilization | < 20% | All Always Free instances |
| Network utilization | < 20% | All Always Free instances |
| Memory utilization | < 20% | **A1 Ampere instances only** |

For a 4 OCPU / 24 GB A1 instance, the memory threshold means you need **~4.8 GB consistently in use** to stay above 20%.

### Warning and grace period

1. **Day 7:** If your instance has been idle for 7 consecutive days, Oracle sends an email notification and displays a warning in the console.
2. **Day 14:** One week after the warning, the instance is **stopped** (not deleted).

This gives you a full week to take action after the warning.

### What "reclaimed" means

- The instance is **stopped, not terminated**
- All data, configuration, and boot volumes are preserved
- You can restart the instance anytime — subject to capacity availability
- No data loss occurs

The risk is that if capacity is tight when you try to restart, you may hit "Out of host capacity" again.

### Why the Budget Analyzer stack should be safe

If you're running the full architecture (k3s + Istio + services + Prometheus/Grafana/Loki), you'll comfortably exceed all thresholds:

- **Memory:** k3s, Istio control plane, Prometheus, and even a modest workload will easily use 5+ GB
- **CPU:** Prometheus scraping, Istio sidecar proxies, and background reconciliation loops generate continuous CPU activity
- **Network:** Prometheus scrapes, log shipping, and health checks create steady network traffic

### Monitoring your utilization

Check your metrics in the OCI console:

1. Compute → Instances → click your instance
2. Scroll to "Metrics" section
3. Review CPU, Memory, and Network charts
4. Look at the 7-day view to see if you're consistently above 20%

Do this weekly for the first month after deployment to confirm your workload keeps the instance active.

### If you're not running workloads yet

If your instance will sit idle while you prepare deployment:

- You have **14 days minimum** before any action (7 days idle + 7 days grace)
- Rebooting or restarting the instance does **not** reset the 7-day metrics window — the idle determination is based on rolling utilization metrics, not instance state changes
- Don't leave it idle for extended periods — deploy something or accept the risk of needing to fight the capacity lottery again to restart

### Recommended: set up UptimeRobot during the setup phase

Before the full stack is running, set up a free [UptimeRobot](https://uptimerobot.com/) HTTP check hitting the instance every 5 minutes. This generates steady network traffic that contributes to keeping the network utilization metric above the 20% threshold. Once k3s and the application stack are deployed, Prometheus scraping (~20 targets every 15 seconds) and Istio sidecar telemetry will keep all three metrics well above threshold permanently — but UptimeRobot covers the gap during the setup phase when the box is mostly idle between SSH sessions.

UptimeRobot also serves a second purpose once the demo is live: it keeps the JVMs warm so the first visitor after an idle period doesn't hit a 30+ second cold-start (see [`single-instance-demo-hosting.md` §7](./single-instance-demo-hosting.md#7-is-this-a-bad-idea-honest-assessment)).

---

## What comes next

Once you have SSH access to a confirmed 4 OCPU / 24 GB / aarch64 box with ports 80 and 443 reachable from the internet, you're at the "install k3s" step of the main plan.

Return to [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md) §8 "Concrete next steps" starting from step 4: install k3s with the disable flags, then Istio, then the existing manifests under `kubernetes/`, then the observability bundle, then cert-manager.

## If Oracle doesn't work out

If you spend more than a week fighting the capacity lottery, account flagging, or any other Oracle-specific friction, the escape hatch is documented in [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md) §8: sign up for Hetzner Cloud and provision a CAX41 (€31.49/mo + €6.30 backups, ~$40/mo all-in). Same ARM architecture, same container images, no capacity lottery, refund-backed consumer-protection. Do not spend more than a week trying to save $40/mo.

---

## References

- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
- [Always Free Resources documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Oracle Cloud Free Tier FAQ](https://www.oracle.com/cloud/free/faq/)
- [Resolving Out of Host Capacity errors](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/troubleshooting-out-of-host-capacity.htm)
- [hitrov/oci-arm-host-capacity — community retry script](https://github.com/hitrov/oci-arm-host-capacity)
- [r/oraclecloud — current capacity reports](https://www.reddit.com/r/oraclecloud/)

### Related internal docs

- [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md) — the research note that explains why Oracle (or Hetzner CAX41) is the right host for this workload, with the full architecture sizing and the "asterisks" list of Oracle Free Tier catches
