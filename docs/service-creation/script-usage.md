# Service Creation Script Usage Guide

## Overview

The `create-service.sh` script automates the creation of new Spring Boot microservices using the standardized template repository. It reduces service creation time from 2-3 hours to approximately 15 minutes.

## Location

```bash
/workspace/orchestration/scripts/create-service.sh
```

## Prerequisites

Before running the script, ensure you have:

- **git**: Version control
- **gh CLI**: GitHub integration (optional, for automatic repository creation)
- **Java 24+**: For building and testing the generated service
- **Gradle**: Provided via wrapper in generated service

### Check Prerequisites

```bash
git --version
gh --version
java -version
```

### Authenticate GitHub CLI (Optional)

If you want automatic GitHub repository creation:

```bash
gh auth login
```

## Basic Usage

### Quick Start

```bash
cd /workspace/orchestration
./scripts/create-service.sh
```

The script will interactively prompt you for:

1. **Service Configuration**
   - Service name (e.g., `currency-service`)
   - Domain name (e.g., `currency`)
   - Service port (e.g., `8082`)
   - Java version (default: `24`)
   - service-web version (default: `0.0.1-SNAPSHOT`)
   - Database name (default: same as domain name)

2. **Add-On Selection**
   - PostgreSQL + Flyway
   - Redis
   - RabbitMQ + Spring Cloud Stream
   - WebFlux WebClient
   - ShedLock
   - SpringDoc OpenAPI
   - Spring Security

3. **GitHub Integration**
   - Create GitHub repository automatically (requires gh CLI)

## Configuration Options

### Service Name

- **Format**: Lowercase, alphanumeric + hyphens
- **Must**: Start with a letter and end with `-service`
- **Examples**:
  - ✅ `currency-service`
  - ✅ `transaction-service`
  - ✅ `user-profile-service`
  - ❌ `currencyService` (not kebab-case)
  - ❌ `currency` (missing `-service` suffix)
  - ❌ `9currency-service` (starts with number)

### Domain Name

- **Purpose**: Used for package naming and class names
- **Default**: First word of service name (before first hyphen)
- **Format**: Lowercase alphanumeric starting with letter
- **Examples**:
  - Service: `currency-service` → Domain: `currency`
  - Service: `user-profile-service` → Domain: `user` (or override to `userprofile`)

### Service Port

- **Range**: 1024-65535
- **Validation**: Script checks if port is already in use in docker-compose.yml
- **Convention**: Start at 8082 for microservices (8080 is NGINX gateway)
- **Examples**:
  - `8082` - Currency service
  - `8083` - Transaction service
  - `8084` - User service

### Database Name

- **Default**: Same as domain name (dedicated database per service)
- **Alternative**: Leave empty for shared `budget_analyzer` database
- **Format**: Lowercase alphanumeric + underscores
- **Examples**:
  - Domain: `currency` → Database: `currency` (dedicated)
  - Domain: `transaction` → Database: `budget_analyzer` (shared, to avoid SQL keyword confusion)

### Java Version

- **Default**: `24`
- **Format**: Single number (e.g., `17`, `21`, `24`)
- **Note**: Must match your installed JDK version

### service-web Version

- **Default**: `0.0.1-SNAPSHOT`
- **Format**: Semantic version (e.g., `1.0.0`, `0.0.1-SNAPSHOT`)
- **Note**: Must match published version in Maven Local

## Add-Ons

### PostgreSQL + Flyway

**Includes**:
- Spring Boot Data JPA
- Flyway database migrations
- PostgreSQL driver
- H2 for testing

**Adds to Project**:
- Dependencies in `build.gradle.kts`
- Database configuration in `application.yml`
- `db/migration/` directory
- Initial migration template `V1__initial_schema.sql`

**Use When**: Service needs database persistence

### Redis

**Includes**:
- Spring Boot Data Redis
- Spring Cache abstraction

**Adds to Project**:
- Redis dependencies
- Cache configuration in `application.yml`
- Connection pool settings

**Use When**: Service needs caching or session storage

### RabbitMQ + Spring Cloud Stream

**Includes**:
- Spring Cloud Stream
- RabbitMQ binder
- Spring Modulith events (AMQP)

**Adds to Project**:
- RabbitMQ dependencies
- Spring Cloud BOM
- RabbitMQ configuration in `application.yml`
- Example channel bindings (commented)

**Use When**: Service needs event-driven messaging

### WebFlux WebClient

**Includes**:
- Spring WebFlux (for WebClient only)
- Reactor Test

**Adds to Project**:
- WebFlux dependency
- Reactor test utilities

**Important**:
- Does NOT convert service to reactive architecture
- Only provides HTTP client capability
- Service remains servlet-based

**Use When**: Service needs to call external REST APIs

### ShedLock

**Includes**:
- ShedLock core
- JDBC provider

