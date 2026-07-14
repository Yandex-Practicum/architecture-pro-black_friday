#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

wait_for_mongo() {
  local service=$1 port=$2
  echo "  ждём $service:$port..."
  until docker compose exec -T "$service" mongosh --port "$port" --quiet --eval "db.runCommand('ping').ok" >/dev/null 2>&1; do
    sleep 1
  done
}

echo "1) Ждём поднятия mongod (configsvr1 и все узлы шардов)..."
for svc_port in configsvr1:27019 shard1-1:27018 shard1-2:27018 shard1-3:27018 shard2-1:27018 shard2-2:27018 shard2-3:27018; do
  svc="${svc_port%%:*}"; port="${svc_port##*:}"
  wait_for_mongo "$svc" "$port"
done

echo "2) Инициализация config server replica set..."
docker compose exec -T configsvr1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "configsvr1:27019" }]
})
EOF

echo "3) Инициализация shard1rs (3 узла)..."
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1rs",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF

echo "4) Инициализация shard2rs (3 узла)..."
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2rs",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF

echo "5) Ждём выбора primary на каждом replica set (15 сек)..."
sleep 15

echo "6) Ждём поднятия mongos (готов только после инициализации config server replica set)..."
wait_for_mongo mongos 27017

echo "7) Добавляем шарды в кластер через mongos..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1rs/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2rs/shard2-1:27018,shard2-2:27018,shard2-3:27018")
EOF

echo "8) Включаем шардирование для somedb.helloDoc (хэшированный _id)..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
db.getSiblingDB("somedb").helloDoc.createIndex({ _id: "hashed" })
sh.shardCollection("somedb.helloDoc", { _id: "hashed" })
EOF

echo "9) Заполняем данными (1000 документов)..."
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({age: i, name: "ly" + i})
EOF

echo "Готово. Итоговый count через mongos:"
docker compose exec -T mongos mongosh --port 27017 --quiet --eval 'db.getSiblingDB("somedb").helloDoc.countDocuments()'
