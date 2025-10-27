# Service Layer Architecture
# Service Layer Architecture Pattern

## Overview

This document describes an architectural pattern for Spring Boot microservices that emphasizes **service reusability** and **clean separation of concerns** by keeping API-specific classes (request/response DTOs) out of the service layer.

## Core Principle

> **API DTOs are presentation layer concerns, not domain concerns.**

Services should accept and return **domain entities**, not API request/response objects. This enables services to be reused across multiple contexts: REST APIs, message queues, scheduled jobs, and GraphQL endpoints.

## Architecture Layers

### Controller Layer (Presentation)
**Responsibilities:**
- Handle HTTP concerns (status codes, headers, content negotiation)
- Retrieve entities by ID from repositories
- Map API DTOs to/from domain entities
- Delegate business logic to services

**What Controllers Do:**
```java
@RestController
@RequestMapping("/customers")
public class CustomerController {
  
  @Autowired private CustomerRepository customerRepository;
  @Autowired private CustomerMapper customerMapper;
  @Autowired private CustomerService customerService;
  
  @PutMapping("/{id}")
  public CustomerResponse update(@PathVariable Long id, 
                                  @RequestBody CustomerRequest request) {
    // 1. Retrieve entity (throw ResourceNotFoundException if not found)
    var customer = customerRepository.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("Customer not found"));
    
    // 2. Map request DTO to entity
    customerMapper.updateFromRequest(request, customer);
    
    // 3. Delegate to service
    var updated = customerService.update(customer);
    
    // 4. Map entity to response DTO
    return customerMapper.toResponse(updated);
  }
}
```

**What Controllers DON'T Do:**
- ❌ Business validation (e.g., checking if email already exists)
- ❌ Business logic (e.g., cascading updates, event publishing)
- ❌ Complex repository queries (only `findById`)
- ❌ Transaction management

**Exception Handling:**
Controllers only throw `InvalidRequestException` when a request is poorly formatted (i.e. invalid email address) or `ResourceNotFoundException` when an entity is not found. All other exceptions come from the service layer.

### Service Layer (Business Logic)
**Responsibilities:**
- Execute business logic
- Perform business validation
- Manage transactions
- Coordinate between repositories
- Publish domain events

**What Services Do:**
```java
@Service
public class CustomerService {
  
  @Autowired private CustomerRepository customerRepository;
  @Autowired private EmailService emailService;
  @Autowired private AuditService auditService;
  
  @Transactional
  public Customer update(Customer customer) {
    // Business validation
    validateEmailUniqueness(customer.getEmail(), customer.getId());
    validateBusinessRules(customer);
    
    // Business logic
    customer.setUpdatedAt(LocalDateTime.now());
    
    // Side effects
    auditService.logCustomerUpdate(customer);
    emailService.sendUpdateNotification(customer);
    
    // Persistence
    return customerRepository.save(customer);
  }
  
  private void validateEmailUniqueness(String email, Long customerId) {
    customerRepository.findByEmail(email)
        .filter(existing -> !existing.getId().equals(customerId))
        .ifPresent(existing -> {
          throw new DuplicateEmailException("Email already in use");
        });
  }
}
```

**What Services DON'T Do:**
- ❌ Import API request/response classes
- ❌ Know about HTTP status codes
- ❌ Handle DTO mapping
- ❌ Access `HttpServletRequest` or similar web constructs

### Repository Layer (Data Access)
**Responsibilities:**
- Data access operations
- Custom queries

Standard Spring Data JPA repositories.

## Why This Pattern?

### 1. Service Reusability
Services can be called from multiple contexts without modification:

#### REST API
```java
@PostMapping("/sales/{id}/refund")
public RefundResponse refund(@PathVariable Long id, 
                              @RequestBody RefundRequest request) {
  var sale = saleRepository.findById(id)
      .orElseThrow(() -> new ResourceNotFoundException("Sale not found"));
  
  var refunded = paymentService.refundSale(sale, request.getAmount());
  return mapper.toResponse(refunded);
}
```

#### Message Queue Consumer
```java
@RabbitListener(queues = "refund-requests")
public void handleRefundMessage(RefundMessage message) {
  var sale = saleRepository.findById(message.getSaleId())
      .orElseThrow(() -> new IllegalStateException("Sale not found"));
  
  // Same service, different trigger
  paymentService.refundSale(sale, message.getAmount());
}
```

#### Scheduled Batch Job
```java
@Scheduled(cron = "0 0 2 * * *")
public void processAutoRefunds() {
  var eligibleSales = saleRepository.findEligibleForAutoRefund();
  
  for (var sale : eligibleSales) {
    // Same service, no API DTOs involved
    paymentService.refundSale(sale, sale.getTotalAmount());
  }
}
```

