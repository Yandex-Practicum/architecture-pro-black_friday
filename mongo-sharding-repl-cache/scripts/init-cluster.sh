#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}MongoDB Sharding + Redis Cache Cluster${NC}"
echo -e "${BLUE}=========================================${NC}"

print_separator() {
    echo -e "${YELLOW}----------------------------------------${NC}"
}

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Success${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
}

# Функция для ожидания готовности сервиса
wait_for_service() {
    local service=$1
    local port=$2
    local max_attempts=30
    local attempt=1

    echo -e "${YELLOW}Waiting for $service to be ready...${NC}"
    while [ $attempt -le $max_attempts ]; do
        if docker exec $service mongosh --port $port --eval "db.adminCommand('ping')" &>/dev/null; then
            echo -e "${GREEN}✓ $service is ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    echo -e "\n${RED}✗ $service failed to start${NC}"
    return 1
}

# 1. Запуск всех сервисов
echo -e "\n${YELLOW}[1/9] Starting all services...${NC}"
print_separator

cd ..
docker-compose -f compose.yaml up -d
check_success
echo -e "${GREEN}Waiting for services to initialize (30 seconds)...${NC}"
sleep 30

# 2. Проверка готовности MongoDB сервисов
echo -e "\n${YELLOW}[2/9] Checking MongoDB services...${NC}"
print_separator

wait_for_service "configSrv1" 27017
wait_for_service "shard1_primary" 27018
wait_for_service "shard2_primary" 27019

# 3. Инициализация Config Server Replica Set
echo -e "\n${YELLOW}[3/9] Initializing Config Server replica set (3 nodes)...${NC}"
print_separator

docker exec configSrv1 mongosh --port 27017 --eval '
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27017" },
    { _id: 1, host: "configSrv2:27017" },
    { _id: 2, host: "configSrv3:27017" }
  ]
})
' > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Config Server initialized${NC}"
else
    echo -e "${YELLOW}⚠ Config Server may already be initialized${NC}"
fi
sleep 15

# 4. Инициализация Shard1 Replica Set
echo -e "\n${YELLOW}[4/9] Initializing Shard1 replica set (3 nodes)...${NC}"
print_separator

docker exec shard1_primary mongosh --port 27018 --eval '
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1_primary:27018" },
    { _id: 1, host: "shard1_secondary1:27018" },
    { _id: 2, host: "shard1_secondary2:27018" }
  ]
})
' > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Shard1 initialized${NC}"
else
    echo -e "${YELLOW}⚠ Shard1 may already be initialized${NC}"
fi
sleep 15

# 5. Инициализация Shard2 Replica Set
echo -e "\n${YELLOW}[5/9] Initializing Shard2 replica set (3 nodes)...${NC}"
print_separator

docker exec shard2_primary mongosh --port 27019 --eval '
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2_primary:27019" },
    { _id: 1, host: "shard2_secondary1:27019" },
    { _id: 2, host: "shard2_secondary2:27019" }
  ]
})
' > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Shard2 initialized${NC}"
else
    echo -e "${YELLOW}⚠ Shard2 may already be initialized${NC}"
fi
sleep 20

# 6. Добавление шардов через mongos
echo -e "\n${YELLOW}[6/9] Configuring sharding...${NC}"
print_separator

# Проверка, добавлены ли уже шарды
SHARDS_COUNT=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "sh.status().shards.length" 2>/dev/null || echo "0")

if [ "$SHARDS_COUNT" -eq "0" ]; then
    docker exec mongos_router mongosh --port 27020 --eval '
    sh.addShard("shard1/shard1_primary:27018,shard1_secondary1:27018,shard1_secondary2:27018");
    sh.addShard("shard2/shard2_primary:27019,shard2_secondary1:27019,shard2_secondary2:27019");
    sh.enableSharding("somedb");
    sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
    ' > /dev/null 2>&1
    echo -e "${GREEN}✓ Sharding configured${NC}"
else
    echo -e "${YELLOW}⚠ Sharding already configured (${SHARDS_COUNT} shards)${NC}"
fi
sleep 5

# 7. Вставка тестовых данных (только если нет данных)
echo -e "\n${YELLOW}[7/9] Checking/Inserting test data...${NC}"
print_separator

