
#!/bin/bash
set -e

docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
const admin = db.getSiblingDB("admin");
const config = db.getSiblingDB("config");
const database = db.getSiblingDB("somedb");

// Register shards
const shards = admin.runCommand({listShards: 1}).shards;

if (!shards.some(s => s._id === "shard1")) {
  sh.addShard("shard1/shard1:27018");
}

if (!shards.some(s => s._id === "shard2")) {
  sh.addShard("shard2/shard2:27019");
}

// Enable sharding
if (!config.collections.findOne({_id: "somedb.helloDoc"})) {
  sh.shardCollection("somedb.helloDoc", {name: "hashed"});
}

// Insert test data
const operations = [];

for (let i = 0; i < 1000; i++) {
  operations.push({
    updateOne: {
      filter: {name: "ly" + i},
      update: {$setOnInsert: {age: i}},
      upsert: true
    }
  });
}

database.helloDoc.bulkWrite(operations);

print("Total:", database.helloDoc.countDocuments());
EOF
