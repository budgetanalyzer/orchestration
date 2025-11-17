#!/bin/bash

################################################################################
# Budget Analyzer - Spring Boot Microservice Creation Script
#
# This script automates the creation of new Spring Boot microservices using
# the standardized template repository.
#
# Usage: ./create-service.sh
#
# The script will:
# 1. Prompt for service details (name, port, domain, etc.)
# 2. Allow selection of add-ons (PostgreSQL, Redis, etc.)
# 3. Clone and customize the template repository
# 4. Apply selected add-ons
# 5. Initialize git repository
# 6. Optionally create GitHub repository
# 7. Validate the generated service builds
#
# Prerequisites:
# - git
# - gh CLI (for GitHub integration)
# - Java 24+
# - Gradle (via wrapper)
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_REPO="git@github.com:budgetanalyzer/spring-boot-service-template.git"
DEFAULT_JAVA_VERSION="24"
DEFAULT_SERVICE_COMMON_VERSION="0.0.1-SNAPSHOT"

# Template paths
TEMPLATE_REPO_PATH=""  # Will be set after SERVICE_DIR is determined
TEMPLATE_ADDONS_PATH=""  # Will be set after TEMPLATE_REPO_PATH

# Service configuration (populated by prompts)
SERVICE_NAME=""
DOMAIN_NAME=""
SERVICE_CLASS_NAME=""
SERVICE_PORT=""
DATABASE_NAME=""
JAVA_VERSION=""
SERVICE_COMMON_VERSION=""
SERVICE_DIR=""

# Add-on flags
USE_SPRING_BOOT_WEB=false
USE_POSTGRESQL=false
USE_REDIS=false
USE_RABBITMQ=false
USE_WEBFLUX=false
USE_SCHEDULING=false
USE_SHEDLOCK=false
USE_SPRINGDOC=false
USE_TESTCONTAINERS=false
USE_SECURITY=false

# GitHub integration flags
CREATE_GITHUB_REPO=false
GITHUB_REPO_CREATED=false

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Budget Analyzer - Spring Boot Microservice Creator${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────────${NC}"
}

################################################################################
# Validation Functions
################################################################################

validate_service_name() {
    local name="$1"

    # Must be lowercase, alphanumeric + hyphens, start with letter
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        return 1
    fi

    # Must end with -service
    if [[ ! "$name" =~ -service$ ]]; then
        return 1
    fi

    return 0
}

validate_port() {
    local port="$1"

    # Must be a number
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Must be in valid range
    if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi

    # Check if port is already in use (in docker-compose.yml)
    if grep -q "\"$port:" "$WORKSPACE_DIR/docker-compose.yml" 2>/dev/null; then
        print_warning "Port $port appears to be in use in docker-compose.yml"
        read -p "Continue anyway? (y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || return 1
    fi

    return 0
}

validate_database_name() {
    local name="$1"

    # Must not be empty (each service has its own database)
    if [ -z "$name" ]; then
        return 1
    fi

    # Must be alphanumeric + underscores, start with letter
    if [[ ! "$name" =~ ^[a-z][a-z0-9_]*$ ]]; then
        return 1
    fi

    return 0
}

validate_version() {
    local version="$1"

    # Basic semantic version check (allows -SNAPSHOT)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Z]+)?$ ]]; then
        return 1
    fi

    return 0
}

################################################################################
# Prerequisites Check
################################################################################

check_prerequisites() {
    print_section "Checking Prerequisites"

    local missing_tools=()

    # Check for git
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    else
        print_success "git found: $(git --version)"
    fi

    # Check for gh CLI
    if ! command -v gh &> /dev/null; then
        print_warning "gh CLI not found (GitHub integration will be disabled)"
    else
        print_success "gh CLI found: $(gh --version | head -n1)"
    fi

    # Check for Java
    if ! command -v java &> /dev/null; then
        missing_tools+=("java")
    else
        local java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
        print_success "Java found: version $java_version"
    fi

    # Report missing tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools and try again."
        exit 1
    fi

    echo ""
}

################################################################################
# Interactive Prompts
################################################################################

