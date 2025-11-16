# Add-On: PostgreSQL + Flyway

## Purpose
Database persistence with schema migration management. PostgreSQL provides robust relational
database capabilities, and Flyway handles version-controlled database migrations.

## Use Cases
- Persistent data storage
- Relational data modeling
- Database schema versioning
- Migration management across environments
- Audit trailing with timestamps
- Soft-delete patterns

## Benefits
- **Version Control**: Database schema changes tracked in migration files
- **Reproducibility**: Same migrations produce identical schema across environments
- **Rollback Safety**: Migrations are immutable and ordered
- **Team Coordination**: No manual schema changes, everything in code
- **Production-Ready**: Proven technology stack
- **Base Entity Classes**: Leverage service-common for auditing and soft-deletes

## Dependencies

### Step 1: Add to `gradle/libs.versions.toml`

```toml
[versions]
postgresql = "42.7.4"

[libraries]
# Add to existing libraries section
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-validation = { module = "org.springframework.boot:spring-boot-starter-validation" }
flyway-core = { module = "org.flywaydb:flyway-core" }
flyway-database-postgresql = { module = "org.flywaydb:flyway-database-postgresql" }
postgresql = { module = "org.postgresql:postgresql", version.ref = "postgresql" }
h2 = { module = "com.h2database:h2" }
```

### Step 2: Add to `build.gradle.kts`

```kotlin
dependencies {
    // ... existing dependencies

    // PostgreSQL + Flyway
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.flyway.core)
    implementation(libs.flyway.database.postgresql)
    runtimeOnly(libs.postgresql)

    // H2 for in-memory testing (optional, TestContainers recommended)
    testImplementation(libs.h2)
}
```

## Configuration

### application.yml

```yaml
spring:
  application:
    name: {SERVICE_NAME}

  datasource:
    url: jdbc:postgresql://localhost:5432/{DATABASE_NAME}
    username: ${DB_USERNAME:budget_analyzer}
    password: ${DB_PASSWORD:budget_analyzer}
    driver-class-name: org.postgresql.Driver

  jpa:
    hibernate:
      ddl-auto: validate  # Flyway manages schema, Hibernate only validates
    open-in-view: false   # Prevent lazy-loading in controllers
    show-sql: false       # Set to true for debugging
    properties:
      hibernate:
        format_sql: true
        dialect: org.hibernate.dialect.PostgreSQLDialect
        jdbc:
          batch_size: 20  # Batch inserts/updates for performance

  flyway:
    enabled: true
    locations: classpath:db/migration
    validate-on-migrate: true
    baseline-on-migrate: false
    out-of-order: false
```

### Test Configuration (src/test/resources/application.yml)

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/test_{DATABASE_NAME}
    # Or use H2 for fast in-memory tests:
    # url: jdbc:h2:mem:testdb;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE
    # driver-class-name: org.h2.Driver

  jpa:
    hibernate:
      ddl-auto: create-drop  # Recreate schema for each test
    show-sql: true

  flyway:
    enabled: false  # Disable for unit tests, enable for integration tests

logging:
  level:
    org.budgetanalyzer: DEBUG
    org.hibernate.SQL: DEBUG
```

## Directory Structure

```
src/main/resources/
└── db/
    └── migration/
        ├── V1__initial_schema.sql
        ├── V2__add_user_table.sql
        ├── V3__add_indexes.sql
        └── ...
```

## Migration Naming Convention

```
V{version}__{description}.sql

Examples:
V1__initial_schema.sql
V2__add_user_table.sql
V3__add_user_email_index.sql
V4__alter_user_add_status.sql
V5__seed_initial_data.sql
```

**Rules:**
- Start with `V` (uppercase)
- Version number (can be dotted: `V1.1`, `V2.0.1`)
- Double underscore `__`
- Description (use underscores for spaces)
- `.sql` extension

## Using Service-Common Base Entity Classes

Service-common provides base entity classes for common patterns.

### AuditableEntity

Automatically tracks creation and modification timestamps.

```java
package org.budgetanalyzer.common.domain;

