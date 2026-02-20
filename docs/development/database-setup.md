# Local Development Database Setup

## Overview

For local development, PostgreSQL runs as a StatefulSet in the Kind cluster's `infrastructure` namespace. Each microservice has its own database within the shared PostgreSQL instance.

## Configuration

**Access via port forward (Tilt manages this automatically):**
- **Host**: `localhost`
- **Port**: `5432`
- **User**: `budget_analyzer`
- **Password**: `budget_analyzer`

**Access within cluster:**
- **Host**: `postgresql.infrastructure`
- **Port**: `5432`

## Databases

| Service | Database Name | Connection String |
|---------|--------------|-------------------|
| transaction-service | `budget_analyzer` | `postgresql://budget_analyzer:budget_analyzer@localhost:5432/budget_analyzer` |
| currency-service | `currency` | `postgresql://budget_analyzer:budget_analyzer@localhost:5432/currency` |

## Starting the Database

PostgreSQL is started automatically when you run:

```bash
tilt up
```

Tilt will:
1. Deploy PostgreSQL StatefulSet to the `infrastructure` namespace
2. Create databases via init scripts in `postgres-init/`
3. Set up port forward to `localhost:5432`

## Connecting from Your Application

### From Host Machine (via port forward)

Tilt automatically sets up port forwarding. Connect to:
```
postgresql://budget_analyzer:budget_analyzer@localhost:5432/budget_analyzer
```

### From Pods in Kubernetes

Services running in the cluster use the Kubernetes DNS name:
```
postgresql://budget_analyzer:budget_analyzer@postgresql.infrastructure:5432/budget_analyzer
```

## Adding New Databases

When adding a new microservice that needs its own database:

1. Edit `postgres-init/01-init-databases.sql` and add:
   ```sql
   CREATE DATABASE your_database_name;
   GRANT ALL PRIVILEGES ON DATABASE your_database_name TO budget_analyzer;
   ```

2. Create the database manually:
   ```bash
   kubectl exec -n infrastructure postgresql-0 -- psql -U budget_analyzer -c "CREATE DATABASE your_db;"
   ```

3. Update the PostgreSQL credentials secret in `Tiltfile`:
   ```starlark
   pg_data = encode_secret_data({
       # ... existing databases ...
       'your-service-url': 'jdbc:postgresql://postgresql.' + INFRA_NAMESPACE + ':5432/your_database_name',
   })
   ```

## Direct Database Access

### Using psql

```bash
# Connect via kubectl exec
kubectl exec -it -n infrastructure postgresql-0 -- psql -U budget_analyzer -d budget_analyzer

# Or use local psql with port forward (Tilt manages this)
psql -h localhost -U budget_analyzer -d budget_analyzer
```

### Using a GUI Client

Connect your favorite database client (DBeaver, DataGrip, etc.) to:
- Host: `localhost`
- Port: `5432`
- User: `budget_analyzer`
- Password: `budget_analyzer`

## Troubleshooting

### Port Already in Use

If you see port 5432 already in use, check for other PostgreSQL instances:

```bash
# Check for local PostgreSQL
lsof -i :5432

# Check if Tilt port forward is active
ps aux | grep "kubectl.*port-forward.*5432"
```

### Database Not Found

The initialization scripts only run when the PVC is first created. If you added a new database but it doesn't exist:

Create the database manually:
```bash
kubectl exec -n infrastructure postgresql-0 -- psql -U budget_analyzer -c "CREATE DATABASE your_db;"
```

### Can't Connect from Service

Ensure your service:
1. Uses the correct hostname: `postgresql.infrastructure` (not `localhost`)
2. Has the correct port: `5432`
3. Uses credentials from the `postgresql-credentials` secret

### PostgreSQL Pod Not Starting

```bash
# Check pod status
kubectl get pods -n infrastructure

# Check pod events
kubectl describe pod -n infrastructure postgresql-0

# Check PVC status
kubectl get pvc -n infrastructure
```

## Backup and Restore

### Backup

```bash
# Backup all databases
kubectl exec -n infrastructure postgresql-0 -- pg_dumpall -U budget_analyzer > backup.sql

# Backup specific database
kubectl exec -n infrastructure postgresql-0 -- pg_dump -U budget_analyzer budget_analyzer > budget_analyzer.sql
```

### Restore

```bash
# Restore from backup
kubectl exec -i -n infrastructure postgresql-0 -- psql -U budget_analyzer < backup.sql
```
