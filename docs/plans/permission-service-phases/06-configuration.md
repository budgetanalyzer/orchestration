# Permission Service - Phase 7: Configuration

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

## Phase 7: Configuration

### 7.1 application.yml

```yaml
server:
  servlet:
    context-path: /permission-service
  port: 8086

logging:
  level:
    root: WARN
    org.budgetanalyzer: TRACE

spring:
  application:
    name: permission-service

  datasource:
    url: jdbc:postgresql://localhost:5432/permission
    username: budget_analyzer
    password: budget_analyzer
    driver-class-name: org.postgresql.Driver

  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false
    database-platform: org.hibernate.dialect.PostgreSQLDialect
    properties:
      hibernate:
        default_schema: public

  flyway:
    enabled: true
    locations: classpath:db/migration
    validate-on-migrate: true

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${AUTH0_ISSUER_URI:https://dev-gcz1r8453xzz0317.us.auth0.com/}
          audiences:
            - ${AUTH0_AUDIENCE:https://api.budgetanalyzer.org}

  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}

budgetanalyzer:
  service:
    http-logging:
      enabled: true
      log-level: DEBUG
```

### 7.2 application-test.yml

```yaml
spring:
  main:
    allow-bean-definition-overriding: true

  datasource:
    url: jdbc:h2:mem:testdb;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE
    driver-class-name: org.h2.Driver
    username: sa
    password:

  jpa:
    hibernate:
      ddl-auto: validate
    database-platform: org.hibernate.dialect.H2Dialect

  flyway:
    enabled: true
    locations: classpath:db/migration

  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://test-issuer.example.com/
          audiences:
            - https://test-api.example.com

  data:
    redis:
      host: localhost
      port: 6379

# Use embedded Redis for tests or mock
```

### 7.3 OpenAPI Configuration

```java
@Configuration
@OpenAPIDefinition(
    info = @Info(
        title = "Permission Service",
        version = "1.0",
        description = "Authorization management API for Budget Analyzer",
        contact = @Contact(name = "Budget Analyzer Team", email = "budgetanalyzer@proton.me"),
        license = @License(name = "MIT", url = "https://opensource.org/licenses/MIT")),
    servers = {
      @Server(url = "http://localhost:8080/api", description = "Local (via gateway)"),
      @Server(url = "http://localhost:8086/permission-service", description = "Local (direct)"),
      @Server(url = "https://api.budgetanalyzer.org", description = "Production")
    })
public class OpenApiConfig extends BaseOpenApiConfig {}
```
