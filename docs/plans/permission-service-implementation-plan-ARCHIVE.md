# Permission Service - Detailed Implementation Plan

> **Status**: Planning
> **Created**: 2025-11-20
> **Parent Plan**: [authorization-implementation-plan.md](./authorization-implementation-plan.md)

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

### ✅ COMPLETED: `deletedBy` in SoftDeletableEntity

The `deletedBy` field was added in commit ea1976a.

**Implementation in `/workspace/service-common/service-core/src/main/java/org/budgetanalyzer/core/domain/SoftDeletableEntity.java`:**
- Added `deletedBy VARCHAR(50)` field
- Updated `markDeleted(String deletedBy)` method signature
- Added clearing of `deletedBy` on `restore()`

### ✅ COMPLETED: `createdBy`/`updatedBy` in AuditableEntity

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

---

## Phase 1: Repository Setup

### 1.1 Create GitHub Repository

- Create `https://github.com/budgetanalyzer/permission-service`
- Clone to `/workspace/permission-service`

### 1.2 Initialize Project Structure

Copy structure from `transaction-service` and adapt:

```
permission-service/
├── build.gradle.kts
├── settings.gradle.kts
├── gradle/
│   └── libs.versions.toml
├── src/
│   ├── main/
│   │   ├── java/org/budgetanalyzer/permission/
│   │   │   ├── PermissionServiceApplication.java
│   │   │   ├── api/
│   │   │   ├── config/
│   │   │   ├── domain/
│   │   │   ├── repository/
│   │   │   └── service/
│   │   └── resources/
│   │       ├── application.yml
│   │       ├── application-test.yml
│   │       └── db/migration/
│   └── test/
├── Dockerfile
└── README.md
```

### 1.3 Configure Gradle Build

**`build.gradle.kts`**:
```kotlin
plugins {
    java
    checkstyle
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.spring.dependency.management)
    alias(libs.plugins.spotless)
}

group = "org.budgetanalyzer"
version = "0.0.1-SNAPSHOT"

dependencies {
    implementation(libs.service.web)
    implementation(libs.spring.boot.starter.web)
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.spring.boot.starter.oauth2.resource.server)
    implementation(libs.spring.boot.starter.data.redis)  // For caching
    implementation(libs.flyway.core)
    implementation(libs.flyway.database.postgresql)
    runtimeOnly(libs.postgresql)

    testImplementation(libs.spring.boot.starter.test)
    testImplementation(libs.h2)
}
```

**`settings.gradle.kts`**:
```kotlin
rootProject.name = "permission-service"
```

---

## Phase 2: Flyway Database Migrations

**Migration Structure:**
```
db/migration/
├── V1__initial_schema.sql      # All tables + indexes
└── V2__seed_default_data.sql   # Default roles and permissions
```

### 2.1 V1__initial_schema.sql

```sql
-- =============================================================================
-- Users table (authorization subjects, linked to Auth0)
-- =============================================================================
CREATE TABLE users (
    id VARCHAR(50) PRIMARY KEY,
    auth0_sub VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    created_by VARCHAR(50),
    updated_by VARCHAR(50),
    -- Soft delete fields
    deleted BOOLEAN NOT NULL DEFAULT false,
    deleted_at TIMESTAMP(6) WITH TIME ZONE,
    deleted_by VARCHAR(50)
);

CREATE INDEX idx_users_auth0_sub ON users(auth0_sub) WHERE deleted = false;
CREATE INDEX idx_users_email ON users(email) WHERE deleted = false;
-- Partial unique indexes to allow reuse after soft delete
CREATE UNIQUE INDEX users_auth0_sub_active ON users(auth0_sub) WHERE deleted = false;
CREATE UNIQUE INDEX users_email_active ON users(email) WHERE deleted = false;

COMMENT ON TABLE users IS 'Local user records linked to Auth0 for authorization';
COMMENT ON COLUMN users.id IS 'Internal user ID (e.g., usr_xxx)';
COMMENT ON COLUMN users.auth0_sub IS 'Auth0 subject identifier';
COMMENT ON COLUMN users.deleted IS 'Soft delete flag';

-- =============================================================================
-- Role definitions with hierarchy support
-- =============================================================================
CREATE TABLE roles (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    parent_role_id VARCHAR(50) REFERENCES roles(id),
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    created_by VARCHAR(50),
    updated_by VARCHAR(50),
    -- Soft delete fields
    deleted BOOLEAN NOT NULL DEFAULT false,
    deleted_at TIMESTAMP(6) WITH TIME ZONE,
    deleted_by VARCHAR(50)
);

-- Partial unique index to allow role name reuse after soft delete
CREATE UNIQUE INDEX roles_name_active ON roles(name) WHERE deleted = false;
CREATE INDEX idx_roles_parent ON roles(parent_role_id) WHERE deleted = false;

COMMENT ON TABLE roles IS 'Role definitions for RBAC';
COMMENT ON COLUMN roles.parent_role_id IS 'Parent role for hierarchy (inherits permissions)';
COMMENT ON COLUMN roles.deleted IS 'Soft delete flag';

-- =============================================================================
-- Atomic permission definitions
-- =============================================================================
CREATE TABLE permissions (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    resource_type VARCHAR(50),
    action VARCHAR(50),
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    created_by VARCHAR(50),
    updated_by VARCHAR(50),
    -- Soft delete fields
    deleted BOOLEAN NOT NULL DEFAULT false,
    deleted_at TIMESTAMP(6) WITH TIME ZONE,
    deleted_by VARCHAR(50)
);

CREATE INDEX idx_permissions_resource_type ON permissions(resource_type) WHERE deleted = false;

COMMENT ON TABLE permissions IS 'Atomic permission definitions';
COMMENT ON COLUMN permissions.id IS 'Permission ID in format resource:action (e.g., transactions:write)';
COMMENT ON COLUMN permissions.deleted IS 'Soft delete flag';

-- =============================================================================
-- Role to permission mappings (temporal - supports point-in-time queries)
-- =============================================================================
CREATE TABLE role_permissions (
    id BIGSERIAL PRIMARY KEY,
    role_id VARCHAR(50) NOT NULL REFERENCES roles(id),
    permission_id VARCHAR(100) NOT NULL REFERENCES permissions(id),
    -- Audit fields (from AuditableEntity)
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    created_by VARCHAR(50),
    updated_by VARCHAR(50),
    -- Temporal fields for business audit trail
    granted_at TIMESTAMP(6) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    granted_by VARCHAR(50) REFERENCES users(id),
    revoked_at TIMESTAMP(6) WITH TIME ZONE,
    revoked_by VARCHAR(50) REFERENCES users(id)
);

-- Index for active permissions lookup
CREATE INDEX idx_role_permissions_role_active ON role_permissions(role_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_role_permissions_permission ON role_permissions(permission_id);
-- Unique constraint: only one active assignment per role-permission pair
CREATE UNIQUE INDEX role_permissions_active ON role_permissions(role_id, permission_id) WHERE revoked_at IS NULL;

COMMENT ON TABLE role_permissions IS 'Role to permission mappings with temporal audit trail';
COMMENT ON COLUMN role_permissions.revoked_at IS 'NULL means currently active';

-- =============================================================================
-- User role assignments (temporal - supports point-in-time queries)
-- =============================================================================
CREATE TABLE user_roles (
    id BIGSERIAL PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL REFERENCES users(id),
    role_id VARCHAR(50) NOT NULL REFERENCES roles(id),
    organization_id VARCHAR(50),
    -- Audit fields (from AuditableEntity)
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    created_by VARCHAR(50),
    updated_by VARCHAR(50),
    -- Temporal fields for business audit trail
    granted_at TIMESTAMP(6) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    granted_by VARCHAR(50) REFERENCES users(id),
    expires_at TIMESTAMP(6) WITH TIME ZONE,
    revoked_at TIMESTAMP(6) WITH TIME ZONE,
    revoked_by VARCHAR(50) REFERENCES users(id)
);

-- Index for active role lookup
CREATE INDEX idx_user_roles_user_active ON user_roles(user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_user_roles_role ON user_roles(role_id);
CREATE INDEX idx_user_roles_org ON user_roles(organization_id) WHERE organization_id IS NOT NULL;
-- Unique constraint: only one active assignment per user-role-org combination
CREATE UNIQUE INDEX user_roles_active ON user_roles(user_id, role_id, COALESCE(organization_id, '')) WHERE revoked_at IS NULL;

COMMENT ON TABLE user_roles IS 'User to role assignments with temporal audit trail';
COMMENT ON COLUMN user_roles.organization_id IS 'Optional org scope for multi-tenancy';
COMMENT ON COLUMN user_roles.expires_at IS 'Optional expiration for temporary role assignments';
COMMENT ON COLUMN user_roles.revoked_at IS 'NULL means currently active';

-- =============================================================================
-- Instance-level permissions (user X can access resource Y) - temporal
-- =============================================================================
CREATE TABLE resource_permissions (
    id BIGSERIAL PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL REFERENCES users(id),
    resource_type VARCHAR(50) NOT NULL,
    resource_id VARCHAR(100) NOT NULL,
    permission VARCHAR(50) NOT NULL,
    -- Audit fields (from AuditableEntity)
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    created_by VARCHAR(50),
    updated_by VARCHAR(50),
    -- Temporal fields for business audit trail
    granted_at TIMESTAMP(6) WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    granted_by VARCHAR(50) REFERENCES users(id),
    expires_at TIMESTAMP(6) WITH TIME ZONE,
    revoked_at TIMESTAMP(6) WITH TIME ZONE,
    revoked_by VARCHAR(50) REFERENCES users(id),
    reason TEXT
);

-- Index for active permissions lookup
CREATE INDEX idx_resource_permissions_user_active ON resource_permissions(user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_resource_permissions_resource ON resource_permissions(resource_type, resource_id);
-- Unique constraint: only one active permission per user-resource-permission combination
CREATE UNIQUE INDEX resource_permissions_active ON resource_permissions(user_id, resource_type, resource_id, permission) WHERE revoked_at IS NULL;

COMMENT ON TABLE resource_permissions IS 'Fine-grained permissions for specific resource instances with temporal audit trail';
COMMENT ON COLUMN resource_permissions.resource_type IS 'Type of resource (e.g., account, transaction)';
COMMENT ON COLUMN resource_permissions.resource_id IS 'ID of the specific resource instance';
COMMENT ON COLUMN resource_permissions.revoked_at IS 'NULL means currently active';

-- =============================================================================
-- User-to-user delegation
-- =============================================================================
CREATE TABLE delegations (
    id BIGSERIAL PRIMARY KEY,
    delegator_id VARCHAR(50) REFERENCES users(id) ON DELETE CASCADE,
    delegatee_id VARCHAR(50) REFERENCES users(id) ON DELETE CASCADE,
    scope VARCHAR(50) NOT NULL,
    resource_type VARCHAR(50),
    resource_ids TEXT[],
    -- Audit fields (from AuditableEntity)
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE,
    created_by VARCHAR(50),
    updated_by VARCHAR(50),
    -- Temporal fields for business audit trail
    valid_from TIMESTAMP(6) WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMP(6) WITH TIME ZONE,
    revoked_at TIMESTAMP(6) WITH TIME ZONE,
    revoked_by VARCHAR(50) REFERENCES users(id),
    reason TEXT
);

CREATE INDEX idx_delegations_delegator ON delegations(delegator_id);
CREATE INDEX idx_delegations_delegatee ON delegations(delegatee_id);
CREATE INDEX idx_delegations_active ON delegations(delegatee_id)
    WHERE revoked_at IS NULL AND (valid_until IS NULL OR valid_until > CURRENT_TIMESTAMP);

COMMENT ON TABLE delegations IS 'User-to-user permission delegations';
COMMENT ON COLUMN delegations.scope IS 'Delegation scope: full, read_only, transactions_only';
COMMENT ON COLUMN delegations.resource_ids IS 'Specific resource IDs if not delegating all';

-- =============================================================================
-- Immutable authorization audit log
-- =============================================================================
CREATE TABLE authorization_audit_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP(6) WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    user_id VARCHAR(50),
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    decision VARCHAR(20) NOT NULL,
    reason TEXT,
    request_ip VARCHAR(45),
    user_agent TEXT,
    additional_context JSONB
);

CREATE INDEX idx_audit_log_user ON authorization_audit_log(user_id);
CREATE INDEX idx_audit_log_timestamp ON authorization_audit_log(timestamp);
CREATE INDEX idx_audit_log_action ON authorization_audit_log(action);
CREATE INDEX idx_audit_log_decision ON authorization_audit_log(decision);

COMMENT ON TABLE authorization_audit_log IS 'Immutable audit trail for authorization events';
COMMENT ON COLUMN authorization_audit_log.decision IS 'GRANTED or DENIED';
COMMENT ON COLUMN authorization_audit_log.additional_context IS 'Extra context as JSON';
```

