#!/bin/bash

wait_mongo() {
  local container_name=$1
  local port=$2
  echo "Ожидание готовности: $container_name ($port)..."
  until docker compose exec -T "$container_name" mongosh --port "$port" --eval "db.adminCommand('ping')" &>/dev/null; do
    sleep 2
  done
  echo "✅ $container_name ($port) готов."
}

echo "Запуск контейнеров..."
docker compose up -d
sleep 3
echo "✅Контейнеры запущены"

wait_mongo config 27017
wait_mongo shard1 27018
wait_mongo shard2 27019


echo "Инициализация Config..."
docker compose exec -T config mongosh --port 27017 --quiet <<'EOF'
rs.initiate(
  {
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "config:27017" },
  ]
  }
);
EOF
sleep 3
echo "✅ Config инициализирован"


echo "Инициализация Shard1..."
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1:27018" }
  ]
});
EOF
sleep 3
echo "✅Shard1 инициализирован"


echo "Инициализация Shard2..."
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2:27019" }
  ]
});
EOF
sleep 3
echo "✅Shard2 инициализирован"

wait_mongo router 27020

echo "Инициализация Router..."
docker compose exec -T router mongosh --port 27020 --quiet <<'EOF'
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );

use somedb;
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
print("Количество документов:", db.helloDoc.countDocuments());
EOF
sleep 3
echo "✅Router инициализирован"
echo "✅Кластер инициализирован"