#!/bin/bash
set -e

# Инициализация Config Server Replica Set
# Это обязательный шаг: без PRIMARY в configRS mongos работать не сможет
echo 'Инициализация Config Server Replica Set...'
docker exec -it configSrv mongosh --port 27019 --eval '
rs.initiate({
  _id: "configRS",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
'
sleep 2

# Инициализация Replica Set для первого шарда
# shard1 становится PRIMARY своего реплика-сета
echo 'Инициализация Replica Set для первого шарда...'
docker exec -it shard1 mongosh --port 27018 --eval '
rs.initiate({
  _id: "shard1RS",
  members: [{ _id: 0, host: "shard1:27018" }]
})
'
sleep 2

# Инициализация Replica Set для второго шарда
# shard2 становится PRIMARY своего реплика-сета
echo 'Инициализация Replica Set для второго шарда...'
docker exec -it shard2 mongosh --port 27118 --eval '
rs.initiate({
  _id: "shard2RS",
  members: [{ _id: 0, host: "shard2:27118" }]
})
'
sleep 2

# Подключаем первый шард к mongos
# mongos регистрирует shard1RS как участника sharded cluster
echo 'Подключаем первый шард к mongos...'
docker exec -it mongos mongosh --port 27017 --eval '
sh.addShard("shard1RS/shard1:27018");
'
sleep 2

# Подключаем второй шард к mongos
# mongos регистрирует shard2RS как участника sharded cluster
echo 'Подключаем второй шард к mongos...'
docker exec -it mongos mongosh --port 27017 --eval '
sh.addShard("shard2RS/shard2:27118");
'

# Ждём, пока стабилизируется routing и shard registry
# Без этого возможны ошибки при создании базы
echo 'Ждём, пока стабилизируется routing и shard registry...'
sleep 7

# Включаем шардинг для базы и коллекции (иначе записи уйдут в один primary shard)
# - enableSharding: разрешает шардирование базы somedb
# - createIndex: создаём hashed-индекс по _id как shard key
# - shardCollection: включаем шардирование коллекции somedb.helloDoc
echo 'Включаем шардинг для базы и коллекции...'
docker compose exec -T mongos mongosh --host mongos --port 27017 <<'EOF'
sh.enableSharding("somedb");
use somedb;
db.helloDoc.createIndex({ _id: "hashed" });
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
sh.status();
EOF

# Подключаемся к mongos и начинаем писать данные
# Теперь коллекция шардирована, и данные смогут распределяться по шардам
echo 'Подключаемся к mongos и начинаем писать данные...'
docker compose exec -T mongos mongosh --host mongos --port 27017 <<'EOF'
use somedb
for (var i = 0; i < 2000; i++) {
  db.helloDoc.insertOne({
    age: i,
    name: "ly" + i
  })
}

db.helloDoc.getShardDistribution();
EOF