EXISTING_DATA=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

if [ "$EXISTING_DATA" -eq "0" ]; then
    echo "Inserting 2000 documents..."
    docker exec -i mongos_router mongosh --port 27020 > /dev/null 2>&1 <<EOF
use somedb;
var bulk = [];
for(var i = 0; i < 2000; i++) {
    bulk.push({insertOne: {document: {age: i, name: "ly" + i, created: new Date()}}});
    if(bulk.length === 500) {
        db.helloDoc.bulkWrite(bulk);
        bulk = [];
    }
}
if(bulk.length) {
    db.helloDoc.bulkWrite(bulk);
}
EOF
    echo -e "${GREEN}✓ Inserted 2000 documents${NC}"
else
    echo -e "${YELLOW}⚠ Data already exists (${EXISTING_DATA} documents)${NC}"
fi

# 8. Проверка статуса репликации
echo -e "\n${YELLOW}[8/9] Checking replication status...${NC}"
print_separator

echo -e "${BLUE}Config Server Replica Set Status:${NC}"
docker exec configSrv1 mongosh --port 27017 --quiet --eval "
try {
    rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr));
} catch(e) {
    print('Not initialized yet');
}
"

echo -e "\n${BLUE}Shard1 Replica Set Status:${NC}"
docker exec shard1_primary mongosh --port 27018 --quiet --eval "
try {
    rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr));
} catch(e) {
    print('Not initialized yet');
}
"

echo -e "\n${BLUE}Shard2 Replica Set Status:${NC}"
docker exec shard2_primary mongosh --port 27019 --quiet --eval "
try {
    rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr));
} catch(e) {
    print('Not initialized yet');
}
"

# 9. Проверка распределения данных
echo -e "\n${YELLOW}[9/9] Checking data distribution...${NC}"
print_separator

TOTAL=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

if [ "$TOTAL" -gt "0" ]; then
    echo -e "${GREEN}Total documents: ${TOTAL}${NC}"

    SHARD1_COUNT=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
    SHARD2_COUNT=$(docker exec shard2_primary mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

    echo -e "${GREEN}Shard1: ${SHARD1_COUNT} documents${NC}"
    echo -e "${GREEN}Shard2: ${SHARD2_COUNT} documents${NC}"

    if [ "$SHARD1_COUNT" -gt 0 ] && [ "$SHARD2_COUNT" -gt 0 ]; then
        PERCENT1=$(echo "scale=1; $SHARD1_COUNT * 100 / $TOTAL" | bc 2>/dev/null || echo "0")
        PERCENT2=$(echo "scale=1; $SHARD2_COUNT * 100 / $TOTAL" | bc 2>/dev/null || echo "0")
        echo -e "${BLUE}Distribution: Shard1: ${PERCENT1}%, Shard2: ${PERCENT2}%${NC}"
        echo -e "\n${GREEN}✓ SUCCESS: Data is distributed across shards with replication!${NC}"
    else
        echo -e "\n${YELLOW}⚠ Data is on single shard, balancer may need time${NC}"
    fi
else
    echo -e "${RED}✗ No data found!${NC}"
fi

# Проверка Redis
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

# Финальная информация
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Cluster initialization complete!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Architecture:${NC}"
echo -e "  • Config Server: 3-node replica set"
echo -e "  • Shard1: 3-node replica set"
echo -e "  • Shard2: 3-node replica set"
echo -e "  • Redis Cache: 6-node cluster"
echo -e "  • Mongos Router: 1 instance"
echo -e "\n${YELLOW}Connection:${NC}"
echo -e "  MongoDB Router: ${GREEN}mongodb://localhost:27020${NC}"
echo -e "  Redis Cluster: ${GREEN}redis://localhost:6379${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:8080${NC}"
echo -e "\n${YELLOW}Test commands:${NC}"
echo -e "  ${GREEN}./status-cluster.sh${NC} - Check cluster status"
echo -e "  ${GREEN}docker stop shard1_primary${NC} - Test failover"
echo -e "  ${GREEN}curl http://localhost:8080/helloDoc/users${NC} - Test API with cache"
echo -e "${BLUE}=========================================${NC}"
read -p ""