# AGENTS.md Checkstyle

**Status:** Active
**Purpose:** Provide reusable rules for writing `AGENTS.md` files that help
AI coding agents work safely and accurately without creating documentation
drift.

Use this document as a public reference when creating or reviewing an
`AGENTS.md` file in any repository:

```text
Inspect this repository and generate an AGENTS.md file using the guidelines in
budgetanalyzer/orchestration/docs/agents-md-checkstyle.md.
```

For remote use, point agents at:
https://github.com/budgetanalyzer/orchestration/blob/main/docs/agents-md-checkstyle.md

## Core Standard

An `AGENTS.md` file is an operating contract for coding agents. It should teach
the agent how to work in the repository, where to find current truth, what it
may change, what it must not change, and how to verify work.

It should not become a stale inventory of services, classes, endpoints, ports,
dependency versions, or setup steps that already have a closer source of truth.

The durable pattern is:

```text
Stable rule + discovery command + source-of-truth pointer
```

Prefer this:

````markdown
Service manifests live under kubernetes/services/. Discover them with:

```bash
find kubernetes/services -maxdepth 2 -type f | sort
```

Exact ports and exposure rules live in docs/architecture/port-reference.md.
````

Avoid this:

```markdown
Services:
- transaction-service on port 8082
- currency-service on port 8084
- permission-service on port 8086
```

The first form survives refactoring. The second form drifts.

## Preservation Rule

When tightening or refactoring an existing `AGENTS.md`, preserve unique
information. Do not remove a rule, guardrail, workflow, boundary, or operating
constraint unless one of these is true:

- The same meaning is preserved in the rewritten `AGENTS.md`.
- The information is moved to a clearly named, closer source-of-truth document
  and `AGENTS.md` now points to it.
- The rule is genuinely obsolete for the current repository, and the rewrite
  says so intentionally rather than deleting it silently.

Treat deletion as the last option, not the default cleanup action.

Do not equate "shorter" with "better." If a section contains non-duplicated
repo-specific guidance, keep it or re-home it before removing it.

Example:

```markdown
Keep this kind of direct guardrail if no closer owner doc exists:

## Git Safety

Never run git write commands such as `commit`, `push`, `checkout`, `reset`, or
branch manipulation unless explicitly requested.
```

If you replace a concrete section with a pointer, verify the pointer actually
owns the full instruction. Do not replace unique guidance with an empty link.

## Consultation Trigger Pattern

Important pointers should explain when an agent should read the referenced
file. A path alone says where detail exists; a consultation trigger tells the
agent when to spend context on that detail.

The trigger does not need to be a literal `When to consult` block. It can be an
inline rule, a section-level bullet list, or a short imperative sentence. Use
the block form when several related triggers need to be grouped together.

Use this pattern for source-of-truth docs, config files, runbooks, generated
artifacts, and decision records:

```text
Topic summary:
- Stable rule or short orientation.
- Current details live in <path>.
- Trigger: read <path> when <specific task or failure mode applies>.
```

Good forms:

```markdown
Before writing or modifying Java code, read
docs/code-quality-standards.md. Do not skip this step.
```

```markdown
For comprehensive testing strategies, read docs/testing-patterns.md when
writing tests.
```

```markdown
API routes are resource-based and should stay decoupled from service names.
Current gateway routes live in nginx/nginx.k8s.conf.

When to consult nginx/nginx.k8s.conf:
- Adding or changing a public `/api/...` route.
- Debugging a request that reaches the SPA instead of a backend.
- Verifying local and production gateway parity.
```

Avoid this:

```markdown
See nginx/nginx.k8s.conf for routes.
```

Good triggers are action-oriented:

- Before changing setup, read the getting-started or bootstrap docs.
- Before changing public APIs, read OpenAPI specs and route ownership docs.
- Before changing deployment, read manifests, overlays, and deployment runbooks.
- Before changing architecture or ownership, read the relevant ADRs and active
  architecture docs.
