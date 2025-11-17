# Spring Boot Microservice Template & Creation System - Implementation Plan

**Date**: 2025-11-16
**Status**: Planning
**Author**: Architecture Team

## Executive Summary

This plan outlines the creation of a standardized Spring Boot microservice template and creation system for the Budget Analyzer project. The goal is to reduce service creation time from 2-3 hours to ~15 minutes while ensuring consistency across all microservices.

---

## Decision Points

### 1. Service-Common Module Split Strategy

**Decision**: CONFIRMED - Split service-common into multi-module monorepo

**Final Decision**:
- **Monorepo structure** with 2 modules: `service-core` and `service-web`
- Parent project remains `service-common`
- Modules use `api()` dependencies for implicit transitive dependencies (simpler consuming services)
- CSV parsing refactored to remove Spring Web dependency from core

**Rationale**:
1. **Future flexibility**: Will support non-web services (CLI tools, batch processors, message consumers)
2. **Clear separation**: Core utilities vs web-specific components
3. **Developer preference**: Implicit dependencies via `api()` keeps service build files simple
4. **Monorepo benefits**: Atomic changes, shared tooling, coordinated releases
5. **Current impact minimal**: Both existing services use both modules, so minimal migration pain

---

#### Module Structure

```
service-common/                           (parent/root project)
├── settings.gradle.kts                   (defines subprojects)
├── build.gradle.kts                      (root config, shared settings)
├── gradle/
│   └── libs.versions.toml                (shared version catalog)
├── service-core/                         (NEW - minimal foundation)
│   ├── build.gradle.kts
│   └── src/
│       └── main/java/org/budgetanalyzer/
│           ├── core/
│           │   └── logging/              (SafeLogger, Sensitive, etc.)
│           └── service/                  (TODO: rename to 'web' in Phase 2)
│               └── exception/            (all exception classes)
└── service-web/                          (NEW - Spring Boot web components)
    ├── build.gradle.kts
    └── src/
        └── main/java/org/budgetanalyzer/
            ├── core/
            │   ├── csv/                  (CSV parsing - after refactor)
            │   ├── domain/               (JPA entities)
            │   └── repository/           (JPA repositories)
            └── service/                  (TODO: rename to 'web' in Phase 2)
                ├── api/                  (API error handling)
                ├── http/                 (HTTP filters)
                └── config/               (OpenAPI config)
```

---

#### service-core Module

**Purpose**: Foundation-level utilities with minimal dependencies. Reusable across any application type (web services, CLI tools, batch jobs).

**Contents**:
- `org.budgetanalyzer.core.logging.*` - SafeLogger, Sensitive annotation, SensitiveDataModule
- `org.budgetanalyzer.service.exception.*` - All exception classes (pure POJOs)

**Dependencies**:
```kotlin
dependencies {
    api("com.fasterxml.jackson.core:jackson-databind")
    api("com.fasterxml.jackson.datatype:jackson-datatype-jsr310")
    api("org.slf4j:slf4j-api")
    api("org.springframework.boot:spring-boot-starter-actuator")  // Health checks and metrics

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
```

**Use Cases**:
- CLI tools (only need logging and exceptions)
- Batch jobs (minimal Spring Boot, no web)
- Web services (via service-web dependency)

---

#### service-web Module

**Purpose**: Spring Boot web service components with auto-configuration. Includes all web-specific, JPA, and service infrastructure.

**Contents**:
- `org.budgetanalyzer.core.csv.*` - CSV parsing (refactored to use InputStream)
- `org.budgetanalyzer.core.domain.*` - JPA base entities (AuditableEntity, SoftDeletableEntity)
- `org.budgetanalyzer.core.repository.*` - Repository interfaces (SoftDeleteOperations)
- `org.budgetanalyzer.service.api.*` - API error responses and handlers
- `org.budgetanalyzer.service.http.*` - HTTP filters and logging
- `org.budgetanalyzer.service.config.*` - OpenAPI configuration

**Dependencies**:
```kotlin
plugins {
    alias(libs.plugins.spring.dependency.management)
}

dependencyManagement {
    imports {
        mavenBom("org.springframework.boot:spring-boot-dependencies:${libs.versions.springBoot.get()}")
    }
}

dependencies {
    // Core module dependency (transitive to consumers via api())
    api(project(":service-core"))

    // Spring Boot (use api() for implicit dependencies)
    api("org.springframework.boot:spring-boot-starter-web")
    api("org.springframework.boot:spring-boot-starter-data-jpa")

    // Third-party
    implementation("com.opencsv:opencsv")
    implementation("org.springdoc:springdoc-openapi-starter-webmvc-ui")
    implementation("org.apache.commons:commons-lang3")

    // Test
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testRuntimeOnly("com.h2database:h2")
}
```

**Use Cases**:
- Spring Boot REST API microservices
- Services with JPA persistence
- Services with CSV upload capabilities

---

#### Consuming Service Impact

**REST API Services** (transaction-service, currency-service):
```kotlin
// BEFORE (current):
implementation("org.budgetanalyzer:service-common:0.0.1-SNAPSHOT")

// AFTER (module split):
implementation("org.budgetanalyzer:service-web:0.0.1-SNAPSHOT")
// Automatically includes service-core via transitive dependency
// Automatically includes Spring Boot Web + JPA via api() dependencies
```

**CLI/Batch Services** (future):
```kotlin
// Only need core utilities:
implementation("org.budgetanalyzer:service-core:0.0.1-SNAPSHOT")
// Gets: Jackson, SLF4J, exceptions, logging utilities
// Does NOT get: Spring Web, JPA, OpenCSV, SpringDoc
```

---

#### CSV Parsing Refactor

**Problem**: Current `CsvParser` interface uses `MultipartFile` from Spring Web, forcing web dependency on core.

**Solution**: Remove Spring Web dependency by refactoring to use `InputStream`.

**Changes**:

