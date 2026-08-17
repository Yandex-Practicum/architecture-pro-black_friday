#!/bin/bash

###
# Инициализация кластера MongoDB
###

echo 'Initializing...'

# Инициализация config server
echo 'Initializing config server'
docker compose exec -T configSrv mongosh --port 27017 <<EOF
rs.initiate({
  _id: "configSrv",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
});
EOF
echo 'Config server done'
sleep 5

# Инициализация шарда 1
echo 'Initializing shard 1'
docker compose exec -T shard1_1 mongosh --port 27031 <<EOF
rs.initiate({
  _id: "shard-1",
  members: [
    { _id: 0, host: "shard1_1:27031" },
    { _id: 1, host: "shard1_2:27032" },
    { _id: 2, host: "shard1_3:27033" }
  ]
});
EOF
sleep 10

# Инициализация шарда 2
echo 'Initializing shard 2'
docker compose exec -T shard2_1 mongosh --port 27041 <<EOF
rs.initiate({
  _id: "shard-2",
  members: [
    { _id: 0, host: "shard2_1:27041" },
    { _id: 1, host: "shard2_2:27042" },
    { _id: 2, host: "shard2_3:27043" }
  ]
});
EOF
echo 'Shards done'
sleep 10

# Настройка роутера
echo 'Initializing router'
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.addShard("shard-1/shard1_1:27031");
sh.addShard("shard-2/shard2_1:27041");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });
EOF
echo 'Router done'
sleep 5

# Инициализация набора данных
echo 'Data seeding'
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
use somedb
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
EOF
echo 'Seeding done'

# Проверка
echo 'Checking data'
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
use somedb
db.helloDoc.countDocuments()
db.helloDoc.getShardDistribution()
EOF

echo 'Initialization completed!'