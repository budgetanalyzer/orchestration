# Budget Analyzer

A production-grade microservices financial management system built as an open-source learning resource for architects exploring AI-assisted development.

## Prerequisites

**Host Tools**: Docker, Kind, kubectl, Helm, Tilt, mkcert

**Optional**: JDK 24, Node.js 18+ (only if running services locally)

### Development Environment

**This project is designed for AI-assisted development.**

**Required**: VS Code with Dev Containers extension

**Not supported**: Cursor (closed source), IntelliJ (no container support)

The devcontainer provides a safe isolated environment for AI agents with pre-installed tools (JDK, Node.js, Maven, Docker CLI) and workspace-wide repository access.

> **Note**: You can work without AI using any IDE, but this is an AI-first learning resource.

See [CLAUDE.md](CLAUDE.md#development-environment-requirements) for details.

## Quick Start

### 1. Clone & Setup

```bash
git clone https://github.com/budgetanalyzer/orchestration.git
cd orchestration
./setup.sh
```

### 2. Configure Auth0

1. Create account at https://manage.auth0.com
2. Create Application → **Regular Web Application**
3. Settings → copy **Domain**, **Client ID**, **Client Secret**
4. Set Allowed Callback URLs:
   ```
   https://app.budgetanalyzer.localhost/login/oauth2/code/auth0
   ```
5. Set Allowed Logout URLs:
   ```
   https://app.budgetanalyzer.localhost/peace
   ```

See [docs/setup/auth0-setup.md](docs/setup/auth0-setup.md) for details.

### 3. Configure FRED API

1. Register at https://fred.stlouisfed.org/docs/api/api_key.html
2. Copy your API key

See [docs/setup/fred-api-setup.md](docs/setup/fred-api-setup.md) for details.

### 4. Configure & Run

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your Auth0 and FRED credentials
vi .env

# Start all services
tilt up
```

Open https://app.budgetanalyzer.localhost

## Documentation

- [Getting Started](docs/development/getting-started.md)
- [Architecture Overview](docs/architecture/system-overview.md)
- [Development Guide](CLAUDE.md)

## Service Repositories

- [service-common](https://github.com/budgetanalyzer/service-common) - Shared library
- [transaction-service](https://github.com/budgetanalyzer/transaction-service) - Transaction API
- [currency-service](https://github.com/budgetanalyzer/currency-service) - Currency API
- [budget-analyzer-web](https://github.com/budgetanalyzer/budget-analyzer-web) - React frontend
- [session-gateway](https://github.com/budgetanalyzer/session-gateway) - Authentication BFF
- [token-validation-service](https://github.com/budgetanalyzer/token-validation-service) - JWT validation
- [permission-service](https://github.com/budgetanalyzer/permission-service) - Permissions API

## License

MIT