### 2.2 V2__seed_default_data.sql

```sql
-- =============================================================================
-- SYSTEM user for audit trail on seeded data
-- =============================================================================
INSERT INTO users (id, auth0_sub, email, display_name, created_at, created_by)
VALUES ('SYSTEM', 'system|internal', 'system@budgetanalyzer.local', 'System', CURRENT_TIMESTAMP, 'SYSTEM');

-- =============================================================================
-- Default roles (hierarchical structure for proper governance)
-- =============================================================================
--
-- Role Hierarchy:
--   SYSTEM_ADMIN - Platform owner, manages permission system (database-only assignment)
--   ORG_ADMIN    - Organization administrator, manages users and basic roles
--   MANAGER      - Team oversight, approvals, read access to team data
--   ACCOUNTANT   - Professional access to delegated accounts
--   AUDITOR      - Read-only compliance access
--   USER         - Self-service access to own resources
--
INSERT INTO roles (id, name, description, created_at, created_by) VALUES
    ('SYSTEM_ADMIN', 'System Administrator', 'Platform administration - manages roles, permissions, and can assign admin roles. Cannot be assigned via API.', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'Organization Administrator', 'Organization administration - manages users and can assign basic roles within organization', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('MANAGER', 'Manager', 'Team oversight - can view team data and approve operations', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ACCOUNTANT', 'Accountant', 'Professional access - can manage delegated user accounts', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('AUDITOR', 'Auditor', 'Compliance access - read-only with full visibility', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'User', 'Self-service - access to own resources only', CURRENT_TIMESTAMP, 'SYSTEM');

-- =============================================================================
-- Default permissions
-- =============================================================================
INSERT INTO permissions (id, name, resource_type, action, created_at, created_by) VALUES
    -- User management
    ('users:read', 'Read Users', 'user', 'read', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('users:write', 'Write Users', 'user', 'write', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('users:delete', 'Delete Users', 'user', 'delete', CURRENT_TIMESTAMP, 'SYSTEM'),

    -- Transaction management
    ('transactions:read', 'Read Transactions', 'transaction', 'read', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('transactions:write', 'Write Transactions', 'transaction', 'write', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('transactions:delete', 'Delete Transactions', 'transaction', 'delete', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('transactions:approve', 'Approve Transactions', 'transaction', 'approve', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('transactions:bulk', 'Bulk Transaction Operations', 'transaction', 'bulk', CURRENT_TIMESTAMP, 'SYSTEM'),

    -- Account management
    ('accounts:read', 'Read Accounts', 'account', 'read', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('accounts:write', 'Write Accounts', 'account', 'write', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('accounts:delete', 'Delete Accounts', 'account', 'delete', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('accounts:delegate', 'Delegate Accounts', 'account', 'delegate', CURRENT_TIMESTAMP, 'SYSTEM'),

    -- Budget management
    ('budgets:read', 'Read Budgets', 'budget', 'read', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('budgets:write', 'Write Budgets', 'budget', 'write', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('budgets:delete', 'Delete Budgets', 'budget', 'delete', CURRENT_TIMESTAMP, 'SYSTEM'),

    -- Audit and reporting
    ('audit:read', 'Read Audit Logs', 'audit', 'read', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('reports:export', 'Export Reports', 'report', 'export', CURRENT_TIMESTAMP, 'SYSTEM'),

    -- =============================================================================
    -- Meta-permissions (govern the authorization system itself)
    -- =============================================================================
    ('roles:read', 'View Roles', 'role', 'read', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('roles:write', 'Create/Modify Roles', 'role', 'write', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('roles:delete', 'Delete Roles', 'role', 'delete', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('permissions:read', 'View Permissions', 'permission', 'read', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('permissions:write', 'Create/Modify Permissions', 'permission', 'write', CURRENT_TIMESTAMP, 'SYSTEM'),

    -- Role assignment permissions (critical for governance)
    -- assign-basic: Can assign USER, ACCOUNTANT, AUDITOR
    -- assign-elevated: Can assign MANAGER, ORG_ADMIN (requires higher privilege)
    ('user-roles:assign-basic', 'Assign Basic Roles', 'user-role', 'assign-basic', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('user-roles:assign-elevated', 'Assign Elevated Roles', 'user-role', 'assign-elevated', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('user-roles:revoke', 'Revoke User Roles', 'user-role', 'revoke', CURRENT_TIMESTAMP, 'SYSTEM');

-- =============================================================================
-- Default role-permission mappings
-- =============================================================================

-- SYSTEM_ADMIN gets ALL permissions (including meta-permissions)
-- This role can only be assigned directly in the database, not via API
INSERT INTO role_permissions (role_id, permission_id, created_at, created_by, granted_at, granted_by)
SELECT 'SYSTEM_ADMIN', id, CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM' FROM permissions;

-- ORG_ADMIN: Business oversight + basic role assignment
-- Cannot modify roles/permissions or assign elevated roles
INSERT INTO role_permissions (role_id, permission_id, created_at, created_by, granted_at, granted_by) VALUES
    -- User management
    ('ORG_ADMIN', 'users:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'users:write', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'users:delete', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    -- Business data (read-only for oversight)
    ('ORG_ADMIN', 'transactions:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'accounts:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'budgets:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'audit:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'reports:export', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    -- Role management (limited)
    ('ORG_ADMIN', 'roles:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'user-roles:assign-basic', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ORG_ADMIN', 'user-roles:revoke', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM');

-- MANAGER: Team oversight and approvals (no role management)
INSERT INTO role_permissions (role_id, permission_id, created_at, created_by, granted_at, granted_by) VALUES
    ('MANAGER', 'users:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('MANAGER', 'transactions:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('MANAGER', 'transactions:approve', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('MANAGER', 'accounts:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('MANAGER', 'budgets:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('MANAGER', 'reports:export', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM');

-- ACCOUNTANT: Professional access to delegated accounts
INSERT INTO role_permissions (role_id, permission_id, created_at, created_by, granted_at, granted_by) VALUES
    ('ACCOUNTANT', 'transactions:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ACCOUNTANT', 'transactions:write', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ACCOUNTANT', 'transactions:approve', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ACCOUNTANT', 'accounts:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('ACCOUNTANT', 'reports:export', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM');

-- AUDITOR: Read-only compliance access
INSERT INTO role_permissions (role_id, permission_id, created_at, created_by, granted_at, granted_by) VALUES
    ('AUDITOR', 'users:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('AUDITOR', 'transactions:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('AUDITOR', 'accounts:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('AUDITOR', 'budgets:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('AUDITOR', 'audit:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('AUDITOR', 'reports:export', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM');

-- USER: Self-service access to own resources
INSERT INTO role_permissions (role_id, permission_id, created_at, created_by, granted_at, granted_by) VALUES
    ('USER', 'transactions:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'transactions:write', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'transactions:delete', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'accounts:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'accounts:write', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'accounts:delegate', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'budgets:read', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM'),
    ('USER', 'budgets:write', CURRENT_TIMESTAMP, 'SYSTEM', CURRENT_TIMESTAMP, 'SYSTEM');
```

### 2.3 Role Assignment Policy

**Critical Governance Rules:**

| Action | Required Permission | Who Has It |
|--------|---------------------|------------|
| Assign USER, ACCOUNTANT, AUDITOR | `user-roles:assign-basic` | SYSTEM_ADMIN, ORG_ADMIN |
| Assign MANAGER, ORG_ADMIN | `user-roles:assign-elevated` | SYSTEM_ADMIN only |
| Assign SYSTEM_ADMIN | N/A - Database only | DBA/DevOps only |
| Revoke any role | `user-roles:revoke` | SYSTEM_ADMIN, ORG_ADMIN |
| Create/modify roles | `roles:write` | SYSTEM_ADMIN only |
| Create/modify permissions | `permissions:write` | SYSTEM_ADMIN only |

**Bootstrap Process:**
1. First SYSTEM_ADMIN is created via database seed or migration
2. SYSTEM_ADMIN can then assign ORG_ADMIN to organization administrators
3. ORG_ADMIN can assign basic roles to users within their organization

**Protection in Code:**
- `SYSTEM_ADMIN` role cannot be assigned via any API endpoint
- Role assignment checks both the granter's permissions AND the target role level
- All role changes are logged to authorization_audit_log

---

## Phase 3: Domain Layer

### 3.1 Entity Classes

Create JPA entities in `domain/`:

| Entity | Table | Base Class | Notes |
|--------|-------|------------|-------|
| `User.java` | users | `SoftDeletableEntity` | Soft-deletable, linked to Auth0 |
| `Role.java` | roles | `SoftDeletableEntity` | Soft-deletable, self-referencing for hierarchy |
| `Permission.java` | permissions | `SoftDeletableEntity` | Soft-deletable |
| `UserRole.java` | user_roles | `AuditableEntity` | Temporal with `grantedAt`/`revokedAt` |
| `RolePermission.java` | role_permissions | `AuditableEntity` | Temporal with `grantedAt`/`revokedAt` |
| `ResourcePermission.java` | resource_permissions | `AuditableEntity` | Temporal with `grantedAt`/`revokedAt` |
| `Delegation.java` | delegations | `AuditableEntity` | Temporal with `validFrom`/`revokedAt` |
| `AuthorizationAuditLog.java` | authorization_audit_log | None | Immutable, no base class |

**Note on Temporal Entities**:

Temporal entities (UserRole, RolePermission, ResourcePermission, Delegation) do **not** extend `SoftDeletableEntity`. Instead:

- They extend `AuditableEntity` to get `createdAt`/`updatedAt` tracking
- They use explicit `grantedAt`/`revokedAt` fields for point-in-time queries
- They are never deleted; revocation is tracked via `revokedAt` timestamp

Example temporal entity structure:

```java
@Entity
@Table(name = "user_roles")
public class UserRole extends AuditableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "role_id", nullable = false)
    private String roleId;

    @Column(name = "organization_id")
    private String organizationId;

    // Temporal fields for audit trail
    @Column(name = "granted_at", nullable = false)
    private Instant grantedAt;

    @Column(name = "granted_by")
    private String grantedBy;

    @Column(name = "expires_at")
    private Instant expiresAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    @Column(name = "revoked_by")
    private String revokedBy;

    // Getters and setters...
}
```

`AuthorizationAuditLog` is special - it's immutable and doesn't extend any base class since it's never updated or deleted.

### 3.2 DTOs

Create DTOs following strict layer separation:

#### API DTOs (`api/request/` and `api/response/`)

**Responses** - Returned by controllers to API clients:
- `UserPermissionsResponse.java` - For `/me/permissions` endpoint (transforms from `EffectivePermissions`)
- `RoleResponse.java` - Role data for API (transforms from `Role` entity)
- `DelegationResponse.java` - Single delegation (transforms from `Delegation` entity)
- `DelegationsResponse.java` - Combined given/received delegations (transforms from `DelegationsSummary`)
- `AuditLogResponse.java` - Audit log entry (transforms from `AuthorizationAuditLog` entity)
- `ResourcePermissionResponse.java` - Resource permission (transforms from `ResourcePermission` entity)

**Requests** - Received by controllers from API clients:
- `RoleRequest.java`
- `UserRoleAssignmentRequest.java`
- `ResourcePermissionRequest.java`
- `DelegationRequest.java`

#### Request DTO Definitions

All request DTOs must have:
1. `@Schema` annotations on every field with `description`, `example`, and `requiredMode`
2. Bean Validation annotations (`@NotBlank`, `@Size`, etc.) that coordinate with `@Schema`

