#!/bin/bash

# Flush Redis Cache (Kubernetes/Tilt)
# Clears all Redis data including sessions
#
# Usage:
#   ./flush-redis.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Redis Flush Script (Kubernetes)${NC}"
echo ""

read -p "$(echo -e ${RED}WARNING: This will delete ALL Redis data including sessions. Continue? [y/N]:${NC} )" -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && echo "Aborted." && exit 0

echo ""
echo -e "${YELLOW}Flushing Redis...${NC}"
echo ""

# Find Redis pod
REDIS_POD=$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$REDIS_POD" ]; then
    echo -e "${RED}Redis pod not found in infrastructure namespace${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Is Tilt running? Try: tilt up"
    echo "  2. Check pods: kubectl get pods -n infrastructure"
    exit 1
fi

echo -e "${YELLOW}Using Redis pod: $REDIS_POD${NC}"
echo ""

# Flush all Redis data
kubectl exec -n infrastructure "$REDIS_POD" -- redis-cli FLUSHALL > /dev/null 2>&1

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SUCCESS! Redis has been flushed${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "All sessions and cached data have been ${GREEN}cleared${NC}."
echo -e "Users will need to log in again."
echo ""
