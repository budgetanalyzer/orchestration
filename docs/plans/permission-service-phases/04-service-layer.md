# Permission Service - Phase 5: Service Layer

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

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
```

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