prompt_service_details() {
    print_section "Service Configuration"

    # Service name
    while true; do
        read -p "Service name (e.g., 'currency-service'): " SERVICE_NAME
        if validate_service_name "$SERVICE_NAME"; then
            break
        else
            print_error "Invalid service name. Must be lowercase, alphanumeric + hyphens, start with letter, and end with '-service'"
        fi
    done

    # Extract default domain name (first word before first hyphen)
    local default_domain=$(echo "$SERVICE_NAME" | sed 's/-service$//' | sed 's/-.*$//')

    # Domain name
    read -p "Domain name [$default_domain] (or specify custom): " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-$default_domain}

    # Validate domain name
    while [[ ! "$DOMAIN_NAME" =~ ^[a-z][a-z0-9]*$ ]]; do
        print_error "Invalid domain name. Must be lowercase alphanumeric starting with letter"
        read -p "Domain name: " DOMAIN_NAME
    done

    # Generate class name
    SERVICE_CLASS_NAME=$(echo "$DOMAIN_NAME" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')

    # Service port
    while true; do
        read -p "Service port (e.g., 8082): " SERVICE_PORT
        if validate_port "$SERVICE_PORT"; then
            break
        else
            print_error "Invalid port. Must be a number between 1024-65535 and not in use"
        fi
    done

    # Java version
    read -p "Java version [$DEFAULT_JAVA_VERSION]: " JAVA_VERSION
    JAVA_VERSION=${JAVA_VERSION:-$DEFAULT_JAVA_VERSION}

    # service-common version
    read -p "service-web version [$DEFAULT_SERVICE_COMMON_VERSION]: " SERVICE_COMMON_VERSION
    SERVICE_COMMON_VERSION=${SERVICE_COMMON_VERSION:-$DEFAULT_SERVICE_COMMON_VERSION}

    # Set service directory
    SERVICE_DIR="$WORKSPACE_DIR/../$SERVICE_NAME"

    # Set template paths
    TEMPLATE_REPO_PATH="$(dirname "$SERVICE_DIR")/spring-boot-service-template"
    TEMPLATE_ADDONS_PATH="$TEMPLATE_REPO_PATH/addons"

    # Summary
    echo ""
    print_section "Configuration Summary"
    echo "Service Name:          $SERVICE_NAME"
    echo "Domain Name:           $DOMAIN_NAME"
    echo "Class Name:            ${SERVICE_CLASS_NAME}Application"
    echo "Service Port:          $SERVICE_PORT"
    echo "Java Version:          $JAVA_VERSION"
    echo "service-web Version:   $SERVICE_COMMON_VERSION"
    echo "Service Directory:     $SERVICE_DIR"
    echo ""

    read -p "Is this correct? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_error "Configuration rejected. Please restart the script."
        exit 1
    fi
}

