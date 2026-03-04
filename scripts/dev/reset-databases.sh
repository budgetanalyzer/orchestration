#!/bin/bash

# Reset Local Development Databases (Kubernetes/Tilt)
# Drops and recreates all databases, or truncates all tables (--data-only)
#
# Usage:
#   ./reset-databases.sh            # Full reset: drop and recreate databases
#   ./reset-databases.sh --data-only # Keep schema, delete all rows

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DATA_ONLY=false
DATABASES=("budget_analyzer" "currency" "permission")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --data-only)
            DATA_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--data-only]"
            echo ""
            echo "Options:"
            echo "  --data-only  Keep tables, just delete all rows (TRUNCATE)"
            echo "  (default)    Drop and recreate databases entirely"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [ "$DATA_ONLY" = true ]; then
    echo -e "${YELLOW}Database Data Reset Script (Kubernetes)${NC}"
    echo -e "${YELLOW}Mode: Truncate all tables (keep schema)${NC}"
else
    echo -e "${YELLOW}Database Reset Script (Kubernetes)${NC}"
    echo -e "${YELLOW}Mode: Drop and recreate databases${NC}"
fi
echo ""

read -p "$(echo -e ${RED}WARNING: This will delete ALL data. Continue? [y/N]:${NC} )" -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && echo "Aborted." && exit 0

echo ""
echo -e "${YELLOW}Starting database reset...${NC}"
echo ""

# Find PostgreSQL pod
POSTGRES_POD=$(kubectl get pods -n infrastructure -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POSTGRES_POD" ]; then
    echo -e "${RED}PostgreSQL pod not found in infrastructure namespace${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Is Tilt running? Try: tilt up"
    echo "  2. Check pods: kubectl get pods -n infrastructure"
    exit 1
fi

echo -e "${YELLOW}Using PostgreSQL pod: $POSTGRES_POD${NC}"
echo ""

RESET_COUNT=0

if [ "$DATA_ONLY" = true ]; then
    # Truncate all tables in each database
    for DB in "${DATABASES[@]}"; do
        echo -n -e "${YELLOW}Truncating all tables in $DB...${NC} "

        # Check if database exists
        DB_EXISTS=$(kubectl exec -n infrastructure "$POSTGRES_POD" -- \
            psql -U budget_analyzer -d postgres -tAc \
            "SELECT 1 FROM pg_database WHERE datname='$DB';" 2>/dev/null)

        if [ "$DB_EXISTS" != "1" ]; then
            echo -e "${YELLOW}skipped (not found)${NC}"
            continue
        fi

        # Truncate all tables in public schema
        kubectl exec -n infrastructure "$POSTGRES_POD" -- \
            psql -U budget_analyzer -d "$DB" -c "
DO \$\$
DECLARE
    tables_list TEXT;
BEGIN
    SELECT string_agg(quote_ident(tablename), ', ')
    INTO tables_list
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename != 'flyway_schema_history';

    IF tables_list IS NOT NULL AND tables_list != '' THEN
        EXECUTE 'TRUNCATE TABLE ' || tables_list || ' CASCADE';
    END IF;
END \$\$;
" > /dev/null 2>&1

        echo -e "${GREEN}done${NC}"
        ((RESET_COUNT++))
    done
else
    # Drop and recreate each database
    for DB in "${DATABASES[@]}"; do
        echo -n -e "${YELLOW}Dropping and recreating $DB...${NC} "

        # Terminate existing connections
        kubectl exec -n infrastructure "$POSTGRES_POD" -- \
            psql -U budget_analyzer -d postgres -c \
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB' AND pid != pg_backend_pid();" \
            > /dev/null 2>&1 || true

        kubectl exec -n infrastructure "$POSTGRES_POD" -- \
            psql -U budget_analyzer -d postgres -c "DROP DATABASE IF EXISTS $DB;" \
            > /dev/null 2>&1

        kubectl exec -n infrastructure "$POSTGRES_POD" -- \
            psql -U budget_analyzer -d postgres -c "CREATE DATABASE $DB OWNER budget_analyzer;" \
            > /dev/null 2>&1

        echo -e "${GREEN}done${NC}"
        ((RESET_COUNT++))
    done
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SUCCESS! Reset $RESET_COUNT database(s)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$DATA_ONLY" = true ]; then
    echo -e "All table data has been ${GREEN}deleted${NC} (schema preserved)."
    echo -e "Flyway migration history was preserved."
else
    echo -e "Databases have been ${GREEN}dropped and recreated${NC}."
    echo ""
    echo "Restart services to run migrations:"
    echo -e "  ${YELLOW}tilt trigger transaction-service${NC}"
    echo -e "  ${YELLOW}tilt trigger currency-service${NC}"
    echo -e "  ${YELLOW}tilt trigger permission-service${NC}"
    echo ""
    echo "Or restart everything:"
    echo -e "  ${YELLOW}tilt down && tilt up${NC}"
fi
echo ""
