#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Testing Replication and Failover${NC}"
echo -e "${BLUE}=========================================${NC}"

# 1. Проверка текущего primary в Shard1
echo -e "\n${YELLOW}Current Shard1 Primary:${NC}"
PRIMARY=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
echo -e "${GREEN}$PRIMARY${NC}"

# 2. Проверка синхронизации данных
echo -e "\n${YELLOW}Data synchronization check:${NC}"
PRIMARY_COUNT=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null)
SECONDARY1_COUNT=$(docker exec shard1_secondary1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null)
SECONDARY2_COUNT=$(docker exec shard1_secondary2 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null)

echo -e "Primary: ${GREEN}$PRIMARY_COUNT${NC} documents"
echo -e "Secondary1: ${GREEN}$SECONDARY1_COUNT${NC} documents"
echo -e "Secondary2: ${GREEN}$SECONDARY2_COUNT${NC} documents"

if [ "$PRIMARY_COUNT" -eq "$SECONDARY1_COUNT" ] && [ "$PRIMARY_COUNT" -eq "$SECONDARY2_COUNT" ]; then
    echo -e "${GREEN}✓ Data is synchronized across all replicas${NC}"
else
    echo -e "${RED}✗ Data mismatch detected!${NC}"
fi

# 3. Тест автоматического переключения
echo -e "\n${YELLOW}Testing automatic failover...${NC}"
echo -e "${RED}Stopping Shard1 Primary...${NC}"
docker stop shard1_primary

echo -e "${YELLOW}Waiting for election (15 seconds)...${NC}"
sleep 15

NEW_PRIMARY=$(docker exec shard1_secondary1 mongosh --port 27018 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
echo -e "${GREEN}New Primary elected: $NEW_PRIMARY${NC}"

# Проверка доступности данных
echo -e "\n${YELLOW}Checking data availability after failover:${NC}"
NEW_PRIMARY_COUNT=$(docker exec shard1_secondary1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null)
echo -e "Documents available: ${GREEN}$NEW_PRIMARY_COUNT${NC}"

if [ "$NEW_PRIMARY_COUNT" -eq "$PRIMARY_COUNT" ]; then
    echo -e "${GREEN}✓ Failover successful! Data is intact.${NC}"
else
    echo -e "${RED}✗ Failover issue detected!${NC}"
fi

# 4. Восстановление
echo -e "\n${YELLOW}Restarting original primary...${NC}"
docker start shard1_primary
sleep 10

echo -e "\n${GREEN}Replication test completed!${NC}"
read -p ""