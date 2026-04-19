# Production Secrets Management & AI Agent Boundaries

**Date:** 2026-04-12
**Status:** Research / architecture decision
**Audience:** Project owner planning the OCI demo deployment
**Companion to:** [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md), [`oracle-cloud-always-free-provisioning.md`](./oracle-cloud-always-free-provisioning.md)

This document addresses a question that the other deployment research docs left open: how do production secrets get into the cluster, and how do we keep them invisible to the AI agents that help build and deploy this project?

---

## TL;DR

| Concern | Local Dev | Production (OCI) |
|---|---|---|
| Secret storage | `.env` in workspace (Tilt reads it) | OCI Vault — secrets never on disk in workspace |
| K8s Secret injection | Tilt creates Secrets from `.env` values | External Secrets Operator syncs from OCI Vault |
| AI agent visibility | Agent can read `.env` if it exists (accepted risk for dev) | **Agent never sees production secrets** |
| Instance identifiers (OCIDs, IPs) | N/A | `~/.config/budget-analyzer/` — outside workspace |
| Rotation | Manual | OCI Vault rotation policies |

**Principle:** AI agents work with secret *names* and vault *paths*, never secret *values*. Templates and manifests are committed; populated values never enter the repo or the workspace directory tree.

---

## 1. The problem: gitignore is not a secrets boundary

The existing `.env` / `.gitignore` approach works for local dev: Tilt reads `.env`, creates Kubernetes Secrets, and `.gitignore` keeps `.env` out of version control. This is fine for local Kind clusters where the "secrets" are throwaway values like `budget-analyzer-postgres-admin`.

But `.gitignore` only prevents git commits. It does not prevent:

- **AI agents reading the file.** Any file under `/workspace/` is readable by Claude Code and any other AI coding assistant with filesystem access. A gitignored `deploy/secrets.env` in the workspace is fully visible to every AI session.
- **Accidental exposure in conversation context.** If an agent reads a file containing secrets, those values enter the conversation context and are transmitted to the LLM provider's servers. Even if the agent doesn't *display* the values, they've left the machine.
- **Persistence across sessions.** Every new AI session that happens to read (or be asked about) a secrets file sees those values independently.

**Conclusion:** Production secrets must not exist as files anywhere under `/workspace/`. The workspace is the AI agent's domain. Secrets belong in infrastructure the agent cannot reach.

---

## 2. OCI Vault: the production secrets store

### Why OCI Vault

- **Always Free tier includes 20 master encryption keys and 150 vault secrets.** The Budget Analyzer has ~10 Kubernetes Secrets with ~25 total keys. Well within free limits.
- **HSM-backed.** Even the free-tier Virtual Vault uses a multitenant HSM for master key protection.
- **Native OCI integration.** Instance principal authentication means the k3s node can authenticate to the vault without static credentials on disk — the instance's identity *is* the credential.
- **No new vendor.** Already committed to OCI for the compute instance.

### What goes in the vault

Every value currently listed in `docs/development/secrets-only-handling.md` as a Kubernetes Secret key:

| Vault secret path | Corresponds to K8s Secret | Keys |
|---|---|---|
| `budget-analyzer-auth0-client-secret` | `auth0-credentials` | AUTH0_CLIENT_SECRET |
| `budget-analyzer-fred-api-key` | `fred-api-credentials` | api-key |
| `budget-analyzer-postgres-admin-password` | `postgresql-bootstrap-credentials` | password |
| `budget-analyzer-postgres-transaction-svc` | `transaction-service-postgresql-credentials` | password |
| `budget-analyzer-postgres-currency-svc` | `currency-service-postgresql-credentials` | password |
| `budget-analyzer-postgres-permission-svc` | `permission-service-postgresql-credentials` | password |
| `budget-analyzer-rabbitmq-admin-password` | `rabbitmq-bootstrap-credentials` | password |
| `budget-analyzer-rabbitmq-definitions` | `rabbitmq-bootstrap-credentials` | definitions.json |
| `budget-analyzer-rabbitmq-currency-svc` | `currency-service-rabbitmq-credentials` | password |
| `budget-analyzer-redis-default-password` | `redis-bootstrap-credentials` | default-password |
| `budget-analyzer-redis-ops-password` | `redis-bootstrap-credentials` | ops-password |
| `budget-analyzer-redis-session-gateway` | `redis-bootstrap-credentials` | session-gateway-password |
| `budget-analyzer-redis-ext-authz` | `redis-bootstrap-credentials` | ext-authz-password |
| `budget-analyzer-redis-currency-svc` | `redis-bootstrap-credentials` | currency-service-password |

This is ~14 vault secrets. The free tier allows 150.

### Vault bootstrap is a manual, out-of-band operation

The project owner creates the vault and populates secrets through the OCI Console or OCI CLI on their local machine — never through an AI agent session. The commands are templated in the repo (with placeholders), but the actual execution happens outside the AI-assisted workflow.

