#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-somedb}"
COLL_NAME="${COLL_NAME:-helloDoc}"

echo "[shard1] verify countDocuments in ${DB_NAME}.${COLL_NAME}"

docker exec -i shard1 mongosh --quiet --port 27018 <<JS
use ${DB_NAME};
print("countDocuments (shard1) =", db.${COLL_NAME}.countDocuments());
JS

echo "[shard1] done"
