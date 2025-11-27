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

echo "Запуск контейнеры..."
docker compose up -d
sleep 3
echo "✅Контейнеры запущены"

wait_mongo config 27017
wait_mongo shard1-1 27018
wait_mongo shard1-2 27019
wait_mongo shard1-3 27020
wait_mongo shard2-1 27021
wait_mongo shard2-2 27022
wait_mongo shard2-3 27023

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
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27019" },
    { _id: 2, host: "shard1-3:27020" }
  ]
});
EOF
sleep 3
echo "✅Shard1 инициализирован"

echo "Инициализация Shard2..."
docker compose exec -T shard2-1 mongosh --port 27021 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27021" },
    { _id: 1, host: "shard2-2:27022" },
    { _id: 2, host: "shard2-3:27023" }
  ]
});
EOF
sleep 3
echo "✅Shard2 инициализирован"

wait_mongo router 27024

echo "Инициализация Router..."
docker compose exec -T router mongosh --port 27024 --quiet <<'EOF'
sh.addShard("shard1/shard1-1:27018,shard1-2:27019,shard1-3:27020");
sh.addShard("shard2/shard2-1:27021,shard2-2:27022,shard2-3:27023");
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
echo "✅Кластер  инициализирован"