# Budget Analyzer - Orchestration

> **⚠️ Work in Progress**: This project is under active development. Features and documentation are subject to change.

Orchestration repository for Budget Analyzer - a microservices-based personal finance management tool built with Spring Boot and React.

## Overview

This repository coordinates the deployment and local development environment for the Budget Analyzer application. Individual service code lives in separate repositories.

## Architecture

The application follows a microservices architecture with BFF (Backend for Frontend) pattern:

- **Frontend**: React 19 + TypeScript web application
- **Session Gateway (BFF)**: Spring Cloud Gateway for browser authentication and session management
- **Backend Services**: Spring Boot REST APIs
  - Transaction Service - Manages financial transactions
  - Currency Service - Handles currencies and exchange rates
  - Token Validation Service - JWT validation for NGINX
- **API Gateway**: NGINX reverse proxy for request routing and JWT validation
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ

## Quick Start

### Prerequisites

- Docker and Docker Compose
- JDK 24 (for local Spring Boot development)
- Node.js 18+ (for local React development)

**First-time setup**: See [docs/development/getting-started.md](docs/development/getting-started.md)

### Running the Application

```bash
# Start all infrastructure services
docker compose up -d

# View logs
docker compose logs -f

# Stop all services
docker compose down
```

The application will be available at `http://localhost:8081` (Session Gateway)

### Service Ports

- Session Gateway (BFF): `8081` (browser entry point)
- API Gateway (NGINX): `8080` (internal routing)
- Token Validation Service: `8088`
- PostgreSQL: `5432`
- Redis: `6379`
- RabbitMQ: `5672` (Management UI: `15672`)

## Project Structure

```
orchestration/
├── docker-compose.yml    # Service definitions
├── nginx/                # API gateway configuration
├── postgres-init/        # Database initialization scripts
├── scripts/              # Automation tools
├── docs/                 # Cross-service documentation
└── kubernetes/           # Production deployment manifests (future)
```

## Service Repositories

Each microservice is maintained in its own repository:

- **service-common**: https://github.com/budgetanalyzer/service-common
- **transaction-service**: https://github.com/budgetanalyzer/transaction-service
- **currency-service**: https://github.com/budgetanalyzer/currency-service
- **budget-analyzer-web**: https://github.com/budgetanalyzer/budget-analyzer-web
- **session-gateway**: https://github.com/budgetanalyzer/session-gateway
- **token-validation-service**: https://github.com/budgetanalyzer/token-validation-service
- **basic-repository-template**: https://github.com/budgetanalyzer/basic-repository-template

## Development

For detailed development instructions including:
- API gateway routing patterns
- Adding new services
- Troubleshooting
- Cross-service documentation standards

See [CLAUDE.md](CLAUDE.md)

## Technology Stack

- **Backend**: Spring Boot 3.x, Java 24
- **Frontend**: React 19, TypeScript, Vite
- **Session Management**: Spring Cloud Gateway, Redis
- **Authentication**: Auth0 (OAuth2/OIDC)
- **Database**: PostgreSQL
- **Cache**: Redis
- **Message Queue**: RabbitMQ
- **API Gateway**: NGINX
- **Container Orchestration**: Docker Compose

## License

MIT

## Contributing

This project is currently in early development. Contributions, issues, and feature requests are welcome as we build toward a stable release.