```java
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RoleRequest(
    @Schema(description = "Role name", example = "Project Manager", maxLength = 100,
            requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "Role name is required")
    @Size(max = 100, message = "Role name must be at most 100 characters")
    String name,

    @Schema(description = "Role description", example = "Manages project resources and timelines",
            maxLength = 500, requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    @Size(max = 500, message = "Description must be at most 500 characters")
    String description,

    @Schema(description = "Parent role ID for hierarchy inheritance", example = "MANAGER",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String parentRoleId
) {}

public record UserRoleAssignmentRequest(
    @Schema(description = "Role ID to assign", example = "ACCOUNTANT",
            requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "Role ID is required")
    String roleId,

    @Schema(description = "Organization scope for multi-tenancy", example = "org_123",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String organizationId,

    @Schema(description = "Optional expiration for temporary assignments",
            example = "2024-12-31T23:59:59Z",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    Instant expiresAt
) {}

public record ResourcePermissionRequest(
    @Schema(description = "User ID to grant permission to", example = "usr_abc123",
            requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "User ID is required")
    String userId,

    @Schema(description = "Type of resource", example = "account",
            requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "Resource type is required")
    String resourceType,

    @Schema(description = "Specific resource ID", example = "acc_789",
            requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "Resource ID is required")
    String resourceId,

    @Schema(description = "Permission to grant", example = "read",
            requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "Permission is required")
    String permission,

    @Schema(description = "When permission expires", example = "2024-12-31T23:59:59Z",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    Instant expiresAt,

    @Schema(description = "Reason for granting permission", example = "Audit review access",
            maxLength = 500, requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    @Size(max = 500, message = "Reason must be at most 500 characters")
    String reason
) {}

public record DelegationRequest(
    @Schema(description = "User ID to delegate to", example = "usr_def456",
            requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "Delegatee ID is required")
    String delegateeId,

    @Schema(description = "Delegation scope: full, read_only, transactions_only",
            example = "read_only", requiredMode = Schema.RequiredMode.REQUIRED)
    @NotBlank(message = "Scope is required")
    String scope,

    @Schema(description = "Type of resource being delegated", example = "account",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String resourceType,

    @Schema(description = "Specific resource IDs (null = all resources of type)",
            example = "[\"acc_123\", \"acc_456\"]",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String[] resourceIds,

    @Schema(description = "When delegation expires", example = "2024-12-31T23:59:59Z",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    Instant validUntil
) {}
```

#### Service-Layer DTOs (`service/dto/`)

These DTOs are used internally by services to return complex data structures that don't map directly to a single entity. Controllers transform these into API response DTOs.

**Note**: Service-layer DTOs also use `@Schema` annotations for documentation, but these are internal DTOs not exposed directly via API.

```java
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * Contains a user's effective permissions from all sources.
 * Used by PermissionService, transformed to UserPermissionsResponse by controller.
 */
@Schema(description = "Internal DTO containing all effective permissions for a user")
public record EffectivePermissions(
    @Schema(description = "Permission IDs from assigned roles")
    Set<String> rolePermissions,

    @Schema(description = "Resource-specific permissions")
    List<ResourcePermission> resourcePermissions,

    @Schema(description = "Active delegations")
    List<Delegation> delegations
) {
    /**
     * Combines all permission sources into a single set of permission IDs.
     *
     * @return set of all effective permission IDs
     */
    public Set<String> getAllPermissionIds() {
        var all = new HashSet<>(rolePermissions);
        resourcePermissions.forEach(rp -> all.add(rp.getPermission()));
        return all;
    }
}

/**
 * Contains both delegations given by and received by a user.
 * Used by DelegationService, transformed to DelegationsResponse by controller.
 */
@Schema(description = "Internal DTO containing delegations summary for a user")
public record DelegationsSummary(
    @Schema(description = "Delegations created by this user")
    List<Delegation> given,

    @Schema(description = "Delegations received by this user")
    List<Delegation> received
) {}

/**
 * Filter criteria for querying audit logs.
 * Built by controller from query parameters, used by AuditService.
 */
@Schema(description = "Internal DTO for audit log query filters")
public record AuditQueryFilter(
    @Schema(description = "Filter by user ID", example = "usr_abc123")
    String userId,

    @Schema(description = "Start of time range", example = "2024-01-01T00:00:00Z")
    Instant startTime,

    @Schema(description = "End of time range", example = "2024-12-31T23:59:59Z")
    Instant endTime
) {}
```

#### Response DTO Transformation Pattern

All response DTOs must have:
1. `@Schema` annotations on every field with `description`, `example`, and `requiredMode` (for optional fields)
2. A static `from()` factory method for transforming entities/service DTOs

```java
import io.swagger.v3.oas.annotations.media.Schema;

public record RoleResponse(
    @Schema(description = "Role identifier", example = "MANAGER")
    String id,

    @Schema(description = "Human-readable role name", example = "Manager")
    String name,

    @Schema(description = "Role description", example = "Team oversight and approvals")
    String description,

    @Schema(description = "Parent role ID for hierarchy", example = "ORG_ADMIN",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String parentRoleId,

    @Schema(description = "When the role was created", example = "2024-01-15T10:30:00Z")
    Instant createdAt
) {
    public static RoleResponse from(Role role) {
        return new RoleResponse(
            role.getId(),
            role.getName(),
            role.getDescription(),
            role.getParentRoleId(),
            role.getCreatedAt()
        );
    }
}

public record UserPermissionsResponse(
    @Schema(description = "Set of all effective permission IDs from roles",
            example = "[\"transactions:read\", \"accounts:write\"]")
    Set<String> permissions,

    @Schema(description = "Resource-specific permissions granted to user")
    List<ResourcePermissionResponse> resourcePermissions,

    @Schema(description = "Active delegations granting additional access")
    List<DelegationResponse> delegations
) {
    public static UserPermissionsResponse from(EffectivePermissions effective) {
        return new UserPermissionsResponse(
            effective.getAllPermissionIds(),
            effective.resourcePermissions().stream()
                .map(ResourcePermissionResponse::from)
                .toList(),
            effective.delegations().stream()
                .map(DelegationResponse::from)
                .toList()
        );
    }
}

public record DelegationsResponse(
    @Schema(description = "Delegations created by this user")
    List<DelegationResponse> given,

    @Schema(description = "Delegations received by this user")
    List<DelegationResponse> received
) {
    public static DelegationsResponse from(DelegationsSummary summary) {
        return new DelegationsResponse(
            summary.given().stream().map(DelegationResponse::from).toList(),
            summary.received().stream().map(DelegationResponse::from).toList()
        );
    }
}

public record DelegationResponse(
    @Schema(description = "Delegation ID", example = "123")
    Long id,

    @Schema(description = "User who created the delegation", example = "usr_abc123")
    String delegatorId,

    @Schema(description = "User who received the delegation", example = "usr_def456")
    String delegateeId,

    @Schema(description = "Delegation scope", example = "read_only")
    String scope,

    @Schema(description = "Type of resource being delegated", example = "account",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String resourceType,

    @Schema(description = "Specific resource IDs if not delegating all",
            example = "[\"acc_123\", \"acc_456\"]",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String[] resourceIds,

    @Schema(description = "When delegation becomes active", example = "2024-01-15T10:30:00Z")
    Instant validFrom,

    @Schema(description = "When delegation expires", example = "2024-12-31T23:59:59Z",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    Instant validUntil,

    @Schema(description = "When delegation was revoked", example = "2024-06-15T14:00:00Z",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    Instant revokedAt
) {
    public static DelegationResponse from(Delegation delegation) {
        return new DelegationResponse(
            delegation.getId(),
            delegation.getDelegatorId(),
            delegation.getDelegateeId(),
            delegation.getScope(),
            delegation.getResourceType(),
            delegation.getResourceIds(),
            delegation.getValidFrom(),
            delegation.getValidUntil(),
            delegation.getRevokedAt()
        );
    }
}

public record ResourcePermissionResponse(
    @Schema(description = "Resource permission ID", example = "456")
    Long id,

    @Schema(description = "User ID granted permission", example = "usr_abc123")
    String userId,

    @Schema(description = "Type of resource", example = "account")
    String resourceType,

    @Schema(description = "Specific resource ID", example = "acc_789")
    String resourceId,

    @Schema(description = "Permission granted", example = "read")
    String permission,

    @Schema(description = "When permission was granted", example = "2024-01-15T10:30:00Z")
    Instant grantedAt,

    @Schema(description = "Who granted the permission", example = "usr_admin",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String grantedBy,

    @Schema(description = "When permission expires", example = "2024-12-31T23:59:59Z",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    Instant expiresAt,

    @Schema(description = "Reason for granting permission", example = "Temporary access for audit",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String reason
) {
    public static ResourcePermissionResponse from(ResourcePermission rp) {
        return new ResourcePermissionResponse(
            rp.getId(),
            rp.getUserId(),
            rp.getResourceType(),
            rp.getResourceId(),
            rp.getPermission(),
            rp.getGrantedAt(),
            rp.getGrantedBy(),
            rp.getExpiresAt(),
            rp.getReason()
        );
    }
}

public record AuditLogResponse(
    @Schema(description = "Audit log entry ID", example = "789")
    Long id,

    @Schema(description = "When the event occurred", example = "2024-01-15T10:30:00Z")
    Instant timestamp,

    @Schema(description = "User who performed the action", example = "usr_abc123",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String userId,

    @Schema(description = "Action performed", example = "ROLE_ASSIGNED")
    String action,

    @Schema(description = "Type of resource affected", example = "user-role",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String resourceType,

    @Schema(description = "ID of resource affected", example = "usr_def456",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String resourceId,

    @Schema(description = "Access decision", example = "GRANTED")
    String decision,

    @Schema(description = "Reason for decision", example = "User has required permission",
            requiredMode = Schema.RequiredMode.NOT_REQUIRED)
    String reason
) {
    public static AuditLogResponse from(AuthorizationAuditLog log) {
        return new AuditLogResponse(
            log.getId(),
            log.getTimestamp(),
            log.getUserId(),
            log.getAction(),
            log.getResourceType(),
            log.getResourceId(),
            log.getDecision(),
            log.getReason()
        );
    }
}
```

### 3.3 Package Structure and DTO Boundaries

#### Package Organization

```
org.budgetanalyzer.permission/
├── PermissionServiceApplication.java
├── api/
│   ├── UserPermissionController.java
│   ├── RoleController.java
│   ├── ResourcePermissionController.java
│   ├── DelegationController.java
│   ├── AuditController.java
│   ├── request/                    # API request DTOs
│   │   ├── RoleRequest.java
│   │   ├── UserRoleAssignmentRequest.java
│   │   ├── ResourcePermissionRequest.java
│   │   └── DelegationRequest.java
│   └── response/                   # API response DTOs
│       ├── RoleResponse.java
│       ├── UserPermissionsResponse.java
│       ├── DelegationResponse.java
│       ├── DelegationsResponse.java
│       ├── ResourcePermissionResponse.java
│       └── AuditLogResponse.java
├── config/
│   ├── OpenApiConfig.java
│   └── AsyncConfig.java
├── domain/                         # JPA entities
│   ├── User.java
│   ├── Role.java
│   ├── Permission.java
│   ├── UserRole.java
│   ├── RolePermission.java
│   ├── ResourcePermission.java
│   ├── Delegation.java
│   └── AuthorizationAuditLog.java
├── repository/                     # Spring Data JPA repositories
│   ├── UserRepository.java
│   ├── RoleRepository.java
│   ├── PermissionRepository.java
│   ├── UserRoleRepository.java
│   ├── RolePermissionRepository.java
│   ├── ResourcePermissionRepository.java
│   ├── DelegationRepository.java
│   └── AuditLogRepository.java
├── service/
│   ├── dto/                        # Service-layer DTOs (internal)
│   │   ├── EffectivePermissions.java
│   │   ├── DelegationsSummary.java
│   │   └── AuditQueryFilter.java
│   ├── exception/                  # Custom exceptions
│   │   ├── PermissionDeniedException.java
│   │   ├── ProtectedRoleException.java
│   │   └── DuplicateRoleAssignmentException.java
│   ├── PermissionService.java
│   ├── RoleService.java
│   ├── DelegationService.java
│   ├── UserService.java
│   ├── UserSyncService.java
│   ├── AuditService.java
│   ├── ResourcePermissionService.java
│   ├── CascadingRevocationService.java
│   └── PermissionCacheService.java
└── event/                          # Domain events
    └── PermissionChangeEvent.java
```

#### DTO Boundary Rules

**CRITICAL**: Strict separation between API and service layers.

| DTO Type | Package | Used By | Returns To |
|----------|---------|---------|------------|
| Request DTOs | `api/request/` | Controllers only | N/A |
| Response DTOs | `api/response/` | Controllers only | API clients |
| Service DTOs | `service/dto/` | Services | Controllers |
| Entities | `domain/` | Repositories, Services | Services |

**Data Flow Pattern**:
```
API Request → Controller → [transform to primitives/service DTOs] → Service → Repository
                                                                      ↓
API Response ← Controller ← [transform via Response.from()] ← Service-layer DTO/Entity
```

**Rules**:
1. **Services NEVER accept API request DTOs** - Controllers must extract primitives or build service DTOs
2. **Services NEVER return API response DTOs** - They return entities or service-layer DTOs
3. **Controllers transform using `Response.from()`** - All response DTOs have static factory methods
4. **Service DTOs are for complex aggregates** - When returning data that doesn't map to a single entity

**Example - Correct Pattern**:
```java
// Controller - transforms API DTO to primitives for service
@PostMapping
public ResponseEntity<RoleResponse> createRole(@RequestBody @Valid RoleRequest request) {
    var created = roleService.createRole(
        request.name(),           // Extract primitives
        request.description(),
        request.parentRoleId()
    );
    return ResponseEntity.created(location).body(RoleResponse.from(created));
}

// Service - accepts primitives, returns entity
@Transactional
public Role createRole(String name, String description, String parentRoleId) {
    var role = new Role();
    role.setName(name);
    // ...
    return roleRepository.save(role);
}
```