prompt_addons() {
    print_section "Add-On Selection"

    echo "Select add-ons to include (y/n):"
    echo ""

    read -p "  Spring Boot Web (REST API with embedded Tomcat) [y/n]: " USE_SPRING_BOOT_WEB
    [[ "$USE_SPRING_BOOT_WEB" =~ ^[Yy]$ ]] && USE_SPRING_BOOT_WEB=true || USE_SPRING_BOOT_WEB=false

    read -p "  PostgreSQL + Flyway (database persistence with migrations) [y/n]: " USE_POSTGRESQL
    [[ "$USE_POSTGRESQL" =~ ^[Yy]$ ]] && USE_POSTGRESQL=true || USE_POSTGRESQL=false

    read -p "  Redis (caching and session storage) [y/n]: " USE_REDIS
    [[ "$USE_REDIS" =~ ^[Yy]$ ]] && USE_REDIS=true || USE_REDIS=false

    read -p "  RabbitMQ + Spring Cloud Stream (event-driven messaging) [y/n]: " USE_RABBITMQ
    [[ "$USE_RABBITMQ" =~ ^[Yy]$ ]] && USE_RABBITMQ=true || USE_RABBITMQ=false

    read -p "  WebFlux WebClient (reactive HTTP client) [y/n]: " USE_WEBFLUX
    [[ "$USE_WEBFLUX" =~ ^[Yy]$ ]] && USE_WEBFLUX=true || USE_WEBFLUX=false

    read -p "  Scheduling (@Scheduled tasks) [y/n]: " USE_SCHEDULING
    [[ "$USE_SCHEDULING" =~ ^[Yy]$ ]] && USE_SCHEDULING=true || USE_SCHEDULING=false

    read -p "  ShedLock (distributed scheduled task locking) [y/n]: " USE_SHEDLOCK
    [[ "$USE_SHEDLOCK" =~ ^[Yy]$ ]] && USE_SHEDLOCK=true || USE_SHEDLOCK=false

    read -p "  SpringDoc OpenAPI (API documentation) [y/n]: " USE_SPRINGDOC
    [[ "$USE_SPRINGDOC" =~ ^[Yy]$ ]] && USE_SPRINGDOC=true || USE_SPRINGDOC=false

    read -p "  TestContainers (smoke test with real infrastructure) [y/n]: " USE_TESTCONTAINERS
    [[ "$USE_TESTCONTAINERS" =~ ^[Yy]$ ]] && USE_TESTCONTAINERS=true || USE_TESTCONTAINERS=false

    # Spring Security (future)
    # read -p "  Spring Security (authentication and authorization) [y/n]: " USE_SECURITY
    # [[ "$USE_SECURITY" =~ ^[Yy]$ ]] && USE_SECURITY=true || USE_SECURITY=false

    echo ""
    print_section "Selected Add-Ons"
    $USE_SPRING_BOOT_WEB && echo "  ✓ Spring Boot Web"
    $USE_POSTGRESQL && echo "  ✓ PostgreSQL + Flyway"
    $USE_REDIS && echo "  ✓ Redis"
    $USE_RABBITMQ && echo "  ✓ RabbitMQ + Spring Cloud Stream"
    $USE_WEBFLUX && echo "  ✓ WebFlux WebClient"
    $USE_SCHEDULING && echo "  ✓ Scheduling"
    $USE_SHEDLOCK && echo "  ✓ ShedLock"
    $USE_SPRINGDOC && echo "  ✓ SpringDoc OpenAPI"
    $USE_TESTCONTAINERS && echo "  ✓ TestContainers"
    $USE_SECURITY && echo "  ✓ Spring Security"
    echo ""
}

prompt_postgresql_config() {
    # Only prompt for database name if PostgreSQL addon is selected
    if [ "$USE_POSTGRESQL" = false ]; then
        DATABASE_NAME=""
        return
    fi

    print_section "PostgreSQL Configuration"

    echo ""
    print_info "PostgreSQL database configuration:"
    print_info "- Default: '$DOMAIN_NAME' (dedicated database per service)"
    print_info "- Or specify a custom database name"
    read -p "Database name (default: $DOMAIN_NAME): " DATABASE_NAME
    DATABASE_NAME=${DATABASE_NAME:-$DOMAIN_NAME}

    while ! validate_database_name "$DATABASE_NAME"; do
        print_error "Invalid database name. Must be lowercase alphanumeric + underscores"
        read -p "Database name: " DATABASE_NAME
    done

    echo ""
    echo "Database Name:         $DATABASE_NAME"
    echo ""
}

prompt_github_integration() {
    print_section "GitHub Integration"

    if ! command -v gh &> /dev/null; then
        print_warning "gh CLI not found. Skipping GitHub integration."
        CREATE_GITHUB_REPO=false
        return
    fi

    # Check if gh is authenticated
    if ! gh auth status &> /dev/null; then
        print_warning "gh CLI not authenticated. Skipping GitHub integration."
        print_info "Run 'gh auth login' to enable GitHub integration."
        CREATE_GITHUB_REPO=false
        return
    fi

    read -p "Create GitHub repository? (y/n): " CREATE_GITHUB_REPO
    [[ "$CREATE_GITHUB_REPO" =~ ^[Yy]$ ]] && CREATE_GITHUB_REPO=true || CREATE_GITHUB_REPO=false

    echo ""
}

################################################################################
# Template Cloning
################################################################################

