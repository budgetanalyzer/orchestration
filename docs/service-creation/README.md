# Service Creation Guide

## Overview

This directory contains documentation for creating new Spring Boot microservices in the Budget Analyzer project using the standardized template system.

## Quick Start

### Using the Creation Script (Recommended)

The fastest way to create a new service:

```bash
cd /workspace/orchestration
./scripts/create-service.sh
```

The script will:
- ✅ Interactively collect service configuration
- ✅ Clone the template repository
- ✅ Replace all placeholders
- ✅ Apply selected add-ons
- ✅ Initialize git repository
- ✅ Create GitHub repository (optional)
- ✅ Validate the build

**Time**: ~15 minutes (vs 2-3 hours manual setup)

See [Script Usage Guide](script-usage.md) for detailed documentation.

### Manual Template Usage

Alternative approach using GitHub's "Use this template" feature:

1. Visit: https://github.com/budgetanalyzer/spring-boot-service-template
2. Click "Use this template" → "Create a new repository"
3. Clone your new repository
4. Manually replace placeholders (see template README)
5. Apply add-ons manually (see add-on documentation below)

**Time**: 30-60 minutes

## Template System

### Template Repository

- **Location**: https://github.com/budgetanalyzer/spring-boot-service-template
- **Type**: GitHub Template Repository
- **Purpose**: Single source of truth for microservice structure
- **Updates**: Template versioned, changes via PR

### Template System Architecture

The service creation process uses a **template-based architecture** where all configuration text lives in the `spring-boot-service-template` repository as pre-verified template files.

#### Benefits

- ✅ **Pre-verified**: All YAML/SQL/TOML validated before use
- ✅ **Testable**: Templates independently tested in CI/CD
- ✅ **Maintainable**: Configuration changes made in template files, not shell scripts
- ✅ **Documented**: Templates ARE the documentation source
- ✅ **No duplication**: Single source of truth

#### Template Structure

- **Base template**: Minimal non-web baseline
- **Add-on templates**: 8 add-ons in separate directories
- **30 template files**: YAML, TOML, Kotlin, SQL, Java patches

