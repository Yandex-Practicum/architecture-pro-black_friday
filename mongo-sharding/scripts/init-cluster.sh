#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}MongoDB Sharding Cluster Initialization${NC}"
echo -e "${BLUE}=========================================${NC}"

# Функция для вывода разделителя
print_separator() {
    echo -e "${YELLOW}----------------------------------------${NC}"
}

# Функция для проверки успешности
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Success${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
        exit 1
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

# 1. Проверка наличия docker-compose файла
echo -e "\n${YELLOW}[1/9] Checking docker-compose file...${NC}"
print_separator

COMPOSE_FILE="../compose.yaml"
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}Compose file not found: $COMPOSE_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Compose file found${NC}"

# 2. Запуск всех сервисов
echo -e "\n${YELLOW}[2/9] Starting all services...${NC}"
print_separator

cd ..
docker-compose -f compose.yaml up -d
check_success
sleep 5

# 3. Ожидание готовности сервисов
echo -e "\n${YELLOW}[3/9] Waiting for services to be ready...${NC}"
print_separator

wait_for_service "configSrv" 27017
wait_for_service "shard1" 27018
wait_for_service "shard2" 27019
sleep 5

# 4. Инициализация Config Server
echo -e "\n${YELLOW}[4/9] Initializing Config Server replica set...${NC}"
print_separator

docker exec configSrv mongosh --port 27017 --eval '
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
' &>/dev/null
check_success
sleep 5

# 5. Инициализация Shard1
echo -e "\n${YELLOW}[5/9] Initializing Shard1 replica set...${NC}"
print_separator

docker exec shard1 mongosh --port 27018 --eval '
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
' &>/dev/null
check_success
sleep 5

# 6. Инициализация Shard2
echo -e "\n${YELLOW}[6/9] Initializing Shard2 replica set...${NC}"
print_separator

docker exec shard2 mongosh --port 27019 --eval '
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }]
})
' &>/dev/null
check_success
sleep 10

# 7. Добавление шардов через mongos
echo -e "\n${YELLOW}[7/9] Configuring sharding...${NC}"
print_separator

docker exec mongos_router mongosh --port 27020 --eval '
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
' &>/dev/null
check_success
sleep 5

# 8. Вставка тестовых данных
echo -e "\n${YELLOW}[8/9] Inserting test data (2000 documents)...${NC}"
print_separator

# Используем интерактивный подход через heredoc
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

# 9. Проверка распределения данных
echo -e "\n${YELLOW}[9/9] Checking data distribution...${NC}"
print_separator

# Получаем статистику из mongos
TOTAL=$(docker exec mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()")

# Получаем данные с шардов
SHARD1_COUNT=$(docker exec shard1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")
SHARD2_COUNT=$(docker exec shard2 mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()" 2>/dev/null || echo "0")

echo -e "${GREEN}Total documents: ${TOTAL}${NC}"
echo -e "${GREEN}Shard1: ${SHARD1_COUNT} documents${NC}"
echo -e "${GREEN}Shard2: ${SHARD2_COUNT} documents${NC}"

# Вычисляем процентное распределение
if [ "$TOTAL" -gt 0 ]; then
    PERCENT1=$(echo "scale=1; $SHARD1_COUNT * 100 / $TOTAL" | bc)
    PERCENT2=$(echo "scale=1; $SHARD2_COUNT * 100 / $TOTAL" | bc)
    echo -e "${BLUE}Distribution: Shard1: ${PERCENT1}%, Shard2: ${PERCENT2}%${NC}"
fi

# Проверяем, что данные распределены
if [ "$SHARD1_COUNT" -gt 0 ] && [ "$SHARD2_COUNT" -gt 0 ]; then
    echo -e "\n${GREEN}✓ SUCCESS: Data is properly distributed across shards!${NC}"
else
    echo -e "\n${YELLOW}⚠ WARNING: Data is on single shard, balancer may need time${NC}"
fi

# Финальная информация
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}Cluster initialization completed!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${YELLOW}Connection details:${NC}"
echo -e "  MongoDB Router: ${GREEN}mongodb://localhost:27020${NC}"
echo -e "  Database: ${GREEN}somedb${NC}"
echo -e "  Collection: ${GREEN}helloDoc${NC}"
echo -e "  API Endpoint: ${GREEN}http://localhost:8080${NC}"
echo -e "${BLUE}=========================================${NC}"

# Дополнительная информация
echo -e "\n${YELLOW}Useful commands:${NC}"
echo -e "  Check sharding status: ${GREEN}docker exec mongos_router mongosh --port 27020 --eval \"sh.status()\"${NC}"
echo -e "  View distribution: ${GREEN}docker exec mongos_router mongosh --port 27020 --eval \"db.getSiblingDB('somedb').helloDoc.getShardDistribution()\"${NC}"
echo -e "  View logs: ${GREEN}docker-compose -f $COMPOSE_FILE logs -f${NC}"
echo -e "${BLUE}=========================================${NC}"
read -p ""