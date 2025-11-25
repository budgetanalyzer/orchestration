# claude-discovery: Finding Peers in AI-Native Architecture

## Vision

Discover architects who've independently adopted discovery patterns for AI-native development. This isn't about evangelism or user acquisition - it's about finding peers who independently arrived at similar insights about building software with AI as a collaborative partner.

## The Problem We're Solving

> "I want to meet someone who is good enough to understand what I built. 'For architects by architects' isn't meant to spread adoption."

You can't get people to run setup scripts. You can't evangelize architectural patterns. But you **can** find people who've already figured it out independently. Discovery patterns in documentation are the beacon - a signal that someone is thinking about AI-native architecture at a similar level.

## What Is claude-discovery?

A tool to:
1. **Search GitHub** for repositories using discovery patterns in root-level markdown files
2. **Extract contact information** from those repos
3. **Analyze quality signals** to distinguish production implementations from tutorials or static documentation
4. **Generate a registry** of potential peers for conversation
5. **Identify emergent patterns** across different implementations

This is **discovery**, not indexing. We're looking for the "five people on the planet" working on this, not building a comprehensive catalog.

## Why Discovery Patterns Matter

We're looking for a specific architectural approach, not a filename convention:
- **Discovery commands over static lists** - repos that teach through exploration rather than exhaustive documentation
- **Pattern recognition** - if someone independently adopted discovery-based documentation, they "get it"
- **Filename agnostic** - whether it's README.md, CONTRIBUTING.md, or CLAUDE.md doesn't matter
- **Signal of sophistication** - using grep/kubectl/docker commands in docs shows production thinking

The pattern is what matters. If a root markdown file contains discovery commands that help you understand the codebase, that architect independently figured out what we're looking for.

## Repository Strategy: Standalone

**Decision:** New repository `claude-discovery` separate from Budget Analyzer

**Rationale:**
- **Different purpose**: Discovery vs demonstration
- **Different lifecycle**: Budget Analyzer shows what; claude-discovery finds who
- **Different dependencies**: GitHub API vs microservices infrastructure
- **Reusability**: Anyone can use claude-discovery; it's not Budget Analyzer-specific
- **Clean separation**: The discovery tool could find Budget Analyzer as one of many

**Location:** `/workspace/claude-discovery/` (sibling to orchestration, not nested)

## Phase 1: MVP Discovery Engine

### Goals
- Prove the concept
- Find the first 10-20 repos using discovery patterns
- Extract contact information
- Generate shareable discoveries report
- Start conversations with 1-3 potential peers

### Two-Stage Strategy

**Problem:** Searching all of GitHub for discovery patterns is too slow (millions of repos).

**Solution:** Pre-filter with GitHub topics first, then search content.

**Stage 1: Topic-Based Pre-Filtering** (NEW)
- Use GitHub Search API with topic and metadata filters
- Primary query: `topic:ai-assisted-development archived:false fork:false stars:>=50 pushed:>2024-01-01`
- Expected results: ~50 high-quality candidate repos (99% reduction from millions)
- Fast: 5-10 API calls, <1 minute

**Stage 2: Content Search** (existing, but modified)
- Search only the pre-filtered candidate repos
- Look for discovery patterns in root markdown files
- Expected speedup: 10-50x faster (searching 50 repos vs millions)

### Core Components

#### 0. Topic Pre-Filter (`src/prefilter.py`) - NEW
```python
# Pseudo-code
prefilter_by_topics()
- GitHub Search API queries with topic filters:
  - Tier 1 (Primary): topic:ai-assisted-development
  - Tier 2 (Fallback): topic:devcontainer topic:kubernetes
  - Tier 3 (Expansion): topic:spring-boot-microservices
- Metadata filters (all queries):
  - archived:false (no abandoned projects)
  - fork:false (original work only)
  - stars:>=50 (quality signal)
  - pushed:>2024-01-01 (active development)
  - size:>=5000 (substantial codebases)
  - topics:>=5 (well-categorized)
- Handle rate limiting (30 requests/min)
- Output: List of {owner, repo, url, stars, topics, last_push}
- Expected: 50-200 repos depending on tier
```

