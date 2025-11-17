# Complete Template Extraction Plan: Remove All Embedded Content from create-service.sh

## Overview

Extract **~200 lines of embedded configuration/code** from `create-service.sh` into **30 template files** organized in the `spring-boot-service-template` repository. This ensures all text is pre-verified, independently testable, and follows the "cut and paste pre-verified pieces" principle.

---

## Phase 1: Extract Templates to spring-boot-service-template Repository

### 1.1 Create Addon Directory Structure

```
spring-boot-service-template/
├── base/                                     # Minimal non-web baseline
│   ├── build.gradle.kts
│   ├── gradle/libs.versions.toml
│   ├── src/main/java/.../Application.java   # With DataSource exclusions
│   └── src/main/resources/application.yml   # Minimal config
│
└── addons/                                   # One directory per addon
    ├── spring-boot-web/
    │   ├── libs.versions.toml
    │   ├── build.gradle.kts
    │   ├── application.yml
    │   └── Application.java.patch
    │
    ├── postgresql-flyway/
    │   ├── libs.versions.toml
    │   ├── build.gradle.kts
    │   ├── application.yml
    │   ├── Application.java.patch
    │   └── V1__initial_schema.sql
    │
    ├── redis/
    │   ├── libs.versions.toml
    │   ├── build.gradle.kts
    │   └── application.yml
    │
    ├── rabbitmq-spring-cloud/
    │   ├── libs.versions.toml
    │   ├── build.gradle.kts.dependencyManagement
    │   ├── build.gradle.kts.dependencies
    │   └── application.yml
    │
    ├── webflux/
    │   ├── libs.versions.toml
    │   └── build.gradle.kts
    │
    ├── shedlock/
    │   ├── libs.versions.toml
    │   ├── build.gradle.kts
    │   └── V2__create_shedlock_table.sql
    │
    ├── springdoc/
    │   ├── libs.versions.toml
    │   └── build.gradle.kts
    │
    └── spring-security/
        ├── libs.versions.toml
        └── build.gradle.kts
```

**Total: 8 addon directories, 30 template files**

---

### 1.2 Base Template Updates

#### Update: src/main/java/org/budgetanalyzer/test/TestApplication.java

Make this the **non-web baseline with DataSource exclusions**:

```java
package org.budgetanalyzer.{DOMAIN_NAME};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;

@SpringBootApplication(
    exclude = {DataSourceAutoConfiguration.class, HibernateJpaAutoConfiguration.class})
public class {ServiceClassName}Application {

  public static void main(String[] args) {
    SpringApplication.run({ServiceClassName}Application.class, args);
  }
}
```

**Rationale**: Non-web services need exclusions. Addons will remove them when appropriate.

#### Update: src/main/resources/application.yml

Complete production-ready baseline (extracted from docs):

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

budgetanalyzer:
  {SERVICE_NAME}:
    # Service-specific properties here
```

#### Update: gradle/libs.versions.toml

Minimal baseline with service-core:

```toml
[versions]
java = "{JAVA_VERSION}"
springBoot = "3.5.7"
serviceCommon = "{SERVICE_COMMON_VERSION}"

[libraries]
service-core = { module = "org.budgetanalyzer:service-core", version.ref = "serviceCommon" }

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "springBoot" }
spring-dependency-management = { id = "io.spring.dependency-management", version = "1.1.7" }
```

---

### 1.3 Spring Boot Web Add-On Templates

#### Create: addons/spring-boot-web/libs.versions.toml

```toml
# Spring Boot Web - Changes service-core to service-web
service-web = { module = "org.budgetanalyzer:service-web", version.ref = "serviceCommon" }
```

**Note**: Script will REPLACE `service-core` line with this

#### Create: addons/spring-boot-web/build.gradle.kts

```kotlin
    // Spring Boot Web (already included via service-web)
```

**Note**: service-web transitively includes spring-boot-starter-web

#### Create: addons/spring-boot-web/application.yml

Complete configuration from documentation:

```yaml
server:
  port: {SERVICE_PORT}

