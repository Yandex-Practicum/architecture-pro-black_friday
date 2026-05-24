#!/bin/bash
###
# Инициализация шардированного кластера MongoDB:
#   1. инициализируем replica-set для configSrv
#   2. инициализируем replica-set для shard1 и shard2
#   3. добавляем шарды через mongos и включаем шардирование коллекции somedb.helloDoc
#   4. заливаем 1000 документов через mongos
#   5. печатаем количество документов в каждом шарде
###
set -e

echo "==> 1/5 Инициализация configSrv replica-set..."
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF

echo "==> 2/5 Инициализация shard1 и shard2 replica-set'ов..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27018" }]
})
EOF

echo "==> Ждём, пока mongos подхватит configSrv (10 сек)..."
sleep 10

echo "==> 3/5 Добавляем шарды и включаем sharding для somedb.helloDoc..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
EOF

echo "==> 4/5 Заливаем 1000 документов через mongos..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF

echo "==> 5/5 Количество документов по шардам:"
echo "--- shard1 ---"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "--- shard2 ---"
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "--- ИТОГО через mongos ---"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo ""
echo "Готово. Веб-интерфейс: http://localhost:8080"
