# Users, Roles & Permissions Reference Implementation Plan

> **Status**: Documentation Only - Not Implemented
> **Created**: 2025-11-20
> **Goal**: Document the authorization challenge for architects adapting this reference

---

**IMPORTANT**: This plan documents the authorization architecture challenge but is **NOT implemented**. The permission-service exists and manages authorization metadata (roles, permissions, delegations), but the cross-service data ownership problem ("which transactions belong to which user?") is intentionally left as an exercise.

We're surfacing the problem, not prescribing the solution. Data ownership is domain-specific and opinionated - see [system-overview.md](../architecture/system-overview.md#intentional-boundaries) for why we stopped here.

---

## Executive Summary

This plan outlines a comprehensive authorization system for the Budget Analyzer application using a **Hybrid RBAC + ABAC** architecture. The system uses Auth0 for authentication and coarse-grained roles, the application database for fine-grained permissions, and Redis for caching.

---

## Recommended Architecture

**Core Pattern**: Auth0 (authentication + coarse roles) → Application Database (fine-grained permissions) → Redis (caching)

### Why This Architecture?

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| Auth0 Only | Simple, centralized | Limited flexibility, no audit trail, API rate limits | Not suitable for financial app |
| App Database Only | Full control, complex queries, audit trail | Must sync with Auth0, more code | Too much duplication |
| **Hybrid** | Best of both worlds | Slightly more complex | **Recommended** |

### Microservices Architecture

**Pattern**: Dedicated service for management, shared library for evaluation

```
┌─────────────────────────────────────────────────────────────┐
│                    Permission Checks (Fast Path)            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ transaction │  │  currency   │  │   budget    │         │
│  │   service   │  │   service   │  │   service   │         │
│  │ +---------+ │  │ +---------+ │  │ +---------+ │         │
│  │ | service | │  │ | service | │  │ | service | │         │
│  │ | common  | │  │ | common  | │  │ | common  | │         │
│  │ +---------+ │  │ +---------+ │  │ +---------+ │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         └────────────────┼────────────────┘                 │
│                          ▼                                  │
│                  ┌──────────────┐                           │
│                  │    Redis     │  ← L2 Cache (read-only)   │
│                  └──────────────┘                           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                Permission Management (Slow Path)            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │          permissions-service (new)                   │   │
│  │  • POST /api/permissions/* (CRUD)                    │   │
│  │  • POST /api/delegations/*                           │   │
│  │  • GET  /api/users/me/permissions                    │   │
│  │  • Admin UI endpoints                                │   │
│  │  • Cache invalidation                                │   │
│  └──────────────────┬───────────────────────────────────┘   │
│                     │                                       │
│           ┌─────────▼─────────┐                             │
│           │    PostgreSQL     │  ← Permission tables        │
│           └───────────────────┘                             │
└─────────────────────────────────────────────────────────────┘
```

**Service Responsibilities**:

| Component | Purpose | Owns Data? |
|-----------|---------|------------|
| `permissions-service` | Permission CRUD, delegations, admin, audit, cache invalidation | Yes (PostgreSQL) |
| `service-common` | Permission evaluation library (read-only checks) | No (reads Redis) |
| Business services | Use service-common for authorization checks | No |

**Why This Pattern**:
- Mirrors existing architecture (`token-validation-service` for JWT validation)
- Fast path: No network hop for permission checks (< 10ms)
- Slow path: Centralized management with proper audit trail
- Clear ownership: Only `permissions-service` writes to permission tables

### User Management Architecture

**Design Principle**: Clean separation of concerns without over-architecting.

The system splits user management across services by domain:

| Service | User Data Owned | Purpose |
|---------|-----------------|---------|
| Auth0 | Identity, credentials, MFA | Authentication - "prove who you are" |
| `permissions-service` | `users` table (id, auth0_sub, email, display_name) | Authorization subjects - "who can do what" |
| `profile-service` | Rich profile data (avatar, preferences, bio, etc.) | User profile - "who they are" [YAGNI - build when needed] |

**Why permissions-service owns the `users` table**:
- The `users` table is an **authorization subject** - the minimum needed to reference who has permissions
- Fields like `email` and `display_name` exist for audit trail readability ("granted by: John Smith")
- It's not a full user management system - it's permission infrastructure

**YAGNI for Profile Management**:
- Don't build `profile-service` until you need richer profile features
- When needed, it will own its own domain (avatars, preferences, notification settings)
- Both services share the same internal `user_id` as foreign key
- If `profile-service` later has a richer `display_name`, decide which is authoritative at that time

---

## Phase 1: Foundation (Infrastructure & Schema)

### 1.1 Auth0 Configuration

**Roles to Configure**:
- `ADMIN` - System-wide administrative access
- `ACCOUNTANT` - Can manage delegated user accounts
- `AUDITOR` - Read-only access with full visibility
- `USER` - Access to own resources only

