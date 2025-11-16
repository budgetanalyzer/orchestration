# Add-On: Spring Modulith

## Purpose
Define application module boundaries and enable event-driven communication between modules.
Spring Modulith helps structure microservices using domain-driven design principles, enforce
module boundaries, and provide internal event publishing/subscribing capabilities.

## Use Cases
- Domain-driven design enforcement within a microservice
- Internal event publishing between application modules
- Module dependency management and verification
- Modular monolith architecture within a single service
- Documentation of module structure
- Testing module interactions

## Benefits
- **Architectural Verification**: Automatically verify module boundaries aren't violated
- **Event-Driven**: Loosely coupled modules communicate via events
- **Documentation**: Generate module structure documentation
- **Testing**: Test module interactions in isolation
- **Refactoring Safety**: Detect unintended dependencies during build
- **Domain Boundaries**: Enforce domain-driven design patterns

## Dependencies

### Step 1: Add to `gradle/libs.versions.toml`

```toml
[versions]
spring-modulith = "1.3.1"

[libraries]
# Add to existing libraries section
spring-modulith-bom = { module = "org.springframework.modulith:spring-modulith-bom", version.ref = "spring-modulith" }
spring-modulith-api = { module = "org.springframework.modulith:spring-modulith-api" }
spring-modulith-events-api = { module = "org.springframework.modulith:spring-modulith-events-api" }
spring-modulith-starter-core = { module = "org.springframework.modulith:spring-modulith-starter-core" }
spring-modulith-starter-jpa = { module = "org.springframework.modulith:spring-modulith-starter-jpa" }
spring-modulith-starter-test = { module = "org.springframework.modulith:spring-modulith-starter-test" }
```

### Step 2: Add to `build.gradle.kts`

```kotlin
dependencies {
    // ... existing dependencies

    // Spring Modulith BOM for version management
    implementation(platform(libs.spring.modulith.bom))

    // Spring Modulith dependencies
    implementation(libs.spring.modulith.api)
    implementation(libs.spring.modulith.events.api)
    implementation(libs.spring.modulith.starter.core)
    implementation(libs.spring.modulith.starter.jpa)  // If using event persistence

    // Testing
    testImplementation(libs.spring.modulith.starter.test)
}
```

## Module Structure

### Directory Structure

Organize your code into modules using package structure:

```
src/main/java/org/budgetanalyzer/{DOMAIN_NAME}/
├── Application.java                    # Main application class
├── module1/                            # Module 1
│   ├── Module1Service.java            # Public API
│   ├── internal/                      # Internal implementation (hidden)
│   │   ├── Module1Entity.java
│   │   ├── Module1Repository.java
│   │   └── Module1InternalService.java
│   └── events/                        # Module events
│       ├── Module1Event.java
│       └── Module1EventListener.java
├── module2/                            # Module 2
│   ├── Module2Service.java
│   ├── internal/
│   │   └── ...
│   └── events/
│       └── ...
└── shared/                            # Shared utilities (accessible to all)
    └── ...
```

### Example Module Structure (Currency Service)

```
org/budgetanalyzer/currency/
├── CurrencyApplication.java
├── exchangerate/                       # Exchange Rate module
│   ├── ExchangeRateService.java       # Public API
│   ├── internal/
│   │   ├── ExchangeRate.java          # Entity
│   │   ├── ExchangeRateRepository.java
│   │   └── ExchangeRateImportService.java
│   └── events/
│       ├── ExchangeRateImportedEvent.java
│       └── ExchangeRateEventListener.java
├── currency/                           # Currency module
│   ├── CurrencyService.java
│   ├── internal/
│   │   ├── Currency.java
│   │   └── CurrencyRepository.java
│   └── events/
│       └── CurrencyCreatedEvent.java
└── api/                                # API/Controller layer
    ├── ExchangeRateController.java
    └── CurrencyController.java
```

## Configuration

### Module Metadata (package-info.java)

Define module boundaries using `package-info.java`:

```java
// src/main/java/org/budgetanalyzer/{DOMAIN_NAME}/module1/package-info.java

@org.springframework.modulith.ApplicationModule(
    displayName = "Module 1",
    allowedDependencies = {"shared", "module2::events"}  // Can depend on shared and module2 events
)
package org.budgetanalyzer.{DOMAIN_NAME}.module1;
```

### Enable Modulith Verification

Add verification to your main application class:

