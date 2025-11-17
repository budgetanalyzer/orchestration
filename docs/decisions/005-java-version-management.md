# 005. Java Version Management Strategy

**Date:** 2025-11-17
**Status:** Accepted
**Deciders:** Architecture Team

## Context

The Budget Analyzer project uses Java 24 across all microservices. Each service needs to specify its Java version for the Gradle toolchain, which downloads and manages the appropriate JDK version.

**Current State**:
- All services use Java 24
- Java version is hardcoded in each service's `build.gradle.kts`
- No centralized version management
- Upgrading Java requires editing multiple files per service

**Example (current)**:
```kotlin
// build.gradle.kts
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(24)  // Hardcoded
    }
}
```

**Problem**: How should we manage Java versions across services to make upgrades easier while maintaining per-service flexibility?

## Decision

Use **Gradle Version Catalog** (`libs.versions.toml`) to manage Java version as a centralized, per-service configuration.

**Implementation**:

1. **Define in `gradle/libs.versions.toml`**:
```toml
[versions]
java = "24"
springBoot = "3.5.7"
# ... other versions
```

2. **Reference in `build.gradle.kts`**:
```kotlin
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(libs.versions.java.get().toInt())
    }
}
```

3. **Upgrade Process**:
   - Update `java` version in `gradle/libs.versions.toml`
   - Test service builds (`./gradlew clean build`)
   - Test service runs (`./gradlew bootRun`)
   - Update JVM args if needed (e.g., `--add-opens` for newer Java versions)
   - Run tests (`./gradlew test`)
   - Commit change

## Alternatives Considered

### Alternative 1: Hardcode in build.gradle.kts
Keep Java version hardcoded in each service's build file.

**Pros:**
- Simplest approach (current state)
- No indirection
- Explicit version visible in build file

**Cons:**
- ❌ Java version buried in build logic, not easily discoverable
- ❌ No single source of truth per service
- ❌ Harder to see at a glance what Java version service uses
- ❌ Must search build file for toolchain configuration

### Alternative 2: Shared Version Catalog Across All Services
Create a shared version catalog repository that all services import.

**Pros:**
- Single source of truth across entire project
- Update Java version once, affects all services
- Consistent versions guaranteed

**Cons:**
- ❌ Forces all services to upgrade simultaneously (breaking change risk)
- ❌ Requires Gradle composite build or published version catalog
- ❌ Significant complexity for marginal benefit
- ❌ Removes per-service flexibility
- ❌ Not standard Gradle practice for multi-repo projects

### Alternative 3: gradle.properties
Store Java version in `gradle.properties`.

**Pros:**
- Simple key-value configuration
- Easy to override with `-P` flag

**Cons:**
- ❌ Not the idiomatic Gradle approach
- ❌ Version catalog is designed for this purpose
- ❌ gradle.properties better suited for build configuration (not versions)
- ❌ Inconsistent with how other dependency versions are managed

### Alternative 4: Environment Variable
Use environment variable for Java version.

**Pros:**
- Can override per build
- Flexible for CI/CD

**Cons:**
- ❌ Version not tracked in source control
- ❌ Requires environment setup
- ❌ Not portable across developers
- ❌ Inconsistent with how other versions are managed

## Consequences

**Positive:**
- ✅ Single source of truth per service (`libs.versions.toml`)
- ✅ Easy to discover current Java version (`cat gradle/libs.versions.toml | grep java`)
- ✅ Simple upgrade process (change one line)
- ✅ Consistent with how other dependencies are managed
- ✅ Can upgrade services individually or all at once
- ✅ IDE support for version catalog (autocomplete, navigation)
- ✅ Version visible in version catalog alongside other versions

**Negative:**
- ❌ Slightly more verbose than hardcoding (`.get().toInt()` conversion)
- ❌ Requires understanding Gradle version catalog syntax

**Neutral:**
- 🔷 Per-service versioning (not cross-service)
- 🔷 Each service can use different Java version if needed (flexibility)

## Implementation Pattern

### Services
Migration for transaction-service and currency-service:

1. Add `java = "24"` to `[versions]` section in `gradle/libs.versions.toml`
2. Update `build.gradle.kts` to reference version catalog
3. Test build and runtime
4. Commit changes

### Discovery Commands
Check Java version across services:

```bash
# Check Java version for a service
cat gradle/libs.versions.toml | grep 'java = '

# Check across all services (from orchestration repo)
for service in /workspace/*/gradle/libs.versions.toml; do
  echo "$(dirname $(dirname $service)):"
  grep 'java = ' "$service"
done
```

### JVM Arguments Pattern
Java 24 requires specific JVM arguments for compatibility. These are managed separately in `build.gradle.kts`:

```kotlin
val jvmArgsList = listOf(
    "--add-opens=java.base/java.nio=ALL-UNNAMED",
    "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
    "--enable-native-access=ALL-UNNAMED"
)

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

**Note**: JVM args are Java-version-specific and should be updated when upgrading Java versions.

## References
- [Gradle Version Catalogs Documentation](https://docs.gradle.org/current/userguide/platforms.html)

---

**Note**: This pattern applies to per-service version management. Future consideration: If cross-service version consistency becomes critical, revisit shared version catalog approach.