**Auth0 Action for Custom Claims**:
```javascript
// Post-login Action
exports.onExecutePostLogin = async (event, api) => {
  const namespace = 'https://budgetanalyzer.com/claims';

  api.accessToken.setCustomClaim(`${namespace}/roles`, event.authorization?.roles || []);
  api.accessToken.setCustomClaim(`${namespace}/userId`, event.user.app_metadata?.internal_user_id);
};
```

**JWT Structure** (keep lean):
```json
{
  "sub": "auth0|abc123",
  "iss": "https://your-tenant.auth0.com/",
  "aud": ["https://api.budgetanalyzer.com"],
  "exp": 1234567890,
  "https://budgetanalyzer.com/claims": {
    "roles": ["USER"],
    "userId": "usr_internal_123"
  }
}
```

### 1.2 PostgreSQL Permission Schema

**Migration Structure:**
```
db/migration/
├── V1__initial_schema.sql      # All tables + indexes
└── V2__seed_default_data.sql   # Default roles and permissions
```

#### V1__initial_schema.sql

```sql
-- Core tables for authorization

-- Local user record linked to Auth0
CREATE TABLE users (
    id VARCHAR(50) PRIMARY KEY,
    auth0_sub VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Role definitions with hierarchy support
CREATE TABLE roles (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    parent_role_id VARCHAR(50) REFERENCES roles(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Atomic permission definitions
CREATE TABLE permissions (
    id VARCHAR(100) PRIMARY KEY,  -- e.g., 'transactions:write'
    name VARCHAR(100) NOT NULL,
    description TEXT,
    resource_type VARCHAR(50),    -- e.g., 'transaction', 'account'
    action VARCHAR(50),           -- e.g., 'read', 'write', 'delete'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Role to permission mappings
CREATE TABLE role_permissions (
    role_id VARCHAR(50) REFERENCES roles(id),
    permission_id VARCHAR(100) REFERENCES permissions(id),
    PRIMARY KEY (role_id, permission_id)
);

-- User role assignments (with organization scope for multi-tenancy)
CREATE TABLE user_roles (
    user_id VARCHAR(50) REFERENCES users(id),
    role_id VARCHAR(50) REFERENCES roles(id),
    organization_id VARCHAR(50),
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    granted_by VARCHAR(50) REFERENCES users(id),
    expires_at TIMESTAMP,
    PRIMARY KEY (user_id, role_id, COALESCE(organization_id, ''))
);

-- Instance-level permissions (user X can access account Y)
CREATE TABLE resource_permissions (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50) REFERENCES users(id),
    resource_type VARCHAR(50) NOT NULL,
    resource_id VARCHAR(100) NOT NULL,
    permission VARCHAR(50) NOT NULL,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    granted_by VARCHAR(50) REFERENCES users(id),
    expires_at TIMESTAMP,
    reason TEXT,
    UNIQUE (user_id, resource_type, resource_id, permission)
);

-- User-to-user delegation
CREATE TABLE delegations (
    id SERIAL PRIMARY KEY,
    delegator_id VARCHAR(50) REFERENCES users(id),
    delegatee_id VARCHAR(50) REFERENCES users(id),
    scope VARCHAR(50) NOT NULL,           -- 'full', 'read_only', 'transactions_only'
    resource_type VARCHAR(50),            -- NULL = all resources
    resource_ids TEXT[],                  -- Specific resource IDs
    valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMP,
    revoked_at TIMESTAMP,
    revoked_by VARCHAR(50) REFERENCES users(id),
    reason TEXT
);

-- Immutable audit log
CREATE TABLE authorization_audit_log (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_id VARCHAR(50),
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    decision VARCHAR(20) NOT NULL,        -- 'GRANTED', 'DENIED'
    reason TEXT,
    request_ip VARCHAR(45),
    user_agent TEXT,
    additional_context JSONB
);

-- Indexes for performance
CREATE INDEX idx_user_roles_user ON user_roles(user_id);
CREATE INDEX idx_resource_permissions_user ON resource_permissions(user_id);
CREATE INDEX idx_resource_permissions_resource ON resource_permissions(resource_type, resource_id);
CREATE INDEX idx_delegations_delegatee ON delegations(delegatee_id);
CREATE INDEX idx_audit_log_user ON authorization_audit_log(user_id);
CREATE INDEX idx_audit_log_timestamp ON authorization_audit_log(timestamp);
```

#### V2__seed_default_data.sql