---

## 3. External Secrets Operator: vault-to-k8s sync

[External Secrets Operator](https://external-secrets.io/) (ESO) is the bridge between OCI Vault and Kubernetes Secrets. It runs as a controller in the cluster, watches `ExternalSecret` custom resources, and creates/updates native Kubernetes `Secret` objects from vault data.

### Why ESO over alternatives

| Option | Verdict |
|---|---|
| **External Secrets Operator** | Best fit. Has a native [Oracle Vault provider](https://external-secrets.io/latest/provider/oracle-vault/). Helm install, low resource footprint (~50-100 MiB). |
| **CSI Secrets Store Driver** | Mounts secrets as files into pods. More complex, less Kubernetes-native (doesn't create Secret objects). |
| **Init container pulling from vault** | Custom code, no standard lifecycle management, harder to rotate. |
| **Sealed Secrets / SOPS** | Encrypts secrets *in git*. The encrypted blob is still in the repo and the decryption key is another secret to manage. Doesn't solve the "secrets outside workspace" requirement. |

### How it works

1. A `SecretStore` resource (committed to the repo) tells ESO how to reach OCI Vault. Authentication uses **instance principal** — the OCI instance's own identity, no static credentials needed.

2. `ExternalSecret` resources (committed to the repo) declare which vault secrets to sync and what Kubernetes Secret to create:

```yaml
# Example — committed to repo. Contains no secret values.
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgresql-bootstrap-credentials
  namespace: infrastructure
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: oci-vault
    kind: SecretStore
  target:
    name: postgresql-bootstrap-credentials
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: budget-analyzer-postgres-admin-password
```

3. ESO creates the native `Secret` object. Pods reference it exactly as they do today — no application code changes.

### What this means for the existing manifests

The `kubernetes/infrastructure/` and `kubernetes/services/` manifests that reference Secrets by name (`secretKeyRef`, `secretRef`, etc.) **do not change**. ESO creates the same Secret objects that Tilt creates locally. The difference is only in *how* the Secret gets populated — Tilt from `.env`, ESO from OCI Vault.

---

## 4. Instance-specific config: outside the workspace

Non-secret but deployment-specific values — OCIDs, compartment ID, public IP, domain name, availability domain — are not secrets, but they:

- Enable targeted reconnaissance if exposed publicly
- Are specific to one deployment, not useful to other contributors
- Should not clutter the committed repo

These live at **`~/.config/budget-analyzer/instance.env`** on the project owner's machine, outside `/workspace/` entirely. Deployment scripts source this file. The repo contains only a template documenting the expected keys:

```bash
# deploy/instance.env.template — committed to repo
# Copy to ~/.config/budget-analyzer/instance.env and fill in the blank values.

OCI_TENANCY_OCID=
OCI_COMPARTMENT_OCID=
OCI_REGION=us-phoenix-1
OCI_AVAILABILITY_DOMAIN=
OCI_VAULT_OCID=
OCI_VAULT_KEY_OCID=
OCI_INSTANCE_OCID=
OCI_SUBNET_OCID=
INSTANCE_PUBLIC_IP=
INSTANCE_SSH_KEY_PATH=~/.ssh/oci-budgetanalyzer
DEMO_DOMAIN=demo.budgetanalyzer.org
GRAFANA_DOMAIN=grafana.budgetanalyzer.org
KIALI_DOMAIN=
JAEGER_DOMAIN=
LETSENCRYPT_EMAIL=
PRODUCTION_RELEASE_VERSION=0.0.12
```

AI agents can read the template (it's in the repo) and write deployment scripts that reference `$OCI_VAULT_OCID`, but they never see the actual OCID value.

---

## 5. Deployment command patterns

Three patterns for different risk levels:

### Pattern A: Template commands — human pastes and fills in values

For one-time operations touching IAM, vault creation, and secret population. AI agent writes the command template with placeholders; human substitutes values and executes.

**Used for:** OCI Vault creation, populating vault secrets, IAM policy setup, DNS configuration.

### Pattern B: Idempotent scripts sourcing external config

For repeatable deployment operations. Scripts live in `deploy/scripts/`, source `~/.config/budget-analyzer/instance.env`, and are safe to re-run. Human reviews and executes. Temporary drafts or debug probes may live under `tmp/` while they are being iterated, but the repeatable deployment path belongs in `deploy/scripts/`, not `tmp/`.

**Used for:** k3s installation, Helm chart installs (Istio, ESO, cert-manager, observability), application deployment, certificate renewal.

### Pattern C: Direct execution by AI agent

For non-secret, non-destructive, local-only operations. The AI agent runs commands directly with user approval.

**Used for:** Writing manifests, editing scripts, running local `kubectl` against Kind, linting, static analysis.

### What this looks like in practice

```
deploy/
  instance.env.template              # committed — documents expected keys
  vault-bootstrap.sh.template        # committed — OCI Vault population (Pattern A)
  scripts/
    01-install-k3s.sh                # committed — pinned k3s install
    02-bootstrap-cluster.sh          # committed — Gateway API CRDs + namespaces
    03-render-phase-4-istio-manifests.sh
    04-install-istio.sh              # committed — Istio + mesh policy install
    05-install-platform-controllers.sh
    06-configure-host-redirects.sh
    07-apply-network-policies.sh
```

---

## 6. Threat model for this project

This section is deliberately honest about what we're protecting and what we're not. This is a portfolio demo project, not a bank.

### What we're protecting

| Asset | Impact if exposed | Mitigation |
|---|---|---|
| Database passwords | Attacker could read/destroy demo data | OCI Vault + ESO, never on disk |
| Auth0 client secret | Attacker could impersonate the app to Auth0 | OCI Vault, rotate if exposed |
| FRED API key | Attacker could exhaust rate limits | OCI Vault, free to replace |
| SSH private key | Full instance access | `~/.ssh/`, never in workspace, never in repo |
| OCI tenancy/compartment OCIDs | Targeted reconnaissance (not direct compromise) | Outside workspace, not committed |
| Instance public IP | Port scanning, targeted attacks | Outside workspace; public by nature once DNS is set |

### What we're NOT doing (and why)

- **Not encrypting secrets in git (Sealed Secrets / SOPS).** Adds complexity, the encrypted blob is still in the repo, and the decryption key is another secret to manage. OCI Vault is simpler and more aligned with the OCI-native deployment.
- **Not using a private fork.** The research docs, manifests, and scripts contain no secrets or deployment-specific values. A private fork creates sync overhead for no security benefit.
- **Not using HashiCorp Vault.** OCI Vault is free, native, and sufficient. HashiCorp Vault is excellent but adds an entire component to run and maintain on a single-node demo.
- **Not implementing dynamic short-lived credentials.** Industry best practice for production, overkill for a portfolio demo. Static secrets in OCI Vault with manual rotation is the right complexity level.

---

## 7. Action items for the deployment plan

These feed into the implementation plan doc (`docs/plans/single-instance-demo-hosting-plan.md`, to be created):

1. **Create `~/.config/budget-analyzer/` directory** on the project owner's machine. Populate `instance.env` after OCI instance is provisioned.
2. **Create OCI Vault** in the same compartment as the compute instance. Use the default Virtual Vault (free tier).
3. **Create IAM dynamic group + policy** allowing the compute instance to read vault secrets (instance principal auth).
4. **Populate vault secrets** via OCI CLI or Console (Pattern A — template commands).
5. **Add ESO Helm install** to the deployment script sequence.
6. **Write `ExternalSecret` manifests** for all 10 Kubernetes Secrets, referencing vault paths by name.
7. **Verify** that existing pod manifests work unchanged — they reference Secret names, and ESO creates those same Secret objects.

---

## References

### OCI Vault
- [OCI Vault Basics for Beginners](https://medium.com/oracledevs/oci-vault-basics-for-beginners-29988c375753) — walkthrough of vault and key creation
- [OCI Key Management FAQ](https://www.oracle.com/security/cloud-security/key-management/faq/) — free tier limits (20 keys, 150 secrets)
- [Oracle Cloud Always Free Tier](https://grokipedia.com/page/Oracle_Cloud_Always_Free_Tier) — free tier resource inventory

### External Secrets Operator + OCI
- [Using ESO with OCI Kubernetes and OCI Vault](https://medium.com/oracledevs/using-the-external-secrets-operator-with-oci-kubernetes-and-oci-vault-6865f2e1fe35) — end-to-end walkthrough
- [ESO Oracle Vault Provider](https://external-secrets.io/latest/provider/oracle-vault/) — provider configuration reference
- [External Secrets Operator GitHub](https://github.com/external-secrets/external-secrets) — project repo and docs

### AI agent security and secrets management
- [Future of Secrets Management in the Era of Agentic AI](https://aembit.io/blog/future-of-secrets-management-in-the-era-of-agentic-ai/) — identity-driven access patterns for AI agents
- [AI Agent Security: Enterprise Guide 2026](https://www.mintmcp.com/blog/ai-agent-security) — zero-trust patterns for AI-assisted workflows
- [State of Secrets Sprawl 2026](https://thehackernews.com/2026/03/the-state-of-secrets-sprawl-2026-9.html) — 81% increase in AI-service-related credential leaks

### Internal cross-references
- [`single-instance-demo-hosting.md`](./single-instance-demo-hosting.md) — workload sizing, provider selection, k3s topology
- [`oracle-cloud-always-free-provisioning.md`](./oracle-cloud-always-free-provisioning.md) — OCI account and instance provisioning
- [`docs/development/secrets-only-handling.md`](../development/secrets-only-handling.md) — the secret/config boundary policy and Kubernetes Secret inventory
- `.env.example` — local dev environment variable template (the dev-only counterpart to OCI Vault)