**Example - Incorrect Pattern (DO NOT DO)**:
```java
// WRONG - Service accepting API DTO
public Role createRole(RoleRequest request) { ... }

// WRONG - Service returning API response DTO
public RoleResponse getRole(String id) { ... }
```

---

## Phase 4: Repository Layer

### 4.1 JPA Repositories

Create in `repository/`:

```java
// Soft-deletable entities implement SoftDeleteOperations from service-common
public interface UserRepository extends JpaRepository<User, String>, SoftDeleteOperations<User> {
    // Active user queries (filter by deleted = false)
    Optional<User> findByAuth0SubAndDeletedFalse(String auth0Sub);
    Optional<User> findByEmailAndDeletedFalse(String email);

    // Include deleted for admin/audit purposes
    Optional<User> findByAuth0Sub(String auth0Sub);
}

public interface RoleRepository extends JpaRepository<Role, String>, SoftDeleteOperations<Role> {
    List<Role> findByParentRoleIdAndDeletedFalse(String parentRoleId);
    List<Role> findAllByDeletedFalse();
}

public interface PermissionRepository extends JpaRepository<Permission, String>, SoftDeleteOperations<Permission> {
    List<Permission> findByResourceTypeAndDeletedFalse(String resourceType);
    List<Permission> findAllByDeletedFalse();
}

// Temporal entities use revoked_at queries
public interface UserRoleRepository extends JpaRepository<UserRole, Long> {
    // Active roles for a user
    List<UserRole> findByUserIdAndRevokedAtIsNull(String userId);

    // Find specific active assignment
    Optional<UserRole> findByUserIdAndRoleIdAndRevokedAtIsNull(String userId, String roleId);

    // Point-in-time query: roles user had at specific date
    @Query("SELECT ur FROM UserRole ur " +
           "WHERE ur.userId = :userId " +
           "AND ur.grantedAt <= :pointInTime " +
           "AND (ur.revokedAt IS NULL OR ur.revokedAt > :pointInTime)")
    List<UserRole> findRolesAtPointInTime(
        @Param("userId") String userId,
        @Param("pointInTime") Instant pointInTime);

    // Get active permission IDs for user (considering role-based permissions)
    @Query("SELECT rp.permissionId FROM UserRole ur " +
           "JOIN RolePermission rp ON ur.roleId = rp.roleId " +
           "WHERE ur.userId = :userId " +
           "AND ur.revokedAt IS NULL " +
           "AND rp.revokedAt IS NULL " +
           "AND (ur.expiresAt IS NULL OR ur.expiresAt > :now)")
    Set<String> findActivePermissionIdsByUserId(
        @Param("userId") String userId,
        @Param("now") Instant now);

    // For cascading revocation when user is soft-deleted
    @Query("SELECT ur FROM UserRole ur WHERE ur.userId = :userId AND ur.revokedAt IS NULL")
    List<UserRole> findActiveByUserId(@Param("userId") String userId);
}

public interface RolePermissionRepository extends JpaRepository<RolePermission, Long> {
    // Active permissions for a role
    List<RolePermission> findByRoleIdAndRevokedAtIsNull(String roleId);

    // For cascading revocation when role is soft-deleted
    @Query("SELECT rp FROM RolePermission rp WHERE rp.roleId = :roleId AND rp.revokedAt IS NULL")
    List<RolePermission> findActiveByRoleId(@Param("roleId") String roleId);

    // For cascading revocation when permission is soft-deleted
    @Query("SELECT rp FROM RolePermission rp WHERE rp.permissionId = :permissionId AND rp.revokedAt IS NULL")
    List<RolePermission> findActiveByPermissionId(@Param("permissionId") String permissionId);
}

public interface ResourcePermissionRepository extends JpaRepository<ResourcePermission, Long> {
    // Active permissions for a user
    List<ResourcePermission> findByUserIdAndRevokedAtIsNull(String userId);

    // Find active permission for specific resource
    @Query("SELECT rp FROM ResourcePermission rp " +
           "WHERE rp.userId = :userId " +
           "AND rp.resourceType = :resourceType " +
           "AND rp.resourceId = :resourceId " +
           "AND rp.revokedAt IS NULL " +
           "AND (rp.expiresAt IS NULL OR rp.expiresAt > :now)")
    List<ResourcePermission> findActivePermissions(
        @Param("userId") String userId,
        @Param("resourceType") String resourceType,
        @Param("resourceId") String resourceId,
        @Param("now") Instant now);

    // Point-in-time query
    @Query("SELECT rp FROM ResourcePermission rp " +
           "WHERE rp.userId = :userId " +
           "AND rp.grantedAt <= :pointInTime " +
           "AND (rp.revokedAt IS NULL OR rp.revokedAt > :pointInTime)")
    List<ResourcePermission> findPermissionsAtPointInTime(
        @Param("userId") String userId,
        @Param("pointInTime") Instant pointInTime);

    // For cascading revocation when user is soft-deleted
    @Query("SELECT rp FROM ResourcePermission rp WHERE rp.userId = :userId AND rp.revokedAt IS NULL")
    List<ResourcePermission> findActiveByUserId(@Param("userId") String userId);
}

public interface DelegationRepository extends JpaRepository<Delegation, Long> {
    // Active delegations received by user
    @Query("SELECT d FROM Delegation d " +
           "WHERE d.delegateeId = :userId " +
           "AND d.revokedAt IS NULL " +
           "AND d.validFrom <= :now " +
           "AND (d.validUntil IS NULL OR d.validUntil > :now)")
    List<Delegation> findActiveDelegationsForUser(
        @Param("userId") String userId,
        @Param("now") Instant now);

    // All delegations created by user (including revoked, for audit)
    List<Delegation> findByDelegatorId(String delegatorId);

    // Active delegations created by user
    List<Delegation> findByDelegatorIdAndRevokedAtIsNull(String delegatorId);

    // For cascading revocation when user is soft-deleted
    @Query("SELECT d FROM Delegation d WHERE (d.delegatorId = :userId OR d.delegateeId = :userId) AND d.revokedAt IS NULL")
    List<Delegation> findActiveByUserId(@Param("userId") String userId);
}

public interface AuditLogRepository extends JpaRepository<AuthorizationAuditLog, Long> {
    Page<AuthorizationAuditLog> findByUserId(String userId, Pageable pageable);

    @Query("SELECT a FROM AuthorizationAuditLog a " +
           "WHERE a.timestamp BETWEEN :start AND :end " +
           "ORDER BY a.timestamp DESC")
    Page<AuthorizationAuditLog> findByTimestampRange(
        @Param("start") Instant start,
        @Param("end") Instant end,
        Pageable pageable);
}
```

---

## Phase 5: Service Layer

### 5.1 Core Services

Create in `service/`:

#### Custom Exceptions

The permission service uses custom exceptions that extend the service-web exception hierarchy:

```java
import org.budgetanalyzer.service.exception.BusinessException;

/**
 * Thrown when a user attempts an operation they don't have permission for.
 * Results in HTTP 403 Forbidden.
 */
public class PermissionDeniedException extends BusinessException {

    public PermissionDeniedException(String message) {
        super(message, "PERMISSION_DENIED");
    }

    public PermissionDeniedException(String message, String errorCode) {
        super(message, errorCode);
    }
}

/**
 * Thrown when trying to assign/revoke protected roles via API.
 * Results in HTTP 403 Forbidden.
 */
public class ProtectedRoleException extends BusinessException {

    public ProtectedRoleException(String message) {
        super(message, "PROTECTED_ROLE_VIOLATION");
    }
}

/**
 * Thrown when a user already has an active role assignment.
 * Results in HTTP 422 Unprocessable Entity.
 */
public class DuplicateRoleAssignmentException extends BusinessException {

    public DuplicateRoleAssignmentException(String userId, String roleId) {
        super("User " + userId + " already has role " + roleId, "DUPLICATE_ROLE_ASSIGNMENT");
    }
}
```

#### PermissionService.java

Main permission operations:

```java
@Service
@Transactional(readOnly = true)
public class PermissionService {

    private final UserRepository userRepository;
    private final UserRoleRepository userRoleRepository;
    private final RoleRepository roleRepository;
    private final ResourcePermissionRepository resourcePermissionRepository;
    private final DelegationRepository delegationRepository;
    private final AuditService auditService;
    private final PermissionCacheService permissionCacheService;

    public PermissionService(UserRepository userRepository,
                             UserRoleRepository userRoleRepository,
                             RoleRepository roleRepository,
                             ResourcePermissionRepository resourcePermissionRepository,
                             DelegationRepository delegationRepository,
                             AuditService auditService,
                             PermissionCacheService permissionCacheService) {
        this.userRepository = userRepository;
        this.userRoleRepository = userRoleRepository;
        this.roleRepository = roleRepository;
        this.resourcePermissionRepository = resourcePermissionRepository;
        this.delegationRepository = delegationRepository;
        this.auditService = auditService;
        this.permissionCacheService = permissionCacheService;
    }

    public EffectivePermissions getEffectivePermissions(String userId) {
        // 1. Get role-based permissions
        var rolePermissions = userRoleRepository.findActivePermissionIdsByUserId(
            userId, Instant.now());

        // 2. Get resource-specific permissions
        var resourcePermissions = resourcePermissionRepository
            .findByUserIdAndRevokedAtIsNull(userId);

        // 3. Get delegated permissions
        var delegations = delegationRepository.findActiveDelegationsForUser(
            userId, Instant.now());

        // 4. Build and return service-layer DTO
        return new EffectivePermissions(rolePermissions, resourcePermissions, delegations);
    }

    public List<Role> getUserRoles(String userId) {
        // Return list of roles for user
        var userRoles = userRoleRepository.findByUserIdAndRevokedAtIsNull(userId);

        return userRoles.stream()
            .map(ur -> roleRepository.findByIdAndDeletedFalse(ur.getRoleId()))
            .filter(Optional::isPresent)
            .map(Optional::get)
            .toList();
    }

    // Role classification for assignment governance
    private static final Set<String> BASIC_ROLES = Set.of("USER", "ACCOUNTANT", "AUDITOR");
    private static final Set<String> ELEVATED_ROLES = Set.of("MANAGER", "ORG_ADMIN");
    private static final String PROTECTED_ROLE = "SYSTEM_ADMIN";

    @Transactional
    public void assignRole(String userId, String roleId, String grantedBy) {
        // 1. SYSTEM_ADMIN cannot be assigned via API - database only
        if (PROTECTED_ROLE.equals(roleId)) {
            throw new ProtectedRoleException(
                "SYSTEM_ADMIN role cannot be assigned via API. Use database directly.");
        }

        // 2. Check granter has permission to assign this role level
        var granterPermissions = getEffectivePermissions(grantedBy).getAllPermissionIds();

        if (ELEVATED_ROLES.contains(roleId)) {
            if (!granterPermissions.contains("user-roles:assign-elevated")) {
                throw new PermissionDeniedException(
                    "Cannot assign elevated role: " + roleId +
                    ". Requires 'user-roles:assign-elevated' permission.",
                    "INSUFFICIENT_PERMISSION_FOR_ELEVATED_ROLE");
            }
        } else if (BASIC_ROLES.contains(roleId)) {
            if (!granterPermissions.contains("user-roles:assign-basic") &&
                !granterPermissions.contains("user-roles:assign-elevated")) {
                throw new PermissionDeniedException(
                    "Cannot assign role: " + roleId +
                    ". Requires 'user-roles:assign-basic' permission.",
                    "INSUFFICIENT_PERMISSION_FOR_BASIC_ROLE");
            }
        } else {
            // Custom role - require elevated permission
            if (!granterPermissions.contains("user-roles:assign-elevated")) {
                throw new PermissionDeniedException(
                    "Cannot assign custom role: " + roleId,
                    "INSUFFICIENT_PERMISSION_FOR_CUSTOM_ROLE");
            }
        }

        // 3. Validate user exists and is not soft-deleted
        userRepository.findByIdAndDeletedFalse(userId)
            .orElseThrow(() -> new ResourceNotFoundException("User not found: " + userId));

        // 4. Validate role exists and is not soft-deleted
        roleRepository.findByIdAndDeletedFalse(roleId)
            .orElseThrow(() -> new ResourceNotFoundException("Role not found: " + roleId));

        // 5. Check if active assignment already exists
        if (userRoleRepository.findByUserIdAndRoleIdAndRevokedAtIsNull(userId, roleId).isPresent()) {
            throw new DuplicateRoleAssignmentException(userId, roleId);
        }

        // 6. Create new UserRole entry (re-granting creates new row)
        var userRole = new UserRole();
        userRole.setUserId(userId);
        userRole.setRoleId(roleId);
        userRole.setGrantedAt(Instant.now());
        userRole.setGrantedBy(grantedBy);
        userRoleRepository.save(userRole);

        // 7. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.roleAssigned(userId, roleId, grantedBy));

        // 8. Invalidate cache
        permissionCacheService.invalidateCache(userId);
    }

    @Transactional
    public void revokeRole(String userId, String roleId, String revokedBy) {
        // 1. SYSTEM_ADMIN role cannot be revoked via API
        if (PROTECTED_ROLE.equals(roleId)) {
            throw new ProtectedRoleException(
                "SYSTEM_ADMIN role cannot be revoked via API. Use database directly.");
        }

        // 2. Check revoker has permission
        var revokerPermissions = getEffectivePermissions(revokedBy).getAllPermissionIds();
        if (!revokerPermissions.contains("user-roles:revoke")) {
            throw new PermissionDeniedException(
                "Cannot revoke roles. Requires 'user-roles:revoke' permission.",
                "INSUFFICIENT_PERMISSION_FOR_REVOKE");
        }

        // 3. Find active UserRole entry
        var userRole = userRoleRepository.findByUserIdAndRoleIdAndRevokedAtIsNull(userId, roleId)
            .orElseThrow(() -> new ResourceNotFoundException("Active role assignment not found"));

        // 4. Set revokedAt = now, revokedBy = revokedBy (temporal revocation, not delete)
        userRole.setRevokedAt(Instant.now());
        userRole.setRevokedBy(revokedBy);
        userRoleRepository.save(userRole);

        // 5. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.roleRevoked(userId, roleId, revokedBy));

        // 6. Invalidate cache
        permissionCacheService.invalidateCache(userId);
    }

    // Point-in-time query for compliance/audit
    public EffectivePermissions getPermissionsAtPointInTime(String userId, Instant pointInTime) {
        // Query all temporal tables with point-in-time filters
        var rolesAtTime = userRoleRepository.findRolesAtPointInTime(userId, pointInTime);
        var resourcePermsAtTime = resourcePermissionRepository
            .findPermissionsAtPointInTime(userId, pointInTime);

        // Build permissions from roles at that time
        var rolePermissions = rolesAtTime.stream()
            .flatMap(ur -> getRolePermissionsAtPointInTime(ur.getRoleId(), pointInTime).stream())
            .collect(Collectors.toSet());

        return new EffectivePermissions(rolePermissions, resourcePermsAtTime, List.of());
    }
}

#### CascadingRevocationService.java

Handles auto-revocation when parent entities are soft-deleted:

```java
@Service
@Transactional
public class CascadingRevocationService {

