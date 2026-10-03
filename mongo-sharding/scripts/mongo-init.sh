#!/bin/bash
set -e

###
# Инициализируем шардированный кластер MongoDB и заполняем его данными
###

# Ждём, пока узел replica set станет PRIMARY
wait_primary() {
  local service=$1 port=$2
  echo "Ожидаем PRIMARY на ${service}:${port}..."
  until docker compose exec -T "$service" mongosh --port "$port" --quiet --eval "db.hello().isWritablePrimary" | grep -q true; do
    sleep 2
  done
}

echo "1. Инициализация сервера конфигурации"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
EOF
wait_primary configSrv 27017

echo "2. Инициализация shard1"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF
wait_primary shard1 27018

echo "3. Инициализация shard2"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }]
})
EOF
wait_primary shard2 27019

echo "4. Добавление шардов в роутер и шардирование коллекции somedb.helloDoc"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27019")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
EOF

echo "5. Заполнение данными"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
print("Всего документов: " + db.helloDoc.countDocuments())
EOF

echo "6. Количество документов на шардах"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
print("shard1: " + db.helloDoc.countDocuments())
EOF
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
print("shard2: " + db.helloDoc.countDocuments())
EOF
