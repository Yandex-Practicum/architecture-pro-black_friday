#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-somedb}"
COLL_NAME="${COLL_NAME:-helloDoc}"
N="${N:-3000}"

echo "=== 1. Инициализация config server (1 node) ==="
docker exec -i configSrv mongosh --quiet --port 27017 <<'JS'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv:27017" }
  ]
});
JS

echo "=== 2. Инициализация shard1 (3 nodes) ==="
docker exec -i shard1 mongosh --quiet --port 27018 <<'JS'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27018" },
    { _id: 1, host: "shard1_2:27018" },
    { _id: 2, host: "shard1_3:27018" }
  ]
});
JS

echo "=== 3. Инициализация shard2 (3 nodes) ==="
docker exec -i shard2 mongosh --quiet --port 27019 <<'JS'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27019" },
    { _id: 1, host: "shard2_2:27019" },
    { _id: 2, host: "shard2_3:27019" }
  ]
});
JS

echo "Ожидание 15 секунд для выбора Primary узлов в репликах..."
sleep 15

echo "=== 4. Настройка маршрутизатора и шардирования (db=${DB_NAME}, coll=${COLL_NAME}, n=${N}) ==="
docker exec -i mongos_router mongosh --quiet --port 27020 <<JS
sh.addShard("shard1/shard1:27018,shard1_2:27018,shard1_3:27018");
sh.addShard("shard2/shard2:27019,shard2_2:27019,shard2_3:27019");

sh.enableSharding("${DB_NAME}");
sh.shardCollection("${DB_NAME}.${COLL_NAME}", { name: "hashed" });

use ${DB_NAME};

var docs = [];
for (var i = 0; i < ${N}; i++) {
  docs.push({ age: i, name: "ly" + i });
}
db.${COLL_NAME}.insertMany(docs);

print("countDocuments (mongos) =", db.${COLL_NAME}.countDocuments());
JS

echo "Инициализация завершена!"