1. **Remove convenience method from CsvParser interface**:
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
   ```

2. **Update consuming code** (TransactionImportService.java):
   ```java
   // BEFORE:
   var csvData = csvParser.parseCsvFile(file, format);

   // AFTER:
   var csvData = csvParser.parseCsvInputStream(
       file.getInputStream(),       // Extract InputStream
       file.getOriginalFilename(),  // Extract filename
       format
   );
   ```

**Impact**:
- Only 1 call site needs updating (TransactionImportService.java:66)
- Change is trivial (extract InputStream and filename from MultipartFile)
- Core parsing logic already uses InputStream (no changes needed)
- Eliminates Spring Web dependency from service-core

---

#### Package Naming Strategy

**Phase 1** (Current Implementation - NOW):
- Keep package names as-is: `org.budgetanalyzer.service.exception.*`
- Focus on module split, not package renames
- Minimize scope of changes

**Phase 2** (Future Refactoring - LATER):
- Rename `service` packages to `web` for clarity:
  - `org.budgetanalyzer.service.exception.*` → `org.budgetanalyzer.web.exception.*`
  - `org.budgetanalyzer.service.api.*` → `org.budgetanalyzer.web.api.*`
  - `org.budgetanalyzer.service.http.*` → `org.budgetanalyzer.web.http.*`
  - `org.budgetanalyzer.service.config.*` → `org.budgetanalyzer.web.config.*`

**Rationale**: One step at a time - complete module split first, refine naming later.

---

#### Why Monorepo Over Multi-Repo?

**Monorepo Advantages** (chosen approach):
- ✅ Shared Gradle configuration (version catalogs, plugins, checkstyle, spotless)
- ✅ Single version for both modules (coordinated releases)
- ✅ Atomic commits across modules (change both in one PR)
- ✅ Easier refactoring between modules
- ✅ Single CI/CD pipeline
- ✅ Faster development (no cross-repo coordination)

**Multi-Repo Disadvantages** (not chosen):
- ❌ Must duplicate tooling config (checkstyle, spotless, etc.)
- ❌ Cross-repo changes require multiple PRs
- ❌ Version coordination overhead
- ❌ Two CI pipelines to maintain

**Conclusion**: Modules are tightly coupled and evolve together, making monorepo the better choice.

---

#### Version Catalog Updates

**Add to libs.versions.toml** (in consuming services):
```toml
[libraries]
service-core = { module = "org.budgetanalyzer:service-core", version = "0.0.1-SNAPSHOT" }
service-web = { module = "org.budgetanalyzer:service-web", version = "0.0.1-SNAPSHOT" }
```

**Usage in consuming services**:
```kotlin
// For REST API services (most common):
implementation(libs.service.web)