clone_template() {
    print_section "Cloning Template Repository"

    # Check if service directory already exists
    if [ -d "$SERVICE_DIR" ]; then
        print_error "Directory $SERVICE_DIR already exists"
        read -p "Delete and continue? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        rm -rf "$SERVICE_DIR"
    fi

    # Clone template
    print_info "Cloning template from $TEMPLATE_REPO..."
    if git clone "$TEMPLATE_REPO" "$SERVICE_DIR" --quiet; then
        print_success "Template cloned successfully"
    else
        print_error "Failed to clone template repository"
        exit 1
    fi

    # Remove .git directory
    rm -rf "$SERVICE_DIR/.git"
    print_success "Removed template .git directory"

    echo ""
}

################################################################################
# Placeholder Replacement
################################################################################

replace_placeholders() {
    print_section "Replacing Placeholders"

    print_info "Replacing placeholders in files..."

    # Find all files (excluding binary files) and replace placeholders
    find "$SERVICE_DIR" -type f \( \
        -name "*.java" -o \
        -name "*.kt" -o \
        -name "*.kts" -o \
        -name "*.xml" -o \
        -name "*.yml" -o \
        -name "*.yaml" -o \
        -name "*.properties" -o \
        -name "*.md" -o \
        -name "*.toml" \
    \) -exec sed -i \
        -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
        -e "s/{DOMAIN_NAME}/$DOMAIN_NAME/g" \
        -e "s/{ServiceClassName}/$SERVICE_CLASS_NAME/g" \
        -e "s/{SERVICE_PORT}/$SERVICE_PORT/g" \
        -e "s/{DATABASE_NAME}/$DATABASE_NAME/g" \
        -e "s/{SERVICE_COMMON_VERSION}/$SERVICE_COMMON_VERSION/g" \
        -e "s/{JAVA_VERSION}/$JAVA_VERSION/g" \
        {} \;

    print_success "Placeholders replaced in files"

    # Rename directories
    print_info "Renaming package directories..."

    mv "$SERVICE_DIR/src/main/java/org/budgetanalyzer/{DOMAIN_NAME}" \
       "$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME"
    print_success "Renamed main package directory"

    mv "$SERVICE_DIR/src/test/java/org/budgetanalyzer/{DOMAIN_NAME}" \
       "$SERVICE_DIR/src/test/java/org/budgetanalyzer/$DOMAIN_NAME"
    print_success "Renamed test package directory"

    # Rename Application class files
    print_info "Renaming Application class files..."

    mv "$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME/{ServiceClassName}Application.java" \
       "$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME/${SERVICE_CLASS_NAME}Application.java"
    print_success "Renamed Application class"

    mv "$SERVICE_DIR/src/test/java/org/budgetanalyzer/$DOMAIN_NAME/{ServiceClassName}ApplicationTests.java" \
       "$SERVICE_DIR/src/test/java/org/budgetanalyzer/$DOMAIN_NAME/${SERVICE_CLASS_NAME}ApplicationTests.java"
    print_success "Renamed ApplicationTests class"

    echo ""
}

################################################################################
# Add-On Application
################################################################################

################################################################################
# Template Application Helper Functions
################################################################################

apply_application_class_patch() {
    local addon_name=$1
    local app_file="$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME/${SERVICE_CLASS_NAME}Application.java"

    if [ ! -f "$app_file" ]; then
        print_error "Application class not found at: $app_file"
        print_error "Cannot apply $addon_name patch. Skipping..."
        return 1
    fi

    print_info "Removing DataSource exclusions from Application class..."

    # Remove the exclude parameter and closing parenthesis
    sed -i 's/@SpringBootApplication(/@SpringBootApplication/' "$app_file"
    sed -i '/exclude = {DataSourceAutoConfiguration.class, HibernateJpaAutoConfiguration.class})/d' "$app_file"

    # Remove the imports
    sed -i '/import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;/d' "$app_file"
    sed -i '/import org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration;/d' "$app_file"
}

apply_addon_toml() {
    local addon_name=$1
    local addon_toml="$TEMPLATE_ADDONS_PATH/$addon_name/libs.versions.toml"

    if [ -f "$addon_toml" ]; then
        print_info "Adding $addon_name dependencies to libs.versions.toml..."

        # Handle special case: Spring Boot Web replaces service-core with service-web
        if [ "$addon_name" = "spring-boot-web" ]; then
            sed -i 's/service-core/service-web/g' "$SERVICE_DIR/gradle/libs.versions.toml"
            sed -i 's/service\.core/service.web/g' "$SERVICE_DIR/build.gradle.kts"
        else
            # Append to the [libraries] section (after the last library entry)
            # This avoids creating duplicate [libraries] headers
            cat "$addon_toml" >> "$SERVICE_DIR/gradle/libs.versions.toml"
        fi
    fi
}

