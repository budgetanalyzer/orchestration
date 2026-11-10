# Aggregate smoketest runs the static security suite twice

- **Severity:** Low
- **Owner:** orchestration
- **Status:** Open
- **Source:** [review](../research/security-hardening-implementation-review-2026-11-09.md)
  O1; [independent review](../research/security-hardening-implementation-review-independent-2026-11-09.md)
  O7

## Problem

`scripts/smoketest/smoketest.sh:115-116` runs
`scripts/guardrails/verify-static-security-manifests.sh`. Later the same run
invokes `scripts/smoketest/verify-security-guardrails.sh`, which runs the
static suite again (`STATIC_GATE`, `:10`) before its runtime and edge steps.

The static suite does schema, linter and admission checks plus Helm and
Kustomize rendering, so running it twice is noticeably slow.

## Proposed fix

Keep `verify-security-guardrails.sh` self-contained when run on its own. Have
the aggregate run each of the static, runtime and edge steps exactly once, for
example by letting the aggregate skip the wrapper's static step. Do not add a
result cache or an execution framework.

## Acceptance

- One aggregate run executes the static suite exactly once.
- A standalone `verify-security-guardrails.sh` run still includes the static
  suite.
