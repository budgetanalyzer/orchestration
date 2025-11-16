# Add-On: WebClient (Spring WebFlux HTTP Client)

## Purpose
Adds Spring WebFlux's `WebClient` for making HTTP requests to external APIs.
This does NOT convert your service to reactive architecture - it only adds
the HTTP client capability.

## Use Case
- Calling external REST APIs (e.g., FRED API in currency-service)
- Modern replacement for RestTemplate
- Non-blocking HTTP client in servlet applications

## Important Notes
- Your service remains servlet-based (Spring Boot Web)
- Only WebClient is used, NOT reactive web controllers
- You CANNOT mix reactive controllers with servlet controllers
- WebClient is configured as a bean and can be injected where needed

## Dependencies

### Step 1: Add to `gradle/libs.versions.toml`

```toml
[libraries]
# Add to existing libraries section
spring-boot-starter-webflux = { module = "org.springframework.boot:spring-boot-starter-webflux" }
reactor-test = { module = "io.projectreactor:reactor-test" }
```

### Step 2: Add to `build.gradle.kts`

```kotlin
dependencies {
    // ... existing dependencies

    // WebClient for HTTP calls
    implementation(libs.spring.boot.starter.webflux)

    // Testing reactive components
    testImplementation(libs.reactor.test)
}
```

## Configuration

### WebClient Bean Configuration

Create a configuration class to define WebClient beans:

```java
package org.budgetanalyzer.{DOMAIN_NAME}.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration
public class WebClientConfig {

    /**
     * Creates a default WebClient bean with common settings.
     * This can be injected and used throughout the application.
     */
    @Bean
    public WebClient.Builder webClientBuilder() {
        return WebClient.builder()
            .defaultHeader("User-Agent", "{SERVICE_NAME}")
            .codecs(configurer -> configurer
                .defaultCodecs()
                .maxInMemorySize(16 * 1024 * 1024) // 16MB buffer
            );
    }

    /**
     * Optional: Create named WebClient beans for specific external services.
     * Example: WebClient configured for a specific API
     */
    @Bean
    public WebClient externalApiClient(WebClient.Builder webClientBuilder) {
        return webClientBuilder
            .baseUrl("https://api.example.com")
            .build();
    }
}
```

## Usage Examples

### Basic GET Request

```java
package org.budgetanalyzer.{DOMAIN_NAME}.service;

import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

@Service
public class ExampleService {

    private final WebClient webClient;

    public ExampleService(WebClient.Builder webClientBuilder) {
        this.webClient = webClientBuilder.build();
    }

    public String fetchData(String id) {
        return webClient.get()
            .uri("https://api.example.com/data/{id}", id)
            .retrieve()
            .bodyToMono(String.class)
            .block(); // Block to convert Mono to synchronous result
    }
}
```

### POST Request with Body

```java
public String createResource(ResourceDto resource) {
    return webClient.post()
        .uri("https://api.example.com/resources")
        .contentType(MediaType.APPLICATION_JSON)
        .bodyValue(resource)
        .retrieve()
        .bodyToMono(String.class)
        .block();
}
```

### Error Handling

```java
public String fetchDataWithErrorHandling(String id) {
    return webClient.get()
        .uri("https://api.example.com/data/{id}", id)
        .retrieve()
        .onStatus(
            HttpStatusCode::is4xxClientError,
            response -> Mono.error(new RuntimeException("Client error: " + response.statusCode()))
        )
        .onStatus(
            HttpStatusCode::is5xxServerError,
            response -> Mono.error(new RuntimeException("Server error: " + response.statusCode()))
        )
        .bodyToMono(String.class)
        .block();
}
```

### Using Named Bean (Injected WebClient)

```java
@Service
public class ExampleService {

    private final WebClient externalApiClient;

    public ExampleService(WebClient externalApiClient) {
        this.externalApiClient = externalApiClient;
    }

    public String fetchData(String id) {
        return externalApiClient.get()
            .uri("/data/{id}", id) // Base URL already configured
            .retrieve()
            .bodyToMono(String.class)
            .block();
    }
}
```

### Async (Non-Blocking) Usage

If you want to use WebClient asynchronously in a servlet application:

```java
public CompletableFuture<String> fetchDataAsync(String id) {
    return webClient.get()
        .uri("https://api.example.com/data/{id}", id)
        .retrieve()
        .bodyToMono(String.class)
        .toFuture(); // Convert Mono to CompletableFuture
}
```

## Testing

### Unit Test with MockWebServer

