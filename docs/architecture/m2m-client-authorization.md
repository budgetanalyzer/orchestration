# Machine-to-Machine (M2M) Client Authorization

**Status:** Superseded. The previous content described a token-exchange flow
(`POST /auth/token/exchange` → Redis session → ext_authz) that has been removed
from Session Gateway. Session Gateway is now explicitly browser-only.

Current state:
- There is no supported M2M authorization path through Session Gateway.
- Internal service-to-service calls rely on Istio mTLS plus NetworkPolicy, with
  one explicit east-west allowance: permission-service may call
  `DELETE /internal/v1/sessions/users/{userId}` on Session Gateway (port 8081)
  for bulk session revocation.
- A future stateless bearer-token lane for external / M2M API access is
  described — as a draft, not architecture of record — in
  [`../plans/stateless-m2m-edge-authorization-plan.md`](../plans/stateless-m2m-edge-authorization-plan.md).

For browser session architecture see
[`security-architecture.md`](security-architecture.md) and
[`session-edge-authorization-pattern.md`](session-edge-authorization-pattern.md).