apply_addon_gradle() {
    local addon_name=$1
    local gradle_file="$SERVICE_DIR/build.gradle.kts"

    # Handle special prepend case (RabbitMQ dependencyManagement)
    local gradle_prepend="$TEMPLATE_ADDONS_PATH/$addon_name/build.gradle.kts.dependencyManagement"
    if [ -f "$gradle_prepend" ]; then
        print_info "Adding $addon_name dependency management to build.gradle.kts..."
        # Insert before dependencies block
        sed -i '/^dependencies {$/e cat '"$gradle_prepend" "$gradle_file"
    fi

    # Handle standard append case (dependencies)
    local gradle_deps="$TEMPLATE_ADDONS_PATH/$addon_name/build.gradle.kts.dependencies"
    if [ ! -f "$gradle_deps" ]; then
        gradle_deps="$TEMPLATE_ADDONS_PATH/$addon_name/build.gradle.kts"
    fi

    if [ -f "$gradle_deps" ]; then
        print_info "Adding $addon_name dependencies to build.gradle.kts..."
        # Find the line with testRuntimeOnly(libs.junit.platform.launcher) and append after it
        sed -i '/testRuntimeOnly(libs.junit.platform.launcher)/r '"$gradle_deps" "$gradle_file"
    fi
}

apply_addon_yaml() {
    local addon_name=$1
    local addon_yaml="$TEMPLATE_ADDONS_PATH/$addon_name/application.yml"

    if [ -f "$addon_yaml" ]; then
        print_info "Adding $addon_name configuration to application.yml..."

        # Create temp file with substitutions
        local temp_yaml=$(mktemp)
        sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
            -e "s/{DATABASE_NAME}/$DATABASE_NAME/g" \
            -e "s/{SERVICE_PORT}/$SERVICE_PORT/g" \
            "$addon_yaml" > "$temp_yaml"

        # Append to application.yml
        cat "$temp_yaml" >> "$SERVICE_DIR/src/main/resources/application.yml"
        rm "$temp_yaml"
    fi
}

apply_addon_sql() {
    local addon_name=$1
    local migration_pattern="$TEMPLATE_ADDONS_PATH/$addon_name/V*.sql"

    for sql_file in $migration_pattern; do
        if [ -f "$sql_file" ]; then
            local filename=$(basename "$sql_file")
            print_info "Copying $filename to db/migration..."

            # Create temp file with substitutions
            local temp_sql=$(mktemp)
            sed -e "s/{SERVICE_NAME}/$SERVICE_NAME/g" \
                -e "s/{DATABASE_NAME}/$DATABASE_NAME/g" \
                "$sql_file" > "$temp_sql"

            # Copy to migration directory
            mkdir -p "$SERVICE_DIR/src/main/resources/db/migration"
            cp "$temp_sql" "$SERVICE_DIR/src/main/resources/db/migration/$filename"
            rm "$temp_sql"
        fi
    done
}

apply_addon_java_patch() {
    local addon_name=$1
    local patch_file="$TEMPLATE_ADDONS_PATH/$addon_name/Application.java.patch"

    if [ -f "$patch_file" ]; then
        apply_application_class_patch "$addon_name"
    fi
}

# Master function to apply all addon templates
apply_addon_templates() {
    local addon_name=$1

    apply_addon_toml "$addon_name"
    apply_addon_gradle "$addon_name"
    apply_addon_yaml "$addon_name"
    apply_addon_sql "$addon_name"
    apply_addon_java_patch "$addon_name"
}

################################################################################
# Add-On Functions
################################################################################

apply_spring_boot_web_addon() {
    print_info "Applying Spring Boot Web add-on..."
    apply_addon_templates "spring-boot-web"
}

