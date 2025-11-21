# Claude Code Sandbox - Shared VS Code Devcontainer Configuration

This directory contains a shared Docker-based development environment for Claude Code in VS Code that works across all Budget Analyzer projects. The environment is already set up and configured.

## What This Is

A single Docker container that provides a consistent development environment for all projects in the Budget Analyzer ecosystem. You open the orchestration project in VS Code's devcontainer, and from there you have access to all service repositories:

- **🔒 SECURITY: Sandbox Claude Code file access to only the /workspace directory on the host**
- Use the same tools (JDK, Node.js, Maven, Git) across all projects
- Have Claude Code work seamlessly across the entire codebase in VS Code
- Maintain consistent development environments

## Why This Matters

**Claude Code gets a complete Linux system with full sudo access** - and that's the point.

When Claude runs directly on your host machine, you're naturally cautious about what it can do. But inside this container, Claude has unrestricted access to:

- **Full root privileges**: `sudo apt-get install anything` - compilers, libraries, database clients, whatever the task needs
- **System-level operations**: Modify configurations, install global packages, compile from source
- **Safe experimentation**: Try approaches that might fail spectacularly - the container is disposable

This isn't just about security (though it is secure). It's about **removing friction**. Claude can install a missing tool, configure a service, or run commands that would make you nervous on your actual machine - all without risk. Your host system is completely isolated.

If something goes wrong? `docker compose down && docker compose up`. Fresh start, zero consequences.

**The tradeoff**: A bit more setup complexity in exchange for maximum capability with zero risk to your development machine.

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
├── transaction-service/                ← Accessible from container
├── budget-analyzer-web/                ← Accessible from container
├── currency-service/                   ← Accessible from container
└── service-common/                     ← Accessible from container
```

## How It Works

**Single Entry Point**: Open the orchestration project in VS Code and reopen in the devcontainer. The container mounts your entire workspace root as `/workspace`, giving you access to all service repositories from one place.

**Key Components**:
- [Dockerfile](../claude-code-sandbox/Dockerfile) - Defines the container image with all development tools
- [docker-compose.yml](../claude-code-sandbox/docker-compose.yml) - Configures container networking, volumes, and environment
- [entrypoint.sh](../claude-code-sandbox/entrypoint.sh) - Initializes the container and keeps it running
- [.devcontainer/devcontainer.json](../.devcontainer/devcontainer.json) - VS Code configuration that starts the container

## Usage

### Opening the Development Environment
```bash
# Open orchestration in VS Code
code ./orchestration

# VS Code will detect the devcontainer configuration
# Click "Reopen in Container" when prompted
# Or: F1 → "Dev Containers: Reopen in Container"
```

### How Container Startup Works

**First time:**
1. Docker builds the image from Dockerfile (takes 5-10 minutes)
2. Container starts and mounts your workspace
3. Claude Code extension installs automatically
4. Container remains running (due to `shutdownAction: none`)

**Subsequent times:**
1. Reuses the existing container (instant startup)
2. Same tools and environment available

### Using Claude Code in VS Code

1. Click the Spark icon (⚡) in the VS Code sidebar
2. Claude Code panel opens
3. Start working: "Add unit tests to UserService.java in transaction-service"

### Working Across Multiple Projects

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

### Safe Power Through Isolation

The container design gives Claude maximum capability while protecting your system:

**What Claude CAN do (inside container)**:
- Run `sudo` commands freely
- Install any package via `apt-get`
- Modify system configurations
- Install global npm/pip packages
- Compile and build anything
- Create, modify, delete files in `/workspace`

**What Claude CANNOT do**:
- Access files outside `/workspace`
- Affect your host system's packages or configuration
- Modify the sandbox configuration itself (mounted read-only)
- Persist changes outside the container's designated volumes

**Self-protecting configuration**: The sandbox directory (`claude-code-sandbox/`) is mounted read-only inside the container. Claude cannot modify its own container configuration - even accidentally. To update the Dockerfile or docker-compose.yml, you must edit from outside the container on your host machine. This prevents Claude from inadvertently breaking its own environment.

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

This is intentional - the sandbox directory is mounted read-only so Claude cannot modify its own container configuration. To modify configuration:

1. Exit the devcontainer VS Code window
2. Stop the container: `docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml down`
3. Edit files on host: `./orchestration/claude-code-sandbox/`
4. Rebuild: `docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml build`
5. Restart: Open orchestration in VS Code and reopen in container

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

Edit `.devcontainer/devcontainer.json` in orchestration:
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
- **Read-only sandbox is intentional**: Prevents Claude from modifying its own configuration

## Maintenance

### Updating Tools
```bash
# Stop container
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml down

# Update Dockerfile with new versions (on host, outside container)

# Rebuild
docker compose -f ./orchestration/claude-code-sandbox/docker-compose.yml build --no-cache

# Restart by opening orchestration in VS Code
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
- Single `.devcontainer/devcontainer.json` in orchestration starts the environment
- All service repositories accessible under `/workspace`
- Container stays running (`shutdownAction: none`) for fast reconnection

This provides the benefits of containerization (consistency, isolation) without the overhead of managing multiple containers or configurations.