#### 1. GitHub Search (`src/search.py`)
```python
# Pseudo-code
search_github_for_discovery_patterns(candidate_repos)
- For each repo in pre-filtered set (from prefilter.py):
  - Fetch root-level markdown files:
    - README.md
    - CONTRIBUTING.md
    - DEVELOPMENT.md
    - ARCHITECTURE.md
    - CLAUDE.md (yes, still include it)
- Use GitHub REST API or GraphQL
- Handle pagination (100 results at a time)
- Handle rate limiting (5000 requests/hour authenticated)
- Fetch file content for each candidate
- Filter: Keep only files containing discovery command patterns
  - Look for code blocks with: grep, kubectl, docker, tree, find, git
  - Pattern: Commands that explore/understand, not just run
- Output: List of {owner, repo, url, stars, language, markdown_file, pattern_score}
```

#### 2. Contact Extractor (`src/extract.py`)
```python
# Pseudo-code
extract_contacts(repo)
- Fetch discovered markdown file content
- Check SECURITY.md for security contact
- Check CODE_OF_CONDUCT.md for enforcement contact
- Check package.json for author email
- Parse common patterns: email addresses, GitHub @mentions
- Privacy: Public information only, respect robots.txt
- Output: List of {email, github_username, source_file}
```

#### 3. Quality Analyzer (`src/analyze.py`)
```python
# Pseudo-code
analyze_quality(repo)
- Production evidence:
  - Multiple related repos? (Microservices pattern)
  - CI/CD configs? (GitHub Actions, CircleCI, etc.)
  - Test directories? (Serious about quality)
  - Docker/K8s? (Deployment thinking)
- Discovery pattern depth:
  - Contains discovery commands? (Pattern-based thinking)
  - Quality of commands? (Generic tutorials vs production-specific)
  - Has architecture context? (Thoughtful documentation)
  - Multiple discovery patterns? (Systematic approach)
- Activity signals:
  - Recent commits? (Active development)
  - Multiple contributors? (Team vs solo)
  - Commit message quality? (Engineering discipline)
- Score 1-10 for "peer potential"
- Output: {score, signals_found, reasoning}
```

#### 4. Discovery Report Generator (`src/generate.py`)
```python
# Pseudo-code
generate_reports()
- discoveries.json (machine-readable)
  - Full structured data
  - Queryable, scriptable
- DISCOVERIES.md (human-readable)
  - Markdown table of repos
  - Contact info, patterns, scores
  - Links to discovered markdown files
  - Last indexed timestamp
- Output files to repo root
```

### Technical Stack

**Language:** Python 3.10+
- Simple, excellent for scripting
- Great GitHub API libraries (PyGithub, requests)
- Easy text processing (regex, parsing)

**Dependencies:**
- `PyGithub` - GitHub API wrapper
- `requests` - HTTP library
- `python-dotenv` - Environment variable management
- `pytest` - Testing framework (for Phase 2)

**Authentication:**
- GitHub Personal Access Token
- Stored in `.env` (gitignored)
- Template in `.env.example`

**Data Format:**
- JSON for structured data (git-trackable)
- Markdown for human presentation
- No database (yet) - keep it simple

### File Structure

```
claude-discovery/
├── README.md                    # Vision, usage, current findings
├── CLAUDE.md                    # Meta: This tool's own CLAUDE.md
├── discoveries.json             # Machine-readable registry (generated)
├── DISCOVERIES.md               # Human-readable findings (generated)
├── .env.example                 # Template for GitHub token
├── .gitignore                   # Ignore .env, __pycache__, etc.
├── requirements.txt             # Python dependencies
├── src/
│   ├── __init__.py
│   ├── prefilter.py            # Topic-based pre-filtering (NEW)
│   ├── search.py               # GitHub API search (modified)
│   ├── extract.py              # Contact extraction
│   ├── analyze.py              # Quality scoring
│   ├── generate.py             # Report generation
│   └── config.py               # Configuration management
├── config/
│   └── search_queries.yaml     # Configurable topic queries (NEW)
├── docs/
│   ├── PLAN.md                 # This document
│   ├── PATTERNS.md             # Observed architectural patterns
│   └── FINDINGS.md             # Qualitative observations
└── tests/                       # Unit tests (Phase 2)
    ├── __init__.py
    └── test_extract.py
```

