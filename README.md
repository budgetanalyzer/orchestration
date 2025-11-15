# Budget Analyzer - Orchestration

> **⚠️ Work in Progress**: This project is under active development. Features and documentation are subject to change.

Orchestration repository for Budget Analyzer - a microservices-based personal finance management tool built with Spring Boot and React.

## Overview

This repository coordinates the deployment and local development environment for the Budget Analyzer application. Individual service code lives in separate repositories.

## Architecture

The application follows a microservices architecture:

- **Frontend**: React 19 + TypeScript web application
- **Backend Services**: Spring Boot REST APIs
  - Transaction Service - Manages financial transactions
  - Currency Service - Handles currencies and exchange rates
- **API Gateway**: NGINX reverse proxy for unified routing
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ

## Quick Start

### Prerequisites

- Docker and Docker Compose
- JDK 24 (for local Spring Boot development)
- Node.js 18+ (for local React development)

### Running the Application

```bash
# Start all infrastructure services
docker compose up -d

# View logs
docker compose logs -f

# Stop all services
docker compose down
```

The API gateway will be available at `http://localhost:8080`

### Service Ports

- API Gateway (NGINX): `8080`
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

- **service-common**: https://github.com/budget-analyzer/service-common
- **transaction-service**: https://github.com/budget-analyzer/transaction-service
- **currency-service**: https://github.com/budget-analyzer/currency-service
- **budget-analyzer-web**: https://github.com/budget-analyzer/budget-analyzer-web

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
- **Database**: PostgreSQL
- **Cache**: Redis
- **Message Queue**: RabbitMQ
- **API Gateway**: NGINX
- **Container Orchestration**: Docker Compose

## License

MIT

## Contributing

This project is currently in early development. Contributions, issues, and feature requests are welcome as we build toward a stable release.
