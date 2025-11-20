# Claude Code Sandbox - Shared VS Code Devcontainer Configuration

This directory contains a shared Docker-based development environment for Claude Code in VS Code that works across all Budget Analyzer projects. The environment is already set up and configured.

## What This Is

A single Docker container that provides a consistent development environment for all projects in the Budget Analyzer ecosystem. Each project has its own `.devcontainer/devcontainer.json` that connects to this shared container, allowing you to:

- Use the same tools (JDK, Node.js, Maven, Git) across all projects
- Switch between projects instantly without rebuilding containers
- Have Claude Code work seamlessly across the entire codebase in VS Code
- Maintain consistent development environments
- **🔒 SECURITY: Sandbox Claude Code file access to only the /workspace directory on the host**

## Directory Structure
```
<your-workspace>/
├── orchestration/
│   ├── claude-code-sandbox/          ← Shared configuration (this directory)
│   │   ├── Dockerfile                  Container image definition
│   │   ├── docker-compose.yml          Container orchestration
│   │   ├── entrypoint.sh               Container initialization
│   │   └── README.md                   This file
│   └── .devcontainer/
│       └── devcontainer.json           VS Code devcontainer config
├── transaction-service/
│   └── .devcontainer/
│       └── devcontainer.json           Points to shared container
├── budget-analyzer-web/
│   └── .devcontainer/
│       └── devcontainer.json           Points to shared container
├── currency-service/
│   └── .devcontainer/
│       └── devcontainer.json           Points to shared container
└── service-common/
    └── .devcontainer/
        └── devcontainer.json           Points to shared container
```

## How It Works

**Single Container, Multiple Projects**: One Docker container (`claude-dev`) runs continuously and mounts your workspace root as `/workspace`. Each project's devcontainer configuration connects to this same container but changes the workspace folder to focus on that specific project.

**Key Components**:
- [Dockerfile](Dockerfile) - Defines the container image with all development tools
- [docker-compose.yml](docker-compose.yml) - Configures container networking, volumes, and environment
- [entrypoint.sh](entrypoint.sh) - Initializes the container and keeps it running
- Each `.devcontainer/devcontainer.json` - VS Code configuration that connects to the shared container

## Usage

### Opening a Project in VS Code
```bash
# Open any project in VS Code
code ./orchestration
code ./transaction-service
code ./budget-analyzer-web

# VS Code will detect the devcontainer configuration
# Click "Reopen in Container" when prompted
# Or: F1 → "Dev Containers: Reopen in Container"
```

### How Container Startup Works

**First time opening any project:**
1. Docker builds the image from Dockerfile (takes 5-10 minutes)
2. Container starts and mounts your workspace
3. Claude Code extension installs automatically
4. Container remains running (due to `shutdownAction: none`)

**Opening additional projects:**
1. Reuses the existing container (instant startup)
2. Changes workspace folder to the opened project
3. Same tools and environment available

### Using Claude Code in VS Code

1. Click the Spark icon (⚡) in the VS Code sidebar
2. Claude Code panel opens
3. Start working: "Add unit tests to UserService.java"

### Working Across Multiple Projects

You can have multiple VS Code windows open simultaneously, each connected to the same container but with different workspace folders:
```bash
# Terminal 1
code ./transaction-service

# Terminal 2
code ./budget-analyzer-web
```

Both windows share the same container and tools but focus on different projects.

## Configuration Details

### Container User

- User: `vscode`
- UID: 1001
- GID: 1001
- Setup automatically detects and matches your host user to prevent permission issues

### Mounted Directories

- `<workspace-root>` → `/workspace` (read/write) - All projects accessible
- `<workspace-root>/orchestration/claude-code-sandbox` → `/workspace/orchestration/claude-code-sandbox` (read-only) - Prevents accidental config changes

### Installed Tools

- Node.js (latest LTS)
- JDK 24
- Maven 3.9.9
- Python 3 (Ubuntu default)
- Git
- Claude Code CLI

### Security Features

- Sandbox directory mounted read-only for safety
- Container user matches host user (no root access needed)
- API key passed securely via environment variable

### Workspace Access

From within the container, all projects are accessible under `/workspace`:
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
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml logs

# Rebuild container
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml build --no-cache
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
2. Stop the container: `docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml down`
3. Edit files on host: `./orchestration/claude-code-sandbox/`
4. Rebuild: `docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml build`
5. Restart: Open any project in VS Code and reopen in container

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

Edit Dockerfile on your host machine and rebuild:
```dockerfile
# Example: Add PostgreSQL client
RUN apt-get update && apt-get install -y postgresql-client

# Example: Add additional npm packages globally
RUN npm install -g @angular/cli
```

Then rebuild:
```bash
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml build --no-cache
```

### Changing Java or Maven Versions

Edit the version URLs in Dockerfile and rebuild.

### Adding VS Code Extensions

Edit any project's `.devcontainer/devcontainer.json`:
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

Note: Extensions are per-project configuration, though they run in the shared container.

### Network Configuration

Currently using `network_mode: host` for simplicity - the container shares the host's network stack. This means:

- Services running in the container are accessible on localhost
- No port mapping needed
- Container can access host services directly

To use bridge networking instead, edit docker-compose.yml:
```yaml
network_mode: bridge
ports:
  - "3000:3000"
  - "8080:8080"
```

## Best Practices

- **Always specify project in Claude Code prompts**: "In transaction-service, add validation..."
- **Keep sandbox directory in git**: Already committed to orchestration repo for version control
- **Run services from host**: Don't run dev servers inside the container - use host terminal
- **Git operations from host**: Commit and push from your host terminal, not container
- **One container, multiple windows**: Open different projects in separate VS Code windows
- **Read-only sandbox is intentional**: Prevents accidental changes to shared configuration

## Maintenance

### Updating Tools
```bash
# Stop container
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml down

# Update Dockerfile with new versions (on host, outside container)

# Rebuild
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml build --no-cache

# Restart by opening any project in VS Code
```

### Cleaning Up
```bash
# Stop container
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml down

# Remove volumes (loses Claude Code credentials)
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml down -v

# Remove images
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml down --rmi all
```

## Architecture Notes

This setup follows the shared devcontainer pattern:

- One Dockerfile builds the base image with all tools
- One docker-compose.yml defines the container lifecycle
- Multiple `.devcontainer/devcontainer.json` files reference the same container
- VS Code's `workspaceFolder` setting determines which project is active
- Container stays running (`shutdownAction: none`) for fast project switching

This provides the benefits of containerization (consistency, isolation) without the overhead of managing multiple containers for each project.