// For CLI/batch services (future):
implementation(libs.service.core)
```

---

### 2. Template Source of Truth: GitHub Template Repository

**Decision**: CONFIRMED - GitHub template repository is the source of truth

**Implementation**:
- Create `budget-analyzer/spring-boot-service-template` repository
- Mark as template repository in GitHub settings
- All changes to template structure go through PR process
- Script reads from template to generate services
- Version template with semantic versioning

**Benefits**:
- Single source of truth
- Version control for template changes
- Easy to see template history
- Can fork/clone for experimentation
- GitHub native "Use this template" button for manual use

**Structure**:
```
budget-analyzer/spring-boot-service-template/
├── README.md (usage instructions)
├── TEMPLATE_USAGE.md (detailed guide)
├── template/ (actual template files with placeholders)
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   ├── gradle/libs.versions.toml
│   ├── src/...
│   └── ...
└── .github/workflows/ (CI for template validation)
```

---

### 3. Build Order: Full Template System First

**Decision**: CONFIRMED - Build complete template system first, validate with test services

**Rationale**:
- Better to validate template thoroughly before using for production services
- Iterate on template based on learnings from test services
- Can adjust template structure before committing to production use

**Implementation Order**:
1. Build GitHub template repository
2. Create interactive creation script
3. Document add-on patterns
4. Test template with throwaway test services
5. Validate with real service creation (post-template)
6. Iterate based on learnings

**Note on Reactive Services**: Services using Spring Cloud Gateway (reactive/WebFlux architecture) cannot use this servlet-based template. See Phase 7 for details.

---

## Implementation Phases

### Phase 0: Service-Common Module Split

**Duration**: 2-3 days

**Purpose**: Split the monolithic service-common into service-core and service-web modules to support both web services and non-web applications (CLI, batch).

**Tasks**:

1. **CSV Parser Refactoring** (Remove Spring Web Dependency)
   - Remove `parseCsvFile(MultipartFile)` method from `CsvParser` interface
   - Remove MultipartFile override from `OpenCsvParser` implementation
   - Update transaction-service `TransactionImportService` to use `parseCsvInputStream()`
   - Update `OpenCsvParserTest` to remove MockMultipartFile test
   - Verify CSV parsing still works with InputStream-based API

2. **Create Multi-Module Structure**

   **Root configuration**:
   - Create `service-common/settings.gradle.kts`:
     ```kotlin
     rootProject.name = "service-common"
     include("service-core")
     include("service-web")
     ```

   - Update `service-common/build.gradle.kts` as root project:
     ```kotlin
     plugins {
         java
         checkstyle
         alias(libs.plugins.spotless) apply false
     }

     allprojects {
         group = "org.budgetanalyzer"
         version = "0.0.1-SNAPSHOT"
         repositories {
             mavenCentral()
         }
     }

     subprojects {
         apply(plugin: "java")
         apply(plugin: "checkstyle")
         apply(plugin: "maven-publish")
         apply(plugin: "com.diffplug.spotless")

         java {
             toolchain {
                 languageVersion = JavaLanguageVersion.of(libs.versions.java.get().toInt())
             }
             withSourcesJar()
             withJavadocJar()
         }

         tasks.withType<Test> {
             useJUnitPlatform()
         }

         // Shared spotless and checkstyle configuration
         configure<com.diffplug.gradle.spotless.SpotlessExtension> {
             java {
                 googleJavaFormat(libs.versions.googleJavaFormat.get())
                 trimTrailingWhitespace()
                 endWithNewline()
                 importOrder("java", "javax", "jakarta", "org", "com", "", "org.budgetanalyzer")
                 removeUnusedImports()
             }
         }

         configure<CheckstyleExtension> {
             toolVersion = libs.versions.checkstyle.get()
         }

         tasks.named("check") {
             dependsOn("spotlessCheck")
         }

         // Publishing configuration
         configure<PublishingExtension> {
             publications {
                 create<MavenPublication>("mavenJava") {
                     from(components["java"])
                     groupId = project.group.toString()
                     artifactId = project.name
                     version = project.version.toString()
                 }
             }
             repositories {
                 mavenLocal()
             }
         }
     }
     ```

3. **Create service-core Module**

   **Directory structure**:
   ```
   service-core/
   ├── build.gradle.kts
   └── src/
       ├── main/java/org/budgetanalyzer/
       │   ├── core/
       │   │   └── logging/        (move from root)
       │   └── service/
       │       └── exception/      (move from root)
       └── test/java/...           (move tests)
   ```

   **build.gradle.kts**:
   ```kotlin
   dependencies {
       api("com.fasterxml.jackson.core:jackson-databind")
       api("com.fasterxml.jackson.datatype:jackson-datatype-jsr310")
       api("org.slf4j:slf4j-api")

       testImplementation("org.springframework.boot:spring-boot-starter-test")
       testRuntimeOnly("org.junit.platform:junit-platform-launcher")
   }
   ```

4. **Create service-web Module**

   **Directory structure**:
   ```
   service-web/
   ├── build.gradle.kts
   └── src/
       ├── main/java/org/budgetanalyzer/
       │   ├── core/
       │   │   ├── csv/           (move from root)
       │   │   ├── domain/        (move from root)
       │   │   └── repository/    (move from root)
       │   └── service/
       │       ├── api/           (move from root)
       │       ├── http/          (move from root)
       │       └── config/        (move from root)
       └── test/java/...          (move tests)
   ```

   **build.gradle.kts**:
   ```kotlin
   plugins {
       alias(libs.plugins.spring.dependency.management)
   }

   dependencyManagement {
       imports {
           mavenBom("org.springframework.boot:spring-boot-dependencies:${libs.versions.springBoot.get()}")
       }
   }

   dependencies {
       // Core module dependency
       api(project(":service-core"))

       // Spring Boot
       api("org.springframework.boot:spring-boot-starter-web")
       api("org.springframework.boot:spring-boot-starter-data-jpa")

       // Third-party
       implementation("com.opencsv:opencsv:${libs.versions.opencsv.get()}")
       implementation("org.springdoc:springdoc-openapi-starter-webmvc-ui:${libs.versions.springdoc.get()}")
       implementation("org.apache.commons:commons-lang3")

       // Test
       testImplementation("org.springframework.boot:spring-boot-starter-test")
       testRuntimeOnly("org.junit.platform:junit-platform-launcher")
       testRuntimeOnly("com.h2database:h2")
   }
   ```

5. **Update Consuming Services**

   **transaction-service/build.gradle.kts**:
   ```kotlin
   // BEFORE:
   implementation(libs.service.common)

   // AFTER:
   implementation(libs.service.web)
   ```

   **currency-service/build.gradle.kts**:
   ```kotlin
   // BEFORE:
   implementation(libs.service.common)

   // AFTER:
   implementation(libs.service.web)
   ```

   **Update libs.versions.toml** (in each service):
   ```toml
   [libraries]
   # BEFORE:
   service-common = { module = "org.budgetanalyzer:service-common", version.ref = "serviceCommon" }

   # AFTER:
   service-core = { module = "org.budgetanalyzer:service-core", version.ref = "serviceCommon" }
   service-web = { module = "org.budgetanalyzer:service-web", version.ref = "serviceCommon" }
   ```

6. **Build and Publish**
   ```bash
   # Build service-common (both modules)
   cd /workspace/service-common
   ./gradlew clean build

   # Publish to Maven Local
   ./gradlew publishToMavenLocal

   # Build transaction-service
   cd /workspace/transaction-service
   ./gradlew clean build

   # Build currency-service
   cd /workspace/currency-service
   ./gradlew clean build
   ```

7. **Testing & Validation**
   - Run all tests in service-core
   - Run all tests in service-web
   - Run all tests in transaction-service
   - Run all tests in currency-service
   - Manual test: CSV upload in transaction-service
   - Verify no runtime errors
   - Verify autoconfiguration still works

**Deliverables**:
- ✅ service-common split into service-core and service-web modules
- ✅ CSV parser refactored to use InputStream (no Spring Web dependency in core)
- ✅ All consuming services updated and building successfully
- ✅ All tests passing
- ✅ Both modules published to Maven Local
- ✅ No breaking changes to public APIs (except CSV parser method signature)

**Files Modified**:
- `service-common/src/.../csv/CsvParser.java`
- `service-common/src/.../csv/impl/OpenCsvParser.java`
- `service-common/src/test/.../csv/impl/OpenCsvParserTest.java`
- `transaction-service/src/.../service/TransactionImportService.java`
- `service-common/build.gradle.kts` (converted to root project)
- `service-common/settings.gradle.kts` (NEW)
- `service-core/build.gradle.kts` (NEW)
- `service-web/build.gradle.kts` (NEW)
- `transaction-service/build.gradle.kts`
- `currency-service/build.gradle.kts`
- `transaction-service/gradle/libs.versions.toml`
- `currency-service/gradle/libs.versions.toml`

---

### Phase 1: Service-Common Audit & Standardization

**Duration**: 1-2 days

**Tasks**:

1. **Audit Existing Conditional Autoconfiguration** ✅
   - Verify `@ConditionalOnWebApplication` on `DefaultApiExceptionHandler`
   - Verify `@ConditionalOnProperty` on `HttpLoggingConfig`
   - Document any other conditional patterns
   - Results: Autoconfiguration patterns already properly implemented

2. **Standardize Configuration Namespaces** ✅
   - Fix transaction-service configuration namespace (budget-analyzer → budgetanalyzer)
   - Update `@ConfigurationProperties` classes to match new namespace
   - Verify currency-service already uses correct namespace
   - Test that configuration still loads correctly
   - Results: Both services now use consistent `budgetanalyzer.*` namespace

3. **Standardize Java Version Management** ✅
   - Add Java version to `gradle/libs.versions.toml` in both services
   - Update `build.gradle.kts` to reference version from catalog
   - Verify Java version is correctly applied
   - Results: Both services use centralized Java version management

4. **Extract and Document Existing Config Files** ✅
   - Extract `.editorconfig` from transaction-service
   - Document `checkstyle.xml` (28KB Google Java Style)
   - Document JVM args pattern for Java 24 compatibility
   - Document test configuration patterns
   - Results: Config files documented for template inclusion

5. **Document Established Autoconfiguration Patterns** ✅
   - Document existing autoconfiguration in service-common
   - Verify patterns work correctly across both services
   - No changes needed, patterns already well-established
   - Results: Patterns documented for template users

**Deliverables**:
   - ✅ Transaction-service with standardized configuration namespaces
   - ✅ Both services with centralized Java version management
   - ✅ Documented config files (.editorconfig, checkstyle.xml)
   - ✅ Documented JVM args and test patterns
   - ✅ All tests passing after changes

---

### Phase 2: GitHub Template Repository Creation

**Duration**: 2-3 days

**Tasks**:

1. **Create Repository**
   - Repository name: `budget-analyzer/spring-boot-service-template`
   - Visibility: Private
   - Enable template repository setting
   - Add standard labels, branch protection

2. **Minimal Template Structure**

   **Root files**:
   ```
   .editorconfig
   .gitignore
   LICENSE
   README.md
   CLAUDE.md
   TEMPLATE_USAGE.md
   build.gradle.kts
   settings.gradle.kts
   gradlew
   gradlew.bat
   ```

   **Gradle configuration**:
   ```
   gradle/
   ├── libs.versions.toml (MINIMAL - core versions only)
   └── wrapper/
       ├── gradle-wrapper.jar
       └── gradle-wrapper.properties (Gradle 8.14.2)
   ```

   **Code quality**:
   ```
   config/
   └── checkstyle/
       └── checkstyle.xml
   ```

   **Source structure**:
   ```
   src/
   ├── main/
   │   ├── java/org/budgetanalyzer/{DOMAIN_NAME}/
   │   │   ├── {ServiceClassName}Application.java
   │   │   ├── api/          # Controllers, DTOs
   │   │   ├── config/       # Configuration classes
   │   │   ├── domain/       # Entities, enums
   │   │   ├── repository/   # Data access
   │   │   └── service/      # Business logic
   │   └── resources/
   │       └── application.yml
   └── test/
       ├── java/org/budgetanalyzer/{DOMAIN_NAME}/
       │   └── {ServiceClassName}ApplicationTests.java
       └── resources/
           └── application.yml
   ```

   **GitHub workflows**:
   ```
   .github/
   ├── CODEOWNERS
   ├── PULL_REQUEST_TEMPLATE.md
   ├── dependabot.yml
   └── workflows/
       └── build.yml (validate template builds)
   ```

3. **Placeholder System**

   **Placeholders**:
   - `{SERVICE_NAME}` → Full service name in kebab-case (e.g., `currency-service`, `transaction-service`)
   - `{DOMAIN_NAME}` → Domain/package name (e.g., `currency`, `session`)
     - Default: First word of service name
     - User can override during script execution
   - `{ServiceClassName}` → PascalCase class name (e.g., `Currency`, `Session`)
     - Derived from `{DOMAIN_NAME}`
   - `{SERVICE_PORT}` → Port number (e.g., `8082`)
   - `{DATABASE_NAME}` → Database name (e.g., `currency`, `session`)
     - Default: Same as `{DOMAIN_NAME}`
     - User can override during script execution
   - `{SERVICE_COMMON_VERSION}` → service-common version (e.g., `0.0.1-SNAPSHOT`)
   - `{JAVA_VERSION}` → Java version (e.g., `24`)

   **Package Structure Pattern**:
   ```
   org.budgetanalyzer.{DOMAIN_NAME}
   ```

   **Examples**:
   - `currency-service` → package: `org.budgetanalyzer.currency`
   - `transaction-service` → package: `org.budgetanalyzer.transaction`

   **Files with placeholders**:
   - `settings.gradle.kts`: rootProject.name
   - `gradle/libs.versions.toml`: serviceCommon version, java version
   - `src/main/resources/application.yml`: server.port, context-path, application.name, configuration properties
   - `src/main/java/.../Application.java`: package, class name
   - `CLAUDE.md`: Service name, port references
   - `README.md`: Service name, descriptions

4. **Configuration Namespace Standard**

   **Root Namespace**: `budgetanalyzer` (no hyphens)

   All configuration properties use `budgetanalyzer` as the root namespace, following a consistent pattern:

   **Service-Common Configurations** (shared features from service-common):
   ```yaml
   budgetanalyzer:
     service:
       http-logging:
         enabled: true
         log-level: DEBUG
         # ... etc
   ```

   **Service-Specific Configurations**:
   ```yaml
   budgetanalyzer:
     {SERVICE_NAME}:  # e.g., currency-service, transaction-service
       # Service-specific properties
   ```

   **Complete Example (Currency Service)**:
   ```yaml
   spring:
     application:
       name: currency-service

   budgetanalyzer:
     service:
       http-logging:
         enabled: true
     currency-service:
       exchange-rate-import:
         cron: "0 0 23 * * ?"
         import-on-startup: true
   ```

   **Java @ConfigurationProperties Classes**:
   ```java
   // Service-common feature
   @ConfigurationProperties(prefix = "budgetanalyzer.service.http-logging")
   public class HttpLoggingProperties { }

   // Service-specific feature
   @ConfigurationProperties(prefix = "budgetanalyzer.{SERVICE_NAME}.{feature-name}")
   public class FeatureProperties { }
   ```

   **Why This Pattern?**
   - Consistent across all services
   - Clear ownership: `budgetanalyzer.service.*` = shared, `budgetanalyzer.{SERVICE_NAME}.*` = specific
   - Prevents configuration collisions
   - IDE auto-completion support

5. **Database Naming Pattern**

   **Default Behavior**: Dedicated database per service

   **Naming Convention**:
   - Database name = `{DOMAIN_NAME}` (e.g., `currency`, `session`)
   - User can override during script execution

   **Script Prompting**:
   ```bash
   Database name (default: {DOMAIN_NAME}, or specify custom): _
   ```

   **Template Configuration (application.yml)**:
   ```yaml
   spring:
     datasource:
       url: jdbc:postgresql://localhost:5432/{DATABASE_NAME}
   ```

   **Special Case - Transaction Service**:
   - Uses shared database `budget_analyzer`
   - Reason: Avoid confusion with SQL "transaction" concept
   - **Note**: This is an exception, not recommended pattern

6. **Minimal Dependencies**

   **libs.versions.toml**:
   ```toml
   [versions]
   java = "{JAVA_VERSION}"
   springBoot = "3.5.7"
   dependencyManagement = "1.1.7"
   spotless = "8.0.0"
   checkstyle = "12.0.1"
   googleJavaFormat = "1.32.0"
   junitPlatform = "1.12.2"
   serviceCommon = "{SERVICE_COMMON_VERSION}"

   [plugins]
   spring-boot = { id = "org.springframework.boot", version.ref = "springBoot" }
   spring-dependency-management = { id = "io.spring.dependency-management", version.ref = "dependencyManagement" }
   spotless = { id = "com.diffplug.spotless", version.ref = "spotless" }

   [libraries]
   # Service-common shared libraries
   service-core = { module = "org.budgetanalyzer:service-core", version.ref = "serviceCommon" }
   service-web = { module = "org.budgetanalyzer:service-web", version.ref = "serviceCommon" }

   # Spring Boot starters
   spring-boot-starter-actuator = { module = "org.springframework.boot:spring-boot-starter-actuator" }

   # Test dependencies
   spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }
   junit-platform-launcher = { module = "org.junit.platform:junit-platform-launcher", version.ref = "junitPlatform" }
   ```

   **build.gradle.kts** (absolute minimum with JVM args):
   ```kotlin
   // JVM arguments for Java 24 compatibility
   val jvmArgsList = listOf(
       "--add-opens=java.base/java.nio=ALL-UNNAMED",
       "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
       "--enable-native-access=ALL-UNNAMED"
   )

   java {
       toolchain {
           languageVersion.set(JavaLanguageVersion.of(libs.versions.java.get().toInt()))
       }
   }

   dependencies {
       // Minimal foundation - logging, exceptions, utilities
       implementation(libs.service.core)

       // Health checks and metrics
       implementation(libs.spring.boot.starter.actuator)

       testImplementation(libs.spring.boot.starter.test)
       testRuntimeOnly(libs.junit.platform.launcher)
   }

   tasks.withType<Test> {
       jvmArgs = jvmArgsList
   }

   tasks.withType<JavaExec> {
       jvmArgs = jvmArgsList
   }

   tasks.named<org.springframework.boot.gradle.tasks.run.BootRun>("bootRun") {
       jvmArgs = jvmArgsList
   }
   ```

   **Note**: This provides a non-web baseline. Add `service-web` dependency for REST API services (see Spring Boot Web add-on).

7. **Minimal application.yml with Standard Configurations**

   **Minimal Non-Web application.yml**:
   ```yaml
   spring:
     application:
       name: {SERVICE_NAME}

     jackson:
       default-property-inclusion: non_null
       serialization:
         indent-output: true
         write-dates-as-timestamps: false
       date-format: com.fasterxml.jackson.databind.util.StdDateFormat

   management:
     endpoints:
       web:
         exposure:
           include: health,info,metrics
     endpoint:
       health:
         show-details: when-authorized

   logging:
     level:
       root: WARN
       org.budgetanalyzer: TRACE

   # Add service-specific configuration here
   budgetanalyzer:
     {SERVICE_NAME}:
       # your-property: value
   ```

   **Note**: Configuration is intentionally minimal. Add-ons will add their own configuration sections:
   - **Spring Boot Web** - server.port, spring.mvc.servlet.path, budgetanalyzer.service.http-logging
   - **PostgreSQL + Flyway** - spring.datasource, spring.jpa, spring.flyway
   - **Redis** - spring.data.redis, spring.cache
   - **RabbitMQ** - spring.rabbitmq, spring.cloud.stream

   **Test Configuration (src/test/resources/application.yml)**:
   ```yaml
   logging:
     level:
       org.budgetanalyzer: DEBUG

   budgetanalyzer:
     {SERVICE_NAME}:
       # Service-specific test properties
   ```

8. **Example Test Classes**

   **Context Load Test (src/test/java/org/budgetanalyzer/{DOMAIN_NAME}/ApplicationTests.java)**:
   ```java
   @SpringBootTest
   class ApplicationTests {
       @Test
       void contextLoads() {
       }
   }
   ```

9. **Code Quality Configuration Files**

   **`.editorconfig`** (from transaction-service):
   ```
   root = true

   [*]
   charset = utf-8
   end_of_line = lf
   insert_final_newline = true

   [*.java]
   indent_style = space
   indent_size = 2
   trim_trailing_whitespace = true
   ```

   **`config/checkstyle/checkstyle.xml`**:
   - Source: transaction-service/config/checkstyle/checkstyle.xml
   - Size: 28KB (514 lines)
   - Format: Google Java Style configuration
   - Action: Copy complete file to template repository
   - Note: This is a standard Google Java Style checkstyle configuration
   - Enforces consistent code formatting across all services

5. **Template Validation**
   - GitHub Actions workflow validates template builds
   - Runs spotlessCheck, checkstyleMain
   - Runs tests
   - Ensures template is always in working state

6. **Documentation**
   - README.md: Template overview, features
   - TEMPLATE_USAGE.md: Detailed usage instructions
   - CLAUDE.md template with placeholder sections
   - CODEOWNERS: Assign template ownership

7. **Deliverables**
   - GitHub template repository created and configured
   - Template builds successfully
   - CI/CD pipeline validates template
   - Documentation complete

---

### Phase 3: Add-On Documentation

**Duration**: 2-3 days

**Location**: `/workspace/orchestration/docs/service-creation/addons/`

**Add-On Guides**:

1. **postgresql-flyway.md**
   - Purpose: Database persistence with schema migration
   - Dependencies to add (libs.versions.toml + build.gradle.kts)
   - Configuration (application.yml)
   - Directory structure (db/migration/)
   - Initial migration template
   - Testing with H2 vs TestContainers
   - Base entity classes (AuditableEntity, SoftDeletableEntity)

2. **redis.md**
   - Purpose: Caching and session storage
   - Dependencies
   - Configuration
   - Cache configuration class
   - Common caching patterns
   - Testing with TestContainers

3. **rabbitmq-spring-cloud.md** (future)
   - Purpose: Event-driven messaging
   - Dependencies (Spring Cloud Stream, Spring Modulith)
   - Configuration (exchanges, bindings)
   - Event publishing patterns
   - Event consumption patterns
   - Testing with TestContainers

4. **webclient.md** ✅
   - Purpose: HTTP client for calling external APIs (WebFlux WebClient)
   - Dependencies
   - WebClient configuration
   - Common patterns (REST calls, error handling)
   - Testing with MockWebServer
   - Real example: currency-service FRED API integration

5. **testcontainers.md** ✅
   - Purpose: Integration testing with real PostgreSQL
   - Dependencies (TestContainers Core, PostgreSQL, JUnit Jupiter)
   - Configuration (BaseRepositoryTest pattern)
   - Usage examples (repository tests, integration tests)
   - Singleton container pattern for faster tests
   - CI/CD configuration

6. **spring-modulith.md** ✅
   - Purpose: Module boundaries and event-driven communication
   - Dependencies
   - Module structure and package organization
   - Event publishing/subscribing with @ApplicationModuleListener
   - Event persistence with JPA
   - Module verification tests

7. **scheduling.md** ✅
   - Purpose: Scheduled tasks using @Scheduled
   - Configuration (@EnableScheduling, thread pool)
   - Usage examples (fixedRate, fixedDelay, cron)
   - Real example: currency-service exchange rate import
   - Distributed scheduling considerations (ShedLock reference)

8. **shedlock.md** (future)
   - Purpose: Distributed scheduled task locking
   - Dependencies
   - Configuration
   - Database migration for shedlock table
   - Usage with @SchedulerLock

9. **springdoc-openapi.md** ✅
   - Purpose: API documentation with OpenAPI/Swagger
   - Dependencies
   - Configuration (extends BaseOpenApiConfig)
   - Annotations for documentation (@Operation, @Schema, @Tag)
   - Accessing Swagger UI
   - Real example: transaction-service API docs

10. **redis.md** (future)
    - Purpose: Caching and session storage
    - Dependencies
    - Configuration
    - Cache configuration class
    - Common caching patterns
    - Testing with TestContainers

11. **spring-security.md** (future)
    - Purpose: Authentication and authorization
    - Dependencies
    - Security configuration
    - Common patterns

**Each guide includes**:
- Use cases and when to use
- Step-by-step dependency addition
- Configuration examples
- Code examples
- Testing approach
- Links to official documentation

**Deliverables**:
- All add-on guides completed
- Index document: `addons/README.md`
- Reviewed and validated

---

### Phase 4: Interactive Creation Script

**Duration**: 3-4 days

**Script**: `/workspace/orchestration/scripts/create-service.sh`

**Features**:

1. **Interactive Prompts**
   ```bash
   Service name (e.g., 'currency-service'):
   Domain name [currency] (or specify custom):
   Service port (e.g., 8082):
   Java version [24]:
   service-common version [0.0.1-SNAPSHOT]:
   PostgreSQL database name (leave empty for shared 'budget_analyzer'):
   ```

2. **Add-On Selection**
   ```bash
   Select add-ons (y/n):
   [ ] PostgreSQL + Flyway
   [ ] Redis caching
   [ ] RabbitMQ messaging (includes Spring Cloud/Modulith)
   [ ] WebFlux (reactive HTTP client)
   [ ] ShedLock (distributed scheduling)
   [ ] SpringDoc OpenAPI
   [ ] Spring Security (future)
   ```

3. **Validation**
   - Service name: lowercase, alphanumeric + hyphens, starts with letter
   - Port: number between 1024-65535, not already in use
   - Database name: valid PostgreSQL identifier
   - Versions: semantic version format

4. **Generation Process**
   ```bash
   1. Clone GitHub template repository
   2. Replace all placeholders in files
   3. Rename directories (org/budgetanalyzer/{DOMAIN_NAME})
   4. Apply selected add-ons:
      - Add dependencies to libs.versions.toml
      - Add dependencies to build.gradle.kts
      - Add configuration to application.yml
      - Create necessary directories (db/migration, etc.)
      - Create template files (migrations, configs, etc.)
   5. Initialize git repository
   6. Create initial commit
   7. Optionally create GitHub repository
   8. Run build validation (./gradlew clean build)
   9. Report success/failure
   ```

5. **GitHub Integration**
   - Use `gh` CLI for repository creation
   - Set repository to private
   - Push initial commit
   - Set up branch protection (optional)

6. **Post-Generation**
   - Print summary of created service
   - Show next steps (add to docker-compose.yml, configure nginx, etc.)
   - Provide links to relevant documentation

7. **Error Handling**
   - Validate all inputs before proceeding
   - Check prerequisites (git, gh CLI, Java, Gradle)
   - Rollback on failure (clean up generated files)
   - Provide helpful error messages

**Deliverables**:
- Fully functional create-service.sh script
- Script tested with multiple scenarios
- Error handling comprehensive
- Documentation for script usage

---

### Phase 5: Documentation & ADRs

**Duration**: 1-2 days

**Documents to Create**:

1. **ADR: Service-Common Dependency Strategy**
   - File: `docs/decisions/005-service-common-dependency-strategy.md`
   - Content: Decision from Phase 1, rationale, consequences

2. **ADR: Java Version Management**
   - File: `docs/decisions/006-java-version-management.md`
   - Content: Using libs.versions.toml for Java version
   - Upgrade process documentation

3. **Service Creation Guide**
   - File: `docs/service-creation/README.md`
   - Content: Complete guide to creating services
   - When to use script vs manual template
   - Common patterns and best practices

4. **Update Orchestration CLAUDE.md**
   - Add "Service Creation Workflow" section
   - Link to template repository
   - Link to add-on documentation
   - Quick reference for common operations

5. **Standardized CLAUDE.md Template**
   - File: `templates/CLAUDE.md.template`
   - Standard sections all services should have
   - Placeholder-driven for easy customization

**Deliverables**:
- All documentation complete
- Cross-references validated
- Discovery commands tested
- Reviewed for clarity

---

### Phase 6: Testing & Validation

**Duration**: 2-3 days
**Status**: 🔄 In Progress (Phase 6.1 Complete, Full Testing Ongoing)

**Test Scenarios**:

1. **Minimal Non-Web Service**
   ```bash
   ./create-service.sh
   # Name: test-minimal
   # Add-ons: None
   ```
   - Verify builds successfully
   - Verify runs briefly (./gradlew bootRun) then exits (no web container)
   - Verify service-core utilities available (logging, exceptions)
   - Verify code quality checks pass (spotlessCheck, checkstyleMain)

2. **REST API Service**
   ```bash
   ./create-service.sh
   # Name: test-rest-api
   # Port: 9991
   # Add-ons: Spring Boot Web, PostgreSQL + Flyway, SpringDoc OpenAPI
   ```
   - Verify builds successfully
   - Verify runs with embedded Tomcat on port 9991
   - Verify actuator endpoints accessible
   - Verify Swagger UI accessible at /swagger-ui.html
   - Verify database connection and migrations
   - Verify HTTP request logging works

3. **Message Consumer Service (Non-Web)**
   ```bash
   ./create-service.sh
   # Name: test-consumer
   # Add-ons: PostgreSQL + Flyway, RabbitMQ + Spring Cloud, Spring Modulith
   ```
   - Verify builds successfully
   - Verify runs without web container (no Tomcat)
   - Verify database connection works
   - Verify RabbitMQ connection works
   - Verify event handling setup correct

4. **Scheduled Batch Service (Non-Web)**
   ```bash
   ./create-service.sh
   # Name: test-batch
   # Add-ons: PostgreSQL + Flyway, Scheduling, ShedLock
   ```
   - Verify builds successfully
   - Verify runs without web container
   - Verify scheduling configuration present
   - Verify ShedLock database table created
   - Verify database connection works

5. **Full-Featured REST Service**
   ```bash
   ./create-service.sh
   # Name: test-full
   # Port: 9992
   # Add-ons: Spring Boot Web, PostgreSQL, Redis, TestContainers, SpringDoc
   ```
   - Verify all dependencies resolve
   - Verify builds successfully
   - Verify all autoconfiguration activates
   - Verify no conflicts between add-ons

6. **Manual Template Usage**
   - Use GitHub "Use this template" button
   - Clone repository
   - Manually replace placeholders
   - Add Spring Boot Web add-on manually
   - Verify builds

7. **GitHub Template Validation**
   - Verify CI/CD pipeline passes
   - Verify template repository builds
   - Verify no broken links in documentation

8. **Code Quality**
   - Run spotlessCheck on generated services
   - Run checkstyleMain on generated services
   - Verify no warnings/errors

**Deliverables**:
- All test scenarios pass
- Issues documented and fixed
- Template validated as production-ready

**Current Status** (2025-11-17):

**Completed**:
- ✅ Phase 6.1: Service-common module split and auto-configuration refactoring
- ✅ Test Scenario 1: Minimal Non-Web Service (passed with automated fix)
- ✅ Template repository builds successfully
- ✅ Automated testing script created (scripts/test-phase-6.sh)
- ✅ Comprehensive testing guide created (docs/service-creation/phase-6-testing-guide.md)
- ✅ DataSource auto-exclusion fix implemented in create-service.sh

**In Progress**:
- ⏳ Test Scenario 2: REST API Service (Web + PostgreSQL + SpringDoc)
- ⏳ Test Scenario 3: Message Consumer Service
- ⏳ Test Scenario 4: Scheduled Batch Service
- ⏳ Test Scenario 5: Full-Featured REST Service
- ⏳ Test Scenario 6: Manual Template Usage
- ⏳ Test Scenario 7: GitHub Template Validation (build test passed)
- ⏳ Test Scenario 8: Code Quality Checks

**Blockers**:
- ✅ Scheduling add-on implemented (blocker resolved)
- ✅ TestContainers add-on implemented with smoke test pattern (blocker resolved)
- ⚠️ ShedLock add-on fully implemented in template repository (see addons/shedlock)
- Interactive script makes full automation challenging
  (Note: This is a design choice, not a blocker. Non-interactive mode not currently needed.)

**Next Actions**:
1. Execute remaining test scenarios manually following phase-6-testing-guide.md
2. Document results in phase-6-testing-report.md
3. Implement missing add-ons or mark as future work
4. Complete Phase 6 validation

---

### Phase 7: Post-Template Development

**Duration**: Ongoing

**Purpose**: This phase covers service development that occurs after the template system is in place.

#### Template Service Types

This template supports multiple service types by using different add-on combinations:

**Supported Service Types:**

1. **REST API Services** ✅
   - Add-ons: Spring Boot Web (required), PostgreSQL, SpringDoc OpenAPI, etc.
   - Use case: Traditional HTTP/JSON microservices
   - Architecture: Servlet-based (blocking I/O) with embedded Tomcat
   - Examples: transaction-service, currency-service

2. **Message Consumer Services** ✅
   - Add-ons: RabbitMQ + Spring Cloud, PostgreSQL, Spring Modulith
   - Use case: Event-driven background processors
   - Architecture: No web container, listens to RabbitMQ queues
   - Examples: Audit log processor, notification sender

3. **Scheduled Batch Services** ✅
   - Add-ons: Scheduling, ShedLock (for multi-instance), PostgreSQL
   - Use case: Periodic background tasks, data imports, cleanup jobs
   - Architecture: No web container, runs on schedule
   - Examples: Currency rate importer, data archiver

4. **CLI Tools** ✅
   - Add-ons: None (base template only)
   - Use case: Command-line utilities, one-off data migrations
   - Architecture: Minimal Spring Boot, runs and exits
   - Examples: Data migration tools, administrative utilities

**Unsupported Service Types:**

5. **Reactive Services** ❌
   - Examples: Spring Cloud Gateway, fully reactive WebFlux applications
   - Reason: Different architecture (reactive/non-blocking vs servlet/blocking)
   - Solution: Create manually using Spring Cloud Gateway or WebFlux patterns
   - Future: Consider separate "Reactive Microservice Template" if needed

**Key Principle**: The template provides a **minimal non-web baseline** (`service-core` only). Add web support via the Spring Boot Web add-on only when needed for REST APIs. This allows the template to support both web and non-web service types.

#### Using the Template for New Services

Once the template is ready, new microservices follow this workflow:

1. **Run Creation Script**
   ```bash
   cd /workspace/orchestration
   ./scripts/create-service.sh
   ```

2. **Configure Service**
   - Provide service name
   - Provide port (if using Spring Boot Web add-on)
   - Provide database name (if using PostgreSQL add-on)
   - Select add-ons based on service type:
     - **REST API**: Spring Boot Web, PostgreSQL, SpringDoc OpenAPI
     - **Message Consumer**: RabbitMQ, PostgreSQL, Spring Modulith
     - **Batch Job**: Scheduling, ShedLock (if multi-instance), PostgreSQL
     - **CLI Tool**: None
   - Review generated structure

3. **Validate**
   - Verify builds successfully
   - Verify runs locally (with or without web container, depending on add-ons)
   - Run tests

4. **Integrate** (if applicable)
   - Add to orchestration docker-compose.yml (if using infrastructure services)
   - Configure nginx routing (if REST API service)
   - Update orchestration documentation

5. **Implement Features**
   - Add domain logic
   - Add API endpoints (if web service)
   - Add message consumers (if messaging service)
   - Add scheduled tasks (if batch service)
   - Write tests
   - Deploy

**Deliverables**:
- New services created using validated template
- Services integrated into orchestration
- Template continuously improved based on learnings

---

## Success Criteria

### Quantitative Metrics

1. **Service Creation Time**
   - Baseline: 2-3 hours (manual setup)
   - Target: < 15 minutes (with script)

2. **Template Consistency**
   - All new services use template: 100%
   - Code quality checks pass: 100%
   - Build success rate: 100%

3. **Documentation Coverage**
   - All add-ons documented: 100%
   - All discovery commands tested: 100%
   - No broken links: 100%

### Qualitative Metrics

1. **Developer Experience**
   - Survey rating: > 4.5/5
   - Ease of use: High
   - Documentation clarity: High

2. **Maintainability**
   - Template ownership assigned
   - Update process documented
   - Version control in place

3. **Adoption**
   - New servlet-based services use template
   - Team trained on process
   - Clear guidance for reactive services

---

## Risks & Mitigation

### Risk 1: service-common Breaking Changes

**Impact**: Existing services fail to build

**Likelihood**: Medium

**Mitigation**:
- Semantic versioning for service-common
- Test with all existing services before publishing
- Document migration path
- Maintain backward compatibility where possible

### Risk 2: Template Drift

**Impact**: Template becomes outdated

**Likelihood**: High (over time)

**Mitigation**:
- Assign template owner
- Regular review cadence (quarterly)
- Update template when patterns change
- Version template with changelog

### Risk 3: Script Bugs

**Impact**: Generated services don't work

**Likelihood**: Medium

**Mitigation**:
- Comprehensive testing before production use
- Build validation in script
- Error handling and rollback
- Manual template option available

### Risk 4: Add-On Conflicts

**Impact**: Some add-on combinations don't work together

**Likelihood**: Low

**Mitigation**:
- Test common combinations
- Document known conflicts
- Validation in script for incompatible combinations

---

## Timeline

**Total Duration**: 3-4 weeks

```
Week 1:
├── Phase 0: Service-Common Module Split (2-3 days)
├── Phase 1: Service-Common Audit & Standardization (1-2 days)
└── Phase 2: GitHub Template Creation (2-3 days)

