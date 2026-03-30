#!/bin/bash
set -e

echo "Waiting for MongoDB containers..."
sleep 10

echo "Initiating config server replica set..."
docker compose exec -T monogdb-config mongosh --port 27017 <<'EOF'
try {
  rs.status()
  print("config_server already initialized")
} catch (e) {
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [
      { _id: 0, host: "monogdb-config:27017" }
    ]
  })
  print("config_server initiated")
}
EOF

echo "Initiating shard1 replica set..."
docker compose exec -T mongodb-shard-1 mongosh --port 27018 <<'EOF'
try {
  rs.status()
  print("shard1 already initialized")
} catch (e) {
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "mongodb-shard-1:27018" }
    ]
  })
  print("shard1 initiated")
}
EOF

echo "Initiating shard2 replica set..."
docker compose exec -T mongodb-shard-2 mongosh --port 27019 <<'EOF'
try {
  rs.status()
  print("shard2 already initialized")
} catch (e) {
  rs.initiate({
    _id: "shard2",
    members: [
      { _id: 0, host: "mongodb-shard-2:27019" }
    ]
  })
  print("shard2 initiated")
}
EOF

echo "Waiting for replica sets to elect primary..."
sleep 10

echo "Adding shards to mongos..."
docker compose exec -T mongodb-router mongosh --port 27020 <<'EOF'
try {
  sh.addShard("shard1/mongodb-shard-1:27018")
} catch (e) {
  print("shard1 may already be added: " + e)
}

try {
  sh.addShard("shard2/mongodb-shard-2:27019")
} catch (e) {
  print("shard2 may already be added: " + e)
}

sh.status()
EOF

echo "Enabling sharding and loading data..."
docker compose exec -T mongodb-router mongosh --port 27020 <<'EOF'
sh.enableSharding("somedb")

try {
  sh.shardCollection("somedb.helloDoc", { age: 1 })
} catch (e) {
  print("Collection may already be sharded: " + e)
}

use somedb

for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i })
}

print("Inserted 1000 docs into somedb.helloDoc")
EOF

echo "Done"