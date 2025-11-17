# Scheduling and TestContainers Add-Ons Implementation Plan

**Date**: 2025-11-17
**Status**: Planning
**Goal**: Implement missing Scheduling and TestContainers add-ons to complete template system automation

## Background

The service creation template system has two remaining blockers preventing full automation:

1. **Scheduling add-on**: Documented but not implemented in template
2. **TestContainers add-on**: Documented but not implemented in template

Both are listed as "available" in CLAUDE.md but cannot actually be applied by the create-service.sh script.

**Note**: ShedLock was incorrectly listed as a blocker - it is fully implemented.

## Requirements

### Scheduling Add-On

**Purpose**: Enable scheduled tasks using Spring's `@Scheduled` annotation

**Scope**:
- Add `@EnableScheduling` annotation to Application class
- No additional dependencies needed (built into Spring Framework)
- Minimal configuration required

**Use Cases**:
- Batch processing services
- Periodic data synchronization
- Scheduled cleanup tasks
- Cron-style job execution

### TestContainers Add-On

**Purpose**: Provide smoke test that validates full application context startup with real infrastructure

**Scope**:
- Add TestContainers dependencies based on selected infrastructure add-ons
- Generate ApplicationSmokeTest.java that:
  - Starts real containers (PostgreSQL, Redis, RabbitMQ) based on what's configured
  - Loads full Spring Boot context
  - Wires container URLs to Spring properties via @DynamicPropertySource
  - Passes a simple test proving the service boots correctly
- Ensures every generated service has a passing test out-of-the-box

**Philosophy**:
- Smoke test pattern > Repository test pattern
- Validates entire service configuration
- Tests real infrastructure integration
- Works for any service type (web, messaging, batch, CLI)

**Conditional Dependencies**:
| Infrastructure Add-On | TestContainers Dependency |
|----------------------|---------------------------|
| PostgreSQL + Flyway  | `testcontainers-postgresql` |
| Redis                | `testcontainers` (GenericContainer) |
| RabbitMQ             | `testcontainers-rabbitmq` |

## Implementation Plan

### Part 1: Scheduling Add-On

**Repository**: `spring-boot-service-template`

#### 1.1 Create Template Files

**File**: `addons/scheduling/Application.java.patch`

```java
// Patch to add to Application.java
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableScheduling
@SpringBootApplication
public class {SERVICE_NAME_PASCAL}Application {
    // ... existing code
}
```

**Pattern**: Uses patch file approach (like existing add-ons)

#### 1.2 Update create-service.sh

**Changes**:

1. Add flag variable:
```bash
USE_SCHEDULING=false
```

2. Add interactive prompt (after other add-on prompts):
```bash
read -p "  Scheduling (@Scheduled tasks) [y/n]: " USE_SCHEDULING
USE_SCHEDULING=$(echo "$USE_SCHEDULING" | tr '[:upper:]' '[:lower:]')
```

3. Add apply function:
```bash
apply_scheduling_addon() {
    echo "Applying Scheduling add-on..."

    # Apply Application.java patch
    local app_file="src/main/java/com/budgetanalyzer/${DOMAIN_NAME}/${SERVICE_NAME_PASCAL}Application.java"

    # Add import
    sed -i '/^package/a\
import org.springframework.scheduling.annotation.EnableScheduling;' "$app_file"

    # Add annotation (before @SpringBootApplication)
    sed -i '/^@SpringBootApplication/i\
@EnableScheduling' "$app_file"

    echo "  ✓ Added @EnableScheduling to Application class"
}
```

4. Call in apply_addons():
```bash
apply_addons() {
    # ... existing add-on applications

    if [ "$USE_SCHEDULING" = "y" ]; then
        apply_scheduling_addon
    fi

    # ... rest of function
}
```

### Part 2: TestContainers Add-On

**Repository**: `spring-boot-service-template`

#### 2.1 Create Template Files

**File**: `addons/testcontainers/libs.versions.toml`

```toml
[versions]
testcontainers = "1.19.3"

[libraries]
testcontainers-bom = { module = "org.testcontainers:testcontainers-bom", version.ref = "testcontainers" }
testcontainers-junit-jupiter = { module = "org.testcontainers:junit-jupiter" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql" }
testcontainers-rabbitmq = { module = "org.testcontainers:rabbitmq" }
```

