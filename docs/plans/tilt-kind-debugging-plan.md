# Tilt/Kind PostgreSQL Connectivity Debugging Plan

## Problem Statement

Services in the Kind cluster fail to connect to PostgreSQL. There may be confusion between deployment strategies for different infrastructure components (RabbitMQ vs PostgreSQL/Redis).

## Prerequisites

User will shut down their Tilt environment before this debugging session begins.

---

## Phase 1: Environment Setup

### 1.1 Check Prerequisites Script

```bash
./scripts/dev/check-tilt-prerequisites.sh
```

This will identify what tools are missing from the container environment.

### 1.2 Install Required Tools

**kubectl:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

**kind:**
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
kind version
```

**tilt:**
```bash
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
tilt version
```

**helm (if needed):**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### 1.3 Verify Docker Access

```bash
docker ps
docker info
```

Ensure Docker daemon is accessible from the container.

---

## Phase 2: Kind Cluster Inspection

### 2.1 Check Kind Cluster Exists

```bash
kind get clusters
```

Expected output: `kind` or `budgetanalyzer` (whatever the cluster is named)

### 2.2 Set Kubectl Context

```bash
kubectl config get-contexts
kubectl config use-context kind-kind
# or
kubectl cluster-info --context kind-kind
```

### 2.3 Check Cluster Health

```bash
kubectl get nodes
kubectl get namespaces
```

Expected namespaces:
- `default` - where services deploy
- `infrastructure` - where PostgreSQL, Redis, RabbitMQ deploy
- `gateway-system` - where Gateway API controller deploys

### 2.4 List All Pods

```bash
kubectl get pods -A
```

Look for:
- Pod statuses (Running, Pending, CrashLoopBackOff, etc.)
- Restart counts
- Age

---

## Phase 3: Infrastructure Component Deep Dive

### 3.1 PostgreSQL Investigation

**Check all PostgreSQL resources:**
```bash
kubectl get all -n infrastructure -l app=postgresql
kubectl get pvc -n infrastructure -l app=postgresql
kubectl get configmap -n infrastructure -l app=postgresql
kubectl get secret -n infrastructure -l app=postgresql
```

**Describe the pod for events:**
```bash
kubectl describe pod -n infrastructure -l app=postgresql
```

Look for:
- Init container status
- Volume mount issues
- Scheduling problems
- Readiness probe failures

**Check PostgreSQL logs:**
```bash
# Main container logs
kubectl logs -n infrastructure -l app=postgresql --tail=200

# If there's an init container
kubectl logs -n infrastructure -l app=postgresql -c init-db
```

Look for:
- Database creation errors
- Permission issues
- Startup failures

**Verify Service endpoint:**
```bash
kubectl get endpoints postgresql -n infrastructure
kubectl describe service postgresql -n infrastructure
```

The endpoint should show the PostgreSQL pod IP.

### 3.2 RabbitMQ Investigation

```bash
kubectl get all -n infrastructure -l app=rabbitmq
kubectl describe pod -n infrastructure -l app=rabbitmq
kubectl logs -n infrastructure -l app=rabbitmq --tail=100
kubectl get endpoints rabbitmq -n infrastructure
```

### 3.3 Redis Investigation

```bash
kubectl get all -n infrastructure -l app=redis
kubectl describe pod -n infrastructure -l app=redis
kubectl logs -n infrastructure -l app=redis --tail=100
kubectl get endpoints redis -n infrastructure
```

### 3.4 Compare Deployment Patterns

Document for each component:
- Resource type (Deployment vs StatefulSet)
- Service name
- Service type (ClusterIP, etc.)
- Namespace
- Labels used

Check if there are any inconsistencies between the three.

---

## Phase 4: Tilt Analysis

### 4.1 Review Tiltfile Configuration

Before starting Tilt, review the Tiltfile for:
- How secrets are generated
- Resource dependencies
- Deploy order

Key areas to examine:
- Lines 105-167: Secret generation for PostgreSQL, Redis, RabbitMQ
- How `postgresql-credentials` secret is created
- The exact hostnames being used

### 4.2 Start Tilt in Foreground

```bash
tilt up --stream
```

Or in background with web UI:
```bash
tilt up
# Then access Tilt UI at http://localhost:10350
```

### 4.3 Monitor Resource Creation

Watch for:
- Order of resource creation
- Which resources succeed/fail
- Error messages for failed resources

```bash
# In another terminal
tilt get uiresources
tilt describe uiresource postgresql
tilt describe uiresource transaction-service
```

### 4.4 Check Generated Secrets

```bash
kubectl get secrets -n default
kubectl get secret postgresql-credentials -n default -o yaml
```

Decode and verify the URLs:
```bash
kubectl get secret postgresql-credentials -n default -o jsonpath='{.data.budget-analyzer-url}' | base64 -d
echo ""
kubectl get secret postgresql-credentials -n default -o jsonpath='{.data.currency-url}' | base64 -d
echo ""
kubectl get secret postgresql-credentials -n default -o jsonpath='{.data.permission-url}' | base64 -d
echo ""
```

Expected format:
```
jdbc:postgresql://postgresql.infrastructure:5432/budget_analyzer
jdbc:postgresql://postgresql.infrastructure:5432/currency
jdbc:postgresql://postgresql.infrastructure:5432/permission
```

---

## Phase 5: Network Connectivity Testing

### 5.1 Deploy Debug Pod

```bash
kubectl run debug-pod --rm -it --restart=Never --image=busybox:1.36 -- sh
```

From inside the debug pod:

### 5.2 Test DNS Resolution

```bash
# From inside debug pod
nslookup postgresql.infrastructure
nslookup postgresql.infrastructure.svc.cluster.local
nslookup redis.infrastructure
nslookup rabbitmq.infrastructure
```

Expected: Should resolve to pod IPs in the infrastructure namespace.

### 5.3 Test TCP Connectivity

```bash
# From inside debug pod
nc -zv postgresql.infrastructure 5432
nc -zv redis.infrastructure 6379
nc -zv rabbitmq.infrastructure 5672
```

### 5.4 Test PostgreSQL Authentication

Deploy a PostgreSQL client pod:
```bash
kubectl run pg-client --rm -it --restart=Never --image=postgres:16-alpine -- sh
```

From inside:
```bash
# Test connection with expected credentials
psql -h postgresql.infrastructure -U budget_analyzer -d budget_analyzer -c 'SELECT 1'
psql -h postgresql.infrastructure -U budget_analyzer -d currency -c 'SELECT 1'
psql -h postgresql.infrastructure -U budget_analyzer -d permission -c 'SELECT 1'
```

If prompted for password, use the password from the secret (check Tiltfile for default).

### 5.5 Test from Service Namespace Perspective

```bash
# Check if services can resolve from default namespace
kubectl run dns-test --rm -it --restart=Never --namespace=default --image=busybox:1.36 -- nslookup postgresql.infrastructure
```

---

## Phase 6: Service Deployment Analysis

### 6.1 Check Failing Service Logs

```bash
# Example for transaction-service
kubectl logs -n default -l app=transaction-service --tail=200