    private final UserRoleRepository userRoleRepository;
    private final RolePermissionRepository rolePermissionRepository;
    private final ResourcePermissionRepository resourcePermissionRepository;
    private final DelegationRepository delegationRepository;
    private final AuditService auditService;
    private final PermissionCacheService permissionCacheService;

    public CascadingRevocationService(UserRoleRepository userRoleRepository,
                                      RolePermissionRepository rolePermissionRepository,
                                      ResourcePermissionRepository resourcePermissionRepository,
                                      DelegationRepository delegationRepository,
                                      AuditService auditService,
                                      PermissionCacheService permissionCacheService) {
        this.userRoleRepository = userRoleRepository;
        this.rolePermissionRepository = rolePermissionRepository;
        this.resourcePermissionRepository = resourcePermissionRepository;
        this.delegationRepository = delegationRepository;
        this.auditService = auditService;
        this.permissionCacheService = permissionCacheService;
    }

    public void revokeAllForUser(String userId, String revokedBy) {
        // Called when User is soft-deleted
        var now = Instant.now();

        // 1. Revoke all UserRole entries for user
        userRoleRepository.findActiveByUserId(userId).forEach(ur -> {
            ur.setRevokedAt(now);
            ur.setRevokedBy(revokedBy);
            userRoleRepository.save(ur);
        });

        // 2. Revoke all ResourcePermission entries for user
        resourcePermissionRepository.findActiveByUserId(userId).forEach(rp -> {
            rp.setRevokedAt(now);
            rp.setRevokedBy(revokedBy);
            resourcePermissionRepository.save(rp);
        });

        // 3. Revoke all Delegation entries (as delegator or delegatee)
        delegationRepository.findActiveByUserId(userId).forEach(d -> {
            d.setRevokedAt(now);
            d.setRevokedBy(revokedBy);
            delegationRepository.save(d);
        });

        // 4. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.cascadingRevocation("user", userId, revokedBy));

        // 5. Invalidate cache
        permissionCacheService.invalidateCache(userId);
    }

    public void revokeAllForRole(String roleId, String revokedBy) {
        // Called when Role is soft-deleted
        var now = Instant.now();

        // 1. Revoke all UserRole entries for role and collect affected users
        var affectedUserIds = new HashSet<String>();
        userRoleRepository.findActiveByRoleId(roleId).forEach(ur -> {
            ur.setRevokedAt(now);
            ur.setRevokedBy(revokedBy);
            userRoleRepository.save(ur);
            affectedUserIds.add(ur.getUserId());
        });

        // 2. Revoke all RolePermission entries for role
        rolePermissionRepository.findActiveByRoleId(roleId).forEach(rp -> {
            rp.setRevokedAt(now);
            rp.setRevokedBy(revokedBy);
            rolePermissionRepository.save(rp);
        });

        // 3. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.cascadingRevocation("role", roleId, revokedBy));

        // 4. Invalidate affected users' caches
        affectedUserIds.forEach(permissionCacheService::invalidateCache);
    }

    public void revokeAllForPermission(String permissionId, String revokedBy) {
        // Called when Permission is soft-deleted
        var now = Instant.now();

        // 1. Revoke all RolePermission entries for permission
        var affectedRoleIds = new HashSet<String>();
        rolePermissionRepository.findActiveByPermissionId(permissionId).forEach(rp -> {
            rp.setRevokedAt(now);
            rp.setRevokedBy(revokedBy);
            rolePermissionRepository.save(rp);
            affectedRoleIds.add(rp.getRoleId());
        });

        // 2. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.cascadingRevocation("permission", permissionId, revokedBy));

        // 3. Invalidate affected users' caches (via roles)
        // Find all users with these roles and invalidate their caches
        affectedRoleIds.forEach(roleId -> {
            userRoleRepository.findActiveByRoleId(roleId).forEach(ur ->
                permissionCacheService.invalidateCache(ur.getUserId())
            );
        });
    }
}
```

#### RoleService.java

Role CRUD operations:

```java
@Service
@Transactional(readOnly = true)
public class RoleService {

    private final RoleRepository roleRepository;
    private final CascadingRevocationService cascadingRevocationService;

    public RoleService(RoleRepository roleRepository,
                       CascadingRevocationService cascadingRevocationService) {
        this.roleRepository = roleRepository;
        this.cascadingRevocationService = cascadingRevocationService;
    }

    public List<Role> getAllRoles() {
        return roleRepository.findAllByDeletedFalse();
    }

    public Role getRole(String id) {
        return roleRepository.findByIdAndDeletedFalse(id)
            .orElseThrow(() -> new ResourceNotFoundException("Role not found: " + id));
    }

    @Transactional
    public Role createRole(String name, String description, String parentRoleId) {
        var role = new Role();
        role.setId(generateRoleId());
        role.setName(name);
        role.setDescription(description);
        role.setParentRoleId(parentRoleId);
        return roleRepository.save(role);
    }

    @Transactional
    public Role updateRole(String id, String name, String description, String parentRoleId) {
        var role = getRole(id);
        role.setName(name);
        role.setDescription(description);
        role.setParentRoleId(parentRoleId);
        return roleRepository.save(role);
    }

    @Transactional
    public void deleteRole(String id, String deletedBy) {
        // 1. Find role (must not already be deleted)
        // 2. Call cascadingRevocationService.revokeAllForRole(id, deletedBy)
        // 3. role.markDeleted(deletedBy) - soft delete
        // 4. Log to audit
    }

    @Transactional
    public void restoreRole(String id) {
        // Optional: restore a soft-deleted role
        // Note: Does NOT restore revoked UserRole/RolePermission entries
    }
}
```

#### DelegationService.java

Delegation management:

```java
@Service
@Transactional(readOnly = true)
public class DelegationService {

    private final DelegationRepository delegationRepository;
    private final UserRepository userRepository;
    private final AuditService auditService;
    private final PermissionCacheService permissionCacheService;

    public DelegationService(DelegationRepository delegationRepository,
                             UserRepository userRepository,
                             AuditService auditService,
                             PermissionCacheService permissionCacheService) {
        this.delegationRepository = delegationRepository;
        this.userRepository = userRepository;
        this.auditService = auditService;
        this.permissionCacheService = permissionCacheService;
    }

    @Transactional
    public Delegation createDelegation(String delegatorId, String delegateeId, String scope,
                                        String resourceType, String[] resourceIds, Instant validUntil) {
        // 1. Validate delegator owns the resources
        // 2. Validate delegatee exists
        userRepository.findByIdAndDeletedFalse(delegateeId)
            .orElseThrow(() -> new ResourceNotFoundException("Delegatee not found"));

        // 3. Create delegation with time bounds
        var delegation = new Delegation();
        delegation.setDelegatorId(delegatorId);
        delegation.setDelegateeId(delegateeId);
        delegation.setScope(scope);
        delegation.setResourceType(resourceType);
        delegation.setResourceIds(resourceIds);
        delegation.setValidFrom(Instant.now());
        delegation.setValidUntil(validUntil);

        var saved = delegationRepository.save(delegation);

        // 4. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.delegationCreated(saved));

        // 5. Invalidate delegatee's permission cache
        permissionCacheService.invalidateCache(delegateeId);

        return saved;
    }

    @Transactional
    public void revokeDelegation(Long id, String revokedBy) {
        var delegation = delegationRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Delegation not found: " + id));

        // 1. Mark delegation as revoked
        delegation.setRevokedAt(Instant.now());
        delegation.setRevokedBy(revokedBy);
        delegationRepository.save(delegation);

        // 2. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.delegationRevoked(delegation));

        // 3. Invalidate cache
        permissionCacheService.invalidateCache(delegation.getDelegateeId());
    }

    public DelegationsSummary getDelegationsForUser(String userId) {
        // Return both given and received delegations as service-layer DTO
        var given = delegationRepository.findByDelegatorIdAndRevokedAtIsNull(userId);
        var received = delegationRepository.findActiveDelegationsForUser(userId, Instant.now());

        return new DelegationsSummary(given, received);
    }

    public boolean hasDelegatedAccess(String delegateeId, String resourceType,
                                       String resourceId, String permission) {
        // Check if active delegation exists
        var delegations = delegationRepository.findActiveDelegationsForUser(
            delegateeId, Instant.now());

        return delegations.stream().anyMatch(d ->
            d.matchesResource(resourceType, resourceId, permission));
    }
}
```

#### UserSyncService.java

Auth0 user synchronization:

```java
@Service
@Transactional
public class UserSyncService {

    public User syncUser(String auth0Sub, String email, String displayName) {
        // Find or create local user record
        return userRepository.findByAuth0Sub(auth0Sub)
            .map(user -> updateUser(user, email, displayName))
            .orElseGet(() -> createUser(auth0Sub, email, displayName));
    }

    private User createUser(String auth0Sub, String email, String displayName) {
        var user = new User();
        user.setId(generateUserId());  // e.g., "usr_" + UUID
        user.setAuth0Sub(auth0Sub);
        user.setEmail(email);
        user.setDisplayName(displayName);

        // Assign default USER role
        assignDefaultRole(user);

        return userRepository.save(user);
    }
}
```

#### UserService.java

User management with soft delete:

```java
@Service
@Transactional(readOnly = true)
public class UserService {

    private final UserRepository userRepository;
    private final CascadingRevocationService cascadingRevocationService;
    private final AuditService auditService;

    public UserService(UserRepository userRepository,
                       CascadingRevocationService cascadingRevocationService,
                       AuditService auditService) {
        this.userRepository = userRepository;
        this.cascadingRevocationService = cascadingRevocationService;
        this.auditService = auditService;
    }

    public User getUser(String id) {
        return userRepository.findByIdAndDeletedFalse(id)
            .orElseThrow(() -> new ResourceNotFoundException("User not found: " + id));
    }

    public List<User> getAllUsers() {
        return userRepository.findAllByDeletedFalse();
    }

    @Transactional
    public void deleteUser(String id, String deletedBy) {
        // 1. Find user (must not already be deleted)
        var user = getUser(id);

        // 2. Call cascadingRevocationService.revokeAllForUser(id, deletedBy)
        cascadingRevocationService.revokeAllForUser(id, deletedBy);

        // 3. user.markDeleted(deletedBy) - soft delete
        user.markDeleted(deletedBy);
        userRepository.save(user);

        // 4. Log to audit
        auditService.logPermissionChange(PermissionChangeEvent.userDeleted(user, deletedBy));
    }

