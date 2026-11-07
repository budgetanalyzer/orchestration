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
- Durable, atomic publication intent (transactional outbox); delivery of a failed send is not retried, so each use needs its own recovery contract
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

### 3. Bounded Synchronous Service-to-Service Calls

**Use Case:** A service needs another service's current, authoritative answer
before it can respond, and stale or replicated data would be wrong

**Example:** Session Gateway calls permission-service at login, with a
`POST` user sync by IdP identity, and on each heartbeat, with a `GET` by
internal user ID, to fetch account status, roles and permissions. A cached or
replicated copy could keep a deactivated account's grants. The mesh admits
only those two method and path pairs, both calls have a timeout, and neither
call is on the per-request `/api/*` path. See
[session-edge-authorization-pattern.md](session-edge-authorization-pattern.md)
for its failure behavior.

**Rules:**
- Call the owning service's API; never read another service's database or cache
- Bound each call with a timeout and define the caller's failure behavior
- Prefer async events when the caller does not need the answer to respond

### 4. External API Integration

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
- Pattern details: [@service-common/docs/advanced-patterns.md](https://github.com/budgetanalyzer/service-common/blob/main/docs/advanced-patterns.md#provider-abstraction-pattern)
- Example: currency-service FRED integration

## Event-Driven Architecture

### Spring Modulith Transactional Outbox

**Pattern:** Records publication intent atomically with the business change; it does not guarantee delivery

**How it works:**
```
1. Service writes domain data + event publication to database (single transaction)
2. After commit, a background listener publishes the message to RabbitMQ
3. Publication is marked completed only after the broker confirms it
4. A failed or interrupted publication stays incomplete; nothing resubmits it
5. Consuming service processes delivered messages
```

**What it provides:**
- No message for a rolled-back change, and no committed change without a recorded publication (no dual-write problem)
- Incomplete publications remain in `event_publication` as a record of failed sends

**What it does not provide:** Outstanding publications are not republished on
restart, so the outbox alone does not deliver a failed send.

**Current Usage:**
- currency-service: exchange rate import requests. Its recovery contract is
  import reconciliation: the startup and daily scheduled imports reload every
  enabled series from its latest stored rate, so a lost import request catches
  up at the next run. See the
  [MessagingEventListener contract](../../../currency-service/src/main/java/org/budgetanalyzer/currency/messaging/listener/MessagingEventListener.java).
  This fits reconstructible exchange-rate imports only; an event that cannot be
  reconstructed needs its own replay or reconciliation design before it uses
  this pattern.

**Documentation:**
- Pattern: [@service-common/docs/advanced-patterns.md](https://github.com/budgetanalyzer/service-common/blob/main/docs/advanced-patterns.md#event-driven-messaging)

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
- Gateway aggregates if needed
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
PGPASSWORD="$POSTGRES_TRANSACTION_SERVICE_PASSWORD" psql "host=localhost user=transaction_service dbname=budget_analyzer sslmode=verify-full sslrootcert=./nginx/certs/infra/infra-ca.pem" -c \
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

- **Patterns:** [@service-common/docs/advanced-patterns.md](https://github.com/budgetanalyzer/service-common/blob/main/docs/advanced-patterns.md)
- **Gateway:** [resource-routing-pattern.md](resource-routing-pattern.md)
- **Architecture:** [system-overview.md](system-overview.md)
- **Security:** [security-architecture.md](security-architecture.md)
