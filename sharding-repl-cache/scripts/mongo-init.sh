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
exit(); 
EOF

docker compose exec -T shard1r1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1r1:27018" },
        { _id : 1, host : "shard1r2:27021" },
        { _id : 2, host : "shard1r3:27022" }
      ]
    }
);
exit();
EOF

docker compose exec -T shard2r1 mongosh --port 27019 --quiet <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 3, host : "shard2r1:27019" },
        { _id : 4, host : "shard2r2:27023" },
        { _id : 5, host : "shard2r3:27024" }
      ]
    }
  );
exit();
EOF

docker compose exec -T redis_1 redis-cli --cluster create \
  redis_1:6379 redis_2:6379 redis_3:6379 \
  redis_4:6379 redis_5:6379 redis_6:6379 \
  --cluster-replicas 1 --cluster-yes

docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF

sh.addShard( "shard1/shard1r1:27018");
sh.addShard( "shard2/shard2r1:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

