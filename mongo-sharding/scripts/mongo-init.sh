#!/bin/bash

echo "=== Config Server ==="
docker compose exec -T configSrv mongosh --port 27017 <<EOF
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
sleep 2

echo "=== shard #1 ==="
docker compose exec -T shard1 mongosh --port 27100 <<EOF
 rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1:27100" },
      ]
    }
);
exit();
EOF
sleep 2

echo "=== shard #2 ==="
docker compose exec -T shard2 mongosh --port 27200 <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 1, host : "shard2:27200" }
      ]
    }
  );
exit();
EOF
sleep 2

echo "=== shard #3 ==="
docker compose exec -T shard3 mongosh --port 27300 <<EOF
rs.initiate(
    {
      _id : "shard3",
      members: [
        { _id : 2, host : "shard3:27300" }
      ]
    }
  );
exit();
EOF
sleep 2


echo "=== router ==="
docker compose exec -T mongos_router mongosh --port 27018 <<EOF
use somedb

sh.addShard( "shard1/shard1:27100");
sh.addShard( "shard2/shard2:27200");
sh.addShard( "shard3/shard3:27300");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
exit()
EOF