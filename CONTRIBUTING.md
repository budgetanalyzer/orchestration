# Contributing to Budget Analyzer

Budget Analyzer is a reference architecture for enterprise architects and senior developers. We welcome contributions that improve the patterns, documentation, or implementation.

## Philosophy

- **Minimal and simple** - Less is more. Avoid over-engineering.
- **Clone and play** - The system should work out of the box with minimal setup.
- **Production parity** - Development environment mirrors production.

## Getting Started

1. Clone all repositories side-by-side in a common parent directory
2. Follow the setup in the [orchestration README](README.md)
3. Run `tilt up` and you're coding

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
