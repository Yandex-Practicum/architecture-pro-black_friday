#!/bin/bash

###
# Инициализация шардированного кластера MongoDB с репликацией
###

# 1. Инициализация replica set для config server (3 узла)
docker compose exec -T configsvr1 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configsvr1:27017" },
    { _id: 1, host: "configsvr2:27017" },
    { _id: 2, host: "configsvr3:27017" }
  ]
})
EOF

sleep 5

# 2. Инициализация replica set для shard1 (3 узла)
docker compose exec -T shard1-1 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27017" },
    { _id: 1, host: "shard1-2:27017" },
    { _id: 2, host: "shard1-3:27017" }
  ]
})
EOF

sleep 5

# 3. Инициализация replica set для shard2 (3 узла)
docker compose exec -T shard2-1 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-1:27017" },
    { _id: 1, host: "shard2-2:27017" },
    { _id: 2, host: "shard2-3:27017" }
  ]
})
EOF

sleep 5

# 4. Добавление шардов через mongos (указываем replica set)
docker compose exec -T mongos_router mongosh --port 27017 <<EOF
sh.addShard("shard1ReplSet/shard1-1:27017,shard1-2:27017,shard1-3:27017")
sh.addShard("shard2ReplSet/shard2-1:27017,shard2-2:27017,shard2-3:27017")

sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { age: "hashed" })
EOF

sleep 3

# 5. Заполнение тестовыми данными
docker compose exec -T mongos_router mongosh --port 27017 <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age: i, name: "ly" + i})
EOF
