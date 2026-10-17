# Auth0 Findings

**Date:** 2026-04-17
**Status:** Historical OCI research with retained provider-neutral conclusions

OCI is retired and no production environment or production identity-provider
tenant is currently configured. Do not use the former demo custom-domain, DNS,
OCI Vault, or secret-sync steps as deployment guidance. The lean archive,
complete-tree Git provenance, and restoration caveats live in
[`archive/oci/README.md`](../../archive/oci/README.md).

The durable findings are:

- Browser clients use OAuth2/OIDC through Session Gateway; tokens do not belong
  in the SPA.
- Local development and any future hosted environment need separate registered
  callback, logout, and origin URLs even if a constrained Auth0 plan requires
  them to share one tenant.
- `https://api.budgetanalyzer.org` is the existing API audience identifier. It
  is an identifier, not evidence of a live API endpoint.
- Issuer, client id, client secret, callback URLs, and logout return URLs are
  environment-specific inputs. A future deployment must select and verify them
  rather than inheriting the retired values.
- Client secrets must remain outside Git and agent-visible production
  workflows. The active security boundary is documented in
  [`autonomous-ai-execution.md`](../architecture/autonomous-ai-execution.md).

Use [`docs/setup/auth0-setup.md`](../setup/auth0-setup.md) for the supported
local Auth0 setup and
[`session-edge-authorization-pattern.md`](../architecture/session-edge-authorization-pattern.md)
for the browser session contract. The maintained production reference retains
historical hostname and issuer values only as labeled, non-secret offline render
inputs; see [`deploy/README.md`](../../deploy/README.md).
