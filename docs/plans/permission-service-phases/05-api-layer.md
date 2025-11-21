# Permission Service - Phase 6: API Layer (Controllers)

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

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