spring:
  mvc:
    servlet:
      path: /{SERVICE_NAME}

budgetanalyzer:
  service:
    http-logging:
      enabled: true
      log-level: DEBUG
      include-request-body: true
      include-response-body: true
      max-body-size: 10000
      exclude-patterns:
        - /actuator/**
        - /swagger-ui/**
        - /v3/api-docs/**
```

#### Create: addons/spring-boot-web/Application.java.patch

Script instructions for removing DataSource exclusions (if PostgreSQL NOT selected):

```
# Remove exclusions from @SpringBootApplication
# Replace:
#   @SpringBootApplication(
#       exclude = {DataSourceAutoConfiguration.class, HibernateJpaAutoConfiguration.class})
# With:
#   @SpringBootApplication
#
# Remove imports:
#   import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;
#   import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;
```

---

### 1.4 PostgreSQL + Flyway Add-On Templates

#### Create: addons/postgresql-flyway/libs.versions.toml

```toml
# PostgreSQL + Flyway
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-validation = { module = "org.springframework.boot:spring-boot-starter-validation" }
flyway-core = { module = "org.flywaydb:flyway-core" }
flyway-database-postgresql = { module = "org.flywaydb:flyway-database-postgresql" }
postgresql = { module = "org.postgresql:postgresql" }
h2 = { module = "com.h2database:h2" }
```

#### Create: addons/postgresql-flyway/build.gradle.kts

```kotlin
    // PostgreSQL + Flyway
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.flyway.core)
    implementation(libs.flyway.database.postgresql)
    runtimeOnly(libs.postgresql)
    testImplementation(libs.h2)
```

#### Create: addons/postgresql-flyway/application.yml

Complete configuration from documentation:

```yaml
  datasource:
    url: jdbc:postgresql://localhost:5432/{DATABASE_NAME}
    username: ${DB_USERNAME:postgres}
    password: ${DB_PASSWORD:postgres}
    driver-class-name: org.postgresql.Driver

  jpa:
    hibernate:
      ddl-auto: validate
    open-in-view: false
    properties:
      hibernate:
        format_sql: true
    show-sql: false

  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true
    validate-on-migrate: true
```

#### Create: addons/postgresql-flyway/Application.java.patch

```
# Remove DataSource exclusions (PostgreSQL needs them active)
# Same as spring-boot-web/Application.java.patch
```

#### Create: addons/postgresql-flyway/V1__initial_schema.sql

```sql
-- Initial schema for {SERVICE_NAME}

-- Example table (customize as needed)
-- CREATE TABLE example (
--     id BIGSERIAL PRIMARY KEY,
--     created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     deleted BOOLEAN NOT NULL DEFAULT FALSE
-- );
```

---

### 1.5 Redis Add-On Templates

#### Create: addons/redis/libs.versions.toml

```toml
# Redis
spring-boot-starter-data-redis = { module = "org.springframework.boot:spring-boot-starter-data-redis" }
spring-boot-starter-cache = { module = "org.springframework.boot:spring-boot-starter-cache" }
```

#### Create: addons/redis/build.gradle.kts

```kotlin
    // Redis
    implementation(libs.spring.boot.starter.data.redis)
    implementation(libs.spring.boot.starter.cache)
```

#### Create: addons/redis/application.yml

Complete configuration from documentation:

```yaml
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD:}
      database: 0
      timeout: 2000ms
      lettuce:
        pool:
          max-active: 8
          max-idle: 8
          min-idle: 0
          max-wait: -1ms

  cache:
    type: redis
    redis:
      time-to-live: 600000  # 10 minutes
      cache-null-values: false
      use-key-prefix: true
      key-prefix: "{SERVICE_NAME}:"
```

---

### 1.6 RabbitMQ + Spring Cloud Add-On Templates

#### Create: addons/rabbitmq-spring-cloud/libs.versions.toml

```toml
# RabbitMQ + Spring Cloud Stream
springCloudVersion = "2024.0.1"

[libraries]
spring-cloud-stream = { module = "org.springframework.cloud:spring-cloud-stream" }
spring-cloud-stream-binder-rabbit = { module = "org.springframework.cloud:spring-cloud-stream-binder-rabbit" }
spring-modulith-events-amqp = { module = "org.springframework.modulith:spring-modulith-events-amqp" }
```

#### Create: addons/rabbitmq-spring-cloud/build.gradle.kts.dependencyManagement

**Special file - PREPENDED before dependencies block**:

```kotlin
dependencyManagement {
    imports {
        mavenBom("org.springframework.cloud:spring-cloud-dependencies:2024.0.1")
    }
}
```

#### Create: addons/rabbitmq-spring-cloud/build.gradle.kts.dependencies

**Standard file - APPENDED to dependencies**:

```kotlin
    // RabbitMQ + Spring Cloud Stream
    implementation(libs.spring.cloud.stream)
    implementation(libs.spring.cloud.stream.binder.rabbit)
    implementation(libs.spring.modulith.events.amqp)
```

#### Create: addons/rabbitmq-spring-cloud/application.yml

Complete configuration from documentation:

```yaml
  rabbitmq:
    host: ${RABBITMQ_HOST:localhost}
    port: ${RABBITMQ_PORT:5672}
    username: ${RABBITMQ_USERNAME:guest}
    password: ${RABBITMQ_PASSWORD:guest}
    virtual-host: /
    connection-timeout: 30000
    requested-heartbeat: 60

  cloud:
    stream:
      default-binder: rabbit
      bindings:
        # Example output channel (publishing events)
        output-out-0:
          destination: {SERVICE_NAME}.events
          content-type: application/json
        # Example input channel (consuming events)
        input-in-0:
          destination: other-service.events
          group: {SERVICE_NAME}
          content-type: application/json
      rabbit:
        bindings:
          output-out-0:
            producer:
              routing-key-expression: headers['routingKey']
              delivery-mode: PERSISTENT
          input-in-0:
            consumer:
              auto-bind-dlq: true
              republish-to-dlq: true
```

---

### 1.7 WebFlux Add-On Templates

#### Create: addons/webflux/libs.versions.toml

```toml
# WebFlux (for WebClient HTTP client)
spring-boot-starter-webflux = { module = "org.springframework.boot:spring-boot-starter-webflux" }
reactor-test = { module = "io.projectreactor:reactor-test" }
```

#### Create: addons/webflux/build.gradle.kts

```kotlin
    // WebClient for HTTP calls
    implementation(libs.spring.boot.starter.webflux)

    // Testing reactive components
    testImplementation(libs.reactor.test)
```

**Note**: No application.yml (requires manual WebClientConfig class)

---

### 1.8 ShedLock Add-On Templates

#### Create: addons/shedlock/libs.versions.toml

```toml
# ShedLock (distributed scheduled task locking)
shedlock = "5.17.1"

[libraries]
shedlock-spring = { module = "net.javacrumbs.shedlock:shedlock-spring", version.ref = "shedlock" }
shedlock-provider-jdbc-template = { module = "net.javacrumbs.shedlock:shedlock-provider-jdbc-template", version.ref = "shedlock" }
```

#### Create: addons/shedlock/build.gradle.kts

```kotlin
    // ShedLock (distributed scheduled task locking)
    implementation(libs.shedlock.spring)
    implementation(libs.shedlock.provider.jdbc.template)
```

#### Create: addons/shedlock/V2__create_shedlock_table.sql

```sql
-- ShedLock table for distributed scheduled task locking

CREATE TABLE shedlock (
    name VARCHAR(64) NOT NULL PRIMARY KEY,
    lock_until TIMESTAMP NOT NULL,
    locked_at TIMESTAMP NOT NULL,
    locked_by VARCHAR(255) NOT NULL
);

CREATE INDEX idx_shedlock_lock_until ON shedlock(lock_until);
```

---

### 1.9 SpringDoc OpenAPI Add-On Templates

#### Create: addons/springdoc/libs.versions.toml

```toml
# SpringDoc OpenAPI
springdoc = "2.7.0"

[libraries]
springdoc-openapi-starter-webmvc-ui = { module = "org.springdoc:springdoc-openapi-starter-webmvc-ui", version.ref = "springdoc" }
```

#### Create: addons/springdoc/build.gradle.kts

```kotlin
    // SpringDoc OpenAPI
    implementation(libs.springdoc.openapi.starter.webmvc.ui)
```

---

### 1.10 Spring Security Add-On Templates

#### Create: addons/spring-security/libs.versions.toml

```toml
# Spring Security
spring-boot-starter-security = { module = "org.springframework.boot:spring-boot-starter-security" }
spring-security-test = { module = "org.springframework.security:spring-security-test" }
```

#### Create: addons/spring-security/build.gradle.kts

```kotlin
    // Spring Security
    implementation(libs.spring.boot.starter.security)

    // Security testing
    testImplementation(libs.spring.security.test)
```

---

## Phase 2: Update create-service.sh to Use Templates

### 2.1 Add Template Path Constants

Add near top of script:

```bash
TEMPLATE_REPO_PATH="$(dirname "$SERVICE_DIR")/spring-boot-service-template"
TEMPLATE_ADDONS_PATH="$TEMPLATE_REPO_PATH/addons"
```

### 2.2 Create Template Application Helper Functions

Replace `exclude_datasource_when_no_database()` with:

```bash
apply_application_class_patch() {
  local addon_name=$1
  local app_file="$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME/${SERVICE_CLASS_NAME}Application.java"

  info "Removing DataSource exclusions from Application class..."

  # Remove the exclude parameter
  sed -i 's/@SpringBootApplication($/@SpringBootApplication/' "$app_file"
  sed -i '/exclude = {DataSourceAutoConfiguration.class, HibernateJpaAutoConfiguration.class})/d' "$app_file"

  # Remove the imports
  sed -i '/import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;/d' "$app_file"
  sed -i '/import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;/d' "$app_file"
}
```

### 2.3 Create Generic Addon Application Functions

```bash
apply_addon_toml() {
  local addon_name=$1
  local addon_toml="$TEMPLATE_ADDONS_PATH/$addon_name/libs.versions.toml"

  if [ -f "$addon_toml" ]; then
    info "Adding $addon_name dependencies to libs.versions.toml..."

    # Handle special case: Spring Boot Web replaces service-core with service-web
    if [ "$addon_name" = "spring-boot-web" ]; then
      sed -i 's/service-core/service-web/g' "$SERVICE_DIR/gradle/libs.versions.toml"
    else
      cat "$addon_toml" >> "$SERVICE_DIR/gradle/libs.versions.toml"
    fi
  fi
}

apply_addon_gradle() {
  local addon_name=$1
  local gradle_file="$SERVICE_DIR/build.gradle.kts"

  # Handle special prepend case (RabbitMQ dependencyManagement)
  local gradle_prepend="$TEMPLATE_ADDONS_PATH/$addon_name/build.gradle.kts.dependencyManagement"
  if [ -f "$gradle_prepend" ]; then
    info "Adding $addon_name dependency management to build.gradle.kts..."
    # Insert before dependencies block
    sed -i '/^dependencies {$/e cat '"$gradle_prepend" "$gradle_file"
  fi

  # Handle standard append case (dependencies)
  local gradle_deps="$TEMPLATE_ADDONS_PATH/$addon_name/build.gradle.kts.dependencies"
  if [ ! -f "$gradle_deps" ]; then
    gradle_deps="$TEMPLATE_ADDONS_PATH/$addon_name/build.gradle.kts"
  fi

  if [ -f "$gradle_deps" ]; then
    info "Adding $addon_name dependencies to build.gradle.kts..."
    # Find the line with testRuntimeOnly(libs.junit.platform.launcher) and append after it
    sed -i '/testRuntimeOnly(libs.junit.platform.launcher)/r '"$gradle_deps" "$gradle_file"
  fi
}

apply_addon_yaml() {
  local addon_name=$1
  local addon_yaml="$TEMPLATE_ADDONS_PATH/$addon_name/application.yml"

  if [ -f "$addon_yaml" ]; then
    info "Adding $addon_name configuration to application.yml..."

    # Create temp file with substitutions
    local temp_yaml=$(mktemp)
    sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
        -e "s/{DATABASE_NAME}/$DATABASE_NAME/g" \
        -e "s/{SERVICE_PORT}/$SERVICE_PORT/g" \
        "$addon_yaml" > "$temp_yaml"

    # Append to application.yml
    cat "$temp_yaml" >> "$SERVICE_DIR/src/main/resources/application.yml"
    rm "$temp_yaml"
  fi
}

apply_addon_sql() {
  local addon_name=$1
  local migration_pattern="$TEMPLATE_ADDONS_PATH/$addon_name/V*.sql"

  for sql_file in $migration_pattern; do
    if [ -f "$sql_file" ]; then
      local filename=$(basename "$sql_file")
      info "Copying $filename to db/migration..."

      # Create temp file with substitutions
      local temp_sql=$(mktemp)
      sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
          -e "s/{DATABASE_NAME}/$DATABASE_NAME/g" \
          "$sql_file" > "$temp_sql"

      # Copy to migration directory
      mkdir -p "$SERVICE_DIR/src/main/resources/db/migration"
      cp "$temp_sql" "$SERVICE_DIR/src/main/resources/db/migration/$filename"
      rm "$temp_sql"
    fi
  done
}

apply_addon_java_patch() {
  local addon_name=$1
  local patch_file="$TEMPLATE_ADDONS_PATH/$addon_name/Application.java.patch"

  if [ -f "$patch_file" ]; then
    apply_application_class_patch "$addon_name"
  fi
}

# Master function to apply all addon templates
apply_addon_templates() {
  local addon_name=$1

  apply_addon_toml "$addon_name"
  apply_addon_gradle "$addon_name"
  apply_addon_yaml "$addon_name"
  apply_addon_sql "$addon_name"
  apply_addon_java_patch "$addon_name"
}
```

### 2.4 Update Each Addon Function

Replace entire body of each `apply_*_addon()` function with:

#### Spring Boot Web
```bash
apply_spring_boot_web_addon() {
  info "Applying Spring Boot Web add-on..."
  apply_addon_templates "spring-boot-web"
}
```

#### PostgreSQL
```bash
apply_postgresql_addon() {
  info "Applying PostgreSQL + Flyway add-on..."
  apply_addon_templates "postgresql-flyway"

  # Additional setup
  info "Database '$DATABASE_NAME' needs to be created manually"
  info "Run: createdb $DATABASE_NAME"
}
```

#### Redis
```bash
apply_redis_addon() {
  info "Applying Redis add-on..."
  apply_addon_templates "redis"
}
```

#### RabbitMQ
```bash
apply_rabbitmq_addon() {
  info "Applying RabbitMQ + Spring Cloud Stream add-on..."
  apply_addon_templates "rabbitmq-spring-cloud"

  info "Note: Configure your event bindings in application.yml"
}
```

#### WebFlux
```bash
apply_webflux_addon() {
  info "Applying WebFlux (WebClient) add-on..."
  apply_addon_templates "webflux"

  info "Note: Create WebClientConfig class manually for HTTP client setup"
}
```

#### ShedLock
```bash
apply_shedlock_addon() {
  if [ "$USE_POSTGRESQL" != true ]; then
    error "ShedLock add-on requires PostgreSQL add-on"
    exit 1
  fi

  info "Applying ShedLock add-on..."
  apply_addon_templates "shedlock"

  info "Note: Create SchedulingConfig class manually with @EnableSchedulerLock"
}
```

#### SpringDoc
```bash
apply_springdoc_addon() {
  info "Applying SpringDoc OpenAPI add-on..."
  apply_addon_templates "springdoc"

  info "Swagger UI will be available at: http://localhost:$SERVICE_PORT/$SERVICE_NAME/swagger-ui.html"
}
```

#### Spring Security
```bash
apply_security_addon() {
  info "Applying Spring Security add-on..."
  apply_addon_templates "spring-security"

  info "Note: Create SecurityConfig class manually to configure authentication"
}
```

### 2.5 Remove Old Functions

Delete these functions entirely:
- `exclude_datasource_when_no_database()` (replaced by `apply_application_class_patch()`)
- All heredoc blocks inside addon functions

---

## Phase 3: Update Documentation

### 3.1 Update Template Repository Documentation

#### Create: spring-boot-service-template/TEMPLATE_USAGE.md

```markdown
# Service Template Usage

This template provides a minimal non-web Spring Boot service baseline with an addon system.

## Base Template

The base template includes:
- **Java 24** with Spring Boot 3.5.7
- **service-core** dependency (logging, exceptions, utilities)
- **Actuator** for health checks
- **Gradle** with version catalog
- **Code quality tools** (Checkstyle, Spotless)
- **Non-web Application class** with DataSource exclusions

## Add-On System

Add-ons are located in `addons/` directory. Each addon contains:
- `libs.versions.toml` - Gradle version catalog additions
- `build.gradle.kts` - Gradle dependency additions
- `application.yml` - Spring Boot configuration additions
- `*.sql` - Database migration files (if applicable)
- `Application.java.patch` - Instructions for modifying Application class (if applicable)

### Available Add-Ons

| Add-On | Description | Files |
|--------|-------------|-------|
| `spring-boot-web` | REST API with embedded Tomcat | 4 files |
| `postgresql-flyway` | PostgreSQL + Flyway migrations | 5 files |
| `redis` | Redis cache and data store | 3 files |
| `rabbitmq-spring-cloud` | Event-driven messaging | 4 files |
| `webflux` | WebClient for HTTP calls | 2 files |
| `shedlock` | Distributed task locking | 3 files |
| `springdoc` | OpenAPI/Swagger documentation | 2 files |
| `spring-security` | Authentication/authorization | 2 files |

## Placeholder Substitution

Templates use placeholders that are replaced during service creation:

| Placeholder | Example | Used In |
|-------------|---------|---------|
| `{SERVICE_NAME}` | `currency-service` | YAML, SQL, Java |
| `{DOMAIN_NAME}` | `currency` | Java packages |
| `{ServiceClassName}` | `Currency` | Java class names |
| `{SERVICE_PORT}` | `8082` | YAML (web addon) |
| `{DATABASE_NAME}` | `currency` | YAML, SQL |
| `{SERVICE_COMMON_VERSION}` | `0.0.1-SNAPSHOT` | TOML |
| `{JAVA_VERSION}` | `24` | TOML |

## Template Validation

All templates should be valid independently:
```bash
# Validate YAML syntax
yamllint addons/**/application.yml

