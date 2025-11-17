# 004. Service-Common Module Split Strategy

**Date:** 2025-11-17
**Status:** Accepted
**Deciders:** Architecture Team

## Context

The Budget Analyzer project has a shared library (`service-common`) that provides common utilities, configurations, and patterns for all microservices. As the project evolves, we need to support different types of applications:

1. **Web services** (REST APIs) - Current: transaction-service, currency-service
2. **Non-web applications** (future) - CLI tools, batch processors, message consumers

The current monolithic `service-common` library includes both foundational utilities (logging, exceptions) and web-specific components (Spring MVC filters, JPA entities, OpenAPI configuration). This means non-web applications must include unnecessary web dependencies.

**Problem**: How should we structure service-common to support both web and non-web applications while maintaining simplicity and consistency?

## Decision

Split `service-common` into a **multi-module monorepo** with two modules:

1. **`service-core`** - Minimal foundation utilities (logging, exceptions, Jackson)
   - No Spring Web or JPA dependencies
   - Reusable across any application type

2. **`service-web`** - Spring Boot web service components
   - Depends on `service-core` (transitive to consumers)
   - Includes Spring Web, JPA, OpenAPI, CSV parsing
   - Uses `api()` dependencies for implicit transitive dependencies

**Module Structure**:
```
service-common/                           (parent/root project)
├── settings.gradle.kts                   (defines subprojects)
├── build.gradle.kts                      (root config, shared settings)
├── gradle/
│   └── libs.versions.toml                (shared version catalog)
├── service-core/                         (minimal foundation - no Spring deps)
│   ├── build.gradle.kts
│   └── src/main/java/org/budgetanalyzer/core/
│       ├── csv/                          (CSV parsing utilities)
│       │   ├── CsvData.java
│       │   ├── CsvParser.java
│       │   ├── CsvRow.java
│       │   └── impl/OpenCsvParser.java
│       ├── domain/                       (JPA base entities)
│       │   ├── AuditableEntity.java
│       │   ├── SoftDeletableEntity.java
│       │   └── SoftDeleteListener.java
│       ├── logging/                      (Safe logging utilities)
│       │   ├── SafeLogger.java
│       │   ├── Sensitive.java
│       │   └── SensitiveDataModule.java
│       └── repository/                   (Repository interfaces)
│           └── SoftDeleteOperations.java
└── service-web/                          (Spring Boot web components)
    ├── build.gradle.kts
    └── src/main/java/org/budgetanalyzer/service/
        ├── api/                          (API error handling)
        │   ├── ApiErrorResponse.java
        │   ├── ApiErrorType.java
        │   ├── DefaultApiExceptionHandler.java
        │   └── FieldError.java
        ├── config/                       (Spring configuration)
        │   └── BaseOpenApiConfig.java
        ├── exception/                    (Exception classes)
        │   ├── BusinessException.java
        │   ├── ClientException.java
        │   ├── InvalidRequestException.java
        │   ├── ResourceNotFoundException.java
        │   ├── ServiceException.java
        │   └── ServiceUnavailableException.java
        └── http/                         (HTTP filters and utilities)
            ├── ContentLoggingUtil.java
            ├── CorrelationIdFilter.java
            ├── HttpLoggingConfig.java
            ├── HttpLoggingFilter.java
            └── HttpLoggingProperties.java
```

**Consuming Service Pattern**:
```kotlin
// REST API Services (most common):
implementation("org.budgetanalyzer:service-web:0.0.1-SNAPSHOT")
// Automatically includes service-core via transitive dependency
// Automatically includes Spring Boot Web + JPA via api() dependencies

// CLI/Batch Services (future):
implementation("org.budgetanalyzer:service-core:0.0.1-SNAPSHOT")
// Gets: Jackson, SLF4J, exceptions, logging utilities
// Does NOT get: Spring Web, JPA, OpenCSV, SpringDoc
```

## Alternatives Considered