**Adds to Project**:
- ShedLock dependencies
- Database migration for `shedlock` table (`V2__create_shedlock_table.sql`)

**Requirements**:
- **Requires PostgreSQL add-on** (will error if not enabled)

**Use When**:
- Service has scheduled tasks
- Service runs with multiple instances
- Tasks should execute only once per schedule

### SpringDoc OpenAPI

**Includes**:
- SpringDoc OpenAPI starter
- Swagger UI

**Adds to Project**:
- SpringDoc dependency
- Automatic OpenAPI documentation generation
- Swagger UI endpoint

**Access**: `http://localhost:{PORT}/{SERVICE_NAME}/swagger-ui.html`

**Use When**: Service needs API documentation

### Spring Security

**Includes**:
- Spring Boot Security
- Spring Security Test

**Adds to Project**:
- Spring Security dependencies
- Default security configuration (all endpoints protected)

**Important**:
- Security is enabled by default
- Must create `SecurityConfig` class to customize

**Use When**: Service needs authentication/authorization

## Script Flow

The script follows this sequence:

1. **Check Prerequisites**
   - Validates required tools are installed
   - Checks for gh CLI (optional)

2. **Collect Configuration**
   - Interactive prompts for service details
   - Add-on selection
   - GitHub integration preference

3. **Clone Template**
   - Clones template repository from GitHub
   - Removes template .git directory

4. **Replace Placeholders**
   - Replaces all placeholders in files
   - Renames package directories
   - Renames Application class files

5. **Apply Add-Ons**
   - Adds dependencies to `libs.versions.toml`
   - Updates `build.gradle.kts`
   - Configures `application.yml`
   - Creates necessary files (migrations, etc.)

6. **Initialize Git**
   - Creates new git repository
   - Stages all files
   - Creates initial commit

7. **Create GitHub Repository** (if enabled)
   - Creates private repository on GitHub
   - Pushes initial commit
   - Sets up remote

8. **Validate Build**
   - Runs `./gradlew clean build`
   - Reports success or failure

9. **Display Summary**
   - Shows service details
   - Lists next steps
   - Provides relevant documentation links

## Output

### Generated Service Structure

```
{service-name}/
├── .editorconfig
├── .gitignore
├── build.gradle.kts
├── settings.gradle.kts
├── gradlew
├── gradlew.bat
├── gradle/
│   ├── libs.versions.toml
│   └── wrapper/
├── config/
│   └── checkstyle/
│       └── checkstyle.xml
├── src/
│   ├── main/
│   │   ├── java/org/budgetanalyzer/{domain}/
│   │   │   ├── {ServiceClassName}Application.java
│   │   │   ├── api/
│   │   │   ├── config/
│   │   │   ├── domain/
│   │   │   ├── repository/
│   │   │   └── service/
│   │   └── resources/
│   │       ├── application.yml
│   │       └── db/migration/  (if PostgreSQL enabled)
│   └── test/
│       ├── java/org/budgetanalyzer/{domain}/
│       │   └── {ServiceClassName}ApplicationTests.java
│       └── resources/
│           └── application.yml
├── CLAUDE.md
└── README.md
```

## Error Handling

### Script Errors

The script includes comprehensive error handling:

- **Validation**: All inputs validated before proceeding
- **Rollback**: Incomplete services cleaned up on error
- **Clear Messages**: Helpful error messages with suggestions

### Common Issues

#### 1. Port Already in Use

**Error**: Port appears to be in use in docker-compose.yml

**Solution**:
- Choose a different port
- Or confirm to continue anyway

#### 2. Service Directory Exists

**Error**: Directory already exists

**Solution**:
- Choose 'yes' to delete and continue
- Or choose 'no' and rename/move existing directory

#### 3. Build Fails

**Error**: `./gradlew clean build` fails

**Solution**:
- Check build output for specific errors
- Verify service-web is published to Maven Local
- Check Java version matches
- Review add-on configurations

#### 4. GitHub Repository Creation Fails

**Error**: gh CLI fails to create repository

**Solution**:
- Verify gh CLI is authenticated: `gh auth status`
- Create repository manually later using provided command
- Check repository doesn't already exist

## Next Steps After Creation

After the script completes successfully:

### 1. Review Generated Service

```bash
cd /path/to/{service-name}
```

Review generated files, especially:
- `src/main/resources/application.yml` - Configuration
- `build.gradle.kts` - Dependencies
- `src/main/java/.../Application.java` - Main class

### 2. Run Service Locally

```bash
./gradlew bootRun
```

Verify service starts successfully.

### 3. Add to Orchestration

Edit `/workspace/orchestration/docker-compose.yml`:

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
      - DB_USERNAME=postgres
      - DB_PASSWORD=postgres
    depends_on:
      - postgres
      # Add other dependencies as needed
