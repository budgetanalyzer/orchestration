# Local Development Database Setup

## Overview

For local development, all microservices share a single PostgreSQL instance to avoid port conflicts. The shared PostgreSQL instance creates separate databases for each service.

## Configuration

**Host**: `localhost` (or `shared-postgres` from within Docker network)
**Port**: `5432`
**User**: `budget_analyzer`
**Password**: `budget_analyzer`

## Databases

| Service | Database Name | Connection String |
|---------|--------------|-------------------|
| transaction-service | `budget_analyzer` | `postgresql://budget_analyzer:budget_analyzer@localhost:5432/budget_analyzer` |
| currency-service | `currency` | `postgresql://budget_analyzer:budget_analyzer@localhost:5432/currency` |
| permission-service | `permission` | `postgresql://budget_analyzer:budget_analyzer@localhost:5432/permission` |

## Starting the Database

From the root orchestration directory:

```bash
docker compose up
```

This will start:
- Shared PostgreSQL instance on port 5432
- NGINX gateway on port 443 (HTTPS)

The databases are automatically created on first run via initialization scripts in `postgres-init/`.

## Connecting from Your Application

### From Host Machine (localhost)
```
postgresql://budget_analyzer:budget_analyzer@localhost:5432/budget_analyzer
```

### From Docker Containers
When your microservices run as Docker containers, use the container name as the hostname:
```
postgresql://budget_analyzer:budget_analyzer@shared-postgres:5432/budget_analyzer
```

Make sure your service's compose configuration includes the `gateway-network` network.

## Adding New Databases

When adding a new microservice that needs its own database:

1. Edit `postgres-init/01-init-databases.sql` and add:
   ```sql
   CREATE DATABASE your_database_name;
   GRANT ALL PRIVILEGES ON DATABASE your_database_name TO budget_analyzer;
   ```

2. Remove and recreate the PostgreSQL container:
   ```bash
   docker compose down -v  # WARNING: This deletes all data!
   docker compose up
   ```

   Alternatively, create the database manually without losing data:
   ```bash
   docker exec -it shared-postgres psql -U budget_analyzer -c "CREATE DATABASE your_db;"
   ```

## Troubleshooting

### Port Already in Use

If you see port 5432 already in use, check for other PostgreSQL instances:

```bash
# Check running containers
docker ps | grep postgres

# Check processes using port 5432
lsof -i :5432
```

### Database Not Found

The initialization scripts only run when the container is first created. If you added a new database but it doesn't exist, either:
- Recreate the container (loses data): `docker compose down -v && docker compose up`
- Manually create it (preserves data): `docker exec -it shared-postgres psql -U budget_analyzer -c "CREATE DATABASE your_db;"`

### Can't Connect from Microservice

Ensure your microservice:
1. Is on the same Docker network (`gateway-network`)
2. Uses `shared-postgres` as the hostname (not `localhost`)
3. Waits for PostgreSQL to be ready (use `depends_on` or health checks)
