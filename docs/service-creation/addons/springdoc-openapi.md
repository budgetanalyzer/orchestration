# Add-On: SpringDoc OpenAPI (Swagger UI)

## Purpose
Generate interactive API documentation using OpenAPI 3.0 specification.
Provides automatically generated, interactive API documentation accessible via Swagger UI.

## Use Cases
- API documentation for developers
- Interactive API testing
- Client SDK generation
- API contract validation
- Integration with API gateways
- Postman collection generation

## Benefits
- **Automatic Documentation**: Generated from code annotations
- **Interactive Testing**: Try API endpoints directly in browser
- **Always Up-to-Date**: Documentation syncs with code
- **OpenAPI Standard**: Industry-standard specification
- **Base Configuration**: Leverage service-common's BaseOpenApiConfig

## Dependencies

### Step 1: Add to `gradle/libs.versions.toml`

```toml
[versions]
springdoc = "2.7.0"

[libraries]
# Add to existing libraries section
springdoc-openapi-starter-webmvc-ui = { module = "org.springdoc:springdoc-openapi-starter-webmvc-ui", version.ref = "springdoc" }
```

### Step 2: Add to `build.gradle.kts`

```kotlin
dependencies {
    // ... existing dependencies

    // SpringDoc OpenAPI
    implementation(libs.springdoc.openapi.starter.webmvc.ui)
}
```

## Configuration

### Using BaseOpenApiConfig from Service-Common

Service-common provides `BaseOpenApiConfig` with standard OpenAPI configuration.

```java
package org.budgetanalyzer.{DOMAIN_NAME}.config;

import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import org.budgetanalyzer.common.config.BaseOpenApiConfig;
import org.springframework.context.annotation.Configuration;

/**
 * OpenAPI configuration for {SERVICE_NAME}.
 * Extends BaseOpenApiConfig from service-common for standard setup.
 */
@Configuration
public class OpenApiConfig extends BaseOpenApiConfig {

    @Override
    protected Info apiInfo() {
        return new Info()
            .title("{ServiceClassName} API")
            .description("REST API for {SERVICE_NAME}")
            .version("1.0.0")
            .contact(new Contact()
                .name("Budget Analyzer Team")
                .email("team@budgetanalyzer.org")
                .url("https://github.com/budgetanalyzer"))
            .license(new License()
                .name("Apache 2.0")
                .url("https://www.apache.org/licenses/LICENSE-2.0"));
    }
}
```

### What BaseOpenApiConfig Provides

From service-common, `BaseOpenApiConfig` provides:

```java
package org.budgetanalyzer.common.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;

import java.util.List;

/**
 * Base OpenAPI configuration with standard settings.
 * Extend this class and override apiInfo() to customize.
 */
public abstract class BaseOpenApiConfig {

    @Value("${server.servlet.context-path:}")
    private String contextPath;

    @Value("${server.port:8080}")
    private String serverPort;

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
            .info(apiInfo())
            .servers(List.of(
                new Server()
                    .url("http://localhost:" + serverPort + contextPath)
                    .description("Local Development Server"),
                new Server()
                    .url("http://localhost:8080" + contextPath)
                    .description("API Gateway (Development)")
            ));
    }

    /**
     * Override this method to provide service-specific API information.
     */
    protected abstract Info apiInfo();
}
```

### Application Properties

```yaml
# application.yml
spring:
  application:
    name: {SERVICE_NAME}

  mvc:
    servlet:
      path: /{SERVICE_NAME}  # Context path for service

springdoc:
  api-docs:
    path: /v3/api-docs  # OpenAPI spec endpoint
    enabled: true
  swagger-ui:
    path: /swagger-ui.html  # Swagger UI endpoint
    enabled: true
    operationsSorter: method
    tagsSorter: alpha
    tryItOutEnabled: true
  show-actuator: false  # Hide actuator endpoints from docs

budgetanalyzer:
  service:
    http-logging:
      exclude-patterns:
        - /swagger-ui/**
        - /v3/api-docs/**
```

### Accessing Swagger UI

After starting the application:

**Direct Service Access:**
- Swagger UI: http://localhost:{SERVICE_PORT}/{SERVICE_NAME}/swagger-ui.html
- OpenAPI Spec: http://localhost:{SERVICE_PORT}/{SERVICE_NAME}/v3/api-docs

**Via API Gateway:**
- Swagger UI: http://localhost:8080/{SERVICE_NAME}/swagger-ui.html
- OpenAPI Spec: http://localhost:8080/{SERVICE_NAME}/v3/api-docs

## Customization Points

### Custom Security Schemes

```java
@Configuration
public class OpenApiConfig extends BaseOpenApiConfig {

    @Override
    protected Info apiInfo() {
        return new Info()
            .title("{ServiceClassName} API")
            .version("1.0.0");
    }

    @Bean
    public OpenAPI customOpenAPIWithSecurity() {
        OpenAPI openAPI = customOpenAPI();

        // Add JWT security scheme
        openAPI.components(new Components()
            .addSecuritySchemes("bearerAuth", new SecurityScheme()
                .type(SecurityScheme.Type.HTTP)
                .scheme("bearer")
                .bearerFormat("JWT")
                .description("JWT authentication")));

        // Apply security globally
        openAPI.security(List.of(
            new SecurityRequirement().addList("bearerAuth")
        ));

        return openAPI;
    }
}
```

