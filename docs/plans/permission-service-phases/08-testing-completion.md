# Permission Service - Phase 9: Testing & Completion

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

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
- [ ] All Flyway migrations run successfully
- [ ] `/api/v1/users/me/permissions` returns user's effective permissions
- [ ] Role CRUD operations work correctly
- [ ] Delegations can be created and revoked
- [ ] All permission changes are logged to audit table
- [ ] Cache is invalidated on permission changes
- [ ] All tests pass
- [ ] Service starts and health check passes
- [ ] NGINX routes correctly to permission-service

### Role Governance (Critical for Security)
- [ ] 6 default roles seeded: SYSTEM_ADMIN, ORG_ADMIN, MANAGER, ACCOUNTANT, AUDITOR, USER
- [ ] Meta-permissions seeded: `roles:*`, `permissions:*`, `user-roles:assign-*`, `user-roles:revoke`
- [ ] SYSTEM_ADMIN cannot be assigned/revoked via API (throws AccessDeniedException)
- [ ] Only `user-roles:assign-elevated` holders can assign MANAGER/ORG_ADMIN
- [ ] Only `user-roles:assign-basic` holders can assign USER/ACCOUNTANT/AUDITOR
- [ ] Only `roles:write` holders can create/modify/delete roles
- [ ] ORG_ADMIN has `user-roles:assign-basic` but NOT `user-roles:assign-elevated`
- [ ] First SYSTEM_ADMIN created via database seed (not API)

### Conventions Compliance (service-common)
- [ ] Services return entities or service-layer DTOs, never API response objects
- [ ] Controllers handle all DTO transformation via `Response.from()` methods
- [ ] All services use constructor injection (no field injection)
- [ ] POST endpoints return 201 with Location header
- [ ] Service-layer DTOs are in `service/dto/` package
- [ ] API DTOs are in `api/request/` and `api/response/` packages
- [ ] Temporal entities extend `AuditableEntity`
- [ ] Async configuration properly documented with `@EnableAsync`
- [ ] Controllers use `@PreAuthorize("hasAuthority(...)")` not `hasRole(...)`

### OpenAPI/SpringDoc Compliance
- [ ] All request DTOs have `@Schema` annotations with description, example, and requiredMode
- [ ] All response DTOs have `@Schema` annotations with description and example
- [ ] All request DTOs have Bean Validation annotations (`@NotBlank`, `@Size`, etc.)
- [ ] All controller methods have `@Operation` with summary and description
- [ ] All controller methods have complete `@ApiResponses` with content schemas
- [ ] All path variables and query params have `@Parameter` annotations with examples
- [ ] Error responses reference `ApiErrorResponse.class` schema

### Exception Handling
- [ ] Custom exceptions extend `BusinessException` from service-web
- [ ] `PermissionDeniedException` used for authorization failures (403)
- [ ] `ProtectedRoleException` used for SYSTEM_ADMIN protection (403)
- [ ] `DuplicateRoleAssignmentException` used for duplicate assignments (422)
- [ ] `ResourceNotFoundException` used for missing entities (404)
- [ ] All exceptions have meaningful error codes

### Testing Compliance
- [ ] Test method names use camelCase (no underscores)
- [ ] `TestConstants` class created with reusable test data
- [ ] Error response tests only assert on stable contract fields (type, status, title)
- [ ] JwtTestBuilder used for testing secured endpoints
- [ ] Tests cover all key scenarios in section 9.4

### Soft Delete & Audit Trail
- [ ] User, Role, Permission entities extend SoftDeletableEntity
- [ ] Hard delete throws UnsupportedOperationException for soft-deletable entities
- [ ] Soft-deleting User cascades to revoke all UserRole, ResourcePermission, Delegation
- [ ] Soft-deleting Role cascades to revoke all UserRole, RolePermission entries
- [ ] Soft-deleting Permission cascades to revoke all RolePermission entries
- [ ] `deletedBy` is recorded for all soft deletes
- [ ] Partial unique indexes allow reuse of email/role name after soft delete

### Temporal Queries
- [ ] Point-in-time query returns correct historical permission state
- [ ] Re-granting revoked role creates new row (preserves history)
- [ ] All temporal tables have `granted_at`, `granted_by`, `revoked_at`, `revoked_by`
- [ ] Active queries filter by `revoked_at IS NULL`

### Prerequisites Complete
- [ ] service-common `SoftDeletableEntity` enhanced with `deletedBy` field
- [ ] transaction-service migration adds `deleted_by` column
