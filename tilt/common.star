# ============================================================================
# Budget Analyzer - Common Tilt Configuration
# ============================================================================

# Workspace configuration
# This is the parent directory containing all repositories
config.define_string('main-dir', args=False, usage='Parent directory containing all repos')
cfg = config.parse()

# Get the directory containing the Tiltfile (orchestration repo)
# Then get its parent to find sibling repositories
_tiltfile_dir = config.main_dir
_workspace_default = os.path.dirname(_tiltfile_dir)

# Allow override via config, default to parent of orchestration directory
WORKSPACE = cfg.get('main-dir', _workspace_default)

# Kubernetes namespaces
DEFAULT_NAMESPACE = 'default'
INFRA_NAMESPACE = 'infrastructure'

# Service ports mapping
SERVICE_PORTS = {
    'transaction-service': 8082,
    'currency-service': 8084,
    'permission-service': 8086,
    'token-validation-service': 8088,
    'session-gateway': 8081,
    'budget-analyzer-web': 3000,
    'nginx-gateway': 8080,
}

# Debug ports for remote debugging
DEBUG_PORTS = {
    'transaction-service': 5006,
    'currency-service': 5007,
    'permission-service': 5008,
    'token-validation-service': 5010,
    'session-gateway': 5009,
}

def get_repo_path(name):
    """
    Get the full path to a service repository.

    Args:
        name: Service name (must match repository directory name)

    Returns:
        Full path to the repository
    """
    return WORKSPACE + '/' + name
