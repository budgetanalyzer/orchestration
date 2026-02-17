# Budget Analyzer Authentication - Testing & Production Plan

**Version:** 1.0
**Date:** November 24, 2025
**Status:** In Progress - Phase 6 Testing (Tasks 6.3-6.5)

**Previous Work:** Phases 1-6.2 completed and archived in `docs/archive/authentication-implementation-plan-ARCHIVE.md`

---

## Overview

This plan covers the remaining testing, validation, and production hardening tasks for the Budget Analyzer authentication system.

### Completed (Archived)
- ✅ Phase 1: Infrastructure Setup
- ✅ Phase 2: Session Gateway Implementation
- ✅ Phase 3: NGINX Configuration
- ✅ Phase 4: Backend Service Authorization
- ✅ Phase 5: React Frontend Integration
- ✅ Phase 6.1: Test OAuth Flow
- ✅ Phase 6.2: Test JWT Validation

---

## Phase 6: Testing & Validation (Continued)

### Task 6.3: Test Token Refresh
- Wait until token near expiration (or mock expiration)
- Verify Session Gateway refreshes automatically
- Verify user session continues without interruption
- Test refresh token rotation

### Task 6.4: Test Data-Level Authorization
- Create two test users in Auth0
- User A creates transaction
- User B attempts to access User A's transaction (should fail 403)
- Verify service layer enforces user_id scoping

### Task 6.5: Test Edge Cases
- Test concurrent requests during token refresh
- Test session timeout (30 min idle)
- Test rate limiting triggers 429
- Test same-origin enforcement (all requests through Session Gateway)
- Load test with realistic user patterns
- Test M2M client flow (direct NGINX access with Client Credentials)

---

## Phase 7: Service-to-Service Auth Design (Future - No Implementation Yet)

**NOTE:** No service-to-service traffic currently exists. This phase is design-only to ensure current implementation doesn't preclude future requirements.

### Task 7.1: Document Service-to-Service Strategy
- Document OAuth2 Client Credentials flow for future
- Document mTLS layer for future (manual → Linkerd)
- Create architecture diagram showing future state
- No code implementation - just design documentation

### Task 7.2: Design Client Credentials Flow
- Document how services will register as OAuth2 clients in Auth0
- Define scopes for service-to-service calls (e.g., currency:read)
- Document Spring Boot OAuth2 client configuration (for future)
- Document RestClient configuration with OAuth2 interceptor (for future)

### Task 7.3: Design mTLS Layer
- Document manual mTLS approach for initial implementation
- Document certificate generation process (CA, service certs)
- Document Spring Boot mTLS configuration
- Document NGINX mTLS configuration
- Create certificate rotation runbook

### Task 7.4: Design Linkerd Migration Path
- Document when to migrate to Linkerd (5+ services, Kubernetes production)
- Document Linkerd installation process
- Document service injection strategy
- Document automatic mTLS verification
- Note: Linkerd is FREE (open source), no license costs

### Task 7.5: Update Security Architecture Document
- Add service-to-service section with layered approach (mTLS + OAuth2)
- Document defense-in-depth: transport layer (mTLS) + application layer (OAuth2)
- Add decision log for future service-to-service implementation
- Document that implementation is deferred until needed

---

## Phase 8: Production Hardening

### Task 8.1: Enable HTTPS and Load Balancer Configuration
- **Load Balancer Setup**:
  - Configure GCP Load Balancer (or AWS ALB) on port 80/443
  - SSL/TLS termination at load balancer
  - Generate SSL certificates (Let's Encrypt or GCP-managed certificates)
- **Two Entry Points**:
  - `budgetanalyzer.com` → Load Balancer → Session Gateway (8081) - for web browsers
  - `api.budgetanalyzer.com` → Load Balancer → NGINX (8080) - for M2M clients
- **Internal Service Configuration**:
  - Session Gateway remains on port 8081 (internal)
  - NGINX remains on port 8080 (internal)
  - No port 80 conflict - load balancer handles external ports
- **Security Headers**:
  - Enable HSTS headers at load balancer or NGINX
  - Configure Secure flag on session cookies (HTTPS only)

### Task 8.2: Implement Monitoring
- Add metrics for Session Gateway (active sessions, token refresh rate)
- Add metrics for NGINX (request rate, error rate, latency)
- Add metrics for Token Validation Service (validation failures)
- Add audit logging for authentication events
- Set up alerting thresholds

### Task 8.3: Implement Audit Logging
- Log all login/logout events
- Log all authorization failures (401, 403)
- Log sensitive data access (with user context)
- Use structured JSON logging format
- Configure log retention policies

### Task 8.4: Security Review
- Review token lifetimes (access: 15-30 min, refresh: 8 hours)
- Review session configuration (HttpOnly, Secure, SameSite)
- Review same-origin enforcement (Session Gateway entry point)
- Review rate limiting rules
- Review NGINX security headers
- Review M2M client access controls

### Task 8.5: Documentation
- Document architecture for team
- Create runbooks for common operations
- Document troubleshooting guides
- Document Auth0 configuration
- Document local development setup

---

## Success Criteria

### Phase 6 (Testing)
- [ ] Token refresh happens automatically before expiration
- [ ] Users cannot access other users' data (403)
- [ ] Rate limiting triggers 429 on abuse
- [ ] Session timeout works correctly
- [ ] M2M client flow works

### Phase 7 (Design Only)
- [ ] Service-to-service authentication strategy documented
- [ ] OAuth2 Client Credentials flow designed
- [ ] mTLS implementation approach documented
- [ ] Linkerd migration path defined
- [ ] No breaking changes to current implementation

### Phase 8 (Production Ready)
- [ ] HTTPS enabled everywhere
- [ ] Monitoring and alerting configured
- [ ] Audit logs capture all security events
- [ ] Security review completed
- [ ] Documentation complete
- [ ] Load testing validates performance

---

## References

- [security-architecture.md](../architecture/security-architecture.md) - Overall security design
- [authentication-implementation-plan-ARCHIVE.md](../archive/authentication-implementation-plan-ARCHIVE.md) - Completed phases 1-6.2

---

**End of Document**
