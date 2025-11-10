# Claude Code Sandbox - Shared Devcontainer Configuration

This configuration provides a sandboxed Claude Code environment shared across multiple projects using Docker Compose.

## Directory Structure

```
/home/devex/dev/
├── orchestration/
│   ├── claude-code-sandbox/          ← Shared configuration (this directory)
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   ├── entrypoint.sh
│   │   └── README.md
│   └── .devcontainer/
│       └── devcontainer.json
├── transaction-service/
│   └── .devcontainer/
│       └── devcontainer.json
├── budget-analyzer-web/
│   └── .devcontainer/
│       └── devcontainer.json
├── currency-service/
│   └── .devcontainer/
│       └── devcontainer.json
└── service-common/
    └── .devcontainer/
        └── devcontainer.json
```

## Installation

### 1. Set Up Shared Configuration

```bash
# Navigate to orchestration project
cd /home/devex/dev/orchestration

# Create claude-code-sandbox directory if it doesn't exist
mkdir -p claude-code-sandbox

# Copy these files into claude-code-sandbox/:
# - Dockerfile
# - docker-compose.yml
# - entrypoint.sh
# - README.md (this file)

# Make entrypoint script executable
chmod +x claude-code-sandbox/entrypoint.sh
```

### 2. Set Up Each Project's Devcontainer

For each project, create a `.devcontainer` directory and copy the corresponding devcontainer.json file:

```bash
# orchestration
mkdir -p /home/devex/dev/orchestration/.devcontainer
# Copy orchestration-devcontainer.json as devcontainer.json

# transaction-service
mkdir -p /home/devex/dev/transaction-service/.devcontainer
# Copy transaction-service-devcontainer.json as devcontainer.json

# budget-analyzer-web
mkdir -p /home/devex/dev/budget-analyzer-web/.devcontainer
# Copy budget-analyzer-web-devcontainer.json as devcontainer.json

# currency-service
mkdir -p /home/devex/dev/currency-service/.devcontainer
# Copy currency-service-devcontainer.json as devcontainer.json

# service-common
mkdir -p /home/devex/dev/service-common/.devcontainer
# Copy service-common-devcontainer.json as devcontainer.json
```

### 3. Configure API Key

```bash
# Add to ~/.bashrc or ~/.zshrc
export ANTHROPIC_API_KEY="your-api-key-here"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

### 4. Verify Setup

```bash
# Check API key is set
echo $ANTHROPIC_API_KEY

# Verify file structure
ls -la /home/devex/dev/orchestration/claude-code-sandbox/
ls -la /home/devex/dev/orchestration/.devcontainer/
ls -la /home/devex/dev/transaction-service/.devcontainer/
```

## Usage

### Opening a Project

```bash
# Open any project in VS Code
code /home/devex/dev/orchestration

# VS Code will detect the devcontainer configuration
# Click "Reopen in Container" when prompted
# Or: F1 → "Dev Containers: Reopen in Container"
```

### First Time Setup

The first time you open a project:
1. Docker will build the image (takes 5-10 minutes)
2. Container starts and mounts your workspace
3. Claude Code extension installs automatically
4. Container remains running (due to `shutdownAction: none`)

### Subsequent Opens

When opening other projects:
1. Reuses the existing container (instant startup)
2. Changes workspace folder to the opened project
3. Same tools and environment available

### Using Claude Code

1. Click the **Spark icon** (⚡) in the VS Code sidebar
2. Claude Code panel opens
3. Start working: "Add unit tests to UserService.java"

### Switching Projects

You can have multiple VS Code windows open, each connected to the same container but with different workspace folders:

```bash
# Terminal 1
code /home/devex/dev/transaction-service

# Terminal 2
code /home/devex/dev/budget-analyzer-web
```

Both windows share the same container and tools but focus on different projects.

## Configuration Details

### Container User
- User: `vscode`
- UID: 1002
- GID: 1002
- Matches your host user to prevent permission issues

### Mounted Directories
- `/home/devex/dev` → `/workspace` (read/write)
- `/home/devex/dev/orchestration/claude-code-sandbox` → `/workspace/orchestration/claude-code-sandbox` (read-only)

### Installed Tools
- Node.js (latest LTS)
- JDK 24
- Maven 3.9.9
- Python 3 (Ubuntu default)
- Git
- Claude Code CLI

### Security Features
- Claude Code sandbox directory mounted read-only
- Cannot modify Dockerfile, docker-compose.yml, or entrypoint.sh
- Container user matches host user (no root access needed)

## Workspace Access

From within the container, all projects are accessible:

```bash
# Inside container terminal
ls /workspace
# Shows: orchestration, transaction-service, budget-analyzer-web, currency-service, service-common

