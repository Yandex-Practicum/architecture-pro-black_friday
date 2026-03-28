#!/bin/bash
set -e

echo "Waiting for MongoDB containers..."
sleep 15

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

echo "Waiting for config server primary election..."
sleep 10

echo "Initiating shard1 replica set..."
docker compose exec -T mongodb-shard-1-1 mongosh --port 27018 <<'EOF'
try {
  rs.status()
  print("shard1 already initialized")
} catch (e) {
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "mongodb-shard-1-1:27018" },
      { _id: 1, host: "mongodb-shard-1-2:27018" },
      { _id: 2, host: "mongodb-shard-1-3:27018" }
    ]
  })
  print("shard1 initiated")
}
EOF

echo "Initiating shard2 replica set..."
docker compose exec -T mongodb-shard-2-1 mongosh --port 27019 <<'EOF'
try {
  rs.status()
  print("shard2 already initialized")
} catch (e) {
  rs.initiate({
    _id: "shard2",
    members: [
      { _id: 0, host: "mongodb-shard-2-1:27019" },
      { _id: 1, host: "mongodb-shard-2-2:27019" },
      { _id: 2, host: "mongodb-shard-2-3:27019" }
    ]
  })
  print("shard2 initiated")
}
EOF

echo "Waiting for shard replica sets to elect primary..."
sleep 15

echo "Checking shard1 replica set status..."
docker compose exec -T mongodb-shard-1-1 mongosh --port 27018 --quiet --eval 'rs.status().members.forEach(m => print(m.name + " => " + m.stateStr))'

echo "Checking shard2 replica set status..."
docker compose exec -T mongodb-shard-2-1 mongosh --port 27019 --quiet --eval 'rs.status().members.forEach(m => print(m.name + " => " + m.stateStr))'

echo "Adding shards to mongos..."
docker compose exec -T mongodb-router mongosh --port 27020 <<'EOF'
const current = sh.status()

try {
  sh.addShard("shard1/mongodb-shard-1-1:27018,mongodb-shard-1-2:27018,mongodb-shard-1-3:27018")
  print("shard1 added")
} catch (e) {
  print("shard1 may already be added: " + e)
}

try {
  sh.addShard("shard2/mongodb-shard-2-1:27019,mongodb-shard-2-2:27019,mongodb-shard-2-3:27019")
  print("shard2 added")
} catch (e) {
  print("shard2 may already be added: " + e)
}

sh.status()
EOF

echo "Enabling sharding and loading data..."
docker compose exec -T mongodb-router mongosh --port 27020 <<'EOF'
db = db.getSiblingDB("somedb")

try {
  sh.enableSharding("somedb")
  print("Sharding enabled for somedb")
} catch (e) {
  print("Sharding may already be enabled: " + e)
}

try {
  db.helloDoc.drop()
  print("Dropped somedb.helloDoc")
} catch (e) {
  print("Collection drop skipped: " + e)
}

// Индекс под shard key
try {
  db.helloDoc.createIndex({ age: "hashed" })
  print("Created hashed index on age")
} catch (e) {
  print("Hashed index may already exist: " + e)
}

try {
  sh.shardCollection("somedb.helloDoc", { age: "hashed" })
  print("Collection somedb.helloDoc sharded with hashed key")
} catch (e) {
  print("Collection may already be sharded: " + e)
}

const docs = []
for (let i = 0; i < 1000; i++) {
  docs.push({ age: i, name: "ly" + i })
}
db.helloDoc.insertMany(docs)

print("Inserted 1000 docs into somedb.helloDoc")
print("Total docs: " + db.helloDoc.countDocuments())

print("")
print("Shard distribution:")
printjson(db.helloDoc.getShardDistribution())
EOF

echo "Done"