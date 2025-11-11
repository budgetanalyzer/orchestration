# Budget Analyzer Service Templates

This directory contains templates for creating new services in the Budget Analyzer microservices architecture.

## Purpose

These templates implement the **pattern-based documentation strategy** described in [docs/decisions/003-pattern-based-claude-md.md](../docs/decisions/003-pattern-based-claude-md.md). They ensure:

- Consistent documentation structure across services
- Pattern-based approach that survives refactoring
- Proper reference to service-common conventions
- Separation of concerns (service-specific vs. shared patterns)

## Available Templates

### 1. service-CLAUDE.md
Template for Spring Boot microservice CLAUDE.md files.

**When to use**: Creating any new Spring Boot backend service (REST APIs, domain services, etc.)

**Features**:
- References service-common for shared Spring Boot patterns
- Documents only service-specific concerns
- Includes discovery commands
- Provides OpenAPI, domain model, and database schema references

**Usage**:
```bash
# Copy template to new service
cp templates/service-CLAUDE.md ../{service-name}/CLAUDE.md

# Customize placeholders:
# - {Service Name}: e.g., "Payment Service"
# - {Brief Domain Description}: e.g., "Payment Processing and Invoicing"
# - {Domain}: e.g., "Payment processing"
# - {Key responsibility 1-3}: List main responsibilities
# - {PORT}: Service port (8082+)
# - {service-name}: Repository name
# - {Entity 1-2}: Domain entities
# - {table_name}: Database tables (if applicable)
# - {feature-name}: Unique features (if applicable)
```

**Example**: See `transaction-service/CLAUDE.md` for a real implementation

### 2. frontend-CLAUDE.md
Template for React frontend application CLAUDE.md files.

**When to use**: Creating any new React-based web application

**Features**:
- Documents frontend-specific patterns
- API integration through NGINX gateway
- Component structure and state management
- Build and deployment patterns

**Usage**:
```bash
# Copy template to new frontend
cp templates/frontend-CLAUDE.md ../{frontend-name}/CLAUDE.md

# Customize placeholders:
# - {Frontend Name}: e.g., "Admin Dashboard"
# - {Brief Description}: e.g., "Administrative Interface"
# - {version}: React version
# - {Key responsibility 1-3}: Main features
# - {State management library}: Redux, Context API, etc.
# - {Routing library}: React Router, etc.
# - {UI component library}: Material-UI, etc.
```

**Example**: See `budget-analyzer-web/CLAUDE.md` for a real implementation

### 3. new-service-checklist.md
Comprehensive checklist for creating a new Spring Boot service.

**When to use**: Every time you create a new backend microservice

**Features**:
- Step-by-step checklist for service creation
- Repository setup
- Code structure guidelines
- Documentation requirements
- Integration steps (docker-compose, NGINX)
- CI/CD setup
- Validation steps

**Usage**:
```bash
# View checklist
cat templates/new-service-checklist.md

# Copy to track progress for specific service
cp templates/new-service-checklist.md ../{service-name}/SERVICE_SETUP_CHECKLIST.md

# Check off items as you complete them
```

## Template Principles

### 1. Pattern-Based (Not Specificity-Based)

**❌ Anti-Pattern**: List specific classes, endpoints, ports
```markdown
### Endpoints
- POST /api/transactions - TransactionController.createTransaction()
- GET /api/transactions/{id} - TransactionController.getTransaction()
```

**✅ Pattern-Based**: Provide discovery commands
```markdown
### API Contracts
Full API specification: @docs/api/openapi.yaml

**Discovery**:
```bash
grep -r "@GetMapping\|@PostMapping" src/
```

### 2. Reference, Don't Duplicate

**❌ Anti-Pattern**: Duplicate Spring Boot patterns in every service
```markdown
### Service Layer
Services contain business logic. They use the @Service annotation...
[100 lines of Spring patterns duplicated from service-common]
```

**✅ Reference**: Point to single source of truth
```markdown
## Spring Boot Patterns

**This service follows standard Budget Analyzer Spring Boot conventions.**

