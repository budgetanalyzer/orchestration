# service-common Architecture: Design Decisions

## Overview

The `service-common` repository provides shared utilities and auto-configuration for Budget Analyzer microservices. It is split into two modules that follow Spring Boot's library + starter pattern with conditional auto-configuration.

## Module Structure

```
service-common/
├── service-core/          # Core utilities (minimal dependencies)
└── service-web/           # Web-specific features (REST APIs)
```

## Design Principles

### 1. Opt-In Dependencies, Not Transitive Bloat

**Problem**: If every utility library forces all its dependencies on consumers, services get bloated with libraries they don't use.

**Solution**: Use `implementation()` for heavy dependencies, not `api()`

```kotlin
// service-core/build.gradle.kts
dependencies {
    // TRANSITIVE - every service gets these
    api(libs.spring.boot.starter.actuator)  // Health checks for everyone

    // NOT TRANSITIVE - services opt-in
    implementation(libs.spring.boot.starter.data.jpa)  // Only if service adds JPA
    implementation(libs.opencsv)  // Only if service adds this
}
```

**Result**: Services only get dependencies they explicitly add.

### 2. Conditional Auto-Configuration

**Problem**: How do we provide JPA base entities (AuditableEntity) without forcing JPA on all services?

**Solution**: Use `@ConditionalOnClass(DataSource.class)` to activate features only when needed

```java
@AutoConfiguration
public class ServiceCoreAutoConfiguration {
    // Always: component scanning for utilities

    @AutoConfiguration
    @ConditionalOnClass(DataSource.class)  // Only if JPA is on classpath
    @EntityScan(basePackages = "org.budgetanalyzer.core.domain")
    @EnableJpaAuditing
    public static class JpaConfiguration {
        // Activates ONLY if service added spring-boot-starter-data-jpa
    }
}
```

**Result**: Services without databases don't get JPA entity scanning.

### 3. Actuator Always Available

**Decision**: Keep `spring-boot-starter-actuator` as `api()` in service-core

**Rationale**: Every service should have health checks and metrics. This is non-negotiable.

```kotlin
api(libs.spring.boot.starter.actuator)  // ✅ Transitive
```

**Result**: All services automatically expose:
- `/actuator/health`
- `/actuator/metrics`
- `/actuator/info`

### 4. Exceptions are HTTP-Specific (Stay in service-web)

**Decision**: Keep exception classes in service-web, not service-core

**Rationale**: These exceptions map to HTTP status codes:

```java
// All in service-web:
ResourceNotFoundException    → 404 Not Found
ValidationException          → 400 Bad Request
ConflictException            → 409 Conflict
ServiceUnavailableException  → 503 Service Unavailable
```