apply_postgresql_addon() {
    print_info "Applying PostgreSQL + Flyway add-on..."
    apply_addon_templates "postgresql-flyway"

    # Additional setup
    print_info "Database '$DATABASE_NAME' needs to be created manually"
    print_info "Run: createdb $DATABASE_NAME"
}

apply_redis_addon() {
    print_info "Applying Redis add-on..."
    apply_addon_templates "redis"
}

apply_rabbitmq_addon() {
    print_info "Applying RabbitMQ + Spring Cloud Stream add-on..."
    apply_addon_templates "rabbitmq-spring-cloud"

    print_info "Note: Configure your event bindings in application.yml"
}

apply_webflux_addon() {
    print_info "Applying WebFlux (WebClient) add-on..."
    apply_addon_templates "webflux"

    print_info "Note: Create WebClientConfig class manually for HTTP client setup"
}

apply_scheduling_addon() {
    print_info "Applying Scheduling add-on..."

    local app_file="$SERVICE_DIR/src/main/java/org/budgetanalyzer/$DOMAIN_NAME/${SERVICE_CLASS_NAME}Application.java"

    if [ ! -f "$app_file" ]; then
        print_error "Application class not found at: $app_file"
        print_error "Cannot apply Scheduling add-on. Skipping..."
        return 1
    fi

    # Add import
    sed -i '/^package/a\
import org.springframework.scheduling.annotation.EnableScheduling;' "$app_file"

    # Add annotation (before @SpringBootApplication)
    sed -i '/^@SpringBootApplication/i\
@EnableScheduling' "$app_file"

    print_success "✓ Added @EnableScheduling to Application class"
}

apply_shedlock_addon() {
    if [ "$USE_POSTGRESQL" != true ]; then
        print_error "ShedLock add-on requires PostgreSQL add-on"
        exit 1
    fi

    print_info "Applying ShedLock add-on..."
    apply_addon_templates "shedlock"

    print_info "Note: Create SchedulingConfig class manually with @EnableSchedulerLock"
}

apply_springdoc_addon() {
    print_info "Applying SpringDoc OpenAPI add-on..."
    apply_addon_templates "springdoc"

    print_info "Swagger UI will be available at: http://localhost:$SERVICE_PORT/$SERVICE_NAME/swagger-ui.html"
}

