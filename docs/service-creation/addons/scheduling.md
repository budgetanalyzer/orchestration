# Add-On: Task Scheduling

## Purpose
Enable scheduled tasks using Spring's `@Scheduled` annotation for periodic operations,
background jobs, and time-based automation within your microservice.

## Use Cases
- Periodic data imports (e.g., currency-service exchange rate import)
- Cleanup jobs (old records, temporary files)
- Report generation on a schedule
- Cache warming or refresh
- Health checks and monitoring tasks
- Data synchronization between services
- Batch processing

## Benefits
- **Simple Configuration**: Just annotate methods with `@Scheduled`
- **Cron Support**: Full cron expression support for complex schedules
- **Fixed Rate/Delay**: Simple periodic execution
- **Thread Pool Management**: Configure concurrent task execution
- **Spring Integration**: Works seamlessly with transactions, events, etc.

## Configuration

### Step 1: Enable Scheduling

Add `@EnableScheduling` to your main application class or a configuration class:

```java
package org.budgetanalyzer.{DOMAIN_NAME};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling  // Enable scheduled task support
public class {ServiceClassName}Application {

    public static void main(String[] args) {
        SpringApplication.run({ServiceClassName}Application.class, args);
    }
}
```

### Step 2: Configure Thread Pool (Optional but Recommended)

```java
package org.budgetanalyzer.{DOMAIN_NAME}.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

@Configuration
public class SchedulingConfig {

    /**
     * Configure thread pool for scheduled tasks.
     * Without this, all scheduled tasks run in a single thread.
     */
    @Bean
    public ThreadPoolTaskScheduler taskScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(5);  // Number of concurrent scheduled tasks
        scheduler.setThreadNamePrefix("scheduled-");
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(30);
        return scheduler;
    }
}
```

### Step 3: Application Properties (Optional)

```yaml
# application.yml
spring:
  task:
    scheduling:
      pool:
        size: 5  # Thread pool size for scheduled tasks
      thread-name-prefix: "scheduled-"

budgetanalyzer:
  {SERVICE_NAME}:
    scheduling:
      enabled: ${SCHEDULING_ENABLED:true}  # Feature flag to enable/disable scheduling
      cleanup-cron: "0 0 2 * * ?"          # 2 AM daily
      import-cron: "0 0 23 * * ?"          # 11 PM daily
```

## Usage Examples

### Fixed Rate Scheduling

Runs at fixed intervals (regardless of previous execution time):

```java
package org.budgetanalyzer.{DOMAIN_NAME}.scheduled;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "budgetanalyzer.{SERVICE_NAME}.scheduling.enabled", havingValue = "true")
public class PeriodicTasks {

    private static final Logger log = LoggerFactory.getLogger(PeriodicTasks.class);

    /**
     * Runs every 5 minutes (300,000 milliseconds).
     * Next execution starts 5 minutes after the PREVIOUS START time.
     */
    @Scheduled(fixedRate = 300_000)
    public void performPeriodicTask() {
        log.info("Executing periodic task");
        // Task logic here
    }

    /**
     * Using property-based configuration for the rate.
     */
    @Scheduled(fixedRateString = "${budgetanalyzer.{SERVICE_NAME}.task-rate:60000}")
    public void configurableRateTask() {
        log.info("Executing configurable rate task");
    }
}
```

### Fixed Delay Scheduling

Waits a fixed time after the previous execution completes:

```java
/**
 * Runs 10 minutes (600,000 ms) AFTER the previous execution finishes.
 * Good for tasks that may take variable time.
 */
@Scheduled(fixedDelay = 600_000)
public void performTaskWithDelay() {
    log.info("Executing task with fixed delay");
    // Long-running task logic
}

/**
 * Initial delay of 30 seconds, then every 60 seconds after completion.
 */
@Scheduled(initialDelay = 30_000, fixedDelay = 60_000)
public void performTaskWithInitialDelay() {
    log.info("Executing task with initial delay");
}
```

### Cron Expression Scheduling

Most flexible option using cron syntax:

```java
/**
 * Runs every day at 2:00 AM.
 * Cron format: second minute hour day month weekday
 */
@Scheduled(cron = "0 0 2 * * ?")
public void dailyCleanupTask() {
    log.info("Running daily cleanup at 2 AM");
    // Cleanup logic
}

/**
 * Runs every weekday at 6:00 AM.
 */
@Scheduled(cron = "0 0 6 ? * MON-FRI")
public void weekdayMorningTask() {
    log.info("Running weekday morning task");
}

/**
 * Using property-based cron expression.
 */
@Scheduled(cron = "${budgetanalyzer.{SERVICE_NAME}.cleanup-cron}")
public void configurableCronTask() {
    log.info("Running configurable cron task");
}

/**
 * With timezone specification.
 */
@Scheduled(cron = "0 0 23 * * ?", zone = "America/New_York")
public void taskWithTimezone() {
    log.info("Running task at 11 PM Eastern Time");
}
```

