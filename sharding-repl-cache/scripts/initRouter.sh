#!/bin/bash
docker compose exec -T mongos_router mongosh --port 27024 --quiet <<EOF
sh.addShard( "rs1/shard1_1:27018,shard1_2:27019,shard1_3:27020");
sh.addShard( "rs2/shard2_1:27021,shard2_2:27022,shard2_3:27023");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
db.helloDoc.countDocuments() 
EOF