cd /workspace/transaction-service
cd /workspace/currency-service
```

Claude Code can reference files across all projects:
```
"Compare the error handling in transaction-service 
with the approach in currency-service"
```

## Troubleshooting

### Container Not Starting

```bash
# Check if container is running
docker ps | grep claude-dev

# View container logs
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml logs

# Rebuild container
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml build --no-cache
```

### Permission Errors

```bash
# Inside container
sudo chown -R vscode:vscode /workspace

# Or from host
docker exec -it <container-id> sudo chown -R vscode:vscode /workspace
```

### API Key Not Found

```bash
# Verify environment variable on host
echo $ANTHROPIC_API_KEY

# Check it's passed to container
docker exec -it <container-id> printenv ANTHROPIC_API_KEY
```

### Extension Not Installing

```bash
# Manually install in VS Code
# Extensions sidebar → Search "anthropic.claude-code"
# Install in container
```

### Cannot Modify Sandbox Files

This is intentional - the sandbox directory is mounted read-only for security. To modify configuration:

1. Exit all devcontainer VS Code windows
2. Stop the container: `docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml down`
3. Edit files on host: `/home/devex/dev/orchestration/claude-code-sandbox/`
4. Restart: Open any project in VS Code and reopen in container

### Java Version Issues

```bash
# Verify Java installation
java --version

# Check JAVA_HOME
echo $JAVA_HOME

# Maven should use the correct Java
mvn --version
```

## Modifying Configuration

### Adding More Tools

Edit `Dockerfile` and rebuild:

```dockerfile
# Add PostgreSQL client
RUN apt-get update && apt-get install -y postgresql-client

# Add additional npm packages globally
RUN npm install -g @angular/cli
```

Then rebuild:
```bash
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml build
```

### Changing Java or Maven Versions

Edit the version URLs in `Dockerfile` and rebuild.

### Adding VS Code Extensions

Edit any project's `devcontainer.json`:

```json
"customizations": {
  "vscode": {
    "extensions": [
      "anthropic.claude-code",
      "vscjava.vscode-java-pack"
    ]
  }
}
```

Note: Extensions are per-project, not shared across all projects.

### Network Configuration

Currently using `network_mode: host` for simplicity. To use bridge networking:

Edit `docker-compose.yml`:
```yaml
network_mode: bridge
ports:
  - "3000:3000"
  - "8080:8080"
```

## Best Practices

1. **Always specify project in Claude Code prompts**: "In transaction-service, add validation..."
2. **Keep sandbox directory in git**: Commit to orchestration repo for version control
3. **Use shutdownAction: none**: Keeps container running when switching between projects
4. **Run services from host**: Don't run dev servers inside the container
5. **Git operations from host**: Commit and push from your host terminal
6. **One container, multiple windows**: Open different projects in separate VS Code windows

## Maintenance

### Updating Tools

```bash
# Stop container
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml down

# Update Dockerfile with new versions

# Rebuild
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml build --no-cache

# Restart by opening any project in VS Code
```

### Cleaning Up

```bash
# Stop container
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml down

# Remove volumes (loses Claude Code credentials)
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml down -v

# Remove images
docker-compose -f /home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml down --rmi all
```

## File Naming Reference

When copying files from the outputs directory:

| Output File | Destination |
|------------|-------------|
| `Dockerfile` | `/home/devex/dev/orchestration/claude-code-sandbox/Dockerfile` |
| `docker-compose.yml` | `/home/devex/dev/orchestration/claude-code-sandbox/docker-compose.yml` |
| `entrypoint.sh` | `/home/devex/dev/orchestration/claude-code-sandbox/entrypoint.sh` |
| `orchestration-devcontainer.json` | `/home/devex/dev/orchestration/.devcontainer/devcontainer.json` |
| `transaction-service-devcontainer.json` | `/home/devex/dev/transaction-service/.devcontainer/devcontainer.json` |
| `budget-analyzer-web-devcontainer.json` | `/home/devex/dev/budget-analyzer-web/.devcontainer/devcontainer.json` |
| `currency-service-devcontainer.json` | `/home/devex/dev/currency-service/.devcontainer/devcontainer.json` |
| `service-common-devcontainer.json` | `/home/devex/dev/service-common/.devcontainer/devcontainer.json` |
