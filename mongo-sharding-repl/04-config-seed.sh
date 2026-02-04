#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-somedb}"
COLL_NAME="${COLL_NAME:-helloDoc}"
N="${N:-3000}"

echo "[mongos_router] addShard + enableSharding + shardCollection + seed (db=${DB_NAME}, coll=${COLL_NAME}, n=${N})"

docker exec -i mongos_router mongosh --quiet --port 27020 <<JS
sh.addShard("shard1/shard1:27018,shard1_2:27018,shard1_3:27018");
sh.addShard("shard2/shard2:27019,shard2_2:27019,shard2_3:27019");

sh.enableSharding("${DB_NAME}");
sh.shardCollection("${DB_NAME}.${COLL_NAME}", { name: "hashed" });

use ${DB_NAME};

for (var i = 0; i < ${N}; i++) {
  db.${COLL_NAME}.insertOne({ age: i, name: "ly" + i });
}

print("countDocuments (mongos) =", db.${COLL_NAME}.countDocuments());
JS

echo "[mongos_router] done"
