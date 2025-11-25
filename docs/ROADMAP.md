# Budget Analyzer Roadmap

This document outlines planned features and enhancements across the Budget Analyzer application. For current implementation details, see individual service CLAUDE.md files.

**Last Updated**: 2025-11-25

---

## Project Status: Reference Architecture Complete

This project has reached its intended scope as a reference architecture. We are no longer actively developing Budget Analyzer features.

**Current focus:**
- Documentation improvements
- Architectural discussions
- Bug fixes in existing functionality

**Out of scope (intentionally left as exercises):**
- Data ownership: "Which transactions belong to which user?"
- Cross-service user scoping
- Multi-tenancy / organization isolation

See [system-overview.md](architecture/system-overview.md#intentional-boundaries) for why this boundary exists.

The items below remain as reference for what a production system might need - but we're not actively implementing them.

---

## Orchestration & Infrastructure

### Planned

#### HIGH PRIORITY - Production Readiness
- [ ] **Production Docker Compose configuration** - Separate production-optimized compose file with proper resource limits, health checks, and restart policies
- [ ] **Complete Kubernetes manifests for all services** - Deployments, services, ingress, configmaps, secrets for production deployment
- [ ] **CI/CD pipeline integration** - GitHub Actions or Jenkins for automated builds, tests, and deployments
- [ ] **Expand automated testing scripts** - Beyond current markdown/repo validation; add integration test orchestration

#### MEDIUM PRIORITY - Observability & Monitoring
- [ ] **Monitoring and observability stack** - Prometheus and Grafana for metrics collection and visualization
- [ ] **Distributed tracing** - Jaeger or Zipkin for request flow visibility across microservices
- [ ] **Centralized logging** - ELK (Elasticsearch, Logstash, Kibana) or Loki stack for log aggregation

#### MEDIUM PRIORITY - API Documentation
- [ ] **API documentation aggregation** - Aggregate Swagger/OpenAPI specs from all services (note: generate-unified-api-docs.sh exists as starting point)

#### LOW PRIORITY - Optional Features
- [ ] **Service mesh integration** - Istio or Linkerd for advanced traffic management (optional)

---

## Service-Common (Shared Library)

### Planned

#### HIGH PRIORITY - Library Features
- [ ] **Add MapStruct integration** - Provide base mapper interfaces for DTO transformations across all services
- [ ] **Add validation utilities** - Common validation annotations and validators
- [ ] **Add pagination support** - Standard Page and Pageable response wrappers
- [ ] **Add audit logging interceptor** - Automatic logging of entity changes

#### HIGH PRIORITY - Testing
- [ ] **Add example usage tests** - Demonstrate how to use each feature

#### MEDIUM PRIORITY - Utilities
- [ ] **Add JSON utilities** - Common JSON serialization/deserialization helpers
- [ ] **Add date/time utilities** - Standard date formatting and timezone handling
- [ ] **Add currency utilities** - ISO 4217 currency code validation
- [ ] **Add HTTP client utilities** - Standardized RestTemplate/WebClient configuration

#### MEDIUM PRIORITY - Documentation
- [ ] **Add usage examples** - Create example microservice showing all features
- [ ] **Add migration guide** - Document how to migrate existing services to use this library
- [ ] **Add contribution guide** - Guidelines for adding new features

#### LOW PRIORITY - Optional Features
- [ ] **Add metrics support** - Standard Micrometer metrics for common operations
- [ ] **Add distributed tracing** - OpenTelemetry integration for tracing
- [ ] **Add event publishing support** - Base event classes for domain events
- [ ] **Add security utilities** - Common security filters and authentication helpers

---

## Currency Service

### Planned

#### 🚨 HIGH PRIORITY - Testing & Quality
_(All critical testing items completed as of 2025-11-15)_

#### MEDIUM PRIORITY - Observability
- [ ] **Complete Prometheus metrics setup** - Configure Prometheus endpoint exposure; Micrometer instrumentation already present in scheduler
- [ ] **Implement distributed tracing** - Add Zipkin/Jaeger for request flow visibility across microservices

#### MEDIUM PRIORITY - Data Management
- [ ] **Add audit logging for data changes** - Track who changed what and when using JPA entity listeners
- [ ] **Implement MapStruct for DTO mapping** - Replace manual mapping with compile-time safe DTO transformations

#### LOW PRIORITY - Optional Features
- [ ] **Add GraphQL endpoint (optional)** - Provide GraphQL API alongside REST for flexible querying
- [ ] **Implement event publishing (Kafka/RabbitMQ)** - Publish domain events for exchange rate updates to enable event-driven architecture

#### Notes
**Circuit Breakers Not Needed**: Circuit breakers were considered for FRED API integration but deemed inappropriate. The scheduled import job makes only 1-3 API calls per day (1 request with max 3 retry attempts), which doesn't match the high-frequency usage pattern that circuit breakers are designed for (hundreds to thousands of requests per minute). Existing retry logic with exponential backoff plus alerting via Micrometer metrics is the appropriate solution.

---

## Transaction Service

### Planned

#### 🚨 HIGH PRIORITY - Testing & Quality (CRITICAL - Zero tests currently exist!)
- [ ] **Add comprehensive unit tests** - Service, repository, and controller layer tests
- [ ] **Add CSV import integration tests** - End-to-end tests with sample CSV files from each supported bank
- [ ] **Add transaction search tests** - Test all filter combinations and edge cases in JPA specifications
- [ ] **Add error handling tests** - Validate exception handling for invalid CSVs, missing files, malformed data
- [ ] **Implement TestContainers for integration tests** - Replace H2 with PostgreSQL test containers for realistic integration testing

#### HIGH PRIORITY - Database Management
- [ ] **Document baseline migration** - Ensure V1__initial_schema.sql is properly documented
- [ ] **Add indexes for search queries** - Index frequently searched columns (date, accountId, bankName, currencyIsoCode)

#### HIGH PRIORITY - API Enhancements
- [ ] **Add pagination to transaction list and search endpoints** - Currently returns all results; need Page/Pageable support
- [ ] **Add bulk delete endpoint** - Delete multiple transactions in single request

#### MEDIUM PRIORITY - Resilience & Features
- [ ] **Implement MapStruct for DTO mapping** - Replace manual mapping with compile-time safe DTO transformations
- [ ] **Add duplicate transaction detection** - Prevent importing same transaction multiple times (by date, amount, description)
- [ ] **Add transaction categorization** - Support manual or automatic categorization of transactions
- [ ] **Add CSV export capability** - Export transactions back to CSV format

#### MEDIUM PRIORITY - Observability
- [ ] **Add Prometheus metrics** - Custom business metrics for imports, search queries, error rates
- [ ] **Implement distributed tracing** - Add Zipkin/Jaeger for request flow visibility across microservices
- [ ] **Add audit logging for data changes** - Track who changed what and when using JPA entity listeners

#### MEDIUM PRIORITY - Data Management
- [ ] **Implement hard delete capability** - Admin endpoint to permanently remove soft-deleted transactions
- [ ] **Add transaction reconciliation** - Compare imported transactions against expected balances

#### LOW PRIORITY - Optional Features
- [ ] **Add GraphQL endpoint (optional)** - Provide GraphQL API alongside REST for flexible querying
- [ ] **Implement event publishing (Kafka/RabbitMQ)** - Publish domain events for transaction CRUD to enable event-driven architecture
- [ ] **Add real-time CSV validation endpoint** - Validate CSV format without importing
- [ ] **Add scheduled cleanup job** - Purge soft-deleted transactions older than retention period
- [ ] **Add support for CSV templates** - Generate template CSV files for each bank format

---

## Budget Analyzer Web

### Planned
- TBD

---

## API Gateway / NGINX

### Planned
- [ ] **Implement API rate limiting** - Protect against abuse with request throttling at gateway level

---

## Cross-Service Initiatives

### Planned
- TBD

---

## Completed

### Service-Common
- [x] **Add integration tests** - Test Spring Boot integration and component scanning (Completed: 2025-11-11)

### Currency Service
- [x] **Add comprehensive integration tests** - Controller, service, and repository layer tests (Completed: 2025-11-15)
- [x] **Migrate to Testcontainers for integration tests** - Replace H2 with PostgreSQL/Redis test containers for realistic integration testing (Completed: 2025-11-15)
- [x] **Add PostgreSQL partial indexes after Testcontainers migration** - Replace full indexes with partial indexes (e.g., `WHERE completion_date IS NULL` for event_publication table) (Completed: 2025-11-15)
- [x] **Add WireMock for external API testing** - Mock FRED API responses for reliable external integration tests (Completed: 2025-11-15)

_Items moved here when implemented_

---

## Notes

- **How to use this roadmap**: Items listed here are potential future enhancements, not commitments
- **Implementation**: Move items from "Planned" to a GitHub Issue when work begins
- **Completion**: Move items from "Planned" to "Completed" section when shipped to production
- **Priority**: Items are not ordered by priority within sections
- **Contributing**: Add new ideas to the appropriate service section
