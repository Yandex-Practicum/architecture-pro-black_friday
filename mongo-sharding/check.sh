#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-somedb}"
COLL_NAME="${COLL_NAME:-helloDoc}"

echo "=== Проверка shard1 ==="
docker exec -i shard1 mongosh --quiet --port 27018 <<JS
use ${DB_NAME};
print("countDocuments (shard1) =", db.${COLL_NAME}.countDocuments());
JS

echo "=== Проверка shard2 ==="
docker exec -i shard2 mongosh --quiet --port 27019 <<JS
use ${DB_NAME};
print("countDocuments (shard2) =", db.${COLL_NAME}.countDocuments());
JS

echo "=== Распределение данных (mongos) ==="
docker exec -i mongos_router mongosh --quiet --port 27020 <<JS
use ${DB_NAME};
db.${COLL_NAME}.getShardDistribution();
JS

echo "Проверка завершена!"
