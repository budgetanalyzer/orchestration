# Permission Service - Phase 4: Repository Layer

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

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