### Cron Expression Examples

```
0 0 12 * * ?        Every day at noon
0 15 10 * * ?       Every day at 10:15 AM
0 0/5 * * * ?       Every 5 minutes
0 0 0 * * ?         Every day at midnight
0 0 1 1 * ?         First day of every month at 1 AM
0 0 9-17 * * MON-FRI Every hour between 9 AM and 5 PM on weekdays
0 0 0 ? * SUN       Every Sunday at midnight
```

Format: `second minute hour day-of-month month day-of-week`

## Real-World Example: Currency Service

From the currency-service, scheduled exchange rate import:

```java
package org.budgetanalyzer.currency.exchangerate.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(
    name = "budgetanalyzer.currency-service.exchange-rate-import.enabled",
    havingValue = "true",
    matchIfMissing = true
)
public class ExchangeRateImportScheduler {

    private static final Logger log = LoggerFactory.getLogger(ExchangeRateImportScheduler.class);

    private final ExchangeRateImportService importService;

    public ExchangeRateImportScheduler(ExchangeRateImportService importService) {
        this.importService = importService;
    }

    /**
     * Import exchange rates on application startup (if enabled).
     */
    @EventListener(ApplicationReadyEvent.class)
    @ConditionalOnProperty(
        name = "budgetanalyzer.currency-service.exchange-rate-import.import-on-startup",
        havingValue = "true"
    )
    public void importOnStartup() {
        log.info("Importing exchange rates on application startup");
        performImport();
    }

    /**
     * Scheduled import using cron expression from configuration.
     * Default: Every day at 11 PM.
     */
    @Scheduled(cron = "${budgetanalyzer.currency-service.exchange-rate-import.cron:0 0 23 * * ?}")
    public void scheduledImport() {
        log.info("Running scheduled exchange rate import");
        performImport();
    }

    private void performImport() {
        try {
            importService.importAllCurrencies();
            log.info("Exchange rate import completed successfully");
        } catch (Exception e) {
            log.error("Exchange rate import failed", e);
        }
    }
}
```

Configuration in `application.yml`:

```yaml
budgetanalyzer:
  currency-service:
    exchange-rate-import:
      enabled: true
      import-on-startup: true
      cron: "0 0 23 * * ?"  # 11 PM daily
```

## Advanced Patterns

### Transactional Scheduled Tasks

```java
import org.springframework.transaction.annotation.Transactional;

@Component
public class TransactionalScheduledTasks {

    @Scheduled(cron = "0 0 1 * * ?")
    @Transactional
    public void transactionalTask() {
        // All database operations in this method run in a single transaction
        // Transaction will rollback if an exception occurs
    }
}
```

### Conditional Execution

```java
@Component
public class ConditionalScheduledTasks {

    @Value("${budgetanalyzer.{SERVICE_NAME}.feature.enabled:false}")
    private boolean featureEnabled;

    @Scheduled(fixedRate = 60_000)
    public void conditionalTask() {
        if (!featureEnabled) {
            log.debug("Task skipped - feature disabled");
            return;
        }

        // Task logic
    }
}
```

### Lock-Based Scheduling (Prevent Concurrent Execution)

```java
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

@Component
public class LockedScheduledTasks {

    private final Lock taskLock = new ReentrantLock();

    @Scheduled(fixedRate = 60_000)
    public void exclusiveTask() {
        if (taskLock.tryLock()) {
            try {
                // Task logic - only runs if lock acquired
                // Prevents concurrent executions
            } finally {
                taskLock.unlock();
            }
        } else {
            log.warn("Previous execution still running, skipping");
        }
    }
}
```

### Metrics and Monitoring

```java
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;

@Component
public class MonitoredScheduledTasks {

    private final MeterRegistry meterRegistry;
    private final Timer importTimer;

    public MonitoredScheduledTasks(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
        this.importTimer = Timer.builder("scheduled.import.duration")
            .description("Duration of scheduled import task")
            .register(meterRegistry);
    }

    @Scheduled(cron = "0 0 2 * * ?")
    public void monitoredTask() {
        importTimer.record(() -> {
            // Task logic
            // Duration will be recorded in metrics
        });

        meterRegistry.counter("scheduled.import.count").increment();
    }
}
```