**File**: `addons/testcontainers/build.gradle.kts`

```kotlin
dependencies {
    // TestContainers
    testImplementation(platform(libs.testcontainers.bom))
    testImplementation(libs.testcontainers.junit.jupiter)
    // Additional containers added conditionally by script
}
```

**File**: `addons/testcontainers/ApplicationSmokeTest.java`

```java
package com.budgetanalyzer.{DOMAIN_NAME};

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.DynamicPropertyRegistry;

// Container imports added conditionally by script

@SpringBootTest
@Testcontainers
class ApplicationSmokeTest {

    // Container declarations added conditionally by script

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        // Property configuration added conditionally by script
    }

    @Test
    void contextLoads() {
        // Test passes if Spring context loads successfully
    }
}
```

**File**: `addons/testcontainers/application-test.yml` (optional)

```yaml
# Test-specific configuration overrides
spring:
  jpa:
    hibernate:
      ddl-auto: validate  # Ensure Flyway migrations are used
```

#### 2.2 Update create-service.sh

**Changes**:

1. Add flag variable:
```bash
USE_TESTCONTAINERS=false
```

2. Add interactive prompt:
```bash
read -p "  TestContainers (smoke test with real infrastructure) [y/n]: " USE_TESTCONTAINERS
USE_TESTCONTAINERS=$(echo "$USE_TESTCONTAINERS" | tr '[:upper:]' '[:lower:]')
```

3. Add apply function:
```bash
apply_testcontainers_addon() {
    echo "Applying TestContainers add-on..."

    local addon_dir="${TEMPLATE_DIR}/addons/testcontainers"

    # 1. Add base dependencies
    cat "${addon_dir}/libs.versions.toml" >> gradle/libs.versions.toml
    cat "${addon_dir}/build.gradle.kts" >> build.gradle.kts

    # 2. Track which containers are needed
    local containers=()
    local imports=()
    local declarations=()
    local properties=()

    # 3. Check which infrastructure add-ons are selected
    if [ "$USE_POSTGRESQL" = "y" ]; then
        containers+=("postgresql")
        imports+=("import org.testcontainers.containers.PostgreSQLContainer;")
        declarations+=("    @Container")
        declarations+=("    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>(\"postgres:16-alpine\")")
        declarations+=("        .withDatabaseName(\"${DATABASE_NAME}\")")
        declarations+=("        .withUsername(\"postgres\")")
        declarations+=("        .withPassword(\"postgres\");")
        properties+=("        registry.add(\"spring.datasource.url\", postgres::getJdbcUrl);")
        properties+=("        registry.add(\"spring.datasource.username\", postgres::getUsername);")
        properties+=("        registry.add(\"spring.datasource.password\", postgres::getPassword);")

        # Add PostgreSQL TestContainer dependency
        echo "    testImplementation(libs.testcontainers.postgresql)" >> build.gradle.kts
    fi

    if [ "$USE_REDIS" = "y" ]; then
        containers+=("redis")
        imports+=("import org.testcontainers.containers.GenericContainer;")
        declarations+=("    @Container")
        declarations+=("    static GenericContainer<?> redis = new GenericContainer<>(\"redis:7-alpine\")")
        declarations+=("        .withExposedPorts(6379);")
        properties+=("        registry.add(\"spring.data.redis.host\", redis::getHost);")
        properties+=("        registry.add(\"spring.data.redis.port\", () -> redis.getMappedPort(6379).toString());")
    fi

    if [ "$USE_RABBITMQ" = "y" ]; then
        containers+=("rabbitmq")
        imports+=("import org.testcontainers.containers.RabbitMQContainer;")
        declarations+=("    @Container")
        declarations+=("    static RabbitMQContainer rabbitmq = new RabbitMQContainer(\"rabbitmq:3-management-alpine\");")
        properties+=("        registry.add(\"spring.rabbitmq.host\", rabbitmq::getHost);")
        properties+=("        registry.add(\"spring.rabbitmq.port\", () -> rabbitmq.getMappedPort(5672).toString());")
        properties+=("        registry.add(\"spring.rabbitmq.username\", rabbitmq::getAdminUsername);")
        properties+=("        registry.add(\"spring.rabbitmq.password\", rabbitmq::getAdminPassword);")

        # Add RabbitMQ TestContainer dependency
        echo "    testImplementation(libs.testcontainers.rabbitmq)" >> build.gradle.kts
    fi

    # 4. Generate ApplicationSmokeTest.java
    local test_file="src/test/java/com/budgetanalyzer/${DOMAIN_NAME}/ApplicationSmokeTest.java"

    cat > "$test_file" <<EOF
package com.budgetanalyzer.${DOMAIN_NAME};

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.DynamicPropertyRegistry;
$(printf '%s\n' "${imports[@]}")

@SpringBootTest
@Testcontainers
class ApplicationSmokeTest {

$(printf '%s\n' "${declarations[@]}")

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
$(printf '%s\n' "${properties[@]}")
    }

    @Test
    void contextLoads() {
        // Test passes if Spring context loads successfully with all containers
    }
}
EOF

    # 5. Copy test configuration if it exists
    if [ -f "${addon_dir}/application-test.yml" ]; then
        cp "${addon_dir}/application-test.yml" src/test/resources/
        echo "  ✓ Added application-test.yml"
    fi

    echo "  ✓ Generated ApplicationSmokeTest with containers: ${containers[*]}"
    echo "  ✓ Added TestContainers dependencies"
}
```