# Validate TOML syntax
taplo check addons/**/libs.versions.toml

# Validate SQL syntax
sqlfluff lint addons/**/*.sql
```
```

### 3.2 Update Orchestration Documentation

#### Update: docs/service-creation/README.md

Add section about template extraction:

```markdown
## Template System Architecture

The service creation process uses a **template-based architecture** where all configuration text lives in the `spring-boot-service-template` repository as pre-verified template files.

### Benefits
- ✅ **Pre-verified**: All YAML/SQL/Kotlin validated before use
- ✅ **Testable**: Templates independently tested in CI/CD
- ✅ **Maintainable**: Configuration changes made in template files, not shell scripts
- ✅ **Documented**: Templates ARE the documentation source
- ✅ **No duplication**: Single source of truth

### Template Structure
- **Base template**: Minimal non-web service (service-core dependency)
- **Add-on templates**: 8 add-ons in separate directories
- **30 template files**: YAML, TOML, Kotlin, SQL, Java patches

See [spring-boot-service-template/TEMPLATE_USAGE.md](https://github.com/budgetanalyzer/spring-boot-service-template/blob/main/TEMPLATE_USAGE.md) for details.
```

#### Update: docs/service-creation/script-usage.md

Add troubleshooting section:

```markdown
## Troubleshooting

### "Template file not found" Error

If you see errors like:
```
Error: Template file not found: /workspace/spring-boot-service-template/addons/postgresql-flyway/application.yml
```

**Solution**: Ensure `spring-boot-service-template` is cloned in `/workspace/`:
```bash
cd /workspace
git clone https://github.com/budgetanalyzer/spring-boot-service-template.git
```

The script expects this repository structure:
```
/workspace/
├── orchestration/                  # This repository
│   └── scripts/create-service.sh
├── spring-boot-service-template/   # Template repository
│   ├── base/
│   └── addons/
└── {new-service}/                  # Generated service
```
```

