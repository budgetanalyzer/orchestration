# CSP renderer validates issuer parts it never emits

- **Severity:** Info (maintenance)
- **Owner:** orchestration
- **Status:** Leave unless the renderer is otherwise being changed
- **Source:** [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  O4

## Observation

`issuer_origin` (`deploy/scripts/render/render-csp.py:17-44`) validates the
issuer's path, percent escapes and IPv6 zone identifiers, although only
`scheme://host[:port]` is emitted. The input is operator configuration, not
attacker input. `scripts/guardrails/verify-edge-headers.py:41-45` carries 19
invalid-issuer cases, several of which exercise those branches.

## Assessment

The review suggests keeping the HTTPS, hostname, port and unsafe-header-
character checks and dropping the path checks and their cases. That is
reasonable, but it removes working validation without fixing a defect.
Do it only when the renderer is being touched for another reason.
