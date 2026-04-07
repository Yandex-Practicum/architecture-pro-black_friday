#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}MongoDB Sharding + Replication Cluster${NC}"
echo -e "${BLUE}=========================================${NC}"

print_separator() {
    echo -e "${YELLOW}----------------------------------------${NC}"
}

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Success${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
        exit 1
    fi
}

# 1. Запуск всех сервисов
echo -e "\n${YELLOW}[1/8] Starting all services...${NC}"
print_separator

cd ..
docker-compose -f compose.yaml up -d
check_success
echo -e "${GREEN}Waiting for services to initialize (20 seconds)...${NC}"
sleep 20

# 2. Инициализация Config Server Replica Set
echo -e "\n${YELLOW}[2/8] Initializing Config Server replica set (3 nodes)...${NC}"
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
' &>/dev/null
check_success
sleep 10

# 3. Инициализация Shard1 Replica Set
echo -e "\n${YELLOW}[3/8] Initializing Shard1 replica set (3 nodes)...${NC}"
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
' &>/dev/null
check_success
sleep 10

# 4. Инициализация Shard2 Replica Set
echo -e "\n${YELLOW}[4/8] Initializing Shard2 replica set (3 nodes)...${NC}"
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
' &>/dev/null
check_success
sleep 15

# 5. Добавление шардов через mongos
echo -e "\n${YELLOW}[5/8] Adding shards to cluster...${NC}"
print_separator

docker exec mongos_router mongosh --port 27020 --eval '
sh.addShard("shard1/shard1_primary:27018,shard1_secondary1:27018,shard1_secondary2:27018");
sh.addShard("shard2/shard2_primary:27019,shard2_secondary1:27019,shard2_secondary2:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
' &>/dev/null
check_success
sleep 5

# 6. Вставка тестовых данных
echo -e "\n${YELLOW}[6/8] Inserting test data (2000 documents)...${NC}"
print_separator

docker exec -i mongos_router mongosh --port 27020 <<EOF
use somedb;
print("Clearing existing data...");
db.helloDoc.deleteMany({});

print("Inserting 2000 documents...");
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
print("Total documents: " + db.helloDoc.countDocuments());
EOF

check_success

# 7. Проверка статуса репликации
echo -e "\n${YELLOW}[7/8] Checking replication status...${NC}"
print_separator

echo -e "${BLUE}Config Server Replica Set Status:${NC}"
docker exec configSrv1 mongosh --port 27017 --quiet --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

echo -e "\n${BLUE}Shard1 Replica Set Status:${NC}"
docker exec shard1_primary mongosh --port 27018 --quiet --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

echo -e "\n${BLUE}Shard2 Replica Set Status:${NC}"
docker exec shard2_primary mongosh --port 27019 --quiet --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

# 8. Проверка распределения данных
echo -e "\n${YELLOW}[8/8] Checking data distribution...${NC}"
print_separator

TOTAL=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()")

echo -e "${GREEN}Total documents: ${TOTAL}${NC}"

# Получаем данные с primary шардов
SHARD1_COUNT=$(docker exec shard1_primary mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD2_COUNT=$(docker exec shard2_primary mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

echo -e "${GREEN}Shard1 (Primary): ${SHARD1_COUNT} documents${NC}"
echo -e "${GREEN}Shard2 (Primary): ${SHARD2_COUNT} documents${NC}"

if [ "$SHARD1_COUNT" -gt 0 ] && [ "$SHARD2_COUNT" -gt 0 ]; then
    PERCENT1=$(echo "scale=1; $SHARD1_COUNT * 100 / $TOTAL" | bc)
    PERCENT2=$(echo "scale=1; $SHARD2_COUNT * 100 / $TOTAL" | bc)
    echo -e "${BLUE}Distribution: Shard1: ${PERCENT1}%, Shard2: ${PERCENT2}%${NC}"
    echo -e "\n${GREEN}✓ SUCCESS: Data is distributed across shards with replication!${NC}"
else
    echo -e "\n${YELLOW}⚠ WARNING: Data is on single shard${NC}"
fi

# Финальная информация
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Cluster with Replication initialized!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Architecture:${NC}"
echo -e "  • Config Server: 3-node replica set"
echo -e "  • Shard1: 3-node replica set (1 primary + 2 secondary)"
echo -e "  • Shard2: 3-node replica set (1 primary + 2 secondary)"
echo -e "  • Mongos Router: 1 instance"
echo -e "\n${YELLOW}Connection:${NC}"
echo -e "  MongoDB Router: ${GREEN}mongodb://localhost:27020${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:8080${NC}"
echo -e "\n${YELLOW}Test replication:${NC}"
echo -e "  ${GREEN}docker stop shard1_primary${NC} # Check automatic failover"
echo -e "${BLUE}=========================================${NC}"
read -p ""