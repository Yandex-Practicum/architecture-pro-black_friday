#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}=========================================${NC}"
echo -e "${RED}Resetting MongoDB Sharding Cluster${NC}"
echo -e "${RED}=========================================${NC}"

read -p "Are you sure you want to reset the cluster? This will DELETE ALL DATA! (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Reset cancelled${NC}"
    exit 1
fi

echo -e "\n${YELLOW}[1/3] Stopping and removing containers...${NC}"
cd ..
docker-compose -f compose.yaml down -v

echo -e "\n${YELLOW}[2/3] Removing volumes...${NC}"
docker volume rm config-data shard1-data shard2-data 2>/dev/null
docker volume prune -f

echo -e "\n${YELLOW}[3/3] Starting fresh cluster...${NC}"
docker-compose -f compose.yaml up -d

echo -e "\n${GREEN}✓ Cluster reset completed!${NC}"
echo -e "${YELLOW}Run ./init-cluster.sh to initialize the cluster${NC}"
read -p ""