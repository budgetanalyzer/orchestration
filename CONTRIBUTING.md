# Contributing to Budget Analyzer

Budget Analyzer is a reference architecture for enterprise architects and senior developers. This project has reached its intended scope - we're now focused on architectural discussions rather than new features.

## What We're Looking For

**High value contributions:**
- Documentation improvements and clarifications
- Architectural discussions (open an Issue or Discussion)
- Bug fixes in existing functionality
- Pattern explanations that help other architects

**Out of scope:**
- New features or services
- Multi-tenancy / organization isolation

## Philosophy

- **Minimal and simple** - Less is more. Avoid over-engineering.
- **Clone and play** - The system should work out of the box with minimal setup.
- **Production parity** - Development environment mirrors production.
- **Discussion over code** - We'd rather talk about patterns than generate more code.

## Getting Started

1. Clone the application repositories side by side under one parent directory.
2. Follow orchestration's [Getting Started guide](docs/development/getting-started.md)
   to install local prerequisites, prepare ingress TLS, bootstrap the
   application and use the daily `tilt up` startup.
3. Use the optional workspace
   [development VM workflow](../workspace/docs/host-isolation.md) when you want
   the project's managed VM, agent tooling or personal-host tunnel.

The orchestration first-bootstrap command recreates Kind with the required
Calico configuration; do not delete or replace the cluster outside that
workflow.

> **Note**: Orchestration does not require a specific editor. VS Code Remote
> SSH is a documented and tested option for the workspace development VM.
> Other editors and terminals may use orchestration's self-contained local
> application workflow.

## How to Contribute

### Reporting Issues

- Use GitHub Issues in the appropriate repository
- Include steps to reproduce, expected behavior, and actual behavior
- For security vulnerabilities, see [SECURITY.md](SECURITY.md)

### Pull Requests

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes with clear commit messages
4. Ensure tests pass and the build succeeds
5. Submit a PR with a description of what and why

### Code Style

- **Java**: Follow existing patterns in service-common
- **React**: Follow existing patterns in budget-analyzer-web
- **Documentation**: Keep it concise and actionable

## Architecture Decisions

Major changes should be documented as Architecture Decision Records (ADRs) in `docs/decisions/`. Use the [template](docs/decisions/template.md).

## Questions?

Open a GitHub Discussion or Issue. We're happy to help architects understand and adapt these patterns.