    @Transactional
    public void restoreUser(String id) {
        // Optional: restore a soft-deleted user
        var user = userRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("User not found: " + id));

        if (!user.isDeleted()) {
            throw new IllegalStateException("User is not deleted");
        }

        user.restore();
        userRepository.save(user);

        // Note: Does NOT restore revoked assignments - must be re-granted
        auditService.logPermissionChange(PermissionChangeEvent.userRestored(user));
    }
}
```

#### AuditService.java

Audit logging:

```java
@Service
public class AuditService {

    private final AuditLogRepository auditLogRepository;

    public AuditService(AuditLogRepository auditLogRepository) {
        this.auditLogRepository = auditLogRepository;
    }

    @Async
    public void logPermissionChange(PermissionChangeEvent event) {
        var log = new AuthorizationAuditLog();
        log.setUserId(event.getUserId());
        log.setAction(event.getAction());
        log.setDecision("GRANTED");
        log.setAdditionalContext(event.getContext());
        auditLogRepository.save(log);
    }

    @Async
    public void logAccessDecision(String userId, String action, String resourceType,
                                   String resourceId, String decision, String reason) {
        var log = new AuthorizationAuditLog();
        log.setUserId(userId);
        log.setAction(action);
        log.setResourceType(resourceType);
        log.setResourceId(resourceId);
        log.setDecision(decision);
        log.setReason(reason);
        auditLogRepository.save(log);
    }

    public Page<AuthorizationAuditLog> queryAuditLog(AuditQueryFilter filter, Pageable pageable) {
        // Query with filters - controller transforms to AuditLogResponse
        if (filter.userId() != null) {
            return auditLogRepository.findByUserId(filter.userId(), pageable);
        }
        if (filter.startTime() != null && filter.endTime() != null) {
            return auditLogRepository.findByTimestampRange(
                filter.startTime(), filter.endTime(), pageable);
        }
        return auditLogRepository.findAll(pageable);
    }

    public Page<AuthorizationAuditLog> queryByUser(String userId, Pageable pageable) {
        return auditLogRepository.findByUserId(userId, pageable);
    }
}
```

**Note**: Async configuration requires `@EnableAsync` on a configuration class. Add this to the application or a dedicated config:

```java
@Configuration
@EnableAsync
public class AsyncConfig {
    // Optional: customize executor
}
```

#### ResourcePermissionService.java

Resource-specific permission management:

```java
@Service
@Transactional(readOnly = true)
public class ResourcePermissionService {

    private final ResourcePermissionRepository resourcePermissionRepository;
    private final UserRepository userRepository;
    private final AuditService auditService;
    private final PermissionCacheService permissionCacheService;

    public ResourcePermissionService(ResourcePermissionRepository resourcePermissionRepository,
                                     UserRepository userRepository,
                                     AuditService auditService,
                                     PermissionCacheService permissionCacheService) {
        this.resourcePermissionRepository = resourcePermissionRepository;
        this.userRepository = userRepository;
        this.auditService = auditService;
        this.permissionCacheService = permissionCacheService;
    }

    @Transactional
    public ResourcePermission grantPermission(String userId, String resourceType, String resourceId,
                                               String permission, Instant expiresAt, String reason,
                                               String grantedBy) {
        // Validate user exists
        userRepository.findByIdAndDeletedFalse(userId)
            .orElseThrow(() -> new ResourceNotFoundException("User not found: " + userId));

        // Create resource permission
        var resourcePermission = new ResourcePermission();
        resourcePermission.setUserId(userId);
        resourcePermission.setResourceType(resourceType);
        resourcePermission.setResourceId(resourceId);
        resourcePermission.setPermission(permission);
        resourcePermission.setGrantedAt(Instant.now());
        resourcePermission.setGrantedBy(grantedBy);
        resourcePermission.setExpiresAt(expiresAt);
        resourcePermission.setReason(reason);

        var saved = resourcePermissionRepository.save(resourcePermission);

        // Log and invalidate cache
        auditService.logPermissionChange(PermissionChangeEvent.resourcePermissionGranted(saved));
        permissionCacheService.invalidateCache(userId);

        return saved;
    }

    @Transactional
    public void revokePermission(Long id, String revokedBy) {
        var permission = resourcePermissionRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Resource permission not found: " + id));

        permission.setRevokedAt(Instant.now());
        permission.setRevokedBy(revokedBy);
        resourcePermissionRepository.save(permission);

        auditService.logPermissionChange(PermissionChangeEvent.resourcePermissionRevoked(permission));
        permissionCacheService.invalidateCache(permission.getUserId());
    }

    public List<ResourcePermission> getForUser(String userId) {
        return resourcePermissionRepository.findByUserIdAndRevokedAtIsNull(userId);
    }
}
```

### 5.2 Caching Service

#### PermissionCacheService.java

```java
@Service
public class PermissionCacheService {

    private final RedisTemplate<String, Set<String>> redisTemplate;
    private final StringRedisTemplate stringRedisTemplate;

    private static final String PERMISSION_KEY_PREFIX = "permissions:";
    private static final String INVALIDATION_CHANNEL = "permission-invalidation";
    private static final Duration CACHE_TTL = Duration.ofMinutes(5);

    public Set<String> getCachedPermissions(String userId) {
        var key = PERMISSION_KEY_PREFIX + userId;
        return redisTemplate.opsForSet().members(key);
    }

    public void cachePermissions(String userId, Set<String> permissions) {
        var key = PERMISSION_KEY_PREFIX + userId;
        if (!permissions.isEmpty()) {
            redisTemplate.opsForSet().add(key, permissions.toArray(new String[0]));
            redisTemplate.expire(key, CACHE_TTL);
        }
    }

    public void invalidateCache(String userId) {
        var key = PERMISSION_KEY_PREFIX + userId;
        redisTemplate.delete(key);

        // Publish invalidation event for other service instances
        stringRedisTemplate.convertAndSend(INVALIDATION_CHANNEL, userId);
    }

    @EventListener
    public void onPermissionChange(PermissionChangeEvent event) {
        invalidateCache(event.getUserId());
    }
}
```

---

## Phase 6: API Layer (Controllers)

### 6.1 Controllers

Create in `api/`:

#### UserPermissionController.java

```java
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.budgetanalyzer.service.api.ApiErrorResponse;

@Tag(name = "User Permissions", description = "User permission management")
@RestController
@RequestMapping("/v1/users")
public class UserPermissionController {

    private final PermissionService permissionService;
    private final UserSyncService userSyncService;

    public UserPermissionController(PermissionService permissionService,
                                    UserSyncService userSyncService) {
        this.permissionService = permissionService;
        this.userSyncService = userSyncService;
    }

