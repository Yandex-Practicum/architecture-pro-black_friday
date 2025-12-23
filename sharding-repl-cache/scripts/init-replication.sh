#!/bin/bash

set -e

echo "==================================="
echo "Инициализация MongoDB Sharding с Репликацией"
echo "==================================="

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ждем запуска контейнеров
echo -e "${YELLOW}Ожидание запуска MongoDB контейнеров...${NC}"
sleep 15

# 1. Инициализация Config Server Replica Set
echo -e "\n${BLUE}Шаг 1: Инициализация Config Server Replica Set${NC}"
docker compose exec -T configSrv1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27019" },
    { _id: 1, host: "configSrv2:27019" },
    { _id: 2, host: "configSrv3:27019" }
  ]
});
EOF

echo -e "${GREEN}✓ Config Server Replica Set инициализирован${NC}"
sleep 5

# 2. Инициализация Shard 1 Replica Set (3 ноды)
echo -e "\n${BLUE}Шаг 2: Инициализация Shard 1 Replica Set (3 реплики)${NC}"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
EOF

echo -e "${GREEN}✓ Shard 1 Replica Set инициализирован (3 реплики)${NC}"
sleep 5

# 3. Инициализация Shard 2 Replica Set (3 ноды)
echo -e "\n${BLUE}Шаг 3: Инициализация Shard 2 Replica Set (3 реплики)${NC}"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
});
EOF

echo -e "${GREEN}✓ Shard 2 Replica Set инициализирован (3 реплики)${NC}"
sleep 5

# 4. Добавление шардов в кластер
echo -e "\n${BLUE}Шаг 4: Добавление шардов в кластер${NC}"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("shard2ReplSet/shard2-1:27018,shard2-2:27018,shard2-3:27018");
EOF

echo -e "${GREEN}✓ Шарды с репликами добавлены в кластер${NC}"
sleep 2

# 5. Включение шардирования для базы данных
echo -e "\n${BLUE}Шаг 5: Включение шардирования для БД somedb${NC}"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb");
EOF

echo -e "${GREEN}✓ Шардирование включено для БД somedb${NC}"
sleep 2

# 6. Создание шардированной коллекции
echo -e "\n${BLUE}Шаг 6: Создание шардированной коллекции helloDoc${NC}"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF

echo -e "${GREEN}✓ Коллекция helloDoc создана и шардирована${NC}"
sleep 2

# 7. Заполнение данными
echo -e "\n${BLUE}Шаг 7: Заполнение коллекции данными (1000 документов)${NC}"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF

echo -e "${GREEN}✓ Данные загружены${NC}"
sleep 2

# 8. Проверка статуса репликации
echo -e "\n${BLUE}Шаг 8: Проверка статуса репликации${NC}"

echo -e "\n${YELLOW}Shard 1 Replica Set:${NC}"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(member) {
  print(member.name + " - " + member.stateStr);
});
EOF

echo -e "\n${YELLOW}Shard 2 Replica Set:${NC}"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(member) {
  print(member.name + " - " + member.stateStr);
});
EOF

# 9. Проверка распределения данных
echo -e "\n${BLUE}Шаг 9: Проверка распределения данных по шардам${NC}"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution();
EOF

echo -e "\n${GREEN}==================================="
echo "✓ Инициализация завершена успешно!"
echo "===================================${NC}"
echo -e "\n${YELLOW}Проверьте результат:${NC}"
echo "  curl http://127.0.0.1:8080"
echo ""
echo -e "${YELLOW}Архитектура:${NC}"
echo "  • 11 контейнеров запущено"
echo "  • Config Servers: 3 реплики"
echo "  • Shard 1: 3 реплики (shard1-1, shard1-2, shard1-3)"
echo "  • Shard 2: 3 реплики (shard2-1, shard2-2, shard2-3)"
echo "  • Mongos: 1 роутер"
echo "  • API: 1 приложение"
echo ""

