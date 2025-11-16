# Add-On: TestContainers

## Purpose
Integration testing with real PostgreSQL database using Docker containers.
TestContainers provides lightweight, disposable database instances for tests,
ensuring tests run against actual PostgreSQL instead of in-memory databases like H2.

## Use Cases
- Integration tests that require real database behavior
- Testing PostgreSQL-specific features (JSON columns, array types, etc.)
- Verifying Flyway migrations work correctly
- Testing JPA repositories with actual database queries
- Avoiding inconsistencies between H2 and PostgreSQL

## Benefits
- **Real Database**: Tests run against actual PostgreSQL
- **Isolation**: Each test class can have its own database instance
- **CI/CD Friendly**: Works in CI pipelines with Docker support
- **Automatic Cleanup**: Containers are automatically destroyed after tests
- **No Manual Setup**: No need to maintain a test database

## Dependencies

### Step 1: Add to `gradle/libs.versions.toml`

```toml
[versions]
testcontainers = "1.20.4"

[libraries]
# Add to existing libraries section
testcontainers-core = { module = "org.testcontainers:testcontainers", version.ref = "testcontainers" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql", version.ref = "testcontainers" }
testcontainers-junit-jupiter = { module = "org.testcontainers:junit-jupiter", version.ref = "testcontainers" }
```

### Step 2: Add to `build.gradle.kts`

```kotlin
dependencies {
    // ... existing dependencies

    // TestContainers for integration testing
    testImplementation(libs.testcontainers.core)
    testImplementation(libs.testcontainers.postgresql)
    testImplementation(libs.testcontainers.junit.jupiter)
}
```

## Configuration

### Base Test Configuration Class

Create a base class that other test classes can extend:

```java
package org.budgetanalyzer.{DOMAIN_NAME}.test;

import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Base class for repository tests using TestContainers.
 * Extend this class to automatically get a PostgreSQL container for testing.
 */
@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
public abstract class BaseRepositoryTest {

    @Container
    protected static final PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:16-alpine")
            .withDatabaseName("test_db")
            .withUsername("test")
            .withPassword("test");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }
}
```

### Test Configuration (src/test/resources/application.yml)

Update test configuration to work with TestContainers:

```yaml
spring:
  # DataSource will be overridden by @DynamicPropertySource in tests
  datasource:
    url: jdbc:postgresql://localhost:5432/test_{DATABASE_NAME}
    username: test
    password: test

  jpa:
    hibernate:
      ddl-auto: create-drop  # Let Hibernate create schema for tests
    show-sql: true           # Show SQL in test output
    properties:
      hibernate:
        format_sql: true

  flyway:
    enabled: false           # Disable Flyway for unit tests, enable for integration tests

logging:
  level:
    org.budgetanalyzer: DEBUG
    org.hibernate.SQL: DEBUG
    org.hibernate.type.descriptor.sql.BasicBinder: TRACE
```

## Usage Examples

### Repository Test

```java
package org.budgetanalyzer.{DOMAIN_NAME}.repository;

import org.budgetanalyzer.{DOMAIN_NAME}.domain.Example;
import org.budgetanalyzer.{DOMAIN_NAME}.test.BaseRepositoryTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class ExampleRepositoryTest extends BaseRepositoryTest {

    @Autowired
    private ExampleRepository repository;

    @Test
    void findAll_returnsAllEntities() {
        // Arrange
        Example entity1 = new Example("test1");
        Example entity2 = new Example("test2");
        repository.save(entity1);
        repository.save(entity2);

        // Act
        List<Example> results = repository.findAll();

        // Assert
        assertThat(results).hasSize(2);
    }

    @Test
    void save_persistsEntity() {
        // Arrange
        Example entity = new Example("test");

        // Act
        Example saved = repository.save(entity);

        // Assert
        assertThat(saved.getId()).isNotNull();
        assertThat(repository.findById(saved.getId())).isPresent();
    }
}
```

### Integration Test with Full Application Context

```java
package org.budgetanalyzer.{DOMAIN_NAME}.integration;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest
@Testcontainers
class ApplicationIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Test
    void contextLoads() {
        // Verifies application context loads with real database
    }
}
```

### Testing with Flyway Migrations

```java
package org.budgetanalyzer.{DOMAIN_NAME}.integration;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@TestPropertySource(properties = {
    "spring.flyway.enabled=true",
    "spring.jpa.hibernate.ddl-auto=validate"  // Use Flyway instead of Hibernate
})
class FlywayMigrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Test
    void migrationsApplySuccessfully() {
        // Verify tables were created by migrations
        Integer count = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'",
            Integer.class
        );

        assertThat(count).isGreaterThan(0);
    }
}
```

### Custom Container Configuration

