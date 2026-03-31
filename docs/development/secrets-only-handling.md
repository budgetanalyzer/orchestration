# Secrets-Only Handling

This repo now enforces a simple boundary:

- Kubernetes `Secret` objects hold only sensitive material.
- Non-secret runtime settings stay in checked-in manifests or explicit
  ConfigMap render paths.
- Sourcing a value from `.env` does not make it a secret by itself.

## Current Local Secret Inventory

| Secret | Keys |
|--------|------|
| `auth0-credentials` | `AUTH0_CLIENT_SECRET` |
| `fred-api-credentials` | `api-key` |
| `postgresql-bootstrap-credentials` | `password`, `transaction-service-password`, `currency-service-password`, `permission-service-password` |
| `transaction-service-postgresql-credentials` | `password` |
| `currency-service-postgresql-credentials` | `password` |
| `permission-service-postgresql-credentials` | `password` |
| `rabbitmq-bootstrap-credentials` | `password`, `definitions.json` |
| `currency-service-rabbitmq-credentials` | `password` |
| `redis-bootstrap-credentials` | `default-password`, `ops-password`, `session-gateway-password`, `ext-authz-password`, `currency-service-password` |
| `session-gateway-redis-credentials` | `password` |
| `ext-authz-redis-credentials` | `password` |
| `currency-service-redis-credentials` | `password` |

`rabbitmq-bootstrap-credentials[definitions.json]` is the one documented
mixed-required payload. RabbitMQ boot import expects a single definitions
document, so the file necessarily includes usernames and the vhost alongside
the secret values it configures.

## Current Local Config Inventory

| Config Path | Purpose |
|-------------|---------|
| Checked-in service deployments | PostgreSQL JDBC URLs, service usernames, Redis hosts/ports/usernames, RabbitMQ host/port/username/vhost |
| `ConfigMap/session-gateway-config` | checked-in Session Gateway runtime settings such as `SESSION_TTL_SECONDS` |
| `ConfigMap/session-gateway-idp-config` | checked-in fallback for non-secret Auth0/IDP settings: `AUTH0_CLIENT_ID`, `AUTH0_ISSUER_URI`, `IDP_AUDIENCE`, `IDP_LOGOUT_RETURN_TO`; Tilt overwrites it locally from `.env` |

## Misclassified Keys Removed

| Previous Secret Path | Removed Non-Secret Keys | New Home |
|----------------------|-------------------------|----------|
| `auth0-credentials` | `AUTH0_CLIENT_ID`, `AUTH0_ISSUER_URI`, `IDP_AUDIENCE`, `IDP_LOGOUT_RETURN_TO` | `session-gateway-idp-config` |
| `postgresql-bootstrap-credentials` | `username` | checked-in PostgreSQL StatefulSet env |
| `*-postgresql-credentials` | `username`, `url` | checked-in service deployment env |
| `currency-service-rabbitmq-credentials` | `host`, `amqp-port`, `username`, `virtual-host` | checked-in currency-service deployment env |
| `rabbitmq-bootstrap-credentials` | `username`, `currency-service-username`, `virtual-host` | checked-in manifest values and the documented `definitions.json` exception |
| `*-redis-credentials` | `host`, `port`, `username` | checked-in service deployment env |
| `redis-bootstrap-credentials` | `default-username`, `ops-username`, `session-gateway-username`, `ext-authz-username`, `currency-service-username` | checked-in manifest values and verifier constants |

## Guardrail

Run:

```bash
./scripts/dev/check-secrets-only-handling.sh
```

`./scripts/dev/verify-phase-7-static-manifests.sh` now includes that check, so
secret/config boundary regressions fail in the normal local static guardrail
path too.
