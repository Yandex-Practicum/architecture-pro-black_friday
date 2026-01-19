#!/bin/bash

# Инициализируем сервер конфигурации
docker-compose exec -T configSrv mongosh --port 27019 <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27019" }
    ]
  }
)
EOF

# Инициализируем шарды
docker-compose exec -T shard1-1 mongosh --port 27021 <<EOF
rs.initiate(
  {
      _id : "shard1",
      members: [
      { _id : 0, host : "shard1-1:27021" },
      { _id : 1, host : "shard1-2:27023" },
      { _id : 2, host : "shard1-3:27025" }      
      ]
    }
)
EOF

docker-compose exec -T shard2-1 mongosh --port 27022 <<EOF
rs.initiate(
  {
    _id : "shard2",
    members: [
      { _id : 0, host : "shard2-1:27022" },
      { _id : 1, host : "shard2-2:27024" },
      { _id : 2, host : "shard2-3:27026" }    
    ]
  }
)
EOF

sleep 5

# Инициализируем роутер и наполним БД тестовыми данными
docker-compose exec -T mongos_router mongosh --port 27017 <<EOF
sh.addShard( "shard1/shard1-1:27021")
sh.addShard( "shard2/shard2-1:27022")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF
