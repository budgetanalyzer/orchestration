# Getting Started

**Tested with:** VS Code, Claude Code (extension or terminal), Anthropic account. We use open source tools—Cursor is closed source.

```bash
git clone https://github.com/budgetanalyzer/workspace.git
```

Open in VS Code → "Reopen in Container" when prompted.

First time takes several minutes to download Docker images. Click "show log" in the VS Code notification to watch progress — otherwise it looks stuck.

You're now in the devcontainer. You'll see all repos in the sidebar, but don't just click them — that browses files but doesn't load the repo's AGENTS.md. Use File → Open Folder to launch a new VS Code instance with the right Claude context.

---

## Talk to Architecture Claude

Want to discuss AI-native architecture patterns, explore how this system is designed, or understand the decisions behind it?

1. File → Open Folder → `/workspace/architecture-conversations`
2. Start a Claude Code conversation

Claude has full context on the architectural patterns and the relationships between repos.

---

## Run the Budget Analyzer App

Want to see the microservices architecture running locally? Useful for understanding how the pieces connect or making changes to services.

1. File → Open Folder → `/workspace/orchestration`
2. Follow the steps below

From your **host terminal** (not the devcontainer):

```bash
cd path/to/workspace/orchestration
./setup.sh        # Recreates the kind cluster, ensures supported Helm, installs Calico, configures certs (browser + infra TLS), DNS, and .env
vim .env          # Review infra password defaults; add Auth0 + FRED credentials
tilt up           # Start everything
./scripts/dev/verify-security-prereqs.sh   # Optional but recommended Phase 0 proof
./scripts/dev/verify-phase-1-credentials.sh   # Optional but recommended Phase 1 proof
./scripts/dev/verify-phase-2-network-policies.sh  # Optional but recommended Phase 2 proof
./scripts/dev/verify-phase-4-transport-encryption.sh  # Optional but recommended Phase 4 proof
```

Open https://app.budgetanalyzer.localhost when services are green.

Tilt now generates the local PostgreSQL, RabbitMQ, and Redis secrets from `.env`.
PostgreSQL uses a `postgres_admin` bootstrap user plus distinct per-service
database users. RabbitMQ uses `rabbitmq-admin` plus the `currency-service`
broker identity. Redis uses ACL users (`session-gateway`, `ext-authz`,
`currency-service`, `redis-ops`) plus a restricted probe-only `default` user.
`setup.sh` now rebuilds the `kind` cluster from scratch on every run instead of
reusing an existing cluster, and it installs Helm `v3.20.1` automatically if
the current Helm binary is missing or unsupported.
`setup.sh` now generates the internal transport-TLS secrets automatically.
To regenerate them standalone, run `./scripts/dev/setup-infra-tls.sh` from the host.
`./scripts/dev/check-tilt-prerequisites.sh` fails until `infra-ca` plus the
three `infra-tls-*` secrets exist.
`./scripts/dev/verify-phase-4-transport-encryption.sh` is the transport-TLS
completion gate for Redis, PostgreSQL, and RabbitMQ.
All verification scripts run against the current `kubectl` context. If a
verifier says pods or network policies are missing while Tilt looks healthy,
check `kubectl config current-context` and `tilt get uiresources` from the same
host shell before debugging the verifier itself.

> **Setup failing?** Run `./scripts/dev/check-tilt-prerequisites.sh` — it tells you exactly what's missing and how to install it.

## External Services (~10 min one-time setup)

The app needs two external accounts in addition to the local infrastructure password defaults already present in `.env`. Both are free:

### Auth0 (authentication)

1. Create account at [auth0.com](https://auth0.com)
2. Create Application → "Regular Web Application"
3. Copy Domain, Client ID, Client Secret to `.env`
4. Full guide: [auth0-setup.md](../setup/auth0-setup.md)

### FRED API (exchange rates)

1. Get free key at [fred.stlouisfed.org](https://fred.stlouisfed.org/docs/api/api_key.html)
2. Copy to `.env`
3. Full guide: [fred-api-setup.md](../setup/fred-api-setup.md)

### Using the App

- **Application**: https://app.budgetanalyzer.localhost
- **API Docs**: https://app.budgetanalyzer.localhost/api/docs
- **Tilt UI**: http://localhost:10350 (logs and status)

### Stopping

```bash
tilt down
```