```java
package org.budgetanalyzer.{DOMAIN_NAME};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.modulith.Modulith;

@SpringBootApplication
@Modulith  // Enable Spring Modulith
public class {ServiceClassName}Application {

    public static void main(String[] args) {
        SpringApplication.run({ServiceClassName}Application.class, args);
    }
}
```

## Event-Driven Communication

### Publishing Events

Define an event:

```java
package org.budgetanalyzer.{DOMAIN_NAME}.module1.events;

import java.time.Instant;

/**
 * Event published when Module1 completes an operation.
 * Other modules can listen to this event.
 */
public record Module1Event(
    String entityId,
    String action,
    Instant occurredAt
) {}
```

Publish the event:

```java
package org.budgetanalyzer.{DOMAIN_NAME}.module1;

import org.budgetanalyzer.{DOMAIN_NAME}.module1.events.Module1Event;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class Module1Service {

    private final ApplicationEventPublisher eventPublisher;

    public Module1Service(ApplicationEventPublisher eventPublisher) {
        this.eventPublisher = eventPublisher;
    }

    @Transactional
    public void performOperation(String entityId) {
        // Perform business logic
        // ...

        // Publish event for other modules
        eventPublisher.publishEvent(new Module1Event(
            entityId,
            "CREATED",
            Instant.now()
        ));
    }
}
```

### Listening to Events

```java
package org.budgetanalyzer.{DOMAIN_NAME}.module2.events;

import org.budgetanalyzer.{DOMAIN_NAME}.module1.events.Module1Event;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

@Component
public class Module1EventListener {

    /**
     * Listens to Module1Event from module1.
     * Uses @ApplicationModuleListener for module boundary-aware event handling.
     */
    @ApplicationModuleListener
    public void onModule1Event(Module1Event event) {
        // React to the event
        System.out.println("Module2 received event: " + event);

        // Perform module2-specific logic
        // ...
    }
}
```

### Asynchronous Event Handling

```java
@Component
public class AsyncEventListener {

    @Async
    @ApplicationModuleListener
    public void onModule1EventAsync(Module1Event event) {
        // Handle event asynchronously
        // This runs in a separate thread
    }
}
```

Enable async in your configuration:

```java
@Configuration
@EnableAsync
public class AsyncConfig {
    // Async configuration
}
```

## Event Persistence (Event Externalization)

For reliable event processing with JPA-based event log:

### Configuration

```yaml
# application.yml
spring:
  modulith:
    events:
      jdbc:
        enabled: true  # Enable event persistence
      republish-outstanding-events-on-restart: true  # Retry failed events
```

### Creating Event Publication Table

Spring Modulith will automatically create the required table, but you can also create it manually via Flyway:

```sql
-- src/main/resources/db/migration/V2__create_event_publication_table.sql

CREATE TABLE IF NOT EXISTS event_publication (
    id UUID PRIMARY KEY,
    completion_date TIMESTAMP,
    event_type VARCHAR(255) NOT NULL,
    listener_id VARCHAR(255) NOT NULL,
    publication_date TIMESTAMP NOT NULL,
    serialized_event TEXT NOT NULL
);

CREATE INDEX idx_event_publication_completion_date ON event_publication(completion_date);
CREATE INDEX idx_event_publication_event_type ON event_publication(event_type);
```

## Testing

### Module Verification Test

```java
package org.budgetanalyzer.{DOMAIN_NAME};

import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.docs.Documenter;

class ModuleStructureTest {

    ApplicationModules modules = ApplicationModules.of({ServiceClassName}Application.class);

    @Test
    void verifyModuleStructure() {
        // Verify module structure is valid
        modules.verify();
    }

    @Test
    void generateModuleDocumentation() throws Exception {
        // Generate documentation (PlantUML diagrams, etc.)
        new Documenter(modules)
            .writeDocumentation()
            .writeIndividualModulesAsPlantUml();
    }
}
```

### Module Integration Test

```java
package org.budgetanalyzer.{DOMAIN_NAME}.module1;

import org.budgetanalyzer.{DOMAIN_NAME}.module1.events.Module1Event;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.test.ApplicationModuleTest;
import org.springframework.modulith.test.Scenario;

@ApplicationModuleTest
class Module1IntegrationTest {

    @Test
    void testEventPublishing(Scenario scenario) {
        scenario.stimulate(() -> {
            // Perform operation that publishes event
            return new Module1Event("123", "CREATED", Instant.now());
        })
        .andWaitForEventOfType(Module1Event.class)
        .matching(event -> event.entityId().equals("123"))
        .toArriveAndVerify(event -> {
            // Verify event was published correctly
            assertThat(event.action()).isEqualTo("CREATED");
        });
    }
}
```

