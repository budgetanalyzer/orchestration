# Runbooks

Operational guides for debugging and troubleshooting the Budget Analyzer development environment.

## Available Runbooks

| Runbook | Description | When to Use |
|---------|-------------|-------------|
| [Tilt Debugging](tilt-debugging.md) | Debug Tilt/Kind local development environment | Services not starting, auth failures, network issues |

## Runbook Philosophy

These runbooks follow a **decision tree approach**:
1. Start with the symptom you're seeing
2. Follow the diagnostic steps
3. Each step either resolves the issue or points to the next diagnostic

## Quick Links

### Tilt Development
- **Tilt UI**: http://localhost:10350
- **App URL**: https://app.budgetanalyzer.localhost
- **API URL**: https://api.budgetanalyzer.localhost

### Related Documentation
- [Tilt Kind Setup Guide](../tilt-kind-setup-guide.md) - Initial setup instructions
- [NGINX Gateway README](../../nginx/README.md) - Routing configuration
- [CLAUDE.md](../../CLAUDE.md) - Architecture overview

## Contributing

When adding new runbooks:
1. Use the existing runbook as a template
2. Include a quick reference section at the top
3. Organize by symptom, not by component
4. Include actual commands that can be copy-pasted
5. Add the runbook to the table above
