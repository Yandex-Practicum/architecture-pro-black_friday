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

wait_for_primary() {
  local service="$1"
  local port="$2"

  until docker compose exec -T "$service" mongosh --port "$port" --quiet --eval "db.hello().isWritablePrimary" | grep -q "true"; do
    echo "Waiting for primary on $service:$port..."
    sleep 2
  done
}

wait_for_mongo configsvr 27019
for service in shard1-1 shard1-2 shard1-3 shard2-1 shard2-2 shard2-3; do
  wait_for_mongo "$service" 27018
done

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

docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
try {
  rs.status();
} catch (e) {
  rs.initiate({
    _id: "shard1rs",
    members: [
      { _id: 0, host: "shard1-1:27018", priority: 2 },
      { _id: 1, host: "shard1-2:27018", priority: 1 },
      { _id: 2, host: "shard1-3:27018", priority: 1 }
    ]
  });
}
EOF

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<'EOF'
try {
  rs.status();
} catch (e) {
  rs.initiate({
    _id: "shard2rs",
    members: [
      { _id: 0, host: "shard2-1:27018", priority: 2 },
      { _id: 1, host: "shard2-2:27018", priority: 1 },
      { _id: 2, host: "shard2-3:27018", priority: 1 }
    ]
  });
}
EOF

wait_for_primary shard1-1 27018
wait_for_primary shard2-1 27018

docker compose up -d mongos redis pymongo_api >/dev/null
wait_for_mongo mongos 27017

docker compose exec -T mongos mongosh --port 27017 --quiet <<'EOF'
const existingShardIds = db.adminCommand({ listShards: 1 }).shards.map((shard) => shard._id);

if (!existingShardIds.includes("shard1rs")) {
  sh.addShard("shard1rs/shard1-1:27018,shard1-2:27018,shard1-3:27018");
}

if (!existingShardIds.includes("shard2rs")) {
  sh.addShard("shard2rs/shard2-1:27018,shard2-2:27018,shard2-3:27018");
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

for shard in shard1-1 shard2-1; do
  docker compose exec -T "$shard" mongosh --port 27018 --quiet <<EOF
use somedb
print("$shard documents: " + db.helloDoc.countDocuments())
EOF
done

for shard in shard1-1 shard2-1; do
  docker compose exec -T "$shard" mongosh --port 27018 --quiet <<EOF
print("$shard replica set members: " + rs.status().members.length)
EOF
done