```java
package org.budgetanalyzer.{DOMAIN_NAME}.service;

import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;

import static org.assertj.core.api.Assertions.assertThat;

class ExampleServiceTest {

    private MockWebServer mockWebServer;
    private ExampleService service;

    @BeforeEach
    void setUp() throws Exception {
        mockWebServer = new MockWebServer();
        mockWebServer.start();

        WebClient webClient = WebClient.builder()
            .baseUrl(mockWebServer.url("/").toString())
            .build();

        service = new ExampleService(webClient);
    }

    @AfterEach
    void tearDown() throws Exception {
        mockWebServer.shutdown();
    }

    @Test
    void fetchData_returnsExpectedResponse() {
        // Arrange
        mockWebServer.enqueue(new MockResponse()
            .setBody("{\"data\": \"test\"}")
            .addHeader("Content-Type", "application/json"));

        // Act
        String result = service.fetchData("123");

        // Assert
        assertThat(result).contains("test");
    }
}
```

### Test with WebTestClient

```java
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.reactive.server.WebTestClient;

@SpringBootTest
@AutoConfigureWebTestClient
class WebClientIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void testExternalApiCall() {
        // Test reactive components if needed
    }
}
```

## Real-World Example: Currency Service

The currency-service uses WebClient to fetch exchange rates from the FRED API:

```java
@Service
public class FredApiService {

    private final WebClient fredWebClient;

    public FredApiService(WebClient.Builder webClientBuilder,
                          @Value("${budgetanalyzer.currency-service.fred.base-url}") String baseUrl,
                          @Value("${budgetanalyzer.currency-service.fred.api-key}") String apiKey) {
        this.fredWebClient = webClientBuilder
            .baseUrl(baseUrl)
            .defaultUriVariables(Map.of("api_key", apiKey, "file_type", "json"))
            .build();
    }

    public FredObservationsResponse fetchObservations(String seriesId, LocalDate startDate) {
        return fredWebClient.get()
            .uri(uriBuilder -> uriBuilder
                .path("/series/observations")
                .queryParam("series_id", seriesId)
                .queryParam("observation_start", startDate.toString())
                .queryParam("api_key", "{api_key}")
                .queryParam("file_type", "{file_type}")
                .build())
            .retrieve()
            .bodyToMono(FredObservationsResponse.class)
            .block();
    }
}
```

## Configuration Properties

Add API-specific properties to `application.yml`:

```yaml
budgetanalyzer:
  {SERVICE_NAME}:
    external-api:
      base-url: ${EXTERNAL_API_URL:https://api.example.com}
      api-key: ${EXTERNAL_API_KEY}
      timeout-seconds: 30
```

## Common Patterns

### Timeout Configuration

```java
@Bean
public WebClient webClientWithTimeout(WebClient.Builder builder) {
    return builder
        .clientConnector(new ReactorClientHttpConnector(
            HttpClient.create()
                .responseTimeout(Duration.ofSeconds(30))
        ))
        .build();
}
```

### Retry Logic

```java
import reactor.util.retry.Retry;

public String fetchDataWithRetry(String id) {
    return webClient.get()
        .uri("/data/{id}", id)
        .retrieve()
        .bodyToMono(String.class)
        .retryWhen(Retry.backoff(3, Duration.ofSeconds(2))
            .maxBackoff(Duration.ofSeconds(10)))
        .block();
}
```

### Custom Headers

```java
public String fetchDataWithHeaders(String id, String authToken) {
    return webClient.get()
        .uri("/data/{id}", id)
        .header("Authorization", "Bearer " + authToken)
        .header("X-Custom-Header", "value")
        .retrieve()
        .bodyToMono(String.class)
        .block();
}
```

## Additional Dependencies for Testing

If using MockWebServer for testing:

```toml
# In gradle/libs.versions.toml
[versions]
mockwebserver = "4.12.0"

[libraries]
mockwebserver = { module = "com.squareup.okhttp3:mockwebserver", version.ref = "mockwebserver" }
```

```kotlin
// In build.gradle.kts
dependencies {
    testImplementation(libs.mockwebserver)
}
```

## See Also

- [Spring WebClient Documentation](https://docs.spring.io/spring-framework/reference/web/webflux-webclient.html)
- [Reactor Core Documentation](https://projectreactor.io/docs/core/release/reference/)
- [Spring WebFlux Testing](https://docs.spring.io/spring-framework/reference/testing/webtestclient.html)

## Notes

- WebClient is part of Spring WebFlux but can be used in servlet applications
- Blocking calls (`.block()`) convert reactive Mono/Flux to synchronous results
- For fully reactive applications, consider using WebFlux controllers instead of servlet controllers
- WebClient is the recommended replacement for RestTemplate (which is in maintenance mode)