```sql
-- Default roles
INSERT INTO roles (id, name, description) VALUES
('ADMIN', 'Administrator', 'Full system access'),
('ACCOUNTANT', 'Accountant', 'Manage delegated accounts'),
('AUDITOR', 'Auditor', 'Read-only access with full visibility'),
('USER', 'User', 'Access to own resources only');

-- Default permissions
INSERT INTO permissions (id, name, resource_type, action) VALUES
-- System permissions
('users:read', 'View users', 'user', 'read'),
('users:write', 'Create/update users', 'user', 'write'),
('users:delete', 'Delete users', 'user', 'delete'),
('audit:read', 'View audit logs', 'audit', 'read'),
('reports:export', 'Export reports', 'report', 'export'),
-- Transaction permissions
('transactions:read', 'View transactions', 'transaction', 'read'),
('transactions:write', 'Create/update transactions', 'transaction', 'write'),
('transactions:delete', 'Delete transactions', 'transaction', 'delete'),
('transactions:approve', 'Approve transactions', 'transaction', 'approve'),
('transactions:bulk', 'Bulk operations', 'transaction', 'bulk'),
-- Account permissions
('accounts:read', 'View accounts', 'account', 'read'),
('accounts:write', 'Create/update accounts', 'account', 'write'),
('accounts:delete', 'Delete accounts', 'account', 'delete'),
('accounts:delegate', 'Delegate access', 'account', 'delegate'),
-- Budget permissions
('budgets:read', 'View budgets', 'budget', 'read'),
('budgets:write', 'Create/update budgets', 'budget', 'write'),
('budgets:delete', 'Delete budgets', 'budget', 'delete');

-- ADMIN gets all permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'ADMIN', id FROM permissions;

-- ACCOUNTANT permissions
INSERT INTO role_permissions (role_id, permission_id) VALUES
('ACCOUNTANT', 'transactions:read'),
('ACCOUNTANT', 'transactions:write'),
('ACCOUNTANT', 'transactions:approve'),
('ACCOUNTANT', 'accounts:read'),
('ACCOUNTANT', 'reports:export');

-- AUDITOR permissions (read-only)
INSERT INTO role_permissions (role_id, permission_id) VALUES
('AUDITOR', 'transactions:read'),
('AUDITOR', 'accounts:read'),
('AUDITOR', 'budgets:read'),
('AUDITOR', 'audit:read'),
('AUDITOR', 'reports:export');

-- USER permissions (own resources)
INSERT INTO role_permissions (role_id, permission_id) VALUES
('USER', 'transactions:read'),
('USER', 'transactions:write'),
('USER', 'transactions:delete'),
('USER', 'accounts:read'),
('USER', 'accounts:write'),
('USER', 'accounts:delegate'),
('USER', 'budgets:read'),
('USER', 'budgets:write');
```

### 1.3 service-common Authorization Module

Create a shared authorization library in `service-common` repository for **read-only permission evaluation**:

> **Note**: This module only evaluates permissions. All permission management (CRUD, delegations, cache invalidation) is handled by `permissions-service`.

**Package Structure**:
```
com.budgetanalyzer.common.security/
├── config/
│   └── AuthorizationConfig.java
├── jwt/
│   ├── JwtClaimsExtractor.java
│   └── BudgetAnalyzerJwtConverter.java
├── permission/
│   ├── PermissionEvaluator.java
│   ├── PermissionService.java        # Read-only evaluation
│   └── PermissionCacheService.java   # L1 (Caffeine) + L2 (Redis) reads
├── audit/
│   ├── AuthorizationAuditAspect.java
│   └── AuditEvent.java
└── model/
    ├── UserPrincipal.java
    └── Permission.java
```

### 1.4 permissions-service Microservice

Create a new microservice to own all permission data and management:

**Repository**: `https://github.com/budgetanalyzer/permissions-service`

**Responsibilities**:
- Own PostgreSQL permission tables (users, roles, permissions, delegations, audit_log)
- Provide REST API for permission management
- Handle cache invalidation (publish events to Redis pub/sub)
- Serve frontend permission requests (`/api/users/me/permissions`)

**API Endpoints**:
```
# User Permissions (Frontend calls these)
GET  /api/users/me/permissions              → Current user's effective permissions
GET  /api/users/{id}/permissions            → Admin: view user's permissions

# Role Management (Admin only)
GET  /api/roles                             → List all roles
POST /api/roles                             → Create role
PUT  /api/roles/{id}                        → Update role
DELETE /api/roles/{id}                      → Delete role

# Role Assignments
GET  /api/users/{id}/roles                  → Get user's roles
POST /api/users/{id}/roles                  → Assign role to user
DELETE /api/users/{id}/roles/{roleId}       → Revoke role from user

# Resource Permissions
POST /api/resource-permissions              → Grant resource-specific permission
DELETE /api/resource-permissions/{id}       → Revoke resource permission

# Delegations
GET  /api/delegations                       → List user's delegations (given/received)
POST /api/delegations                       → Create delegation
DELETE /api/delegations/{id}                → Revoke delegation

# Audit
GET  /api/audit/permissions                 → Query permission audit log
GET  /api/audit/access                      → Query access decision audit log
```

