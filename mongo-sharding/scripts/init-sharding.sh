#!/bin/bash

echo "Ожидание запуска MongoDB..."
sleep 10

echo ">>> Инициализация Config Server Replica Set"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
})
EOF

sleep 3

echo ">>> Инициализация Shard 1 Replica Set"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
})
EOF

sleep 3

echo ">>> Инициализация Shard 2 Replica Set"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27019" }
  ]
})
EOF

sleep 5

echo ">>> Добавление шардов в кластер"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27019")
EOF

sleep 3

echo ">>> Включение шардирования для базы данных somedb"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.enableSharding("somedb")
EOF

sleep 2

echo ">>> Создание индекса и шардирование коллекции helloDoc"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.createIndex({ "age": "hashed" })
sh.shardCollection("somedb.helloDoc", { "age": "hashed" })
EOF

echo ">>> Шардирование настроено!"

