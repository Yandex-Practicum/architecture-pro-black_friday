#!/bin/bash

###
# Скрипт инициализации шардированного кластера MongoDB с репликацией и кешированием
###

# 1. Инициализация Config Server Replica Set
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF

sleep 5

# 2. Инициализация Shard1 Replica Set (3 реплики)
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF

sleep 5

# 3. Инициализация Shard2 Replica Set (3 реплики)
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF

sleep 5

# 4. Добавление шардов в кластер через mongos
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018")
EOF

sleep 3

# 5. Включение шардирования для БД и коллекции
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "age": "hashed" })
EOF

sleep 3

# 6. Заполнение данными (1000 документов)
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

echo ""
echo "=== Инициализация завершена ==="
echo ""

# 7. Проверка количества документов, реплик и кеширования
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
print("Общее количество документов: " + db.helloDoc.countDocuments())
db.helloDoc.getShardDistribution()
EOF

# Проверка статуса реплик
echo ""
echo "=== Статус реплик Shard1 ==="
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - state: " + m.stateStr)
})
EOF

echo ""
echo "=== Статус реплик Shard2 ==="
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(function(m) {
  print(m.name + " - state: " + m.stateStr)
})
EOF

echo ""
echo "=== Проверка кеширования ==="
echo "Откройте http://localhost:8080 — в ответе cache_enabled должен быть true"
echo "Для проверки скорости кеширования выполните:"
echo "  curl -w '\\nВремя: %{time_total}s\\n' http://localhost:8080/helloDoc/users"
echo "  curl -w '\\nВремя: %{time_total}s\\n' http://localhost:8080/helloDoc/users"
echo "Второй запрос должен выполняться < 100мс"
