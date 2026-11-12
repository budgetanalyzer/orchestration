# Audit scope docs omit Spring Security filter-chain rejections

- **Severity:** Low (documentation)
- **Owner:** orchestration docs; service-common docs
- **Status:** Open
- **Source:** 2026-11-09 independent implementation review C8

## Problem

Servlet audit events come from service-common's `AuditRequestInterceptor`
(`../service-common/service-web/src/main/java/org/budgetanalyzer/service/servlet/audit/AuditRequestInterceptor.java`),
which is an MVC interceptor. Requests rejected in the Spring Security filter
chain never reach it and are not audited.

`docs/architecture/security-architecture.md:773-777` says servlet services
audit "every mapped `POST`, `PUT`, `PATCH` and `DELETE`, emitted once after
completion with the actual response status." That reads as if filter-chain
rejections are included.

The behavior matches the intended scope; only the wording is inaccurate.

## Proposed fix

State in `security-architecture.md`, and in service-common's structured audit
events section if it has the same gap, that requests rejected before handler
dispatch (Spring Security filter chain) are not audited.

## Acceptance

Both docs describe the interceptor boundary explicitly.
