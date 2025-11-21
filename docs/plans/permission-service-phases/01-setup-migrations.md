# Permission Service - Phase 1 & 2: Setup and Migrations

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

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
