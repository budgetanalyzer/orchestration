# CLAUDE.md Reorganization Plan
## Budget Analyzer Microservices Documentation Strategy

**Date:** 2025-11-10
**Status:** Approved - Ready for Implementation
**Context:** Addressing documentation drift and establishing sustainable patterns for AI context files

---

## Executive Summary

This plan transforms the Budget Analyzer documentation from specificity-based (listing services, classes, ports) to **pattern-based** (teaching discovery, referencing source files). This approach:

- ✅ Survives refactoring without updates
- ✅ Eliminates drift between docs and code
- ✅ Teaches AI assistants to discover current state
- ✅ Reduces maintenance burden
- ✅ Scales as microservices grow

---

## Problem Statement

### Current Issues
1. **Service inventory drift** - Hard-coded service lists become outdated
2. **Port/config brittleness** - Specific values duplicate docker compose.yml
3. **Route documentation lag** - NGINX routes documented incompletely
4. **Version vagueness** - "Spring Boot 3.x" will become stale
5. **Class name references** - Extremely prone to refactoring drift
6. **Inconsistent docs** - Overlap between orchestration, service-common, and service repos
7. **Missing implementations** - Scripts directories documented but don't exist
8. **Infrastructure gaps** - Redis/RabbitMQ deployed but not documented as core services

### Research Findings (2025 Best Practices)

From web research and codebase analysis:

1. **Hierarchical CLAUDE.md files** - Claude loads from root → subdirectory automatically
2. **Patterns over examples** - Document "how to find" not "what exists"
3. **Reference source files** - Use `@path/to/file` syntax, don't duplicate content
4. **Discovery commands** - Provide grep/tree commands to reveal current state
5. **Hub-and-spoke docs** - Central architecture docs, service-specific details in service repos
6. **Keep CLAUDE.md concise** - 50-200 lines max, delegate details to docs/
7. **Living documentation** - Acknowledge evolution, teach validation

---

## Documentation Philosophy

### Core Principle: Pattern-Based Documentation

**❌ Anti-Pattern: Specificity-Based**
```markdown
### Core Services
1. **transaction-service** - Handles budgets (port 8082)
2. **currency-service** - Converts currencies (port 8084)

### API Routes
- POST /api/transactions - Create transaction (TransactionController)
- GET /api/currencies - List currencies (CurrencyController)
```

**Problems:**
- Service list grows, docs lag behind
- Port changes break documentation
- Class names drift during refactoring
- Routes incomplete (missing admin endpoints, versioning)
- Creates maintenance burden

**✅ Pattern: Discovery-Based**
```markdown
### Core Services
Services defined in `docker compose.yml`. Discover with:
```bash
docker compose config --services
```

**Patterns:**
- **Frontend**: React apps (dev port 3000)
- **Backend**: Spring Boot microservices (ports 8082+)
- **Gateway**: NGINX (port 8080) - see @nginx/nginx.dev.conf

### API Routes
Gateway routes by **resource** (not service name) - see @nginx/nginx.dev.conf

**Pattern**: Frontend calls `/api/v1/{resource}`, gateway routes to service.
Moving resources between services requires only NGINX config change.

**Discovery:**
```bash
cat nginx/nginx.dev.conf | grep "location /api"
```

**Benefits:**
- ✅ Self-documenting - always accurate
- ✅ Survives refactoring
- ✅ Teaches AI to check source
- ✅ Minimal maintenance

### When to Be Specific

| Documentation Type | Specificity Level | Location | Rationale |
|-------------------|------------------|----------|-----------|
| Architecture patterns | ABSTRACT | orchestration/CLAUDE.md | Cross-service, rarely changes |
| Service discovery | DISCOVERY COMMANDS | orchestration/CLAUDE.md | Always accurate |
| Spring Boot patterns | PATTERN-BASED | service-common/CLAUDE.md | Naming conventions, not classes |
| API contracts | FULLY SPECIFIC | service/docs/api/openapi.yaml | Machine-readable, versioned |
| Business domain | SEMI-SPECIFIC | service/docs/domain.md | Service-specific, detailed |
| Deployment config | FILE REFERENCES | orchestration/CLAUDE.md | Point to docker compose.yml |

**Rule of Thumb:**
- If it changes during refactoring → Use patterns
- If it's in a config file → Reference the file
- If it's an API contract → Specify in OpenAPI
- If it's a principle → Document in CLAUDE.md
- If it's detailed → Put in docs/ and reference it

---

## CLAUDE.md Hierarchy Strategy

### Hierarchical Loading (How Claude Works)

Claude automatically loads CLAUDE.md files hierarchically:
```
/orchestration/CLAUDE.md           # Loaded first
  └── /service-common/CLAUDE.md    # Loaded when working in service-common
  └── /transaction-service/CLAUDE.md # Loaded when working in transaction-service
```

This enables **context layering**: general → specific.

### Recommended Hierarchy

```
budget-analyzer/
├── orchestration/
│   ├── CLAUDE.md                    # 🎯 THIN: Architecture patterns, discovery
│   ├── README.md                    # Human-readable overview
│   └── docs/
│       ├── architecture/            # 🎯 System-wide design
│       │   ├── system-overview.md
│       │   ├── resource-routing-pattern.md
│       │   └── security-architecture.md
│       ├── development/             # 🎯 Cross-service dev setup
│       │   ├── local-environment.md
│       │   └── debugging-guide.md
│       └── decisions/               # 🎯 ADRs (Architecture Decision Records)
│           ├── 001-orchestration-repo.md
│           └── 002-resource-based-routing.md
│
├── service-common/
│   ├── CLAUDE.md                    # 🎯 Spring Boot patterns (no specifics)
│   ├── README.md                    # How to use this library
│   └── docs/
│       ├── spring-boot-conventions.md  # 🎯 THE canonical Spring patterns
│       ├── testing-patterns.md
│       ├── error-handling.md
│       └── common-dependencies.md   # Version management strategy
│
├── transaction-service/
│   ├── CLAUDE.md                    # 🎯 THIN: References service-common + unique aspects
│   ├── README.md                    # Service overview
│   └── docs/
│       ├── api/
│       │   └── openapi.yaml        # 🎯 Specific API contracts
│       ├── domain-model.md         # Business concepts
│       └── database-schema.md      # Service-specific DB
│
└── currency-service/
    ├── CLAUDE.md                    # 🎯 THIN: References service-common + unique aspects
    ├── README.md
    └── docs/
        ├── api/
        │   └── openapi.yaml
        ├── exchange-rate-providers.md
        └── caching-strategy.md
```

### Content Distribution Rules

| Content Type | Location | Example |
|--------------|----------|---------|
| System architecture | `orchestration/docs/architecture/` | Microservices diagram, gateway pattern |
| Development environment | `orchestration/docs/development/` | Docker setup, database seeding |
| Deployment patterns | `orchestration/docs/deployment/` | K8s manifests, docker compose |
| Spring Boot conventions | `service-common/docs/` | **THE** source of truth for all Spring services |
| Service API contracts | `service/docs/api/` | OpenAPI specs, endpoint docs |
| Service business logic | `service/docs/` | Domain models, business rules |
| Cross-cutting concerns | `orchestration/docs/architecture/` OR `service-common/docs/` | Security, observability |

**DRY Principle:**
- ✅ Write Spring Boot patterns ONCE in service-common
- ✅ Individual services REFERENCE service-common, never duplicate
- ✅ Orchestration documents system-wide concerns
- ✅ Services document their unique business logic

---

## Phase 1: De-Specify orchestration/CLAUDE.md

### Current Problems

From drift analysis:
1. Lists specific services (will grow)
2. Documents script directories that don't exist
3. Duplicates NGINX routes (incomplete)
4. Uses `latest` Docker tags (unpinned)
5. Omits Redis/RabbitMQ as core services
6. Mixes service/container names inconsistently

### Transformation Strategy

#### Before: Specificity-Based (Current)
```markdown
### Core Services

