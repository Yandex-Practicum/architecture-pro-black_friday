#!/bin/bash
set -e

###
# Инициализируем шардированный кластер MongoDB с репликацией (3 реплики на шард)
# и заполняем его данными
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

echo "2. Инициализация replica set shard1 (shard1-1, shard1-2, shard1-3)"
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
wait_primary shard1-1 27018

echo "3. Инициализация replica set shard2 (shard2-1, shard2-2, shard2-3)"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" }
  ]
})
EOF
wait_primary shard2-1 27019

echo "4. Добавление шардов в роутер и шардирование коллекции somedb.helloDoc"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name": "hashed" })
EOF

echo "5. Заполнение данными"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i })
print("Всего документов: " + db.helloDoc.countDocuments())
EOF

echo "6. Количество документов и реплик на шардах"
for shard in "shard1-1 27018" "shard2-1 27019"; do
  set -- $shard
  docker compose exec -T "$1" mongosh --port "$2" --quiet <<EOF
use somedb
print(rs.conf()._id + ": документов " + db.helloDoc.countDocuments() + ", реплик " + rs.status().members.length)
rs.status().members.forEach(m => print("  " + m.name + " " + m.stateStr))
EOF
done