4. Call in apply_addons():
```bash
apply_addons() {
    # ... existing add-on applications

    if [ "$USE_TESTCONTAINERS" = "y" ]; then
        apply_testcontainers_addon
    fi

    # ... rest of function
}
```

### Part 3: Documentation Updates

**Repository**: `orchestration`

#### 3.1 Update microservice-template-plan.md

**File**: `docs/service-creation/microservice-template-plan.md`

**Change at lines 1334-1336**:

```diff
**Blockers**:
-- Some add-ons not yet implemented in template (Scheduling, ShedLock, TestContainers)
+- ShedLock add-on fully implemented (blocker resolved)
+- Scheduling add-on implemented (blocker resolved)
+- TestContainers add-on implemented with smoke test pattern (blocker resolved)
 - Interactive script makes full automation challenging
+  (Note: This is a design choice, not a blocker. Non-interactive mode not currently needed.)
```

#### 3.2 Update addons/testcontainers.md

**File**: `docs/service-creation/addons/testcontainers.md`

Update to reflect smoke test pattern instead of base repository test pattern:

- Remove BaseRepositoryTest examples
- Add ApplicationSmokeTest examples
- Document conditional container selection
- Show examples for each infrastructure combination

### Part 4: Testing

#### 4.1 Test Scenarios

**Test 1: Scheduling Add-On**

```bash
cd /workspace
./orchestration/scripts/create-service.sh

# Inputs:
# - Service name: test-scheduling
# - Domain: scheduling
# - Port: 9001
# - Scheduling: y
# - Other add-ons: n

# Verify:
cd test-scheduling
grep "@EnableScheduling" src/main/java/com/budgetanalyzer/scheduling/TestSchedulingApplication.java
./gradlew clean build
```

**Expected**: Build succeeds, @EnableScheduling present in Application class

**Test 2: TestContainers with PostgreSQL**

```bash
cd /workspace
./orchestration/scripts/create-service.sh

# Inputs:
# - Service name: test-postgres-tc
# - Domain: postgrestc
# - Port: 9002
# - Spring Boot Web: y
# - PostgreSQL: y
# - TestContainers: y
# - Other add-ons: n

# Verify:
cd test-postgres-tc
grep "PostgreSQLContainer" src/test/java/com/budgetanalyzer/postgrestc/ApplicationSmokeTest.java
./gradlew test
```

**Expected**: Smoke test runs, starts PostgreSQL container, loads context, passes

**Test 3: TestContainers with Multiple Infrastructure**

```bash
cd /workspace
./orchestration/scripts/create-service.sh

# Inputs:
# - Service name: test-multi-tc
# - Domain: multitc
# - Port: 9003
# - Spring Boot Web: y
# - PostgreSQL: y
# - Redis: y
# - RabbitMQ: y
# - TestContainers: y

# Verify:
cd test-multi-tc
grep "PostgreSQLContainer" src/test/java/com/budgetanalyzer/multitc/ApplicationSmokeTest.java
grep "GenericContainer.*redis" src/test/java/com/budgetanalyzer/multitc/ApplicationSmokeTest.java
grep "RabbitMQContainer" src/test/java/com/budgetanalyzer/multitc/ApplicationSmokeTest.java
./gradlew test
```