### Additional Servers

```java
@Override
public OpenAPI customOpenAPI() {
    OpenAPI openAPI = super.customOpenAPI();

    openAPI.addServersItem(new Server()
        .url("https://api.production.com/{SERVICE_NAME}")
        .description("Production Server"));

    return openAPI;
}
```

## API Documentation Annotations

### Controller Documentation

```java
package org.budgetanalyzer.{DOMAIN_NAME}.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/transactions")
@Tag(name = "Transactions", description = "Transaction management APIs")
public class TransactionController {

    @Operation(
        summary = "Get all transactions",
        description = "Retrieves a list of all transactions in the system"
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "200",
            description = "Successfully retrieved transactions",
            content = @Content(
                mediaType = "application/json",
                schema = @Schema(implementation = TransactionDto.class)
            )
        ),
        @ApiResponse(
            responseCode = "500",
            description = "Internal server error"
        )
    })
    @GetMapping
    public ResponseEntity<List<TransactionDto>> getAllTransactions() {
        // Implementation
    }

    @Operation(summary = "Get transaction by ID")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Transaction found"),
        @ApiResponse(responseCode = "404", description = "Transaction not found")
    })
    @GetMapping("/{id}")
    public ResponseEntity<TransactionDto> getTransaction(
        @Parameter(description = "Transaction ID", required = true)
        @PathVariable Long id
    ) {
        // Implementation
    }

    @Operation(summary = "Create new transaction")
    @ApiResponse(responseCode = "201", description = "Transaction created successfully")
    @PostMapping
    public ResponseEntity<TransactionDto> createTransaction(
        @io.swagger.v3.oas.annotations.parameters.RequestBody(
            description = "Transaction to create",
            required = true
        )
        @RequestBody TransactionDto transaction
    ) {
        // Implementation
    }
}
```

### DTO/Schema Documentation

```java
package org.budgetanalyzer.{DOMAIN_NAME}.api.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.time.LocalDate;

@Schema(description = "Transaction data transfer object")
public record TransactionDto(

    @Schema(description = "Transaction unique identifier", example = "123", accessMode = Schema.AccessMode.READ_ONLY)
    Long id,

    @Schema(description = "Transaction description", example = "Grocery shopping", required = true)
    @NotBlank
    String description,

    @Schema(description = "Transaction amount", example = "45.99", required = true)
    @NotNull
    BigDecimal amount,

    @Schema(description = "Transaction date", example = "2024-01-15", required = true)
    @NotNull
    LocalDate transactionDate,

    @Schema(description = "Category ID", example = "5")
    Long categoryId
) {}
```

### Enum Documentation

```java
@Schema(description = "Transaction status")
public enum TransactionStatus {

    @Schema(description = "Transaction is pending approval")
    PENDING,

    @Schema(description = "Transaction is approved and processed")
    APPROVED,

    @Schema(description = "Transaction was rejected")
    REJECTED
}
```

## Grouping Endpoints with Tags

```java
@Tag(name = "Transactions", description = "Transaction management")
@RestController
@RequestMapping("/api/v1/transactions")
public class TransactionController {
    // Endpoints will be grouped under "Transactions"
}

@Tag(name = "Categories", description = "Category management")
@RestController
@RequestMapping("/api/v1/categories")
public class CategoryController {
    // Endpoints will be grouped under "Categories"
}
```

## Global Configuration

### Custom Operation Customizer

```java
package org.budgetanalyzer.{DOMAIN_NAME}.config;

import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.media.Content;
import io.swagger.v3.oas.models.media.MediaType;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.responses.ApiResponse;
import org.springdoc.core.customizers.OperationCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.HandlerMethod;

@Configuration
public class SwaggerCustomization {

    /**
     * Add common error responses to all endpoints.
     */
    @Bean
    public OperationCustomizer customizeOperations() {
        return (Operation operation, HandlerMethod handlerMethod) -> {
            // Add 500 response to all operations
            operation.getResponses().addApiResponse("500",
                new ApiResponse()
                    .description("Internal Server Error")
                    .content(new Content()
                        .addMediaType("application/json",
                            new MediaType()
                                .schema(new Schema<>().$ref("#/components/schemas/ErrorResponse")))));

            return operation;
        };
    }
}
```

### Exclude Endpoints from Documentation

```java
@Hidden  // Hides entire controller from documentation
@RestController
public class InternalController {
    // Won't appear in Swagger UI
}

// Or hide specific endpoints
@GetMapping("/internal")
@Hidden
public String internalEndpoint() {
    // Won't appear in Swagger UI
}
```

## Real-World Example: Transaction Service