#### Update: docs/service-creation/addons/README.md

Update each addon entry to reference template files:

```markdown
## PostgreSQL + Flyway

**Template Files**: `spring-boot-service-template/addons/postgresql-flyway/`
- `libs.versions.toml` - Gradle dependencies (JPA, Flyway, PostgreSQL, H2)
- `build.gradle.kts` - Gradle dependency declarations
- `application.yml` - DataSource, JPA, Flyway configuration
- `Application.java.patch` - Removes DataSource exclusions
- `V1__initial_schema.sql` - Initial migration template

**Documentation**: [postgresql-flyway.md](./postgresql-flyway.md)

... (repeat for all addons)
```

---

## Phase 4: Validation & Testing

### 4.1 Validate Template Syntax

Add to spring-boot-service-template CI/CD:

```bash
# Validate YAML
for file in addons/**/application.yml; do
  echo "Validating $file..."
  yamllint "$file" || exit 1
done

# Validate TOML
for file in addons/**/libs.versions.toml; do
  echo "Validating $file..."
  # TOML validator
done

# Validate SQL
for file in addons/**/*.sql; do
  echo "Validating $file..."
  # SQL syntax check
done
```

### 4.2 Test Service Creation with All Addon Combinations

Test matrix:

1. **REST API Service**: Spring Boot Web + PostgreSQL + SpringDoc
2. **Minimal Service**: No addons (baseline)
3. **Message Consumer**: PostgreSQL + RabbitMQ (no web)
4. **Batch Service**: PostgreSQL + ShedLock (no web)
5. **Full Stack**: Web + PostgreSQL + Redis + RabbitMQ + Security + SpringDoc

