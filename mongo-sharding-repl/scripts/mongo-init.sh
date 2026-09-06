#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
EOF

docker compose exec -T shard1-node1 mongosh --port 27018 <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1-node1:27018" },
        { _id : 1, host : "shard1-node2:27018" },
        { _id : 2, host : "shard1-node3:27018" },
      ]
    }
);
EOF


docker compose exec -T shard2-node1 mongosh --port 27019 <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 0, host : "shard2-node1:27019" },
        { _id : 1, host : "shard2-node2:27019" },
        { _id : 2, host : "shard2-node3:27019" },
      ]
    }
);
EOF

docker compose exec -T shard3-node1 mongosh --port 27020 <<EOF
rs.initiate(
    {
      _id : "shard3",
      members: [
        { _id : 0, host : "shard3-node1:27020" },
        { _id : 1, host : "shard3-node2:27020" },
        { _id : 2, host : "shard3-node3:27020" },
      ]
    }
);
EOF

docker compose exec -T mongos_router mongosh --port 27021 <<EOF
sh.addShard( "shard1/shard1-node1:27018,shard1-node2:27018,shard1-node3:27018");
sh.addShard( "shard2/shard2-node1:27019,shard2-node2:27019,shard2-node3:27019");
sh.addShard( "shard3/shard3-node1:27020,shard3-node2:27020,shard3-node3:27020");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );

use somedb;

for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i});
EOF
