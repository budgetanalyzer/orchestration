# {Frontend Name} - {Brief Description}

## Application Purpose
{2-3 sentences describing frontend application}

**Type**: React {version} web application
**Responsibilities**:
- {Key responsibility 1}
- {Key responsibility 2}
- {Key responsibility 3}

## Frontend Patterns

### Technology Stack

**Discovery**:
```bash
# View dependencies
cat package.json

# React version
cat package.json | grep '"react"'
```

**Key technologies**:
- React {version}
- {State management library}
- {Routing library}
- {UI component library}

### API Integration

**Pattern**: All API calls go through NGINX gateway at `http://localhost:8080/api/*`

See [@orchestration/nginx/nginx.dev.conf](https://github.com/budget-analyzer/orchestration/blob/main/nginx/nginx.dev.conf) for available routes.

**Discovery**:
```bash
# See all API routes
cat orchestration/nginx/nginx.dev.conf | grep "location /api"
```

**Usage**:
```javascript
// Always use relative paths
fetch('/api/v1/transactions')
  .then(res => res.json())

// Never hardcode service URLs
// ❌ fetch('http://localhost:8082/transactions')
// ✅ fetch('/api/v1/transactions')
```

### Component Structure

**Discovery**:
```bash
# Find all components
find src/components -name "*.jsx" -o -name "*.tsx"
```

**Organization**:
{Describe component organization pattern}

### State Management

{Describe state management approach}

See @docs/state-management.md

### Routing

{Describe routing strategy}

See @docs/routing.md

## Running Locally

```bash
# Install dependencies
npm install

# Start dev server (with hot reload)
npm start

# Access application
open http://localhost:3000
```

**Note**: Backend services must be running (see [@orchestration/docs/development/local-environment.md](https://github.com/budget-analyzer/orchestration/blob/main/docs/development/local-environment.md))

## Building

```bash
# Production build
npm run build

# Output in build/ directory
ls -lh build/
```

## Discovery Commands

```bash
# View available scripts
cat package.json | grep -A 10 '"scripts"'

# Check for unused dependencies
npx depcheck

# Bundle analysis
npm run build && npx webpack-bundle-analyzer build/stats.json
```

## AI Assistant Guidelines

1. **Follow React best practices** - {Link to team conventions}
2. **API calls through gateway** - Always use `/api/*` paths
3. **Component patterns** - See @docs/component-patterns.md
4. **Testing** - {Testing strategy}
5. {Frontend-specific guideline}
