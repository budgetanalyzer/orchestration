# Frontend session-expiry warning edge cases

- **Severity:** Low (UX only; the server enforces expiry)
- **Owner:** budget-analyzer-web
- **Status:** Open
- **Source:** [review](../research/security-hardening-implementation-review-2026-11-09.md)
  O3

## Problem

Two issues, both found by reading the source and not tested in a browser:

1. **Absolute cap inferred from timing.**
   `../budget-analyzer-web/src/hooks/useSessionHeartbeat.ts` decides a session
   can't be extended when a fresh expiry falls inside the warning window. With
   a 15-minute TTL and a 2-minute warning this works as a heuristic, but the
   server never says so explicitly. The warning timer changes only
   `showWarning`. An inactive user whose last capped response arrived before
   the window can still see the "Continue" inactivity wording.
2. **No auto-logout when the modal opens at zero.**
   `../budget-analyzer-web/src/components/InactivityWarningModal.tsx:36-46`
   sets `countdownReady` only after a positive countdown. If a suspended tab
   resumes after expiry and the modal first renders at zero, auto-logout never
   fires. Whether this happens depends on the first value `useCountdown`
   returns, which has not been checked.

## Proposed fix

- Make countdown initialization explicit, so that opening at zero logs out.
- Either keep the warning wording neutral, or return a small explicit
  cap/extension field from the heartbeat response.
- Do not add a client-side session state machine.

## Acceptance

- A modal that first renders with an expiry already in the past submits
  logout.
- A capped session never shows "Continue" wording.