```

### 4. Configure NGINX Routing

Edit `/workspace/orchestration/nginx/nginx.dev.conf`:

```nginx
# Add location block for service API endpoints
location /api/{resource} {
    rewrite ^/api/(.*)$ /$1 break;
    proxy_pass http://host.docker.internal:{port}/{service-name};
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

See [nginx/README.md](../../nginx/README.md) for detailed NGINX configuration guide.

### 5. Update Documentation

- Add service to [orchestration/CLAUDE.md](../../CLAUDE.md)
- Create service-specific CLAUDE.md
- Document API endpoints
- Update architecture diagrams

## Examples

### Example 1: Minimal Service

```bash
./scripts/create-service.sh

# Prompts:
Service name: notification-service
Domain name: [notification]
Service port: 8085
Java version: [24]
service-web version: [0.0.1-SNAPSHOT]
Database name: [notification]

# Add-ons: All 'n'

# GitHub: n
```

**Result**: Minimal Spring Boot service with actuator only

### Example 2: Full-Featured REST API Service

```bash
./scripts/create-service.sh

# Prompts:
Service name: user-profile-service
Domain name: [user]
Service port: 8086
Java version: [24]
service-web version: [0.0.1-SNAPSHOT]
Database name: [user]

# Add-ons:
PostgreSQL + Flyway: y
Redis: y
RabbitMQ: y
WebFlux WebClient: y
ShedLock: y
SpringDoc OpenAPI: y
Spring Security: n

# GitHub: y
```

**Result**: Full-featured service with database, caching, messaging, HTTP client, distributed locking, and API docs

### Example 3: Scheduled Job Service

```bash
./scripts/create-service.sh

# Prompts:
Service name: data-import-service
Domain name: [data]
Service port: 8087
Java version: [24]
service-web version: [0.0.1-SNAPSHOT]
Database name: [data]

# Add-ons:
PostgreSQL + Flyway: y
Redis: n
RabbitMQ: n
WebFlux WebClient: y
ShedLock: y
SpringDoc OpenAPI: n
Spring Security: n

# GitHub: y
```

**Result**: Service configured for scheduled data imports with distributed locking

## Troubleshooting

### "Template file not found" Error

If you see errors like:
```
Error: Template file not found: /workspace/spring-boot-service-template/addons/postgresql-flyway/application.yml
```

**Solution**: Ensure `spring-boot-service-template` is cloned in `/workspace/`:
```bash
cd /workspace
git clone https://github.com/budgetanalyzer/spring-boot-service-template.git
```

The script expects this repository structure:
```
/workspace/
├── orchestration/                  # This repository
│   └── scripts/create-service.sh
├── spring-boot-service-template/   # Template repository
│   ├── base/
│   └── addons/
└── {new-service}/                  # Generated service
```

### Build Fails After Generation

1. **Check service-web is published**:
   ```bash
   cd /workspace/service-common
   ./gradlew publishToMavenLocal
   ```

2. **Verify Java version**:
   ```bash
   java -version
   ```

3. **Clean build**:
   ```bash
   cd /path/to/{service-name}
   ./gradlew clean build --stacktrace
   ```

### Template Repository Not Found

**Error**: Failed to clone template repository

**Solutions**:
- Verify template repository exists: `https://github.com/budgetanalyzer/spring-boot-service-template`
- Check internet connection
- Verify git credentials

### Placeholder Not Replaced

If you find unreplaced placeholders like `{SERVICE_NAME}`:

1. Check script placeholder replacement logic
2. Verify file type is included in find command
3. Manually replace with find/replace

## Advanced Usage

### Dry Run (Future Enhancement)

Not yet implemented, but planned:

```bash
./scripts/create-service.sh --dry-run
```

Would show what would be created without actually creating it.

### Custom Template Repository (Future Enhancement)

Not yet implemented, but planned:

```bash
./scripts/create-service.sh --template-repo https://github.com/custom/template.git
```

Would allow using a custom template repository.

## Add-On Documentation

For detailed add-on configuration and usage, see:

```
/workspace/orchestration/docs/service-creation/addons/
├── postgresql-flyway.md
├── redis.md
├── rabbitmq-spring-cloud.md
├── webclient.md
├── shedlock.md
├── springdoc-openapi.md
├── spring-security.md
├── scheduling.md
├── spring-modulith.md
└── testcontainers.md
```

## See Also

- [Service Creation Overview](README.md)
- [Add-Ons Index](addons/README.md)
- [NGINX Configuration Guide](../../nginx/README.md)
- [Orchestration CLAUDE.md](../../CLAUDE.md)

## Support

For issues or questions:

1. Check this documentation
2. Review add-on documentation
3. Check script error messages
4. Review template repository issues: https://github.com/budgetanalyzer/spring-boot-service-template/issues
5. Review orchestration repository issues: https://github.com/budgetanalyzer/orchestration/issues
