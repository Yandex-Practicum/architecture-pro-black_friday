#!/bin/bash

###
# Инициализация шардированного кластера MongoDB
###

echo ">>> 1. Config Server ReplicaSet"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({ _id: "configRs", configsvr: true, members: [{ _id: 0, host: "configSrv:27017" }] })
EOF

sleep 5

echo ">>> 2. Shard1 ReplicaSet"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({ _id: "shard1Rs", members: [{ _id: 0, host: "shard1:27018" }] })
EOF

sleep 5

echo ">>> 3. Shard2 ReplicaSet"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({ _id: "shard2Rs", members: [{ _id: 0, host: "shard2:27019" }] })
EOF

sleep 5

echo ">>> 4. Регистрация шардов в роутере"
docker compose exec -T mongos mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1Rs/shard1:27018")
sh.addShard("shard2Rs/shard2:27019")
EOF

sleep 3

echo ">>> 5. Шардирование коллекции"
docker compose exec -T mongos mongosh --port 27020 --quiet <<EOF
sh.enableSharding("somedb")
use somedb
db.helloDoc.createIndex({ name: "hashed" })
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
EOF

sleep 3

echo ">>> 6. Наполнение данными"
docker compose exec -T mongos mongosh --port 27020 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age: i, name: "ly"+i})
print("Всего документов: " + db.helloDoc.countDocuments())
EOF

echo ">>> 7. Распределение по шардам"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
print("shard1: " + db.helloDoc.countDocuments())
EOF

docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
print("shard2: " + db.helloDoc.countDocuments())
EOF

echo "=== Инициализация завершена ==="

echo ">>> Финальная проверка для ревью"

echo "-- Общее количество документов (через mongos) --"
docker compose exec -T mongos mongosh --port 27020 --quiet <<EOF
use somedb
print("TOTAL: " + db.helloDoc.countDocuments())
EOF

echo "-- Количество документов на shard1 --"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
print("SHARD1: " + db.helloDoc.countDocuments())
EOF

echo "-- Количество документов на shard2 --"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
print("SHARD2: " + db.helloDoc.countDocuments())
EOF

echo "-- Статус шардирования --"
docker compose exec -T mongos mongosh --port 27020 --quiet <<EOF
sh.status()
EOF