Week 2:
├── Phase 3: Add-On Documentation (3 days)
└── Phase 4: Creation Script (2 days)

Week 3:
├── Phase 4: Script Testing (2 days)
├── Phase 5: Documentation (2 days)
└── Phase 6: Testing & Validation (2 days)

Week 4:
├── Phase 6: Testing & Validation (1 day)
└── Phase 7: Post-Template Development (ongoing)
```

**Critical Path**: Phase 0 → Phase 1 → Phase 2 → Phase 4 → Phase 6

**Parallel Work**: Phase 3 can happen alongside Phase 4

**Note**: Phase 0 is a prerequisite for the template system, as it establishes the foundational module structure that the template will depend on.

---

## Next Steps

1. **Review this plan** with team and stakeholders
2. **Prioritize phases** based on immediate needs
3. **Assign ownership** for each phase
4. **Begin Phase 1**: Service-Common evaluation
5. **Schedule reviews** at end of each phase
6. **Iterate** based on learnings

---

## Appendix A: Java Version Management Strategy

**Current State**:
- All services use Java 24
- Specified in each service's build.gradle.kts
- Gradle toolchain manages JDK

**Proposed Strategy**:

1. **Define in libs.versions.toml**:
   ```toml
   [versions]
   java = "24"
   ```

2. **Reference in build.gradle.kts**:
   ```kotlin
   java {
       toolchain {
           languageVersion = JavaLanguageVersion.of(libs.versions.java.get().toInt())
       }
   }
   ```

3. **Upgrade Process**:
   - Update `java` version in libs.versions.toml
   - Test service builds
   - Test service runs
   - Update JVM args if needed (--add-opens, etc.)
   - Commit change

**Benefits**:
- Single source of truth per service
- Easy to see current version
- Simple upgrade process
- Can upgrade services individually or all at once

**Note**: This is per-service versioning. Cross-service version management would require shared version catalog or composite build (future enhancement).

---

## Appendix B: Placeholder Replacement Algorithm

**String Replacement**:
```bash
# Service name conversions
SERVICE_NAME="currency-service"  # User input
DOMAIN_NAME="currency"           # Default: first word, or user override
SERVICE_CLASS_NAME="Currency"    # Capitalized domain name

