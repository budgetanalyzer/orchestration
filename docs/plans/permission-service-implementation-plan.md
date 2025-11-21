# Permission Service - Implementation Plan

> **Status**: Planning
> **Created**: 2025-11-20
> **Parent Plan**: [authorization-implementation-plan.md](./authorization-implementation-plan.md)

## Overview

This is the implementation plan for the Permission Service - a Spring Boot microservice to manage authorization data including users, roles, permissions, delegations, and audit logs.

| Property | Value |
|----------|-------|
| **Name** | `permission-service` |
| **Port** | 8086 |
| **Database** | `permission` |
| **Context Path** | `/permission-service` |
| **Repository** | `https://github.com/budgetanalyzer/permission-service` |

---

## Historical Archive

The complete original implementation plan is preserved as a historical record:

**[permission-service-implementation-plan-ARCHIVE.md](./permission-service-implementation-plan-ARCHIVE.md)** (~3,338 lines)

---

## Phase Documents

The plan has been split into manageable sections for easier navigation:

| Phase | Document | Lines | Description |
|-------|----------|-------|-------------|
| Overview | [00-overview-prerequisites.md](./permission-service-phases/00-overview-prerequisites.md) | ~125 | Service overview, soft delete strategy, prerequisites |
| **1-2** | [01-setup-migrations.md](./permission-service-phases/01-setup-migrations.md) | ~485 | Repository setup, Gradle config, Flyway migrations |
| **3** | [02-domain-layer.md](./permission-service-phases/02-domain-layer.md) | ~594 | Entity classes, DTOs, package structure |
| **4** | [03-repository-layer.md](./permission-service-phases/03-repository-layer.md) | ~141 | JPA repositories with temporal queries |
| **5** | [04-service-layer.md](./permission-service-phases/04-service-layer.md) | ~773 | Core services, exceptions, caching |
| **6** | [05-api-layer.md](./permission-service-phases/05-api-layer.md) | ~676 | Controllers with OpenAPI documentation |
| **7** | [06-configuration.md](./permission-service-phases/06-configuration.md) | ~118 | application.yml, OpenAPI config |
| **8** | [07-infrastructure-integration.md](./permission-service-phases/07-infrastructure-integration.md) | ~105 | Docker Compose, NGINX routes |
| **9+** | [08-testing-completion.md](./permission-service-phases/08-testing-completion.md) | ~321 | Testing patterns, success criteria |

---

## Quick Reference

### Implementation Order

| Step | Task | Est. Time |
|------|------|-----------|
| 0 | Enhance service-common (deletedBy field) | 30 min |
| 1 | Repository & Gradle setup | 30 min |
| 2 | Flyway migrations | 45 min |
| 3 | Domain entities | 1.5 hours |
| 4 | Repositories | 45 min |
| 5 | Core services | 2.5 hours |
| 6 | Controllers | 1.5 hours |
| 7 | Configuration | 30 min |
| 8 | Infrastructure | 30 min |
| 9 | Tests | 2.5 hours |

**Total: ~11.5 hours**

### Key Features

- **RBAC with Governance**: 6 default roles with tiered assignment permissions
- **Temporal Audit Trail**: Point-in-time queries for compliance
- **Soft Delete with Cascading**: Auto-revocation when entities are deleted
- **Redis Caching**: Permission caching with pub/sub invalidation
- **Delegations**: User-to-user access sharing

### Files to Create

- **~45 Source Files**: Entities, repositories, services, controllers, DTOs
- **~10 Test Files**: Unit and integration tests
- **2 Migrations**: Schema and seed data
- **2 Config Files**: application.yml (main + test)

---

## Navigation

- **Start here**: [00-overview-prerequisites.md](./permission-service-phases/00-overview-prerequisites.md)
- **Database schema**: [01-setup-migrations.md](./permission-service-phases/01-setup-migrations.md)
- **Success criteria**: [08-testing-completion.md](./permission-service-phases/08-testing-completion.md)
