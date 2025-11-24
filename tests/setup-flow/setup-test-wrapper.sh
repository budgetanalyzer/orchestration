#!/bin/bash

# setup-test-wrapper.sh - Wrapper to run setup.sh in test mode
#
# This script modifies the setup.sh behavior for testing:
# - Skips the git clone step (repos are pre-copied)
# - Automatically answers "yes" to DNS prompt
# - Runs all other steps normally

set -e

REPOS_DIR="/repos"
ORCHESTRATION_DIR="$REPOS_DIR/orchestration"

# Colors for output
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Setup Test Wrapper - Running setup.sh in test mode${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

cd "$ORCHESTRATION_DIR"

# Export environment variable to skip git clone
export SKIP_GIT_CLONE=true
export BA_TEST_MODE=true

# Create a modified clone-repos.sh that just validates
cat > /tmp/clone-repos-test.sh << 'EOF'
#!/bin/bash
# Test version: just validates repos exist, doesn't clone

REPOS_DIR="/repos"
REPOS=(
    "service-common"
    "transaction-service"
    "currency-service"
    "budget-analyzer-web"
    "session-gateway"
    "token-validation-service"
    "permission-service"
)

echo "[INFO] Test mode: Validating repositories exist..."

for repo in "${REPOS[@]}"; do
    if [ -d "$REPOS_DIR/$repo" ]; then
        echo "[OK] $repo exists"
    else
        echo "[ERROR] $repo not found"
        exit 1
    fi
done

echo "[SUCCESS] All repositories validated!"
EOF

chmod +x /tmp/clone-repos-test.sh

# Temporarily replace clone-repos.sh
cp "$ORCHESTRATION_DIR/scripts/clone-repos.sh" /tmp/clone-repos-backup.sh
cp /tmp/clone-repos-test.sh "$ORCHESTRATION_DIR/scripts/clone-repos.sh"

# Run setup.sh with auto-yes for DNS prompt
echo "y" | "$ORCHESTRATION_DIR/setup.sh"

# Restore original clone-repos.sh
cp /tmp/clone-repos-backup.sh "$ORCHESTRATION_DIR/scripts/clone-repos.sh"

echo ""
echo -e "${BLUE}Setup wrapper completed${NC}"
