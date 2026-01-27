#!/bin/bash

echo; echo "=====> initializing config servers..."
docker compose exec -T configsvr1 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configsvr1:27017" },
    { _id: 1, host: "configsvr2:27017" },
    { _id: 2, host: "configsvr3:27017" }
  ]
})
EOF

sleep 5

echo; echo "=====> initializing shards..."
docker compose exec -T shard1 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1:27017" }
  ]
})
EOF

docker compose exec -T shard2 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2:27017" }
  ]
})
EOF

sleep 10

echo; echo "=====> adding shards to cluster..."
docker compose exec -T mongos mongosh --port 27017 <<EOF
sh.addShard("shard1ReplSet/shard1:27017")
sh.addShard("shard2ReplSet/shard2:27017")
sh.enableSharding("somedb")
EOF

echo; echo "=====> creating sharded collection..."
docker compose exec -T mongos mongosh --port 27017 <<EOF
use somedb
db.createCollection("helloDoc")
sh.shardCollection("somedb.helloDoc", { age: 1 })
sh.splitAt("somedb.helloDoc", { age: 500 })
sh.moveChunk("somedb.helloDoc", { age: 500 }, "shard2ReplSet")
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i})
}
EOF

echo; echo "=====> checking distribution..."
docker compose exec -T mongos mongosh --port 27017 <<EOF
use somedb
db.helloDoc.getShardDistribution()
EOF

echo; echo "=====> done"

