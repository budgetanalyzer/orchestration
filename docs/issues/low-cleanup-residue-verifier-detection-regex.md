# Residue cleanup detects running verifiers with a command-line regex

- **Severity:** Low
- **Owner:** orchestration
- **Status:** Open. This is follow-up work next to the hardening plans, not an unmet plan requirement.
- **Source:** 2026-11-09 implementation review O2
- **Related:** [edge verifier deletes existing load-test fixture](medium-edge-verifier-deletes-existing-loadtest-fixture.md)

## Problem

`scripts/smoketest/cleanup-smoketest-residue.sh:575-577` decides whether a
verifier is running with:

```bash
pgrep -u "$(id -u)" -a -f '^[^ ]*bash [^ ]*smoketest/verify-[a-z0-9-]+\.sh'
```

It recognizes the documented root-relative invocation, but not equivalent
forms:

- `bash -x scripts/smoketest/verify-edge-contract.sh` (an option between `bash`
  and the path);
- `./verify-edge-contract.sh` run from `scripts/smoketest/`.

It also cannot exclude a run that starts after the process scan.

Confirmed by reading the source; not tested against live processes.

## Proposed fix

Replace the heuristic with the same lock or run-ownership contract used for
load-test fixture ownership. Do not extend the regex.

## Acceptance

- Cleanup refuses to run while any verifier holds the lock, however that
  verifier was invoked.
- A verifier that starts during cleanup waits or fails instead of racing.