For each:
```bash
# Generate service
cd /workspace/orchestration
./scripts/create-service.sh

# Verify build
cd /workspace/{new-service}
./gradlew clean build

# Verify configuration
cat src/main/resources/application.yml  # Check YAML structure
cat gradle/libs.versions.toml          # Check TOML structure
```

### 4.3 Verify No Embedded Content Remains

```bash
# Check for heredocs in script
grep -n "<<EOF" scripts/create-service.sh
# Should return 0 results

# Check for sed with Java code
grep -n "sed.*@SpringBootApplication" scripts/create-service.sh
# Should only be in apply_application_class_patch() function
```

---

## Phase 5: Update CLAUDE.md

### Update: orchestration/CLAUDE.md

Update "Service Creation Workflow" section:

```markdown
### Template-Based Architecture

**Principle**: All configuration text lives in pre-verified template files in the `spring-boot-service-template` repository, not embedded in shell scripts.

**Benefits**:
- Pre-verification of all YAML/SQL/TOML syntax
- Independent testing of templates
- Single source of truth (no duplication)
- Easier maintenance and review

**Structure**:
```
spring-boot-service-template/
├── base/          # Minimal non-web baseline
└── addons/        # 8 add-ons, 30 template files
    ├── spring-boot-web/
    ├── postgresql-flyway/
    ├── redis/
    └── ... (8 total)
