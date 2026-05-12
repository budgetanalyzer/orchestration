# Plan: Transaction Preview Import Token Secret

Date: 2026-05-11
Status: Draft

Related documents:

- `docs/development/secrets-only-handling.md`
- `docs/development/local-environment.md`
- `docs/development/database-setup.md`
- `deploy/README.md`
- `deploy/manifests/phase-5/external-secrets.yaml`
- `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh`
- `docs/plans/oci-deployment-upgrade-lockstep-plan.md`
- `../transaction-service/README.md`

## Scope

The `transaction-service` branch `duplicate-file-upload-warning` adds a
required `PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET` setting for encrypted preview
import tokens. This plan adds that secret to the orchestration-owned local and
OCI deployment flows.

The service calls the value an encryption secret, not a signing secret. The
implementation uses AES-GCM and derives deterministic key material from the
configured UTF-8 secret with SHA-256. Rotating the secret invalidates outstanding
preview import tokens.

## Decision

Add a dedicated Kubernetes Secret:

```text
Secret/default/transaction-service-preview-import-token-credentials
  encryption-secret
```

Do not add this key to `transaction-service-postgresql-credentials`. That Secret
is intentionally scoped to the PostgreSQL password only, and the current
secrets-only inventory documents it that way.

For OCI, add a new OCI Vault secret:

```text
budget-analyzer-transaction-preview-import-token-encryption-secret
```

The production `ExternalSecret` should map that vault secret into
`transaction-service-preview-import-token-credentials[encryption-secret]`.

## Required Changes

### 1. Local Tilt Secret Producer

Update `Tiltfile` to create the new local secret:

```python
transaction_preview_import_token_encryption_secret = os.getenv(
    'PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET',
    'budget-analyzer-transaction-preview-import-token-encryption-secret',
)

create_secret('transaction-service-preview-import-token-credentials', DEFAULT_NAMESPACE, {
    'encryption-secret': transaction_preview_import_token_encryption_secret,
})
```

Add the new Secret to the `transaction-service` Tilt resource object list so
Tilt tracks it as part of that workload.

### 2. Transaction Service Deployment

Update `kubernetes/services/transaction-service/deployment.yaml`:

```yaml
- name: PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET
  valueFrom:
    secretKeyRef:
      name: transaction-service-preview-import-token-credentials
      key: encryption-secret
```

Leave `PREVIEW_IMPORT_TOKEN_TTL` out of the Secret path. It is non-sensitive and
already has a service default of `PT30M`. Only add a checked-in env value or
ConfigMap entry if the deployment intentionally chooses a non-default TTL.

### 3. Local Secret Inventory And Docs

Update the local secret/config boundary:

- `scripts/lib/secrets-only-expected-keys.txt`
- `docs/development/secrets-only-handling.md`
- `docs/development/local-environment.md`

The inventory entry should classify
`transaction-service-preview-import-token-credentials[encryption-secret]` as
`secret`.

Run:

```bash
./scripts/guardrails/check-secrets-only-handling.sh
./scripts/guardrails/verify-phase-7-static-manifests.sh
```

### 4. OCI Vault Bootstrap

Update `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh`:

- add `TRANSACTION_PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET`
- generate it with the same random secret helper used for PostgreSQL, RabbitMQ,
  and Redis
- persist it in the operator-only generated env file
- create the new OCI Vault secret named
  `budget-analyzer-transaction-preview-import-token-encryption-secret`
- keep existing vault secrets unchanged on rerun

Validate the script:

```bash
bash -n deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh
shellcheck deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh
```

### 5. OCI ExternalSecret Inventory

Update `deploy/manifests/phase-5/external-secrets.yaml` with a new
`ExternalSecret` in `default`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: transaction-service-preview-import-token-credentials
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: budget-analyzer-oci-vault
  target:
    name: transaction-service-preview-import-token-credentials
    creationPolicy: Owner
    deletionPolicy: Retain
    template:
      type: Opaque
  data:
    - secretKey: encryption-secret
      remoteRef:
        key: budget-analyzer-transaction-preview-import-token-encryption-secret
```

Render and review:

```bash
./deploy/scripts/09-render-phase-5-secrets.sh
sed -n '1,320p' tmp/phase-5/external-secrets.yaml
```

Apply through the existing production secret sync path:

```bash
./deploy/scripts/10-apply-phase-5-secrets.sh
kubectl get externalsecret -n default transaction-service-preview-import-token-credentials
kubectl get secret -n default transaction-service-preview-import-token-credentials
```

### 6. Documentation

Update:

- `deploy/README.md` script descriptions and the phase 5 checkpoint
- `kubernetes/production/README.md` if the production verifier or secret
  baseline summary names the exact secret set
- `docs/plans/oci-deployment-upgrade-lockstep-plan.md`

The docs should state that this is a generated application secret in OCI Vault,
not a value for `deploy/instance.env.template`.

### 7. Verification

Before deploying a transaction-service image that requires this property:

```bash
kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
./scripts/guardrails/check-secrets-only-handling.sh
./scripts/guardrails/verify-production-image-overlay.sh
./deploy/scripts/09-render-phase-5-secrets.sh
```

After applying production secrets and apps:

```bash
kubectl get externalsecret -n default transaction-service-preview-import-token-credentials
kubectl rollout status deployment/transaction-service --timeout=300s
```

## Ordering Constraint

Apply the new secret path before deploying the new `transaction-service` image.
The service validates the property at startup, so a release image containing
this branch will fail to start if `PREVIEW_IMPORT_TOKEN_ENCRYPTION_SECRET` is not
injected.
