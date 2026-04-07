#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}MongoDB Sharding Cluster Status${NC}"
echo -e "${BLUE}=========================================${NC}"

# Статус контейнеров
echo -e "\n${YELLOW}Container Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "configSrv|shard|mongos|pymongo"

# Статус репликасетов
echo -e "\n${YELLOW}Replica Sets Status:${NC}"
echo -n "Config Server: "
docker exec configSrv mongosh --port 27017 --quiet --eval "rs.status().ok" 2>/dev/null && echo -e "${GREEN}✓ OK${NC}" || echo -e "${RED}✗ Not initialized${NC}"

echo -n "Shard1: "
docker exec shard1 mongosh --port 27018 --quiet --eval "rs.status().ok" 2>/dev/null && echo -e "${GREEN}✓ OK${NC}" || echo -e "${RED}✗ Not initialized${NC}"

echo -n "Shard2: "
docker exec shard2 mongosh --port 27019 --quiet --eval "rs.status().ok" 2>/dev/null && echo -e "${GREEN}✓ OK${NC}" || echo -e "${RED}✗ Not initialized${NC}"

# Статус шардирования
echo -e "\n${YELLOW}Sharding Status:${NC}"
docker exec mongos_router mongosh --port 27020 --quiet --eval "
try {
  var status = sh.status();
  print('Shards configured: ' + sh.status().shards.length);
} catch(e) {
  print('Not configured');
}
" 2>/dev/null

# Статистика данных
echo -e "\n${YELLOW}Data Distribution:${NC}"
TOTAL=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD1=$(docker exec shard1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD2=$(docker exec shard2 mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

echo -e "Total documents: ${GREEN}${TOTAL}${NC}"
echo -e "Shard1: ${GREEN}${SHARD1}${NC}"
echo -e "Shard2: ${GREEN}${SHARD2}${NC}"

# API статус
echo -e "\n${YELLOW}API Status:${NC}"
if curl -s http://localhost:8080/health > /dev/null; then
    echo -e "${GREEN}✓ API is running${NC}"
else
    echo -e "${RED}✗ API is not responding${NC}"
fi

echo -e "\n${BLUE}=========================================${NC}"
read -p ""