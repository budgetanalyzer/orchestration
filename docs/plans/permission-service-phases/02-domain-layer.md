# Permission Service - Phase 3: Domain Layer

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

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
