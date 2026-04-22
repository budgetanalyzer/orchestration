# Plan: Documentation Ownership And DRY Consolidation

Date: 2026-04-22
Status: Proposed

Related documents:

- `AGENTS.md`
- `README.md`
- `docs/decisions/003-pattern-based-claude-md.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/tilt-kind-setup-guide.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/port-reference.md`
- `docs/architecture/observability.md`
- `nginx/README.md`
- `scripts/README.md`
- `docs-aggregator/README.md`

## Scope

This plan defines how the orchestration repository should move back toward a DRY documentation
model with explicit topic ownership and link-based reuse.

The plan covers:

- adding `docs/OWNERSHIP.md` as the repo-visible documentation ownership map
- reducing repeated exact detail across `README.md`, `docs/`, `nginx/README.md`, and
  `scripts/README.md`
- making only minimal, targeted changes to `AGENTS.md`

The plan does not require a large-scale rewrite of every document in one pass.

## Problem Statement

The current documentation set repeats the same operational facts in too many places:

- local startup and verifier sequences
- browser request flow and route ownership
- shared session contract details
- observability access commands and port-forward rules
- port inventories and service topology summaries
- `/api-docs` behavior and CSP posture

That duplication has already produced drift. One concrete example is the frontend session
heartbeat cadence, which is described as a 2-minute cadence in one architecture document and a
3-minute cadence in others.

The repo already has the correct general policy in `AGENTS.md` and
`docs/decisions/003-pattern-based-claude-md.md`: prefer pattern-based guidance, keep the closest
source of truth, and link instead of copying. This plan exists to apply that policy consistently.

## Constraints

### Preserve Rich AI Context In `AGENTS.md`

`AGENTS.md` is intentionally useful as direct AI context. This plan should not treat aggressive
shrinking of `AGENTS.md` as success.

The working constraint is:

- keep the high-signal orchestration context in `AGENTS.md`
- make only minimal edits there
- prefer adding clearer source-of-truth links and ownership references over removing large sections

### Use Single Owners For Exact Detail

A non-owner document may summarize a topic briefly, but exact operational detail should live in one
canonical place.

Examples of exact detail:

- step-by-step startup sequences
- full verifier inventories
- port tables
- observability access commands
- route ownership lists
- detailed `/api-docs` contract behavior

### Keep Changes Reviewable

The cleanup should be staged so reviewers can see:

- which topic now has a canonical owner
- what text was kept as summary
- what exact detail was moved behind a link

## Goals

1. Add an explicit documentation ownership map in `docs/OWNERSHIP.md`.
2. Establish one canonical owner per recurring topic.
3. Reduce drift by keeping exact commands, tables, and contracts in one place.
4. Preserve `AGENTS.md` as rich AI context while still making drift-prone sections easier to
   maintain.
5. Resolve known contradictions as part of the consolidation pass.

## Non-Goals

- turning `AGENTS.md` into a thin index
- rewriting all documentation to optimize only for token minimization
- removing every repeated mention of a topic
- changing architecture, routing, or runtime behavior as part of the doc cleanup
- editing `docs/archive/` or decision records beyond using them as reference

## Proposed Ownership Model

`docs/OWNERSHIP.md` should become the control surface for documentation ownership.

It should define, at minimum, the following topic owners:

| Topic | Canonical owner | Notes for non-owner docs |
| --- | --- | --- |
| Documentation ownership policy | `docs/OWNERSHIP.md` | Other docs may link to it, not restate the full map |
| Supported local happy path | `docs/development/getting-started.md` | Other docs may point readers there |
| Local environment mechanics and live-update internals | `docs/development/local-environment.md` | Keep implementation detail there |
| Manual Tilt/Kind bootstrap internals | `docs/tilt-kind-setup-guide.md` if retained, otherwise archive or demote it | Do not let it compete with Getting Started |
| Browser request flow and shared session contract | `docs/architecture/session-edge-authorization-pattern.md` | Other architecture docs should summarize and link |
| Security controls and layered posture | `docs/architecture/security-architecture.md` | Keep threat/control detail there |
| Ports and service exposure | `docs/architecture/port-reference.md` | Other docs should not carry their own port tables |
| Observability access model and operator entry points | `docs/architecture/observability.md` | Use one source for port-forward commands and access posture |
| Resource-routing authoring and NGINX route work | `nginx/README.md` | Architecture docs can reference the pattern only |
| Script catalog and verifier entry points | `scripts/README.md` | Other docs can link to targeted scripts |
| Unified API docs surface (`/api-docs`) | `docs-aggregator/README.md` | Keep route behavior and outputs there |

## Allowed Duplication Policy

The repo should follow a stricter distinction between summary and ownership:

- allowed: a short summary, one diagram, or one orientation paragraph in a non-owner doc
- allowed: `AGENTS.md` keeping stable orchestration summaries that are useful in direct AI context
- not allowed: multiple docs each owning the same exact command sequence, port table, or contract
- not allowed: repeating the same detailed route ownership list or observability access instructions
  in several files

The practical rule is:

- summaries can repeat
- exact detail should not

## Planned Change Set

### Phase 1: Add Ownership Map

Create `docs/OWNERSHIP.md` with:

- purpose of the ownership model
- one owner per recurring topic
- a short rule for how non-owner docs may mention that topic
- a maintenance rule that when a topic changes, the owner doc must be updated first

This file should also state explicitly that `AGENTS.md` is a special case:

- it may keep stable AI-valuable context
- it is not the owner for every exact operational detail it mentions

### Phase 2: Normalize The Setup/Workflow Layer

The setup and workflow docs currently overlap too heavily. The target split should be:

- `docs/development/getting-started.md` owns the supported happy path
- `docs/development/local-environment.md` owns how the local environment works
- `docs/tilt-kind-setup-guide.md` either becomes a clearly labeled manual/deep-dive reference or is
  otherwise demoted so it no longer competes with the supported path
- `docs/runbooks/README.md` should link to the active setup sources, not older competing paths

Specific cleanup targets:

- stop repeating the full startup/verifier sequence in several docs
- keep one canonical startup checklist
- keep one canonical explanation of the `service-common` local publication path

### Phase 3: Normalize Architecture Topic Ownership

The architecture layer should be split by responsibility:

- `docs/architecture/system-overview.md` stays high level
- `docs/architecture/session-edge-authorization-pattern.md` owns request flow, route ownership, and
  the shared browser session contract
- `docs/architecture/security-architecture.md` owns security rationale and controls
- `docs/architecture/port-reference.md` owns exact port tables
- `docs/architecture/observability.md` owns exact observability access posture and commands
- `docs-aggregator/README.md` owns `/api-docs` behavior

Specific cleanup targets:

- remove duplicate port tables from non-owner docs
- reduce repeated full request-flow walkthroughs outside the session-edge pattern doc
- reduce repeated observability access command blocks outside the observability doc
- keep `/api-docs` contract detail in one place and link to it elsewhere

### Phase 4: Minimal `AGENTS.md` Pass

`AGENTS.md` should get a constrained cleanup, not a major reduction.

The intended changes are:

- add a clear pointer to `docs/OWNERSHIP.md`
- tighten source-of-truth references where the current text already points outward
- keep the core runtime pattern, repo boundaries, workflow guardrails, and orchestration-specific
  constraints intact
- remove or shorten only the most drift-prone repeated exact detail where the canonical owner is now
  explicit

Examples of what should stay in `AGENTS.md`:

- repository boundaries
- orchestration guardrails
- direct AI execution constraints
- high-level runtime pattern
- high-signal workflow and troubleshooting entry points

Examples of what may be reduced only if needed:

- long repeated observability command inventories
- repeated exact startup/verifier lists that already live elsewhere
- repeated exact route/port inventories when a canonical doc exists

If there is doubt, keep the `AGENTS.md` content and add a source-of-truth link instead of cutting
more.

### Phase 5: Drift Fixes And Link Repair

As the ownership cleanup proceeds, resolve factual inconsistencies that the duplication exposed.

Known examples to verify during implementation:

- frontend heartbeat cadence
- which setup doc is the supported happy path
- where observability access commands are canonical
- where port inventories are canonical

This phase should also update cross-links so indexes and runbooks point to the active owner docs.

## Recommended Implementation Order

1. Add `docs/OWNERSHIP.md`.
2. Update the setup/runbook index layer so readers land in the correct owner docs first.
3. Normalize architecture ownership by topic.
4. Perform the minimal `AGENTS.md` pass last, after the owner docs are already in place.
5. Run a final contradiction and link sweep.

Doing `AGENTS.md` last keeps that diff smaller and makes it easier to preserve context without
guessing what the owner docs will look like.

## Review Heuristics

Reviewers should judge the cleanup using these questions:

- does this topic now have one clear owner?
- does this non-owner doc summarize and link, or is it still trying to own the detail?
- did the change preserve useful AI-facing context in `AGENTS.md`?
- did the cleanup remove an actual drift risk, or just shorten text for its own sake?
- if two docs still mention the topic, is it obvious which one wins when facts change?

## Acceptance Criteria

- `docs/OWNERSHIP.md` exists and names canonical owner docs for the recurring duplicated topics.
- `README.md`, setup docs, architecture docs, and runbook indexes point to the canonical owners.
- `AGENTS.md` remains rich in direct AI context and is changed only minimally.
- exact port tables live only in `docs/architecture/port-reference.md`.
- exact observability access commands live only in `docs/architecture/observability.md`.
- `/api-docs` exact behavior lives only in `docs-aggregator/README.md`.
- the setup docs no longer present multiple competing supported startup paths.
- known contradictions exposed by the scan are resolved.

## Risks

### Risk: Over-thinning `AGENTS.md`

This would reduce useful direct AI context and move too much responsibility onto “when to consult”
behavior.

Mitigation:

- keep `AGENTS.md` high-signal and summary-rich
- only remove exact detail that is both drift-prone and clearly owned elsewhere
- prefer link addition over deletion

### Risk: Creating Ownership But Not Following It

A new ownership file helps only if later edits actually use it.

Mitigation:

- place `docs/OWNERSHIP.md` near the rest of active docs
- reference it from `AGENTS.md` and relevant indexes
- treat owner-first updates as part of review expectations

### Risk: Moving Content Without Resolving Contradictions

That would preserve drift under a cleaner file layout.

Mitigation:

- use the consolidation pass to resolve conflicting facts
- explicitly verify known contradiction hotspots during implementation

## Follow-Up

After the initial cleanup, consider adding a lightweight documentation review checklist for future
changes:

- does this topic already have an owner?
- should this text be a summary with a link instead?
- are we copying exact commands or tables from another active doc?
- if `AGENTS.md` is touched, are we adding clarity without unnecessarily removing useful context?