```

**How it works**:
1. Script clones base template
2. Replaces placeholders ({SERVICE_NAME}, etc.)
3. For each selected add-on:
   - Copies template files
   - Substitutes placeholders
   - Appends to target files
   - Applies patches if needed

**No code generation**: Script only does file operations (copy, substitute, append)
```

---

## Summary

### Changes to spring-boot-service-template Repository
- ✅ **1 base template update** (non-web Application.java with exclusions)
- ✅ **8 addon directories** created
- ✅ **30 template files** extracted
- ✅ **1 documentation file** (TEMPLATE_USAGE.md)

### Changes to orchestration Repository
- ✅ **~200 lines removed** from create-service.sh (all heredocs)
- ✅ **~100 lines added** (template application functions)
- ✅ **8 addon functions simplified** (now just call `apply_addon_templates()`)
- ✅ **3 documentation files updated** (README.md, script-usage.md, addons/README.md)
- ✅ **1 CLAUDE.md section updated**

### Benefits Achieved
- ✅ **Separation of concerns**: Script orchestrates files, doesn't generate code
- ✅ **Pre-verification**: All templates independently validated
- ✅ **Testability**: Templates can be tested in isolation
- ✅ **Maintainability**: Configuration changes made in template files
- ✅ **Documentation**: Templates ARE the source of truth
- ✅ **No duplication**: Single source for all configuration

