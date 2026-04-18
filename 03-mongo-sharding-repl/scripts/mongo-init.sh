#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T configSrv mongosh <<EOF
rs.initiate(
  {
    _id : "config_server",
    configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
exit(); 
EOF

docker compose exec -T shard1_master mongosh --port 27018 <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1_master:27018" },
        { _id : 1, host : "shard1_repl1:27019" },
        { _id : 2, host : "shard1_repl2:27020" }
      ]
    }
);
exit(); 
EOF

docker compose exec -T shard2_master mongosh --port 27021 <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 0, host : "shard2_master:27021" },
        { _id : 1, host : "shard2_repl1:27022" },
        { _id : 2, host : "shard2_repl2:27023" }
      ]
    }
);
exit(); 
EOF

docker compose exec -T mongos_router mongosh --port 27030 <<EOF
sh.addShard( "shard1/shard1_master:27018");
sh.addShard( "shard2/shard2_master:27021");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

use somedb

for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i})

db.helloDoc.countDocuments() 
exit(); 
EOF


echo "Counting items in replicaset 1. Should get equal numbers."

docker compose exec -T shard1_master mongosh --port 27018 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard1_repl1 mongosh --port 27019 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard1_repl2 mongosh --port 27020 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF


echo "Counting items in replicaset 2. Should get equal numbers."

docker compose exec -T shard2_master mongosh --port 27021 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard2_repl1 mongosh --port 27022 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF

docker compose exec -T shard2_repl2 mongosh --port 27023 <<EOF
use somedb
db.helloDoc.countDocuments() 
exit(); 
EOF