- When a verifier fails, read the focused troubleshooting runbook before
  inventing a workaround.

Do not add consultation triggers mechanically for every link. Use them for
references where timing matters or where agents are likely to guess instead of
loading the owner doc.

## Imperative Language

Write agent instructions as direct operating rules, not passive descriptions.
Agents follow clear commands better than background prose.

Prefer imperative forms:

```markdown
Before writing or modifying Java code, read docs/code-quality-standards.md.
Run `./gradlew test` before finishing Java changes.
Do not edit generated files directly.
Stop and report missing prerequisites instead of inventing workarounds.
```

Avoid descriptive forms that leave the action implicit:

```markdown
The code-quality standards document contains Java style guidance.
Tests are available through Gradle.
Generated files are usually produced by the build.
Prerequisites may be required.
```

Use `must`, `never`, `always`, `do not`, `before`, `after`, and `when` where
the rule is mandatory. Use `prefer` where the guidance is a default with
legitimate exceptions.

Do not make every sentence forceful. Repository purpose, architecture summaries,
and source-of-truth descriptions can be explanatory. Guardrails, workflows,
validation gates, and consultation triggers should be imperative.

## Rule Set

| ID | Rule | Check |
| --- | --- | --- |
| AG001 | Prefer patterns over inventories. | If adding a list of concrete services, classes, endpoints, ports, or versions, ask whether a command or owner doc can reveal it instead. |
| AG002 | Point to the closest source of truth. | Link to config, manifests, README files, runbooks, OpenAPI specs, package files, or build files instead of copying their exact detail. |
| AG003 | Include discovery commands. | Give `rg`, `find`, `tree`, package-manager, runtime, or framework commands that reveal current state. |
| AG004 | Keep stable guardrails directly in `AGENTS.md`. | Include write boundaries, destructive-command policy, security constraints, validation requirements, and workflow rules that agents must always see. |
| AG005 | Keep volatile details out of `AGENTS.md`. | Do not duplicate full setup flows, generated route maps, dependency tables, class inventories, or API contracts. |
| AG006 | Make repository authority explicit. | State the repo role, scope, read/write permissions, related repos, and ownership boundaries. |
| AG007 | Use prerequisite-first workflows. | Tell agents to check required tools, environment, credentials, and repo-owned setup docs before implementing work. |
| AG008 | Define verification gates. | Name the tests, linters, smoke checks, scripts, or manual checks expected before work is complete. |
| AG009 | Keep paths portable. | Use relative paths or repo-root-relative paths. Avoid machine-specific absolute paths. |
| AG010 | Avoid eager file imports unless intended. | Use plain text paths (`docs/file.md`) or markdown links (`[docs/file.md](docs/file.md)`). In Claude-oriented files, avoid `@path` syntax, which pre-loads content at startup. |
| AG011 | Use hierarchy intentionally. | Put global rules at the repo root and place subtree-specific `AGENTS.md` files near specialized code only when the agent tooling supports hierarchical context. |
| AG012 | Keep active docs separate from history. | Point to active owner docs for implementation work. Mark archives and decision records as context unless they are intentionally active surfaces. |
| AG013 | Preserve useful direct context. | Do not shrink `AGENTS.md` into a bare index. Keep enough high-signal rules for agents to act without rediscovering basic operating constraints. |
| AG014 | Make missing prerequisites explicit. | Tell agents to stop and report missing required tools or environment state rather than inventing workarounds. |
| AG015 | Explain when to update `AGENTS.md`. | Update it for new instructions, guardrails, workflows, or discovery commands, not for every ordinary code or config change. |
| AG016 | Add consultation triggers for important references. | For key docs and config pointers, name the concrete tasks or failure modes that should trigger reading them. Inline guidance is fine; a literal `When to consult` block is optional. |
| AG017 | Use imperative language for agent actions. | Write guardrails, workflows, validation gates, and consultation triggers as direct commands. Avoid passive descriptions when action is required. |
| AG018 | Re-home unique guidance before removing it. | Do not delete repo-specific instructions just to reduce length. Preserve them in `AGENTS.md`, or move them to a real owner doc and leave a pointer. |