### Implementation Order
1. **Phase 1**: Create addon directories and extract templates in spring-boot-service-template
2. **Phase 2**: Update create-service.sh to use templates
3. **Phase 3**: Update documentation in both repositories
4. **Phase 4**: Validate and test all addon combinations
5. **Phase 5**: Update CLAUDE.md

### Testing Checklist
- [ ] All 30 template files have valid syntax
- [ ] All 8 addon combinations build successfully
- [ ] No heredocs remain in create-service.sh
- [ ] Documentation accurately reflects template system
- [ ] CLAUDE.md updated with template architecture

---

## Appendix: Why DataSource Exclusions Are Necessary

### Understanding Gradle's `implementation` Configuration

**Common Misconception**: `implementation` dependencies are not transitive to consumers.

**Reality**: `implementation` dependencies ARE transitive at **runtime**, just not at **compile-time**.

| Configuration | Compile-time Transitive | Runtime Transitive | Published Maven Scope |
|---------------|------------------------|-------------------|----------------------|
| `api()` | ✅ YES | ✅ YES | `compile` |
| `implementation()` | ❌ NO | ✅ **YES** | `runtime` |
| `compileOnly()` | ✅ YES | ❌ NO | Not published |

### Why This Matters for Spring Boot Autoconfiguration

1. **service-core declares JPA as `implementation`**:
   ```kotlin
   implementation(libs.spring.boot.starter.data.jpa)
   ```

