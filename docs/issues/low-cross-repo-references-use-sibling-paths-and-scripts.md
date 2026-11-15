# Cross-repo doc references use sibling paths and other repos' scripts

- **Severity:** Low
- **Owner:** orchestration (the standard in `docs/agents-md-checkstyle.md`);
  every repository (its own docs)
- **Status:** Open
- **Source:** 2026-11-15 review of the Redis session/cache split

## Problem

Documentation across the Budget Analyzer repositories refers to other
repositories in two ways that cause problems.

**Relative sibling links in ordinary docs.** Links such as
`[guide](../../workspace/docs/host-isolation.md)` work only in a local
checkout where every repository sits side by side. On GitHub, a relative link
resolves inside the current repository, so these links are broken for anyone
reading the docs there.

**Instructions to run another repository's script.** Docs tell readers to run
commands such as `../orchestration/scripts/ops/flush-redis.sh`. The owning
repository cannot see these copies, so they drift. The Redis split review
found two examples:

- `ext-authz/README.md`, `session-gateway/docs/security.md` and
  `session-gateway/docs/session-configuration.md` call `flush-redis.sh` without
  its required `session` or `cache` argument.
- `session-gateway/AGENTS.md` copies orchestration's `redis-cli` access
  commands and reads an `ops-username` key that the bootstrap Secret does not
  have.

No repository states a rule for cross-repo references. The example in
`docs/agents-md-checkstyle.md` itself points at a manifest directory with
`../orchestration/kubernetes/services/payments/`.

## Current extent

These are line counts measured on 2026-11-15. Archived docs, ADRs and plans are
excluded.

| Repository | Relative sibling links outside `AGENTS.md` | References to another repo's scripts |
| --- | --- | --- |
| orchestration | 35 (mostly `workspace` docs) | 1 (`AGENTS.md`) |
| service-common | 8 | 0 |
| budget-analyzer-api-tests | 6 | 7 |
| session-gateway | 4 | 3 |
| ext-authz | 2 | 1 |
| workspace | 2 | 5 |
| currency-service | 1 | 1 |
| permission-service | 1 | 0 |
| transaction-service | 1 | 0 |
| budget-analyzer-web | 0 | 1 (`AGENTS.md`) |
| ai-session-handler | 0 | 0 |

Run these from the orchestration root:

```bash
repos='ai-session-handler budget-analyzer-api-tests budget-analyzer-web currency-service ext-authz orchestration permission-service service-common session-gateway transaction-service workspace'
alt=$(tr ' ' '|' <<<"$repos")
excludes=(--glob '*.md' --glob '!**/docs/archive/**' --glob '!**/archive/**'
  --glob '!**/docs/decisions/**' --glob '!**/docs/plans/**' --glob '!**/node_modules/**')

# Relative sibling links in docs other than AGENTS.md
for r in $repos; do
  rg -n -P "${excludes[@]}" --glob '!AGENTS.md' --glob '!CLAUDE.md' \
    "\]\((\.\./)+(${alt})/" "../$r"
done

# References to another repository's scripts, by sibling path
for r in $repos; do
  rg -n -P "${excludes[@]}" "\.\./(${alt})/scripts/" "../$r"
done

# Orchestration script paths named in other repositories
for r in ${repos/orchestration/}; do
  rg -n -P "${excludes[@]}" \
    '(?<![\w./-])\.?/?scripts/(ops|bootstrap|smoketest|repo|guardrails)/' "../$r"
done
```

Use `**/`-prefixed exclusion globs. A glob such as `!docs/plans/**` does not
exclude anything when the search root is `../<repo>`. The commands overlap, so
the same line can match more than one of them. The table counts each line once.

## Proposed rule

- **In `AGENTS.md`:** refer to other repositories with relative sibling paths,
  such as `../orchestration/docs/...`. Point only at documentation: a README, a
  `docs/` page, or orchestration's `scripts/README.md`. Never point at a script,
  manifest or other executable file.
- **In every other doc:** link to other repositories with the public URL
  `https://github.com/budgetanalyzer/<repo>/blob/main/<path>`. Never use a
  `../<repo>/` path.
- **No doc tells the reader to run another repository's script.** Link to the
  section of the owning repository's docs that describes the procedure.
- **Agents read such a link locally.** Read
  `https://github.com/budgetanalyzer/<repo>/blob/main/<path>` from the local
  `../<repo>/<path>` instead of fetching it.

The rule covers documentation only. Build, Tilt, CI and code wiring that uses
sibling paths, such as `../service-common`, is out of scope.

All eleven repositories are public on GitHub, so the URLs work for any reader.

## Proposed fix

1. In orchestration:
   - Add the rule as a new check in `docs/agents-md-checkstyle.md`, and change
     its examples to match.
   - Add a one-line form of the rule to orchestration's `AGENTS.md`.
   - Replace `AGENTS.md`'s `../workspace/scripts/check-agent-vm-boundary.sh`
     reference with a link to workspace's pre-agent boundary-check doc
     section.
   - Convert orchestration's relative sibling links.
2. Make sure an owner doc covers every cross-repo procedure that a sibling
   currently copies before replacing the copy with a link. For example, the
   `generate-unified-api-docs.sh --session-gateway-only` command in
   api-tests' `README.md` and web's `AGENTS.md` needs a section in
   orchestration's `scripts/README.md` or `docs-aggregator/README.md`.
3. In each other repository:
   - Add the one-line rule to `AGENTS.md`.
   - Convert relative sibling links to GitHub URLs.
   - Replace script references with links to the owning doc section.
4. Run the work as a plan with one phase per repository. The Redis split
   review remediation already removed the `flush-redis.sh` references in
   `ext-authz/README.md`, `session-gateway/docs/security.md` and
   `session-gateway/docs/session-configuration.md`.

## Decisions to make first

- **Naming a script in a prohibition.** Workspace's TLS docs and `AGENTS.md`
  name orchestration's `setup-k8s-tls.sh` to say that agents must never run
  it. Decide whether naming a script in a prohibition is allowed, or whether it
  also becomes a link to the owning doc.
- **`blob/main` lag.** A link to a section that a cross-repo change adds stays
  broken on GitHub until the target repository merges. Any link check should
  map the URL to the local sibling path so that it validates the working tree.

## Acceptance

- `docs/agents-md-checkstyle.md` contains the rule as a check, and its examples
  follow it.
- Every repository's `AGENTS.md` states the rule.
- The three discovery commands return no matches outside the decided
  exceptions.