1. **budget-analyzer-web** - React 19 web application
   - Modern frontend for budget tracking and financial analysis
   - Development server runs on port 3000
   - Production build served as static assets

2. **transaction-service** - Spring Boot microservice
   - Core business logic for budget and transaction management
   - Runs on port 8082
   - RESTful API endpoints under `/transaction-service/*`

3. **currency-service** - Spring Boot microservice
   - Currency conversion and exchange rate management
   - Runs on port 8084
   - RESTful API endpoints under `/currency-service/*`
```

**Problems:**
- Adding a fourth service means updating CLAUDE.md
- Port numbers duplicate docker compose.yml
- Descriptions will drift from actual functionality

#### After: Pattern-Based (Target)
```markdown
### Service Architecture

**Pattern**: Microservices defined in `docker compose.yml`

**Discovery:**
```bash
# List all services
docker compose config --services

# View service details
docker compose config

# See ports and routing
cat docker compose.yml | grep -A 5 "ports:"
cat nginx/nginx.dev.conf | grep "location /api"
```

**Service Types:**
- **Frontend services**: React-based web applications (typically port 3000 in dev)
- **Backend microservices**: Spring Boot REST APIs (ports 8082+, see docker compose.yml)
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (see docker compose.yml)
- **Gateway**: NGINX reverse proxy (port 8080) routes all frontend requests

**Adding New Services:**
1. Add service to `docker compose.yml`
2. Add routes to `nginx/nginx.dev.conf` if frontend-facing
3. Follow naming: `{domain}-service` for backends, `{domain}-web` for frontends
4. See @docs/architecture/service-onboarding.md

**See also:**
- @nginx/README.md - Gateway routing patterns
- @docs/architecture/system-overview.md - Architecture diagrams
```

**Benefits:**
- ✅ Adding services requires no CLAUDE.md update
- ✅ Always accurate (references source files)
- ✅ Teaches discovery patterns
- ✅ Documents the "why" (naming conventions)

---

### Before/After: API Routes

#### Before: Specific Routes (Incomplete)
```markdown
### Frontend Access Pattern

The frontend should call the NGINX gateway at `http://localhost:8080/api/*`:
- `/api/transactions` → routed to transaction-service
- `/api/currencies` → routed to currency-service
- `/api/exchange-rates` → routed to currency-service
```

**Problems:**
- Missing API versioning (`/v1/`)
- Missing admin routes
- Missing OpenAPI documentation routes
- Will drift when routes added

#### After: Pattern + Discovery
```markdown
### API Gateway Pattern

**Frontend calls**: All requests go through NGINX gateway (`http://localhost:8080/api/*`)

**Routing Strategy**: Resource-based (not service-based)
- Frontend is decoupled from service topology
- Moving a resource to different service = NGINX config change only
- No DNS resolver needed
- Clean RESTful paths

**Current Routes**: See @nginx/nginx.dev.conf (source of truth)

**Discovery:**
```bash
# List all API routes
cat nginx/nginx.dev.conf | grep "location /api" | grep -v "#"

# Test a specific route
curl -v http://localhost:8080/api/v1/transactions
```

**Adding Routes:**
1. Add location block in `nginx/nginx.dev.conf`:
   ```nginx
   location /api/v1/your-resource {
       proxy_pass http://host.docker.internal:8082/your-resource;
   }
   ```
2. Restart gateway: `docker compose restart nginx-gateway`
3. Test: `curl http://localhost:8080/api/v1/your-resource`

**Pattern Benefits:**
- Frontend never knows which service handles a resource
- Services can be split/merged without frontend changes
- API versioning handled at gateway level

**See also:**
- @nginx/README.md - Routing configuration guide
- @docs/architecture/resource-routing-pattern.md
```

**Benefits:**
- ✅ Documents the pattern, not the inventory
- ✅ Provides discovery commands
- ✅ Explains the architectural principle
- ✅ Shows how to extend

---

### Before/After: Technology Stack

#### Before: Version Inventory
```markdown
### Technology Stack

#### Frontend
- React 19
- Modern JavaScript/TypeScript
- Webpack/Vite for bundling

#### Backend
- Spring Boot 3.x
- Java 17+
- RESTful APIs

#### Infrastructure
- Docker for containerization
- NGINX for API gateway
- PostgreSQL/MySQL for databases (if applicable)
```

**Problems:**
- Versions drift (React 19 → 20, Spring Boot 3.x → 4.0)
- "PostgreSQL/MySQL (if applicable)" is vague (it's PostgreSQL, definitively)
- Doesn't mention Redis, RabbitMQ (actually deployed)

#### After: Discovery + Principles
```markdown
### Technology Stack

**Principle**: Each service manages its own dependencies.
Versions are defined in service-specific files.

**Discovery:**
```bash
# Frontend framework
cat budget-analyzer-web/package.json | grep '"react"'

# Spring Boot version (canonical)
cat service-common/pom.xml | grep '<spring-boot.version>'

# Docker images (all infrastructure)
cat docker compose.yml | grep 'image:' | sort -u
```

**Stack Patterns:**
- **Frontend**: React (see individual service package.json)
- **Backend**: Spring Boot + Java (version in service-common/pom.xml)
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (see docker compose.yml)
- **Gateway**: NGINX (Alpine-based)

**Version Management:**
- Spring Boot: Defined in `service-common/pom.xml` (single source of truth)
- Individual services: Inherit from service-common, never override
- Docker images: **Should be pinned** (TODO: pin versions in docker compose.yml)