```java
package org.budgetanalyzer.transaction.config;

import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import org.budgetanalyzer.common.config.BaseOpenApiConfig;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig extends BaseOpenApiConfig {

    @Override
    protected Info apiInfo() {
        return new Info()
            .title("Transaction Service API")
            .description("""
                REST API for transaction management in the Budget Analyzer system.

                Features:
                - Transaction CRUD operations
                - CSV import/export
                - Transaction categorization
                - Search and filtering
                """)
            .version("1.0.0")
            .contact(new Contact()
                .name("Budget Analyzer Team")
                .email("team@budgetanalyzer.org")
                .url("https://github.com/budgetanalyzer/transaction-service"))
            .license(new License()
                .name("Apache 2.0")
                .url("https://www.apache.org/licenses/LICENSE-2.0"));
    }
}
```

## Testing

### Integration Test

```java
package org.budgetanalyzer.{DOMAIN_NAME}.api;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class OpenApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void openApiDocsShouldBeAccessible() throws Exception {
        mockMvc.perform(get("/{SERVICE_NAME}/v3/api-docs"))
            .andExpect(status().isOk());
    }

    @Test
    void swaggerUiShouldBeAccessible() throws Exception {
        mockMvc.perform(get("/{SERVICE_NAME}/swagger-ui.html"))
            .andExpect(status().isOk());
    }
}
```

## Advanced Features

### Pageable Support

SpringDoc automatically documents Pageable parameters:

```java
@GetMapping
public ResponseEntity<Page<TransactionDto>> getTransactions(
    @PageableDefault(size = 20, sort = "transactionDate,desc") Pageable pageable
) {
    // Swagger UI will show: page, size, sort parameters
}
```

### File Upload Documentation

```java
@Operation(summary = "Upload CSV file")
@PostMapping(value = "/import", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
public ResponseEntity<ImportResult> importCsv(
    @Parameter(description = "CSV file to import", required = true)
    @RequestParam("file") MultipartFile file
) {
    // Implementation
}
```

### Polymorphic Types

```java
@Schema(
    description = "Payment method",
    oneOf = {CreditCardPayment.class, BankTransferPayment.class},
    discriminatorProperty = "type"
)
public interface Payment {
    String getType();
}
```

## Production Configuration

### Disable Swagger UI in Production

```yaml
# application-prod.yml
springdoc:
  swagger-ui:
    enabled: false  # Disable Swagger UI in production
  api-docs:
    enabled: true   # Keep OpenAPI spec for tooling
```

Or use profile-based configuration:

```java
@Configuration
@Profile("!prod")  // Only active when NOT in production
public class OpenApiConfig extends BaseOpenApiConfig {
    // Configuration
}
```

## Export OpenAPI Specification

### During Build

```kotlin
// build.gradle.kts
tasks.register("generateOpenApiSpec") {
    dependsOn("bootRun")
    doLast {
        // Download spec from running application
        exec {
            commandLine("curl", "-o", "openapi.json",
                "http://localhost:8082/{SERVICE_NAME}/v3/api-docs")
        }
    }
}
```

### Generate Client SDK

Use OpenAPI Generator to generate client SDKs:

```bash
# Generate TypeScript client
openapi-generator-cli generate \
  -i http://localhost:8080/{SERVICE_NAME}/v3/api-docs \
  -g typescript-fetch \
  -o ./client-sdk

# Generate Java client
openapi-generator-cli generate \
  -i http://localhost:8080/{SERVICE_NAME}/v3/api-docs \
  -g java \
  -o ./java-client
```

## Best Practices

1. **Use BaseOpenApiConfig**: Leverage service-common for consistency
2. **Document DTOs**: Add `@Schema` annotations to all DTOs
3. **Provide Examples**: Use `example` attribute in `@Schema`
4. **Group Endpoints**: Use `@Tag` to organize endpoints
5. **Document Errors**: Include error responses in `@ApiResponses`
6. **Hide Internal APIs**: Use `@Hidden` for internal endpoints
7. **Disable in Production**: Turn off Swagger UI in production
8. **Version Your API**: Include version in URL and Info
9. **Test Documentation**: Write tests to ensure docs are accessible
10. **Export Specification**: Generate OpenAPI spec during build

## Troubleshooting

### Swagger UI Not Loading

1. Check `springdoc.swagger-ui.enabled=true`
2. Verify URL includes context path
3. Check for browser console errors
4. Ensure application is running

### Endpoints Not Appearing

1. Verify controller has `@RestController`
2. Check endpoints aren't marked `@Hidden`
3. Ensure controller is in component scan package
4. Review springdoc configuration

### Custom DTO Not Documented

1. Add `@Schema` annotation to class
2. Use DTO in controller method signature
3. Reference in `@ApiResponse` content

## See Also

- [SpringDoc OpenAPI Documentation](https://springdoc.org/)
- [OpenAPI Specification](https://spec.openapis.org/oas/latest.html)
- [Swagger UI Documentation](https://swagger.io/tools/swagger-ui/)
- [OpenAPI Generator](https://openapi-generator.tech/)

## Notes

- SpringDoc automatically scans controllers and generates documentation
- BaseOpenApiConfig from service-common provides standard configuration
- Swagger UI is interactive - you can test API endpoints directly
- OpenAPI spec can be used to generate client SDKs
- Consider disabling Swagger UI in production for security
- Documentation is generated at runtime from code and annotations