**Docker Compose Addition**:
```yaml
permissions-service:
  build:
    context: ../permissions-service
  ports:
    - "8086:8086"
  environment:
    - SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/budgetanalyzer
    - SPRING_REDIS_HOST=redis
  depends_on:
    - postgres
    - redis
```

**NGINX Route** (in `nginx/nginx.dev.conf`):
```nginx
location /api/users {
    auth_request /auth/validate;
    proxy_pass http://permissions-service:8086;
}

location /api/roles {
    auth_request /auth/validate;
    proxy_pass http://permissions-service:8086;
}

location /api/delegations {
    auth_request /auth/validate;
    proxy_pass http://permissions-service:8086;
}

location /api/resource-permissions {
    auth_request /auth/validate;
    proxy_pass http://permissions-service:8086;
}

location /api/audit {
    auth_request /auth/validate;
    proxy_pass http://permissions-service:8086;
}
```

---

## Phase 2: Backend Authorization (Spring Security)

### 2.1 Security Configuration

```java
@Configuration
@EnableMethodSecurity(prePostEnabled = true)
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt
                    .jwtAuthenticationConverter(jwtAuthenticationConverter())
                )
            )
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health").permitAll()
                .anyRequest().authenticated()
            );
        return http.build();
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        BudgetAnalyzerJwtConverter converter = new BudgetAnalyzerJwtConverter();
        JwtAuthenticationConverter jwtConverter = new JwtAuthenticationConverter();
        jwtConverter.setJwtGrantedAuthoritiesConverter(converter);
        return jwtConverter;
    }

    @Bean
    public PermissionEvaluator permissionEvaluator(PermissionService permissionService) {
        return new BudgetAnalyzerPermissionEvaluator(permissionService);
    }
}
```

### 2.2 JWT Claims Converter

```java
public class BudgetAnalyzerJwtConverter implements Converter<Jwt, Collection<GrantedAuthority>> {

    private static final String CLAIMS_NAMESPACE = "https://budgetanalyzer.com/claims";

    @Override
    public Collection<GrantedAuthority> convert(Jwt jwt) {
        Collection<GrantedAuthority> authorities = new ArrayList<>();

        // Extract roles from custom claims
        Map<String, Object> claims = jwt.getClaimAsMap(CLAIMS_NAMESPACE);
        if (claims != null) {
            List<String> roles = (List<String>) claims.get("roles");
            if (roles != null) {
                roles.forEach(role ->
                    authorities.add(new SimpleGrantedAuthority("ROLE_" + role))
                );
            }
        }

        return authorities;
    }
}
```

### 2.3 Custom Permission Evaluator

```java
@Component
public class BudgetAnalyzerPermissionEvaluator implements PermissionEvaluator {

    private final PermissionService permissionService;

    @Override
    public boolean hasPermission(Authentication auth, Object targetDomainObject, Object permission) {
        if (auth == null || targetDomainObject == null || !(permission instanceof String)) {
            return false;
        }

        String userId = extractUserId(auth);
        String permissionStr = (String) permission;

        // Fast path: check if user is admin
        if (hasRole(auth, "ADMIN")) {
            return true;
        }

        // Check ownership for domain objects
        if (targetDomainObject instanceof OwnedResource) {
            OwnedResource resource = (OwnedResource) targetDomainObject;
            if (resource.getOwnerId().equals(userId)) {
                return permissionService.hasPermission(userId, permissionStr);
            }
        }

        // Check delegated access
        return permissionService.hasDelegatedAccess(userId, targetDomainObject, permissionStr);
    }

    @Override
    public boolean hasPermission(Authentication auth, Serializable targetId,
                                  String targetType, Object permission) {
        String userId = extractUserId(auth);

        // Check resource-specific permission
        return permissionService.hasResourcePermission(
            userId, targetType, targetId.toString(), (String) permission
        );
    }
}
```

### 2.4 Authorization Patterns

**Pattern 1: Role-based (coarse-grained)**
```java
@PreAuthorize("hasRole('ADMIN')")
public void deleteUser(String userId) {
    // Only admins can delete users
}
```

**Pattern 2: Permission-based (medium-grained)**
```java
@PreAuthorize("hasAuthority('transactions:write')")
public Transaction createTransaction(TransactionDTO dto) {
    // Users with transactions:write permission
}
```

**Pattern 3: Resource ownership (fine-grained)**
```java
@PreAuthorize("hasPermission(#transactionId, 'Transaction', 'read')")
public Transaction getTransaction(Long transactionId) {
    // Checks if user owns or has delegated access to this transaction
}

@PostAuthorize("hasPermission(returnObject, 'read')")
public Transaction findTransaction(Long id) {
    // Check permission after loading the object
}
```

