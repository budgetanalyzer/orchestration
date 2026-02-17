# Plan: Remove Docker Compose & Local SSL, Migrate to Tilt/Kubernetes

## Overview

Completely remove Docker Compose and local SSL infrastructure, consolidating all development workflow on Tilt/Kubernetes.

---

## Phase 1: Delete Deprecated Files

### Files to Delete
- `docker-compose.yml` - Main Docker Compose file
- `nginx/nginx.dev.conf` - Docker-specific NGINX config
- `nginx/certs/_wildcard.budgetanalyzer.localhost.pem` - Docker SSL cert
- `nginx/certs/_wildcard.budgetanalyzer.localhost-key.pem` - Docker SSL key
- `scripts/dev/setup-local-https.sh` - Docker SSL setup script
- `scripts/dev/reset-databases.sh` - Docker-based database reset

### Files to Keep
- `claude-code-sandbox/docker-compose.yml` - Separate concern (VS Code devcontainer)
- `nginx/nginx.k8s.conf` - Kubernetes NGINX config
- `nginx/certs/k8s/` - Kubernetes certificates
- `scripts/dev/setup-k8s-tls.sh` - Kubernetes SSL setup
- `postgres-init/` - Shared by K8s ConfigMap

---

## Phase 2: Add Tilt Database Management

### Add to Tiltfile
Create a `reset-databases` local_resource button that:
1. Deletes the PostgreSQL PVC (`postgresql-data-postgresql-0`)
2. Deletes the PostgreSQL pod to trigger recreation
3. Waits for pod to be ready
4. Automatically triggers `run-all-migrations`

This gives you a single button in the Tilt UI to reset all databases to a clean state with migrations applied.

---

## Phase 3: Update Documentation

### CLAUDE.md (extensive rewrite)
- Remove "Containerization: Docker and Docker Compose" from Architecture Principles
- Update Service Discovery section: remove `docker compose` commands
- Update Port Summary: remove ports 443/80 from NGINX (now Envoy Gateway)
- Update SSL setup section to reference `setup-k8s-tls.sh` only
- Update Quick Start to use `tilt up`
- Update Troubleshooting: replace docker commands with kubectl
- Update Architecture Flow to show Envoy Gateway (not NGINX) for SSL

### README.md
- Update prerequisites (add Kind, kubectl, helm, tilt; keep Docker)
- Change Quick Start from `docker compose up -d` to `tilt up`
- Update technology stack
- Update service access instructions

### docs/development/getting-started.md
- Complete rewrite for Tilt-based workflow
- Update SSL setup to reference `setup-k8s-tls.sh`
- Replace all Docker Compose commands with Tilt/kubectl

### docs/development/local-environment.md
- Major rewrite (35+ Docker Compose references)
- Document Tilt resources and buttons
- Document database reset via Tilt UI
- Update troubleshooting for K8s

### docs/development/database-setup.md
- Update for Kubernetes PostgreSQL
- Document Tilt database reset button
- Document `run-all-migrations` resource

### nginx/README.md
- Remove references to Docker Compose setup
- Focus on nginx.k8s.conf
- Update troubleshooting for kubectl

### docs/architecture/system-overview.md
- Update to reflect Tilt/Kind as the only dev environment

---

## Summary of Changes

| Category | Action |
|----------|--------|
| **Files deleted** | 6 files |
| **Tiltfile additions** | 1 local_resource (reset-databases) |
| **Docs updated** | 7 files |
| **Scripts remaining** | `setup-k8s-tls.sh`, `check-tilt-prerequisites.sh` |

### New Workflow

```bash
# First time setup
./scripts/dev/check-tilt-prerequisites.sh
./scripts/dev/setup-k8s-tls.sh   # Run on HOST (not in Claude sandbox)
tilt up

# Reset databases (in Tilt UI)
Click "reset-databases" button → automatically runs migrations

# Access app
https://app.budgetanalyzer.localhost
```