import jakarta.persistence.Column;
import jakarta.persistence.EntityListeners;
import jakarta.persistence.MappedSuperclass;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.Instant;

@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
public abstract class AuditableEntity {

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    // Getters and setters
}
```

**Usage:**

```java
package org.budgetanalyzer.{DOMAIN_NAME}.domain;

import jakarta.persistence.*;
import org.budgetanalyzer.common.domain.AuditableEntity;

@Entity
@Table(name = "transactions")
public class Transaction extends AuditableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String description;

    // createdAt and updatedAt inherited from AuditableEntity
    // Automatically populated by JPA

    // Getters and setters
}
```

**Enable JPA Auditing:**

```java
package org.budgetanalyzer.{DOMAIN_NAME}.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@Configuration
@EnableJpaAuditing
public class JpaConfig {
}
```

### SoftDeletableEntity

Extends AuditableEntity with soft-delete support.

```java
package org.budgetanalyzer.common.domain;

import jakarta.persistence.Column;
import jakarta.persistence.MappedSuperclass;

import java.time.Instant;

@MappedSuperclass
public abstract class SoftDeletableEntity extends AuditableEntity {

    @Column(name = "deleted", nullable = false)
    private Boolean deleted = false;

    @Column(name = "deleted_at")
    private Instant deletedAt;

    public void softDelete() {
        this.deleted = true;
        this.deletedAt = Instant.now();
    }

    public void restore() {
        this.deleted = false;
        this.deletedAt = null;
    }

    // Getters and setters
}
```

**Usage:**

```java
@Entity
@Table(name = "users")
public class User extends SoftDeletableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String username;

    // deleted, deletedAt, createdAt, updatedAt all inherited

    // Getters and setters
}
```

**Repository with Soft-Delete Support:**

```java
package org.budgetanalyzer.{DOMAIN_NAME}.repository;

import org.budgetanalyzer.common.repository.SoftDeleteOperations;
import org.budgetanalyzer.{DOMAIN_NAME}.domain.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserRepository extends JpaRepository<User, Long>,
                                         SoftDeleteOperations<User> {

    // Find only non-deleted users
    @Query("SELECT u FROM User u WHERE u.deleted = false")
    List<User> findAllActive();

    // Find by ID, only if not deleted
    @Query("SELECT u FROM User u WHERE u.id = :id AND u.deleted = false")
    Optional<User> findByIdActive(Long id);

    // Custom queries automatically exclude deleted if using default methods
    List<User> findByUsernameAndDeletedFalse(String username);
}
```

**SoftDeleteOperations Interface** (from service-common):

```java
package org.budgetanalyzer.common.repository;

import org.budgetanalyzer.common.domain.SoftDeletableEntity;

public interface SoftDeleteOperations<T extends SoftDeletableEntity> {

    default void softDelete(T entity) {
        entity.softDelete();
    }

    default void restore(T entity) {
        entity.restore();
    }
}
```

## Migration Templates

### Initial Schema with Auditable Columns

```sql
-- V1__initial_schema.sql

CREATE TABLE transactions (
    id BIGSERIAL PRIMARY KEY,

    -- Business columns
    description VARCHAR(500) NOT NULL,
    amount DECIMAL(15, 2) NOT NULL,
    transaction_date DATE NOT NULL,

    -- Audit columns (from AuditableEntity)
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX idx_transactions_date ON transactions(transaction_date);
CREATE INDEX idx_transactions_created_at ON transactions(created_at);
```

### Schema with Soft-Delete Support

```sql
-- V1__initial_schema.sql

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,

    -- Business columns
    username VARCHAR(100) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,

    -- Audit columns (from AuditableEntity)
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Soft-delete columns (from SoftDeletableEntity)
    deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP
);