2. **Published as `runtime` scope in Maven POM**:
   ```xml
   <dependency>
     <groupId>org.springframework.boot</groupId>
     <artifactId>spring-boot-starter-data-jpa</artifactId>
     <scope>runtime</scope>
   </dependency>
   ```

3. **Consumer projects get JPA on runtime classpath**:
   - Hibernate classes present
   - HikariCP present
   - DataSourceAutoConfiguration present

4. **Spring Boot autoconfiguration scans runtime classpath**:
   - Finds `DataSourceAutoConfiguration.class`
   - Tries to activate autoconfiguration
   - Requires `DataSource` bean
   - **Fails to start** if no database configured

### Why Exclusions Are the Right Solution

**Alternatives considered**:

❌ **Use `compileOnly` for JPA in service-core**
- Would prevent runtime inclusion
- BUT service-core's own code needs JPA at runtime
- Would break base entity classes like `AuditableEntity`

❌ **Move JPA to service-web only**
- Non-web services with databases wouldn't have base entities
- Forces duplicate code

❌ **Remove JPA from service-core entirely**
- Every service manually adds JPA
- Defeats purpose of shared base entities

✅ **Base template excludes DataSource, addons remove exclusions**
- Non-database services: Keep exclusions
- Database services: PostgreSQL addon removes exclusions
- Clean, explicit, minimal boilerplate

### Conclusion

The exclusions exist because `implementation` dependencies ARE on the runtime classpath (by design), and Spring Boot scans the runtime classpath for autoconfiguration. This is correct Gradle behavior, not a workaround.
