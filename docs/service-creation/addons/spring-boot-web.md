# Spring Boot Web Add-On

## Overview

Add Spring Boot Web support to enable REST API endpoints with embedded Tomcat servlet container.

**Use this add-on when**: Your service needs to expose HTTP REST endpoints for client consumption.

**Skip this add-on when**: Your service is a background processor (message consumer, batch job, CLI tool) with no HTTP interface.

## Use Cases

- ✅ REST API microservices
- ✅ Services with HTTP endpoints
- ✅ Services requiring web MVC features
- ❌ Message consumers (use RabbitMQ add-on instead)
- ❌ Scheduled batch processors (use Scheduling add-on instead)
- ❌ CLI tools (base template only)

## What's Included

The `service-web` dependency provides:

- **Spring Boot Starter Web** - Embedded Tomcat, Spring MVC, REST support
- **HTTP Request/Response Logging** - Automatic logging via service-common
- **Global Exception Handling** - Standardized API error responses
- **Base JPA Entities** - AuditableEntity, SoftDeletableEntity (if using PostgreSQL)
- **OpenAPI Configuration** - BaseOpenApiConfig for Swagger (if using SpringDoc)
- **Standard API Response Formats** - Consistent error/success responses

**Note**: Spring Boot Actuator (health checks, metrics) comes from `service-core` and is already available in the base template.

## Step-by-Step Integration

### 1. Add Dependency

Update `build.gradle.kts`:

```kotlin
dependencies {
    // Change from service-core to service-web
    implementation(libs.service.web)  // Replaces service-core

    // ... rest of dependencies
}
```

**Note**: `service-web` includes `service-core` transitively, so you don't need both. Actuator is already available from `service-core`.

### 2. Add Web Configuration

Update `src/main/resources/application.yml`:

```yaml
spring:
  application:
    name: test-service

  # Web server configuration
  mvc:
    servlet:
      path: /test-service  # Context path for all endpoints

server:
  port: 9999  # HTTP port

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

logging:
  level:
    root: WARN
    org.budgetanalyzer: TRACE

# HTTP request/response logging (from service-web)
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

### 3. Create REST Controller

Create your first REST endpoint in `src/main/java/org/budgetanalyzer/test/api/`:

```java
package org.budgetanalyzer.test.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class TestController {

  @GetMapping("/health")
  public ResponseEntity<String> health() {
    return ResponseEntity.ok("Service is healthy");
  }
}
```

## Verify Integration

### 1. Build the Service

```bash
./gradlew clean build
```

### 2. Run the Service

```bash
./gradlew bootRun
```

You should see:
```
Tomcat started on port 9999 (http) with context path '/test-service'
```

### 3. Test Endpoints

```bash
# Test your custom endpoint
curl http://localhost:9999/test-service/api/v1/health

