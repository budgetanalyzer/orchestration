# Plan: Publish service-common to Maven Central as AI-Native Library

**Status**: Draft
**Created**: 2025-11-26
**Context**: [Conversation 020 - The Product](../../architecture-conversations/conversations/020-the-product.md) (to be re-added after implementation)

## Vision

Make `org.budgetanalyzer:service-common` the first AI-native Spring Boot library - differentiated by CLAUDE.md that teaches AI how to use it correctly.

## Decisions

- **AI Discovery**: WebFetch pattern only (document GitHub raw URL in consuming project's CLAUDE.md)
- **Namespace**: `org.budgetanalyzer` (requires domain ownership proof via TXT record)
- **Scope**: Full automation (Claude handles all code/docs, user handles Sonatype/GPG setup)

---

## Phase 0: Remove "The Product" Conversation from Git History

**Reason**: The conversation announces the product before it exists. Save locally, remove from public git history, republish after Maven Central release.

### Steps

1. **Save locally** (outside git):
   ```bash
   cp /workspace/architecture-conversations/conversations/020-the-product.md ~/drafts/
   ```

2. **Remove from git history** using `git filter-repo` (recommended) or `git filter-branch`:
   ```bash
   cd /workspace/architecture-conversations

   # Install git-filter-repo if needed
   pip install git-filter-repo

   # Remove file from entire history
   git filter-repo --path conversations/020-the-product.md --invert-paths

   # Force push to rewrite remote history
   git push origin --force --all
   ```

3. **Update INDEX.md** - Remove entry for conversation 020

4. **After service-common is published** - Re-add the conversation with updated content referencing the actual Maven Central artifact

---

## Phase 1: Documentation Cleanup

### Files to Update

1. **README.md** - Reposition as generic Spring Boot library
   - Update title and description to remove "Budget Analyzer microservices"
   - Add prominent "AI-Native Documentation" section explaining the CLAUDE.md differentiator
   - Remove "Related Repositories" section
   - Add Maven Central badge (after publishing)

2. **CLAUDE.md** - Reframe for public library consumption
   - Remove "Tree Position" ecosystem references
   - Keep all technical content (this IS the differentiator)
   - Add section: "For Consuming Projects" with WebFetch instructions
   - Add example CLAUDE.md snippet for consumers to copy

3. **docs/code-quality-standards.md**
   - Update title to generic "Code Quality Standards"

4. **docs/spring-boot-conventions.md**
   - Update title to generic "Spring Boot Conventions"
   - Change "BudgetController" example to "AccountController" or similar

---

## Phase 2: Build Configuration

### build.gradle.kts Changes

**Current state** (line 84-116):
- Has maven-publish plugin
- Has sources/javadoc JARs
- Has Apache 2.0 license
- Missing: signing, developers, SCM, URL, Central Portal config

**Changes needed**:

1. Add `signing` plugin to subprojects
2. Add `io.github.gradle-nexus.publish-plugin` to root
3. Add POM metadata: `url`, `developers`, `scm`
4. Add Central Portal repository config
5. Add signing configuration (conditional on env vars)

```kotlin
// Root build.gradle.kts additions
plugins {
    id("io.github.gradle-nexus.publish-plugin") version "2.0.0"
}

nexusPublishing {
    repositories {
        sonatype {
            nexusUrl.set(uri("https://central.sonatype.com/api/v1/publisher"))
            username.set(providers.environmentVariable("SONATYPE_USERNAME"))
            password.set(providers.environmentVariable("SONATYPE_PASSWORD"))
        }
    }
}

// Subprojects additions
apply(plugin = "signing")

pom {
    url.set("https://github.com/budgetanalyzerllc/service-common")
    developers {
        developer {
            id.set("budgetanalyzer")
            name.set("Budget Analyzer")
        }
    }
    scm {
        url.set("https://github.com/budgetanalyzerllc/service-common")
        connection.set("scm:git:https://github.com/budgetanalyzerllc/service-common.git")
        developerConnection.set("scm:git:ssh://git@github.com:budgetanalyzer/service-common.git")
    }
}

signing {
    val signingKey = providers.environmentVariable("SIGNING_KEY")
    val signingPassword = providers.environmentVariable("SIGNING_KEY_PASSPHRASE")
    if (signingKey.isPresent) {
        useInMemoryPgpKeys(signingKey.get(), signingPassword.orNull)
        sign(publishing.publications["mavenJava"])
    }
}
```

---

## Phase 3: GitHub Actions Workflow

Create `.github/workflows/publish.yml`:

```yaml
name: Publish to Maven Central

on:
  push:
    tags:
      - 'v*'

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 24
        uses: actions/setup-java@v4
        with:
          java-version: '24'
          distribution: 'temurin'

      - name: Build and Publish
        env:
          SONATYPE_USERNAME: ${{ secrets.SONATYPE_USERNAME }}
          SONATYPE_PASSWORD: ${{ secrets.SONATYPE_PASSWORD }}
          SIGNING_KEY: ${{ secrets.SIGNING_KEY }}
          SIGNING_KEY_PASSPHRASE: ${{ secrets.SIGNING_KEY_PASSPHRASE }}
        run: |
          ./gradlew clean build
          ./gradlew publishToSonatype closeAndReleaseSonatypeStagingRepository
```

---

## Phase 4: AI-Native Documentation Strategy

### The Differentiator

Traditional library: "Read the JavaDoc, figure it out"
This library: "Point your AI at the CLAUDE.md, get working code"

### WebFetch Pattern for Consumers

Add to service-common's CLAUDE.md a section for consuming projects:

```markdown
## For Consuming Projects

Add this to your project's CLAUDE.md to enable AI-native documentation:

### Using service-common

When working with error handling, exception patterns, or API responses in this project,
fetch the service-common documentation for current patterns:

**Reference**: https://raw.githubusercontent.com/budgetanalyzer/service-common/main/CLAUDE.md

Key patterns from service-common:
- Exception hierarchy: ResourceNotFoundException (404), BusinessException (422), etc.
- API error format: ApiErrorResponse with type, message, and field errors
- Base entities: AuditableEntity, SoftDeletableEntity
```

### README "AI-Native" Section

```markdown
## AI-Native Documentation

This library includes comprehensive documentation designed for AI code assistants.

**For AI-assisted development**, add this to your project's `CLAUDE.md`:

> When implementing error handling or extending service-common patterns,
> reference: https://raw.githubusercontent.com/budgetanalyzer/service-common/main/CLAUDE.md
```

---

## Phase 5: Manual Steps (Human Does This)

### 1. Namespace Verification for org.budgetanalyzer

Since you're using `org.budgetanalyzer` (not `io.github.*`), you need domain ownership proof:

1. Go to https://central.sonatype.com/
2. Create account / sign in
3. Navigate to Namespaces → Add Namespace
4. Enter `org.budgetanalyzer`
5. **Add DNS TXT record** to `budgetanalyzer.org`:
   - Record: `TXT`
   - Host: `@` or `budgetanalyzer.org`
   - Value: (Sonatype will provide verification code)
6. Verify in Sonatype portal

### 2. GPG Key Setup

```bash
# Generate key (RSA 4096, no expiration recommended)
gpg --full-generate-key

# List keys to get KEY_ID
gpg --list-secret-keys --keyid-format=long

# Upload public key to keyserver
gpg --keyserver keys.openpgp.org --send-keys <KEY_ID>

# Export private key for GitHub Actions (base64)
gpg --armor --export-secret-keys <KEY_ID> | base64 > signing-key.txt
```

### 3. GitHub Secrets

In repo Settings → Secrets and variables → Actions, add:

| Secret | Value |
|--------|-------|
| `SONATYPE_USERNAME` | Your Central Portal username |
| `SONATYPE_PASSWORD` | Your Central Portal user token |
| `SIGNING_KEY` | Base64-encoded GPG private key |
| `SIGNING_KEY_PASSPHRASE` | GPG key passphrase |

### 4. First Release

After Claude's changes are merged:

```bash
# Update version in build.gradle.kts to 1.0.0 (remove -SNAPSHOT)
# Commit

git tag v1.0.0
git push origin v1.0.0
# GitHub Actions will publish automatically
```

---

## Implementation Order

### Claude Will Do:
1. Update documentation files (README.md, CLAUDE.md, docs/*.md)
2. Update build.gradle.kts with signing and Central Portal config
3. Create .github/workflows/publish.yml

### Human Will Do:
1. Verify `org.budgetanalyzer` namespace (DNS TXT record)
2. Generate and upload GPG key
3. Configure GitHub secrets
4. Test locally: `./gradlew build publishToMavenLocal`
5. Tag v1.0.0 and push to trigger publish

---

## Critical Files to Modify

| File | Action |
|------|--------|
| `/workspace/service-common/build.gradle.kts` | Add signing, POM metadata, Central Portal |
| `/workspace/service-common/README.md` | Reposition as generic library, add AI-Native section |
| `/workspace/service-common/CLAUDE.md` | Remove ecosystem refs, add consumer instructions |
| `/workspace/service-common/docs/code-quality-standards.md` | Update title |
| `/workspace/service-common/docs/spring-boot-conventions.md` | Update title, fix examples |
| `/workspace/service-common/.github/workflows/publish.yml` | **NEW** - GitHub Actions workflow |

---

## Success Criteria

1. `./gradlew clean build` passes
2. `./gradlew publishToMavenLocal` creates signed artifacts
3. Documentation clearly positions as AI-native library
4. README explains WebFetch pattern for consumers
5. GitHub Actions workflow ready for tag-based releases

---

## Key Research Findings

### OSSRH Sunset (Critical)
OSSRH (the old Nexus-based publishing) reached end-of-life on **June 30, 2025**. Must use new Central Publisher Portal at `https://central.sonatype.com/`.

### Domain Neutrality Assessment
Code is genuinely domain-neutral - all Java is generic patterns. Only documentation references "Budget Analyzer" which needs cleanup.

### Package Namespace
`org.budgetanalyzer.*` is acceptable - just organization namespace, not domain-specific content.
