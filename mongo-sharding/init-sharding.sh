#!/usr/bin/env bash
# Инициализация кластера (задание 2). Сначала: docker-compose up -d --build
# Повтор на чистом стенде: docker-compose down -v
set -e
cd "$(dirname "$0")"

echo "1) config replica set"
docker-compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }],
});
EOF

echo "2) шард1"
docker-compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }],
});
EOF

echo "3) шард2"
docker-compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }],
});
EOF

echo "4) перезапуск mongos (подождать выборы ~15 c)"
sleep 15
docker-compose restart mongos_router
sleep 5

echo "5) addShard, enableSharding, shardCollection"
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF

echo "6) вставка 1200 документов"
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
const n = 1200;
const dbn = db.getSiblingDB("somedb");
const batch = 300;
for (let s = 0; s * batch < n; s++) {
  const m = Math.min(batch, n - s * batch);
  const docs = Array.from({ length: m }, (_, i) => ({ n: s * batch + i, t: "seed" }));
  dbn.helloDoc.insertMany(docs, { ordered: false });
}
print("Всего: " + dbn.helloDoc.countDocuments());
EOF

echo "Готово. http://localhost:8080/"