    @Operation(
        summary = "Get current user's permissions",
        description = "Returns all effective permissions for the authenticated user including role-based, resource-specific, and delegated permissions"
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Permissions retrieved successfully",
            content = @Content(schema = @Schema(implementation = UserPermissionsResponse.class))
        ),
        @ApiResponse(
            responseCode = "401",
            description = "Not authenticated",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping("/me/permissions")
    @PreAuthorize("isAuthenticated()")
    public UserPermissionsResponse getCurrentUserPermissions(Authentication auth) {
        var userId = SecurityContextUtil.getCurrentUserId();
        var permissions = permissionService.getEffectivePermissions(userId);

        return UserPermissionsResponse.from(permissions);
    }

    @Operation(
        summary = "Get user's permissions",
        description = "Returns all effective permissions for a specified user. Requires users:read permission."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Permissions retrieved successfully",
            content = @Content(schema = @Schema(implementation = UserPermissionsResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "User not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping("/{id}/permissions")
    @PreAuthorize("hasAuthority('users:read')")
    public UserPermissionsResponse getUserPermissions(
            @Parameter(description = "User ID", example = "usr_abc123")
            @PathVariable String id) {
        var permissions = permissionService.getEffectivePermissions(id);

        return UserPermissionsResponse.from(permissions);
    }

    @Operation(
        summary = "Get user's roles",
        description = "Returns all active roles assigned to a user. User can view their own roles or requires users:read permission."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Roles retrieved successfully",
            content = @Content(schema = @Schema(implementation = RoleResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "User not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping("/{id}/roles")
    @PreAuthorize("hasAuthority('users:read') or #id == authentication.name")
    public List<RoleResponse> getUserRoles(
            @Parameter(description = "User ID", example = "usr_abc123")
            @PathVariable String id) {
        return permissionService.getUserRoles(id).stream()
            .map(RoleResponse::from)
            .toList();
    }

    @Operation(
        summary = "Assign role to user",
        description = "Assigns a role to a user with governance checks. Basic roles require 'user-roles:assign-basic', elevated roles require 'user-roles:assign-elevated'."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "204",
            description = "Role assigned successfully"
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions for this role level",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "User or role not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "422",
            description = "User already has this role or protected role violation",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @PostMapping("/{id}/roles")
    @PreAuthorize("hasAuthority('user-roles:assign-basic') or hasAuthority('user-roles:assign-elevated')")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void assignRole(
            @Parameter(description = "User ID", example = "usr_abc123")
            @PathVariable String id,
            @RequestBody @Valid UserRoleAssignmentRequest request) {
        // Service layer enforces role-level restrictions
        var grantedBy = SecurityContextUtil.getCurrentUserId();
        permissionService.assignRole(id, request.roleId(), grantedBy);
    }

    @Operation(
        summary = "Revoke role from user",
        description = "Revokes a role from a user. Requires 'user-roles:revoke' permission."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "204",
            description = "Role revoked successfully"
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions or protected role",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "Active role assignment not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @DeleteMapping("/{id}/roles/{roleId}")
    @PreAuthorize("hasAuthority('user-roles:revoke')")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revokeRole(
            @Parameter(description = "User ID", example = "usr_abc123")
            @PathVariable String id,
            @Parameter(description = "Role ID to revoke", example = "ACCOUNTANT")
            @PathVariable String roleId) {
        var revokedBy = SecurityContextUtil.getCurrentUserId();
        permissionService.revokeRole(id, roleId, revokedBy);
    }
}
```

#### RoleController.java

```java
@Tag(name = "Roles", description = "Role management - CRUD operations for authorization roles")
@RestController
@RequestMapping("/v1/roles")
public class RoleController {

    private final RoleService roleService;

    public RoleController(RoleService roleService) {
        this.roleService = roleService;
    }

    @Operation(
        summary = "List all roles",
        description = "Returns all active (non-deleted) roles. Requires 'roles:read' permission."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Roles retrieved successfully",
            content = @Content(schema = @Schema(implementation = RoleResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping
    @PreAuthorize("hasAuthority('roles:read')")
    public List<RoleResponse> getAllRoles() {
        return roleService.getAllRoles().stream()
            .map(RoleResponse::from)
            .toList();
    }

    @Operation(
        summary = "Get role by ID",
        description = "Returns a specific role by ID. Requires 'roles:read' permission."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Role retrieved successfully",
            content = @Content(schema = @Schema(implementation = RoleResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "Role not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('roles:read')")
    public RoleResponse getRole(
            @Parameter(description = "Role ID", example = "MANAGER")
            @PathVariable String id) {
        return RoleResponse.from(roleService.getRole(id));
    }

    @Operation(
        summary = "Create new role",
        description = "Creates a new role. Requires 'roles:write' permission (SYSTEM_ADMIN only)."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "201",
            description = "Role created successfully",
            content = @Content(schema = @Schema(implementation = RoleResponse.class))
        ),
        @ApiResponse(
            responseCode = "400",
            description = "Invalid request data",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @PostMapping
    @PreAuthorize("hasAuthority('roles:write')")
    public ResponseEntity<RoleResponse> createRole(@RequestBody @Valid RoleRequest request) {
        var created = roleService.createRole(
            request.name(),
            request.description(),
            request.parentRoleId()
        );

        var location = ServletUriComponentsBuilder.fromCurrentRequest()
            .path("/{id}")
            .buildAndExpand(created.getId())
            .toUri();

        return ResponseEntity.created(location).body(RoleResponse.from(created));
    }

    @Operation(
        summary = "Update role",
        description = "Updates an existing role. Requires 'roles:write' permission (SYSTEM_ADMIN only)."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Role updated successfully",
            content = @Content(schema = @Schema(implementation = RoleResponse.class))
        ),
        @ApiResponse(
            responseCode = "400",
            description = "Invalid request data",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "Role not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('roles:write')")
    public RoleResponse updateRole(
            @Parameter(description = "Role ID", example = "MANAGER")
            @PathVariable String id,
            @RequestBody @Valid RoleRequest request) {
        return RoleResponse.from(roleService.updateRole(
            id,
            request.name(),
            request.description(),
            request.parentRoleId()
        ));
    }

    @Operation(
        summary = "Delete role",
        description = "Soft-deletes a role and cascades revocation to all assignments. Requires 'roles:delete' permission (SYSTEM_ADMIN only)."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "204",
            description = "Role deleted successfully"
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "Role not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('roles:delete')")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteRole(
            @Parameter(description = "Role ID", example = "MANAGER")
            @PathVariable String id) {
        var deletedBy = SecurityContextUtil.getCurrentUserId();
        roleService.deleteRole(id, deletedBy);
    }
}
```

#### ResourcePermissionController.java

```java
@Tag(name = "Resource Permissions", description = "Fine-grained permissions for specific resource instances")
@RestController
@RequestMapping("/v1/resource-permissions")
public class ResourcePermissionController {

    private final ResourcePermissionService resourcePermissionService;

    public ResourcePermissionController(ResourcePermissionService resourcePermissionService) {
        this.resourcePermissionService = resourcePermissionService;
    }

    @Operation(
        summary = "Grant resource-specific permission",
        description = "Grants a permission for a specific resource instance to a user. Requires admin role or ownership of the resource."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "201",
            description = "Permission granted successfully",
            content = @Content(schema = @Schema(implementation = ResourcePermissionResponse.class))
        ),
        @ApiResponse(
            responseCode = "400",
            description = "Invalid request data",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "User not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @PostMapping
    @PreAuthorize("hasAuthority('permissions:write') or @authzService.canGrantResourcePermission(authentication, #request)")
    public ResponseEntity<ResourcePermissionResponse> grantPermission(
            @RequestBody @Valid ResourcePermissionRequest request) {
        var grantedBy = SecurityContextUtil.getCurrentUserId();
        var created = resourcePermissionService.grantPermission(
            request.userId(),
            request.resourceType(),
            request.resourceId(),
            request.permission(),
            request.expiresAt(),
            request.reason(),
            grantedBy
        );

        var location = ServletUriComponentsBuilder.fromCurrentRequest()
            .path("/{id}")
            .buildAndExpand(created.getId())
            .toUri();

        return ResponseEntity.created(location).body(ResourcePermissionResponse.from(created));
    }

    @Operation(
        summary = "Revoke resource-specific permission",
        description = "Revokes a resource-specific permission. Requires admin permissions."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "204",
            description = "Permission revoked successfully"
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "Resource permission not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('permissions:write')")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revokePermission(
            @Parameter(description = "Resource permission ID", example = "456")
            @PathVariable Long id) {
        var revokedBy = SecurityContextUtil.getCurrentUserId();
        resourcePermissionService.revokePermission(id, revokedBy);
    }

    @Operation(
        summary = "Get resource permissions for user",
        description = "Returns all active resource-specific permissions for a user. User can view their own or requires admin permissions."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Permissions retrieved successfully",
            content = @Content(schema = @Schema(implementation = ResourcePermissionResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping("/user/{userId}")
    @PreAuthorize("hasAuthority('permissions:read') or #userId == authentication.name")
    public List<ResourcePermissionResponse> getUserResourcePermissions(
            @Parameter(description = "User ID", example = "usr_abc123")
            @PathVariable String userId) {
        return resourcePermissionService.getForUser(userId).stream()
            .map(ResourcePermissionResponse::from)
            .toList();
    }
}
```

#### DelegationController.java

```java
@Tag(name = "Delegations", description = "User-to-user permission delegations for shared access")
@RestController
@RequestMapping("/v1/delegations")
@PreAuthorize("isAuthenticated()")
public class DelegationController {

    private final DelegationService delegationService;

    public DelegationController(DelegationService delegationService) {
        this.delegationService = delegationService;
    }

    @Operation(
        summary = "Get user's delegations",
        description = "Returns all delegations given by and received by the authenticated user"
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Delegations retrieved successfully",
            content = @Content(schema = @Schema(implementation = DelegationsResponse.class))
        ),
        @ApiResponse(
            responseCode = "401",
            description = "Not authenticated",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping
    public DelegationsResponse getDelegations() {
        var userId = SecurityContextUtil.getCurrentUserId();
        var summary = delegationService.getDelegationsForUser(userId);

        return DelegationsResponse.from(summary);
    }

    @Operation(
        summary = "Create delegation",
        description = "Creates a new delegation to share access with another user. The authenticated user becomes the delegator."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "201",
            description = "Delegation created successfully",
            content = @Content(schema = @Schema(implementation = DelegationResponse.class))
        ),
        @ApiResponse(
            responseCode = "400",
            description = "Invalid request data",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "Delegatee not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @PostMapping
    public ResponseEntity<DelegationResponse> createDelegation(
            @RequestBody @Valid DelegationRequest request) {
        var delegatorId = SecurityContextUtil.getCurrentUserId();
        var created = delegationService.createDelegation(
            delegatorId,
            request.delegateeId(),
            request.scope(),
            request.resourceType(),
            request.resourceIds(),
            request.validUntil()
        );

        var location = ServletUriComponentsBuilder.fromCurrentRequest()
            .path("/{id}")
            .buildAndExpand(created.getId())
            .toUri();

        return ResponseEntity.created(location).body(DelegationResponse.from(created));
    }

    @Operation(
        summary = "Revoke delegation",
        description = "Revokes a delegation. Only the delegator can revoke their own delegations."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "204",
            description = "Delegation revoked successfully"
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Not authorized to revoke this delegation",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        ),
        @ApiResponse(
            responseCode = "404",
            description = "Delegation not found",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revokeDelegation(
            @Parameter(description = "Delegation ID", example = "123")
            @PathVariable Long id) {
        var revokedBy = SecurityContextUtil.getCurrentUserId();
        delegationService.revokeDelegation(id, revokedBy);
    }
}
```

#### AuditController.java

```java
@Tag(name = "Audit", description = "Authorization audit logs for compliance and investigation")
@RestController
@RequestMapping("/v1/audit")
@PreAuthorize("hasAuthority('audit:read')")
public class AuditController {

    private final AuditService auditService;

    public AuditController(AuditService auditService) {
        this.auditService = auditService;
    }

    @Operation(
        summary = "Query audit log",
        description = "Queries authorization audit logs with optional filters for user and time range. Requires 'audit:read' permission."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Audit logs retrieved successfully",
            content = @Content(schema = @Schema(implementation = AuditLogResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping
    public Page<AuditLogResponse> getAuditLog(
            @Parameter(description = "Filter by user ID", example = "usr_abc123")
            @RequestParam(required = false) String userId,
            @Parameter(description = "Start of time range (ISO-8601)", example = "2024-01-01T00:00:00Z")
            @RequestParam(required = false) Instant startTime,
            @Parameter(description = "End of time range (ISO-8601)", example = "2024-12-31T23:59:59Z")
            @RequestParam(required = false) Instant endTime,
            @ParameterObject Pageable pageable) {
        var filter = new AuditQueryFilter(userId, startTime, endTime);
        var logs = auditService.queryAuditLog(filter, pageable);

        return logs.map(AuditLogResponse::from);
    }

    @Operation(
        summary = "Get audit log for specific user",
        description = "Returns all audit log entries for a specific user. Requires 'audit:read' permission."
    )
    @ApiResponses({
        @ApiResponse(
            responseCode = "200",
            description = "Audit logs retrieved successfully",
            content = @Content(schema = @Schema(implementation = AuditLogResponse.class))
        ),
        @ApiResponse(
            responseCode = "403",
            description = "Insufficient permissions",
            content = @Content(schema = @Schema(implementation = ApiErrorResponse.class))
        )
    })
    @GetMapping("/users/{userId}")
    public Page<AuditLogResponse> getUserAudit(
            @Parameter(description = "User ID", example = "usr_abc123")
            @PathVariable String userId,
            @ParameterObject Pageable pageable) {
        var logs = auditService.queryByUser(userId, pageable);

        return logs.map(AuditLogResponse::from);
    }
}
```

---

## Phase 7: Configuration

### 7.1 application.yml

```yaml
server:
  servlet:
    context-path: /permission-service
  port: 8086

logging:
  level:
    root: WARN
    org.budgetanalyzer: TRACE

spring:
  application:
    name: permission-service

  datasource:
    url: jdbc:postgresql://localhost:5432/permission
    username: budget_analyzer
    password: budget_analyzer
    driver-class-name: org.postgresql.Driver

  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false
    database-platform: org.hibernate.dialect.PostgreSQLDialect
    properties:
      hibernate:
        default_schema: public

  flyway:
    enabled: true
    locations: classpath:db/migration
    validate-on-migrate: true

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${AUTH0_ISSUER_URI:https://dev-gcz1r8453xzz0317.us.auth0.com/}
          audiences:
            - ${AUTH0_AUDIENCE:https://api.budgetanalyzer.org}

  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}

budgetanalyzer:
  service:
    http-logging:
      enabled: true
      log-level: DEBUG
```

### 7.2 application-test.yml

```yaml
spring:
  main:
    allow-bean-definition-overriding: true

  datasource:
    url: jdbc:h2:mem:testdb;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE
    driver-class-name: org.h2.Driver
    username: sa
    password:

  jpa:
    hibernate:
      ddl-auto: validate
    database-platform: org.hibernate.dialect.H2Dialect

  flyway:
    enabled: true
    locations: classpath:db/migration

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://test-issuer.example.com/
          audiences:
            - https://test-api.example.com

  data:
    redis:
      host: localhost
      port: 6379

# Use embedded Redis for tests or mock
```

### 7.3 OpenAPI Configuration

```java
@Configuration
@OpenAPIDefinition(
    info = @Info(
        title = "Permission Service",
        version = "1.0",
        description = "Authorization management API for Budget Analyzer",
        contact = @Contact(name = "Budget Analyzer Team", email = "budgetanalyzer@proton.me"),
        license = @License(name = "MIT", url = "https://opensource.org/licenses/MIT")),
    servers = {
      @Server(url = "http://localhost:8080/api", description = "Local (via gateway)"),
      @Server(url = "http://localhost:8086/permission-service", description = "Local (direct)"),
      @Server(url = "https://api.budgetanalyzer.org", description = "Production")
    })
public class OpenApiConfig extends BaseOpenApiConfig {}
```

---

## Phase 8: Infrastructure Integration

### 8.1 Database Initialization

Add to `/workspace/orchestration/postgres-init/01-init-databases.sql`:

```sql
-- Permission Service database
CREATE DATABASE permission;
GRANT ALL PRIVILEGES ON DATABASE permission TO budget_analyzer;
```

### 8.2 Docker Compose

Add to `/workspace/orchestration/docker-compose.yml`:

```yaml
  permission-service:
    build:
      context: ../permission-service
      dockerfile: Dockerfile
    container_name: permission-service
    ports:
      - "8086:8086"
    environment:
      - SPRING_DATASOURCE_URL=jdbc:postgresql://shared-postgres:5432/permission
      - SPRING_DATASOURCE_USERNAME=budget_analyzer
      - SPRING_DATASOURCE_PASSWORD=budget_analyzer
      - SPRING_REDIS_HOST=redis
      - AUTH0_ISSUER_URI=${AUTH0_ISSUER_URI}
      - AUTH0_AUDIENCE=${AUTH0_AUDIENCE}
    depends_on:
      shared-postgres:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - gateway-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8086/permission-service/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 8.3 NGINX Configuration

Add to `/workspace/orchestration/nginx/nginx.dev.conf`:

**Upstream definition** (add with other upstreams):

```nginx
upstream permission_service {
    server host.docker.internal:8086;
}
```

**Route definitions** (add in server block):

```nginx
# Permission Service Routes

# User permissions (including /me/permissions)
location /api/v1/users {
    include includes/api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Role management (admin only - stricter rate limiting)
location /api/v1/roles {
    include includes/admin-api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Delegations
location /api/v1/delegations {
    include includes/api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Resource permissions
location /api/v1/resource-permissions {
    include includes/api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Audit logs (admin/auditor only - stricter rate limiting)
location /api/v1/audit {
    include includes/admin-api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}
```

---

## Phase 9: Testing

### 9.1 Test Configuration

Use H2 in-memory database with PostgreSQL mode and TestSecurityConfig from service-common.

### 9.2 Test Patterns and Conventions

#### Test Naming Conventions

Use camelCase for test method names (no underscores per project conventions):

```java
// CORRECT - camelCase method names
@Test
void assignRoleShouldSucceedWhenUserHasBasicAssignPermission() { }

@Test
void assignRoleShouldThrowWhenAttemptingToAssignSystemAdmin() { }

@Test
void revokeRoleShouldThrowWhenUserLacksRevokePermission() { }

// INCORRECT - underscores
@Test
void assign_role_should_succeed_when_user_has_permission() { }
```

#### TestConstants Pattern

Create a `TestConstants` class for reusable test data:

```java
public final class TestConstants {

    private TestConstants() {
        // Utility class
    }

    // User IDs
    public static final String TEST_USER_ID = "usr_test123";
    public static final String TEST_ADMIN_ID = "usr_admin456";
    public static final String TEST_MANAGER_ID = "usr_manager789";

    // Role IDs
    public static final String ROLE_USER = "USER";
    public static final String ROLE_ADMIN = "SYSTEM_ADMIN";
    public static final String ROLE_MANAGER = "MANAGER";
    public static final String ROLE_ACCOUNTANT = "ACCOUNTANT";

    // Permissions
    public static final String PERM_USERS_READ = "users:read";
    public static final String PERM_ROLES_WRITE = "roles:write";
    public static final String PERM_ASSIGN_BASIC = "user-roles:assign-basic";
    public static final String PERM_ASSIGN_ELEVATED = "user-roles:assign-elevated";

    // Auth0 test subjects
    public static final String TEST_AUTH0_SUB = "auth0|test123";
    public static final String TEST_EMAIL = "test@example.com";
}
```

#### API Error Response Contract Testing

When testing error responses, only assert on stable contract fields to avoid brittle tests:

```java
@Test
void assignRoleShouldReturnForbiddenWhenUserLacksPermission() throws Exception {
    // Arrange
    var request = new UserRoleAssignmentRequest("MANAGER", null, null);

    // Act & Assert
    mockMvc.perform(post("/v1/users/{id}/roles", TestConstants.TEST_USER_ID)
            .contentType(MediaType.APPLICATION_JSON)
            .content(objectMapper.writeValueAsString(request)))
        .andExpect(status().isForbidden())
        // Only assert on stable contract fields
        .andExpect(jsonPath("$.type").value("PERMISSION_DENIED"))
        .andExpect(jsonPath("$.status").value(403))
        // DO NOT assert on message text - it may change
        .andExpect(jsonPath("$.title").exists());
}

@Test
void createRoleShouldReturnBadRequestWhenNameIsBlank() throws Exception {
    // Arrange
    var request = new RoleRequest("", "description", null);

    // Act & Assert
    mockMvc.perform(post("/v1/roles")
            .contentType(MediaType.APPLICATION_JSON)
            .content(objectMapper.writeValueAsString(request)))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.type").value("VALIDATION_ERROR"))
        .andExpect(jsonPath("$.status").value(400))
        .andExpect(jsonPath("$.fieldErrors").isArray())
        .andExpect(jsonPath("$.fieldErrors[0].field").value("name"));
}
```

#### JwtTestBuilder Usage

Use JwtTestBuilder from service-web for testing secured endpoints:

```java
@Test
void getUserPermissionsShouldSucceedWithValidJwt() throws Exception {
    // Arrange - use JwtTestBuilder to create test JWT
    var jwt = JwtTestBuilder.create()
        .withSubject(TestConstants.TEST_USER_ID)
        .withPermissions(TestConstants.PERM_USERS_READ)
        .build();

    // Act & Assert
    mockMvc.perform(get("/v1/users/{id}/permissions", TestConstants.TEST_USER_ID)
            .with(jwt(jwt)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.permissions").isArray());
}
```

### 9.3 Test Classes

| Test Class | Purpose |
|------------|---------|
| `UserPermissionControllerTest.java` | Test permission endpoints with various auth scenarios |
| `RoleControllerTest.java` | Test role CRUD with admin authorization |
| `DelegationControllerTest.java` | Test delegation creation/revocation |
| `PermissionServiceTest.java` | Unit test permission computation |
| `DelegationServiceTest.java` | Unit test delegation logic |
| `PermissionCacheServiceTest.java` | Test cache operations |
| `UserSyncServiceTest.java` | Test Auth0 user sync |
| `CascadingRevocationServiceTest.java` | Test cascading revocation on soft delete |
| `PointInTimeQueryTest.java` | Test temporal queries |

### 9.4 Key Test Scenarios

**Permission Computation:**
1. User with multiple roles gets combined permissions
2. Delegatee can access delegated resources
3. Expired roles/delegations are not included
4. Cache is cleared when permissions change

**Role Assignment Governance (Critical):**
5. **SYSTEM_ADMIN protection**: Assigning SYSTEM_ADMIN via API throws AccessDeniedException
6. **SYSTEM_ADMIN revoke protection**: Revoking SYSTEM_ADMIN via API throws AccessDeniedException
7. **Elevated role restriction**: ORG_ADMIN cannot assign MANAGER or ORG_ADMIN (lacks `user-roles:assign-elevated`)
8. **Basic role assignment**: ORG_ADMIN can assign USER, ACCOUNTANT, AUDITOR (has `user-roles:assign-basic`)
9. **Role revocation permission**: User without `user-roles:revoke` cannot revoke roles
10. **Role CRUD restriction**: Only users with `roles:write` can create/modify roles

**Audit & Compliance:**
11. All permission changes are logged to audit table
12. Point-in-time query returns correct historical state
13. Re-granting a revoked role creates new row, preserves history

**Soft Delete:**
14. Deleting user cascades to revoke all assignments
15. Deleting role revokes UserRole and RolePermission entries
16. Deleting permission revokes RolePermission entries
17. Can reuse email/role name after soft delete (partial unique indexes)
18. Hard delete throws UnsupportedOperationException

**Authorization Enforcement:**
19. `@PreAuthorize` annotations use `hasAuthority()` not `hasRole()`
20. Custom `PermissionEvaluator` converts JWT claims to authorities
21. Endpoints return 403 when user lacks required permission

---

## Implementation Order

| Step | Task | Estimated Time |
|------|------|----------------|
| 0 | **Prerequisite**: Enhance service-common SoftDeletableEntity with `deletedBy` | 30 min |
| 1 | Repository & Gradle setup | 30 min |
| 2 | Flyway migrations (V1-V2) | 45 min |
| 3 | Domain entities (including SoftDeletable + temporal patterns) | 1.5 hours |
| 4 | Repositories (with soft delete and temporal queries) | 45 min |
| 5 | Core services (including CascadingRevocationService) | 2.5 hours |
| 6 | Controllers | 1.5 hours |
| 7 | Configuration files | 30 min |
| 8 | Infrastructure integration | 30 min |
| 9 | Tests (including soft delete and temporal scenarios) | 2.5 hours |

**Total estimated time**: ~11.5 hours

**Note**: Step 0 (service-common enhancement) must be completed first and will require:
- Updating SoftDeletableEntity.java
- Adding migration for transaction-service (V2__add_deleted_by.sql)
- Updating any existing usages of markDeleted()

---

## Files to Create (Summary)

### Source Files (~45 files)

- 1 Application class
- 8 Domain entities
- 8 Repositories
- 9 Services (PermissionService, RoleService, DelegationService, UserService, UserSyncService, AuditService, ResourcePermissionService, CascadingRevocationService, PermissionCacheService)
- 5 Controllers (UserPermissionController, RoleController, ResourcePermissionController, DelegationController, AuditController)
- 2 Config classes (OpenApiConfig, AsyncConfig)
- 3 Custom exceptions (PermissionDeniedException, ProtectedRoleException, DuplicateRoleAssignmentException)
- 1 Event class (PermissionChangeEvent)
- ~13 DTOs:
  - 6 API Response DTOs (api/response/): RoleResponse, UserPermissionsResponse, DelegationResponse, DelegationsResponse, ResourcePermissionResponse, AuditLogResponse
  - 4 API Request DTOs (api/request/): RoleRequest, UserRoleAssignmentRequest, ResourcePermissionRequest, DelegationRequest
  - 3 Service-layer DTOs (service/dto/): EffectivePermissions, DelegationsSummary, AuditQueryFilter

### Test Files (~10 files)

- TestConstants.java (reusable test data)
- 9 Test classes per section 9.3

### service-common Updates

- `SoftDeletableEntity.java` - Add `deletedBy` field

### Resource Files

- 2 Flyway migrations (V1-V2)
- 2 application.yml files (main + test)

### Infrastructure Updates

- `docker-compose.yml` - Add permission-service
- `nginx.dev.conf` - Add upstream and routes
- `01-init-databases.sql` - Add permission database

---

## Dependencies on Other Work

| Dependency | Status | Notes |
|------------|--------|-------|
| service-common authorization module | Future | For read-only evaluation in other services |
| Auth0 custom claims | Future | Phase 1.1 of main auth plan |
| Redis pub/sub for cache invalidation | In this plan | Other services will subscribe |

---

## Success Criteria

### Core Functionality
- [x] All Flyway migrations run successfully
- [x] `/api/v1/users/me/permissions` returns user's effective permissions
- [x] Role CRUD operations work correctly
- [x] Delegations can be created and revoked
- [x] All permission changes are logged to audit table
- [x] Cache is invalidated on permission changes
- [x] All tests pass
- [x] Service starts and health check passes
- [x] NGINX routes correctly to permission-service

### Role Governance (Critical for Security)
- [x] 6 default roles seeded: SYSTEM_ADMIN, ORG_ADMIN, MANAGER, ACCOUNTANT, AUDITOR, USER
- [x] Meta-permissions seeded: `roles:*`, `permissions:*`, `user-roles:assign-*`, `user-roles:revoke`
- [x] SYSTEM_ADMIN cannot be assigned/revoked via API (throws AccessDeniedException)
- [x] Only `user-roles:assign-elevated` holders can assign MANAGER/ORG_ADMIN
- [x] Only `user-roles:assign-basic` holders can assign USER/ACCOUNTANT/AUDITOR
- [x] Only `roles:write` holders can create/modify/delete roles
- [x] ORG_ADMIN has `user-roles:assign-basic` but NOT `user-roles:assign-elevated`
- [x] First SYSTEM_ADMIN created via database seed (not API)

### Conventions Compliance (service-common)
- [x] Services return entities or service-layer DTOs, never API response objects
- [x] Controllers handle all DTO transformation via `Response.from()` methods
- [x] All services use constructor injection (no field injection)
- [x] POST endpoints return 201 with Location header
- [x] Service-layer DTOs are in `service/dto/` package
- [x] API DTOs are in `api/request/` and `api/response/` packages
- [x] Temporal entities extend `AuditableEntity`
- [x] Async configuration properly documented with `@EnableAsync`
- [x] Controllers use `@PreAuthorize("hasAuthority(...)")` not `hasRole(...)`

### OpenAPI/SpringDoc Compliance
- [x] All request DTOs have `@Schema` annotations with description, example, and requiredMode
- [x] All response DTOs have `@Schema` annotations with description and example
- [x] All request DTOs have Bean Validation annotations (`@NotBlank`, `@Size`, etc.)
- [x] All controller methods have `@Operation` with summary and description
- [x] All controller methods have complete `@ApiResponses` with content schemas
- [x] All path variables and query params have `@Parameter` annotations with examples
- [x] Error responses reference `ApiErrorResponse.class` schema

### Exception Handling
- [x] Custom exceptions extend `BusinessException` from service-web
- [x] `PermissionDeniedException` used for authorization failures (403)
- [x] `ProtectedRoleException` used for SYSTEM_ADMIN protection (403)
- [x] `DuplicateRoleAssignmentException` used for duplicate assignments (422)
- [x] `ResourceNotFoundException` used for missing entities (404)
- [x] All exceptions have meaningful error codes

### Testing Compliance
- [x] Test method names use camelCase (no underscores)
- [x] `TestConstants` class created with reusable test data
- [x] Error response tests only assert on stable contract fields (type, status, title)
- [x] JwtTestBuilder used for testing secured endpoints
- [x] Tests cover all key scenarios in section 9.4

### Soft Delete & Audit Trail
- [x] User, Role, Permission entities extend SoftDeletableEntity
- [x] Hard delete throws UnsupportedOperationException for soft-deletable entities
- [x] Soft-deleting User cascades to revoke all UserRole, ResourcePermission, Delegation
- [x] Soft-deleting Role cascades to revoke all UserRole, RolePermission entries
- [x] Soft-deleting Permission cascades to revoke all RolePermission entries
- [x] `deletedBy` is recorded for all soft deletes
- [x] Partial unique indexes allow reuse of email/role name after soft delete

### Temporal Queries
- [x] Point-in-time query returns correct historical permission state
- [x] Re-granting revoked role creates new row (preserves history)
- [x] All temporal tables have `granted_at`, `granted_by`, `revoked_at`, `revoked_by`
- [x] Active queries filter by `revoked_at IS NULL`

### Prerequisites Complete
- [x] service-common `SoftDeletableEntity` enhanced with `deletedBy` field
- [x] transaction-service migration adds `deleted_by` column