# File content replacement
find "$SERVICE_DIR" -type f -exec sed -i \
    -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
    -e "s/{DOMAIN_NAME}/$DOMAIN_NAME/g" \
    -e "s/{ServiceClassName}/$SERVICE_CLASS_NAME/g" \
    -e "s/{SERVICE_PORT}/$SERVICE_PORT/g" \
    -e "s/{DATABASE_NAME}/$DATABASE_NAME/g" \
    -e "s/{SERVICE_COMMON_VERSION}/$SERVICE_COMMON_VERSION/g" \
    -e "s/{JAVA_VERSION}/$JAVA_VERSION/g" \
    {} \;
```

**Directory Renaming**:
```bash
# Rename Java package directories from template to actual domain name
mv "$SERVICE_DIR/src/main/java/org/budgetanalyzer/template" \
   "$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME"

mv "$SERVICE_DIR/src/test/java/org/budgetanalyzer/template" \
   "$SERVICE_DIR/src/test/java/org/budgetanalyzer/$DOMAIN_NAME"
```

**File Renaming**:
```bash
# Rename Application class
mv "$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME/TemplateApplication.java" \
   "$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME/${SERVICE_CLASS_NAME}Application.java"

mv "$SERVICE_DIR/src/test/java/org/budgetanalyzer/$DOMAIN_NAME/TemplateApplicationTests.java" \
   "$SERVICE_DIR/src/test/java/org/budgetanalyzer/$DOMAIN_NAME/${SERVICE_CLASS_NAME}ApplicationTests.java"
