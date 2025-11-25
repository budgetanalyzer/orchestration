# AI Coding Assistant Configuration: Avoiding Vendor Lock-in

## Overview

This guide presents three strategies for managing AI coding assistant configuration files (like CLAUDE.md, .cursorrules, .github/copilot-instructions.md) across different providers without getting locked into a specific vendor.

---

## Option 1: Write Provider-Agnostic Documentation

### Description
Maintain a single source of truth using standard markdown that works across all AI coding assistants (Claude, GitHub Copilot, Cursor, Windsurf, etc.).

### Approach
- Use standard markdown formatting (headers, lists, code blocks)
- Avoid provider-specific syntax (e.g., Claude's XML tags like `<example>`)
- Focus on semantic content: coding standards, architecture patterns, conventions
- Keep one canonical file and copy it to provider-specific locations

### Example Structure
```markdown
# Project AI Instructions

## Architecture
- Use Spring Boot 3.x with constructor-based dependency injection
- Follow package-by-feature structure
- Implement domain-driven design patterns

## Code Standards
- Use Java 24 features
- Prefer immutable objects
- Write comprehensive unit tests with JUnit 5

## React/Frontend
- Use functional components with TypeScript
- Implement hooks for state management
- Follow Airbnb style guide
```

### Implementation
```bash
# Simple copy script
cp AI_INSTRUCTIONS.md CLAUDE.md
cp AI_INSTRUCTIONS.md .cursorrules
mkdir -p .github && cp AI_INSTRUCTIONS.md .github/copilot-instructions.md
```

### Use Cases
✅ **Best for:**
- Individual developers or small teams (2-5 people)
- Simple projects with straightforward conventions
- Teams just starting with AI coding assistants
- When you want zero tooling overhead

❌ **Not ideal for:**
- Large teams with complex, evolving rule sets
- Multiple projects that need synchronized updates
- When you need version control for instruction sets

### Further Research
- [GitHub Copilot Instructions Documentation](https://docs.github.com/en/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot)
- [Cursor Rules Best Practices](https://docs.cursor.com/context/rules-for-ai)
- [Anthropic Claude Documentation](https://docs.anthropic.com/en/docs/welcome)

---

## Option 2: Use a Universal Configuration Manager

### Description
Use a dedicated tool that generates provider-specific configuration files from a single source configuration (YAML or similar).

### Tools Available

#### ai-rulez
Define once in `ai-rulez.yml`, generate for all providers automatically.

**Example:**
```yaml
$schema: https://github.com/Goldziher/ai-rulez/schema/ai-rules-v2.schema.json
metadata:
  name: "Spring Boot Microservices"
  
rules:
  - name: "Spring Boot Standards"
    priority: high
    content: |
      - Use constructor injection
      - Follow package-by-feature structure
      - Implement proper error handling
      
  - name: "React Best Practices"
    priority: medium
    content: |
      - Functional components only
      - TypeScript strict mode
      - Component composition over inheritance
```

**Generate files:**
```bash
ai-rulez generate  # Creates .cursorrules, copilot-instructions.md, CLAUDE.md, etc.
```

#### rulebook-ai
Pack-based system for managing AI environments across multiple assistants.

**Example:**
```bash
# Add configuration packs
rulebook-ai project sync --assistant cursor copilot claude

# Generate for all assistants
rulebook-ai project sync
```

### Use Cases
✅ **Best for:**
- Medium teams (5-20 developers)
- Organizations with 5+ repositories using similar standards
- Teams that want versioned, reproducible AI configurations
- Projects requiring different rule sets for different components
- DevOps-minded teams comfortable with CLI tools

❌ **Not ideal for:**
- Solo developers with simple needs
- Teams resistant to adopting new tooling
- One-off projects

### Further Research
- [ai-rulez GitHub Repository](https://github.com/Goldziher/ai-rulez)
- [ai-rulez Schema Documentation](https://github.com/Goldziher/ai-rulez/schema)
- [rulebook-ai GitHub Repository](https://github.com/botingw/rulebook-ai)
- [rulebook-ai User Guide](https://github.com/botingw/rulebook-ai/blob/main/memory/docs/user_guide/supported_assistants.md)

---

## Option 4: Shared Rules Repository (Team Scale)

### Description
Treat AI assistant rules as versioned dependencies using a package manager approach. Teams maintain a central repository of curated rules that projects install like npm packages.

### Implementation with AI Rules Manager (ARM)

**Setup:**
```bash
# 1. Install ARM
npm install -g ai-rules-manager

# 2. Connect to your team's rules registry
arm config registry add company-rules https://github.com/yourcompany/ai-rules --type git

# 3. Define where rules should go (sinks)
arm config sink add cursor --directories .cursor/rules
arm config sink add copilot --directories .github/instructions

# 4. Install specific rule sets
arm install company-rules/spring-boot@2.1.0
arm install company-rules/react-patterns@1.5.0
```

**Team workflow:**
```bash
# New developer setup (one command)
git clone your-project
arm install  # Reads arm.json, installs all configured rules

# Update rules across all projects
arm update company-rules/spring-boot@2.2.0
```

### Rule Repository Structure
```
ai-rules-repo/
├── spring-boot/
│   ├── v2.1.0/
│   │   ├── rules.md
│   │   └── metadata.json
│   └── v2.2.0/
├── react-patterns/
│   └── v1.5.0/
└── python-fastapi/
```

### Use Cases
✅ **Best for:**
- Large organizations (20+ developers)
- Teams managing 10+ repositories
- Organizations with strict coding standards and compliance requirements
- Monorepo architectures with different rule sets per service
- Companies that need audit trails for AI instruction changes
- Teams with dedicated DevOps/Platform engineering

❌ **Not ideal for:**
- Small teams or solo developers
- Startups moving quickly without established standards
- Projects with frequently changing, experimental guidelines

### Advanced Features
- **Version pinning**: Lock to specific rule versions to prevent breaking changes
- **Automated updates**: CI/CD pipelines can enforce rule updates
- **Rule composition**: Combine multiple rule sets (e.g., base + framework-specific)
- **Team onboarding**: New developers get consistent AI configuration instantly

### Further Research
- [AI Rules Manager GitHub](https://github.com/arm-ai/arm)
- [AI Rules Manager on Hacker News Discussion](https://news.ycombinator.com/item?id=41559000)
- [Understanding ARM: Taming AI-Assisted Development](https://skywork.ai/blog/understanding-ai-rules-manager-arm-taming-the-chaos-of-ai-assisted-development)
- [awesome-cursorrules Repository](https://github.com/PatrickJS/awesome-cursorrules) (Example public registry)

---

## Decision Matrix

| Factor | Option 1: Provider-Agnostic | Option 2: Config Manager | Option 4: Shared Repository |
|--------|----------------------------|-------------------------|---------------------------|
| Setup Time | 5 minutes | 15-30 minutes | 1-2 hours |
| Team Size | 1-5 developers | 5-20 developers | 20+ developers |
| Maintenance | Manual copy/paste | Automated generation | Centralized versioning |
| Learning Curve | None | Low | Medium |
| Scalability | Low | Medium | High |
| Version Control | Git (manual) | Git + tool config | Full dependency management |
| Cost | Free | Free (open source) | Free (open source) |

---

## Recommended Path

### For Individual Developers or Small Teams
**Start with Option 1** → Keep it simple, use standard markdown, copy files as needed

### For Growing Teams (5-15 people)
**Adopt Option 2** → Invest 30 minutes in ai-rulez or rulebook-ai for automated generation

### For Enterprise/Large Organizations
**Implement Option 4** → Build a proper rules repository with versioning and team governance

### Migration Path
1. **Start**: Option 1 (immediate value, no overhead)
2. **Grow**: Option 2 when managing 5+ repos (add automation)
3. **Scale**: Option 4 when coordinating across teams (full governance)

---

## Additional Resources

- [Cursor vs GitHub Copilot Comparison](https://www.builder.io/blog/cursor-vs-github-copilot)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Instructa AI Prompts Repository](https://github.com/instructa/ai-prompts) (Community-curated examples)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io) (Future standardization effort)