#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DC="docker compose"

wait_mongo() {
  local svc=$1
  local port=${2:-27017}
  echo "Ожидание ${svc}..."
  local i=0
  while [ "$i" -lt 120 ]; do
    if $DC exec -T "$svc" mongosh --port "$port" --quiet --eval 'db.runCommand({ ping: 1 })' &>/dev/null; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  echo "Таймаут: ${svc} не отвечает"
  exit 1
}

echo "Запуск config-сервера и всех узлов шардов (по 3 на шард)..."
$DC up -d mongo-config1 shard1-1 shard1-2 shard1-3 shard2-1 shard2-2 shard2-3
wait_mongo mongo-config1
wait_mongo shard1-1
wait_mongo shard1-2
wait_mongo shard1-3
wait_mongo shard2-1
wait_mongo shard2-2
wait_mongo shard2-3

echo "Инициализация replica set configRS (config server)..."
$DC exec -T mongo-config1 mongosh --port 27017 --quiet <<'EOF'
try {
  rs.status();
} catch (e) {
  rs.initiate({
    _id: "configRS",
    configsvr: true,
    members: [{ _id: 0, host: "mongo-config1:27017" }],
  });
}
EOF

sleep 5

echo "Инициализация replica set shard1 (3 узла: primary + 2 secondary)..."
$DC exec -T shard1-1 mongosh --port 27017 --quiet <<'EOF'
try {
  rs.status();
} catch (e) {
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "shard1-1:27017" },
      { _id: 1, host: "shard1-2:27017" },
      { _id: 2, host: "shard1-3:27017" },
    ],
  });
}
EOF

echo "Инициализация replica set shard2 (3 узла)..."
$DC exec -T shard2-1 mongosh --port 27017 --quiet <<'EOF'
try {
  rs.status();
} catch (e) {
  rs.initiate({
    _id: "shard2",
    members: [
      { _id: 0, host: "shard2-1:27017" },
      { _id: 1, host: "shard2-2:27017" },
      { _id: 2, host: "shard2-3:27017" },
    ],
  });
}
EOF

sleep 8

echo "Запуск mongos и приложения..."
$DC up -d mongos pymongo_api
wait_mongo mongos

echo "Регистрация шардов (полная строка replica set) и шардирование somedb.helloDoc..."
$DC exec -T mongos mongosh --port 27017 --quiet <<'EOF'
try {
  sh.addShard("shard1/shard1-1:27017,shard1-2:27017,shard1-3:27017");
} catch (e) {
  print("addShard shard1:", e.message);
}
try {
  sh.addShard("shard2/shard2-1:27017,shard2-2:27017,shard2-3:27017");
} catch (e) {
  print("addShard shard2:", e.message);
}
sh.enableSharding("somedb");
try {
  sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
} catch (e) {
  if (String(e.message || e).indexOf("already sharded") === -1) {
    throw e;
  }
}
EOF

echo "Загрузка данных в helloDoc (не менее 1000 документов)..."
$DC exec -T mongos mongosh --port 27017 --quiet <<'EOF'
var somedb = db.getSiblingDB("somedb");
var n = somedb.helloDoc.countDocuments();
if (n < 1000) {
  var docs = [];
  for (var i = 0; i < 1000; i++) {
    docs.push({ age: i, name: "ly" + i });
  }
  somedb.helloDoc.insertMany(docs);
}
print("helloDoc total:", somedb.helloDoc.countDocuments());
EOF

echo "Готово. Проверка: curl -s http://localhost:8080/ | head"