## Recommended Structure

Use the sections that fit the repository. Rename them if local terminology is
clearer, but keep the same intent.

### 1. Repository Position

State what the repo is and what authority it has.

Include:

- Archetype, such as application, library, service, orchestration, tooling, or
  documentation.
- Scope, such as one service, one package, a monorepo area, or a whole
  ecosystem.
- Relationships to sibling repos, generated artifacts, deployment repos, or
  shared libraries.
- Read and write boundaries for agents.

Example:

```markdown
## Repository Position

**Archetype:** service
**Scope:** payments API
**Role:** owns payment authorization and capture workflows

### Boundaries
- Read shared contracts from ../service-common.
- Write application code, tests, and docs in this repo.
- Do not change deployment manifests in ../orchestration from this context.
```

### 2. Discovery

Give commands that reveal current structure and runtime state. Discovery
commands are better than static inventories because they remain accurate when
the repository changes.

Common examples:

```bash
# Repo structure
find . -maxdepth 2 -type f | sort
tree -L 2 -I 'node_modules|target|build|dist|.git'

# Text and symbol search
rg -n "pattern"
rg --files

# Build tool state
./gradlew tasks
npm run
go test ./...

# Runtime state
docker compose ps
kubectl get pods -A
```

Only include commands that are relevant to the repo and likely to work in a
normal development environment.

### 3. Source Of Truth

Name canonical docs and files by topic. This lets `AGENTS.md` summarize without
copying. For high-value references, include consultation triggers so the agent
knows when to load the owner doc.

Good source-of-truth pointers include:

- Setup and onboarding docs.
- Architecture docs.
- API specs.
- Build files and dependency catalogs.
- Runtime manifests.
- Script catalogs.
- Runbooks.
- Security policy docs.
- ADRs for decision rationale.

Example:

```markdown
## Source Of Truth

- Local setup: docs/development/getting-started.md
- API contract: docs/api/openapi.yaml
- Build and dependency rules: build.gradle.kts and gradle/libs.versions.toml
- Deployment manifests: ../orchestration/kubernetes/services/payments/
- Operational runbooks: docs/runbooks/

Consultation triggers:
- Setup docs: before changing prerequisites, bootstrap, or local run behavior.
- API contracts: before adding, removing, or reshaping endpoints.
- Deployment manifests: before changing probes, ports, resources, or service
  wiring.
- Runbooks: when reproducing or debugging an operational failure.
```

### 4. Operating Rules

Put stable constraints directly in `AGENTS.md`. Agents should not have to hunt
for rules that prevent unsafe or invalid changes.

Common operating rules:

- Never run destructive git commands unless explicitly requested.
- Do not commit, push, reset, or rewrite history unless explicitly requested.
- Do not write outside the allowed repository or owned subtree.
- Do not edit generated files directly unless the generator is unavailable and
  the limitation is documented.
- Do not bypass security, auth, policy, persistence, or validation layers as a
  durable fix.
- Treat manual live-environment changes as diagnostics unless they are encoded
  back into repo-owned config.
- Stop and report if a required prerequisite is missing.

Do not demote stable guardrails into a vague summary. If the repository has a
direct rule like "Never run git write commands unless explicitly requested,"
keep that exact operational meaning visible unless a closer owner doc now
authoritatively owns it.

### 5. Development Workflow

Describe the normal path for making changes without duplicating long setup
docs.

Include:

- The prerequisite check or setup doc to read first.
- The default build, test, and local run entry points.
- The preferred debugging flow.
- The correct place to add new files or modules.
- The docs that must change with code changes.

Example:

````markdown
## Development Workflow

