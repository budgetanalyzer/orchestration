# Documentation Ownership

**Status:** Active
**Purpose:** Define the canonical owner for recurring documentation topics so
exact operational detail lives in one place and non-owner docs summarize and
link instead of copying.

## Rules

- One recurring topic should have one canonical owner.
- Non-owner docs may give a short summary, orientation paragraph, or diagram,
  but they should not own the full command sequence, table, or contract.
- When a topic changes, update the owner doc first, then update summaries,
  indexes, and cross-links that point to it.
- `docs/archive/` is historical reference only and does not own active
  implementation detail.
- If no existing owner fits a new recurring topic, choose one and update this
  file in the same change.

## Exact Detail vs. Summary

In this repo, "exact detail" includes things such as:

- full startup and verifier sequences
- complete port tables
- observability access commands
- detailed route ownership lists
- detailed `/api-docs` behavior and output definitions

Those details should live in the owner doc. Non-owner docs can summarize the
shape of the topic and link outward.

## Ownership Map

| Topic | Canonical owner | Rule for non-owner docs |
| --- | --- | --- |
| Documentation ownership policy | [docs/OWNERSHIP.md](OWNERSHIP.md) | Link here instead of restating the full ownership map. |
| AI instructions and repo guardrails | [AGENTS.md](../AGENTS.md) | Other docs may describe the repo, but agent instructions and repo-operating constraints belong there. |
| Reusable `AGENTS.md` authoring standard | [docs/agents-md-checkstyle.md](agents-md-checkstyle.md) | Link here instead of restating the pattern-based authoring rules. |
| Supported local happy path | [docs/development/getting-started.md](development/getting-started.md) | Point readers there instead of repeating the full supported setup flow. |
| Local environment mechanics and live-update internals | [docs/development/local-environment.md](development/local-environment.md) | Keep implementation detail there; summarize elsewhere. |
| Manual Tilt/Kind bootstrap internals | [docs/tilt-kind-setup-guide.md](tilt-kind-setup-guide.md) | Treat it as a manual/deep-dive reference, not a competing default path. |
| High-level system orientation | [docs/architecture/system-overview.md](architecture/system-overview.md) | Keep this high level and defer exact contracts to the topic owners below. |
| Browser request flow and shared session contract | [docs/architecture/session-edge-authorization-pattern.md](architecture/session-edge-authorization-pattern.md) | Other docs may summarize the flow, but detailed route ownership and session contract behavior belong there. |
| Security controls and layered posture | [docs/architecture/security-architecture.md](architecture/security-architecture.md) | Link there for detailed control rationale and layered defenses. |
| Ports and service exposure | [docs/architecture/port-reference.md](architecture/port-reference.md) | Do not maintain competing port tables elsewhere. |
| Observability access model and operator entry points | [docs/architecture/observability.md](architecture/observability.md) | Keep exact access posture and port-forward commands there. |
| Resource-routing authoring and NGINX route work | [nginx/README.md](../nginx/README.md) | Architecture docs may reference the pattern, but NGINX route authoring detail belongs there. |
| Script catalog and verifier entry points | [scripts/README.md](../scripts/README.md) | Other docs may call out specific scripts, but the script tree map and canonical entry points belong there. |
| Unified API docs surface (`/api-docs`) | [docs-aggregator/README.md](../docs-aggregator/README.md) | Keep exact route behavior, generated outputs, and docs-surface details there. |

## `AGENTS.md` Special Case

`AGENTS.md` is intentionally rich direct AI context. It is the canonical source
for repo guardrails, execution constraints, and orchestration-specific working
rules.

It is not the canonical owner for every exact operational detail it mentions.
When `AGENTS.md` references setup flows, ports, observability access, routing,
or `/api-docs` behavior, prefer a stable summary plus a pointer to the owner
doc above instead of maintaining a second full inventory there.

## Maintenance Workflow

When a recurring topic changes:

1. Update the canonical owner doc first.
2. Update summaries, indexes, and cross-links that mention the topic.
3. Remove or shorten any duplicated exact detail that now conflicts with the
   owner doc.
4. If ownership changed, update this file in the same change.
