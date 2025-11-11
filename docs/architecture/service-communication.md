# Service Communication Patterns

**Category:** Inter-Service Architecture
**Status:** Active

## Overview

Budget Analyzer services communicate using multiple patterns depending on the use case: synchronous REST for user-facing operations and asynchronous messaging for background processing and cross-service events.

## Communication Patterns

### 1. Synchronous REST (Frontend → Backend)

**Use Case:** User-initiated actions requiring immediate response

**Pattern:**
```
User → Frontend → NGINX Gateway → Backend Service → Response
```

**Example:**
```javascript
// Frontend: Get transactions
const response = await fetch('/api/v1/transactions');
```

**Characteristics:**
- Request-response cycle
- Blocking (user waits for response)
- Timeout-sensitive
- Stateless

**When to Use:**
- CRUD operations
- User queries (search, list, get)
- Operations requiring immediate feedback

**When NOT to Use:**
- Long-running operations (use async)
- Operations not requiring immediate response
- High-volume background processing

### 2. Asynchronous Messaging (Service → Service)

**Use Case:** Background processing, cross-service notifications, eventual consistency

**Pattern:**
```
Service A → Transactional Outbox → RabbitMQ → Service B
```

**Implementation:** Spring Modulith with transactional outbox

**Example:**
```java
// Publishing service
@ApplicationModuleListener
public void onCurrencyImported(CurrencyImportedEvent event) {
    // Event published to RabbitMQ via transactional outbox
}

// Consuming service
@ApplicationModuleListener
public void handleCurrencyImported(CurrencyImportedEvent event) {
    // Process event asynchronously
}
```

**Characteristics:**
- Fire-and-forget
- Non-blocking
- Guaranteed delivery (transactional outbox)
- Eventual consistency

**When to Use:**
- Cross-service notifications
- Background data processing
- Decoupled workflows
- Scheduled operations

**When NOT to Use:**
- User needs immediate response
- Strong consistency required
- Simple request-response

### 3. External API Integration

**Use Case:** Integrating with third-party services

**Pattern:** Provider abstraction layer

**Example:**
```java
// Abstraction
public interface ExchangeRateProvider {
    List<ExchangeRate> fetchRates(String currencyCode, LocalDate startDate, LocalDate endDate);
}

// Implementation
@Service
public class FredExchangeRateProvider implements ExchangeRateProvider {
    // FRED API client implementation
}
```

**Characteristics:**
- Abstracted behind interface
- Resilience patterns (retry, circuit breaker)
- Caching for performance
- Configuration-driven

**When to Use:**
- Third-party data sources
- External service dependencies
- Pluggable implementations

