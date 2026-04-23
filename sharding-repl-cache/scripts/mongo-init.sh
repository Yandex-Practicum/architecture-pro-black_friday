#!/bin/bash
set -e

echo "==> 1. Инициализация Config Server ReplicaSet"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_rs",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
EOF

sleep 3

echo "==> 2. Инициализация ReplicaSet Shard1"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1_rs",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF

sleep 3

echo "==> 3. Инициализация ReplicaSet Shard2"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2_rs",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF

sleep 5

echo "==> 4. Добавление шардов в кластер через mongos"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1_rs/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2_rs/shard2-1:27018,shard2-2:27018,shard2-3:27018")
EOF

sleep 2

echo "==> 5. Включение шардирования и заполнение данными"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF

echo "==> 6. Проверка - подсчет документов"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
print("Total:", db.helloDoc.countDocuments())
EOF

docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
print("Shard1:", db.helloDoc.countDocuments())
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb
print("Shard2:", db.helloDoc.countDocuments())
EOF

echo "==> 7. Статус реплик"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(m => print(m.name, m.stateStr))
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(m => print(m.name, m.stateStr))
EOF

echo "Готово!"