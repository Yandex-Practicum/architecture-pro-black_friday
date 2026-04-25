#!/bin/bash

set -e

echo ">>> Инициализация config server replica set..."
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF

sleep 3

echo ">>> Инициализация shard1 replica set..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF

echo ">>> Инициализация shard2 replica set..."
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27018" }]
})
EOF

sleep 5

echo ">>> Добавление шардов в mongos router..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27018")
EOF

sleep 3

echo ">>> Включение шардирования для базы данных somedb..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" })
EOF

echo ">>> Наполнение базы данных тестовыми данными (1000 документов)..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
db.helloDoc.countDocuments()
EOF

echo ">>> Проверка распределения данных по шардам..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF

echo ">>> Готово! Шардирование настроено."