**For non-web services**:
- Throw standard Java exceptions (`IllegalArgumentException`, `IllegalStateException`)
- Or create custom exceptions specific to the domain
- Or add `service-web` as a dependency (it won't auto-configure web features without Spring Boot Web)

### 5. Auto-Scan Both Modules

**Decision**: Auto-configuration classes handle component scanning, not individual services

**service-core auto-configuration**:
```java
@ComponentScan(basePackages = {
    "org.budgetanalyzer.core.logging",    // SafeLogger, SensitiveDataModule
    "org.budgetanalyzer.core.csv"          // OpenCsvParser
})
```

**service-web auto-configuration**:
```java
@ConditionalOnWebApplication
@ComponentScan(basePackages = {
    "org.budgetanalyzer.service.api",      // DefaultApiExceptionHandler
    "org.budgetanalyzer.service.http",     // HttpLoggingConfig, filters
    "org.budgetanalyzer.service.config"    // OpenApiConfig
})
```

**Result**: Services don't need to add `@ComponentScan` annotations. Everything is auto-configured.

### 6. Utilities Are Spring Components

**Decision**: Keep utilities as `@Component` beans (e.g., `OpenCsvParser`)

**Rationale**: Works both ways:

**With dependency injection**:
```java
@Service
public class TransactionService {
    private final CsvParser csvParser;

    @Autowired
    public TransactionService(CsvParser csvParser) {
        this.csvParser = csvParser;  // Spring injects OpenCsvParser
    }
}
```

**Without dependency injection**:
```java
CsvParser parser = new OpenCsvParser();  // Direct instantiation
```

**Result**: Flexible - use autowiring when convenient, direct instantiation when needed.

### 7. Conditionals on Auto-Configuration, Not Individual Beans

**Decision**: Put `@ConditionalOnWebApplication` on the top-level auto-configuration class, not individual beans

**Before (redundant)**:
```java
// Auto-configuration imports file:
org.budgetanalyzer.service.http.HttpLoggingConfig
org.budgetanalyzer.service.api.DefaultApiExceptionHandler

// HttpLoggingConfig.java:
@AutoConfiguration
@ConditionalOnWebApplication  // ← Conditional here
public class HttpLoggingConfig { ... }

// DefaultApiExceptionHandler.java:
@AutoConfiguration
@ConditionalOnWebApplication  // ← And here
public class DefaultApiExceptionHandler { ... }
```

**After (cleaner)**:
```java
// Auto-configuration imports file:
org.budgetanalyzer.service.config.ServiceWebAutoConfiguration

// ServiceWebAutoConfiguration.java:
@AutoConfiguration
@ConditionalOnWebApplication  // ← Single conditional
@ComponentScan(basePackages = {
    "org.budgetanalyzer.service.api",
    "org.budgetanalyzer.service.http"
})
public class ServiceWebAutoConfiguration { ... }

// HttpLoggingConfig.java:
@Configuration  // ← No conditional needed
public class HttpLoggingConfig { ... }

// DefaultApiExceptionHandler.java:
@RestControllerAdvice  // ← No conditional needed
public class DefaultApiExceptionHandler { ... }
```

**Rationale**:
- Single point of control for when web features activate
- Individual beans don't need to know about activation logic
- Easier to test and reason about

**Exception**: Fine-grained conditionals within a config are fine:
```java
@Bean
@ConditionalOnProperty(
    prefix = "budgetanalyzer.service.http-logging",
    name = "enabled",
    havingValue = "true")
public HttpLoggingFilter httpLoggingFilter(HttpLoggingProperties properties) {
    // This is fine - optional feature within web applications
}
```

## Module Details

### service-core

**Purpose**: Foundation utilities for all services (minimal dependencies)

**Dependencies**:
```kotlin
// Transitive (every service gets):
api(libs.spring.boot.starter.actuator)

// Not transitive (services opt-in):
implementation(libs.spring.boot.starter.data.jpa)
implementation(libs.jackson.databind)
implementation(libs.opencsv)
```

**Contents**:
- `org.budgetanalyzer.core.logging.*` - SafeLogger, Sensitive annotation, SensitiveDataModule
- `org.budgetanalyzer.core.csv.*` - OpenCsvParser (CSV parsing with OpenCSV)
- `org.budgetanalyzer.core.domain.*` - AuditableEntity, SoftDeletableEntity (JPA base entities)
- `org.budgetanalyzer.core.repository.*` - SoftDeleteOperations interface

**Auto-Configuration**:
- Always: Component scan for logging and CSV utilities
- Conditional: JPA entity scanning (only if DataSource on classpath)

### service-web

**Purpose**: Web-specific features for REST APIs

**Dependencies**:
```kotlin
// Transitive (web services get):
api(project(":service-core"))         // Includes service-core
api(libs.spring.boot.starter.web)      // Spring MVC + Tomcat
api(libs.springdoc.openapi)            // OpenAPI/Swagger

// Not transitive:
implementation(libs.commons.lang3)
```

**Contents**:
- `org.budgetanalyzer.service.exception.*` - HTTP exception classes (ResourceNotFoundException, etc.)
- `org.budgetanalyzer.service.api.*` - ApiError, ApiErrorResponse, DefaultApiExceptionHandler
- `org.budgetanalyzer.service.http.*` - HttpLoggingConfig, CorrelationIdFilter, HttpLoggingFilter
- `org.budgetanalyzer.service.config.*` - OpenApiConfig

**Auto-Configuration**:
- Conditional: Only activates if @ConditionalOnWebApplication
- Component scans exception handlers, filters, config classes

## Service Types and Dependencies

### Minimal Non-Web Service (No Database)

**Example**: Scheduled batch job, CLI tool

**Dependencies**:
```kotlin
dependencies {
    implementation(libs.service.core)
    implementation(libs.spring.boot.starter)
}
```

**Gets**:
- ✅ Actuator (health checks)
- ✅ SafeLogger, OpenCsvParser
- ❌ No JPA entities
- ❌ No web container

### Minimal Non-Web Service (With Database)

**Example**: Message consumer that writes to database

**Dependencies**:
```kotlin
dependencies {
    implementation(libs.service.core)
    implementation(libs.spring.boot.starter)
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.postgresql)
}
```

**Gets**:
- ✅ Actuator
- ✅ SafeLogger, OpenCsvParser
- ✅ JPA entities (AuditableEntity, SoftDeletableEntity)
- ✅ JPA auditing (automatic createdAt, updatedAt)
- ❌ No web container

**How it works**: `@ConditionalOnClass(DataSource.class)` detects JPA and activates entity scanning.

### REST API Service (With Database)

**Example**: Standard microservice with REST endpoints

**Dependencies**:
```kotlin
dependencies {
    implementation(libs.service.web)  // Includes service-core + web
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.postgresql)
}
```

**Gets**:
- ✅ Actuator (from service-core)
- ✅ SafeLogger, OpenCsvParser (from service-core)
- ✅ JPA entities and auditing (from service-core)
- ✅ Web container (from service-web)
- ✅ Exception handlers (from service-web)
- ✅ HTTP filters (from service-web)
- ✅ OpenAPI/Swagger (from service-web)

**How it works**:
- `service-web` includes `service-core` via `api()`
- `@ConditionalOnWebApplication` detects web and activates web auto-configuration
- `@ConditionalOnClass(DataSource.class)` detects JPA and activates entity scanning

### REST API Service (No Database)

**Example**: API Gateway, proxy service

**Dependencies**:
```kotlin
dependencies {
    implementation(libs.service.web)
    implementation(libs.spring.boot.starter.webflux)  // For WebClient
}
```

**Gets**:
- ✅ Actuator
- ✅ SafeLogger, OpenCsvParser
- ✅ Web container and all web features
- ✅ WebClient for calling external APIs
- ❌ No JPA entities (no DataSource on classpath)

## Migration Guide for Existing Services

If you have existing services using the old `service-core` with transitive JPA:

**Before**:
```kotlin
dependencies {
    implementation(libs.service.core)  // Got JPA transitively
}
```

**After**:
```kotlin
dependencies {
    implementation(libs.service.core)  // No longer includes JPA
    implementation(libs.spring.boot.starter.data.jpa)  // Add explicitly
}
```

**Services affected**:
- transaction-service
- currency-service

**Note**: Web services using `service-web` are not affected (web includes core).

## Testing Auto-Configuration

**Test: Verify JPA Conditional Activation**

```java
@SpringBootTest
class ServiceCoreAutoConfigurationTest {

    @Autowired
    private ApplicationContext context;

    @Test
    void jpaEntitiesScannedWhenDataSourcePresent() {
        // If service has spring-boot-starter-data-jpa
        assertThat(context.getBean(EntityManagerFactory.class)).isNotNull();
    }

    @Test
    void csvParserAlwaysAvailable() {
        assertThat(context.getBean(CsvParser.class)).isNotNull();
    }
}
```

**Test: Verify Web Conditional Activation**

```java
@SpringBootTest(webEnvironment = WebEnvironment.MOCK)
class ServiceWebAutoConfigurationTest {

    @Autowired
    private ApplicationContext context;

    @Test
    void exceptionHandlerActiveInWebApplication() {
        assertThat(context.getBean(DefaultApiExceptionHandler.class)).isNotNull();
    }
}
```

## FAQ

### Q: Why not create separate lib/starter modules like Spring Boot does?

**A**: We considered it (see Phase 6.1 plan - Approach A). Decision:
- 2 modules is simpler than 6 modules (service-core-lib, service-core-starter, service-data-lib, service-data-starter, service-web-lib, service-web-starter)
- Conditional auto-configuration achieves the same goal with less complexity
- Easier to maintain

### Q: Can non-web services use the exception classes?

**A**: They can, but they probably shouldn't. Those exceptions are HTTP-specific. Options:
1. Use standard Java exceptions (`IllegalArgumentException`, `IllegalStateException`)
2. Create domain-specific exceptions
3. Add `service-web` dependency (won't auto-configure web features without Spring Boot Web on classpath)

### Q: What if a service needs JPA entities but not a database?

**A**: Unlikely scenario, but possible. Add `spring-boot-starter-data-jpa` with `compileOnly`:
```kotlin
compileOnly(libs.spring.boot.starter.data.jpa)  // Entities available at compile time
```

### Q: Can I use utilities without Spring?

**A**: Yes! All utilities are Spring components, but you can instantiate them directly:
```java
CsvParser parser = new OpenCsvParser();
SafeLogger logger = new SafeLogger(LoggerFactory.getLogger(MyClass.class));
```

### Q: How do I know what auto-configuration activated?

**A**: Enable debug logging:
```yaml
logging:
  level:
    org.springframework.boot.autoconfigure: DEBUG
```

Or use Spring Boot Actuator's `/actuator/conditions` endpoint.

## References

- [Spring Boot Auto-Configuration](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.developing-auto-configuration)
- [Creating Your Own Starter](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.developing-auto-configuration.custom-starter)
- [Conditional Annotations](https://docs.spring.io/spring-boot/docs/current/api/org/springframework/boot/autoconfigure/condition/package-summary.html)
- [Component Scanning](https://docs.spring.io/spring-framework/docs/current/reference/html/core.html#beans-scanning-autodetection)