**Pattern 4: Custom authorization service**
```java
@PreAuthorize("@authzService.canAccessAccount(authentication, #accountId)")
public Account getAccount(Long accountId) {
    // Complex authorization logic in dedicated service
}
```

**Pattern 5: Filtering collections**
```java
@PostFilter("hasPermission(filterObject, 'read')")
public List<Transaction> getAllTransactions() {
    // Filter results based on permissions
}
```

### 2.5 Permission Caching Service

```java
@Service
public class PermissionCacheService {

    private final RedisTemplate<String, Set<String>> redisTemplate;
    private final PermissionRepository permissionRepository;

    // L1 Cache: Local Caffeine
    private final LoadingCache<String, Set<String>> localCache = Caffeine.newBuilder()
        .maximumSize(10_000)
        .expireAfterWrite(1, TimeUnit.MINUTES)
        .build(this::loadFromRedis);

    public Set<String> getUserPermissions(String userId) {
        return localCache.get(userId);
    }

    private Set<String> loadFromRedis(String userId) {
        String key = "permissions:" + userId;
        Set<String> permissions = redisTemplate.opsForSet().members(key);

        if (permissions == null || permissions.isEmpty()) {
            // Compute from database
            permissions = computeEffectivePermissions(userId);

            // Store in Redis (L2 cache)
            if (!permissions.isEmpty()) {
                redisTemplate.opsForSet().add(key, permissions.toArray(new String[0]));
                redisTemplate.expire(key, 5, TimeUnit.MINUTES);
            }
        }

        return permissions;
    }

    private Set<String> computeEffectivePermissions(String userId) {
        Set<String> permissions = new HashSet<>();

        // Get role-based permissions
        permissions.addAll(permissionRepository.findPermissionsByUserId(userId));

        // Get resource-specific permissions
        permissions.addAll(permissionRepository.findResourcePermissionsByUserId(userId));

        // Get delegated permissions
        permissions.addAll(permissionRepository.findDelegatedPermissionsByUserId(userId));

        return permissions;
    }

    @CacheEvict(allEntries = true)
    public void invalidateUserPermissions(String userId) {
        localCache.invalidate(userId);
        redisTemplate.delete("permissions:" + userId);
    }

    // Call this when any permission changes
    public void onPermissionChange(String userId) {
        invalidateUserPermissions(userId);
        // Optionally publish event for other service instances
    }
}
```

---

## Phase 3: Frontend Authorization (React + CASL)

### 3.1 Install Dependencies

```bash
npm install @casl/ability @casl/react
```

### 3.2 Define Abilities

```typescript
// src/auth/ability.ts
import { defineAbility, AbilityBuilder, Ability } from '@casl/ability';

export type Actions = 'create' | 'read' | 'update' | 'delete' | 'manage';
export type Subjects = 'Transaction' | 'Account' | 'Budget' | 'Report' | 'User' | 'all';

export type AppAbility = Ability<[Actions, Subjects]>;

export interface UserPermissions {
  roles: string[];
  permissions: string[];
  userId: string;
}

export function defineAbilitiesFor(user: UserPermissions): AppAbility {
  const { can, cannot, build } = new AbilityBuilder<AppAbility>(Ability);

  // Admin can do everything
  if (user.roles.includes('ADMIN')) {
    can('manage', 'all');
    return build();
  }

  // Auditor has read-only access to everything
  if (user.roles.includes('AUDITOR')) {
    can('read', 'all');
    return build();
  }

  // Map permissions to abilities
  user.permissions.forEach(permission => {
    const [resource, action] = permission.split(':');
    const subject = capitalizeFirst(resource) as Subjects;

    switch (action) {
      case 'read':
        can('read', subject);
        break;
      case 'write':
        can('create', subject);
        can('update', subject);
        break;
      case 'delete':
        can('delete', subject);
        break;
    }
  });

  // Users can always manage their own resources
  if (user.roles.includes('USER')) {
    can('read', 'Transaction', { userId: user.userId });
    can('update', 'Transaction', { userId: user.userId });
    can('delete', 'Transaction', { userId: user.userId });
    can('read', 'Account', { userId: user.userId });
    can('update', 'Account', { userId: user.userId });
  }

  return build();
}

function capitalizeFirst(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}
```

### 3.3 Ability Context Provider