### Success Criteria for Phase 1

**Quantitative:**
- [ ] Pre-filtering reduces search space by 95-99% (millions → ~50 repos)
- [ ] Content search completes in <5 minutes (vs current timeout)
- [ ] Find 10+ repos using discovery patterns in root markdown (excluding Budget Analyzer)
- [ ] Successfully extract contact info from 5+ repos
- [ ] Generate valid `discoveries.json` and `DISCOVERIES.md`
- [ ] Achieve 50%+ success rate on contact extraction

**Qualitative:**
- [ ] Identify at least 1 "high potential" peer (score 7+)
- [ ] Document at least 3 distinct architectural patterns
- [ ] Find evidence of production usage (not just tutorials)
- [ ] Validate the hypothesis: Discovery pattern adopters exist independently
- [ ] Tool discovers Budget Analyzer itself via topic search (dogfooding validation)

**Next Steps:**
- [ ] Start conversation with 1-3 potential peers
- [ ] Validate if they "figured it out too" independently
- [ ] Learn what patterns they've discovered
- [ ] Update discoveries based on conversations

## Phase 2: Pattern Recognition (Future)

Once we have initial discoveries, enhance analysis:

### Pattern Detection
- **Microservices topology**: How many repos? How organized?
- **Tech stack clustering**: Spring Boot + React? Django + Vue? Go microservices?
- **Documentation patterns**: What discovery commands are common?
- **Architecture styles**: Monorepo? Repo-per-service? Hybrid?

### Quality Signals
- **Production indicators**:
  - Monitoring/observability configs
  - Database migrations
  - Secret management
  - Load balancer configs
- **Maturity markers**:
  - CHANGELOG.md present?
  - Semantic versioning?
  - Release tags?
  - Public API docs?

### Network Analysis
- **Cross-references**: Do repos link to each other?
- **Common authors**: Same person/team across multiple discovery pattern repos?
- **Fork relationships**: Who's building on whose patterns?
- **Citation patterns**: Who credits whom?

## Phase 3: Connection Layer (Future Vision)

### Opt-In Registry
- Static site hosted on GitHub Pages
- Searchable by tech stack, pattern, quality score
- Opt-in only: Repos can request inclusion or exclusion
- Privacy-first: Only display publicly stated contact preferences

### Pattern Library
- Catalog common discovery documentation patterns
- Link to examples in discovered repos
- Attribution to originators
- Living document updated as ecosystem evolves

### Discourse Facilitation
- GitHub Discussions for pattern sharing
- Optional: Mailing list for high-quality signal
- Goal: Enable "oh, you figured that out too" moments
- Anti-goal: Not another Slack channel no one reads

## Philosophical Principles

### 1. Discovery, Not Evangelism
We're not trying to convince people to adopt a convention. We're finding people who already figured out the pattern independently. Discovery-based documentation spreads through use, not through evangelism.

### 2. Quality Over Quantity
Finding 5 peer architects is more valuable than cataloging 500 repos with renamed READMEs. We're looking for production experience and independent insight.

### 3. Privacy-Respecting
Only index public information. Respect `robots.txt`. Provide opt-out mechanisms. Don't scrape aggressively. Be a good citizen.

### 4. Open Source as Substrate
The code is public not for user acquisition but for discoverability. Someone pointing their AI at `github.com/yourname/claude-discovery` should understand the pattern immediately.

### 5. AI-Native Architecture
This tool itself should exemplify the patterns we're looking for:
- Discoverable (its own CLAUDE.md)
- Pattern-based documentation
- Simple, bounded context
- Runnable without complex setup

### 6. Topic Standardization
**Establishing `ai-native-development` as a GitHub topic:**
- Repositories built FOR and WITH AI as collaborative partner
- Discovery patterns in documentation (not just renamed files)
- Production-grade implementations (not tutorials)
- Containerized development environments for AI agents

**Dogfooding:** Budget Analyzer repos will use this topic, making them discoverable by the tool we're building.

## Why This Will Work

### The Hypothesis
**There are architects independently discovering that:**
1. Microservices align perfectly with AI context windows
2. Pattern-based documentation beats static lists
3. Discovery commands in documentation enable AI-native development
4. This is the future of software architecture

