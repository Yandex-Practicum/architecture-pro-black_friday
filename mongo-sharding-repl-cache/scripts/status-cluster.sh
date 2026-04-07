#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}MongoDB Sharding + Redis Cache Cluster Status${NC}"
echo -e "${BLUE}=========================================${NC}"

# Статус контейнеров
echo -e "\n${YELLOW}Container Status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "configSrv|shard|mongos|redis|pymongo"

# Статус репликасетов MongoDB
echo -e "\n${YELLOW}MongoDB Replica Sets Status:${NC}"

echo -n "Config Server: "
if docker exec configSrv1 mongosh --port 27017 --quiet --eval "rs.status().ok" 2>/dev/null; then
    PRIMARY=$(docker exec configSrv1 mongosh --port 27017 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
    echo -e "${GREEN}✓ OK${NC} (Primary: ${PRIMARY})"
else
    echo -e "${RED}✗ Not initialized${NC}"
fi

echo -n "Shard1: "
if docker exec shard1_primary mongosh --port 27018 --quiet --eval "rs.status().ok" 2>/dev/null; then
    PRIMARY=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
    echo -e "${GREEN}✓ OK${NC} (Primary: ${PRIMARY})"
else
    echo -e "${RED}✗ Not initialized${NC}"
fi

echo -n "Shard2: "
if docker exec shard2_primary mongosh --port 27019 --quiet --eval "rs.status().ok" 2>/dev/null; then
    PRIMARY=$(docker exec shard2_primary mongosh --port 27019 --quiet --eval "rs.isMaster().primary" 2>/dev/null)
    echo -e "${GREEN}✓ OK${NC} (Primary: ${PRIMARY})"
else
    echo -e "${RED}✗ Not initialized${NC}"
fi

# Статус Redis
echo -e "\n${YELLOW}Redis Cache Status:${NC}"
REDIS_OK=0
for i in 1 2 3 4 5 6; do
    if docker exec redis_$i redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo -e "  redis_$i: ${GREEN}✓ OK${NC}"
        ((REDIS_OK++))
    else
        echo -e "  redis_$i: ${RED}✗ Failed${NC}"
    fi
done
echo -e "${GREEN}Redis cluster: ${REDIS_OK}/6 nodes healthy${NC}"

# Статистика данных MongoDB
echo -e "\n${YELLOW}MongoDB Data Distribution:${NC}"
TOTAL=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD1=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD2=$(docker exec shard2_primary mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

echo -e "Total documents: ${GREEN}${TOTAL}${NC}"
echo -e "Shard1: ${GREEN}${SHARD1}${NC} documents"
echo -e "Shard2: ${GREEN}${SHARD2}${NC} documents"

# API статус с проверкой кеша
echo -e "\n${YELLOW}API & Cache Status:${NC}"
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API is running${NC}"

    # Проверка кеширования
    echo -e "\n${YELLOW}Testing cache performance:${NC}"

    # Первый запрос (без кеша)
    echo -n "First request (uncached): "
    time1=$(curl -s -o /dev/null -w "%{time_total}\n" http://localhost:8080/helloDoc/users)
    echo "${time1}s"

    # Второй запрос (с кешем)
    echo -n "Second request (cached): "
    time2=$(curl -s -o /dev/null -w "%{time_total}\n" http://localhost:8080/helloDoc/users)
    echo "${time2}s"

    # Сравнение с использованием awk
    FASTER=$(echo "$time1 $time2" | awk '{if ($2 < $1) print "yes"; else print "no"}')

    if [ "$FASTER" = "yes" ]; then
        # Вычисляем процент улучшения
        IMPROVEMENT=$(echo "$time1 $time2" | awk '{printf "%.1f", ($1 - $2) * 100 / $1}')
        echo -e "${GREEN}✓ Cache is working! Speed improved by ${IMPROVEMENT}%${NC}"
    else
        echo -e "${YELLOW}⚠ Cache may not be configured properly${NC}"
        echo -e "  First request: ${time1}s, Second request: ${time2}s"
    fi

    # Проверка Redis кеша
    echo -e "\n${YELLOW}Redis cache keys:${NC}"
    CACHE_KEYS=$(docker exec redis_1 redis-cli keys "api:cache*" 2>/dev/null)
    if [ -n "$CACHE_KEYS" ]; then
        CACHE_COUNT=$(echo "$CACHE_KEYS" | wc -l)
        echo -e "${GREEN}✓ Found ${CACHE_COUNT} cache key(s) in Redis${NC}"
        echo "$CACHE_KEYS" | head -5
    else
        echo -e "${RED}✗ No cache keys found in Redis${NC}"
    fi
else
    echo -e "${RED}✗ API is not responding${NC}"
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Cluster Status Check Complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
read -p ""