Read docs/development/getting-started.md before changing setup assumptions.
Use the checked-in scripts rather than reconstructing commands from memory.

Before finishing service code changes, run:

```bash
./gradlew test
./gradlew check
```
````

### 6. Validation

Be explicit about completion gates. If validation differs by change type, say
so.

Example:

```markdown
## Validation

- Shell scripts: `bash -n <script>` and `shellcheck <script>`.
- Java changes: `./gradlew test` and `./gradlew check`.
- Frontend changes: `npm test` and `npm run lint`.
- Kubernetes changes: `kubectl apply --dry-run=server -f <file>` when a
  cluster is available.
```

Also say what to do when a gate cannot run:

```markdown
If a required verifier cannot run because a tool, cluster, credential, or
service is unavailable, report that explicitly. Do not claim the work is fully
verified.
```

### 7. Documentation Maintenance

Tell agents when to update docs and which docs own recurring topics.

Recommended rules:

- Update `AGENTS.md` when repo instructions, guardrails, discovery commands, or
  workflows change.
- Update `README.md` when setup, usage, public purpose, or human onboarding
  changes.
- Update `docs/` when architecture, operations, APIs, behavior, or design
  rationale changes.
- Do not update archived docs unless explicitly requested.
- Do not duplicate a detailed topic across multiple docs. Choose or update the
  owner doc and link to it.

## Specificity Guidance

Use this table to decide what belongs directly in `AGENTS.md`.

| Content | Put In `AGENTS.md`? | Better Owner |
| --- | --- | --- |
| Repo role and scope | Yes | `AGENTS.md` |
| Agent write boundaries | Yes | `AGENTS.md` |
| Destructive command policy | Yes | `AGENTS.md` |
| Security or compliance guardrails | Yes | `AGENTS.md`, with links to detailed policy docs |
| Discovery commands | Yes | `AGENTS.md` |
| Full setup sequence | Usually no | Getting-started docs or setup scripts |
| Complete port table | No | Architecture docs, manifests, compose files |
| API endpoint inventory | No | OpenAPI specs, route files, controller discovery |
| Dependency versions | No | Build files, lockfiles, version catalogs |
| Class names and package inventories | No | Source code discovery |
| Historical rationale | Brief pointer only | ADRs or decision records |
| Generated output definitions | No | Generator docs or generated artifacts |

Rule of thumb:

```text
If it changes during normal implementation, point to the source of truth.
If it constrains every agent action, keep it directly in AGENTS.md.
```

## Anti-Patterns

Avoid these patterns during authoring and review.

### Static Inventories

Static lists of services, endpoints, ports, packages, classes, or versions tend
to drift. Replace them with discovery commands and owner-doc links.

### Duplicated Procedures

If a setup flow or operational runbook already exists, `AGENTS.md` should link
to it and summarize when to use it. It should not maintain a second copy.

### Vague Guardrails

Rules like "be careful with deployment" are too weak. Name the exact forbidden
or required behavior.

Prefer:

```markdown
Do not use `--address 0.0.0.0` for observability port-forwards.
```

Avoid:

```markdown
Be careful exposing observability.
```

### Context Preload By Accident

Some agent tools support syntax that imports file contents into the startup
context. For example, in Claude-oriented context files, `@docs/file.md` imports
the file rather than acting as a lazy pointer.

For portable `AGENTS.md` files, prefer plain text paths or markdown links:

```markdown
Read docs/architecture/system-overview.md when changing service boundaries.
```

Use eager imports only when you intentionally want the full referenced content
loaded every time.

### Token Minimization As The Only Goal

Short files are not automatically good. A useful `AGENTS.md` should be concise,
but it must still include high-signal operating constraints that agents need
before making changes.

## Generation Workflow

When asking an agent to create a new `AGENTS.md`, require this workflow.

1. Inspect the repository structure with `find`, `tree`, or equivalent
   commands.