See [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md) for architecture layers, naming conventions, and testing patterns.
```

### 3. Document the "Why"

Templates should explain:
- Why this pattern exists (architectural decision)
- When to use vs. not use
- What makes this service unique (not just what it does)

### 4. Keep CLAUDE.md Thin (50-150 lines)

- CLAUDE.md provides AI context, not comprehensive documentation
- Detailed docs belong in `docs/` directory
- Use @references to point to detailed docs

## Customization Guidelines

### Placeholders to Replace

All templates use `{placeholder}` format for values you must customize:

| Placeholder | Example | Where to Find |
|-------------|---------|---------------|
| `{Service Name}` | Payment Service | Your service's business domain |
| `{domain}` | payment | Lowercase, hyphenated |
| `{PORT}` | 8086 | Check docker-compose.yml for available ports |
| `{service-name}` | payment-service | Repository name |
| `{Entity 1}` | Payment | Domain model entities |
| `{table_name}` | payments | Database table names |
| `{version}` | 19 | Current React version (package.json) |

### Optional Sections

Some sections are marked `{If applicable}`:
- **Database Schema**: Only if service has its own database
- **Service-Specific Feature**: Only if unique functionality exists
- **State Management**: Only for frontend with complex state

**Remove these sections** if not applicable, don't leave placeholders.

### Discovery Commands

All templates include discovery commands in bash code blocks. These must:
- ✅ Execute successfully (test before committing)
- ✅ Return useful information
- ✅ Work from service root directory
- ❌ Never use hardcoded values that might change

## Validation

After using a template, validate it:

```bash
# From orchestration repo
./scripts/validate-claude-context.sh

# Check that all @references work
# Check that discovery commands execute successfully
```

## Examples

### Good Service CLAUDE.md (Pattern-Based)
```markdown
# Payment Service - Payment Processing and Invoicing

## Service Purpose
Handles payment transactions, invoice generation, and payment gateway integrations.

## Spring Boot Patterns
See [@service-common/CLAUDE.md](https://github.com/budget-analyzer/service-common/blob/main/CLAUDE.md) for standard conventions.

## Service-Specific Patterns

### API Contracts
See @docs/api/openapi.yaml

**Discovery**:
```bash
grep -r "@PostMapping" src/main/java/*/controller/
```

### Payment Gateway Integration
This service integrates with Stripe and PayPal.

See @docs/payment-gateways.md for configuration details.
```

**Why it's good**:
- ✅ References service-common (no duplication)
- ✅ Documents unique concern (payment gateways)
- ✅ Provides discovery command
- ✅ References detailed docs
- ✅ Thin (could fit in ~100 lines)

### Bad Service CLAUDE.md (Specificity-Based)
```markdown
# Payment Service

## Endpoints
- POST /api/payments - Creates payment (PaymentController.createPayment)
- GET /api/payments/{id} - Gets payment (PaymentController.getPayment)
- PUT /api/payments/{id} - Updates payment (PaymentController.updatePayment)
[... 50 more endpoints listed]

## Classes
- PaymentController - Handles HTTP requests
- PaymentService - Business logic
- PaymentServiceImpl - Implementation
- PaymentRepository - Data access
[... Spring Boot architecture duplicated]

## Database
- payments table: id, amount, currency, status...
[... entire schema duplicated]
```

**Why it's bad**:
- ❌ Lists specific classes (will drift during refactoring)
- ❌ Duplicates Spring Boot patterns (should reference service-common)
- ❌ Duplicates database schema (should reference schema doc)
- ❌ Huge file (200+ lines)
- ❌ High maintenance burden

## Maintenance

### When to Update Templates

**Do update** when:
- Documentation strategy changes (new patterns adopted)
- Service-common conventions evolve
- Discovery commands need improvement
- New best practices emerge

**Don't update** for:
- Individual service changes
- Technology version updates (templates should be version-agnostic)
- Specific implementation details

### Template Versioning

Templates evolve. Consider:
- Dating significant changes in this README
- Creating template-v2.md if breaking changes needed
- Documenting migration path for existing services

## Quick Start

Creating a new payment service example:

```bash
# 1. Create service repository
mkdir payment-service
cd payment-service

# 2. Copy CLAUDE.md template
cp ../orchestration/templates/service-CLAUDE.md ./CLAUDE.md

# 3. Copy checklist to track progress
cp ../orchestration/templates/new-service-checklist.md ./SERVICE_SETUP.md

# 4. Customize CLAUDE.md
# Replace {Service Name} with "Payment Service"
# Replace {Brief Domain Description} with "Payment Processing and Invoicing"
# Replace {domain} with "payment"
# Replace {PORT} with "8086"
# Replace {service-name} with "payment-service"

# 5. Create standard directories
mkdir -p docs/api
mkdir -p src/main/java/com/budgetanalyzer/payment/{controller,service,repository,dto}

# 6. Follow checklist
cat SERVICE_SETUP.md
```

## References

- [docs/decisions/003-pattern-based-claude-md.md](../docs/decisions/003-pattern-based-claude-md.md) - Documentation strategy
- [service-common/CLAUDE.md](../../service-common/CLAUDE.md) - Spring Boot conventions
- [CLAUDE.md](../CLAUDE.md) - Architecture patterns

## Questions?

- Check the pattern-based documentation plan: [docs/decisions/003-pattern-based-claude-md.md](../docs/decisions/003-pattern-based-claude-md.md)
- Review existing service implementations for examples
- Ask the team for clarification on conventions

---

**Last Updated**: 2025-11-10
**Status**: Phase 7 implementation complete