# Test actuator endpoint
curl http://localhost:9999/test-service/actuator/health
```

## HTTP Request Logging

The `service-web` dependency automatically enables HTTP request/response logging.

**Example log output**:
```
[HTTP] --> GET /test-service/api/v1/health
[HTTP] Request Headers: {Accept=[application/json], User-Agent=[curl/7.68.0]}
[HTTP] <-- 200 OK (15ms)
[HTTP] Response Headers: {Content-Type=[application/json]}
[HTTP] Response Body: "Service is healthy"
```

**Configuration options**:
```yaml
budgetanalyzer:
  service:
    http-logging:
      enabled: true           # Enable/disable logging
      log-level: DEBUG        # Log level (TRACE, DEBUG, INFO)
      include-request-body: true
      include-response-body: true
      max-body-size: 10000    # Max bytes to log
      exclude-patterns:       # Paths to exclude
        - /actuator/**
```

## Global Exception Handling

The `service-web` dependency provides automatic exception handling for common errors.

**Example**:

```java
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

  @GetMapping("/{id}")
  public User getUser(@PathVariable Long id) {
    return userService.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("User", "id", id));
  }
}
```

**Automatic response** (404):
```json
{
  "timestamp": "2025-11-17T10:30:00Z",
  "status": 404,
  "error": "Not Found",
  "message": "User not found with id: 123",
  "path": "/test-service/api/v1/users/123"
}
```

**Handled exceptions**:
- `ResourceNotFoundException` → 404
- `ValidationException` → 400
- `IllegalArgumentException` → 400
- Generic exceptions → 500

## Integration with API Gateway

When using the NGINX API gateway (standard for all Budget Analyzer services):

**Service configuration** (`application.yml`):
```yaml
server:
  port: 9999

spring:
  mvc:
    servlet:
      path: /test-service
```

**Gateway routing** (in `orchestration/nginx/nginx.dev.conf`):
```nginx
location /api/test-service {
    rewrite ^/api/test-service/(.*)$ /test-service/$1 break;
    proxy_pass http://test-service:9999;
}
```

**Client calls**:
```bash
# Direct to service (development)
curl http://localhost:9999/test-service/api/v1/health

# Through API gateway (production pattern)
curl http://localhost:8080/api/test-service/api/v1/health
```

## Common Patterns

### Request/Response DTOs

```java
package org.budgetanalyzer.test.api.request;

import jakarta.validation.constraints.NotBlank;

public record CreateUserRequest(
    @NotBlank String username,
    @NotBlank String email
) {}
```

```java
package org.budgetanalyzer.test.api.response;

public record UserResponse(
    Long id,
    String username,
    String email
) {}
```

### Controller with Validation

```java
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

  private final UserService userService;

  public UserController(UserService userService) {
    this.userService = userService;
  }

  @PostMapping
  public ResponseEntity<UserResponse> createUser(
      @Valid @RequestBody CreateUserRequest request) {
    UserResponse user = userService.create(request);
    return ResponseEntity.status(HttpStatus.CREATED).body(user);
  }
}
```

## Testing

### Integration Test

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class UserControllerIntegrationTest {

  @Autowired
  private TestRestTemplate restTemplate;

  @Test
  void shouldCreateUser() {
    CreateUserRequest request = new CreateUserRequest("john", "john@example.com");

    ResponseEntity<UserResponse> response = restTemplate.postForEntity(
        "/api/v1/users",
        request,
        UserResponse.class
    );

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    assertThat(response.getBody().username()).isEqualTo("john");
  }
}
```

### Controller Test (MockMvc)

```java
@WebMvcTest(UserController.class)
class UserControllerTest {

  @Autowired
  private MockMvc mockMvc;

  @MockBean
  private UserService userService;

  @Test
  void shouldReturnUser() throws Exception {
    UserResponse user = new UserResponse(1L, "john", "john@example.com");
    when(userService.findById(1L)).thenReturn(Optional.of(user));

    mockMvc.perform(get("/api/v1/users/1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.username").value("john"));
  }
}
```

## Troubleshooting

### Port Already in Use

```
Error: Port 9999 is already in use
```

**Solution**: Change port in `application.yml` or find/kill the process using the port:
```bash
lsof -i :9999
kill -9 <PID>
```

### Context Path Issues

If endpoints return 404, verify:
1. Context path is set: `spring.mvc.servlet.path=/test-service`
2. Controller mapping includes version: `@RequestMapping("/api/v1")`
3. Full URL includes context path: `http://localhost:9999/test-service/api/v1/endpoint`

### HTTP Logging Not Working

Verify configuration:
```yaml
budgetanalyzer:
  service:
    http-logging:
      enabled: true  # Must be true
```

Check log level:
```yaml
logging:
  level:
    org.budgetanalyzer: DEBUG  # Must be DEBUG or TRACE
```

## Related Add-Ons

- **[SpringDoc OpenAPI](springdoc-openapi.md)** - API documentation (Swagger UI)
- **[PostgreSQL + Flyway](postgresql-flyway.md)** - Database persistence for API data
- **[Spring Security](spring-security.md)** - Secure API endpoints

## Additional Resources

- [Spring Boot Web Documentation](https://docs.spring.io/spring-boot/reference/web/servlet.html)
- [Spring MVC Documentation](https://docs.spring.io/spring-framework/reference/web/webmvc.html)
- [REST API Best Practices](https://restfulapi.net/)
- [service-common Documentation](https://github.com/budgetanalyzer/service-common) (exception handling, logging)