# Look for connection errors like:
# - "Connection refused"
# - "Unknown host"
# - "Authentication failed"
# - "Database does not exist"
```

### 6.2 Examine Service Environment Variables

```bash
kubectl get pod -n default -l app=transaction-service -o jsonpath='{.items[0].spec.containers[0].env}' | jq .
```

Or describe the pod:
```bash
kubectl describe pod -n default -l app=transaction-service
```

Look for:
- `SPRING_DATASOURCE_URL` - is it set correctly?
- `SPRING_DATASOURCE_USERNAME`
- `SPRING_DATASOURCE_PASSWORD`

### 6.3 Verify Secret References

Check the deployment manifest vs actual secret:
```bash
# What the deployment expects
grep -A5 "secretKeyRef" kubernetes/services/transaction-service/deployment.yaml

# What actually exists
kubectl get secret postgresql-credentials -n default -o jsonpath='{.data}' | jq -r 'keys[]'
```

Ensure the key names match.

---

## Phase 7: Common Issues Checklist

### 7.1 Namespace Issues

- [ ] PostgreSQL Service is in `infrastructure` namespace
- [ ] Services reference `postgresql.infrastructure` (cross-namespace DNS)
- [ ] Secrets are created in `default` namespace (where services run)

### 7.2 Service Name Issues

- [ ] Service name is `postgresql` (not `postgresql-primary` or `budgetanalyzer-postgresql`)
- [ ] No Bitnami Helm chart naming conventions in use
- [ ] Consistent naming across Tiltfile, manifests, and secrets

### 7.3 Database Initialization Issues

- [ ] All three databases created (budget_analyzer, currency, permission)
- [ ] User `budget_analyzer` has access to all databases
- [ ] PostgreSQL accepts connections from other pods

### 7.4 Secret Generation Issues

- [ ] Tiltfile `local_resource` for secrets ran successfully
- [ ] Secret exists in correct namespace
- [ ] Secret keys match what deployments expect

### 7.5 Network Policy Issues

- [ ] No NetworkPolicies blocking cross-namespace traffic
- [ ] Services have correct selectors matching pod labels

---

## Phase 8: Root Cause Documentation

After completing the investigation, document:

### 8.1 Actual Error Message

Copy the exact error from service logs.

### 8.2 Root Cause

Describe what's actually wrong:
- Configuration issue in manifests?
- Runtime issue with pod initialization?
- DNS resolution problem?
- Authentication/authorization issue?
- Missing resources?

### 8.3 Evidence

List the specific findings that confirm the root cause.

### 8.4 Fix Recommendation

Specific changes needed:
- File path and line numbers
- Exact changes required
- Any additional resources needed

---

## Expected Outcomes

After this debugging session, we should have:

1. **Clear understanding** of why PostgreSQL connections fail
2. **Verified configuration** - confirmed Tiltfile, manifests, and secrets are aligned
3. **Documented fix** - specific changes needed to resolve the issue
4. **Validation steps** - commands to verify the fix works

---

## Notes

- This plan assumes the Kind cluster already exists
- If cluster doesn't exist, will need to create it first with `kind create cluster`
- All debugging is non-destructive (read-only inspection)
- Fix implementation will be done separately after root cause is identified