See [spring-boot-service-template/TEMPLATE_USAGE.md](https://github.com/budgetanalyzer/spring-boot-service-template/blob/main/TEMPLATE_USAGE.md) for details.

#### How it Works

1. Script clones base template
2. Replaces placeholders (`{SERVICE_NAME}`, etc.)
3. For each selected add-on:
   - Copies template files
   - Substitutes placeholders
   - Appends to target files
   - Applies patches if needed

**No code generation**: Script only does file operations (copy, substitute, append)

### What's Included

The template provides:

- ✅ **Build Configuration**: Gradle with Kotlin DSL, version catalogs
- ✅ **Code Quality**: Checkstyle, Spotless, EditorConfig
- ✅ **Testing**: JUnit 5, Spring Boot Test
- ✅ **Minimal Dependencies**: service-web, Spring Boot Actuator
- ✅ **Standard Structure**: Organized package layout
- ✅ **Documentation**: CLAUDE.md, README.md templates
- ✅ **CI/CD**: GitHub Actions workflow
- ✅ **Java 24 Support**: JVM args for compatibility

### service-web Dependency

All services use `service-web` from service-common:

```kotlin
dependencies {
    implementation(libs.service.web)
}
```

**service-web provides**:
- Spring Boot Web (servlet-based)
- Spring Data JPA
- HTTP request/response logging
- API error handling
- OpenAPI base configuration
- CSV parsing utilities
- Audit entities and soft-delete patterns

See [service-common repository](https://github.com/budgetanalyzer/service-common) for details.

## Add-Ons

### Available Add-Ons

The template supports optional add-ons for common requirements:

| Add-On | Purpose | Documentation |
|--------|---------|---------------|
| **PostgreSQL + Flyway** | Database persistence with migrations | [postgresql-flyway.md](addons/postgresql-flyway.md) |
| **Redis** | Caching and session storage | [redis.md](addons/redis.md) |
| **RabbitMQ + Spring Cloud** | Event-driven messaging | [rabbitmq-spring-cloud.md](addons/rabbitmq-spring-cloud.md) |
| **WebFlux WebClient** | Reactive HTTP client | [webclient.md](addons/webclient.md) |
| **ShedLock** | Distributed scheduled task locking | [shedlock.md](addons/shedlock.md) |
| **SpringDoc OpenAPI** | API documentation (Swagger UI) | [springdoc-openapi.md](addons/springdoc-openapi.md) |
| **Spring Security** | Authentication and authorization | [spring-security.md](addons/spring-security.md) |
| **TestContainers** | Integration testing with real PostgreSQL | [testcontainers.md](addons/testcontainers.md) |
| **Spring Modulith** | Module boundaries and events | [spring-modulith.md](addons/spring-modulith.md) |
| **Scheduling** | Scheduled tasks with @Scheduled | [scheduling.md](addons/scheduling.md) |

See [Add-Ons Index](addons/README.md) for complete list and details.

### Applying Add-Ons

#### Automated (via Script)

The creation script prompts for add-on selection and applies them automatically.

#### Manual Application

Each add-on guide includes step-by-step instructions for manual application:

1. Read the add-on documentation
2. Add dependencies to `gradle/libs.versions.toml`
3. Add dependencies to `build.gradle.kts`
4. Configure in `application.yml`
5. Create necessary files (migrations, configs, etc.)

## Service Types

### Servlet-Based Microservices (Use Template)

The template is designed for **servlet-based** Spring Boot microservices:

- REST APIs
- Services with database persistence
- Services with scheduled tasks
- Services calling external APIs

**Technology Stack**:
- Spring Boot Web (servlet, blocking I/O)
- Spring Data JPA
- Traditional @RestController

### Reactive Services (Do NOT Use Template)

Some services require **reactive architecture** and cannot use this template:

- API gateways (Spring Cloud Gateway)
- WebFlux-based services
- Fully reactive services with R2DBC

**Why?**: Reactive and servlet architectures are incompatible. Mixing them causes conflicts.

**Alternative**: Create reactive services manually using Spring Cloud Gateway or WebFlux documentation.

## Configuration Conventions

### Naming Conventions

- **Service Name**: `{domain}-service` (e.g., `currency-service`, `transaction-service`)
- **Package Name**: `org.budgetanalyzer.{domain}` (e.g., `org.budgetanalyzer.currency`)
- **Main Class**: `{Domain}Application` (e.g., `CurrencyApplication`)
- **Port Range**: 8082+ (8080 reserved for NGINX gateway)

### Configuration Namespace

All services use consistent configuration namespacing:

```yaml
budgetanalyzer:
  service:
    # Shared features from service-common
    http-logging:
      enabled: true

  {service-name}:
    # Service-specific features
    feature-name:
      property: value
```

### Database Naming

**Default Pattern**: Dedicated database per service

- Service: `currency-service` → Database: `currency`
- Service: `user-service` → Database: `user`

**Exception**: Shared database for specific cases

- Service: `transaction-service` → Database: `budget_analyzer` (avoids SQL keyword confusion)

## Orchestration Integration

After creating a service, integrate it with the orchestration:

### 1. Docker Compose

Add service to [`docker-compose.yml`](../../docker-compose.yml):

```yaml
services:
  {service-name}:
    build:
      context: ../{service-name}
      dockerfile: Dockerfile
    ports:
      - "{port}:{port}"
    environment:
      - SPRING_PROFILES_ACTIVE=dev
    depends_on:
      - postgres
```

### 2. NGINX Gateway

Add routes to [`nginx/nginx.dev.conf`](../../nginx/nginx.dev.conf):

```nginx
location /api/{resource} {
    rewrite ^/api/(.*)$ /$1 break;
    proxy_pass http://host.docker.internal:{port}/{service-name};
    # ... proxy headers
}
```

See [NGINX README](../../nginx/README.md) for detailed routing configuration.

### 3. Documentation

Update orchestration documentation:

- Add service to [orchestration CLAUDE.md](../../CLAUDE.md)
- Create service-specific CLAUDE.md
- Document API endpoints
- Update architecture diagrams

## Best Practices

### 1. Service Independence

- Each service should be independently deployable
- Avoid tight coupling between services
- Use events for inter-service communication
- Database per service (avoid shared databases)

### 2. Configuration Management

- Use environment variables for environment-specific config
- Keep secrets out of application.yml
- Use Spring profiles for environment-specific behavior

### 3. API Versioning

- Version APIs for backward compatibility: `/api/v1/...`
- Plan for API evolution
- Document breaking changes

### 4. Health Checks

- All services expose `/actuator/health`
- Include database health indicators
- Include external dependency health checks

### 5. Logging

- Use service-common's SafeLogger
- Mark sensitive data with @Sensitive
- Enable HTTP logging in development
- Disable HTTP logging in production (or limit to errors)

### 6. Testing

- Unit tests for business logic
- Integration tests with TestContainers
- API tests with MockMvc or RestAssured
- Test coverage > 80%

### 7. Documentation

- Keep CLAUDE.md up-to-date
- Document all API endpoints
- Include examples in API docs
- Use SpringDoc for interactive API documentation

## Development Workflow

### Creating a New Service

1. **Plan**: Define service purpose, boundaries, dependencies
2. **Create**: Run `./scripts/create-service.sh` or use template manually
3. **Configure**: Select appropriate add-ons
4. **Implement**: Add business logic, APIs, tests
5. **Integrate**: Add to docker-compose, configure NGINX
6. **Document**: Update CLAUDE.md, API docs
7. **Test**: Run tests, validate build
8. **Deploy**: Push to repository, create PR

### Updating service-web

When service-common is updated:

1. Update `serviceCommon` version in `gradle/libs.versions.toml`
2. Run `./gradlew clean build`
3. Test service with new version
4. Commit version bump

### Updating Java Version

To upgrade Java version:

1. Update `java` version in `gradle/libs.versions.toml`
2. Update JVM args if needed (for compatibility)
3. Run `./gradlew clean build`
4. Test thoroughly
5. Update Dockerfile base image

## Troubleshooting

### Common Issues

#### Build Fails: service-web Not Found

**Solution**: Publish service-common to Maven Local:

```bash
cd /workspace/service-common
./gradlew publishToMavenLocal
```

#### Port Already in Use

**Solution**: Check docker-compose.yml and choose different port:

```bash
grep "ports:" docker-compose.yml
```

#### Database Connection Failed

**Solution**: Verify database exists and credentials match:

```bash
docker compose ps postgres
docker compose logs postgres
```

#### NGINX 502 Bad Gateway

**Solution**: Verify service is running and port is correct:

```bash
curl http://localhost:{port}/{service-name}/actuator/health
```

See [NGINX Troubleshooting](../../nginx/README.md#troubleshooting) for detailed debugging.

## Reference Documentation

### Service Creation

- [Script Usage Guide](script-usage.md) - Detailed script documentation
- [Add-Ons Index](addons/README.md) - All available add-ons
- [Template Repository](https://github.com/budgetanalyzer/spring-boot-service-template) - Template source code

### Architecture

- [Orchestration CLAUDE.md](../../CLAUDE.md) - Overall architecture
- [NGINX Configuration](../../nginx/README.md) - Gateway routing
- [Implementation Plan](microservice-template-plan.md) - Design decisions

### Spring Boot

- [Spring Boot Documentation](https://docs.spring.io/spring-boot/docs/current/reference/html/)
- [Spring Data JPA](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/)
- [Spring Cloud Stream](https://docs.spring.io/spring-cloud-stream/docs/current/reference/html/)

## Support

For questions or issues:

1. Check this documentation
2. Review add-on documentation
3. Check service-common documentation
4. Review template repository
5. Ask team in Slack/Teams
6. Create issue in orchestration repository

## Contributing

### Updating the Template

Template changes go through PR process:

1. Fork template repository
2. Make changes
3. Test with script
4. Create PR
5. Review and merge
6. Update template version

### Adding New Add-Ons

To add a new add-on:

1. Create add-on documentation in `addons/`
2. Update script with add-on logic
3. Test with multiple services
4. Update this README
5. Create PR

### Improving the Script

Script improvements welcome:

1. Add feature to script
2. Test thoroughly
3. Update script-usage.md
4. Create PR

## Version History

- **v1.0.0** (2025-11-17): Initial release
  - Creation script with interactive prompts
  - 7 add-ons supported
  - GitHub integration
  - Build validation
  - Comprehensive documentation

## Future Enhancements

Planned improvements:

- [ ] Dry-run mode for script
- [ ] Custom template repository support
- [ ] Docker Compose auto-generation
- [ ] NGINX config auto-generation
- [ ] More add-ons (GraphQL, gRPC, etc.)
- [ ] Template versioning support
- [ ] Service health check validation
- [ ] Kubernetes manifests generation

---

**Happy service creation! 🚀**