-- Indexes for soft-delete queries
CREATE INDEX idx_users_deleted ON users(deleted);
CREATE INDEX idx_users_username_not_deleted ON users(username) WHERE deleted = false;
```

### Adding a New Table

```sql
-- V2__add_categories_table.sql

CREATE TABLE categories (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,

    -- Audit columns
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Add foreign key to transactions
ALTER TABLE transactions
ADD COLUMN category_id BIGINT,
ADD CONSTRAINT fk_transactions_category
    FOREIGN KEY (category_id)
    REFERENCES categories(id)
    ON DELETE SET NULL;

CREATE INDEX idx_transactions_category_id ON transactions(category_id);
```

### Adding Columns

```sql
-- V3__add_user_status.sql

ALTER TABLE users
ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE';

CREATE INDEX idx_users_status ON users(status);
```

### Creating Indexes

```sql
-- V4__add_performance_indexes.sql

CREATE INDEX idx_transactions_amount ON transactions(amount);
CREATE INDEX idx_transactions_composite ON transactions(transaction_date, amount);

-- Partial index for common query patterns
CREATE INDEX idx_transactions_recent
ON transactions(transaction_date)
WHERE transaction_date >= CURRENT_DATE - INTERVAL '90 days';
```

### Data Migration

```sql
-- V5__migrate_legacy_data.sql

-- Migrate data from old structure to new
INSERT INTO categories (name, description)
SELECT DISTINCT legacy_category, 'Migrated from legacy system'
FROM legacy_transactions
WHERE legacy_category IS NOT NULL;

-- Update foreign keys
UPDATE transactions t
SET category_id = c.id
FROM categories c
WHERE t.legacy_category_name = c.name;
```

## JPA Entity Examples

### Basic Entity with Auditing

```java
package org.budgetanalyzer.{DOMAIN_NAME}.domain;

import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.budgetanalyzer.common.domain.AuditableEntity;

import java.math.BigDecimal;
import java.time.LocalDate;

@Entity
@Table(name = "transactions")
public class Transaction extends AuditableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotBlank
    @Column(nullable = false, length = 500)
    private String description;

    @NotNull
    @Column(nullable = false, precision = 15, scale = 2)
    private BigDecimal amount;

    @NotNull
    @Column(name = "transaction_date", nullable = false)
    private LocalDate transactionDate;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id")
    private Category category;

    // Constructors, getters, setters, equals, hashCode
}
```

### Entity with Soft-Delete

```java
package org.budgetanalyzer.{DOMAIN_NAME}.domain;

import jakarta.persistence.*;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import org.budgetanalyzer.common.domain.SoftDeletableEntity;

@Entity
@Table(name = "users")
public class User extends SoftDeletableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotBlank
    @Column(nullable = false, unique = true, length = 100)
    private String username;

    @Email
    @NotBlank
    @Column(nullable = false, length = 255)
    private String email;

    @Column(length = 20)
    @Enumerated(EnumType.STRING)
    private UserStatus status = UserStatus.ACTIVE;

    // Constructors, getters, setters, equals, hashCode

    public enum UserStatus {
        ACTIVE, INACTIVE, SUSPENDED
    }
}
```

### Entity with JSON Column (PostgreSQL-specific)

```java
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.util.Map;