**See also:**
- [@service-common/docs/common-dependencies.md](https://github.com/budget-analyzer/service-common/blob/main/docs/common-dependencies.md) - Spring Boot dependency strategy
- @docs/development/local-environment.md - Setup requirements
```

**Benefits:**
- ✅ Always shows current versions
- ✅ Documents version management strategy
- ✅ Highlights TODOs (unpinned Docker images)
- ✅ No maintenance needed

---

### Before/After: Script Organization

#### Before: Fictional Structure
```markdown
### Build and Release Scripts

#### Build Scripts (`scripts/build/`)
- Build individual services
- Create Docker images
- Run tests and quality checks

#### Release Scripts (`scripts/release/`)
- Version management
- Tag creation
- Deployment automation

#### Development Scripts (`scripts/dev/`)
- Environment setup
- Database migrations
- Test data seeding
```

**Problems:**
- `scripts/build/` doesn't exist
- `scripts/release/` doesn't exist (scripts are at root)
- Describes capabilities, not actual tools

#### After: Discovery + Actual Structure
```markdown
### Scripts and Automation

**Current structure**: See actual layout with `tree scripts/ -L 2`

**Discovery:**
```bash
# List available scripts
find scripts/ -name "*.sh" -type f | sort

# View script documentation
cat scripts/README.md
```

**Common tasks:**
```bash
# Reset development databases
scripts/dev/reset-databases.sh

# Tag a release
scripts/tag-release.sh v1.2.3

# Validate repository structure
scripts/validate-repos.sh

# Generate unified API docs
scripts/generate-unified-api-docs.sh
```

**Adding Scripts:**
1. Create script in appropriate category directory
2. Make executable: `chmod +x scripts/path/to/script.sh`
3. Document in `scripts/README.md`
4. Test before committing

**Note**: Script organization is evolving. Always check actual structure with `tree` or `ls`.

**See also:**
- @scripts/README.md - Complete script documentation
```

**Benefits:**
- ✅ Doesn't claim non-existent directories exist
- ✅ Provides discovery commands
- ✅ Shows actual usage
- ✅ Acknowledges evolution

---

### De-Specification Checklist

Transform orchestration/CLAUDE.md:

- [ ] Replace service inventory with discovery pattern
- [ ] Replace port numbers with docker compose.yml reference
- [ ] Replace route list with nginx config reference + pattern explanation
- [ ] Replace technology versions with discovery commands
- [ ] Replace script directory claims with actual structure discovery
- [ ] Add Redis/RabbitMQ to infrastructure (not optional)
- [ ] Document container vs service name distinction
- [ ] Add "Living Documentation" philosophy section
- [ ] Remove class name references (none currently, keep it that way)
- [ ] Add discovery commands throughout
- [ ] Reference detailed docs with @path syntax

**Target length**: 100-150 lines (currently ~250 lines)

---

## Phase 2: Create service-common/CLAUDE.md

### Purpose

Single source of truth for **Spring Boot patterns** shared across all microservices.

### Content Strategy

**DO document:**
- ✅ Architectural layers (Controller → Service → Repository)
- ✅ Naming conventions (`*Controller`, `*Service`, `*ServiceImpl`)
- ✅ Package structure patterns
- ✅ Testing patterns (JUnit 5, TestContainers)
- ✅ Error handling patterns
- ✅ Logging conventions
- ✅ Dependency management strategy

**DON'T document:**
- ❌ Specific class names (`TransactionController`)
- ❌ Specific endpoints (`POST /transactions`)
- ❌ Business logic (belongs in service repos)
- ❌ Service-specific configurations

### Template: service-common/CLAUDE.md

```markdown
# Service-Common - Spring Boot Shared Patterns

## Purpose
Shared library for all Budget Analyzer Spring Boot microservices.

**Impacts**: transaction-service, currency-service, and all future Spring Boot services.
Changes here affect all services that depend on this library.

## When to Use This Library
- ✅ Cross-service utilities (logging, error handling, common DTOs)
- ✅ Shared Spring Boot configurations
- ✅ Common dependencies and version management
- ❌ Service-specific business logic (belongs in service repos)

## Spring Boot Conventions

### Architecture Layers

**Pattern**: Clean layered architecture

```
Controller Layer (HTTP concerns)
    ↓
Service Layer (business logic)
    ↓
Repository Layer (data access)
```

**Rules**:
- Controllers never call repositories directly
- Services contain all business logic
- Repositories are thin data access only

### Naming Conventions

**Discovery**:
```bash
# Find all controllers in a service
grep -r "@RestController" transaction-service/src/

# Find all services
grep -r "@Service" transaction-service/src/

# Find all repositories
grep -r "@Repository" transaction-service/src/
```

**Patterns**:
- Controllers: `*Controller` in `*.controller` package
- Services: `*Service` interface + `*ServiceImpl` implementation
- Repositories: `*Repository` in `*.repository` package
- DTOs: `*DTO` or `*Request`/`*Response` in `*.dto` package

**Example** (pattern only, not specific classes):
```
com.budgetanalyzer.{service}.controller.SomeResourceController
com.budgetanalyzer.{service}.service.SomeResourceService
com.budgetanalyzer.{service}.service.impl.SomeResourceServiceImpl
com.budgetanalyzer.{service}.repository.SomeResourceRepository
```

### Dependency Management

**Principle**: service-common defines canonical versions.

**Source of truth**: `service-common/pom.xml`
```bash
# View Spring Boot version
cat service-common/pom.xml | grep '<spring-boot.version>'

# View all managed dependencies
cat service-common/pom.xml | grep -A 1 '<dependencyManagement>'
```

**Service POM Rules**:
- ✅ Inherit from service-common parent
- ✅ Declare dependencies without versions (inherited)
- ❌ NEVER override versions in service POMs
- ❌ NEVER duplicate dependency management

### Testing Patterns

**Pattern**: JUnit 5 + TestContainers for integration tests

**Discovery**:
```bash
# Find test patterns in any service
find transaction-service/ -name "*Test.java" | head -5
```

**Conventions**:
- Unit tests: `*Test.java` (no Spring context)
- Integration tests: `*IntegrationTest.java` (with @SpringBootTest)
- TestContainers: Used for database/Redis/RabbitMQ in integration tests

**See**: @docs/testing-patterns.md for detailed examples

### Error Handling

**Pattern**: Centralized exception handling with `@ControllerAdvice`

**Convention**:
- Custom exceptions extend `BudgetAnalyzerException`
- Global exception handler in each service
- Standard error response format (see @docs/error-handling.md)

**Discovery**:
```bash
# Find exception handlers
grep -r "@ControllerAdvice" */src/
```

### Logging

**Pattern**: SLF4J with structured logging

**Convention**:
```java
// Pattern (not real code)
private static final Logger log = LoggerFactory.getLogger(ClassName.class);

log.info("Action performed: resource={}, user={}", resourceId, userId);
```

**See**: @docs/logging-conventions.md

## Adding to service-common

**When to add code here**:
- Used by 2+ services
- Cross-cutting concern (logging, error handling, security)
- Common DTOs or utilities

**When NOT to add**:
- Service-specific business logic
- One-off utilities
- Domain models (unless truly shared)

**Process**:
1. Verify need (is this really shared?)
2. Add to service-common with tests
3. Version bump (semantic versioning)
4. Update consuming services
5. Document in `service-common/CHANGELOG.md`

## Documentation References

Detailed patterns documented in `docs/`:
- @docs/spring-boot-conventions.md - Complete architecture guide
- @docs/testing-patterns.md - Testing strategies and examples
- @docs/error-handling.md - Exception handling patterns
- @docs/logging-conventions.md - Logging best practices
- @docs/common-dependencies.md - Dependency management details

## AI Assistant Guidelines

When working on Spring Boot services:
1. **Check service-common first** - Don't reinvent patterns
2. **Follow naming conventions** - Discover with grep, don't guess
3. **Never duplicate dependency versions** - Inherit from service-common
4. **Reference detailed docs** - Don't assume patterns, read @docs/
5. **Test patterns matter** - Follow established testing conventions

When you see drift between service implementations and these patterns,
consider: Is the service wrong, or is the pattern evolving?
If pattern evolving → Update service-common + all services consistently
If service wrong → Align service to service-common patterns
```

### service-common/docs/ Structure

Create detailed pattern documentation:

```
service-common/
└── docs/
    ├── spring-boot-conventions.md   # Detailed architecture guide
    ├── testing-patterns.md          # Test examples with code
    ├── error-handling.md            # Exception handling with examples
    ├── logging-conventions.md       # Logging patterns
    ├── common-dependencies.md       # Dependency version strategy
    └── upgrade-guide.md             # How to upgrade Spring Boot version
```

**Key principle**: service-common/docs/ is THE source of truth for Spring patterns.
Individual service CLAUDE.md files reference this, never duplicate.

---

## Phase 3: Transform Service CLAUDE.md Files

### Current Problem

transaction-service, currency-service, and future services likely have:
- Duplicated Spring Boot patterns (should reference service-common)
- Specific class names (will drift)
- Duplicated testing patterns
- Inconsistent conventions

### Service CLAUDE.md Template

```markdown
# {Service Name} - [Brief Domain Description]

## Service Purpose
[2-3 sentences describing business domain this service handles]

**Domain**: [e.g., "Transaction management and budget tracking"]
**Responsibilities**:
- [Key responsibility 1]
- [Key responsibility 2]
- [Key responsibility 3]

## Spring Boot Patterns

**This service follows standard Budget Analyzer Spring Boot conventions.**

See [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md) for:
- Architecture layers (Controller → Service → Repository)
- Naming conventions
- Testing patterns
- Error handling
- Logging conventions
- Dependency management

## Service-Specific Patterns

[Only document patterns UNIQUE to this service]

### API Contracts
Full API specification: @docs/api/openapi.yaml

**Discovery**:
```bash
# Start service and view Swagger UI
./mvnw spring-boot:run
open http://localhost:8082/swagger-ui.html

# View OpenAPI spec
cat docs/api/openapi.yaml
```

### Domain Model
See @docs/domain-model.md for:
- Business entities
- Aggregate boundaries
- Domain rules

### Database Schema
See @docs/database-schema.md for:
- Table structures
- Relationships
- Migration strategy

### [Service-Specific Concerns]
[Only document what's UNIQUE to this service]
[Examples: caching strategy, external API integrations, batch processing]

## Running Locally

**Quick start**:
```bash
# From orchestration repo
docker compose up shared-postgres
./mvnw spring-boot:run

# Run tests
./mvnw test
```

**See**: [@orchestration/docs/development/local-environment.md](https://github.com/budget-analyzer/orchestration/blob/main/docs/development/local-environment.md) for full setup

## Discovery Commands

```bash
# Find all endpoints
grep -r "@GetMapping\|@PostMapping\|@PutMapping\|@DeleteMapping" src/

# View application configuration
cat src/main/resources/application.yml

# Check dependencies
./mvnw dependency:tree
```

## AI Assistant Guidelines

1. **Follow service-common patterns** - Reference [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md)
2. **Check OpenAPI spec first** - See @docs/api/openapi.yaml for endpoints
3. **Understand domain model** - Read @docs/domain-model.md before changes
4. **Test everything** - Follow patterns in [@service-common/docs/testing-patterns.md](https://github.com/budget-analyzer/service-common/blob/main/docs/testing-patterns.md)
5. **Service-specific only** - Don't modify cross-service patterns here

[Add service-specific guidelines if needed]
```

### Example: transaction-service/CLAUDE.md

```markdown
# Transaction Service - Budget and Transaction Management

## Service Purpose
Manages financial transactions, budget creation, and spending analysis.

**Domain**: Transaction and budget management
**Responsibilities**:
- CRUD operations for transactions
- Budget creation and management
- Transaction categorization
- Spending analysis and reporting

## Spring Boot Patterns

**This service follows standard Budget Analyzer Spring Boot conventions.**

See [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md) for:
- Architecture layers (Controller → Service → Repository)
- Naming conventions
- Testing patterns
- Error handling
- Logging conventions
- Dependency management

## Service-Specific Patterns

### API Contracts
Full API specification: @docs/api/openapi.yaml

**Key endpoints** (see OpenAPI spec for details):
- Transaction CRUD: `/api/v1/transactions/**`
- Budget management: `/api/v1/budgets/**`
- Admin operations: `/api/v1/admin/transactions/**`

**Discovery**:
```bash
# View all endpoints
grep -r "@GetMapping\|@PostMapping" src/main/java/*/controller/

# Start service with Swagger UI
./mvnw spring-boot:run
open http://localhost:8082/swagger-ui.html
```

### Domain Model
See @docs/domain-model.md for detailed entity relationships.

**Key aggregates**:
- Transaction (root entity with line items)
- Budget (with category allocations)
- Category (hierarchical structure)

### Database Schema
See @docs/database-schema.md

**Key tables**:
- `transactions` (financial transactions)
- `budgets` (budget definitions)
- `categories` (spending categories)

**Migrations**: Flyway (see `src/main/resources/db/migration/`)

### Transaction Import Feature
**Unique to this service**: Bulk CSV/OFX import handling

See @docs/import-processing.md for:
- Supported file formats
- Parsing strategies
- Deduplication logic

## Running Locally

```bash
# Start dependencies
cd orchestration/
docker compose up shared-postgres

# Run service
cd transaction-service/
./mvnw spring-boot:run

# Access service
curl http://localhost:8082/api/v1/transactions
```

## Discovery Commands

```bash
# Find all controllers
grep -r "@RestController" src/

# Find transaction-specific logic
grep -r "Transaction" src/main/java/*/service/

# View configuration
cat src/main/resources/application.yml
```

## AI Assistant Guidelines

1. **Follow service-common patterns** - See [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md)
2. **Transaction domain complexity** - Read @docs/domain-model.md before changes
3. **Import feature** - See @docs/import-processing.md for bulk import logic
4. **Database changes** - Create Flyway migrations, never alter schema directly
5. **Testing transactions** - Use TestContainers for database tests (see service-common)
```

### Transformation Checklist (Per Service)

For each service (transaction-service, currency-service, future services):

- [ ] Create thin CLAUDE.md (50-100 lines)
- [ ] Reference service-common for Spring Boot patterns
- [ ] Document only service-specific concerns
- [ ] Add OpenAPI spec to docs/api/
- [ ] Create docs/domain-model.md
- [ ] Create docs/database-schema.md (if applicable)
- [ ] Add discovery commands
- [ ] Remove specific class names
- [ ] Add service-specific guidelines only

---

## Phase 4: Documentation Structure

### Create docs/ Hierarchy

#### orchestration/docs/

```
orchestration/docs/
├── architecture/                    # System-wide design
│   ├── system-overview.md          # High-level architecture diagram
│   ├── resource-routing-pattern.md # Gateway routing strategy
│   ├── security-architecture.md    # Cross-service security
│   └── service-communication.md    # How services interact
│
├── development/                     # Cross-service dev setup
│   ├── local-environment.md        # Complete setup guide
│   ├── debugging-guide.md          # Multi-service debugging
│   ├── database-setup.md           # Local database configuration
│   └── testing-strategy.md         # Cross-service testing
│
├── deployment/                      # Infrastructure as code
│   ├── docker compose-guide.md     # Using docker compose
│   ├── kubernetes-deployment.md    # K8s deployment
│   └── environment-variables.md    # Config management
│
└── decisions/                       # Architecture Decision Records
    ├── 001-orchestration-repo.md   # Why this repo exists
    ├── 002-resource-based-routing.md # NGINX routing strategy
    ├── 003-pattern-based-claude-md.md # This plan!
    └── template.md                  # ADR template
```

#### service-common/docs/

```
service-common/docs/
├── spring-boot-conventions.md       # THE canonical Spring patterns
├── testing-patterns.md              # Test strategies with examples
├── error-handling.md                # Exception patterns
├── logging-conventions.md           # Logging best practices
├── common-dependencies.md           # Dependency management
├── security-patterns.md             # Spring Security patterns
└── upgrade-guide.md                 # How to upgrade versions
```

#### service/docs/ (per service)

```
{service}/docs/
├── api/
│   ├── openapi.yaml                 # OpenAPI 3.0 spec
│   └── README.md                    # API usage guide
├── domain-model.md                  # Business entities
├── database-schema.md               # DB structure (if applicable)
└── [service-specific-docs].md       # Unique concerns
```

### Content Migration

**From orchestration/docs/ (current):**
- `persistence-layer-architecture.md` → service-common/docs/spring-boot-conventions.md
- `service-layer-architecture.md` → service-common/docs/spring-boot-conventions.md
- `security-architecture.md` → orchestration/docs/architecture/ (stays, system-wide)
- `authentication-implementation-plan.md` → Implement or archive
- `local-development-database.md` → orchestration/docs/development/database-setup.md

**Create new:**
- orchestration/docs/architecture/system-overview.md (with diagrams)
- orchestration/docs/architecture/resource-routing-pattern.md (extract from NGINX docs)
- orchestration/docs/decisions/001-orchestration-repo.md (why this exists)
- orchestration/docs/decisions/002-resource-based-routing.md (architectural choice)
- orchestration/docs/decisions/003-pattern-based-claude-md.md (this plan!)

---

## Phase 5: Architecture Decision Records (ADRs)

### Why ADRs?

**Problem**: Architectural decisions made months ago are forgotten or unclear.

**Solution**: Lightweight decision records documenting:
- What was decided
- Why it was decided
- What alternatives were considered
- What consequences resulted

### ADR Template

Create `orchestration/docs/decisions/template.md`:

```markdown
# {Number}. {Title}

**Date:** YYYY-MM-DD
**Status:** [Proposed | Accepted | Superseded | Deprecated]
**Deciders:** [List of people involved]

## Context

[Describe the situation that led to this decision. What problem are we trying to solve?]

## Decision

[Describe the decision we made. Keep it concise and action-oriented.]

## Alternatives Considered

### Alternative 1: [Name]
**Pros:**
- [Benefit 1]
- [Benefit 2]

**Cons:**
- [Drawback 1]
- [Drawback 2]

### Alternative 2: [Name]
[Same format]

## Consequences

**Positive:**
- [Benefit 1]
- [Benefit 2]

**Negative:**
- [Drawback 1]
- [Drawback 2]

**Neutral:**
- [Change 1]
- [Change 2]

## References
- [Link to related docs]
- [Link to discussions]
```

### Initial ADRs to Create

#### 001-orchestration-repo.md

```markdown
# 001. Orchestration Repository Pattern

**Date:** 2025-11-10
**Status:** Accepted

## Context

Budget Analyzer is a microservices architecture with multiple independently deployed services (transaction-service, currency-service, budget-analyzer-web). We need a way to:
- Coordinate local development environment
- Manage shared infrastructure (database, message queue, gateway)
- Document system-wide architecture
- Provide a single entry point for developers

## Decision

Create a dedicated "orchestration" repository that:
- Contains no application code
- Hosts docker compose for local development
- Manages NGINX gateway configuration
- Provides system-wide documentation
- Includes deployment manifests (Kubernetes)
- Coordinates cross-service concerns

## Alternatives Considered

### Alternative 1: Monorepo
Put all services in a single repository.

**Pros:**
- Single clone for entire system
- Atomic cross-service changes
- Simpler dependency management

**Cons:**
- Large repository size
- Couples deployment of all services
- Harder to manage independent service lifecycles
- Team boundaries less clear

### Alternative 2: No Orchestration Repo
Each service self-contains its docker compose and docs.

**Pros:**
- No extra repository
- Each service fully independent

**Cons:**
- Duplicated infrastructure definitions
- No single source of truth for system architecture
- Harder to onboard new developers
- Inconsistent local environments

### Alternative 3: Infrastructure Repo
Similar to orchestration, but focused only on deployment.

**Pros:**
- Clear focus on infrastructure
- Separation of concerns

**Cons:**
- Where do architecture docs go?
- Where does local dev setup live?
- "Infrastructure" implies production, confusing for dev

## Consequences

**Positive:**
- Single place to start for new developers
- Clear separation: orchestration vs. service code
- Easy to coordinate local development environment
- System-wide documentation has a home
- Gateway configuration centralized

**Negative:**
- One more repository to manage
- Developers need to clone orchestration + service repos
- Risk of orchestration/service version mismatches

**Neutral:**
- Introduces new pattern (not common in all organizations)
- Requires discipline to keep orchestration docs updated

## References
- README.md in orchestration repo
- CLAUDE.md reorganization plan
```

#### 002-resource-based-routing.md

```markdown
# 002. Resource-Based API Gateway Routing

**Date:** 2025-11-10
**Status:** Accepted

## Context

Frontend needs to call backend microservices through NGINX gateway. We must decide how to structure routes:
- Service-based: `/api/transaction-service/transactions`, `/api/currency-service/currencies`
- Resource-based: `/api/transactions`, `/api/currencies`

Moving resources between services (e.g., splitting transaction-service) should not require frontend changes.

## Decision

Use **resource-based routing** at the NGINX gateway:
- Frontend calls clean paths: `/api/v1/transactions`, `/api/v1/currencies`
- NGINX routes to appropriate backend service
- Backend services can use any internal path structure
- Moving a resource to a different service requires only NGINX config change

## Alternatives Considered

### Alternative 1: Service-Based Routing
Frontend calls `/api/{service-name}/{resource}`

**Pros:**
- Clear which service handles request
- Easy to debug (service name in URL)
- No ambiguity in routing

**Cons:**
- Frontend tightly coupled to service topology
- Moving resource to different service breaks frontend
- Service names exposed to frontend (implementation detail leakage)
- Refactoring services requires frontend changes

### Alternative 2: Backend for Frontend (BFF)
Create aggregation layer that composes multiple services.

**Pros:**
- Frontend has single tailored API
- Can aggregate multiple backend calls
- Hides backend complexity

**Cons:**
- Adds complexity (another service to maintain)
- Can become bloated "god service"
- Increases latency (extra hop)
- Requires careful API design

## Consequences

**Positive:**
- Frontend decoupled from service topology
- Can refactor/split services without frontend impact
- Clean, RESTful API paths
- API versioning at gateway level (`/api/v1/`, `/api/v2/`)
- Simpler frontend code (no service names)

**Negative:**
- NGINX config is critical path (must be correct)
- Less obvious which service handles request (need docs or logs)
- NGINX becomes single point of configuration change

**Neutral:**
- NGINX configuration grows as resources added
- Need documentation to map resources → services

## Implementation Notes

Example NGINX configuration:
```nginx
location /api/v1/transactions {
    proxy_pass http://transaction-service:8082/transactions;
}

location /api/v1/currencies {
    proxy_pass http://currency-service:8084/currencies;
}
```

If we later move currency conversion to a new service, only NGINX changes:
```nginx
location /api/v1/currencies {
    proxy_pass http://currency-service-v2:8085/currencies;
}
```

Frontend code unchanged.

## References
- nginx/nginx.dev.conf
- orchestration/docs/architecture/resource-routing-pattern.md
```

#### 003-pattern-based-claude-md.md

```markdown
# 003. Pattern-Based CLAUDE.md Documentation

**Date:** 2025-11-10
**Status:** Accepted

## Context

CLAUDE.md files provide context to AI coding assistants (Claude Code, etc.). We've experienced:
- Documentation drift (services added, docs not updated)
- Specificity problems (class names change, docs stale)
- Duplication (Spring Boot patterns repeated in multiple services)
- Maintenance burden (every refactor requires doc updates)

We need a sustainable approach that survives refactoring.

## Decision

Use **pattern-based documentation** in CLAUDE.md files:
- Document "how to discover" rather than "what exists"
- Reference source files with @path/to/file syntax
- Provide grep/tree commands to reveal current state
- Keep CLAUDE.md files thin (50-150 lines)
- Delegate detailed docs to docs/ directories
- Never reference specific class names
- Hierarchical structure: orchestration (patterns) → service-common (Spring patterns) → services (unique concerns)

## Alternatives Considered

### Alternative 1: Specificity-Based Documentation
List all services, classes, endpoints explicitly.

**Pros:**
- Complete information in one place
- No need to run discovery commands
- Easy to read (everything visible)

**Cons:**
- High maintenance burden
- Drifts quickly during refactoring
- Creates false sense of completeness
- Duplicates information from config files

### Alternative 2: No CLAUDE.md Files
Let AI assistants learn from code only.

**Pros:**
- No documentation maintenance
- Always reflects current code

**Cons:**
- AI lacks architectural context
- No guidance on conventions/patterns
- Misses "why" behind decisions
- Slower AI performance (more exploration needed)

### Alternative 3: Single Central CLAUDE.md
One CLAUDE.md in orchestration covers everything.

**Pros:**
- Single source of context
- Easier to maintain consistency

**Cons:**
- Becomes massive and hard to navigate
- Mixes abstraction levels (system-wide + service details)
- Doesn't scale as services grow
- Doesn't leverage Claude's hierarchical loading

## Consequences

**Positive:**
- Survives refactoring without updates (discovery commands always work)
- Eliminates drift (references source of truth)
- Teaches AI to discover current state
- Scales as microservices grow
- Reduced maintenance burden
- Encourages DRY (reference, don't duplicate)

**Negative:**
- Requires learning curve (new pattern for team)
- Discovery commands must be tested/maintained
- Less "self-contained" (need to run commands)
- Relies on file structure stability

**Neutral:**
- New approach (not widely documented yet)
- Requires discipline (easy to fall back to specificity)

## Implementation Notes

**Example transformation:**

Before (specificity-based):
```markdown
### Core Services
1. transaction-service (port 8082)
2. currency-service (port 8084)
```

After (pattern-based):
```markdown
### Core Services
Services defined in `docker compose.yml`. Discover with:
```bash
docker compose config --services
```

Pattern: Spring Boot services on ports 8082+
```

**Validation**: Create scripts/validate-claude-context.sh to test that:
- All @references point to existing files
- All discovery commands execute successfully
- No broken links in CLAUDE.md files

## References
- This reorganization plan document
- Research: Claude Code Best Practices (anthropic.com)
- Research: Pattern-based documentation (2025 best practices)
```

### ADR Maintenance

**When to create an ADR:**
- Any architectural decision that affects multiple services
- Technology choices (Spring Boot version upgrade, new framework)
- Pattern changes (new testing strategy, API design)
- Infrastructure decisions (add Redis, switch databases)

**Process:**
1. Copy `template.md` to `00N-decision-title.md`
2. Fill in sections (especially "Alternatives Considered")
3. Commit with PR
4. Update status when decision changes (Accepted → Superseded)

---

## Phase 6: Validation and Tooling

### Validation Script: scripts/validate-claude-context.sh

Create script to catch documentation drift:

```bash
#!/usr/bin/env bash
# scripts/validate-claude-context.sh
# Validates CLAUDE.md files for broken references and dead commands

set -e

echo "=== Validating CLAUDE.md Context Files ==="

ERRORS=0

# Find all CLAUDE.md files
CLAUDE_FILES=$(find . -name "CLAUDE.md" -o -name "CLAUDE.local.md")

for file in $CLAUDE_FILES; do
    echo ""
    echo "Checking: $file"

    # Extract @references (e.g., @docs/some-file.md)
    REFS=$(grep -o '@[a-zA-Z0-9/_.-]*' "$file" || true)

    for ref in $REFS; do
        # Remove @ prefix
        path="${ref:1}"

        # Check if referenced file exists (relative to CLAUDE.md location)
        dir=$(dirname "$file")
        full_path="$dir/$path"

        if [ ! -e "$full_path" ]; then
            echo "  ❌ Broken reference: $ref (expected: $full_path)"
            ERRORS=$((ERRORS + 1))
        else
            echo "  ✅ Valid reference: $ref"
        fi
    done

    # Extract discovery commands (lines between ```bash and ```)
    # Test that they execute without error (optional: check output too)
    # NOTE: This is simplified - full implementation would parse markdown better

done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All CLAUDE.md files valid!"
    exit 0
else
    echo "❌ Found $ERRORS broken references"
    exit 1
fi
```

**Usage:**
```bash
# Validate all CLAUDE.md files
./scripts/validate-claude-context.sh

# Run in CI
# Add to .github/workflows/validate-docs.yml
```

### CI Integration

Add to `.github/workflows/validate-docs.yml` (if using GitHub Actions):

```yaml
name: Validate Documentation

on:
  pull_request:
    paths:
      - '**.md'
      - 'CLAUDE.md'
      - 'docs/**'
      - 'scripts/validate-claude-context.sh'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Validate CLAUDE.md references
        run: ./scripts/validate-claude-context.sh

      - name: Check for TODO markers in production docs
        run: |
          # Fail if docs contain unresolved TODOs
          if grep -r "TODO\|FIXME\|XXX" docs/; then
            echo "❌ Unresolved TODOs found in docs"
            exit 1
          fi

      - name: Validate ADR numbering
        run: |
          # Check that ADRs are numbered sequentially
          cd docs/decisions
          ls -1 *.md | grep -E '^[0-9]{3}-' | sort -n
```

### Documentation Coverage Report

Create `scripts/doc-coverage-report.sh`:

```bash
#!/usr/bin/env bash
# scripts/doc-coverage-report.sh
# Reports on documentation coverage

echo "=== Documentation Coverage Report ==="
echo ""

# Check for OpenAPI specs
echo "## API Documentation"
for service in transaction-service currency-service; do
    if [ -f "../$service/docs/api/openapi.yaml" ]; then
        echo "  ✅ $service has OpenAPI spec"
    else
        echo "  ❌ $service missing OpenAPI spec"
    fi
done
echo ""

# Check for CLAUDE.md files
echo "## CLAUDE.md Files"
for repo in orchestration service-common transaction-service currency-service; do
    if [ -f "../$repo/CLAUDE.md" ]; then
        lines=$(wc -l < "../$repo/CLAUDE.md")
        echo "  ✅ $repo/CLAUDE.md ($lines lines)"
    else
        echo "  ❌ $repo/CLAUDE.md missing"
    fi
done
echo ""

# Check for ADRs
echo "## Architecture Decision Records"
adr_count=$(find docs/decisions -name "*.md" ! -name "template.md" | wc -l)
echo "  📝 $adr_count ADRs documented"
echo ""

# Check for service docs
echo "## Service Documentation"
for service in transaction-service currency-service; do
    if [ -d "../$service/docs" ]; then
        doc_count=$(find "../$service/docs" -name "*.md" | wc -l)
        echo "  📄 $service: $doc_count documentation files"
    else
        echo "  ❌ $service/docs/ missing"
    fi
done
```

---

## Phase 7: Templates for New Services

### New Service Checklist

When creating a new Spring Boot service:

```markdown
## New Spring Boot Service Checklist

### Repository Setup
- [ ] Create repo in budget-analyzer org: `{domain}-service`
- [ ] Copy `.gitignore` from template
- [ ] Set up branch protection on main
- [ ] Add repo to `scripts/repo-config.sh`

### Code Structure
- [ ] Inherit from service-common in `pom.xml`
- [ ] Follow package structure: `com.budgetanalyzer.{domain}.{layer}`
- [ ] Create standard layers: controller, service, repository, dto
- [ ] Add TestContainers for integration tests

### Documentation
- [ ] Create `CLAUDE.md` from template (below)
- [ ] Create `docs/api/openapi.yaml`
- [ ] Create `docs/domain-model.md`
- [ ] Create `docs/database-schema.md` (if applicable)
- [ ] Update `orchestration/docs/architecture/system-overview.md`

### Integration
- [ ] Add service to `orchestration/docker compose.yml`
- [ ] Add routes to `orchestration/nginx/nginx.dev.conf`
- [ ] Add health check endpoint (`/actuator/health`)
- [ ] Test routing through gateway

### CI/CD
- [ ] Set up GitHub Actions workflow
- [ ] Add build pipeline
- [ ] Add test pipeline
- [ ] Configure deployment

### Validation
- [ ] Run `scripts/validate-repos.sh`
- [ ] Run `scripts/validate-claude-context.sh`
- [ ] Test local development setup
- [ ] Verify Swagger UI works
```

### Service CLAUDE.md Template

Create `templates/service-CLAUDE.md`:

```markdown
# {Service Name} - {Brief Domain Description}

## Service Purpose
{2-3 sentences describing business domain}

**Domain**: {e.g., "Payment processing and invoicing"}
**Responsibilities**:
- {Key responsibility 1}
- {Key responsibility 2}
- {Key responsibility 3}

## Spring Boot Patterns

**This service follows standard Budget Analyzer Spring Boot conventions.**

See [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md) for:
- Architecture layers (Controller → Service → Repository)
- Naming conventions
- Testing patterns
- Error handling
- Logging conventions
- Dependency management

## Service-Specific Patterns

### API Contracts
Full API specification: @docs/api/openapi.yaml

**Discovery**:
```bash
# Start service with Swagger UI
./mvnw spring-boot:run
open http://localhost:{PORT}/swagger-ui.html

# View OpenAPI spec
cat docs/api/openapi.yaml
```

### Domain Model
See @docs/domain-model.md

**Key concepts**:
- {Entity 1}: {Brief description}
- {Entity 2}: {Brief description}

### Database Schema
{If applicable}
See @docs/database-schema.md

**Key tables**:
- `{table_name}`: {Brief description}

**Migrations**: Flyway (see `src/main/resources/db/migration/`)

### {Service-Specific Feature}
{If applicable - document unique concerns only}

See @docs/{feature-name}.md

## Running Locally

```bash
# Start dependencies
cd orchestration/
docker compose up shared-postgres

# Run service
cd {service-name}/
./mvnw spring-boot:run

# Access service
curl http://localhost:{PORT}/actuator/health
```

**See**: [@orchestration/docs/development/local-environment.md](https://github.com/budget-analyzer/orchestration/blob/main/docs/development/local-environment.md)

## Discovery Commands

```bash
# Find all endpoints
grep -r "@GetMapping\|@PostMapping\|@PutMapping\|@DeleteMapping" src/

# View configuration
cat src/main/resources/application.yml

# Check dependencies
./mvnw dependency:tree
```

## AI Assistant Guidelines

1. **Follow service-common patterns** - See [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md)
2. **Check OpenAPI spec first** - See @docs/api/openapi.yaml
3. **Understand domain** - Read @docs/domain-model.md before changes
4. **Test everything** - Follow @service-common/docs/testing-patterns.md
5. {Service-specific guideline}
```

### Frontend Service Template

Create `templates/frontend-CLAUDE.md`:

```markdown
# {Frontend Name} - {Brief Description}

## Application Purpose
{2-3 sentences describing frontend application}

**Type**: React {version} web application
**Responsibilities**:
- {Key responsibility 1}
- {Key responsibility 2}
- {Key responsibility 3}

## Frontend Patterns

### Technology Stack

**Discovery**:
```bash
# View dependencies
cat package.json

# React version
cat package.json | grep '"react"'
```

**Key technologies**:
- React {version}
- {State management library}
- {Routing library}
- {UI component library}

### API Integration

**Pattern**: All API calls go through NGINX gateway at `http://localhost:8080/api/*`

See [@orchestration/nginx/nginx.dev.conf](https://github.com/budget-analyzer/orchestration/blob/main/nginx/nginx.dev.conf) for available routes.

**Discovery**:
```bash
# See all API routes
cat orchestration/nginx/nginx.dev.conf | grep "location /api"
```

**Usage**:
```javascript
// Always use relative paths
fetch('/api/v1/transactions')
  .then(res => res.json())

// Never hardcode service URLs
// ❌ fetch('http://localhost:8082/transactions')
// ✅ fetch('/api/v1/transactions')
```

### Component Structure

**Discovery**:
```bash
# Find all components
find src/components -name "*.jsx" -o -name "*.tsx"
```

**Organization**:
{Describe component organization pattern}

### State Management

{Describe state management approach}

See @docs/state-management.md

### Routing

{Describe routing strategy}

See @docs/routing.md

## Running Locally

```bash
# Install dependencies
npm install

# Start dev server (with hot reload)
npm start

# Access application
open http://localhost:3000
```

**Note**: Backend services must be running (see [@orchestration/docs/development/local-environment.md](https://github.com/budget-analyzer/orchestration/blob/main/docs/development/local-environment.md))

## Building

```bash
# Production build
npm run build

# Output in build/ directory
ls -lh build/
```

## Discovery Commands

```bash
# View available scripts
cat package.json | grep -A 10 '"scripts"'

# Check for unused dependencies
npx depcheck

# Bundle analysis
npm run build && npx webpack-bundle-analyzer build/stats.json
```

## AI Assistant Guidelines

1. **Follow React best practices** - {Link to team conventions}
2. **API calls through gateway** - Always use `/api/*` paths
3. **Component patterns** - See @docs/component-patterns.md
4. **Testing** - {Testing strategy}
5. {Frontend-specific guideline}
```

---

## Migration Timeline

### Immediate (Phase 1-2): Foundation
**Estimated time**: 2-4 hours

1. ✅ Read this plan thoroughly
2. ✅ Create `docs/decisions/` directory
3. ✅ Write ADRs (001, 002, 003)
4. ✅ Create `service-common/docs/` structure
5. ✅ Transform `orchestration/CLAUDE.md` (pattern-based)
6. ✅ Create `service-common/CLAUDE.md`

**Validation**: Run grep commands in new CLAUDE.md files to verify they work

### Short-term (Phase 3-4): Service Updates
**Estimated time**: 1-2 hours per service

1. ✅ Transform `transaction-service/CLAUDE.md`
2. ✅ Create `transaction-service/docs/api/openapi.yaml`
3. ✅ Create `transaction-service/docs/domain-model.md`
4. ✅ Repeat for `currency-service`
5. ✅ Repeat for `budget-analyzer-web`

**Validation**: Test discovery commands in each CLAUDE.md

### Medium-term (Phase 5-6): Tooling
**Estimated time**: 2-3 hours

1. ✅ Create `scripts/validate-claude-context.sh`
2. ✅ Create `scripts/doc-coverage-report.sh`
3. ✅ Add CI validation (if using CI/CD)
4. ✅ Test validation scripts

**Validation**: Run validation script, ensure it catches broken references

### Long-term (Phase 7): Templates & Standards
**Estimated time**: 1-2 hours

1. ✅ Create `templates/` directory
2. ✅ Create service CLAUDE.md template
3. ✅ Create new service checklist
4. ✅ Document the documentation strategy (meta!)

**Validation**: Use template for next new service

---

## Success Criteria

### Immediate Wins
- [ ] `orchestration/CLAUDE.md` is < 150 lines
- [ ] All @references in CLAUDE.md files point to existing files
- [ ] Discovery commands in CLAUDE.md files execute successfully
- [ ] No duplicate Spring Boot pattern documentation across repos

### Medium-term Goals
- [ ] New team member can set up environment using only orchestration docs
- [ ] Adding a new service doesn't require updating orchestration/CLAUDE.md
- [ ] Refactoring a service doesn't require updating CLAUDE.md
- [ ] CI validates documentation on every PR

### Long-term Vision
- [ ] Every service has complete API documentation (OpenAPI)
- [ ] Every architectural decision has an ADR
- [ ] Documentation coverage report shows 100% coverage
- [ ] New service creation uses templates (10-minute setup)

---

## Maintenance Strategy

### Quarterly Reviews
Every 3 months:
1. Run `scripts/doc-coverage-report.sh`
2. Check for CLAUDE.md drift (do discovery commands still work?)
3. Review ADRs for outdated decisions
4. Update templates if patterns evolved

### When to Update CLAUDE.md Files
- **Do update** when:
  - Architectural pattern changes (e.g., new testing strategy)
  - Discovery command changes (e.g., new grep pattern needed)
  - New principle added (e.g., new security rule)
  - File structure changes (e.g., docs/ reorganized)

- **Don't update** when:
  - New service added (discovery commands reveal it)
  - Specific class renamed (not referenced in CLAUDE.md)
  - Port numbers change (docker compose.yml is source of truth)
  - New API endpoint added (OpenAPI spec is source of truth)

### Red Flags (Indicates Drift)
- ❌ CLAUDE.md file > 200 lines (too specific)
- ❌ Mentions specific class names
- ❌ Contains hardcoded service list
- ❌ Discovery commands fail
- ❌ @references point to non-existent files
- ❌ Duplicates content from config files

---

## Rollout Communication

### Team Announcement Template

```markdown
Subject: New Documentation Strategy - Pattern-Based CLAUDE.md Files

Team,

We're adopting a new approach to CLAUDE.md files and documentation to reduce drift and maintenance burden.

**Key Changes:**
1. CLAUDE.md files now document **patterns**, not **specifics**
2. Use **discovery commands** (grep, tree) instead of lists
3. **Reference source files** with @path/to/file syntax
4. Detailed docs go in `docs/` directories
5. Service-specific CLAUDE.md files reference `service-common/CLAUDE.md`

**Why?**
- Survives refactoring (no updates needed)
- Eliminates drift (always accurate)
- Scales as we add services
- Reduces maintenance burden

**Action Required:**
- Read: orchestration/docs/claude-md-reorganization-plan.md
- When creating new services: Use templates in templates/
- When working with AI: Trust the new CLAUDE.md discovery patterns

**Examples:**
Before: "transaction-service runs on port 8082"
After: "See docker compose.yml for ports: `cat docker compose.yml | grep ports:`"

Questions? See the full plan doc or ping me.

Thanks!
```

---

## FAQ

### Q: Why not just keep CLAUDE.md comprehensive and detailed?
**A:** Comprehensive documentation drifts quickly. Pattern-based docs teach AI to discover current state, which is always accurate.

### Q: What if discovery commands break?
**A:** The validation script (`scripts/validate-claude-context.sh`) catches this. Fix the command or update the pattern.

### Q: Should we never reference specific services?
**A:** Reference them when teaching the pattern ("e.g., transaction-service"), but don't maintain an inventory.

### Q: What about onboarding new developers?
**A:** The README.md files remain human-friendly. CLAUDE.md files are optimized for AI assistants. Both are important.

### Q: How do we know if CLAUDE.md is too specific?
**A:** Ask: "If I refactor, do I need to update this?" If yes, it's too specific. Use a pattern instead.

### Q: Where do code examples go?
**A:** In `docs/` directories with full examples. CLAUDE.md references them with @docs/file.md.

### Q: What if a pattern evolves?
**A:** Update service-common/docs/ (the source of truth), then all services inherit the change. Document the evolution in CHANGELOG.md.

### Q: Do we need ADRs for every decision?
**A:** Only architectural decisions that affect multiple services or have lasting impact.

---

## Appendix A: Before/After Full Example

### Before: orchestration/CLAUDE.md (Excerpt)
```markdown
## Architecture

### Core Services

1. **budget-analyzer-web** - React 19 web application
   - Modern frontend for budget tracking and financial analysis
   - Development server runs on port 3000
   - Production build served as static assets

2. **transaction-service** - Spring Boot microservice
   - Core business logic for budget and transaction management
   - Runs on port 8082
   - RESTful API endpoints under `/transaction-service/*`

3. **currency-service** - Spring Boot microservice
   - Currency conversion and exchange rate management
   - Runs on port 8084
   - RESTful API endpoints under `/currency-service/*`

4. **nginx-gateway** - NGINX API Gateway
   - Unified entry point for all services (port 8080)
   - Resource-based routing (frontend calls clean `/api/*` paths)

### Frontend Access Pattern

The frontend should call the NGINX gateway at `http://localhost:8080/api/*`:
- `/api/transactions` → routed to transaction-service
- `/api/currencies` → routed to currency-service
- `/api/exchange-rates` → routed to currency-service

### Technology Stack

#### Frontend
- React 19
- Modern JavaScript/TypeScript

#### Backend
- Spring Boot 3.x
- Java 17+
- RESTful APIs

#### Infrastructure
- Docker for containerization
- NGINX for API gateway
- PostgreSQL/MySQL for databases (if applicable)
```

### After: orchestration/CLAUDE.md (Pattern-Based)
```markdown
## Architecture

### Service Discovery

**Pattern**: Microservices architecture with NGINX API gateway.

**Discovery**:
```bash
# List all services
docker compose config --services

# View full configuration
docker compose config

# See service ports
docker compose ps
```

**Service Types**:
- **Frontend**: React-based web apps (dev port 3000)
- **Backend**: Spring Boot REST APIs (ports 8082+)
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ
- **Gateway**: NGINX (port 8080) - unified entry point

**See**: @docs/architecture/system-overview.md for architecture diagram

### API Gateway Pattern

**Frontend access**: All requests through `http://localhost:8080/api/*`

**Routing strategy**: Resource-based (not service-based)
- Frontend decoupled from service topology
- Moving resources = NGINX config change only
- Clean RESTful paths with versioning (`/api/v1/...`)

**Current routes**: See @nginx/nginx.dev.conf (source of truth)

**Discovery**:
```bash
# List all API routes
cat nginx/nginx.dev.conf | grep "location /api" | grep -v "#"

# Test gateway
curl -v http://localhost:8080/api/v1/health
```

**See**: @docs/architecture/resource-routing-pattern.md

### Technology Stack

**Discovery**:
```bash
# Frontend framework
cat budget-analyzer-web/package.json | grep '"react"'

# Spring Boot version (canonical)
cat service-common/pom.xml | grep '<spring-boot.version>'

# Infrastructure versions
docker compose config | grep 'image:' | sort -u
```

**Stack patterns**:
- **Frontend**: React (version in package.json)
- **Backend**: Spring Boot + Java (version in service-common)
- **Infrastructure**: PostgreSQL, Redis, RabbitMQ (see docker compose.yml)

**Version management**:
- Spring Boot: Defined in service-common/pom.xml (single source of truth)
- Services: Inherit versions, never override

**See**:
- [@service-common/docs/common-dependencies.md](https://github.com/budget-analyzer/service-common/blob/main/docs/common-dependencies.md)
- @docs/development/local-environment.md
```

**Line count**:
- Before: ~250 lines (specific)
- After: ~120 lines (pattern-based)

**Maintenance**:
- Before: Update on every service addition, port change, version upgrade
- After: Update only when patterns change

---

## Appendix B: Key Research Citations

### 2025 Best Practices (Web Search Results)

**Claude Code Best Practices (Anthropic)**
- "Keep CLAUDE.md concise and human-readable"
- "Use @syntax to import other files"
- "Hierarchical loading: root → subdirectory"

**Pattern-Based Documentation**
- "Examples beat abstractions - point to real files"
- "Document how to discover, not what exists"
- "Discovery commands better than inventories"

**Microservices Documentation**
- "Topic-based organization"
- "Service-level separation"
- "Living documentation culture"
- "Automate where possible"

**Context Engineering**
- "Focus on decision-making context"
- "Hierarchical rules for large repos"
- "Patterns over specifics"

### Internal Analysis (Budget Analyzer Drift Report)

**Current drift issues identified:**
- Version vagueness (latest tags)
- Fictional script directories
- Incomplete route documentation
- Missing infrastructure services
- Container/service name confusion

**Validation**: These issues would not exist with pattern-based docs.

---

## Conclusion

This plan transforms Budget Analyzer documentation from **inventory-based** (brittle, high maintenance) to **pattern-based** (resilient, low maintenance).

**Next Steps:**
1. Review this plan with team
2. Begin Phase 1 (foundation)
3. Incrementally update services
4. Add validation tooling
5. Create templates for future services

**Success looks like:**
- Refactoring code without updating CLAUDE.md
- Adding services without updating orchestration docs
- New developers discovering current state easily
- AI assistants understanding patterns, not memorizing specifics

**Timeline**: 8-12 hours total spread across phases.

**Outcome**: Sustainable, scalable documentation that grows with your architecture.

---

**Document Status**: Ready for implementation
**Reviewed by**: [Your name]
**Date**: 2025-11-10
**Next review**: After Phase 1 completion
