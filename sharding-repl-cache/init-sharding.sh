#!/usr/bin/env bash
# Задание 4: шарды + реплики + сид (helloDoc, cache_demo). Сначала: docker-compose up -d --build
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

echo "2) шард1 — replica set из 3 узлов (инициализация с shard1-1)"
docker-compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" },
  ],
});
EOF

echo "3) шард2 — replica set из 3 узлов (инициализация с shard2-1)"
docker-compose exec -T shard2-1 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" },
  ],
});
EOF

echo "4) ожидание выборов, перезапуск mongos"
sleep 20
docker-compose restart mongos_router
sleep 5

echo "5) addShard, enableSharding, shardCollection"
docker-compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard("shard1/shard1-1:27018");
sh.addShard("shard2/shard2-1:27019");
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
dbn.cache_demo.insertMany([
  { name: "Alice", age: 30 },
  { name: "Bob", age: 25 },
  { name: "Carol", age: 40 },
]);
print("Всего helloDoc: " + dbn.helloDoc.countDocuments());
print("Пользователей в cache_demo: " + dbn.cache_demo.countDocuments());
EOF

echo "Готово. http://localhost:8080/"