## Real-World Example: Currency Service

From currency-service, the exchange rate import event:

### Event Definition

```java
package org.budgetanalyzer.currency.exchangerate.events;

import java.time.LocalDate;

public record ExchangeRateImportedEvent(
    String currencyCode,
    LocalDate effectiveDate,
    int importedCount
) {}
```

### Publishing the Event

```java
package org.budgetanalyzer.currency.exchangerate.internal;

import org.budgetanalyzer.currency.exchangerate.events.ExchangeRateImportedEvent;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ExchangeRateImportService {

    private final ApplicationEventPublisher eventPublisher;

    @Transactional
    public void importExchangeRates(String currencyCode, LocalDate startDate) {
        // Import exchange rates from external API
        int count = performImport(currencyCode, startDate);

        // Publish event for other modules
        eventPublisher.publishEvent(new ExchangeRateImportedEvent(
            currencyCode,
            startDate,
            count
        ));
    }
}
```

### Listening to the Event

```java
package org.budgetanalyzer.currency.notification.events;

import org.budgetanalyzer.currency.exchangerate.events.ExchangeRateImportedEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

@Component
public class ExchangeRateEventListener {

    private static final Logger log = LoggerFactory.getLogger(ExchangeRateEventListener.class);

    @ApplicationModuleListener
    public void onExchangeRateImported(ExchangeRateImportedEvent event) {
        log.info("Exchange rates imported: {} rates for {} on {}",
            event.importedCount(),
            event.currencyCode(),
            event.effectiveDate()
        );

        // Could trigger notifications, update caches, etc.
    }
}
```

## Best Practices

1. **Package by Feature**: Organize code by domain modules, not layers
2. **Hide Internals**: Use `internal` package for implementation details
3. **Event Records**: Use Java records for immutable events
4. **Transactional Publishing**: Publish events within `@Transactional` methods
5. **Module Tests**: Write tests to verify module boundaries
6. **Event Naming**: Use past tense for event names (`EntityCreatedEvent`, not `CreateEntityEvent`)
7. **Documentation**: Generate and review module documentation regularly

## Common Patterns

### Transactional Event Listener

```java
@Component
public class TransactionalEventListener {

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @ApplicationModuleListener
    public void onEventAfterCommit(Module1Event event) {
        // Executed only after transaction commits successfully
    }
}
```

### Conditional Event Processing

```java
@Component
public class ConditionalEventListener {

    @ApplicationModuleListener
    @ConditionalOnProperty(name = "feature.module2.enabled", havingValue = "true")
    public void onModule1Event(Module1Event event) {
        // Only processes events if feature is enabled
    }
}
```

## Module Documentation

Spring Modulith can generate documentation of your module structure:

```java
@Test
void generateDocumentation() throws Exception {
    ApplicationModules modules = ApplicationModules.of({ServiceClassName}Application.class);

    new Documenter(modules)
        .writeDocumentation()                        // Generates AsciiDoc
        .writeModulesAsPlantUml()                   // PlantUML component diagram
        .writeIndividualModulesAsPlantUml();        // Individual module diagrams
}
```

Generated documentation will be in: `target/modulith-docs/`

## Troubleshooting

### Module Verification Failures

If module verification fails:

1. Check `package-info.java` for correct `allowedDependencies`
2. Review import statements for unintended cross-module dependencies
3. Move shared code to a `shared` or `common` package
4. Use events instead of direct service calls across modules

### Events Not Received

If events aren't received by listeners:

1. Ensure listener method is `public`
2. Check listener is a Spring bean (`@Component`)
3. Verify `@ApplicationModuleListener` annotation is present
4. Check event class package is accessible
5. Review transaction boundaries (events published within transactions)

## See Also

- [Spring Modulith Reference Documentation](https://docs.spring.io/spring-modulith/reference/)
- [Spring Modulith Events](https://docs.spring.io/spring-modulith/reference/events.html)
- [Modular Monolith Architecture](https://www.infoq.com/articles/modular-monoliths/)

## Notes

- Spring Modulith is complementary to microservices, not a replacement
- Use it to enforce boundaries within a single microservice
- Great for preventing "big ball of mud" in complex services
- Event persistence ensures reliable event processing
- Module verification runs at application startup (can be disabled in production)