@Entity
@Table(name = "configurations")
public class Configuration extends AuditableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotBlank
    private String key;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    private Map<String, Object> value;

    // Getters and setters
}
```

Migration for JSON column:

```sql
CREATE TABLE configurations (
    id BIGSERIAL PRIMARY KEY,
    key VARCHAR(100) NOT NULL UNIQUE,
    value JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_configurations_value ON configurations USING GIN(value);
```

## Repository Examples

### Basic Repository

```java
package org.budgetanalyzer.{DOMAIN_NAME}.repository;

import org.budgetanalyzer.{DOMAIN_NAME}.domain.Transaction;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Repository
public interface TransactionRepository extends JpaRepository<Transaction, Long> {

    List<Transaction> findByTransactionDateBetween(LocalDate start, LocalDate end);

    @Query("SELECT t FROM Transaction t WHERE t.amount > :minAmount ORDER BY t.amount DESC")
    List<Transaction> findLargeTransactions(BigDecimal minAmount);

    @Query(value = """
        SELECT * FROM transactions
        WHERE transaction_date >= CURRENT_DATE - INTERVAL '30 days'
        AND deleted = false
        ORDER BY transaction_date DESC
        """, nativeQuery = true)
    List<Transaction> findRecentTransactions();
}
```

### Repository with Soft-Delete

See example in "SoftDeletableEntity" section above.

## Testing

### Repository Test with H2

```java
package org.budgetanalyzer.{DOMAIN_NAME}.repository;

import org.budgetanalyzer.{DOMAIN_NAME}.domain.Transaction;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest  // Uses H2 in-memory database by default
class TransactionRepositoryTest {

    @Autowired
    private TransactionRepository repository;

    @Test
    void save_persistsTransaction() {
        // Arrange
        Transaction transaction = new Transaction();
        transaction.setDescription("Test transaction");
        transaction.setAmount(BigDecimal.valueOf(100.00));
        transaction.setTransactionDate(LocalDate.now());

        // Act
        Transaction saved = repository.save(transaction);

        // Assert
        assertThat(saved.getId()).isNotNull();
        assertThat(saved.getCreatedAt()).isNotNull();
        assertThat(saved.getUpdatedAt()).isNotNull();
    }
}
```

### Repository Test with TestContainers

For testing with real PostgreSQL, see [testcontainers.md](./testcontainers.md).

## Flyway Commands

### Via Gradle

```bash
# Migrate database to latest version
./gradlew flywayMigrate

# Show migration status
./gradlew flywayInfo

# Validate migrations
./gradlew flywayValidate

# Clean database (development only!)
./gradlew flywayClean
```

### Via Spring Boot

Flyway runs automatically on application startup if `spring.flyway.enabled=true`.

## Best Practices

1. **Never Modify Committed Migrations**: Create new migration instead
2. **Use Descriptive Names**: `V2__add_user_email_column.sql` not `V2__update.sql`
3. **Test Migrations**: Test on copy of production data before deploying
4. **Baseline Existing Databases**: Use `flyway.baseline-on-migrate` for existing databases
5. **Version Control**: Commit migration files with application code
6. **One Change Per Migration**: Easier to rollback and debug
7. **Use Transactions**: Wrap DDL in transactions when possible (PostgreSQL supports this)
8. **Add Indexes**: Include appropriate indexes in migrations
9. **Default Values**: Provide default values when adding NOT NULL columns
10. **Leverage Base Classes**: Use AuditableEntity and SoftDeletableEntity from service-common

## Troubleshooting

### Migration Failed

```bash
# View migration status
./gradlew flywayInfo

# Repair migration metadata (if migration was manually fixed)
./gradlew flywayRepair

# Baseline (for existing databases)
./gradlew flywayBaseline
```

### Checksum Mismatch

If migration checksum changes:
- DON'T modify committed migrations
- Use `flyway.validateOnMigrate=false` temporarily (not recommended)
- Or repair: `./gradlew flywayRepair`

### Schema Not Created

Ensure database exists:
```bash
psql -U postgres
CREATE DATABASE {DATABASE_NAME};
```

## See Also

- [Flyway Documentation](https://flywaydb.org/documentation/)
- [Spring Data JPA Reference](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [TestContainers Add-On](./testcontainers.md)
- [Hibernate Documentation](https://hibernate.org/orm/documentation/)

## Notes

- Flyway migrations are immutable - never modify after committing
- Use `ddl-auto: validate` in production (Flyway manages schema)
- PostgreSQL supports transactional DDL (most databases don't)
- Service-common base classes require JPA Auditing to be enabled
- Soft-delete pattern requires careful query design (filter deleted=false)
- Consider using database migration testing in CI/CD pipeline