#### Internal Service Call
```java
@Service
public class SubscriptionService {
  
  @Autowired private PaymentService paymentService;
  @Autowired private SaleRepository saleRepository;
  
  public void cancelSubscription(Subscription subscription) {
    var lastPayment = saleRepository.findLastPaymentForSubscription(subscription.getId());
    
    if (lastPayment != null) {
      // Direct service-to-service call with entities
      paymentService.refundSale(lastPayment, lastPayment.getTotalAmount());
    }
    
    subscription.setStatus(SubscriptionStatus.CANCELLED);
  }
}
```

### 2. API Versioning Flexibility
Different API versions can use the same service with different DTOs:

```java
// v1 API
@PostMapping("/v1/sales/{id}/refund")
public RefundResponseV1 refundV1(@PathVariable Long id, 
                                  @RequestBody RefundRequestV1 request) {
  var sale = saleRepository.findById(id)
      .orElseThrow(() -> new ResourceNotFoundException("Sale not found"));
  
  var refunded = paymentService.refundSale(sale, request.getAmount());
  return mapperV1.toResponse(refunded);
}

// v2 API - different DTO structure, same service
@PostMapping("/v2/sales/{id}/refund")
public RefundResponseV2 refundV2(@PathVariable Long id, 
                                  @RequestBody RefundRequestV2 request) {
  var sale = saleRepository.findById(id)
      .orElseThrow(() -> new ResourceNotFoundException("Sale not found"));
  
  // Same service call, different mapping
  var refunded = paymentService.refundSale(sale, request.getRefundAmount());
  return mapperV2.toResponse(refunded);
}
```

### 3. Clear Dependency Direction
```
api (requests/responses)
  ↓ depends on
domain (entities)
  ↓ depends on  
service (business logic)
  ↓ depends on
repository (data access)
```

Services never depend on the API layer, making them truly reusable.

### 4. Improved Testability

**Service tests** have no HTTP/API concerns:
```java
@Test
void refundSale_whenAmountValid_processesRefund() {
  // Arrange
  var sale = createTestSale();
  var refundAmount = new BigDecimal("50.00");
  
  // Act
  var refunded = paymentService.refundSale(sale, refundAmount);
  
  // Assert
  assertThat(refunded.getStatus()).isEqualTo(SaleStatus.REFUNDED);
  assertThat(refunded.getRefundedAmount()).isEqualTo(refundAmount);
  verify(paymentGateway).processRefund(any(), eq(refundAmount));
}
```

**Controller tests** focus on HTTP/mapping concerns:
```java
@Test
void refund_whenSaleNotFound_returns404() {
  when(saleRepository.findById(999L)).thenReturn(Optional.empty());
  
  mockMvc.perform(post("/sales/999/refund")
      .contentType(MediaType.APPLICATION_JSON)
      .content("{\"amount\": 50.00}"))
      .andExpect(status().isNotFound());
  
  verify(paymentService, never()).refundSale(any(), any());
}
```

### 5. Domain-Driven Design
Service method signatures use **domain language**, not API language:

```java
// ✅ Domain-focused signature
public Sale refundSale(Sale sale, BigDecimal amount)

// ❌ API-coupled signature  
public RefundResponse refundSale(Long saleId, RefundRequest request)
```

## Mapping Strategy

### Use MapStruct for DTO ↔ Entity Mapping

```kotlin
// build.gradle.kts
dependencies {
    implementation("org.mapstruct:mapstruct:1.6.3")
    annotationProcessor("org.mapstruct:mapstruct-processor:1.6.3")
}
```

```java
@Mapper(componentModel = "spring")
public interface CustomerMapper {
  
  // Update existing entity from request
  @Mapping(target = "id", ignore = true)
  @Mapping(target = "createdAt", ignore = true)
  void updateFromRequest(CustomerRequest request, @MappingTarget Customer customer);
  
  // Map entity to response
  CustomerResponse toResponse(Customer customer);
  
  // Complex mapping example
  @Mapping(target = "fullName", expression = "java(customer.getFirstName() + ' ' + customer.getLastName())")
  @Mapping(target = "accountAge", expression = "java(java.time.Period.between(customer.getCreatedAt().toLocalDate(), java.time.LocalDate.now()).getYears())")
  CustomerDetailResponse toDetailResponse(Customer customer);
}
```

**Why MapStruct?**
- Compile-time code generation (no reflection)
- Type-safe
- Reduces boilerplate
- Easy to customize complex mappings

## Common Questions

### Q: Isn't accessing repositories in controllers an anti-pattern?

