#!/bin/bash

# Reset Local Development Databases
# This script drops and recreates all local Docker databases for development
# WARNING: This will delete ALL data in the development databases!

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Development Database Reset Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Confirmation prompt
read -p "$(echo -e ${RED}WARNING: This will delete ALL data in the development databases. Continue? [y/N]:${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Aborted.${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Step 1: Stopping PostgreSQL container...${NC}"
docker compose stop shared-postgres 2>/dev/null || echo "Container already stopped"

echo ""
echo -e "${YELLOW}Step 2: Removing PostgreSQL container...${NC}"
docker compose rm -f shared-postgres 2>/dev/null || echo "Container already removed"

echo ""
echo -e "${YELLOW}Step 3: Removing PostgreSQL volume...${NC}"
docker volume rm orchestration_shared-pgdata 2>/dev/null || echo "Volume already removed or doesn't exist"

echo ""
echo -e "${YELLOW}Step 4: Starting PostgreSQL container...${NC}"
echo "This will automatically recreate the databases using init scripts..."
docker compose up -d shared-postgres

echo ""
echo -e "${YELLOW}Step 5: Waiting for PostgreSQL to be ready...${NC}"
echo "Waiting 10 seconds for database initialization..."
sleep 10

# Check if PostgreSQL is ready
echo ""
echo -e "${YELLOW}Step 6: Verifying database connection...${NC}"
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    if docker exec shared-postgres pg_isready -U budget_analyzer > /dev/null 2>&1; then
        echo -e "${GREEN}PostgreSQL is ready!${NC}"
        break
    fi

    if [ $attempt -eq $max_attempts ]; then
        echo -e "${RED}Failed to connect to PostgreSQL after $max_attempts attempts${NC}"
        exit 1
    fi

    echo "Waiting for PostgreSQL to be ready... (attempt $attempt/$max_attempts)"
    sleep 2
    ((attempt++))
done

echo ""
echo -e "${YELLOW}Step 7: Listing created databases...${NC}"
docker exec shared-postgres psql -U budget_analyzer -d postgres -c "\l" | grep -E "budget_analyzer|currency|permission|Name"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Database reset completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Databases created:"
echo "  - budget_analyzer (for transaction-service)"
echo "  - currency (for currency-service)"
echo "  - permission (for permission-service)"
echo ""
echo "Connection details:"
echo "  Host: localhost"
echo "  Port: 5432"
echo "  User: budget_analyzer"
echo "  Password: budget_analyzer"
echo ""
echo "To connect to a database:"
echo "  docker exec -it shared-postgres psql -U budget_analyzer -d budget_analyzer"
echo "  docker exec -it shared-postgres psql -U budget_analyzer -d currency"
echo "  docker exec -it shared-postgres psql -U budget_analyzer -d permission"
echo ""
