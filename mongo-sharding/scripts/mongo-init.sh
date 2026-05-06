#!/usr/bin/env bash
set -euo pipefail

wait_for_mongo() {
  local service="$1"
  local port="$2"

  until docker compose exec -T "$service" mongosh --port "$port" --quiet --eval "db.adminCommand({ ping: 1 }).ok" >/dev/null 2>&1; do
    echo "Waiting for $service:$port..."
    sleep 2
  done
}

wait_for_mongo configsvr 27019
wait_for_mongo shard1 27018
wait_for_mongo shard2 27018

docker compose exec -T configsvr mongosh --port 27019 --quiet <<'EOF'
try {
  rs.status();
} catch (e) {
  rs.initiate({
    _id: "configReplSet",
    configsvr: true,
    members: [
      { _id: 0, host: "configsvr:27019" }
    ]
  });
}
EOF

docker compose up -d mongos pymongo_api >/dev/null
wait_for_mongo mongos 27017

docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
const existingShards = db.adminCommand({ listShards: 1 }).shards.map((shard) => shard.host);

if (!existingShards.some((host) => host.includes("shard1:27018"))) {
  sh.addShard("shard1:27018");
}

if (!existingShards.some((host) => host.includes("shard2:27018"))) {
  sh.addShard("shard2:27018");
}

sh.enableSharding("somedb");

const database = db.getSiblingDB("somedb");
database.helloDoc.drop();
database.createCollection("helloDoc");
database.helloDoc.createIndex({ _id: "hashed" });
sh.shardCollection("somedb.helloDoc", { _id: "hashed" }, false, { numInitialChunks: 8 });

const bulk = database.helloDoc.initializeUnorderedBulkOp();
for (let i = 0; i < 1000; i += 1) {
  bulk.insert({ age: i, name: `ly${i}` });
}
const writeResult = bulk.execute();

print("Inserted documents: " + writeResult.insertedCount);
print("Total documents: " + database.helloDoc.countDocuments());
printjson(db.adminCommand({ listShards: 1 }).shards);
EOF

for shard in shard1 shard2; do
  docker compose exec -T "$shard" mongosh --port 27018 --quiet <<EOF
use somedb
print("$shard documents: " + db.helloDoc.countDocuments())
EOF
done