apply_testcontainers_addon() {
    print_info "Applying TestContainers add-on..."

    # Track which containers are needed
    local -a imports=()
    local -a declarations=()
    local -a properties=()
    local -a containers_used=()

    # Check which infrastructure add-ons are selected
    if [ "$USE_POSTGRESQL" = true ]; then
        containers_used+=("postgresql")
        imports+=("import org.testcontainers.containers.PostgreSQLContainer;")
        declarations+=("    @Container")
        declarations+=("    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>(\"postgres:16-alpine\")")
        declarations+=("        .withDatabaseName(\"$DATABASE_NAME\")")
        declarations+=("        .withUsername(\"postgres\")")
        declarations+=("        .withPassword(\"postgres\");")
        properties+=("        registry.add(\"spring.datasource.url\", postgres::getJdbcUrl);")
        properties+=("        registry.add(\"spring.datasource.username\", postgres::getUsername);")
        properties+=("        registry.add(\"spring.datasource.password\", postgres::getPassword);")
    fi

    if [ "$USE_REDIS" = true ]; then
        containers_used+=("redis")
        imports+=("import org.testcontainers.containers.GenericContainer;")
        declarations+=("    @Container")
        declarations+=("    static GenericContainer<?> redis = new GenericContainer<>(\"redis:7-alpine\")")
        declarations+=("        .withExposedPorts(6379);")
        properties+=("        registry.add(\"spring.data.redis.host\", redis::getHost);")
        properties+=("        registry.add(\"spring.data.redis.port\", () -> redis.getMappedPort(6379).toString());")
    fi

    if [ "$USE_RABBITMQ" = true ]; then
        containers_used+=("rabbitmq")
        imports+=("import org.testcontainers.containers.RabbitMQContainer;")
        declarations+=("    @Container")
        declarations+=("    static RabbitMQContainer rabbitmq = new RabbitMQContainer(\"rabbitmq:3-management-alpine\");")
        properties+=("        registry.add(\"spring.rabbitmq.host\", rabbitmq::getHost);")
        properties+=("        registry.add(\"spring.rabbitmq.port\", () -> rabbitmq.getMappedPort(5672).toString());")
        properties+=("        registry.add(\"spring.rabbitmq.username\", rabbitmq::getAdminUsername);")
        properties+=("        registry.add(\"spring.rabbitmq.password\", rabbitmq::getAdminPassword);")
    fi

    # If no infrastructure containers are selected, create a basic smoke test
    if [ ${#containers_used[@]} -eq 0 ]; then
        print_warning "No infrastructure add-ons selected. Creating basic smoke test without containers."
    fi

    # Add TestContainers dependencies to libs.versions.toml
    cat >> "$SERVICE_DIR/gradle/libs.versions.toml" <<EOF

# TestContainers
testcontainers-bom = { module = "org.testcontainers:testcontainers-bom", version = "1.19.3" }
testcontainers-junit-jupiter = { module = "org.testcontainers:junit-jupiter" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql" }
testcontainers-rabbitmq = { module = "org.testcontainers:rabbitmq" }
EOF

    # Add base dependencies to build.gradle.kts (insert before closing brace of dependencies block)
    local deps_content="
    // TestContainers
    testImplementation(platform(libs.testcontainers.bom))
    testImplementation(libs.testcontainers.junit.jupiter)"

    # Add specific container dependencies
    if [ "$USE_POSTGRESQL" = true ]; then
        deps_content="$deps_content
    testImplementation(libs.testcontainers.postgresql)"
    fi
    if [ "$USE_RABBITMQ" = true ]; then
        deps_content="$deps_content
    testImplementation(libs.testcontainers.rabbitmq)"
    fi

    # Create temp file with the content
    local temp_file=$(mktemp)
    echo "$deps_content" > "$temp_file"

    # Insert after the testRuntimeOnly line in dependencies block
    sed -i "/testRuntimeOnly(libs.junit.platform.launcher)/r $temp_file" "$SERVICE_DIR/build.gradle.kts"
    rm "$temp_file"

    # Generate ApplicationSmokeTest.java
    local test_file="$SERVICE_DIR/src/test/java/org/budgetanalyzer/$DOMAIN_NAME/ApplicationSmokeTest.java"

    # Build imports section
    local imports_section=""
    for import in "${imports[@]}"; do
        imports_section+="$import"$'\n'
    done

    # Build declarations section
    local declarations_section=""
    for decl in "${declarations[@]}"; do
        declarations_section+="$decl"$'\n'
    done

    # Build properties section
    local properties_section=""
    for prop in "${properties[@]}"; do
        properties_section+="$prop"$'\n'
    done

    # Create the test file
    cat > "$test_file" <<EOF
package org.budgetanalyzer.$DOMAIN_NAME;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.DynamicPropertyRegistry;
${imports_section}
@SpringBootTest
@Testcontainers
class ApplicationSmokeTest {

${declarations_section}
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
${properties_section}    }

    @Test
    void contextLoads() {
        // Test passes if Spring context loads successfully with all containers
    }
}
EOF

    print_success "✓ Generated ApplicationSmokeTest with containers: ${containers_used[*]:-none}"
    print_success "✓ Added TestContainers dependencies"
}

apply_security_addon() {
    print_info "Applying Spring Security add-on..."
    apply_addon_templates "spring-security"

    print_info "Note: Create SecurityConfig class manually to configure authentication"
}

apply_addons() {
    print_section "Applying Add-Ons"

    $USE_SPRING_BOOT_WEB && apply_spring_boot_web_addon
    $USE_POSTGRESQL && apply_postgresql_addon
    $USE_REDIS && apply_redis_addon
    $USE_RABBITMQ && apply_rabbitmq_addon
    $USE_WEBFLUX && apply_webflux_addon
    $USE_SCHEDULING && apply_scheduling_addon
    $USE_SHEDLOCK && apply_shedlock_addon
    $USE_SPRINGDOC && apply_springdoc_addon
    $USE_TESTCONTAINERS && apply_testcontainers_addon
    $USE_SECURITY && apply_security_addon

    echo ""
}

################################################################################
# Git Initialization
################################################################################

initialize_git() {
    print_section "Initializing Git Repository"

    cd "$SERVICE_DIR"

    git init --quiet
    print_success "Git repository initialized"

    git add .
    print_success "Files staged"

    git commit -m "Initial commit from template

Generated by create-service.sh

Service: $SERVICE_NAME
Domain: $DOMAIN_NAME
Port: $SERVICE_PORT
Database: $DATABASE_NAME

🤖 Generated with Budget Analyzer Service Template" --quiet

    print_success "Initial commit created"

    cd - > /dev/null
    echo ""
}

################################################################################
# GitHub Integration
################################################################################

create_github_repository() {
    if [ "$CREATE_GITHUB_REPO" = false ]; then
        return
    fi

    print_section "Creating GitHub Repository"

    cd "$SERVICE_DIR"

    print_info "Creating GitHub repository: budgetanalyzer/$SERVICE_NAME..."

    if gh repo create "budgetanalyzer/$SERVICE_NAME" \
        --private \
        --source=. \
        --remote=origin \
        --push; then
        print_success "GitHub repository created and pushed"
        GITHUB_REPO_CREATED=true
    else
        print_error "Failed to create GitHub repository"
        print_warning "You can create it manually later with: gh repo create budgetanalyzer/$SERVICE_NAME --private --source=. --remote=origin --push"
    fi

    cd - > /dev/null
    echo ""
}

################################################################################
# Build Validation
################################################################################

validate_build() {
    print_section "Validating Build"

    cd "$SERVICE_DIR"

    print_info "Running ./gradlew clean build..."
    echo ""

    if ./gradlew clean build; then
        echo ""
        print_success "Build successful! ✨"
    else
        echo ""
        print_error "Build failed!"
        print_warning "Please check the build output above for errors."
        exit 1
    fi

    cd - > /dev/null
    echo ""
}

################################################################################
# Summary and Next Steps
################################################################################

print_summary() {
    print_section "✨ Service Created Successfully!"

    echo "Service Details:"
    echo "  Name:       $SERVICE_NAME"
    echo "  Domain:     $DOMAIN_NAME"
    echo "  Port:       $SERVICE_PORT"
    echo "  Location:   $SERVICE_DIR"
    echo ""

    if [ "$GITHUB_REPO_CREATED" = true ]; then
        echo "GitHub Repository:"
        echo "  URL: https://github.com/budgetanalyzer/$SERVICE_NAME"
        echo ""
    fi

    echo "Next Steps:"
    echo ""
    echo "1. Review the generated service:"
    echo "   cd $SERVICE_DIR"
    echo ""
    echo "2. Run the service locally:"
    echo "   ./gradlew bootRun"
    echo ""
    echo "3. Add to orchestration docker-compose.yml:"
    echo "   - Add service definition"
    echo "   - Configure environment variables"
    echo "   - Set up database (if using PostgreSQL)"
    echo ""
    echo "4. Configure NGINX routing (if needed):"
    echo "   - Edit nginx/nginx.dev.conf"
    echo "   - Add location blocks for API endpoints"
    echo "   - Restart NGINX container"
    echo ""
    echo "5. Update orchestration documentation:"
    echo "   - Add service to CLAUDE.md"
    echo "   - Document API endpoints"
    echo "   - Update architecture diagrams"
    echo ""
    echo "For add-on configuration details, see:"
    echo "  $WORKSPACE_DIR/docs/service-creation/addons/"
    echo ""

    print_section "Happy coding! 🚀"
}

################################################################################
# Error Handling and Cleanup
################################################################################

cleanup_on_error() {
    print_error "Script failed. Cleaning up..."

    if [ -d "$SERVICE_DIR" ] && [ ! -d "$SERVICE_DIR/.git" ]; then
        print_warning "Removing incomplete service directory: $SERVICE_DIR"
        rm -rf "$SERVICE_DIR"
    fi

    exit 1
}

trap cleanup_on_error ERR

################################################################################
# Main Script Flow
################################################################################

main() {
    print_header

    check_prerequisites
    prompt_service_details
    prompt_addons
    prompt_postgresql_config
    prompt_github_integration

    clone_template
    replace_placeholders
    apply_addons
    initialize_git
    create_github_repository
    validate_build

    print_summary
}

# Run main function
main "$@"
