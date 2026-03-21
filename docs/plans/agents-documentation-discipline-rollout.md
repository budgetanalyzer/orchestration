# AGENTS.md documentation-discipline rollout

## Goal

Add an explicit, imperative instruction to every `AGENTS.md` under `/workspace` stating that documentation must be kept up to date after any configuration or code change.

This should become a cross-repo rule, not an implied convention.

## Scope

Current `AGENTS.md` files in scope:

- `/workspace/architecture-conversations/AGENTS.md`
- `/workspace/budget-analyzer-web/AGENTS.md`
- `/workspace/currency-service/AGENTS.md`
- `/workspace/orchestration/AGENTS.md`
- `/workspace/permission-service/AGENTS.md`
- `/workspace/service-common/AGENTS.md`
- `/workspace/session-gateway/AGENTS.md`
- `/workspace/shopping-claude/AGENTS.md`
- `/workspace/transaction-service/AGENTS.md`
- `/workspace/workspace/AGENTS.md`

## Proposed standard blurb

Insert the same section in every file for consistency:

```md
## Documentation Discipline

Always keep documentation up to date after any configuration or code change.

Update the nearest affected documentation in the same work:
- `AGENTS.md` when instructions, guardrails, discovery commands, or repository-specific workflow changes
- `README.md` when setup, usage, or repository purpose changes
- `docs/` when architecture, configuration, APIs, behaviors, or operational workflows change

Do not leave documentation updates as follow-up work.
```

## Placement strategy

Use a single insertion point across all repositories:

- Insert the new section immediately after `## Code Exploration`

Why this location:

- It is present in all 10 files
- It keeps the rule near other global working instructions
- It avoids burying the requirement deep inside repo-specific sections

## Repo-specific notes

Use the standard blurb everywhere unless a repository needs a small clarification line directly below it.

### `/workspace/architecture-conversations`

- Keep the new blurb, but avoid wording that implies editing historical conversation artifacts.
- If needed, add one clarifier sentence: update operational docs and metadata, not historical conversation content.

### `/workspace/workspace`

- This repo intentionally has little documentation.
- The blurb still applies because configuration changes here affect `.devcontainer`, sandbox behavior, setup instructions, and `AGENTS.md`.

### `/workspace/shopping-claude`

- Keep the same blurb even though this repo is more research-oriented.
- Documentation updates here should cover operational instructions and reference material when workflow or configuration changes.

## Implementation sequence

1. Re-scan `/workspace/*/AGENTS.md` to confirm the target set has not changed.
2. Insert the new `## Documentation Discipline` section after `## Code Exploration` in each file.
3. Check for files that already contain similar documentation-maintenance language and remove only obvious duplication.
4. Keep all existing repo-specific instructions intact.
5. Review each diff for tone consistency and imperative wording.

## Validation

After the edit pass:

1. Run `rg -n "^## Documentation Discipline$" /workspace/*/AGENTS.md` and confirm 10 matches.
2. Run `rg -n "Always keep documentation up to date after any configuration or code change\\." /workspace/*/AGENTS.md` and confirm 10 matches.
3. Spot-check the three special cases:
   - `architecture-conversations` does not conflict with the "do not modify historical artifacts" rule
   - `workspace` still reads coherently despite limited local docs
   - `shopping-claude` still reads coherently despite its non-service role

## Risks

- Duplicating existing guidance in `architecture-conversations` if the new section is added without checking the later "Documentation can change" language.
- Over-specifying `docs/` expectations in repositories where documentation is intentionally thin.
- Inconsistent wording if some files get custom edits instead of the shared section.

## Recommendation

Keep the rollout mechanical:

- one shared blurb
- one shared placement
- only minimal repo-specific clarification where coherence would otherwise break

That gives you a clear cross-workspace norm without turning the change into 10 separate writing tasks.