**A:** In this pattern, controllers only use `repository.findById(id)` for **entity resolution**, not business logic. This is bounded and intentional.

**Allowed in controllers:**
```java
✅ var customer = customerRepository.findById(id)
      .orElseThrow(() -> new ResourceNotFoundException("Customer not found"));
```

**NOT allowed in controllers:**
```java
❌ List<Customer> customers = customerRepository.findByDateRange(start, end);
❌ Customer customer = customerRepository.findByIdWithOrdersAndPayments(id);
❌ boolean exists = customerRepository.existsByEmail(email);
```

Complex queries, joins, and business-related lookups belong in the service layer.

### Q: Why not create `service.get(id)` methods to avoid repository access in controllers?

**A:** This creates unnecessary indirection:

```java
// Adding a pointless pass-through method
@Service
public class CustomerService {
  public Customer get(Long id) {
    return customerRepository.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("Customer not found"));
  }
}
```

This adds no value and makes code harder to follow. Entity resolution by ID is **plumbing**, not business logic.

### Q: What about PATCH requests (partial updates)?

**A:** PATCH requests work fine with this pattern:

```java
@PatchMapping("/{id}")
public CustomerResponse partialUpdate(@PathVariable Long id,
                                       @RequestBody Map<String, Object> updates) {
  var customer = customerRepository.findById(id)
      .orElseThrow(() -> new ResourceNotFoundException("Customer not found"));
  
  // Apply only provided fields
  customerMapper.applyPartialUpdate(updates, customer);
  
  var updated = customerService.update(customer);
  return customerMapper.toResponse(updated);
}
```

Or use a dedicated partial update DTO:
```java
@PatchMapping("/{id}")
public CustomerResponse partialUpdate(@PathVariable Long id,
                                       @RequestBody CustomerPatchRequest request) {
  var customer = customerRepository.findById(id)
      .orElseThrow(() -> new ResourceNotFoundException("Customer not found"));
  
  customerMapper.applyPartialUpdate(request, customer);
  
  var updated = customerService.update(customer);
  return customerMapper.toResponse(updated);
}
```

### Q: Where does business validation belong?

**A:** Always in the service layer.

```java
// Controller - only bean validation
@PostMapping
public CustomerResponse create(@Valid @RequestBody CustomerRequest request) {
  var customer = customerMapper.toEntity(request);
  var created = customerService.create(customer);
  return customerMapper.toResponse(created);
}

// Service - business validation
@Service
public class CustomerService {
  public Customer create(Customer customer) {
    // Business rules
    if (customerRepository.existsByEmail(customer.getEmail())) {
      throw new DuplicateEmailException("Email already registered");
    }
    
    if (customer.getAge() < 18 && customer.getAccountType() == AccountType.PREMIUM) {
      throw new BusinessRuleException("Premium accounts require age 18+");
    }
    
    return customerRepository.save(customer);
  }
}
```

## Exception Handling Strategy

### Controller-Level Exceptions
- `InvalidRequestException` - Entity not found by ID (400)
- `ResourceNotFoundException` - Entity not found by ID (404)

### Service-Level Exceptions
- `BusinessException` - Generic business rule violation (422)
- `ServiceUnavailableException` - External system failure (502)

### Global Exception Handler
```java
@RestControllerAdvice
public class GlobalExceptionHandler {
  
  @ExceptionHandler(ResourceNotFoundException.class)
  @ResponseStatus(HttpStatus.NOT_FOUND)
  public ApiErrorResponse handleNotFound(ResourceNotFoundException ex) {
    return new ApiErrorResponse("not_found", ex.getMessage());
  }
  
  @ExceptionHandler(BusinessRuleException.class)
  @ResponseStatus(HttpStatus.UNPROCESSABLE_ENTITY)
  public ApiErrorResponse handleBusinessRule(BusinessRuleException ex) {
    return new ApiErrorResponse("business_rule_violation", ex.getMessage());
  }
}
```

## When to Use This Pattern
- Microservices with multiple integration points (REST, messaging, jobs)
- Applications requiring API versioning
- Domain-driven design approach
- Services that need to be called from multiple contexts

## Summary

This architectural pattern provides:

1. **Service Reusability** - Services work across REST APIs, message queues, scheduled jobs, and internal calls
2. **Clean Separation** - Each layer has a single, well-defined responsibility
3. **Testability** - Business logic can be tested independently of HTTP concerns
4. **Maintainability** - Changes to API contracts don't affect business logic
5. **API Versioning** - Multiple API versions can use the same services

The key insight: **API DTOs are serialization formats, not domain objects.** Keep them in the presentation layer where they belong.
