# Budget Analyzer

A production-grade microservices financial management system built as an open-source learning resource for architects exploring AI-assisted development.

## Prerequisites

Docker, Kind, kubectl, Helm, Tilt, JDK 24, Node.js 18+, mkcert

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
# Edit .env with your Auth0 and FRED credentials
vim .env

# Start all services
tilt up
```

Open https://app.budgetanalyzer.localhost

## Documentation

- [Architecture Overview](docs/architecture/overview.md)
- [Development Guide](CLAUDE.md)
- [Troubleshooting](docs/development/troubleshooting.md)

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
