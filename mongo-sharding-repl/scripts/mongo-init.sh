#!/bin/bash

docker compose exec -T config-srv-repl mongosh --port 27017 <<EOF
rs.initiate(
  {
    _id: "config_server", 
    configsvr: true,
    members: [
      { _id : 0, host : "config-srv-repl:27017" }
    ]
  }
);
exit();
EOF
sleep 0.1
docker compose exec -T shard1-1 mongosh --port 27020 <<EOF
rs.initiate(
  {
    _id : "shard1",
    members: [
      { _id: 0, host : "shard1-1:27020" }, 
      { _id: 1, host : "shard1-2:27021" }, 
      { _id: 2, host : "shard1-3:27022" }
    ]
  }
);
exit();
EOF
sleep 0.1
docker compose exec -T shard2-1 mongosh --port 27023 <<EOF
rs.initiate(
  {
    _id : "shard2",
    members: [
      { _id: 0, host : "shard2-1:27023" }, 
      { _id: 1, host : "shard2-2:27024" }, 
      { _id: 2, host : "shard2-3:27025" }
    ]
  }
);
exit();
EOF
sleep 1
docker compose exec -T router1-repl mongosh --port 27018 <<EOF
sh.addShard("shard1/shard1-1:27020");
sh.addShard("shard1/shard1-2:27021");
sh.addShard("shard1/shard1-3:27022");
sh.addShard("shard2/shard2-1:27023");
sh.addShard("shard2/shard2-2:27024");
sh.addShard("shard2/shard2-3:27025");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );

use somedb;
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i});

db.helloDoc.countDocuments();
exit();
EOF
sleep 1
docker compose exec -T router2-repl mongosh --port 27019 <<EOF
sh.addShard("shard1/shard1-1:27020");
sh.addShard("shard1/shard1-2:27021");
sh.addShard("shard1/shard1-3:27022");
sh.addShard("shard2/shard2-1:27023");
sh.addShard("shard2/shard2-2:27024");
sh.addShard("shard2/shard2-3:27025");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );

sh.status();

use somedb;
db.helloDoc.countDocuments();
exit();
EOF
sleep 0.1
docker compose exec -T shard1-3 mongosh --port 27022 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF

docker compose exec -T shard2-2 mongosh --port 27024 <<EOF
use somedb;
db.helloDoc.countDocuments();
exit();
EOF