```typescript
// src/auth/AbilityContext.tsx
import React, { createContext, useContext, useEffect, useState } from 'react';
import { createContextualCan } from '@casl/react';
import { AppAbility, defineAbilitiesFor, UserPermissions } from './ability';
import { useAuth } from './useAuth';
import { fetchUserPermissions } from '../api/permissions';

const AbilityContext = createContext<AppAbility>(undefined!);

export const Can = createContextualCan(AbilityContext.Consumer);

export function AbilityProvider({ children }: { children: React.ReactNode }) {
  const { user, isAuthenticated } = useAuth();
  const [ability, setAbility] = useState<AppAbility>(() =>
    defineAbilitiesFor({ roles: [], permissions: [], userId: '' })
  );

  useEffect(() => {
    if (isAuthenticated && user) {
      fetchUserPermissions().then((permissions: UserPermissions) => {
        setAbility(defineAbilitiesFor(permissions));
      });
    }
  }, [isAuthenticated, user]);

  return (
    <AbilityContext.Provider value={ability}>
      {children}
    </AbilityContext.Provider>
  );
}

export function useAbility() {
  return useContext(AbilityContext);
}
```

### 3.4 Permission-Based Component Rendering

```typescript
// src/components/TransactionList.tsx
import { Can } from '../auth/AbilityContext';

export function TransactionList() {
  return (
    <div>
      <h1>Transactions</h1>

      <Can I="create" a="Transaction">
        <button onClick={handleCreate}>New Transaction</button>
      </Can>

      <TransactionTable />

      <Can I="delete" a="Transaction">
        <button onClick={handleBulkDelete}>Delete Selected</button>
      </Can>
    </div>
  );
}

// Programmatic check
export function TransactionRow({ transaction }) {
  const ability = useAbility();

  return (
    <tr>
      <td>{transaction.description}</td>
      <td>{transaction.amount}</td>
      <td>
        {ability.can('update', 'Transaction') && (
          <button onClick={() => handleEdit(transaction)}>Edit</button>
        )}
      </td>
    </tr>
  );
}
```

### 3.5 Protected Routes

```typescript
// src/components/ProtectedRoute.tsx
import { Navigate } from 'react-router-dom';
import { useAbility } from '../auth/AbilityContext';
import { Actions, Subjects } from '../auth/ability';

interface ProtectedRouteProps {
  action: Actions;
  subject: Subjects;
  children: React.ReactNode;
}

export function ProtectedRoute({ action, subject, children }: ProtectedRouteProps) {
  const ability = useAbility();

  if (ability.can(action, subject)) {
    return <>{children}</>;
  }

  return <Navigate to="/unauthorized" replace />;
}

// Usage in router
<Route
  path="/admin/users"
  element={
    <ProtectedRoute action="manage" subject="User">
      <UserManagement />
    </ProtectedRoute>
  }
/>
```

### 3.6 Permission API Endpoint

This endpoint lives in `permissions-service` (not in business services):

```java
// permissions-service: src/main/java/.../controller/UserPermissionController.java
@RestController
@RequestMapping("/api/users")
public class UserPermissionController {

    @Autowired
    private PermissionService permissionService;

    @GetMapping("/me/permissions")
    public UserPermissionsDTO getCurrentUserPermissions(Authentication auth) {
        String userId = extractUserId(auth);

        return UserPermissionsDTO.builder()
            .userId(userId)
            .roles(extractRoles(auth))
            .permissions(permissionService.getEffectivePermissions(userId))
            .build();
    }

    @GetMapping("/{id}/permissions")
    @PreAuthorize("hasRole('ADMIN')")
    public UserPermissionsDTO getUserPermissions(@PathVariable String id) {
        return UserPermissionsDTO.builder()
            .userId(id)
            .roles(permissionService.getUserRoles(id))
            .permissions(permissionService.getEffectivePermissions(id))
            .build();
    }
}
```

**Frontend fetches from**: `GET https://api.budgetanalyzer.localhost/api/users/me/permissions`

---

## Phase 4: User Types & Permission Model

### 4.1 Role Hierarchy

```
SYSTEM_ADMIN (platform-level, all access)
└── ORGANIZATION_ADMIN (tenant-scoped administration)
    ├── ACCOUNTANT (manage delegated accounts)
    │   ├── Can view/edit delegated user transactions
    │   ├── Can approve transactions under limits
    │   └── Can generate reports for managed users
    ├── AUDITOR (read-only, full visibility)
    │   ├── Can view all transactions
    │   ├── Can view audit logs
    │   └── Cannot modify any data
    └── USER (own resources only)
        ├── Can manage own transactions
        ├── Can manage own accounts
        ├── Can delegate access to accountants
        └── Can view own reports
```

### 4.2 Permission Definitions

**System Permissions**:
- `users:read` - View user list
- `users:write` - Create/update users
- `users:delete` - Delete users
- `audit:read` - View audit logs
- `reports:export` - Export reports to file

**Transaction Permissions**:
- `transactions:read` - View transactions
- `transactions:write` - Create/update transactions
- `transactions:delete` - Delete transactions
- `transactions:approve` - Approve pending transactions
- `transactions:bulk` - Bulk operations

**Account Permissions**:
- `accounts:read` - View accounts
- `accounts:write` - Create/update accounts
- `accounts:delete` - Delete accounts
- `accounts:delegate` - Delegate access to others

**Budget Permissions**:
- `budgets:read` - View budgets
- `budgets:write` - Create/update budgets
- `budgets:delete` - Delete budgets

### 4.3 Default Role Permissions

> **Implementation**: See `V2__seed_default_data.sql` in [Section 1.2](#12-postgresql-permission-schema)

**Summary of role-permission mappings:**

| Role | Permissions |
|------|-------------|
| ADMIN | All permissions (dynamic SELECT from permissions table) |
| ACCOUNTANT | `transactions:read`, `transactions:write`, `transactions:approve`, `accounts:read`, `reports:export` |
| AUDITOR | `transactions:read`, `accounts:read`, `budgets:read`, `audit:read`, `reports:export` |
| USER | `transactions:read/write/delete`, `accounts:read/write/delegate`, `budgets:read/write` |

### 4.4 Delegation Model

```java
@Service
public class DelegationService {

    public void createDelegation(DelegationRequest request) {
        // Validate delegator owns the resources
        // Validate delegatee exists and can receive delegation
        // Create delegation with time bounds
        // Invalidate permission caches
        // Log to audit trail
    }

    public boolean hasDelegatedAccess(String delegateeId, String resourceType,
                                       String resourceId, String permission) {
        // Check if there's an active delegation
        // Verify delegation scope includes the permission
        // Verify delegation includes the resource
        return delegationRepository.findActiveDelegation(
            delegateeId, resourceType, resourceId, permission
        ).isPresent();
    }

    public void revokeDelegation(String delegationId, String revokedBy) {
        // Mark delegation as revoked
        // Invalidate permission caches
        // Log to audit trail
    }
}
```

---

## Phase 5: Audit & Compliance

### 5.1 Authorization Audit Aspect

```java
@Aspect
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class AuthorizationAuditAspect {

    private final AuditService auditService;

    @Around("@annotation(org.springframework.security.access.prepost.PreAuthorize)")
    public Object auditAuthorizationDecision(ProceedingJoinPoint joinPoint) throws Throwable {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        String userId = extractUserId(auth);

        AuditEvent event = AuditEvent.builder()
            .userId(userId)
            .action(joinPoint.getSignature().toShortString())
            .timestamp(Instant.now())
            .requestIp(getRequestIp())
            .build();

        try {
            Object result = joinPoint.proceed();
            event.setDecision("GRANTED");

            // Extract resource info from result if available
            if (result instanceof OwnedResource) {
                event.setResourceType(result.getClass().getSimpleName());
                event.setResourceId(((OwnedResource) result).getId());
            }

            return result;
        } catch (AccessDeniedException e) {
            event.setDecision("DENIED");
            event.setReason(e.getMessage());
            throw e;
        } finally {
            auditService.logAsync(event);
        }
    }
}
```

### 5.2 Permission Change Auditing

```java
@Service
public class PermissionAuditService {

    @Transactional
    public void logRoleAssignment(String userId, String roleId, String grantedBy) {
        AuditEvent event = AuditEvent.builder()
            .action("ROLE_ASSIGNED")
            .userId(userId)
            .additionalContext(Map.of(
                "roleId", roleId,
                "grantedBy", grantedBy
            ))
            .build();

        auditRepository.save(event);
    }

    @Transactional
    public void logDelegationCreated(Delegation delegation) {
        AuditEvent event = AuditEvent.builder()
            .action("DELEGATION_CREATED")
            .userId(delegation.getDelegateeId())
            .additionalContext(Map.of(
                "delegatorId", delegation.getDelegatorId(),
                "scope", delegation.getScope(),
                "validUntil", delegation.getValidUntil()
            ))
            .build();

        auditRepository.save(event);
    }
}
```

### 5.3 Compliance Queries

```sql
-- Find all permission changes for a user in date range
SELECT * FROM authorization_audit_log
WHERE user_id = ?
  AND action IN ('ROLE_ASSIGNED', 'ROLE_REVOKED', 'DELEGATION_CREATED', 'DELEGATION_REVOKED')
  AND timestamp BETWEEN ? AND ?
ORDER BY timestamp DESC;

-- Find all denied access attempts
SELECT * FROM authorization_audit_log
WHERE decision = 'DENIED'
  AND timestamp > NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC;

-- Find users with specific permission
SELECT DISTINCT u.id, u.email
FROM users u
JOIN user_roles ur ON u.id = ur.user_id
JOIN role_permissions rp ON ur.role_id = rp.role_id
WHERE rp.permission_id = 'transactions:approve';
```

---

## Phase 6: Testing & Documentation

### 6.1 Security Test Cases

```java
@SpringBootTest
@AutoConfigureMockMvc
class AuthorizationSecurityTest {

    @Test
    @WithMockUser(roles = "USER")
    void userCannotAccessOtherUsersTransaction() {
        // Attempt to access transaction owned by another user
        mockMvc.perform(get("/api/transactions/{id}", otherUserTransactionId))
            .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void adminCanAccessAnyTransaction() {
        mockMvc.perform(get("/api/transactions/{id}", anyTransactionId))
            .andExpect(status().isOk());
    }

    @Test
    void delegateeCanAccessDelegatedResources() {
        // Create delegation
        // Verify delegatee can access
        // Revoke delegation
        // Verify delegatee cannot access
    }

    @Test
    void permissionCacheIsInvalidatedOnChange() {
        // Check permission (should cache)
        // Change permission
        // Check permission again (should reflect change)
    }
}
```

### 6.2 Performance Benchmarks

**Targets**:
- Authorization check (cached): < 10ms
- Authorization check (cold): < 100ms
- Permission computation: < 200ms
- Cache hit ratio: > 95%

```java
@Test
void authorizationCheckLatency() {
    // Warm up cache
    permissionService.getUserPermissions(userId);

    long start = System.nanoTime();
    for (int i = 0; i < 1000; i++) {
        permissionService.hasPermission(userId, "transactions:read");
    }
    long elapsed = System.nanoTime() - start;

    double avgMs = (elapsed / 1000.0) / 1_000_000.0;
    assertThat(avgMs).isLessThan(10.0);
}
```

---

## Implementation Timeline

| Week | Phase | Deliverables |
|------|-------|--------------|
| 1-2 | Foundation | Auth0 config, PostgreSQL schema, service-common authorization module |
| 3-4 | permissions-service | New microservice: REST API, permission management, cache invalidation |
| 5 | Backend Integration | Spring Security integration in transaction-service (reference implementation) |
| 6 | Frontend | React CASL integration, AbilityContext, protected routes |
| 7 | Permission Model | Complete permission definitions, delegation system |
| 8 | Audit | Audit logging, compliance queries, monitoring |
| 9 | Testing & Docs | Security tests, performance benchmarks, documentation |

---

## Key Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Permission storage | Hybrid (Auth0 + App DB) | Flexibility for fine-grained control while leveraging Auth0 |
| Microservices pattern | Dedicated permissions-service + shared library | Centralized management, fast distributed evaluation |
| User management | Auth0 + permissions-service (YAGNI for profile-service) | Clean separation: Auth0 for identity, permissions-service for authorization subjects, profile-service only when needed |
| Frontend library | CASL | Lightweight (6KB), isomorphic, TypeScript support |
| Caching | Caffeine L1 + Redis L2 | Low latency with distributed consistency |
| Granularity | Three-level | Balances security with maintainability |
| Audit | Comprehensive logging | Financial compliance requirements |
| Token claims | Minimal (roles + userId only) | Keep JWT small, compute permissions server-side |

---

## Anti-Patterns to Avoid

### Security
- Never trust frontend permission checks alone (always verify server-side)
- Don't store sensitive data in JWT
- Don't hardcode role checks (use configurable permissions)
- Don't allow implicit permission inheritance without explicit configuration

### Performance
- Don't check permissions in loops (batch them)
- Don't skip caching for permission lookups
- Don't compute all permissions upfront (lazy load)

### Maintenance
- Avoid role explosion (keep under 20 roles)
- Don't embed authorization in business logic (separate concerns)
- Don't skip permission model versioning
- Always document permission rules

---

## Deliverables Checklist

- [ ] Auth0 tenant configuration with roles and Actions
- [ ] PostgreSQL migration scripts for permission schema
- [ ] `service-common` authorization module (read-only evaluation)
  - [ ] JWT claims extractor
  - [ ] Custom PermissionEvaluator
  - [ ] Permission caching service (L1 Caffeine + L2 Redis reads)
  - [ ] Audit logging aspect
- [ ] `permissions-service` microservice (new repository)
  - [ ] Repository setup from basic-repository-template
  - [ ] REST API for permission management
  - [ ] Role assignment endpoints
  - [ ] Delegation endpoints
  - [ ] Resource permission endpoints
  - [ ] Audit query endpoints
  - [ ] `/api/users/me/permissions` endpoint
  - [ ] Cache invalidation (Redis pub/sub)
  - [ ] Docker Compose integration
  - [ ] NGINX routing configuration
- [ ] Reference implementation in `transaction-service`
  - [ ] Security configuration
  - [ ] Protected endpoints with all patterns
- [ ] React authorization setup in `budget-analyzer-web`
  - [ ] CASL ability definitions
  - [ ] AbilityContext provider
  - [ ] Can component usage
  - [ ] Protected routes
- [ ] Comprehensive test suite
- [ ] Performance benchmarks
- [ ] Architecture documentation
- [ ] Runbook for permission management

---

## Next Steps

1. Review and approve this plan
2. Create Jira/GitHub issues for each phase
3. Begin Phase 1: Foundation setup