```

---

## Appendix C: Add-On Application Logic

**PostgreSQL + Flyway Add-On**:
```bash
if [[ $USE_POSTGRESQL =~ ^[Yy]$ ]]; then
    # Add to libs.versions.toml
    cat >> "$SERVICE_DIR/gradle/libs.versions.toml" <<EOF

# PostgreSQL + Flyway
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-validation = { module = "org.springframework.boot:spring-boot-starter-validation" }
flyway-core = { module = "org.flywaydb:flyway-core" }
flyway-database-postgresql = { module = "org.flywaydb:flyway-database-postgresql" }
postgresql = { module = "org.postgresql:postgresql" }
h2 = { module = "com.h2database:h2" }
EOF

    # Add to build.gradle.kts dependencies block
    sed -i '/testRuntimeOnly(libs.junit.platform.launcher)/a \    \n    // PostgreSQL + Flyway\n    implementation(libs.spring.boot.starter.data.jpa)\n    implementation(libs.spring.boot.starter.validation)\n    implementation(libs.flyway.core)\n    implementation(libs.flyway.database.postgresql)\n    runtimeOnly(libs.postgresql)\n    testImplementation(libs.h2)' \
        "$SERVICE_DIR/build.gradle.kts"

    # Add to application.yml
    cat >> "$SERVICE_DIR/src/main/resources/application.yml" <<EOF

spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/${DATABASE_NAME}
    username: budget_analyzer
    password: budget_analyzer
    driver-class-name: org.postgresql.Driver

  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false
    database-platform: org.hibernate.dialect.PostgreSQLDialect

  flyway:
    enabled: true
    locations: classpath:db/migration
    validate-on-migrate: true
EOF

    # Create migration directory
    mkdir -p "$SERVICE_DIR/src/main/resources/db/migration"

    # Create initial migration
    cat > "$SERVICE_DIR/src/main/resources/db/migration/V1__initial_schema.sql" <<EOF
-- Initial schema for ${SERVICE_NAME}

-- Example table (customize as needed)
-- CREATE TABLE example (
--     id BIGSERIAL PRIMARY KEY,
--     created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     deleted BOOLEAN NOT NULL DEFAULT FALSE
-- );
EOF
fi
```

**Similar logic for other add-ons**: Redis, RabbitMQ, WebFlux, ShedLock, SpringDoc

---

## Conclusion

This plan provides a comprehensive roadmap for creating a standardized Spring Boot microservice template and creation system. The approach prioritizes:

1. **Minimal baseline** with optional add-ons
2. **GitHub template repository** as source of truth
3. **Interactive creation script** for automation
4. **Comprehensive documentation** for all patterns
5. **Validation with test services** before production use

Implementation will proceed in phases, with each phase building on the previous one. The plan balances long-term maintainability (template repository, documentation, automation) with flexibility for different service types (servlet-based vs reactive).

**Key Success Factor**: Completing Phase 1 (service-common evaluation) is critical for determining the final template structure.
