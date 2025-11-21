# Permission Service - Overview & Prerequisites

> **Status**: Planning
> **Created**: 2025-11-20
> **Parent Plan**: [authorization-implementation-plan.md](../authorization-implementation-plan.md)
> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

## Overview

Create a new Spring Boot microservice to manage authorization data: users, roles, permissions, delegations, and audit logs.

| Property | Value |
|----------|-------|
| **Name** | `permission-service` (singular, following project conventions) |
| **Port** | 8086 |
| **Database** | `permission` |
| **Context Path** | `/permission-service` |
| **Repository** | `https://github.com/budgetanalyzer/permission-service` |

---

## Soft Delete & Audit Trail Strategy

### Design Decisions

This service manages authorization data for a financial application. Data integrity and audit requirements are paramount. We use a tiered approach:

| Entity Type | Strategy | Rationale |
|-------------|----------|-----------|
| **User, Role, Permission** | Soft delete (extend `SoftDeletableEntity`) | Foreign key references everywhere (`granted_by`, `revoked_by`, audit logs). Hard delete = orphaned references. |
| **UserRole, RolePermission, ResourcePermission, Delegation** | Temporal fields (`granted_at`/`revoked_at`) | Enables point-in-time queries: "what roles did user X have on date Y?" Better than boolean soft delete for compliance reporting. |
| **AuthorizationAuditLog** | Immutable | Never modified, never deleted. |

### Why Temporal Over Boolean Soft Delete for Assignments

Assignment tables use `granted_at`/`revoked_at` timestamps instead of boolean `deleted` flags:

```sql
-- Point-in-time query: What roles did user have on March 15th?
SELECT r.name FROM user_roles ur
JOIN roles r ON ur.role_id = r.id
WHERE ur.user_id = ?
  AND ur.granted_at <= '2024-03-15'
  AND (ur.revoked_at IS NULL OR ur.revoked_at > '2024-03-15')
```

Benefits:
- Direct SQL for compliance reports (no log parsing)
- Instant incident investigation
- Full audit trail queryable by date range
- Survives log rotation/archival

### Re-granting Strategy

When a role is revoked and later re-granted to the same user, **create a new row** rather than clearing `revoked_at` on the existing row. This preserves complete history:

```
user_id | role_id | granted_at | revoked_at | granted_by | revoked_by
--------|---------|------------|------------|------------|------------
usr_123 | ADMIN   | 2024-01-01 | 2024-03-15 | usr_001    | usr_002
usr_123 | ADMIN   | 2024-06-01 | NULL       | usr_001    | NULL
```

### Cascading Rules

When soft-deleting entities, related assignments are automatically revoked:

| When This Is Soft-Deleted | Auto-Revoke These |
|---------------------------|-------------------|
| **User** | All `UserRole`, `ResourcePermission`, and `Delegation` entries for that user |
| **Role** | All `UserRole` and `RolePermission` entries for that role |
| **Permission** | All `RolePermission` entries for that permission |

Implementation: Use `@PreUpdate` listener on soft-deletable entities to trigger cascading revocation via service methods.

### Partial Unique Indexes

Soft-deletable entities require partial unique indexes to allow reuse of identifiers after deletion:

```sql
-- Allow same email to be reused after user is soft-deleted
CREATE UNIQUE INDEX users_email_active ON users (email) WHERE deleted = false;

-- Allow same role name to be reused after role is soft-deleted
CREATE UNIQUE INDEX roles_name_active ON roles (name) WHERE deleted = false;

-- Allow same permission ID to be reused after permission is soft-deleted
CREATE UNIQUE INDEX permissions_id_active ON permissions (id) WHERE deleted = false;
```

---

## Prerequisites: service-common Enhancement

### COMPLETED: `deletedBy` in SoftDeletableEntity

The `deletedBy` field was added in commit ea1976a.

**Implementation in `/workspace/service-common/service-core/src/main/java/org/budgetanalyzer/core/domain/SoftDeletableEntity.java`:**
- Added `deletedBy VARCHAR(50)` field
- Updated `markDeleted(String deletedBy)` method signature
- Added clearing of `deletedBy` on `restore()`

### COMPLETED: `createdBy`/`updatedBy` in AuditableEntity

The audit fields were added in commit 8183eb2.

**Implementation in `/workspace/service-common/service-core/src/main/java/org/budgetanalyzer/core/domain/AuditableEntity.java`:**
```java
@CreatedBy
@Column(name = "created_by", length = 50, updatable = false)
private String createdBy;

@LastModifiedBy
@Column(name = "updated_by", length = 50)
private String updatedBy;
```

These fields are auto-populated via Spring Data JPA auditing when an `AuditorAware` bean is configured.

**Migration for existing services** (transaction-service):
- Add `deleted_by VARCHAR(50)` column to transaction table
- Add `created_by VARCHAR(50)` and `updated_by VARCHAR(50)` columns to transaction table
- Existing records will have these audit fields as NULL (acceptable for historical data)