```java
@Container
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
    .withDatabaseName("custom_test_db")
    .withUsername("custom_user")
    .withPassword("custom_pass")
    .withInitScript("init-test-data.sql")  // Run SQL script on startup
    .withReuse(true);  // Reuse container across test runs (faster, but stateful)
```

## Singleton Container Pattern (Faster Tests)

For faster test execution, use a singleton container shared across all tests:

```java
package org.budgetanalyzer.{DOMAIN_NAME}.test;

import org.testcontainers.containers.PostgreSQLContainer;

/**
 * Singleton PostgreSQL container shared across all tests.
 * Significantly faster than creating a new container per test class.
 */
public class TestPostgreSQLContainer {

    private static final PostgreSQLContainer<?> CONTAINER;

    static {
        CONTAINER = new PostgreSQLContainer<>("postgres:16-alpine")
            .withDatabaseName("test_db")
            .withUsername("test")
            .withPassword("test")
            .withReuse(true);
        CONTAINER.start();
    }

    public static PostgreSQLContainer<?> getInstance() {
        return CONTAINER;
    }

    private TestPostgreSQLContainer() {
        // Private constructor to prevent instantiation
    }
}
```

Then use it in tests:

```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class FastRepositoryTest {

    private static final PostgreSQLContainer<?> postgres = TestPostgreSQLContainer.getInstance();

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    // ... tests
}
```

## Real-World Example: Currency Service

From the currency-service, testing the ExchangeRateRepository:

```java
package org.budgetanalyzer.currency.repository;

import org.budgetanalyzer.currency.domain.Currency;
import org.budgetanalyzer.currency.domain.ExchangeRate;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class ExchangeRateRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private ExchangeRateRepository repository;

    @Autowired
    private CurrencyRepository currencyRepository;

    @Test
    void findByCurrencyAndEffectiveDate_returnsMatchingRate() {
        // Arrange
        Currency usd = currencyRepository.save(new Currency("USD", "US Dollar"));
        ExchangeRate rate = new ExchangeRate();
        rate.setCurrency(usd);
        rate.setEffectiveDate(LocalDate.of(2024, 1, 1));
        rate.setRate(BigDecimal.valueOf(1.0));
        repository.save(rate);

        // Act
        List<ExchangeRate> results = repository.findByCurrencyAndEffectiveDate(
            usd,
            LocalDate.of(2024, 1, 1)
        );

        // Assert
        assertThat(results).hasSize(1);
        assertThat(results.get(0).getRate()).isEqualByComparingTo(BigDecimal.valueOf(1.0));
    }
}
```

## CI/CD Configuration

### GitHub Actions

Ensure Docker is available in CI:

```yaml
# .github/workflows/build.yml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 24
        uses: actions/setup-java@v4
        with:
          java-version: '24'
          distribution: 'temurin'

      - name: Build with Gradle
        run: ./gradlew build

      # TestContainers will automatically use Docker
      # No additional setup needed on GitHub Actions
```

## Troubleshooting

### Container Not Starting

If containers fail to start:

1. Ensure Docker is running
2. Check Docker daemon logs
3. Verify port availability
4. Try pulling the image manually: `docker pull postgres:16-alpine`

### Tests Slow

To speed up tests:

1. Use singleton container pattern
2. Enable container reuse: `.withReuse(true)`
3. Use faster PostgreSQL image: `postgres:16-alpine`
4. Run tests in parallel (Gradle: `--parallel`)

### Permission Issues

On Linux, if you get permission errors:

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Restart Docker daemon
sudo systemctl restart docker
```

## Best Practices

1. **Use Alpine Images**: Smaller and faster (`postgres:16-alpine` vs `postgres:16`)
2. **Reuse Containers**: Use singleton pattern or `.withReuse(true)` for faster tests
3. **Static Containers**: Use `static` container instances to avoid recreating per test
4. **Clean Data**: Use `@Transactional` on test methods for automatic rollback
5. **Specific Versions**: Pin PostgreSQL version to match production
6. **Resource Limits**: Set memory limits if needed: `.withTmpFs(Map.of("/var/lib/postgresql/data", "rw"))`

## See Also

- [TestContainers Documentation](https://www.testcontainers.org/)
- [TestContainers PostgreSQL Module](https://www.testcontainers.org/modules/databases/postgres/)
- [Spring Boot Testing with TestContainers](https://spring.io/blog/2023/06/23/improved-testcontainers-support-in-spring-boot-3-1)

## Notes

- TestContainers requires Docker to be installed and running
- Each container startup adds ~2-3 seconds to test execution
- Use singleton containers for faster test suites
- Works great in CI/CD with Docker support (GitHub Actions, GitLab CI, etc.)
- Not suitable for environments without Docker (use H2 as fallback)
