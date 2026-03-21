# Local Development Database Setup

## Overview

For local development, PostgreSQL runs as a StatefulSet in the Kind cluster's
`infrastructure` namespace. Each backend service gets its own database and its
own login inside the shared PostgreSQL instance.

Phase 1 Step 2 hardens that local PostgreSQL path:

- PostgreSQL bootstrap credentials come from `postgresql-bootstrap-credentials`
  instead of inline manifest values.
- The bootstrap superuser is now `postgres_admin`.
- Each consuming service gets its own PostgreSQL connection secret and its own
  database user.
- First-time bootstrap uses a shell init script that reads per-service
  passwords from Kubernetes Secrets and stores them with SCRAM-SHA-256.

This step changes first-init behavior. If your PostgreSQL PVC predates Step 2,
recreate PostgreSQL state before expecting the new users or auth rules:

```bash
kubectl delete pvc -n infrastructure postgresql-data-postgresql-0
kubectl delete pod -n infrastructure postgresql-0
```

Recreating the Kind cluster is also valid if you want a clean local reset.

## Secret Contract

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `postgresql-bootstrap-credentials` | `infrastructure` | PostgreSQL bootstrap admin and per-service init passwords |
| `transaction-service-postgresql-credentials` | `default` | transaction-service connection |
| `currency-service-postgresql-credentials` | `default` | currency-service connection |
| `permission-service-postgresql-credentials` | `default` | permission-service connection |

Each service secret uses the same keys:

- `username`
- `password`
- `url`

## Current Local Access

**Access via port forward (Tilt manages this automatically):**

- **Host**: `localhost`
- **Port**: `5432`
- **Bootstrap user**: `postgres_admin`
- **Bootstrap password**: `POSTGRES_BOOTSTRAP_PASSWORD` from `.env`
  - Default: `budget-analyzer-postgres-admin`

**Access within cluster:**

- **Host**: `postgresql.infrastructure`
- **Port**: `5432`

## Databases

| Service | Database Name | Database User | Secret | Local Connection String |
|---------|---------------|---------------|--------|-------------------------|
| transaction-service | `budget_analyzer` | `transaction_service` | `transaction-service-postgresql-credentials` | `postgresql://transaction_service:${POSTGRES_TRANSACTION_SERVICE_PASSWORD:-budget-analyzer-transaction-service}@localhost:5432/budget_analyzer` |
| currency-service | `currency` | `currency_service` | `currency-service-postgresql-credentials` | `postgresql://currency_service:${POSTGRES_CURRENCY_SERVICE_PASSWORD:-budget-analyzer-currency-service}@localhost:5432/currency` |
| permission-service | `permission` | `permission_service` | `permission-service-postgresql-credentials` | `postgresql://permission_service:${POSTGRES_PERMISSION_SERVICE_PASSWORD:-budget-analyzer-permission-service}@localhost:5432/permission` |

Only the owning service user is granted `CONNECT` on its database. The
`postgres_admin` superuser remains the break-glass path across all databases.

## Starting the Database

PostgreSQL is started automatically when you run:

```bash
tilt up
```

Tilt will:

1. Deploy the PostgreSQL StatefulSet to the `infrastructure` namespace.
2. Generate `postgresql-bootstrap-credentials`.
3. Generate one PostgreSQL connection secret per consuming service.
4. Start PostgreSQL with SCRAM-SHA-256 auth enabled.
5. On first init, create the service users, databases, and ownership/grants.
6. Set up port forwarding to `localhost:5432`.

## Connecting from Your Application

### From Host Machine

Service-owned connection:

```bash
psql -h localhost -U transaction_service -d budget_analyzer
```

Break-glass admin connection:

```bash
psql -h localhost -U postgres_admin -d postgres
```

Connection string examples:

```bash
postgresql://transaction_service:${POSTGRES_TRANSACTION_SERVICE_PASSWORD:-budget-analyzer-transaction-service}@localhost:5432/budget_analyzer
postgresql://postgres_admin:${POSTGRES_BOOTSTRAP_PASSWORD:-budget-analyzer-postgres-admin}@localhost:5432/postgres
```

### From Pods in Kubernetes

Services running in the cluster use the Kubernetes DNS name:

```text
jdbc:postgresql://postgresql.infrastructure:5432/<database>
```

The corresponding service deployment reads the exact URL, username, and password
from its own `*-postgresql-credentials` secret.

## Adding a New Database

When adding a new microservice that needs its own database:

1. Add a new password entry to `.env.example` and secret generation to
   `Tiltfile`.
2. Extend `kubernetes/infrastructure/postgresql/configmap.yaml` with the new
   service role and database mapping.
3. Add a dedicated secret in `Tiltfile` with the pattern
   `your-service-postgresql-credentials`.
4. Populate that service secret with `username`, `password`, and `url`.
5. Update the consuming deployment to read from that service-specific secret.

Do not recreate the old shared `postgresql-credentials` secret shape. The local
contract is one secret per consuming service.

## Direct Database Access

### Using psql in the Pod

```bash
kubectl exec -it -n infrastructure postgresql-0 -- /bin/sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d postgres'
```

### Using a GUI Client

Connect your database client (DBeaver, DataGrip, etc.) to:

- Host: `localhost`
- Port: `5432`
- User: `transaction_service` for the application database, or `postgres_admin`
  for admin access
- Password: the corresponding value from `.env`

## Troubleshooting

### Port Already in Use

```bash
lsof -i :5432
ps aux | grep "kubectl.*port-forward.*5432"
```

### Existing PVC Still Has Pre-Step-2 State

Symptoms include probes failing because `postgres_admin` does not exist yet or
service connections failing because `transaction_service` / `currency_service` /
`permission_service` were never created. Recreate PostgreSQL state:

```bash
kubectl delete pvc -n infrastructure postgresql-data-postgresql-0
kubectl delete pod -n infrastructure postgresql-0
```

### Database Not Found

The init script only runs when the PVC is first created. If you changed the
first-boot database mapping, update the init script and recreate PostgreSQL
state. For one-off local admin work, use `postgres_admin` and then apply the
same ownership/grant pattern manually.

### Can't Connect from a Service

Ensure the service:

1. Uses `postgresql.infrastructure` as the hostname.
2. Reads from its own `*-postgresql-credentials` secret.
3. Uses the correct `url`, `username`, and `password` keys.
4. Is connecting with its own database user, not `postgres_admin`.

### PostgreSQL Pod Not Starting

```bash
kubectl get pods -n infrastructure
kubectl describe pod -n infrastructure postgresql-0
kubectl get pvc -n infrastructure
```

## Backup and Restore

### Backup

```bash
kubectl exec -n infrastructure postgresql-0 -- /bin/sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dumpall -U "$POSTGRES_USER"' > backup.sql
kubectl exec -n infrastructure postgresql-0 -- /bin/sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" budget_analyzer' > budget_analyzer.sql
```

### Restore

```bash
kubectl exec -i -n infrastructure postgresql-0 -- /bin/sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER"' < backup.sql
```