2. Read the primary human docs, such as `README.md`, `CONTRIBUTING.md`, setup
   docs, architecture docs, and script catalogs.
3. Inspect build files, package files, manifests, and test configuration to
   discover current commands.
4. Identify the repository archetype, ownership boundaries, and closest source
   of truth for recurring topics.
5. Draft `AGENTS.md` using stable rules, discovery commands, and pointers
   instead of copied inventories.
6. Add consultation triggers for references that agents should not ignore
   during related changes.
7. Compare the draft against the existing `AGENTS.md` and explicitly preserve,
   re-home, or intentionally retire each repo-specific rule that is not
   duplicated elsewhere.
8. Verify every included command is syntactically plausible and every referenced
   file exists.
9. Update documentation indexes or ownership maps if the repository has them.

Do not generate `AGENTS.md` from assumptions alone. The file should be grounded
in discovered repository facts.

## Review Checklist

Use this checklist before accepting a new or modified `AGENTS.md`.

- The repo role, scope, and agent write boundaries are explicit.
- The file contains discovery commands for structure, source search, and key
  runtime or build state.
- The file points to owner docs for setup, architecture, APIs, operations, and
  deployment instead of copying their full detail.
- Important references include inline or block-form triggers for the tasks or
  failures that require reading them.
- Guardrails, workflow steps, and validation gates use imperative language.
- Stable safety rules are directly visible.
- Unique repo-specific guidance from the previous `AGENTS.md` was preserved,
  re-homed to a real owner doc, or intentionally retired with justification.
- Validation gates are clear by change type.
- Missing-prerequisite behavior is explicit.
- No machine-specific absolute paths are required.
- No stale-looking inventories of services, ports, endpoints, classes, or
  dependency versions are maintained.
- Historical docs and ADRs are treated as context unless explicitly active.
- The file is long enough to be useful but not bloated with details owned
  elsewhere.
- References use plain paths or markdown links unless eager import semantics are
  intentional.
- No section was removed solely because it looked verbose. Information loss was
  checked explicitly.

## Minimal Template

Use this as a starting point, then tailor it to the repository.

````markdown
# <Project> Agent Instructions

## Repository Position

**Archetype:** <application | service | library | orchestration | tooling>
**Scope:** <owned system area>
**Role:** <what this repo owns>

### Boundaries
- Read: <allowed external paths or systems>
- Write: <owned paths>
- Do not write: <forbidden paths or generated surfaces>

## Discovery

```bash
# Repo structure
find . -maxdepth 2 -type f | sort

# Source search
rg -n "<important pattern>"

# Available scripts or build tasks
<repo-specific command>
```

## Source Of Truth

- Setup: <path>
- Architecture: <path>
- API contracts: <path>
- Build and dependencies: <path>
- Operations: <path>

Consultation triggers:
- <path>: <trigger for reading this owner doc>.
- <path>: <trigger for reading this owner doc>.
- <path>: <trigger for reading this owner doc>.

## Operating Rules

- Do not <forbidden action>.
- Always <required action>.
- Before <task>, read <path>.
- Stop and report <missing prerequisite or boundary issue>.

## Development Workflow

- Check prerequisites in <path> before implementation.
- Use <command> for the normal local run path.
- Follow <path> when adding new modules, routes, or services.

## Validation

- <change type>: <command>
- <change type>: <command>

If a required verifier cannot run, report the missing prerequisite or failure
instead of claiming full verification.

## Documentation Maintenance

- Update `AGENTS.md` when agent instructions or guardrails change.
- Update `README.md` when human setup or usage changes.
- Update `docs/` when architecture, behavior, operations, or APIs change.
- Keep detailed recurring topics in one owner doc and link to it here.
````

## Relationship To Decision Records

This checkstyle is distilled from the pattern-based documentation principles in
docs/decisions/003-pattern-based-claude-md.md. That decision record remains
historical context and rationale. This file is the active reusable authoring
standard for new `AGENTS.md` files.