**Expected**: All three containers start, context loads, test passes

**Test 4: Scheduling + TestContainers (Batch Service)**

```bash
cd /workspace
./orchestration/scripts/create-service.sh

# Inputs:
# - Service name: test-batch
# - Domain: batch
# - Port: 9004
# - PostgreSQL: y
# - Scheduling: y
# - TestContainers: y
# - Other add-ons: n

# Verify:
cd test-batch
grep "@EnableScheduling" src/main/java/com/budgetanalyzer/batch/TestBatchApplication.java
grep "PostgreSQLContainer" src/test/java/com/budgetanalyzer/batch/ApplicationSmokeTest.java
./gradlew test
```

**Expected**: Non-web service with scheduling and passing smoke test

#### 4.2 Validation Checklist

- [ ] Scheduling add-on applies @EnableScheduling annotation
- [ ] Scheduling service builds without errors
- [ ] TestContainers with PostgreSQL generates correct container code
- [ ] TestContainers with Redis generates correct container code
- [ ] TestContainers with RabbitMQ generates correct container code
- [ ] TestContainers with multiple infrastructure works correctly
- [ ] ApplicationSmokeTest passes for all combinations
- [ ] Non-web service + TestContainers works (no web container, just context)
- [ ] Spring Boot Web + TestContainers works
- [ ] Documentation accurately reflects implementation

## Risks and Mitigations

### Risk 1: TestContainers Version Compatibility

**Risk**: TestContainers version might not be compatible with all container images

**Mitigation**:
- Use latest stable TestContainers version (1.19.3+)
- Pin container image versions (postgres:16-alpine, redis:7-alpine, etc.)
- Document version compatibility in addons/testcontainers.md

### Risk 2: Test Execution Time

**Risk**: Smoke tests with multiple containers might be slow

**Mitigation**:
- This is expected and acceptable for integration tests
- Document that smoke test downloads images on first run
- Consider adding `@Tag("integration")` for selective test execution in CI

### Risk 3: Docker Not Available in Test Environment

**Risk**: Some CI environments might not have Docker

**Mitigation**:
- Document Docker requirement for running tests
- Smoke test is optional (can be skipped with `./gradlew build -x test`)
- Consider TestContainers Cloud for CI environments without Docker

### Risk 4: Complex Conditional Logic in Script

**Risk**: TestContainers apply function has complex conditional logic

**Mitigation**:
- Thorough testing of all infrastructure combinations
- Clear comments in script code
- Consider extracting to separate helper functions if it grows

## Success Criteria

1. ✅ Scheduling add-on can be applied via create-service.sh
2. ✅ Services with Scheduling add-on build successfully
3. ✅ TestContainers add-on can be applied via create-service.sh
4. ✅ ApplicationSmokeTest generated with correct containers based on infrastructure
5. ✅ Smoke tests pass for all infrastructure combinations
6. ✅ Documentation updated to reflect new add-ons
7. ✅ Blockers removed from microservice-template-plan.md
8. ✅ Both add-ons tested individually and in combination

## Timeline

**Estimated Total Time**: 4-5 hours

- Part 1 (Scheduling): 1 hour
- Part 2 (TestContainers): 2-3 hours
- Part 3 (Documentation): 30 minutes
- Part 4 (Testing): 1 hour

## Future Enhancements

1. **Conditional Test Tags**: Add `@Tag("integration")` to smoke tests
2. **Test Profile**: Consider separate test profile for container tests
3. **Container Reuse**: Explore TestContainers reuse feature for faster local dev
4. **Additional Containers**: Support for more infrastructure (MongoDB, Kafka, etc.)
5. **WebClient TestContainers**: Mock HTTP services with WireMock containers

## References

- TestContainers Documentation: https://testcontainers.com/
- Spring Boot Testing: https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.testing
- Existing Add-Ons: `/workspace/spring-boot-service-template/addons/`
- Create Service Script: `/workspace/orchestration/scripts/create-service.sh`
