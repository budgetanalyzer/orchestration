# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Budget Analyzer, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, email **security@budgetanalyzer.ai** with:

1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Any suggested fixes (optional)

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 1 week
- **Resolution timeline**: Depends on severity, typically 30-90 days

## Scope

This policy applies to all repositories in the Budget Analyzer organization:

- orchestration
- session-gateway
- token-validation-service
- transaction-service
- currency-service
- permission-service
- budget-analyzer-web
- service-common

## Security Architecture

Budget Analyzer implements defense-in-depth security patterns. For details, see:

- [Security Architecture](docs/architecture/security-architecture.md)
- [BFF Security Benefits](docs/architecture/bff-security-benefits.md)

## Supported Versions

We provide security updates for the latest release only. This is a reference architecture, not production software with LTS guarantees.

## Recognition

We appreciate security researchers who help keep Budget Analyzer secure. With your permission, we'll acknowledge your contribution in our release notes.
