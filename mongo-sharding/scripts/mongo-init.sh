#!/bin/bash

###
# Инициализация шардированного кластера MongoDB
###

# 1. Инициализация replica set для config server
docker compose exec -T configsvr mongosh --port 27017 <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "configsvr:27017" }]
})
EOF

sleep 5

# 2. Добавление шардов через mongos
docker compose exec -T mongos_router mongosh --port 27017 <<EOF
sh.addShard("shard1:27017")
sh.addShard("shard2:27017")

sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { age: "hashed" })
EOF

sleep 3

# 3. Заполнение тестовыми данными
docker compose exec -T mongos_router mongosh --port 27017 <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age: i, name: "ly" + i})
EOF
