#!/bin/bash

docker compose exec -T configSrv mongosh --port 27018 --quiet <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27018" }
    ]
  }
);
EOF

docker compose exec -T shard1-mongodb1 mongosh --port 27019 --quiet <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id: 0, host: "shard1-mongodb1:27019" },
        { _id: 1, host: "shard1-mongodb2:27020" },
        { _id: 2, host: "shard1-mongodb3:27021" }
      ]
    }
);
EOF

docker compose exec -T shard2-mongodb1 mongosh --port 27022 --quiet <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id: 3, host: "shard2-mongodb1:27022" },
        { _id: 4, host: "shard2-mongodb2:27023" },
        { _id: 5, host: "shard2-mongodb3:27024" }
      ]
    }
  );
EOF


docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1-mongodb1:27019");
sh.addShard("shard2/shard2-mongodb1:27022");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i})
EOF

docker compose exec -T redis_1 bash <<EOF
echo "yes" | redis-cli --cluster create \
  173.17.0.2:6379 \
  173.17.0.3:6379 \
  173.17.0.4:6379 \
  173.17.0.5:6379 \
  173.17.0.6:6379 \
  173.17.0.7:6379 \
  --cluster-replicas 1
EOF