### Alternative 1: Multi-Repository Approach
Split into separate repositories: `service-core` and `service-web`.

**Pros:**
- Complete independence between modules
- Clear ownership boundaries
- Can version independently

**Cons:**
- Must duplicate tooling config (checkstyle, spotless, etc.)
- Cross-repo changes require multiple PRs
- Version coordination overhead
- Two CI pipelines to maintain
- Slower development workflow
- More complex release process

### Alternative 2: Keep Monolithic Library
Keep single `service-common` with all dependencies.

**Pros:**
- Simplest approach - no changes needed
- Single dependency for all consumers
- No module coordination

**Cons:**
- Forces unnecessary dependencies on non-web applications
- Larger dependency footprint for simple CLI tools
- Tighter coupling between web and non-web concerns
- Cannot support lightweight applications

### Alternative 3: Separate Repositories Per Concern
Create multiple small repositories: `logging-commons`, `exception-commons`, `web-commons`, `jpa-commons`.

**Pros:**
- Maximum granularity
- Pick and choose dependencies

**Cons:**
- Significant overhead (4+ repositories to maintain)
- Complex dependency management
- Version coordination nightmare
- Overkill for project size
- Slower development across concerns

## Consequences

**Positive:**
- ✅ Future flexibility for non-web applications (CLI tools, batch processors)
- ✅ Clear separation of concerns (core utilities vs web-specific)
- ✅ Monorepo benefits: atomic changes, shared tooling, coordinated releases
- ✅ Simple consuming service build files via `api()` dependencies
- ✅ Single version for both modules
- ✅ Single CI/CD pipeline
- ✅ Minimal migration impact (both existing services use web module)

**Negative:**
- ❌ Migration effort required for existing services (update dependency from `service-common` to `service-web`)
- ❌ CSV parser refactoring needed (remove Spring Web dependency from core)
- ❌ Slightly more complex build structure (multi-module Gradle)
- ❌ Must coordinate changes across modules (though easier than multi-repo)

**Neutral:**
- 🔷 Package naming kept as-is initially (`org.budgetanalyzer.service.*`), can refactor to `web` later
- 🔷 Both modules published to Maven Local for development
- 🔷 Consuming services must explicitly choose `service-core` or `service-web`

## Implementation Notes

### CSV Parser Refactoring
The `CsvParser` interface currently has a convenience method accepting Spring's `MultipartFile`, which creates a web dependency in core. Solution:

```java
// BEFORE:
public interface CsvParser {
  CsvData parseCsvInputStream(InputStream inputStream, String fileName, String format) throws IOException;
  default CsvData parseCsvFile(MultipartFile file, String format) throws IOException { ... }
}

// AFTER:
public interface CsvParser {
  CsvData parseCsvInputStream(InputStream inputStream, String fileName, String format) throws IOException;
}

// Consuming code updates:
// BEFORE:
var csvData = csvParser.parseCsvFile(file, format);

// AFTER:
var csvData = csvParser.parseCsvInputStream(file.getInputStream(), file.getOriginalFilename(), format);
```

### Version Catalog Updates
Consuming services update their `libs.versions.toml`:

```toml
[libraries]
# BEFORE:
service-common = { module = "org.budgetanalyzer:service-common", version.ref = "serviceCommon" }

# AFTER:
service-core = { module = "org.budgetanalyzer:service-core", version.ref = "serviceCommon" }
service-web = { module = "org.budgetanalyzer:service-web", version.ref = "serviceCommon" }
```

### Build Configuration
Root `build.gradle.kts` manages shared configuration:
- Java toolchain
- Spotless formatting
- Checkstyle
- Publishing to Maven Local
- Common plugin application

Subprojects inherit configuration and add module-specific dependencies.

## References
- [Service-Common Repository](https://github.com/budgetanalyzer/service-common)
- [Transaction Service](https://github.com/budgetanalyzer/transaction-service)
- [Currency Service](https://github.com/budgetanalyzer/currency-service)