**Evidence:**
- You discovered it independently
- It's emergent, not planned
- The constraints are universal (context limits, economics, AI capabilities)
- The benefits are real (productivity, maintainability)

**Implication:**
If you found it, others will too. Discovery patterns in documentation are the beacon that makes them discoverable.

### The Network Effect
1. **Early**: A few isolated repos using discovery patterns
2. **Discovery**: claude-discovery finds them, connects peers
3. **Learning**: Patterns cross-pollinate, improve
4. **Visibility**: More repos adopt as pattern becomes known
5. **Ecosystem**: Tools emerge (linters, generators, analyzers)
6. **Standard**: Discovery-based documentation becomes expected practice

We're in phase 1-2. Building this tool accelerates toward phase 3-4.

## Open Questions

### Technical
1. **Rate limiting strategy**: How to stay within GitHub API limits?
2. **False positives**: How to filter renamed READMEs vs real adoption?
3. **Update cadence**: Daily? Weekly? On-demand?
4. **Data storage**: Commit JSON to git, or external database?
5. **Topic tier expansion**: Start with Tier 1 (ai-assisted-development), expand to other tiers if <10 results?

### Strategic
1. **Public vs private**: Should discoveries be public immediately?
2. **Contact approach**: Direct email, GitHub issues, or passive index?
3. **Opt-in/out**: How do repos signal inclusion/exclusion preferences?
4. **Governance**: Who decides what's a "quality" implementation?

### Philosophical
1. **First contact**: What do you say when you find a peer?
2. **Community structure**: Mailing list? Discord? GitHub Discussions?
3. **Ownership**: Is this your project, or does it bootstrap and decentralize?
4. **Success metrics**: How do we know this worked? Quality of conversations?

## Implementation Timeline

### Week 1: Foundation
- [ ] Create `claude-discovery` repository
- [ ] Write comprehensive README.md explaining vision
- [ ] Write CLAUDE.md for the discovery tool itself
- [ ] Set up Python environment, dependencies

### Week 2: Core Search
- [ ] Implement topic-based pre-filtering (prefilter.py)
- [ ] Implement GitHub API search for discovery patterns in pre-filtered repos (search.py)
- [ ] Handle pagination and rate limiting
- [ ] Output initial results (10-20 repos)
- [ ] Manual review: Do these look promising?

### Week 3: Extraction & Analysis
- [ ] Implement contact extraction
- [ ] Implement basic quality scoring
- [ ] Generate first discoveries.json
- [ ] Document patterns observed

### Week 4: Refinement & Outreach
- [ ] Refine quality scoring based on findings
- [ ] Generate human-readable DISCOVERIES.md
- [ ] Identify top 3 potential peers
- [ ] Draft outreach message
- [ ] Send first contact

### Success After 30 Days
- **Quantitative**: 10+ repos discovered, 5+ contacts extracted
- **Qualitative**: 1 meaningful conversation with a peer who "gets it"

## The Bigger Picture

This isn't just a discovery tool. It's a test of the hypothesis:

> **AI-native architecture is emerging as a distinct discipline, and discovery-based documentation is the pattern that makes it visible.**

If we find peers, the hypothesis is validated. If those peers have production implementations, the pattern is proven. If we can learn from each other, the ecosystem accelerates.

This is how movements start: not with manifestos, but with people independently discovering truth and finding each other.

## Next Steps

1. **Create the repository**: `claude-discovery` at `/workspace/claude-discovery/`
2. **Write the README**: Public-facing vision statement
3. **Write the CLAUDE.md**: Self-documenting, meta
4. **Implement search.py**: First working code
5. **Run first search**: See what we find
6. **Iterate**: Learn, refine, discover

---

**This plan is a living document.** As we discover peers and patterns, we'll update our understanding and approach. The goal isn't to execute a fixed plan - it's to find the people who can help us discover what this really is.

**Status:** Planning revised with two-stage topic pre-filtering approach
**Author:** Human architect + AI collaborator
**Date:** 2025-01-24 (revised 2025-11-25)
**Version:** 1.1 - Added topic-based pre-filtering strategy
