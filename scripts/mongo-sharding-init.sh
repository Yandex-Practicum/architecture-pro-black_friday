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
docker compose exec -T shard1 mongosh --port 27031 <<EOF
rs.initiate({
  _id: "shard-1",
  members: [
    { _id: 0, host: "shard1:27031" }
  ]
});
EOF
sleep 3

# Инициализация шарда 2
echo 'Initializing shard 2'
docker compose exec -T shard2 mongosh --port 27041 <<EOF
rs.initiate({
  _id: "shard-2",
  members: [
    { _id: 0, host: "shard2:27041" }
  ]
});
EOF
echo 'Shards done'
sleep 5

# Настройка роутера
echo 'Initializing router'
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.addShard("shard-1/shard1:27031");
sh.addShard("shard-2/shard2:27041");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });
EOF
echo 'Router done'
sleep 5

# Инициализация набора данных
bash "$(dirname "$0")/seed.sh"

echo 'Initialization completed!'