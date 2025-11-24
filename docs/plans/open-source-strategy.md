# Budget Analyzer Open Source Strategy

## Overview

This plan outlines the steps to establish Budget Analyzer as a professional open source organization targeting enterprise architects and senior developers.

**Philosophy**: Minimal and simple. Clone and play.

**Target Audience**: Enterprise architects and senior developers, not beginners.

---

## Phase 1: Foundation (Manual + Automated)

### 1.1 Community Files
Create in orchestration repo, then copy to other repos as needed.

- [x] `CONTRIBUTING.md` - Target architects, emphasize "clone and play" philosophy
- [x] `CODE_OF_CONDUCT.md` - Contributor Covenant (standard)
- [x] `SECURITY.md` - Vulnerability reporting process
- [x] Add LICENSE to `checkstyle-config` repo (currently missing)

### 1.2 GitHub Organization Setup

**Add GitHub topics to all repos:**

| Repository | Topics |
|------------|--------|
| orchestration | `microservices`, `kubernetes`, `tilt`, `reference-architecture`, `spring-boot`, `oauth2`, `bff-pattern`, `ai-assisted-development`, `enterprise-security` |
| session-gateway | `bff`, `spring-cloud-gateway`, `oauth2`, `redis-session`, `spring-boot` |
| token-validation-service | `jwt`, `spring-boot`, `oauth2`, `microservice` |
| transaction-service | `spring-boot`, `microservice`, `rest-api`, `postgresql` |
| currency-service | `spring-boot`, `microservice`, `rest-api`, `redis` |
| permission-service | `spring-boot`, `microservice`, `authorization`, `rbac` |
| budget-analyzer-web | `react`, `typescript`, `vite`, `casl`, `frontend` |
| service-common | `spring-boot`, `java`, `shared-library` |

**Script:** `scripts/github/add-repo-topics.sh` - Run on host with `gh` CLI authenticated.

**GitHub templates and settings:**

- [x] Create `.github/ISSUE_TEMPLATE/bug_report.md`
- [x] Create `.github/ISSUE_TEMPLATE/feature_request.md`
- [x] Create `.github/PULL_REQUEST_TEMPLATE.md`
- [ ] Pin key repos in org (orchestration first)

### 1.3 Update Organization README

- [x] Add badges (license, build status, etc.)
- [x] Add "Quick Start for Architects" section (DRY - links to orchestration)
- [ ] Link to live demo (when available)
- [x] Clarify target audience: "Enterprise architects and senior developers"

---

## Phase 2: Infrastructure & Auth

### 2.1 Auth0 Upgrade

**Recommendation: B2B Essentials ($150/month)**

Why this tier:
- Enables separate dev/prod tenants (not available on free tier)
- 10 organizations for multi-tenant demo
- RBAC and MFA included
- Standard support

**Tasks:**
- [x] Upgrade Auth0 to B2B Essentials
- [ ] Create production tenant
- [ ] Update `docs/setup/auth0-setup.md` with multi-tenant configuration

### 2.2 Domain Strategy

| Domain | Purpose |
|--------|---------|
| `budgetanalyzer.ai` | Primary marketing/landing page |
| `budgetanalyzer.org` | Documentation site (optional, can use GitHub Pages) |
| `app.budgetanalyzer.ai` | Production demo instance (future) |

---

## Phase 3: Demo Deployment

### 3.1 GCP Demo Mode Implementation

Reference: [deployment-architecture-gcp-demo-mode.md](../architecture/deployment-architecture-gcp-demo-mode.md)

- [ ] Implement `scripts/gcp/gcp-demo-deploy.sh`
- [ ] Implement `scripts/gcp/gcp-demo-teardown.sh`
- [ ] Implement `scripts/gcp/gcp-demo-backup.sh`
- [ ] Implement `scripts/gcp/gcp-demo-restore.sh`
- [ ] Test backup/restore workflow
- [ ] Document cost management (~$35-45/month for ~100 hours)

### 3.2 CI/CD Workflows

- [x] Add GitHub Actions for service builds (all backend services)
- [x] Add automated testing workflows
- [ ] Consider release automation with semantic versioning
- [x] Add build status badges to READMEs

---

## Phase 4: Discoverability & Marketing

### 4.1 README Enhancements

- [x] Add architecture diagram to org README
- [x] ~~Create "Why Budget Analyzer?" section~~ (skipped - architecture speaks for itself)

### 4.2 External Presence

- [ ] Submit to [awesome-microservices](https://github.com/mfornos/awesome-microservices)
- [ ] Consider blog post about AI-assisted development journey
- [ ] Highlight **AI-first containerized development architecture** as key differentiator:
  - Effective technique for AI agents: autonomous execution with `--dangerously-skip-permissions`
  - VS Code devcontainer sandbox enables safe sudo access for AI agents
  - Docker wormhole pattern (PR #3) allows TestContainers integration tests
  - Test-driven AI pattern: define success criteria → run autonomously → verify
  - See [autonomous-ai-execution.md](../architecture/autonomous-ai-execution.md)
- [ ] Add project to relevant Spring Boot/Kubernetes showcases
- [ ] Share on relevant subreddits (r/java, r/kubernetes, r/microservices)

---

## Cost Summary

| Item | Recommendation | Monthly Cost |
|------|---------------|--------------|
| License | MIT (keep current) | Free |
| Auth0 Tier | B2B Essentials | $150 |
| GCP Demo | Demo Mode deployment (~100 hrs) | $35-45 |
| Domains | budgetanalyzer.ai, .org | ~$30/year |
| **Total Monthly** | | **~$185-195** |

---

## License Recommendation

**Keep MIT License** - This is the correct choice for Budget Analyzer.

**Why MIT over Apache 2.0:**
- Maximum adoption with minimal friction
- Perfect for "clone and play" educational/reference architecture
- Simpler and shorter (170 words vs 1700+)
- No patent protection needed for this use case
- Compatible with GPL v2 projects

**Why not copyleft (GPL):**
- Want enterprises to freely adopt and modify
- No requirement for derivative works to be open source
- Encourages commercial adoption

---

## Sources

### Open Source Best Practices
- [Linux Foundation: Hosting OS Projects on GitHub](https://www.linuxfoundation.org/research/hosting-os-projects-on-github)
- [GitHub Open Source Guides](https://github.com/github/opensource.guide)
- [Microsoft Learn: Create an Open Source Program](https://learn.microsoft.com/en-us/training/modules/create-open-source-program-github/)

### Licensing
- [Apache vs MIT License Comparison](https://soos.io/apache-vs-mit-license)
- [MIT vs Apache vs GPL](https://www.exygy.com/blog/which-license-should-i-use-mit-vs-apache-vs-gpl)
- [Open Source Licenses 101](https://fossa.com/blog/open-source-licenses-101-apache-license-2-0/)

### Auth0 Pricing
- [Auth0 Official Pricing](https://auth0.com/pricing)
- [Auth0 Pricing Guide 2025](https://www.saasworthy.com/blog/auth0-pricing-plans-guide)
- [Auth0 Pricing Explained](https://blog.logto.io/auth0-pricing-explain)

### GitHub Discoverability
- [microservices-architecture topic](https://github.com/topics/microservices-architecture)
- [awesome-microservices](https://github.com/mfornos/awesome-microservices)
- [spring-boot-microservices topic](https://github.com/topics/spring-boot-microservices)