**Documentation:**
- Pattern details: [@service-common/docs/advanced-patterns.md](https://github.com/budget-analyzer/service-common/blob/main/docs/advanced-patterns.md#provider-abstraction-pattern)
- Example: currency-service FRED integration

## Event-Driven Architecture

### Spring Modulith Transactional Outbox

**Pattern:** Guarantees event delivery with database consistency

**How it works:**
```
1. Service writes domain data + event to database (single transaction)
2. Outbox table persists event
3. Background job publishes event to RabbitMQ
4. Event marked as published in outbox
5. Consuming service processes event
```

**Benefits:**
- ✅ No lost events (transactional)
- ✅ At-least-once delivery
- ✅ Survives service crashes
- ✅ No dual-write problem

**Configuration:**
```yaml
spring:
  modulith:
    events:
      enabled: true
      republish-outstanding-events-on-restart: true
```

**Current Usage:**
- currency-service: Exchange rate import events
- Future: Cross-service domain events

**Documentation:**
- Pattern: [@service-common/docs/advanced-patterns.md](https://github.com/budget-analyzer/service-common/blob/main/docs/advanced-patterns.md#event-driven-messaging)

## Communication Flow Examples

### Example 1: Transaction Import

**Synchronous (user-facing):**
```
1. User uploads CSV
2. Frontend → POST /api/v1/transactions/import
3. Gateway → transaction-service
4. Service validates, parses, saves transactions
5. Response: 201 Created with import summary
6. Frontend displays success message
```

### Example 2: Currency Rate Scheduled Import

**Asynchronous (background):**
```
1. Scheduled job triggers in currency-service
2. Service fetches rates from FRED API
3. Service saves rates to database
4. Service publishes CurrencyImportedEvent to outbox
5. Background job sends event to RabbitMQ
6. (Future) Other services consume event if needed
```

### Example 3: Cross-Service Analytics (Future)

**Hybrid (sync + async):**
```
1. User requests analytics report
2. Frontend → POST /api/v1/analytics/generate
3. Gateway → analytics-service
4. Service returns: 202 Accepted (job ID)
5. Service publishes AnalyticsRequestedEvent
6. Background worker processes request
7. Worker publishes AnalyticsCompletedEvent
8. Frontend polls: GET /api/v1/analytics/jobs/:id
9. When complete, frontend displays report
```

## Anti-Patterns to Avoid

### ❌ Synchronous Service-to-Service Calls

**Don't do this:**
```java
// transaction-service calling currency-service directly
@Autowired
private RestTemplate restTemplate;

public Transaction createTransaction(TransactionRequest request) {
    // DON'T: Synchronous HTTP call to another service
    ExchangeRate rate = restTemplate.getForObject(
        "http://currency-service:8084/exchange-rates/..." ,
        ExchangeRate.class
    );
    // Creates tight coupling and cascading failures
}
```

**Instead:**
- Cache exchange rates locally (read from shared database or Redis)
- Use async events if cross-service coordination needed
- Denormalize data if needed for performance

### ❌ Shared Database Tables

**Don't do this:**
```sql
-- DON'T: Both services writing to same table
-- transaction-service writes transactions
-- currency-service writes transactions (for conversion tracking)
```

**Instead:**
- Each service owns its tables
- Use events to notify other services
- Duplicate data if needed (eventual consistency)

### ❌ Frontend Calling Multiple Services

**Don't do this:**
```javascript
// DON'T: Frontend orchestrating multiple services
const transactions = await fetch('/api/v1/transactions');
const currencies = await fetch('/api/v1/currencies');
const rates = await fetch('/api/v1/exchange-rates');
// Manually combining data in frontend
```

**Instead:**
- Gateway or BFF aggregates if needed
- Single API endpoint returns complete data
- Backend handles data composition

## Resilience Patterns

### Circuit Breaker (External APIs)

**Pattern:** Prevent cascading failures from external dependencies

**Implementation:**
```java
@CircuitBreaker(name = "fred-api", fallbackMethod = "fallbackRates")
public List<ExchangeRate> fetchRates(...) {
    // Call external API
}

private List<ExchangeRate> fallbackRates(...) {
    // Return cached data or empty list
}
```

### Retry with Backoff

**Pattern:** Retry transient failures with exponential backoff

**Configuration:**
```yaml
resilience4j:
  retry:
    instances:
      fred-api:
        maxAttempts: 3
        waitDuration: 1s
        exponentialBackoff: true
```

### Timeout

**Pattern:** Fail fast on slow dependencies

**Configuration:**
```yaml
resilience4j:
  timelimiter:
    instances:
      fred-api:
        timeout-duration: 10s
```

## Monitoring & Observability

### Discovery Commands

```bash
# Check RabbitMQ queues
docker exec rabbitmq rabbitmqctl list_queues

# View message flow
docker logs rabbitmq | grep "delivering"

# Check outbox table (per service)
docker exec postgres psql -U budget_analyzer -c \
  "SELECT * FROM event_publication WHERE completion_date IS NULL;"
```

### Key Metrics to Monitor

- **REST APIs:** Response time, error rate, throughput
- **Message queues:** Queue depth, consumer lag, delivery rate
- **Circuit breakers:** Open/closed state, failure rate
- **Outbox:** Pending events, publishing lag

## Future Enhancements

### Planned

- [ ] Service mesh (Istio/Linkerd) for traffic management
- [ ] Distributed tracing (OpenTelemetry)
- [ ] Centralized logging (ELK stack)
- [ ] API rate limiting

### Under Consideration

- [ ] GraphQL gateway (alternative to REST)
- [ ] gRPC for service-to-service calls
- [ ] Event sourcing for audit trail

## References

- **Patterns:** [@service-common/docs/advanced-patterns.md](https://github.com/budget-analyzer/service-common/blob/main/docs/advanced-patterns.md)
- **Gateway:** [resource-routing-pattern.md](resource-routing-pattern.md)
- **Architecture:** [system-overview.md](system-overview.md)
- **Security:** [security-architecture.md](security-architecture.md)