## Testing

### Testing Scheduled Methods

```java
package org.budgetanalyzer.{DOMAIN_NAME}.scheduled;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;

import static org.mockito.Mockito.verify;

@SpringBootTest(properties = {
    "budgetanalyzer.{SERVICE_NAME}.scheduling.enabled=false"  // Disable actual scheduling
})
class PeriodicTasksTest {

    @Autowired
    private PeriodicTasks periodicTasks;

    @MockBean
    private SomeService someService;

    @Test
    void performPeriodicTask_executesSuccessfully() {
        // Directly call the scheduled method for testing
        periodicTasks.performPeriodicTask();

        // Verify expected behavior
        verify(someService).doSomething();
    }
}
```

### Integration Test with Scheduled Tasks

```java
import org.awaitility.Awaitility;

import java.time.Duration;

@SpringBootTest(properties = {
    "budgetanalyzer.{SERVICE_NAME}.task-rate=1000"  // Fast rate for testing
})
class SchedulingIntegrationTest {

    @Autowired
    private SomeRepository repository;

    @Test
    void scheduledTask_createsRecords() {
        // Wait for scheduled task to execute
        Awaitility.await()
            .atMost(Duration.ofSeconds(5))
            .untilAsserted(() -> {
                long count = repository.count();
                assertThat(count).isGreaterThan(0);
            });
    }
}
```

## Distributed Scheduling with ShedLock

For multi-instance deployments, use ShedLock to ensure tasks run only once:

See [shedlock.md](./shedlock.md) for distributed scheduling setup.

## Best Practices

1. **Feature Flags**: Use `@ConditionalOnProperty` to enable/disable scheduling
2. **Configuration**: Externalize cron expressions to application.yml
3. **Error Handling**: Wrap task logic in try-catch to prevent scheduler from stopping
4. **Thread Pool**: Configure appropriate thread pool size
5. **Monitoring**: Add metrics and logging to scheduled tasks
6. **Idempotency**: Design tasks to be safely re-executable
7. **Transactional Boundaries**: Use `@Transactional` carefully with scheduled tasks
8. **Testing**: Disable scheduling in tests with property overrides

## Troubleshooting

### Task Not Running

1. Verify `@EnableScheduling` is present
2. Check class is a Spring bean (`@Component`, `@Service`, etc.)
3. Verify method is `public` (not `private` or `protected`)
4. Check conditional properties are correctly set
5. Review application startup logs for scheduling initialization

### Task Running Multiple Times

1. In multi-instance deployments, use ShedLock
2. Check thread pool configuration
3. Verify cron expression is correct
4. Use `fixedDelay` instead of `fixedRate` if overlap is an issue

### Performance Issues

1. Reduce thread pool size if too many concurrent tasks
2. Use `fixedDelay` to prevent task overlap
3. Add task duration metrics to identify slow tasks
4. Consider moving long-running tasks to async processing

## Configuration Properties Reference

```yaml
spring:
  task:
    scheduling:
      pool:
        size: 5                              # Thread pool size
      thread-name-prefix: "scheduled-"       # Thread name prefix
      shutdown:
        await-termination: true              # Wait for tasks on shutdown
        await-termination-period: 30s        # Max wait time

budgetanalyzer:
  {SERVICE_NAME}:
    scheduling:
      enabled: ${SCHEDULING_ENABLED:true}    # Master toggle
      import:
        enabled: true
        cron: "0 0 23 * * ?"                 # Import schedule
        import-on-startup: false
      cleanup:
        enabled: true
        cron: "0 0 2 * * ?"                  # Cleanup schedule
        retention-days: 90
```

## See Also

- [Spring Task Scheduling Documentation](https://docs.spring.io/spring-framework/reference/integration/scheduling.html)
- [Cron Expression Generator](https://www.freeformatter.com/cron-expression-generator-quartz.html)
- [ShedLock for Distributed Scheduling](./shedlock.md)
- [Spring Scheduling with @Scheduled](https://spring.io/guides/gs/scheduling-tasks/)

## Notes

- Scheduled methods must be in Spring-managed beans
- Methods must be public and have no parameters
- By default, all tasks run in a single thread (configure thread pool!)
- Cron expressions use server's local timezone unless specified
- Failed tasks don't affect other scheduled tasks
- Use ShedLock for multi-instance deployments to prevent duplicate execution
