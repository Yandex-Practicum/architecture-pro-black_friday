#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}MongoDB Sharding + Replication Cluster Status${NC}"
echo -e "${BLUE}=========================================${NC}"

# Статус контейнеров
echo -e "\n${YELLOW}Container Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "configSrv|shard|mongos|pymongo"

# Статус репликасетов
echo -e "\n${YELLOW}Replica Sets Status:${NC}"

# Config Server
echo -n "Config Server: "
if docker exec configSrv1 mongosh --port 27017 --quiet --eval "rs.status().ok" 2>/dev/null; then
    PRIMARY=$(docker exec configSrv1 mongosh --port 27017 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
    echo -e "${GREEN}✓ OK${NC} (Primary: ${PRIMARY})"
else
    echo -e "${RED}✗ Not initialized${NC}"
fi

# Shard1
echo -n "Shard1: "
if docker exec shard1_primary mongosh --port 27018 --quiet --eval "rs.status().ok" 2>/dev/null; then
    PRIMARY=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
    echo -e "${GREEN}✓ OK${NC} (Primary: ${PRIMARY})"
else
    echo -e "${RED}✗ Not initialized${NC}"
fi

# Shard2
echo -n "Shard2: "
if docker exec shard2_primary mongosh --port 27019 --quiet --eval "rs.status().ok" 2>/dev/null; then
    PRIMARY=$(docker exec shard2_primary mongosh --port 27019 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
    echo -e "${GREEN}✓ OK${NC} (Primary: ${PRIMARY})"
else
    echo -e "${RED}✗ Not initialized${NC}"
fi

# Статус шардирования
echo -e "\n${YELLOW}Sharding Status:${NC}"
docker exec mongos_router mongosh --port 27020 --quiet --eval "
try {
  var status = sh.status();
  if (status && status.shards) {
    print('Shards configured: ' + status.shards.length);
    status.shards.forEach(s => print('  - ' + s._id + ': ' + s.host));
    print('Balancer: ' + (status.balancer.'Currently enabled' || 'unknown'));
  } else {
    print('Not configured');
  }
} catch(e) {
  print('Error: ' + e.message);
}
" 2>/dev/null || echo "  Unable to get sharding status"

# Статистика данных
echo -e "\n${YELLOW}Data Distribution:${NC}"
TOTAL=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD1=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD2=$(docker exec shard2_primary mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

echo -e "Total documents: ${GREEN}${TOTAL}${NC}"
echo -e "Shard1: ${GREEN}${SHARD1}${NC} documents"
echo -e "Shard2: ${GREEN}${SHARD2}${NC} documents"

if [ "$TOTAL" -gt 0 ] && [ "$TOTAL" != "0" ]; then
    # Используем awk для вычисления процентов (более надежно)
    PERCENT1=$(awk "BEGIN {printf \"%.1f\", ($SHARD1 * 100 / $TOTAL)}")
    PERCENT2=$(awk "BEGIN {printf \"%.1f\", ($SHARD2 * 100 / $TOTAL)}")
    echo -e "Distribution: Shard1: ${PERCENT1}%, Shard2: ${PERCENT2}%"
fi

# Детальное распределение по шардам
echo -e "\n${YELLOW}Detailed Shard Distribution:${NC}"
docker exec mongos_router mongosh --port 27020 --quiet --eval "
try {
  var stats = db.getSiblingDB('somedb').helloDoc.getShardDistribution();
  if (stats) {
    print('Data distribution verified');
  }
} catch(e) {
  print('Unable to get distribution details');
}
" 2>/dev/null

# Статус репликации (проверка синхронизации)
echo -e "\n${YELLOW}Replication Sync Status:${NC}"

# Проверка Shard1
SHARD1_PRIMARY_COUNT=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD1_SECONDARY1_COUNT=$(docker exec shard1_secondary1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD1_SECONDARY2_COUNT=$(docker exec shard1_secondary2 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

echo -n "Shard1 replication: "
if [ "$SHARD1_PRIMARY_COUNT" -eq "$SHARD1_SECONDARY1_COUNT" ] && [ "$SHARD1_PRIMARY_COUNT" -eq "$SHARD1_SECONDARY2_COUNT" ]; then
    echo -e "${GREEN}✓ Synced${NC} (${SHARD1_PRIMARY_COUNT} docs on all nodes)"
else
    echo -e "${RED}✗ Sync issue${NC} (Primary: ${SHARD1_PRIMARY_COUNT}, Secondary1: ${SHARD1_SECONDARY1_COUNT}, Secondary2: ${SHARD1_SECONDARY2_COUNT})"
fi

# Проверка Shard2
SHARD2_PRIMARY_COUNT=$(docker exec shard2_primary mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD2_SECONDARY1_COUNT=$(docker exec shard2_secondary1 mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD2_SECONDARY2_COUNT=$(docker exec shard2_secondary2 mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

echo -n "Shard2 replication: "
if [ "$SHARD2_PRIMARY_COUNT" -eq "$SHARD2_SECONDARY1_COUNT" ] && [ "$SHARD2_PRIMARY_COUNT" -eq "$SHARD2_SECONDARY2_COUNT" ]; then
    echo -e "${GREEN}✓ Synced${NC} (${SHARD2_PRIMARY_COUNT} docs on all nodes)"
else
    echo -e "${RED}✗ Sync issue${NC} (Primary: ${SHARD2_PRIMARY_COUNT}, Secondary1: ${SHARD2_SECONDARY1_COUNT}, Secondary2: ${SHARD2_SECONDARY2_COUNT})"
fi

# API статус
echo -e "\n${YELLOW}API Status:${NC}"
if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API is running${NC}"
else
    echo -e "${RED}✗ API is not responding${NC}"
    echo -e "  ${YELLOW}Check: docker logs pymongo_api --tail 20${NC}"
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Cluster Status Check Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
read -p ""