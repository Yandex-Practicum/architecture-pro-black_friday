#!/bin/bash
###
# Инициализация шардированного кластера MongoDB с репликацией:
#   1. инициализируем replica-set из 3 узлов для configSrv
#   2. инициализируем replica-set из 3 узлов для shard1 и shard2
#   3. добавляем шарды через mongos и включаем шардирование коллекции somedb.helloDoc
#   4. заливаем 1000 документов через mongos
#   5. печатаем количество документов в каждом шарде и состав реплика-сетов
###
set -e

echo "==> 1/5 Инициализация configSrv replica-set (3 узла)..."
docker compose exec -T configSrv1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27019" },
    { _id: 1, host: "configSrv2:27019" },
    { _id: 2, host: "configSrv3:27019" }
  ]
})
EOF

echo "==> 2/5 Инициализация shard1 replica-set (3 узла)..."
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF

echo "==> Инициализация shard2 replica-set (3 узла)..."
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF

echo "==> Ждём выборов primary во всех replica-set'ах (15 сек)..."
sleep 15

echo "==> Ждём, пока mongos подхватит configSrv (mongos bootstrap ~60 сек на холодную)..."
for i in $(seq 1 60); do
  if docker compose exec -T mongos_router mongosh --port 27017 --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q "^1$"; then
    echo "mongos готов (попытка $i)"
    break
  fi
  sleep 2
done

echo "==> 3/5 Добавляем шарды и включаем sharding для somedb.helloDoc..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
EOF

echo "==> 4/5 Заливаем 1000 документов через mongos..."
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
EOF

echo "==> 5/5 Количество документов по шардам + состав реплика-сетов:"
echo "--- shard1 (primary) ---"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.secondaryOk()
use somedb
print("documents:", db.helloDoc.countDocuments())
print("replicas:", rs.status().members.length)
EOF

echo "--- shard2 (primary) ---"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.secondaryOk()
use somedb
print("documents:", db.helloDoc.countDocuments())
print("replicas:", rs.status().members.length)
EOF

echo "--- configSrv (replica set) ---"
docker compose exec -T configSrv1 mongosh --port 27019 --quiet <<EOF
print("replicas:", rs.status().members.length)
EOF

echo "--- ИТОГО через mongos ---"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
print("documents:", db.helloDoc.countDocuments())
EOF

echo ""
echo "Готово. Веб-интерфейс: http://localhost:8080"
